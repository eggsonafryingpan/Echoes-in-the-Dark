extends Node3D

## The way out: birds outside (was a wind; the code still calls it the wind),
## a navigation cue the player follows from the landing to
## the exit, so it sits on Priority, above the ambient layers.
##
## One continuous source that rides path_points a little ahead of the player
## (lead_distance), so it is heard through the passage they will actually walk
## rather than straight through rock. Turning toward the way out puts it in
## front. The story reason: outside air leaks in along the tunnels, so the
## draft always comes from further along the way out.
##
## Modes:
##   OFF      silent, until the bat's "do you feel that?" (E2)
##   HEADING  fades in, then steady, louder the further along the path the
##            player is, so getting closer is audible.
##   FULL     the top of the climb: wind comes in full.
##
## It ducks while an event needs the player listening to something else. At the
## river the water has to be the only thing to listen to: the crossing is timed
## by hearing the current drop.
##
## Debug: a cyan sphere where the wind currently sits, labelled with its mode.

enum Mode { OFF, HEADING, FULL }

@export var level_path: NodePath = ^".."

# ------------------------------------------------------------------------
# WIND PATH CONFIG
# ------------------------------------------------------------------------
@export_group("Wind path")
## Floor points from the landing to the exit, in order, in world space.
## Defaults follow the level's Route, but can be moved independently of it.
@export var path_points := PackedVector3Array([
	Vector3(0, 0, 3), Vector3(0, 0, -42), Vector3(22, 0, -42), Vector3(22, 0, -84),
	Vector3(0, 0, -84), Vector3(0, 0, -105), Vector3(0, 0, -136), Vector3(0, 6, -172),
	Vector3(0, 6, -180),
])
## Height above the path. The player's head is about 2.1, so this is slightly
## above eye level.
@export var height: float = 2.4
## How far ahead of the player the wind sits along the path.
@export var lead_distance: float = 8.0
## How far to the left of the path the wind runs, so it hugs the left wall
## of each passage instead of filling the middle of it.
@export var left_wall_offset: float = 2.5
## The wind glides to its new spot at this speed (m/s) rather than jumping
## when the path turns a corner.
@export var follow_speed: float = 6.0

@export_group("Wind volume")
## The clip averages about -32 dB, so these need to be well above 0. Level
## grows along the path, from min at the landing to max at the exit.
@export var heading_min_db: float = -5.0
@export var heading_max_db: float = 5.0
@export var full_db: float = 8.0
## Output ceiling. Has to sit above the loudest level here.
@export var max_db: float = 26.0
## 3D pan amount: how strongly turning the head moves it between the ears.
@export var panning_strength: float = 2.0
## dB per second the level moves toward its target.
@export var level_slew_db: float = 18.0
## Where the level starts from when the wind comes in.
@export var fade_in_db: float = -24.0

@export_group("Wind ducking")
## Taken off while each event runs. River: effectively silent, so the water's
## quiet window can be heard. Stealth and climb: under their audio cues.
@export var river_duck_db: float = 45.0
@export var stealth_duck_db: float = 10.0
@export var climb_duck_db: float = 8.0
@export_group("")

var mode: Mode = Mode.OFF

@onready var _player: AudioStreamPlayer3D = $Player
@onready var _describable: Describable = $Describable
var _level: Node = null
var _path_s := PackedFloat32Array()  # distance along the path at each point
var _label: Label3D = null
var _sphere: MeshInstance3D = null


func _ready() -> void:
	_level = get_node(level_path)
	_build_path()
	var stream: AudioStream = SfxLibrary.get_stream(&"outside_wind")
	stream = SfxLibrary.looping(stream)
	_player.stream = stream
	_player.bus = AudioDirector.BUS_PRIORITY
	_player.max_db = max_db
	_player.panning_strength = panning_strength
	_sphere = DebugDraw.sphere(self, 0.45, Color(0.3, 0.95, 1.0, 0.85))
	_label = DebugDraw.label(self, "", Vector3.UP * 0.9, Color(0.5, 1.0, 1.0))
	set_mode(Mode.OFF)


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	match mode:
		Mode.OFF:
			_player.stop()
		Mode.HEADING, Mode.FULL:
			if not _player.playing:
				_player.volume_db = fade_in_db
				_player.play()
	# Once it's the steady heading it is heard directly, so the scan stops
	# spending a return on it (§9.2: continuous sources don't return).
	_describable.continuous = mode == Mode.HEADING or mode == Mode.FULL


func _physics_process(delta: float) -> void:
	var player: Node3D = _level.player
	if player == null:
		return
	var s := _nearest_s(player.global_position)
	var ahead := _point_at(s + lead_distance)
	var along := (_point_at(s + lead_distance + 0.5) - _point_at(s + lead_distance - 0.5))
	along.y = 0.0
	var left := Vector3.UP.cross(along.normalized()) if along.length() > 0.01 else Vector3.ZERO
	var spot := ahead + left * left_wall_offset + Vector3.UP * height
	if global_position.distance_to(spot) > 15.0:
		global_position = spot  # a teleport or jump: don't drift across the map
	else:
		global_position = global_position.move_toward(spot, follow_speed * delta)

	if mode == Mode.HEADING or mode == Mode.FULL:
		var target := full_db if mode == Mode.FULL \
				else lerpf(heading_min_db, heading_max_db, s / maxf(_path_s[-1], 0.01)) - _duck_db()
		_player.volume_db = move_toward(_player.volume_db, target, level_slew_db * delta)

	_sphere.visible = mode != Mode.OFF
	_label.text = "OUTSIDE BIRDS  %s  %.0f dB" % [Mode.keys()[mode], _player.volume_db]


func _duck_db() -> float:
	if not EventDirector.event_running:
		return 0.0
	match EventDirector.current_event:
		EventDirector.Event.RIVER:
			return river_duck_db
		EventDirector.Event.STEALTH:
			return stealth_duck_db
		EventDirector.Event.ESCAPE:
			return climb_duck_db
	return 0.0


func _build_path() -> void:
	_path_s.resize(path_points.size())
	for i in range(1, path_points.size()):
		_path_s[i] = _path_s[i - 1] + path_points[i - 1].distance_to(path_points[i])


## Distance along the path of the point nearest pos.
func _nearest_s(pos: Vector3) -> float:
	var best_s := 0.0
	var best := INF
	for i in range(1, path_points.size()):
		var closest := Geometry3D.get_closest_point_to_segment(pos, path_points[i - 1], path_points[i])
		var distance := pos.distance_squared_to(closest)
		if distance < best:
			best = distance
			best_s = _path_s[i - 1] + path_points[i - 1].distance_to(closest)
	return best_s


func _point_at(s: float) -> Vector3:
	for i in range(1, path_points.size()):
		if s <= _path_s[i]:
			var length := _path_s[i] - _path_s[i - 1]
			return path_points[i - 1].lerp(path_points[i], (s - _path_s[i - 1]) / maxf(length, 0.001))
	return path_points[-1]
