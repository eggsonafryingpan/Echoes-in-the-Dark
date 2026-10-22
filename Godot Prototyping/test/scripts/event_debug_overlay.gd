extends CanvasLayer

## Playtest readout, top-right: which event the run is on and what it is
## doing, plus the keys that move between events. F12 toggles it. Below the
## filming black-out (100) like every other readout.

const TOGGLE_ACTION := &"debug_event_readout"
const Stealth := preload("res://scripts/events/stealth_encounter.gd")

@export var overlay_layer: int = 58
@export var level_path: NodePath = ^".."

var _label: Label = null
var _level: Node = null


func _ready() -> void:
	layer = overlay_layer
	_level = get_node_or_null(level_path)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.position = Vector2(-620, 12)
	_label.size = Vector2(600, 0)
	_label.add_theme_font_size_override(&"font_size", 15)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		_label.visible = not _label.visible
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _label.visible:
		return
	var lines: Array[String] = []
	var ev := EventDirector.current_event
	lines.append("%s  %s   [F12]" % [EventDirector.event_name(ev),
			"RUNNING" if EventDirector.event_running or EventDirector.event_one_active else "armed (walk to trigger)"])
	if _level != null:
		lines.append("route %3.0f%%   den %s   input %s" % [
			_level.progress_fraction() * 100.0, "FOUND" if _level.den_found else "not found",
			"LOCKED" if GameState.input_locked else "free"])
		var stealth = _level.stealth
		lines.append("stealth: %s, attempt %d  %s" % [
			Stealth.State.keys()[stealth.state], stealth.attempt, stealth.last_verdict])
		var climb = _level.climb
		lines.append("climb: %s, rocks %d, hits %d" % [
			"active" if climb.active else "idle", climb.rocks_dropped, climb.hits])
	lines.append("head yaw %.0f°  ref %.0f°   C / touchpad = recenter" % [
		rad_to_deg(GameState.effective_orientation().y), rad_to_deg(GameState.reference_yaw)])
	lines.append("F6 skip · Ctrl+1-4 jump · F11 fail · F4 calm assist · V aerial")
	_label.text = "\n".join(lines)
