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
## The first range's foot stands this high; the foothills run to it from just under the meadow's edge.
const FOOT_HIGH := 6.0
const RIM_SAG := 0.5
const RIM_STEP := 5.0
## The foothills' rows from the meadow's edge to the foot, and how high they roll between.
const HILL_ROWS := [0.0, 0.02, 0.05, 0.09, 0.14, 0.22, 0.32, 0.45, 0.6, 0.75, 0.88, 1.0]
const HILL := 26.0
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


## Each range's facing slopes, as one indexed surface whose normals are smoothed across every fold gentler than
## CREASE. COLOR.r is the height as a share of the farthest range's highest, COLOR.g the haze of the air in front,
## COLOR.b where snow may lie.
static func arrays() -> Array:
	var corners := PackedVector3Array()
	var colors := PackedColorArray()
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
			row.append(Vector3(out.x * dist, FOOT_HIGH + h * ROWS[k], out.y * dist))
		grid.append(row)
	for c in cols:
		var next := grid[(c + 1) % cols]
		for k in ROWS.size() - 1:
			_face(corners, colors, r, [grid[c][k], grid[c][k + 1], next[k]])
			_face(corners, colors, r, [next[k], grid[c][k + 1], next[k + 1]])


static func _face(corners: PackedVector3Array, colors: PackedColorArray, r: Dictionary, tri: Array) -> void:
	var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0])
	if n.dot(SEEN_FROM - tri[0]) < 0.0:
		tri = [tri[0], tri[2], tri[1]]
	var top: float = RANGES[RANGES.size() - 1].high
	for p: Vector3 in tri:
		corners.append(p)
		colors.append(Color((p.y - FOOT_HIGH) / top, r.haze, r.snow))


static func _rim() -> PackedVector3Array:
	var half := Terrain.SIZE * 0.5
	var heights := Terrain.base_heights()
	var rim := PackedVector3Array()
	for side in 4:
		for k in int(Terrain.SIZE / RIM_STEP):
			var t := -half + k * RIM_STEP
			var p: Vector2 = [Vector2(t, -half), Vector2(half, t), Vector2(-t, half), Vector2(-half, -t)][side]
			var g := Vector2i(clampi(roundi((p.x + half) / Terrain.STEP), 0, Terrain.CELLS), clampi(roundi((p.y + half) / Terrain.STEP), 0, Terrain.CELLS))
			rim.append(Vector3(p.x, heights[g.y * Terrain.VERTS + g.x] - RIM_SAG, p.y))
	return rim


static func _hill_noise(seed: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_octaves = 2
	return n


## The foothills from the meadow's edge to the first range's foot, flat-shaded. COLOR.r is how dry, COLOR.g how wooded.
static func hill_arrays() -> Array:
	var foot: float = RANGES[0].radius - RANGES[0].depth
	var rolling := _hill_noise(21, 0.011)
	var dry := _hill_noise(22, 0.02)
	var wood := _hill_noise(23, 0.016)
	var rim := _rim()
	var grid: Array[PackedVector3Array] = []
	var tones: Array[PackedColorArray] = []
	for k in rim.size() + 1:
		var a := rim[k % rim.size()]
		var out := Vector3(a.x, 0, a.z).normalized() * foot
		var row := PackedVector3Array()
		var tone := PackedColorArray()
		for t: float in HILL_ROWS:
			var p := Vector3(lerpf(a.x, out.x, t), 0, lerpf(a.z, out.z, t))
			p.y = lerpf(a.y, FOOT_HIGH, t) + HILL * pow(sin(PI * t), 0.8) * (1.0 + 0.6 * rolling.get_noise_2d(p.x, p.z))
			row.append(p)
			tone.append(Color(dry.get_noise_2d(p.x, p.z) * 0.5 + 0.5, smoothstep(0.1, 0.4, wood.get_noise_2d(p.x, p.z)) * smoothstep(0.03, 0.12, t), 0))
		grid.append(row)
		tones.append(tone)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for c in rim.size():
		for k in HILL_ROWS.size() - 1:
			_tile(verts, normals, colors, [grid[c][k], grid[c][k + 1], grid[c + 1][k]], [tones[c][k], tones[c][k + 1], tones[c + 1][k]])
			_tile(verts, normals, colors, [grid[c + 1][k], grid[c][k + 1], grid[c + 1][k + 1]], [tones[c + 1][k], tones[c][k + 1], tones[c + 1][k + 1]])
	return _surface(verts, normals, colors)


static func _tile(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, tri: Array, tone: Array) -> void:
	var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
	if n.y < 0.0:
		n = -n
		tri = [tri[0], tri[2], tri[1]]
		tone = [tone[0], tone[2], tone[1]]
	for i in 3:
		verts.append(tri[i])
		normals.append(n)
		colors.append(tone[i])


static func _surface(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	return out


## The ranges in `ranges`, unfogged since their shader hazes them itself; the foothills in `hills`, under the
## garden's own fog so they meet the meadow in the same air.
static func build(ranges: Material, hills: Material) -> MeshInstance3D:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays())
	m.surface_set_material(0, ranges)
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, hill_arrays())
	m.surface_set_material(1, hills)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi
