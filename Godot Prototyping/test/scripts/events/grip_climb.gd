extends Node3D

## E5: ESCAPE. Climb out of the shaft with the triggers as hands.
##
##   L2 / R2 grip a rock on the left / right. Each new press (trigger pulled
##   past grip_press) grabs the next hold up on that side, and the trigger
##   stiffens (adaptive resistance) while the hand holds on.
##
##   Holds crumble. A held grip gives way: a crumble from that side, and that
##   trigger goes slack. The player has recovery_window seconds to catch a new
##   hold (press either trigger) or they FALL to the bottom of the climb and
##   start again.
##
##   Fly swarms come from one side. Flies on the left mean grip right, and the
##   other way round. They come only now and then, never on every move, and
##   more often on the side the player keeps climbing toward: drifting left
##   leads into flies waiting on the left. Grip toward the flies, or linger
##   while they're there, and they swarm the player: shake the head (the
##   calibrated shake) to clear them.
##
##   At the top the cave's reverb opens out and the wind comes in full.
##
## The bat teaches each thing the first time it happens and reacts to falls.
## Keyboard fallback: hold the Left / Right arrow keys as the triggers.
## Anti-lockout: after falls_before_assist falls, holds stop crumbling.
## Debug: F11 crumbles a held grip now. V shows the climbing-wall view.

const Event := preload("res://autoload/event_director.gd").Event
const ExitWind := preload("res://scripts/events/exit_wind.gd")
const WallView := preload("res://scripts/climb_wall_view.gd")
const LEFT := -1
const RIGHT := 1

enum State { IDLE, CLIMBING, RECOVERING, SWARMED, FALLING, DONE }

# ------------------------------------------------------------------------
# GRIP CLIMB CONFIG
# ------------------------------------------------------------------------
@export_group("Grips")
## Holds to the top.
@export var holds_to_top: int = 14
## Trigger travel (0-1) that counts as a grip, and below which it lets go.
@export var grip_press: float = 0.55
@export var grip_release: float = 0.3
## Adaptive resistance while a hand holds on (0-1, sent to the bridge).
@export var grip_resistance: float = 0.7
## Seconds a move takes to pull the player up to the new hold.
@export var move_seconds: float = 0.35

@export_group("Crumbling")
## THE difficulty: seconds after a crumble to catch a new hold before falling.
## Tune on real hardware.
@export var recovery_window: float = 1.6
## Seconds of climbing between crumbles (random range). The clock keeps running
## while the player climbs: grabbing a new hold doesn't reset it (it used to,
## so anyone climbing steadily never had a hold crumble).
@export var crumble_after: Vector2 = Vector2(2.5, 5.5)
## Chance a due crumble actually happens (else the timer just restarts).
@export var crumble_chance: float = 0.6
## No crumbles in the first few holds, while the grips are being learnt.
@export var safe_holds: int = 3
## After this many falls, holds stop crumbling (anti-lockout).
@export var falls_before_assist: int = 3
## Seconds at the bottom after a fall before climbing again.
@export var fall_recover_seconds: float = 2.5

@export_group("Fly swarms")
## Chance of a swarm after each move, and the moves that must pass between swarms.
@export var swarm_chance: float = 0.35
@export var swarm_min_gap: int = 2
## No swarms in the first few holds.
@export var swarm_safe_holds: int = 4
## How much drifting to one side makes swarms wait on that side (0 = none,
## 1 = always on the side the player is drifting toward).
@export var swarm_drift_bias: float = 0.6
## How far each grip drifts the player toward its side (in -1..1 units).
@export var drift_per_grip: float = 0.18
## Seconds a swarm waits for the player to grip away before it swarms them.
@export var swarm_linger_seconds: float = 6.0
## Shake swings to clear a swarm that caught the player, and the longest it
## holds them before the flies give up (anti-lockout).
@export var clear_swings: int = 3
@export var swarm_fail_forward_seconds: float = 20.0
## How far to the side of the head the flies are heard.
@export var swarm_offset: float = 2.2
@export var swarm_db: float = 6.0
@export var swarmed_db: float = 12.0

@export_group("Escape soundscape")
## Cave reverb added during the climb (wet 0-1), opened out at the top.
@export var cave_reverb_wet: float = 0.25
@export var open_air_seconds: float = 3.5

@export_group("Sounds and lines")
@export var crumble_sfx: StringName = &"climb_crumble"
@export var crumble_db: float = 10.0
## Where in the recording the crumble starts: rocktumbling.mp3 fades in over its
## first second, so starting into it makes the crumble crack rather than creep.
@export var crumble_clip_start: float = 0.7
@export var fall_sfx: StringName = &"climb_rock_impact"
@export var swarm_sfx: StringName = &"swarm_cue"
@export var intro_line: StringName = &"climb_intro"
@export var crumble_line: StringName = &"climb_crumble"
@export var flies_line: StringName = &"climb_flies"
@export var swarmed_line: StringName = &"climb_swarmed"
@export var fell_line: StringName = &"climb_fell"
@export_group("")

@export var level_path: NodePath = ^".."
@export var trigger_path: NodePath
@export var shaft_start_path: NodePath = ^"ShaftStart"
@export var shaft_end_path: NodePath = ^"ShaftEnd"
@export var shaft_half_width: float = 2.9

signal changed()

var active: bool = false
var state: State = State.IDLE
var progress: int = 0
## -1 (far left) .. 1 (far right): where the player's choices have taken them.
var lateral: float = 0.0
var held := {LEFT: false, RIGHT: false}
## Every hold grabbed this attempt: {side, height (0-1), lateral, crumbled}.
var holds: Array[Dictionary] = []
## 0 = no swarm, else the side it's on.
var swarm_side: int = 0
## For the end-of-run summary (escape_level prints climb.hits).
var hits: int = 0
var falls: int = 0
var crumbles: int = 0
var swarms_avoided: int = 0

var _level: Node = null
var _taught := {}
var _pressed := {LEFT: false, RIGHT: false}
var _t_state: float = 0.0
var _crumble_due: float = 0.0
var _moves_since_swarm: int = 0
var _swarm_t: float = 0.0
var _swarm_player: AudioStreamPlayer3D = null
var _reverb: AudioEffectReverb = null
var _tween: Tween = null
var wall_view: CanvasLayer = null


func _ready() -> void:
	_level = get_node(level_path)
	if trigger_path != NodePath():
		get_node(trigger_path).body_entered.connect(_on_trigger)
	GameState.head_shaken.connect(_on_head_shaken)
	_swarm_player = AudioStreamPlayer3D.new()
	_swarm_player.name = "Swarm"
	var stream: AudioStream = SfxLibrary.get_stream(swarm_sfx)
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
	_swarm_player.stream = stream
	_swarm_player.bus = AudioDirector.BUS_ESSENTIAL
	_swarm_player.max_db = 24.0
	_swarm_player.unit_size = 3.0
	add_child(_swarm_player)
	wall_view = WallView.new()
	wall_view.name = "WallView"
	wall_view.climb = self
	add_child(wall_view)


## Leaving mid-climb (a jump, X to the menu) must not leave the cave reverb on
## the master bus or a trigger stiff.
func _exit_tree() -> void:
	_remove_cave_reverb(0.0)
	Haptics.release_triggers()


## The V key during the climb: the climbing-wall view instead of the map.
func toggle_wall_view() -> void:
	wall_view.set_showing(not wall_view.showing)


func _on_trigger(body: Node3D) -> void:
	if body != _level.player or active:
		return
	if EventDirector.current_event != Event.ESCAPE or EventDirector.event_running:
		return
	start_climb()


func start_climb() -> void:
	active = true
	hits = 0
	falls = 0
	crumbles = 0
	swarms_avoided = 0
	_taught.clear()
	_reset_attempt()
	GameState.input_locked = true
	if not EventDirector.event_running:
		EventDirector.begin(Event.ESCAPE)
	_add_cave_reverb()
	_set_state(State.CLIMBING)
	_schedule_crumble()
	_teach(intro_line)


func stop_climb() -> void:
	active = false
	_clear_swarm()
	_release_all()
	_remove_cave_reverb(0.0)
	if state != State.DONE:
		_set_state(State.IDLE)


## F11: crumble a held grip now.
func force_hit() -> void:
	if state == State.CLIMBING:
		var side := LEFT if held[LEFT] else RIGHT
		_crumble(side)


# --- Input --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active:
		return
	_t_state += delta
	for side in [LEFT, RIGHT]:
		var amount := _trigger_amount(side)
		if not _pressed[side] and amount >= grip_press:
			_pressed[side] = true
			press(side)
		elif _pressed[side] and amount <= grip_release:
			_pressed[side] = false
			release(side)
	_update(delta)


func _trigger_amount(side: int) -> float:
	var amount := 0.0
	for device in Input.get_connected_joypads():
		amount = maxf(amount, Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT if side == LEFT else JOY_AXIS_TRIGGER_RIGHT))
	if Input.is_physical_key_pressed(KEY_LEFT if side == LEFT else KEY_RIGHT):
		amount = 1.0
	return amount


## A trigger pulled: grab the next hold up on that side.
func press(side: int) -> void:
	if state == State.FALLING or state == State.DONE or state == State.IDLE or state == State.SWARMED:
		return
	if swarm_side == side:
		_get_swarmed()
		return
	var was_recovering := state == State.RECOVERING
	held[side] = true
	Haptics.set_trigger(side, grip_resistance)
	progress += 1
	lateral = clampf(lateral + side * drift_per_grip, -1.0, 1.0)
	holds.append({"side": side, "height": _height(), "lateral": lateral, "crumbled": false})
	_move_player()
	if swarm_side == -side:
		swarms_avoided += 1
		_clear_swarm()
	if was_recovering:
		_set_state(State.CLIMBING)
		_schedule_crumble()  # the next crumble counts from the catch
	if progress >= holds_to_top:
		_reach_top()
		return
	_maybe_swarm()
	changed.emit()


func release(side: int) -> void:
	if not held[side]:
		return
	held[side] = false
	Haptics.set_trigger(side, 0.0)
	# Letting go with both hands is a slip: the same window to catch a hold.
	if state == State.CLIMBING and not held[LEFT] and not held[RIGHT] and progress > 0:
		_start_recovery()
	changed.emit()


# --- The climb ----------------------------------------------------------------

func _update(delta: float) -> void:
	match state:
		State.CLIMBING:
			if swarm_side != 0:
				_swarm_t += delta
				if _swarm_t >= swarm_linger_seconds:
					_get_swarmed()
					return
			if (held[LEFT] or held[RIGHT]) and _crumble_due > 0.0:
				_crumble_due -= delta
				if _crumble_due <= 0.0:
					if progress >= safe_holds and falls < falls_before_assist and randf() < crumble_chance:
						var options := [LEFT, RIGHT].filter(func(s): return held[s])
						_crumble(options.pick_random())
					else:
						_schedule_crumble()
		State.RECOVERING:
			if _t_state >= recovery_window:
				_fall()
		State.SWARMED:
			if _t_state >= swarm_fail_forward_seconds:
				print("Climb: the flies give up by themselves.")
				_clear_swarm()
				_set_state(State.CLIMBING)


func _crumble(side: int) -> void:
	crumbles += 1
	held[side] = false
	Haptics.set_trigger(side, 0.0)  # the grip goes slack in the hand
	Haptics.pulse_side(side, 0.8, 0.25)
	for i in range(holds.size() - 1, -1, -1):
		if holds[i].side == side and not holds[i].crumbled:
			holds[i].crumbled = true
			break
	_play_at_side(crumble_sfx, side, crumble_db, crumble_clip_start)
	print("Climb: %s grip crumbled" % ("left" if side == LEFT else "right"))
	_start_recovery()
	_teach(crumble_line)
	changed.emit()


func _start_recovery() -> void:
	_set_state(State.RECOVERING)


func _fall() -> void:
	falls += 1
	hits = falls
	print("Climb: fell (fall %d)" % falls)
	_clear_swarm()
	_release_all()
	_set_state(State.FALLING)
	Haptics.pulse_both(1.0, 0.5)
	_play_at_side(fall_sfx, 0, 6.0)
	BatCompanion.shut_up()
	BatCompanion.say(fell_line)
	_reset_attempt()
	_move_player(0.8)
	await get_tree().create_timer(fall_recover_seconds).timeout
	if active and state == State.FALLING:
		_set_state(State.CLIMBING)
		_schedule_crumble()


func _reach_top() -> void:
	print("Climb: reached the top (falls %d, crumbles %d, swarms avoided %d)" % [falls, crumbles, swarms_avoided])
	_set_state(State.DONE)
	_clear_swarm()
	_release_all()
	_open_out()
	active = false
	_level._finish_run()
	changed.emit()


# --- Swarms -------------------------------------------------------------------

## Now and then, more often on the side the player keeps drifting toward.
func _maybe_swarm() -> void:
	_moves_since_swarm += 1
	if swarm_side != 0 or progress < swarm_safe_holds or _moves_since_swarm < swarm_min_gap:
		return
	if randf() >= swarm_chance:
		return
	var p_left := clampf(0.5 - lateral * swarm_drift_bias, 0.05, 0.95)
	start_swarm(LEFT if randf() < p_left else RIGHT)


func start_swarm(side: int) -> void:
	swarm_side = side
	_swarm_t = 0.0
	_moves_since_swarm = 0
	_place_swarm()
	_swarm_player.volume_db = swarm_db
	_swarm_player.play()
	print("Climb: flies on the %s" % ("left" if side == LEFT else "right"))
	_teach(flies_line)
	changed.emit()


func _get_swarmed() -> void:
	print("Climb: swarmed")
	GameState.reset_shake()
	_swarm_player.volume_db = swarmed_db
	_set_state(State.SWARMED)
	BatCompanion.say(swarmed_line)
	changed.emit()


func _on_head_shaken(swings: int) -> void:
	if state == State.SWARMED and swings >= clear_swings:
		print("Climb: shook the flies off")
		_clear_swarm()
		_set_state(State.CLIMBING if (held[LEFT] or held[RIGHT]) else State.RECOVERING)


func _clear_swarm() -> void:
	swarm_side = 0
	if _swarm_player != null and _swarm_player.playing:
		var fade := create_tween()
		fade.tween_property(_swarm_player, "volume_db", -50.0, 1.0)
		fade.tween_callback(_swarm_player.stop)
	changed.emit()


func _place_swarm() -> void:
	var head := GameState.head_position
	_swarm_player.global_position = head + Vector3.RIGHT * swarm_side * swarm_offset + Vector3.UP * 0.5


# --- Helpers ------------------------------------------------------------------

func _height() -> float:
	return clampf(float(progress) / maxf(holds_to_top, 1), 0.0, 1.0)


## Up the shaft by progress, across it by lateral.
func _move_player(seconds: float = -1.0) -> void:
	var start := (get_node(shaft_start_path) as Node3D).global_position
	var end := (get_node(shaft_end_path) as Node3D).global_position
	var target := start.lerp(end, _height()) + Vector3.RIGHT * lateral * (shaft_half_width - 0.6) + Vector3.UP * 0.1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_level.player, "global_position", target, move_seconds if seconds < 0.0 else seconds)
	if swarm_side != 0:
		_tween.tween_callback(_place_swarm)


func _schedule_crumble() -> void:
	_crumble_due = randf_range(crumble_after.x, crumble_after.y)


func _reset_attempt() -> void:
	progress = 0
	lateral = 0.0
	holds.clear()
	held = {LEFT: false, RIGHT: false}
	_moves_since_swarm = 0
	_crumble_due = 0.0


func _release_all() -> void:
	held = {LEFT: false, RIGHT: false}
	Haptics.release_triggers()


func _teach(line: StringName) -> void:
	if line == &"" or _taught.has(line):
		return
	_taught[line] = true
	BatCompanion.say(line)


func _set_state(new_state: State) -> void:
	state = new_state
	_t_state = 0.0
	changed.emit()


## A one-shot from the left/right of the head (0 = centred).
func _play_at_side(sfx: StringName, side: int, volume_db: float, from_seconds: float = 0.0) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.stream = SfxLibrary.get_stream(sfx)
	sound.bus = AudioDirector.BUS_PRIORITY
	sound.max_db = 24.0
	sound.volume_db = volume_db
	sound.unit_size = 4.0
	add_child(sound)
	sound.global_position = GameState.head_position + Vector3.RIGHT * side * 1.5 + Vector3.UP * 0.8
	sound.finished.connect(sound.queue_free)
	sound.play(from_seconds)


# --- Escape soundscape --------------------------------------------------------

func _add_cave_reverb() -> void:
	if _reverb != null:
		return
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.7
	_reverb.damping = 0.4
	_reverb.wet = cave_reverb_wet
	_reverb.dry = 1.0
	AudioServer.add_bus_effect(0, _reverb)


## The payoff: the walls fall away. Reverb opens out to nothing, the cave's
## ambience drops away and the outside wind comes in full.
func _open_out() -> void:
	_level.exit_wind.set_mode(ExitWind.Mode.FULL)
	AudioDirector.set_layer_volume(AudioDirector.BUS_ENVIRONMENTAL, 0.0)
	_remove_cave_reverb(open_air_seconds)


func _remove_cave_reverb(seconds: float) -> void:
	if _reverb == null:
		return
	var reverb := _reverb
	_reverb = null
	var done := func():
		for i in AudioServer.get_bus_effect_count(0):
			if AudioServer.get_bus_effect(0, i) == reverb:
				AudioServer.remove_bus_effect(0, i)
				break
	if seconds <= 0.0:
		done.call()
		return
	var fade := create_tween()
	fade.tween_property(reverb, "wet", 0.0, seconds)
	fade.tween_callback(done)
