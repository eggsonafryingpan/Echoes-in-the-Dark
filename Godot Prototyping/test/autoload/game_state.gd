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
## AudioDirector read it for context.
##
## The behavioral counters below are the "Stuck" prototype's tracking,
## migrated here rather than duplicated (§13 Phase 3): rolling-window
## collision counting, no-progress-toward-objective tracking, and
## confinement/circling detection. OverloadDetector owns the DECISION
## (thresholds, HR conjunction, hysteresis); this just tracks the raw
## windows, fed by whatever's doing navigation each physics frame
## (player.gd calls report_collision()/report_position()/
## report_distance_to_objective()).
##
## Note: Stuck's actual third signal was confinement (circling within a
## small radius), not the brief's literal "few object interactions" -- there
## is no object-interaction tracking anywhere in this codebase to migrate.
## Confinement is kept as the existing, working proxy; flagged for whoever
## wants a real interaction counter later.

signal elevated_changed(is_elevated: bool)
signal still_changed(is_still: bool)

## Resting HR + this margin (bpm) counts as "elevated." Relative to baseline,
## never absolute BPM (§3.3) — this is a placeholder default, not a tuned
## value; real tuning needs playtest data (human task, §0.1).
@export var elevated_margin_bpm: float = 15.0

var orientation: Vector3 = Vector3.ZERO

## Per-scene calibration offset (yaw only): the physical player's real-world
## heading at boot is arbitrary and has nothing to do with how a given level
## was authored, so a scene's spawn point sets this once (see player.gd's
## spawn_yaw_offset) to align yaw=0 with "forward into the level." Everything
## that needs facing (AudioDirector's listener/bat source, player movement)
## should read effective_orientation(), never `orientation` directly, so
## there's exactly one place this gets applied.
var yaw_offset: float = 0.0

var is_still: bool = false
var hr_valid: bool = false
var hr_bpm: float = -1.0
var hr_elevated: bool = false

## Unused so far -- no system increments this yet. Left in place rather than
## removed as unrelated scope creep; OverloadDetector's behavioral test
## doesn't use it (see confinement/collisions/no-progress below).
var disorientation_count: int = 0

## --- Behavioral tracking migrated from "Stuck" (§13 Phase 3) -------------

@export var behavior_window_seconds: float = 20.0
@export var confinement_radius: float = 3.0
@export var no_progress_seconds: float = 25.0
@export var collision_window_seconds: float = 15.0
@export var collision_threshold: int = 4

const _SAMPLE_INTERVAL := 0.5

var _collision_times: Array[float] = []
var _position_samples: Array = []  # [{t: float, pos: Vector3}]
var _next_position_sample_t: float = 0.0
var _best_distance_to_objective: float = INF
var _t_best_distance: float = -1.0


func _ready() -> void:
	SensorBridge.orientation_updated.connect(_on_orientation_updated)
	SensorBridge.heart_rate_updated.connect(_on_heart_rate_updated)


func _on_orientation_updated(euler: Vector3) -> void:
	orientation = euler


## orientation with the scene's yaw calibration applied -- read this, not
## `orientation`, for anything that renders or moves relative to facing.
func effective_orientation() -> Vector3:
	return orientation + Vector3(0.0, yaw_offset, 0.0)


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


## Call from the navigation/collision system on every wall hit.
func report_collision() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_collision_times.append(now)
	_trim_collisions(now)


## Call once per physics frame from the navigation system with the player's
## current position, for confinement/circling detection. Internally
## throttled to _SAMPLE_INTERVAL, same cadence Stuck used.
func report_position(pos: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_position_sample_t:
		return
	_next_position_sample_t = now + _SAMPLE_INTERVAL
	_position_samples.append({"t": now, "pos": pos})
	_trim_positions(now)


## Call once per physics frame with the current distance to the level's
## objective (e.g. player.global_position.distance_to(exit_marker.global_position)).
## Tracks the best (smallest) distance seen and when it was last improved.
func report_distance_to_objective(distance: float) -> void:
	if distance < _best_distance_to_objective - 0.5:
		_best_distance_to_objective = distance
		_t_best_distance = Time.get_ticks_msec() / 1000.0


## True once collision_threshold hits have landed within collision_window_seconds.
## A single stray collision can never satisfy this on its own (§13 Phase 3
## spike debounce) -- the threshold itself is the debounce.
func recent_collision_count() -> int:
	_trim_collisions(Time.get_ticks_msec() / 1000.0)
	return _collision_times.size()


## Seconds since distance-to-objective last improved. 0 until the first
## report_distance_to_objective() call, so this never falsely reads as
## "stuck" before navigation tracking has even started.
func seconds_since_progress() -> float:
	if _t_best_distance < 0.0:
		return 0.0
	return (Time.get_ticks_msec() / 1000.0) - _t_best_distance


## True when the player has stayed within confinement_radius of their own
## recent-average position for most of behavior_window_seconds -- circling
## rather than exploring. Needs a mostly-full window before it means
## anything, same as Stuck._confined().
func is_confined() -> bool:
	var expected := int(behavior_window_seconds / _SAMPLE_INTERVAL)
	if _position_samples.size() < int(expected * 0.8):
		return false

	var centre := Vector3.ZERO
	for s in _position_samples:
		centre += s.pos
	centre /= float(_position_samples.size())

	var max_r := 0.0
	for s in _position_samples:
		max_r = maxf(max_r, centre.distance_to(s.pos))
	return max_r < confinement_radius


func _trim_collisions(now: float) -> void:
	while _collision_times.size() > 0 and now - _collision_times[0] > collision_window_seconds:
		_collision_times.pop_front()


func _trim_positions(now: float) -> void:
	while _position_samples.size() > 0 and now - _position_samples[0].t > behavior_window_seconds:
		_position_samples.pop_front()


func reset_counters() -> void:
	disorientation_count = 0
	_collision_times.clear()
	_position_samples.clear()
	_best_distance_to_objective = INF
	_t_best_distance = -1.0
