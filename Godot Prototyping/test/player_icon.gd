extends Node2D


@onready var player = get_node_or_null("/root/World/player")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# Absent when TopDownView is run standalone (e.g. it's the current
	# run/main_scene) instead of nested inside echoes_in_the_dark.tscn.
	if player == null:
		return
	var player_pos = player.global_position
	global_position = Vector2(player_pos.x, player_pos.z)
