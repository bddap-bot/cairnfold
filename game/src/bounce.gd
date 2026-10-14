class_name Bounce
extends RefCounted

## Light the built garden gives back: a probe per ground cell over the play area in LAYERS a metre apart that
## follow the ground, shared with shaders as the global bounce_volume (bounce.gdshaderinc). Alpha is how
## much of the sky a probe sees past the builds around it, darkening ambient light at wall feet and in
## corners; RGB is sunlight thrown back by the sunlit stone faces it sees, added to what it lights.
##
## The builds are read as a height field: per column the top of the pieces over it and their mean colour.
## Walls, towers and houses stand straight up, so a height field holds them, and it makes a probe's view a
## horizon per direction: REACH columns walked in each of AZIMUTHS directions.

const LAYERS := 12
const CELLS := Terrain.CELLS
const AREA := Rect2i(0, 0, CELLS, CELLS)
const AZIMUTHS := 8
const REACH := 6
## How many columns toward the sun are walked to find whether a face is in shadow.
const SUN_WALK := 12
## Stones are grey before the palette tints them; light off them is taken this bright.
const ALBEDO := 0.75
## Bounce is stored this many times over, for precision in a byte: it rarely passes a third of the sun.
const ENCODE := 2.0

## Owner id -> the columns it fills: column -> Vector4(top, colour). Worker-side while a solve runs.
var _owners := {}
var _tops := PackedFloat32Array()
var _colors := PackedColorArray()
## Owner id -> its pieces' instance buffers and their strides, placed since the last solve began.
var _pending := {}
var _sun := Vector3.UP
var _relight := false
## The ground's heights the last solve stood on, and the Terrain.revision they were read at. A stroke's live
## hump moves the revision without them.
var _heights := PackedFloat32Array()
var _ground := -1
var _task := -1
var _out := {}
var _layers: Array[Image] = []
var texture := ImageTexture3D.new()


func _init() -> void:
	_tops.resize(CELLS * CELLS)
	_tops.fill(-INF)
	_colors.resize(CELLS * CELLS)
	for k in LAYERS:
		var img := Image.create(CELLS, CELLS, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 1))
		_layers.append(img)
	texture.create(Image.FORMAT_RGBA8, CELLS, CELLS, LAYERS, false, _layers)


func install() -> void:
	RenderingServer.global_shader_parameter_set(&"bounce_volume", texture)
	RenderingServer.global_shader_parameter_set(&"bounce_grid", Vector3(-Terrain.SIZE * 0.5, Terrain.SIZE, LAYERS))


static func column(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x + Terrain.SIZE * 0.5) / Terrain.STEP), floori((z + Terrain.SIZE * 0.5) / Terrain.STEP))


## What a probe holds: rgb bounce as stored, alpha sky seen.
func probe(x: float, z: float, layer: int) -> Color:
	var c := column(x, z)
	return _layers[layer].get_pixel(c.x, c.y)


## The columns pieces fill, from instance buffers (Masonry.Kind: origin at 3, 7 and 11, the basis's row of
## heights at 4 to 6, colour at 12) of the given strides. A piece is a unit box under its transform.
static func columns(buffers: Array[PackedFloat32Array], strides: PackedInt32Array) -> Dictionary:
	var out := {}
	for b in buffers.size():
		var buf := buffers[b]
		for i in range(0, buf.size(), strides[b]):
			var c := column(buf[i + 3], buf[i + 11])
			if not AREA.has_point(c):
				continue
			var top := buf[i + 7] + 0.5 * (absf(buf[i + 4]) + absf(buf[i + 5]) + absf(buf[i + 6]))
			var color := Color(buf[i + 12], buf[i + 13], buf[i + 14])
			if out.has(c):
				var e: Array = out[c]
				e[0] = maxf(e[0], top)
				e[1] += color
				e[2] += 1
			else:
				out[c] = [top, color, 1]
	var cols := {}
	for c in out:
		var e: Array = out[c]
		cols[c] = Vector4(e[0], e[1].r / e[2], e[1].g / e[2], e[1].b / e[2])
	return cols


## What `owner` stands in the garden, as Masonry places it; no pieces once it is gone.
func place(owner: int, buffers: Array[PackedFloat32Array], strides: PackedInt32Array) -> void:
	_pending[owner] = [buffers, strides]


## Light comes from `toward_sun` in `light` (colour times strength); bounce off faces is taken again when it
## moves.
func set_sun(toward_sun: Vector3, light: Color) -> void:
	RenderingServer.global_shader_parameter_set(&"bounce_light", light / ENCODE)
	if toward_sun.is_equal_approx(_sun):
		return
	_sun = toward_sun
	_relight = true


## Takes a finished solve and starts one for whatever changed since; called once a frame.
func update() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		_collect()
	if _ground != Terrain.revision:
		_ground = Terrain.revision
		var heights := Terrain.read(Terrain.ALL)
		if heights != _heights:
			_heights = heights
			_relight = true
	if _pending.is_empty() and not _relight:
		return
	var job := {"pending": _pending, "sun": _sun, "relight": _relight, "heights": _heights}
	_pending = {}
	_relight = false
	var out := {}
	_out = out
	_task = WorkerThreadPool.add_task(func() -> void: out.merge(_work(job)), false)


## Solves everything changed so far before returning.
func finish() -> void:
	update()
	while _task >= 0:
		_collect()
		update()


## Lets a solve under way end, so none outlives the game.
func stop() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _collect() -> void:
	stop()
	if _out.has("layers"):
		var area: Rect2i = _out.area
		for k in LAYERS:
			var region := Image.create_from_data(area.size.x, area.size.y, false, Image.FORMAT_RGBA8, _out.layers[k])
			_layers[k].blit_rect(region, Rect2i(Vector2i.ZERO, area.size), area.position)
		texture.update(_layers)


## On the worker: the height field takes the pending owners, then every probe that could see a change is
## solved again: a probe sees columns REACH out, whose faces are shaded by columns SUN_WALK beyond them.
func _work(job: Dictionary) -> Dictionary:
	var changed := {}
	for owner: int in job.pending:
		var cols := columns(job.pending[owner][0], job.pending[owner][1])
		changed.merge(_owners.get(owner, {}))
		changed.merge(cols)
		if cols.is_empty():
			_owners.erase(owner)
		else:
			_owners[owner] = cols
	for c in changed:
		_refill(c)
	if job.relight:
		for o in _owners.values():
			changed.merge(o)
	if changed.is_empty():
		return {}
	var area := Rect2i(changed.keys()[0], Vector2i.ONE)
	for c in changed:
		area = area.expand(c).expand(c + Vector2i.ONE)
	area = area.grow(REACH + SUN_WALK).intersection(AREA)
	return solve(_tops, _colors, grounds(job.heights), job.sun, area)


func _refill(c: Vector2i) -> void:
	var top := -INF
	var sum := Color(0, 0, 0)
	var n := 0
	for o in _owners.values():
		if o.has(c):
			var v: Vector4 = o[c]
			top = maxf(top, v.x)
			sum += Color(v.y, v.z, v.w)
			n += 1
	var i := c.y * CELLS + c.x
	_tops[i] = top
	_colors[i] = sum / n if n > 0 else Color(0, 0, 0)


## The ground's height at each column's middle, from Terrain's heights at the grid points.
static func grounds(heights: PackedFloat32Array) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(CELLS * CELLS)
	var v := Terrain.VERTS
	for j in CELLS:
		for i in CELLS:
			var at := j * v + i
			g[j * CELLS + i] = (heights[at] + heights[at + 1] + heights[at + v] + heights[at + v + 1]) * 0.25
	return g


## The probes over `area`, one byte array per layer, from the builds' `tops` and `colors` per column, the
## ground under each and the sun.
static func solve(tops: PackedFloat32Array, colors: PackedColorArray, ground: PackedFloat32Array, sun: Vector3, area: Rect2i) -> Dictionary:
	var sun_flat := Vector2(sun.x, sun.z)
	var sun_rise := sun.y / maxf(sun_flat.length(), 0.05)
	sun_flat = sun_flat.normalized() if sun_flat.length() > 0.0 else Vector2.ZERO
	var dirs: Array[Vector2i] = []
	var steps := PackedFloat32Array()
	var facing := PackedFloat32Array()
	for a in AZIMUTHS:
		var d := Vector2.from_angle(TAU * a / AZIMUTHS)
		dirs.append(Vector2i(roundi(d.x), roundi(d.y)))
		steps.append(Vector2(dirs[a]).length() * Terrain.STEP)
		# A face seen looking along d faces back along -d.
		facing.append(maxf(-Vector2(dirs[a]).normalized().dot(sun_flat), 0.0) * clampf(sun.y * 4.0, 0.0, 1.0))
	var lit := _lit(tops, ground, sun_flat, sun_rise, area)
	var layers := []
	for k in LAYERS:
		var px := PackedByteArray()
		px.resize(area.size.x * area.size.y * 4)
		layers.append(px)
	for j in area.size.y:
		for i in area.size.x:
			var c := area.position + Vector2i(i, j)
			var base := ground[c.y * CELLS + c.x]
			# Per direction, each built column passed: how far, its top and where it is.
			var near := []
			var found := false
			for a in AZIMUTHS:
				var hits := []
				var p := c
				for s in REACH:
					p += dirs[a]
					if not AREA.has_point(p):
						break
					var at := p.y * CELLS + p.x
					if tops[at] > -INF:
						hits.append([steps[a] * (s + 1), tops[at], at])
						found = true
				near.append(hits)
			var o := (j * area.size.x + i) * 4
			for k in LAYERS:
				var px: PackedByteArray = layers[k]
				if not found:
					px[o] = 0
					px[o + 1] = 0
					px[o + 2] = 0
					px[o + 3] = 255
					continue
				var h := base + k + 0.5
				var sky := 0.0
				var bounce := Color(0, 0, 0)
				for a in AZIMUTHS:
					var sin_max := 0.0
					for hit: Array in near[a]:
						var rise: float = hit[1] - h
						if rise <= 0.0:
							continue
						var sn: float = rise / sqrt(rise * rise + hit[0] * hit[0])
						if sn > sin_max:
							bounce += colors[hit[2]] * ((sn - sin_max) * facing[a] * lit[hit[2]])
							sin_max = sn
					sky += 1.0 - sin_max
				sky /= AZIMUTHS
				# Each direction's slice of the upper hemisphere, weighted toward the horizon it was seen at.
				bounce *= ALBEDO * ENCODE * 255.0 * 2.0 / AZIMUTHS
				px[o] = clampi(roundi(bounce.r), 0, 255)
				px[o + 1] = clampi(roundi(bounce.g), 0, 255)
				px[o + 2] = clampi(roundi(bounce.b), 0, 255)
				px[o + 3] = clampi(roundi(sky * 255.0), 0, 255)
	return {"area": area, "layers": layers}


## Per built column a probe in `area` can see, whether the sun reaches its faces at their middle height
## past the builds between it and the sun.
static func _lit(tops: PackedFloat32Array, ground: PackedFloat32Array, sun_flat: Vector2, sun_rise: float, area: Rect2i) -> PackedFloat32Array:
	var lit := PackedFloat32Array()
	lit.resize(CELLS * CELLS)
	var reach := area.grow(REACH).intersection(AREA)
	for j in range(reach.position.y, reach.end.y):
		for i in range(reach.position.x, reach.end.x):
			var at := j * CELLS + i
			if tops[at] == -INF:
				continue
			var mid := (tops[at] + ground[at]) * 0.5
			lit[at] = 1.0
			for s in range(1, SUN_WALK + 1):
				var p := Vector2(i + 0.5, j + 0.5) + sun_flat * s
				var q := Vector2i(floori(p.x), floori(p.y))
				if not AREA.has_point(q):
					break
				if tops[q.y * CELLS + q.x] > mid + sun_rise * s * Terrain.STEP:
					lit[at] = 0.0
					break
	return lit
