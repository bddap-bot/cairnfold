class_name Masonry
extends Node3D

## Settled pieces of every build, drawn per ground chunk: one MultiMesh per kind of piece per chunk, so a
## glade full of walls costs a few draw calls per chunk rather than several per wall, and a chunk out of
## view is culled whole. Pieces still changing (a wall being drawn or pulled, ivy still growing) stay with
## their owner until they settle.

## A chunk is also the step of culling and of level of detail: the renderer picks both for a chunk's
## MultiMesh as a whole, by its bounds.
const CHUNK_METRES := 16.0

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
	func write(buf: PackedFloat32Array, n: int, x: Transform3D, color := Color.WHITE, occlusion := 1.0, material := 0.0) -> void:
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
	## Owner id -> one buffer per kind.
	var parts := {}


var kinds: Array[Kind]
var _chunks := {}
var _dirty := {}
## Owner id -> the chunk holding its pieces.
var _owners := {}


func _init(piece_kinds: Array[Kind]) -> void:
	kinds = piece_kinds
	set_process(false)


## Draws `parts` (one buffer per kind, in `kinds` order) for `owner` in the chunk under `at`, replacing what
## it had placed before. An owner stays whole in one chunk, so placing it splits no buffer.
func place(owner: int, at: Vector3, parts: Array[PackedFloat32Array]) -> void:
	assert(parts.size() == kinds.size(), "one buffer per kind")
	var had := _drop(owner)
	var buffers: Array[PackedFloat32Array] = []
	var strides := PackedInt32Array()
	for k in kinds.size():
		if kinds[k].occludes and not parts[k].is_empty():
			buffers.append(parts[k])
			strides.append(kinds[k].stride())
	if had or not buffers.is_empty():
		placed.emit(owner, buffers, strides)
	if parts.all(func(b: PackedFloat32Array) -> bool: return b.is_empty()):
		return
	var key := Vector2i(floori(at.x / CHUNK_METRES), floori(at.z / CHUNK_METRES))
	_chunk(key).parts[owner] = parts
	_owners[owner] = key
	_dirty[key] = true
	set_process(true)


func remove(owner: int) -> void:
	if _drop(owner):
		placed.emit(owner, [] as Array[PackedFloat32Array], PackedInt32Array())


## Takes away what `owner` had placed; false if it had nothing.
func _drop(owner: int) -> bool:
	if not _owners.has(owner):
		return false
	var key: Vector2i = _owners[owner]
	_chunks[key].parts.erase(owner)
	_owners.erase(owner)
	_dirty[key] = true
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
		_chunks[key] = c
	return _chunks[key]


func _process(_delta: float) -> void:
	for key in _dirty:
		var c: Chunk = _chunks[key]
		for k in kinds.size():
			var buf := PackedFloat32Array()
			for parts in c.parts.values():
				buf.append_array(parts[k])
			var mm := c.instances[k].multimesh
			mm.instance_count = buf.size() / kinds[k].stride()
			if mm.instance_count > 0:
				mm.buffer = buf
	_dirty.clear()
	set_process(false)
