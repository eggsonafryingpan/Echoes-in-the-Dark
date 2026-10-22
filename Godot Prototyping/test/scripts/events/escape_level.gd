extends Node3D

## The escape blockout (escape_level.tscn): landing -> wind chamber -> fork
## (side branch to the den) -> stealth chamber -> climb -> exit.
##
## Runs Events 2-4 for EventDirector (which runs Event 1 itself) and owns
## everything that needs this level's layout:
##   - the ROUTE: a polyline of Marker3Ds down the main path. The exit wind
##     sits a little way ahead along it (so it is heard through the passage
##     the player will actually walk, not through rock), knockbacks slide the
##     player back along it, and "distance to the objective" for the
##     overload detector is distance left along it.
##   - CHECKPOINTS: where each event starts, and where a knockback lands.
##   - TRIGGERS: Area3Ds that start each event when the player walks in.
##   - E2 (FOCUS on the wind) and the den reward, directly in this file;
##     E3 and E4 are their own nodes (stealth_encounter.gd, rockfall_climb.gd).
##   - the debug markers: every trigger zone, checkpoint and landmark gets a
##     visible shape and a floating label, so autopilot shows what is going
##     on. All of it sits under the filming black-out like everything else.

const Event := preload("res://autoload/event_director.gd").Event
const ExitWind := preload("res://scripts/events/exit_wind.gd")

@export var player_path: NodePath = ^"player"
@export var route_path: NodePath = ^"Route"
@export var exit_wind_path: NodePath = ^"ExitWind"
@export var stealth_path: NodePath = ^"Stealth"
@export var climb_path: NodePath = ^"Climb"
@export var den_focus_path: NodePath = ^"Den/Focusable"

## Checkpoints, one per event, each a Marker3D whose -Z is "ahead" there.
@export var checkpoint_paths: Array[NodePath] = [
	^"Checkpoints/E1_Landing", ^"Checkpoints/E2_WindChamber",
	^"Checkpoints/E3_BeforeStealth", ^"Checkpoints/E4_ShaftBottom",
]
@export var e2_trigger_path: NodePath = ^"Triggers/E2_WindChamber"
@export var exit_trigger_path: NodePath = ^"Triggers/Exit"

## Bat line when E2 starts, and when the den is identified.
@export var e2_prompt_line: StringName = &"e2_prompt"
@export var den_reward_line: StringName = &"den_reward"
@export var exit_line: StringName = &"e4_exit"

## True once the den's FOCUS reveal has landed: the stealth encounter reads
## it (the animal is heard earlier and passes farther away).
var den_found: bool = false
var run_finished: bool = false

var player: CharacterBody3D = null
var exit_wind: Node3D = null
var stealth: Node3D = null
var climb: Node3D = null

var _route: PackedVector3Array = PackedVector3Array()
var _route_s: PackedFloat32Array = PackedFloat32Array()  # arc length at each point
var _checkpoints: Array[Marker3D] = []
var _labels_root: Node3D = null


func _ready() -> void:
	player = get_node(player_path)
	exit_wind = get_node(exit_wind_path)
	stealth = get_node(stealth_path)
	climb = get_node(climb_path)
	for p in checkpoint_paths:
		_checkpoints.append(get_node(p))
	_build_route()

	get_node(e2_trigger_path).body_entered.connect(_on_e2_trigger)
	get_node(exit_trigger_path).body_entered.connect(_on_exit_trigger)
	var den_focus := get_node_or_null(den_focus_path)
	if den_focus != null:
		den_focus.revealed.connect(_on_den_revealed)
	exit_wind.get_node("Focusable").revealed.connect(_on_wind_revealed)

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


func _physics_process(_delta: float) -> void:
	if player == null:
		return
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


## Knockback: back down the route by distance, never below min_s -- and
## never forward, even when the player is already below min_s.
func knock_back_along_route(distance: float, min_s: float) -> void:
	var here: float = project(player.global_position).s
	var s := minf(here, maxf(here - distance, min_s))
	teleport_player(point_at(s), yaw_at(s))


# --- Event control (called by EventDirector) ------------------------------

## Ctrl+1..4 / --event=N. Everything earlier is treated as done; everything
## from the target on is reset, so an event can be replayed.
func jump_to(event: int) -> void:
	run_finished = false
	stealth.reset_encounter()
	climb.stop_climb()
	GameState.input_locked = false
	GameState.reset_counters()
	BatCompanion.shut_up()

	var wind_focus: Focusable = exit_wind.get_node("Focusable")
	if event <= Event.FOCUS:
		wind_focus.reset()
		exit_wind.set_mode(ExitWind.Mode.OFF)
	else:
		wind_focus.force_reveal(true)
		exit_wind.set_mode(ExitWind.Mode.HEADING)

	EventDirector.current_event = event as Event
	EventDirector.event_running = false
	teleport_to_checkpoint(event)
	print("EscapeLevel: jumped to %s" % EventDirector.event_name(event as Event))
	match event:
		Event.CALM:
			EventDirector.start_event_one()
		Event.FOCUS:
			_start_e2()
		Event.STEALTH:
			stealth.begin_encounter()
		Event.ESCAPE:
			climb.start_climb()


## F6 with an event running: finish it as if passed.
func skip_event(event: int) -> void:
	match event:
		Event.FOCUS:
			exit_wind.get_node("Focusable").force_reveal()
		Event.STEALTH:
			stealth.skip()
		Event.ESCAPE:
			climb.stop_climb()
			var top := _checkpoints[Event.ESCAPE]
			teleport_player(get_node(exit_trigger_path).global_position, top.global_rotation.y)


## F11.
func force_fail(event: int) -> void:
	match event:
		Event.STEALTH:
			stealth.force_fail()
		Event.ESCAPE:
			climb.force_hit()
		_:
			print("EscapeLevel: F11 only does something during E3 (caught) and E4 (hit).")


# --- E2: FOCUS on the outside wind ------------------------------------------

func _on_e2_trigger(body: Node3D) -> void:
	if body == player and EventDirector.current_event == Event.FOCUS and not EventDirector.event_running:
		_start_e2()


func _start_e2() -> void:
	EventDirector.begin(Event.FOCUS)
	exit_wind.set_mode(ExitWind.Mode.FOCUS)
	BatCompanion.say(e2_prompt_line)


## The reveal itself (sting + the bat naming it) is Focusable's; this only
## turns the wind into the heading and moves the run on.
func _on_wind_revealed() -> void:
	exit_wind.set_mode(ExitWind.Mode.HEADING)
	if EventDirector.current_event == Event.FOCUS:
		EventDirector.complete(Event.FOCUS)


# --- The den (side branch reward) -------------------------------------------

func _on_den_revealed() -> void:
	if den_found:
		return
	den_found = true
	print("EscapeLevel: den found -- the stealth encounter is now easier.")
	await get_tree().create_timer(3.0).timeout
	BatCompanion.say(den_reward_line)


# --- The end ------------------------------------------------------------------

func _on_exit_trigger(body: Node3D) -> void:
	if body != player or run_finished or EventDirector.current_event != Event.ESCAPE:
		return
	run_finished = true
	climb.stop_climb()
	exit_wind.set_mode(ExitWind.Mode.FULL)
	GameState.input_locked = true
	EventDirector.complete(Event.ESCAPE)
	await get_tree().create_timer(1.5).timeout
	BatCompanion.say(exit_line)
	print("EscapeLevel: RUN COMPLETE -- den %s, stealth attempts %d, rock hits %d." % [
		"found" if den_found else "not found", stealth.attempt, climb.hits])


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
		mi.material_override = DebugDraw.material(Color(1.0, 0.55, 0.1, 0.18))
		shape_node.add_child(mi)
		DebugDraw.label(area, "TRIGGER  " + String(area.name), Vector3.UP * (box.size.y * 0.5 + 0.4), Color(1.0, 0.7, 0.3))

	for cp in _checkpoints:
		DebugDraw.post(cp, Color(0.2, 0.95, 0.35), "CHECKPOINT  " + String(cp.name))
	var fork := get_node_or_null("Landmarks/Fork")
	if fork != null:
		DebugDraw.post(fork, Color(1.0, 0.9, 0.1), "FORK  (left: den / ahead-right: main path)")
	var exit_mark := get_node_or_null("Landmarks/Exit")
	if exit_mark != null:
		DebugDraw.post(exit_mark, Color(1, 1, 1), "EXIT")
	var den := get_node_or_null("Den") as Node3D
	if den != null:
		DebugDraw.post(den, Color(0.7, 0.3, 1.0), "DEN  (focus it: stealth gets easier)")

	# The player: a label, and a dot on the head's nose so facing reads from
	# the aerial view (the head turns; the body never does).
	DebugDraw.label(player, "YOU", Vector3.UP * 3.0, Color(0.6, 1.0, 0.6))
	var nose := DebugDraw.sphere(player.pivot, 0.18, Color(1.0, 1.0, 0.2))
	nose.position = Vector3(0, 0, -0.9)
