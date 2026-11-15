class_name Mountains
extends RefCounted

## Each range dips where the sun rises and sets, so it comes up and goes down through a pass.

## radius: the ridge's distance from the centre, far enough that both eyes and every step see it as distant; depth: how
## far in front of the ridge the foot lies; low, high: the ridge's span; haze: how much the air hides it.
const RANGES := [
	{"radius": 560.0, "depth": 300.0, "low": 70.0, "high": 200.0, "columns": 224, "seed": 5, "haze": 0.35, "snow": 0.0},
	{"radius": 1300.0, "depth": 800.0, "low": 230.0, "high": 520.0, "columns": 192, "seed": 9, "haze": 0.55, "snow": 0.72},
]
## The farthest range's highest, the scale its shader and the lake's read heights on.
const TOP: float = RANGES[-1].high
## Rows from foot to ridge, each its share of the height; the last rows stand steep, a stone face over its talus.
const ROWS := [0.0, 0.12, 0.3, 0.5, 0.68, 0.84, 1.0]
const REACH := [0.0, 0.42, 0.66, 0.8, 0.88, 0.95, 1.0]
## Under the meadow's edge, over the bank's foot, out past the first ridge; the ranges' feet stand SUNK under it, so
## it meets them on a contour.
const LAKE := 3.5
const SUNK := 12.0
const FOOT := LAKE - SUNK
## Metres between the lake's shore vertices.
const SHORE_STEP := 5.0
const LAKE_OUT := 600.0
const RIDGE_SAMPLES := 512
## The sun's elevation in degrees where a pass is centred on its path, rising and setting.
const PASS_SUN := 4.0
## How far either side of a pass's centre it opens, in radians, and how low it takes the ridge.
const PASS_WIDTH := 0.32
const PASS_DEPTH := 0.7
## Every face is turned toward it.
const SEEN_FROM := Vector3(0, 40, 0)
## How far a face's rock juts out of the slope, as a share of the range's depth.
const CRAG := 0.08
## Degrees: a sharper fold keeps a hard edge, so ridges and crags stay crisp while slopes shade smoothly.
const CREASE := 40.0
## How many times finer than the range's columns each row is cut.
const DETAIL := [1, 1, 1, 1, 1, 2, 4]
## How tall the skyline's crags stand, as a share of the range's highest, and how much finer they are than its peaks.
const JAG := 0.05
const TEETH := 10.0
## Per row, its share of the crags.
const CRAGGED := [0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 1.0]


## Above the foot, at `azimuth` radians from +x toward +z.
static func ridge(r: Dictionary, noise: FastNoiseLite, azimuth: float) -> float:
	return _body(r, noise, azimuth) + _crags(r, noise, azimuth)


static func _body(r: Dictionary, noise: FastNoiseLite, azimuth: float) -> float:
	var on: Vector2 = Vector2(cos(azimuth), sin(azimuth)) * r.radius * 0.01
	var peaks := 1.0 - absf(noise.get_noise_2dv(on))
	peaks = pow(clampf(peaks, 0.0, 1.0), 1.6)
	var h: float = lerpf(r.low, r.high, peaks)
	return h * (1.0 - PASS_DEPTH * passes(azimuth))


static func _crags(r: Dictionary, noise: FastNoiseLite, azimuth: float) -> float:
	var on: Vector2 = Vector2(cos(azimuth), sin(azimuth)) * r.radius * 0.01 * TEETH
	var tooth := 1.0 - absf(noise.get_noise_3d(on.x, on.y, 50.0))
	return JAG * r.high * pow(tooth, 3.0) * (1.0 - passes(azimuth))


static func hides(from: Vector3, dir: Vector3) -> bool:
	var flat := Vector2(dir.x, dir.z)
	if flat.length() < 1e-6:
		return false
	var rise := dir.y / flat.length()
	var start := Vector2(from.x, from.z)
	var way := flat.normalized()
	for r: Dictionary in RANGES:
		var along := _crossing(start, way, r.radius)
		if is_nan(along):
			continue
		var at := start + way * along
		if from.y + rise * along < FOOT + ridge(r, noise_for(r), at.angle()):
			return true
	return false


## The far crossing along the unit `way`, or NAN on a miss.
static func _crossing(p: Vector2, way: Vector2, radius: float) -> float:
	var b := p.dot(way)
	var d := b * b - p.length_squared() + radius * radius
	return -b + sqrt(d) if d >= 0.0 else NAN


## 1 in the middle of a pass toward the rising or setting sun, 0 away from both.
static func passes(azimuth: float) -> float:
	var out := 0.0
	for toward in [Daylight.toward_sun(Daylight.sun_at(PASS_SUN, true)), Daylight.toward_sun(Daylight.sun_at(PASS_SUN, false))]:
		var off: float = absf(angle_difference(azimuth, atan2(toward.z, toward.x)))
		out = maxf(out, smoothstep(PASS_WIDTH, 0.0, off))
	return out


static func noise_for(r: Dictionary) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = r.seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.18
	n.fractal_octaves = 4
	n.fractal_gain = 0.5
	return n


## Lake bed, then the ranges: COLOR.r the height in shares of TOP, .g the haze in front, .b where snow may lie.
static func arrays() -> Array:
	var corners := PackedVector3Array()
	var colors := PackedColorArray()
	_edge(corners, colors)
	for r: Dictionary in RANGES:
		_range(corners, colors, r)
	return _smooth(corners, colors)


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
		at.get_or_add(p, []).append(i)
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
	var grid: Array[PackedVector3Array] = []
	for k in ROWS.size():
		var n: int = r.columns * DETAIL[k]
		var row := PackedVector3Array()
		for c in n:
			var a := TAU * c / n
			var h: float = _body(r, noise, a) * ROWS[k] + _crags(r, noise, a) * CRAGGED[k]
			var jut: float = crag.get_noise_2d(c * 0.7 / DETAIL[k], k * 1.3) * CRAG * r.depth * (1.0 - absf(ROWS[k] * 2.0 - 1.0))
			var dist: float = r.radius - r.depth * (1.0 - REACH[k]) + jut
			row.append(Vector3(cos(a) * dist, FOOT + h, sin(a) * dist))
		grid.append(row)
	for k in ROWS.size() - 1:
		_strip(corners, colors, r, grid[k], grid[k + 1])


static func _strip(corners: PackedVector3Array, colors: PackedColorArray, r: Dictionary, lo: PackedVector3Array, hi: PackedVector3Array) -> void:
	var i := 0
	var j := 0
	while i < lo.size() or j < hi.size():
		if j == hi.size() or (i < lo.size() and (i + 1) * hi.size() <= (j + 1) * lo.size()):
			_face(corners, colors, r, [lo[i], hi[j % hi.size()], lo[(i + 1) % lo.size()]])
			i += 1
		else:
			_face(corners, colors, r, [lo[i % lo.size()], hi[j], hi[(j + 1) % hi.size()]])
			j += 1


## Point for point from the bank's foot, so Terrain.bank_mesh meets it with no crack.
static func _edge(corners: PackedVector3Array, colors: PackedColorArray) -> void:
	var r: Dictionary = RANGES[0]
	var bank := Terrain.edge(Terrain.BANK)
	for k in bank.size():
		var a := Vector3(bank[k].x, Terrain.BANK_FOOT, bank[k].y)
		var b := Vector3(bank[(k + 1) % bank.size()].x, Terrain.BANK_FOOT, bank[(k + 1) % bank.size()].y)
		var fa := _outward(a, r.radius - r.depth, FOOT)
		var fb := _outward(b, r.radius - r.depth, FOOT)
		_face(corners, colors, r, [a, fa, b])
		_face(corners, colors, r, [b, fa, fb])


static func _outward(p: Vector3, distance: float, y: float) -> Vector3:
	return Vector3(p.x, 0, p.z).normalized() * distance + Vector3.UP * y


static func lake_arrays() -> Array:
	var verts := PackedVector3Array()
	var shore := Terrain.edge(0.0)
	var every := int(SHORE_STEP / Terrain.STEP)
	for k in range(0, shore.size(), every):
		var a := Vector3(shore[k].x, LAKE, shore[k].y)
		var b := Vector3(shore[(k + every) % shore.size()].x, LAKE, shore[(k + every) % shore.size()].y)
		var fa := _outward(a, LAKE_OUT, LAKE)
		var fb := _outward(b, LAKE_OUT, LAKE)
		verts.append_array([a, b, fa, b, fb, fa])
	return Meshes.level(verts)


## R, G: each range's ridge over LAKE in shares of TOP, so the water mirrors the ranges without drawing them twice.
static func ridge_image() -> Image:
	var img := Image.create(RIDGE_SAMPLES, 1, false, Image.FORMAT_RGF)
	var noises := RANGES.map(noise_for)
	for i in RIDGE_SAMPLES:
		var a := TAU * i / RIDGE_SAMPLES
		var h := [0.0, 0.0]
		for k in RANGES.size():
			h[k] = (FOOT - LAKE + ridge(RANGES[k], noises[k], a)) / TOP
		img.set_pixel(i, 0, Color(h[0], h[1], 0))
	return img


static func _face(corners: PackedVector3Array, colors: PackedColorArray, r: Dictionary, tri: Array) -> void:
	var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0])
	if n.dot(SEEN_FROM - tri[0]) < 0.0:
		tri = [tri[0], tri[2], tri[1]]
	for p: Vector3 in tri:
		corners.append(p)
		colors.append(Color((p.y - FOOT) / TOP, r.haze, r.snow))


## The ranges, and the lake's water.
static func build() -> Array[MeshInstance3D]:
	var material := ShaderMaterial.new()
	material.shader = load("res://src/mountains.gdshader")
	var water := ShaderMaterial.new()
	water.shader = load("res://src/lake.gdshader")
	water.set_shader_parameter("ridges", ImageTexture.create_from_image(ridge_image()))
	water.set_shader_parameter("level", LAKE)
	water.set_shader_parameter("radii", Vector2(RANGES[0].radius, RANGES[1].radius))
	water.set_shader_parameter("top", TOP)
	return [_instance(arrays(), material), _instance(lake_arrays(), water)]


static func _instance(a: Array, material: ShaderMaterial) -> MeshInstance3D:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi
