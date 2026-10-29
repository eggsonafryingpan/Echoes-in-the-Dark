extends Control

func _ready():
	$VBoxContainer/Button.pressed.connect(_on_baseline_pressed)
	$VBoxContainer/Button2.pressed.connect(_on_start_pressed)
	$VBoxContainer/Button4.pressed.connect(_on_quit_pressed)
	$VBoxContainer/Button3.pressed.connect(_on_minigame_pressed)

## Playtesting: F6 (debug_skip_event, the same key that skips the cold
## open once it is running) starts the game with Event 1 skipped entirely.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_skip_event"):
		get_viewport().set_input_as_handled()
		EventDirector.skip_intro = true
		_on_start_pressed()

func _on_baseline_pressed():
	print("Baseline calibration starting...")

## The escape blockout (E1-E4). The original cave, echoes_in_the_dark.tscn,
## is untouched and still runs on its own (Run Current Scene).
const GAME_SCENE := "res://escape_level.tscn"

func _on_start_pressed():
	print("Starting game...")
	# The level decides where the run starts (Event 1, or --event=N) when it
	# registers with EventDirector; nothing to arm from here.
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_quit_pressed():
	get_tree().quit()
	
func _on_minigame_pressed():
	get_tree().change_scene_to_file("res://minigame.tscn")
