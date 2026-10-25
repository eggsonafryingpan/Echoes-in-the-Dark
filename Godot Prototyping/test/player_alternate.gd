extends CharacterBody3D

@export var mouse_sensitivity := 0.005

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
	if Input.is_action_just_pressed("exit_to_main_menu"):
		print("exit")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://main_menu.tscn")
		
		
