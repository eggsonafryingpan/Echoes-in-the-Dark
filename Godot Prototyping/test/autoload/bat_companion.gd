extends Node

## Autoload this as "BatCompanion". Brief: CLAUDE_CODE_BRIEF.md §9, §13 Phases 6-7.
##
## Scan (bearing only, no identification) + dialogue, rendered as a virtual
## spatial source anchored to a fixed shoulder position via head-tracking
## (§9.1 default resolution — one clean audio path into the headphones, no
## physical shoulder speaker).
##
## The existing "Bat" autoload already implements the speech backend (TTS
## queueing via say()/_pump(), diegetic and clean to reuse as-is) and a scan
## that finds nearby Describable nodes. Its scan currently speaks label +
## clock bearing + distance directly, which is the "current label-reading"
## behavior §9.2 calls out to rework: the scan should return bearing only
## (spatialized directional returns), and identity should be earned via
## FOCUS instead. That rework is Phase 6, not this scaffold — do not
## reimplement Bat's TTS plumbing here, migrate/wrap it.
##
## Dialogue is data-driven (§9.3): lines as resources/JSON with id, audio
## file, trigger, mandatory/cutscene flag. EventDirector fires by id.

signal scan_performed(returns: Array)
signal spoke(line_id: StringName)

## ~2-3s per §9.2, replaces Bat.SCAN_COOLDOWN once the rework lands.
@export var scan_cooldown: float = 2.5

## Fixed offset from the player's head, in head-local space (§9.1).
@export var shoulder_offset: Vector3 = Vector3(0.3, -0.15, 0.0)

var head: Node3D = null
var enabled: bool = true


func scan() -> void:
	pass  # Phase 6: bearing-only spatialized returns, no spoken coordinates.


func say(_line_id: StringName) -> void:
	pass  # Phase 7: data-driven dialogue lookup, then delegate to speech backend.
