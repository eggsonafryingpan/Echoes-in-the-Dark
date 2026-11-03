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


# --- Adaptive triggers (L2 / R2 resistance) ----------------------------------
#
# Godot has no API for DualSense trigger resistance, so the game asks the
# Python bridge to do it: one OSC message, /echoes/trigger [side, strength],
# to TRIGGER_PORT. The bridge applies it over HID with pydualsense (see
# sensor_bridge/trigger_out.py). With no bridge, or no pydualsense, nothing
# happens and the game plays the same.

const TRIGGER_HOST := "127.0.0.1"
const TRIGGER_PORT := 12347
static var _trigger_udp: PacketPeerUDP = null
## Last strength sent per side, for the climb's wall view and tests.
static var trigger_strength := {LEFT: 0.0, RIGHT: 0.0}
static var _helper_started := false


## Resistance needs sensor_bridge/trigger_out.py running. ./launch.sh (live)
## runs it inside the bridge; anywhere else (the Godot editor, launch.sh mouse)
## this starts it on its own with the bridge's venv. It quits by itself if the
## bridge already has the port, and when the game exits. Headless: skipped.
static func ensure_trigger_helper() -> void:
	if _helper_started or DisplayServer.get_name() == "headless":
		return
	_helper_started = true
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().get_base_dir()
	var python := root.path_join("sensor_bridge/.venv/bin/python")
	var script := root.path_join("sensor_bridge/trigger_out.py")
	if not FileAccess.file_exists(python) or not FileAccess.file_exists(script):
		print("Haptics: no %s; no trigger resistance." % python)
		return
	var pid := OS.create_process(python, [script, "--port", str(TRIGGER_PORT), "--parent-pid", str(OS.get_process_id())])
	print("Haptics: trigger helper started (pid %d)" % pid)


## side LEFT (-1, L2) or RIGHT (+1, R2); strength 0 (off) to 1 (stiffest).
static func set_trigger(side: int, strength: float) -> void:
	var s := clampf(strength, 0.0, 1.0)
	trigger_strength[side] = s
	if _trigger_udp == null:
		_trigger_udp = PacketPeerUDP.new()
		_trigger_udp.set_dest_address(TRIGGER_HOST, TRIGGER_PORT)
	_trigger_udp.put_packet(_osc_message("/echoes/trigger", side, s))


static func release_triggers() -> void:
	set_trigger(LEFT, 0.0)
	set_trigger(RIGHT, 0.0)


## A minimal OSC message: address, ",if", one int32, one float32 (big-endian).
static func _osc_message(address: String, i: int, f: float) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(_osc_string(address))
	out.append_array(_osc_string(",if"))
	var num := StreamPeerBuffer.new()
	num.big_endian = true
	num.put_32(i)
	num.put_float(f)
	out.append_array(num.data_array)
	return out


static func _osc_string(text: String) -> PackedByteArray:
	var b := text.to_ascii_buffer()
	b.append(0)
	while b.size() % 4 != 0:
		b.append(0)
	return b
