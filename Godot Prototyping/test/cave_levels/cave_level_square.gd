extends MeshInstance3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var mesh: ArrayMesh = $MeshInstance3D.mesh
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)

	var array_mesh := st.commit()

	ResourceSaver.save(array_mesh, "res://exported_mesh.res")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
