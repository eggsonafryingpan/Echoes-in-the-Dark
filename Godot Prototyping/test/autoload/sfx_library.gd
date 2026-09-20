extends Node

## Autoload this as "SfxLibrary".
##
## Drop-in SFX system: a sound designer adds a matching .wav or .ogg file to
## the right assets/sfx/<folder>/ directory -- no code or manifest edits
## needed, since every logical name this project uses is already listed in
## assets/sfx/manifest.json. Code never touches file paths directly; it asks
## for a logical name via get_stream() and gets back a stream, so the
## manifest stays the single source of truth for what a sound designer needs
## to deliver (see assets/sfx/README.md for the handoff list).
##
## A missing or not-yet-imported file falls back to a procedurally generated
## placeholder tone (a short sine beep, synthesized in code -- no binary
## asset needed) so nothing is ever silent during development, and the
## placeholder is obviously not a real sound rather than easy to mistake for
## one.
##
## Note: Godot still needs to import a freshly dropped file once (open the
## project in the editor, or run it headless once) before load() can see it
## -- that is an engine requirement this script cannot bypass.

const MANIFEST_PATH := "res://assets/sfx/manifest.json"
const SFX_ROOT := "res://assets/sfx/"
const _EXTENSIONS := ["wav", "ogg"]

var _manifest: Dictionary = {}
var _cache: Dictionary = {}
var _placeholder: AudioStream = null


func _ready() -> void:
	_load_manifest()


func _load_manifest() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("SfxLibrary: manifest not found at %s" % MANIFEST_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SfxLibrary: malformed manifest.json")
		return
	_manifest = parsed


## Returns the AudioStream for a logical name (e.g. "footstep_rock"). Falls
## back to a placeholder tone if the manifest doesn't list it, or if it does
## but no .wav/.ogg has been dropped in (or imported) yet.
func get_stream(logical_name: String) -> AudioStream:
	if _cache.has(logical_name):
		return _cache[logical_name]

	var stream := _resolve(logical_name)
	if stream == null:
		if not _manifest.has(logical_name):
			push_warning("SfxLibrary: '%s' isn't in manifest.json -- add it there first." % logical_name)
		stream = _get_placeholder()
	_cache[logical_name] = stream
	return stream


func _resolve(logical_name: String) -> AudioStream:
	if not _manifest.has(logical_name):
		return null
	var entry: Dictionary = _manifest[logical_name]
	var folder: String = entry.get("folder", "")
	var file_base: String = entry.get("file", logical_name)
	var base_path := "%s%s/%s" % [SFX_ROOT, folder, file_base]

	for ext in _EXTENSIONS:
		var path := "%s.%s" % [base_path, ext]
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream is AudioStream:
				return stream
	return null


func _get_placeholder() -> AudioStream:
	if _placeholder != null:
		return _placeholder

	var sample_rate := 44100
	var duration := 0.12
	var freq := 880.0
	var frame_count := int(sample_rate * duration)
	var fade_frames := 200

	var data := PackedByteArray()
	data.resize(frame_count * 2)  # 16-bit mono
	for i in frame_count:
		var t := float(i) / sample_rate
		var envelope := minf(1.0, minf(i / float(fade_frames), (frame_count - i) / float(fade_frames)))
		var sample := sin(TAU * freq * t) * 0.25 * envelope
		var v := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	_placeholder = stream
	return _placeholder
