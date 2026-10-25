extends PathFollow3D

@export var speed: float = 2.0
@onready var reverie = $Node3D/Reverie
@onready var debussy = $Node3D/Debussy
@onready var knoop = $Node3D/Knoop
@onready var schubert = $Node3D/Schubert

@onready var songs = [reverie, debussy, knoop, schubert]
@onready var currSong = reverie

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	setRandSong()
	
func setRandSong() -> void:
	randomize()
	currSong.stream_paused = true
	var lastSong = currSong	
	while (lastSong == currSong):
		var roll = randf_range(0,7)
		progress_ratio = roll/7
		currSong = songs[(roll as int) / 2]
	currSong.play()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
