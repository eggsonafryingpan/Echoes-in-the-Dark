extends Camera3D

## The reveal: a clean overhead view of the whole cave for sighted viewers, on
## its own screen. The switch_camera key (V) goes in and out. Audio is
## unaffected, since the listener is driven separately from whichever camera
## is showing.
##
## Framed from the cave's own geometry, so it follows layout changes. No text:
## playtest visuals sit on a render layer this camera leaves out, the operator
## overlays are hidden while it shows, and markers are drawn as shapes on top.
##
## Markers: the player, an arrow turning with the head; each thing in
## anomaly_paths, once identified; the exit.

# ------------------------------------------------------------------------
# REVEAL VIEW CONFIG
# ------------------------------------------------------------------------
@export_group("Framing")
## Frame the cave's carved rooms automatically. Off: use the two values below.
@export var auto_frame: bool = true
@export var cave_path: NodePath = ^"../CaveBody"
## Empty world-space margin around the cave, in metres.
@export var frame_margin: float = 10.0
## Nudges the framing. x and y are world X and Z.
@export var frame_offset: Vector2 = Vector2.ZERO
## Used when auto_frame is off: what to look at (world X, Z), and how many
## metres of the world the screen height covers.
@export var manual_center: Vector2 = Vector2(0.0, -88.0)
@export var manual_size: float = 215.0
## Keep above the cave's top. Height has no effect on scale in this projection.
@export var camera_height: float = 150.0
## Rotates the map on screen, in degrees. 90 lays the long cave on its side
## so it fills a widescreen.
@export var map_rotation_deg: float = 90.0

@export_group("Markers")
@export var player_path: NodePath = ^"../player"
## During the final climb V shows that scene's own wall view instead.
@export var climb_path: NodePath = ^"../Climb"
@export var exit_path: NodePath = ^"../Landmarks/Exit"
## Describable nodes. Each gets a marker once it is identified.
@export var anomaly_paths: Array[NodePath] = [
	^"../Den/Describable", ^"../Swarm/Flies/Describable", ^"../BatRoost/Source/Describable",
	^"../Frogs/FrogLanding/Source/Describable", ^"../Frogs/FrogCorridor/Source/Describable",
	^"../Frogs/FrogRiver/Source/Describable", ^"../Frogs/FrogStealth/Source/Describable",
]
@export var show_player: bool = true
@export var show_exit: bool = true
@export var show_anomalies: bool = true
## Marker sizes, in pixels at 1080p tall.
@export var player_marker_size: float = 22.0
@export var anomaly_marker_size: float = 18.0
@export var exit_marker_size: float = 20.0
@export var player_color: Color = Color(1.0, 0.85, 0.2)
@export var anomaly_color: Color = Color(1.0, 0.35, 0.45)
@export var exit_color: Color = Color(0.4, 1.0, 0.65)
## Soft pulse on the player marker. 0 turns it off.
@export var player_pulse_speed: float = 2.5

@export_group("Screen")
## Matches the lit rock, so the map has no hard edge where the block ends.
@export var background_color: Color = Color(0.478, 0.455, 0.424)
## Hidden while the reveal shows, then put back as they were.
@export var hide_while_showing: Array[NodePath] = [
	^"../AudioDebugOverlay", ^"../ObjectDebugOverlay", ^"../HrDebugOverlay",
	^"../FocusDebugOverlay", ^"../EventDebugOverlay", ^"../FilmingOverlay",
]
## Above every operator overlay, including the filming black-out.
@export var marker_layer: int = 110
@export_group("")

const SWITCH_ACTION := &"switch_camera"

var showing: bool = false

var _first_person: Camera3D = null
var _player: Node3D = null
var _exit: Node3D = null
var _anomalies: Array[Describable] = []
var _canvas: CanvasLayer = null
var _markers: Control = null
var _hidden: Array[CanvasLayer] = []
var _environment: Environment = null


func _ready() -> void:
	_first_person = get_viewport().get_camera_3d()
	_player = get_node_or_null(player_path)
	_exit = get_node_or_null(exit_path)
	for path in anomaly_paths:
		var d := get_node_or_null(path) as Describable
		if d != null:
			_anomalies.append(d)

	projection = PROJECTION_ORTHOGONAL
	far = camera_height * 2.0
	# Every layer except the playtest visuals.
	cull_mask = cull_mask & ~DebugDraw.LAYER
	_environment = _base_environment()
	environment = _environment

	_canvas = CanvasLayer.new()
	_canvas.name = "RevealMarkers"
	_canvas.layer = marker_layer
	_canvas.visible = false
	add_child(_canvas)
	_markers = Control.new()
	_markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers.draw.connect(_draw_markers)
	_canvas.add_child(_markers)
	_frame.call_deferred()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(SWITCH_ACTION):
		var climb := get_node_or_null(climb_path)
		if climb != null and climb.has_method("toggle_wall_view") and climb.active:
			set_showing(false)
			climb.toggle_wall_view()
		else:
			set_showing(not showing)
	if showing:
		_markers.queue_redraw()


func set_showing(on: bool) -> void:
	if on == showing:
		return
	showing = on
	_canvas.visible = on
	if on:
		_frame()
		_hide_overlays()
		make_current()
	else:
		for overlay in _hidden:
			overlay.visible = true
		_hidden.clear()
		if _first_person != null:
			_first_person.make_current()


func _hide_overlays() -> void:
	for path in hide_while_showing:
		var overlay := get_node_or_null(path) as CanvasLayer
		if overlay != null and overlay.visible:
			overlay.visible = false
			_hidden.append(overlay)


func _base_environment() -> Environment:
	var world := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	var env: Environment = world.environment.duplicate() if world != null else Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = background_color
	return env


## Points straight down. map_rotation_deg spins the view about that axis.
func _frame() -> void:
	var bounds := _cave_bounds() if auto_frame else Rect2()
	var center := bounds.get_center() if auto_frame else manual_center
	center += frame_offset
	rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	rotate_object_local(Vector3.BACK, deg_to_rad(map_rotation_deg))
	global_position = Vector3(center.x, camera_height, center.y)
	if not auto_frame:
		size = manual_size
		return

	var view := get_viewport().get_visible_rect().size
	var aspect := view.x / maxf(view.y, 1.0)
	var turned := absf(sin(deg_to_rad(map_rotation_deg)))
	var wide := lerpf(bounds.size.x, bounds.size.y, turned) + frame_margin * 2.0
	var tall := lerpf(bounds.size.y, bounds.size.x, turned) + frame_margin * 2.0
	keep_aspect = KEEP_HEIGHT
	size = maxf(tall, wide / aspect)


## The footprint of the rooms, as world (X, Z). The solid block around them
## says nothing about the layout, so only carved boxes count.
func _cave_bounds() -> Rect2:
	var cave := get_node_or_null(cave_path)
	var bounds := Rect2()
	var started := false
	if cave == null:
		return Rect2(manual_center - Vector2.ONE * manual_size * 0.5, Vector2.ONE * manual_size)
	for child in cave.get_children():
		var box := child as CSGBox3D
		if box == null or box.operation != CSGShape3D.OPERATION_SUBTRACTION:
			continue
		var at := box.global_position
		var rect := Rect2(at.x - box.size.x * 0.5, at.z - box.size.z * 0.5, box.size.x, box.size.z)
		bounds = rect if not started else bounds.merge(rect)
		started = true
	return bounds


func _to_screen(world: Vector3) -> Vector2:
	return unproject_position(world)


func _scale() -> float:
	return _markers.size.y / 1080.0


func _draw_markers() -> void:
	if show_exit and _exit != null:
		_draw_exit(_to_screen(_exit.global_position))
	if show_anomalies:
		for anomaly in _anomalies:
			if anomaly.identified and is_instance_valid(anomaly):
				_draw_anomaly(_to_screen(anomaly.global_position))
	if show_player and _player != null:
		_draw_player(_to_screen(_player.global_position))


## A ring and a dot.
func _draw_anomaly(at: Vector2) -> void:
	var r := anomaly_marker_size * _scale()
	_markers.draw_arc(at, r, 0.0, TAU, 40, anomaly_color, 3.0 * _scale(), true)
	_markers.draw_circle(at, r * 0.35, anomaly_color)


## A diamond.
func _draw_exit(at: Vector2) -> void:
	var r := exit_marker_size * _scale()
	var points := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	_markers.draw_colored_polygon(points, exit_color)


## An arrow along the head's facing, over a pulsing halo.
func _draw_player(at: Vector2) -> void:
	var r := player_marker_size * _scale()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * player_pulse_speed) if player_pulse_speed > 0.0 else 0.5
	var halo := player_color
	halo.a = 0.15 + 0.15 * pulse
	_markers.draw_circle(at, r * (1.5 + 0.3 * pulse), halo)

	var facing := -Basis.from_euler(Vector3(0.0, GameState.effective_orientation().y, 0.0)).z
	var ahead := _to_screen(_player.global_position + facing) - at
	var forward := ahead.normalized() if ahead.length() > 0.001 else Vector2.UP
	var side := forward.orthogonal()
	_markers.draw_colored_polygon(PackedVector2Array([
		at + forward * r, at - forward * r * 0.7 + side * r * 0.75,
		at - forward * r * 0.3, at - forward * r * 0.7 - side * r * 0.75,
	]), player_color)
