extends Node3D

## The escape blockout (escape_level.tscn): landing -> corridor -> fork (left to
## the den, with the swarm of flies right in front of it; right to the river)
## -> river -> stealth chamber -> the climb -> the exit.
##
## Runs Events 2-5 for EventDirector (which runs Event 1 itself) and owns
## everything that needs this level's layout:
##   - the ROUTE: a polyline of Marker3Ds down the main path. Knockbacks slide
##     the player back along it, and "distance to the objective" for the
##     overload detector is distance left along it. The exit wind has its own
##     copy of the path (exit_wind.gd) so it can be placed separately.
##   - CHECKPOINTS: where each event starts, and where a knockback lands.
##   - TRIGGERS: Area3Ds that start each event when the player walks in.
##   - E2 (the bat's line), the den and the swarm, directly in this file;
##     the rest are their own nodes (river_crossing.gd, stealth_encounter.gd,
##     rockfall_climb.gd).
##   - the debug markers: every trigger zone, checkpoint and landmark gets a
##     visible shape and a floating label, so autopilot shows what is going
##     on. All of it sits under the filming black-out like everything else.

const Event := preload("res://autoload/event_director.gd").Event
const ExitWind := preload("res://scripts/events/exit_wind.gd")

@export var player_path: NodePath = ^"player"
@export var route_path: NodePath = ^"Route"
@export var exit_wind_path: NodePath = ^"ExitWind"
@export var river_path: NodePath = ^"River"
@export var stealth_path: NodePath = ^"Stealth"
@export var climb_path: NodePath = ^"Climb"
@export var den_scan_path: NodePath = ^"Den/Describable"
@export var swarm_focus_path: NodePath = ^"Swarm/Focusable"
@export var swarm_trigger_path: NodePath = ^"Triggers/Swarm"

## Checkpoints, one per event, each a Marker3D whose -Z is "ahead" there.
@export var checkpoint_paths: Array[NodePath] = [
	^"Checkpoints/E1_Landing", ^"Checkpoints/E2_Corridor", ^"Checkpoints/E3_RiverBank",
	^"Checkpoints/E3_BeforeStealth", ^"Checkpoints/E4_ShaftBottom",
]
@export var e2_trigger_path: NodePath = ^"Triggers/E2_Corridor"
@export var exit_trigger_path: NodePath = ^"Triggers/Exit"

## Bat lines for E2, the den (found by a scan) and the way into the swarm.
@export var e2_line: StringName = &"e2_follow_wind"
@export var den_reveal_line: StringName = &"den_reveal"
## Empty: no prompt on walking up to the flies. The scan's own (limited)
## "face it and hold" covers it, and finding it is the player's job.
@export var swarm_prompt_line: StringName = &""
## Empty: the den's reward is heard at the stealth encounter instead
## (e3_warning_den), so finding the den is one line, not two.
@export var den_reward_line: StringName = &""
## A scan that reaches the flies before they're cleared: two things ahead, one
## blocked; get closer and focus that way.
@export var den_two_things_line: StringName = &"den_two_things"
@export var exit_line: StringName = &"e4_exit"

## Seconds after a scan finds the den before the bat speaks, so the chirps land first.
@export var den_line_delay: float = 1.2

# ------------------------------------------------------------------------
# SWARM SHAKE CONFIG
# ------------------------------------------------------------------------
# While the flies are still at the den, a scan that reaches it can't make it
# out: the bat says the flies are all over them and to shake them off. Enough
# swings of the head clear the flies, and only then does the den resolve.
# ------------------------------------------------------------------------
# DISCOVERIES CONFIG (frog, bats): scan flags it, FOCUS names it, it goes in
# the player's notes -- but only if they built the FOCUS themselves.
# ------------------------------------------------------------------------
@export_group("Discoveries")
@export var frog_focus_paths: Array[NodePath] = [
	^"Frogs/FrogLanding/Focusable", ^"Frogs/FrogCorridor/Focusable",
	^"Frogs/FrogRiver/Focusable", ^"Frogs/FrogStealth/Focusable",
]
@export var bat_focus_path: NodePath = ^"BatRoost/Focusable"
@export var frog_note_text: String = "A frog, deep in the cave, jumping."
@export var frog_note_line: StringName = &"end_note_frog"
## More than one frog: the note becomes a count, read back with the line for it.
@export var frogs_note_text: String = "%d frogs, deep in the cave, jumping."
## Index = frogs found; [1] is frog_note_line.
@export var frog_count_lines: Array[StringName] = [&"", &"end_note_frog", &"end_note_frogs_2", &"end_note_frogs_3", &"end_note_frogs_4"]
## What the bat says for every frog after the first.
@export var frog_again_line: StringName = &"focus_reveal_frog_again"
@export var bat_note_text: String = "Bats perched right side up, not hanging."
@export var bat_note_line: StringName = &"end_note_bats"
## A frog jumps on the spot once identified: how high, how long each rise
## and fall takes, the rest between jumps, and the level swell at the top.
@export var frog_hop_height: float = 1.6
@export var frog_hop_rise_seconds: float = 0.3
@export var frog_hop_rest_seconds: float = 0.6
@export var frog_hop_swell_db: float = 8.0
## The croak rises in pitch on the way up and drops back on the way down.
@export var frog_hop_pitch_lift: float = 1.2
## The splash it lands with, every jump. Empty for none.
@export var frog_land_sfx: StringName = &"footstep_water_splash_small"
@export var frog_land_db: float = 4.0

@export_group("End screen")
@export var end_screen_delay: float = 2.0
## Optional: the ending switches to the overhead reveal map (the V view) with
## the notes in a panel beside it. Off: the final scene has its own reveal.
@export var end_shows_reveal_map: bool = false
## Demo shortcut: Ctrl + this key skips straight to the end (exit line, notes,
## reveal map) from anywhere in the run, like Ctrl+1..5 for the events.
@export var skip_to_end_key: Key = KEY_6
@export var end_notes_intro_line: StringName = &"end_notes_intro"
@export var end_notes_none_line: StringName = &"end_notes_none"

@export_group("Swarm shake")
## Side-to-side swings needed, each the opposite way to the last: 4 is two
## full shakes. How fast and far a swing must be is in GameState's
## HEAD GESTURES CONFIG (shake_min_rate_deg, shake_min_swing_deg).
@export var shake_swings_required: int = 4
## The bat says it again after this long...
@export var shake_reminder_seconds: float = 12.0
## ...and the flies give up by themselves after this long (anti-lockout).
@export var shake_fail_forward_seconds: float = 35.0
## How long the buzz takes to fade once the flies are driven off.
@export var flies_clear_seconds: float = 2.5
@export var flies_path: NodePath = ^"Swarm/Flies"
@export var shake_prompt_line: StringName = &"swarm_shake_prompt"
## Empty: the reminder repeats shake_prompt_line.
@export var shake_again_line: StringName = &""
@export var shake_cleared_line: StringName = &"swarm_shake_cleared"
@export_group("")

## True once a scan has found the den: the stealth encounter reads it (the
## animal is heard earlier and passes farther away).
var den_found: bool = false
var swarm_found: bool = false
## True once the player has shaken the flies off the den.
var swarm_cleared: bool = false
var shaking: bool = false
var _t_shaking: float = 0.0
var _shake_reminded: bool = false
var run_finished: bool = false

var player: CharacterBody3D = null
var exit_wind: Node3D = null
var river: Node3D = null
var stealth: Node3D = null
var climb: Node3D = null

var _route: PackedVector3Array = PackedVector3Array()
var _route_s: PackedFloat32Array = PackedFloat32Array()  # arc length at each point
var _checkpoints: Array[Marker3D] = []
var _labels_root: Node3D = null
var _slide: Tween = null
var _den_scan: Describable = null
var _two_things_said: bool = false
## Frogs the player found themselves, for the note's count.
var frogs_found: int = 0
var _swarm_prompted: bool = false


func _ready() -> void:
	player = get_node(player_path)
	exit_wind = get_node(exit_wind_path)
	river = get_node(river_path)
	stealth = get_node(stealth_path)
	climb = get_node(climb_path)
	for p in checkpoint_paths:
		_checkpoints.append(get_node(p))
	_build_route()

	get_node(e2_trigger_path).body_entered.connect(_on_e2_trigger)
	get_node(exit_trigger_path).body_entered.connect(_on_exit_trigger)
	_den_scan = get_node(den_scan_path)
	_den_scan.blocked = true  # behind the flies until they're shaken off
	BatCompanion.scan_performed.connect(_on_scan_performed)
	get_node(swarm_trigger_path).body_entered.connect(_on_swarm_trigger)
	get_node(swarm_focus_path).revealed.connect(_on_swarm_revealed)
	GameState.head_shaken.connect(_on_head_shaken)
	for path in frog_focus_paths:
		var frog_focus := get_node(path)
		frog_focus.revealed.connect(_on_frog_revealed.bind(frog_focus))
	var bat_focus := get_node(bat_focus_path)
	bat_focus.revealed.connect(_on_bats_revealed.bind(bat_focus))

	_build_debug_markers()
	EventDirector.register_level(self)

	# Autopilot regression run (tests/escape_autotest.gd): -- --autotest,
	# -- --livecheck to watch what the live sensor pipeline delivers, or
	# -- --aerial-shot=<png> for a top-down screenshot.
	var args := Array(OS.get_cmdline_user_args())
	if args.has("--autotest") or args.has("--livecheck") \
			or args.any(func(a): return a.begins_with("--aerial-shot=")):
		var test := Node.new()
		test.name = "Autotest"
		test.set_script(load("res://tests/escape_autotest.gd"))
		add_child(test)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if shaking:
		_t_shaking += delta
		if not _shake_reminded and _t_shaking >= shake_reminder_seconds:
			_shake_reminded = true
			BatCompanion.say(shake_again_line if shake_again_line != &"" else shake_prompt_line)
		if _t_shaking >= shake_fail_forward_seconds:
			print("EscapeLevel: no shake in time, the flies leave by themselves.")
			_clear_swarm()
	# The overload detector's no-progress signal: distance left along the
	# route, not straight-line distance -- the route bends, and walking the
	# right way round a bend must count as progress.
	GameState.report_distance_to_objective(route_length() - project(player.global_position).s)


# --- Route ---------------------------------------------------------------

func _build_route() -> void:
	var total := 0.0
	for child in get_node(route_path).get_children():
		if child is Marker3D:
			if not _route.is_empty():
				total += _route[-1].distance_to(child.global_position)
			_route.append(child.global_position)
			_route_s.append(total)


func route_length() -> float:
	return _route_s[-1] if not _route_s.is_empty() else 0.0


## Closest point on the route to pos: {s (arc length), point}. Horizontal
## distance decides closeness, so the climb's slope doesn't skew it.
func project(pos: Vector3) -> Dictionary:
	var best := {"s": 0.0, "point": _route[0] if not _route.is_empty() else pos}
	var best_d := INF
	for i in range(_route.size() - 1):
		var a := _route[i]
		var b := _route[i + 1]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(pos.x - a.x, pos.z - a.z)
		var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a.lerp(b, t)
		var d := Vector2(pos.x - q.x, pos.z - q.z).length()
		if d < best_d:
			best_d = d
			best = {"s": lerpf(_route_s[i], _route_s[i + 1], t), "point": q}
	return best


func point_at(s: float) -> Vector3:
	s = clampf(s, 0.0, route_length())
	for i in range(_route.size() - 1):
		if s <= _route_s[i + 1]:
			var seg := _route_s[i + 1] - _route_s[i]
			return _route[i].lerp(_route[i + 1], (s - _route_s[i]) / maxf(seg, 0.0001))
	return _route[-1]


## World yaw of "ahead along the route" at s.
func yaw_at(s: float) -> float:
	var a := point_at(s - 0.5)
	var b := point_at(s + 0.5)
	var d := Vector2(b.x - a.x, b.z - a.z)
	return atan2(-d.x, -d.y)


func progress_fraction() -> float:
	return clampf(project(player.global_position).s / maxf(route_length(), 0.001), 0.0, 1.0)


# --- Moving the player ------------------------------------------------------

## Puts the player at pos facing yaw, stopped, with "ahead" recentred onto
## that yaw -- arriving somewhere new with the old forward would point the
## player at a wall.
func teleport_player(pos: Vector3, yaw: float) -> void:
	player.global_position = pos + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO
	GameState.set_reference_yaw(yaw)


func teleport_to_checkpoint(index: int) -> void:
	var cp := _checkpoints[index]
	teleport_player(cp.global_position, cp.global_rotation.y)


## The one way the player gets pushed back in the same event: a quick slide
## to pos, ending stopped, with their facing left alone. The caller holds
## input_locked for the whole of it.
func slide_player_to(pos: Vector3, seconds: float) -> void:
	_stop_slide()
	player.velocity = Vector3.ZERO
	_slide = create_tween()
	_slide.tween_property(player, "global_position", pos, seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _slide.finished


func _stop_slide() -> void:
	if _slide != null and _slide.is_valid():
		_slide.kill()
	_slide = null


## Waits out whatever the bat is saying, up to timeout.
func wait_for_bat(timeout: float) -> void:
	var t := 0.0
	while BatCompanion.is_speaking() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()


## Knockback: back down the route by distance, never below min_s -- and
## never forward, even when the player is already below min_s.
func knock_back_along_route(distance: float, min_s: float) -> void:
	var here: float = project(player.global_position).s
	var s := minf(here, maxf(here - distance, min_s))
	teleport_player(point_at(s), yaw_at(s))


# --- Event control (called by EventDirector) ------------------------------

## Ctrl+1..5 / --event=N. Everything earlier is treated as done; everything
## from the target on is reset, so an event can be replayed.
func jump_to(event: int) -> void:
	run_finished = false
	_stop_slide()
	if event <= Event.RIVER:
		river.reset_crossing()
	else:
		river.mark_crossed()
	stealth.reset_encounter()
	climb.stop_climb()
	GameState.input_locked = false
	GameState.reset_counters()
	BatCompanion.shut_up()

	exit_wind.set_mode(ExitWind.Mode.OFF if event <= Event.WIND else ExitWind.Mode.HEADING)

	EventDirector.current_event = event as Event
	EventDirector.event_running = false
	teleport_to_checkpoint(event)
	print("EscapeLevel: jumped to %s" % EventDirector.event_name(event as Event))
	match event:
		Event.CALM:
			EventDirector.start_event_one()
		Event.WIND:
			_start_e2()
		Event.RIVER:
			river.begin_crossing()
		Event.STEALTH:
			stealth.begin_encounter()
		Event.ESCAPE:
			climb.start_climb()


## F6 with an event running: finish it as if passed.
func skip_event(event: int) -> void:
	match event:
		Event.WIND:
			BatCompanion.shut_up()
			EventDirector.complete(Event.WIND)
		Event.RIVER:
			river.skip()
		Event.STEALTH:
			stealth.skip()
		Event.ESCAPE:
			climb.stop_climb()
			var top := _checkpoints[Event.ESCAPE]
			teleport_player(get_node(exit_trigger_path).global_position, top.global_rotation.y)


## F11.
func force_fail(event: int) -> void:
	match event:
		Event.RIVER:
			river.force_fail()
		Event.STEALTH:
			stealth.force_fail()
		Event.ESCAPE:
			climb.force_hit()
		_:
			print("EscapeLevel: F11 only does something during the river (swept), stealth (caught) and the climb (hit).")


# --- E2: the bat says to follow the wind --------------------------------------

func _on_e2_trigger(body: Node3D) -> void:
	if body == player and EventDirector.current_event == Event.WIND and not EventDirector.event_running:
		_start_e2()


func _start_e2() -> void:
	EventDirector.begin(Event.WIND)
	# On before the line, so "do you feel that?" has something to refer to.
	exit_wind.set_mode(ExitWind.Mode.HEADING)
	BatCompanion.say(e2_line)
	await wait_for_bat(30.0)
	# No-op if a skip or a jump already moved the run on.
	EventDirector.complete(Event.WIND)


# --- The den (found by echolocation) ----------------------------------------
#
# The den makes no sound, so nothing draws the player there or holds FOCUS on
# it: a scan from close enough is what finds it, and the bat says what it is.

## The nest, one step at a time: a scan picks up the flies with something
## behind them (the bat says so, once); FOCUS on the buzzing sets the flies on
## the player; shaking them off reveals the den.
func _on_scan_performed(returns: Array) -> void:
	if den_found or swarm_cleared or _two_things_said:
		return
	var flies: Describable = get_node(flies_path).get_node("Describable")
	for entry in returns:
		if flies in entry.nodes:
			_two_things_said = true
			print("EscapeLevel: the scan reached the flies, with the den blocked behind them.")
			BatCompanion.say(den_two_things_line)
			return


func _on_den_found() -> void:
	den_found = true
	_den_scan.identified = true
	print("EscapeLevel: den found -- the stealth encounter is now easier.")
	await get_tree().create_timer(den_line_delay).timeout
	BatCompanion.say(den_reveal_line)
	if den_reward_line != &"":
		BatCompanion.say(den_reward_line)


# --- The swarm (found by FOCUS, shaken off to reach the den) -------------------

func _start_shaking() -> void:
	if shaking:
		return
	shaking = true
	_t_shaking = 0.0
	_shake_reminded = false
	GameState.reset_shake()
	print("EscapeLevel: the flies swarm the player.")
	await get_tree().create_timer(den_line_delay).timeout
	if shaking:
		BatCompanion.say(shake_prompt_line)


func _on_head_shaken(swings: int) -> void:
	if not shaking:
		return
	print("EscapeLevel: shake swing %d of %d" % [swings, shake_swings_required])
	if swings >= shake_swings_required:
		_clear_swarm()


## The flies scatter: their buzz fades and they are gone from the scan and from
## FOCUS. Then the den behind them resolves.
func _clear_swarm() -> void:
	shaking = false
	swarm_cleared = true
	_den_scan.blocked = false
	var flies := get_node(flies_path) as Node3D
	var focus := get_node(swarm_focus_path)
	focus.active = false
	var buzz: AudioStreamPlayer3D = flies.get_node("Body/AudioStreamPlayer3D")
	var fade := create_tween()
	fade.tween_property(buzz, "volume_db", -50.0, flies_clear_seconds)
	fade.tween_callback(func():
		buzz.stop()
		flies.visible = false)
	BatCompanion.shut_up()
	BatCompanion.say(shake_cleared_line)
	_on_den_found()



func _on_swarm_trigger(body: Node3D) -> void:
	if body == player and not _swarm_prompted and not swarm_found and not swarm_cleared:
		_swarm_prompted = true
		if swarm_prompt_line != &"":
			BatCompanion.say(swarm_prompt_line)


## FOCUS on the buzzing found the flies, and they swarm the player.
func _on_swarm_revealed() -> void:
	swarm_found = true
	print("EscapeLevel: swarm identified.")
	_start_shaking()


# --- The frog and the bats (found by scan + FOCUS) -----------------------------

## Every frog jumps once named. The note is taken once, and only if the player
## built the focus themselves (not the fail-forward timer).
func _on_frog_revealed(focus: Node) -> void:
	# Every frog after the first is just "another frog".
	for path in frog_focus_paths:
		var other := get_node(path)
		if other != focus and not other.revealed_state:
			other.reveal_line = frog_again_line
	if focus.earned:
		frogs_found += 1
		if frogs_found == 1:
			GameState.record_observation(&"frog", frog_note_text, frog_note_line)
		else:
			var line: StringName = frog_count_lines[mini(frogs_found, frog_count_lines.size() - 1)]
			GameState.update_observation(&"frog", frogs_note_text % frogs_found, line)
	# Hops start once FOCUS has settled the croak at its revealed level.
	var source := focus.get_node(focus.audio_player_path).get_parent().get_parent()
	await get_tree().create_timer(focus.reveal_settle_seconds).timeout
	source.start_hopping(frog_hop_height, frog_hop_rise_seconds, frog_hop_rest_seconds, frog_hop_swell_db,
			frog_hop_pitch_lift, frog_land_sfx, frog_land_db)


func _on_bats_revealed(focus: Node) -> void:
	if focus.earned:
		GameState.record_observation(&"bats_upright", bat_note_text, bat_note_line)


# --- The end ------------------------------------------------------------------

func _on_exit_trigger(body: Node3D) -> void:
	if body != player or run_finished or EventDirector.current_event != Event.ESCAPE:
		return
	_finish_run()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.ctrl_pressed and event.keycode == skip_to_end_key:
		get_viewport().set_input_as_handled()
		skip_to_end()


## Demo: straight to the ending from anywhere. Leaves whatever is running the
## same way the Ctrl+1..5 jumps do, puts the player at the exit and finishes.
func skip_to_end() -> void:
	if run_finished:
		return
	print("EscapeLevel: skipping to the end (demo).")
	EventDirector.jump_to(Event.ESCAPE)
	climb.stop_climb()
	BatCompanion.shut_up()
	var exit_mark := get_node("Landmarks/Exit") as Node3D
	teleport_player(exit_mark.global_position + Vector3.UP * 0.1, exit_mark.global_rotation.y)
	_finish_run()


func _finish_run() -> void:
	run_finished = true
	climb.stop_climb()
	exit_wind.set_mode(ExitWind.Mode.FULL)
	GameState.input_locked = true
	EventDirector.complete(Event.ESCAPE)
	await get_tree().create_timer(1.5).timeout
	BatCompanion.say(exit_line)
	_show_end_screen()
	print("EscapeLevel: RUN COMPLETE -- river swept %d, den %s, swarm %s, stealth attempts %d, rock hits %d." % [
		river.swept, "found" if den_found else "not found", "found" if swarm_found else "not found",
		stealth.attempt, climb.hits])


# --- Debug markers ------------------------------------------------------------
#
# Key: translucent boxes = trigger zones (orange), green posts = checkpoints,
# yellow post = the fork, white post = the exit. The wind, the animal, the
# den and the rocks draw their own (exit_wind.gd, stealth_encounter.gd,
# rockfall_climb.gd). Labels float above everything and ignore depth, so the
# aerial camera (V) reads them through the open-topped rock.

func _build_debug_markers() -> void:
	_labels_root = Node3D.new()
	_labels_root.name = "DebugMarkers"
	add_child(_labels_root)

	for area in get_tree().get_nodes_in_group(&"debug_zone"):
		var shape_node := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node == null or not (shape_node.shape is BoxShape3D):
			continue
		var box := BoxMesh.new()
		box.size = (shape_node.shape as BoxShape3D).size
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.layers = DebugDraw.LAYER
		mi.material_override = DebugDraw.material(Color(1.0, 0.55, 0.1, 0.18))
		shape_node.add_child(mi)
		DebugDraw.label(area, "TRIGGER  " + String(area.name), Vector3.UP * (box.size.y * 0.5 + 0.4), Color(1.0, 0.7, 0.3))

	for cp in _checkpoints:
		DebugDraw.post(cp, Color(0.2, 0.95, 0.35), "CHECKPOINT  " + String(cp.name))
	var fork := get_node_or_null("Landmarks/Fork")
	if fork != null:
		DebugDraw.post(fork, Color(1.0, 0.9, 0.1), "FORK  (left: den / right: river)")
	var exit_mark := get_node_or_null("Landmarks/Exit")
	if exit_mark != null:
		DebugDraw.post(exit_mark, Color(1, 1, 1), "EXIT")
	var den := get_node_or_null("Den") as Node3D
	if den != null:
		DebugDraw.post(den, Color(0.7, 0.3, 1.0), "DEN  (scan it: stealth gets easier)")
	var swarm := get_node_or_null("Swarm") as Node3D
	if swarm != null:
		DebugDraw.post(swarm, Color(0.3, 0.8, 0.5), "SWARM  (focus it)")

	# The player: a label, and a dot on the head's nose so facing reads from
	# the aerial view (the head turns; the body never does).
	DebugDraw.label(player, "YOU", Vector3.UP * 3.0, Color(0.6, 1.0, 0.6))
	var nose := DebugDraw.sphere(player.pivot, 0.18, Color(1.0, 1.0, 0.2))
	nose.position = Vector3(0, 0, -0.9)


## After the exit line: the notes, shown and read out. A run with no notes says so.
func _show_end_screen() -> void:
	await wait_for_bat(20.0)
	await get_tree().create_timer(end_screen_delay).timeout
	if end_shows_reveal_map:
		get_node("TopDownCamera").set_showing(true)
	var screen := CanvasLayer.new()
	screen.name = "EndScreen"
	screen.set_script(load("res://scripts/end_screen.gd"))
	add_child(screen)
	screen.show_notes(GameState.observations, end_shows_reveal_map)
	if GameState.observations.is_empty():
		BatCompanion.say(end_notes_none_line)
		return
	BatCompanion.say(end_notes_intro_line)
	for note in GameState.observations:
		BatCompanion.say(note.line)
