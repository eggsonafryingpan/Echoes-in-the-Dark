extends Node3D

@onready
var collision_shape = $CaveBody/CollisionShape3D
@onready
var map = $Map

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	collision_shape.shape = map.mesh.create_trimesh_shape()
	# Raytraced Audio needs no geometry-registration node (unlike Steam Audio) --
	# RaytracedAudioListener raycasts directly against this physics shape.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
