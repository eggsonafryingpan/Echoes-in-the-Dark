extends Node3D

@onready
var collision_shape = $CaveBody/CollisionShape3D
@onready
var map = $Map

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	collision_shape.shape = map.mesh.create_trimesh_shape()
	var steam_audio = SteamAudioGeometry.new()
	collision_shape.add_child(steam_audio)
	
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
