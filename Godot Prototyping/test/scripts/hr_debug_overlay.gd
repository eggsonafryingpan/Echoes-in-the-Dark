extends CanvasLayer

## Playtest readout of heart rate, bottom-left: the live value, whether it
## is currently trusted, and a rolling graph so a downward trend during
## CALM is visible at a glance rather than inferred from a flickering
## number. F10 toggles it; on by default because it exists for exactly the
## sessions where someone is watching CALM.
##
## During CALM the graph also plots what the gate actually compares
## against -- the heavily smoothed rate and the start-of-event reference
## minus the required drop -- so "why hasn't it passed yet" has an answer
## on screen. With the F4 filming assist running, CALM reads the scripted
## descent rather than the sensor; that line is drawn instead and labelled.
##
## Below the filming black-out (100) like every other readout, so nothing
## here can leak into a take.

const TOGGLE_ACTION := &"debug_hr_readout"

@export var overlay_layer: int = 55
@export var enabled: bool = true
## Seconds of history the graph spans.
@export var history_seconds: float = 45.0
@export var sample_interval: float = 0.1

const COLOR_LIVE := Color(1.0, 0.35, 0.35)
const COLOR_SMOOTHED := Color(1.0, 0.85, 0.3)
const COLOR_TARGET := Color(0.4, 1.0, 0.5)

var _panel: Control = null
var _label: Label = null
var _graph: Control = null
var _live: Array[float] = []      # -1 = no valid sample at that instant
var _smoothed: Array[float] = []  # -1 = CALM not running
var _target: Array[float] = []    # start - required drop, -1 when n/a
var _t_sample: float = 0.0


func _ready() -> void:
	layer = overlay_layer

	_panel = Control.new()
	_panel.name = "HeartRate"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.position = Vector2(14, -214)
	_panel.size = Vector2(420, 200)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
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
	_graph.size = Vector2(420, 120)
	_graph.draw.connect(_draw_graph)
	_panel.add_child(_graph)

	_panel.visible = enabled


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		enabled = not enabled
		_panel.visible = enabled
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var calm: Dictionary = EventDirector.calm_readout()
	_t_sample += delta
	if _t_sample >= sample_interval:
		_t_sample = 0.0
		_push_sample(calm)

	if not enabled:
		return
	_label.text = _readout(calm)
	_graph.queue_redraw()


func _push_sample(calm: Dictionary) -> void:
	var live: float = GameState.hr_bpm if GameState.hr_bpm > 0.0 else -1.0
	if calm.assist_bpm >= 0.0:
		live = calm.assist_bpm
	var smoothed: float = calm.smoothed_bpm if calm.active else -1.0
	var target: float = -1.0
	if calm.active and calm.start_bpm > 0.0:
		target = calm.start_bpm - calm.required_drop

	var cap := int(history_seconds / sample_interval)
	for pair in [[_live, live], [_smoothed, smoothed], [_target, target]]:
		pair[0].append(pair[1])
		if pair[0].size() > cap:
			pair[0].pop_front()


func _readout(calm: Dictionary) -> String:
	var lines: Array[String] = []
	var bpm := GameState.hr_bpm
	var rate := "--" if bpm <= 0.0 else "%.1f" % bpm
	lines.append("HR %s bpm   %s   resting %s   %s   [F10]" % [
		rate,
		"valid" if GameState.hr_valid else "MOTION-GATED",
		"--" if SensorBridge.resting_bpm <= 0.0 else "%.0f" % SensorBridge.resting_bpm,
		"ELEVATED" if GameState.hr_elevated else "not elevated",
	])

	if calm.active:
		var drop: float = calm.start_bpm - calm.smoothed_bpm if calm.start_bpm > 0.0 else 0.0
		lines.append("CALM %.1fs  start %s  smoothed %s  drop %.1f / %.1f needed" % [
			calm.t,
			"--" if calm.start_bpm <= 0.0 else "%.1f" % calm.start_bpm,
			"--" if calm.smoothed_bpm <= 0.0 else "%.1f" % calm.smoothed_bpm,
			drop, calm.required_drop,
		])
		lines.append("     dwell pass at %.0fs, fail-forward at %.0fs%s" % [
			calm.dwell_seconds, calm.fail_forward_seconds,
			"   F4 ASSIST: CALM reads %.1f" % calm.assist_bpm if calm.assist_bpm >= 0.0 else "",
		])
	else:
		lines.append("CALM not running")
	return "\n".join(lines)


func _draw_graph() -> void:
	var size := _graph.size
	_graph.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))

	var lo := INF
	var hi := -INF
	for series in [_live, _smoothed, _target]:
		for v in series:
			if v > 0.0:
				lo = minf(lo, v)
				hi = maxf(hi, v)
	if lo == INF:
		_graph.draw_string(ThemeDB.fallback_font, Vector2(8, 20), "no heart-rate samples yet",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
		return
	# At least a 20 bpm window, so a steady 70 is a flat line rather than
	# sensor noise blown up to fill the box.
	var mid := (lo + hi) * 0.5
	var span := maxf(hi - lo, 20.0) * 1.15
	lo = mid - span * 0.5
	hi = mid + span * 0.5

	var cap := int(history_seconds / sample_interval)
	_plot(_target, cap, lo, hi, COLOR_TARGET)
	_plot(_smoothed, cap, lo, hi, COLOR_SMOOTHED)
	_plot(_live, cap, lo, hi, COLOR_LIVE)

	var font := ThemeDB.fallback_font
	_graph.draw_string(font, Vector2(4, 14), "%.0f" % hi, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
	_graph.draw_string(font, Vector2(4, size.y - 4), "%.0f" % lo, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
	var x := size.x - 200.0
	for key in [["live", COLOR_LIVE], ["smoothed", COLOR_SMOOTHED], ["pass line", COLOR_TARGET]]:
		_graph.draw_string(font, Vector2(x, 14), key[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, key[1])
		x += font.get_string_size(key[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10.0


## Draws one series right-aligned (newest at the right edge), breaking the
## line wherever a sample is missing rather than bridging the gap.
func _plot(series: Array[float], cap: int, lo: float, hi: float, color: Color) -> void:
	var size := _graph.size
	var offset := cap - series.size()
	var run := PackedVector2Array()
	for i in series.size():
		var v := series[i]
		if v <= 0.0:
			if run.size() >= 2:
				_graph.draw_polyline(run, color, 2.0, true)
			run = PackedVector2Array()
			continue
		var x := size.x * float(offset + i) / float(maxi(cap - 1, 1))
		var y := size.y * (1.0 - (v - lo) / (hi - lo))
		run.append(Vector2(x, y))
	if run.size() >= 2:
		_graph.draw_polyline(run, color, 2.0, true)
