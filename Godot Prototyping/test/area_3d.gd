extends Area3D

@onready var audio = $Chime
@onready var timer = $Timer
@onready var path = get_parent().get_parent()
var focused = false



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func updateFocus():
	path.setNextSong() 
		
		
	
