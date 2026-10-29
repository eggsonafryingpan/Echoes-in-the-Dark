extends PathFollow3D

@export var speed: float = 2.0
@onready var DM = $Node3D/DM
@onready var GM = $Node3D/GM
@onready var AM = $Node3D/AM

@onready var chords = [DM, GM, AM, DM]
@onready var currChord = DM
var index = 0

func _ready() -> void:
	currChord.play()
	
func setNextSong() -> void:
	randomize()
	currChord.stream_paused = true
	if index == chords.size() - 1:
		index = 0
	else:
		index += 1
	currChord = chords[index]
	print(index)
	var roll = randf_range(0,7)
	progress_ratio = roll/7
	currChord.play()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
