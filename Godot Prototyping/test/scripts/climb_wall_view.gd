extends CanvasLayer

## The final climb's own reveal: a front-on view of the climbing wall for
## sighted observers. Switched in and out with V during the climb (the same
## key as the overhead map, which it stands in for while the climb runs).
##
## Shows, with no text: every hold grabbed this attempt (grey, turning red
## when it crumbles), the swarm's side and height when one is there, and the
## player, with each hand lit while it grips. Drawn in 2D over a full-screen
## backing, so nothing in the 3D scene shows through. Purely visual.

# ------------------------------------------------------------------------
# WALL VIEW CONFIG
# ------------------------------------------------------------------------
@export_group("Wall")
@export var background: Color = Color(0.06, 0.05, 0.07)
@export var wall_color: Color = Color(0.32, 0.29, 0.27)
## Share of the screen the wall takes, wide and tall.
@export var wall_size: Vector2 = Vector2(0.42, 0.86)
@export var top_color: Color = Color(0.75, 0.9, 1.0)

@export_group("Markers")
## Sizes in pixels at 1080p tall.
@export var hold_radius: float = 16.0
@export var hold_color: Color = Color(0.82, 0.8, 0.76)
@export var crumbled_color: Color = Color(0.95, 0.15, 0.15)
@export var swarm_radius: float = 46.0
@export var swarm_color: Color = Color(0.4, 0.9, 0.35, 0.55)
@export var player_radius: float = 22.0
@export var player_color: Color = Color(1.0, 0.85, 0.2)
@export var hand_radius: float = 11.0
@export var gripping_color: Color = Color(1.0, 0.55, 0.1)
@export var free_hand_color: Color = Color(0.5, 0.45, 0.35)
@export var falling_color: Color = Color(1.0, 0.2, 0.2)

@export_group("Screen")
## Operator overlays hidden while this shows, then put back.
@export var hide_while_showing: Array[NodePath] = [
	^"../../AudioDebugOverlay", ^"../../ObjectDebugOverlay", ^"../../HrDebugOverlay",
	^"../../FocusDebugOverlay", ^"../../EventDebugOverlay", ^"../../FilmingOverlay",
]
@export var view_layer: int = 115
@export_group("")

var climb: Node = null
var showing: bool = false
var _canvas: Control = null
var _hidden: Array[CanvasLayer] = []


func _ready() -> void:
	layer = view_layer
	visible = false
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_wall)
	add_child(_canvas)


func set_showing(on: bool) -> void:
	if on == showing:
		return
	showing = on
	visible = on
	if on:
		for path in hide_while_showing:
			var overlay := get_node_or_null(path) as CanvasLayer
			if overlay != null and overlay.visible:
				overlay.visible = false
				_hidden.append(overlay)
	else:
		for overlay in _hidden:
			overlay.visible = true
		_hidden.clear()


func _process(_delta: float) -> void:
	if showing:
		_canvas.queue_redraw()


func _scale() -> float:
	return _canvas.size.y / 1080.0


## The wall's rectangle on screen.
func _wall_rect() -> Rect2:
	var size := _canvas.size * wall_size
	return Rect2((_canvas.size - size) * 0.5, size)


## lateral -1..1 across, height 0 (bottom) .. 1 (top) up.
func _at(lateral: float, height: float) -> Vector2:
	var r := _wall_rect()
	return Vector2(r.position.x + r.size.x * (0.5 + lateral * 0.42),
			r.end.y - r.size.y * (0.04 + height * 0.92))


func _draw_wall() -> void:
	var k := _scale()
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), background)
	var r := _wall_rect()
	_canvas.draw_rect(r, wall_color)
	_canvas.draw_rect(Rect2(r.position, Vector2(r.size.x, 6.0 * k)), top_color)
	if climb == null:
		return

	for hold in climb.holds:
		var c: Color = crumbled_color if hold.crumbled else hold_color
		var at := _at(hold.lateral + 0.12 * hold.side, hold.height)
		_canvas.draw_circle(at, hold_radius * k, c)

	var height: float = clampf(float(climb.progress) / maxf(climb.holds_to_top, 1), 0.0, 1.0)
	if climb.swarm_side != 0:
		var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() / 160.0)
		var at := _at(climb.swarm_side * 1.05, height + 0.04)
		_canvas.draw_circle(at, swarm_radius * k * pulse, swarm_color)
		_canvas.draw_arc(at, swarm_radius * k * pulse, 0.0, TAU, 40, Color(swarm_color, 1.0), 3.0 * k, true)

	var body := _at(climb.lateral, height)
	var falling: bool = climb.state == climb.State.FALLING
	_canvas.draw_circle(body, player_radius * k, falling_color if falling else player_color)
	for side in [climb.LEFT, climb.RIGHT]:
		var hand := body + Vector2(side * player_radius * 1.4 * k, -player_radius * 1.1 * k)
		_canvas.draw_circle(hand, hand_radius * k, gripping_color if climb.held[side] else free_hand_color)
