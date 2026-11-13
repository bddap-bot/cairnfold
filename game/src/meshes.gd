class_name Meshes
extends RefCounted

const ROUND := 0.6
## In blob radii.
const BLOB_LUMP := 0.35
## A bare trunk's boughs: how many ring its top, the sides of each tube, how many times over each forks into twigs,
## and the height over the trunk's middle, in trunk heights, past which a vertex is a bough's.
const BOUGHS := 5
const BOUGH_SIDES := 3
const BOUGH_TWIGS := 2
const BOUGH_FROM := 0.51


static func bind_bone(skin: Skin, i: int, skeleton: Skeleton3D) -> int:
	return skin.get_bind_bone(i) if skin.get_bind_bone(i) >= 0 else skeleton.find_bone(skin.get_bind_name(i))


static func level(verts: PackedVector3Array) -> Array:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	return out


static func glow(colour: Color, see_through := true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if see_through:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = colour
	return mat


static func ball(radius: float, colour: Color, see_through := true) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = ToolModels.sphere(radius, radius * 2.0)
	m.material_override = glow(colour, see_through)
	return m


## Works outside the tree, where global_transform does not.
static func relative(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != root:
		t = n.transform * t
		n = n.get_parent()
	return t


static func ghostly(node: Node, look: Material) -> void:
	for g: GeometryInstance3D in node.find_children("*", "GeometryInstance3D", true, false):
		g.material_override = look


static func moss() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0.5, 0.5))
	st.add_vertex(Vector3(0, 0.045, 0))
	for i in 12:
		var angle := TAU * i / 12.0
		var p := Vector3(cos(angle), 0, sin(angle)) * (0.4 + 0.1 * sin(i * 7.0))
		st.set_normal(Vector3(p.x * 1.5, 1, p.z * 1.5).normalized())
		st.set_uv(Vector2(p.x, p.z) + Vector2.ONE * 0.5)
		st.add_vertex(p)
	for i in 12:
		st.add_index(0)
		st.add_index(i + 1)
		st.add_index((i + 1) % 12 + 1)
	return st.commit()


const LOD_SEGMENTS := 2


## A unit cube (-0.5..0.5); faces share border vertices since a stone's GPU cost follows its vertex count. Finer than
## LOD_SEGMENTS, it carries that lattice as an LOD keyed by `lod_error`.
static func rounded_box(radius: float, segments: int, seed: int) -> ArrayMesh:
	var lump := FastNoiseLite.new()
	lump.seed = seed
	lump.frequency = 1.6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	var full := _lattice(arrays, radius, segments, lump)
	arrays[Mesh.ARRAY_INDEX] = full.indices
	var lods := {}
	if segments > LOD_SEGMENTS:
		var coarse := _lattice(arrays, radius, LOD_SEGMENTS, lump)
		lods[lod_error(arrays[Mesh.ARRAY_VERTEX], full, coarse)] = coarse.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	return mesh


## Appends to `arrays` and returns {indices, grids, segments}: a face's lattice point (i, j) is its grid's
## j * (segments + 1) + i entry.
static func _lattice(arrays: Array, radius: float, segments: int, lump: FastNoiseLite) -> Dictionary:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var faces := [
		[Vector3i.RIGHT, Vector3i.UP, Vector3i.BACK],
		[Vector3i.LEFT, Vector3i.UP, Vector3i.FORWARD],
		[Vector3i.UP, Vector3i.BACK, Vector3i.RIGHT],
		[Vector3i.DOWN, Vector3i.FORWARD, Vector3i.RIGHT],
		[Vector3i.BACK, Vector3i.UP, Vector3i.LEFT],
		[Vector3i.FORWARD, Vector3i.UP, Vector3i.RIGHT],
	]
	var inner := 1.0 - radius * 2.0
	var row := segments + 1
	# Lattice point on the cube's surface, in steps of 2 / segments -> vertex index.
	var made := {}
	var indices := PackedInt32Array()
	var grids: Array[PackedInt32Array] = []
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
					made[q] = verts.size()
					normals.append(off)
					verts.append(p * 0.5)
				grid.append(made[q])
		for j in segments:
			for i in segments:
				var a := j * row + i
				indices.append_array([grid[a], grid[a + row], grid[a + 1], grid[a + 1], grid[a + row], grid[a + row + 1]])
		grids.append(grid)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	return {"indices": indices, "grids": grids, "segments": segments}


## The farthest a vertex of `fine` lies from `coarse`'s surface at the same face point, in mesh units: the renderer's
## LOD key.
static func lod_error(verts: PackedVector3Array, fine: Dictionary, coarse: Dictionary) -> float:
	var n: int = fine.segments
	var m: int = coarse.segments
	var error := 0.0
	for f in fine.grids.size():
		var g: PackedInt32Array = fine.grids[f]
		var c: PackedInt32Array = coarse.grids[f]
		for j in n + 1:
			for i in n + 1:
				var u := float(i) * m / n
				var v := float(j) * m / n
				var ci := mini(floori(u), m - 1)
				var cj := mini(floori(v), m - 1)
				var fu := u - ci
				var fv := v - cj
				var a := verts[c[cj * (m + 1) + ci]]
				var b := verts[c[cj * (m + 1) + ci + 1]]
				var d := verts[c[(cj + 1) * (m + 1) + ci]]
				var e := verts[c[(cj + 1) * (m + 1) + ci + 1]]
				# Each cell's two triangles meet along its b-d diagonal.
				var at := a + (b - a) * fu + (d - a) * fv if fu + fv <= 1.0 else e + (d - e) * (1.0 - fu) + (b - e) * (1.0 - fv)
				error = maxf(error, verts[g[j * (n + 1) + i]].distance_to(at))
	return error


## 8 vertices where BoxMesh runs 24, for shadow casters and far stones, whose faces must stand where
## `rounded_box`'s flat faces do.
static func plain_box() -> ArrayMesh:
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


## UV.y runs 0 at the root to 1 at the tip.
static func grass_clump(blades: int, seed: int, wide := 1.0) -> ArrayMesh:
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
		var w := rng.randf_range(0.016, 0.026) * wide
		var lean := dir * rng.randf_range(0.04, 0.14)
		var top := root + Vector3.UP * h + lean
		var nrm := side.cross(top - root).normalized()
		# One triangle a blade: on the Quest 2 the meadow costs by the triangles it rasterises.
		var pts := [root - side * w, top, root + side * w]
		var uvs := [Vector2(0, 0), Vector2(0.5, 1), Vector2(1, 0)]
		# Edge normals tilt outward, so a flat blade shades as if rounded across its width.
		var rounded := [nrm - side * 0.7, nrm, nrm + side * 0.7]
		for k in 3:
			st.set_normal(rounded[k].normalized())
			st.set_uv(uvs[k])
			st.add_vertex(pts[k])
	return st.commit()


const STALK := Color(0.25, 0.45, 0.12)
const EYE := Color(1.0, 0.78, 0.25)
## To the head, unscaled.
const FLOWER_HEIGHT := 0.22


## Height of a flower's sword leaves' lower shoulders, which the flower shader stands just under a pond's surface.
const LEAF_SHOULDER := 0.05


## UV.x is 0 on the stalk and 1 on the head, UV.y 1 at its eye and -1 on the sword leaves, which the shader opens only
## in the shallows.
static func flower(petals: int, head := Color.WHITE, leaves := false) -> ArrayMesh:
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
	for i in 3 if leaves else 0:
		var a := TAU * i / 3 + 0.4 * i
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var top := h * (1.0 - 0.1 * i)
		var foot := Vector3.ZERO
		var low := [out * 0.015 - side * 0.03 + Vector3.UP * LEAF_SHOULDER, out * 0.015 + side * 0.03 + Vector3.UP * LEAF_SHOULDER]
		var high := [out * 0.05 - side * 0.024 + Vector3.UP * lerpf(LEAF_SHOULDER, top, 0.6), out * 0.05 + side * 0.024 + Vector3.UP * lerpf(LEAF_SHOULDER, top, 0.6)]
		var tip := out * 0.09 + Vector3.UP * top
		for tri in [[foot, low[0], low[1]], [low[0], high[0], low[1]], [low[1], high[0], high[1]], [high[0], tip, high[1]]]:
			for p: Vector3 in tri:
				st.set_color(STALK)
				st.set_uv(Vector2(0, -1))
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
	st.index()
	return st.commit()


## An icosphere: it holds a latitude-longitude sphere's lumps with far fewer vertices, which is what the Quest 2 pays
## for. Normals stay the sphere's, so light wraps the blob as one soft mass and the lumps show only in its outline.
static func blob(seed: int, subdiv := 2) -> ArrayMesh:
	var arrays := icosphere(subdiv)
	var sphere: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var verts := PackedVector3Array()
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 2.2
	var colors := PackedColorArray()
	for u in sphere:
		var v := u * (1.0 + noise.get_noise_3dv(u) * BLOB_LUMP)
		verts.append(v)
		var shade := clampf(0.55 + v.y * 0.45, 0.35, 1.0)
		colors.append(Color(shade, shade, shade))
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = sphere
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A tree's trunk, a cylinder one high about its middle, with the boughs it stands bare under in winter: a leader
## and BOUGHS boughs from its top, each forking into twigs BOUGH_TWIGS times over, as three-sided tubes. Each leaves the
## trunk from its axis, inside its top; every other bough vertex lies over BOUGH_FROM, and is one unit out where its
## bough is to reach the crown's edge: the plant shader spreads them by that.
static func bare_trunk(trunk: PrimitiveMesh) -> ArrayMesh:
	var arrays := trunk.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# [from, to, radius at from, radius at to]
	var tubes := []
	var crook := Vector3(0.03, 0.8, 0.02)
	tubes.append([Vector3(0, 0.45, 0), crook, 0.035, 0.035])
	_limb(tubes, crook, Vector3(-0.03, 1.16, -0.04), 0.035, BOUGH_TWIGS, rng)
	for b in BOUGHS:
		var a := (b + rng.randf_range(-0.25, 0.25)) * TAU / BOUGHS
		var out := Vector3(cos(a), 0, sin(a))
		var elbow := out * rng.randf_range(0.36, 0.46) + Vector3.UP * rng.randf_range(0.64, 0.72)
		tubes.append([Vector3(0, rng.randf_range(0.36, 0.46), 0), elbow, 0.03, 0.03])
		_limb(tubes, elbow, out.rotated(Vector3.UP, rng.randf_range(-0.25, 0.25)) + Vector3.UP * rng.randf_range(0.84, 1.0), 0.03, BOUGH_TWIGS, rng)
	for t: Array in tubes:
		var along: Vector3 = (t[1] - t[0]).normalized()
		var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
		var first := verts.size()
		for end in 2:
			for s in BOUGH_SIDES:
				var n := side.rotated(along, s * TAU / BOUGH_SIDES)
				verts.append(t[end] + n * t[2 + end])
				normals.append(n)
				uvs.append(Vector2(0.5, 0.5))
		for s in BOUGH_SIDES:
			var next := (s + 1) % BOUGH_SIDES
			indices.append_array([first + s, first + BOUGH_SIDES + s, first + next, first + next, first + BOUGH_SIDES + s, first + BOUGH_SIDES + next])
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = verts
	out_arrays[Mesh.ARRAY_NORMAL] = normals
	out_arrays[Mesh.ARRAY_TEX_UV] = uvs
	out_arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	return mesh


## Adds to `tubes` a limb from `a` to `b`, `radius` thick at `a` and tapering to a point's, and `forks` times over
## the two twigs forking from along it, each turned out to a side and up.
static func _limb(tubes: Array, a: Vector3, b: Vector3, radius: float, forks: int, rng: RandomNumberGenerator) -> void:
	tubes.append([a, b, radius, 0.004])
	if forks == 0:
		return
	var run := b - a
	var flat := Vector3(run.x, 0, run.z)
	for side in [-1.0, 1.0]:
		var t := rng.randf_range(0.35, 0.65)
		var from := a.lerp(b, t)
		var to := from + flat.rotated(Vector3.UP, side * rng.randf_range(0.5, 0.9)) * 0.62 + Vector3.UP * maxf(run.y, flat.length() * 0.4) * rng.randf_range(0.45, 0.75)
		_limb(tubes, from, to, lerpf(radius, 0.004, t) * 0.75, forks - 1, rng)


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


## Three leaf cards in the XY plane facing +Z, stem below tip, a leaf one unit long. Two triangles a leaf: on the
## Quest 2 ivy costs by the triangles it rasterises, not by its area or its instances.
static func sprig() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Vector3(0, 0, 0)
	var tip := Vector3(0, 1, 0)
	var placed := [
		[Transform3D(Basis(Vector3.BACK, 0.55), Vector3(-0.45, -0.3, 0.0)), 0.85],
		[Transform3D(Basis(Vector3.BACK, -0.6), Vector3(0.4, -0.2, 0.02)), 0.95],
		[Transform3D(Basis(Vector3.BACK, 0.1), Vector3(0.05, 0.15, 0.04)), 1.05],
	]
	for leaf in placed:
		var x: Transform3D = leaf[0]
		for lobe in [Vector3(-0.5, 0.5, -0.06), Vector3(0.5, 0.5, -0.06)]:
			# Godot's front face winds clockwise; a lobe wound against its normal draws its back face, whose normal
			# the renderer turns into the wall: black on the Quest.
			var corners := [stem, lobe, tip]
			var n: Vector3 = (tip - stem).cross(lobe - stem).normalized()
			if n.z < 0.0:
				corners = [stem, tip, lobe]
				n = -n
			for p in corners:
				st.set_normal(x.basis * n)
				st.set_color(Color(leaf[1], leaf[1], leaf[1]))
				st.add_vertex(x * p)
	st.index()
	return st.commit()


## Facing -Z, wings flat. UV.x runs 0 at the body to 1 at a wing's edge; UV.y is 0 on a forewing, 1 on a hindwing,
## 2 on the body.
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


## Half-axes `r` along `axes`; `part` goes in UV2.x for a vertex shader to pivot by; `shape` maps each point in the
## ellipsoid's own frame about its centre. Normals lean ROUND away from `round` (INF: none) so blobs shade as one mass.
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


## Appends a surface's (or a blend shape's) arrays to `into`, slot by slot where both have one, first moving
## `arrays`' indices, in place, past `into`'s vertices.
static func join(into: Array, arrays: Array) -> void:
	if into[Mesh.ARRAY_INDEX] != null and arrays[Mesh.ARRAY_INDEX] != null:
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base: int = into[Mesh.ARRAY_VERTEX].size()
		for j in idx.size():
			idx[j] += base
		arrays[Mesh.ARRAY_INDEX] = idx
	for k in mini(into.size(), arrays.size()):
		if into[k] != null and arrays[k] != null:
			var joined: Variant = into[k]
			joined.append_array(arrays[k])
			into[k] = joined


static func shaped_like(im: ImporterMesh) -> ImporterMesh:
	var out := ImporterMesh.new()
	out.resource_name = im.resource_name
	out.set_blend_shape_mode(im.get_blend_shape_mode())
	for k in im.get_blend_shape_count():
		out.add_blend_shape(im.get_blend_shape_name(k))
	return out


static func surface_shapes(im: ImporterMesh, i: int) -> Array:
	return range(im.get_blend_shape_count()).map(func(k: int) -> Array: return im.get_surface_blend_shape_arrays(i, k))


static func noise_texture(n: FastNoiseLite, side: int) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = side
	t.height = side
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	return t
