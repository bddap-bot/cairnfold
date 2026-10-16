class_name Masonry
extends Node3D

## Settled pieces of every build, drawn per ground chunk: one MultiMesh per kind of piece per chunk, so a
## glade full of walls costs a few draw calls per chunk rather than several per wall, and a chunk out of
## view is culled whole. Pieces still changing (a wall being drawn or pulled, ivy still growing) stay with
## their owner until they settle.

## A chunk is also the step of culling and of reach: the renderer culls a chunk's MultiMesh as a whole, by its
## bounds, so each piece goes to the chunk under it, however long the wall it belongs to.
const CHUNK_METRES := 16.0
## How far a chunk's pieces reach from the centre of its bounds, where the renderer measures its distance: half its
## diagonal, with room for slopes and what stands on them.
const CHUNK_RADIUS := CHUNK_METRES * 0.8

## An owner's pieces that stand in the light (`Kind.occludes`) changed: their buffers and strides, empty
## once it is gone.
signal placed(owner: int, buffers: Array[PackedFloat32Array], strides: PackedInt32Array)


## How one kind of piece is drawn. An instance is 12 transform floats, then 4 colour floats and 4 custom
## floats (occlusion, then the code of its palette material) when the kind uses them.
class Kind:
	var mesh: Mesh
	var material: Material
	var colors: bool
	var custom: bool
	var shadow: GeometryInstance3D.ShadowCastingSetting
	## Whether its pieces shade the light around them (Bounce); such a kind uses colours.
	var occludes: bool
	## Metres beyond which a piece is not seen, so a settled chunk wholly past it is not drawn; 0 for no limit.
	var reach := 0.0
	## Drawn instead of `mesh` by a settled chunk wholly beyond `near` metres; null to draw `mesh` at every distance.
	var far: Mesh
	var near := 0.0

	func _init(m: Mesh, mat: Material, use_colors: bool, use_custom: bool, cast: GeometryInstance3D.ShadowCastingSetting, occluding := false) -> void:
		assert(use_colors or not occluding, "occluding pieces carry colours")
		mesh = m
		material = mat
		colors = use_colors
		custom = use_custom
		shadow = cast
		occludes = occluding

	func stride() -> int:
		return 12 + (4 if colors else 0) + (4 if custom else 0)

	## Writes instance `n` of `buf`.
	func write(buf: PackedFloat32Array, n: int, x: Transform3D, color := Color.WHITE, occlusion := 1.0, material := 0.0, ends := Vector2.ZERO) -> void:
		var i := n * stride()
		var b := x.basis
		buf[i] = b.x.x
		buf[i + 1] = b.y.x
		buf[i + 2] = b.z.x
		buf[i + 3] = x.origin.x
		buf[i + 4] = b.x.y
		buf[i + 5] = b.y.y
		buf[i + 6] = b.z.y
		buf[i + 7] = x.origin.y
		buf[i + 8] = b.x.z
		buf[i + 9] = b.y.z
		buf[i + 10] = b.z.z
		buf[i + 11] = x.origin.z
		if colors:
			buf[i + 12] = color.r
			buf[i + 13] = color.g
			buf[i + 14] = color.b
			buf[i + 15] = color.a
		if custom:
			buf[i + 16] = occlusion
			buf[i + 17] = material
			buf[i + 18] = ends.x
			buf[i + 19] = ends.y

	func instance() -> MultiMeshInstance3D:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = colors
		mm.use_custom_data = custom
		mm.mesh = mesh
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = material
		mmi.cast_shadow = shadow
		return mmi


class Chunk:
	var instances: Array[MultiMeshInstance3D] = []
	## Each kind's far instance, null for a kind without one.
	var fars: Array[MultiMeshInstance3D] = []
	## Owner id -> one buffer per kind.
	var parts := {}


var kinds: Array[Kind]
var _chunks := {}
var _dirty := {}
## Owner id -> the chunks holding its pieces.
var _owners := {}


func _init(piece_kinds: Array[Kind]) -> void:
	kinds = piece_kinds
	set_process(false)


## Splits a buffer of instances `stride` floats long by the chunk under each: chunk key -> buffer. Reads nothing
## but its arguments, so it runs on a worker thread.
static func split(buf: PackedFloat32Array, stride: int) -> Dictionary:
	var out := {}
	var start := 0
	var run := Vector2i.ZERO
	for i in range(0, buf.size(), stride):
		var key := Vector2i(floori(buf[i + 3] / CHUNK_METRES), floori(buf[i + 11] / CHUNK_METRES))
		if i > start and key != run:
			_gather(out, run, buf.slice(start, i))
			start = i
		run = key
	if buf.size() > start:
		_gather(out, run, buf.slice(start))
	return out


static func _gather(out: Dictionary, key: Vector2i, buf: PackedFloat32Array) -> void:
	var have: PackedFloat32Array = out.get(key, PackedFloat32Array())
	have.append_array(buf)
	out[key] = have


## Draws `parts` (per kind, in `kinds` order, a `split` buffer) for `owner`, replacing what it had placed before.
func place(owner: int, parts: Array[Dictionary]) -> void:
	assert(parts.size() == kinds.size(), "one split buffer per kind")
	var had := _drop(owner)
	var buffers: Array[PackedFloat32Array] = []
	var strides := PackedInt32Array()
	for k in kinds.size():
		if kinds[k].occludes and not parts[k].is_empty():
			var all := PackedFloat32Array()
			for buf in parts[k].values():
				all.append_array(buf)
			buffers.append(all)
			strides.append(kinds[k].stride())
	if had or not buffers.is_empty():
		placed.emit(owner, buffers, strides)
	var keys := {}
	for k in kinds.size():
		for key in parts[k]:
			var c := _chunk(key)
			if not c.parts.has(owner):
				var bufs: Array[PackedFloat32Array] = []
				bufs.resize(kinds.size())
				c.parts[owner] = bufs
			c.parts[owner][k] = parts[k][key]
			keys[key] = true
			_dirty[key] = true
	if keys.is_empty():
		return
	_owners[owner] = keys.keys()
	set_process(true)


func remove(owner: int) -> void:
	if _drop(owner):
		placed.emit(owner, [] as Array[PackedFloat32Array], PackedInt32Array())


## Takes away what `owner` had placed; false if it had nothing.
func _drop(owner: int) -> bool:
	if not _owners.has(owner):
		return false
	for key in _owners[owner]:
		_chunks[key].parts.erase(owner)
		_dirty[key] = true
	_owners.erase(owner)
	set_process(true)
	return true


## Instances placed, by kind: what the build costs to render.
func counts() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(kinds.size())
	for c in _chunks.values():
		for parts in c.parts.values():
			for k in kinds.size():
				out[k] += parts[k].size() / kinds[k].stride()
	return out


func _chunk(key: Vector2i) -> Chunk:
	if not _chunks.has(key):
		var c := Chunk.new()
		for k in kinds:
			var mmi := k.instance()
			c.instances.append(mmi)
			add_child(mmi)
			var far: MultiMeshInstance3D = null
			if k.far != null:
				far = k.instance()
				far.multimesh.mesh = k.far
				add_child(far)
			c.fars.append(far)
		_chunks[key] = c
		_ranges(c)
	return _chunks[key]


## Puts every chunk's instances of each kind within its reach and its near distance, after either changed.
func set_ranges() -> void:
	for c in _chunks.values():
		_ranges(c)


func _ranges(c: Chunk) -> void:
	for k in kinds.size():
		var kind := kinds[k]
		var end := kind.reach + CHUNK_RADIUS if kind.reach > 0.0 else 0.0
		if c.fars[k] == null:
			c.instances[k].visibility_range_end = end
		else:
			var split := kind.near + CHUNK_RADIUS
			c.instances[k].visibility_range_end = split
			c.fars[k].visibility_range_begin = split
			c.fars[k].visibility_range_end = end


func _process(_delta: float) -> void:
	for key in _dirty:
		var c: Chunk = _chunks[key]
		for k in kinds.size():
			var buf := PackedFloat32Array()
			for parts in c.parts.values():
				buf.append_array(parts[k])
			for mmi in [c.instances[k], c.fars[k]]:
				if mmi == null:
					continue
				var mm: MultiMesh = mmi.multimesh
				mm.instance_count = buf.size() / kinds[k].stride()
				if mm.instance_count > 0:
					mm.buffer = buf
	_dirty.clear()
	set_process(false)
