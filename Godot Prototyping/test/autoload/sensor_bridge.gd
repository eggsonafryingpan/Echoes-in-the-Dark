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

enum SourceMode { LIVE, MOCK, DEV_MOUSE }

## orientation as Euler angles (radians), head-tracking reference frame (§0.1, §6.1)
signal orientation_updated(euler: Vector3)

## bpm is only meaningful when valid is true (motion-gated, §3.2)
signal heart_rate_updated(bpm: float, valid: bool)

## fires once after the ~30s quiet-stillness baseline window completes (§3.3)
signal baseline_ready(resting_bpm: float)

## Head pitch rate in rad/s, positive = up. Separate from orientation_updated,
## which carries no pitch from the headband.
signal pitch_rate_updated(rate: float)

## DEV_MOUSE (default) is mouse orientation plus a constant 70 bpm. It opens
## no OSC port, so the receivers in player.tscn and player_alternate.tscn
## keep port 8687 to themselves.
##
## LIVE is the real pipeline: sensor_bridge/bridge.py -> OSC -> LiveOSCSource.
## Until live orientation is actually arriving (no bridge, no headband), the
## mouse steers instead; the moment live packets flow they take over. Heart
## rate in LIVE comes from the bridge only: no fallback value, since an
## invented resting rate would become the baseline and read as the player's
## own. LIVE binds 8687 first, so those scene receivers go deaf while it runs.
##
## MOCK replays a scripted trace for testing CALM/overload against known
## numbers; it drives orientation too, so the player can't steer under it.
##
## Override per launch without editing anything: `-- --sensor=mouse`,
## `--sensor=mock`, `--sensor=live`, or ECHOES_SENSOR=<same>.
@export var source_mode: SourceMode = SourceMode.DEV_MOUSE

## LIVE only: live orientation older than this counts as stopped, and the
## mouse takes back over. Generous, so one dropped UDP packet never flips it.
@export var live_stale_seconds: float = 1.0

## Which MockSource trace to play when source_mode is MOCK. Ignored otherwise.
@export var mock_trace: String = "startled_then_calming"

## LiveOSCSource's listening port. Must match the Python bridge's --godot-port.
@export var live_port: int = 8687

## Seconds of quiet stillness used to compute resting_bpm (§3.3). Counted
## from the first valid heart-rate sample, not from launch: with live
## hardware the bridge often starts after the game, and a window that had
## already run out by then left the baseline unset for the whole session.
@export var baseline_seconds: float = 30.0

## resting HR from the session-start baseline. Everything downstream reads
## HR relative to this, never absolute BPM (§3.3). -1 until baseline_ready fires.
var resting_bpm: float = -1.0

var _source: SensorSource = null
## LIVE only: the mouse, standing in for orientation while live is silent.
var _fallback: DevMouseSource = null
var _live: LiveOSCSource = null
var _baseline_samples: Array[float] = []
var _baseline_elapsed: float = 0.0
var _baseline_done: bool = false
## True once osc_receiver.gd has delivered a real heart rate.
var _osc_heart_rate: bool = false


func _ready() -> void:
	source_mode = _mode_override(source_mode)
	match source_mode:
		SourceMode.MOCK:
			var mock := MockSource.new()
			mock.trace_name = mock_trace
			_source = mock
		SourceMode.LIVE:
			_live = LiveOSCSource.new()
			_live.port = live_port
			_source = _live
			_fallback = DevMouseSource.new()
			_fallback.emit_heart_rate = false
			add_child(_fallback)
			_fallback.orientation_sample.connect(_on_fallback_orientation)
			_fallback.pitch_rate_sample.connect(_on_fallback_pitch_rate)
			_fallback.start()
		SourceMode.DEV_MOUSE:
			_source = DevMouseSource.new()

	add_child(_source)
	_source.orientation_sample.connect(_on_orientation_sample)
	_source.heart_rate_sample.connect(_on_heart_rate_sample)
	_source.pitch_rate_sample.connect(_on_pitch_rate_sample)
	_source.start()
	print("SensorBridge: %s" % status_text())


func _mode_override(current: SourceMode) -> SourceMode:
	var value := OS.get_environment("ECHOES_SENSOR")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sensor="):
			value = arg.trim_prefix("--sensor=")
	match value.to_lower():
		"live":
			return SourceMode.LIVE
		"mouse", "dev_mouse":
			return SourceMode.DEV_MOUSE
		"mock":
			return SourceMode.MOCK
	return current


func _process(delta: float) -> void:
	# The window only runs once real samples are arriving (see baseline_seconds).
	if _baseline_done or _baseline_samples.is_empty():
		return
	_baseline_elapsed += delta
	if _baseline_elapsed >= baseline_seconds:
		_finish_baseline()


## True while the bridge's orientation stream is flowing (LIVE only).
func live_orientation_active() -> bool:
	return _live != null and _live.last_orientation_t >= 0.0 \
			and Time.get_ticks_msec() / 1000.0 - _live.last_orientation_t < live_stale_seconds


## True while the bridge's heart-rate stream is flowing (LIVE only). Valid
## or not: an invalid (motion-gated) sample still proves the bridge is up.
func live_heart_rate_active() -> bool:
	return _live != null and _live.last_heart_rate_t >= 0.0 \
			and Time.get_ticks_msec() / 1000.0 - _live.last_heart_rate_t < 3.0


## One line for the HR readout and the log: which pipeline is driving what.
func status_text() -> String:
	match source_mode:
		SourceMode.MOCK:
			return "MOCK trace '%s'" % mock_trace
		SourceMode.DEV_MOUSE:
			return "DEV_MOUSE (mouse head, %s)" % ("OSC heart rate" if _osc_heart_rate else "fixed 70 bpm")
	return "LIVE :%d  head=%s  hr=%s" % [
		live_port,
		"EmotiBit" if live_orientation_active() else "mouse (no live data)",
		"EmotiBit" if live_heart_rate_active() else "none yet",
	]


func _on_fallback_orientation(euler: Vector3) -> void:
	if not live_orientation_active():
		orientation_updated.emit(euler)


func _on_fallback_pitch_rate(rate: float) -> void:
	if not live_orientation_active():
		pitch_rate_updated.emit(rate)


func _on_pitch_rate_sample(rate: float) -> void:
	pitch_rate_updated.emit(rate)


func _on_orientation_sample(euler: Vector3) -> void:
	orientation_updated.emit(euler)


## osc_receiver.gd: a real bpm. The first one drops any baseline built on the
## source's stand-in rate, and from then on the stand-in is ignored.
func set_osc_heart_rate(bpm: float) -> void:
	if not _osc_heart_rate:
		_osc_heart_rate = true
		_baseline_samples.clear()
		_baseline_elapsed = 0.0
		_baseline_done = false
		resting_bpm = -1.0
	_report_heart_rate(bpm, true)


func _on_heart_rate_sample(bpm: float, valid: bool) -> void:
	if not _osc_heart_rate:
		_report_heart_rate(bpm, valid)


func _report_heart_rate(bpm: float, valid: bool) -> void:
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
