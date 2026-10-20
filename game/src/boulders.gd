class_name Boulders
extends Node3D

## The garden's boulders, each grown from its seed (BoulderLayout) in wall stone of its paint, standing on the ground
## under it and grown to its scale. `World` puts and takes them, and reshapes their size and paint; tools pick them by
## `pick`, a hand stops at them by `inside`.
## Each draws a near mesh and, past a distance that grows with it, a far one of a sixteenth the triangles, so a pebble
## costs little and a house-sized one keeps its outline far off.

## Where a unit boulder swaps to its far mesh, and where its far mesh stops drawing, in metres; both grow with its scale.
const NEAR_TO := 30.0
const FAR_TO := 220.0
## Occlusion a boulder is shaded with, as a laid stone carries.
const AO := 0.92

## One standing boulder.
class Boulder:
	extends Node3D
	var id := 0
	var shape: BoulderLayout.Shape
	var ground := Vector3.ZERO
	var size := 1.0
	var data: Dictionary
	var near: MultiMeshInstance3D
	var far: MultiMeshInstance3D

	## Shows it as `d` ({at, seed, scale, paint}) has it, its seed its own.
	func appear(d: Dictionary) -> void:
		ground = d.at
		var c := Palette.swatch(Palette.Element.STONE, d.paint[Palette.Element.STONE])
		near.multimesh.set_instance_color(0, c)
		far.multimesh.set_instance_color(0, c)
		seat(d.scale)

	## Stands it at `size` on the ground under it as the ground is now.
	func seat(scale: float) -> void:
		size = scale
		ground.y = Terrain.height_at(ground.x, ground.z)
		transform = BoulderLayout.xform(shape, ground, size)
		near.visibility_range_end = NEAR_TO * size
		far.visibility_range_begin = NEAR_TO * size
		far.visibility_range_end = FAR_TO * size

	## How high over the ground it reaches.
	func top() -> float:
		return shape.top() * size


var boulders := {}
## Counts every put, take and resize, so what caches their shapes knows to look again.
var changes := 0


func _init() -> void:
	name = "Boulders"


## Puts boulder `id` as `data` ({at, seed, scale, paint}) has it; one standing with that seed keeps its meshes.
func put(id: int, data: Dictionary) -> Boulder:
	var b: Boulder = boulders.get(id)
	if b == null or b.shape.seed != data.seed:
		take(id)
		b = Boulder.new()
		b.id = id
		b.name = "Boulder%d" % id
		b.shape = BoulderLayout.shape(data.seed)
		b.near = _instance(b.shape, BoulderLayout.NEAR)
		b.far = _instance(b.shape, BoulderLayout.FAR)
		b.far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(b.near)
		b.add_child(b.far)
		add_child(b)
		boulders[id] = b
	b.data = data
	b.appear(data)
	changes += 1
	return b


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
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	mm.set_instance_custom_data(0, Stones.custom({"ao": AO, "kind": "rubble"}))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = Stones.shared_material()
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


## Stands the boulders over `area` again on the ground as it now lies there.
func reseat(area: Rect2, _settled := true) -> void:
	for b: Boulder in boulders.values():
		if area.has_point(Vector2(b.ground.x, b.ground.z)):
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
		if t < INF:
			best = {"boulder": b, "along": t / unit, "point": origin + d * t / unit}
	return best


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
