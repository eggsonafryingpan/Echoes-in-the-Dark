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
## What a return is, and is not: a short ping rendered in 3D at the source's
## bearing. Direction is carried by where the ping sits in space, proximity
## by how loud it is. There is no speech, no coordinate readout, and no
## identity — two objects three metres apart sound identical because the
## scan's answer is *where*, never *what*. Identity is earned by holding
## FOCUS on a source (focusable.gd, §6.3); the two stay decoupled, and this
## file never reads a Describable's label.
##
## Dialogue is data-driven (§9.3): lines as resources/JSON with id, audio
## file, trigger, mandatory/cutscene flag. EventDirector fires by id.

## returns is an Array of {bearing: Vector3, distance: float, node: Describable}.
## The node reference is for instrumentation only (§11's sighted-observer
## replay/HUD wants to know what returned) — nothing on the player-facing
## audio path may read its label.
signal scan_performed(returns: Array)
signal spoke(line_id: StringName)
## One return's ping just started playing. Fires per return, at the moment
## it becomes audible, so debug visuals line up with what the ear gets.
signal return_pinged(entry: Dictionary)

## ~2-3s per §9.2. Single source of truth for scan pacing: Bat routes its
## input action straight here rather than keeping a second cooldown.
@export var scan_cooldown: float = 2.5

## Fixed offset from the player's head, in head-local space (§9.1).
@export var shoulder_offset: Vector3 = Vector3(0.3, -0.15, 0.0)

## Bat voice gain. Above 0 dB so lines sit clearly over the environmental
## bed; the runtime-TTS fallback always speaks at the OS maximum.
@export var voice_volume_db: float = 8.0

## More simultaneous pings than this stop being separable as directions,
## which defeats the point of a bearing-only return.
@export var max_returns: int = 3

## Hard range cap, applied on top of each Describable's own scan_radius —
## "range-limited to proximate sources" (§9.2).
@export var max_return_distance: float = 14.0

## Returns fire nearest-first, this far apart, so several reads as distinct
## directions rather than one smeared chord.
@export var return_stagger: float = 0.35

## Returns wait this long after the press. startup.mp3 peaks around
## 0.2-0.5 s, and pings fired on top of it were masked outright -- the
## original cause of "I scan and hear no returns".
@export var return_delay: float = 0.7

## Ping gain. detected.mp3 peaks at about -17 dBFS and the pings are
## distance-attenuated on top of that, so at 0 dB they sat under the
## environmental bed.
@export var return_volume_db: float = 10.0

## The sweep is a 3 s flat drone at roughly ping level; it fades out over
## this long as the first return lands so the pings are not competing with it.
@export var sweep_fade_seconds: float = 0.3

## Speak a short, non-identifying acknowledgement after each scan.
@export var speak_after_scan: bool = true
## Gap between the last ping starting and the line.
@export var scan_line_delay: float = 0.6

const SCAN_LINES_NONE: Array[StringName] = [&"scan_nothing_close"]
const SCAN_LINES_ONE: Array[StringName] = [&"scan_found_one_a", &"scan_found_one_b"]
const SCAN_LINES_FEW: Array[StringName] = [&"scan_found_few_a", &"scan_found_few_b"]

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
var _trigger_player: AudioStreamPlayer = null
var _sweep_player: AudioStreamPlayer = null
var _ping_pool: Array[AudioStreamPlayer3D] = []
var _voice_queue: Array = []
var _voice_cache: Dictionary = {}
var _speaking_line: bool = false
var _line_text: Dictionary = {}
var _fallback_warned: Dictionary = {}
var _tts_voice: String = ""
var _sweep_tween: Tween = null
var _last_scan_line: StringName = &""
## Bumped per scan, so a stale scan's deferred line or sweep fade never
## lands on top of a newer scan.
var _scan_serial: int = 0


func _ready() -> void:
	# Two separate non-positional players because the trigger blip and the
	# sweep overlap: the blip answers "your press registered" the instant
	# the key goes down, while the sweep is still running underneath it.
	# One AudioStreamPlayer can only carry one of them.
	_trigger_player = _make_flat_player("TriggerPlayer")
	_sweep_player = _make_flat_player("SweepPlayer")
	AudioDirector.bat_source.finished.connect(_on_bat_source_finished)
	_load_line_text()
	_setup_tts_fallback()


## Non-positional (AudioStreamPlayer, not 3D): the trigger blip and the
## sweep are the player's own instrument, not something in the cave, so
## they belong flat in both ears rather than somewhere in the world. On the
## UI bus, so overload stripping can never take away the confirmation that
## the player's own action registered.
func _make_flat_player(node_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = AudioDirector.BUS_UI
	add_child(player)
	return player


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"bat_scan"):
		scan()
		get_viewport().set_input_as_handled()


## Player-initiated echolocation. Silently no-ops inside the cooldown —
## spamming the key must not stack sweeps on top of each other.
func scan() -> void:
	if not enabled or GameState.input_locked:
		return
	if head == null:
		push_warning("BatCompanion.head is not set.")
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_scan < scan_cooldown:
		return
	_last_scan = now

	# Trigger blip first, then the sweep under it. Both flat, both UI bus.
	_trigger_player.stream = SfxLibrary.get_stream(&"ui_startup")
	_trigger_player.play()
	if _sweep_tween != null:
		_sweep_tween.kill()
	_sweep_player.volume_db = 0.0
	_sweep_player.stream = SfxLibrary.get_stream(&"ui_scan_sweep")
	_sweep_player.play()

	_scan_serial += 1
	var serial := _scan_serial
	var found := _gather_returns()
	scan_performed.emit(found)
	for i in found.size():
		_emit_return(found[i], return_delay + i * return_stagger)
	_finish_scan(serial, found.size())


## Fade the sweep as returns start, then acknowledge the scan in words.
func _finish_scan(serial: int, count: int) -> void:
	await get_tree().create_timer(return_delay).timeout
	if serial != _scan_serial:
		return
	_sweep_tween = create_tween()
	_sweep_tween.tween_property(_sweep_player, "volume_db", -60.0, sweep_fade_seconds)
	_sweep_tween.tween_callback(_sweep_player.stop)

	if not speak_after_scan:
		return
	var tail := maxf(0, count - 1) * return_stagger + scan_line_delay
	await get_tree().create_timer(tail).timeout
	if serial != _scan_serial:
		return
	_say_scan_line(count)


## Flavor only: says *how many* in the vaguest terms, never what or where.
## Skipped if the bat is already talking or CALM is running -- bat_source
## carries CALM's breathing and coaching, and a scan quip must never
## interrupt or queue behind that.
func _say_scan_line(count: int) -> void:
	if is_speaking() or EventDirector.calm_active:
		return
	var pool := SCAN_LINES_NONE
	if count == 1:
		pool = SCAN_LINES_ONE
	elif count > 1:
		pool = SCAN_LINES_FEW
	var choices := pool.filter(func(id): return id != _last_scan_line)
	if choices.is_empty():
		choices = pool
	_last_scan_line = choices.pick_random()
	say(_last_scan_line)


## Nearest/highest-priority scannable sources in range, as
## {bearing, distance, node}. Continuous self-announcing sources are
## excluded by Describable.scannable().
func _gather_returns() -> Array:
	var results: Array = []
	var origin := head.global_position

	for node in get_tree().get_nodes_in_group(&"describable"):
		var d := node as Describable
		if d == null or not d.scannable():
			continue
		var offset := d.global_position - origin
		var distance := offset.length()
		if distance > minf(d.scan_radius, max_return_distance):
			continue
		if distance < 0.001:
			continue  # Standing inside it: no meaningful bearing to render.
		results.append({
			"bearing": offset / distance,
			"distance": distance,
			"node": d,
		})

	results.sort_custom(func(a, b):
		if a.node.priority != b.node.priority:
			return a.node.priority > b.node.priority
		return a.distance < b.distance
	)
	return results.slice(0, max_returns)


## One ping, placed along the source's bearing at its real distance so
## standard 3D attenuation does the nearer/louder work (§9.2). Every return
## uses the same stream: a per-object timbre would leak identity.
func _emit_return(entry: Dictionary, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if head == null:
			return  # Scene changed mid-sweep.

	var ping := _free_ping()
	ping.global_position = head.global_position + entry.bearing * entry.distance
	ping.stream = SfxLibrary.get_stream(&"ui_scan_detected")
	ping.play()
	return_pinged.emit(entry)


func _free_ping() -> AudioStreamPlayer3D:
	for p in _ping_pool:
		if not p.playing:
			return p

	var ping := AudioStreamPlayer3D.new()
	ping.bus = AudioDirector.BUS_UI
	ping.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	ping.max_distance = max_return_distance * 1.5
	ping.unit_size = 6.0
	ping.volume_db = return_volume_db
	ping.max_db = 12.0
	add_child(ping)
	_ping_pool.append(ping)
	return ping


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


## Match the rendered clips' voice where it exists, so a half-rendered set
## does not switch character mid-conversation.
func _setup_tts_fallback() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	for v in DisplayServer.tts_get_voices():
		if String(v.get("name", "")).to_lower() == "superstar":
			_tts_voice = String(v.get("id", ""))
			return
	var english := DisplayServer.tts_get_voices_for_language("en")
	if english.size() > 0:
		_tts_voice = english[0]


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
	# Only another *line* defers this one. bat_source also carries the bat's
	# breathing during CALM (event_director.gd), and a guided count that
	# waited politely behind a breathing loop would never be heard at all —
	# the hint exists precisely because the player is struggling.
	if _speaking_line and source.playing:
		return

	var item: Dictionary = _voice_queue.pop_front()
	_speaking_line = true
	source.stream = item.stream
	# Reset gain: whatever else last used this player set its own level
	# (CALM's breathing hint drops it to -6 dB and never puts it back).
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
