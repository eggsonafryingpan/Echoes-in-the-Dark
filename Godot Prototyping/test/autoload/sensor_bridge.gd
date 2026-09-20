extends Node

## Autoload this as "SensorBridge". Brief: CLAUDE_CODE_BRIEF.md §3, §13 Phase 1.
##
## Receives already-processed orientation + heart rate from the Python sensor
## bridge (Process A) over OSC via GodOSC, or from a MockSource replaying a
## recorded/scripted trace (§3.5). Godot never does IMU fusion or PPG
## filtering itself — that lives in Python (Madgwick, HeartPy). This node's
## job is just: receive, expose clean signals, own the resting-HR baseline.
##
## SensorSource split (§3.5): build and test everything against MockSource
## first. LiveOSCSource is only for hardware-in-the-loop testing, which is a
## human task, not a Claude Code task.
##
## GameState (not this node) turns these raw signals into derived state like
## "elevated" or "is_still" — SensorBridge only reports what the hardware/mock
## said, relative-baseline math and thresholds live downstream.

enum SourceMode { LIVE, MOCK }

## orientation as Euler angles (radians), head-tracking reference frame (§0.1, §6.1)
signal orientation_updated(euler: Vector3)

## bpm is only meaningful when valid is true (motion-gated, §3.2)
signal heart_rate_updated(bpm: float, valid: bool)

## fires once after the ~30s quiet-stillness baseline window completes (§3.3)
signal baseline_ready(resting_bpm: float)

@export var source_mode: SourceMode = SourceMode.MOCK

## Which MockSource trace to play when source_mode is MOCK. Ignored for LIVE.
@export var mock_trace: String = "startled_then_calming"

## LiveOSCSource's listening port. Must match the Python bridge's --godot-port.
@export var live_port: int = 8687

## Seconds of quiet stillness at session start used to compute resting_bpm
## (§3.3). Folded into the spoken intro in the real game, not a visible wait.
@export var baseline_seconds: float = 30.0

## resting HR from the session-start baseline. Everything downstream reads
## HR relative to this, never absolute BPM (§3.3). -1 until baseline_ready fires.
var resting_bpm: float = -1.0

var _source: SensorSource = null
var _baseline_samples: Array[float] = []
var _baseline_elapsed: float = 0.0
var _baseline_done: bool = false


func _ready() -> void:
	match source_mode:
		SourceMode.MOCK:
			var mock := MockSource.new()
			mock.trace_name = mock_trace
			_source = mock
		SourceMode.LIVE:
			var live := LiveOSCSource.new()
			live.port = live_port
			_source = live

	add_child(_source)
	_source.orientation_sample.connect(_on_orientation_sample)
	_source.heart_rate_sample.connect(_on_heart_rate_sample)
	_source.start()


func _process(delta: float) -> void:
	if _baseline_done:
		return
	_baseline_elapsed += delta
	if _baseline_elapsed >= baseline_seconds:
		_finish_baseline()


func _on_orientation_sample(euler: Vector3) -> void:
	orientation_updated.emit(euler)


func _on_heart_rate_sample(bpm: float, valid: bool) -> void:
	heart_rate_updated.emit(bpm, valid)
	if not _baseline_done and valid:
		_baseline_samples.append(bpm)


func _finish_baseline() -> void:
	_baseline_done = true
	if _baseline_samples.is_empty():
		push_warning("SensorBridge: no valid HR samples during the baseline window; resting_bpm stays unset.")
		return
	var total := 0.0
	for v in _baseline_samples:
		total += v
	resting_bpm = total / _baseline_samples.size()
	baseline_ready.emit(resting_bpm)
