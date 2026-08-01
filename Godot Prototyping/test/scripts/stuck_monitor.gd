extends Node

## Autoload this as "Stuck".
##
## This is the behavioural half of your overload detector. It is deliberately
## built as a count of independent converging signals rather than a single
## continuous score, so that the EmotiBit heart-rate term drops into
## _evaluate() as one more line when the hardware is wired up.
##
## Three behavioural signals:
##   1. no progress    - hasn't gotten closer to the exit in a while
##   2. collisions     - bumping walls repeatedly in a short window
##   3. confinement    - milling around inside a small radius
##
## Two of three fires the signal. With heart rate added, keep the threshold at
## two but require that at least one of them be behavioural — elevated heart
## rate alone should never flag anyone, because your own calming mechanic
## raises heart rate on purpose.

signal became_stuck(level: int)
signal recovered()

@export var sample_interval: float = 0.5
@export var window_seconds: float = 20.0

## Seconds without getting closer to the exit before that counts as a signal.
@export var no_progress_seconds: float = 25.0

@export var collision_window: float = 15.0
@export var collision_count: int = 4

## If every sample in the window sits inside a sphere this small, the player
## is circling rather than exploring.
@export var confinement_radius: float = 3.0

## Minimum gap between escalations, so the bat doesn't nag.
@export var rearm_seconds: float = 20.0

var player: Node3D = null
var exit: Node3D = null
var enabled: bool = true

var _t: float = 0.0
var _next_sample: float = 0.0
var _positions: Array = []   # [{t: float, pos: Vector3}]
var _collisions: Array = []  # [float]
var _best_distance: float = INF
var _t_best: float = 0.0
var _flagged: bool = false
var _t_last_flag: float = -999.0
var _level: int = 0


## Call once per level: Stuck.configure(player_node, exit_marker)
func configure(p: Node3D, e: Node3D) -> void:
	player = p
	exit = e
	reset()


func reset() -> void:
	_positions.clear()
	_collisions.clear()
	_best_distance = INF
	_t_best = _t
	_flagged = false
	_level = 0


## Call from your player when it hits a wall.
func report_collision() -> void:
	_collisions.append(_t)


## Current escalation level, 0 when not flagged.
func level() -> int:
	return _level if _flagged else 0


func _physics_process(delta: float) -> void:
	if not enabled or player == null or exit == null:
		return

	_t += delta
	if _t < _next_sample:
		return
	_next_sample = _t + sample_interval

	_positions.append({"t": _t, "pos": player.global_position})
	_trim()

	var d := player.global_position.distance_to(exit.global_position)
	if d < _best_distance - 0.5:
		_best_distance = d
		_t_best = _t
		if _flagged:
			_flagged = false
			_level = 0
			recovered.emit()

	_evaluate()


func _trim() -> void:
	while _positions.size() > 0 and _t - _positions[0].t > window_seconds:
		_positions.pop_front()
	while _collisions.size() > 0 and _t - _collisions[0] > collision_window:
		_collisions.pop_front()


func _evaluate() -> void:
	if _t - _t_last_flag < rearm_seconds:
		return

	var signal_count := 0
	if _t - _t_best > no_progress_seconds:
		signal_count += 1
	if _collisions.size() >= collision_count:
		signal_count += 1
	if _confined():
		signal_count += 1

	# When the EmotiBit is wired up:
	# if Emotibit.hr_above_baseline(8.0) and not Emotibit.in_calming_encounter:
	#     signal_count += 1

	if signal_count >= 2:
		_flagged = true
		_level = mini(_level + 1, 3)
		_t_last_flag = _t
		became_stuck.emit(_level)


func _confined() -> bool:
	# Need a mostly-full window before this means anything.
	var expected := int(window_seconds / sample_interval)
	if _positions.size() < int(expected * 0.8):
		return false

	var centre := Vector3.ZERO
	for s in _positions:
		centre += s.pos
	centre /= float(_positions.size())

	var max_r := 0.0
	for s in _positions:
		max_r = maxf(max_r, centre.distance_to(s.pos))
	return max_r < confinement_radius
