class_name MockSource
extends SensorSource

## Replays a recorded/scripted trace instead of listening for real OSC
## (brief CLAUDE_CODE_BRIEF.md §3.5). Build and test everything against this
## before touching hardware.
##
## Traces are small keyframe JSON files under sensor/mock_traces/; this node
## linearly interpolates orientation + bpm between keyframes and holds the
## "still" flag from the keyframe at-or-before the current time (a boolean
## doesn't have a meaningful halfway point).

@export var trace_name: String = "startled_then_calming"

## Loop back to the start once the trace ends. Off by default: these traces
## are one-shot scripted moments (a CALM cold open, a stuck-and-colliding
## stretch), not ambient loops.
@export var loop: bool = false

var _keyframes: Array = []
var _t: float = 0.0
var _running: bool = false


func start() -> void:
	_keyframes = _load_trace(trace_name)
	_t = 0.0
	_running = not _keyframes.is_empty()
	set_process(_running)


func stop() -> void:
	_running = false
	set_process(false)


func _load_trace(trace: String) -> Array:
	var path := "res://sensor/mock_traces/%s.json" % trace
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MockSource: no such trace '%s' (%s)" % [trace, path])
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("keyframes"):
		push_error("MockSource: malformed trace file %s" % path)
		return []
	return parsed["keyframes"]


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta

	var last_t: float = _keyframes[-1]["t"]
	if _t >= last_t:
		_t = last_t
		if loop:
			_t = 0.0
		else:
			_running = false
			set_process(false)

	var sample := _sample_at(_t)
	orientation_sample.emit(Vector3(sample.pitch, sample.yaw, sample.roll))
	heart_rate_sample.emit(sample.bpm, sample.still)


## Linear interpolation between the two keyframes surrounding t. still holds
## at the earlier keyframe's value rather than interpolating.
func _sample_at(t: float) -> Dictionary:
	var prev: Dictionary = _keyframes[0]
	var next: Dictionary = _keyframes[0]
	for kf in _keyframes:
		if kf["t"] <= t:
			prev = kf
		if kf["t"] >= t:
			next = kf
			break

	var span: float = next["t"] - prev["t"]
	var f: float = 0.0 if span <= 0.0 else (t - prev["t"]) / span

	return {
		"pitch": lerpf(prev.get("pitch", 0.0), next.get("pitch", 0.0), f),
		"yaw": lerpf(prev.get("yaw", 0.0), next.get("yaw", 0.0), f),
		"roll": lerpf(prev.get("roll", 0.0), next.get("roll", 0.0), f),
		"bpm": lerpf(prev.get("bpm", 70.0), next.get("bpm", 70.0), f),
		"still": prev.get("still", true),
	}
