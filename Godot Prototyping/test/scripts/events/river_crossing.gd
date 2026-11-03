extends Node3D

## E3: RIVER. The river bars the way; jump it when the current is weakest.
##
## The river fills the chamber wall to wall, with a barrier the player can't
## walk through. The only way over is a sharp upward head flick
## (GameState.head_flicked), so the crossing is scripted: the player arcs
## over the barrier rather than being moved by physics.
##
## The current runs in a cycle, and the only thing that shows it is the water
## itself, on the Priority layer so overload can never strip the cue:
##
##   STRONG  loud, dangerous          strong_seconds
##   EASING  fading down              easing_seconds
##   WEAK    quiet: the safe window   weak_seconds
##   RISING  building back up         rising_seconds
##
## A flick during WEAK lands on the far bank. A flick at any other time drops
## the player in the river and the current sweeps them back to the near bank.
## Missing a window costs nothing: the next one comes round.
##
## Anti-lockout (§1): after assist_after_swept sweeps, or assist_after_missed
## windows missed, the current stays weak and any flick crosses. F6 crosses
## now; F11 jumps at the wrong moment.
##
## The strength of the flick sets the height of the jump.
##
## Debug: a label over the river with the current, the windows and the last
## flick's rate, for tuning GameState.flick_min_rate_deg.

const Event := preload("res://autoload/event_director.gd").Event

enum State { IDLE, INTRO, LISTENING, JUMPING, SWEPT, DONE }
enum Current { STRONG, EASING, WEAK, RISING }

@export var level_path: NodePath = ^".."
@export var trigger_path: NodePath
@export var river_source_path: NodePath
@export var near_bank_path: NodePath = ^"NearBank"
@export var far_bank_path: NodePath = ^"FarBank"

# ------------------------------------------------------------------------
# RIVER TIMING CONFIG (the head flick itself is tuned in GameState's
# HEAD GESTURES CONFIG: rate, travel and capture time, live and mouse)
# ------------------------------------------------------------------------
@export_group("Current cycle")
@export var strong_seconds: float = 7.0
@export var easing_seconds: float = 2.0
@export var weak_seconds: float = 5.0
@export var rising_seconds: float = 2.0
@export_group("Safe window")
## The water already sounds quiet near the end of EASING, and a flick is only
## recognised partway through the movement. These widen the safe window: the
## last part of EASING, and the first part of RISING.
@export var window_early_seconds: float = 0.8
@export var window_late_seconds: float = 0.5
@export_group("")
@export var strong_db: float = 4.0
@export var weak_db: float = -11.0
## Pulled down under the bat's explanation, so it can be heard.
@export var intro_db: float = -12.0

@export var assist_after_swept: int = 2
@export var assist_after_missed: int = 3

@export var jump_seconds: float = 0.9
## Arc height at the weakest and at the strongest flick (strength 1 and 2).
@export var jump_height: Vector2 = Vector2(1.2, 2.2)
@export var swept_seconds: float = 1.6
## Longest the player waits on a spoken line before getting control back.
@export var line_timeout: float = 8.0
## The player lands no further than this from the middle of the bank.
@export var bank_half_width: float = 7.5

@export var intro_line: StringName = &"river_intro"
@export var missed_line: StringName = &"river_missed"
@export var swept_line: StringName = &"river_swept"
@export var assist_line: StringName = &"river_assist"
@export var crossed_line: StringName = &"river_crossed"
@export var land_sfx: StringName = &"footstep_water_splash_small"
@export var fall_sfx: StringName = &"footstep_water_splash_big"

var state: State = State.IDLE
var current: Current = Current.STRONG
var swept: int = 0
var missed: int = 0
var assisted: bool = false
var last_flick: String = ""

var _level: Node = null
var _trigger: Area3D = null
var _water: AudioStreamPlayer3D = null
var _label: Label3D = null
var _t_current: float = 0.0
var _jumped_this_window: bool = false
var _window_counted: bool = true
var _tween: Tween = null
## Bumped when the crossing is reset, so a sequence still waiting on a spoken
## line wakes up, sees it is stale and leaves the player alone.
var _run: int = 0


func _ready() -> void:
	_level = get_node(level_path)
	_trigger = get_node(trigger_path)
	var source := get_node(river_source_path)
	_water = source.get_node("Body/AudioStreamPlayer3D")
	_label = DebugDraw.label(self, "", Vector3.UP * 3.0, Color(0.5, 0.8, 1.0))
	GameState.head_flicked.connect(_on_head_flicked)


func _physics_process(delta: float) -> void:
	_update_current(delta)
	_label.text = "RIVER  %s  %s  %.0f dB  swept %d  missed %d%s%s" % [
		State.keys()[state], Current.keys()[current], _water.volume_db, swept, missed,
		"  ASSIST" if assisted else "", "\n" + last_flick if last_flick != "" else ""]

	if state == State.IDLE and EventDirector.current_event == Event.RIVER \
			and _trigger.overlaps_body(_level.player):
		begin_crossing()


## True while a flick lands on the far bank.
func window_open() -> bool:
	match current:
		Current.WEAK:
			return true
		Current.EASING:
			return _t_current >= easing_seconds - window_early_seconds
		Current.RISING:
			return _t_current <= window_late_seconds
	return false


func begin_crossing() -> void:
	if state != State.IDLE:
		return
	_run += 1
	var run := _run
	if not EventDirector.event_running:
		EventDirector.begin(Event.RIVER)
	_set_state(State.INTRO)
	BatCompanion.say(intro_line)
	await _level.wait_for_bat(40.0)
	if run != _run:
		return
	_start_cycle()
	_set_state(State.LISTENING)


## Back to the start, for a jump. Fresh counts: a jump is a fresh run.
func reset_crossing() -> void:
	_stop_sequence()
	swept = 0
	missed = 0
	assisted = false
	last_flick = ""
	_set_state(State.IDLE)
	_water.volume_db = strong_db


## Treats the river as already crossed, for a jump to a later event.
func mark_crossed() -> void:
	_stop_sequence()
	_set_state(State.DONE)
	_set_current(Current.WEAK)


## F6: across, now.
func skip() -> void:
	if state == State.DONE:
		return
	_stop_sequence()
	if not EventDirector.event_running:
		EventDirector.begin(Event.RIVER)
	_level.player.global_position = _bank_point(far_bank_path)
	_finish_crossing()


## F11: jump at the wrong moment.
func force_fail() -> void:
	if state == State.LISTENING:
		_jump(1.0, false)


func _on_head_flicked(direction: int, strength: float) -> void:
	last_flick = "last flick: %s  strength %.2f  during %s %.1fs" % [
		"UP" if direction > 0 else "DOWN", strength, Current.keys()[current], _t_current]
	if direction > 0 and state == State.LISTENING:
		print("River: " + last_flick)
	if direction <= 0 or state != State.LISTENING:
		return
	if not _trigger.overlaps_body(_level.player):
		return
	_jump(strength, assisted or window_open())


func _jump(strength: float, safe: bool) -> void:
	_set_state(State.JUMPING)
	_jumped_this_window = true
	GameState.input_locked = true
	var run := _run
	print("River: jump, strength %.2f, current %s -> %s" % [
		strength, Current.keys()[current], "safe" if safe else "swept"])

	var player: Node3D = _level.player
	var from: Vector3 = player.global_position
	var far := _bank_point(far_bank_path)
	var to := far if safe else from.lerp(far, 0.5)
	var peak := lerpf(jump_height.x, jump_height.y, clampf(strength - 1.0, 0.0, 1.0))
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(func(f: float):
		player.global_position = from.lerp(to, f) + Vector3.UP * peak * 4.0 * f * (1.0 - f),
		0.0, 1.0, jump_seconds)
	await _tween.finished
	if run != _run:
		return
	if safe:
		_splash(land_sfx, -2.0)
		_finish_crossing()
	else:
		_swept_back()


func _swept_back() -> void:
	var run := _run
	_set_state(State.SWEPT)
	swept += 1
	_splash(fall_sfx, 6.0)
	Haptics.pulse_both(1.0, 0.45)
	BatCompanion.shut_up()
	BatCompanion.say(swept_line)
	await _level.slide_player_to(_bank_point(near_bank_path), swept_seconds)
	if run != _run:
		return
	await _level.wait_for_bat(line_timeout)
	if run != _run:
		return
	GameState.input_locked = false
	_set_state(State.LISTENING)
	_maybe_assist()


func _finish_crossing() -> void:
	_set_state(State.DONE)
	_set_current(Current.WEAK)
	GameState.input_locked = false
	BatCompanion.shut_up()
	BatCompanion.say(crossed_line)
	EventDirector.complete(Event.RIVER)


func _maybe_assist() -> void:
	if assisted or (swept < assist_after_swept and missed < assist_after_missed):
		return
	assisted = true
	_set_current(Current.WEAK)
	BatCompanion.say(assist_line)


# --- The current ------------------------------------------------------------

func _start_cycle() -> void:
	_set_current(Current.WEAK if assisted else Current.STRONG)


func _set_current(new_current: Current) -> void:
	current = new_current
	_t_current = 0.0


func _update_current(delta: float) -> void:
	match state:
		State.IDLE:
			return
		State.INTRO:
			_water.volume_db = move_toward(_water.volume_db, intro_db, 12.0 * delta)
			return
		State.DONE:
			_water.volume_db = move_toward(_water.volume_db, weak_db, 12.0 * delta)
			return

	_t_current += delta
	match current:
		Current.STRONG:
			_water.volume_db = move_toward(_water.volume_db, strong_db, 12.0 * delta)
			if _t_current >= strong_seconds:
				_jumped_this_window = false
				_window_counted = false
				_set_current(Current.EASING)
		Current.EASING:
			_water.volume_db = lerpf(strong_db, weak_db, minf(_t_current / easing_seconds, 1.0))
			if _t_current >= easing_seconds:
				_set_current(Current.WEAK)
		Current.WEAK:
			_water.volume_db = weak_db
			if not assisted and _t_current >= weak_seconds:
				_set_current(Current.RISING)
		Current.RISING:
			_water.volume_db = lerpf(weak_db, strong_db, minf(_t_current / rising_seconds, 1.0))
			# The window's late grace is over: only now is it a miss.
			if not _window_counted and _t_current > window_late_seconds:
				_window_counted = true
				_end_window()
			if _t_current >= rising_seconds:
				_set_current(Current.STRONG)


func _end_window() -> void:
	if _jumped_this_window or state != State.LISTENING:
		return
	missed += 1
	if missed == 1:
		BatCompanion.say(missed_line)
	_maybe_assist()


# --- Helpers ----------------------------------------------------------------

## The point on a bank straight across from the player.
func _bank_point(path: NodePath) -> Vector3:
	var bank := (get_node(path) as Node3D).global_position
	var player: Vector3 = _level.player.global_position
	return Vector3(clampf(player.x, bank.x - bank_half_width, bank.x + bank_half_width), player.y, bank.z)


## Priority, like the water: this is the result of the player's own action.
func _splash(sfx: StringName, volume_db: float) -> void:
	var sound := AudioStreamPlayer.new()
	sound.stream = SfxLibrary.get_stream(sfx)
	sound.bus = AudioDirector.BUS_PRIORITY
	sound.volume_db = volume_db
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


func _set_state(new_state: State) -> void:
	state = new_state


func _stop_sequence() -> void:
	_run += 1
	_kill_tween()
	_set_current(Current.STRONG)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
