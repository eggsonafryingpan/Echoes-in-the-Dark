extends Node

## Autoload this as "BatCompanion". Brief: CLAUDE_CODE_BRIEF.md §9, §13 Phases 6-7.
##
## Scan (bearing only, no identification) + dialogue, rendered as a virtual
## spatial source anchored to a fixed shoulder position via head-tracking
## (§9.1 default resolution — one clean audio path into the headphones, no
## physical shoulder speaker).
##
## Sole owner of both verbs. The scan came here in Phase 6 (cooldown, which
## sources return, the pings themselves); speech followed once dialogue
## moved to pre-rendered clips. The former "Bat" autoload held a runtime
## DisplayServer TTS backend and a scan that spoke label + clock bearing +
## distance — the "current label-reading" behavior §9.2 says to replace —
## and is gone.
##
## Dialogue is clips addressed by id (voices/lines.txt + the generator),
## played on the shoulder-anchored source so the bat's voice comes from the
## bat. EventDirector fires lines by id and never sees a string of text.
## An id with no clip yet falls back to runtime TTS reading that id's text
## from the same file — see say() — so writing is never blocked on
## rendering, but the fallback is flat rather than spatialized and every
## id that uses it is named in a warning.
##
## What a return is, and is not: one short chirp per object, rendered from
## the object's direction. The scan answers *where* -- never *what* -- so
## every return uses the same sound and nothing here reads a Describable's
## label. Identity is earned by holding FOCUS on a source (focusable.gd,
## §6.3); the two stay decoupled.
##
## How a return carries "where" (rework of the original scan, which pinged
## everything in range with a 2 s clip, so returns smeared into one buzz):
##   direction  the chirp plays 2 m from the head along the object's
##              horizontal bearing, so panning alone places it.
##   behind     stereo panning cannot tell front from back, so returns from
##              behind use a muffled, lower chirp -- the way a head shadows
##              sound arriving from behind it. Front returns are bright.
##   distance   encoded twice, and the two agree: a near return comes back
##              sooner AND louder (echo delay grows with distance, like real
##              echolocation), a far one later and quieter.
##   how many   at most max_returns, nearby objects merged into one return,
##              and no two returns within min_separation_deg of each other,
##              so each chirp is a direction you can point at.
##
## Dialogue is data-driven (§9.3): lines as resources/JSON with id, audio
## file, trigger, mandatory/cutscene flag. EventDirector fires by id.

## returns is an Array of return entries (see _gather_returns): position,
## bearing, distance, behind, band, delay, volume_db, node, nodes. The node
## references are for instrumentation only (§11's observer HUD wants to know
## what returned) -- nothing on the player-facing audio path reads a label.
signal scan_performed(returns: Array)
signal spoke(line_id: StringName)
## One return's chirp just started playing. Fires per return, at the moment
## it becomes audible, so debug visuals line up with what the ear gets.
signal return_pinged(entry: Dictionary)

## Seconds between scans. A press inside it plays a soft dull tick instead
## of scanning, so the button never feels dead and can never rapid-fire.
@export var scan_cooldown: float = 3.0

## Fixed offset from the player's head, in head-local space (§9.1).
@export var shoulder_offset: Vector3 = Vector3(0.3, -0.15, 0.0)

## Bat voice gain. Above 0 dB so lines sit clearly over the environmental
## bed; the runtime-TTS fallback always speaks at the OS maximum.
@export var voice_volume_db: float = 8.0

## The voice the runtime-TTS fallback speaks unrendered lines in -- change
## this one line to swap it. An exact id from DisplayServer.tts_get_voices()
## (the "id" field, not the display name: several voices share a name across
## languages). Rendered clips are unaffected; their voice is set separately
## in voices/generate_voices.sh. An id this machine doesn't have falls back
## to the first English voice, with a warning listing what to use instead.
@export var tts_voice_id: String = "com.apple.voice.enhanced.en-US.Joelle"  # "Joelle (Enhanced)"

## --- Scan ------------------------------------------------------------------

## The most returns one scan gives back.
@export var max_returns: int = 3

## Hard range cap, applied on top of each Describable's own scan_radius --
## "range-limited to proximate sources" (§9.2).
@export var max_return_distance: float = 14.0

## Scannable objects closer together than this come back as ONE return at
## their middle: a cluster of creatures is one thing to walk toward, and
## three chirps from the same direction only read as a smear.
@export var merge_radius: float = 2.5

## A return within this many degrees (horizontal) of one already chosen is
## dropped, so every chirp in a scan is a clearly different direction.
@export var min_separation_deg: float = 35.0

## Echo delay after the outgoing chirp, nearest to farthest return.
@export var near_delay: float = 0.15
@export var far_delay: float = 0.9
## Returns never land closer together than this, even two at almost the
## same distance, so each is heard as its own chirp.
@export var min_return_gap: float = 0.45

## Return loudness, nearest to farthest (dB on top of the chirp itself).
@export var near_volume_db: float = 2.0
@export var far_volume_db: float = -14.0

## Horizontal angle off straight-ahead past which a return counts as
## behind and gets the muffled chirp. 100 rather than 90 so something
## exactly beside you still sounds bright.
@export var behind_angle_deg: float = 100.0

## Where returns are rendered: this far from the head along their bearing.
## Close, so panning is clean and loudness is ours to set rather than the
## 3D falloff's.
@export var render_distance: float = 2.0

## The bat says "nothing close" after a scan that found nothing, so silence
## after a sweep is never mistaken for the scan not working. A scan that
## did find things says nothing: the chirps are the answer.
@export var speak_when_empty: bool = true
@export var empty_line_delay: float = 0.5

## Distance bands, for the debug markers and the observer HUD only. The
## player hears distance continuously (delay + loudness), not in bands.
const NEAR_BAND_MAX := 4.5
const MID_BAND_MAX := 9.0

const SCAN_LINE_EMPTY := &"scan_nothing_close"

## Where voices/generate_voices.sh writes. Clips are addressed by id alone,
## so re-wording a line and re-running the generator changes nothing here —
## that is the whole point of the id indirection. Extensions are tried in
## order because the generator emits mp3 when ffmpeg or lame is installed
## and wav otherwise; the game should not care which.
const VOICE_DIR := "res://assets/sfx/voice/"
const VOICE_EXTENSIONS := ["mp3", "wav", "ogg"]

## Read for the runtime-TTS fallback, so an unrendered line still speaks.
const LINES_PATH := "res://voices/lines.txt"

var head: Node3D = null
var enabled: bool = true

var _last_scan: float = -999.0
## The player's own instrument: outgoing chirp, not-ready tick, recenter
## confirmation. Flat (both ears) and on the UI bus, so it is never stripped.
var _ui_player: AudioStreamPlayer = null
var _ping_pool: Array[AudioStreamPlayer3D] = []
var _voice_queue: Array = []
var _voice_cache: Dictionary = {}
var _speaking_line: bool = false
var _line_text: Dictionary = {}
var _fallback_warned: Dictionary = {}
var _tts_voice: String = ""
## Bumped per scan, so a stale scan's deferred return or line never lands
## on top of a newer scan.
var _scan_serial: int = 0

## Synthesized in code (_chirp) rather than delivered assets: their exact
## shape is the design -- short, sharp attack, nothing to smear -- and a
## missing file must never be able to make the scan silent.
var _sound_out: AudioStreamWAV = null
var _sound_front: AudioStreamWAV = null
var _sound_behind: AudioStreamWAV = null
var _sound_not_ready: AudioStreamWAV = null
var _sound_recenter: AudioStreamWAV = null


func _ready() -> void:
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "ScanUiPlayer"
	_ui_player.bus = AudioDirector.BUS_UI
	add_child(_ui_player)

	_sound_out = _chirp(1400.0, 4200.0, 0.22, 0.0, 0.45)
	_sound_front = _chirp(3100.0, 2300.0, 0.09, 38.0, 0.6)
	_sound_behind = _chirp(1150.0, 800.0, 0.13, 24.0, 0.6, 0.85)
	_sound_not_ready = _chirp(320.0, 260.0, 0.06, 45.0, 0.35, 0.9)
	_sound_recenter = _chirp(1900.0, 1900.0, 0.05, 50.0, 0.4)

	AudioDirector.bat_source.finished.connect(_on_bat_source_finished)
	GameState.recentered.connect(_on_recentered)
	_load_line_text()
	_setup_tts_fallback()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"bat_scan"):
		scan()
		get_viewport().set_input_as_handled()


## Player-initiated echolocation. Inside the cooldown it only plays the
## not-ready tick -- spamming the key can never stack scans.
func scan() -> void:
	if not enabled or GameState.input_locked:
		return
	if head == null:
		push_warning("BatCompanion.head is not set.")
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_scan < scan_cooldown:
		_play_ui(_sound_not_ready, -6.0)
		return
	_last_scan = now

	_play_ui(_sound_out, -4.0)
	_scan_serial += 1
	var serial := _scan_serial
	var found := _gather_returns()
	scan_performed.emit(found)
	for entry in found:
		_emit_return(entry, serial)
	if found.is_empty() and speak_when_empty:
		_say_empty(serial)


func _play_ui(stream: AudioStream, volume_db: float) -> void:
	_ui_player.stream = stream
	_ui_player.volume_db = volume_db
	_ui_player.play()


## Two quick ticks: the player cannot see a recenter happen.
func _on_recentered() -> void:
	if _ui_player == null:
		return
	_play_ui(_sound_recenter, -8.0)
	await get_tree().create_timer(0.09).timeout
	_play_ui(_sound_recenter, -8.0)


func _say_empty(serial: int) -> void:
	await get_tree().create_timer(empty_line_delay).timeout
	if serial != _scan_serial or is_speaking() or EventDirector.calm_active:
		return
	say(SCAN_LINE_EMPTY)


## The few most relevant returns, nearest first, each with its timing and
## loudness already decided. Steps: everything scannable in range -> merge
## near neighbours into one cluster -> rank (priority, then distance) ->
## keep only clearly separate directions, up to max_returns -> schedule.
func _gather_returns() -> Array:
	var origin := head.global_position
	var candidates: Array = []
	for node in get_tree().get_nodes_in_group(&"describable"):
		var d := node as Describable
		if d == null or not d.scannable() or not d.is_visible_in_tree():
			continue
		var distance := origin.distance_to(d.global_position)
		if distance > minf(d.scan_radius, max_return_distance) or distance < 0.3:
			continue
		candidates.append({"node": d, "distance": distance})
	candidates.sort_custom(func(a, b):
		if a.node.priority != b.node.priority:
			return a.node.priority > b.node.priority
		return a.distance < b.distance
	)

	# Merge: each candidate joins the first cluster whose centre is within
	# merge_radius, else starts its own. Ranked order means a cluster is
	# named after (and ranked by) its most relevant member.
	var clusters: Array = []
	for c in candidates:
		var pos: Vector3 = c.node.global_position
		var joined := false
		for cl in clusters:
			if cl.position.distance_to(pos) <= merge_radius:
				cl.nodes.append(c.node)
				cl.position = cl.position.lerp(pos, 1.0 / cl.nodes.size())
				joined = true
				break
		if not joined:
			clusters.append({"position": pos, "nodes": [c.node], "priority": c.node.priority})

	var yaw := GameState.effective_orientation().y
	var head_basis := Basis.from_euler(Vector3(0.0, yaw, 0.0))
	var chosen: Array = []
	for cl in clusters:
		if chosen.size() >= max_returns:
			break
		var offset: Vector3 = cl.position - origin
		offset.y = 0.0
		if offset.length() < 0.3:
			continue
		var bearing := offset.normalized()
		var separate := true
		for other in chosen:
			if rad_to_deg(bearing.angle_to(other.bearing)) < min_separation_deg:
				separate = false
				break
		if not separate:
			continue
		var local := head_basis.inverse() * bearing  # head space: -Z ahead, +X right
		var off_ahead := rad_to_deg(Vector3.FORWARD.angle_to(local))
		var distance := origin.distance_to(cl.position)
		chosen.append({
			"position": cl.position,
			"bearing": bearing,
			"local_bearing": local,
			"distance": distance,
			"behind": off_ahead > behind_angle_deg,
			"band": _band(distance),
			"node": cl.nodes[0],
			"nodes": cl.nodes,
		})

	chosen.sort_custom(func(a, b): return a.distance < b.distance)
	var last_delay := -INF
	for entry in chosen:
		var t := clampf(entry.distance / max_return_distance, 0.0, 1.0)
		var delay := maxf(lerpf(near_delay, far_delay, t), last_delay + min_return_gap)
		last_delay = delay
		entry["delay"] = delay
		entry["volume_db"] = lerpf(near_volume_db, far_volume_db, t)
	return chosen


func _band(distance: float) -> StringName:
	if distance <= NEAR_BAND_MAX:
		return &"near"
	if distance <= MID_BAND_MAX:
		return &"mid"
	return &"far"


## One chirp, placed render_distance from the head along the return's
## horizontal bearing in head space -- recomputed when it fires, so a head
## turned during the echo delay still hears the return from where the
## object really is.
func _emit_return(entry: Dictionary, serial: int) -> void:
	await get_tree().create_timer(entry.delay).timeout
	if serial != _scan_serial or head == null or not is_instance_valid(head):
		return
	var to_object: Vector3 = entry.position - head.global_position
	to_object.y = 0.0
	var bearing: Vector3 = to_object.normalized() if to_object.length() > 0.01 else entry.bearing

	var ping := _free_ping()
	ping.global_position = head.global_position + bearing * render_distance
	ping.stream = _sound_behind if entry.behind else _sound_front
	ping.volume_db = entry.volume_db + (-2.0 if entry.behind else 0.0)
	ping.play()
	return_pinged.emit(entry)


func _free_ping() -> AudioStreamPlayer3D:
	for p in _ping_pool:
		if not p.playing:
			return p

	var ping := AudioStreamPlayer3D.new()
	ping.bus = AudioDirector.BUS_UI
	# Loudness is set per return from distance; 3D falloff stays out of it.
	ping.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	ping.max_db = 12.0
	ping.panning_strength = 1.0
	add_child(ping)
	_ping_pool.append(ping)
	return ping


## A short tone gliding f_start -> f_end with a fast attack and an
## exponential decay (decay_rate per second; 0 = a gentle swell and fade,
## used for the outgoing sweep). darken > 0 low-passes it, for the muffled
## behind-you chirp. 16-bit mono.
func _chirp(f_start: float, f_end: float, seconds: float, decay_rate: float,
		amplitude: float, darken: float = 0.0) -> AudioStreamWAV:
	var rate := 44100
	var frames := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	var smoothed := 0.0
	var attack := int(rate * 0.003)
	for i in frames:
		var t := float(i) / rate
		var f := lerpf(f_start, f_end, t / seconds)
		phase += TAU * f / rate
		var env: float
		if decay_rate > 0.0:
			env = exp(-decay_rate * t) * minf(1.0, float(i) / attack)
		else:
			env = sin(PI * t / seconds)
		# A touch of second harmonic so it reads as a chirp, not a test tone.
		var v := (sin(phase) + 0.25 * sin(2.0 * phase)) * env * amplitude
		smoothed = lerpf(v, smoothed, darken)
		var tail := minf(1.0, float(frames - i) / (rate * 0.004))
		data.encode_s16(i * 2, int(clampf(smoothed * tail, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream


## Speak a pre-rendered line by id. The clip plays from AudioDirector's
## bat_source, which is pinned to the shoulder offset and re-positioned
## every frame from head orientation (§9.1) — so the voice is genuinely
## located on the player's shoulder and turns with them, rather than
## arriving flat in both ears.
##
## Hybrid, so a new line is playable the moment it is written rather than
## after someone remembers to run the generator: if a clip exists for the
## id it plays spatialized from the bat, and if not the id's text from
## lines.txt is read aloud with runtime TTS. Rendering the clip later takes
## over automatically — the clip path is simply tried first, so there is
## nothing to switch over and no code to change.
##
## The fallback is a playtesting aid, not a shipping path: OS speech cannot
## be spatialized, so a fallen-back line arrives flat in both ears instead
## of from the shoulder, and it varies between machines. Every id that
## falls back is named in a warning, once, so the list of what still needs
## rendering is visible in the log rather than something to go hunting for.
##
## Lines queue rather than interrupt — the bat cutting itself off mid-word
## reads as a bug, and CALM coaching is several short lines in sequence.
func say(line_id: StringName) -> void:
	if not enabled:
		return

	var stream := _voice_clip(line_id)
	if stream != null:
		_voice_queue.append({"id": line_id, "stream": stream})
		_pump_voice()
		return

	_speak_unrendered(line_id)


## No clip for this id yet: read its lines.txt text with runtime TTS.
func _speak_unrendered(line_id: StringName) -> void:
	var text: String = _line_text.get(line_id, "")
	if text.is_empty():
		push_warning(
			"BatCompanion: '%s' has neither a rendered clip nor an entry in voices/lines.txt — nothing to say."
			% line_id
		)
		return

	if not _fallback_warned.has(line_id):
		_fallback_warned[line_id] = true
		push_warning(
			"BatCompanion: '%s' has no rendered clip, speaking it with runtime TTS (flat, not from the bat). Run voices/generate_voices.sh to render it."
			% line_id
		)

	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	DisplayServer.tts_speak(text, _tts_voice, 100)
	spoke.emit(line_id)


## lines.txt is the same file the generator reads, so the spoken fallback
## and the rendered clip always come from one source of truth for wording.
func _load_line_text() -> void:
	var file := FileAccess.open(LINES_PATH, FileAccess.READ)
	if file == null:
		push_warning("BatCompanion: %s not found — unrendered lines will be silent." % LINES_PATH)
		return

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var sep := line.find("|")
		if sep == -1:
			continue
		_line_text[StringName(line.substr(0, sep).strip_edges())] = line.substr(sep + 1).strip_edges()


## Uses tts_voice_id when this machine has it. Keep it matching the rendered
## clips' voice, so a half-rendered set does not switch character
## mid-conversation.
func _setup_tts_fallback() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	var available: Array[String] = []
	for v in DisplayServer.tts_get_voices():
		available.append(String(v.get("id", "")))
	if available.has(tts_voice_id):
		_tts_voice = tts_voice_id
		return

	var english := DisplayServer.tts_get_voices_for_language("en")
	if english.size() > 0:
		_tts_voice = english[0]
	push_warning(
		"BatCompanion: TTS voice '%s' is not installed here; using '%s'. English voices available: %s"
		% [tts_voice_id, _tts_voice, ", ".join(english)]
	)


func shut_up() -> void:
	_voice_queue.clear()
	_speaking_line = false
	AudioDirector.bat_source.stop()


func is_speaking() -> bool:
	return _speaking_line or not _voice_queue.is_empty()


func _pump_voice() -> void:
	var source := AudioDirector.bat_source
	if _voice_queue.is_empty():
		return
	# Only another *line* defers this one: anything else that happens to be
	# on bat_source must not hold up a guided count, which exists precisely
	# because the player is struggling.
	if _speaking_line and source.playing:
		return

	var item: Dictionary = _voice_queue.pop_front()
	_speaking_line = true
	source.stream = item.stream
	# Reset gain: whatever else last used this player set its own level.
	source.volume_db = voice_volume_db
	source.play()
	spoke.emit(item.id)


func _on_bat_source_finished() -> void:
	_speaking_line = false
	_pump_voice()


## Looked up by id only — the generator owns filenames, so nothing here
## needs to change when a line's wording does.
func _voice_clip(line_id: StringName) -> AudioStream:
	if _voice_cache.has(line_id):
		return _voice_cache[line_id]

	for ext in VOICE_EXTENSIONS:
		var path := "%s%s.%s" % [VOICE_DIR, line_id, ext]
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream is AudioStream:
				_voice_cache[line_id] = stream
				return stream
	return null
