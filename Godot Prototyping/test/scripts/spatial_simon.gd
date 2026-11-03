extends Node3D

## Spatial Simon: the head-orientation memory minigame (minigame.tscn).
##
## Six notes each live in one head direction. The game plays a growing
## sequence (Twinkle Twinkle, one phrase per level) and the player reproduces
## it by turning their head. Untimed and self-paced. All the tuning is in the
## CONFIG section directly below.
##
## What it reuses rather than rebuilds:
##   head      GameState.effective_orientation() and
##             SensorBridge.pitch_rate_updated, so mouse, live EmotiBit and
##             the recenter key all work as they do in the main game.
##   voice     BatCompanion.say(): a clip if one is rendered, otherwise
##             runtime TTS reading voices/lines.txt.
##   success   SfxLibrary ("ui_success" in manifest.json).
##   audio     plain AudioStreamPlayer3Ds on the UI bus, set up like the
##             scan's pings. UI is never stripped by overload.
##
## Live head tracking needs -- --sensor=live: the older /Godot/IMU path has no
## pitch angle. Godot's stereo panning also has no elevation, so "up" and
## "down" are carried by a note's pitch, not by where it sounds from.
##
## Do not set BatCompanion.head here: EventDirector takes that as the signal
## to start Event 1's cold open when one is pending.
##
## Playtesting keys: mouse or arrow keys turn the head, N nods, C recenters,
## X returns to the menu, Esc frees the mouse (click to recapture).
##
## Automated check: Godot --headless --path . minigame.tscn -- --autotest

signal note_played(note: int, in_demo: bool)
signal game_ended(rounds_passed: int, won: bool)

enum Phase { IDLE, DEMO, TURN, SUCCESS, OVER }
enum ZoneMode { DIRECTION, PRECISE }

# ==============================================================================
# CONFIG: everything meant to be retuned is in this section.
# ==============================================================================

@export_group("Notes")
## Row N of these four lists is one note. Yaw: negative = left. Pitch:
## positive = up. pitch_scale is relative to the base sample (C4).
##                                                  C      D       E      F      G      A
@export var note_names := PackedStringArray(      ["C",   "D",    "E",   "F",   "G",   "A"])
@export var note_pitch_scales := PackedFloat32Array([1.000, 1.122,  1.260, 1.335, 1.498, 1.682])
@export var note_yaw_deg := PackedFloat32Array(   [0.0,  -30.0,  -55.0,  55.0,  30.0,   0.0])
@export var note_pitch_deg := PackedFloat32Array( [-35.0, -20.0,   0.0,   0.0,  20.0,  35.0])

@export_group("Song")
## One entry per level. Level N plays phrases 1..N joined together. Each extra
## level also needs a matching <end_line_prefix>N line in voices/lines.txt.
@export var song_phrases := PackedStringArray([
	"C C G G A A G",
	"F F E E D D C",
	"G G F F E E D",
	"G G F F E E D",
	"C C G G A A G",
	"F F E E D D C",
])

@export_group("Audio")
## One sustained C4 note. Empty or missing: a tone is synthesized instead.
@export_file("*.wav", "*.ogg", "*.mp3") var note_sample_path: String = "res://assets/sfx/minigame/note_c4.wav"
@export var note_bus: StringName = AudioDirector.BUS_UI
## How far from the head each note plays. With attenuation off this only
## sets direction, not loudness.
@export var note_distance: float = 2.0
@export var note_volume_db: float = 0.0
## 3D pan amount. Doubled from the scan's 1.0, which only gave about 5 dB of
## left/right difference at 65 degrees; direction is the whole game here.
@export var note_panning_strength: float = 2.0
## How long each note sounds, in the demonstration and when played back.
@export var note_seconds: float = 0.55
## Silence between notes in the demonstration.
@export var note_gap_seconds: float = 0.2
## Fade at the end of a note, so a sustained sample does not click off.
@export var note_release_seconds: float = 0.08

@export_group("Pacing")
## Seconds after the scene opens before the head is zeroed and the game starts.
@export var start_delay_seconds: float = 1.0
## Seconds between the success sound ending and the next demonstration.
@export var after_success_seconds: float = 0.6
## Seconds between the last note and the spoken result.
@export var before_result_seconds: float = 0.7
## Line id for the result: this prefix plus the number of rounds passed.
@export var end_line_prefix: String = "simon_rounds_"
## SfxLibrary name of the success sound.
@export var success_sound: String = "ui_success"

@export_group("Zones")
## DIRECTION (default): looking roughly toward a note counts -- whichever note
## direction the head is closest to, once it is off centre. PRECISE: the head
## must be within zone_radius_deg of the note's exact direction.
@export var zone_mode: ZoneMode = ZoneMode.DIRECTION
## DIRECTION: within this many degrees of straight ahead, no note counts.
@export var center_deadzone_deg: float = 12.0
## DIRECTION: another note has to be this many degrees closer before the head
## counts as having moved to it, so the line between neighbours doesn't flicker.
@export var direction_switch_margin_deg: float = 6.0
## DIRECTION: further than this from every note (looking behind) counts as none.
@export var direction_max_deg: float = 50.0
## PRECISE: the head is on a target when it is within this many degrees of it.
@export var zone_radius_deg: float = 13.0
## Extra degrees past zone_radius_deg before the head counts as having left.
## The gap stops tracker jitter flickering a zone, and the space between zones
## stays free to move through. Keep 2 * radius + dead zone below the closest
## pair of notes (about 30 degrees by default); startup warns if it isn't.
@export var dead_zone_deg: float = 4.0
## Seconds the head must stay on a target to register it. Faster passes count
## as pass-through. Live pitch is smoothed, so allow time for it to settle.
@export var dwell_seconds: float = 0.35

@export_group("Nod")
## With the mouse, ordinary up/down movement crosses the nod speed, so it would
## count phantom nods while settling onto a note. Off: with the mouse, nods
## come only from the nod key (N, or Space). Head-motion nods always work live.
@export var motion_nods_with_mouse: bool = false
## Off: nods beyond what a note needs are ignored. On: too many is a miss.
@export var strict_repeat_count: bool = false
## Pitch speed (deg/s) a gentle nod must pass, downward and then back upward.
## Below the 200 deg/s of the river's flick. Tune on a real head.
@export var nod_velocity_threshold_deg: float = 60.0
## Use the nod threshold calibrated in the tutorial (GameState.nod_threshold)
## instead of the value above, so all scenes share one calibration.
@export var use_calibrated_nod: bool = true
## The upward swing must come within this many seconds of the downward one.
@export var nod_window_seconds: float = 0.7
## Dead time after a nod, so its rebound does not start another.
@export var nod_cooldown_seconds: float = 0.15

@export_group("Demo visuals")
## A cube at each note's direction that lights up when its note plays, and a
## small marker where the head points: for sighted observers and demos.
## Purely visual; the game is unchanged with it off.
@export var show_note_cubes: bool = true
## C D E F G A, in order.
@export var note_colors := PackedColorArray([
	Color(0.95, 0.25, 0.25), Color(1.0, 0.6, 0.15), Color(1.0, 0.9, 0.2),
	Color(0.3, 0.85, 0.35), Color(0.25, 0.55, 1.0), Color(0.7, 0.35, 0.95),
])
@export var cube_size: float = 0.45
## How dim a cube rests at, and how big it pops when its note sounds.
@export var cube_idle_brightness: float = 0.25
@export var cube_flash_scale: float = 1.5
## Per-note colours (note_colors) for lit cubes, or one shared lit colour.
@export var use_note_colors: bool = true
## Resting colour when use_note_colors is off (otherwise each note's colour, dimmed).
@export var cube_rest_color: Color = Color(0.22, 0.22, 0.26)
## Lit colour when use_note_colors is off.
@export var cube_lit_color: Color = Color(1.0, 0.95, 0.6)
## A cube the PLAYER just hit flashes this instead, so a confirm reads apart
## from the demonstration.
@export var cube_confirm_color: Color = Color(0.4, 1.0, 0.55)
## How long a cube stays lit before fading back.
@export var cube_hold_seconds: float = 0.6
## Starts in the cube view (sighted testing); view_toggle_key switches to the
## black screen, the real nonvisual play view, and back.
@export var start_in_cube_view: bool = true
@export var view_toggle_key: Key = KEY_F2
## Starts the game over from level 1.
@export var restart_key: Key = KEY_R
## The camera is the player's head: it turns with the head, so you look around
## to find each cube. A crosshair marks the middle of the view.
@export var camera_fov: float = 75.0

@export_group("Testing")
## Arrow keys steer on top of the mouse. Ignored while live data is flowing.
@export var keyboard_head_enabled: bool = true
@export var keyboard_head_speed_deg: float = 80.0
@export var nod_key: Key = KEY_N
## Log zone entry/exit, dwell, nods and note validation to the output.
@export var debug_logging: bool = true
## Small on-screen readout for sighted playtesting.
@export var show_debug_readout: bool = true

# ==============================================================================
# End of CONFIG
# ==============================================================================

const SYNTH_BASE_HZ := 261.63
const SYNTH_MIX_RATE := 44100

var phase: Phase = Phase.IDLE
var level: int = 0
var rounds_passed: int = 0
## The line id spoken at game end, for logging and the autotest.
var end_line: StringName = &""

var _players: Array[AudioStreamPlayer3D] = []
var _targets: Array[Vector3] = []  # unit vector per note
var _phrases: Array[PackedInt32Array] = []
var _sequence := PackedInt32Array()
var _runs: Array[Dictionary] = []  # {note, count}: the sequence with repeats grouped
var _run_index: int = 0
var _run_count: int = 0

var _head: Node3D = null
var _listener: AudioListener3D = null
var _success_player: AudioStreamPlayer = null
var _readout: Label = null
var _cubes: Array[MeshInstance3D] = []
var _cube_tweens: Array[Tween] = []
var _camera: Camera3D = null
var _crosshair: CanvasLayer = null
var cube_view: bool = true
var _black: CanvasLayer = null

var _clock: float = 0.0
## Bumped per game so a stale await from a previous game stops.
var _game_serial: int = 0
var _note_serials := PackedInt32Array()
var _note_fades: Array[Tween] = []

## The pitch that counts as level. The bridge's zero is the head's pose when
## the bridge started, and GameState.recenter() only zeroes yaw.
var _pitch_zero_deg: float = 0.0
var _sim_yaw_deg: float = 0.0
var _sim_pitch_deg: float = 0.0

var _zone: int = -1
var _dwell: float = 0.0
var _registered: bool = false
## A wrong zone the head was resting in when the turn began. It has to be
## left first: the previous level's last note is usually still being faced,
## and must not read as a miss. Resting on the expected first note is not
## locked (level 2 ends on C and level 3 starts on it), so that dwells normally.
var _locked_zone: int = -1

var _nod_down: bool = false
var _t_nod_down: float = 0.0
var _t_next_nod: float = 0.0


func _ready() -> void:
	_parse_config()
	_build_audio()
	_build_cubes()
	_build_readout()
	set_cube_view(start_in_cube_view)

	# Stops the bat's scan from firing here. Recentering is unaffected.
	GameState.input_locked = true
	GameState.recentered.connect(_on_recentered)
	SensorBridge.pitch_rate_updated.connect(_on_pitch_rate)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if OS.get_cmdline_user_args().has("--autotest"):
		var test := Node.new()
		test.name = "Autotest"
		test.set_script(load("res://tests/spatial_simon_autotest.gd"))
		add_child(test)
		return
	start_game.call_deferred()


func _exit_tree() -> void:
	GameState.input_locked = false
	AudioDirector.register_listener(null, null)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## recenter: zero the head where it points now. Only the first start does; a
## restart (R) keeps the zero, since the head may be on a cube at that moment.
func start_game(recenter: bool = true) -> void:
	_game_serial += 1
	var serial := _game_serial
	phase = Phase.IDLE
	level = 0
	rounds_passed = 0
	end_line = &""
	_reset_turn_state()
	await _wait(start_delay_seconds)
	if serial != _game_serial:
		return
	if recenter:
		GameState.set_reference_yaw(0.0)
	_log("game start, %d levels" % _phrases.size())
	_start_level(1)


# --- Game loop ----------------------------------------------------------------

func _start_level(new_level: int) -> void:
	var serial := _game_serial
	level = new_level
	_build_level_sequence()
	_log("level %d: demonstrating %d notes" % [level, _sequence.size()])

	phase = Phase.DEMO
	for note in _sequence:
		_play_note(note, true)
		await _wait(note_seconds + note_gap_seconds)
		if serial != _game_serial:
			return
	_begin_turn()


func _begin_turn() -> void:
	_reset_turn_state()
	_run_index = 0
	_run_count = 0
	var resting := _zone_at(_head_direction())
	_locked_zone = resting if resting != _runs[0].note else -1
	phase = Phase.TURN
	_log("your turn: %d runs, resting zone locked: %s" % [_runs.size(), _note_label(_locked_zone)])


func _on_level_complete() -> void:
	var serial := _game_serial
	phase = Phase.SUCCESS
	rounds_passed = level
	_log("level %d complete" % level)

	var stream := SfxLibrary.get_stream(success_sound)
	_success_player.stream = stream
	_success_player.play()
	await _wait(stream.get_length() + after_success_seconds)
	if serial != _game_serial:
		return

	if level >= _phrases.size():
		_end_game(true)
	else:
		_start_level(level + 1)


func _on_miss(reason: String) -> void:
	_log("MISS: %s" % reason)
	_end_game(false)


func _end_game(won: bool) -> void:
	var serial := _game_serial
	phase = Phase.OVER
	end_line = StringName("%s%d" % [end_line_prefix, rounds_passed])
	_log("game over: %s, %d rounds passed, line %s" % ["won" if won else "lost", rounds_passed, end_line])
	game_ended.emit(rounds_passed, won)
	await _wait(before_result_seconds)
	if serial == _game_serial:
		BatCompanion.say(end_line)


## Sets _sequence to phrases 1..level and _runs to the same notes with
## consecutive repeats grouped, including any repeat across a phrase boundary.
func _build_level_sequence() -> void:
	_sequence = PackedInt32Array()
	for i in level:
		_sequence.append_array(_phrases[i])
	_runs.clear()
	for note in _sequence:
		if not _runs.is_empty() and _runs[-1].note == note:
			_runs[-1].count += 1
		else:
			_runs.append({"note": note, "count": 1})


# --- Per-frame head tracking --------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if _camera != null:
		var view := head_angles_deg()
		_camera.global_rotation = Vector3(deg_to_rad(view.y), deg_to_rad(-view.x), 0.0)
	_update_keyboard_head(delta)
	var direction := _head_direction()

	# Runs after AudioDirector's _process (autoloads go first) and replaces
	# its rotation, so the pitch zero and the arrow keys are heard too.
	var angles := head_angles_deg()
	_listener.global_rotation = Vector3(deg_to_rad(angles.y), deg_to_rad(-angles.x), 0.0)

	if _nod_down and _clock - _t_nod_down > nod_window_seconds:
		_nod_down = false
		_log("nod timed out")
	if phase == Phase.TURN:
		_update_zones(direction, delta)
	if _readout != null:
		_readout.text = "%s  level %d  head yaw %+.0f pitch %+.0f  zone %s  run %d/%d  count %d\n%s" % [
			Phase.keys()[phase], level, angles.x, angles.y, _note_label(_zone),
			_run_index + 1, _runs.size(), _run_count, SensorBridge.status_text(),
		]


## Head as (yaw, pitch) in degrees, in the note table's convention: yaw
## negative = left, pitch positive = up. GameState's yaw has positive = left,
## so this is the one place the sign flips.
func head_angles_deg() -> Vector2:
	var euler := GameState.effective_orientation()
	return Vector2(
		wrapf(-rad_to_deg(euler.y) + _sim_yaw_deg, -180.0, 180.0),
		wrapf(rad_to_deg(euler.x) - _pitch_zero_deg + _sim_pitch_deg, -180.0, 180.0))


func _head_direction() -> Vector3:
	var angles := head_angles_deg()
	return _direction(angles.x, angles.y)


## Unit vector for a (yaw, pitch) in the note table's convention.
func _direction(yaw_deg: float, pitch_deg: float) -> Vector3:
	return Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(-yaw_deg), 0.0)) * Vector3.FORWARD


func _angle_to_zone(direction: Vector3, zone: int) -> float:
	return rad_to_deg(direction.angle_to(_targets[zone]))


## The zone this direction is on, or -1 in the free space between zones.
func _zone_at(direction: Vector3) -> int:
	if zone_mode == ZoneMode.DIRECTION:
		if rad_to_deg(direction.angle_to(Vector3.FORWARD)) < center_deadzone_deg:
			return -1
		var nearest := _nearest_zone(direction)
		return nearest if _angle_to_zone(direction, nearest) <= direction_max_deg else -1
	var best := -1
	var best_angle := zone_radius_deg
	for i in _targets.size():
		var angle := _angle_to_zone(direction, i)
		if angle <= best_angle:
			best = i
			best_angle = angle
	return best


func _nearest_zone(direction: Vector3) -> int:
	var best := 0
	for i in range(1, _targets.size()):
		if _angle_to_zone(direction, i) < _angle_to_zone(direction, best):
			best = i
	return best


## Whether the head still counts as on zone: a little looser than entering, so
## tracker jitter at a boundary never flickers it.
func _still_in(zone: int, direction: Vector3) -> bool:
	if zone_mode == ZoneMode.PRECISE:
		return _angle_to_zone(direction, zone) <= zone_radius_deg + dead_zone_deg
	if rad_to_deg(direction.angle_to(Vector3.FORWARD)) < center_deadzone_deg * 0.75:
		return false
	var angle := _angle_to_zone(direction, zone)
	if angle > direction_max_deg + dead_zone_deg:
		return false
	return _angle_to_zone(direction, _nearest_zone(direction)) >= angle - direction_switch_margin_deg


func _update_zones(direction: Vector3, delta: float) -> void:
	var on_zone := _zone_at(direction)

	if _locked_zone >= 0 and not _still_in(_locked_zone, direction):
		_log("resting zone %s released" % _note_label(_locked_zone))
		_locked_zone = -1

	if _zone >= 0:
		# A nod in progress can swing past the edge without meaning to leave,
		# so only reaching another zone ends the run until the nod resolves.
		var moved := not _still_in(_zone, direction)
		if moved and (not _nod_down or (on_zone >= 0 and on_zone != _zone)):
			_leave_zone()
			if phase != Phase.TURN:
				return

	if _zone < 0 and on_zone >= 0 and on_zone != _locked_zone:
		_zone = on_zone
		_dwell = 0.0
		_registered = false
		_log("zone enter %s" % _note_label(_zone))

	if _zone >= 0 and not _registered:
		_dwell += delta
		if _dwell >= dwell_seconds:
			_registered = true
			_log("dwell complete %s" % _note_label(_zone))
			_on_arrival(_zone)


func _leave_zone() -> void:
	var zone := _zone
	var registered := _registered
	_zone = -1
	_registered = false
	_nod_down = false
	if not registered:
		_log("zone exit %s: pass-through, nothing registered" % _note_label(zone))
		return
	_log("zone exit %s" % _note_label(zone))

	var wanted: int = _runs[_run_index].count
	if _run_count != wanted:
		_on_miss("%s played %d times, wanted %d" % [_note_label(zone), _run_count, wanted])
		return
	_log("run ok: %s x%d" % [_note_label(zone), wanted])
	_run_index += 1
	_run_count = 0


func _on_arrival(zone: int) -> void:
	_play_note(zone, false)
	var expected: int = _runs[_run_index].note
	if zone != expected:
		_on_miss("heard %s, wanted %s" % [_note_label(zone), _note_label(expected)])
		return
	_run_count = 1
	_log("note ok: %s (%d/%d)" % [_note_label(zone), _run_count, _runs[_run_index].count])
	_check_level_done()


## The level's last note ends the level as soon as its count is met: the
## player should not have to turn away to prove they finished.
func _check_level_done() -> void:
	if _run_index == _runs.size() - 1 and _run_count >= _runs[_run_index].count:
		_on_level_complete()


# --- Nod detection ------------------------------------------------------------

## Gyro pitch rate in rad/s, positive = up. Down past the threshold arms a
## nod, and up past it inside the window completes one.
func _on_pitch_rate(rate: float) -> void:
	if not motion_nods_with_mouse and not SensorBridge.live_orientation_active():
		return
	_detect_nod(rate)


func _detect_nod(rate: float) -> void:
	var rate_deg := rad_to_deg(rate)
	if not _nod_down:
		if rate_deg <= -_nod_threshold() and _clock >= _t_next_nod:
			_nod_down = true
			_t_nod_down = _clock
			_log("nod down, %.0f deg/s" % rate_deg)
	elif rate_deg >= _nod_threshold():
		_nod_down = false
		_t_next_nod = _clock + nod_cooldown_seconds
		_log("nod detected, up %.0f deg/s after %.2fs" % [rate_deg, _clock - _t_nod_down])
		_on_nod()


func _nod_threshold() -> float:
	return GameState.nod_threshold() if use_calibrated_nod else nod_velocity_threshold_deg


func _on_nod() -> void:
	if phase != Phase.TURN or _zone < 0 or not _registered:
		_log("nod ignored: not holding a registered zone")
		return
	if not strict_repeat_count and _run_count >= _runs[_run_index].count:
		_log("nod ignored: %s already has its %d" % [_note_label(_zone), _run_count])
		return
	_play_note(_zone, false)
	_run_count += 1
	_log("nod repeat: %s (%d/%d)" % [_note_label(_zone), _run_count, _runs[_run_index].count])
	_check_level_done()


func _reset_turn_state() -> void:
	_zone = -1
	_dwell = 0.0
	_registered = false
	_locked_zone = -1
	_nod_down = false


# --- Input --------------------------------------------------------------------

func _update_keyboard_head(delta: float) -> void:
	if not keyboard_head_enabled or SensorBridge.live_orientation_active():
		return
	var step := keyboard_head_speed_deg * delta
	_sim_yaw_deg += step * (Input.get_axis(&"ui_left", &"ui_right"))
	_sim_pitch_deg += step * (Input.get_axis(&"ui_down", &"ui_up"))


## "Wherever I'm facing is straight ahead" for pitch as well: GameState has
## just done yaw. Fires on C and on the first live sample.
func _on_recentered() -> void:
	_sim_yaw_deg = 0.0
	_sim_pitch_deg = 0.0
	_pitch_zero_deg = rad_to_deg(GameState.orientation.x)
	_log("recentered")


## The nod key sends a real down-then-up through the same detector.
func simulate_nod() -> void:
	var rate := deg_to_rad(_nod_threshold() * 1.5)
	_detect_nod(-rate)
	await _wait(0.08)
	_detect_nod(rate)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"exit_to_main_menu"):
		get_tree().change_scene_to_file("res://main_menu.tscn")
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == nod_key or event.keycode == KEY_SPACE:
			simulate_nod()
		elif event.keycode == restart_key:
			_log("restart")
			start_game(false)
		elif event.keycode == view_toggle_key:
			set_cube_view(not cube_view)
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Audio --------------------------------------------------------------------

func _play_note(note: int, in_demo: bool) -> void:
	var player := _players[note]
	var fade := _note_fades[note]
	if fade != null:
		fade.kill()
	_note_serials[note] += 1
	var serial := _note_serials[note]
	player.volume_db = note_volume_db
	player.play()
	note_played.emit(note, in_demo)
	_flash_cube(note, not in_demo)

	await _wait(note_seconds)
	if serial != _note_serials[note]:
		return
	fade = create_tween()
	fade.tween_property(player, "volume_db", -60.0, note_release_seconds)
	fade.tween_callback(player.stop)
	_note_fades[note] = fade


func _build_audio() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	add_child(_head)
	# AudioStreamPlayer3D only mixes through a viewport that has a Camera3D,
	# even with an AudioListener3D present: without this every note is silent.
	var camera := Camera3D.new()
	camera.name = "Camera"
	_head.add_child(camera)
	camera.make_current()
	_camera = camera
	camera.fov = camera_fov
	if show_note_cubes:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.03, 0.03, 0.05)
		camera.environment = env
	_listener = AudioListener3D.new()
	_listener.name = "Listener"
	_head.add_child(_listener)
	_listener.make_current()
	AudioDirector.register_listener(_listener, _head)

	var stream := _note_stream()
	for i in note_names.size():
		var player := AudioStreamPlayer3D.new()
		player.name = "Note" + note_names[i]
		player.stream = stream
		player.pitch_scale = note_pitch_scales[i]
		player.bus = note_bus
		# Direction only. Loudness stays even across all six notes.
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.panning_strength = note_panning_strength
		player.max_db = 12.0
		_head.add_child(player)
		player.position = _targets[i] * note_distance
		_players.append(player)
	_note_serials.resize(note_names.size())
	_note_fades.resize(note_names.size())

	_success_player = AudioStreamPlayer.new()
	_success_player.name = "Success"
	_success_player.bus = AudioDirector.BUS_UI
	add_child(_success_player)


func _note_stream() -> AudioStream:
	if not note_sample_path.is_empty() and ResourceLoader.exists(note_sample_path):
		var stream = load(note_sample_path)
		if stream is AudioStream:
			_log("note sample: %s" % note_sample_path)
			return stream
	_log("no note sample at '%s', using the synthesized tone" % note_sample_path)
	return _synth_tone()


## A soft C4: a few harmonics with a quick attack and a slow decay. Long
## enough to outlast note_seconds at the highest pitch_scale, which plays it
## back faster. 16-bit mono.
func _synth_tone() -> AudioStreamWAV:
	var seconds := note_seconds * 3.0 + 0.5
	var count := int(SYNTH_MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / SYNTH_MIX_RATE
		var envelope := minf(t / 0.012, 1.0) * exp(-1.2 * t) * minf((seconds - t) / 0.05, 1.0)
		var wave := 0.0
		for harmonic in [[1.0, 0.65], [2.0, 0.22], [3.0, 0.08], [4.0, 0.05]]:
			wave += harmonic[1] * sin(TAU * SYNTH_BASE_HZ * harmonic[0] * t)
		data.encode_s16(i * 2, int(clampf(wave * envelope, -1.0, 1.0) * 26000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SYNTH_MIX_RATE
	stream.data = data
	return stream


# --- Setup helpers ------------------------------------------------------------

func _parse_config() -> void:
	var size := note_names.size()
	if note_pitch_scales.size() != size or note_yaw_deg.size() != size or note_pitch_deg.size() != size:
		push_error("Spatial Simon: the four note lists must be the same length.")
		return
	for i in size:
		_targets.append(_direction(note_yaw_deg[i], note_pitch_deg[i]))

	for phrase in song_phrases:
		var notes := PackedInt32Array()
		for note_name in phrase.split(" ", false):
			var note := note_names.find(note_name)
			if note < 0:
				push_error("Spatial Simon: phrase '%s' uses unknown note '%s'." % [phrase, note_name])
				continue
			notes.append(note)
		_phrases.append(notes)

	var needed := zone_radius_deg * 2.0 + dead_zone_deg if zone_mode == ZoneMode.PRECISE else 0.0
	for a in size:
		for b in range(a + 1, size):
			var apart := rad_to_deg(_targets[a].angle_to(_targets[b]))
			if apart < needed:
				push_warning("Spatial Simon: %s and %s are %.1f degrees apart, less than the %.1f the zones need."
						% [note_names[a], note_names[b], apart, needed])


func _build_cubes() -> void:
	if not show_note_cubes:
		return
	for i in _targets.size():
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * cube_size
		var cube := MeshInstance3D.new()
		cube.name = "Cube" + note_names[i]
		cube.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = _rest_color(i)
		cube.material_override = material
		_head.add_child(cube)
		cube.position = _targets[i] * note_distance
		cube.look_at_from_position(cube.position, Vector3.ZERO)
		_cubes.append(cube)
		var label := Label3D.new()
		label.text = note_names[i]
		label.font_size = 64
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, cube_size * 0.9, 0)
		cube.add_child(label)
	_cube_tweens.resize(_targets.size())
	_crosshair = CanvasLayer.new()
	_crosshair.name = "Crosshair"
	var mark := Label.new()
	mark.text = "+"
	mark.add_theme_font_size_override("font_size", 40)
	mark.add_theme_color_override("font_color", Color.WHITE)
	mark.add_theme_color_override("font_outline_color", Color.BLACK)
	mark.add_theme_constant_override("outline_size", 6)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.add_child(mark)
	add_child(_crosshair)


func _note_color(i: int) -> Color:
	if not use_note_colors:
		return cube_lit_color
	return note_colors[i] if i < note_colors.size() else Color.WHITE


func _rest_color(i: int) -> Color:
	return _note_color(i) * cube_idle_brightness if use_note_colors else cube_rest_color


## Full colour and a pop in size for as long as the note sounds, then back.
func _flash_cube(note: int, confirm: bool = false) -> void:
	if note >= _cubes.size():
		return
	var cube := _cubes[note]
	var material := cube.material_override as StandardMaterial3D
	if _cube_tweens[note] != null:
		_cube_tweens[note].kill()
	material.albedo_color = cube_confirm_color if confirm else _note_color(note)
	cube.scale = Vector3.ONE * cube_flash_scale
	var back := create_tween()
	back.tween_interval(cube_hold_seconds)
	back.tween_property(material, "albedo_color", _rest_color(note), 0.25)
	back.parallel().tween_property(cube, "scale", Vector3.ONE, 0.25)
	_cube_tweens[note] = back


## Cube view: the cubes, head dot and readout for sighted testing. Black view:
## a plain black screen, the real way the game is played. Visual only.
func set_cube_view(on: bool) -> void:
	cube_view = on
	if _black == null:
		_black = CanvasLayer.new()
		_black.name = "BlackScreen"
		_black.layer = 100
		var rect := ColorRect.new()
		rect.color = Color.BLACK
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_black.add_child(rect)
		add_child(_black)
	_black.visible = not on
	if _crosshair != null:
		_crosshair.visible = on
	print("Minigame view: %s" % ("cubes" if on else "black screen"))


func _build_readout() -> void:
	if not show_debug_readout:
		return
	_readout = Label.new()
	_readout.name = "DebugReadout"
	_readout.position = Vector2(16, 16)
	add_child(_readout)


func _note_label(note: int) -> String:
	return note_names[note] if note >= 0 else "-"


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _log(message: String) -> void:
	if debug_logging:
		print("[Simon %7.2f] %s" % [_clock, message])
