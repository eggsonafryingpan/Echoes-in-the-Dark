extends MeshInstance3D

var array_mesh: ArrayMesh

@export var reload := false :
	set(new_reload):
		reload = false
		regenerate_mesh()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	regenerate_mesh()


func regenerate_mesh() -> void:
	if !array_mesh:
		array_mesh = ArrayMesh.new()
		mesh = array_mesh
	array_mesh.clear_surfaces()
	var surface_array := create_triangle()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)

func create_triangle() -> Array:
	var surface_array: Array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	
	var positions:= PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	
	positions = [
		Vector3(0,0,0), Vector3(1,0,0), Vector3(1,0,1)
	]
	
	normals = [
		Vector3.UP,Vector3.UP,Vector3.UP
	]
	
	indices = [
		0,1,2
	]
	surface_array[Mesh.ARRAY_VERTEX] = positions
	surface_array[Mesh.ARRAY_NORMAL] = normals
	surface_array[Mesh.ARRAY_INDEX] = indices
	
	return surface_array



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
