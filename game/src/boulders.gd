class_name Boulders
extends Node3D

## Distances grow with size, so a pebble costs little and a house-sized boulder keeps its outline far off.

## Metres for a unit boulder; both grow with its scale.
const NEAR_TO := 30.0
const FAR_TO := 220.0
const AO := 0.92
## Surface speed in metres a second, and the least scale that whooshes: a pebble swung about is silent.
const SWING_FROM := 0.6
const SWING_FULL := 5.0
const WHOOSH_SIZE := 0.4
## Landing speed of the loudest thud, in metres a second (a 2.5 m drop).
const LAND_FULL := 7.0

class Boulder:
	extends Node3D
	var id := 0
	var shape: BoulderLayout.Shape
	var terrain: Terrain
	var ground := Vector3.ZERO
	var turn := Quaternion.IDENTITY
	## Depth below where it would rest, in unit metres (BoulderLayout.rest).
	var sink := 0.0
	var size := 1.0
	var held := false
	var near: MultiMeshInstance3D
	var far: MultiMeshInstance3D

	func appear(d: Dictionary) -> void:
		if shape == null or shape.seed != d.seed or shape.style != d.style:
			_grow(BoulderLayout.shape(d.seed, d.style))
		ground = d.at
		turn = d.turn
		sink = d.sink
		held = false
		var c := Palette.tint(Palette.Element.STONE, d.paint[Palette.Element.STONE])
		for mesh: MultiMeshInstance3D in [near, far]:
			mesh.multimesh.set_instance_color(0, c)
			mesh.set_instance_shader_parameter("stone_style", d.style)
		seat(d.scale, terrain.height_at)

	func _grow(s: BoulderLayout.Shape) -> void:
		for mesh in [near, far]:
			if mesh != null:
				remove_child(mesh)
				mesh.queue_free()
		shape = s
		near = Boulders._instance(s, BoulderLayout.NEAR)
		far = Boulders._instance(s, BoulderLayout.FAR)
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(near)
		add_child(far)

	func seat(scale: float, height: Callable) -> void:
		ground.y = height.call(ground.x, ground.z)
		_show(BoulderLayout.rest(shape, turn, scale, ground.x, ground.z, height, sink), scale)

	## `pose` is unscaled.
	func hold(pose: Transform3D, scale: float) -> void:
		var was := pose()
		var moving := held
		held = true
		_show(Transform3D(pose.basis.orthonormalized() * Basis.from_scale(Vector3.ONE * scale), pose.origin), scale)
		if moving and scale >= WHOOSH_SIZE:
			var swing := Boulders.swing(was, pose, shape.reach() * scale, get_process_delta_time())
			if swing > 0.0:
				Cues.play(Cues.Act.BOULDER_MOVE, pose.origin, null, swing, scale)

	func landed(from_y: float, hand: XRController3D = null) -> void:
		Cues.play(Cues.Act.BOULDER_PLACE, position, hand, Boulders.impact(from_y - position.y), size)

	func pose() -> Transform3D:
		return Transform3D(transform.basis.orthonormalized(), transform.origin)

	func _show(at: Transform3D, scale: float) -> void:
		size = scale
		transform = at
		near.visibility_range_end = NEAR_TO * size
		far.visibility_range_begin = NEAR_TO * size
		far.visibility_range_end = FAR_TO * size


var terrain: Terrain
var world: World
var boulders := {}
## So what caches their shapes knows to look again.
var changes := 0


func _init() -> void:
	name = "Boulders"


## `data` keys: at, turn, sink, seed, scale, paint, style.
func put(id: int, data: Dictionary) -> Boulder:
	var b: Boulder = boulders.get(id)
	if b == null:
		b = ghost(data)
		b.id = id
		b.name = "Boulder%d" % id
		boulders[id] = b
	else:
		b.appear(data)
	changes += 1
	return b


## No part of the garden: nothing picks it or stops at it. Its holder frees it.
func ghost(data: Dictionary) -> Boulder:
	var b := Boulder.new()
	b.terrain = terrain
	add_child(b)
	b.appear(data)
	return b


func show_held(id: int, pose: Transform3D, scale: float) -> void:
	var b: Boulder = boulders.get(id)
	if b != null:
		b.hold(pose, scale)
		changes += 1


static func carried(pose: Transform3D, from: Transform3D, to: Transform3D, gain: float) -> Transform3D:
	var turned := to.basis.orthonormalized() * from.basis.orthonormalized().inverse() * pose.basis
	return Transform3D(turned.orthonormalized(), pose.origin + (to.origin - from.origin) * gain)


static func swing(from: Transform3D, to: Transform3D, reach: float, seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	var turned := (to.basis.orthonormalized() * from.basis.orthonormalized().inverse()).get_rotation_quaternion().get_angle()
	var speed := (from.origin.distance_to(to.origin) + turned * reach) / seconds
	return clampf((speed - SWING_FROM) / (SWING_FULL - SWING_FROM), 0.0, 1.0)


static func impact(fall: float) -> float:
	return clampf(sqrt(2.0 * 9.8 * maxf(fall, 0.0)) / LAND_FULL, 0.0, 1.0)


## On this player's view only.
func show_reshaped(id: int, data := {}) -> void:
	var b: Boulder = boulders.get(id)
	if b != null:
		b.appear(World.reshaped(world.state.boulders[id], data))
		changes += 1


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


func find(id: int) -> Boulder:
	return boulders.get(id)


func reseat(area: Rect2) -> void:
	for b: Boulder in boulders.values():
		if not b.held and area.grow(b.shape.reach() * b.size).has_point(Vector2(b.ground.x, b.ground.z)):
			b.seat(b.size, terrain.shown_at)
			changes += 1


## The nearest hit: {boulder, along, point}, or {}.
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
		if t < INF and point.y >= terrain.shown_at(point.x, point.z):
			best = {"boulder": b, "along": t / unit, "point": point}
	return best


func floor_under(p: Vector3) -> float:
	var rock := pick(p, Vector3.DOWN)
	return rock.point.y if not rock.is_empty() else -INF


func inside(p: Vector3) -> Boulder:
	for b: Boulder in boulders.values():
		var local := b.transform.affine_inverse() * p
		if local.length() < b.shape.reach() and b.shape.inside(local):
			return b
	return null


static func facing(b: Boulder, p: Vector3) -> Vector3:
	return (b.transform.basis * b.shape.normal(b.transform.affine_inverse() * p)).normalized()
