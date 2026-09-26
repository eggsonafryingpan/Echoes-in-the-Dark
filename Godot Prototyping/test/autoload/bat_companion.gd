extends Node

## Autoload this as "BatCompanion". Brief: CLAUDE_CODE_BRIEF.md §9, §13 Phases 6-7.
##
## Scan (bearing only, no identification) + dialogue, rendered as a virtual
## spatial source anchored to a fixed shoulder position via head-tracking
## (§9.1 default resolution — one clean audio path into the headphones, no
## physical shoulder speaker).
##
## The scan owns the whole echolocation verb as of Phase 6: cooldown, which
## sources return, and the spatialized pings themselves. The "Bat" autoload
## keeps only the speech backend (TTS queueing via say()/_pump()) — its old
## scan spoke label + clock bearing + distance, which is exactly the
## "current label-reading" behavior §9.2 says to replace.
##
## What a return is, and is not: a short ping rendered in 3D at the source's
## bearing. Direction is carried by where the ping sits in space, proximity
## by how loud it is. There is no speech, no coordinate readout, and no
## identity — two objects three metres apart sound identical because the
## scan's answer is *where*, never *what*. Identity is earned by holding
## FOCUS on a source (focusable.gd, §6.3); the two stay decoupled, and this
## file never reads a Describable's label.
##
## Dialogue is data-driven (§9.3): lines as resources/JSON with id, audio
## file, trigger, mandatory/cutscene flag. EventDirector fires by id.

## returns is an Array of {bearing: Vector3, distance: float, node: Describable}.
## The node reference is for instrumentation only (§11's sighted-observer
## replay/HUD wants to know what returned) — nothing on the player-facing
## audio path may read its label.
signal scan_performed(returns: Array)
signal spoke(line_id: StringName)

## ~2-3s per §9.2. Single source of truth for scan pacing: Bat routes its
## input action straight here rather than keeping a second cooldown.
@export var scan_cooldown: float = 2.5

## Fixed offset from the player's head, in head-local space (§9.1).
@export var shoulder_offset: Vector3 = Vector3(0.3, -0.15, 0.0)

## More simultaneous pings than this stop being separable as directions,
## which defeats the point of a bearing-only return.
@export var max_returns: int = 3

## Hard range cap, applied on top of each Describable's own scan_radius —
## "range-limited to proximate sources" (§9.2).
@export var max_return_distance: float = 14.0

## Returns fire nearest-first, this far apart, so several reads as distinct
## directions rather than one smeared chord.
@export var return_stagger: float = 0.12

## Scan feedback is the player's confirmation that their own action
## registered, so it must survive overload stripping (§4). The UI bus sends
## straight to Master; AudioDirector only ever fades Essential and
## Environmental, so nothing here can be silenced out from under the player.
const BUS_UI := &"UI"

var head: Node3D = null
var enabled: bool = true

var _last_scan: float = -999.0
var _sweep_player: AudioStreamPlayer = null
var _ping_pool: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	_sweep_player = AudioStreamPlayer.new()
	_sweep_player.name = "SweepPlayer"
	_sweep_player.bus = BUS_UI
	add_child(_sweep_player)


## Player-initiated echolocation. Silently no-ops inside the cooldown —
## spamming the key must not stack sweeps on top of each other.
func scan() -> void:
	if not enabled:
		return
	if head == null:
		push_warning("BatCompanion.head is not set.")
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_scan < scan_cooldown:
		return
	_last_scan = now

	_sweep_player.stream = SfxLibrary.get_stream(&"echolocation_sweep")
	_sweep_player.play()

	var found := _gather_returns()
	scan_performed.emit(found)
	for i in found.size():
		_emit_return(found[i], i * return_stagger)


## Nearest/highest-priority scannable sources in range, as
## {bearing, distance, node}. Continuous self-announcing sources are
## excluded by Describable.scannable().
func _gather_returns() -> Array:
	var results: Array = []
	var origin := head.global_position

	for node in get_tree().get_nodes_in_group(&"describable"):
		var d := node as Describable
		if d == null or not d.scannable():
			continue
		var offset := d.global_position - origin
		var distance := offset.length()
		if distance > minf(d.scan_radius, max_return_distance):
			continue
		if distance < 0.001:
			continue  # Standing inside it: no meaningful bearing to render.
		results.append({
			"bearing": offset / distance,
			"distance": distance,
			"node": d,
		})

	results.sort_custom(func(a, b):
		if a.node.priority != b.node.priority:
			return a.node.priority > b.node.priority
		return a.distance < b.distance
	)
	return results.slice(0, max_returns)


## One ping, placed along the source's bearing at its real distance so
## standard 3D attenuation does the nearer/louder work (§9.2). Every return
## uses the same stream: a per-object timbre would leak identity.
func _emit_return(entry: Dictionary, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if head == null:
			return  # Scene changed mid-sweep.

	var ping := _free_ping()
	ping.global_position = head.global_position + entry.bearing * entry.distance
	ping.stream = SfxLibrary.get_stream(&"echolocation_return")
	ping.play()


func _free_ping() -> AudioStreamPlayer3D:
	for p in _ping_pool:
		if not p.playing:
			return p

	var ping := AudioStreamPlayer3D.new()
	ping.bus = BUS_UI
	ping.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	ping.max_distance = max_return_distance * 1.5
	ping.unit_size = 4.0
	add_child(ping)
	_ping_pool.append(ping)
	return ping


func say(_line_id: StringName) -> void:
	pass  # Phase 7: data-driven dialogue lookup, then delegate to speech backend.
