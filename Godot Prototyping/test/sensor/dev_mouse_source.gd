class_name DevMouseSource
extends SensorSource

## Mouse-driven stand-in for the EmotiBit (brief CLAUDE_CODE_BRIEF.md §3.5's
## mock-first philosophy, extended to orientation-as-input testing that
## MockSource's scripted traces were never meant for -- those traces exist
## to test CALM/FOCUS/Stuck against a known, repeatable HR+orientation
## script, not to be freely steered during a playtest. Using them as the
## default orientation source made forward movement curve on its own, since
## direction is recomputed from GameState.orientation every physics frame
## and the traces' own head-jitter keyframes have nothing to do with where
## a tester is trying to walk.
##
## Turns mouse motion into (pitch, yaw, roll) like any other SensorSource,
## so SensorBridge/GameState/AudioDirector don't know or care this isn't a
## real sensor.
##
## Does not manage Input.mouse_mode itself -- that's the gameplay scene's
## call (player.gd), since this source has no idea whether a menu or some
## other UI currently wants the cursor free. Motion only accumulates while
## the mouse is already captured, so this is inert until a scene decides
## to capture it.

@export var mouse_sensitivity: float = 0.003
@export var pitch_limit_deg: float = 80.0

var _yaw: float = 0.0
var _pitch: float = 0.0


func start() -> void:
	set_process_input(true)
	set_process(true)


func stop() -> void:
	set_process_input(false)
	set_process(false)


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_yaw -= event.relative.x * mouse_sensitivity
	_pitch -= event.relative.y * mouse_sensitivity
	_pitch = clampf(_pitch, deg_to_rad(-pitch_limit_deg), deg_to_rad(pitch_limit_deg))


func _process(_delta: float) -> void:
	orientation_sample.emit(Vector3(_pitch, _yaw, 0.0))
	# Constant plausible resting rate rather than nothing, so HR-dependent
	# systems (CALM, OverloadDetector) being built alongside navigation
	# don't just silently stall while this source is active.
	heart_rate_sample.emit(70.0, true)
