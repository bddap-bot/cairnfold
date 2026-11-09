extends RefCounted

## A Mesh object (class 43) as Unity serializes it in a text asset: the mesh a build tool generates and saves beside
## the model it came from, which a renderer then names in place of the model's. It reads into the MeshInstance3D Godot's
## importer would make of that model's node, in Godot's axes (Unity's with X mirrored, as Unity's model importer
## mirrors a model's), UVs from the top: each submesh a surface, the material slot each surface draws with in the mesh's
## "slots" meta, every blend shape at its last frame, and, where it has bind poses, skinned to a Skeleton3D whose bone i
## is the renderer's bone i, resting where its bind pose puts it.

const Yaml = preload("res://../scripts/unity/yaml.gd")

## Bytes per component, by Unity's VertexAttributeFormat.
const SIZES := [4, 2, 1, 1, 2, 2, 1, 1, 2, 2, 4, 4]
const POSITION := 0
const NORMAL := 1
const UV0 := 4
const UV1 := 5
const UV2 := 6
const UV3 := 7
const WEIGHTS := 12
const INDICES := 13
## Unity aligns each vertex stream's start in the vertex data to this many bytes.
const STREAM_ALIGN := 16


## The node of the Mesh object `mesh` (its fields, as Yaml.objects reads them) for a renderer whose bones are named
## `bones`, or a String saying why it cannot be drawn.
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
	var column := func(c: int) -> Array:
		var out := []
		if c >= channels.size() or channels[c].dimension == 0:
			return out
		var ch: Dictionary = channels[c]
		out.resize(count)
		for i in count:
			var at: int = starts[ch.stream] + i * strides[ch.stream] + ch.offset
			var v := PackedFloat32Array()
			for k in ch.dimension:
				v.append(_component(data, at + k * SIZES[ch.format], ch.format))
			out[i] = v
		return out
	var positions: Array = column.call(POSITION)
	if positions.is_empty():
		return "no vertex positions"
	var normals: Array = column.call(NORMAL)
	var uvs := [column.call(UV0), column.call(UV1), column.call(UV2), column.call(UV3)]
	var weights: Array = column.call(WEIGHTS)
	var joints: Array = column.call(INDICES)
	var per := 4 if weights.is_empty() or (weights[0] as PackedFloat32Array).size() <= 4 else 8
	var binds := Yaml.list(mesh.get("m_BindPose"))
	if not binds.is_empty() and (weights.is_empty() or joints.is_empty()):
		return "bind poses without fixed per-vertex bone weights"
	var indices := str(mesh.get("m_IndexBuffer", "")).hex_decode()
	var wide := str(mesh.get("m_IndexFormat", "0")) == "1"
	var shapes: Dictionary = mesh.get("m_Shapes", {}) if mesh.get("m_Shapes") is Dictionary else {}
	var shape_vertices := Yaml.list(shapes.get("vertices"))
	var frames := Yaml.list(shapes.get("shapes"))
	var full := Yaml.list(shapes.get("fullWeights"))
	var morphs := []
	for c: Variant in Yaml.list(shapes.get("channels")):
		var last := str(c.get("frameIndex", "0")).to_int() + str(c.get("frameCount", "1")).to_int() - 1
		if last >= frames.size():
			return "blend shape %s past the mesh's frames" % c.get("name", "")
		var weight := str(full[last]).to_float() if last < full.size() else 100.0
		var deltas := {}
		var first := str(frames[last].get("firstVertex", "0")).to_int()
		for k in str(frames[last].get("vertexCount", "0")).to_int():
			var e: Dictionary = shape_vertices[first + k]
			var by := 100.0 / weight if weight != 0.0 else 1.0
			deltas[str(e.get("index", "0")).to_int()] = [_unity_vector(e.get("vertex")) * by, _unity_vector(e.get("normal")) * by]
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
		var idx := PackedInt32Array()
		for t in str(sm.get("indexCount", "0")).to_int() / 3 * 3:
			var at := start + t * (4 if wide else 2)
			idx.append((indices.decode_u32(at) if wide else indices.decode_u16(at)) + base - first)
		if idx.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var v := PackedVector3Array()
		var nv := PackedVector3Array()
		for i in range(first, first + n):
			v.append(_unity_vector(positions[i]))
			nv.append(_unity_vector(normals[i]) if not normals.is_empty() else Vector3.UP)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = nv
		var flags := 0
		for u in 2:
			if not uvs[u].is_empty():
				arrays[Mesh.ARRAY_TEX_UV if u == 0 else Mesh.ARRAY_TEX_UV2] = _uv(uvs[u], first, n)
		# Godot's FBX importer carries a model's third and fourth UV sets in CUSTOM0, as this does.
		if not uvs[2].is_empty():
			var third := _uv(uvs[2], first, n)
			var fourth := _uv(uvs[3], first, n) if not uvs[3].is_empty() else PackedVector2Array()
			var custom := PackedFloat32Array()
			for i in n:
				custom.append_array([third[i].x, third[i].y] + ([fourth[i].x, fourth[i].y] if not fourth.is_empty() else []))
			arrays[Mesh.ARRAY_CUSTOM0] = custom
			flags |= (Mesh.ARRAY_CUSTOM_RGBA_FLOAT if not uvs[3].is_empty() else Mesh.ARRAY_CUSTOM_RG_FLOAT) << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		if not binds.is_empty():
			var b := PackedInt32Array()
			var w := PackedFloat32Array()
			for i in range(first, first + n):
				for k in per:
					b.append(int(joints[i][k]) if k < (joints[i] as PackedFloat32Array).size() else 0)
					w.append(weights[i][k] if k < (weights[i] as PackedFloat32Array).size() else 0.0)
			arrays[Mesh.ARRAY_BONES] = b
			arrays[Mesh.ARRAY_WEIGHTS] = w
			if per == 8:
				flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		arrays[Mesh.ARRAY_INDEX] = idx
		var blends := []
		for m: Array in morphs:
			var sv := v.duplicate()
			var sn := nv.duplicate()
			for i: int in m[1]:
				if i >= first and i < first + n:
					sv[i - first] += m[1][i][0]
					sn[i - first] += m[1][i][1]
			var shape := []
			shape.resize(Mesh.ARRAY_MAX)
			shape[Mesh.ARRAY_VERTEX] = sv
			shape[Mesh.ARRAY_NORMAL] = sn
			blends.append(shape)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends, {}, flags)
		slots.append(slot)
	if slots.is_empty():
		return "no triangles"
	am.set_meta("slots", slots)
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
			var bind := _matrix(binds[i])
			sk.add_bone(bones[i] if i < bones.size() and bones[i] != "" else "bone %d" % i)
			sk.set_bone_rest(i, bind.affine_inverse())
			skin.add_bind(i, bind)
		sk.reset_bone_poses()
		root.add_child(sk)
		mi.skin = skin
		mi.skeleton = NodePath("../Skeleton")
	root.add_child(mi)
	return mi


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


## A Unity vector, as a column's components or a YAML {x, y, z}, in Godot's axes.
static func _unity_vector(v: Variant) -> Vector3:
	if v is PackedFloat32Array:
		return Vector3(-v[0], v[1], v[2])
	var get := func(k: String) -> float: return str((v as Dictionary).get(k, "0")).to_float() if v is Dictionary else 0.0
	return Vector3(-get.call("x"), get.call("y"), get.call("z"))


static func _uv(column: Array, first: int, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(first, first + n):
		out.append(Vector2(column[i][0], 1.0 - column[i][1]))
	return out


## A Unity Matrix4x4 ({e00 ... e33}) in Godot's axes.
static func _matrix(m: Dictionary) -> Transform3D:
	var e := func(r: int, c: int) -> float: return str(m.get("e%d%d" % [r, c], "0")).to_float() * (-1.0 if (r == 0) != (c == 0) else 1.0)
	return Transform3D(Vector3(e.call(0, 0), e.call(1, 0), e.call(2, 0)), Vector3(e.call(0, 1), e.call(1, 1), e.call(2, 1)), Vector3(e.call(0, 2), e.call(1, 2), e.call(2, 2)), Vector3(e.call(0, 3), e.call(1, 3), e.call(2, 3)))
