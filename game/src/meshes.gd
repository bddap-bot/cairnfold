class_name Meshes
extends RefCounted


## A unit cube (-0.5..0.5) with rounded edges, its surface lumped by `seed` so no two variants match.
static func rounded_box(radius: float, segments: int, seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
		[Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		[Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT],
		[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	var lump := FastNoiseLite.new()
	lump.seed = seed
	lump.frequency = 1.6
	var inner := 1.0 - radius * 2.0
	var row := segments + 1
	var start := 0
	for f in faces:
		for j in row:
			for i in row:
				var d: Vector3 = f[0] + f[1] * (float(i) / segments * 2.0 - 1.0) + f[2] * (float(j) / segments * 2.0 - 1.0)
				var core := d.clamp(-Vector3.ONE * inner, Vector3.ONE * inner)
				var off := (d - core).normalized()
				var p := core + off * radius * 2.0
				p += off * lump.get_noise_3dv(p * 1.3) * 0.06
				st.set_normal(off)
				st.add_vertex(p * 0.5)
		for j in segments:
			for i in segments:
				var a := start + j * row + i
				st.add_index(a); st.add_index(a + row); st.add_index(a + 1)
				st.add_index(a + 1); st.add_index(a + row); st.add_index(a + row + 1)
		start += row * row
	return st.commit()


## A clump of crossed blades; UV.y runs 0 at the root to 1 at the tip.
static func grass_clump(blades: int, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades:
		var ang := rng.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var root := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var h := rng.randf_range(0.12, 0.27)
		var w := rng.randf_range(0.012, 0.02)
		var lean := dir * rng.randf_range(0.04, 0.14)
		var mid := root + Vector3.UP * h * 0.55 + lean * 0.4
		var top := root + Vector3.UP * h + lean
		var nrm := side.cross(top - root).normalized()
		var pts := [root - side * w, root + side * w, mid - side * w * 0.7, mid + side * w * 0.7, top]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 0.55), Vector2(1, 0.55), Vector2(0.5, 1)]
		# Edge normals tilt outward, so a flat blade shades as if rounded across its width.
		var rounded := [nrm - side * 0.7, nrm + side * 0.7, nrm - side * 0.7, nrm + side * 0.7, nrm]
		for tri in [[0, 2, 1], [1, 2, 3], [2, 4, 3]]:
			for k in tri:
				st.set_normal(rounded[k].normalized())
				st.set_uv(uvs[k])
				st.add_vertex(pts[k])
	return st.commit()


const STALK := Color(0.25, 0.45, 0.12)
const EYE := Color(1.0, 0.78, 0.25)


## A tiny flower head: a flat star of `head`-coloured petals around a raised eye, on a stalk.
## UV.x is 0 on the stalk and 1 on the head, UV.y 1 at its eye, for shaders that colour each instance.
static func flower(petals: int, head := Color.WHITE) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.22
	for tri in [[Vector3(-0.006, 0, 0), Vector3(0, h, 0), Vector3(0.006, 0, 0)], [Vector3(0, 0, -0.006), Vector3(0, h, 0), Vector3(0, 0, 0.006)]]:
		for p in tri:
			st.set_color(STALK)
			st.set_uv(Vector2(0, 0))
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	var c := Vector3(0, h, 0)
	for i in petals:
		var a0 := TAU * i / petals
		var a1 := TAU * (i + 0.5) / petals
		var a2 := TAU * (i + 1) / petals
		var r := 0.06
		var eye := c + Vector3(0, 0.008, 0)
		var tip := c + Vector3(cos(a1), 0.004, sin(a1)) * r
		for tri in [[eye, c + Vector3(cos(a0), 0, sin(a0)) * r * 0.5, tip], [eye, tip, c + Vector3(cos(a2), 0, sin(a2)) * r * 0.5]]:
			for p: Vector3 in tri:
				st.set_color(EYE if p == eye else head)
				st.set_uv(Vector2(1, 1 if p == eye else 0))
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
	return st.commit()


## A lumpy foliage blob: an icosphere pushed out by noise, shaded darker underneath.
static func blob(seed: int, subdiv: int = 2) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 10 * subdiv
	sphere.rings = 5 * subdiv
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 2.2
	var colors := PackedColorArray()
	for i in verts.size():
		var v := verts[i] * 2.0
		v *= 1.0 + noise.get_noise_3dv(v) * 0.35
		verts[i] = v
		var shade := clampf(0.55 + v.y * 0.45, 0.35, 1.0)
		colors.append(Color(shade, shade, shade))
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	st.create_from(tmp, 0)
	st.generate_normals()
	return st.commit()


## An ivy leaf card in the XY plane facing +Z, its stem at the origin and its tip at Y = 1, folded along the vein.
static func leaf() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Vector3(0, 0, 0)
	var tip := Vector3(0, 1, 0)
	var vein := Vector3(0, 0.45, 0.04)
	for lobe in [Vector3(-0.5, 0.5, -0.06), Vector3(0.5, 0.5, -0.06)]:
		for tri in [[stem, lobe, vein], [vein, lobe, tip]]:
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			if n.z < 0.0:
				n = -n
			for p in tri:
				st.set_normal(n)
				st.set_color(Color(1, 1, 1))
				st.add_vertex(p)
	return st.commit()
