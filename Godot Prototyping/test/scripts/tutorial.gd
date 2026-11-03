extends Node3D

## The tutorial (tutorial.tscn, "Tutorial" on the main menu). One guided
## sequence, narrated by the bat, that moves on only when the player has
## done each thing:
##
##   Part A, calibration: nod, jolt up, jolt down (a headbutt). Each is
##   captured from the player's real movement, and the thresholds derived
##   from it are saved through GameState, so the main game and the minigame
##   use them too.
##   Part B, the loop: scan, walk toward what the scan found, hear it, hold
##   FOCUS on it until it is named, then record it in the notes.
##
## No fail state. A prompt repeats if the player stalls; a gesture that was
## too small gets "a bit bigger". X returns to the menu at any point.
##
## Automated check: Godot --headless --path . tutorial.tscn -- --autotest

signal step_changed(step: StringName)

# ------------------------------------------------------------------------
# TUTORIAL CONFIG
# ------------------------------------------------------------------------
@export_group("Calibration")
## Thresholds are this fraction of what the player actually did, so the
## same movement, done a little more gently next time, still counts.
@export var calibration_margin: float = 0.65
## A movement starts being captured once it is this fast (deg/s).
@export var nod_detect_deg: float = 25.0
@export var jolt_detect_deg: float = 50.0
## How long after it starts a movement is measured.
@export var nod_window_seconds: float = 1.0
@export var jolt_window_seconds: float = 0.5
## Smaller than this and the bat asks for a bit bigger.
@export var min_nod_rate_deg: float = 30.0
@export var min_jolt_rate_deg: float = 60.0
@export var min_jolt_travel_deg: float = 8.0
## Jolt thresholds are kept at least this many times the nod's speed, so a
## nod in the minigame can never read as a river jump or a headbutt.
@export var jolt_above_nod: float = 1.25
## The shake sample: capture starts at this yaw speed (deg/s), runs this long,
## and needs at least this many alternating swings.
@export var shake_detect_deg: float = 40.0
@export var shake_window_seconds: float = 2.5
@export var min_shake_swings: int = 3
## The saved "too big to be a shake" limit is this many times the sample's
## biggest swing.
@export var shake_max_swing_factor: float = 2.0
## Saved thresholds are held inside these ranges (rate deg/s, travel deg).
@export var rate_limits: Vector2 = Vector2(25.0, 400.0)
@export var travel_limits: Vector2 = Vector2(5.0, 60.0)

@export_group("Mode")
## Only the gesture calibration, then back to the menu (calibration.tscn,
## "Calibrate" on the menu, ./launch.sh calibrate).
@export var calibration_only: bool = false

@export_group("Pacing")
## A prompt is said again after this long with nothing happening.
@export var stall_repeat_seconds: float = 12.0
## Close enough to the target for "have you started to hear that?".
@export var near_distance: float = 7.0
## Back to the main menu this long after the last line. 0 stays.
@export var return_to_menu_seconds: float = 4.0

@export_group("Scene")
@export var player_path: NodePath = ^"player"
@export var target_path: NodePath = ^"Target"
@export var focus_path: NodePath = ^"Target/Focusable"
@export var note_text: String = "A bird, in the practice cave."
## Read back on an end screen; the tutorial has none, so no line.
@export var note_line: StringName = &""

@export_group("Lines")
## Empty: no separate welcome. The first prompt does the job.
@export var welcome_line: StringName = &""
@export var nod_line: StringName = &"tut_nod"
@export var jolt_up_line: StringName = &"tut_jolt_up"
@export var jolt_down_line: StringName = &"tut_jolt_down"
@export var shake_line: StringName = &"tut_shake"
@export var good_line: StringName = &"tut_good"
@export var bigger_line: StringName = &"try_again"
@export var scan_line: StringName = &"tut_scan"
@export var walk_line: StringName = &"tut_walk"
## Empty: the walk line already says to listen as you get closer.
@export var hear_line: StringName = &""
@export var focus_line: StringName = &"tut_focus"
## Empty: the notes step uses the main game's own "noted" line (note_added).
@export var notes_line: StringName = &""
@export var done_line: StringName = &"tut_done"
@export_group("")

var step: StringName = &""
## What the calibration measured and saved, for the log and the autotest.
var measured: Dictionary = {}

var _player: Node3D = null
var _target: Node3D = null
var _focus: Node = null
var _scanned := false

# Gesture capture: pitch-rate samples in deg/s, timed per sample.
var _capture := &""          # "", "nod", "up", "down", "shake"
# Shake capture: yaw swings, each {peak, travel}, alternating.
var _last_yaw := 0.0
var _have_yaw := false
var _t_yaw := 0.0
var _swings: Array = []
var _swing_dir := 0
var _swing_peak := 0.0
var _swing_travel := 0.0
var _capturing := false
var _t_start := 0.0
var _down_peak := 0.0
var _up_peak := 0.0
var _peak := 0.0
var _travel := 0.0
var _t_arrival := 0.0
var _result: Variant = null  # a Dictionary once a capture finishes, "small" if too small


func _ready() -> void:
	_player = get_node(player_path)
	_target = get_node(target_path)
	_focus = get_node(focus_path)
	_focus.active = false  # FOCUS is taught last
	BatCompanion.reset_scan_session()
	BatCompanion.scan_performed.connect(func(_r): _scanned = true)
	SensorBridge.pitch_rate_updated.connect(_on_pitch_rate)
	SensorBridge.orientation_updated.connect(_on_orientation)
	if OS.get_cmdline_user_args().has("--autotest"):
		var test := Node.new()
		test.name = "Autotest"
		test.set_script(load("res://tests/tutorial_autotest.gd"))
		add_child(test)
		return
	run.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"exit_to_main_menu"):
		_to_menu()


func run() -> void:
	await _say_and_wait(welcome_line)

	# --- Part A: calibration ---
	var nod: Dictionary = await _calibrate(&"nod", nod_line)
	var up: Dictionary = await _calibrate(&"up", jolt_up_line)
	var down: Dictionary = await _calibrate(&"down", jolt_down_line)
	var shake: Dictionary = await _calibrate(&"shake", shake_line)
	var nod_rate := clampf(nod.rate * calibration_margin, rate_limits.x, rate_limits.y)
	var floor_rate: float = nod.rate * jolt_above_nod
	measured = {
		"nod_rate": nod_rate,
		"up_rate": clampf(maxf(up.rate * calibration_margin, floor_rate), rate_limits.x, rate_limits.y),
		"up_travel": clampf(up.travel * calibration_margin, travel_limits.x, travel_limits.y),
		"down_rate": clampf(maxf(down.rate * calibration_margin, floor_rate), rate_limits.x, rate_limits.y),
		"down_travel": clampf(down.travel * calibration_margin, travel_limits.x, travel_limits.y),
		"shake_rate": clampf(shake.rate * calibration_margin, rate_limits.x, rate_limits.y),
		"shake_swing": clampf(shake.travel * calibration_margin, travel_limits.x, travel_limits.y),
		"shake_max_swing": clampf(shake.max_swing * shake_max_swing_factor, 30.0, 150.0),
	}
	GameState.save_calibration(measured)
	if calibration_only:
		_set_step(&"done")
		await _say_and_wait(done_line)
		if return_to_menu_seconds > 0.0:
			await get_tree().create_timer(return_to_menu_seconds).timeout
			_to_menu()
		return

	# --- Part B: the loop ---
	_set_step(&"scan")
	await _until(func(): return _scanned, scan_line)
	_set_step(&"walk")
	await _until(func(): return _player.global_position.distance_to(_target.global_position) <= near_distance, walk_line)
	_set_step(&"hear")
	await _say_and_wait(hear_line)
	_set_step(&"focus")
	_focus.active = true
	await _until(func(): return _focus.revealed_state, focus_line)
	# The target's own reveal line ("You've identified ...") plays from FOCUS.
	await _bat_quiet()
	_set_step(&"notes")
	# Same notes sound and "noted" line as the main game, straight away.
	GameState.record_observation(&"tutorial_chime", note_text, note_line, true, 0.0)
	await get_tree().create_timer(1.0).timeout
	await _say_and_wait(notes_line)
	_set_step(&"done")
	await _say_and_wait(done_line)
	if return_to_menu_seconds > 0.0:
		await get_tree().create_timer(return_to_menu_seconds).timeout
		_to_menu()


## Asks for a gesture until a big enough one is captured; returns its
## {rate, travel}.
func _calibrate(kind: StringName, prompt: StringName) -> Dictionary:
	_set_step(StringName("calibrate_" + kind))
	BatCompanion.say(prompt)
	await _bat_quiet()
	var waited := 0.0
	while true:
		_begin_capture(kind)
		while _result == null:
			await get_tree().process_frame
			waited += get_process_delta_time()
			if waited >= stall_repeat_seconds and not BatCompanion.is_speaking():
				waited = 0.0
				BatCompanion.say(prompt)
		if _result is Dictionary:
			print("Tutorial: %s captured: %s" % [kind, _result])
			var got: Dictionary = _result
			_capture = &""
			BatCompanion.say(good_line)
			await _bat_quiet()
			return got
		print("Tutorial: %s too small, asking for bigger" % kind)
		waited = 0.0
		BatCompanion.say(bigger_line)
		await _bat_quiet()
	return {}


func _begin_capture(kind: StringName) -> void:
	_capture = kind
	_capturing = false
	_result = null
	_down_peak = 0.0
	_up_peak = 0.0
	_peak = 0.0
	_travel = 0.0
	_swings.clear()
	_swing_dir = 0
	_swing_peak = 0.0
	_swing_travel = 0.0


func _on_pitch_rate(rate: float) -> void:
	# The mouse reports an exact 0 every idle frame; like GameState, those are
	# not samples, or they would shrink the time each real sample covers.
	if rate == 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var gap := now - _t_arrival
	_t_arrival = now
	if _capture == &"" or _result != null:
		return
	# Same timing as GameState's detector: live samples are one sample period
	# each, mouse samples the time since the last.
	var dt := 1.0 / GameState.live_sample_hz if SensorBridge.live_orientation_active() \
			else (gap if gap <= 0.1 else 1.0 / 60.0)
	var deg := rad_to_deg(rate)
	match _capture:
		&"nod":
			if not _capturing:
				if deg <= -nod_detect_deg:
					_capturing = true
					_t_start = now
				else:
					return
			_down_peak = maxf(_down_peak, -deg)
			_up_peak = maxf(_up_peak, deg)
		&"up", &"down":
			var along := deg if _capture == &"up" else -deg
			if not _capturing:
				if along >= jolt_detect_deg:
					_capturing = true
					_t_start = now
				else:
					return
			if along > 0.0:
				_peak = maxf(_peak, along)
				_travel += along * dt


## Yaw for the shake sample, timed per sample like the pitch captures.
func _on_orientation(euler: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var gap := now - _t_yaw
	_t_yaw = now
	if not _have_yaw:
		_have_yaw = true
		_last_yaw = euler.y
		return
	var dt := 1.0 / GameState.live_sample_hz if SensorBridge.live_orientation_active() \
			else clampf(gap, 0.001, 0.1)
	var rate := rad_to_deg(wrapf(euler.y - _last_yaw, -PI, PI)) / dt
	_last_yaw = euler.y
	if _capture != &"shake" or _result != null:
		return
	if not _capturing:
		if absf(rate) < shake_detect_deg:
			return
		_capturing = true
		_t_start = now
	var dir := signi(int(signf(rate)))
	if dir == 0:
		return
	if dir != _swing_dir:
		_close_swing()
		_swing_dir = dir
	_swing_peak = maxf(_swing_peak, absf(rate))
	_swing_travel += absf(rate) * dt


func _close_swing() -> void:
	if _swing_dir != 0 and _swing_travel >= 3.0 and _swing_peak >= shake_detect_deg:
		_swings.append({"peak": _swing_peak, "travel": _swing_travel})
	_swing_peak = 0.0
	_swing_travel = 0.0


func _process(_delta: float) -> void:
	if not _capturing or _result != null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _capture == &"shake":
		if now - _t_start >= shake_window_seconds:
			_close_swing()
			_capturing = false
			if _swings.size() < min_shake_swings:
				_result = "small"
				return
			var peaks := _swings.map(func(s): return s.peak)
			var travels := _swings.map(func(s): return s.travel)
			_result = {"rate": peaks.min(), "travel": travels.min(), "max_swing": travels.max()}
		return
	if _capture == &"nod" and now - _t_start >= nod_window_seconds:
		var rate := minf(_down_peak, _up_peak)
		_result = {"rate": rate, "travel": 0.0} if rate >= min_nod_rate_deg else "small"
		_capturing = false
	elif _capture != &"nod" and now - _t_start >= jolt_window_seconds:
		var ok := _peak >= min_jolt_rate_deg and _travel >= min_jolt_travel_deg
		_result = {"rate": _peak, "travel": _travel} if ok else "small"
		_capturing = false


## Says the prompt, then says it again every stall_repeat_seconds until done.
func _until(done: Callable, prompt: StringName) -> void:
	BatCompanion.say(prompt)
	var waited := 0.0
	while not done.call():
		await get_tree().process_frame
		waited += get_process_delta_time()
		if waited >= stall_repeat_seconds and not BatCompanion.is_speaking():
			waited = 0.0
			BatCompanion.say(prompt)


func _say_and_wait(line: StringName) -> void:
	if line == &"":
		return
	BatCompanion.say(line)
	await _bat_quiet()


func _bat_quiet() -> void:
	await get_tree().process_frame
	var waited := 0.0
	while BatCompanion.is_speaking() and waited < 30.0:
		await get_tree().process_frame
		waited += get_process_delta_time()


func _set_step(new_step: StringName) -> void:
	step = new_step
	print("Tutorial: step %s" % step)
	step_changed.emit(step)


func _to_menu() -> void:
	BatCompanion.shut_up()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://main_menu.tscn")
