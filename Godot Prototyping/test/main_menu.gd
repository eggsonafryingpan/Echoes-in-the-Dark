extends Control

func _ready():
	$VBoxContainer/Button.pressed.connect(_on_baseline_pressed)
	$VBoxContainer/Button2.pressed.connect(_on_start_pressed)
	$VBoxContainer/Button3.pressed.connect(_on_quit_pressed)

## Playtesting: F6 (debug_skip_event, the same key that skips the cold
## open once it is running) starts the game with Event 1 skipped entirely.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_skip_event"):
		get_viewport().set_input_as_handled()
		EventDirector.skip_intro = true
		_on_start_pressed()

func _on_baseline_pressed():
	print("Baseline calibration starting...")

func _on_start_pressed():
	print("Starting game...")
	# Arms Event 1 (§10's cold open). The gameplay scene is not loaded yet,
	# so EventDirector waits for the player to exist before starting it.
	EventDirector.queue_event_one()
	get_tree().change_scene_to_file("res://echoes_in_the_dark.tscn")

func _on_quit_pressed():
	get_tree().quit()
