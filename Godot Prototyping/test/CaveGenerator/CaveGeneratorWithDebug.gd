extends Node3D

# This script contains the full suite of tools to visualize the cave generation
# It also contains the raw script I preferred to use with my testing.
# It has some experimental or redundant functions and sections.

@export
var voxel_terrain : VoxelTerrain

@onready
var voxel_tool : VoxelTool = voxel_terrain.get_voxel_tool()

@export
var generation_start_marker : Marker3D

@export
var show_walker : bool = true

@onready
var current_walker : Node3D = $CurrentWalker

@export
var random_walk_length : int = 100

@export
var removal_size : float = 2.0

@export
var display_speed : float = 0.1

@export
var ceiling_thickness_m : int = 5

@onready
var crystal_preload : PackedScene = preload("res://CaveAdditions/Crystal/Crystal.tscn")

@onready
var rock_preload : PackedScene = preload("res://CaveAdditions/Rocks/Rock1.tscn")

@export
var do_wall_decoration_step : bool = true

@export
var do_voxel_addition : bool = true

var random_walk_positions : Array[Vector3] = []



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	if show_walker:
		current_walker.show()
	
	setup()
	#await get_tree().physics_frame
	#random_walk()

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("cave_gen"):
		random_walk()


func setup():
	current_walker.transform = generation_start_marker.transform

func random_walk():
	
	for i in range(random_walk_length):
		
		# Move the random walker to the new position:
		current_walker.global_position += get_random_direction()
		
		current_walker.global_position.y = clampf(current_walker.global_position.y, -1000, voxel_terrain.generator.height - ceiling_thickness_m)
		
		# Only store half the random walk positions
		if i % 2 == 0:
			random_walk_positions.append(current_walker.global_position)
		
		if display_speed > 0:
			await get_tree().create_timer(display_speed).timeout
		
		# Carve out a chunk
		
		do_sphere_removal()
		
		if do_voxel_addition:
			var wall_point = get_random_wall_point()
			if wall_point:
				$CurrentWalker/DebugRaycast.look_at(wall_point)
				do_sphere_addition(true, wall_point)

	if do_wall_decoration_step:
		wall_additions_pass()

func wall_additions_pass():
	
	for walk_position : Vector3 in random_walk_positions:
		
		if display_speed > 0:
			await get_tree().create_timer(display_speed).timeout
		
		
		var raycast_result : VoxelRaycastResult = voxel_tool.raycast(walk_position, get_random_direction(true), 20)
		
		# Visualize the raycast.
		$CurrentWalker.global_position = walk_position
		
		if raycast_result:
			
			#Visualize the raycast pt2
			$CurrentWalker/DebugRaycast.look_at(raycast_result.position)
			
			# Create new crystal
			var new_instance : Node3D = [crystal_preload].pick_random().instantiate()
			#var new_crystal_instance : Node3D = crystal_preload.instantiate()
			self.add_child(new_instance)
						
			new_instance.global_position = raycast_result.position
			new_instance.scale = new_instance.scale * randf_range(1, 2.0)
			new_instance.look_at(new_instance.global_position + raycast_result.normal)

# Removal size returns the removal size with a small randomization
# Currently that is removal size =- removal_size * 0.25
func get_removal_size(variance : float = 1):
	
	return removal_size + randf_range(-removal_size * variance, removal_size * variance)

#func do_sphere_smoothing():
	#voxel_tool.mode = VoxelTool.MODE_REMOVE
	#
	#voxel_tool.smooth_sphere($CurrentWalker.global_position, removal_size * 2, 2)

func get_random_wall_point():
	
	var raycast_result : VoxelRaycastResult = voxel_tool.raycast($CurrentWalker.global_position, get_random_direction(true), 20)

	if raycast_result:
		return raycast_result.position
	else:
		return null
	
func do_sphere_removal():
	voxel_tool.mode = VoxelTool.MODE_REMOVE
	
	voxel_tool.do_sphere($CurrentWalker.global_position, get_removal_size())

func do_sphere_addition(at_point : bool = false, global_point : Vector3 = Vector3.ZERO):
	voxel_tool.mode = VoxelTool.MODE_ADD
	
	if at_point:
		voxel_tool.do_sphere(global_point, get_removal_size(2) / 2)
	else:
		voxel_tool.do_sphere($CurrentWalker.global_position, get_removal_size(2) / 2)

#func add_hard_surface():
	#voxel_tool.mode = VoxelTool.MODE_ADD
#
	#var box_removal_vector : Vector3i = Vector3i(get_removal_size(), get_removal_size(), get_removal_size())
	#
	#$BoxEndHelper.global_position = Vector3i($CurrentWalker.global_position) + box_removal_vector
	#
	#voxel_tool.do_box($CurrentWalker.global_position, Vector3i($CurrentWalker.global_position) + box_removal_vector)

#func do_box_removal():
	#voxel_tool.mode = VoxelTool.MODE_REMOVE
	#
	#var box_removal_vector : Vector3i = Vector3i(get_removal_size(), get_removal_size(), get_removal_size())
	#
	#$BoxEndHelper.global_position = Vector3i($CurrentWalker.global_position) + box_removal_vector * 3
	#
	#voxel_tool.do_box($CurrentWalker.global_position, Vector3i($CurrentWalker.global_position) + box_removal_vector)

func get_random_direction(use_float : bool = false):
	
	var direction_vector : Vector3
	
	# Omniderectional with float
	if use_float:
		direction_vector = Vector3(randf_range(-1,1),randf_range(-1,1),randf_range(-1,1))
	else:
		# 9 directions with int
		direction_vector = Vector3([-1,0,1].pick_random(),[-1,0,1].pick_random(),[-1,0,1].pick_random())
	
	var vector_with_magnitude : Vector3 = direction_vector * removal_size
	
	return direction_vector
