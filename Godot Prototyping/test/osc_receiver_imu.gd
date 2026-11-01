#meta-name: OSCReceiver Default

extends OSCReceiver

@onready var player = get_parent()

@export var SENS = 2
## Which /Godot/IMU value is the head's nod, and which way is up.
@export var pitch_index: int = 2
@export var pitch_sign: float = -1.0
## IMUCalc_WORKING.py sends one change per IMU sample, at this rate (Hz).
@export var imu_rate: float = 25.0

## Code to be ran when Parent Control is set to custom.
func _custom_control(address : String, vals : Array, time):
	if vals != []:
		if target_server.incoming_messages.has(osc_address):
			var turn: float = vals[1] * SENS
			GameState.add_head_turn(turn)
			GameState.add_head_pitch_change(vals[pitch_index] * pitch_sign * imu_rate)
			# player.gd steers from GameState. Only a scene that steers by its
			# own body (player_alternate) still turns the body.
			if not "pivot" in player:
				player.rotate_y(turn)
