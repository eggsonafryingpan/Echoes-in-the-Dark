extends Node3D

## E4: STEALTH. Something big walks past; stay calm and it never notices.
##
## Walking into the trigger zone freezes the player (input_locked) and starts
## CALM in non-self-completing mode (EventDirector.start_calm_event(false)):
## the heartbeat pulse, the breathing guide and the bat's guided count all
## run exactly as in E1. The animal walks from its start marker to its
## closest-approach marker over approach_seconds; at that moment the
## encounter decides:
##
##   PASS  the player is calm -- their smoothed rate has come down from
##         where it was when the animal appeared by at least the required
##         drop, OR they are simply not elevated above their resting
##         baseline. The animal walks on to its end marker; E3 complete.
##   FAIL  it spots the player and rushes them. The bat raises the alarm and
##         says to headbutt it: a sharp forward head flick (GameState's
##         head_flicked, downward) knocks it back, and the player flees on
##         along the route. E3 complete either way: no restart. If no headbutt
##         comes, the bat repeats itself, then the animal breaks off by itself
##         (anti-lockout).
##
## The player is locked for the whole of an encounter: from the moment they
## are in the zone until the animal has gone, or until they have landed and
## the bat has finished speaking. Free again means IDLE or DONE, nothing else.
## The zone is polled rather than signalled, so standing in it when the event
## arms starts the encounter too.
##
## F4 (CALM assist) makes the encounter pass; F11 makes it fail now. The
## required drop and auto_pass_attempt still apply if an encounter is replayed
## by a jump.
##
## The den reward (escape_level.den_found): the animal is heard from much
## further off (a longer approach, so more time to settle), it passes
## further from the player, and the required drop is lower.
##
## Debug: the animal is an orange sphere labelled with the encounter state;
## its path markers are small orange dots.

const Event := preload("res://autoload/event_director.gd").Event

enum State { IDLE, APPROACH, PASSING, SPOTTED, FLEEING, DONE }

@export var level_path: NodePath = ^".."
@export var trigger_path: NodePath
@export var retry_checkpoint_path: NodePath

## Normal path, and the farther path used once the den has been found.
@export var path_start: NodePath = ^"Path/Start"
@export var path_closest: NodePath = ^"Path/Closest"
@export var path_end: NodePath = ^"Path/End"
@export var den_path_start: NodePath = ^"DenPath/Start"
@export var den_path_closest: NodePath = ^"DenPath/Closest"
@export var den_path_end: NodePath = ^"DenPath/End"

@export var approach_seconds: float = 16.0
@export var den_approach_seconds: float = 24.0
@export var pass_seconds: float = 7.0
## How fast it rushes the player once it has noticed them.
@export var charge_seconds: float = 0.7
## Longest the player waits on the bat, once free of the animal, before
## getting control back.
@export var recover_timeout: float = 6.0

## Required drop (bpm) on attempt 1, 2, ... -- the last entry repeats.
@export var required_drop_by_attempt: Array[float] = [4.0, 2.0]
@export var den_drop_bonus: float = 1.5
@export var auto_pass_attempt: int = 3

# ------------------------------------------------------------------------
# CREATURE SOUND CONFIG
# ------------------------------------------------------------------------
@export_group("Creature sounds")
@export var footsteps_sfx: StringName = &"animal_footsteps"
@export var growl_sfx: StringName = &"animal_growl"
## Playback pitch. The old placeholders (human footsteps, breathing) were
## pitched far down to pass as an animal; the real creature recordings play
## as recorded.
@export var footsteps_pitch: float = 1.0
@export var growl_pitch: float = 1.0
## When it spots the player: lower and louder than its approach growl.
@export var spotted_growl_pitch: float = 0.9
@export var spotted_growl_db: float = 15.0
@export var footsteps_db: float = 7.0
@export var growl_db: float = 11.0
@export_group("")
@export var hit_sfx: StringName = &"wall_collision_thud"

@export var warn_line: StringName = &"e3_warning"
@export var warn_line_den: StringName = &"e3_warning_den"
@export var pass_line: StringName = &"e3_pass"

# ------------------------------------------------------------------------
# HEADBUTT CONFIG (spotted -> headbutt -> flee)
# ------------------------------------------------------------------------
@export_group("Headbutt")
## How hard the forward flick has to be, as a multiple of GameState's flick
## rate threshold (live or mouse). 1.0 is any flick it already recognises.
@export var headbutt_min_strength: float = 1.0
## The animal stops this far in front of the player's head when it rushes.
@export var spotted_distance: float = 1.8
## The bat says it again after this long without a headbutt...
@export var headbutt_reminder_seconds: float = 6.0
## ...and the animal breaks off by itself after this long (anti-lockout).
@export var headbutt_fail_forward_seconds: float = 15.0
## How far along the route the player flees, and how long it takes.
@export var flee_distance: float = 6.0
@export var flee_seconds: float = 1.6
@export var spotted_line: StringName = &"e3_spotted"
## Empty: the reminder repeats spotted_line.
@export var headbutt_again_line: StringName = &""
@export var headbutt_hit_line: StringName = &"e3_headbutt_hit"
@export_group("")

var state: State = State.IDLE
## 1-based once the first encounter starts.
var attempt: int = 0
var last_verdict: String = ""

var _level: Node = null
var _trigger: Area3D = null
var _animal: Node3D = null
var _steps: AudioStreamPlayer3D = null
var _growl: AudioStreamPlayer3D = null
var _hit: AudioStreamPlayer3D = null
var _label: Label3D = null
var _tween: Tween = null
var _force_fail: bool = false
var _reminded: bool = false
var last_headbutt: String = ""
var _t_state: float = 0.0
## Bumped when a recovery is abandoned, so one still waiting on the bat wakes
## up, sees it is stale and leaves the player alone.
var _run: int = 0


func _ready() -> void:
	_level = get_node(level_path)
	_trigger = get_node(trigger_path)

	_animal = Node3D.new()
	_animal.name = "Animal"
	add_child(_animal)
	DebugDraw.sphere(_animal, 0.8, Color(1.0, 0.45, 0.1))
	_label = DebugDraw.label(_animal, "", Vector3.UP * 1.4, Color(1.0, 0.6, 0.3))
	_steps = _make_player("Steps", footsteps_sfx, true, footsteps_pitch, footsteps_db)
	_growl = _make_player("Growl", growl_sfx, false, growl_pitch, growl_db)
	_hit = _make_player("Hit", hit_sfx, false, 0.8, 4.0)

	for path in [path_start, path_closest, path_end, den_path_start, den_path_closest, den_path_end]:
		var m := get_node_or_null(path) as Node3D
		if m != null:
			DebugDraw.sphere(m, 0.15, Color(1.0, 0.5, 0.1, 0.6))
	_reset_animal()
	GameState.head_flicked.connect(_on_head_flicked)


## Essential, not Environmental: a threat the player has to act on is not
## ambience. The overload detector is suppressed for the whole encounter
## anyway (CALM), so nothing strips it mid-approach.
func _make_player(node_name: String, sfx: StringName, loop: bool, pitch: float,
		volume_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	var stream: AudioStream = SfxLibrary.get_stream(sfx)
	if loop and (stream is AudioStreamMP3 or stream is AudioStreamOggVorbis):
		stream = stream.duplicate()
		stream.loop = true
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.bus = AudioDirector.BUS_ESSENTIAL
	p.max_db = 24.0  # the default +3 would cap the louder creature levels
	p.unit_size = 5.0
	p.max_distance = 40.0
	_animal.add_child(p)
	return p


func _process(delta: float) -> void:
	_t_state += delta
	var den: bool = _level.den_found
	var extra := ""
	if state == State.APPROACH:
		extra = "  %.0fs  drop %.1f / %.1f%s" % [
			_approach_time() - _t_state, EventDirector.calm_drop(), _required_drop(),
			"  (auto-pass)" if attempt >= auto_pass_attempt else ""]
	if state == State.SPOTTED:
		if not _reminded and _t_state >= headbutt_reminder_seconds:
			_reminded = true
			BatCompanion.say(headbutt_again_line if headbutt_again_line != &"" else spotted_line)
		if _t_state >= headbutt_fail_forward_seconds:
			last_headbutt = "no headbutt: it broke off by itself"
			_break_away()
	_label.text = "ANIMAL  %s  attempt %d%s%s%s" % [
		State.keys()[state], attempt, "  DEN" if den else "", extra,
		"\n" + last_verdict if last_verdict != "" else ""]


func _physics_process(_delta: float) -> void:
	if state == State.IDLE and EventDirector.current_event == Event.STEALTH \
			and _trigger.overlaps_body(_level.player):
		begin_encounter()


func begin_encounter() -> void:
	if state != State.IDLE:
		return
	if not EventDirector.event_running:
		EventDirector.begin(Event.STEALTH)
	attempt += 1
	_force_fail = false
	_set_state(State.APPROACH)
	GameState.input_locked = true
	EventDirector.start_calm_event(false)

	var den: bool = _level.den_found
	_reset_animal()
	_animal.visible = true
	_steps.play()
	_growl.play()
	BatCompanion.say(warn_line_den if den else warn_line)

	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_animal, "global_position", _marker(den_path_closest if den else path_closest),
			_approach_time()).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_decide)


## F11: during the approach, fail right now; otherwise the next decision fails.
func force_fail() -> void:
	_force_fail = true
	if state == State.APPROACH:
		_kill_tween()
		_decide()


## F6: the animal passes, now.
func skip() -> void:
	if state == State.DONE:
		return
	if state == State.IDLE:
		attempt += 1
		if not EventDirector.event_running:
			EventDirector.begin(Event.STEALTH)
	_run += 1
	_kill_tween()
	GameState.input_locked = true
	_pass()


## Back to armed, for a jump. Attempt count resets too: a jump is a fresh run.
func reset_encounter() -> void:
	_run += 1
	_kill_tween()
	EventDirector.stop_calm_event(&"reset")
	_steps.stop()
	attempt = 0
	last_verdict = ""
	_force_fail = false
	_set_state(State.IDLE)
	_reset_animal()


func _decide() -> void:
	var drop := EventDirector.calm_drop()
	var required := _required_drop()
	var calm_by_drop := EventDirector.calm_has_reading() and drop >= required
	var not_elevated := SensorBridge.resting_bpm > 0.0 and GameState.hr_valid and not GameState.hr_elevated
	var auto := attempt >= auto_pass_attempt
	var passed := (calm_by_drop or not_elevated or auto) and not (_force_fail and not auto)
	last_verdict = "attempt %d: %s (drop %.1f/%.1f%s%s%s)" % [
		attempt, "PASS" if passed else "CAUGHT", drop, required,
		", not elevated" if not_elevated else "", ", auto-pass" if auto else "",
		", forced fail" if _force_fail and not auto else ""]
	print("Stealth: " + last_verdict)
	if passed:
		_pass()
	else:
		_spotted()


func _pass() -> void:
	_set_state(State.PASSING)
	EventDirector.stop_calm_event(&"stealth_pass")
	var den: bool = _level.den_found
	_tween = create_tween()
	_tween.tween_property(_animal, "global_position", _marker(den_path_end if den else path_end), pass_seconds)
	_tween.parallel().tween_property(_steps, "volume_db", -40.0, pass_seconds).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_finish_pass)


func _finish_pass() -> void:
	_steps.stop()
	_animal.visible = false
	_set_state(State.DONE)
	GameState.input_locked = false
	BatCompanion.say(pass_line)
	EventDirector.complete(Event.STEALTH)


## It has noticed the player: it rushes in and stops right in front of them,
## and the bat says to headbutt it.
func _spotted() -> void:
	_set_state(State.SPOTTED)
	_reminded = false
	EventDirector.stop_calm_event(&"stealth_spotted")
	_growl.pitch_scale = spotted_growl_pitch
	_growl.volume_db = spotted_growl_db
	_growl.play()
	Haptics.pulse_both(0.8, 0.3)
	BatCompanion.shut_up()
	BatCompanion.say(spotted_line)
	var head := GameState.head_position
	var from_animal := (_animal.global_position - head)
	from_animal.y = 0.0
	var stop_at := head + from_animal.normalized() * spotted_distance + Vector3.DOWN * 0.8
	_tween = create_tween()
	_tween.tween_property(_animal, "global_position", stop_at, charge_seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _on_head_flicked(direction: int, strength: float) -> void:
	if state != State.SPOTTED or direction >= 0:
		return
	if strength < headbutt_min_strength:
		last_headbutt = "headbutt too soft: strength %.2f of %.2f" % [strength, headbutt_min_strength]
		print("Stealth: " + last_headbutt)
		return
	last_headbutt = "headbutt: strength %.2f" % strength
	print("Stealth: " + last_headbutt)
	_hit.play()
	Haptics.pulse_both(1.0, 0.5)
	_break_away()


## The animal reels back down its path, and the player runs on.
func _break_away() -> void:
	_set_state(State.FLEEING)
	_run += 1
	var run := _run
	BatCompanion.shut_up()
	BatCompanion.say(headbutt_hit_line)
	var den: bool = _level.den_found
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_animal, "global_position", _marker(den_path_end if den else path_end), pass_seconds)
	_tween.parallel().tween_property(_steps, "volume_db", -40.0, pass_seconds).set_ease(Tween.EASE_IN)

	var player: Node3D = _level.player
	var ahead: Vector3 = _level.point_at(_level.project(player.global_position).s + flee_distance)
	ahead.y = player.global_position.y
	await _level.slide_player_to(ahead, flee_seconds)
	if run != _run:
		return
	await _level.wait_for_bat(recover_timeout)
	if run != _run:
		return
	_animal.visible = false
	_set_state(State.DONE)
	GameState.input_locked = false
	EventDirector.complete(Event.STEALTH)


func _required_drop() -> float:
	var i := clampi(attempt - 1, 0, required_drop_by_attempt.size() - 1)
	var required: float = required_drop_by_attempt[i]
	if _level.den_found:
		required -= den_drop_bonus
	return maxf(required, 0.5)


func _approach_time() -> float:
	return den_approach_seconds if _level.den_found else approach_seconds


func _reset_animal() -> void:
	_animal.global_position = _marker(den_path_start if _level.den_found else path_start)
	_animal.visible = state != State.DONE
	_steps.volume_db = footsteps_db
	_growl.pitch_scale = growl_pitch
	_growl.volume_db = growl_db


func _marker(path: NodePath) -> Vector3:
	return (get_node(path) as Node3D).global_position


func _set_state(new_state: State) -> void:
	state = new_state
	_t_state = 0.0


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
