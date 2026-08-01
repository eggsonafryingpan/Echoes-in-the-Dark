extends Node

## Autoload this as "Bat".
##
## Single authority for everything the companion says. Every line of speech in
## the game goes through say(), so when you swap the speech backend later —
## pre-rendered clips, Piper, whatever — you change one function and nothing
## else in the project notices.
##
## Bearings are reported as clock positions because that is the convention
## orientation-and-mobility instructors actually teach. "Door at two o'clock"
## is a phrase your players may already think in.
##
## Bearings are computed from the HEAD, not the body. That is deliberate: it
## means the same object is described differently depending on where the player
## is looking, which reinforces the head-direction coupling instead of
## competing with it.

signal spoke(text: String, reason: String)

const MAX_ITEMS := 3
const SCAN_COOLDOWN := 1.5

const CLOCK_WORDS := {
	0: "straight ahead",
	1: "right",
	2: "behind you",
	3: "left"
}

## Tuned to sound flat and synthetic rather than warm. Lower pitch, slightly
## fast. Adjust to taste — this is the bat's character.
@export var volume: int = 60
@export var pitch: float = 0.8
@export var rate: float = 1.15

## Set this from your level: Bat.head = $Player/Head
var head: Node3D = null

## Turn off to silence the bat entirely (useful for a control condition).
var enabled: bool = true

var _voice: String = ""
var _last_scan: float = -999.0
var _speaking: bool = false
var _queue: Array = []
var _next_id: int = 1


func _ready() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		push_error("TTS unavailable. Project Settings > Audio > General > Text To Speech must be on. On Linux you also need speech-dispatcher installed.")
		return
	_pick_voice()
	DisplayServer.tts_set_utterance_callback(
		DisplayServer.TTS_UTTERANCE_ENDED, _on_utterance_done
	)
	DisplayServer.tts_set_utterance_callback(
		DisplayServer.TTS_UTTERANCE_CANCELED, _on_utterance_done
	)


func _pick_voice() -> void:
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if voices.size() > 0:
		_voice = voices[0]
	else:
		push_warning("No English TTS voice installed on this machine.")


## Move this to your player script if you'd rather keep input in one place.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"bat_scan"):
		scan()
		get_viewport().set_input_as_handled()


# --- speech -------------------------------------------------------------

## The one function that speaks. Swap the body of _pump() to change backends.
func say(text: String, reason: String = "", interrupt: bool = false) -> void:
	if not enabled or text.is_empty():
		return
	if interrupt:
		_queue.clear()
		DisplayServer.tts_stop()
		_speaking = false
	_queue.append({"text": text, "reason": reason})
	_pump()


func shut_up() -> void:
	_queue.clear()
	DisplayServer.tts_stop()
	_speaking = false


func is_speaking() -> bool:
	return _speaking or not _queue.is_empty()


func _pump() -> void:
	if _speaking or _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	_speaking = true
	_next_id += 1
	DisplayServer.tts_speak(item.text, _voice, volume, pitch, rate, _next_id, false)
	spoke.emit(item.text, item.reason)


func _on_utterance_done(_utterance_id: int) -> void:
	_speaking = false
	_pump()


# --- scanning -----------------------------------------------------------

## Player-initiated area scan. reason is logged with the spoke signal so you
## can separate requested speech from volunteered speech in your session data.
func scan(reason: String = "player_request") -> void:
	if head == null:
		push_warning("Bat.head is not set.")
		return

	var now := Time.get_ticks_msec() / 1000.0
	if reason == "player_request" and now - _last_scan < SCAN_COOLDOWN:
		return
	_last_scan = now

	var found := nearby()
	if found.is_empty():
		say("Nothing close enough to make out.", reason, true)
		return

	var parts: Array[String] = []
	for entry in found:
		var d: Describable = entry.node
		parts.append("%s, %s, %d meters" % [
			d.label, CLOCK_WORDS[entry.clock], int(round(entry.distance))
		])
		d.announced = true
	say(". ".join(parts) + ".", reason, true)


## Returns up to MAX_ITEMS dictionaries: {node, distance, clock}
## sorted by priority then proximity.
func nearby() -> Array:
	var results: Array = []
	if head == null:
		return results
	var origin := head.global_position
	var basis := head.global_transform.basis

	for node in get_tree().get_nodes_in_group(&"describable"):
		var d := node as Describable
		if d == null or not d.available():
			continue
		var dist := origin.distance_to(d.global_position)
		if dist > d.scan_radius:
			continue
		results.append({
			"node": d,
			"distance": dist,
			"clock": _clock(origin, basis, d.global_position),
		})

	results.sort_custom(func(a, b):
		if a.node.priority != b.node.priority:
			return a.node.priority > b.node.priority
		return a.distance < b.distance
	)
	return results.slice(0, MAX_ITEMS)


# --- bearings -----------------------------------------------------------

## Clock hour of a world position relative to where the head is facing.
func clock_to(target: Vector3) -> int:
	if head == null:
		return 12
	return _clock(head.global_position, head.global_transform.basis, target)


func clock_word(deg: int) -> String:
	return CLOCK_WORDS.get(deg, "straight ahead")


func _clock(origin: Vector3, basis: Basis, target: Vector3) -> int:
	var to_target := target - origin
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return 12
	to_target = to_target.normalized()

	var forward := -basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right := basis.x
	right.y = 0.0
	right = right.normalized()

	# +angle is to the player's right
	var angle := atan2(to_target.dot(right), to_target.dot(forward))
	print("deg",angle)
	var deg = (angle + PI/2) / (PI / 4)
	print(deg)
	#var hour := int(round(angle / (TAU / 12.0)))
	#if hour <= 0:
		#hour += 12
	return deg
