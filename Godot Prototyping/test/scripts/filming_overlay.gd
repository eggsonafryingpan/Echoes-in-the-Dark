extends CanvasLayer

## The view modes for filming and observers. F2 cycles, without interrupting
## play:
##
##   NORMAL  the 3D scene (development, and the V aerial reveal)
##   BLACK   View 1: a plain black screen, the real nonvisual play view
##   COLOR   View 2: a colour that follows the player's progress -- dark
##           until the river, blue at the river, fading lighter toward the
##           exit, and fully white as they leave
##
## A visual aid only: it reads the level's progress and changes nothing in
## game logic or audio. In a scene with no escape route (the tutorial, the old
## cave), View 2 just stays at its start colour.
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

# ------------------------------------------------------------------------
# VIEW 2 (COLOUR) CONFIG
# ------------------------------------------------------------------------
@export_group("View 2 colours")
@export var level_path: NodePath = ^".."
## Before the river.
@export var start_color: Color = Color(0.0, 0.0, 0.0)
## Reached at the river's near bank.
@export var river_color: Color = Color(0.08, 0.28, 0.85)
## Reached at the exit; full once the run is over.
@export var exit_color: Color = Color(1.0, 1.0, 1.0)
## Metres before the river over which the blue fades in.
@export var river_fade_in_distance: float = 15.0
## Where the river is, for the blue stop.
@export var river_marker_path: NodePath = ^"../River/NearBank"
## How quickly the screen catches up with the target colour (per second).
## Lower is slower and smoother.
@export var fade_speed: float = 0.8
@export_group("")

enum ViewMode { NORMAL, BLACK, COLOR }
var mode: ViewMode = ViewMode.NORMAL
var _level: Node = null
var _river_s: float = -1.0

var _rect: ColorRect = null


func _ready() -> void:
	layer = overlay_layer
	_rect = ColorRect.new()
	_rect.name = "Black"
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_level = get_node_or_null(level_path)
	set_mode(ViewMode.BLACK if start_black else ViewMode.NORMAL)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		set_mode(((mode + 1) % ViewMode.size()) as ViewMode)
		print("View: %s" % ["normal 3D", "View 1 (black)", "View 2 (colour)"][mode])
		get_viewport().set_input_as_handled()


func set_mode(new_mode: ViewMode) -> void:
	mode = new_mode
	_rect.visible = mode != ViewMode.NORMAL
	if mode == ViewMode.BLACK:
		_rect.color = Color.BLACK
	elif mode == ViewMode.COLOR:
		_rect.color = target_color()


func _process(delta: float) -> void:
	if mode == ViewMode.COLOR:
		_rect.color = _rect.color.lerp(target_color(), 1.0 - exp(-fade_speed * delta))


## The colour for where the player is now along the route.
func target_color() -> Color:
	if _level == null or not _level.has_method("project") or _level.player == null:
		return start_color
	if _level.run_finished:
		return exit_color
	if _river_s < 0.0:
		var river := get_node_or_null(river_marker_path) as Node3D
		if river == null:
			return start_color
		_river_s = _level.project(river.global_position).s
	var s: float = _level.project(_level.player.global_position).s
	if s < _river_s:
		var t := clampf((s - (_river_s - river_fade_in_distance)) / maxf(river_fade_in_distance, 0.01), 0.0, 1.0)
		return start_color.lerp(river_color, t)
	var to_exit := clampf((s - _river_s) / maxf(_level.route_length() - _river_s, 0.01), 0.0, 1.0)
	return river_color.lerp(exit_color, to_exit)
