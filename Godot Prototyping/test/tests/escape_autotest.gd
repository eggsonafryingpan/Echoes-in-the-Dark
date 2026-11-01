extends Node

## Autopilot run of the whole escape, E1 -> E4, with assertions. No
## hardware, no hands: it steers the head through the mouse fallback and
## the legs through the movement actions, the same inputs a player has.
##
##   Godot --path . escape_level.tscn -- --autotest --sensor=live            (watch it)
##   Godot --headless --path . escape_level.tscn -- --autotest --sensor=live  (just results)
##
## Prints PASS/FAIL per check and quits with exit code 0 (all passed) or 1.
## Added by escape_level.gd only when --autotest is on the command line.
## Runs at time_scale 3 to keep it short; every timer, tween and physics
## step scales with it, so the logic under test is unchanged.

const Event := preload("res://autoload/event_director.gd").Event
const Stealth := preload("res://scripts/events/stealth_encounter.gd")
const ExitWind := preload("res://scripts/events/exit_wind.gd")
const Climb := preload("res://scripts/events/rockfall_climb.gd")

@export var time_scale: float = 3.0

var _level: Node = null
var _failures: int = 0
var _checks: int = 0
var _aim_target: Variant = null  # Vector3 to keep the head pointed at, or null
var _aim_yaw: Variant = null     # or a fixed world yaw


func _ready() -> void:
	_level = get_parent()
	if OS.get_cmdline_user_args().has("--livecheck"):
		_live_check.call_deferred()
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aerial-shot="):
			_aerial_shot.call_deferred(arg.trim_prefix("--aerial-shot="))
			return
	Engine.time_scale = time_scale
	_run.call_deferred()


## --aerial-shot=<png>: jump into E3 (animal, trigger and markers all on
## show), switch to the aerial camera, save a screenshot, quit. Needs a
## window (not --headless).
func _aerial_shot(path: String) -> void:
	await _frames(20)
	EventDirector.jump_to(Event.STEALTH)
	await _frames(60)
	_level.get_node("TopDownCamera").make_current()
	await _frames(10)
	get_viewport().get_texture().get_image().save_png(path)
	print("aerial shot saved: " + path)
	get_tree().quit(0)


## --livecheck: no driving, no assertions about events -- just report, once
## a second, what the live pipeline is delivering into GameState. Run it
## with sensor_bridge/bridge.py up (and the EmotiBit, or a synthetic feed).
func _live_check() -> void:
	var seconds := 40
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--livecheck-seconds="):
			seconds = arg.trim_prefix("--livecheck-seconds=").to_int()
	print("\n=== LIVE CHECK (%ds) ===" % seconds)
	for i in seconds:
		await get_tree().create_timer(1.0).timeout
		print("  t=%2ds  %s | GameState hr %.1f valid=%s resting=%.1f | yaw %.2f" % [
			i + 1, SensorBridge.status_text(), GameState.hr_bpm, GameState.hr_valid,
			SensorBridge.resting_bpm, GameState.orientation.y])
	get_tree().quit(0)


func _physics_process(_delta: float) -> void:
	# Head steering: write the mouse fallback's yaw so effective yaw lands
	# where we want it (effective = orientation + yaw_offset).
	var want: Variant = null
	if _aim_target != null:
		var d: Vector3 = _aim_target - GameState.head_position
		want = atan2(-d.x, -d.z)
	elif _aim_yaw != null:
		want = _aim_yaw
	if want != null and SensorBridge._fallback != null:
		SensorBridge._fallback._yaw = want - GameState.yaw_offset
		SensorBridge._fallback._pitch = 0.0


func _run() -> void:
	print("\n=== ESCAPE AUTOTEST (sensor: %s) ===" % SensorBridge.status_text())
	await _test_recenter()
	await _test_event_one()
	await _test_event_two()
	await _test_scan()
	await _test_den()
	await _test_stealth_anti_lockout()
	await _test_stealth_assisted_pass()
	await _test_climb()
	print("=== %d/%d checks passed ===\n" % [_checks - _failures, _checks])
	Engine.time_scale = 1.0
	get_tree().quit(1 if _failures > 0 else 0)


# --- helpers ----------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Waits (game time) until cond() is true or timeout; returns whether it held.
func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > timeout:
			return false
	return true


func _hold(action: StringName, seconds: float) -> void:
	Input.action_press(action)
	await get_tree().create_timer(seconds).timeout
	Input.action_release(action)


# --- tests ------------------------------------------------------------------

func _test_recenter() -> void:
	print("[recenter]")
	SensorBridge._fallback._yaw = 1.3
	await _frames(2)
	GameState.recenter()
	await _frames(2)
	_check(absf(GameState.effective_orientation().y - GameState.reference_yaw) < 0.01,
			"recenter makes the current facing 'ahead' (ref %.2f)" % GameState.reference_yaw)


func _test_event_one() -> void:
	print("[E1 CALM]")
	_check(await _until(func(): return EventDirector.event_one_active, 5.0), "Event 1 starts on load")
	_check(await _until(func(): return GameState.input_locked, 3.0), "input locked during the cold open")
	_check(await _until(func(): return EventDirector.calm_active, 60.0), "CALM starts after the bat's lines")
	_check(not await _until(func(): return not EventDirector.calm_active, 12.0),
			"CALM does not pass on time alone with no heart-rate drop")
	EventDirector.start_calm_assist()
	_check(await _until(func(): return EventDirector.current_event == Event.FOCUS, 120.0),
			"F4 assist brings HR down -> Event 1 completes")
	_check(not GameState.input_locked, "input unlocked after Event 1")


func _test_event_two() -> void:
	print("[E2 FOCUS on the wind]")
	_aim_yaw = 0.0
	Input.action_press(&"up")
	var started := await _until(func(): return EventDirector.event_running and EventDirector.current_event == Event.FOCUS, 20.0)
	Input.action_release(&"up")
	_check(started, "walking into the wind chamber starts E2")
	var wind: Node3D = _level.exit_wind
	_check(wind.mode == ExitWind.Mode.FOCUS, "wind is in FOCUS mode (faint, focusable)")
	_aim_yaw = null
	_aim_target = wind.global_position
	var focusable: Focusable = wind.get_node("Focusable")
	var revealed := await _until(func():
		_aim_target = wind.global_position
		return focusable.revealed_state, 30.0)
	_aim_target = null
	_check(revealed, "holding the head on it reveals the wind")
	_check(EventDirector.current_event == Event.STEALTH, "E2 complete -> E3 armed")
	_check(wind.mode == ExitWind.Mode.HEADING, "wind becomes the heading")


func _test_scan() -> void:
	print("[scan]")
	_level.teleport_player(_level.get_node("Landmarks/Fork").global_position, 0.0)
	_aim_yaw = 0.0
	await _frames(5)
	var got: Array = []
	var on_scan := func(r: Array): got.append(r)
	BatCompanion.scan_performed.connect(on_scan)
	BatCompanion._last_scan = -999.0
	BatCompanion.scan()
	BatCompanion.scan()  # inside the cooldown: must not scan again
	await _frames(3)
	BatCompanion.scan_performed.disconnect(on_scan)
	_check(got.size() == 1, "second press inside the cooldown does not scan (scans: %d)" % got.size())
	var returns: Array = got[0] if not got.is_empty() else []
	_check(returns.size() >= 2 and returns.size() <= 3, "fork scan returns 2-3 things (got %d)" % returns.size())
	var separated := true
	var ordered := true
	for i in returns.size():
		for j in range(i + 1, returns.size()):
			if rad_to_deg(returns[i].bearing.angle_to(returns[j].bearing)) < BatCompanion.min_separation_deg - 0.1:
				separated = false
		if i > 0 and (returns[i].delay < returns[i - 1].delay + BatCompanion.min_return_gap - 0.001 \
				or returns[i].volume_db > returns[i - 1].volume_db):
			ordered = false
	_check(separated, "returns are >= %.0f deg apart" % BatCompanion.min_separation_deg)
	_check(ordered, "farther returns come later and quieter")
	for r in returns:
		print("      return: %-18s %5.1fm %-4s %s delay %.2fs %+.1f dB" % [
			r.node.get_parent().name, r.distance, r.band, "BEHIND" if r.behind else "front ", r.delay, r.volume_db])


func _test_den() -> void:
	print("[den reward]")
	var den: Node3D = _level.get_node("Den")
	_level.teleport_player(den.global_position + Vector3(6, 0, 0), deg_to_rad(90))
	var focus: Focusable = den.get_node("Focusable")
	var found := await _until(func():
		_aim_target = den.global_position
		return _level.den_found, 30.0)
	_aim_target = null
	_check(found and focus.revealed_state, "focusing the nest finds the den")


func _test_stealth_anti_lockout() -> void:
	print("[E3 STEALTH: fail, fail, anti-lockout pass]")
	var stealth: Node = _level.stealth
	stealth.den_approach_seconds = 4.0
	stealth.approach_seconds = 4.0
	stealth.pass_seconds = 2.0
	EventDirector.jump_to(Event.STEALTH)
	_check(await _until(func(): return stealth.state == Stealth.State.APPROACH, 3.0), "jump to E3 starts the encounter")
	_check(GameState.input_locked and EventDirector.calm_active, "player frozen, CALM running")
	EventDirector.level.force_fail(Event.STEALTH)  # F11
	_check(await _until(func(): return stealth.state == Stealth.State.IDLE and stealth.attempt == 1, 5.0),
			"F11 -> caught -> knocked back, re-armed")
	var cp: Vector3 = _level.get_node("Checkpoints/E3_BeforeStealth").global_position
	_check(_level.player.global_position.distance_to(cp) < 1.5, "knockback lands at the retry checkpoint")
	_check(not GameState.input_locked, "input free after the knockback")
	_check(EventDirector.current_event == Event.STEALTH, "the run is still on E3 (no game over)")

	await _walk_into_stealth()
	_check(stealth.attempt == 2, "walking back in starts attempt 2")
	_check(await _until(func(): return stealth.state == Stealth.State.IDLE, 10.0),
			"attempt 2 with no heart-rate data is caught (%s)" % stealth.last_verdict)

	await _walk_into_stealth()
	_check(await _until(func(): return EventDirector.current_event == Event.ESCAPE, 15.0),
			"attempt 3 passes regardless (anti-lockout): %s" % stealth.last_verdict)


func _test_stealth_assisted_pass() -> void:
	print("[E3 STEALTH: calm heart rate passes first time]")
	var stealth: Node = _level.stealth
	stealth.den_approach_seconds = 8.0
	EventDirector.jump_to(Event.STEALTH)
	await _until(func(): return EventDirector.calm_active, 3.0)
	EventDirector.start_calm_assist()  # F4: a scripted descending HR
	_check(await _until(func(): return EventDirector.current_event == Event.ESCAPE, 20.0),
			"with HR coming down, attempt 1 passes: %s" % stealth.last_verdict)


func _walk_into_stealth() -> void:
	_aim_yaw = 0.0
	Input.action_press(&"up")
	await _until(func(): return _level.stealth.state != Stealth.State.IDLE, 8.0)
	Input.action_release(&"up")


func _test_climb() -> void:
	print("[E4 ESCAPE]")
	var climb: Node = _level.climb
	climb.first_rock_delay = 1.0
	EventDirector.jump_to(Event.ESCAPE)
	_aim_yaw = 0.0
	await _frames(3)
	_check(climb.active, "jump to E4 starts the climb")

	# Stand still: the first rock lands on us.
	var s0: float = _level.project(_level.player.global_position).s
	_check(await _until(func(): return climb.rocks_dropped >= 1, 5.0), "a rock is announced")
	var side: int = climb.last_side
	_check(await _until(func(): return climb.hits >= 1, 5.0), "standing still under it is a hit")
	var s1: float = _level.project(_level.player.global_position).s
	_check(s1 <= s0 + 0.01, "the hit slides the player back down (s %.1f -> %.1f)" % [s0, s1])
	_check(EventDirector.current_event == Event.ESCAPE, "the run continues after a hit")

	# Next rock: step away from the side it was announced on.
	var before: int = climb.rocks_dropped
	await _until(func(): return climb.rocks_dropped > before, 10.0)
	side = climb.last_side
	var dodge := &"right" if side == Climb.LEFT else &"left"
	var hits_before: int = climb.hits
	await _hold(dodge, 0.5)
	await _until(func(): return climb._pending.is_empty(), 5.0)
	_check(climb.hits == hits_before, "moving away from the %s cue dodges it" % ("left" if side == Climb.LEFT else "right"))

	# Climb out, dodging whatever comes.
	var done := await _climb_to_top(90.0)
	_check(done, "reaching the top completes the run (hits %d)" % climb.hits)
	_check(EventDirector.current_event == Event.DONE, "EventDirector reports DONE")
	_check(_level.exit_wind.mode == ExitWind.Mode.FULL, "wind comes in full at the top")


func _climb_to_top(timeout: float) -> bool:
	var climb: Node = _level.climb
	var t := 0.0
	Input.action_press(&"up")
	while not _level.run_finished and t < timeout:
		if not climb._pending.is_empty():
			var away := &"right" if climb._pending.side == Climb.LEFT else &"left"
			Input.action_press(away)
			await get_tree().create_timer(0.5).timeout
			Input.action_release(away)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release(&"up")
	return _level.run_finished
