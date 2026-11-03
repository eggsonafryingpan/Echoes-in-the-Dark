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
## A missing or not-yet-imported file falls back to a short SILENT
## placeholder: missing means silent. It used to be a sine beep, so that a
## gap was audible during development, but a beep in the middle of a scripted
## beat reads as a bug while a missing layer just reads as a thinner mix.
## Every missing name is still warned about once, so the gaps stay visible in
## the log rather than in the player's ears. The placeholder is a real
## (empty) stream rather than null, so no caller has to special-case it.
##
## Note: Godot still needs to import a freshly dropped file once (open the
## project in the editor, or run it headless once) before load() can see it
## -- that is an engine requirement this script cannot bypass.

const MANIFEST_PATH := "res://assets/sfx/manifest.json"
const SFX_ROOT := "res://assets/sfx/"

## mp3 added alongside the original wav/ogg contract: real deliveries have
## arrived as mp3 (freesound-style downloads), and Godot imports mp3
## natively same as the other two, so there's no reason to reject it.
const _EXTENSIONS := ["wav", "ogg", "mp3"]

var _manifest: Dictionary = {}
var _manifest_loaded: bool = false
var _cache: Dictionary = {}
var _placeholder: AudioStream = null


func _ready() -> void:
	_ensure_manifest()


## The manifest loads on first use, not on _ready, because autoload order
## is not a guarantee this file can make. SfxLibrary is registered last;
## Bat is registered first and asked for a sound from its own _ready, so
## the lookup arrived before the manifest existed, warned that a key it
## does contain was missing, and cached the placeholder beep for the rest
## of the session. Loading on demand makes lookups correct no matter who
## asks first or where they sit in the autoload list.
func _ensure_manifest() -> void:
	if _manifest_loaded:
		return
	_manifest_loaded = true
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
## back to the silent placeholder if the manifest doesn't list it, or if it does
## but no .wav/.ogg has been dropped in (or imported) yet.
func get_stream(logical_name: String) -> AudioStream:
	_ensure_manifest()
	if _cache.has(logical_name):
		return _cache[logical_name]

	var stream := _resolve(logical_name)
	if stream == null:
		if not _manifest.has(logical_name):
			push_warning("SfxLibrary: '%s' isn't in manifest.json -- add it there first." % logical_name)
		else:
			push_warning("SfxLibrary: '%s' has no asset yet; it will play silence." % logical_name)
		stream = _get_placeholder()
	_cache[logical_name] = stream
	return stream


## A copy of stream that loops, whatever its format. MP3 and OGG have a loop
## flag; a WAV needs a loop range, and without one it plays once and goes
## silent (the river and the tutorial's bird did exactly that).
func looping(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		var copy = stream.duplicate()
		copy.loop = true
		return copy
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream.duplicate()
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
		return wav
	return stream


## True when a real file backs this name -- i.e. get_stream() would hand
## back the asset rather than the silent placeholder. For callers that want
## to skip a missing sound entirely rather than play silence in its slot.
func has_stream(logical_name: String) -> bool:
	return get_stream(logical_name) != _get_placeholder()


## An entry may name a "placeholder" file (in the same folder, or in
## "placeholder_folder"): used, with a warning, until the real "file" is
## dropped in. Then the real one wins with
## no manifest or code change.
func _resolve(logical_name: String) -> AudioStream:
	if not _manifest.has(logical_name):
		return null
	var entry: Dictionary = _manifest[logical_name]
	var folder: String = entry.get("folder", "")
	var stream := _load_first("%s%s/%s" % [SFX_ROOT, folder, entry.get("file", logical_name)])
	if stream == null and entry.has("placeholder"):
		var placeholder_folder: String = entry.get("placeholder_folder", folder)
		stream = _load_first("%s%s/%s" % [SFX_ROOT, placeholder_folder, entry.placeholder])
		if stream != null:
			push_warning("SfxLibrary: '%s' is using its placeholder until assets/sfx/%s/%s.(wav|ogg|mp3) is added."
					% [logical_name, folder, entry.get("file", logical_name)])
	return stream


func _load_first(base_path: String) -> AudioStream:
	for ext in _EXTENSIONS:
		var path := "%s.%s" % [base_path, ext]
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream is AudioStream:
				return stream
	return null


## Silence, a tenth of a second long. Short so a looping player on a
## missing asset is not holding anything, and real silence rather than a
## zero-length stream, which AudioStreamWAV refuses to play.
func _get_placeholder() -> AudioStream:
	if _placeholder != null:
		return _placeholder

	var sample_rate := 22050
	var data := PackedByteArray()
	data.resize(int(sample_rate * 0.1) * 2)  # 16-bit mono, zero-filled
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	_placeholder = stream
	return _placeholder
