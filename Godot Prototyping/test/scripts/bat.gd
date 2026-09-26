extends Node

## Autoload this as "Bat".
##
## Single authority for everything the companion says. Every line of speech in
## the game goes through say(), so when you swap the speech backend later —
## pre-rendered clips, Piper, whatever — you change one function and nothing
## else in the project notices.
##
## Speech only. This used to own the scan as well, and that scan spoke
## "label, left, four metres" — the clock-bearing readout §9.2 calls out to
## replace. Phase 6 moved the whole verb to BatCompanion, where a scan
## renders spatialized bearing-only pings and says nothing at all; the clock
## vocabulary went with it rather than lingering as dead code. Verbal lines
## are now reserved for story beats, FOCUS prompts and CALM coaching (§9.2).

signal spoke(text: String, reason: String)

## Tuned to sound flat and synthetic rather than warm. Lower pitch, slightly
## fast. Adjust to taste — this is the bat's character.
@export var volume: int = 60
@export var pitch: float = 0.8
@export var rate: float = 1.15

## Turn off to silence the bat entirely (useful for a control condition).
var enabled: bool = true

var _voice: String = ""
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
## The action routes to BatCompanion, which owns the scan and its cooldown.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"bat_scan"):
		BatCompanion.scan()
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
