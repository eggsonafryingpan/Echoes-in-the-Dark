extends Node

## The controller's two body signals, mixed so they never cancel each other:
##
##   heartbeat  a PULSE in both grips at the player's own heart rate, smoothed
##              so it drifts with them rather than jumping per beat.
##   wall       a STEADY rumble in the grip on the side the wall is on, for
##              exactly as long as the player is pressed against it.
##
## Godot's rumble call replaces whatever the motors were doing, so the two
## can't be sent separately: a pulse would cut off the wall rumble and the
## wall's next refresh would swallow the pulse. While either is on, this sends
## one combined level per frame. The pulse rides on top of the steady rumble,
## so contact still has a felt heartbeat through it.
##
## DualSense motors (see haptics.gd): the strong motor is the LEFT grip, the
## weak motor the RIGHT grip. No controller connected: nothing happens.
##
## Added by player.gd; player.gd reports wall contact through set_wall().

# ------------------------------------------------------------------------
# HAPTICS CONFIG
# ------------------------------------------------------------------------
@export_group("Heartbeat")
@export var heartbeat_enabled: bool = true
## How quickly the pulse follows a change in heart rate: the time to cover
## about two thirds of a change. Bigger is smoother and slower to follow.
@export var heartbeat_smoothing_seconds: float = 1.5
## Pulses per heartbeat. 1 is one pulse per beat; 0.5 halves the tempo.
@export var pulses_per_beat: float = 1.0
## Heart rates outside this range are held at its edges.
@export var heartbeat_min_bpm: float = 45.0
@export var heartbeat_max_bpm: float = 170.0
## Pulse strength at the low and high ends of that range: a racing heart
## pulses harder as well as faster.
@export var heartbeat_strength_low: float = 0.35
@export var heartbeat_strength_high: float = 0.9
@export var pulse_seconds: float = 0.12
## The heartbeat only runs while the player is calming down: the whole of
## Event 1 from the first rock crash, and any CALM (the stealth encounter).
## Walking around, the controller is still except for walls. Off: always on.
@export var heartbeat_only_while_calming: bool = true

@export_group("Wall contact")
@export var wall_strength: float = 0.55
## A wall closer to straight ahead than this (sideways share of the
## direction, 0-1) rumbles both grips.
@export var wall_ahead_share: float = 0.35
## The rumble is re-sent this often (seconds) while nothing changes, rather
## than every frame, which some controller connections drop.
@export var refresh_seconds: float = 0.2
@export_group("")

## What the motors were last told, for tests and the readout: 0-1 per grip.
var left_level: float = 0.0
var right_level: float = 0.0
var smoothed_bpm: float = -1.0

var _wall_side: int = 0   # -1 left, +1 right, 2 both, 0 none
var _until_pulse: float = 0.0
var _pulse_left: float = 0.0
var _driving: bool = false
var _sent_left: float = -1.0
var _sent_right: float = -1.0
var _until_refresh: float = 0.0


## side: -1 left, 1 right, 2 straight ahead (both), 0 no contact.
func set_wall(side: int) -> void:
	_wall_side = side


## Which grip a contact point belongs to, relative to where the head faces.
func side_of(contact_point: Vector3, head_position: Vector3, head_yaw: float) -> int:
	var to_wall := contact_point - head_position
	to_wall.y = 0.0
	if to_wall.length() < 0.01:
		return 2
	var local := Basis.from_euler(Vector3(0.0, head_yaw, 0.0)).inverse() * to_wall.normalized()
	if absf(local.x) < wall_ahead_share:
		return 2
	return -1 if local.x < 0.0 else 1


func _physics_process(delta: float) -> void:
	_update_heartbeat(delta)
	var pulse := 0.0
	if _pulse_left > 0.0:
		_pulse_left -= delta
		pulse = _pulse_strength()
	var wall_l := wall_strength if _wall_side == -1 or _wall_side == 2 else 0.0
	var wall_r := wall_strength if _wall_side == 1 or _wall_side == 2 else 0.0
	left_level = clampf(maxf(wall_l, pulse) + (pulse * 0.5 if wall_l > 0.0 else 0.0), 0.0, 1.0)
	right_level = clampf(maxf(wall_r, pulse) + (pulse * 0.5 if wall_r > 0.0 else 0.0), 0.0, 1.0)

	if left_level > 0.0 or right_level > 0.0:
		_driving = true
		_until_refresh -= delta
		var changed := not is_equal_approx(left_level, _sent_left) or not is_equal_approx(right_level, _sent_right)
		if changed or _until_refresh <= 0.0:
			_sent_left = left_level
			_sent_right = right_level
			_until_refresh = refresh_seconds
			for device in Input.get_connected_joypads():
				# Lasts past the next refresh, so it never gaps; stops promptly
				# if this node goes away.
				Input.start_joy_vibration(device, right_level, left_level, refresh_seconds * 2.5)
	elif _driving:
		_driving = false
		_sent_left = -1.0
		_sent_right = -1.0
		for device in Input.get_connected_joypads():
			Input.stop_joy_vibration(device)


func _update_heartbeat(delta: float) -> void:
	var bpm := _heart_rate()
	if bpm > 0.0:
		bpm = clampf(bpm, heartbeat_min_bpm, heartbeat_max_bpm)
		if smoothed_bpm < 0.0:
			smoothed_bpm = bpm
		else:
			smoothed_bpm += (bpm - smoothed_bpm) * (1.0 - exp(-delta / maxf(heartbeat_smoothing_seconds, 0.01)))
	if not heartbeat_enabled or smoothed_bpm < 0.0 or _suppressed():
		return
	_until_pulse -= delta
	if _until_pulse <= 0.0:
		_until_pulse = beat_interval()
		_pulse_left = pulse_seconds


## Seconds between pulses at the current smoothed rate.
func beat_interval() -> float:
	return 60.0 / maxf(smoothed_bpm, 1.0) / maxf(pulses_per_beat, 0.01)


func _pulse_strength() -> float:
	var t := inverse_lerp(heartbeat_min_bpm, heartbeat_max_bpm, smoothed_bpm)
	return lerpf(heartbeat_strength_low, heartbeat_strength_high, clampf(t, 0.0, 1.0))


## The F4 assist's scripted rate while it runs, else the last valid reading.
## A motion-gated (invalid) sample keeps the previous rate rather than
## dropping the pulse.
func _heart_rate() -> float:
	var debug := EventDirector.debug_hr()
	if debug >= 0.0:
		return debug
	return GameState.hr_bpm


## Off outside the calm-down moments, when heartbeat_only_while_calming.
func _suppressed() -> bool:
	if not heartbeat_only_while_calming:
		return false
	return not (EventDirector.event_one_active or EventDirector.calm_active)
