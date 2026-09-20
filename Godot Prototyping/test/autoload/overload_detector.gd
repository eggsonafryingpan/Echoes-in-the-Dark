extends Node

## Autoload this as "OverloadDetector". Brief: CLAUDE_CODE_BRIEF.md §5, §13 Phase 3.
##
## Conjunctive detector: fires only when BOTH hold —
##   1. HR elevated above session baseline (motion-gated reads only), AND
##   2. behavioral evidence of struggle (repeated wall collisions + no
##      reduction in distance to objective + few object interactions, within
##      a rolling window).
##
## The existing "Stuck" autoload already implements a reasonable version of
## the behavioral half (no-progress / collisions / confinement, 2-of-3). Its
## own comments already anticipate this: "with heart rate added, keep the
## threshold at two but require that at least one of them be behavioral."
## Phase 3 is expected to fold Stuck's counters into GameState and make HR
## the conjunctive AND-term here, not to throw Stuck's logic away.
##
## This never fires on HR alone, never claims to measure cognitive load, and
## identifies a state, not a quantity (§0.1, §5) — real-time cognitive-load
## inference from consumer wearables isn't established, and arousal is hard
## to separate from cognitive demand. Keep that framing in any future
## comments here, not just this header.
##
## Arbitration: EventDirector sets suppress_during_calm = true while a CALM
## sequence is active, because CALM *expects* elevated HR and stripping
## ambience then would fight the mechanic it's supposed to support (§5, §8).

signal overload_detected()
signal recovered()

var enabled: bool = true

## Set by EventDirector during an active CALM sequence (§5 arbitration).
var suppress_during_calm: bool = false


func _physics_process(_delta: float) -> void:
	if not enabled or suppress_during_calm:
		return
	# Phase 3: read GameState.hr_elevated AND behavioral counters;
	# on conjunction, AudioDirector.strip_environmental() then strip_essential();
	# on recovery, restore in the opposite order.
	pass
