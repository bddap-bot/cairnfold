class_name BoulderLayout
extends RefCounted

## A boulder's shape, drawn from its seed alone so every machine and every load grows the same one. A squat ellipsoid
## cut by a handful of fracture planes, one of them its bed, whose edges are worn round and whose faces are pitted:
## the radial distance along each direction from its centre (`radius`), so one function makes its mesh, its picking and
## what a hand stops at. Pure data: the unit boulder is about a metre across, and the garden scales it.

## How far a boulder's size goes, from a pebble a hand could hold to one a house could hide behind.
const SCALES := Vector2(0.08, 8.0)
## Fracture planes besides the bed.
const CUTS := Vector2i(6, 10)
## How round worn edges are, as a share of the unit boulder.
const WEAR := 0.01
## How deep it sits in the ground, as a share of how far it reaches below its centre, whichever way it is turned.
const BURY := 0.2
## The share of its height a boulder pushed into the ground keeps above it, so a ray still finds it to grip, delete
## or restyle it, and a mostly buried one still reads as a stone and not a mark on the grass.
const KEEP := 0.15
## Icosphere subdivision of the surface points it rests on.
const FEET := 2
## Icosphere subdivisions of the near and far meshes.
const NEAR := 3
const FAR := 1


## Half-axes of the ellipsoid; fracture planes as (normal, distance from the centre); and the noise that pits it.
class Shape:
	var seed := 0
	var axes := Vector3.ONE
	var cuts: Array[Vector4] = []
	var pits := FastNoiseLite.new()
	var grain := FastNoiseLite.new()
	## How far below its centre its bed lies.
	var bed := 0.0
	## Points on its surface, any of which may be what it rests on.
	var feet := PackedVector3Array()

	## Distance from the centre to the surface along the unit direction `u`.
	func radius(u: Vector3) -> float:
		var e := 1.0 / sqrt(u.x * u.x / (axes.x * axes.x) + u.y * u.y / (axes.y * axes.y) + u.z * u.z / (axes.z * axes.z))
		# A soft minimum of the ellipsoid and every plane's reach, so where two faces meet the edge is worn round.
		var sum := exp(-e / WEAR)
		for c in cuts:
			var along := u.x * c.x + u.y * c.y + u.z * c.z
			if along > 1e-3:
				sum += exp(-c.w / along / WEAR)
		var worn := -WEAR * log(sum)
		return worn * (1.0 + pits.get_noise_3dv(u) * 0.035 + grain.get_noise_3dv(u) * 0.008)

	## Whether the local point `p` lies inside.
	func inside(p: Vector3) -> bool:
		var l := p.length()
		return l < 1e-6 or l < radius(p / l)

	## The largest distance from the centre to the surface: no part reaches past it.
	func reach() -> float:
		return maxf(axes.x, maxf(axes.y, axes.z)) * 1.06

	## How far along the local ray from `origin` along unit `dir` it first meets the surface, or INF.
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

	## The outward surface normal near the local surface point `p`, from the radial function's slope.
	func normal(p: Vector3) -> Vector3:
		var e := 0.01
		var f := func(q: Vector3) -> float: return q.length() - radius(q.normalized())
		return Vector3(f.call(p + Vector3(e, 0, 0)) - f.call(p - Vector3(e, 0, 0)), f.call(p + Vector3(0, e, 0)) - f.call(p - Vector3(0, e, 0)), f.call(p + Vector3(0, 0, e)) - f.call(p - Vector3(0, 0, e))).normalized()


static func shape(seed: int) -> Shape:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var s := Shape.new()
	s.seed = seed
	s.axes = Vector3(rng.randf_range(0.42, 0.62), rng.randf_range(0.24, 0.46), rng.randf_range(0.3, 0.5))
	for i in rng.randi_range(CUTS.x, CUTS.y):
		var n := Vector3(rng.randfn(), rng.randfn() * 0.6 + 0.25, rng.randfn()).normalized()
		var along := 1.0 / sqrt(n.x * n.x / (s.axes.x * s.axes.x) + n.y * n.y / (s.axes.y * s.axes.y) + n.z * n.z / (s.axes.z * s.axes.z))
		s.cuts.append(Vector4(n.x, n.y, n.z, along * rng.randf_range(0.5, 0.82)))
	var down := Vector3(rng.randf_range(-0.12, 0.12), -1.0, rng.randf_range(-0.12, 0.12)).normalized()
	s.bed = s.axes.y * rng.randf_range(0.55, 0.75)
	s.cuts.append(Vector4(down.x, down.y, down.z, s.bed))
	s.pits.seed = rng.randi()
	s.pits.frequency = rng.randf_range(1.6, 2.4)
	s.pits.fractal_octaves = 2
	s.grain.seed = rng.randi()
	s.grain.frequency = 7.0
	for u: Vector3 in Meshes.icosphere(FEET)[Mesh.ARRAY_VERTEX]:
		s.feet.append(u * s.radius(u))
	return s


## The mesh arrays of `s` at icosphere subdivision `subdiv`: its surface, with normals averaged across faces, so its
## worn edges shade round and its fracture faces flat, and a shade in its colour: darker toward its underside and in
## its pits, where less sky reaches.
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


## A boulder's transform: turned `turn` and grown `scale` times, dropped straight down at (`x`, `z`) onto the ground
## `height` (x, z) gives until some point of it meets the ground, then sunk BURY of how far it reaches below its centre,
## and `sink` unit metres further, as deep as keeps KEEP of its height above the ground: whichever way it is turned and
## however high it was let go, it rests on the ground or in it, never over it.
static func rest(s: Shape, turn: Quaternion, scale: float, x: float, z: float, height: Callable, sink := 0.0) -> Transform3D:
	var basis := Basis(turn) * Basis.from_scale(Vector3.ONE * scale)
	var drop := _drop(s, basis, x, z, height)
	return Transform3D(basis, Vector3(x, drop.x - clampf(sink * scale, 0.0, drop.y), z))


## How far below where it would rest a boulder turned `turn`, grown `scale` times and held with its centre at `at` sits,
## in unit metres, as `rest` takes it: none held over the ground, at most as deep as keeps KEEP of it showing.
static func sink(s: Shape, turn: Quaternion, scale: float, at: Vector3, height: Callable) -> float:
	var drop := _drop(s, Basis(turn) * Basis.from_scale(Vector3.ONE * scale), at.x, at.z, height)
	return clampf(drop.x - at.y, 0.0, drop.y) / scale


## Where the centre of a boulder of `basis` rests at (`x`, `z`), and how much deeper it may sink.
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
