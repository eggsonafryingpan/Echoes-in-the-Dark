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
const River := preload("res://scripts/events/river_crossing.gd")
const Stealth := preload("res://scripts/events/stealth_encounter.gd")
const ExitWind := preload("res://scripts/events/exit_wind.gd")
const Climb := preload("res://scripts/events/grip_climb.gd")

@export var time_scale: float = 3.0

var _level: Node = null
var _failures: int = 0
var _checks: int = 0
var _aim_target: Variant = null  # Vector3 to keep the head pointed at, or null
var _aim_yaw: Variant = null     # or a fixed world yaw


func _ready() -> void:
	_level = get_parent()
	GameState.use_calibration = false  # test the defaults, not this machine's calibration
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
		print("  t=%2ds  %s | GameState hr %.1f valid=%s resting=%.1f elevated=%s | yaw %.2f | body yaw %.2f" % [
			i + 1, SensorBridge.status_text(), GameState.hr_bpm, GameState.hr_valid,
			SensorBridge.resting_bpm, GameState.hr_elevated, GameState.orientation.y, _level.player.rotation.y])
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
	await _test_river()
	await _test_scan()
	await _test_live_flick_timing()
	await _test_nest()
	await _test_calm_dips()
	await _test_discoveries()
	await _test_haptics_and_layers()
	await _test_scan_speech_spacing()
	await _test_reveal_view()
	await _test_stealth_anti_lockout()
	await _test_stealth_already_in_zone()
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
	_check(await _until(func(): return EventDirector.current_event == Event.WIND, 120.0),
			"F4 assist brings HR down -> Event 1 completes")
	_check(not GameState.input_locked, "input unlocked after Event 1")


func _test_event_two() -> void:
	print("[E2 WIND]")
	_aim_yaw = 0.0
	BatCompanion.shut_up()  # E1's last line is real time, the run is at time_scale 3
	_check(_level.exit_wind.mode == ExitWind.Mode.OFF, "no wind before the bat mentions it")
	var said: Array = []
	var on_spoke := func(id: StringName): said.append(id)
	BatCompanion.spoke.connect(on_spoke)
	Input.action_press(&"up")
	var started := await _until(func(): return EventDirector.event_running and EventDirector.current_event == Event.WIND, 20.0)
	Input.action_release(&"up")
	_check(started, "walking into the wind chamber starts E2")
	_check(await _until(func(): return said.has(&"e2_follow_wind"), 5.0), "the bat says to follow the wind")
	BatCompanion.spoke.disconnect(on_spoke)
	_check(await _until(func(): return EventDirector.current_event == Event.RIVER, 40.0), "E2 ends with the line -> river armed")
	var wind: Node3D = _level.exit_wind
	_check(wind.mode == ExitWind.Mode.HEADING, "the wind is on from the bat's line")
	_check(wind._player.bus == AudioDirector.BUS_PRIORITY, "the wind is on the Priority bus")
	_check(await _until(func(): return wind._player.volume_db >= wind.heading_min_db - 0.5, 8.0),
			"the wind reaches its level (%.1f dB)" % wind._player.volume_db)
	var head: Vector3 = _level.player.global_position
	_check(wind.global_position.z < head.z - 4.0, "the wind sits ahead along the path")
	_check(wind.global_position.y > head.y + 2.0, "and above eye level")
	await get_tree().create_timer(2.0).timeout
	_check(wind.global_position.x < head.x - 1.5, "hugging the left wall of the passage (x %.1f vs head %.1f)" % [wind.global_position.x, head.x])


## A head movement through the mouse's path: rad/s, held for seconds of real time.
func _flick(rate_deg: float, seconds: float = 0.2) -> void:
	var t := 0.0
	while t < seconds:
		SensorBridge._on_pitch_rate_sample(deg_to_rad(rate_deg))
		await get_tree().create_timer(0.02, true, false, true).timeout
		t += 0.02
	SensorBridge._on_pitch_rate_sample(0.0)
	# Real seconds: flick timing doesn't scale with time_scale, and neither
	# does its cooldown.
	await get_tree().create_timer(0.7, true, false, true).timeout


func _test_river() -> void:
	print("[E3 RIVER]")
	var river: Node = _level.river
	var flicks: Array = []
	var on_flick := func(d: int, s: float): flicks.append([d, s])
	GameState.head_flicked.connect(on_flick)
	river.strong_seconds = 2.0
	river.weak_seconds = 3.0
	river.easing_seconds = 0.5
	river.rising_seconds = 0.5
	# Windows go by quickly at this speed; only the anti-lockout part wants assist.
	river.assist_after_missed = 99

	_aim_yaw = 0.0
	EventDirector.jump_to(Event.RIVER)
	_check(await _until(func(): return river.state == River.State.LISTENING, 60.0), "the bat explains, then the cycle starts")
	_check(not GameState.input_locked, "free to move while listening")

	await _hold(&"up", 1.5)
	_check(_level.player.global_position.z > -64.5, "the river bars the way (z %.1f)" % _level.player.global_position.z)

	await _until(func(): return river.current == River.Current.STRONG, 10.0)
	var db_strong: float = river._water.volume_db
	await _until(func(): return river.current == River.Current.WEAK, 10.0)
	var db_weak: float = river._water.volume_db
	_check(db_weak < db_strong - 10.0, "the water is quieter in the window (%.0f -> %.0f dB)" % [db_strong, db_weak])

	await _until(func(): return river.current == River.Current.STRONG, 10.0)
	await _flick(60.0, 0.5)
	_check(flicks.is_empty(), "a slow glance up is not a flick")
	await _flick(400.0, 0.04)
	_check(flicks.is_empty(), "a fast little twitch is not a flick")
	await _flick(-300.0)
	_check(flicks.size() == 1 and flicks[0][0] < 0, "a sharp look down reads as a down flick")
	_check(river.state == River.State.LISTENING, "a down flick doesn't jump")
	# The headband's own stream, as bridge.py sends it: a down flick so the
	# river doesn't jump, 300 deg/s for one capture.
	var count: int = flicks.size()
	SensorBridge._on_pitch_rate_sample(0.0)
	var live := LiveOSCSource.new()
	live.pitch_rate_sample.connect(SensorBridge._on_pitch_rate_sample)
	for i in 6:
		live._on_message(LiveOSCSource.PITCH_RATE_ADDRESS, -deg_to_rad(300.0), "")
		await get_tree().create_timer(0.04, true, false, true).timeout
	live.free()
	_check(flicks.size() == count + 1, "the bridge's pitch rate reaches flick detection")
	await get_tree().create_timer(0.7, true, false, true).timeout

	await _until(func(): return river.current == River.Current.STRONG and river._t_current < 1.0, 10.0)
	await _flick(300.0)
	_check(river.swept == 1, "jumping in the strong current gets swept (%s)" % river.last_flick)
	_check(GameState.input_locked, "locked while swept back")
	_check(await _until(func(): return river.state == River.State.LISTENING, 15.0), "the crossing carries on after a sweep")
	_check(not GameState.input_locked, "free again after the sweep")
	_check(_level.player.global_position.z > -64.5, "swept back to the near bank")
	_check(EventDirector.current_event == Event.RIVER, "the run is still on the river")

	var missed_before: int = river.missed
	await _until(func(): return river.current == River.Current.RISING, 15.0)
	# A miss is counted once the late grace after the window is over.
	_check(await _until(func(): return river.missed == missed_before + 1, 3.0), "letting a window go by just waits for the next")
	await _until(func(): return river.current == River.Current.WEAK, 10.0)
	_check(_level.exit_wind._player.volume_db < -20.0, "the wind is ducked out at the river (%.1f dB)" % _level.exit_wind._player.volume_db)
	await _flick(300.0)
	_check(await _until(func(): return EventDirector.current_event == Event.STEALTH, 5.0), "a flick in the quiet window crosses")
	_check(await _until(func(): return _level.exit_wind._player.volume_db > _level.exit_wind.heading_min_db - 1.0, 8.0), "the wind comes back once the river is crossed")
	_check(_level.player.global_position.z < -67.5, "landed on the far bank (z %.1f)" % _level.player.global_position.z)
	_check(not GameState.input_locked, "free after crossing")

	print("[E3 RIVER: anti-lockout]")
	river.assist_after_missed = 3
	EventDirector.jump_to(Event.RIVER)
	await _until(func(): return river.state == River.State.LISTENING, 60.0)
	for i in river.assist_after_swept:
		await _until(func(): return river.current == River.Current.STRONG, 10.0)
		EventDirector.level.force_fail(Event.RIVER)  # F11
		await _until(func(): return river.state == River.State.LISTENING, 15.0)
	_check(river.assisted, "after two sweeps the current stays weak")
	await get_tree().create_timer(4.0).timeout
	_check(river.window_open(), "the assisted current doesn't come back")
	await _flick(300.0)
	_check(await _until(func(): return EventDirector.current_event == Event.STEALTH, 5.0), "any flick crosses once assisted")
	GameState.head_flicked.disconnect(on_flick)
	_aim_yaw = null


func _test_scan() -> void:
	print("[scan]")
	_level.teleport_player(_level.get_node("Landmarks/Fork").global_position, 0.0)
	_aim_yaw = 0.0
	await _frames(5)
	var got: Array = []
	var on_scan := func(r: Array): got.append(r)
	BatCompanion.scan_performed.connect(on_scan)
	var lines: Array = []
	var on_spoke := func(id: StringName): lines.append(id)
	BatCompanion.spoke.connect(on_spoke)
	BatCompanion.reset_scan_session()
	BatCompanion.shut_up()
	BatCompanion._last_scan = -999.0
	BatCompanion.scan()
	_check(BatCompanion._ui_player.stream == SfxLibrary.get_stream("ui_startup"), "first scan plays the startup sound")
	BatCompanion.scan()  # inside the cooldown: must not scan again
	await _frames(3)
	BatCompanion.scan_performed.disconnect(on_scan)
	_check(got.size() == 1, "second press inside the cooldown does not scan (scans: %d)" % got.size())
	await _until(func(): return BatCompanion._last_scan_line != &"", 5.0)
	BatCompanion.spoke.disconnect(on_spoke)
	_check(BatCompanion._ping_pool[0].stream == SfxLibrary.get_stream("ui_scan_detected"), "returns use the detected sound")
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		print("  (no TTS here: the line itself was skipped, _last_scan_line %s)" % BatCompanion._last_scan_line)
	_check(BatCompanion._last_scan_line == BatCompanion.SCAN_LINE_FOUND, "the bat speaks after a scan (%s)" % BatCompanion._last_scan_line)
	_check(BatCompanion._line_text.has(BatCompanion._last_scan_line), "and that line is in lines.txt")
	BatCompanion._last_scan = -999.0
	BatCompanion.scan()
	_check(BatCompanion._ui_player.stream != SfxLibrary.get_stream("ui_startup"), "later scans do not")
	await _frames(3)
	BatCompanion._last_scan = -999.0
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


## Frog and bats: the scan flags them, FOCUS names them, and only a focus the
## player built goes in the notes. Then the fork landmark and the end screen.
func _test_discoveries() -> void:
	print("[discoveries: frog]")
	GameState.clear_observations()
	BatCompanion.shut_up()
	var frog_root: Node3D = _level.get_node("Frogs/FrogCorridor")
	var frog_focus: Focusable = frog_root.get_node("Focusable")
	var frog_src: Node3D = frog_root.get_node("Source")
	var frog_player: AudioStreamPlayer3D = frog_src.get_node("Body/AudioStreamPlayer3D")
	_check(frog_player.bus == AudioDirector.BUS_ESSENTIAL and frog_player.max_db >= 12.0, "an unidentified frog is clearly audible (essential layer, uncapped)")
	_check(frog_root.get_node("Focusable").min_volume_db >= -4.0, "and loud enough before any FOCUS to be found by ear")
	_check(frog_player.stream != null and frog_player.stream.get_length() > 1.0, "the frog has a sound (placeholder until frog_croak is added)")
	_aim_target = null
	_aim_yaw = PI  # facing away, so FOCUS can't build during the scan
	_level.teleport_player(frog_root.global_position + Vector3(0, 0, -6), PI)
	await _frames(5)
	BatCompanion._known_line_times.clear()
	BatCompanion.reset_scan_session()  # a fresh run's prompt budget
	BatCompanion._last_scan = -999.0
	var seen: Array = []
	var on_scan := func(r: Array): seen.append_array(r)
	BatCompanion.scan_performed.connect(on_scan)
	BatCompanion.scan()
	await _frames(3)
	BatCompanion.scan_performed.disconnect(on_scan)
	_check(seen.any(func(e): return frog_src.get_node("Describable") in e.nodes), "the scan pings the frog")
	await _until(func(): return BatCompanion._known_line_times.has(BatCompanion.focus_prompt_line), 6.0)
	_check(BatCompanion._known_line_times.has(BatCompanion.focus_prompt_line), "the bat flags it and says to face it")
	_aim_yaw = null
	_aim_target = frog_focus.global_position
	_check(await _until(func(): return frog_focus.revealed_state, 30.0), "facing it, FOCUS names the frog")
	_check(frog_focus.earned, "the player built that focus themselves")
	_check(GameState.observations.any(func(n): return n.id == &"frog"), "the frog goes in the notes")
	var fed_back := [false]
	GameState.notes_feedback_played.connect(func(): fed_back[0] = true, CONNECT_ONE_SHOT)
	await _frames(5)
	_check(not fed_back[0], "the notes sound waits: it doesn't land on top of the discovery sting")
	_check(await _until(func(): return fed_back[0], 40.0), "then plays once the reveal is over")
	_check(frog_player.bus == AudioDirector.BUS_ESSENTIAL, "once named it moves up to the essential layer")
	var top := 0.0
	var body: Node3D = frog_src.get_node("Body")
	var t := 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		top = maxf(top, body.position.y)
	_check(top > 1.2, "then it jumps up and down (highest %.2f m)" % top)
	_check(_level.get_node("Frogs/FrogLanding/Focusable").reveal_line == _level.frog_again_line,
			"every later frog is just 'another frog'")
	_level.frogs_found = 1
	var second: Focusable = _level.get_node("Frogs/FrogRiver/Focusable")
	second.earned = true
	_level._on_frog_revealed(second)
	var frog_note: Array = GameState.observations.filter(func(n): return n.id == &"frog")
	_check(frog_note.size() == 1 and frog_note[0].text.begins_with("2 frogs") and frog_note[0].line == &"end_note_frogs_2",
			"a second frog makes the note a count (%s)" % [frog_note])
	second.earned = false
	_check(frog_src.has_node("Landing"), "landing on a splash every jump")
	_check(frog_player.playing, "and keeps croaking, close up")
	_aim_target = null

	print("[discoveries: bats, fail-forward is not a note]")
	BatCompanion.shut_up()
	var roost: Node3D = _level.get_node("BatRoost")
	var bat_focus: Focusable = roost.get_node("Focusable")
	var bat_src: Node3D = roost.get_node("Source")
	_check(bat_src.get_node("Body/AudioStreamPlayer3D").stream != null, "the bats have a sound (placeholder until bat_screech is added)")
	_check(is_equal_approx(absf(bat_src.get_node("Body").rotation_degrees.z), 180.0), "the bats stand upright, not hanging")
	var fail_forward := bat_focus.fail_forward_seconds
	bat_focus.fail_forward_seconds = 1.0
	_aim_yaw = 0.0
	_level.teleport_player(roost.global_position + Vector3(-6, 0, 0), 0.0)
	_aim_yaw = deg_to_rad(-90)  # looking away from the bats
	await _frames(10)
	_check(bat_focus.focus_progress == 0.0 and not bat_focus._in_range, "FOCUS waits until a scan has found them")
	BatCompanion._last_scan = -999.0
	BatCompanion.scan()
	await _frames(3)
	_check(await _until(func(): return bat_focus.revealed_state, 10.0), "the fail-forward names them anyway")
	_check(not bat_focus.earned and not GameState.observations.any(func(n): return n.id == &"bats_upright"),
			"but a discovery the player didn't make is not a note")
	bat_focus.reset()
	bat_focus.fail_forward_seconds = fail_forward
	_aim_yaw = null
	_aim_target = bat_focus.global_position
	_check(await _until(func(): return bat_focus.revealed_state, 30.0), "facing them, FOCUS names the bats")
	_check(GameState.observations.any(func(n): return n.id == &"bats_upright"), "and the upright bats go in the notes")
	_aim_target = null
	BatCompanion.shut_up()

	print("[end screen]")
	_level._show_end_screen()
	_check(await _until(func(): return _level.has_node("EndScreen"), 40.0), "the end screen comes up")
	var screen: CanvasLayer = _level.get_node_or_null("EndScreen")
	var shown: String = " | ".join(screen.lines_shown) if screen != null else ""
	_check(shown.contains("frog") and shown.contains(_level.bat_note_text), "with both notes on it (%s)" % shown)
	for line in [&"end_notes_intro", &"end_note_frog", &"end_note_bats", &"end_notes_none"]:
		_check(BatCompanion._line_text.has(line), "%s is in lines.txt" % line)
	if screen != null:
		screen.queue_free()
	BatCompanion.shut_up()


func _test_haptics_and_layers() -> void:
	print("[haptics]")
	var haptics: Node = _level.player.haptics
	_check(not _level.player.get_node("OSCReceiverElevated").get_script().source_code.contains("start_joy_vibration"),
			"the fixed 0.6 s buzz is gone")
	var smoothing: float = haptics.heartbeat_smoothing_seconds
	haptics.heartbeat_smoothing_seconds = 0.5
	GameState.hr_bpm = 60.0
	await get_tree().create_timer(3.0).timeout
	var slow: float = haptics.beat_interval()
	GameState.hr_bpm = 120.0
	await get_tree().create_timer(3.0).timeout
	var fast: float = haptics.beat_interval()
	_check(absf(slow - 1.0) < 0.1 and absf(fast - 0.5) < 0.06, "pulse tempo follows heart rate (60 bpm: %.2fs, 120 bpm: %.2fs)" % [slow, fast])
	GameState.hr_bpm = 150.0
	await get_tree().create_timer(3.0).timeout
	_check(absf(haptics.beat_interval() - 0.4) < 0.05, "a spike to 150 bpm pulses every %.2fs" % haptics.beat_interval())
	var felt := false
	for i in 90:
		await get_tree().physics_frame
		felt = felt or haptics.left_level > 0.0 or haptics.right_level > 0.0
	_check(not felt, "walking around (no CALM running), the controller stays still")
	EventDirector.start_calm_event(false)
	var pulsed := false
	for i in 90:
		await get_tree().physics_frame
		pulsed = pulsed or haptics.left_level > 0.0
	EventDirector.stop_calm_event(&"test")
	_check(pulsed, "during a calm-down it pulses with the heartbeat")
	haptics.heartbeat_smoothing_seconds = smoothing
	haptics.heartbeat_enabled = false
	await _frames(10)
	var head: Vector3 = _level.player.pivot.global_position
	var yaw := GameState.effective_orientation().y
	var left_of := head + Basis.from_euler(Vector3(0, yaw, 0)) * Vector3(-1, 0, -0.2)
	var right_of := head + Basis.from_euler(Vector3(0, yaw, 0)) * Vector3(1, 0, -0.2)
	var ahead := head + Basis.from_euler(Vector3(0, yaw, 0)) * Vector3(0, 0, -1)
	_check(haptics.side_of(left_of, head, yaw) == -1 and haptics.side_of(right_of, head, yaw) == 1
			and haptics.side_of(ahead, head, yaw) == 2, "a wall on the left, right or ahead picks that grip")
	haptics.set_wall(-1)
	var steady := true
	for i in 30:
		await get_tree().physics_frame
		steady = steady and haptics.left_level == haptics.wall_strength and haptics.right_level == 0.0
	_check(steady, "contact on the left is a steady rumble in the left grip only")
	_level.player._wall_contact = true
	_level.player._end_wall_contact()
	await _frames(3)
	_check(haptics.left_level == 0.0 and haptics.right_level == 0.0, "stepping away stops it")
	haptics.heartbeat_enabled = true

	print("[view modes]")
	var view: CanvasLayer = _level.get_node("FilmingOverlay")
	view.set_mode(view.ViewMode.BLACK)
	_check(view._rect.visible and view._rect.color == Color.BLACK, "View 1 is plain black")
	view.set_mode(view.ViewMode.COLOR)
	var river_bank: Vector3 = _level.get_node("River/NearBank").global_position
	_level.player.global_position = river_bank + Vector3(0, 0.1, 0)
	await _frames(3)
	_check(view.target_color().is_equal_approx(view.river_color), "View 2 is blue at the river")
	_level.player.global_position = _level.get_node("Checkpoints/E1_Landing").global_position
	await _frames(3)
	_check(view.target_color().is_equal_approx(view.start_color), "and dark at the landing")
	_level.player.global_position = _level.get_node("Checkpoints/E4_ShaftBottom").global_position
	await _frames(3)
	var near_exit: Color = view.target_color()
	_check(near_exit.v > view.river_color.v and near_exit.v < 1.0, "lighter toward the exit (%s)" % near_exit)
	var before: Color = view._rect.color
	await _frames(2)
	_check(not view._rect.color.is_equal_approx(near_exit), "and it fades there rather than snapping")
	view.set_mode(view.ViewMode.NORMAL)
	_check(not view._rect.visible, "and F2's third state is the normal view")

	print("[audio polish]")
	var wind: Node3D = _level.exit_wind
	_check(wind.heading_max_db <= 10.0, "the wind is well under its old level (max %.0f dB)" % wind.heading_max_db)
	BatCompanion.reset_scan_session()
	BatCompanion._focus_prompts_said = BatCompanion.focus_prompt_max_per_run
	_check(not (BatCompanion._focus_prompts_said < BatCompanion.focus_prompt_max_per_run), "the face-it-and-hold prompt stops after %d times" % BatCompanion.focus_prompt_max_per_run)
	BatCompanion.reset_scan_session()
	_level.player.velocity = Vector3.ZERO
	await _frames(30)
	_check(_level.player.footsteps.volume_db < -50.0, "footsteps fade out when standing still, not a hard pause")

	print("[layers]")
	var env_bus := AudioServer.get_bus_index(AudioDirector.BUS_ENVIRONMENTAL)
	var has_low_pass := false
	for i in AudioServer.get_bus_effect_count(env_bus):
		has_low_pass = has_low_pass or AudioServer.get_bus_effect(env_bus, i) is AudioEffectLowPassFilter
	_check(has_low_pass, "the ambience layer is low-passed under the cues")
	_check(BatCompanion._ping_pool.is_empty() or BatCompanion._ping_pool[0].bus == AudioDirector.BUS_ESSENTIAL, "scan returns are on the essential layer")
	_check(_level.player.wall_audio.bus == AudioDirector.BUS_ESSENTIAL, "the near-a-wall drone is on the essential layer")
	_check(_level.player.footstep_volume_db >= 0.0, "footsteps walk at the raised level (%.0f dB) and fade at rest" % _level.player.footstep_volume_db)
	var env_count := 0
	for node in _level.get_node("CaveNoise").get_children():
		if node.has_node("Body/AudioStreamPlayer3D") and node.get_node("Body/AudioStreamPlayer3D").bus == AudioDirector.BUS_ENVIRONMENTAL:
			env_count += 1
	_check(env_count >= 6, "the ambience layer is well stocked (%d sources, plus the bed)" % env_count)


## Swings the head side to side through the mouse path: this many turns,
## alternating, each 0.5 rad over 0.2 s of real time.
func _shake_head(swings: int) -> void:
	var saved_target: Variant = _aim_target
	var saved_yaw: Variant = _aim_yaw
	_aim_target = null
	_aim_yaw = null
	var source = SensorBridge._fallback
	var dir := 1.0
	for i in swings:
		for step in 10:
			source._yaw += dir * 0.05
			await get_tree().create_timer(0.02, true, false, true).timeout
		dir = -dir
	await get_tree().create_timer(0.1, true, false, true).timeout
	_aim_target = saved_target
	_aim_yaw = saved_yaw


## Live samples come 25 a second, bunched two to a packet. The same flick has
## to register from them as from the mouse, and the river's safe window must
## cover the end of the fade and the start of the rise.
func _test_live_flick_timing() -> void:
	print("[live flick timing and the river window]")
	var flicks: Array = []
	var on_flick := func(d: int, s: float): flicks.append(d)
	GameState.head_flicked.connect(on_flick)
	var live: Node = SensorBridge._live
	await get_tree().create_timer(0.8, true, false, true).timeout
	var i := 0
	while i < 12:
		for k in 2:
			live.last_orientation_t = Time.get_ticks_msec() / 1000.0
			var t := (i + k) / 25.0
			SensorBridge._on_pitch_rate_sample(deg_to_rad(maxf(230.0 * sin(PI * t / 0.25) if t < 0.25 else 0.0, 0.001)))
		i += 2
		await get_tree().create_timer(0.08, true, false, true).timeout
	_check(flicks == [1], "a 40-degree flick in bunched 25 Hz live samples registers (%s)" % [flicks])
	await get_tree().create_timer(1.2, true, false, true).timeout
	flicks.clear()
	for n in 12:
		live.last_orientation_t = Time.get_ticks_msec() / 1000.0
		SensorBridge._on_pitch_rate_sample(deg_to_rad(40.0))
		await get_tree().create_timer(0.04, true, false, true).timeout
	_check(flicks.is_empty(), "a slow look up does not")
	live.last_orientation_t = -1.0
	GameState.head_flicked.disconnect(on_flick)

	var river: Node = _level.river
	var easing: float = river.easing_seconds
	river.easing_seconds = 2.0
	river.current = River.Current.EASING
	river._t_current = river.easing_seconds - river.window_early_seconds * 0.5
	_check(river.window_open(), "the last part of the fade already counts as quiet")
	river._t_current = 0.1
	_check(not river.window_open(), "the start of the fade does not")
	river.current = River.Current.RISING
	river._t_current = river.window_late_seconds * 0.5
	_check(river.window_open(), "a flick just after the quiet ends still counts")
	river.current = River.Current.STRONG
	river.easing_seconds = easing


## The nest, start to finish: the scan finds the flies with something blocked
## behind them; FOCUS on the buzzing sets them on the player; a shake clears
## them and reveals the den, with one line.
func _test_nest() -> void:
	print("[the nest: flies, then the den]")
	var den: Node3D = _level.get_node("Den")
	var den_desc: Describable = _level._den_scan
	var flies_desc: Describable = _level.get_node("Swarm/Flies/Describable")
	var focus: Focusable = _level.get_node("Swarm/Focusable")
	_check(not den.has_node("Focusable"), "the den itself has nothing to focus on")
	_check(den_desc.blocked and not den_desc.scannable(), "the den starts hidden behind the flies")
	_check(not _level.get_node("Landmarks").has_node("ForkLandmark") and not _level.get_node("CaveNoise").has_node("DistantDripRiver"),
			"no water drips anywhere")
	BatCompanion.shut_up()
	BatCompanion.reset_scan_session()
	var said: Array = []
	var on_spoke := func(id: StringName): said.append(id)
	BatCompanion.spoke.connect(on_spoke)
	_aim_target = null
	_aim_yaw = deg_to_rad(-90)  # looking back the way we came, so FOCUS can't build yet
	_level.teleport_player(_level.get_node("Triggers/Swarm").global_position, deg_to_rad(-90))
	await _frames(5)
	var seen: Array = []
	var on_scan := func(r: Array): seen.append_array(r)
	BatCompanion.scan_performed.connect(on_scan)
	BatCompanion._last_scan = -999.0
	BatCompanion.scan()
	await _frames(3)
	BatCompanion.scan_performed.disconnect(on_scan)
	_check(seen.any(func(e): return flies_desc in e.nodes), "the scan picks up the flies")
	_check(not seen.any(func(e): return den_desc in e.nodes), "but not the den, which is blocked")
	_check(_level._two_things_said and BatCompanion._line_text.has(&"den_two_things"),
			"the bat says two things, one blocked (den_two_things)")
	_check(not _level.shaking and not _level.den_found, "nothing else happens from the scan alone")

	_aim_yaw = null
	_aim_target = focus.global_position
	_check(await _until(func(): return focus.revealed_state, 30.0), "FOCUS on the buzzing names the flies")
	_check(_level.shaking, "and they swarm the player straight away")
	_check(focus.reveal_line == &"", "no 'they're harmless' line")
	_aim_target = null
	await _shake_head(1)
	_check(not _level.swarm_cleared, "one swing is not enough")
	await _shake_head(_level.shake_swings_required)
	_check(_level.swarm_cleared and _level.den_found and den_desc.identified, "shaking them off reveals the den")
	_check(not den_desc.blocked, "and the den can be scanned now")
	_check(await _until(func(): return said.has(&"den_reveal"), 10.0), "the bat says what it is")
	_check(_level.den_reward_line == &"" and not said.has(&"den_reward"), "in one line, not two")
	BatCompanion.spoke.disconnect(on_spoke)
	BatCompanion.shut_up()

	print("[the nest: re-scan reads as known]")
	_level.teleport_player(den.global_position + Vector3(7, 0, 0), deg_to_rad(90))
	await _frames(5)
	var again: Array = []
	var on_again := func(r: Array): again.append_array(r)
	BatCompanion.scan_performed.connect(on_again)
	BatCompanion._known_line_times.clear()
	BatCompanion._last_scan = -999.0
	BatCompanion.scan()
	await _frames(3)
	BatCompanion.scan_performed.disconnect(on_again)
	var den_entry: Array = again.filter(func(e): return den_desc in e.nodes)
	_check(den_entry.size() == 1 and den_entry[0].known, "the den comes back marked known")
	BatCompanion.shut_up()


## CALM passes on a rate that wobbles around the line, not only 3 unbroken seconds.
func _test_calm_dips() -> void:
	print("[CALM: dips below the line add up]")
	EventDirector.start_calm_event(true, &"", 999.0, 999.0)
	EventDirector._calm_t = EventDirector.calm_reference_seconds + 1.0
	EventDirector._calm_start_bpm = 100.0
	EventDirector._calm_ref_sum = 100.0  # a reference reading, as the first seconds give
	EventDirector._calm_ref_count = 1
	var below := 100.0 - EventDirector._calm_required_drop() - 3.0
	var above := 100.0
	var passed := false
	var t := 0.0
	while t < 12.0 and EventDirector.calm_active:
		# 1 s under the line, 0.5 s back over it, over and over.
		var phase := fmod(t, 1.5)
		EventDirector._calm_smoothed_bpm = below if phase < 1.0 else above
		EventDirector._debug_hr = EventDirector._calm_smoothed_bpm
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	passed = not EventDirector.calm_active
	_check(passed, "a heart rate wobbling around the line passes (in %.1f s)" % t)
	if EventDirector.calm_active:
		EventDirector.stop_calm_event(&"test")
	EventDirector._debug_hr = -1.0
	_check(EventDirector.calm_fail_forward_seconds <= 45.0, "and the fail-forward is %.0f s, not 75" % EventDirector.calm_fail_forward_seconds)


## Returns and speech must never sound together, whichever comes first.
func _test_scan_speech_spacing() -> void:
	print("[scan and speech never overlap]")
	_level.teleport_player(_level.get_node("Landmarks/Fork").global_position, 0.0)
	await _frames(5)
	BatCompanion.shut_up()

	var pings: Array = []
	var on_ping := func(_e: Dictionary): pings.append(BatCompanion._speaking_line)
	BatCompanion.return_pinged.connect(on_ping)
	var spoke_during: Array = []
	var on_spoke := func(_id: StringName): spoke_during.append(BatCompanion._scan_sounding)
	BatCompanion.spoke.connect(on_spoke)

	# Scan first, then a line asked for mid-scan: the line waits.
	BatCompanion._last_scan = -999.0
	BatCompanion.scan()
	BatCompanion.say(&"e4_hit")
	_check(BatCompanion.is_speaking() and BatCompanion._voice_queue.is_empty(), "a line during returns is held back")
	_check(await _until(func(): return not spoke_during.is_empty(), 8.0), "and spoken once they clear")
	_check(not spoke_during.has(true), "not while the scan was sounding")
	await _until(func(): return not BatCompanion.is_speaking(), 40.0)

	# Bat first, then a press: the returns wait. The hold cap is game time, so
	# at time_scale 3 the default would run out before a real-time clip ends.
	var cap: float = BatCompanion.scan_hold_max_seconds
	BatCompanion.scan_hold_max_seconds = 60.0
	pings.clear()
	BatCompanion.say(&"e4_hit")
	BatCompanion._last_scan = -999.0
	BatCompanion.scan()
	_check(await _until(func(): return not pings.is_empty(), 40.0), "returns from a press during speech still arrive")
	_check(not pings.has(true), "after the bat has finished")
	BatCompanion.scan_hold_max_seconds = cap

	BatCompanion.return_pinged.disconnect(on_ping)
	BatCompanion.spoke.disconnect(on_spoke)
	BatCompanion.shut_up()


func _test_reveal_view() -> void:
	print("[reveal view]")
	var reveal: Camera3D = _level.get_node("TopDownCamera")
	var first_person := get_viewport().get_camera_3d()
	reveal.set_showing(true)
	await _frames(2)
	_check(get_viewport().get_camera_3d() == reveal, "switches to the overhead camera")
	_check(not _level.get_node("EventDebugOverlay").visible, "operator text is hidden")
	_check(reveal.cull_mask & DebugDraw.LAYER == 0, "playtest labels are out of frame")
	var inside := true
	for path in ["Den", "Landmarks/Exit", "Checkpoints/E1_Landing", "Checkpoints/E4_ShaftBottom"]:
		var at: Vector2 = reveal.unproject_position(_level.get_node(path).global_position)
		inside = inside and get_viewport().get_visible_rect().has_point(at)
	_check(inside, "the whole cave is in frame")
	reveal.set_showing(false)
	await _frames(2)
	_check(get_viewport().get_camera_3d() == first_person and _level.get_node("EventDebugOverlay").visible,
			"switching back restores the view")


func _test_stealth_anti_lockout() -> void:
	print("[E4 STEALTH: spotted -> headbutt -> flee]")
	var stealth: Node = _level.stealth
	stealth.den_approach_seconds = 4.0
	stealth.approach_seconds = 4.0
	stealth.pass_seconds = 2.0
	EventDirector.jump_to(Event.STEALTH)
	_check(await _until(func(): return stealth.state == Stealth.State.APPROACH, 3.0), "jump to stealth starts the encounter")
	_check(GameState.input_locked and EventDirector.calm_active, "player frozen, CALM running")
	var said: Array = []
	var on_spoke := func(id: StringName): said.append(id)
	BatCompanion.spoke.connect(on_spoke)
	var before: float = _level.project(_level.player.global_position).s
	EventDirector.level.force_fail(Event.STEALTH)  # F11
	_check(stealth.state == Stealth.State.SPOTTED, "F11 -> spotted, not a restart")
	# Placeholder lines have no clip, and headless has no TTS, so check the wiring.
	_check(stealth.spotted_line == &"e3_spotted" and BatCompanion._line_text.has(&"e3_spotted"),
			"the bat's alarm line is wired and in lines.txt")
	_check(GameState.input_locked, "still held while it is on top of the player")
	await _flick(-300.0)
	_check(stealth.state == Stealth.State.FLEEING or stealth.state == Stealth.State.DONE, "a forward head flick headbutts it (%s)" % stealth.last_headbutt)
	_check(await _until(func(): return EventDirector.current_event == Event.ESCAPE, 20.0), "and the player gets away: stealth complete")
	_check(not GameState.input_locked, "free after fleeing")
	var after: float = _level.project(_level.player.global_position).s
	_check(after > before + stealth.flee_distance * 0.5, "fled on along the route (%.1f m)" % (after - before))
	BatCompanion.spoke.disconnect(on_spoke)

	print("[E4 STEALTH: spotted, no headbutt (anti-lockout)]")
	stealth.headbutt_reminder_seconds = 2.0
	stealth.headbutt_fail_forward_seconds = 8.0
	EventDirector.jump_to(Event.STEALTH)
	await _until(func(): return stealth.state == Stealth.State.APPROACH, 3.0)
	EventDirector.level.force_fail(Event.STEALTH)
	await _flick(-40.0, 0.3)  # a slow nod is not a headbutt
	_check(stealth.state == Stealth.State.SPOTTED, "a gentle nod does not count")
	_check(await _until(func(): return EventDirector.current_event == Event.ESCAPE, 20.0),
			"with no headbutt the animal breaks off by itself: %s" % stealth.last_headbutt)
	stealth.headbutt_reminder_seconds = 6.0
	stealth.headbutt_fail_forward_seconds = 15.0


## Standing in the zone when the event arms has to lock the same as walking in.
func _test_stealth_already_in_zone() -> void:
	print("[E4 STEALTH: already in the zone]")
	var stealth: Node = _level.stealth
	EventDirector.jump_to(Event.STEALTH)
	await _until(func(): return stealth.state == Stealth.State.APPROACH, 3.0)
	stealth.reset_encounter()
	GameState.input_locked = false
	_level.teleport_player(_level.get_node("Triggers/E3_Stealth").global_position, 0.0)
	_check(await _until(func(): return stealth.state == Stealth.State.APPROACH, 2.0), "standing in the zone starts it")
	_check(GameState.input_locked, "and locks the player")


func _test_stealth_assisted_pass() -> void:
	print("[E4 STEALTH: calm heart rate passes first time]")
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
	print("[E5 ESCAPE: the grip climb]")
	var climb: Node = _level.climb
	climb.safe_holds = 1
	climb.swarm_safe_holds = 99  # no random flies in this part
	climb.crumble_after = Vector2(60, 60)  # no random crumbles either
	EventDirector.jump_to(Event.ESCAPE)
	await _frames(3)
	_check(climb.active and climb.state == Climb.State.CLIMBING, "jump to the climb starts it")
	_check(GameState.input_locked, "walking is off: the triggers are the hands")
	var reverb_on := false
	for i in AudioServer.get_bus_effect_count(0):
		reverb_on = reverb_on or AudioServer.get_bus_effect(0, i) is AudioEffectReverb
	_check(reverb_on, "the shaft has cave reverb")

	climb.press(Climb.LEFT)
	climb.press(Climb.RIGHT)
	_check(climb.progress == 2 and climb.held[Climb.LEFT] and climb.held[Climb.RIGHT], "each trigger press grabs the next hold up")
	_check(Haptics.trigger_strength[Climb.LEFT] > 0.0, "and the trigger stiffens while that hand holds")
	climb.release(Climb.LEFT)
	climb.press(Climb.LEFT)
	_check(climb.progress == 3, "let go and grab again to climb")

	print("[E5: crumble, catch, fall]")
	climb.force_hit()
	_check(climb.state == Climb.State.RECOVERING and climb.crumbles == 1, "a hold crumbles")
	_check(climb.holds.any(func(h): return h.crumbled), "it shows red on the wall")
	var crumbled_side: int = Climb.LEFT if not climb.held[Climb.LEFT] else Climb.RIGHT
	_check(Haptics.trigger_strength[crumbled_side] == 0.0, "that trigger goes slack")
	climb.release(crumbled_side)
	climb.press(crumbled_side)
	_check(climb.state == Climb.State.CLIMBING and climb.falls == 0, "catching a new hold in time saves it")
	climb.recovery_window = 0.5
	climb.force_hit()
	await get_tree().create_timer(1.0).timeout
	_check(climb.falls == 1 and climb.progress == 0, "too slow: the player falls to the bottom")
	_check(await _until(func(): return climb.state == Climb.State.CLIMBING, 10.0), "and climbs again")
	climb.recovery_window = 1.6

	print("[E5: flies]")
	climb.press(Climb.LEFT)
	climb.start_swarm(Climb.LEFT)
	_check(climb.swarm_side == Climb.LEFT, "flies on the left")
	var swarm_audio: AudioStreamPlayer3D = climb._swarm_player
	var ear: Vector3 = swarm_audio.global_position - GameState.head_position
	_check(ear.x < -1.0 and swarm_audio.playing, "heard on the left")
	climb.release(Climb.RIGHT)
	climb.press(Climb.RIGHT)
	_check(climb.swarm_side == 0 and climb.swarms_avoided == 1, "grabbing right, away from them, gets past")
	climb.start_swarm(Climb.RIGHT)
	climb.release(Climb.RIGHT)
	climb.press(Climb.RIGHT)
	_check(climb.state == Climb.State.SWARMED, "grabbing toward the flies gets the player swarmed")
	var progress_before: int = climb.progress
	climb.press(Climb.LEFT)
	_check(climb.progress == progress_before, "no climbing while swarmed")
	await _shake_head(climb.clear_swings + 1)
	_check(climb.state != Climb.State.SWARMED and climb.swarm_side == 0, "shaking the head clears them")

	print("[E5: choices steer the flies]")
	var left_count := 0
	climb.lateral = -0.9
	for i in 200:
		climb.swarm_side = 0
		climb._moves_since_swarm = 99
		climb.swarm_chance = 1.0
		climb.swarm_safe_holds = 0
		climb.progress = 5
		climb._maybe_swarm()
		left_count += 1 if climb.swarm_side == Climb.LEFT else 0
	climb._clear_swarm()
	climb.swarm_chance = 0.35
	_check(left_count > 120, "climbing left leads into flies waiting on the left (%d / 200)" % left_count)

	print("[E5: the wall view]")
	climb.toggle_wall_view()
	_check(climb.wall_view.showing and climb.wall_view.visible, "V during the climb shows the wall view")
	_check(not _level.get_node("TopDownCamera").showing, "not the overhead map")
	climb.toggle_wall_view()
	_check(not climb.wall_view.showing, "and V again hides it")

	print("[E5: the top]")
	climb.swarm_safe_holds = 99
	climb.lateral = 0.0
	var side := Climb.LEFT
	while climb.active and climb.progress < climb.holds_to_top:
		climb.release(side)
		climb.press(side)
		side = -side
	_check(_level.run_finished and EventDirector.current_event == Event.DONE, "reaching the top completes the run")
	_check(_level.exit_wind.mode == ExitWind.Mode.FULL, "the outside wind comes in full")
	_check(await _until(func():
		for i in AudioServer.get_bus_effect_count(0):
			if AudioServer.get_bus_effect(0, i) is AudioEffectReverb:
				return false
		return true, 10.0), "and the cave reverb opens out to nothing")
	_check(Haptics.trigger_strength[Climb.LEFT] == 0.0 and Haptics.trigger_strength[Climb.RIGHT] == 0.0, "triggers released")
	for line in [&"climb_intro", &"climb_crumble", &"climb_flies", &"climb_swarmed", &"climb_fell"]:
		_check(BatCompanion._line_text.has(line), "%s is in lines.txt" % line)

