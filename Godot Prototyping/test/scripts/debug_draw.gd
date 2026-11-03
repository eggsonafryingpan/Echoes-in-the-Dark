class_name DebugDraw
extends RefCounted

## Playtest placeholders for the escape level: plain shapes and floating
## labels so autopilot shows what each event is doing. Unshaded and
## emissive-bright so they read in the dark cave and from the aerial camera;
## labels ignore depth so rock never hides them. In the 3D world, so the
## filming black-out (a CanvasLayer) still covers all of it.


## Render layer for playtest visuals. The first-person camera sees every layer;
## the reveal view (reveal_view.gd) leaves this one out.
const LAYER := 1 << 19


static func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func label(parent: Node3D, text: String, offset: Vector3, color: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.name = "DebugLabel"
	l.text = text
	l.position = offset
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0012
	l.font_size = 40
	l.outline_size = 10
	l.layers = LAYER
	parent.add_child(l)
	return l


static func sphere(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var mi := MeshInstance3D.new()
	mi.name = "DebugSphere"
	mi.layers = LAYER
	mi.mesh = mesh
	mi.material_override = material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A thin vertical post with a label on top: checkpoints, the fork, the exit.
static func post(parent: Node3D, color: Color, text: String, height: float = 3.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.12
	mesh.height = height
	var mi := MeshInstance3D.new()
	mi.name = "DebugPost"
	mi.layers = LAYER
	mi.mesh = mesh
	mi.position.y = height * 0.5
	mi.material_override = material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	label(parent, text, Vector3.UP * (height + 0.4), color)


## A flat disc on the floor: where a rock is about to land.
static func disc(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.04
	var mi := MeshInstance3D.new()
	mi.layers = LAYER
	mi.name = "DebugDisc"
	mi.mesh = mesh
	mi.position.y = 0.05
	mi.material_override = material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
