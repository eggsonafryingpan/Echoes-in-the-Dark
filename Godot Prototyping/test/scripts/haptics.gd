class_name Haptics
extends RefCounted

## Controller rumble, in one place, for a PS5 DualSense.
##
## Godot (through SDL) does not address rumble motors by side. It takes a
## weak and a strong magnitude: start_joy_vibration(device, weak, strong, s).
## On the DualSense those land in different grips:
##
##   LEFT  grip = the STRONG, low-frequency motor   -> pulse_side(LEFT, ...)
##   RIGHT grip = the WEAK, high-frequency motor    -> pulse_side(RIGHT, ...)
##
## So "rumble on the left" is the strong motor alone and "on the right" the
## weak motor alone. The two feel different (a deep thump vs a buzz) as well
## as sitting in different hands; that asymmetry is the hardware, not a bug.
##
## UNVERIFIED ON THE REAL CONTROLLER. Test over USB first: over Bluetooth,
## SDL's DualSense rumble depends on the controller having been switched to
## its enhanced report mode, and on some setups it does nothing at all.
## If left and right come out swapped, flip SWAP_SIDES rather than touching
## any caller.
##
## No controller connected -> every call is a harmless no-op.

const LEFT := -1
const RIGHT := 1

## Flip if a hardware test shows the grips the other way round.
const SWAP_SIDES := false


## Same strength in both grips: non-directional, reads as a body state
## (heartbeat) or an impact rather than a direction.
static func pulse_both(intensity: float, seconds: float) -> void:
	var i := clampf(intensity, 0.0, 1.0)
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, i, i, seconds)


## One grip only. side is LEFT (-1) or RIGHT (+1).
static func pulse_side(side: int, intensity: float, seconds: float) -> void:
	var i := clampf(intensity, 0.0, 1.0)
	var left := (side < 0) != SWAP_SIDES
	for device in Input.get_connected_joypads():
		if left:
			Input.start_joy_vibration(device, 0.0, i, seconds)
		else:
			Input.start_joy_vibration(device, i, 0.0, seconds)


static func stop() -> void:
	for device in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)
