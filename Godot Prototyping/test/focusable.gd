class_name Focusable
extends Node3D

## Sustained head orientation toward this object raises its cue's volume
## and builds toward a "reveal" (identity/recognizability), per
## CLAUDE_CODE_BRIEF.md §6.3. FOCUS supplies identity; the scan supplies
## only bearing -- this is "the voluntary counterpart to automatic layer
## removal" (§6.3). Attach as a component (sibling node) on whatever Node3D
## represents a focus target; point audio_player_path at whichever
## AudioStreamPlayer3D's volume should rise as focus builds.
##
## The two halves stay decoupled on purpose: BatCompanion.scan() never reads
## a label and never consults this node, and this node never waits on a scan.
## A player can hold focus on something they heard directly and identify it
## without scanning at all; a scan tells them where to point but hands over
## nothing about what is there. The only handoff is the `identified` flag
## this sets on the linked Describable when the reveal lands (§9.2).
##
## Anti-lockout (§7), both mechanisms present, not just one:
##   1. Auto-relax: the alignment cone widens and the dwell required
##      shrinks continuously from the moment this becomes active, so a
##      player who's merely close (not perfectly on-target) still resolves
##      it, and sooner the longer they've been trying.
##   2. Fail-forward timeout: reveals regardless after fail_forward_seconds
##      of being in range at all, aligned or not. No permanent lockout is
##      possible from this component.
##
## No visual movement/oscillation (§1, audio-only game) -- the observable
## effects are all audio: the linked player's volume while building, and on
## reveal the discovery sting, the source settling louder on a safer layer,
## and the bat saying what it is (plus the Describable's label/detail).

signal revealed()

## Off = frozen: neither builds nor decays nor counts toward fail-forward.
## For a target that only means something once its event has started (the
## exit wind before Event 2).
@export var active: bool = true
## Only start building once a scan has returned this target, so the discovery
## follows the loop: scan pings it, the bat flags it, FOCUS names it. Without
## this, simply facing it in passing could name it.
@export var requires_scan: bool = false

## Half-angle (degrees) of the "looking at it" cone at t=0, before relax.
@export var focus_cone_start_deg: float = 15.0
## Half-angle (degrees) the cone relaxes to by relax_seconds.
@export var focus_cone_max_deg: float = 40.0

## Seconds of continuous, aligned dwell needed to reveal at t=0. Long
## enough that the rise is something you hear happen rather than a switch:
## at the old 4 s (relaxing to 1.5) it was over before it registered.
@export var focus_seconds_required: float = 10.0
## What that required dwell relaxes to by relax_seconds.
@export var focus_seconds_required_min: float = 6.0

## Progress lost per second while not aligned (fraction of 1.0) --
## "drifting decays it," not an instant reset.
@export var decay_per_second: float = 0.2

## Auto-relax ramps linearly over this many seconds since first activated.
@export var relax_seconds: float = 30.0

## Fail-forward: reveals regardless after this long in range, no matter
## how aligned the player has or hasn't been.
@export var fail_forward_seconds: float = 60.0

## How close the player needs to be for this to activate at all (avoids
## building/decaying progress based on stale alignment from far away).
@export var activation_radius: float = 14.0

## AudioStreamPlayer3D whose volume rises as focus builds. Relative to this
## node (e.g. "../SwarmAmbience/AudioStreamPlayer3D").
@export var audio_player_path: NodePath
## Where the source sits with no focus on it, and where it peaks at full
## focus. 0 dB is the authored level, so the peak is well above anything
## the source does on its own: holding focus makes the sound itself
## louder, not merely back to where it started. The player's max_db is
## raised to match in _ready, or the 3D player's default +3 dB ceiling
## would swallow the top of the rise at close range.
@export var min_volume_db: float = -18.0
@export var max_volume_db: float = 10.0

## Describable to update on reveal. Defaults to a "Describable" sibling if
## left unset; set explicitly when the object being focused isn't this
## node's own sibling (e.g. "../SwarmAmbience/Describable").
@export var describable_path: NodePath

## Applied to the sibling "Describable" node (if any) on reveal. Empty
## strings leave that field as whatever it already was.
@export var revealed_label: String = ""
@export var revealed_detail: String = ""

## The discovery sting, played once when the reveal lands. Set to &"" on a
## focus target that should resolve silently.
@export var discovery_sfx: StringName = &"focus_discovery"
## The sting peaks around -17 dBFS and is spatialized at the target, so at
## 0 dB it could pass unnoticed under the bed from across the chamber.
@export var discovery_volume_db: float = 9.0
## How fast the source's level follows the focus, in dB per second.
@export var volume_glide_db_per_second: float = 18.0

## --- After the reveal ------------------------------------------------------
##
## Before this block existed the reveal changed nothing you could hear:
## focus drops the source to min_volume_db when it activates and builds it
## back to max_volume_db, which is where the authored source sat to begin
## with, and it stayed on whatever layer it was on (the swarm: Environmental,
## the first thing overload strips). So the payoff was the sting and then
## exactly the sound you started with.
##
## Now a revealed source stays clearer than it was before anyone focused
## on it: it settles at revealed_volume_db -- down from the focus peak,
## which is too loud to live with, but above the authored 0 dB -- and moves
## to revealed_bus, out of the layer that is stripped first. Something
## identified is no longer texture -- it is a known thing in the scene.
## Essential, not Priority: it informs the route but is not itself the
## objective (§4).
@export var revealed_volume_db: float = 5.0
@export var revealed_bus: StringName = &"Essential"
@export var reveal_settle_seconds: float = 2.0

## The bat reacts once the sting has landed, and says what the thing is.
## Each target sets its own line id here (voices/lines.txt, focus_reveal_*);
## the default is the generic acknowledgement for a target nobody has
## written a line for yet. &"" to stay silent.
@export var reveal_line: StringName = &"focus_reveal_ready"
@export var reveal_line_delay: float = 1.2

var revealed_state: bool = false
## True if the player built the focus all the way, false if it was given by the
## fail-forward timer or a skip. Only an earned reveal goes in the notes.
var earned: bool = false
var focus_progress: float = 0.0  # 0..1

var _t_active: float = -1.0  # seconds since first in range; -1 = never yet
var _audio_player: AudioStreamPlayer3D = null
var _original_bus: StringName = &""
var _settle_tween: Tween = null
var _describable: Node = null
# Last tick's geometry, kept only for focus_readout().
var _in_range: bool = false
var _aligned: bool = false
var _angle: float = 0.0
var _cone: float = 0.0


func _ready() -> void:
	add_to_group(&"focusable")
	if audio_player_path != NodePath():
		_audio_player = get_node_or_null(audio_player_path)
	if _audio_player != null:
		_audio_player.max_db = maxf(_audio_player.max_db, max_volume_db)
		_original_bus = _audio_player.bus
	_describable = get_node_or_null(describable_path) if describable_path != NodePath() else get_node_or_null("Describable")


func _physics_process(delta: float) -> void:
	if revealed_state or not active:
		_in_range = false
		return
	if GameState.input_locked:
		_in_range = false  # Frozen, not building: the readout should say so.
		return

	if requires_scan and _describable != null and not _describable.scanned:
		_in_range = false
		return
	var dist: float = global_position.distance_to(GameState.head_position)
	_in_range = dist <= activation_radius
	if not _in_range:
		return  # Out of range: hold state, neither build nor decay.

	if _t_active < 0.0:
		_t_active = 0.0
	_t_active += delta

	var relax_t: float = clampf(_t_active / relax_seconds, 0.0, 1.0)
	var cone: float = deg_to_rad(lerpf(focus_cone_start_deg, focus_cone_max_deg, relax_t))
	var required: float = lerpf(focus_seconds_required, focus_seconds_required_min, relax_t)

	var forward: Vector3 = -Basis.from_euler(GameState.effective_orientation()).z
	var to_target: Vector3 = (global_position - GameState.head_position)
	if to_target.length_squared() < 0.0001:
		to_target = forward
	else:
		to_target = to_target.normalized()
	var angle: float = forward.angle_to(to_target)
	_angle = angle
	_cone = cone
	_aligned = angle <= cone

	if _aligned:
		focus_progress = clampf(focus_progress + delta / required, 0.0, 1.0)
	else:
		focus_progress = clampf(focus_progress - decay_per_second * delta, 0.0, 1.0)

	_apply_volume(delta)

	if focus_progress >= 1.0 or _t_active >= fail_forward_seconds:
		earned = focus_progress >= 1.0
		_reveal()


## delta 0 sets the level at once (resets); otherwise it glides there, so
## stepping into range or a focus that wavers never jumps the level.
func _apply_volume(delta: float = 0.0) -> void:
	if _audio_player == null:
		return
	var target := lerpf(min_volume_db, max_volume_db, focus_progress)
	if delta <= 0.0:
		_audio_player.volume_db = target
	else:
		_audio_player.volume_db = move_toward(_audio_player.volume_db, target, volume_glide_db_per_second * delta)


## Skip/jump keys: reveal now. silent = no sting and no bat line, for
## jumping past the event rather than skipping through it.
func force_reveal(silent: bool = false) -> void:
	if revealed_state:
		return
	_reveal(silent)


## Back to never-focused, so a jump can replay the event.
func reset() -> void:
	if _settle_tween != null and _settle_tween.is_valid():
		_settle_tween.kill()
	revealed_state = false
	earned = false
	focus_progress = 0.0
	_t_active = -1.0
	if _audio_player != null and _original_bus != &"":
		_audio_player.bus = _original_bus
	_apply_volume()


func _reveal(silent: bool = false) -> void:
	revealed_state = true
	focus_progress = 1.0
	_apply_volume()
	_hold_revealed()
	if _describable != null:
		if revealed_label != "":
			_describable.label = revealed_label
		if revealed_detail != "":
			_describable.detail = revealed_detail
		_describable.identified = true
	if not silent:
		_play_discovery()
		_acknowledge()
	revealed.emit()


func _hold_revealed() -> void:
	if _audio_player == null:
		return
	if revealed_bus != &"":
		_audio_player.bus = revealed_bus
	_settle_tween = create_tween()
	_settle_tween.tween_property(_audio_player, "volume_db",
			revealed_volume_db, reveal_settle_seconds)


## Snapshot for the playtest focus readout (focus_debug_overlay.gd).
## Read-only; nothing on the audio path consults it.
func focus_readout() -> Dictionary:
	return {
		"in_range": _in_range,
		"aligned": _aligned,
		"angle_deg": rad_to_deg(_angle),
		"cone_deg": rad_to_deg(_cone),
		"progress": focus_progress,
		"revealed": revealed_state,
		"volume_db": _audio_player.volume_db if _audio_player != null else min_volume_db,
		"min_volume_db": min_volume_db,
		"max_volume_db": max_volume_db,
		"t": _t_active,
		"fail_forward_seconds": fail_forward_seconds,
		"label": _describable.label if _describable != null else String(name),
	}


## Skipped during CALM, like the post-scan line: bat_source carries CALM's
## coaching then, and this must not queue behind or talk over it.
func _acknowledge() -> void:
	if reveal_line == &"":
		return
	await get_tree().create_timer(reveal_line_delay).timeout
	if not is_inside_tree() or EventDirector.calm_active:
		return
	BatCompanion.say(reveal_line)


## The payoff: sustained attention turned an indistinct sound into
## something recognised, and this is the moment that lands (§6.3).
##
## Essential bus: discoveries are the story layer, stripped second, after the
## ambience. A plain AudioStreamPlayer3D rather than a raytraced one, which
## would reassign its own bus on proximity (see spatial_sfx_source.gd).
##
## Spatialized at this node rather than flat, so the sting comes from the
## thing that was just identified. The player is already facing it — that
## is how the focus was built — so it arrives in front of them.
func _play_discovery() -> void:
	if discovery_sfx == &"":
		return
	var player := AudioStreamPlayer3D.new()
	player.name = "DiscoverySting"
	player.bus = AudioDirector.BUS_ESSENTIAL
	player.stream = SfxLibrary.get_stream(discovery_sfx)
	player.volume_db = discovery_volume_db
	player.max_db = 12.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.max_distance = 30.0
	player.unit_size = 6.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
