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
			player.rotate_y(-vals[0] * SENS)
			player.pivot.rotate_x(-vals[2] * SENS)
			#player.rotate_x(vals[1])
