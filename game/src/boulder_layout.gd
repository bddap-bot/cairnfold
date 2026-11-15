class_name BoulderLayout
extends RefCounted

## Grown from seed and style alone, alike on every machine; `radius` drives its mesh, picking and what a hand stops at.
## The unit boulder is about a metre across; the garden scales it.

const LEAST := 0.08
## No tool or command makes one bigger.
const MOST := 10000.0
## A share of how far it reaches below its centre, whichever way it is turned.
const BURY := 0.2
## The share of its height a sunk boulder keeps above ground, so a ray still finds it and it reads as a stone.
const KEEP := 0.15
## Icosphere subdivisions: FEET of the points it rests on, NEAR and FAR of the meshes.
const FEET := 2
const NEAR := 3
const FAR := 1
const GRAIN := 0.23
const PIT_ROOM := 0.06


## `cuts` are fracture planes as (normal, distance from the centre), the last its bed.
class Shape:
	var seed := 0
	var style := 0
	## A share of the unit boulder.
	var wear: float
	## A share of its radius.
	var pitting: float
	var axes := Vector3.ONE
	var cuts: Array[Vector4] = []
	var pits := FastNoiseLite.new()
	var grain := FastNoiseLite.new()
	var feet := PackedVector3Array()

	## `u` is a unit direction.
	func radius(u: Vector3) -> float:
		var e := 1.0 / sqrt(u.x * u.x / (axes.x * axes.x) + u.y * u.y / (axes.y * axes.y) + u.z * u.z / (axes.z * axes.z))
		# A soft minimum of the ellipsoid and every plane's reach, so where two faces meet the edge is worn round.
		var sum := exp(-e / wear)
		for c in cuts:
			var along := u.x * c.x + u.y * c.y + u.z * c.z
			if along > 1e-3:
				sum += exp(-c.w / along / wear)
		var worn := -wear * log(sum)
		return worn * (1.0 + pits.get_noise_3dv(u) * pitting + grain.get_noise_3dv(u) * pitting * GRAIN)

	## `p` is in the shape's local frame.
	func inside(p: Vector3) -> bool:
		var l := p.length()
		return l < 1e-6 or l < radius(p / l)

	func reach() -> float:
		return maxf(axes.x, maxf(axes.y, axes.z)) * (1.0 + PIT_ROOM)

	## Along the local ray, unit `dir`; INF for a miss.
	func hit(origin: Vector3, dir: Vector3, reach_limit := INF) -> float:
		var r := reach()
		var b := origin.dot(dir)
		var c := origin.length_squared() - r * r
		var disc := b * b - c
		if disc < 0.0:
			return INF
		var t0 := maxf(-b - sqrt(disc), 0.0)
		var t1 := minf(-b + sqrt(disc), reach_limit)
		var step := r * 0.03
		var t := t0
		while t <= t1:
			if inside(origin + dir * t):
				var lo := maxf(t - step, t0)
				var hi := t
				for i in 8:
					var mid := (lo + hi) * 0.5
					if inside(origin + dir * mid):
						hi = mid
					else:
						lo = mid
				return hi
			t += step
		return INF

	func normal(p: Vector3) -> Vector3:
		var e := 0.01
		var f := func(q: Vector3) -> float: return q.length() - radius(q.normalized())
		return Vector3(f.call(p + Vector3(e, 0, 0)) - f.call(p - Vector3(e, 0, 0)), f.call(p + Vector3(0, e, 0)) - f.call(p - Vector3(0, e, 0)), f.call(p + Vector3(0, 0, e)) - f.call(p - Vector3(0, 0, e))).normalized()


static func shape(seed: int, style: int) -> Shape:
	var look: Dictionary = StoneStyles.STYLES[style].boulder
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var s := Shape.new()
	s.seed = seed
	s.style = style
	s.wear = look.wear
	s.pitting = look.pitting
	assert(s.pitting * (1.0 + GRAIN) <= PIT_ROOM, "%s pits deeper than a boulder's reach allows" % StoneStyles.STYLES[style].name)
	s.axes = Vector3(rng.randf_range(0.42, 0.62), rng.randf_range(0.24, 0.46), rng.randf_range(0.3, 0.5)) * look.axes
	for i in rng.randi_range(look.cuts.x, look.cuts.y):
		var n := Vector3(rng.randfn(), rng.randfn() * 0.6 + 0.25, rng.randfn()).normalized()
		var along := 1.0 / sqrt(n.x * n.x / (s.axes.x * s.axes.x) + n.y * n.y / (s.axes.y * s.axes.y) + n.z * n.z / (s.axes.z * s.axes.z))
		s.cuts.append(Vector4(n.x, n.y, n.z, along * rng.randf_range(0.5, 0.82)))
	var down := Vector3(rng.randf_range(-0.12, 0.12), -1.0, rng.randf_range(-0.12, 0.12)).normalized()
	s.cuts.append(Vector4(down.x, down.y, down.z, s.axes.y * rng.randf_range(0.55, 0.75)))
	s.pits.seed = rng.randi()
	s.pits.frequency = rng.randf_range(1.6, 2.4)
	s.pits.fractal_octaves = 2
	s.grain.seed = rng.randi()
	s.grain.frequency = 7.0
	for u: Vector3 in Meshes.icosphere(FEET)[Mesh.ARRAY_VERTEX]:
		s.feet.append(u * s.radius(u))
	return s


static func arrays(s: Shape, subdiv: int) -> Array:
	var a := Meshes.icosphere(subdiv)
	var sphere: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var verts := PackedVector3Array()
	verts.resize(sphere.size())
	for i in sphere.size():
		verts[i] = sphere[i] * s.radius(sphere[i])
	var faces: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for f in range(0, faces.size(), 3):
		var p0 := verts[faces[f]]
		var n := (verts[faces[f + 2]] - p0).cross(verts[faces[f + 1]] - p0)
		for k in 3:
			normals[faces[f + k]] += n
	var shades := PackedColorArray()
	shades.resize(verts.size())
	for i in normals.size():
		normals[i] = normals[i].normalized()
		var k := clampf((0.68 + normals[i].y * 0.22) * (1.0 + s.pits.get_noise_3dv(sphere[i]) * 0.5), 0.35, 1.0)
		shades[i] = Color(k, k, k)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = normals
	a[Mesh.ARRAY_COLOR] = shades
	return a


## Sunk BURY once a point meets the ground, then `sink` unit-boulder metres more, keeping KEEP of its height above.
static func rest(s: Shape, turn: Quaternion, scale: float, x: float, z: float, height: Callable, sink := 0.0) -> Transform3D:
	var basis := Basis(turn) * Basis.from_scale(Vector3.ONE * scale)
	var drop := _drop(s, basis, x, z, height)
	return Transform3D(basis, Vector3(x, drop.x - clampf(sink * scale, 0.0, drop.y), z))


## In unit-boulder metres, as `rest` takes it; 0 held over the ground.
static func sink(s: Shape, turn: Quaternion, scale: float, at: Vector3, height: Callable) -> float:
	var drop := _drop(s, Basis(turn) * Basis.from_scale(Vector3.ONE * scale), at.x, at.z, height)
	return clampf(drop.x - at.y, 0.0, drop.y) / scale


## x: the centre's resting height at (`x`, `z`); y: how much deeper it may sink.
static func _drop(s: Shape, basis: Basis, x: float, z: float, height: Callable) -> Vector2:
	var lift := -INF
	var low := INF
	var high := -INF
	var clear := -INF
	for p in s.feet:
		var w := basis * p
		var under: float = height.call(x + w.x, z + w.z)
		lift = maxf(lift, under - w.y)
		clear = maxf(clear, w.y - under)
		low = minf(low, w.y)
		high = maxf(high, w.y)
	var y := lift + low * BURY
	return Vector2(y, maxf(y + clear - KEEP * (high - low), 0.0))
