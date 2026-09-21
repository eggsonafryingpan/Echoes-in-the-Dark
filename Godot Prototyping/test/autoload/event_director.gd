extends Node

## Autoload this as "EventDirector". Brief: CLAUDE_CODE_BRIEF.md §7, §8, §10, §13 Phases 5-7.
##
## Sequences the three-event demo arc (CALM -> FOCUS -> REVEAL, §10) and owns
## each event's pass logic and anti-lockout timers (§7 FOCUS, §8 CALM). No
## mechanic may hard-lock the player out (§1, §14) — every event here MUST
## have a time-based fail-forward regardless of tuning.
##
## Also owns the suppress_during_calm flag on OverloadDetector: set it true
## for the duration of an active CALM sequence, false otherwise (§5), since
## CALM *expects* elevated HR and stripping ambience then would fight the
## mechanic it's supposed to support.
##
## Full event sequencing (CALM -> FOCUS -> REVEAL, §10, §13 Phase 7) is not
## built yet -- start_calm_event()/calm_completed are a self-contained,
## independently-testable CALM implementation (§13 Phase 5) that whatever
## builds Phase 7's sequencing will call at the right narrative moment.
## FOCUS itself is a per-object component (focusable.gd, §13 Phase 4), not
## owned here, for the same reason: it's a property of individual objects,
## not a single sequenced state.

signal event_started(event_id: StringName)
signal event_completed(event_id: StringName)

enum Event { CALM, FOCUS, REVEAL }

var current_event: Event = Event.CALM


func start_event(_event: Event) -> void:
	pass  # Phase 7: sequence in, set OverloadDetector.suppress_during_calm for CALM.


# --- CALM (§8, §13 Phase 5) ----------------------------------------------
#
# Escalation ladder, all present, not just one:
#   1. Start-of-event reference; downward trend from it (motion-gated,
#      heavily smoothed -- see calm_smoothing).
#   2. Generous threshold at t=0 (calm_generous_drop_bpm).
#   3. Auto-relax: the required drop shrinks toward calm_relaxed_drop_bpm
#      over calm_relax_seconds.
#   4. OR conditions: HR-drop OR dwell time alone (calm_dwell_seconds).
#      Breathing-slowing is NOT implemented as a separate OR-branch --
#      no sensor in this pipeline reports respiration (brief §3.1: EDA and
#      temperature are unused, and respiration is explicitly "not
#      required" -- SensorBridge only ever forwards orientation + HR).
#      Flagged here rather than faked with an invented signal.
#   5. Escalating in-fiction assistance: bat's own breathing grows audible
#      (calm_hint_1_seconds), then a spoken guided count
#      (calm_hint_2_seconds) -- never "hold still"; the guide produces the
#      calming, it doesn't request it.
#   6. Fail-forward timeout (calm_fail_forward_seconds): completes
#      regardless. No lockout is structurally possible.
#
# Controller pulse (§6.2): bilateral, identical magnitude on every
# connected joypad (non-directional -- reads as physiological state, not
# a spatial cue), pulsing at the smoothed live rate throughout, win or
# lose, so success feels genuinely the player's own.

signal calm_progress(fraction: float)
signal calm_completed(reason: StringName)  # &"hr_drop" | &"dwell" | &"fail_forward"

@export var calm_generous_drop_bpm: float = 5.0
@export var calm_relaxed_drop_bpm: float = 1.5
@export var calm_relax_seconds: float = 15.0
@export var calm_dwell_seconds: float = 18.0
@export var calm_fail_forward_seconds: float = 28.0
## Exponential-smoothing coefficient applied once per physics tick to a
## fresh valid HR sample -- "heavily smoothed" per §8, not a raw reading.
@export var calm_smoothing: float = 0.03
@export var calm_hint_1_seconds: float = 8.0
@export var calm_hint_2_seconds: float = 16.0

var calm_active: bool = false

var _calm_t: float = 0.0
var _calm_start_bpm: float = -1.0
var _calm_smoothed_bpm: float = -1.0
var _calm_hint1_fired: bool = false
var _calm_hint2_fired: bool = false
var _next_pulse_t: float = 0.0


## Call once when a CALM sequence begins (Phase 7's sequencer, or a test).
func start_calm_event() -> void:
	calm_active = true
	_calm_t = 0.0
	_calm_start_bpm = -1.0
	_calm_smoothed_bpm = -1.0
	_calm_hint1_fired = false
	_calm_hint2_fired = false
	_next_pulse_t = 0.0
	OverloadDetector.suppress_during_calm = true
	event_started.emit(&"calm")


func _physics_process(delta: float) -> void:
	if not calm_active:
		return
	_calm_t += delta

	# Motion-gated: only a trustworthy, valid HR sample updates the
	# reference/smoothed trend (§3.2, §8 "motion-gated windows only").
	if GameState.hr_valid and GameState.hr_bpm > 0.0:
		if _calm_start_bpm < 0.0:
			_calm_start_bpm = GameState.hr_bpm
			_calm_smoothed_bpm = GameState.hr_bpm
		else:
			_calm_smoothed_bpm = lerpf(_calm_smoothed_bpm, GameState.hr_bpm, calm_smoothing)

	_update_bilateral_heartbeat()
	_update_escalation()

	var relax_t: float = clampf(_calm_t / calm_relax_seconds, 0.0, 1.0)
	var required_drop: float = lerpf(calm_generous_drop_bpm, calm_relaxed_drop_bpm, relax_t)

	var hr_drop_ok: bool = _calm_start_bpm > 0.0 and (_calm_start_bpm - _calm_smoothed_bpm) >= required_drop
	var dwell_ok: bool = _calm_t >= calm_dwell_seconds
	var fail_forward: bool = _calm_t >= calm_fail_forward_seconds

	calm_progress.emit(clampf(_calm_t / calm_fail_forward_seconds, 0.0, 1.0))

	if hr_drop_ok or dwell_ok or fail_forward:
		var reason: StringName = &"fail_forward"
		if hr_drop_ok:
			reason = &"hr_drop"
		elif dwell_ok:
			reason = &"dwell"
		_complete_calm(reason)


func _complete_calm(reason: StringName) -> void:
	calm_active = false
	OverloadDetector.suppress_during_calm = false
	calm_completed.emit(reason)
	event_completed.emit(&"calm")


## Bat's own breathing grows audible, then a guided count -- escalating
## in-fiction help, never an instruction to hold still (§8).
func _update_escalation() -> void:
	if not _calm_hint1_fired and _calm_t >= calm_hint_1_seconds:
		_calm_hint1_fired = true
		if AudioDirector.bat_source != null:
			AudioDirector.bat_source.stream = SfxLibrary.get_stream(&"breathing_calm")
			AudioDirector.bat_source.volume_db = -6.0
			AudioDirector.bat_source.play()
	if not _calm_hint2_fired and _calm_t >= calm_hint_2_seconds:
		_calm_hint2_fired = true
		Bat.say("Slow it down with me. In... and out...", "calm_guide")


## Bilateral (§6.2): identical magnitude on every connected joypad, pulsed
## at the smoothed live rate. No device connected -> harmless no-op.
func _update_bilateral_heartbeat() -> void:
	if _calm_smoothed_bpm <= 0.0 or _calm_t < _next_pulse_t:
		return
	var interval: float = 60.0 / _calm_smoothed_bpm
	_next_pulse_t = _calm_t + interval
	var intensity: float = clampf((_calm_smoothed_bpm - 40.0) / 100.0, 0.1, 1.0)
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, intensity, intensity, 0.12)
