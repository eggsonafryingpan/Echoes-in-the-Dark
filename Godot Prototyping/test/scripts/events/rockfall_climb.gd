extends Node3D

## E4: ESCAPE. Climb the shaft while rocks come down.
##
## Every interval_seconds a rock is announced on one side of the player --
## left or right relative to where their HEAD faces -- in two channels that
## always agree:
##   - rumble in the matching DualSense grip (Haptics.pulse_side: left =
##     strong/low motor, right = weak/high motor), pulsing through the warning;
##   - the rock sound placed in the matching ear (a 3D source beside the head
##     on that side), on the Priority layer so overload never strips a cue the
##     player must act on.
## It lands warning_seconds later just to that side of where the player was
## standing, so standing still gets you hit and stepping away -- stick
## toward the other side, which is head-relative too -- gets you clear.
## "Rumble + rock on the left means move right."
##
## Getting hit is recoverable: a thud, a hard rumble in both grips, and a
## slide knockback_distance back down the route (never below the shaft's
## foot). Anti-lockout: each hit lengthens the warning, and after
## harmless_after_hits hits rocks land beside the player instead of on them;
## after cutoff_seconds no more fall at all. The run never ends here.
##
## Debug: a grey sphere falling onto a red disc (the landing zone), labelled
## LEFT/RIGHT; F11 drops one straight onto the player.

const Event := preload("res://autoload/event_director.gd").Event
const LEFT := -1
const RIGHT := 1

@export var level_path: NodePath = ^".."
@export var trigger_path: NodePath
@export var shaft_start_path: NodePath = ^"ShaftStart"
@export var shaft_end_path: NodePath = ^"ShaftEnd"

## Walking speed on the climb, as a fraction of normal: climbing is slow,
## and the shaft has to last long enough for several rocks.
@export var climb_speed_scale: float = 0.5
@export var first_rock_delay: float = 3.0
@export var interval_seconds: float = 3.0
@export var warning_seconds: float = 1.3
@export var warning_step_per_hit: float = 0.3
@export var max_warning_seconds: float = 2.2
## How far toward the warned side of the player the rock lands, and how
## close (horizontally) counts as a hit.
@export var impact_offset: float = 0.6
@export var hit_radius: float = 1.3
@export var shaft_half_width: float = 1.9
@export var knockback_distance: float = 7.0
@export var harmless_after_hits: int = 4
@export var cutoff_seconds: float = 120.0
## Rocks stop this far before the top, so the exit is a clean arrival.
@export var quiet_before_top: float = 5.0

@export var warning_sfx: StringName = &"climb_rock_warning"
@export var impact_sfx: StringName = &"climb_rock_impact"
@export var hit_line: StringName = &"e4_hit"
@export var start_line: StringName = &"e4_start"

var active: bool = false
var hits: int = 0
var rocks_dropped: int = 0
var last_side: int = 0

var _level: Node = null
var _t: float = 0.0
var _next_rock_t: float = 0.0
var _pending: Dictionary = {}
var _same_side_run: int = 0
var _rng := RandomNumberGenerator.new()
var _start_s: float = 0.0
var _end_s: float = 0.0


func _ready() -> void:
	_level = get_node(level_path)
	_rng.seed = 7
	get_node(trigger_path).body_entered.connect(_on_trigger)


func _on_trigger(body: Node3D) -> void:
	if body != _level.player or active:
		return
	if EventDirector.current_event != Event.ESCAPE or EventDirector.event_running:
		return
	start_climb()


func start_climb() -> void:
	_start_s = _level.project(get_node(shaft_start_path).global_position).s
	_end_s = _level.project(get_node(shaft_end_path).global_position).s
	active = true
	hits = 0
	rocks_dropped = 0
	_t = 0.0
	_next_rock_t = first_rock_delay
	_clear_pending()
	GameState.move_speed_scale = climb_speed_scale
	if not EventDirector.event_running:
		EventDirector.begin(Event.ESCAPE)
	BatCompanion.say(start_line)


func stop_climb() -> void:
	active = false
	GameState.move_speed_scale = 1.0
	_clear_pending()


## F11: a rock straight onto the player, short warning.
func force_hit() -> void:
	if not active:
		return
	_clear_pending()
	_announce(LEFT if _rng.randf() < 0.5 else RIGHT, 0.4, true)


func _physics_process(delta: float) -> void:
	if not active:
		return
	_t += delta

	if not _pending.is_empty():
		if _t >= _pending.t_impact:
			_land()
		return

	var s: float = _level.project(_level.player.global_position).s
	if _t >= cutoff_seconds or s >= _end_s - quiet_before_top:
		return
	if _t >= _next_rock_t:
		_announce(_pick_side(), minf(warning_seconds + hits * warning_step_per_hit, max_warning_seconds), false)


## Random, but never more than twice the same side running, so both ears
## (and both grips) get exercised.
func _pick_side() -> int:
	var side := LEFT if _rng.randf() < 0.5 else RIGHT
	if side == last_side:
		_same_side_run += 1
		if _same_side_run >= 2:
			side = -side
			_same_side_run = 0
	else:
		_same_side_run = 0
	last_side = side
	return side


func _announce(side: int, warning: float, on_player: bool) -> void:
	var player: Node3D = _level.player
	var yaw := GameState.effective_orientation().y
	var right := Basis.from_euler(Vector3(0.0, yaw, 0.0)).x
	var harmless := hits >= harmless_after_hits

	var offset := 0.0 if on_player else impact_offset
	if harmless and not on_player:
		offset = hit_radius + 1.6  # beside them: still a cue, never a hit
	var impact: Vector3 = player.global_position + right * side * offset
	impact = _clamp_to_shaft(impact)
	impact.y = _floor_y(impact)

	var root := Node3D.new()
	root.name = "Rock%d" % rocks_dropped
	add_child(root)
	root.global_position = impact
	var disc := DebugDraw.disc(root, hit_radius, Color(1.0, 0.15, 0.1, 0.45))
	DebugDraw.label(root, "ROCK  %s%s" % ["LEFT" if side == LEFT else "RIGHT", "  (harmless)" if harmless else ""],
			Vector3.UP * 0.8, Color(1.0, 0.4, 0.3))
	var rock := DebugDraw.sphere(root, 0.45, Color(0.6, 0.58, 0.55))
	rock.position.y = 9.0
	var tween := root.create_tween()
	tween.tween_property(rock, "position:y", 0.45, warning).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# The cue: rock sound in the matching ear, rumble in the matching grip.
	var head := GameState.head_position
	var sound := AudioStreamPlayer3D.new()
	sound.name = "Warning"
	sound.stream = SfxLibrary.get_stream(warning_sfx)
	sound.bus = AudioDirector.BUS_PRIORITY
	sound.volume_db = 4.0
	sound.unit_size = 4.0
	sound.panning_strength = 1.5
	add_child(sound)
	sound.global_position = head + right * side * 3.0 + Vector3.UP * 1.5
	sound.play()
	var fade := sound.create_tween()
	fade.tween_interval(warning)
	fade.tween_property(sound, "volume_db", -50.0, 0.5)
	fade.tween_callback(sound.queue_free)
	_rumble_warning(side, warning)

	rocks_dropped += 1
	_pending = {"t_impact": _t + warning, "impact": impact, "root": root, "disc": disc,
			"side": side, "harmless": harmless and not on_player}
	print("Climb: rock %d %s, %.1fs warning%s" % [rocks_dropped, "LEFT" if side == LEFT else "RIGHT",
			warning, " (harmless)" if _pending.harmless else ""])


## Three pulses climbing in strength across the warning, one grip only.
func _rumble_warning(side: int, warning: float) -> void:
	for i in 3:
		Haptics.pulse_side(side, 0.45 + 0.25 * i, minf(0.25, warning / 4.0))
		await get_tree().create_timer(warning / 3.0).timeout
		if not active:
			return


func _land() -> void:
	var impact: Vector3 = _pending.impact
	var root: Node3D = _pending.root
	var p: Vector3 = _level.player.global_position
	var hit: bool = not _pending.harmless and Vector2(p.x - impact.x, p.z - impact.z).length() < hit_radius

	var sound := AudioStreamPlayer3D.new()
	sound.stream = SfxLibrary.get_stream(impact_sfx)
	sound.bus = AudioDirector.BUS_PRIORITY
	sound.volume_db = 2.0
	sound.unit_size = 4.0
	add_child(sound)
	sound.global_position = impact + Vector3.UP * 0.5
	sound.play()
	var fade := sound.create_tween()
	fade.tween_interval(1.4)
	fade.tween_property(sound, "volume_db", -50.0, 0.6)
	fade.tween_callback(sound.queue_free)

	var disc: MeshInstance3D = _pending.disc
	(disc.material_override as StandardMaterial3D).albedo_color = Color(1, 0.1, 0.1, 0.8) if hit else Color(0.3, 0.9, 0.3, 0.5)
	var cleanup := root.create_tween()
	cleanup.tween_interval(1.5)
	cleanup.tween_callback(root.queue_free)
	_pending = {}
	_next_rock_t = _t + interval_seconds + hits * 0.5

	if hit:
		hits += 1
		print("Climb: HIT (%d) -- sliding back %.0f m" % [hits, knockback_distance])
		Haptics.pulse_both(1.0, 0.45)
		_level.knock_back_along_route(knockback_distance, _start_s + 1.0)
		if not BatCompanion.is_speaking():
			BatCompanion.say(hit_line)
	else:
		print("Climb: dodged")


func _clamp_to_shaft(pos: Vector3) -> Vector3:
	var a: Vector3 = get_node(shaft_start_path).global_position
	var b: Vector3 = get_node(shaft_end_path).global_position
	var axis := Vector2(b.x - a.x, b.z - a.z).normalized()
	var perp := Vector2(-axis.y, axis.x)
	var rel := Vector2(pos.x - a.x, pos.z - a.z)
	var along := rel.dot(axis)
	var across := clampf(rel.dot(perp), -shaft_half_width, shaft_half_width)
	var flat := Vector2(a.x, a.z) + axis * along + perp * across
	return Vector3(flat.x, pos.y, flat.y)


func _floor_y(pos: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 6.0, pos + Vector3.DOWN * 12.0)
	query.exclude = [_level.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else pos.y


func _clear_pending() -> void:
	if not _pending.is_empty() and is_instance_valid(_pending.root):
		_pending.root.queue_free()
	_pending = {}
