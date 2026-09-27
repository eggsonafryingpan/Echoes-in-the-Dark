extends Node3D

## The sound of being pressed against rock: runs continuously from start()
## until stop(), with no gaps, and cuts off (with a click-free fade) the
## moment contact ends.
##
## Not a simple looped stream, because hit_wall.mp3 is a one-shot: ~0.2 s
## of silence, ~1.1 s of impact, then ~0.8 s of silent tail. Looping the
## file whole -- or replaying it whenever it finishes, which is what the
## old HitAudio did -- leaves a second of dead air per cycle, which is the
## stutter. Instead two voices leapfrog: each starts past the leading
## silence, and the next starts before the previous one's body has decayed,
## so there is always impact audible while contact lasts. A small pitch
## jitter per retrigger keeps it from reading as a machine-gun loop.
##
## Plain AudioStreamPlayer3D rather than RaytracedAudioPlayer3D: the
## raytraced listener reassigns a raytraced player's bus as it comes in and
## out of range (see spatial_sfx_source.gd), and a player pressed against a
## wall is always right at that boundary. On the UI bus: this is feedback on
## the player's own action, which overload stripping must never remove --
## the moments someone is bumping into walls are exactly when it's active.

@export var sfx_name: StringName = &"wall_collision_thud"
@export var bus: StringName = &"UI"
@export var volume_db: float = 0.0
## Where each voice starts in the clip -- past hit_wall.mp3's leading silence.
@export var body_start_seconds: float = 0.2
## Time between voice starts. Shorter than the clip's ~1.1 s body so the
## voices overlap and there is never a gap.
@export var retrigger_seconds: float = 0.7
@export var pitch_jitter: float = 0.06
@export var fade_out_seconds: float = 0.08

var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _active: bool = false
var _until_retrigger: float = 0.0
var _fade: Tween = null


func _ready() -> void:
	var stream := SfxLibrary.get_stream(sfx_name)
	for i in 2:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Voice%d" % i
		voice.stream = stream
		voice.bus = bus
		voice.unit_size = 4.0
		voice.max_distance = 12.0
		add_child(voice)
		_voices.append(voice)


func is_active() -> bool:
	return _active


func start() -> void:
	if _active:
		return
	_active = true
	if _fade != null:
		_fade.kill()
		_fade = null
	for voice in _voices:
		voice.stop()
	_trigger()


func stop() -> void:
	if not _active:
		return
	_active = false
	_fade = create_tween().set_parallel()
	for voice in _voices:
		if voice.playing:
			_fade.tween_property(voice, "volume_db", -60.0, fade_out_seconds)
	_fade.chain().tween_callback(func():
		for voice in _voices:
			voice.stop()
	)


func _process(delta: float) -> void:
	if not _active:
		return
	_until_retrigger -= delta
	if _until_retrigger <= 0.0:
		_trigger()


func _trigger() -> void:
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.volume_db = volume_db
	voice.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	voice.play(body_start_seconds)
	_until_retrigger = retrigger_seconds
