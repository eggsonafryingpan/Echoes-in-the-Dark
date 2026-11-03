extends Node

## Autopilot checks for the Spatial Simon minigame. No hardware, no hands: the
## head moves through the same mouse source a player uses, and nods arrive
## through SensorBridge's pitch-rate signal.
##
##   Godot --headless --path . minigame.tscn -- --autotest
##
## Prints PASS/FAIL per check and quits with exit code 0 (all passed) or 1.
## Added by spatial_simon.gd when --autotest is on the command line.

const Game := preload("res://scripts/spatial_simon.gd")
const REST := Vector2(0.0, 0.0)

@export var time_scale: float = 6.0

var _game: Game = null
var _failures: int = 0
var _checks: int = 0
var _played: Array[int] = []
var _demo_played: Array[int] = []


func _ready() -> void:
	_game = get_parent()
	GameState.use_calibration = false  # test the defaults, not this machine's calibration
	_game.motion_nods_with_mouse = true  # the tests nod by pitch rate
	Engine.time_scale = time_scale
	_game.note_played.connect(_on_note_played)
	_run.call_deferred()


func _on_note_played(note: int, in_demo: bool) -> void:
	(_demo_played if in_demo else _played).append(note)


func _run() -> void:
	print("\n=== SPATIAL SIMON AUTOTEST (sensor: %s) ===" % SensorBridge.status_text())
	_game.debug_logging = false
	await _check_mapping()
	await _check_level_one_and_resting_lock()
	await _check_resting_on_first_note()
	await _check_wrong_direction()
	await _check_too_few_repeats()
	await _check_too_many_repeats()
	await _check_nod_rules()
	await _check_pass_through()
	await _check_recenter_zeroes_pitch()
	await _check_full_win()

	Engine.time_scale = 1.0
	print("=== %d checks, %d failed ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check_mapping() -> void:
	print("-- directions")
	await _frames(3)
	_aim(Vector2(-55.0, 0.0))
	await _frames(3)
	var angles := _game.head_angles_deg()
	_expect(absf(angles.x + 55.0) < 0.5, "head turned left reads as negative yaw (%.1f)" % angles.x)
	_expect(_game._zone_at(_game._head_direction()) == 2, "facing left lands in E's zone")
	var e_seen: Vector3 = _game._listener.to_local(_game._players[2].global_position)
	_expect(absf(e_seen.x) < 0.05 and e_seen.z < 0.0, "E is straight ahead of a head facing it (%s)" % e_seen)

	_aim(REST)
	await _frames(3)
	var seen := func(note: int) -> Vector3:
		return _game._listener.to_local(_game._players[note].global_position)
	_expect(seen.call(2).x < -1.0, "E sits to the listener's left")
	_expect(seen.call(3).x > 1.0, "F sits to the listener's right")
	_expect(seen.call(5).y > 1.0 and seen.call(0).y < -1.0, "A is above, C below")
	_expect(_game._zone_at(_game._head_direction()) == -1, "straight ahead is free space")
	_aim(Vector2(0.0, 18.0))
	await _frames(3)
	_expect(_game._zone_at(_game._head_direction()) == 5, "looking roughly up counts as A, no need to face its cube exactly")
	_aim(Vector2(-38.0, 4.0))
	await _frames(3)
	_expect(_game._zone_at(_game._head_direction()) == 2, "roughly left counts as E")
	_aim(REST)
	await _frames(3)
	var scales: Array = []
	for player: AudioStreamPlayer3D in _game._players:
		scales.append(snappedf(player.pitch_scale, 0.001))
	_expect(scales == [1.0, 1.122, 1.26, 1.335, 1.498, 1.682], "pitch scales match the table")
	_expect(get_viewport().get_camera_3d() != null, "a camera exists, or 3D audio is silent")
	_expect(_game._cubes.size() == 6, "a cube for each note")
	var cam := get_viewport().get_camera_3d()
	_aim(Vector2(-55.0, 0.0))
	await _frames(3)
	var e_on_screen: Vector2 = cam.unproject_position(_game._cubes[2].global_position)
	var middle := get_viewport().get_visible_rect().size * 0.5
	_expect(not cam.is_position_behind(_game._cubes[2].global_position) and e_on_screen.distance_to(middle) < 40.0,
			"the camera is the head: turning to E puts E's cube in the middle of the view")
	_expect(cam.is_position_behind(_game._cubes[3].global_position) or not get_viewport().get_visible_rect().has_point(cam.unproject_position(_game._cubes[3].global_position)),
			"and F, on the other side, is out of view")
	_aim(REST)
	await _frames(3)
	_game._play_note(3, true)
	_expect(_game._cubes[3].scale.x > 1.2 and (_game._cubes[3].material_override as StandardMaterial3D).albedo_color.is_equal_approx(_game.note_colors[3]),
			"F's cube flashes its colour when F plays")
	_game._play_note(2, false)
	_expect((_game._cubes[2].material_override as StandardMaterial3D).albedo_color.is_equal_approx(_game.cube_confirm_color),
			"a cube the player hits flashes the confirm colour instead")
	_expect(_game.cube_view and not _game._black.visible, "starts in the cube view")
	var key := InputEventKey.new()
	key.keycode = _game.view_toggle_key
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	_expect(not _game.cube_view and _game._black.visible, "the view key switches to the black screen")
	_game.set_cube_view(true)
	_expect(_game._players[0].stream == _game._players[5].stream, "all notes share one stream")
	_expect(_game._players[0].stream is AudioStreamWAV, "no sample present: synthesized tone in use")


func _check_level_one_and_resting_lock() -> void:
	print("-- level 1, then a head resting on a zone")
	await _new_game()
	_expect(_demo_played == _notes("C C G G A A G"), "demo plays phrase 1 with repeats")
	await _play_sequence("C C G G A A G")
	await _until(func(): return _game.phase == Game.Phase.TURN, 90.0)
	_expect(_game.level == 2 and _game.rounds_passed == 1, "completing a level advances")
	_expect(_demo_played == _notes("C C G G A A G  C C G G A A G F F E E D D C"),
			"level 2 demo is both phrases (after level 1's)")

	# The head never left G, and G's dwell has long passed: that must not count.
	_played.clear()
	await _hold(1.0)
	_expect(_played.is_empty() and _game.phase == Game.Phase.TURN, "head resting in G at turn start registers nothing")
	await _arrive("C")
	_expect(_played == [0], "after leaving, the expected zone registers")


func _check_resting_on_first_note() -> void:
	print("-- head resting on the expected first note")
	await _new_game()
	await _play_sequence("C C G G A A G")
	await _until(func(): return _game.phase == Game.Phase.TURN, 90.0)
	await _play_sequence("C C G G A A G F F E E D D C")
	await _until(func(): return _game.level == 3 and _game.phase == Game.Phase.TURN, 90.0)
	_played.clear()
	await _hold(1.0)
	_expect(_played == [0] and _game._run_count == 1, "level 3 starts on C and a head already there counts")


func _check_wrong_direction() -> void:
	print("-- miss: wrong direction")
	await _new_game()
	await _play_sequence("C C G G A A G")
	await _until(func(): return _game.phase == Game.Phase.TURN, 90.0)
	var ended := await _expect_end(func(): await _arrive("A"))
	_expect(ended == [1, false], "wrong note on level 2 ends with 1 round passed, not won")
	_expect(_game.end_line == &"simon_rounds_1", "result line is simon_rounds_1")


func _check_too_few_repeats() -> void:
	print("-- miss: too few repeats")
	await _new_game()
	await _arrive("C")
	_expect(_game.phase == Game.Phase.TURN, "one C so far is not yet a miss")
	var ended := await _expect_end(func(): await _aim_and_hold(REST, 0.5))
	_expect(ended == [0, false], "leaving C after one of two ends the game with 0 rounds")


func _check_too_many_repeats() -> void:
	print("-- extra nods: ignored by default, a miss in strict mode")
	await _new_game()
	await _arrive("C")
	await _nod()
	await _nod()
	_expect(_game._run_count == 2, "an extra nod past what C needs is ignored")
	await _aim_and_hold(REST, 0.5)
	_expect(_game.phase == Game.Phase.TURN and _game._run_index == 1, "so leaving C moves on to the next note")
	_game.strict_repeat_count = true
	await _new_game()
	await _arrive("C")
	await _nod()
	await _nod()
	_expect(_game._run_count == 3, "strict mode counts the extra nod")
	var ended := await _expect_end(func(): await _aim_and_hold(REST, 0.5))
	_expect(ended == [0, false], "and leaving with three of two is a miss")
	_game.strict_repeat_count = false

	print("-- mouse nods and restart")
	_game.motion_nods_with_mouse = false
	await _new_game()
	await _arrive("C")
	_rate(-200.0)
	await _hold(0.05)
	_rate(200.0)
	await _hold(0.2)
	_expect(_game._run_count == 1, "with the mouse, moving it up and down is not a nod")
	await _game.simulate_nod()
	await _hold(0.2)
	_expect(_game._run_count == 2, "the nod key is")
	_game.motion_nods_with_mouse = true
	var key := InputEventKey.new()
	key.keycode = _game.restart_key
	key.pressed = true
	_game._unhandled_input(key)  # exactly one press
	await _until(func(): return _game.phase != Game.Phase.TURN, 5.0)
	await _until(func(): return _game.level == 1 and _game.phase == Game.Phase.TURN, 60.0)
	_expect(_game.level == 1 and _game._run_index == 0 and _game._run_count == 0, "R restarts from level 1")


func _check_nod_rules() -> void:
	print("-- nods")
	await _new_game()
	_played.clear()
	await _nod()
	_expect(_played.is_empty(), "a nod in free space does nothing")

	# Real time for this one: at time_scale a single slow frame can cover the
	# whole dwell before the nod arrives.
	Engine.time_scale = 1.0
	_aim(_game_dir("C"))
	await _frames(2)
	_rate(-120.0)
	_rate(120.0)
	_expect(_game._zone == 0 and not _game._registered and _game._run_count == 0,
			"a nod before the dwell completes does nothing")
	Engine.time_scale = time_scale
	await _hold(0.6)
	_expect(_game._run_count == 1, "the dwell then registers the arrival")

	_rate(-120.0)
	await _hold(_game.nod_window_seconds + 0.3)
	_rate(120.0)
	await _hold(0.2)
	_expect(_game._run_count == 1, "up after the window has closed is not a nod")

	_rate(-30.0)
	await _hold(0.05)
	_rate(30.0)
	await _hold(0.2)
	_expect(_game._run_count == 1, "a slow wobble under the threshold is not a nod")

	# A real nod swings the head past the zone's edge and back.
	_rate(-120.0)
	_aim(_game_dir("C") + Vector2(0.0, -22.0))
	await _hold(0.15)
	_expect(_game.phase == Game.Phase.TURN and _game._zone == 0, "swinging past the edge mid-nod does not leave the zone")
	_rate(120.0)
	_aim(_game_dir("C"))
	await _hold(0.2)
	_expect(_game._run_count == 2, "that nod counts as the repeat")

	_game.strict_repeat_count = true  # count past C's two, to see the key land
	await _game.simulate_nod()
	await _hold(0.2)
	_expect(_game._run_count == 3, "the nod key goes through the same detector")
	_game.strict_repeat_count = false


func _check_pass_through() -> void:
	print("-- pass-through")
	await _new_game()
	_played.clear()
	# Sweep across A's zone without stopping, on the way to the expected C.
	_aim(_game_dir("A"))
	await _hold(0.12)
	_aim(REST)
	await _hold(0.3)
	_expect(_played.is_empty() and _game.phase == Game.Phase.TURN, "passing through a wrong zone without dwell is not a miss")
	# The dead zone: just past the radius, C is still not left.
	await _arrive("C")
	_aim(_game_dir("C") + Vector2(0.0, _game.zone_radius_deg + _game.dead_zone_deg * 0.5))
	await _hold(0.3)
	_expect(_game._zone == 0 and _game.phase == Game.Phase.TURN, "inside the dead zone the head has not left")


func _check_recenter_zeroes_pitch() -> void:
	print("-- recenter")
	_aim(Vector2(10.0, 25.0))
	await _frames(3)
	GameState.recenter()
	await _frames(3)
	var angles := _game.head_angles_deg()
	_expect(angles.length() < 0.5, "recenter zeroes yaw and pitch (%s)" % angles)
	SensorBridge._source._pitch = 0.0
	await _frames(3)
	_expect(absf(_game.head_angles_deg().y + 25.0) < 0.5, "later pitch is read from the new zero (%s, zero %.1f, sim %.1f/%.1f, src pitch %.3f)" % [_game.head_angles_deg(), _game._pitch_zero_deg, _game._sim_yaw_deg, _game._sim_pitch_deg, SensorBridge._source._pitch])
	_aim(REST)
	await _frames(3)
	GameState.recenter()
	await _frames(3)


func _check_full_win() -> void:
	print("-- full game")
	_expect(SfxLibrary.has_stream(_game.success_sound), "success sound resolves through SfxLibrary")
	_expect(SfxLibrary.get_stream(_game.success_sound).get_length() > 2.0, "and it is the 2.5 s success.mp3")
	await _new_game()
	var ended: Array = []
	_game.game_ended.connect(func(rounds, won): ended.append_array([rounds, won]), CONNECT_ONE_SHOT)
	for n in _game.song_phrases.size():
		await _until(func(): return _game.phase == Game.Phase.TURN, 120.0)
		_expect(_game.level == n + 1, "level %d reached" % (n + 1))
		var sequence := " ".join(_game.song_phrases.slice(0, n + 1))
		await _play_sequence(sequence)
		await _until(func(): return _game.phase != Game.Phase.TURN, 5.0)
	await _until(func(): return not ended.is_empty(), 30.0)
	_expect(ended == [6, true], "all levels passed is a win with 6 rounds (%s)" % [ended])
	_expect(_game.end_line == &"simon_rounds_6", "result line is simon_rounds_6")
	for i in 7:
		_expect(BatCompanion._line_text.has(StringName("simon_rounds_%d" % i)), "lines.txt has simon_rounds_%d" % i)
	_expect(_game.get_child_count() > 0 and GameState.input_locked, "scan stays locked during the minigame")


# --- Helpers ------------------------------------------------------------------

## Starts a fresh game and returns when the player's turn begins.
func _new_game() -> void:
	_aim(REST)
	await _frames(3)
	_played.clear()
	_demo_played.clear()
	_game.start_game()
	await _until(func(): return _game.level == 1 and _game.phase == Game.Phase.TURN, 60.0)


## Plays a whole sequence the way a player would: arrive, nod for repeats.
func _play_sequence(sequence: String) -> void:
	var names := sequence.split(" ", false)
	var i := 0
	while i < names.size():
		var length := 1
		while i + length < names.size() and names[i + length] == names[i]:
			length += 1
		await _arrive(names[i])
		for _r in length - 1:
			await _nod()
		i += length
		if i < names.size():
			await _aim_and_hold(REST, 0.1)


func _arrive(note_name: String) -> void:
	_aim(_game_dir(note_name))
	await _hold(_game.dwell_seconds + 0.2)


func _nod() -> void:
	_rate(-120.0)
	await _hold(0.1)
	_rate(120.0)
	await _hold(_game.nod_cooldown_seconds + 0.1)


func _aim_and_hold(angles: Vector2, seconds: float) -> void:
	_aim(angles)
	await _hold(seconds)


func _expect_end(action: Callable) -> Array:
	var ended: Array = []
	_game.game_ended.connect(func(rounds, won): ended.append_array([rounds, won]), CONNECT_ONE_SHOT)
	await action.call()
	await _hold(0.2)
	return ended


func _game_dir(note_name: String) -> Vector2:
	var i: int = _game.note_names.find(note_name)
	return Vector2(_game.note_yaw_deg[i], _game.note_pitch_deg[i])


## Points the head through the mouse source. angles is (yaw, pitch) in the note
## table's convention, relative to the current zero.
func _aim(angles: Vector2) -> void:
	var source: Variant = SensorBridge._source
	source._yaw = -deg_to_rad(angles.x) - GameState.yaw_offset
	source._pitch = deg_to_rad(angles.y + _game._pitch_zero_deg)


func _rate(deg_per_second: float) -> void:
	SensorBridge._on_pitch_rate_sample(deg_to_rad(deg_per_second))


func _notes(sequence: String) -> Array[int]:
	var notes: Array[int] = []
	for note_name in sequence.split(" ", false):
		notes.append(_game.note_names.find(note_name))
	return notes


func _hold(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _until(condition: Callable, timeout: float) -> void:
	var waited := 0.0
	while not condition.call() and waited < timeout:
		await _hold(0.05)
		waited += 0.05
	if not condition.call():
		_expect(false, "timed out waiting (%.0fs game time)" % timeout)


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
