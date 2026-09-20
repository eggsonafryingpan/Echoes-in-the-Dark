# SFX drop-in list

Drop a `.wav` or `.ogg` file with the exact name below into the listed folder.
No code or manifest changes needed — `manifest.json` already lists every
name the game asks for. If a file is missing, the game plays a short
placeholder beep instead of staying silent, so you can tell at a glance
what's still needed.

**One extra step after adding files:** open the project once in the Godot
editor (or ask for a headless `--import` pass) so Godot actually notices the
new files. Just dropping them in isn't quite enough — that's a Godot engine
requirement, not something we can skip.

## assets/sfx/priority/

| Logical name | Expected filename |
|---|---|
| goal_music_motif | goal_music_motif.wav / .ogg |
| swarm_cue | swarm_cue.wav / .ogg |

## assets/sfx/essential/

| Logical name | Expected filename |
|---|---|
| footstep_rock | footstep_rock.wav / .ogg |
| footstep_gravel | footstep_gravel.wav / .ogg |
| footstep_mud | footstep_mud.wav / .ogg |
| footstep_water_shallow | footstep_water_shallow.wav / .ogg |
| wall_collision_thud | wall_collision_thud.wav / .ogg |
| heartbeat_calm | heartbeat_calm.wav / .ogg |
| heartbeat_elevated | heartbeat_elevated.wav / .ogg |
| breathing_calm | breathing_calm.wav / .ogg |
| breathing_panicked | breathing_panicked.wav / .ogg |
| echolocation_sweep | echolocation_sweep.wav / .ogg |
| echolocation_return | echolocation_return.wav / .ogg |

## assets/sfx/animals/

| Logical name | Expected filename |
|---|---|
| bat_chitter | bat_chitter.wav / .ogg |
| bat_wingbeat | bat_wingbeat.wav / .ogg |
| small_prey_rustle | small_prey_rustle.wav / .ogg |
| larger_creature_breathing | larger_creature_breathing.wav / .ogg |
| larger_creature_footsteps | larger_creature_footsteps.wav / .ogg |

All calm/non-threatening variants — nothing aggressive or jump-scare-y.

## assets/sfx/environmental/

| Logical name | Expected filename |
|---|---|
| water_drip | water_drip.wav / .ogg |
| distant_water_flow | distant_water_flow.wav / .ogg |
| wind_passage | wind_passage.wav / .ogg |
| rock_creak | rock_creak.wav / .ogg |
| reverb_bed_low | reverb_bed_low.wav / .ogg |
| rockslide_opening | rockslide_opening.wav / .ogg |
| ambience_flavor_01 | ambience_flavor_01.wav / .ogg |
| ambience_flavor_02 | ambience_flavor_02.wav / .ogg |

## assets/sfx/ui/

| Logical name | Expected filename |
|---|---|
| ui_confirm | ui_confirm.wav / .ogg |
| ui_back | ui_back.wav / .ogg |

---

Need a new sound the game doesn't ask for yet? That's a one-line addition to
`manifest.json` (ping whoever's writing the code) — everything above is
already wired and just waiting for files.
