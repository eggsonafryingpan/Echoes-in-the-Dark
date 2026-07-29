extends Area3D

@onready var audio = $SteamAudioPlayer
var focused = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
	
func updateFocus():
	if !focused:
		focused = true
		audio.stream_paused = false
	if audio.volume_db < 0:
		audio.volume_db += 1

func _on_timer_timeout() -> void:
	if !focused:
		if audio.volume_db < -80:
			audio.stream_paused = true
		else:
			audio.volume_db -= 5
