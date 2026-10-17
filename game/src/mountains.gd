class_name Mountains
extends RefCounted

## The ranges round the garden: rings of crags far enough out that both eyes and every step through the
## garden see them as distant, lit and hazed in their shader from the hour's light (Look), casting no shadow.
## Each range dips where the sun rises and sets, so it comes up and goes down through a pass.
## The mesh is pure data, so tests read it headless.

## radius: the ridge's distance from the garden's centre. depth: how far in front of the ridge the foot lies.
## low, high: the ridge's lowest and highest. haze: how much the air between hides it.
const RANGES := [
	{"radius": 560.0, "depth": 300.0, "low": 70.0, "high": 200.0, "columns": 224, "seed": 5, "haze": 0.35, "snow": 0.0},
	{"radius": 1300.0, "depth": 800.0, "low": 230.0, "high": 520.0, "columns": 192, "seed": 9, "haze": 0.55, "snow": 0.72},
]
## Rows from foot to ridge, each its share of the height; the last rows stand steep, a stone face over its talus.
const ROWS := [0.0, 0.12, 0.3, 0.5, 0.68, 0.84, 1.0]
const REACH := [0.0, 0.42, 0.66, 0.8, 0.88, 0.95, 1.0]
## The plain runs from the meadow's edge, just under it, out to the first range's foot at this height.
const PLAIN_HIGH := 6.0
const PLAIN_SAG := 0.5
const PLAIN_STEP := 5.0
## The sun's elevation in degrees where a pass is centred on its path, rising and setting.
const PASS_SUN := 4.0
## How far either side of a pass's centre it opens, in radians, and how low it takes the ridge.
const PASS_WIDTH := 0.32
const PASS_DEPTH := 0.7
## Every face is turned toward this point over the garden.
const SEEN_FROM := Vector3(0, 40, 0)
## How far a face's rock juts out of the slope, as a share of the range's depth.
const CRAG := 0.08


## Where the ridge stands above the foot at `azimuth` (radians from +x toward +z), from `noise` sampled on a circle.
static func ridge(r: Dictionary, noise: FastNoiseLite, azimuth: float) -> float:
	var on: Vector2 = Vector2(cos(azimuth), sin(azimuth)) * r.radius * 0.01
	var peaks := 1.0 - absf(noise.get_noise_2dv(on))
	peaks = pow(clampf(peaks, 0.0, 1.0), 1.6)
	var h: float = lerpf(r.low, r.high, peaks)
	return h * (1.0 - PASS_DEPTH * passes(azimuth))


## 1 in the middle of a pass toward the rising or setting sun, 0 away from both.
static func passes(azimuth: float) -> float:
	var out := 0.0
	for toward in [Daylight.toward_sun(sun_at(PASS_SUN, true)), Daylight.toward_sun(sun_at(PASS_SUN, false))]:
		var off: float = absf(angle_difference(azimuth, atan2(toward.z, toward.x)))
		out = maxf(out, smoothstep(PASS_WIDTH, 0.0, off))
	return out


## The time the sun stands `elevation` degrees up, in the morning when `rising`, else in the evening.
static func sun_at(elevation: float, rising: bool) -> float:
	var lo := 0.0 if rising else 1.0
	var hi := 0.5
	for i in 30:
		var mid := (lo + hi) * 0.5
		if Daylight.elevation(mid) < elevation:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


static func noise_for(r: Dictionary) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = r.seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.18
	n.fractal_octaves = 4
	n.fractal_gain = 0.5
	return n


## The plain from the meadow's edge to the first range's foot, then each range's facing slopes, as one
## surface of flat-shaded triangles. COLOR.r is the height as a share of the farthest range's highest, COLOR.g the
## haze of the air in front, COLOR.b where snow may lie.
static func arrays() -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	_plain(verts, normals, colors)
	for r: Dictionary in RANGES:
		_range(verts, normals, colors, r)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	return out


static func _range(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, r: Dictionary) -> void:
	var noise := noise_for(r)
	var crag := noise_for(r)
	crag.seed += 100
	crag.frequency = 2.4
	var cols: int = r.columns
	var grid: Array[PackedVector3Array] = []
	for c in cols + 1:
		var a := TAU * c / cols
		var h := ridge(r, noise, a)
		var out := Vector2(cos(a), sin(a))
		var row := PackedVector3Array()
		for k in ROWS.size():
			var jut: float = crag.get_noise_2d(c % cols * 0.7, k * 1.3) * CRAG * r.depth * (1.0 - absf(ROWS[k] * 2.0 - 1.0))
			var dist: float = r.radius - r.depth * (1.0 - REACH[k]) + jut
			row.append(Vector3(out.x * dist, PLAIN_HIGH + h * ROWS[k], out.y * dist))
		grid.append(row)
	for c in cols:
		for k in ROWS.size() - 1:
			_face(verts, normals, colors, r, [grid[c][k], grid[c][k + 1], grid[c + 1][k]])
			_face(verts, normals, colors, r, [grid[c + 1][k], grid[c][k + 1], grid[c + 1][k + 1]])


static func _plain(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	var r: Dictionary = RANGES[0]
	var foot: float = r.radius - r.depth
	var edge := Terrain.SIZE * 0.5
	var heights := Terrain.base_heights()
	var along := int(Terrain.SIZE / PLAIN_STEP)
	var rim := PackedVector3Array()
	for side in 4:
		for k in along:
			var t := -edge + k * PLAIN_STEP
			var p: Vector2 = [Vector2(t, -edge), Vector2(edge, t), Vector2(-t, edge), Vector2(-edge, -t)][side]
			var g := Vector2i(clampi(roundi((p.x + edge) / Terrain.STEP), 0, Terrain.CELLS), clampi(roundi((p.y + edge) / Terrain.STEP), 0, Terrain.CELLS))
			rim.append(Vector3(p.x, heights[g.y * Terrain.VERTS + g.x] - PLAIN_SAG, p.y))
	for k in rim.size():
		var a := rim[k]
		var b := rim[(k + 1) % rim.size()]
		var fa := Vector3(a.x, 0, a.z).normalized() * foot + Vector3.UP * PLAIN_HIGH
		var fb := Vector3(b.x, 0, b.z).normalized() * foot + Vector3.UP * PLAIN_HIGH
		_face(verts, normals, colors, r, [a, fa, b])
		_face(verts, normals, colors, r, [b, fa, fb])


static func _face(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, r: Dictionary, tri: Array) -> void:
	var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
	if n.dot(SEEN_FROM - tri[0]) < 0.0:
		n = -n
		tri = [tri[0], tri[2], tri[1]]
	var top: float = RANGES[RANGES.size() - 1].high
	for p: Vector3 in tri:
		verts.append(p)
		normals.append(n)
		colors.append(Color((p.y - PLAIN_HIGH) / top, r.haze, r.snow))


static func build(material: ShaderMaterial) -> MeshInstance3D:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays())
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi
