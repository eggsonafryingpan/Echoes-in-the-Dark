extends CanvasLayer

## Tuning and filming instrument, not a game system. Three things:
##
##   1/2/3  mute or unmute one audio layer, independently of everything else
##   F3     force the overload strip on or off by hand
##   readout of what is actually audible right now, plus detector state
##
## The mute keys use AudioServer.set_bus_mute rather than touching volumes,
## so they compose with AudioDirector instead of fighting it: the director
## keeps composing base volume x strip fraction into volume_db while a muted
## bus stays silent, and unmuting restores whatever the director had arrived
## at meanwhile. Nothing here writes a volume.
##
## F3 is deliberately not F1. F1 (toggle_adaptive_audio) answers "would this
## build adapt at all" and is the reviewer-facing A/B switch (§11); F3
## answers "show me the stripped mix right now" and overrides both the
## detector and F1 (AudioDirector.force_strip). Conflating them would make
## it impossible to film the stripped mix in a non-adaptive build.
##
## The readout is a plain Label at MOUSE_FILTER_IGNORE on a mid CanvasLayer,
## so it can never intercept a click and always sits under the filming
## overlay. Detector state is read from OverloadDetector.evaluation_log's
## last entry -- the log it already keeps for the observer HUD (§11), so
## this adds no instrumentation of its own.

const MUTE_ACTIONS := {
	&"debug_mute_environmental": &"Environmental",
	&"debug_mute_essential": &"Essential",
	&"debug_mute_priority": &"Priority",
}

const KEY_HINT := {
	&"Environmental": "1",
	&"Essential": "2",
	&"Priority": "3",
}

## Below the filming overlay (Task 3) so black-out always wins, above the
## game so the text is legible.
@export var overlay_layer: int = 50

var _label: Label = null


func _ready() -> void:
	layer = overlay_layer
	_label = Label.new()
	_label.name = "Readout"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(14, 12)
	_label.add_theme_color_override(&"font_color", Color(0.65, 1.0, 0.75))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	for action in MUTE_ACTIONS:
		if event.is_action_pressed(action):
			_toggle_mute(MUTE_ACTIONS[action])
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed(&"debug_force_strip"):
		AudioDirector.force_strip = not AudioDirector.force_strip
		get_viewport().set_input_as_handled()


func _toggle_mute(bus_name: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		push_warning("AudioDebugOverlay: no bus named %s" % bus_name)
		return
	AudioServer.set_bus_mute(idx, not AudioServer.is_bus_mute(idx))


func _process(_delta: float) -> void:
	_label.text = _readout()


func _readout() -> String:
	var lines: Array[String] = ["AUDIO DEBUG"]

	for bus_name in [&"Environmental", &"Essential", &"Priority"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx == -1:
			lines.append("  [%s] %-14s BUS MISSING" % [KEY_HINT[bus_name], bus_name])
			continue

		var muted := AudioServer.is_bus_mute(idx)
		var fraction := AudioDirector.strip_fraction(bus_name)
		var state := "MUTED " if muted else ("AUDIBLE" if fraction > 0.01 else "STRIPPED")
		var detail := "never stripped" if bus_name == &"Priority" else "strip %.2f" % fraction
		lines.append("  [%s] %-14s %-8s  %s" % [KEY_HINT[bus_name], bus_name, state, detail])

	lines.append("  [F1] adaptive %s     [F3] force strip %s" % [
		_on_off(AudioDirector.adaptive_enabled), _on_off(AudioDirector.force_strip)])
	lines.append(_detector_line())
	return "\n".join(lines)


func _detector_line() -> String:
	if OverloadDetector.evaluation_log.is_empty():
		return "  detector: no evaluation yet"

	var e: Dictionary = OverloadDetector.evaluation_log[-1]
	var stage := "normal"
	if e.overloaded:
		stage = "OVERLOADED stage 2/2 (env+ess)" if e.escalated else "OVERLOADED stage 1/2 (env)"
	return "  detector: %s   HR elevated %s   behavioral %d/3 (collisions %s, no-progress %s, confined %s)" % [
		stage,
		_yes_no(e.hr_elevated),
		e.behavioral_count,
		_yes_no(e.collisions),
		_yes_no(e.no_progress),
		_yes_no(e.confined),
	]


func _on_off(v: bool) -> String:
	return "ON " if v else "OFF"


func _yes_no(v: bool) -> String:
	return "yes" if v else "no"
