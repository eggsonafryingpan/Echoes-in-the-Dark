extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const WallContactSound := preload("res://scripts/wall_contact_sound.gd")

var isLocked: bool = false
var isColliding: bool = false
## The head (§6.1): its rotation is GameState.orientation, set every physics
## frame below -- never mouse, never the body's own transform. The body
## (this CharacterBody3D) never rotates on its own; joystick input moves it
## relative to pivot's facing instead.
@onready var pivot: Node3D = $CamOrigin
@onready var wall_audio: RaytracedAudioPlayer3D = $WallAudio
@onready var footsteps: AudioStreamPlayer3D = $FootSteps
@onready var listener: AudioListener3D = $CamOrigin/Camera3D/RaytracedAudioListener
@export var collision_ray_num: int = 10
@export var collision_dist: int = 4

## Wall contact comes from move_and_slide's own collisions, not the ray
## ring below (see _update_wall_contact). A collision counts as a wall when
## its normal is at most this far from horizontal (|normal.y|).
@export var wall_max_normal_y: float = 0.7
## ...and as *pushing* into it when the joystick direction points into the
## wall at least this much (dot with -normal). Lower and grazing a wall
## while walking past it starts the sound; higher and walking into it at an
## angle doesn't.
@export var wall_push_min_dot: float = 0.3
## Contact has to be absent this long before it ends. move_and_slide can
## miss a frame of contact against the cave's trimesh; without this the
## sound would stop and restart, which is its own stutter.
@export var wall_release_seconds: float = 0.12

## Playtest aid (F8): draw the wall-detection ray ring and the live contact
## in the 3D view. See _draw_wall_debug.
@export var debug_draw_wall_rays: bool = true

## Unset until level design places a real objective in this scene (Phase 10,
## §10.1). Without it, distance-to-objective is never reported, so
## OverloadDetector's no-progress signal simply never contributes --
## collisions/confinement still work, matching the old Stuck fail-safe.
@export var exit_marker: Node3D

## This scene's calibration: the physical player's real-world heading at
## boot is arbitrary, so this aligns GameState's yaw=0 with "forward into
## the level" for this spawn point (GameState.effective_orientation()).
## Tune per scene/spawn -- there is no single correct value.
@export var spawn_yaw_offset: float = 0.0
#@onready var cave_generator = $"../CaveGenerater/CSGCombiner3D/CSGBox3D"
var _wall_contact: bool = false
var _wall_release_left: float = 0.0
var _wall_contact_point: Vector3 = Vector3.ZERO
var _wall_contact_normal: Vector3 = Vector3.ZERO
var _wall_contact_sound: Node3D = null
var _wall_debug_mesh: ImmediateMesh = null
var _wall_debug_instance: MeshInstance3D = null

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


#func _on_terrain_loaded():
	#isLocked = false

func _ready():
	#cave_generator.terrain_loaded.connect(_on_terrain_loaded)
	# pivot is a position anchor only here -- AudioDirector drives the
	# listener's rotation from GameState.orientation directly, never from
	# pivot's own transform (CLAUDE_CODE_BRIEF.md §13 Phase 2).
	AudioDirector.register_listener(listener, pivot)
	GameState.yaw_offset = spawn_yaw_offset
	# Scan bearings are measured from the head, not the body -- pivot is
	# exactly that now that its rotation is GameState.orientation. Bat's
	# _unhandled_input listens for "bat_scan" and forwards to BatCompanion,
	# which owns the scan since Phase 6; this is the only wiring this scene
	# needs (ported from sophias_cave.tscn's player_bat_test.gd).
	BatCompanion.head = pivot

	_wall_contact_sound = WallContactSound.new()
	_wall_contact_sound.name = "WallContactSound"
	add_child(_wall_contact_sound)
	_setup_wall_debug()

	# Capturing the OS cursor is this scene's call, not DevMouseSource's --
	# main_menu.tscn never runs this script, so the menu stays fully
	# clickable regardless of which SensorBridge.source_mode is active.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_wall_rays"):
		debug_draw_wall_rays = not debug_draw_wall_rays
		_wall_debug_instance.visible = debug_draw_wall_rays
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


var prev_norm = null
func _physics_process(delta: float) -> void:
	if isLocked or GameState.input_locked:
		_end_wall_contact()
		return

	# Head orientation is GameState.orientation alone (mock trace or live
	# IMU) -- never mouse, never the body's transform (§6.1, §13 Phase-2
	# follow-up). pivot.rotation is set purely for the camera view and the
	# raycasts nested under it; movement below reads GameState directly
	# rather than pivot's transform, so there's exactly one source of truth.
	pivot.rotation = GameState.effective_orientation()
	var facing := Basis.from_euler(Vector3(0.0, GameState.effective_orientation().y, 0.0))
	GameState.report_head_position(pivot.global_position)

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

	# OverloadDetector's behavioral half reads these off GameState (§13
	# Phase 3, migrated from "Stuck") -- confinement/collisions work
	# regardless; no-progress only contributes once exit_marker is set.
	GameState.report_position(global_position)
	if exit_marker != null:
		GameState.report_distance_to_objective(global_position.distance_to(exit_marker.global_position))


	
	
	move_and_slide()
	
	if velocity.length() == 0 or not is_on_floor():
		footsteps.set_stream_paused(true)
	else:
		footsteps.set_stream_paused(false)
	
	_update_wall_contact(direction, delta)

	# The ray ring places WallAudio, the proximity drone that tells the
	# player a wall is *near*. Touching one is _update_wall_contact's job.
	var head_pos = global_position + Vector3(0,1.5,0)
	var closest_dir = null
	var ray_debug: Array = []  # [from, end, hit?]
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
		if !result or result.collider.name != "CaveBody":
			ray_debug.append([from, to, false])
			continue
		var hit_vector = result.position - from
		ray_debug.append([from, result.position, true])
		if closest_dir == null or hit_vector.length() < closest_dir.length():
			closest_dir = hit_vector
	if closest_dir != null:
		wall_audio.global_position = head_pos + closest_dir * 0.9
		get_node("/root/World/Test").global_position = wall_audio.global_position

	if debug_draw_wall_rays:
		_draw_wall_debug(ray_debug, closest_dir, head_pos)

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

		
		
	
	


## Pushing against a wall = move_and_slide collided with something near-
## vertical this frame while the joystick points into it. This is the
## physics engine's own answer to "is the capsule touching rock", so it
## agrees with what the player feels: the old ray-ring test measured from
## the capsule's axis at head height with a 0.6 m threshold against a
## 0.55 m capsule radius, so whether a touch registered depended on which
## of ten rays happened to line up with the wall and how the rock was
## shaped at head height rather than where the capsule actually hit.
##
## The sound runs for exactly as long as the contact does. Only the start
## of a contact is reported to OverloadDetector -- holding the stick into a
## wall is one collision, not one per frame.
func _update_wall_contact(direction: Vector3, delta: float) -> void:
	var touching := false
	if direction != Vector3.ZERO:
		for i in get_slide_collision_count():
			var collision := get_slide_collision(i)
			var normal := collision.get_normal()
			if absf(normal.y) > wall_max_normal_y:
				continue  # floor or ceiling
			if direction.dot(-normal) < wall_push_min_dot:
				continue  # sliding along it, not into it
			touching = true
			_wall_contact_point = collision.get_position()
			_wall_contact_normal = normal
			break

	if touching:
		_wall_release_left = wall_release_seconds
		_wall_contact_sound.global_position = _wall_contact_point
		if not _wall_contact:
			_wall_contact = true
			_wall_contact_sound.start()
			GameState.report_collision()
	elif _wall_contact:
		_wall_release_left -= delta
		if _wall_release_left <= 0.0:
			_end_wall_contact()


func _end_wall_contact() -> void:
	if not _wall_contact:
		return
	_wall_contact = false
	_wall_contact_sound.stop()


func is_touching_wall() -> bool:
	return _wall_contact


## Unshaded, no depth test, world-space: the rays show through the rock
## they are hitting, and the filming black-out (a CanvasLayer) still covers
## them, so nothing leaks into a take.
func _setup_wall_debug() -> void:
	_wall_debug_mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_wall_debug_instance = MeshInstance3D.new()
	_wall_debug_instance.name = "WallRayDebug"
	_wall_debug_instance.mesh = _wall_debug_mesh
	_wall_debug_instance.material_override = material
	_wall_debug_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall_debug_instance.top_level = true  # vertices are world-space
	_wall_debug_instance.visible = debug_draw_wall_rays
	add_child(_wall_debug_instance)


## Key: dim grey = ray that found nothing within collision_dist; yellow =
## ray that hit the cave; red = the nearest hit, which is where WallAudio
## sits; magenta = live wall contact (point plus its normal), i.e. the
## contact sound is playing right now.
func _draw_wall_debug(rays: Array, closest_dir, head_pos: Vector3) -> void:
	_wall_debug_mesh.clear_surfaces()
	_wall_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for ray in rays:
		var color := Color(1.0, 0.85, 0.1) if ray[2] else Color(0.5, 0.5, 0.5, 0.6)
		if ray[2] and closest_dir != null and (ray[1] - head_pos).is_equal_approx(closest_dir):
			color = Color(1.0, 0.15, 0.1)
		_debug_line(ray[0], ray[1], color)
		if ray[2]:
			_debug_cross(ray[1], 0.08, color)
	if _wall_contact:
		var magenta := Color(1.0, 0.1, 1.0)
		_debug_cross(_wall_contact_point, 0.25, magenta)
		_debug_line(_wall_contact_point, _wall_contact_point + _wall_contact_normal * 0.8, magenta)
	_wall_debug_mesh.surface_end()


func _debug_line(a: Vector3, b: Vector3, color: Color) -> void:
	_wall_debug_mesh.surface_set_color(color)
	_wall_debug_mesh.surface_add_vertex(a)
	_wall_debug_mesh.surface_set_color(color)
	_wall_debug_mesh.surface_add_vertex(b)


func _debug_cross(p: Vector3, r: float, color: Color) -> void:
	_debug_line(p - Vector3(r, 0, 0), p + Vector3(r, 0, 0), color)
	_debug_line(p - Vector3(0, r, 0), p + Vector3(0, r, 0), color)
	_debug_line(p - Vector3(0, 0, r), p + Vector3(0, 0, r), color)
