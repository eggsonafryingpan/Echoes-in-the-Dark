extends Node

## Autoload this as "EventDirector". Brief: CLAUDE_CODE_BRIEF.md §7, §8, §10, §13 Phases 5-7.
##
## Sequences the three-event demo arc (CALM -> FOCUS -> REVEAL, §10) and owns
## each event's pass logic and anti-lockout timers (§7 FOCUS, §8 CALM). No
## mechanic may hard-lock the player out (§1, §14) — every event here MUST
## have a time-based fail-forward regardless of tuning.
##
## Also owns the suppress_during_calm flag on OverloadDetector: set it true
## for the duration of an active CALM sequence, false otherwise (§5).

signal event_started(event_id: StringName)
signal event_completed(event_id: StringName)

enum Event { CALM, FOCUS, REVEAL }

var current_event: Event = Event.CALM


func start_event(_event: Event) -> void:
	pass  # Phase 7: sequence in, set OverloadDetector.suppress_during_calm for CALM.


func _on_calm_timeout() -> void:
	pass  # Phase 5: ~25-30s fail-forward (§8 step 6). No lockout possible.


func _on_focus_timeout() -> void:
	pass  # Phase 4: ~20-25s fail-forward (§7 step 3). Player never learns a threshold existed.
