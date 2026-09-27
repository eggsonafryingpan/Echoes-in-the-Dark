extends Camera3D

var fp_camera

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	fp_camera = get_viewport().get_camera_3d()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("switch_camera"):
		var current_camera = get_viewport().get_camera_3d()
		if (current_camera == fp_camera):
			make_current()
		else:
			fp_camera.make_current()
			
