extends Control

func _ready():
	$VBoxContainer/Button.pressed.connect(_on_baseline_pressed)
	$VBoxContainer/Button2.pressed.connect(_on_start_pressed)
	$VBoxContainer/Button3.pressed.connect(_on_quit_pressed)

func _on_baseline_pressed():
	print("Baseline calibration starting...")

func _on_start_pressed():
	print("Starting game...")
	get_tree().change_scene_to_file("res://TerrainGeneration.tscn")

func _on_quit_pressed():
	get_tree().quit()
