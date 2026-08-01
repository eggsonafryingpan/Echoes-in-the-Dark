extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

var isLocked: bool = false
var isColliding: bool = false
@onready var pivot = $CamOrigin
@export var sens: int = 1
@onready var wall_audio: AudioStreamPlayer3D = $WallAudio
@onready var hit_audio: AudioStreamPlayer3D = $HitAudio
@onready var footsteps: AudioStreamPlayer3D = $FootSteps
@export var collision_ray_num: int = 20
@export var collision_dist: int = 4
#@onready var cave_generator = $"../CaveGenerater/CSGCombiner3D/CSGBox3D"
var isTouching: bool = false

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


#func _on_terrain_loaded():
	#isLocked = false

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	#cave_generator.terrain_loaded.connect(_on_terrain_loaded)

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * sens))
		pivot.rotate_x(deg_to_rad(-event.relative.y * sens))
		pivot.rotation.x = clamp(pivot.rotation.x, deg_to_rad(-90),deg_to_rad(45))
		
var prev_norm = null
func _physics_process(delta: float) -> void:
	if isLocked:
		return
	
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)


	
	
	move_and_slide()
	
	if velocity.length() == 0 or not is_on_floor():
		footsteps.set_stream_paused(true)
	else:
		footsteps.set_stream_paused(false)
	
	var raycasts = []
	var head = global_position + Vector3(0,1.5,0)
	for i in range(collision_ray_num):
		var step = deg_to_rad(360*(i/float(collision_ray_num)))
		var ray_dir = Vector3(
			sin(step),
			0,
			cos(step)
		)
		
		var from = head
		var to = from + ray_dir * collision_dist
		
		var query = PhysicsRayQueryParameters3D.create(from,to)
		query.exclude = [self]
		var result = get_world_3d().direct_space_state.intersect_ray(query)
		if !result:
			continue
		if result.collider.name != "CaveBody":
			continue
		var hit = result.position
		var hit_vector = hit - from
		raycasts.append(hit_vector)
	if !raycasts.is_empty():
		var closest_dir = raycasts.reduce(func(acc,curr): return curr if curr.length() < acc.length() else acc,raycasts[0])
		wall_audio.global_position = head + closest_dir * 0.9
		if closest_dir.length() < 0.6:
			if isTouching == false:
				#Only plays when hit from front
				if closest_dir.dot(-global_transform.basis.z) > 1:
					isTouching = true
					hit_audio.global_position = head + closest_dir * 0.9
					hit_audio.play()
		elif closest_dir.length() > 0.7:
			isTouching = false
		#if closest_dir.dot(-global_transform.basis.z) < 1:
			#print("side")
			#wall_audio.volume_db = -20
		#else:
			#print("forward")
			#wall_audio.volume_db = 0
	
		get_node("/root/World/Test").global_position = wall_audio.global_position
		#print(-80 * pow(closest_dir.length()/float(collision_dist),2))
		#wall_audio.volume_db = -40 * closest_dir.length()/float(collision_dist)
	
		
	
	#
	#for i in range(get_slide_collision_count()):
		#var collision = get_slide_collision(i)
		#var norm = collision.get_normal()
		#var pos = collision.get_position()
		#
		#if norm.dot(Vector3.UP) > 0.7:
			#continue
		#if prev_norm != null and prev_norm.dot(norm) < 0.5:
			#wall_audio.global_position = global_position
			#wall_audio.play()
			#print("SOUNDOUSNDOSUNDS")
		#
		##if new collision already handled 
		##if !touching.reduce(func(a,b): return a and b.dot(norm) < 0.2,true):
			##if true:
				##
		#print(prev_norm, "jsfldksj")
		#prev_norm = norm
		#print(norm)
		##touching.append(norm)
		##var colDirection = (pos - global_position)
		##print(get_slide_collision_count())
		#

		
		
	
	
