extends Node

## Autopilot for the tutorial: calibration gestures through SensorBridge's
## pitch-rate signal, then scan, walk, FOCUS and notes, as a player would.
##
##   Godot --headless --path . tutorial.tscn -- --autotest
##
## Saves calibration to a throwaway file, never the real one.

const TEST_CALIBRATION := "user://gesture_calibration_autotest.cfg"

var _tut: Node = null
var _failures := 0
var _checks := 0
var _real_path := ""


func _ready() -> void:
	_tut = get_parent()
	_tut.return_to_menu_seconds = 0.0
	_real_path = GameState.calibration_path
	GameState.calibration_path = TEST_CALIBRATION
	GameState.calibration.clear()
	_run.call_deferred()


func _run() -> void:
	print("\n=== TUTORIAL AUTOTEST ===")
	_check(BatCompanion._line_text.has(&"tut_nod") and BatCompanion._line_text.has(&"note_added"), "tutorial lines are in lines.txt")
	_tut.run()
	await _until_step(&"calibrate_nod")
	await _wait(0.5)
	await _gesture([-15.0])  # far too small: under the detection speed
	await _wait(1.6)
	_check(_tut.step == &"calibrate_nod", "a tiny movement doesn't count")
	await _gesture([-40.0, -70.0, -40.0, 0.001, 40.0, 70.0, 40.0])
	_check(await _until_step(&"calibrate_up"), "a real nod is captured and the bat moves on")
	await _wait(0.5)
	await _gesture([70.0, 70.0])  # fast but tiny: travel too short
	await _wait(1.0)
	_check(_tut.step == &"calibrate_up", "a twitch is 'a bit bigger', not a jolt")
	await _gesture([120.0, 260.0, 300.0, 260.0, 120.0])
	_check(await _until_step(&"calibrate_down"), "a jolt up is captured")
	await _wait(0.5)
	await _gesture([-150.0, -320.0, -360.0, -300.0, -150.0])
	_check(await _until_step(&"calibrate_shake"), "a headbutt is captured")
	await _wait(0.5)
	await _turn(40.0, 0.4)  # one ordinary head turn is not a shake
	await _wait(2.8)
	_check(_tut.step == &"calibrate_shake", "a single head turn doesn't count as a shake")
	for i in 4:
		await _turn(25.0 * (1 if i % 2 == 0 else -1), 0.18)
	_check(await _until_step(&"scan"), "a real shake is captured, calibration done")

	var m: Dictionary = _tut.measured
	print("  measured: %s" % m)
	_check(m.up_rate > m.nod_rate * 1.2 and m.down_rate > m.nod_rate * 1.2, "jolt thresholds sit well above the nod")
	_check(absf(m.up_rate - 300.0 * _tut.calibration_margin) < 1.0, "the jolt-up threshold comes from the player's own speed")
	_check(FileAccess.file_exists(TEST_CALIBRATION), "calibration is saved to disk")
	_check(is_equal_approx(GameState.flick_threshold(1, "rate"), m.up_rate) and is_equal_approx(GameState.flick_threshold(-1, "rate"), m.down_rate),
			"the main game's river jump and headbutt read it (up and down separately)")
	_check(is_equal_approx(GameState.nod_threshold(), m.nod_rate), "the minigame's nod reads it")
	_check(is_equal_approx(GameState.shake_threshold("rate"), m.shake_rate) and m.shake_max_swing >= 30.0,
			"the swarm and climb shakes read it, with a look-around limit (%.0f deg)" % m.shake_max_swing)
	GameState.calibration.clear()
	GameState.load_calibration()
	_check(is_equal_approx(GameState.nod_threshold(), m.nod_rate), "and it is there again after a reload")

	BatCompanion._last_scan = -999.0
	BatCompanion.scan()
	_check(await _until_step(&"walk"), "pressing scan moves on to walking")
	var target: Node3D = _tut.get_node("Target")
	var player: Node3D = _tut.get_node("player")
	var to_target := target.global_position - player.global_position
	_check(to_target.x < -2.0 and to_target.z < -5.0, "the target is ahead and to the left of the start")
	_tut.get_node("Target/Source/Body/AudioStreamPlayer3D")
	var src: AudioStreamPlayer3D = _tut.get_node("Target/Source/Body/AudioStreamPlayer3D")
	_check(src.max_distance < to_target.length(), "it can't be heard from the start (%.0f m away, audible within %.0f)" % [to_target.length(), src.max_distance])
	player.global_position = target.global_position + Vector3(4, 0.1, 3)
	_check(await _until_step(&"focus"), "walking close: 'have you started to hear that', then FOCUS")
	var focus: Node = _tut.get_node("Target/Focusable")
	var d: Vector3 = focus.global_position - GameState.head_position
	SensorBridge._source._yaw = atan2(-d.x, -d.z) - GameState.yaw_offset
	SensorBridge._source._pitch = 0.0
	_check(await _until(func(): return focus.revealed_state, 30.0), "holding on it, FOCUS names it")
	var notes_before := GameState.observations.size()
	_check(await _until_step(&"notes"), "then the notes step")
	_check(GameState.observations.size() == notes_before + 1, "the chime goes in the notes")
	var notes_player: AudioStreamPlayer = GameState._notes_player
	_check(notes_player != null and notes_player.stream == SfxLibrary.get_stream("notes_added"), "with the notes sound")
	_check(notes_player.stream != SfxLibrary.get_stream("focus_discovery"), "which is not the discovery sting")
	_check(await _until_step(&"done", 40.0), "and the tutorial finishes")

	GameState.calibration_path = _real_path
	GameState.calibration.clear()
	GameState.load_calibration()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CALIBRATION))
	print("=== %d checks, %d failed ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Turns the head degrees over seconds of real time, through the mouse source.
func _turn(degrees: float, seconds: float) -> void:
	var steps := maxi(int(seconds * 60.0), 1)
	for i in steps:
		SensorBridge._source._yaw += deg_to_rad(degrees) / steps
		await get_tree().create_timer(1.0 / 60.0).timeout


## Sends a movement as pitch-rate samples (deg/s), one per 1/60 s.
func _gesture(rates: Array) -> void:
	for r in rates:
		SensorBridge._on_pitch_rate_sample(deg_to_rad(r))
		await get_tree().create_timer(1.0 / 60.0).timeout
	SensorBridge._on_pitch_rate_sample(0.0)


func _until_step(step: StringName, timeout: float = 20.0) -> bool:
	return await _until(func(): return _tut.step == step, timeout)


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > timeout:
			return false
	return true


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
