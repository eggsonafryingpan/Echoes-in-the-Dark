extends Area3D

@onready var audio = $SteamAudioPlayer
var focused = false

@export var max_db = -10
@export var min_db = -60
@export var stop_out_of_range = true


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func updateFocus():
	if !focused:
		focused = true
		
		audio.stream_paused = false
	if audio.volume_db < max_db:
		audio.volume_db += 8

func _on_timer_timeout() -> void:
	if audio.volume_db < min_db:
		if stop_out_of_range:
			audio.stream_paused = true
		focused = false
	else:
		audio.volume_db -= 5
