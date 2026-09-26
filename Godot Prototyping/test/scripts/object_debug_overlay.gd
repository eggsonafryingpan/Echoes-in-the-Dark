extends CanvasLayer

## Sighted-operator view of an audio-only game (§11): where every scannable
## and focusable object actually is, what state it is in, and — the part
## that is otherwise pure guesswork — how far a FOCUS has built and on what.
##
## Everything here is created at runtime and starts hidden, so the scene
## file stays clean and nothing can leak into a recording: with the toggle
## off there are no meshes in the world and no text on screen. F7.
##
## The colour key is printed to the console at startup whether or not the
## overlay is on, so the mapping is in the log next to whatever else is
## being debugged.

const TOGGLE_ACTION := &"debug_object_overlay"

## Per the agreed key. LandmarkWater was not in it — it is a discrete
## scannable object, so it gets WHITE rather than being left unmarked.
const COLOR_KEY := {
	&"SwarmAmbience":  [Color.RED,    "swarm"],
	&"WaterDrip":      [Color.BLUE,   "drip"],
	&"LandmarkRubble": [Color.YELLOW, "rubble"],
	&"BatRoost":       [Color.PURPLE, "roost"],
	&"SmallCreatureA": [Color.GREEN,  "creature_1"],
	&"SmallCreatureB": [Color.ORANGE, "creature_2"],
	&"LargerCreature": [Color.CYAN,   "creature_3"],
	&"LandmarkWater":  [Color.WHITE,  "trickle"],
}

## Continuous sources share one look. Long flat bars rather than cubes so
## they read as "a stretch of river" at a glance, and a dimmed teal rather
## than the suggested cyan so they cannot be confused with creature_3.
const CONTINUOUS_COLOR := Color(0.0, 0.45, 0.45)

## Above the audio readout (50), below the filming black-out (100) — the
## filming overlay must always win.
@export var overlay_layer: int = 60

## Nudges the swarm marker up so it does not sit exactly inside
## creature_1's marker; both are authored at the same position.
@export var swarm_marker_lift: float = 0.9

var _enabled: bool = false
var _label: Label = null
var _markers: Array = []      # [{node, describable, mesh, color, key, focusable}]
var _last_scan: Array = []
var _meshes_added: int = 0


func _ready() -> void:
	layer = overlay_layer
	_label = Label.new()
	_label.name = "ObjectReadout"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.position = Vector2(-14, 12)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_color_override(&"font_color", Color(1, 1, 1))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	# Hidden here, not left to _process: otherwise the readout is on screen
	# for the frame between _ready and the first _process, which is exactly
	# the kind of thing that ends up in a recording.
	_label.visible = false
	add_child(_label)

	BatCompanion.scan_performed.connect(_on_scan_performed)
	call_deferred("_build")


func _build() -> void:
	for describable in get_tree().get_nodes_in_group(&"describable"):
		var node: Node3D = describable.get_parent()
		var entry: Variant = COLOR_KEY.get(StringName(node.name), null)
		var color: Color = entry[0] if entry != null else CONTINUOUS_COLOR
		var key: String = entry[1] if entry != null else "continuous"

		if node.find_children("*", "MeshInstance3D", true, false).is_empty():
			_meshes_added += 1
		var mesh: MeshInstance3D = _make_marker(node, color, describable.continuous)
		_markers.append({
			"node": node,
			"describable": describable,
			"mesh": mesh,
			"color": color,
			"key": key,
			"focusable": _focusable_for(describable),
		})

	_markers.sort_custom(func(a, b): return a.key < b.key)
	_print_key()


## Every one of these objects is a bare Node3D or a SpatialSfxSource with no
## visual at all, so the marker is always a new mesh rather than a recolour.
func _make_marker(parent: Node3D, color: Color, continuous: bool) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(6.0, 0.25, 0.25) if continuous else Vector3(0.6, 0.6, 0.6)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.4
	# Unshaded so the colour is exactly the key colour regardless of how dark
	# the cave is -- these have to be identifiable, not lit convincingly.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := MeshInstance3D.new()
	mesh.name = "DebugMarker"
	mesh.mesh = box
	mesh.material_override = material
	mesh.visible = false
	if parent.name == &"SwarmAmbience":
		mesh.position.y += swarm_marker_lift
	parent.add_child(mesh)
	return mesh


## The Focusable governing this Describable, if any. Matched by the node a
## Focusable actually resolves, not by naming convention.
func _focusable_for(describable: Node) -> Node:
	for focusable in _all_focusables():
		var target: Node = null
		if focusable.describable_path != NodePath():
			target = focusable.get_node_or_null(focusable.describable_path)
		else:
			target = focusable.get_node_or_null("Describable")
		if target == describable:
			return focusable
	return null


func _all_focusables() -> Array:
	var found: Array = []
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		var script: Variant = node.get_script()
		if script != null and script.resource_path.ends_with("focusable.gd"):
			found.append(node)
	return found


func _print_key() -> void:
	print("--- object debug key (F7 to show) ---")
	for m in _markers:
		print("    %-12s %-16s %s" % [m.key, m.node.name, _color_name(m.color)])
	print("    %d markers created, %d objects previously had no mesh" % [_markers.size(), _meshes_added])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		_enabled = not _enabled
		for m in _markers:
			m.mesh.visible = _enabled
		get_viewport().set_input_as_handled()


func _on_scan_performed(returns: Array) -> void:
	_last_scan = []
	for entry in returns:
		_last_scan.append("%s %.1fm" % [entry.node.get_parent().name, entry.distance])


func _process(_delta: float) -> void:
	_label.visible = _enabled
	if not _enabled:
		return
	_label.text = _readout()


func _readout() -> String:
	var lines: Array[String] = ["OBJECT DEBUG  [F7]"]

	var orientation := GameState.effective_orientation()
	var forward := -Basis.from_euler(orientation).z
	lines.append("head yaw %6.1f deg   forward %s" % [
		rad_to_deg(orientation.y), str(forward.snapped(Vector3.ONE * 0.01))])

	if _last_scan.is_empty():
		lines.append("last scan: none yet")
	else:
		lines.append("last scan: %d pings -> %s" % [_last_scan.size(), ", ".join(_last_scan)])

	lines.append(_focus_line())
	lines.append("")

	var head := GameState.head_position
	for m in _markers:
		var distance: float = head.distance_to(m.node.global_position)
		var describable = m.describable
		var focusable = m.focusable
		var focus_state := "-"
		if focusable != null:
			focus_state = "DONE" if focusable.revealed_state else "%3.0f%%" % (focusable.focus_progress * 100.0)
		lines.append("%-11s %-16s %-7s scan:%s focus:%-5s d=%5.1f" % [
			m.key, m.node.name, _color_name(m.color),
			"Y" if describable.scannable() else "n", focus_state, distance])

	return "\n".join(lines)


## The whole reason this overlay exists: focus builds invisibly and
## silently, so without this there is no way to tell whether a reveal is
## about to fire, stalled, or never started because nothing is in range.
func _focus_line() -> String:
	var best = null
	var best_progress := -1.0
	for m in _markers:
		var f = m.focusable
		if f == null or f.revealed_state:
			continue
		if f.focus_progress > best_progress:
			best_progress = f.focus_progress
			best = m

	if best == null:
		var total := 0
		for m in _markers:
			if m.focusable != null:
				total += 1
		if total == 0:
			return "FOCUS: no focusable objects in scene"
		return "FOCUS: all revealed"

	var f = best.focusable
	var distance: float = GameState.head_position.distance_to(best.node.global_position)
	var in_range: bool = distance <= f.activation_radius
	var why: String = "building" if in_range else "OUT OF RANGE (%.1f > %.1f)" % [distance, f.activation_radius]
	return "FOCUS: %s %3.0f%%  %s" % [best.key, best_progress * 100.0, why]


func _color_name(c: Color) -> String:
	if c == CONTINUOUS_COLOR:
		return "teal-bar"
	for name in ["RED", "BLUE", "YELLOW", "PURPLE", "GREEN", "ORANGE", "CYAN", "WHITE"]:
		if c == Color(name.to_lower()):
			return name
	return "?"
