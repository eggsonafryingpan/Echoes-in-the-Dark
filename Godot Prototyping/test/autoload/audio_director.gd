extends Node

## Autoload this as "AudioDirector". Brief: CLAUDE_CODE_BRIEF.md §4, §13 Phase 2.
##
## The only thing that changes SFX complexity. Owns the three priority buses
## (paper taxonomy, not the earlier "essential/environmental/elective" draft):
##
##   Priority     - the 1-2 sources representing the current objective. Never stripped.
##   Essential    - story/progression cues that inform the route. Stripped second.
##   Environmental - ambience and spatial texture. Stripped first.
##
## Also owns the godot-steam-audio listener, which is driven by head
## orientation (GameState.orientation), independent of translation (§6.1).
##
## Strip/restore is a smooth fade, never a cut (§4). OverloadDetector calls
## strip_environmental() / strip_essential() / restore_*(); nothing else
## should touch bus volumes directly, so the A/B adaptive toggle (§11) and the
## main-menu per-layer volume sliders (§4) have exactly one place to hook.

signal layer_stripped(layer: StringName)
signal layer_restored(layer: StringName)

const BUS_PRIORITY := &"Priority"
const BUS_ESSENTIAL := &"Essential"
const BUS_ENVIRONMENTAL := &"Environmental"

## Reviewer-requested A/B toggle (§11): when false, overload never strips
## anything, so a demo operator can show the non-adaptive experience.
var adaptive_enabled: bool = true

@export var fade_seconds: float = 1.5

## Bat's virtual spatial source (§9.1): one clean audio path into the
## headphones, anchored to a fixed shoulder offset that tracks head rotation.
## Not raytraced -- it never has a wall between it and the listener, so
## muffle/echo would just add artifacts. BatCompanion (Phase 6-7) assigns
## .stream and calls .play()/.stop() on this; nothing else should.
var bat_source: AudioStreamPlayer3D = null

## The AudioListener3D actually driving godot-steam-audio's (raytraced_audio's)
## spatialization, and the node whose global_position stands in for "where the
## player's head physically is" (translation only -- see _process).
var _listener: AudioListener3D = null
var _position_anchor: Node3D = null


func _ready() -> void:
	bat_source = AudioStreamPlayer3D.new()
	bat_source.name = "BatSource"
	bat_source.bus = BUS_ESSENTIAL
	add_child(bat_source)


## Call once from the player scene's _ready(): tells AudioDirector which
## AudioListener3D to drive and which node's position stands in for the head
## (translation only). Orientation for both the listener and bat_source comes
## exclusively from GameState.effective_orientation() (see _process) -- never
## from position_anchor's own rotation -- so swapping the control scheme
## later (decoupled head/movement, §6.1) needs no changes here.
func register_listener(listener: AudioListener3D, position_anchor: Node3D) -> void:
	_listener = listener
	_position_anchor = position_anchor


func _process(_delta: float) -> void:
	if _listener == null or _position_anchor == null:
		return

	var orientation := GameState.effective_orientation()
	_listener.global_position = _position_anchor.global_position
	_listener.global_rotation = orientation

	if bat_source != null:
		var basis := Basis.from_euler(orientation)
		bat_source.global_position = _position_anchor.global_position + basis * BatCompanion.shoulder_offset
		bat_source.global_basis = basis


func strip_environmental() -> void:
	pass  # Phase 3: fade BUS_ENVIRONMENTAL to silence if adaptive_enabled.


func strip_essential() -> void:
	pass  # Phase 3: fade BUS_ESSENTIAL to silence if adaptive_enabled.


func restore_environmental() -> void:
	pass  # Phase 3: fade BUS_ENVIRONMENTAL back in.


func restore_essential() -> void:
	pass  # Phase 3: fade BUS_ESSENTIAL back in.


## Main-menu per-layer volume control (§4). linear is 0..1; converted to dB
## so the slider behaves perceptually. This is the only place that should
## ever touch these buses' base volume -- strip/restore (Phase 3) fade a
## separate multiplier on top via AudioServer, not this value.
func set_layer_volume(layer: StringName, linear: float) -> void:
	var bus_idx := AudioServer.get_bus_index(layer)
	if bus_idx == -1:
		push_warning("AudioDirector.set_layer_volume: unknown bus %s" % layer)
		return
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clampf(linear, 0.0, 1.0)))
