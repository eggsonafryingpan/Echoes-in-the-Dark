#meta-name: OSCReceiver Default

extends OSCReceiver
var interval: float = 0.6


## Code to be ran when Parent Control is set to custom.
func _custom_control(address : String, vals : Array, time):
	
	if vals != []:
		if target_server.incoming_messages.has(osc_address):
			print(address, "  Elevated: ", vals[0])
			# elevationCalc_WORKING.py sends true/false, betterHR.py sends bpm.
			if vals[0] is bool:
				GameState.set_osc_elevated(vals[0])
			elif vals[0] > 0.0:
				SensorBridge.set_osc_heart_rate(vals[0])
				interval = 60.0 / vals[0]
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
	
	
	
