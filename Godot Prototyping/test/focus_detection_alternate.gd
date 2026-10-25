extends Area3D

@onready var raycast = $"../VisionRaycast"
@onready var waitTimer = $WaitTimer
@onready var chime = $Chime
var focused = false
var confirmed = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_timer_timeout() -> void:
	var overlap = get_overlapping_areas()
	if overlap.size() == 0:
		focused = false
		waitTimer.stop()
		chime.stream_paused = true
	for a in overlap:
		if a.is_in_group("SoundBox"):
			if !focused:
				focused = true
				if (!chime.playing):
					chime.play()
				waitTimer.start()
			else:
				if confirmed:
					a.updateFocus()
					focused = false
					confirmed = false
			return

	

func _on_wait_timer_timeout() -> void:
	confirmed = true 
