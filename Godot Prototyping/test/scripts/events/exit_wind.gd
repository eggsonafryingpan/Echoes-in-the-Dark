extends Node3D

## The outside wind: the exit's sound, and after the river the player's heading.
##
## One Priority-layer source that rides the route a little ahead of the
## player (lead_distance), so it is heard through the passage they will
## actually walk rather than straight through the rock to the exit. The
## story reason: outside air leaks in along the tunnels, so the draft
## always comes from further along the way out.
##
## Modes:
##   OFF      silent, up to and through the river: at the crossing the water
##            has to be the only thing to listen to
##   HEADING  after the river: fades in, then steady, louder the further along the route the
##            player is (heading_min_db at the start -> heading_max_db at the
##            exit), so getting closer is audible.
##   FULL     the top of the climb: wind comes in full.
##
## Debug: a cyan sphere where the wind currently sits, labelled with its mode.

enum Mode { OFF, HEADING, FULL }

@export var level_path: NodePath = ^".."
@export var lead_distance: float = 8.0
@export var height: float = 1.6
@export var heading_min_db: float = -12.0
@export var heading_max_db: float = 0.0
@export var full_db: float = 8.0
## dB per second the level moves toward its target in HEADING/FULL.
@export var level_slew_db: float = 6.0
## Where the level starts from when the wind comes in, so it arrives gradually.
@export var fade_in_db: float = -36.0

var mode: Mode = Mode.OFF

@onready var _player: AudioStreamPlayer3D = $Player
@onready var _describable: Describable = $Describable
var _level: Node = null
var _label: Label3D = null
var _sphere: MeshInstance3D = null


func _ready() -> void:
	_level = get_node(level_path)
	var stream: AudioStream = SfxLibrary.get_stream(&"outside_wind")
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
	_player.stream = stream
	_player.bus = AudioDirector.BUS_PRIORITY
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
	var s: float = _level.project(player.global_position).s
	global_position = _level.point_at(s + lead_distance) + Vector3.UP * height

	if mode == Mode.HEADING or mode == Mode.FULL:
		var target := full_db if mode == Mode.FULL \
				else lerpf(heading_min_db, heading_max_db, _level.progress_fraction())
		_player.volume_db = move_toward(_player.volume_db, target, level_slew_db * delta)

	_sphere.visible = mode != Mode.OFF
	_label.text = "OUTSIDE WIND  %s  %.0f dB" % [Mode.keys()[mode], _player.volume_db]
