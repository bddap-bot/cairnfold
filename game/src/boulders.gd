class_name Boulders
extends Node3D

## The garden's boulders, each grown from its seed (BoulderLayout) in wall stone of its paint and style (StoneStyles), turned as it was set
## down, grown to its scale and resting on the ground under it. `World` puts and takes them, and reshapes their place,
## turn, size, paint and style; a hand holding one shows it where the hand has it (`show_held`) until it is let go; tools pick
## them by `pick`, a hand stops at them by `inside`.
## Each draws a near mesh and, past a distance that grows with it, a far one of a sixteenth the triangles, so a pebble
## costs little and a house-sized one keeps its outline far off.

## Where a unit boulder swaps to its far mesh, and where its far mesh stops drawing, in metres; both grow with its scale.
const NEAR_TO := 30.0
const FAR_TO := 220.0
## Occlusion a boulder is shaded with, as a laid stone carries.
const AO := 0.92
## A held boulder whooshes once its surface moves faster than SWING_FROM metres a second, fully at SWING_FULL, and only
## from WHOOSH_SIZE times a metre wide: a pebble swung about is silent.
const SWING_FROM := 0.6
const SWING_FULL := 5.0
const WHOOSH_SIZE := 0.4
## How fast a boulder meets the ground for its landing thud to be its loudest, in metres a second (a 2.5 m drop).
const LAND_FULL := 7.0

## One standing boulder.
class Boulder:
	extends Node3D
	var id := 0
	var shape: BoulderLayout.Shape
	var ground := Vector3.ZERO
	var turn := Quaternion.IDENTITY
	## How far it is pushed into the ground below where it would rest, in unit metres (BoulderLayout.rest).
	var sink := 0.0
	var size := 1.0
	## Whether a hand has it, so it is shown where the hand holds it, not resting on the ground.
	var held := false
	var data: Dictionary
	var near: MultiMeshInstance3D
	var far: MultiMeshInstance3D

	## Shows it as `d` ({at, turn, sink, seed, scale, paint, style}) has it, its seed its own.
	func appear(d: Dictionary) -> void:
		ground = d.at
		turn = d.turn
		sink = d.sink
		held = false
		# The stone shader tints a style by its paint as the swatch over the one stone is laid in.
		var c := Palette.swatch(Palette.Element.STONE, d.paint[Palette.Element.STONE]) / Palette.swatch(Palette.Element.STONE, 0)
		c.a = 1.0
		for mesh: MultiMeshInstance3D in [near, far]:
			mesh.multimesh.set_instance_color(0, c)
			mesh.set_instance_shader_parameter("stone_style", d.style)
		seat(d.scale)

	## Rests it at `scale` on the ground under it, or as deep in it as it was pushed, as the ground is now.
	func seat(scale: float) -> void:
		ground.y = Terrain.height_at(ground.x, ground.z)
		_show(BoulderLayout.rest(shape, turn, scale, ground.x, ground.z, Terrain.height_at, sink), scale)

	## Shows it at `pose` (unscaled) grown `scale` times, where a hand holds it; moving, it whooshes (`swing`).
	func hold(pose: Transform3D, scale: float) -> void:
		var was := pose()
		var moving := held
		held = true
		_show(Transform3D(pose.basis.orthonormalized() * Basis.from_scale(Vector3.ONE * scale), pose.origin), scale)
		if moving and scale >= WHOOSH_SIZE:
			var swing := Boulders.swing(was, pose, shape.reach() * scale, get_process_delta_time())
			if swing > 0.0:
				Cues.play(Cues.Act.BOULDER_MOVE, pose.origin, null, swing, scale)

	## Thuds as it lands where it now rests, let go with its centre at `from_y`.
	func landed(from_y: float, hand: XRController3D = null) -> void:
		Cues.play(Cues.Act.BOULDER_PLACE, position, hand, Boulders.impact(from_y - position.y), size)

	## Where it is and which way it is turned, unscaled.
	func pose() -> Transform3D:
		return Transform3D(transform.basis.orthonormalized(), transform.origin)

	func _show(at: Transform3D, scale: float) -> void:
		size = scale
		transform = at
		near.visibility_range_end = NEAR_TO * size
		far.visibility_range_begin = NEAR_TO * size
		far.visibility_range_end = FAR_TO * size


var boulders := {}
## Counts every put, take and resize, so what caches their shapes knows to look again.
var changes := 0


func _init() -> void:
	name = "Boulders"


## Puts boulder `id` as `data` ({at, turn, sink, seed, scale, paint, style}) has it; one standing with that seed keeps its meshes.
func put(id: int, data: Dictionary) -> Boulder:
	var b: Boulder = boulders.get(id)
	if b == null or b.shape.seed != data.seed:
		take(id)
		b = ghost(data)
		b.id = id
		b.name = "Boulder%d" % id
		boulders[id] = b
	b.data = data
	b.appear(data)
	changes += 1
	return b


## A boulder as `data` has it that is no part of the garden: nothing picks it or stops at it. Its holder frees it.
func ghost(data: Dictionary) -> Boulder:
	var b := Boulder.new()
	b.shape = BoulderLayout.shape(data.seed)
	b.near = _instance(b.shape, BoulderLayout.NEAR)
	b.far = _instance(b.shape, BoulderLayout.FAR)
	b.far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(b.near)
	b.add_child(b.far)
	add_child(b)
	b.data = data
	b.appear(data)
	return b


## Shows boulder `id` where a hand holds it: at `pose`, grown `scale` times.
func show_held(id: int, pose: Transform3D, scale: float) -> void:
	var b: Boulder = boulders.get(id)
	if b != null:
		b.hold(pose, scale)
		changes += 1


## Where a thing held at `pose` when the hand stood at `from` is, the hand now at `to`: it turns about its own centre
## as the hand turns, every way, and moves `gain` metres for each metre the hand moves.
static func carried(pose: Transform3D, from: Transform3D, to: Transform3D, gain: float) -> Transform3D:
	var turned := to.basis.orthonormalized() * from.basis.orthonormalized().inverse() * pose.basis
	return Transform3D(turned.orthonormalized(), pose.origin + (to.origin - from.origin) * gain)


## How hard a boulder moving from `from` to `to` in `seconds` swings, from 0 to 1: its centre's speed plus the speed its
## turn gives its surface, `reach` metres out.
static func swing(from: Transform3D, to: Transform3D, reach: float, seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	var turned := (to.basis.orthonormalized() * from.basis.orthonormalized().inverse()).get_rotation_quaternion().get_angle()
	var speed := (from.origin.distance_to(to.origin) + turned * reach) / seconds
	return clampf((speed - SWING_FROM) / (SWING_FULL - SWING_FROM), 0.0, 1.0)


## How hard a boulder falling `fall` metres lands, from 0 to 1; one set down where it was held still thuds, softly.
static func impact(fall: float) -> float:
	return clampf(sqrt(2.0 * 9.8 * maxf(fall, 0.0)) / LAND_FULL, 0.0, 1.0)


## Shows boulder `id` as a reshape with `data` would leave it, here alone.
func show_reshaped(id: int, data: Dictionary) -> void:
	var b: Boulder = boulders.get(id)
	if b != null:
		b.appear(World.reshaped(b.data, data))
		changes += 1


## Shows boulder `id` as the garden has it again.
func settle(id: int) -> void:
	show_reshaped(id, {})


static func _instance(shape: BoulderLayout.Shape, subdiv: int) -> MultiMeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoulderLayout.arrays(shape, subdiv))
	var mi := Masonry.Kind.new(mesh, Stones.shared_material(), true, true, GeometryInstance3D.SHADOW_CASTING_SETTING_ON).instance()
	mi.multimesh.instance_count = 1
	mi.multimesh.set_instance_transform(0, Transform3D.IDENTITY)
	mi.multimesh.set_instance_custom_data(0, Stones.custom({"ao": AO, "kind": "rubble"}))
	return mi


func take(id: int) -> void:
	var b: Boulder = boulders.get(id)
	if b == null:
		return
	boulders.erase(id)
	changes += 1
	remove_child(b)
	b.queue_free()


func clear() -> void:
	for id in boulders.keys():
		take(id)


func find(id: int) -> Boulder:
	return boulders.get(id)


## Rests the boulders reaching over `area` again on the ground as it now lies there; one a hand holds stays in hand.
func reseat(area: Rect2, _settled := true) -> void:
	for b: Boulder in boulders.values():
		if not b.held and area.grow(b.shape.reach() * b.size).has_point(Vector2(b.ground.x, b.ground.z)):
			b.seat(b.size)
			changes += 1


## The nearest boulder a ray from `origin` along `dir` meets within `reach`: {boulder, along, point}, or {}.
func pick(origin: Vector3, dir: Vector3, reach := INF) -> Dictionary:
	var best := {}
	var d := dir.normalized()
	for b: Boulder in boulders.values():
		var inv := b.transform.affine_inverse()
		var local_dir := inv.basis * d
		var unit := local_dir.length()
		var t := b.shape.hit(inv * origin, local_dir / unit, minf(reach, best.get("along", INF)) * unit)
		var point := origin + d * t / unit
		# What it meets first under the ground is its buried part, which the ground hides from the ray.
		if t < INF and point.y >= Terrain.height_at(point.x, point.z):
			best = {"boulder": b, "along": t / unit, "point": point}
	return best


## The top of the boulder under `p` at or below it, so a player stands on it; -INF over none.
func floor_under(p: Vector3) -> float:
	var rock := pick(p, Vector3.DOWN)
	return rock.point.y if not rock.is_empty() else -INF


## The boulder holding the point `p`, or null.
func inside(p: Vector3) -> Boulder:
	for b: Boulder in boulders.values():
		var local := b.transform.affine_inverse() * p
		if local.length() < b.shape.reach() and b.shape.inside(local):
			return b
	return null


## Which way the surface of `b` faces nearest `p`.
static func facing(b: Boulder, p: Vector3) -> Vector3:
	return (b.transform.basis * b.shape.normal(b.transform.affine_inverse() * p)).normalized()
