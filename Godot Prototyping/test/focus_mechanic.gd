extends Area3D

@onready var raycast = $"../VisionRaycast"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_timer_timeout() -> void:
	var overlap = get_overlapping_areas()
	if overlap.size() == 0:
		return
	for a in overlap:
		if !a.is_in_group("SoundBox"):
			continue
		raycast.look_at(a.global_transform.origin,Vector3.UP)
		raycast.force_raycast_update()
		if raycast.is_colliding():
			var collider = raycast.get_collider()
			if collider.is_in_group("SoundBox"):
				collider.updateFocus()
			
		
