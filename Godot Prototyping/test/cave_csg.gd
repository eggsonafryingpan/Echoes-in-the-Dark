extends CSGBox3D

@export
var generation_start_marker : Marker3D

@onready
var CaveGenerator = get_parent().get_parent()

@onready
var CSGCombiner = get_parent()

@onready
var current_walker : Node3D = $CurrentWalker

@export
var random_walk_length : int = 300

@export
var removal_size : float = 2

@export
var ceiling_thickness_m : int = 5

@export
var height : int = 200

@export
var turning_freq = 2

@export
var step_size = 0.8

var random_walk_positions : Array[Vector3] = []

signal terrain_loaded()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	setup()
	await get_tree().create_timer(0.3).timeout
	random_walk()
	

#func _unhandled_input(event: InputEvent) -> void:
	#if Input.is_action_just_pressed("cave_gen"):
		
		

func setup():
	current_walker.transform = generation_start_marker.transform

func random_walk():
	
	var curr_direction = get_random_direction()
	for i in range(random_walk_length):
		
		# Move the random walker to the new position:
		current_walker.global_position += curr_direction * step_size
		if i % turning_freq == 0 :
			curr_direction = get_random_direction() 
		
		# Clamp the height to prevent above ground
		current_walker.global_position.y = clampf(current_walker.global_position.y, -height/2, height/2)
		
		# Store the walk positions
		random_walk_positions.append(current_walker.global_position)
		
		# Carve out a chunk at our current position
		do_sphere_removal()
		
		# Get a random position on the wall, and add geometry there if valid
		#var wall_point = get_random_wall_point()
		#if wall_point:
			#do_sphere_addition(wall_point)

	# Once generation is finished, revisit previous locations and add things on the wall.
	#wall_additions_pass()
	_export()
	await get_tree().create_timer(0.5).timeout
	terrain_loaded.emit()


# Removal size returns the removal size with a small randomization
# Currently that is removal size =- removal_size * 0.25
func get_removal_size(variance : float = 0.25):
	return removal_size + randf_range(-removal_size * variance, removal_size * variance)

	
func do_sphere_removal():
	var sphere = CSGSphere3D.new()
	sphere.radius = get_removal_size()
	sphere.operation = CSGShape3D.OPERATION_SUBTRACTION
	CSGCombiner.add_child(sphere)
	sphere.global_position = $CurrentWalker.global_position
	

func get_random_direction(use_float : bool = false):
	
	var direction_vector : Vector3
	
	# Omniderectional with float
	if use_float:
		direction_vector = Vector3(randf_range(-1,1),0,randf_range(-1,1))
	else:
		# 9 directions with int
		direction_vector = Vector3([-1,0,1].pick_random(),0,[-1,0,1].pick_random())
	
	var vector_with_magnitude : Vector3 = direction_vector * removal_size
	
	return direction_vector





func _export():
	await get_tree().create_timer(0.5).timeout
	var meshes = CSGCombiner.get_meshes()
	var mesh = meshes[1]
	var transformation = meshes[0]
	print(meshes)
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.transform = transformation
	CaveGenerator.add_child(mesh_instance)
	#
	#var scene = PackedScene.new()
	#scene.pack(mesh_instance)
	#
	#ResourceSaver.save(scene, "res://cave_level.tscn")
