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
## Each source is also a physical thing in the world: a bat on the ceiling,
## a visible swarm, water along its stretch. The mesh is built at runtime
## under Body, and the AudioStreamPlayer3D is Body's child, so the sound
## and the object it belongs to always move together. The player never sees
## these (the demo runs under the black overlay, §1) -- they are for the
## sighted-observer / aerial view and for playtesting. Colours follow the F7
## debug key where one exists. No collision: nothing here is something the
## player should bump into (water is walked through, the bat and swarm are
## overhead). A future rock-like source should add its own StaticBody3D.

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

## --- Physical body --------------------------------------------------------

enum BodyKind { AUTO, NONE, BAT, SWARM, WATER, WATERFALL, DRIP, WIND }

## AUTO picks from sfx_name (see BODY_FOR_SFX); set explicitly to override.
@export var body_kind: BodyKind = BodyKind.AUTO

## Footprint of stretched bodies (water along a river or stream). Zero
## means the kind's default. X/Z are the stretch; Y is ignored for water.
@export var body_size: Vector3 = Vector3.ZERO

const BODY_FOR_SFX := {
	&"bat_chitter": BodyKind.BAT,
	&"swarm_cue": BodyKind.SWARM,
	&"river_flow_large": BodyKind.WATER,
	&"river_flow_small": BodyKind.WATER,
	&"waterfall": BodyKind.WATERFALL,
	&"water_drip": BodyKind.DRIP,
	&"wind_passage": BodyKind.WIND,
	&"wind_passage_soft": BodyKind.WIND,
}

const COLOR_BAT := Color(0.55, 0.2, 0.8)          # PURPLE, as F7's roost
const COLOR_SWARM := Color(0.9, 0.1, 0.1)         # RED, as F7's swarm
const COLOR_DRIP := Color(0.15, 0.35, 1.0)        # BLUE, as F7's drip
const COLOR_WATER := Color(0.1, 0.55, 0.9, 0.7)
const COLOR_WIND := Color(0.85, 0.9, 1.0, 0.3)
const COLOR_ROCK := Color(0.45, 0.42, 0.4)

## How far up/down to look for the cave's floor and ceiling.
const SURFACE_PROBE := 30.0

@onready var body: Node3D = $Body
@onready var player: AudioStreamPlayer3D = $Body/AudioStreamPlayer3D


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
	_build_body()


func _resolved_kind() -> BodyKind:
	if body_kind != BodyKind.AUTO:
		return body_kind
	return BODY_FOR_SFX.get(sfx_name, BodyKind.NONE)


## Waits one physics frame so the cave's trimesh collision (makeCollision.gd)
## is in the space, then seats the object on the floor or ceiling and builds
## its mesh. Sources are authored at ear height; water lying on the floor
## and a bat hanging from the ceiling is what they actually are.
func _build_body() -> void:
	var kind := _resolved_kind()
	if kind == BodyKind.NONE:
		return
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	var floor_y: Variant = _probe(Vector3.DOWN)
	var ceiling_y: Variant = _probe(Vector3.UP)
	var cave_height: float = (ceiling_y - floor_y) if floor_y != null and ceiling_y != null else 4.0

	match kind:
		BodyKind.BAT:
			if ceiling_y != null:
				global_position.y = ceiling_y
			_build_bat()
		BodyKind.SWARM:
			_build_swarm()
		BodyKind.WATER:
			if floor_y != null:
				global_position.y = floor_y
			_build_water()
		BodyKind.WATERFALL:
			if floor_y != null:
				global_position.y = floor_y
			_build_waterfall(cave_height)
		BodyKind.DRIP:
			if floor_y != null:
				global_position.y = floor_y
			_build_drip(cave_height)
		BodyKind.WIND:
			if floor_y != null:
				global_position.y = floor_y
			_build_wind(cave_height)


## World-space Y of the cave surface above or below, or null if none.
func _probe(direction: Vector3) -> Variant:
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * SURFACE_PROBE)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not (hit.collider is StaticBody3D):
		return null
	return hit.position.y


# --- Meshes -----------------------------------------------------------------

func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	# Emissive so each object reads in a dark cave and from the aerial view.
	m.emission_enabled = true
	m.emission = Color(color.r, color.g, color.b)
	m.emission_energy_multiplier = 0.6
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _add_mesh(part_name: String, mesh: Mesh, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = _material(color)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	return mi


## Hanging upside down from the ceiling, wings folded. The root sits on the
## ceiling, so everything hangs below it.
func _build_bat() -> void:
	var torso := CapsuleMesh.new()
	torso.radius = 0.08
	torso.height = 0.28
	_add_mesh("Torso", torso, COLOR_BAT, Vector3(0, -0.2, 0))

	var head := SphereMesh.new()
	head.radius = 0.07
	head.height = 0.14
	_add_mesh("Head", head, COLOR_BAT, Vector3(0, -0.38, 0))

	for side in [-1.0, 1.0]:
		var wing := PrismMesh.new()
		wing.size = Vector3(0.22, 0.3, 0.02)
		_add_mesh("Wing" + ("L" if side < 0 else "R"), wing, COLOR_BAT.darkened(0.3),
				Vector3(side * 0.1, -0.2, 0), Vector3(0, 0, 180 + side * 15))

	var feet := CylinderMesh.new()
	feet.top_radius = 0.015
	feet.bottom_radius = 0.015
	feet.height = 0.06
	_add_mesh("Feet", feet, COLOR_BAT.darkened(0.3), Vector3(0, -0.03, 0))


## A loose cloud of insects around the source. Seeded from the node name so
## the cloud is identical every run (and every reset between demoers).
func _build_swarm() -> void:
	var dot := SphereMesh.new()
	dot.radius = 0.045
	dot.height = 0.09
	dot.radial_segments = 6
	dot.rings = 3

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = dot
	multimesh.instance_count = 60

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(name))
	var extent := body_size if body_size != Vector3.ZERO else Vector3(1.6, 0.9, 1.6)
	for i in multimesh.instance_count:
		# Rejection-free ellipsoid sample, denser toward the middle.
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var r := pow(rng.randf(), 0.6)
		multimesh.set_instance_transform(i, Transform3D(Basis(), dir * extent * r))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Swarm"
	mmi.multimesh = multimesh
	mmi.material_override = _material(COLOR_SWARM)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mmi)


## A flat sheet of water lying on the floor along the source's stretch.
func _build_water() -> void:
	var size := body_size if body_size != Vector3.ZERO else Vector3(5.0, 0.0, 2.0)
	var sheet := BoxMesh.new()
	sheet.size = Vector3(size.x, 0.05, size.z)
	_add_mesh("Water", sheet, COLOR_WATER, Vector3(0, 0.03, 0))


## A sheet of falling water from the ceiling into a pool on the floor.
func _build_waterfall(cave_height: float) -> void:
	var width := body_size.x if body_size.x > 0.0 else 2.5
	var fall := BoxMesh.new()
	fall.size = Vector3(width, cave_height, 0.15)
	_add_mesh("Fall", fall, COLOR_WATER, Vector3(0, cave_height * 0.5, 0))

	var pool := CylinderMesh.new()
	pool.top_radius = width * 0.7
	pool.bottom_radius = width * 0.7
	pool.height = 0.05
	_add_mesh("Pool", pool, COLOR_WATER, Vector3(0, 0.03, 0.4))


## A stalactite overhead and the small puddle it drips into. The root (and
## the sound) sits on the puddle, where the drops land.
func _build_drip(cave_height: float) -> void:
	var puddle := CylinderMesh.new()
	puddle.top_radius = 0.45
	puddle.bottom_radius = 0.45
	puddle.height = 0.03
	_add_mesh("Puddle", puddle, COLOR_DRIP, Vector3(0, 0.02, 0))

	var stalactite := CylinderMesh.new()
	stalactite.top_radius = 0.18
	stalactite.bottom_radius = 0.0
	stalactite.height = 0.7
	_add_mesh("Stalactite", stalactite, COLOR_ROCK, Vector3(0, cave_height - 0.35, 0))

	var drop := SphereMesh.new()
	drop.radius = 0.04
	drop.height = 0.1
	_add_mesh("Drop", drop, COLOR_DRIP, Vector3(0, cave_height - 0.9, 0))


## A faint column of moving air rising from a crack in the floor.
func _build_wind(cave_height: float) -> void:
	var crack := BoxMesh.new()
	crack.size = Vector3(1.0, 0.04, 0.15)
	_add_mesh("Crack", crack, COLOR_ROCK.darkened(0.5), Vector3(0, 0.02, 0))

	var draft := CylinderMesh.new()
	draft.top_radius = 0.6
	draft.bottom_radius = 0.3
	draft.height = cave_height
	_add_mesh("Draft", draft, COLOR_WIND, Vector3(0, cave_height * 0.5, 0))
