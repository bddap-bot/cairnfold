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
## Faces meeting at a sharper fold than this, in degrees, keep a hard edge between them: the ridges and crags stay
## crisp while the slopes between them shade smoothly.
const CREASE := 40.0


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


## The plain from the meadow's edge to the first range's foot, then each range's facing slopes, as one indexed
## surface whose normals are smoothed across every fold gentler than CREASE. COLOR.r is the height as a share of the
## farthest range's highest, COLOR.g the haze of the air in front, COLOR.b where snow may lie.
static func arrays() -> Array:
	var corners := PackedVector3Array()
	var colors := PackedColorArray()
	_plain(corners, colors)
	for r: Dictionary in RANGES:
		_range(corners, colors, r)
	return _smooth(corners, colors)


## Each corner's normal is the angle-weighted mean of the faces round its point that fold from its own face by less
## than CREASE; corners that agree on point and normal become one vertex.
static func _smooth(corners: PackedVector3Array, colors: PackedColorArray) -> Array:
	var faces := PackedVector3Array()
	var angles := PackedFloat32Array()
	var at := {}
	for i in corners.size():
		var f := i - i % 3
		if i == f:
			faces.append((corners[f + 2] - corners[f]).cross(corners[f + 1] - corners[f]).normalized())
		var p := corners[i]
		angles.append((corners[f + (i + 1) % 3] - p).angle_to(corners[f + (i + 2) % 3] - p))
		if not at.has(p):
			at[p] = []
		at[p].append(i)
	var crease := cos(deg_to_rad(CREASE))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tints := PackedColorArray()
	var indices := PackedInt32Array()
	var seen := {}
	for i in corners.size():
		var own := faces[i / 3]
		var n := Vector3.ZERO
		for j: int in at[corners[i]]:
			if own.dot(faces[j / 3]) >= crease:
				n += faces[j / 3] * angles[j]
		var key := [corners[i], n]
		if not seen.has(key):
			seen[key] = verts.size()
			verts.append(corners[i])
			normals.append(n.normalized())
			tints.append(colors[i])
		indices.append(seen[key])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = tints
	out[Mesh.ARRAY_INDEX] = indices
	return out


static func _range(corners: PackedVector3Array, colors: PackedColorArray, r: Dictionary) -> void:
	var noise := noise_for(r)
	var crag := noise_for(r)
	crag.seed += 100
	crag.frequency = 2.4
	var cols: int = r.columns
	var grid: Array[PackedVector3Array] = []
	for c in cols:
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
		var next := grid[(c + 1) % cols]
		for k in ROWS.size() - 1:
			_face(corners, colors, r, [grid[c][k], grid[c][k + 1], next[k]])
			_face(corners, colors, r, [next[k], grid[c][k + 1], next[k + 1]])


static func _plain(corners: PackedVector3Array, colors: PackedColorArray) -> void:
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
		_face(corners, colors, r, [a, fa, b])
		_face(corners, colors, r, [b, fa, fb])


static func _face(corners: PackedVector3Array, colors: PackedColorArray, r: Dictionary, tri: Array) -> void:
	var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0])
	if n.dot(SEEN_FROM - tri[0]) < 0.0:
		tri = [tri[0], tri[2], tri[1]]
	var top: float = RANGES[RANGES.size() - 1].high
	for p: Vector3 in tri:
		corners.append(p)
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
