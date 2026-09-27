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

## Outside the three-layer taxonomy on purpose: player-facing feedback and
## the bat's own voice, neither of which may ever be stripped. Sends
## straight to Master and has no strip fraction, so nothing below can fade
## it. Owned here because this file owns bus names.
const BUS_UI := &"UI"

## Reviewer-requested A/B toggle (§11): when false, overload never strips
## anything, so a demo operator can show the non-adaptive experience.
## Flipping it off also immediately restores anything currently stripped,
## so the "off" demo always shows the full mix rather than whatever
## fraction happened to be stripped at the moment of the toggle.
var adaptive_enabled: bool = true:
	set(v):
		adaptive_enabled = v
		if not v and not force_strip:
			_fade_bus(BUS_ENVIRONMENTAL, 1.0)
			_fade_bus(BUS_ESSENTIAL, 1.0)

## Manual strip for tuning and filming: holds both strippable layers in a
## chosen state regardless of what OverloadDetector wants and regardless of
## the A/B toggle above. While true, strip_*/restore_* from the detector are
## ignored, so a forced state can't be undone by a detector tick landing a
## moment later; setting it false restores both layers and hands control
## back. Deliberately separate from adaptive_enabled: that switch answers
## "would this build adapt at all", this one answers "show me the stripped
## mix right now."
var force_strip: bool = false:
	set(v):
		if v == force_strip:
			return
		force_strip = v
		if v:
			# Snapshot what the detector had arrived at, so releasing the
			# override hands back exactly what it took rather than blanket-
			# restoring. Without this, dropping F3 while the detector is
			# mid-escalation would un-strip a layer the detector still
			# believes is stripped, and nothing would re-apply it until the
			# next state transition.
			_pre_force_fraction = {
				BUS_ENVIRONMENTAL: _strip_fraction[BUS_ENVIRONMENTAL],
				BUS_ESSENTIAL: _strip_fraction[BUS_ESSENTIAL],
			}
			_apply_fade(BUS_ENVIRONMENTAL, 0.0)
			_apply_fade(BUS_ESSENTIAL, 0.0)
		else:
			_apply_fade(BUS_ENVIRONMENTAL, _pre_force_fraction.get(BUS_ENVIRONMENTAL, 1.0))
			_apply_fade(BUS_ESSENTIAL, _pre_force_fraction.get(BUS_ESSENTIAL, 1.0))

## Operator hotkey for the A/B toggle (§11), bound in Project Settings > Input Map.
const TOGGLE_ADAPTIVE_ACTION := &"toggle_adaptive_audio"

@export var fade_seconds: float = 1.5

## Base volume set via set_layer_volume(), independent of the strip/restore
## fade fraction below -- the two compose into the bus's actual volume_db
## (_apply_bus_volume) rather than fighting over the same value.
var _base_volume_linear: Dictionary = {
	BUS_PRIORITY: 1.0,
	BUS_ESSENTIAL: 1.0,
	# ~-8 dB: the bed must sit under footsteps and the bat, not over them.
	BUS_ENVIRONMENTAL: 0.4,
}

## 1.0 = fully present, 0.0 = fully stripped. Priority never appears here --
## it's never stripped, so it has no fraction to track.
var _strip_fraction: Dictionary = {
	BUS_ESSENTIAL: 1.0,
	BUS_ENVIRONMENTAL: 1.0,
}

var _fade_tweens: Dictionary = {}

## What the detector had arrived at when force_strip was engaged, restored
## verbatim when it is released.
var _pre_force_fraction: Dictionary = {}

## Bat's virtual spatial source (§9.1): one clean audio path into the
## headphones, anchored to a fixed shoulder offset that tracks head rotation.
## Not raytraced -- it never has a wall between it and the listener, so
## muffle/echo would just add artifacts, and a RaytracedAudioPlayer3D would
## reassign .bus out from under us the moment it came in range (see
## spatial_sfx_source.gd). BatCompanion assigns .stream and calls
## .play()/.stop() on this; nothing else should.
##
## On the UI bus, not Essential: the companion's voice carries CALM
## coaching and FOCUS prompts, which are exactly the moments the overload
## detector is most likely to be stripping. A bat that goes quiet when the
## player most needs talking to would be the opposite of the mechanic.
var bat_source: AudioStreamPlayer3D = null

## The AudioListener3D actually driving godot-steam-audio's (raytraced_audio's)
## spatialization, and the node whose global_position stands in for "where the
## player's head physically is" (translation only -- see _process).
var _listener: AudioListener3D = null
var _position_anchor: Node3D = null


func _ready() -> void:
	bat_source = AudioStreamPlayer3D.new()
	bat_source.name = "BatSource"
	bat_source.bus = BUS_UI
	bat_source.max_db = 12.0
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
	if force_strip:
		return
	_fade_bus(BUS_ENVIRONMENTAL, 0.0)
	layer_stripped.emit(BUS_ENVIRONMENTAL)


func strip_essential() -> void:
	if force_strip:
		return
	_fade_bus(BUS_ESSENTIAL, 0.0)
	layer_stripped.emit(BUS_ESSENTIAL)


func restore_environmental() -> void:
	if force_strip:
		return
	_fade_bus(BUS_ENVIRONMENTAL, 1.0)
	layer_restored.emit(BUS_ENVIRONMENTAL)


func restore_essential() -> void:
	if force_strip:
		return
	_fade_bus(BUS_ESSENTIAL, 1.0)
	layer_restored.emit(BUS_ESSENTIAL)


## 1.0 = fully present, 0.0 = fully stripped. Priority reports 1.0 always —
## it has no strip fraction because it is never stripped.
func strip_fraction(layer: StringName) -> float:
	return _strip_fraction.get(layer, 1.0)


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
	if target_fraction < 1.0 and not adaptive_enabled:
		return
	_apply_fade(layer, target_fraction)


## The fade itself, with no policy attached. force_strip goes straight here
## so a manual override answers to neither the detector nor the A/B toggle.
func _apply_fade(layer: StringName, target_fraction: float) -> void:
	if not _strip_fraction.has(layer):
		return  # Priority: never stripped, nothing to fade.

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
