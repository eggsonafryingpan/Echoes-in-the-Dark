extends Node3D

## Reusable spatial-audio object (CLAUDE_CODE_BRIEF.md §12): looks up a
## logical sound name from SfxLibrary, plays it through an AudioStreamPlayer3D
## child on the given AudioDirector bus, and doubles as a Describable so the
## (rework-pending, §9.2/Phase 6) echolocation scan can find it. One scene
## type, configured per instance via the exports below -- not a copy-pasted
## node tree per sound.
##
## Deliberately a PLAIN AudioStreamPlayer3D, not RaytracedAudioPlayer3D:
## RaytracedAudioListener's muffle system calls .enable() on any
## RaytracedAudioPlayer3D that comes within its own max_distance, and
## enable() reassigns .bus to a freshly generated per-instance bus that
## sends into RaytracedReverb -> Master -- silently bypassing whatever named
## bus (Environmental/Essential/Priority) was set, the instant the object
## becomes audible. That would make AudioDirector.strip_environmental()/
## strip_essential() have zero effect on any of these once in range
## (confirmed empirically, not assumed -- see the Phase 3 SFX commit).
## Standard AudioStreamPlayer3D attenuation (attenuation_model/max_distance/
## unit_size, set on the child below) still gives real distance falloff;
## the trade-off is no per-wall muffle/lowpass for these ambient sources,
## which matters far less for background ambience than reliable layer
## stripping does. A future Essential-layer spatial source that specifically
## needs wall-muffle should account for this same interaction rather than
## assume RaytracedAudioPlayer3D + a named bus "just works."
##
## No visual movement/oscillation is added here on purpose -- this is an
## audio-only game (§1); a bob or wobble would be effort spent on something
## nobody experiences.

@export var sfx_name: StringName = &""
@export var bus: StringName = &"Environmental"
@export var loop: bool = true
@export var autoplay: bool = true

## --- Describable values, proxied from HERE rather than set on the child ---
##
## These used to be set as per-instance overrides directly on each
## instance's "Describable" child. Godot drops overrides made on the
## children of an instanced scene when it re-serialises the scene, and that
## is exactly what happened: a re-save silently wiped every label and every
## `continuous = true` flag, which put the rivers, wind and waterfalls back
## into the scan's results and left the discrete objects competing with
## eight ambient loops for three return slots.
##
## Overrides on an instance's own ROOT node survive that, so the root now
## owns these and pushes them down. Applied in _enter_tree(), not _ready():
## _enter_tree runs parent-first, so the child sees its real label before
## its own _ready() checks whether the label is empty.
@export var label: String = ""
@export_multiline var detail: String = ""

## Continuously self-announcing (rivers, wind, waterfalls) -- excluded from
## scan returns per §9.2, since they are already heard directly.
@export var continuous: bool = false

@export var scan_priority: int = 0
@export var scan_radius: float = 12.0

## --- 3D placement ---------------------------------------------------------
##
## Per-source rather than shared, because an ambient river and a discrete
## water drip want opposite settings: the river should be quiet and local,
## audible only near itself, while the drip should read clearly across the
## room. Sharing one setting for both is what made the cave sound like one
## continuous river from any position.
@export var volume_db: float = 0.0
@export var max_distance: float = 25.0

## With ATTENUATION_INVERSE_DISTANCE, gain is unit_size / distance -- so
## this is the falloff steepness, and halving it halves the distance at
## which a source is still at full level.
@export var unit_size: float = 4.0

@onready var player: AudioStreamPlayer3D = $AudioStreamPlayer3D


func _enter_tree() -> void:
	var describable := get_node_or_null("Describable")
	if describable == null:
		return
	if label != "":
		describable.label = label
	if detail != "":
		describable.detail = detail
	describable.continuous = continuous
	describable.priority = scan_priority
	describable.scan_radius = scan_radius


func _ready() -> void:
	var stream: AudioStream = SfxLibrary.get_stream(sfx_name)
	if loop and (stream is AudioStreamMP3 or stream is AudioStreamOggVorbis):
		stream.loop = true
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	player.max_distance = max_distance
	player.unit_size = unit_size
	if autoplay:
		player.play()
