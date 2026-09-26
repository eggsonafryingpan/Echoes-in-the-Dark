extends CanvasLayer

## Black-out for filming the demo (§11, Phase 9). The game is audio-only,
## so the recorded play view should show nothing at all -- but the same
## session needs the 3D scene visible for the aerial backend camera. F2
## switches between the two without interrupting play.
##
## Sits above every other CanvasLayer, including the audio debug readout,
## so a black take is genuinely black rather than black-with-diagnostics.
##
## MOUSE_FILTER_IGNORE is set once and never toggled with visibility. A
## full-rect Control on a high CanvasLayer is precisely the thing that
## silently swallows every click in a scene, and a filming aid that broke
## input would be discovered mid-shoot. Ignoring the mouse always, in both
## states, means this can never be that bug.

const TOGGLE_ACTION := &"toggle_filming_overlay"

## Above AudioDebugOverlay (50).
@export var overlay_layer: int = 100

## Off by default: launching into a black screen looks like a crash. The
## operator turns it on for the take.
@export var start_black: bool = false

var _rect: ColorRect = null


func _ready() -> void:
	layer = overlay_layer
	_rect = ColorRect.new()
	_rect.name = "Black"
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.visible = start_black
	add_child(_rect)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		_rect.visible = not _rect.visible
		get_viewport().set_input_as_handled()
