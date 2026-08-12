#meta-name: OSCReceiver Default

extends OSCReceiver
var interval: float = 0.6


## Code to be ran when Parent Control is set to custom.
func _custom_control(address : String, vals : Array, time):
	
	if vals != []:
		if target_server.incoming_messages.has(osc_address):
			print(address, "  Elevated: ", vals[0])
			interval = vals[0] / 60
		#put your code here. This if statement prevents your code from being ran if you receive an empty message
		pass
	pass

#in seconds
var elapsed = 0
func _process(delta):
	elapsed += delta
	if elapsed >= interval:
		print("buzz buzz")
		print(interval)
		Input.start_joy_vibration(0,1,0.8,0.2)
		elapsed = 0
	
	
	
