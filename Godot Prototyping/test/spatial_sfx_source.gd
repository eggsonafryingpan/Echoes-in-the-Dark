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

## The Describable child (res://scripts/describable.gd) carries its own
## label/detail/scan_radius/priority exports -- set those directly as a
## per-instance override on the "Describable" node in the scene file, not
## here. Describable's own _ready() (a child, so it runs before this node's)
## checks label at that point, so proxying it through this script's _ready()
## would always see the pre-override default and warn spuriously.
@onready var player: AudioStreamPlayer3D = $AudioStreamPlayer3D


func _ready() -> void:
	var stream: AudioStream = SfxLibrary.get_stream(sfx_name)
	if loop and (stream is AudioStreamMP3 or stream is AudioStreamOggVorbis):
		stream.loop = true
	player.stream = stream
	player.bus = bus
	if autoplay:
		player.play()
