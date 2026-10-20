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
## Without the lake a plain runs from the meadow's edge, just under it, out to the first range's foot at this height.
const PLAIN_HIGH := 6.0
## The meadow's edge is sampled RIM_STEP apart, RIM_SAG under the ground.
const RIM_SAG := 0.5
const RIM_STEP := 5.0
## With the lake, water stands round the meadow at LAKE, under every point of the meadow's edge, from a bank BANK out from
## that edge to past the first range's ridge; the ranges' feet stand SUNK under it, so the water floods their lower slopes
## and meets them along a contour, not at a straight foot. Quality draws it whenever the frame has room for it.
const LAKE := 3.5
const BANK := 10.0
const SUNK := 12.0
const LAKE_OUT := 600.0
## The ridge heights the water mirrors, sampled round the circle (ridge_image).
const RIDGE_SAMPLES := 512
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
## How many times finer than the range's columns each row is cut: the skyline carries the crags, the slope below
## stays coarse.
const DETAIL := [1, 1, 1, 1, 1, 2, 4]
## How tall the skyline's crags stand, as a share of the range's highest, and how much finer they are than its peaks.
const JAG := 0.05
const TEETH := 10.0
## How much of the crags each row carries.
const CRAGGED := [0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 1.0]


## Where the ridge stands above the foot at `azimuth` (radians from +x toward +z), from `noise` sampled on a circle.
static func ridge(r: Dictionary, noise: FastNoiseLite, azimuth: float) -> float:
	return _body(r, noise, azimuth) + _crags(r, noise, azimuth)


## The range's broad shape under its crags.
static func _body(r: Dictionary, noise: FastNoiseLite, azimuth: float) -> float:
	var on: Vector2 = Vector2(cos(azimuth), sin(azimuth)) * r.radius * 0.01
	var peaks := 1.0 - absf(noise.get_noise_2dv(on))
	peaks = pow(clampf(peaks, 0.0, 1.0), 1.6)
	var h: float = lerpf(r.low, r.high, peaks)
	return h * (1.0 - PASS_DEPTH * passes(azimuth))


## The jagged teeth along the skyline, sampled from a far slice of the same noise.
static func _crags(r: Dictionary, noise: FastNoiseLite, azimuth: float) -> float:
	var on: Vector2 = Vector2(cos(azimuth), sin(azimuth)) * r.radius * 0.01 * TEETH
	var tooth := 1.0 - absf(noise.get_noise_3d(on.x, on.y, 50.0))
	return JAG * r.high * pow(tooth, 3.0) * (1.0 - passes(azimuth))


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


## The bank from the meadow's edge down under the `lake`, or the plain out to the first range's foot, then each range's facing slopes, as one indexed
## surface whose normals are smoothed across every fold gentler than CREASE. COLOR.r is the height as a share of the
## farthest range's highest, COLOR.g the haze of the air in front, COLOR.b where snow may lie.
static func arrays(lake: bool) -> Array:
	var corners := PackedVector3Array()
	var colors := PackedColorArray()
	var foot := foot_high(lake)
	_edge(corners, colors, lake, foot)
	for r: Dictionary in RANGES:
		_range(corners, colors, r, foot)
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


static func _range(corners: PackedVector3Array, colors: PackedColorArray, r: Dictionary, foot: float) -> void:
	var noise := noise_for(r)
	var crag := noise_for(r)
	crag.seed += 100
	crag.frequency = 2.4
	var grid: Array[PackedVector3Array] = []
	for k in ROWS.size():
		var n: int = r.columns * DETAIL[k]
		var row := PackedVector3Array()
		for c in n:
			var a := TAU * c / n
			var h: float = _body(r, noise, a) * ROWS[k] + _crags(r, noise, a) * CRAGGED[k]
			var jut: float = crag.get_noise_2d(c * 0.7 / DETAIL[k], k * 1.3) * CRAG * r.depth * (1.0 - absf(ROWS[k] * 2.0 - 1.0))
			var dist: float = r.radius - r.depth * (1.0 - REACH[k]) + jut
			row.append(Vector3(cos(a) * dist, foot + h, sin(a) * dist))
		grid.append(row)
	for k in ROWS.size() - 1:
		_strip(corners, colors, r, grid[k], grid[k + 1], foot)


## Joins two rings of points round the range, each fanning to the other where it is cut finer.
static func _strip(corners: PackedVector3Array, colors: PackedColorArray, r: Dictionary, lo: PackedVector3Array, hi: PackedVector3Array, foot: float) -> void:
	var i := 0
	var j := 0
	while i < lo.size() or j < hi.size():
		if j == hi.size() or (i < lo.size() and (i + 1) * hi.size() <= (j + 1) * lo.size()):
			_face(corners, colors, r, [lo[i], hi[j % hi.size()], lo[(i + 1) % lo.size()]], foot)
			i += 1
		else:
			_face(corners, colors, r, [lo[i % lo.size()], hi[j], hi[(j + 1) % hi.size()]], foot)
			j += 1


## Where every range's foot stands: under the `lake`, or on the plain.
static func foot_high(lake: bool) -> float:
	return LAKE - SUNK if lake else PLAIN_HIGH


static func _edge(corners: PackedVector3Array, colors: PackedColorArray, lake: bool, foot: float) -> void:
	var r: Dictionary = RANGES[0]
	var rim := _rim()
	for k in rim.size():
		var a := rim[k]
		var b := rim[(k + 1) % rim.size()]
		var out_a := Vector3(a.x, 0, a.z).normalized()
		var out_b := Vector3(b.x, 0, b.z).normalized()
		var fa: Vector3 = Vector3(a.x, LAKE - 1.0, a.z) + out_a * BANK if lake else out_a * (r.radius - r.depth) + Vector3.UP * PLAIN_HIGH
		var fb: Vector3 = Vector3(b.x, LAKE - 1.0, b.z) + out_b * BANK if lake else out_b * (r.radius - r.depth) + Vector3.UP * PLAIN_HIGH
		_face(corners, colors, r, [a, fa, b], foot)
		_face(corners, colors, r, [b, fa, fb], foot)


## The meadow's edge, RIM_STEP apart round its square, RIM_SAG under the ground.
static func _rim() -> PackedVector3Array:
	var edge := Terrain.SIZE * 0.5
	var heights := Terrain.base_heights()
	var rim := PackedVector3Array()
	for side in 4:
		for k in int(Terrain.SIZE / RIM_STEP):
			var t := -edge + k * RIM_STEP
			var p: Vector2 = [Vector2(t, -edge), Vector2(edge, t), Vector2(-t, edge), Vector2(-edge, -t)][side]
			var g := Vector2i(clampi(roundi((p.x + edge) / Terrain.STEP), 0, Terrain.CELLS), clampi(roundi((p.y + edge) / Terrain.STEP), 0, Terrain.CELLS))
			rim.append(Vector3(p.x, heights[g.y * Terrain.VERTS + g.x] - RIM_SAG, p.y))
	return rim


## The lake's surface: flat at LAKE from the meadow's edge out to LAKE_OUT.
static func lake_arrays() -> Array:
	var verts := PackedVector3Array()
	var rim := _rim()
	for k in rim.size():
		var a := Vector3(rim[k].x, LAKE, rim[k].z)
		var b := Vector3(rim[(k + 1) % rim.size()].x, LAKE, rim[(k + 1) % rim.size()].z)
		var fa := Vector3(a.x, 0, a.z).normalized() * LAKE_OUT + Vector3.UP * LAKE
		var fb := Vector3(b.x, 0, b.z).normalized() * LAKE_OUT + Vector3.UP * LAKE
		verts.append_array([a, b, fa, b, fb, fa])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	return out


## Each range's ridge over the lake round the circle, so the water mirrors the ranges without drawing them twice:
## R the first's, G the second's, in metres over LAKE as a share of the second's highest.
static func ridge_image() -> Image:
	var img := Image.create(RIDGE_SAMPLES, 1, false, Image.FORMAT_RGF)
	var noises := RANGES.map(noise_for)
	var top: float = RANGES[RANGES.size() - 1].high
	for i in RIDGE_SAMPLES:
		var a := TAU * i / RIDGE_SAMPLES
		var h := [0.0, 0.0]
		for k in RANGES.size():
			h[k] = (foot_high(true) - LAKE + ridge(RANGES[k], noises[k], a)) / top
		img.set_pixel(i, 0, Color(h[0], h[1], 0))
	return img


static func _face(corners: PackedVector3Array, colors: PackedColorArray, r: Dictionary, tri: Array, foot: float) -> void:
	var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0])
	if n.dot(SEEN_FROM - tri[0]) < 0.0:
		tri = [tri[0], tri[2], tri[1]]
	var top: float = RANGES[RANGES.size() - 1].high
	for p: Vector3 in tri:
		corners.append(p)
		colors.append(Color((p.y - foot) / top, r.haze, r.snow))


## The ranges over the lake in `material` with its water in `water`, and the ranges over the plain: the lake's two
## instances, then the plain's.
static func build(material: ShaderMaterial, water: ShaderMaterial) -> Array[MeshInstance3D]:
	water.set_shader_parameter("ridges", ImageTexture.create_from_image(ridge_image()))
	water.set_shader_parameter("level", LAKE)
	water.set_shader_parameter("radii", Vector2(RANGES[0].radius, RANGES[1].radius))
	water.set_shader_parameter("top", RANGES[RANGES.size() - 1].high)
	return [_instance(arrays(true), material), _instance(lake_arrays(), water), _instance(arrays(false), material)]


static func _instance(a: Array, material: ShaderMaterial) -> MeshInstance3D:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi
