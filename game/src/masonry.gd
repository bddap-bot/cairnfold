class_name Masonry
extends Node3D

## Settled pieces of every build, drawn per ground chunk: one MultiMesh per kind of piece per chunk, so a
## glade full of walls costs a few draw calls per chunk rather than several per wall, and a chunk out of
## view is culled whole. Pieces still changing (a wall being drawn or pulled, ivy still growing) stay with
## their owner until they settle.

## A chunk is also the step of culling and of reach: the renderer culls a chunk's MultiMesh as a whole, by its
## bounds, so each piece goes to the chunk under it, however long the wall it belongs to. A chunk any of whose pieces
## may stand near draws both its near and its far instance, each of them the pieces on its own side of the near
## distance from the eye (`piece_range`, piece.gdshaderinc): drawn whole a chunk at a time, the near meshes of every
## piece within a chunk's diagonal of the eye cost the Quest 2 most of its masonry's time among houses. Every chunk
## drawn costs a draw call, so a kind cut by distance (`Kind.ranged`) is chunked by FINE, and its far mesh is drawn by
## COARSE chunks once a whole one is past the near distance; the rest, drawn at every distance, by COARSE (see "What
## walls cost the Quest 2" in docs/design.md).
const FINE := 8.0
const COARSE := 16.0
## How tall a chunk's pieces are taken to stand when its draw distances allow for its size; a taller build's top
## swaps to its far mesh a little early.
const TALL := 9.0

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
	## Drawn instead of `mesh` for a settled piece beyond `near` metres of the eye; null to draw `mesh` at every distance.
	var far: Mesh
	## What `far` is drawn in; null to draw it in `material`.
	var far_material: Material
	## What a baked far chunk is drawn in (`bake`): `far_material`'s or `material`'s shader built with BAKED.
	var far_baked: Material
	var _far_surface: Array = []
	var near := 0.0
	## The longest a piece of it is laid, in metres: its mesh's level of detail is keyed in the mesh's own units
	## (Meshes.lod_error), so a chunk scales that key by it and swaps none sooner than its error allows.
	var size := 1.0

	func _init(m: Mesh, mat: Material, use_colors: bool, use_custom: bool, cast: GeometryInstance3D.ShadowCastingSetting, occluding := false) -> void:
		assert(use_colors or not occluding, "occluding pieces carry colours")
		mesh = m
		material = mat
		colors = use_colors
		custom = use_custom
		shadow = cast
		occludes = occluding

	## `far`'s vertices, normals and indices, read once on the main thread so `bake` can run on a worker.
	func far_surface() -> Array:
		if _far_surface.is_empty():
			var a := far.surface_get_arrays(0)
			_far_surface = [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_INDEX]]
		return _far_surface

	func stride() -> int:
		return 12 + (4 if colors else 0) + (4 if custom else 0)

	## Whether it is drawn only so far, or coarser beyond a distance.
	func ranged() -> bool:
		return far != null or reach > 0.0

	## The side of its chunks, in metres.
	func cell() -> float:
		return FINE if ranged() else COARSE

	## How far its pieces reach from the centre of a chunk's bounds, where the renderer measures its distance: half
	## the diagonal of a chunk holding the tallest wall on flat ground. A roof or slope standing higher can switch its
	## top stones to the far mesh a little inside the near distance, which only the ladder's lowest steps ever bring
	## close.
	func radius() -> float:
		return Masonry.radius(cell())

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
		mmi.lod_bias = size
		return mmi


## One kind's pieces in one chunk.
class Chunk:
	var instance: MultiMeshInstance3D
	## Its far instance, null for a kind without one.
	var far: MultiMeshInstance3D
	## Its whole instance for a photo, sharing `instance`'s multimesh at every distance (Quality.FULL_LAYER), null
	## for a kind drawn whole anyway.
	var full: MultiMeshInstance3D
	## Owner id -> its buffer.
	var parts := {}


var kinds: Array[Kind]
## (chunk x, chunk z, kind) -> Chunk.
var _chunks := {}
var _dirty := {}
## Instances placed, by kind, kept as they are placed.
var _counts := PackedInt32Array()
## Coarse chunks whose fine chunks were drawn again since they were.
var _coarse_dirty := {}
## Owner id -> the chunks holding its pieces.
var _owners := {}
## (COARSE chunk x, z, kind) -> the far instance of the FINE chunks under it of a kind with a far mesh, drawn in their
## place once the whole COARSE chunk is past the near distance. Each FINE chunk's near and far instances draw only
## while it is not (`visibility_parent`), so no piece is drawn twice or missed.
var _coarse := {}
## Whether COARSE far chunks are baked into one mesh each (`bake`): settled masonry only, a live wall's changing
## every frame.
var _bakes := false
## COARSE key -> [the worker task baking it, an array its mesh arrays land in]; and the buffer to bake next for a key
## whose pieces changed while it baked.
var _baking := {}
var _rebake := {}


func _init(piece_kinds: Array[Kind], baked := false) -> void:
	kinds = piece_kinds
	_bakes = baked
	_counts.resize(kinds.size())
	set_process(false)


## Splits a buffer of `kind`'s instances by the chunk under each: chunk key -> buffer. Reads nothing but its
## arguments, so it runs on a worker thread.
static func split(buf: PackedFloat32Array, kind: Kind) -> Dictionary:
	var out := {}
	var stride := kind.stride()
	var cell := kind.cell()
	var start := 0
	var run := Vector2i.ZERO
	for i in range(0, buf.size(), stride):
		var key := Vector2i(floori(buf[i + 3] / cell), floori(buf[i + 11] / cell))
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


## Draws `parts` (per kind, in `kinds` order, a `split` buffer) for `owner`, replacing what it had placed before. Only
## the chunks whose pieces changed are drawn again, and the light is told only when its occluders changed.
func place(owner: int, parts: Array[Dictionary]) -> void:
	assert(parts.size() == kinds.size(), "one split buffer per kind")
	var keys := {}
	for k in kinds.size():
		for key: Vector2i in parts[k]:
			keys[Vector3i(key.x, key.y, k)] = true
	var occluders := false
	var none := PackedFloat32Array()
	for key: Vector3i in keys.keys() + Array(_owners.get(owner, [])):
		var c := _chunk(key)
		var now: PackedFloat32Array = parts[key.z].get(Vector2i(key.x, key.y), none)
		var was: PackedFloat32Array = c.parts.get(owner, none)
		if now != was:
			_dirty[key] = true
			occluders = occluders or kinds[key.z].occludes
		if keys.has(key):
			_counts[key.z] += (now.size() - was.size()) / kinds[key.z].stride()
			c.parts[owner] = now
		elif c.parts.erase(owner):
			_counts[key.z] -= was.size() / kinds[key.z].stride()
	if keys.is_empty():
		_owners.erase(owner)
	else:
		_owners[owner] = keys.keys()
	if not _dirty.is_empty():
		set_process(true)
	if not occluders or placed.get_connections().is_empty():
		return
	var buffers: Array[PackedFloat32Array] = []
	var strides := PackedInt32Array()
	for k in kinds.size():
		if kinds[k].occludes and not parts[k].is_empty():
			var all := PackedFloat32Array()
			for buf in parts[k].values():
				all.append_array(buf)
			buffers.append(all)
			strides.append(kinds[k].stride())
	placed.emit(owner, buffers, strides)


func remove(owner: int) -> void:
	var none: Array[Dictionary] = []
	none.resize(kinds.size())
	none.fill({})
	place(owner, none)


static func radius(cell: float) -> float:
	return sqrt(cell * cell * 2.0 + TALL * TALL) * 0.5


static func _coarse_key(key: Vector3i) -> Vector3i:
	var n := roundi(COARSE / FINE)
	return Vector3i(floori(float(key.x) / n), floori(float(key.y) / n), key.z)


## Instances placed, by kind: what the build costs to render.
func counts() -> PackedInt32Array:
	return _counts.duplicate()


## The instances drawing `kind`'s pieces near or far, for measuring what each costs.
func parts(kind: int, near: bool, far: bool) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for key: Vector3i in _chunks:
		if key.z == kind:
			var c: Chunk = _chunks[key]
			if near:
				out.append(c.instance)
			if far and c.far != null:
				out.append(c.far)
	if far:
		for key: Vector3i in _coarse:
			if key.z == kind:
				out.append(_coarse[key])
	return out


func _chunk(key: Vector3i) -> Chunk:
	if not _chunks.has(key):
		var k := kinds[key.z]
		var c := Chunk.new()
		c.instance = k.instance()
		add_child(c.instance)
		if k.far != null:
			c.far = k.instance()
			c.far.multimesh.mesh = k.far
			if k.far_material != null:
				c.far.material_override = k.far_material
			add_child(c.far)
			var parent := _coarse_far(_coarse_key(key))
			c.far.visibility_parent = NodePath("../" + parent.name)
			c.instance.visibility_parent = c.far.visibility_parent
		if k.ranged():
			c.instance.layers = Quality.LADDER_LAYER
			if c.far != null:
				c.far.layers = Quality.LADDER_LAYER
			c.full = k.instance()
			c.full.multimesh = c.instance.multimesh
			c.full.layers = Quality.FULL_LAYER
			add_child(c.full)
		_chunks[key] = c
		_ranges(key)
	return _chunks[key]


func _coarse_far(key: Vector3i) -> MultiMeshInstance3D:
	if not _coarse.has(key):
		var k := kinds[key.z]
		var far := k.instance()
		far.multimesh.mesh = k.far
		if k.far_material != null:
			far.material_override = k.far_material
		far.layers = Quality.LADDER_LAYER
		far.name = "Far_%d_%d_%d" % [key.x, key.y, key.z]
		add_child(far)
		if _bakes and k.far_baked != null:
			k.far_surface()
			var baked := MeshInstance3D.new()
			baked.name = "Baked"
			baked.top_level = true
			baked.material_override = k.far_baked
			baked.cast_shadow = far.cast_shadow
			baked.layers = far.layers
			baked.visible = false
			far.add_child(baked)
		_coarse[key] = far
		_coarse_ranges(key)
	return _coarse[key]


## Puts every chunk's instances within its kind's reach and near distance, after either changed.
func set_ranges() -> void:
	for key: Vector3i in _chunks:
		_ranges(key)
	for key: Vector3i in _coarse:
		_coarse_ranges(key)


func _coarse_ranges(key: Vector3i) -> void:
	var kind := kinds[key.z]
	var baked := _baked(key)
	for g: GeometryInstance3D in [_coarse[key], baked] if baked != null else [_coarse[key]]:
		g.visibility_range_begin = kind.near + radius(COARSE)
		g.visibility_range_end = kind.reach + radius(COARSE) if kind.reach > 0.0 else 0.0


func _baked(key: Vector3i) -> MeshInstance3D:
	return _coarse[key].get_node_or_null(^"Baked")


func _ranges(key: Vector3i) -> void:
	var c: Chunk = _chunks[key]
	var kind := kinds[key.z]
	var end := kind.reach + kind.radius() if kind.reach > 0.0 else 0.0
	if c.far == null:
		c.instance.visibility_range_end = end
	else:
		c.instance.visibility_range_end = kind.near + kind.radius()
		c.instance.set_instance_shader_parameter(&"piece_range", Vector2(0.0, kind.near))
		c.far.set_instance_shader_parameter(&"piece_range", Vector2(kind.near, 1.0e30))
		c.far.visibility_range_end = end


func _process(_delta: float) -> void:
	for key: Vector3i in _baking.keys():
		var task: Array = _baking[key]
		if not WorkerThreadPool.is_task_completed(task[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(task[0])
		_baking.erase(key)
		if _rebake.has(key):
			_start_bake(key, _rebake[key])
			_rebake.erase(key)
		else:
			_show_baked(key, task[1][0])
	flush(Budget.MASONRY_FLUSH_US)


func _exit_tree() -> void:
	for key: Vector3i in _baking:
		WorkerThreadPool.wait_for_task_completion(_baking[key][0])
		_coarse_dirty[key] = true
	_baking.clear()
	_rebake.clear()


## Whether every chunk holding `owner`'s pieces is drawn as they stand.
func drawn(owner: int) -> bool:
	for key: Vector3i in _owners.get(owner, []):
		if _dirty.has(key) or _coarse_dirty.has(_coarse_key(key)):
			return false
	return true


## Draws the chunks changed since, all of them, or with `budget_us` as many as fit that many microseconds (one at
## least) and the rest in the frames after: each chunk swaps its stones whole, so none blink out between.
func flush(budget_us := INF) -> void:
	var start := Time.get_ticks_usec()
	for key: Vector3i in _dirty.keys():
		if Budget.over(start, budget_us):
			break
		_dirty.erase(key)
		var c: Chunk = _chunks[key]
		_ranges(key)
		var buf := PackedFloat32Array()
		for part: PackedFloat32Array in c.parts.values():
			buf.append_array(part)
		for mmi: MultiMeshInstance3D in [c.instance, c.far]:
			if mmi == null:
				continue
			var mm := mmi.multimesh
			mm.instance_count = buf.size() / kinds[key.z].stride()
			if mm.instance_count > 0:
				mm.buffer = buf
		if c.far != null:
			_coarse_dirty[_coarse_key(key)] = true
	var n := roundi(COARSE / FINE)
	for key: Vector3i in _coarse_dirty.keys():
		if Budget.over(start, budget_us):
			break
		_coarse_dirty.erase(key)
		var buf := PackedFloat32Array()
		for x in n:
			for z in n:
				var c: Chunk = _chunks.get(Vector3i(key.x * n + x, key.y * n + z, key.z))
				if c != null:
					for part: PackedFloat32Array in c.parts.values():
						buf.append_array(part)
		var mm: MultiMesh = _coarse[key].multimesh
		mm.instance_count = buf.size() / kinds[key.z].stride()
		if mm.instance_count > 0:
			mm.buffer = buf
		if _baked(key) != null:
			_show_baked(key, [])
			if _baking.has(key):
				_rebake[key] = buf
			else:
				_start_bake(key, buf)
	set_process(not _dirty.is_empty() or not _coarse_dirty.is_empty() or not _baking.is_empty())


func _start_bake(key: Vector3i, buf: PackedFloat32Array) -> void:
	var kind := kinds[key.z]
	var out := []
	_baking[key] = [WorkerThreadPool.add_task(func() -> void: out.append(bake(buf, kind))), out]


## Draws COARSE chunk `key` from its baked `arrays` (`bake`), or while they are empty, from its instances: the baked
## mesh stands in for them only once it holds every piece they do.
func _show_baked(key: Vector3i, arrays: Array) -> void:
	var baked := _baked(key)
	var mm: MultiMesh = _coarse[key].multimesh
	if arrays.is_empty() or mm.instance_count == 0:
		baked.visible = false
		baked.mesh = null
		mm.visible_instance_count = -1
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays[0], [], {}, BAKED_FORMAT)
	mesh.custom_aabb = arrays[1]
	baked.mesh = mesh
	baked.visible = true
	mm.visible_instance_count = 0


const BAKED_FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)


## `buf`'s pieces of `kind` as one mesh of its far mesh, [Mesh arrays, their bounds]: each vertex carries its piece's
## frame and custom data (piece.gdshaderinc), so the chunk draws without instancing. On the Quest 2, with the fixed
## foveation map applied, every tile of the frame shades every instanced vertex in view, so far masonry cost the
## frame several times its unfoveated price; baked, it shades only what each tile holds ("Far masonry under the
## foveation map" in docs/design.md). Reads nothing but its arguments, so it runs on a worker thread.
static func bake(buf: PackedFloat32Array, kind: Kind) -> Array:
	assert(kind.colors and kind.custom, "a baked piece carries its colour and custom data")
	var surface := kind.far_surface()
	var sv: PackedVector3Array = surface[0]
	var sn: PackedVector3Array = surface[1]
	var si: PackedInt32Array = surface[2]
	var stride := kind.stride()
	var n := buf.size() / stride
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var idx := PackedInt32Array()
	var custom: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	verts.resize(n * sv.size())
	normals.resize(verts.size())
	colours.resize(verts.size())
	idx.resize(n * si.size())
	for c in custom:
		c.resize(verts.size() * 4)
	var bounds := AABB()
	for i in n:
		var o := i * stride
		var frame := Transform3D(Basis(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]), Vector3(buf[o + 2], buf[o + 6], buf[o + 10])), Vector3(buf[o + 3], buf[o + 7], buf[o + 11]))
		var colour := Color(buf[o + 12], buf[o + 13], buf[o + 14], buf[o + 15])
		var rows := [PackedFloat32Array([buf[o], buf[o + 1], buf[o + 2], buf[o + 3]]), PackedFloat32Array([buf[o + 4], buf[o + 5], buf[o + 6], buf[o + 7]]), PackedFloat32Array([buf[o + 8], buf[o + 9], buf[o + 10], buf[o + 11]]), PackedFloat32Array([buf[o + 16], buf[o + 17], buf[o + 18], buf[o + 19]])]
		var base := i * sv.size()
		for j in sv.size():
			var v := base + j
			verts[v] = sv[j]
			normals[v] = sn[j]
			colours[v] = colour
			for c in 4:
				for e in 4:
					custom[c][v * 4 + e] = rows[c][e]
			var at := frame * sv[j]
			bounds = AABB(at, Vector3.ZERO) if i == 0 and j == 0 else bounds.expand(at)
		for j in si.size():
			idx[i * si.size() + j] = base + si[j]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_CUSTOM0] = custom[0]
	arrays[Mesh.ARRAY_CUSTOM1] = custom[1]
	arrays[Mesh.ARRAY_CUSTOM2] = custom[2]
	arrays[Mesh.ARRAY_CUSTOM3] = custom[3]
	arrays[Mesh.ARRAY_INDEX] = idx
	return [arrays, bounds]

