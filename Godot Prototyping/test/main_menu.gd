extends Control

func _ready():
	$VBoxContainer/Button.pressed.connect(_on_baseline_pressed)
	$VBoxContainer/Button2.pressed.connect(_on_start_pressed)
	$VBoxContainer/Button3.pressed.connect(_on_quit_pressed)

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
