#meta-name: OSCReceiver Default

extends OSCReceiver


## Code to be ran when Parent Control is set to custom.
func _custom_control(address : String, vals : Array, time):
	
	if vals != []:
		if target_server.incoming_messages.has(osc_address):
			print(address, "  Elevated: ", vals[0])
		#put your code here. This if statement prevents your code from being ran if you receive an empty message
		pass
	pass
