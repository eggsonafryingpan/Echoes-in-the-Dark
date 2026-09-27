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


# --- Event 1: the CALM cold open (§10) -----------------------------------
#
# Runs top to bottom. Each step is its own small function so the sequence
# reads as a list rather than one long coroutine:
#
#   lock      movement, scan and FOCUS off -- the player is on the ground
#   startle   falling whoosh, then the rock tumble landing on top of it
#   elevated  panicked breathing + fast audible heartbeat + bilateral pulse
#   prompt    the bat names the input (seeds it; never says "hold still")
#   calm      the Phase 5 CALM gate exactly as-is, not reimplemented here
#   resolve   bat confirms, environmental layer returns, controls unlock
#
# Skippable at any point (debug_skip_event). Whatever it is skipped from,
# _finish_event_one always unlocks and restores -- a demo must never be
# left with the controls locked because a step was cut short.

signal event_one_step(step: StringName)

const EVENT_ONE_STEPS: Array[StringName] = [
	&"lock", &"startle", &"elevated", &"prompt", &"calm", &"resolve",
]

## Beat lengths for the cold open. Short: this is the first 15 seconds a
## demoer ever hears, and §10 budgets Event 1 at ~2.5 min total with the
## CALM loop taking most of it.
@export var event_one_whoosh_seconds: float = 1.6
@export var event_one_tumble_seconds: float = 2.4
@export var event_one_prompt_seconds: float = 3.5

## Filming aid: with no EmotiBit connected there is no real heart rate to
## bring down, so debug_calm_assist starts a scripted descent that CALM
## reads in place of the sensor. Ramps rather than snapping, so a take
## looks like a recovery rather than a cheat.
@export var debug_hr_ramp_bpm_per_second: float = 6.0

var event_one_active: bool = false

## Playtesting: start past the cold open entirely. Set from the command
## line (`-- --skip-intro`) or the environment (ECHOES_SKIP_INTRO=1) so a
## tester can jump straight to exploration without editing anything; the
## main menu's F6 sets it for a single launch. Running
## echoes_in_the_dark.tscn directly (the editor's Run Current Scene) never
## queues Event 1 in the first place, so it needs neither.
var skip_intro: bool = false

var _event_one_skip: bool = false
## Bumped on every start and every skip, so a sequence still awaiting a
## timer when it was skipped wakes up, sees it is stale, and exits instead
## of running its next step on top of the game.
var _event_one_run: int = 0
var _event_one_pending: bool = false
var _debug_hr: float = -1.0
var _event_players: Dictionary = {}


## Called by the main menu on Start Game. The gameplay scene is not loaded
## yet at that point, so this only arms the event; _process starts it once
## the player exists (BatCompanion.head is set in player.gd's _ready).
func queue_event_one() -> void:
	if skip_intro:
		print("EventDirector: skipping Event 1 (skip_intro).")
		return
	_event_one_pending = true


func _ready() -> void:
	skip_intro = OS.get_cmdline_user_args().has("--skip-intro") \
			or OS.get_environment("ECHOES_SKIP_INTRO") == "1"


func _process(_delta: float) -> void:
	if _event_one_pending and BatCompanion.head != null:
		_event_one_pending = false
		start_event_one()


func start_event_one() -> void:
	if event_one_active:
		return
	event_one_active = true
	_event_one_skip = false
	_event_one_run += 1
	var run := _event_one_run
	event_started.emit(&"event_one")

	for step in EVENT_ONE_STEPS:
		if run != _event_one_run:
			return  # Skipped mid-step; skip_event_one already finished it.
		event_one_step.emit(step)
		await _run_event_one_step(step)

	if run == _event_one_run:
		_finish_event_one()


func _run_event_one_step(step: StringName) -> void:
	match step:
		&"lock":
			GameState.input_locked = true
		&"startle":
			_play_event_sfx(&"whoosh", &"event1_falling_whoosh")
			await _event_wait(event_one_whoosh_seconds)
			_play_event_sfx(&"tumble", &"event1_rock_tumble")
			await _event_wait(event_one_tumble_seconds)
		&"elevated":
			_play_event_sfx(&"breathing", &"breathing_panicked", true)
			_play_event_sfx(&"heartbeat", &"heartbeat_elevated", true)
			await _scripted_pulse()
		&"prompt":
			BatCompanion.say(&"event1_bat_startle")
			await _event_wait(event_one_prompt_seconds)
		&"calm":
			start_calm_event()
			while calm_active and not _event_one_skip:
				await get_tree().process_frame
		&"resolve":
			BatCompanion.say(&"calm_recovered")
			await _event_wait(1.0)


## Always runs, skipped or not. Anything the sequence turned on gets turned
## off here rather than at the end of the step that turned it on.
func _finish_event_one() -> void:
	if not event_one_active:
		return
	event_one_active = false
	_debug_hr = -1.0
	for player in _event_players.values():
		player.stop()
	# "Passage ambience opens on success" (§10): the environmental layer is
	# what that ambience lives on.
	AudioDirector.restore_environmental()
	GameState.input_locked = false
	if calm_active:
		_complete_calm(&"skipped")
	event_completed.emit(&"event_one")


## Immediate: finishes now rather than after the current step's timers run
## out, so F6 during the startle does not leave four more seconds of rock
## fall and a bat line playing over the unlocked game.
func skip_event_one() -> void:
	if not event_one_active:
		return
	_event_one_skip = true
	_event_one_run += 1
	BatCompanion.shut_up()
	_finish_event_one()
	print("EventDirector: Event 1 skipped.")


## §10's "scripted fast bilateral pulse" -- before CALM starts, so it is a
## fixed panic rhythm rather than _update_bilateral_heartbeat's live rate.
func _scripted_pulse() -> void:
	for i in 8:
		if _event_one_skip:
			return
		for device in Input.get_connected_joypads():
			Input.start_joy_vibration(device, 0.8, 0.8, 0.1)
		await _event_wait(0.32)


## Event SFX go to Priority: these are the current objective's sources for
## the duration of the beat, and a scripted cold open that the overload
## detector could fade mid-take would be unusable for filming. Nothing here
## touches the goal music's own routing.
func _play_event_sfx(key: StringName, sfx_name: StringName, looping: bool = false) -> void:
	if not _event_players.has(key):
		var player := AudioStreamPlayer.new()
		player.name = "Event_%s" % key
		player.bus = AudioDirector.BUS_PRIORITY
		add_child(player)
		_event_players[key] = player

	var stream: AudioStream = SfxLibrary.get_stream(sfx_name)
	if looping and (stream is AudioStreamMP3 or stream is AudioStreamOggVorbis):
		stream.loop = true
	_event_players[key].stream = stream
	_event_players[key].play()


func _event_wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout


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
	var bpm := _current_bpm(delta)
	if bpm > 0.0:
		if _calm_start_bpm < 0.0:
			_calm_start_bpm = bpm
			_calm_smoothed_bpm = bpm
		else:
			_calm_smoothed_bpm = lerpf(_calm_smoothed_bpm, bpm, calm_smoothing)

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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_calm_assist"):
		start_calm_assist()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"debug_skip_event"):
		skip_event_one()
		get_viewport().set_input_as_handled()


## Filming / no-hardware path: hands CALM a scripted descent starting from
## wherever the rate currently is, so the drop reads as continuous rather
## than as a jump the moment the key is pressed. The other no-hardware
## path is SensorBridge.source_mode = MOCK with the startled_then_calming
## trace, which drives the same numbers from a recorded script.
func start_calm_assist() -> void:
	if _debug_hr >= 0.0:
		return
	_debug_hr = _calm_smoothed_bpm if _calm_smoothed_bpm > 0.0 else 130.0


## The heart rate CALM actually reads: normally the motion-gated sensor
## value, or the scripted descent while the filming assist is running.
func _current_bpm(delta: float) -> float:
	if _debug_hr >= 0.0:
		_debug_hr = maxf(_debug_hr - debug_hr_ramp_bpm_per_second * delta, 40.0)
		return _debug_hr
	if GameState.hr_valid and GameState.hr_bpm > 0.0:
		return GameState.hr_bpm
	return -1.0


## Snapshot for the playtest HR readout (hr_debug_overlay.gd). Read-only;
## nothing on the audio path consults it.
func calm_readout() -> Dictionary:
	var relax_t: float = clampf(_calm_t / calm_relax_seconds, 0.0, 1.0)
	return {
		"active": calm_active,
		"t": _calm_t,
		"start_bpm": _calm_start_bpm,
		"smoothed_bpm": _calm_smoothed_bpm,
		"required_drop": lerpf(calm_generous_drop_bpm, calm_relaxed_drop_bpm, relax_t),
		"dwell_seconds": calm_dwell_seconds,
		"fail_forward_seconds": calm_fail_forward_seconds,
		"assist_bpm": _debug_hr,
	}


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
		# Pre-rendered clip by id, spatialized on the bat's shoulder, rather
		# than runtime TTS. The wording lives in voices/lines.txt under
		# calm_guide and can change there without touching this file.
		BatCompanion.say(&"calm_guide")


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
