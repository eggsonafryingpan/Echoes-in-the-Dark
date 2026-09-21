extends Node

## Autoload this as "OverloadDetector". Brief: CLAUDE_CODE_BRIEF.md §5, §13 Phase 3.
##
## Conjunctive detector: fires only when BOTH hold --
##   1. HR elevated above session baseline (motion-gated reads only, via
##      GameState.hr_elevated), AND
##   2. behavioral evidence of struggle -- GameState's migrated "Stuck"
##      counters (repeated wall collisions, no reduction in distance to the
##      objective, confinement/circling), at least behavioral_threshold of
##      those 3 signals.
##
## This never fires on HR alone -- structurally, not just by convention:
## behavioral_count is computed entirely from GameState's non-HR counters,
## so raw_condition can only be true if at least behavioral_threshold of
## them are already true, regardless of HR. It never claims to measure
## cognitive load, and identifies a STATE, not a quantity (§0.1, §5):
## real-time cognitive-load inference from consumer wearables isn't
## established, and arousal is hard to separate from cognitive demand.
##
## Debounce/hysteresis: the raw conjunction must hold continuously for
## debounce_seconds before firing overload_detected() (so one stray signal
## blip doesn't flip the state), and must clear continuously for
## recovery_hold_seconds before firing recovered() (so the benefit doesn't
## flicker on and off as signals hover near the threshold).
##
## Arbitration: whatever runs a CALM sequence (Phase 5, or EventDirector
## once it sequences events) sets suppress_during_calm = true while active,
## because CALM *expects* elevated HR and stripping ambience then would
## fight the mechanic it's supposed to support (§5, §8).
##
## The A/B adaptive toggle (§11) is NOT gated here -- this always evaluates
## and logs so the observer HUD/backend can show what the detector *would*
## do, even with adaptation off. AudioDirector.strip_environmental()/
## strip_essential() are what silently no-op when adaptive_enabled is false.

signal overload_detected()
signal recovered()

## Emitted every evaluation tick with the raw signal breakdown, for the
## sighted-observer HUD (§11, Phase 9) and the paper's writeup (§11.1: what
## counts as high-complexity audio and how it's determined).
signal evaluated(signals: Dictionary)

var enabled: bool = true

## Set by whatever runs a CALM sequence (§5 arbitration).
var suppress_during_calm: bool = false

@export var behavioral_threshold: int = 2
@export var debounce_seconds: float = 1.5
@export var recovery_hold_seconds: float = 4.0
@export var eval_interval: float = 0.5

var _overloaded: bool = false
var _t: float = 0.0
var _next_eval: float = 0.0
var _t_condition_true_since: float = -1.0
var _t_condition_false_since: float = -1.0

## Rolling log for the observer HUD/writeup -- capped so it never grows
## unbounded across a long session.
const _LOG_CAP := 200
var evaluation_log: Array[Dictionary] = []


func _physics_process(delta: float) -> void:
	_t += delta
	if not enabled or suppress_during_calm:
		return
	if _t < _next_eval:
		return
	_next_eval = _t + eval_interval
	_evaluate()


func _evaluate() -> void:
	var no_progress: bool = GameState.seconds_since_progress() > GameState.no_progress_seconds
	var collisions: bool = GameState.recent_collision_count() >= GameState.collision_threshold
	var confined: bool = GameState.is_confined()
	var behavioral_count: int = int(no_progress) + int(collisions) + int(confined)
	var behavioral_met: bool = behavioral_count >= behavioral_threshold and behavioral_count >= 1

	var hr_elevated: bool = GameState.hr_elevated
	var raw_condition: bool = hr_elevated and behavioral_met

	var log_entry := {
		"t": _t,
		"hr_elevated": hr_elevated,
		"no_progress": no_progress,
		"collisions": collisions,
		"confined": confined,
		"behavioral_count": behavioral_count,
		"raw_condition": raw_condition,
		"overloaded": _overloaded,
	}
	evaluation_log.append(log_entry)
	if evaluation_log.size() > _LOG_CAP:
		evaluation_log.pop_front()
	evaluated.emit(log_entry)

	_advance_state(raw_condition)


func _advance_state(raw_condition: bool) -> void:
	if raw_condition:
		_t_condition_false_since = -1.0
		if _t_condition_true_since < 0.0:
			_t_condition_true_since = _t
		if not _overloaded and _t - _t_condition_true_since >= debounce_seconds:
			_overloaded = true
			# Environmental first, essential second, leaving priority
			# isolated (§4, §5). AudioDirector itself no-ops these if the
			# A/B toggle has adaptation off.
			AudioDirector.strip_environmental()
			AudioDirector.strip_essential()
			overload_detected.emit()
	else:
		_t_condition_true_since = -1.0
		if _t_condition_false_since < 0.0:
			_t_condition_false_since = _t
		if _overloaded and _t - _t_condition_false_since >= recovery_hold_seconds:
			_overloaded = false
			# Restore in the opposite order (§4).
			AudioDirector.restore_essential()
			AudioDirector.restore_environmental()
			recovered.emit()
