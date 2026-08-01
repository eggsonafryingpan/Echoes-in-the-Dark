extends CharacterBody3D

## Test-scene player for the bat narration prototype.
##
## Scene shape:
##   Player (CharacterBody3D, this script)
##     CollisionShape3D          (capsule)
##     Head (Node3D, y = 1.6)    <- EmotiBit will drive this node's rotation
##       Camera3D
##       AudioListener3D         <- click Make Current. Without this on the
##                                  HEAD, spatial audio won't respond to head
##                                  turns and the core mechanic is dead.
##
## Action names live in the four constants below. They're set to Katie's
## existing names. If any of them are spelled differently in the Input Map,
## change them HERE and nowhere else — and don't rename them in the Input Map,
## because that silently breaks every script of hers that uses them.

const ACT_LEFT := &"left"
const ACT_RIGHT := &"right"
const ACT_FORWARD := &"up"
const ACT_BACK := &"down"
const ACT_SCAN := &"bat_scan"

@export var speed: float = 3.0
@export var exit_marker: Node3D

## Temporary stand-in for the EmotiBit. Delete once the IMU feed is live.
@export var mouse_look: bool = true
@export var mouse_sensitivity: float = 0.003

@onready var head: Node3D = $Head


func _ready() -> void:
	_check_actions()

	Bat.head = head

	if exit_marker != null:
		Stuck.configure(self, exit_marker)
		Stuck.became_stuck.connect(_on_stuck)
	else:
		push_warning("No exit_marker assigned. Stuck detection is off, scanning still works.")

	if mouse_look:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Fails loudly at startup instead of silently at runtime, which is how
## action-name mismatches usually waste an afternoon.
func _check_actions() -> void:
	for action in [ACT_LEFT, ACT_RIGHT, ACT_FORWARD, ACT_BACK, ACT_SCAN]:
		if not InputMap.has_action(action):
			push_error("Input action '%s' does not exist. Check Project Settings > Input Map and fix the constant at the top of this script." % action)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACT_SCAN):
		Bat.scan()
		get_viewport().set_input_as_handled()
		return

	# Replace this block with the EmotiBit yaw feed when the hardware is wired:
	#   head.rotation.y = deg_to_rad(emotibit_yaw)
	if mouse_look and event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			head.rotate_y(-event.relative.x * mouse_sensitivity)

	# Escape to free the mouse, or you can't quit the window.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	var input := Input.get_vector(ACT_LEFT, ACT_RIGHT, ACT_FORWARD, ACT_BACK)

	# The coupling: the joystick moves you relative to where the HEAD faces,
	# and the body never rotates on its own. Look up-left while pushing
	# forward and you walk up-left. This is the thing you're testing.
	var basis := head.global_transform.basis
	var direction := (basis.x * input.x + basis.z * input.y)
	direction.y = 0.0
	direction = direction.normalized()

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	velocity.y -= 9.8 * delta

	move_and_slide()

	# Walls only. Floors and ceilings aren't navigation failures.
	for i in get_slide_collision_count():
		if absf(get_slide_collision(i).get_normal().y) < 0.5:
			Stuck.report_collision()
			break


# --- assistance ladder --------------------------------------------------

## Each rung gives strictly more than the last. Whether the player should be
## TOLD they've been flagged is a question for testers, not for you.
func _on_stuck(level: int) -> void:
	match level:
		1:
			Bat.say("Wait. Listen for a moment.", "hint_1")
		2:
			var hour := Bat.clock_to(exit_marker.global_position)
			Bat.say("The music is %s." % Bat.clock_word(hour), "hint_2")
		3:
			Bat.scan("hint_3")
