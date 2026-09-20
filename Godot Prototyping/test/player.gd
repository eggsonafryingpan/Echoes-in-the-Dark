extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

var isLocked: bool = false
var isColliding: bool = false
## The head (§6.1): its rotation is GameState.orientation, set every physics
## frame below -- never mouse, never the body's own transform. The body
## (this CharacterBody3D) never rotates on its own; joystick input moves it
## relative to pivot's facing instead.
@onready var pivot: Node3D = $CamOrigin
@onready var wall_audio: RaytracedAudioPlayer3D = $WallAudio
@onready var hit_audio: RaytracedAudioPlayer3D = $HitAudio
@onready var footsteps: AudioStreamPlayer3D = $FootSteps
@onready var listener: AudioListener3D = $CamOrigin/Camera3D/RaytracedAudioListener
@export var collision_ray_num: int = 10
@export var collision_dist: int = 4

## Unset until level design places a real objective in this scene (Phase 10,
## §10.1). Stuck detection is off with no exit_marker assigned, same
## fail-safe sophias_cave.tscn's player_bat_test.gd used -- scanning and
## movement work either way, ported here so the ladder is ready the moment
## a marker exists.
@export var exit_marker: Node3D
#@onready var cave_generator = $"../CaveGenerater/CSGCombiner3D/CSGBox3D"
var isTouching: bool = false

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


#func _on_terrain_loaded():
	#isLocked = false

func _ready():
	#cave_generator.terrain_loaded.connect(_on_terrain_loaded)
	# pivot is a position anchor only here -- AudioDirector drives the
	# listener's rotation from GameState.orientation directly, never from
	# pivot's own transform (CLAUDE_CODE_BRIEF.md §13 Phase 2).
	AudioDirector.register_listener(listener, pivot)
	# Bearings are computed from the head, not the body (scripts/bat.gd) --
	# pivot is exactly that now that its rotation is GameState.orientation.
	# Bat's own _unhandled_input already listens for "bat_scan"; this is the
	# only wiring this scene needs (ported from sophias_cave.tscn's
	# player_bat_test.gd).
	Bat.head = pivot

	if exit_marker != null:
		Stuck.configure(self, exit_marker)
		Stuck.became_stuck.connect(_on_stuck)
	else:
		push_warning("No exit_marker assigned. Stuck detection is off, scanning still works.")


## Each rung gives strictly more than the last (ported from
## scripts/player_bat_test.gd). Whether the player should be TOLD they've
## been flagged is a question for testers, not for you.
func _on_stuck(level: int) -> void:
	match level:
		1:
			Bat.say("Wait. Listen for a moment.", "hint_1")
		2:
			var hour: int = Bat.clock_to(exit_marker.global_position)
			Bat.say("The music is %s." % Bat.clock_word(hour), "hint_2")
		3:
			Bat.scan("hint_3")


var prev_norm = null
func _physics_process(delta: float) -> void:
	if isLocked:
		return

	# Head orientation is GameState.orientation alone (mock trace or live
	# IMU) -- never mouse, never the body's transform (§6.1, §13 Phase-2
	# follow-up). pivot.rotation is set purely for the camera view and the
	# raycasts nested under it; movement below reads GameState directly
	# rather than pivot's transform, so there's exactly one source of truth.
	pivot.rotation = GameState.orientation
	var facing := Basis.from_euler(Vector3(0.0, GameState.orientation.y, 0.0))

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("quit"):
		get_tree().quit()

	# Joystick moves relative to where the head faces (yaw only -- looking
	# up/down must not change translation, §6.1); the body never rotates on
	# its own.
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (facing * Vector3(input_dir.x, 0, input_dir.y)).normalized()
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
	var head_pos = global_position + Vector3(0,1.5,0)
	for i in range(collision_ray_num):
		var step = deg_to_rad(360*(i/float(collision_ray_num)))
		var ray_dir = Vector3(
			sin(step),
			0,
			cos(step)
		)

		var from = head_pos
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
		wall_audio.global_position = head_pos + closest_dir * 0.9
		if closest_dir.length() < 0.6:
			if isTouching == false:
				if closest_dir.dot(-facing.z) > 0.4:
					isTouching = true
					hit_audio.global_position = head_pos + closest_dir * 0.9
					hit_audio.play()
					Stuck.report_collision()
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

		
		
	
	
