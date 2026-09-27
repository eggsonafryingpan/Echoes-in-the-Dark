extends Node3D

## A constant ambient bed on the Environmental layer, everywhere in the
## cave -- not tied to any object, so there is always something for
## overload to strip and for the A/B demo (§11) to show being stripped.
## The authored environmental sources (rivers, waterfalls, wind passages)
## are deliberately local and fall silent a few metres away, which left
## most of the cave with no bed at all.
##
## Four emitters on a ring around the listener, following its position but
## not its rotation, so the bed stays fixed in the world while the head
## turns: it surrounds rather than sitting flat inside the head, and turning
## still changes what each ear hears. Each emitter uses a different clip or
## start offset, so the four decorrelate instead of summing to one mono
## source.
##
## Plain AudioStreamPlayer3D on the named bus, never RaytracedAudioPlayer3D,
## for the reason spelled out in spatial_sfx_source.gd (the raytraced
## listener reassigns a raytraced player's bus, which would put this out of
## reach of strip_environmental()). Not a Describable, so the scan never
## returns it.

@export var bus: StringName = &"Environmental"
@export var clips: Array[StringName] = [&"wind_passage", &"wind_passage_soft", &"wind_passage", &"wind_passage_soft"]
@export var volume_db: float = -8.0
@export var ring_radius: float = 6.0
## Above ear height, so the bed reads as the space itself rather than as
## something standing on the floor next to the player.
@export var ring_height: float = 1.5

var _emitters: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	for i in clips.size():
		var stream: AudioStream = SfxLibrary.get_stream(clips[i]).duplicate()
		if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
			stream.loop = true
		var emitter := AudioStreamPlayer3D.new()
		emitter.name = "Bed%d" % i
		emitter.stream = stream
		emitter.bus = bus
		emitter.volume_db = volume_db
		# The ring moves with the listener, so distance is constant and
		# attenuation would only ever be a fixed offset; direction is what
		# matters here, and panning still applies with attenuation off.
		emitter.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		add_child(emitter)
		_emitters.append(emitter)
		var length := stream.get_length()
		emitter.play(fmod(length * float(i) / clips.size(), maxf(length, 0.01)))
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	var centre := GameState.head_position + Vector3(0, ring_height, 0)
	for i in _emitters.size():
		var a := TAU * float(i) / _emitters.size() + PI / 4.0
		_emitters[i].global_position = centre + Vector3(cos(a), 0, sin(a)) * ring_radius
