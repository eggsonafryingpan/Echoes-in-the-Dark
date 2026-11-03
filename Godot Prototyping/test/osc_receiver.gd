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

# The controller heartbeat used to buzz here every `interval` seconds, all
# game, whatever the input -- a fixed 100 bpm unless this receiver happened to
# get a bpm, which it never does in live mode. It now lives in
# scripts/player_haptics.gd and follows GameState.hr_bpm, which the bpm above
# still feeds through SensorBridge.set_osc_heart_rate().
	
	
	
