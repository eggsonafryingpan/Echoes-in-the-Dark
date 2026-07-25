extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

var isLocked: bool = false
var isColliding: bool = false
@onready var pivot = $CamOrigin
@export var sens = 0.5
@onready var hit_audio: SteamAudioPlayer = $HitAudio
#@onready var cave_generator = $"../CaveGenerater/CSGCombiner3D/CSGBox3D"


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
	
	
	
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var norm = collision.get_normal()
		var pos = collision.get_position()
		
		if norm.dot(Vector3.UP) > 0.7:
			continue
		
		
		var colDirection = (pos - global_position)
		var hori_speed = Vector3(velocity.x, 0.0, velocity.z)
		
		if hori_speed > 0.8:
			hit_audio.global_position = global_position + colDirection * 1
			hit_audio.play()
			isColliding = true
			print(colDirection)
		else:
			isColliding = false
		
	
	
