extends Node

## Autoload this as "EventDirector". Brief: CLAUDE_CODE_BRIEF.md §7, §8, §10, §13 Phases 5-7.
##
## Sequences the escape arc, E1 -> E4 (story as of 2026-10: get out of the
## cave by following the wind; supersedes the brief's music ending):
##
##   E1 CALM     fall in, bring the heart rate down       (this file)
##   E2 FOCUS    pick the outside wind out of the noise   (escape_level.gd)
##   E3 STEALTH  stay calm while an animal passes         (stealth_encounter.gd)
##   E4 ESCAPE   dodge falling rocks up the climb         (rockfall_climb.gd)
##
## Event 1 lives here because it needs nothing from a level. Events 2-4 need
## the level's geometry, so the level runs them and reports in through
## begin()/complete(); this file only tracks which event the run is on and
## owns the keys that move between them. No mechanic may hard-lock the
## player out (§1, §14) -- every event has a fail-forward regardless of
## tuning.
##
## Playtest keys (all events):
##   F6           skip: finish the current event now (or start the armed one)
##   Ctrl+1..4    jump straight to Event 1..4 (teleports to its checkpoint)
##   F11          force a failure (stealth: caught now; climb: hit now)
##   F4           CALM assist: a scripted heart-rate descent (E1 and E3)
## Launch straight into an event: `-- --event=3` or ECHOES_EVENT=3.
##
## Also owns the suppress_during_calm flag on OverloadDetector: true for the
## duration of any CALM sequence (E1, and E3's encounter), since CALM
## *expects* elevated HR and stripping ambience then would fight it (§5).

signal event_started(event_id: StringName)
signal event_completed(event_id: StringName)

enum Event { CALM, FOCUS, STEALTH, ESCAPE, DONE }

const EVENT_IDS: Array[StringName] = [&"event_one", &"event_two", &"event_three", &"event_four", &"done"]
const EVENT_NAMES: Array[String] = ["E1 CALM", "E2 FOCUS", "E3 STEALTH", "E4 ESCAPE", "DONE"]

## The event the run is on: running if event_running, otherwise armed and
## waiting for the player to reach its trigger.
var current_event: Event = Event.CALM
var event_running: bool = false

## The level running Events 2-4 (escape_level.gd), registered from its
## _ready. Null in scenes that only have Event 1 (the old cave), where the
## jump keys just say so.
var level: Node = null

## Launch-time jump target (1-4), from --event=N / ECHOES_EVENT. 0 = start
## from the top. Consumed by the level when it registers.
var start_at_event: int = 0


func event_name(event: Event) -> String:
	return EVENT_NAMES[event]


## A level reporting that one of its events has started.
func begin(event: Event) -> void:
	current_event = event
	event_running = true
	print("EventDirector: %s started" % event_name(event))
	event_started.emit(EVENT_IDS[event])


## A level (or Event 1 below) reporting an event done. Arms the next one.
func complete(event: Event) -> void:
	if event != current_event:
		return
	event_running = false
	print("EventDirector: %s complete" % event_name(event))
	event_completed.emit(EVENT_IDS[event])
	current_event = mini(event + 1, Event.DONE) as Event


## Called by a level from its _ready. Decides where the run starts: a
## launch-time --event jump, past Event 1 (skip_intro), or Event 1 itself.
func register_level(new_level: Node) -> void:
	level = new_level
	current_event = Event.CALM
	event_running = false
	var target := start_at_event
	start_at_event = 0
	if target >= 2:
		_event_one_pending = false
		level.call_deferred(&"jump_to", (target - 1) as Event)
	elif skip_intro:
		_event_one_pending = false
		current_event = Event.FOCUS
		print("EventDirector: skipping Event 1 (skip_intro).")
	else:
		_event_one_pending = true


## Ctrl+1..4. Leaves whatever is running, cleanly, and starts the target.
func jump_to(event: Event) -> void:
	if level == null:
		print("EventDirector: no escape level in this scene; jump keys do nothing here.")
		return
	if event_one_active:
		skip_event_one(false)
	if calm_active:
		stop_calm_event(&"jumped")
	level.jump_to(event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_calm_assist"):
		start_calm_assist()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"debug_skip_event"):
		_skip_current()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"debug_force_fail"):
		if level != null:
			level.force_fail(current_event)
		get_viewport().set_input_as_handled()
	else:
		for i in 4:
			if event.is_action_pressed(StringName("jump_event_%d" % (i + 1))):
				jump_to(i as Event)
				get_viewport().set_input_as_handled()
				return


## F6: finish the running event now; with nothing running, start the armed
## one where the player stands rather than making them walk to its trigger.
func _skip_current() -> void:
	if event_one_active:
		skip_event_one()
		return
	if level == null:
		return
	if event_running:
		level.skip_event(current_event)
	elif current_event != Event.DONE:
		jump_to(current_event)


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
# One sound at a time, as far as the story allows: each step hands over
# from the last one (the whoosh fades as the tumble lands, the tumble fades
# as the breathing takes over), spoken lines are waited out rather than
# timed, and nothing is ever cut -- the end of the sequence fades whatever
# is still playing.
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
## How long the whoosh takes to give way to the tumble, and the tumble to
## the panicked breathing. Both recordings run far longer than their beat.
@export var event_one_handover_seconds: float = 1.2
## Longest a spoken line is waited out before the sequence moves on anyway.
@export var event_one_line_timeout: float = 8.0
## Silence after the startle line, before CALM starts listening.
@export var event_one_prompt_gap: float = 0.6
## Fade on whatever is still playing when Event 1 ends (0.3 s when skipped).
@export var event_one_end_fade_seconds: float = 1.5

## Filming aid: with no EmotiBit connected there is no real heart rate to
## bring down, so debug_calm_assist starts a scripted descent that CALM
## reads in place of the sensor. Ramps rather than snapping, so a take
## looks like a recovery rather than a cheat.
@export var debug_hr_ramp_bpm_per_second: float = 6.0

var event_one_active: bool = false

## Playtesting: start past the cold open entirely. Set from the command
## line (`-- --skip-intro`) or the environment (ECHOES_SKIP_INTRO=1) so a
## tester can jump straight to exploration without editing anything; the
## main menu's F6 sets it for a single launch.
var skip_intro: bool = false

var _event_one_skip: bool = false
## Bumped on every start and every skip, so a sequence still awaiting a
## timer when it was skipped wakes up, sees it is stale, and exits instead
## of running its next step on top of the game.
var _event_one_run: int = 0
var _event_one_pending: bool = false
var _debug_hr: float = -1.0
var _event_players: Dictionary = {}
var _event_fades: Dictionary = {}
var _missing_sfx_warned: Dictionary = {}


## Called by the main menu on Start Game. The gameplay scene is not loaded
## yet at that point, so this only arms the event; _process starts it once
## the player exists (BatCompanion.head is set in player.gd's _ready).
func queue_event_one() -> void:
	if skip_intro:
		print("EventDirector: skipping Event 1 (skip_intro).")
		return
	_event_one_pending = true


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	skip_intro = args.has("--skip-intro") or OS.get_environment("ECHOES_SKIP_INTRO") == "1"
	var event_arg := OS.get_environment("ECHOES_EVENT")
	for arg in args:
		if arg.begins_with("--event="):
			event_arg = arg.trim_prefix("--event=")
	if event_arg.is_valid_int():
		start_at_event = clampi(event_arg.to_int(), 1, 4)


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
	begin(Event.CALM)

	for step in EVENT_ONE_STEPS:
		if run != _event_one_run:
			return  # Skipped mid-step; skip_event_one already finished it.
		event_one_step.emit(step)
		await _run_event_one_step(step)

	if run == _event_one_run:
		_finish_event_one(event_one_end_fade_seconds)


func _run_event_one_step(step: StringName) -> void:
	match step:
		&"lock":
			GameState.input_locked = true
		&"startle":
			_play_event_sfx(&"whoosh", &"event1_falling_whoosh")
			await _event_wait(event_one_whoosh_seconds)
			_play_event_sfx(&"tumble", &"event1_rock_tumble")
			_fade_out_event_sfx(&"whoosh", event_one_handover_seconds)
			await _event_wait(event_one_tumble_seconds)
		&"elevated":
			_fade_out_event_sfx(&"tumble", event_one_handover_seconds)
			_play_event_sfx(&"breathing", &"breathing_panicked", true)
			_play_event_sfx(&"heartbeat", &"heartbeat_elevated", true)
			await _scripted_pulse()
		&"prompt":
			BatCompanion.say(&"event1_bat_startle")
			await _await_bat_quiet(event_one_line_timeout)
			await _event_wait(event_one_prompt_gap)
		&"calm":
			start_calm_event()
			while calm_active and not _event_one_skip:
				await get_tree().process_frame
		&"resolve":
			BatCompanion.say(&"calm_recovered")
			await _await_bat_quiet(event_one_line_timeout)


## Always runs, skipped or not. Anything the sequence turned on gets faded
## here rather than at the end of the step that turned it on.
func _finish_event_one(fade_seconds: float) -> void:
	if not event_one_active:
		return
	event_one_active = false
	_debug_hr = -1.0
	for key in _event_players:
		_fade_out_event_sfx(key, fade_seconds)
	# "Passage ambience opens on success" (§10): the environmental layer is
	# what that ambience lives on.
	AudioDirector.restore_environmental()
	GameState.input_locked = false
	if calm_active:
		_complete_calm(&"skipped")
	complete(Event.CALM)


## Immediate: finishes now rather than after the current step's timers run
## out, so F6 during the startle does not leave four more seconds of rock
## fall and a bat line playing over the unlocked game.
func skip_event_one(announce: bool = true) -> void:
	if not event_one_active:
		return
	_event_one_skip = true
	_event_one_run += 1
	BatCompanion.shut_up()
	_finish_event_one(0.3)
	if announce:
		print("EventDirector: Event 1 skipped.")


## §10's "scripted fast bilateral pulse" -- before CALM starts, so it is a
## fixed panic rhythm rather than _update_bilateral_heartbeat's live rate.
func _scripted_pulse() -> void:
	for i in 8:
		if _event_one_skip:
			return
		Haptics.pulse_both(0.8, 0.1)
		await _event_wait(0.32)


## Waits until the bat has finished everything queued, or timeout seconds,
## whichever is first -- a line's length is the clip's business, not a
## number guessed here.
func _await_bat_quiet(timeout: float) -> void:
	var t := 0.0
	await get_tree().process_frame  # say() may still be queuing
	while BatCompanion.is_speaking() and t < timeout and not _event_one_skip:
		await get_tree().process_frame
		t += get_process_delta_time()


## Event SFX go to Priority: these are the current objective's sources for
## the duration of the beat, and a scripted cold open that the overload
## detector could fade mid-take would be unusable for filming.
##
## A name with no delivered asset is skipped entirely (missing = silent).
## Warned once per name so the gap stays visible in the log.
func _play_event_sfx(key: StringName, sfx_name: StringName, looping: bool = false,
		volume_db: float = 0.0) -> void:
	if not SfxLibrary.has_stream(sfx_name):
		if not _missing_sfx_warned.has(sfx_name):
			_missing_sfx_warned[sfx_name] = true
			push_warning("EventDirector: '%s' has no asset yet; skipping it." % sfx_name)
		return

	_kill_event_fade(key)
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
	_event_players[key].volume_db = volume_db
	_event_players[key].play()


## Fade, then stop -- never a cut (§4). No-op for a key that isn't playing.
func _fade_out_event_sfx(key: StringName, seconds: float) -> void:
	if not _event_players.has(key) or not _event_players[key].playing:
		return
	_kill_event_fade(key)
	var player: AudioStreamPlayer = _event_players[key]
	var tween := create_tween()
	_event_fades[key] = tween
	tween.tween_property(player, "volume_db", -60.0, seconds)
	tween.tween_callback(player.stop)


## A gentle level change on a still-playing event sound (the CALM breathing
## ducking under the bat's guided count).
func _fade_event_sfx_to(key: StringName, volume_db: float, seconds: float) -> void:
	if not _event_players.has(key) or not _event_players[key].playing:
		return
	_kill_event_fade(key)
	var tween := create_tween()
	_event_fades[key] = tween
	tween.tween_property(_event_players[key], "volume_db", volume_db, seconds)


func _kill_event_fade(key: StringName) -> void:
	if _event_fades.has(key) and is_instance_valid(_event_fades[key]):
		_event_fades[key].kill()
	_event_fades.erase(key)


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
# The same machinery runs during E3's stealth encounter, started with
# self_completing = false: the reference, smoothing, heartbeat pulse and
# coaching all run, but the encounter decides pass/fail itself (from
# calm_drop()) and ends it with stop_calm_event().
#
# Controller pulse (§6.2): bilateral, identical magnitude in both grips
# (non-directional -- reads as physiological state, not a spatial cue),
# pulsing at the smoothed live rate throughout, win or lose, so success
# feels genuinely the player's own.

signal calm_progress(fraction: float)
signal calm_completed(reason: StringName)  # &"hr_drop" | &"dwell" | &"fail_forward" | &"skipped" | ...

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

## The breathing to follow. breathing.mp3 is a very quiet recording (peaks
## around -33 dBFS), so it needs most of this gain just to reach the level
## of the other event sounds.
@export var calm_breathing_volume_db: float = 24.0
## The player's own panicked breathing fades out over this long as the
## breathing to follow comes in. Two breathing rhythms at once gave no
## clear one to match.
@export var calm_breathing_crossfade_seconds: float = 1.5
## How far the breathing dips while the bat is talking over it, so the
## guided count is heard rather than fought.
@export var calm_breathing_duck_db: float = 9.0

var calm_active: bool = false

var _calm_t: float = 0.0
var _calm_start_bpm: float = -1.0
var _calm_smoothed_bpm: float = -1.0
var _calm_hint1_fired: bool = false
var _calm_hint2_fired: bool = false
var _calm_self_completing: bool = true
var _calm_ducked: bool = false
var _next_pulse_t: float = 0.0


## Call once when a CALM sequence begins. self_completing = false hands the
## pass/fail decision to the caller (E3), which ends it with stop_calm_event().
func start_calm_event(self_completing: bool = true) -> void:
	calm_active = true
	_calm_self_completing = self_completing
	_calm_t = 0.0
	_calm_start_bpm = -1.0
	_calm_smoothed_bpm = -1.0
	_calm_hint1_fired = false
	_calm_hint2_fired = false
	_calm_ducked = false
	_next_pulse_t = 0.0
	OverloadDetector.suppress_during_calm = true
	event_started.emit(&"calm")


## Ends a CALM sequence from outside (E3's verdict, a jump). No-op if none.
func stop_calm_event(reason: StringName) -> void:
	if calm_active:
		_complete_calm(reason)


## How far the smoothed rate has come down from this sequence's own
## starting rate, in bpm. 0 until there is a reading.
func calm_drop() -> float:
	if _calm_start_bpm <= 0.0:
		return 0.0
	return _calm_start_bpm - _calm_smoothed_bpm


func calm_has_reading() -> bool:
	return _calm_start_bpm > 0.0


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
	_update_breathing_duck()

	if not _calm_self_completing:
		return

	var relax_t: float = clampf(_calm_t / calm_relax_seconds, 0.0, 1.0)
	var required_drop: float = lerpf(calm_generous_drop_bpm, calm_relaxed_drop_bpm, relax_t)

	var hr_drop_ok: bool = _calm_start_bpm > 0.0 and (_calm_start_bpm - _calm_smoothed_bpm) >= required_drop
	var dwell_ok: bool = _calm_t >= calm_dwell_seconds
	var fail_forward: bool = _calm_t >= calm_fail_forward_seconds

	calm_progress.emit(clampf(_calm_t / calm_fail_forward_seconds, 0.0, 1.0))

	if hr_drop_ok or dwell_ok or fail_forward:
		# Never resolve over the top of the guided count: the "recovered"
		# line would queue straight behind it and the two would run together.
		# Waited out up to a hard cap, so this can delay but never block.
		if BatCompanion.is_speaking() and _calm_t < calm_fail_forward_seconds + event_one_line_timeout:
			return
		var reason: StringName = &"fail_forward"
		if hr_drop_ok:
			reason = &"hr_drop"
		elif dwell_ok:
			reason = &"dwell"
		_complete_calm(reason)


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
	_debug_hr = -1.0
	OverloadDetector.suppress_during_calm = false
	_fade_out_event_sfx(&"calm_breathing", calm_breathing_crossfade_seconds)
	_fade_out_event_sfx(&"breathing", calm_breathing_crossfade_seconds)
	calm_completed.emit(reason)
	event_completed.emit(&"calm")


## Bat's own breathing grows audible, then a guided count -- escalating
## in-fiction help, never an instruction to hold still (§8).
func _update_escalation() -> void:
	if not _calm_hint1_fired and _calm_t >= calm_hint_1_seconds:
		_calm_hint1_fired = true
		# Hand over, not layer: the panicked loop goes as the slow one
		# arrives, so there is exactly one breath to follow.
		_fade_out_event_sfx(&"breathing", calm_breathing_crossfade_seconds)
		_play_event_sfx(&"calm_breathing", &"breathing_calm", true, -40.0)
		_fade_event_sfx_to(&"calm_breathing", calm_breathing_volume_db, calm_breathing_crossfade_seconds)
	if not _calm_hint2_fired and _calm_t >= calm_hint_2_seconds:
		_calm_hint2_fired = true
		# Pre-rendered clip by id, spatialized on the bat's shoulder, rather
		# than runtime TTS. The wording lives in voices/lines.txt under
		# calm_guide and can change there without touching this file.
		BatCompanion.say(&"calm_guide")


## The breathing steps back while the bat speaks and returns after, so the
## guided count sits on top of it instead of fighting it.
func _update_breathing_duck() -> void:
	var speaking := BatCompanion.is_speaking()
	if speaking == _calm_ducked or not _calm_hint1_fired:
		return
	_calm_ducked = speaking
	var target := calm_breathing_volume_db - (calm_breathing_duck_db if speaking else 0.0)
	_fade_event_sfx_to(&"calm_breathing", target, 0.4)


## Bilateral (§6.2): identical magnitude in both grips, pulsed at the
## smoothed live rate. No device connected -> harmless no-op.
func _update_bilateral_heartbeat() -> void:
	if _calm_smoothed_bpm <= 0.0 or _calm_t < _next_pulse_t:
		return
	var interval: float = 60.0 / _calm_smoothed_bpm
	_next_pulse_t = _calm_t + interval
	var intensity: float = clampf((_calm_smoothed_bpm - 40.0) / 100.0, 0.1, 1.0)
	Haptics.pulse_both(intensity, 0.12)
