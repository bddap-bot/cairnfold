class_name Masonry
extends Node3D

## Settled pieces, one MultiMesh per kind per ground chunk, so a glade of walls costs a few draw calls per chunk. A near
## chunk draws near and far meshes, each only its side of the near distance (`piece_range`): whole near chunks cost the
## Quest 2 most of its masonry time among houses ("What walls cost the Quest 2", docs/design.md).

const FINE := 8.0
const COARSE := 16.0
const FINE_PER_COARSE := int(COARSE / FINE)
## Assumed height of a chunk's pieces in its draw distances; a taller build's top swaps to its far mesh early.
const TALL := 9.0

## An owner's occluding pieces changed; empty arrays once it is gone.
signal placed(owner: int, buffers: Array[PackedFloat32Array], strides: PackedInt32Array)


## An instance is 12 transform floats (basis rows with origin), then when used 4 colour floats and 4 custom floats:
## occlusion, palette material code, the turn of its -x end, the turn of its +x end (stone.gdshaderinc).
class Kind:
	var mesh: Mesh
	var material: Material
	var colors: bool
	var custom: bool
	var shadow: GeometryInstance3D.ShadowCastingSetting
	var occludes: bool
	## Metres beyond which a piece is not drawn; 0 for no limit.
	var reach := 0.0
	## Beyond `near` metres; null for `mesh` at every distance.
	var far: Mesh
	## Null to draw `far` in `material`.
	var far_material: Material
	var far_baked: Material
	var _far_surface: Array = []
	var near := 0.0
	## Longest piece laid, metres: LOD is keyed in the mesh's own units (Meshes.lod_error), so it is the lod_bias.
	var size := 1.0

	func _init(m: Mesh, mat: Material, use_colors: bool, use_custom: bool, cast: GeometryInstance3D.ShadowCastingSetting, occluding := false) -> void:
		assert(use_colors or not occluding, "occluding pieces carry colours")
		mesh = m
		material = mat
		colors = use_colors
		custom = use_custom
		shadow = cast
		occludes = occluding

	## [vertices, normals, indices], read once on the main thread so `bake` can run on a worker.
	func far_surface() -> Array:
		if _far_surface.is_empty():
			var a := far.surface_get_arrays(0)
			_far_surface = [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_INDEX]]
		return _far_surface

	func stride() -> int:
		return 12 + (4 if colors else 0) + (4 if custom else 0)

	func fill(mm: MultiMesh, buf: PackedFloat32Array) -> void:
		mm.instance_count = buf.size() / stride()
		if mm.instance_count > 0:
			mm.buffer = buf

	func ranged() -> bool:
		return far != null or reach > 0.0

	func cell() -> float:
		return FINE if ranged() else COARSE

	## The renderer measures distance from a chunk's bounds' centre.
	func radius() -> float:
		return Masonry.radius(cell())

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

	func far_instance() -> MultiMeshInstance3D:
		var mmi := instance()
		mmi.multimesh.mesh = far
		if far_material != null:
			mmi.material_override = far_material
		return mmi


class Chunk:
	var instance: MultiMeshInstance3D
	## Null for a kind without a far mesh.
	var far: MultiMeshInstance3D
	## `instance`'s multimesh at every distance, for a photo; null for an unranged kind.
	var full: MultiMeshInstance3D
	## Owner id -> its buffer.
	var parts := {}


var kinds: Array[Kind]
## (chunk x, chunk z, kind) -> Chunk.
var _chunks := {}
var _dirty := {}
var _counts := PackedInt32Array()
var _coarse_dirty := {}
## Owner id -> the chunks holding its pieces.
var _owners := {}
## (COARSE x, z, kind) -> the far instance standing in for its FINE chunks' once wholly past the near distance.
var _coarse := {}
var _bakes := false
## How the build drawing these pieces is carried from where it was laid (carried.gdshaderinc).
var carry := Transform3D.IDENTITY:
	set(to):
		carry = to
		for c: Chunk in _chunks.values():
			_show_carry([c.instance, c.far, c.full])
		_show_carry(_coarse.values())
## COARSE key -> [worker task id, array its `bake` result lands in].
var _baking := {}
var _rebake := {}


func _init(piece_kinds: Array[Kind], baked := false) -> void:
	kinds = piece_kinds
	_bakes = baked
	_counts.resize(kinds.size())
	set_process(false)


## Chunk key -> that chunk's instances of `buf`. Reads only its arguments, so it runs on a worker thread.
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


static func build_owner(id: int) -> int:
	return -1 - id


## `parts`: one `split` result per kind, in `kinds` order; replaces what `owner` placed before. Unless `announce` is
## false, `placed` tells of its occluding pieces; a wall tells of its own as each lay lands.
func place(owner: int, parts: Array[Dictionary], announce := true) -> void:
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
	if occluders and announce:
		var flat: Array[PackedFloat32Array] = []
		for k in kinds.size():
			var all := PackedFloat32Array()
			for buf in parts[k].values():
				all.append_array(buf)
			flat.append(all)
		tell(owner, flat)


## Emits `placed` for `owner`'s occluding pieces in `flat`, one buffer per kind in `kinds` order; none if empty.
func tell(owner: int, flat: Array[PackedFloat32Array]) -> void:
	if placed.get_connections().is_empty():
		return
	var buffers: Array[PackedFloat32Array] = []
	var strides := PackedInt32Array()
	for k in flat.size():
		if kinds[k].occludes and not flat[k].is_empty():
			buffers.append(flat[k])
			strides.append(kinds[k].stride())
	placed.emit(owner, buffers, strides)


func remove(owner: int) -> void:
	place(owner, nothing(kinds.size()))


static func nothing(n: int) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	none.resize(n)
	none.fill({})
	return none


static func radius(cell: float) -> float:
	return sqrt(cell * cell * 2.0 + TALL * TALL) * 0.5


static func _coarse_key(key: Vector3i) -> Vector3i:
	return Vector3i(floori(float(key.x) / FINE_PER_COARSE), floori(float(key.y) / FINE_PER_COARSE), key.z)


func counts() -> PackedInt32Array:
	return _counts.duplicate()


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
			c.far = k.far_instance()
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
		if carry != Transform3D.IDENTITY:
			_show_carry([c.instance, c.far, c.full])
	return _chunks[key]


func _show_carry(instances: Array) -> void:
	for g: GeometryInstance3D in instances:
		if g != null and g.material_override is ShaderMaterial:
			Masonry.show_carry(g, carry)


## A carry turns a build about up only.
static func show_carry(g: GeometryInstance3D, x: Transform3D) -> void:
	var turn := x.basis.get_euler().y
	g.set_instance_shader_parameter(&"carried_by", x.origin)
	g.set_instance_shader_parameter(&"carried_turn", Vector2(cos(turn), sin(turn)))


func _coarse_far(key: Vector3i) -> MultiMeshInstance3D:
	if not _coarse.has(key):
		var k := kinds[key.z]
		var far := k.far_instance()
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
		if carry != Transform3D.IDENTITY:
			_show_carry([far])
	return _coarse[key]


## Call after a kind's `reach` or `near` changes.
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


func drawn(owner: int) -> bool:
	for key: Vector3i in _owners.get(owner, []):
		if _dirty.has(key) or _coarse_dirty.has(_coarse_key(key)):
			return false
	return true


## Each chunk swaps its stones whole, so a budgeted flush leaves none blinked out between frames.
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
			kinds[key.z].fill(mmi.multimesh, buf)
		if c.far != null:
			_coarse_dirty[_coarse_key(key)] = true
	for key: Vector3i in _coarse_dirty.keys():
		if Budget.over(start, budget_us):
			break
		_coarse_dirty.erase(key)
		var buf := PackedFloat32Array()
		for x in FINE_PER_COARSE:
			for z in FINE_PER_COARSE:
				var c: Chunk = _chunks.get(Vector3i(key.x * FINE_PER_COARSE + x, key.y * FINE_PER_COARSE + z, key.z))
				if c != null:
					for part: PackedFloat32Array in c.parts.values():
						buf.append_array(part)
		kinds[key.z].fill(_coarse[key].multimesh, buf)
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


## Empty `arrays` draws from the instances: the baked mesh stands in only once it holds every piece they do.
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


## [mesh arrays, bounds], each vertex carrying its piece's frame and custom data. Under fixed foveation each tile shades
## every instanced vertex in view, several times the unfoveated price; baked, only what it holds ("Far masonry under the
## foveation map", docs/design.md). Reads only its arguments, so it runs on a worker thread.
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

