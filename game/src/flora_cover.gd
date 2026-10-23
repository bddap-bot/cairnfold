class_name FloraCover
extends RefCounted

## The grass past the reach its clumps are drawn to, as the ground's shader paints it (terrain.gdshader): a texel per
## ground vertex (Terrain's grid, as its height texture is) holds a clump standing in the square around it, as what its
## tint and shade make of the ground's own grass colour, which takes the meadow's dryness already. Colour is
## premultiplied by presence in alpha, an empty square changing nothing. The ground's vertices carry it into the
## meadow colour they already hand their fragments, so the distant meadow costs the Quest 2 no fragment work, where a
## triangle a clump cost it 1.9 ms over the bare meadow from the air, and the factor read once a fragment 0.2 to 0.4 ms.
## Where two clumps share a square, the one in the higher slot shows.
## How often a painted or mown clump reaches the texture: what changes is near the hand, inside the clumps' reach.
const FLUSH_MSEC := 250

var size := Terrain.VERTS
var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
var texture := ImageTexture.create_from_image(image)
## Each slot's texel, set as its clump is added.
var looks := PackedColorArray()
var _dirty := {}
var _whole := true
var _flushed := -FLUSH_MSEC


func _init(capacity: int) -> void:
	looks.resize(capacity)
	RenderingServer.global_shader_parameter_set(&"flora_grass", texture)


## What a clump of this colour and custom data (as Pool.add takes them) puts in its texel: the factor its tint
## (meadow.gdshaderinc's blade_top), at the ground's canopy height, and its shade make of the ground's colour, halved.
static func look(color: Color, custom: Color) -> Color:
	var cool: Color = Meadow.GRASS[&"cool_clump"]
	var warm: Color = Meadow.GRASS[&"warm_clump"]
	var tint := cool.lerp(warm, custom.g) / cool.lerp(warm, 0.5)
	var f := (Color.WHITE + (tint - Color.WHITE) * Meadow.CANOPY) * color.r * 0.5
	return Color.hex(Color(f.r, f.g, f.b, 1.0).to_rgba32())


func touch(at: Vector3) -> void:
	_dirty[Terrain.grid_point(at.x, at.z)] = true


func touch_all() -> void:
	_whole = true


## Paints what changed in `pool`, the pool this cover was made for.
func flush(pool: Flora.Pool) -> void:
	if not _whole and _dirty.is_empty():
		return
	# Squares are found again a grid square of the pool's at a time; a filled disc repaints faster whole.
	if _whole or _dirty.size() * 16 > pool.size():
		image.fill(Color(0, 0, 0, 0))
		for i in pool.size():
			var p: Flora.Plant = pool.plants[i]
			if _stands(p):
				image.set_pixelv(Terrain.grid_point(p.anchor.x, p.anchor.z), looks[i])
	else:
		# Each grid square under a dirty texel is read once, not once for each texel it holds.
		var best := {}
		var squares := {}
		var reach := Vector3(Terrain.STEP, 0, Terrain.STEP)
		for t: Vector2i in _dirty:
			best[t] = -1
			var centre := Vector3(t.x * Terrain.STEP - Terrain.SIZE * 0.5, 0, t.y * Terrain.STEP - Terrain.SIZE * 0.5)
			var lo := Flora.Pool.square(centre - reach)
			var hi := Flora.Pool.square(centre + reach)
			for j in range(lo.y, hi.y + 1):
				for i in range(lo.x, hi.x + 1):
					squares[Vector2i(i, j)] = true
		for square: Vector2i in squares:
			for slot: int in pool.in_square(square):
				var t := Terrain.grid_point(pool.anchors[slot].x, pool.anchors[slot].z)
				if best.has(t) and slot > best[t] and _stands(pool.plants[slot]):
					best[t] = slot
		for t: Vector2i in best:
			image.set_pixelv(t, looks[best[t]] if best[t] >= 0 else Color(0, 0, 0, 0))
	_whole = false
	_dirty.clear()
	texture.update(image)
	_flushed = Time.get_ticks_msec()


## Flushes once FLUSH_MSEC has passed since the last.
func settle(pool: Flora.Pool) -> void:
	if Time.get_ticks_msec() - _flushed >= FLUSH_MSEC:
		flush(pool)


func _stands(p: Flora.Plant) -> bool:
	return p != null and p.shown() and p.drawn and not p.rock
