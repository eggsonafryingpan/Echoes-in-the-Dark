#meta-name: OSCReceiver Default

extends OSCReceiver

@onready var player = get_parent()

@export var SENS = 2

## Code to be ran when Parent Control is set to custom.
func _custom_control(address : String, vals : Array, time):
	
	if vals != []:
		if target_server.incoming_messages.has(osc_address):
			player.pivot.rotate_x(-vals[2] * SENS) 
			#VALS[2] MAY NEED TO CHANGE/INVERT
			#player.rotate_x(vals[1])
