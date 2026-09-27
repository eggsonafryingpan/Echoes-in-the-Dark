extends Node3D

## Playtest aid: a brief flash in the 3D world at every object a scan
## returns, timed to the moment its ping starts (BatCompanion.return_pinged),
## so a sighted tester can confirm the scan found something even when the
## ping itself is not yet audible. F9 toggles it; on by default because it
## exists for exactly the sessions where the audio is in doubt.
##
## Each flash is a sphere plus a tall vertical beam so it reads from the
## aerial TopDownCamera as well as first person. No depth test, so rock and
## ceiling never hide it. Lives in the 3D world, so the filming black-out
## (a CanvasLayer) still covers it -- nothing leaks into a black take.

const TOGGLE_ACTION := &"debug_scan_markers"

@export var enabled: bool = true
@export var color: Color = Color(1.0, 0.1, 0.9)
@export var flash_seconds: float = 1.5
@export var sphere_radius: float = 1.0
@export var beam_height: float = 25.0


func _ready() -> void:
	BatCompanion.return_pinged.connect(_on_return_pinged)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		enabled = not enabled
		print("Scan ping markers: %s" % ("on" if enabled else "off"))
		get_viewport().set_input_as_handled()


func _on_return_pinged(entry: Dictionary) -> void:
	if not enabled:
		return
	var target: Node3D = entry.get("node")
	if not is_instance_valid(target):
		return

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = color

	var sphere := SphereMesh.new()
	sphere.radius = sphere_radius
	sphere.height = sphere_radius * 2.0
	var beam := CylinderMesh.new()
	beam.top_radius = 0.15
	beam.bottom_radius = 0.15
	beam.height = beam_height

	var marker := Node3D.new()
	add_child(marker)
	marker.global_position = target.global_position
	for mesh in [sphere, beam]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh == beam:
			mi.position.y = beam_height * 0.5
		marker.add_child(mi)

	var tween := marker.create_tween()
	tween.set_parallel()
	tween.tween_property(material, "albedo_color:a", 0.0, flash_seconds)
	tween.tween_property(marker, "scale", Vector3.ONE * 1.6, flash_seconds)
	tween.chain().tween_callback(marker.queue_free)
