class_name Terrain
extends RefCounted

## The ground: one height per metre over the play area, shaped by hand. The CPU reads it here and the GPU
## from the texture `install` shares, so plants follow an edit without being touched.

const SIZE := 160.0
const STEP := 1.0
const CELLS := int(SIZE / STEP)
const VERTS := CELLS + 1
const LOWEST := -8.0
const HIGHEST := 40.0
const NO_HUMP := Vector4(0, 0, 1, 0)

static var _heights := _base_heights()
## The hump a stroke is pulling, not yet baked into the heights: centre x, z, radius and lift. Shaders add
## it through ground_hump, so a stroke moves the ground without rewriting the grid every frame.
static var _hump := NO_HUMP
static var _image: Image
static var _texture: ImageTexture


static func _base_heights() -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_octaves = 3
	var out := PackedFloat32Array()
	out.resize(VERTS * VERTS)
	for j in VERTS:
		for i in VERTS:
			var x := -SIZE * 0.5 + i * STEP
			var z := -SIZE * 0.5 + j * STEP
			var r := Vector2(x, z).length()
			var rolling := noise.get_noise_2d(x, z) * 1.6 + sin(x * 0.045) * cos(z * 0.06) * 0.7
			var rim := smoothstep(34.0, 75.0, r) * (9.0 + noise.get_noise_2d(z * 1.7, x * 1.7) * 6.0)
			out[j * VERTS + i] = rolling + rim
	return out


## Bilinear between the four grid heights around (x, z), as the GPU's filtered texture reads them; a
## live hump is sampled on the same grid points, so baking it moves nothing.
static func height_at(x: float, z: float) -> float:
	var u := clampf((x + SIZE * 0.5) / STEP, 0.0, CELLS - 0.001)
	var v := clampf((z + SIZE * 0.5) / STEP, 0.0, CELLS - 0.001)
	var i := int(u)
	var j := int(v)
	var k := j * VERTS + i
	var a := _heights[k]
	var b := _heights[k + 1]
	var c := _heights[k + VERTS]
	var d := _heights[k + VERTS + 1]
	if _hump.w != 0.0:
		a += _hump_at(i, j)
		b += _hump_at(i + 1, j)
		c += _hump_at(i, j + 1)
		d += _hump_at(i + 1, j + 1)
	return lerpf(lerpf(a, b, u - i), lerpf(c, d, u - i), v - j)


static func ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## First hit of a ray with the ground, or null.
static func raycast(origin: Vector3, dir: Vector3, max_dist := 80.0) -> Variant:
	var step := 0.25
	var prev := 0.0
	var t := 0.0
	while t <= max_dist:
		var p := origin + dir * t
		if p.y <= height_at(p.x, p.z):
			var lo := prev
			var hi := t
			for i in 12:
				var mid := (lo + hi) * 0.5
				var q := origin + dir * mid
				if q.y <= height_at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			return origin + dir * hi
		prev = t
		t += step * (1.0 + t * 0.03)
	return null


## The grid cells within `radius` of (x, z), clipped to the play area.
static func cells_around(x: float, z: float, radius: float) -> Rect2i:
	var lo := Vector2i(floori((x - radius + SIZE * 0.5) / STEP), floori((z - radius + SIZE * 0.5) / STEP))
	var hi := Vector2i(ceili((x + radius + SIZE * 0.5) / STEP), ceili((z + radius + SIZE * 0.5) / STEP))
	return Rect2i(lo, hi - lo + Vector2i.ONE).intersection(Rect2i(0, 0, VERTS, VERTS))


## The world rectangle whose ground `cells` decide.
static func world_rect(cells: Rect2i) -> Rect2:
	return Rect2(Vector2(cells.position - Vector2i.ONE) * STEP - Vector2.ONE * SIZE * 0.5, Vector2(cells.size + Vector2i.ONE) * STEP)


## 1 at the centre, falling to 0 with zero slope at t = 1; ground.gdshaderinc's bell is the same curve.
static func bell(t: float) -> float:
	if t >= 1.0:
		return 0.0
	var s := 1.0 - t * t
	return s * s * s


static func _hump_at(i: int, j: int) -> float:
	return _hump.w * bell(Vector2(-SIZE * 0.5 + i * STEP - _hump.x, -SIZE * 0.5 + j * STEP - _hump.y).length() / _hump.z)


static func set_hump(x: float, z: float, radius: float, lift: float) -> void:
	_hump = Vector4(x, z, maxf(radius, STEP), lift)
	RenderingServer.global_shader_parameter_set(&"ground_hump", _hump)


## Writes the live hump into the heights.
static func bake() -> void:
	var cells := cells_around(_hump.x, _hump.y, _hump.z)
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			_heights[j * VERTS + i] += _hump_at(i, j)
	_hump = NO_HUMP
	RenderingServer.global_shader_parameter_set(&"ground_hump", _hump)
	_sync(cells)


static func read(cells: Rect2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(cells.size.x * cells.size.y)
	var n := 0
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			out[n] = _heights[j * VERTS + i]
			n += 1
	return out


static func write(cells: Rect2i, values: PackedFloat32Array) -> void:
	var n := 0
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			_heights[j * VERTS + i] = values[n]
			n += 1
	_sync(cells)


## Shares the heights with shaders (ground.gdshaderinc) as a texture, one texel per grid point. Half
## floats because only 16-bit float textures are filterable on every Vulkan device; their steps stay
## under 3 cm below HIGHEST.
static func install() -> void:
	_image = Image.create_empty(VERTS, VERTS, false, Image.FORMAT_RH)
	_texture = ImageTexture.create_from_image(_image)
	_sync(Rect2i(0, 0, VERTS, VERTS))
	RenderingServer.global_shader_parameter_set(&"ground_height", _texture)
	RenderingServer.global_shader_parameter_set(&"ground_grid", Vector3(-SIZE * 0.5, STEP, VERTS))
	RenderingServer.global_shader_parameter_set(&"ground_hump", _hump)


## A box holding the ground and anything standing on it, for meshes the GPU lifts onto the heights.
static func bounds() -> AABB:
	return AABB(Vector3(-SIZE * 0.5, LOWEST - 2.0, -SIZE * 0.5), Vector3(SIZE, HIGHEST - LOWEST + 32.0, SIZE))


static func _sync(cells: Rect2i) -> void:
	if _image == null:
		return
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			_image.set_pixel(i, j, Color(_heights[j * VERTS + i], 0, 0))
	_texture.update(_image)


## A flat grid the terrain shader lifts onto the heights; vertex colour red is the meadow's lushness.
static func build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tint := FastNoiseLite.new()
	tint.seed = 11
	tint.frequency = 0.05
	for j in VERTS:
		for i in VERTS:
			var x := -SIZE * 0.5 + i * STEP
			var z := -SIZE * 0.5 + j * STEP
			st.set_color(Color(clampf(0.5 + tint.get_noise_2d(x, z) * 0.9, 0.0, 1.0), 0, 0))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(x, 0, z))
	for j in CELLS:
		for i in CELLS:
			var a := j * VERTS + i
			var b := a + 1
			var c := a + VERTS
			var d := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	return st.commit()
