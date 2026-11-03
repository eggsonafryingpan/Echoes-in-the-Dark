extends CanvasLayer

## The run's end: "you made it out" and the player's notes, the discoveries
## they actually made. Full screen, or with over_map a panel down the right
## side so the overhead reveal map shows beside it. Shown above every overlay, including the filming
## black-out, since this is the screen meant to be seen. The bat reads the
## same notes aloud (escape_level.gd).

@export var screen_layer: int = 120
@export var background: Color = Color(0.02, 0.02, 0.03, 0.92)

var lines_shown: PackedStringArray = []


## Share of the screen width the notes panel takes beside the map.
@export var panel_width: float = 0.34


func show_notes(notes: Array, over_map: bool = false) -> void:
	layer = screen_layer
	var bg := ColorRect.new()
	bg.color = background
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if over_map:
		bg.anchor_left = 1.0 - panel_width
		bg.color.a = 0.82
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 18)
	bg.add_child(box)

	_add_label(box, "You made it out.", 44)
	if notes.is_empty():
		_add_label(box, "No notes this time.", 26)
		return
	_add_label(box, "Your notes", 30)
	for note in notes:
		_add_label(box, "•  " + String(note.text), 26)


func _add_label(parent: Control, text: String, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	lines_shown.append(text)
