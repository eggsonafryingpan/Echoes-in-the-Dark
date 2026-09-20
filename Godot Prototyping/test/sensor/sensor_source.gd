class_name SensorSource
extends Node

## Base interface for where SensorBridge gets its data from (brief
## CLAUDE_CODE_BRIEF.md §3.5). Two implementations: LiveOSCSource (real
## EmotiBit data via the Python sensor bridge) and MockSource (canned
## traces, no hardware). Build and test everything against MockSource first.

## euler is (pitch, yaw, roll) in radians, matching Node3D.rotation's axis
## order, so SensorBridge can forward it without remapping.
signal orientation_sample(euler: Vector3)

## valid is false whenever the head was moving too much to trust the PPG
## reading (§3.2) -- bpm should be ignored when valid is false.
signal heart_rate_sample(bpm: float, valid: bool)


func start() -> void:
	pass


func stop() -> void:
	pass
