class_name Describable
extends Node3D

## Attach as a CHILD of anything the bat should be able to describe.
##
## This node holds data only — it never speaks. Position it at the point you
## actually want described, which is often not the parent's origin: for a
## tunnel, put it at the mouth; for a ledge, put it at the near edge.
##
## An object can have both a Describable and an AudioStreamPlayer3D. They are
## different systems. The AudioStreamPlayer3D is the sound the object makes on
## its own. The Describable is what the bat says about it when asked.

## Short phrase spoken during a scan. Keep it to a few words — during a scan
## the player is hearing three of these in a row.
@export var label: String = ""

## Longer line, used on dwell or on a repeated scan of the same object.
@export_multiline var detail: String = ""

## The bat will not mention this object beyond this distance.
@export var scan_radius: float = 12.0

## Higher priority is spoken first. Suggested: exits 100, hazards 50,
## landmarks 10, scenery 0.
@export var priority: int = 0

## If true, this is described once per session and then goes quiet.
## Useful for one-off story beats, bad for anything load-bearing to navigation.
@export var announce_once: bool = false

## Mark the objects you expect players to build their mental map around.
## Not used by the bat — it's here so you can log landmark encounters
## separately when you analyse whether cognitive mapping actually happened.
@export var is_landmark: bool = false

## True for sources that announce themselves continuously anyway — rivers,
## waterfalls, wind through rock. The scan never returns these (§9.2): they
## are already heard directly, so a ping on top of them spends one of the
## scan's few returns telling the player something they cannot miss. The
## scan is for discrete, quiet objects.
@export var continuous: bool = false

var announced: bool = false

## Set by a sibling Focusable on reveal. Identity is earned through sustained
## FOCUS, never handed over by the scan (§9.2) — nothing should speak this
## object as a recognised thing while this is false.
var identified: bool = false


func _ready() -> void:
	add_to_group(&"describable")
	if label.is_empty():
		push_warning("Describable on %s has no label." % get_parent().name)


func available() -> bool:
	return not (announce_once and announced)


## Eligible to produce a scan return. Distance is the caller's test, not
## this one's — BatCompanion range-limits against its own max as well as
## this node's scan_radius.
func scannable() -> bool:
	return available() and not continuous
