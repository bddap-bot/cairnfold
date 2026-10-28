class_name Terrain
extends RefCounted

## The ground: one height per metre over the play area, shaped by hand, and the ponds on it; each World holds its own.
## The CPU reads it here and the GPU from the texture `install` shares, so plants follow an edit without being touched.
## A stroke's live hump is this player's preview, not the garden: only `shown_at` and what asks for `shown` see it.

const SIZE := 160.0
const STEP := 1.0
const CELLS := int(SIZE / STEP)
const VERTS := CELLS + 1
const NO_HUMP := Vector4(0, 0, 1, 0)
## The ground lies within this many metres above or below zero, past any hand's pull and within what the GPU's half-float
## heights carry: the ground tool stops there, and no command lays it past.
const RELIEF := 10000.0
## A bank runs BANK out from every point of the ground's edge, as that point stands now, down to BANK_FOOT, where the
## plain or the lake's bed (Mountains) begins; the lake stands over the foot, so the water meets the bank.
const BANK := 10.0
const BANK_FOOT := 2.5
## Everywhere a command may place anything, or a player be: the map and its banks, to RELIEF up and down. The same on
## every machine, where bounds() grows with what each has shown.
const ROOM := AABB(Vector3(-SIZE * 0.5 - BANK, -RELIEF - 30.0, -SIZE * 0.5 - BANK), Vector3(SIZE + 2.0 * BANK, 2.0 * RELIEF + 60.0, SIZE + 2.0 * BANK))
## Ground this steep (1 - its normal's y) is rock, too steep to hold soil: the terrain shader's rock rises over this
## span, and no grass or flower stands from where it begins (Flora).
const ROCK := Vector2(0.36, 0.48)

var _heights := base_heights()
## Each grid point's steepness, 1 - its normal's y.
var _steep := _steeps()
## The humps strokes are pulling, one per hand, not yet baked into the heights: centre x, z, radius and lift.
## Shaders add them through ground_humps' columns, so a stroke moves the ground without rewriting the grid every frame.
var _humps: Array[Vector4] = [NO_HUMP, NO_HUMP]
const NO_HUMPS: Array[Vector4] = []
## Counts changes to the ground or the water on it, so work laid on it can tell whether it still stands where it was laid.
var revision := 0
## Counts changes to the heights alone, for light that falls on the ground whatever water stands on it.
var heights_revision := 0
## The same, and every move of a live hump: what work following the shown ground keys on.
var shown_revision := 0
## The highest grid height in each BLOCK by BLOCK of cells, its edge vertices shared with the next, so a ray can pass
## over a block it stays above without sampling it.
const BLOCK := 8
const BLOCKS := ceili(float(CELLS) / BLOCK)
var _tops := _block_tops()
const NO_WATER := -100.0
## Each grid point's pond surface (Water), NO_WATER where none reaches.
var _water := _no_water()
## What shaders read where no pond is (water.gdshaderinc): under the -0.5 the terrain shader smooths from, and far
## enough under a shore point's own depth that a bank fades out before the next point.
const DRY := -0.6
var _water_image: Image
var _water_texture: ImageTexture
var _image: Image
var _texture: ImageTexture
## The lowest and highest the ground has been, and the span bounds() gives, which grows past them in strides so the
## boxes lifted onto it are refitted seldom while a stroke pulls the ground ever further.
var _floor: float = Array(_heights).min()
var _crest: float = Array(_heights).max()
var _low := _floor
var _high := _crest
var _lifted := {}
var _half := PackedByteArray([0, 0])


## Level ground at zero, for layouts built off the garden's terrain.
static func flat(_x: float, _z: float) -> float:
	return 0.0


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
func height_at(x: float, z: float) -> float:
	return _height(x, z, _heights, NO_HUMPS)


## The ground as this player sees it, live humps included.
func shown_at(x: float, z: float) -> float:
	return _height(x, z, _heights, _humps)


## How steep the ground is at (x, z), 1 - its normal's y, as its fragments interpolate it between grid points.
func steep_at(x: float, z: float) -> float:
	return _height(x, z, _steep, NO_HUMPS)


## Whether the ground at (x, z) is rock (ROCK) as it settles, which holds no grass or flowers.
func rock_at(x: float, z: float) -> bool:
	return steep_at(x, z) >= ROCK.x


func _steeps() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(VERTS * VERTS)
	for j in VERTS:
		for i in VERTS:
			out[j * VERTS + i] = 1.0 - _normal(i, j).y
	return out


## The ground and the water as they stand now, for a worker thread to read while this one goes on shaping them.
## Not the live arrays: a write while a copy shares one moves it to new memory and may free the old under the
## reader. A duplicate shares the memory until this thread's next write moves the live array off it.
func held_height(shown := false) -> Callable:
	return _height.bind(_heights.duplicate(), _humps.duplicate() if shown else NO_HUMPS)


func held_water(shown := false) -> Callable:
	return _height.bind(_heights.duplicate(), _humps.duplicate() if shown else NO_HUMPS, _water.duplicate())


## With `water`, the pond surface instead: at a grid point no pond reaches, NO_WATER under that point's own ground, so
## ground dug however deep never stands under water.
static func _height(x: float, z: float, heights: PackedFloat32Array, humps: Array[Vector4], water := PackedFloat32Array()) -> float:
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
	if not water.is_empty():
		a = _wet(water[k], a)
		b = _wet(water[k + 1], b)
		c = _wet(water[k + VERTS], c)
		d = _wet(water[k + VERTS + 1], d)
	return lerpf(lerpf(a, b, u - i), lerpf(c, d, u - i), v - j)


static func _wet(level: float, ground: float) -> float:
	return ground + NO_WATER if level == NO_WATER else level


static func _no_water() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(VERTS * VERTS)
	out.fill(NO_WATER)
	return out


## Every pond gone. Shaders read the water as its depth over the ground (the global water_depth,
## water.gdshaderinc), one texel per grid point: depth filters smoothly into the dry ground around a pond, where
## a level would fall off a cliff to NO_WATER.
func dry_water() -> void:
	_water.fill(NO_WATER)
	_water_image = Image.create_empty(VERTS, VERTS, false, Image.FORMAT_RH)
	_water_image.fill(Color(DRY, 0, 0))
	_water_texture = ImageTexture.create_from_image(_water_image)
	RenderingServer.global_shader_parameter_set(&"water_depth", _water_texture)
	revision += 1
	shown_revision += 1


## The pond surface at every grid point, NO_WATER where none is.
func water_levels() -> PackedFloat32Array:
	return _water.duplicate()


## Takes `levels` as the pond surface at every grid point and `image` (`depth_image`) as what shaders read of it.
func set_water(levels: PackedFloat32Array, image: Image) -> void:
	_water = levels
	_water_image = image
	_water_texture.update(_water_image)
	revision += 1
	shown_revision += 1


## What shaders read of the water at `levels` over the ground at `heights`, both at every grid point, as a texture's
## image: the depth at the grid points `wet` and DRY everywhere else. Reads no shared state, so any thread may run it.
static func depth_image(levels: PackedFloat32Array, heights: PackedFloat32Array, wet: PackedInt32Array) -> Image:
	var depth := PackedFloat32Array()
	depth.resize(levels.size())
	depth.fill(DRY)
	for k in wet:
		if levels[k] != NO_WATER:
			depth[k] = maxf(levels[k] - heights[k], DRY)
	var image := Image.create_from_data(VERTS, VERTS, false, Image.FORMAT_RF, depth.to_byte_array())
	image.convert(Image.FORMAT_RH)
	return image


func _depth(k: int) -> float:
	return DRY if _water[k] == NO_WATER else maxf(_water[k] - _heights[k], DRY)


## How deep pond water stands over (x, z), bilinear between grid points as the shaders read it (water.gdshaderinc):
## DRY where no pond reaches.
func depth_at(x: float, z: float) -> float:
	var u := clampf((x + SIZE * 0.5) / STEP, 0.0, CELLS - 0.001)
	var v := clampf((z + SIZE * 0.5) / STEP, 0.0, CELLS - 0.001)
	var i := int(u)
	var j := int(v)
	var k := j * VERTS + i
	return lerpf(lerpf(_depth(k), _depth(k + 1), u - i), lerpf(_depth(k + VERTS), _depth(k + VERTS + 1), u - i), v - j)


## The pond surface over (x, z), bilinear between grid points: far below the ground where no pond is.
func water_at(x: float, z: float) -> float:
	return _height(x, z, _heights, NO_HUMPS, _water)


func ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## First hit of a ray with the ground, or null.
func raycast(origin: Vector3, dir: Vector3, max_dist := INF) -> Variant:
	max_dist = minf(max_dist, exit_along(origin, dir))
	var step := 0.25
	var prev := 0.0
	var t := 0.0
	while true:
		var end := minf(t + BLOCK * STEP, max_dist)
		if _above(origin + dir * t, origin + dir * end):
			prev = end
			t = end
		else:
			while true:
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
				if t >= end:
					break
				t = minf(t + step * (1.0 + t * 0.03), end)
		if t >= max_dist:
			return null
	return null


## Whether the segment from `a` to `b` stays above every block under it.
func _above(a: Vector3, b: Vector3) -> bool:
	var lo := _block_of(minf(a.x, b.x), minf(a.z, b.z))
	var hi := _block_of(maxf(a.x, b.x), maxf(a.z, b.z))
	var top := -INF
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			top = maxf(top, _tops[j * BLOCKS + i])
	return minf(a.y, b.y) > top


static func _block_of(x: float, z: float) -> Vector2i:
	var u := clampf((x + SIZE * 0.5) / STEP, 0.0, CELLS - 0.001)
	var v := clampf((z + SIZE * 0.5) / STEP, 0.0, CELLS - 0.001)
	return Vector2i(int(u) / BLOCK, int(v) / BLOCK)


func _block_tops() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(BLOCKS * BLOCKS)
	for bj in BLOCKS:
		for bi in BLOCKS:
			out[bj * BLOCKS + bi] = _top(bi, bj)
	return out


## Recomputes the tops of the blocks holding any vertex of `cells`.
func _raise_tops(cells: Rect2i) -> void:
	var lo := Vector2i(maxi(cells.position.x - 1, 0), maxi(cells.position.y - 1, 0)) / BLOCK
	var hi := Vector2i(mini(cells.end.x - 1, CELLS - 1), mini(cells.end.y - 1, CELLS - 1)) / BLOCK
	for bj in range(lo.y, hi.y + 1):
		for bi in range(lo.x, hi.x + 1):
			_tops[bj * BLOCKS + bi] = _top(bi, bj)


func _top(bi: int, bj: int) -> float:
	var top := -INF
	for j in range(bj * BLOCK, mini(bj * BLOCK + BLOCK, CELLS) + 1):
		for i in range(bi * BLOCK, mini(bi * BLOCK + BLOCK, CELLS) + 1):
			top = maxf(top, _heights[j * VERTS + i])
	return top


## How far along `dir` from `origin` the ray leaves `bounds()`; 0 if it is past it already.
func exit_along(origin: Vector3, dir: Vector3) -> float:
	var box := bounds()
	var t := INF
	for axis in 3:
		if dir[axis] > 0.0:
			t = minf(t, (box.end[axis] - origin[axis]) / dir[axis])
		elif dir[axis] < 0.0:
			t = minf(t, (box.position[axis] - origin[axis]) / dir[axis])
	return maxf(t, 0.0)


## How far along `dir` from `origin` the ray leaves the map over its side; INF if it never does, 0 if it is past it.
static func side_along(origin: Vector3, dir: Vector3) -> float:
	var t := INF
	for axis in [0, 2]:
		if dir[axis] != 0.0:
			t = minf(t, (signf(dir[axis]) * SIZE * 0.5 - origin[axis]) / dir[axis])
	return maxf(t, 0.0)


## The grid cells within `radius` of (x, z), clipped to the play area.
static func cells_around(x: float, z: float, radius: float) -> Rect2i:
	var lo := Vector2i(floori((x - radius + SIZE * 0.5) / STEP), floori((z - radius + SIZE * 0.5) / STEP))
	var hi := Vector2i(ceili((x + radius + SIZE * 0.5) / STEP), ceili((z + radius + SIZE * 0.5) / STEP))
	return Rect2i(lo, hi - lo + Vector2i.ONE).intersection(Rect2i(0, 0, VERTS, VERTS))


## The grid point nearest (x, z).
static func grid_point(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(roundi((x + SIZE * 0.5) / STEP), 0, CELLS), clampi(roundi((z + SIZE * 0.5) / STEP), 0, CELLS))


## The grid point water at `g` runs down to over the ground, steepest way first.
func downhill(g: Vector2i) -> Vector2i:
	while true:
		var next := g
		for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n: Vector2i = g + o
			if n.x >= 0 and n.y >= 0 and n.x < VERTS and n.y < VERTS and _heights[n.y * VERTS + n.x] < _heights[next.y * VERTS + next.x]:
				next = n
		if next == g:
			return g
		g = next
	return g


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


func set_hump(slot: int, x: float, z: float, radius: float, lift: float) -> void:
	_humps[slot] = Vector4(x, z, maxf(radius, STEP), lift)
	shown_revision += 1
	_fit()
	_share_humps()


func clear_hump(slot: int) -> void:
	set_hump(slot, 0, 0, 1, 0)


func _share_humps() -> void:
	RenderingServer.global_shader_parameter_set(&"ground_humps", Projection(_humps[0], _humps[1], NO_HUMP, NO_HUMP))


## The heights of `cells` with hump `slot` added, and no other: what the ground under its stroke becomes.
func raised(cells: Rect2i, slot: int) -> PackedFloat32Array:
	var out := read(cells)
	var n := 0
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			out[n] = clampf(out[n] + _lift(_humps[slot], i, j), -RELIEF, RELIEF)
			n += 1
	return out


func read(cells: Rect2i) -> PackedFloat32Array:
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


func write(cells: Rect2i, values: PackedFloat32Array) -> void:
	var n := 0
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			_heights[j * VERTS + i] = values[n]
			_floor = minf(_floor, values[n])
			_crest = maxf(_crest, values[n])
			n += 1
	# A point's normal is from its neighbours' heights, so it changes a step around the edit too.
	var around := cells.grow(1).intersection(ALL)
	for j in range(around.position.y, around.end.y):
		for i in range(around.position.x, around.end.x):
			_steep[j * VERTS + i] = 1.0 - _normal(i, j).y
	_raise_tops(cells)
	revision += 1
	heights_revision += 1
	shown_revision += 1
	_fit()
	_sync(cells)


## Shares the heights with shaders (ground.gdshaderinc) as a texture, one texel per grid point: red the height
## to half precision, blue what that rounding left, green and alpha the normal's x and z there. Half floats because only 16-bit float
## textures are filterable on every Vulkan device; filtering is linear, so red plus blue filters to the height
## itself, true to a fraction of a millimetre on ground a kilometre high.
func install() -> void:
	_image = Image.create_empty(VERTS, VERTS, false, Image.FORMAT_RGBAH)
	_texture = ImageTexture.create_from_image(_image)
	_sync(Rect2i(0, 0, VERTS, VERTS))
	RenderingServer.global_shader_parameter_set(&"ground_height", _texture)
	RenderingServer.global_shader_parameter_set(&"ground_grid", Vector3(-SIZE * 0.5, STEP, VERTS))
	_share_humps()


## A box holding the ground and anything standing on it, for meshes the GPU lifts onto the heights.
func bounds() -> AABB:
	var low := minf(_low, BANK_FOOT) - 2.0
	return AABB(Vector3(-SIZE * 0.5 - BANK, low, -SIZE * 0.5 - BANK), Vector3(SIZE + 2.0 * BANK, _high - low + 30.0, SIZE + 2.0 * BANK))


## Sets `target`'s custom_aabb (a GeometryInstance3D's or a MultiMesh's) to `box`, which spans bounds()' heights,
## and keeps it spanning them as they grow.
func lift(target: Object, box: AABB) -> void:
	target.custom_aabb = box
	_lifted[target.get_instance_id()] = weakref(target)


## Grows bounds() to the ground and its live humps, a stride past them, and every lifted box with it.
func _fit() -> void:
	var low := _floor
	var high := _crest
	for hump in _humps:
		low += minf(hump.w, 0.0)
		high += maxf(hump.w, 0.0)
	if low >= _low and high <= _high:
		return
	var stride := maxf(8.0, (high - low) * 0.5)
	var down := low - stride - _low if low < _low else 0.0
	var up := high + stride - _high if high > _high else 0.0
	_low += down
	_high += up
	for id: int in _lifted.keys():
		var target: Object = _lifted[id].get_ref()
		if target == null:
			_lifted.erase(id)
			continue
		var box: AABB = target.custom_aabb
		box.position.y += down
		box.size.y += up - down
		target.custom_aabb = box


## The ground's normal at grid point (i, j), as ground_normal in ground.gdshaderinc finds it there.
func _normal(i: int, j: int) -> Vector3:
	var row := j * VERTS
	var dx := _heights[row + mini(i + 1, CELLS)] - _heights[row + maxi(i - 1, 0)]
	var dz := _heights[mini(j + 1, CELLS) * VERTS + i] - _heights[maxi(j - 1, 0) * VERTS + i]
	return Vector3(-dx, 2.0 * STEP, -dz).normalized()


func _sync(cells: Rect2i) -> void:
	if _image == null:
		return
	# The normal is each point's from its neighbours' heights, so it changes a step around the edit too.
	var around := cells.grow(1).intersection(ALL)
	for j in range(around.position.y, around.end.y):
		for i in range(around.position.x, around.end.x):
			var h := _heights[j * VERTS + i]
			_half.encode_half(0, h)
			var hi := _half.decode_half(0)
			var n := _normal(i, j)
			_image.set_pixel(i, j, Color(hi, n.x, h - hi, n.z))
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


## A flat grid the terrain shader lifts onto the heights, ringed by the bank's foot, which it leaves where it lies;
## vertex colour red is how dry the meadow's grass is there.
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
	var rim := edge(0.0)
	var foot := edge(BANK)
	for p in foot:
		st.set_color(Color(FloraLayout.dryness(Vector3(p.x, 0, p.y)), 0, 0))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(p.x, BANK_FOOT, p.y))
	var n := rim.size()
	for k in n:
		var a := _rim_vertex(k)
		var b := _rim_vertex((k + 1) % n)
		var c := VERTS * VERTS + k
		var d := VERTS * VERTS + (k + 1) % n
		st.add_index(a); st.add_index(c); st.add_index(b)
		st.add_index(b); st.add_index(c); st.add_index(d)
	return st.commit()


## The points round the ground's edge a STEP apart, starting at its -x, -z corner, each pushed `out` from the edge
## away from the centre: the bank's top at 0, its foot at BANK.
static func edge(out: float) -> PackedVector2Array:
	var half := SIZE * 0.5
	var points := PackedVector2Array()
	for side in 4:
		for k in CELLS:
			var t := -half + k * STEP
			var p: Vector2 = [Vector2(t, -half), Vector2(half, t), Vector2(-t, half), Vector2(-half, -t)][side]
			points.append(p * ((half + out) / half))
	return points


## The grid vertex at edge(0.0)'s `k`th point.
static func _rim_vertex(k: int) -> int:
	var side := k / CELLS
	var t := k % CELLS
	return [t, t * VERTS + CELLS, CELLS * VERTS + CELLS - t, (CELLS - t) * VERTS][side]
