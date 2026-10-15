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

static var _heights := base_heights()
## The humps strokes are pulling, one per hand, not yet baked into the heights: centre x, z, radius and lift.
## Shaders add them through ground_humps' columns, so a stroke moves the ground without rewriting the grid every frame.
static var _humps: Array[Vector4] = [NO_HUMP, NO_HUMP]
static var _flat: Array[Vector4] = []
## Counts changes to the ground or the water on it, so work laid on it can tell whether it still stands where it was laid.
static var revision := 0
const NO_WATER := -100.0
## Each grid point's pond surface (Water), NO_WATER where none reaches.
static var _water := _no_water()
## What shaders read where no pond is (water.gdshaderinc): under the -0.5 the terrain shader smooths from, and far
## enough under a shore point's own depth that a bank fades out before the next point.
const DRY := -0.6
static var _water_image: Image
static var _water_texture: ImageTexture
static var _image: Image
static var _texture: ImageTexture


static func base_heights() -> PackedFloat32Array:
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
## The ground without strokes' live humps, which only their own player sees.
static func base_at(x: float, z: float) -> float:
	return height_at(x, z, false)


static func height_at(x: float, z: float, with_hump := true) -> float:
	return _height(x, z, _heights, _humps if with_hump else _flat)


## The ground and the water as they stand now, for a worker thread to read while this one goes on shaping them.
## Not the live arrays: a write while a copy shares one moves it to new memory and may free the old under the
## reader. A duplicate shares the memory until this thread's next write moves the live array off it.
static func held_height() -> Callable:
	return _height.bind(_heights.duplicate(), _humps.duplicate())


static func held_water() -> Callable:
	return _bilinear.bind(_water.duplicate())


static func _height(x: float, z: float, heights: PackedFloat32Array, humps: Array[Vector4]) -> float:
	var u := clampf((x + SIZE * 0.5) / STEP, 0.0, CELLS - 0.001)
	var v := clampf((z + SIZE * 0.5) / STEP, 0.0, CELLS - 0.001)
	var i := int(u)
	var j := int(v)
	var k := j * VERTS + i
	var a := heights[k]
	var b := heights[k + 1]
	var c := heights[k + VERTS]
	var d := heights[k + VERTS + 1]
	for hump in humps:
		if hump.w != 0.0:
			a += _lift(hump, i, j)
			b += _lift(hump, i + 1, j)
			c += _lift(hump, i, j + 1)
			d += _lift(hump, i + 1, j + 1)
	return lerpf(lerpf(a, b, u - i), lerpf(c, d, u - i), v - j)


static func _no_water() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(VERTS * VERTS)
	out.fill(NO_WATER)
	return out


## Every pond gone. Shaders read the water as its depth over the ground (the global water_depth,
## water.gdshaderinc), one texel per grid point: depth filters smoothly into the dry ground around a pond, where
## a level would fall off a cliff to NO_WATER.
static func dry_water() -> void:
	_water.fill(NO_WATER)
	_water_image = Image.create_empty(VERTS, VERTS, false, Image.FORMAT_RH)
	_water_image.fill(Color(DRY, 0, 0))
	_water_texture = ImageTexture.create_from_image(_water_image)
	RenderingServer.global_shader_parameter_set(&"water_depth", _water_texture)
	revision += 1


## The pond surface at grid point `g`.
static func water_level(g: Vector2i) -> float:
	return _water[g.y * VERTS + g.x]


static func set_water(changed: Dictionary) -> void:
	for g: Vector2i in changed:
		_water[g.y * VERTS + g.x] = changed[g]
		_water_image.set_pixelv(g, Color(_depth(g.y * VERTS + g.x), 0, 0))
	_water_texture.update(_water_image)
	revision += 1


static func _depth(k: int) -> float:
	return DRY if _water[k] == NO_WATER else maxf(_water[k] - _heights[k], DRY)


## The pond surface over (x, z), bilinear between grid points: far below the ground where no pond is.
static func water_at(x: float, z: float) -> float:
	return _bilinear(x, z, _water)


static func _bilinear(x: float, z: float, grid: PackedFloat32Array) -> float:
	var u := clampf((x + SIZE * 0.5) / STEP, 0.0, CELLS - 0.001)
	var v := clampf((z + SIZE * 0.5) / STEP, 0.0, CELLS - 0.001)
	var i := int(u)
	var j := int(v)
	var k := j * VERTS + i
	return lerpf(lerpf(grid[k], grid[k + 1], u - i), lerpf(grid[k + VERTS], grid[k + VERTS + 1], u - i), v - j)


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


## The grid point nearest (x, z).
static func grid_point(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(roundi((x + SIZE * 0.5) / STEP), 0, CELLS), clampi(roundi((z + SIZE * 0.5) / STEP), 0, CELLS))


## The world position of grid point `g` across the ground.
static func grid_xz(g: Vector2i) -> Vector2:
	return Vector2(g) * STEP - Vector2.ONE * SIZE * 0.5


## The world rectangle whose ground `cells` decide.
static func world_rect(cells: Rect2i) -> Rect2:
	return Rect2(Vector2(cells.position - Vector2i.ONE) * STEP - Vector2.ONE * SIZE * 0.5, Vector2(cells.size + Vector2i.ONE) * STEP)


## 1 at the centre, falling to 0 with zero slope at t = 1; ground.gdshaderinc's bell is the same curve.
static func bell(t: float) -> float:
	if t >= 1.0:
		return 0.0
	var s := 1.0 - t * t
	return s * s * s


static func _lift(hump: Vector4, i: int, j: int) -> float:
	return hump.w * bell(Vector2(-SIZE * 0.5 + i * STEP - hump.x, -SIZE * 0.5 + j * STEP - hump.y).length() / hump.z)


const ALL := Rect2i(0, 0, VERTS, VERTS)


static func set_hump(slot: int, x: float, z: float, radius: float, lift: float) -> void:
	_humps[slot] = Vector4(x, z, maxf(radius, STEP), lift)
	revision += 1
	_share_humps()


static func clear_hump(slot: int) -> void:
	set_hump(slot, 0, 0, 1, 0)


static func _share_humps() -> void:
	RenderingServer.global_shader_parameter_set(&"ground_humps", Projection(_humps[0], _humps[1], NO_HUMP, NO_HUMP))


## The heights of `cells` with hump `slot` added, and no other: what the ground under its stroke becomes.
static func raised(cells: Rect2i, slot: int) -> PackedFloat32Array:
	var out := read(cells)
	var n := 0
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			out[n] += _lift(_humps[slot], i, j)
			n += 1
	return out


static func read(cells: Rect2i) -> PackedFloat32Array:
	if cells == ALL:
		return _heights.duplicate()
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
	revision += 1
	_sync(cells)


## Shares the heights with shaders (ground.gdshaderinc) as a texture, one texel per grid point, red the height
## and green the steepness. Half
## floats because only 16-bit float textures are filterable on every Vulkan device; their steps stay
## under 3 cm below HIGHEST.
static func install() -> void:
	_image = Image.create_empty(VERTS, VERTS, false, Image.FORMAT_RGH)
	_texture = ImageTexture.create_from_image(_image)
	_sync(Rect2i(0, 0, VERTS, VERTS))
	RenderingServer.global_shader_parameter_set(&"ground_height", _texture)
	RenderingServer.global_shader_parameter_set(&"ground_grid", Vector3(-SIZE * 0.5, STEP, VERTS))
	_share_humps()


## A box holding the ground and anything standing on it, for meshes the GPU lifts onto the heights.
static func bounds() -> AABB:
	return AABB(Vector3(-SIZE * 0.5, LOWEST - 2.0, -SIZE * 0.5), Vector3(SIZE, HIGHEST - LOWEST + 32.0, SIZE))


## 1 - the ground normal's y at grid point (i, j), as ground_normal in ground.gdshaderinc finds it there.
static func _steepness(i: int, j: int) -> float:
	var row := j * VERTS
	var dx := _heights[row + mini(i + 1, CELLS)] - _heights[row + maxi(i - 1, 0)]
	var dz := _heights[mini(j + 1, CELLS) * VERTS + i] - _heights[maxi(j - 1, 0) * VERTS + i]
	return 1.0 - 2.0 * STEP / sqrt(dx * dx + dz * dz + 4.0 * STEP * STEP)


static func _sync(cells: Rect2i) -> void:
	if _image == null:
		return
	# Green is each point's steepness, from its neighbours' heights, so it changes a step around the edit too.
	var around := cells.grow(1).intersection(ALL)
	for j in range(around.position.y, around.end.y):
		for i in range(around.position.x, around.end.x):
			_image.set_pixel(i, j, Color(_heights[j * VERTS + i], _steepness(i, j), 0))
	_texture.update(_image)
	if _water_image == null:
		return
	var wet := false
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			if _water[j * VERTS + i] != NO_WATER:
				_water_image.set_pixel(i, j, Color(_depth(j * VERTS + i), 0, 0))
				wet = true
	if wet:
		_water_texture.update(_water_image)


## A flat grid the terrain shader lifts onto the heights; vertex colour red is how dry the meadow's grass is there.
static func build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in VERTS:
		for i in VERTS:
			var x := -SIZE * 0.5 + i * STEP
			var z := -SIZE * 0.5 + j * STEP
			st.set_color(Color(FloraLayout.dryness(Vector3(x, 0, z)), 0, 0))
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
