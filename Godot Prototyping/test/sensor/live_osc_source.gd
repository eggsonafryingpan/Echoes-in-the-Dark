class_name LiveOSCSource
extends SensorSource

## Receives already-processed orientation + heart rate from the Python
## sensor bridge (sensor_bridge/bridge.py, Process A) over OSC via GodOSC.
## Godot does no signal processing here -- just parses two addresses. See
## CLAUDE_CODE_BRIEF.md §2, §3.
##
## Needs the Python bridge running and pointed at this port. Hardware-in-
## the-loop testing is a human task (§0.1) -- use MockSource for everything
## else.
##
## Doesn't reuse the addons/godOSC OSCReceiver node (which is built for
## wiring a single address to a scene property in the editor); this listens
## for two addresses itself and owns its own OSCServer instead.

const ORIENTATION_ADDRESS := "/echoes/orientation"
const HEART_RATE_ADDRESS := "/echoes/heart_rate"

@export var port: int = 8687

var _server: OSCServer = null


func start() -> void:
	_server = OSCServer.new()
	_server.port = port
	add_child(_server)
	_server.message_received.connect(_on_message)


func stop() -> void:
	if _server != null:
		_server.message_received.disconnect(_on_message)
		_server.queue_free()
		_server = null


func _on_message(address: String, value, _time) -> void:
	match address:
		ORIENTATION_ADDRESS:
			var v: Array = value if value is Array else [value]
			if v.size() >= 3:
				orientation_sample.emit(Vector3(v[0], v[1], v[2]))
		HEART_RATE_ADDRESS:
			var v: Array = value if value is Array else [value]
			if v.size() >= 2:
				heart_rate_sample.emit(float(v[0]), int(v[1]) != 0)
