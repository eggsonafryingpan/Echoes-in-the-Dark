extends SteamAudioPlayer

#@onready var cave_generator = $"../CaveGenerator"


# Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#cave_generator.terrain_loaded.connect(_on_terrain_loaded)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


#func _on_terrain_loaded():
	#print(cave_generator.random_walk_positions)
	#position += cave_generator.random_walk_positions[-1]
