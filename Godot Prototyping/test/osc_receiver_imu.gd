#meta-name: OSCReceiver Default

extends OSCReceiver

@onready var player = get_parent()

@export var SENS = 2

## Code to be ran when Parent Control is set to custom.
func _custom_control(address : String, vals : Array, time):
	
	if vals != []:
		if target_server.incoming_messages.has(osc_address):
			print(vals[0],vals[1],vals[2])
			#var rotation = Vector3(vals[0],vals[1],vals[2])
			# Turn the head, not the body: movement, the audio listener and
			# FOCUS all read GameState's yaw, so rotating the body here made the
			# view turn while forward kept walking the same way.
			GameState.yaw_offset -= vals[0] * SENS
			#player.pivot.rotate_x(-vals[2] * SENS)
			#player.rotate_x(vals[1])
