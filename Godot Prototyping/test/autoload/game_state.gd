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

## Whether the latest recenter came from the player's key or button.
var recenter_was_manual: bool = false

## The player's notes: discoveries they actually made this run, in order, each
## {id, text, line}. The end screen shows the text and the bat reads each line.
signal observation_recorded(id: StringName)
var observations: Array[Dictionary] = []
## SfxLibrary name and level of the "added to notes" cue.
@export var notes_sound: String = "notes_added"
@export var notes_volume_db: float = 2.0
## Seconds after a discovery before the notes sound, so the discovery sting
## and the bat's reveal line come first.
@export var notes_feedback_delay: float = 3.0
## The bat's short line after the notes sound. Empty for none.
@export var note_added_line: StringName = &"note_added"
signal notes_feedback_played()
var _notes_player: AudioStreamPlayer = null

## Set by EventDirector for the duration of a scripted beat (Event 1's cold
## open, §10). Movement, the scan and FOCUS all check this rather than each
## being reached into and disabled individually, so there is one flag to
## clear and no way for a sequence to end leaving one of them still locked.
var input_locked: bool = false

## A sharp head movement: direction +1 up, -1 down. strength is the peak rate
## as a multiple of flick_min_rate_deg, so it starts at 1.0.
signal head_flicked(direction: int, strength: float)

## A side-to-side head turn, part of a shake. swings counts the turns in this
## shake so far, each the opposite way to the last.
signal head_shaken(swings: int)

# ------------------------------------------------------------------------
# HEAD GESTURES CONFIG
# ------------------------------------------------------------------------
## A flick has to be fast AND big: the pitch rate (deg/s) has to pass the
## rate threshold, and the head has to have travelled the travel threshold
## that way within flick_capture_seconds. Travel counts the whole movement,
## including its start before it was fast.
##
## Live and mouse get separate thresholds. The EmotiBit's gyro is sampled at
## 25 Hz, which clips the peaks of a fast movement, so a real head reads slower
## than the same movement on the mouse.
@export_group("Head flick (river jump, stealth headbutt)")
@export var flick_min_rate_deg: float = 200.0
@export var flick_min_travel_deg: float = 25.0
@export var flick_min_rate_deg_live: float = 110.0
@export var flick_min_travel_deg_live: float = 18.0
@export var flick_capture_seconds: float = 0.35
## Dead time after a flick, so the head coming back doesn't read as another.
@export var flick_cooldown_seconds: float = 0.5
## The bridge's IMU rate. Live samples arrive in bunches, so each is timed as
## one sample period rather than by when it happened to arrive.
@export var live_sample_hz: float = 25.0
## Print each fast movement that fell short, with its peak and travel, so the
## thresholds can be tuned on a real head.
@export var log_near_miss_flicks: bool = true

@export_group("Head nod (minigame repeats)")
## Pitch speed (deg/s) a gentle nod must pass, down and then back up.
@export var nod_rate_deg: float = 60.0
@export var nod_rate_deg_live: float = 45.0

@export_group("Gesture calibration")
## Written by the tutorial's calibration, read here at launch. Calibrated
## values replace the defaults above for that input (live or mouse); up and
## down flicks are calibrated separately (jolt up, headbutt).
@export var calibration_path: String = "user://gesture_calibration.cfg"
@export var use_calibration: bool = true

@export_group("Head shake (swarm)")
## A swing counts once the yaw rate passes this (deg/s) and the head has
## turned shake_min_swing_deg that way.
@export var shake_min_rate_deg: float = 90.0
@export var shake_min_swing_deg: float = 12.0
## A single turn bigger than this is looking around, not shaking: it resets the
## count instead of adding to it. This is what keeps an ordinary head turn
## from reading as a shake (a shake also needs alternating swings).
@export var shake_max_swing_deg: float = 70.0
## A shake ends if the next swing takes longer than this.
@export var shake_gap_seconds: float = 0.8
@export_group("")

## Calibrated values, by input ("live"/"mouse") then key: up_rate, up_travel,
## down_rate, down_travel, nod_rate. Empty until calibrated.
var calibration: Dictionary = {}

## [time, rate_deg, dt] per pitch sample, newest last, on the sample clock.
var _pitch_samples: Array = []
var _flick_direction: int = 0
var _t_flick_armed: float = 0.0
var _t_next_flick: float = 0.0
var _t_pitch_arrival: float = 0.0
## Advances by one sample's length per sample, so a bunched packet still
## spans the time it covered. Never behind real time, so it keeps moving
## across gaps with no samples (the mouse sends none while still).
var _sample_clock: float = 0.0

var _t_yaw_arrival: float = 0.0
var _last_yaw: float = 0.0
var _have_yaw: bool = false
var _swing_dir: int = 0
var _swing_travel: float = 0.0
var _swing_peak: float = 0.0
var _swing_counted: bool = false
var _shake_swings: int = 0
var _t_last_swing: float = -INF
var _yaw_clock: float = 0.0

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
	load_calibration()
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
	_detect_shake(orientation.y)
	# The first live sample replaces the mouse's yaw with the headband's
	# absolute one, which would swing the world by however far apart they
	# happen to be. Recentering on that handover keeps the player facing
	# where they were facing.
	var live := SensorBridge.live_orientation_active()
	if live and not _was_live_orientation:
		recenter()
	_was_live_orientation = live


## Seconds this sample covers. Live: one sample period, whatever the arrival
## time. Mouse: the time since the last sample, as the mouse reports once per
## frame -- except the first after a pause, which gets one frame's worth
## rather than the whole pause.
func _sample_dt(t_last_arrival: float, now: float) -> float:
	if SensorBridge.live_orientation_active():
		return 1.0 / maxf(live_sample_hz, 1.0)
	var gap := now - t_last_arrival
	return gap if gap <= 0.1 else 1.0 / 60.0


## Detects flicks from the rate of the head's pitch, not its angle: how far the
## head is tilted says nothing about how sharply it moved, and on the headband
## the rate is the one pitch measure that doesn't depend on the mounting.
func _on_pitch_rate_updated(rate: float) -> void:
	# The mouse source reports an exact 0 every idle frame, even while the OSC
	# receiver is streaming; those would cut the time between real samples.
	if rate == 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var dt := _sample_dt(_t_pitch_arrival, now)
	_t_pitch_arrival = now
	_sample_clock = maxf(_sample_clock + dt, now)
	var rate_deg := rad_to_deg(rate)
	_pitch_samples.append([_sample_clock, rate_deg, dt])
	while _pitch_samples.size() > 0 and _sample_clock - _pitch_samples[0][0] > flick_capture_seconds:
		_pitch_samples.pop_front()
	if _sample_clock < _t_next_flick:
		return

	var live := SensorBridge.live_orientation_active()
	if _flick_direction == 0:
		var dir := 1 if rate_deg > 0.0 else -1
		if absf(rate_deg) < flick_threshold(dir, "rate"):
			return
		_flick_direction = dir
		_t_flick_armed = _sample_clock
	var min_rate := flick_threshold(_flick_direction, "rate")
	var min_travel := flick_threshold(_flick_direction, "travel")

	var travel := 0.0
	var peak := 0.0
	for sample in _pitch_samples:
		var along: float = sample[1] * _flick_direction
		if along > 0.0:
			travel += along * sample[2]
			peak = maxf(peak, along)
	if travel >= min_travel:
		head_flicked.emit(_flick_direction, peak / min_rate)
		_flick_direction = 0
		_pitch_samples.clear()
		_t_next_flick = _sample_clock + flick_cooldown_seconds
	elif _sample_clock - _t_flick_armed >= flick_capture_seconds:
		if log_near_miss_flicks and peak > 0.0:
			print("GameState: flick %s fell short: peak %.0f deg/s, travel %.0f of %.0f deg (%s)" % [
				"up" if _flick_direction > 0 else "down", peak, travel, min_travel, "live" if live else "mouse"])
		_flick_direction = 0


## Swings for a head shake, from how fast the yaw changes. Timed like the
## flicks, so bunched live samples read at their real speed.
func _detect_shake(yaw: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var dt := _sample_dt(_t_yaw_arrival, now)
	_t_yaw_arrival = now
	if not _have_yaw or dt <= 0.0:
		_have_yaw = true
		_last_yaw = yaw
		return
	_yaw_clock = maxf(_yaw_clock + dt, now)
	var rate_deg := rad_to_deg(wrapf(yaw - _last_yaw, -PI, PI)) / dt
	_last_yaw = yaw
	var dir := signi(int(signf(rate_deg)))
	if dir == 0:
		return
	if dir != _swing_dir:
		_swing_dir = dir
		_swing_travel = 0.0
		_swing_peak = 0.0
		_swing_counted = false
	_swing_travel += absf(rate_deg) * dt
	_swing_peak = maxf(_swing_peak, absf(rate_deg))
	if _swing_travel > shake_threshold("max_swing"):
		if _shake_swings > 0:
			_shake_swings = 0  # a big look-around, not a shake
		_swing_counted = true
		return
	if _swing_counted or _swing_peak < shake_threshold("rate") or _swing_travel < shake_threshold("swing"):
		return
	_swing_counted = true
	if _yaw_clock - _t_last_swing > shake_gap_seconds:
		_shake_swings = 0
	_shake_swings += 1
	_t_last_swing = _yaw_clock
	head_shaken.emit(_shake_swings)


## Adds a note, once per id. False if it was already there. The "added to
## notes" sound (and, with announce, the bat's short line) comes once the
## discovery has landed: after feedback_delay seconds and once the bat is
## quiet, so it never sits on top of the discovery sting or the reveal line.
## feedback_delay < 0 uses notes_feedback_delay.
func record_observation(id: StringName, text: String, line: StringName,
		announce: bool = true, feedback_delay: float = -1.0) -> bool:
	for note in observations:
		if note.id == id:
			return false
	observations.append({"id": id, "text": text, "line": line})
	print("GameState: observation recorded: %s" % text)
	observation_recorded.emit(id)
	_notes_feedback(announce, notes_feedback_delay if feedback_delay < 0.0 else feedback_delay)
	return true


func _notes_feedback(announce: bool, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var waited := 0.0
	while BatCompanion.is_speaking() and waited < 20.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_play_notes_sound()
	notes_feedback_played.emit()
	if announce and note_added_line != &"":
		await get_tree().create_timer(0.5).timeout
		BatCompanion.say(note_added_line)


## The "added to notes" cue: its own sound, never the discovery sting. UI bus,
## like the rest of the player's own feedback, so overload never removes it.
func _play_notes_sound() -> void:
	if _notes_player == null:
		_notes_player = AudioStreamPlayer.new()
		_notes_player.name = "NotesSound"
		_notes_player.bus = AudioDirector.BUS_UI
		add_child(_notes_player)
	_notes_player.stream = SfxLibrary.get_stream(notes_sound)
	_notes_player.volume_db = notes_volume_db
	_notes_player.play()


## Changes an existing note (the frog count going up). Plays the notes sound,
## without the bat's "noted" line. False if there is no such note.
func update_observation(id: StringName, text: String, line: StringName) -> bool:
	for note in observations:
		if note.id == id:
			note.text = text
			note.line = line
			print("GameState: observation updated: %s" % text)
			_notes_feedback(false, notes_feedback_delay)
			return true
	return false


func clear_observations() -> void:
	observations.clear()


# --- Gesture thresholds and calibration --------------------------------------

func _input_key() -> String:
	return "live" if SensorBridge.live_orientation_active() else "mouse"


## The flick threshold in use: direction +1 up, -1 down; what is "rate"
## (deg/s) or "travel" (deg). Calibrated if there is a value, else the exports.
func flick_threshold(direction: int, what: String) -> float:
	var key := ("up_" if direction > 0 else "down_") + what
	var cal: Dictionary = calibration.get(_input_key(), {})
	if use_calibration and cal.has(key):
		return cal[key]
	var live := _input_key() == "live"
	if what == "rate":
		return flick_min_rate_deg_live if live else flick_min_rate_deg
	return flick_min_travel_deg_live if live else flick_min_travel_deg


## Shake thresholds in use: what is "rate" (deg/s a swing must reach),
## "swing" (deg it must turn) or "max_swing" (deg past which it's a look-around).
func shake_threshold(what: String) -> float:
	var cal: Dictionary = calibration.get(_input_key(), {})
	if use_calibration and cal.has("shake_" + what):
		return cal["shake_" + what]
	match what:
		"rate":
			return shake_min_rate_deg
		"swing":
			return shake_min_swing_deg
	return shake_max_swing_deg


## The nod threshold in use (deg/s), shared with the minigame.
func nod_threshold() -> float:
	var cal: Dictionary = calibration.get(_input_key(), {})
	if use_calibration and cal.has("nod_rate"):
		return cal.nod_rate
	return nod_rate_deg_live if _input_key() == "live" else nod_rate_deg


## Stores calibrated values for the current input and saves them to disk, so
## the game, the minigame and the next launch all use them.
func save_calibration(values: Dictionary) -> String:
	var key := _input_key()
	var merged: Dictionary = calibration.get(key, {})
	merged.merge(values, true)
	calibration[key] = merged
	var file := ConfigFile.new()
	for input in calibration:
		for k in calibration[input]:
			file.set_value(input, k, calibration[input][k])
	var err := file.save(calibration_path)
	print("GameState: calibration saved for %s input: %s (%s)" % [key, merged, error_string(err)])
	return key


func load_calibration() -> void:
	calibration.clear()
	var file := ConfigFile.new()
	if file.load(calibration_path) != OK:
		return
	for input in file.get_sections():
		calibration[input] = {}
		for k in file.get_section_keys(input):
			calibration[input][k] = float(file.get_value(input, k))
	print("GameState: loaded gesture calibration: %s" % calibration)


## Starts the next shake count from zero.
func reset_shake() -> void:
	_shake_swings = 0
	_t_last_swing = -INF


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(RECENTER_ACTION):
		recenter(true)
		get_viewport().set_input_as_handled()


## "Wherever I'm facing now is straight ahead": maps the current head yaw
## onto reference_yaw. Pitch is left alone -- only yaw drifts and only yaw
## steers. manual is true when the player asked for it; the bat only ticks
## for those (a scene load or a sensor reconnect is not the player's doing).
func recenter(manual: bool = false) -> void:
	recenter_was_manual = manual
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
