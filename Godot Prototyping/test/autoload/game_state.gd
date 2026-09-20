extends Node

## Autoload this as "GameState". Brief: CLAUDE_CODE_BRIEF.md §2, §13 Phase 1+.
##
## The derived state every other system reads instead of touching SensorBridge
## or gameplay nodes directly: current orientation, whether HR is currently
## valid (motion-gated stillness), HR trend relative to baseline, the
## elevated flag, and the collision / disorientation counters OverloadDetector
## needs for its behavioral half (§5).
##
## This node does not decide anything by itself — it is a shared read model.
## OverloadDetector reads it to decide overload; EventDirector and
## AudioDirector read it for context. Keeping the decision logic out of here
## is what will let the existing "Stuck" prototype's behavioral counters (no
## progress / collisions / confinement) drop in as one input among several
## once OverloadDetector exists (Phase 3) — that phase migrates Stuck's logic
## here rather than duplicating it.

signal elevated_changed(is_elevated: bool)
signal still_changed(is_still: bool)

## Resting HR + this margin (bpm) counts as "elevated." Relative to baseline,
## never absolute BPM (§3.3) — this is a placeholder default, not a tuned
## value; real tuning needs playtest data (human task, §0.1).
@export var elevated_margin_bpm: float = 15.0

var orientation: Vector3 = Vector3.ZERO
var is_still: bool = false
var hr_valid: bool = false
var hr_bpm: float = -1.0
var hr_elevated: bool = false

## Behavioral evidence inputs for OverloadDetector (§5). Populated by the
## navigation/collision system (§6.1) and event logic.
var collision_count: int = 0
var disorientation_count: int = 0


func _ready() -> void:
	SensorBridge.orientation_updated.connect(_on_orientation_updated)
	SensorBridge.heart_rate_updated.connect(_on_heart_rate_updated)


func _on_orientation_updated(euler: Vector3) -> void:
	orientation = euler


func _on_heart_rate_updated(bpm: float, valid: bool) -> void:
	if valid != is_still:
		is_still = valid
		still_changed.emit(is_still)

	hr_valid = valid
	if not valid:
		# Motion-gated out -- keep the last trustworthy reading and elevated
		# state rather than flapping on noise (§3.2: state transitions are
		# evaluated only on settled data).
		return

	hr_bpm = bpm
	if SensorBridge.resting_bpm < 0.0:
		return  # baseline not established yet

	var elevated := bpm > SensorBridge.resting_bpm + elevated_margin_bpm
	if elevated != hr_elevated:
		hr_elevated = elevated
		elevated_changed.emit(hr_elevated)


func report_collision() -> void:
	# Phase 3: fold into a rolling window, same pattern as Stuck._collisions.
	collision_count += 1


func reset_counters() -> void:
	collision_count = 0
	disorientation_count = 0
