extends RefCounted

## A Mesh object (class 43) as Unity serializes it in a text asset: the mesh a build tool generates and saves beside
## the model it came from, which a renderer then names in place of the model's. It reads into the MeshInstance3D Godot's
## importer would make of that model's node, in Godot's axes (Unity's with X mirrored, as Unity's model importer
## mirrors a model's), UVs from the top: each submesh a surface, every blend shape at its last frame, and, where it has
## bind poses, skinned to a Skeleton3D whose bone i is the renderer's bone i, resting where its bind pose puts it.

const Yaml = preload("res://../scripts/unity/yaml.gd")

## Bytes per component, by Unity's VertexAttributeFormat.
const SIZES := [4, 2, 1, 1, 2, 2, 1, 1, 2, 2, 4, 4]
const POSITION := 0
const NORMAL := 1
const UV0 := 4
const WEIGHTS := 12
const INDICES := 13
## Unity aligns each vertex stream's start in the vertex data to this many bytes.
const STREAM_ALIGN := 16
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3.BACK)


## {"node": the MeshInstance3D, under a root the caller frees, "slots": each surface's material slot} of the Mesh object
## `mesh` (its fields, as Yaml.objects reads them) for a renderer whose bones are named `bones`, or a String saying why
## it cannot be drawn.
static func read(mesh: Dictionary, bones: PackedStringArray) -> Variant:
	if str(mesh.get("m_MeshCompression", "0")) != "0":
		return "a compressed mesh"
	var vd: Dictionary = mesh.get("m_VertexData", {})
	if str(vd.get("serializedVersion", "")) != "3":
		return "vertex data of serialized version %s" % vd.get("serializedVersion", "?")
	var count := str(vd.get("m_VertexCount", "0")).to_int()
	var data := str(vd.get("_typelessdata", "")).hex_decode()
	var channels := []
	var strides := {}
	for c: Variant in Yaml.list(vd.get("m_Channels")):
		# The dimension's high bits carry flags, not components.
		var ch := {"stream": str(c.get("stream", "0")).to_int(), "offset": str(c.get("offset", "0")).to_int(), "format": str(c.get("format", "0")).to_int(), "dimension": str(c.get("dimension", "0")).to_int() & 0xF}
		channels.append(ch)
		if ch.dimension > 0:
			if ch.format >= SIZES.size():
				return "vertex format %d" % ch.format
			strides[ch.stream] = maxi(strides.get(ch.stream, 0), ch.offset + SIZES[ch.format] * ch.dimension)
	var starts := {}
	var end := 0
	for s: int in range(strides.keys().max() + 1 if not strides.is_empty() else 0):
		end = ceili(end / float(STREAM_ALIGN)) * STREAM_ALIGN
		starts[s] = end
		end += strides.get(s, 0) * count
	if end > data.size():
		return "%d bytes of vertex data where its channels need %d" % [data.size(), end]
	var dimension := func(c: int) -> int: return channels[c].dimension if c < channels.size() else 0
	# Channel c's first `width` components of each vertex, one after another; components it lacks read 0.
	var column := func(c: int, width: int) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(count * width)
		var ch: Dictionary = channels[c]
		for i in count:
			var at: int = starts[ch.stream] + i * strides[ch.stream] + ch.offset
			for k in mini(ch.dimension, width):
				out[i * width + k] = _component(data, at + k * SIZES[ch.format], ch.format)
		return out
	if dimension.call(POSITION) < 3:
		return "no vertex positions"
	var positions: PackedFloat32Array = column.call(POSITION, 3)
	var normals: PackedFloat32Array = column.call(NORMAL, 3) if dimension.call(NORMAL) >= 3 else PackedFloat32Array()
	var uvs := []
	for u in 4:
		uvs.append(column.call(UV0 + u, 2) if dimension.call(UV0 + u) >= 2 else PackedFloat32Array())
	var binds := Yaml.list(mesh.get("m_BindPose"))
	if not binds.is_empty() and (dimension.call(WEIGHTS) == 0 or dimension.call(INDICES) == 0):
		return "bind poses without per-vertex bone weights"
	if binds.size() > bones.size():
		return "%d bind poses for %d bones" % [binds.size(), bones.size()]
	var weights: PackedFloat32Array = column.call(WEIGHTS, 4) if not binds.is_empty() else PackedFloat32Array()
	var joints: PackedFloat32Array = column.call(INDICES, 4) if not binds.is_empty() else PackedFloat32Array()
	var indices := str(mesh.get("m_IndexBuffer", "")).hex_decode()
	var wide := str(mesh.get("m_IndexFormat", "0")) == "1"
	var shapes: Dictionary = mesh.get("m_Shapes", {}) if mesh.get("m_Shapes") is Dictionary else {}
	var shape_vertices := Yaml.list(shapes.get("vertices"))
	var frames := Yaml.list(shapes.get("shapes"))
	var full := Yaml.list(shapes.get("fullWeights"))
	var morphs := []
	for c: Variant in Yaml.list(shapes.get("channels")):
		var last := str(c.get("frameIndex", "0")).to_int() + str(c.get("frameCount", "1")).to_int() - 1
		if last < 0 or last >= frames.size():
			return "blend shape %s past the mesh's frames" % c.get("name", "")
		var weight := str(full[last]).to_float() if last < full.size() else 100.0
		var by := 100.0 / weight if weight != 0.0 else 1.0
		var first := str(frames[last].get("firstVertex", "0")).to_int()
		var n := str(frames[last].get("vertexCount", "0")).to_int()
		if first < 0 or first + n > shape_vertices.size():
			return "blend shape %s past the mesh's shape vertices" % c.get("name", "")
		var deltas := {}
		for k in n:
			var e: Dictionary = shape_vertices[first + k]
			deltas[str(e.get("index", "0")).to_int()] = [_mirrored(e.get("vertex")) * by, _mirrored(e.get("normal")) * by]
		morphs.append([str(c.get("name", "")), deltas])
	var am := ArrayMesh.new()
	am.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for m: Array in morphs:
		am.add_blend_shape(m[0])
	var slots := []
	var submeshes := Yaml.list(mesh.get("m_SubMeshes"))
	for slot in submeshes.size():
		var sm: Dictionary = submeshes[slot]
		if str(sm.get("topology", "0")) != "0":
			continue
		var first := str(sm.get("firstVertex", "0")).to_int()
		var n := str(sm.get("vertexCount", "0")).to_int()
		var base := str(sm.get("baseVertex", "0")).to_int()
		var start := str(sm.get("firstByte", "0")).to_int()
		var triangles := str(sm.get("indexCount", "0")).to_int() / 3 * 3
		var width := 4 if wide else 2
		if first < 0 or first + n > count or start < 0 or start + triangles * width > indices.size():
			return "submesh %d past the mesh's vertices or indices" % slot
		var idx := PackedInt32Array()
		for t in triangles:
			var i := (indices.decode_u32(start + t * width) if wide else indices.decode_u16(start + t * width)) + base - first
			if i < 0 or i >= n:
				return "submesh %d indexes a vertex outside it" % slot
			idx.append(i)
		if idx.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var v := _vectors(positions, first, n)
		arrays[Mesh.ARRAY_VERTEX] = v
		var nv := _vectors(normals, first, n) if not normals.is_empty() else PackedVector3Array()
		if not normals.is_empty():
			arrays[Mesh.ARRAY_NORMAL] = nv
		if not uvs[0].is_empty():
			arrays[Mesh.ARRAY_TEX_UV] = _uv(uvs[0], first, n)
		if not uvs[1].is_empty():
			arrays[Mesh.ARRAY_TEX_UV2] = _uv(uvs[1], first, n)
		var flags := 0
		# Godot's FBX importer carries a model's third and fourth UV sets in CUSTOM0, where a material's maps on them
		# read them.
		if not uvs[2].is_empty():
			var third := _uv(uvs[2], first, n)
			var fourth := _uv(uvs[3], first, n) if not uvs[3].is_empty() else PackedVector2Array()
			var custom := PackedFloat32Array()
			for i in n:
				custom.append_array([third[i].x, third[i].y] + ([fourth[i].x, fourth[i].y] if not fourth.is_empty() else []))
			arrays[Mesh.ARRAY_CUSTOM0] = custom
			flags |= (Mesh.ARRAY_CUSTOM_RGBA_FLOAT if not fourth.is_empty() else Mesh.ARRAY_CUSTOM_RG_FLOAT) << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		if not binds.is_empty():
			var b := PackedInt32Array()
			for j in joints.slice(first * 4, (first + n) * 4):
				b.append(int(j))
			arrays[Mesh.ARRAY_BONES] = b
			arrays[Mesh.ARRAY_WEIGHTS] = weights.slice(first * 4, (first + n) * 4)
		arrays[Mesh.ARRAY_INDEX] = idx
		var blends := []
		for m: Array in morphs:
			var sv := v.duplicate()
			var sn := nv.duplicate()
			for i: int in m[1]:
				if i >= first and i < first + n:
					sv[i - first] += m[1][i][0]
					if not sn.is_empty():
						sn[i - first] += m[1][i][1]
			var shape := []
			shape.resize(Mesh.ARRAY_MAX)
			shape[Mesh.ARRAY_VERTEX] = sv
			if not sn.is_empty():
				shape[Mesh.ARRAY_NORMAL] = sn
			blends.append(shape)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends, {}, flags)
		slots.append(slot)
	if slots.is_empty():
		return "no triangles"
	am.resource_name = str(mesh.get("m_Name", ""))
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = am.resource_name.validate_node_name() if am.resource_name != "" else "Mesh"
	mi.mesh = am
	if not binds.is_empty():
		var sk := Skeleton3D.new()
		sk.name = "Skeleton"
		var skin := Skin.new()
		for i in binds.size():
			var bind := _transform(binds[i])
			sk.add_bone(bones[i])
			sk.set_bone_rest(i, bind.affine_inverse())
			skin.add_bind(i, bind)
		sk.reset_bone_poses()
		root.add_child(sk)
		mi.skin = skin
		mi.skeleton = NodePath("../Skeleton")
	root.add_child(mi)
	return {"node": mi, "slots": slots}


static func _component(data: PackedByteArray, at: int, format: int) -> float:
	match format:
		0: return data.decode_float(at)
		1: return data.decode_half(at)
		2: return data.decode_u8(at) / 255.0
		3: return maxf(data.decode_s8(at) / 127.0, -1.0)
		4: return data.decode_u16(at) / 65535.0
		5: return maxf(data.decode_s16(at) / 32767.0, -1.0)
		6: return data.decode_u8(at)
		7: return data.decode_s8(at)
		8: return data.decode_u16(at)
		9: return data.decode_s16(at)
		10: return data.decode_u32(at)
		_: return data.decode_s32(at)


## Vertices first to first + n of a column of Unity vectors, in Godot's axes.
static func _vectors(column: PackedFloat32Array, first: int, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(n)
	for i in n:
		out[i] = Vector3(-column[(first + i) * 3], column[(first + i) * 3 + 1], column[(first + i) * 3 + 2])
	return out


static func _uv(column: PackedFloat32Array, first: int, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		out[i] = Vector2(column[(first + i) * 2], 1.0 - column[(first + i) * 2 + 1])
	return out


## A Unity {x, y, z} in Godot's axes.
static func _mirrored(v: Variant) -> Vector3:
	var get := func(k: String) -> float: return str((v as Dictionary).get(k, "0")).to_float() if v is Dictionary else 0.0
	return MIRROR * Vector3(get.call("x"), get.call("y"), get.call("z"))


## A Unity Matrix4x4 ({e00 ... e33}, row then column) in Godot's axes.
static func _transform(m: Dictionary) -> Transform3D:
	var e := func(r: int, c: int) -> float: return str(m.get("e%d%d" % [r, c], "0")).to_float()
	var unity := Transform3D(Vector3(e.call(0, 0), e.call(1, 0), e.call(2, 0)), Vector3(e.call(0, 1), e.call(1, 1), e.call(2, 1)), Vector3(e.call(0, 2), e.call(1, 2), e.call(2, 2)), Vector3(e.call(0, 3), e.call(1, 3), e.call(2, 3)))
	return Transform3D(MIRROR, Vector3.ZERO) * unity * Transform3D(MIRROR, Vector3.ZERO)
