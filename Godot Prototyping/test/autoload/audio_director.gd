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
## Flipping it off also immediately restores anything currently stripped,
## so the "off" demo always shows the full mix rather than whatever
## fraction happened to be stripped at the moment of the toggle.
var adaptive_enabled: bool = true:
	set(v):
		adaptive_enabled = v
		if not v:
			_fade_bus(BUS_ENVIRONMENTAL, 1.0)
			_fade_bus(BUS_ESSENTIAL, 1.0)

## Operator hotkey for the A/B toggle (§11), bound in Project Settings > Input Map.
const TOGGLE_ADAPTIVE_ACTION := &"toggle_adaptive_audio"

@export var fade_seconds: float = 1.5

## Base volume set via set_layer_volume(), independent of the strip/restore
## fade fraction below -- the two compose into the bus's actual volume_db
## (_apply_bus_volume) rather than fighting over the same value.
var _base_volume_linear: Dictionary = {
	BUS_PRIORITY: 1.0,
	BUS_ESSENTIAL: 1.0,
	BUS_ENVIRONMENTAL: 1.0,
}

## 1.0 = fully present, 0.0 = fully stripped. Priority never appears here --
## it's never stripped, so it has no fraction to track.
var _strip_fraction: Dictionary = {
	BUS_ESSENTIAL: 1.0,
	BUS_ENVIRONMENTAL: 1.0,
}

var _fade_tweens: Dictionary = {}

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
	_fade_bus(BUS_ENVIRONMENTAL, 0.0)
	layer_stripped.emit(BUS_ENVIRONMENTAL)


func strip_essential() -> void:
	_fade_bus(BUS_ESSENTIAL, 0.0)
	layer_stripped.emit(BUS_ESSENTIAL)


func restore_environmental() -> void:
	_fade_bus(BUS_ENVIRONMENTAL, 1.0)
	layer_restored.emit(BUS_ENVIRONMENTAL)


func restore_essential() -> void:
	_fade_bus(BUS_ESSENTIAL, 1.0)
	layer_restored.emit(BUS_ESSENTIAL)


## Main-menu per-layer volume control (§4). linear is 0..1; converted to dB
## so the slider behaves perceptually. This is the only place that should
## ever touch a bus's base volume -- strip/restore fade a separate
## multiplier on top (_strip_fraction), composed together in
## _apply_bus_volume() rather than the two fighting over the same value.
func set_layer_volume(layer: StringName, linear: float) -> void:
	if not _base_volume_linear.has(layer):
		push_warning("AudioDirector.set_layer_volume: unknown bus %s" % layer)
		return
	_base_volume_linear[layer] = clampf(linear, 0.0, 1.0)
	_apply_bus_volume(layer)


## target_fraction 0.0 = fully stripped, 1.0 = fully present. Stripping
## (target < 1.0) is skipped while the A/B toggle has adaptation off, so a
## demo operator never gets a strip landing after they've already switched
## to the non-adaptive comparison; restoring always proceeds regardless.
func _fade_bus(layer: StringName, target_fraction: float) -> void:
	if not _strip_fraction.has(layer):
		return  # Priority: never stripped, nothing to fade.
	if target_fraction < 1.0 and not adaptive_enabled:
		return

	if _fade_tweens.has(layer) and is_instance_valid(_fade_tweens[layer]):
		_fade_tweens[layer].kill()

	var start_fraction: float = _strip_fraction[layer]
	var tw := create_tween()
	_fade_tweens[layer] = tw
	tw.tween_method(_set_strip_fraction.bind(layer), start_fraction, target_fraction, fade_seconds)


func _set_strip_fraction(fraction: float, layer: StringName) -> void:
	_strip_fraction[layer] = fraction
	_apply_bus_volume(layer)


func _apply_bus_volume(layer: StringName) -> void:
	var bus_idx := AudioServer.get_bus_index(layer)
	if bus_idx == -1:
		return
	var base: float = _base_volume_linear.get(layer, 1.0)
	var strip: float = _strip_fraction.get(layer, 1.0)
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(base * strip))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ADAPTIVE_ACTION):
		adaptive_enabled = not adaptive_enabled
