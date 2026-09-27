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
## and a short bat acknowledgement (plus the Describable's label/detail).

signal revealed()

## Half-angle (degrees) of the "looking at it" cone at t=0, before relax.
@export var focus_cone_start_deg: float = 15.0
## Half-angle (degrees) the cone relaxes to by relax_seconds.
@export var focus_cone_max_deg: float = 40.0

## Seconds of continuous, aligned dwell needed to reveal at t=0.
@export var focus_seconds_required: float = 4.0
## What that required dwell relaxes to by relax_seconds.
@export var focus_seconds_required_min: float = 1.5

## Progress lost per second while not aligned (fraction of 1.0) --
## "drifting decays it," not an instant reset.
@export var decay_per_second: float = 0.4

## Auto-relax ramps linearly over this many seconds since first activated.
@export var relax_seconds: float = 15.0

## Fail-forward: reveals regardless after this long in range, no matter
## how aligned the player has or hasn't been.
@export var fail_forward_seconds: float = 25.0

## How close the player needs to be for this to activate at all (avoids
## building/decaying progress based on stale alignment from far away).
@export var activation_radius: float = 14.0

## AudioStreamPlayer3D whose volume rises as focus builds. Relative to this
## node (e.g. "../SwarmAmbience/AudioStreamPlayer3D").
@export var audio_player_path: NodePath
@export var min_volume_db: float = -24.0
@export var max_volume_db: float = 0.0

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
@export var discovery_volume_db: float = 6.0

## --- After the reveal ------------------------------------------------------
##
## Before this block existed the reveal changed nothing you could hear:
## focus drops the source to min_volume_db when it activates and builds it
## back to max_volume_db, which is where the authored source sat to begin
## with, and it stayed on whatever layer it was on (the swarm: Environmental,
## the first thing overload strips). So the payoff was the sting and then
## exactly the sound you started with.
##
## Now a revealed source stays clearer than it ever was before: it rises
## revealed_boost_db above max_volume_db and moves to revealed_bus, out of
## the layer that is stripped first. Something identified is no longer
## texture -- it is a known thing in the scene. Essential, not Priority:
## it informs the route but is not itself the objective (§4).
@export var revealed_boost_db: float = 4.0
@export var revealed_bus: StringName = &"Essential"
@export var reveal_rise_seconds: float = 0.8

## The bat reacts once the sting has landed -- acknowledges, never names
## what it is (§1: the player discovers, the game does not explain).
## &"" to stay silent.
@export var reveal_line: StringName = &"focus_reveal_ready"
@export var reveal_line_delay: float = 1.2

var revealed_state: bool = false
var focus_progress: float = 0.0  # 0..1

var _t_active: float = -1.0  # seconds since first in range; -1 = never yet
var _audio_player: AudioStreamPlayer3D = null
var _describable: Node = null


func _ready() -> void:
	if audio_player_path != NodePath():
		_audio_player = get_node_or_null(audio_player_path)
	_describable = get_node_or_null(describable_path) if describable_path != NodePath() else get_node_or_null("Describable")


func _physics_process(delta: float) -> void:
	if revealed_state or GameState.input_locked:
		return

	var dist: float = global_position.distance_to(GameState.head_position)
	if dist > activation_radius:
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

	if angle <= cone:
		focus_progress = clampf(focus_progress + delta / required, 0.0, 1.0)
	else:
		focus_progress = clampf(focus_progress - decay_per_second * delta, 0.0, 1.0)

	_apply_volume()

	if focus_progress >= 1.0 or _t_active >= fail_forward_seconds:
		_reveal()


func _apply_volume() -> void:
	if _audio_player == null:
		return
	_audio_player.volume_db = lerpf(min_volume_db, max_volume_db, focus_progress)


func _reveal() -> void:
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
	_play_discovery()
	_acknowledge()
	revealed.emit()


func _hold_revealed() -> void:
	if _audio_player == null:
		return
	if revealed_bus != &"":
		_audio_player.bus = revealed_bus
	create_tween().tween_property(_audio_player, "volume_db",
			max_volume_db + revealed_boost_db, reveal_rise_seconds)


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
## Priority bus, because the instant the mechanic rewards the player is
## the worst possible instant for the overload detector to be fading
## things out — and a plain AudioStreamPlayer3D rather than a raytraced
## one, which would reassign its own bus on proximity and quietly escape
## Priority (see spatial_sfx_source.gd).
##
## Spatialized at this node rather than flat, so the sting comes from the
## thing that was just identified. The player is already facing it — that
## is how the focus was built — so it arrives in front of them.
func _play_discovery() -> void:
	if discovery_sfx == &"":
		return
	var player := AudioStreamPlayer3D.new()
	player.name = "DiscoverySting"
	player.bus = AudioDirector.BUS_PRIORITY
	player.stream = SfxLibrary.get_stream(discovery_sfx)
	player.volume_db = discovery_volume_db
	player.max_db = 12.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.max_distance = 30.0
	player.unit_size = 6.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
