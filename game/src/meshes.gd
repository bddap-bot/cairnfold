class_name Meshes
extends RefCounted

## How far `ellipsoid` leans normals toward its `round` point.
const ROUND := 0.6


## A unit cube (-0.5..0.5) with rounded edges, its surface lumped by `seed` so no two variants match. Faces share
## the vertices along their borders: a stone's cost on the GPU follows the vertices it runs.
static func rounded_box(radius: float, segments: int, seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [
		[Vector3i.RIGHT, Vector3i.UP, Vector3i.BACK],
		[Vector3i.LEFT, Vector3i.UP, Vector3i.FORWARD],
		[Vector3i.UP, Vector3i.BACK, Vector3i.RIGHT],
		[Vector3i.DOWN, Vector3i.FORWARD, Vector3i.RIGHT],
		[Vector3i.BACK, Vector3i.UP, Vector3i.LEFT],
		[Vector3i.FORWARD, Vector3i.UP, Vector3i.RIGHT],
	]
	var lump := FastNoiseLite.new()
	lump.seed = seed
	lump.frequency = 1.6
	var inner := 1.0 - radius * 2.0
	var row := segments + 1
	## Lattice point on the cube's surface, in steps of 2 / segments -> vertex index.
	var made := {}
	for f in faces:
		var grid := PackedInt32Array()
		for j in row:
			for i in row:
				var q: Vector3i = f[0] * segments + f[1] * (i * 2 - segments) + f[2] * (j * 2 - segments)
				if not made.has(q):
					var d := Vector3(q) / segments
					var core := d.clamp(-Vector3.ONE * inner, Vector3.ONE * inner)
					var off := (d - core).normalized()
					var p := core + off * radius * 2.0
					p += off * lump.get_noise_3dv(p * 1.3) * 0.06
					st.set_normal(off)
					st.add_vertex(p * 0.5)
					made[q] = made.size()
				grid.append(made[q])
		for j in segments:
			for i in segments:
				var a := j * row + i
				st.add_index(grid[a]); st.add_index(grid[a + row]); st.add_index(grid[a + 1])
				st.add_index(grid[a + 1]); st.add_index(grid[a + row]); st.add_index(grid[a + row + 1])
	return st.commit()


## A unit cube (-0.5..0.5) of 8 vertices, for what only casts a shadow: BoxMesh runs 24.
static func shadow_box() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in 8:
		var p := Vector3(c & 1, (c >> 1) & 1, (c >> 2) & 1) - Vector3.ONE * 0.5
		st.set_normal(p.normalized())
		st.add_vertex(p)
	for q in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		for k in [0, 2, 1, 0, 3, 2]:
			st.add_index(q[k])
	return st.commit()


## A clump of crossed blades; UV.y runs 0 at the root to 1 at the tip. Far off, grass.gdshader draws only the first
## `kept` blades, each widened by its CUSTOM0.xz, so they cover the ground all `blades` did; CUSTOM0.z is 1 on the
## blades it drops.
static func grass_clump(blades: int, seed: int, kept := blades) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)
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
		var widen := [-side * w, side * w, -side * w * 0.7, side * w * 0.7, Vector3.ZERO]
		var grow := float(blades) / kept - 1.0 if b < kept else 0.0
		for tri in [[0, 2, 1], [1, 2, 3], [2, 4, 3]]:
			for k in tri:
				st.set_normal(rounded[k].normalized())
				st.set_uv(uvs[k])
				st.set_custom(0, Color(widen[k].x * grow, widen[k].z * grow, float(b >= kept)))
				st.add_vertex(pts[k])
	st.index()
	return st.commit()


const STALK := Color(0.25, 0.45, 0.12)
const EYE := Color(1.0, 0.78, 0.25)
## Stalk length to the head, in an unscaled flower.
const FLOWER_HEIGHT := 0.22


## A tiny flower head: a flat star of `head`-coloured petals around a raised eye, on a stalk.
## UV.x is 0 on the stalk and 1 on the head, UV.y 1 at its eye, for shaders that colour each instance.
static func flower(petals: int, head := Color.WHITE) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := FLOWER_HEIGHT
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
	st.index()
	return st.commit()


## A lumpy foliage blob: an icosphere pushed out by noise, shaded darker underneath. Its vertices are spread evenly,
## so it holds the lumps of a latitude-longitude sphere with far fewer of them, which is what the Quest 2 pays for.
static func blob(seed: int, subdiv := 2) -> ArrayMesh:
	var arrays := icosphere(subdiv)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 2.2
	var colors := PackedColorArray()
	for i in verts.size():
		var v := verts[i] * (1.0 + noise.get_noise_3dv(verts[i]) * 0.35)
		verts[i] = v
		var shade := clampf(0.55 + v.y * 0.45, 0.35, 1.0)
		colors.append(Color(shade, shade, shade))
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var st := SurfaceTool.new()
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	st.create_from(tmp, 0)
	st.generate_normals()
	return st.commit()


static func icosphere(subdiv: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := PackedVector3Array()
	for p in [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
			[t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]]:
		verts.append(Vector3(p[0], p[1], p[2]).normalized())
	var faces := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2,
		10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for s in subdiv:
		var mid := {}
		var split := PackedInt32Array()
		for f in range(0, faces.size(), 3):
			var m := []
			for e in 3:
				var a := faces[f + e]
				var b := faces[f + (e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mid.has(key):
					mid[key] = verts.size()
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
				m.append(mid[key])
			split.append_array([faces[f], m[0], m[2], m[0], faces[f + 1], m[1], m[2], m[1], faces[f + 2], m[0], m[1], m[2]])
		faces = split
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	# Godot's front faces wind clockwise; the faces above wind the other way.
	for f in range(0, faces.size(), 3):
		var b := faces[f + 1]
		faces[f + 1] = faces[f + 2]
		faces[f + 2] = b
	arrays[Mesh.ARRAY_INDEX] = faces
	return arrays


## Three ivy leaf cards around the origin in the XY plane, facing +Z, each folded along its vein with its stem
## below its tip; a leaf is one unit long. A vine lays one sprig a step rather than three leaves, since the
## renderer pays most per instance.
static func sprig() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Vector3(0, 0, 0)
	var tip := Vector3(0, 1, 0)
	var vein := Vector3(0, 0.45, 0.04)
	var placed := [
		[Transform3D(Basis(Vector3.BACK, 0.55), Vector3(-0.45, -0.3, 0.0)), 0.85],
		[Transform3D(Basis(Vector3.BACK, -0.6), Vector3(0.4, -0.2, 0.02)), 0.95],
		[Transform3D(Basis(Vector3.BACK, 0.1), Vector3(0.05, 0.15, 0.04)), 1.05],
	]
	for leaf in placed:
		var x: Transform3D = leaf[0]
		for lobe in [Vector3(-0.5, 0.5, -0.06), Vector3(0.5, 0.5, -0.06)]:
			for tri in [[stem, lobe, vein], [vein, lobe, tip]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if n.z < 0.0:
					n = -n
				for p in tri:
					st.set_normal(x.basis * n)
					st.set_color(Color(leaf[1], leaf[1], leaf[1]))
					st.add_vertex(x * p)
	st.index()
	return st.commit()


## A butterfly facing -Z with its wings flat: fore and hind wings fanned from the body on each side, and a
## thin body. UV.x runs 0 at the body to 1 at a wing's edge; UV.y is 0 on a forewing, 1 on a hindwing, 2 on the body.
static func butterfly() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fore := [Vector2(0.010, -0.006), Vector2(0.030, -0.032), Vector2(0.050, -0.040), Vector2(0.058, -0.028), Vector2(0.050, -0.010), Vector2(0.034, 0.0)]
	var hind := [Vector2(0.036, 0.006), Vector2(0.040, 0.022), Vector2(0.030, 0.036), Vector2(0.014, 0.034), Vector2(0.004, 0.012)]
	for side in [1.0, -1.0]:
		for wing in [[fore, -0.004, 0.0], [hind, 0.004, 1.0]]:
			var rim: Array = wing[0]
			var hinge := Vector3(0, 0, wing[1])
			for i in rim.size() - 1:
				for p in [hinge, Vector3(rim[i].x * side, 0, rim[i].y), Vector3(rim[i + 1].x * side, 0, rim[i + 1].y)]:
					st.set_uv(Vector2(0.0 if p == hinge else 1.0, wing[2]))
					st.set_normal(Vector3.UP)
					st.add_vertex(p)
	var w := 0.004
	for across in [Vector3(w, 0, 0), Vector3(0, w, 0)]:
		for p in [-across - Vector3(0, 0, 0.018), across - Vector3(0, 0, 0.018), across + Vector3(0, 0, 0.026), -across - Vector3(0, 0, 0.018), across + Vector3(0, 0, 0.026), -across + Vector3(0, 0, 0.026)]:
			st.set_uv(Vector2(0, 2))
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	return st.commit()


## A latitude-longitude ellipsoid with half-axes `r` along `axes`, its vertices carrying `part` in UV2.x for a
## vertex shader to pivot by. `shape` may bend each surface point (given in the ellipsoid's own frame, relative
## to its centre), and `ruffle` pushes the surface in and out a little, like fluffed feathers. Given `round`,
## normals lean by ROUND toward pointing away from it, so overlapping blobs shade as one soft mass.
static func ellipsoid(st: SurfaceTool, part: int, c: Vector3, r: Vector3, col: Color, lat: int, lon: int, shape := Callable(), axes := Basis(), ruffle := 0.0, round := Vector3.INF) -> void:
	var ring := []
	for i in lat + 1:
		var row := []
		var th := PI * i / lat
		for j in lon:
			var ph := TAU * j / lon
			var u := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var p := u * r * (1.0 + ruffle * (sin(ph * 5.0 + th * 3.0) * 0.6 + sin(ph * 3.0 - th * 7.0 + 1.3) * 0.4) * sin(th))
			if shape.is_valid():
				p = shape.call(p)
			var at := c + axes * p
			var n := (axes * (u / r)).normalized()
			if round != Vector3.INF:
				n = n.lerp((at - round).normalized(), ROUND).normalized()
			row.append([at, n])
		ring.append(row)
	for i in lat:
		for j in lon:
			var k := (j + 1) % lon
			var quad := [ring[i][j], ring[i + 1][j], ring[i + 1][k], ring[i][k]]
			for t in [[0, 1, 2], [0, 2, 3]]:
				if i == 0 and t[2] == 3:
					continue
				if i == lat - 1 and t[1] == 1:
					continue
				for v in t:
					st.set_color(col)
					st.set_uv2(Vector2(part, 0))
					st.set_normal(quad[v][1])
					st.add_vertex(quad[v][0])
