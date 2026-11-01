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
## After every recenter (key, controller button, or automatic), so the bat
## can confirm it audibly -- the player cannot see that it happened.
signal recentered()

## Keyboard C / DualSense touchpad click, bound in Project Settings.
const RECENTER_ACTION := &"recenter_head"

## Resting HR + this margin (bpm) counts as "elevated." Relative to baseline,
## never absolute BPM (§3.3) — this is a placeholder default, not a tuned
## value; real tuning needs playtest data (human task, §0.1).
@export var elevated_margin_bpm: float = 15.0

var orientation: Vector3 = Vector3.ZERO

## Yaw calibration: the physical player's real-world heading (the EmotiBit
## reports an absolute, magnetometer-referenced yaw) has nothing to do with
## how a level was authored. recenter() sets this so that wherever the
## player's head points right now becomes reference_yaw in the world.
## Everything that needs facing (AudioDirector's listener/bat source, player
## movement) reads effective_orientation(), never `orientation` directly, so
## there's exactly one place this gets applied.
var yaw_offset: float = 0.0

## The world yaw that "straight ahead" means right now: the level's forward
## at the spawn point, or the forward of whichever checkpoint the player was
## last placed at. Recentering points the player along it.
var reference_yaw: float = 0.0

## Current head position in world space, reported every physics frame by
## player.gd (pivot's position). Unthrottled -- unlike report_position()
## below, which feeds a 0.5s-cadence rolling window for confinement, FOCUS
## (§6.3, Phase 4) needs a fresh alignment check every frame.
var head_position: Vector3 = Vector3.ZERO

## Set by EventDirector for the duration of a scripted beat (Event 1's cold
## open, §10). Movement, the scan and FOCUS all check this rather than each
## being reached into and disabled individually, so there is one flag to
## clear and no way for a sequence to end leaving one of them still locked.
var input_locked: bool = false

## A sharp head movement: direction +1 up, -1 down. strength is the peak rate
## as a multiple of flick_min_rate_deg, so it starts at 1.0.
signal head_flicked(direction: int, strength: float)

## A flick has to be fast AND big: this pitch rate (deg/s) starts one, and it
## only counts once the head has travelled flick_min_travel_deg in that
## direction within flick_capture_seconds. Speed alone would pass a tiny twitch
## or a noisy sample; travel alone would pass a slow look up. Placeholders like
## the other thresholds: the real values need a headband on a real head.
@export var flick_min_rate_deg: float = 200.0
@export var flick_min_travel_deg: float = 25.0
@export var flick_capture_seconds: float = 0.3
## Dead time after a flick, so the head coming back doesn't read as another.
@export var flick_cooldown_seconds: float = 0.5

var _flick_direction: int = 0
var _flick_peak: float = 0.0
var _flick_travel: float = 0.0
var _t_flick_start: float = 0.0
var _t_pitch_sample: float = 0.0
var _t_next_flick: float = 0.0

## Multiplies walking speed. 1 everywhere except E4's climb, which is
## slower going (rockfall_climb.gd sets and resets it), so the shaft takes
## long enough for the rocks to be a section rather than two dodges.
var move_speed_scale: float = 1.0

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


var _was_live_orientation: bool = false

## What the sensor source last said, and the yaw added up from the scene OSC
## receiver. orientation is the two together: the source re-sends its value
## every frame, so anything written straight into orientation would be lost.
var _source_orientation: Vector3 = Vector3.ZERO
var _osc_yaw: float = 0.0
## Set by the first /Godot/elevated true/false. From then on that decides
## hr_elevated, not the bpm comparison.
var _elevated_from_osc: bool = false


func _ready() -> void:
	SensorBridge.orientation_updated.connect(_on_orientation_updated)
	SensorBridge.heart_rate_updated.connect(_on_heart_rate_updated)
	SensorBridge.pitch_rate_updated.connect(_on_pitch_rate_updated)


## osc_receiver_imu.gd: a change in head yaw, in radians.
func add_head_turn(yaw: float) -> void:
	_osc_yaw += yaw
	orientation.y += yaw


## osc_receiver_imu.gd: the head's pitch rate in rad/s, positive = up. Rate only:
## pitch stays out of orientation, so looking up or down can't skew FOCUS (§6.1).
func add_head_pitch_change(rate: float) -> void:
	_on_pitch_rate_updated(rate)


## osc_receiver.gd: the elevated state decided outside the game.
func set_osc_elevated(elevated: bool) -> void:
	_elevated_from_osc = true
	_set_elevated(elevated)


func _set_elevated(elevated: bool) -> void:
	if elevated != hr_elevated:
		hr_elevated = elevated
		elevated_changed.emit(hr_elevated)


func _on_orientation_updated(euler: Vector3) -> void:
	_source_orientation = euler
	orientation = euler + Vector3(0.0, _osc_yaw, 0.0)
	# The first live sample replaces the mouse's yaw with the headband's
	# absolute one, which would swing the world by however far apart they
	# happen to be. Recentering on that handover keeps the player facing
	# where they were facing.
	var live := SensorBridge.live_orientation_active()
	if live and not _was_live_orientation:
		recenter()
	_was_live_orientation = live


## Detects flicks from the rate of the head's pitch, not its angle: how far the
## head is tilted says nothing about how sharply it moved, and on the headband
## the rate is the one pitch measure that doesn't depend on the mounting.
func _on_pitch_rate_updated(rate: float) -> void:
	# The mouse source reports an exact 0 every idle frame, even while the OSC
	# receiver is streaming; those would cut the time between real samples.
	if rate == 0.0:
		return
	var rate_deg := rad_to_deg(rate)
	var now := Time.get_ticks_msec() / 1000.0
	# Capped so a gap in the stream can't count as travel.
	var dt := minf(now - _t_pitch_sample, 0.1)
	_t_pitch_sample = now
	if _flick_direction == 0:
		if absf(rate_deg) >= flick_min_rate_deg and now >= _t_next_flick:
			_flick_direction = 1 if rate_deg > 0.0 else -1
			_flick_peak = absf(rate_deg)
			_flick_travel = 0.0
			_t_flick_start = now
		return

	_flick_peak = maxf(_flick_peak, rate_deg * _flick_direction)
	_flick_travel += rate_deg * _flick_direction * dt
	if _flick_travel >= flick_min_travel_deg:
		head_flicked.emit(_flick_direction, _flick_peak / flick_min_rate_deg)
		_flick_direction = 0
		_t_next_flick = now + flick_cooldown_seconds
	elif now - _t_flick_start >= flick_capture_seconds:
		_flick_direction = 0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(RECENTER_ACTION):
		recenter()
		get_viewport().set_input_as_handled()


## "Wherever I'm facing now is straight ahead": maps the current head yaw
## onto reference_yaw. Pitch is left alone -- only yaw drifts and only yaw
## steers.
func recenter() -> void:
	yaw_offset = reference_yaw - orientation.y
	recentered.emit()


## A scene or checkpoint saying which way "ahead" is. Recenters by default,
## so the player arrives facing it.
func set_reference_yaw(yaw: float, recenter_now: bool = true) -> void:
	reference_yaw = yaw
	if recenter_now:
		recenter()


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

	if not _elevated_from_osc:
		_set_elevated(bpm > SensorBridge.resting_bpm + elevated_margin_bpm)


func report_head_position(pos: Vector3) -> void:
	head_position = pos


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
