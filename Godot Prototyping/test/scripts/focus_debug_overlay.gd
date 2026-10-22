extends CanvasLayer

## Playtest readout of FOCUS, bottom-right: the counterpart to the heart
## rate graph (hr_debug_overlay.gd) for the other held mechanic. Shows the
## focused source's volume climbing as focus builds -- a level meter for
## where it is now and a rolling graph for how it got there -- so a sighted
## observer can see the same rise the player is hearing. F5 toggles it.
##
## The graph's dB scale is fixed to the target's own min..max range rather
## than auto-fitted, so "louder" always reads as "higher" and a full meter
## always means the reveal is about to land.
##
## Tracks the nearest in-range Focusable that has not been revealed yet,
## and keeps showing the last one after its reveal so the settle is visible
## too. Read-only: everything here comes from Focusable.focus_readout().
##
## Below the filming black-out (100) like every other readout, so nothing
## here can leak into a take.

const TOGGLE_ACTION := &"debug_focus_readout"

@export var overlay_layer: int = 55
@export var enabled: bool = true
## Seconds of history the graph spans.
@export var history_seconds: float = 30.0
@export var sample_interval: float = 0.1

const COLOR_VOLUME := Color(0.35, 0.8, 1.0)
const COLOR_ON_TARGET := Color(0.4, 1.0, 0.5)
const COLOR_OFF_TARGET := Color(1.0, 0.85, 0.3)
const COLOR_DIM := Color(1, 1, 1, 0.7)

const PANEL_SIZE := Vector2(420, 200)
const METER_WIDTH := 26.0
const METER_GAP := 10.0

var _panel: Control = null
var _label: Label = null
var _graph: Control = null
var _volume: Array[float] = []  # NAN = nothing tracked at that instant
var _target: Focusable = null
var _t_sample: float = 0.0


func _ready() -> void:
	layer = overlay_layer

	_panel = Control.new()
	_panel.name = "Focus"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_SIZE.x - 14
	_panel.offset_right = -14
	_panel.offset_top = -PANEL_SIZE.y - 14
	_panel.offset_bottom = -14
	add_child(_panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"font_size", 18)
	_label.add_theme_color_override(&"font_color", Color.WHITE)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	_panel.add_child(_label)

	_graph = Control.new()
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph.position = Vector2(0, 80)
	_graph.size = Vector2(PANEL_SIZE.x, 120)
	_graph.draw.connect(_draw_graph)
	_panel.add_child(_graph)

	_panel.visible = enabled


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		enabled = not enabled
		_panel.visible = enabled
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_target = _pick_target()
	var readout: Dictionary = _target.focus_readout() if _target != null else {}

	_t_sample += delta
	if _t_sample >= sample_interval:
		_t_sample = 0.0
		_volume.append(readout.volume_db if _tracking(readout) else NAN)
		if _volume.size() > int(history_seconds / sample_interval):
			_volume.pop_front()

	if not enabled:
		return
	_label.text = _readout(readout)
	_graph.queue_redraw()


## Nearest unrevealed Focusable in range; failing that, whichever was being
## shown already, so a reveal does not blank the panel the moment it lands.
func _pick_target() -> Focusable:
	var best: Focusable = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(&"focusable"):
		var f := node as Focusable
		if f == null or f.revealed_state:
			continue
		var dist: float = f.global_position.distance_to(GameState.head_position)
		if dist <= f.activation_radius and dist < best_dist:
			best = f
			best_dist = dist
	if best != null:
		return best
	return _target if is_instance_valid(_target) else null


## Whether there is a level worth plotting: focus is building, or it has
## already paid off.
func _tracking(readout: Dictionary) -> bool:
	return not readout.is_empty() and (readout.in_range or readout.revealed)


func _readout(readout: Dictionary) -> String:
	if not _tracking(readout):
		return "FOCUS   nothing in range   [F5]"

	var lines: Array[String] = []
	if readout.revealed:
		lines.append("FOCUS   REVEALED: %s   [F5]" % readout.label)
		lines.append("volume %+.1f dB   settled, now a known source" % readout.volume_db)
		return "\n".join(lines)

	lines.append("FOCUS %3.0f%%   %s   [F5]" % [
		readout.progress * 100.0,
		"ON TARGET, building" if readout.aligned else "off target, decaying",
	])
	lines.append("volume %+.1f dB   (%+.0f quiet to %+.0f at reveal)" % [
		readout.volume_db, readout.min_volume_db, readout.max_volume_db,
	])
	lines.append("%.0f° off, cone %.0f°   auto-reveal in %.0fs" % [
		readout.angle_deg, readout.cone_deg,
		maxf(readout.fail_forward_seconds - readout.t, 0.0),
	])
	return "\n".join(lines)


func _draw_graph() -> void:
	var size := _graph.size
	var plot := Rect2(Vector2.ZERO, Vector2(size.x - METER_WIDTH - METER_GAP, size.y))
	var meter := Rect2(Vector2(size.x - METER_WIDTH, 0), Vector2(METER_WIDTH, size.y))
	_graph.draw_rect(plot, Color(0, 0, 0, 0.55))
	_graph.draw_rect(meter, Color(0, 0, 0, 0.55))

	var font := ThemeDB.fallback_font
	var readout: Dictionary = _target.focus_readout() if _target != null else {}
	if readout.is_empty():
		_graph.draw_string(font, Vector2(8, 20), "no focus target nearby",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_DIM)
		return

	var lo: float = readout.min_volume_db
	var hi: float = readout.max_volume_db
	var color := COLOR_ON_TARGET if (readout.aligned or readout.revealed) else COLOR_OFF_TARGET

	# Level meter: fills bottom-up with the current volume, in the colour
	# that says whether it is currently climbing or falling back.
	if _tracking(readout):
		var fill: float = clampf((readout.volume_db - lo) / (hi - lo), 0.0, 1.0)
		_graph.draw_rect(Rect2(meter.position + Vector2(0, meter.size.y * (1.0 - fill)),
				Vector2(meter.size.x, meter.size.y * fill)), color)
	_graph.draw_rect(meter, COLOR_DIM, false, 1.0)

	_plot(plot, lo, hi)

	_graph.draw_string(font, Vector2(4, 14), "%+.0f dB" % hi, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_DIM)
	_graph.draw_string(font, Vector2(4, size.y - 4), "%+.0f dB" % lo, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_DIM)
	_graph.draw_string(font, Vector2(plot.size.x - 96, 14), "source volume",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_VOLUME)


## Volume history, right-aligned (newest at the right edge), breaking the
## line wherever nothing was tracked rather than bridging the gap.
func _plot(plot: Rect2, lo: float, hi: float) -> void:
	var cap := int(history_seconds / sample_interval)
	var offset := cap - _volume.size()
	var run := PackedVector2Array()
	for i in _volume.size():
		var v := _volume[i]
		if is_nan(v):
			if run.size() >= 2:
				_graph.draw_polyline(run, COLOR_VOLUME, 2.0, true)
			run = PackedVector2Array()
			continue
		var x := plot.size.x * float(offset + i) / float(maxi(cap - 1, 1))
		var y := plot.size.y * (1.0 - clampf((v - lo) / (hi - lo), 0.0, 1.0))
		run.append(Vector2(x, y))
	if run.size() >= 2:
		_graph.draw_polyline(run, COLOR_VOLUME, 2.0, true)
