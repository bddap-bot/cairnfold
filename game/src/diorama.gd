class_name Diorama
extends RefCounted

## A garden in miniature, built from the commands that rebuild it: its builds as a few kinds of block on a round
## patch of meadow in the season's colour, so a shelf of them reads at a glance and costs a draw a kind each.

enum Part { BLOCK, PRISM, CONE, BALL, DRUM }
## Metres across the smallest garden shown, so a lone house is not drawn as large as a village.
const LEAST := 14.0
## Metres: the miniature's radius.
const RADIUS := 0.028
## Metres along a wall or path one block stands for.
const RUN := 2.0
const STONE := Color(0.72, 0.68, 0.6)
const TIMBER := Color(0.5, 0.36, 0.22)
const ROOF := Color(0.7, 0.36, 0.26)
const LEAVES := Color(0.26, 0.48, 0.2)
const ROCK := Color(0.56, 0.55, 0.52)
const WATER := Color(0.3, 0.55, 0.72)
const SOIL := Color(0.42, 0.33, 0.24)
const SURFACES := [Color(0.62, 0.5, 0.36), Color(0.86, 0.78, 0.6), Color(0.6, 0.58, 0.55), Color(0.68, 0.66, 0.62), Color(0.4, 0.3, 0.2)]
const POND := 3.0
static var _meshes: Array[Mesh] = []
static var _material: StandardMaterial3D


## {parts: [[Part, Transform3D, Color]] in garden metres, centre: Vector3, radius, ground: Color}.
static func layout(cmds: Array) -> Dictionary:
	var parts := []
	var trees := {}
	var season := Palette.SUMMER
	for c: Dictionary in cmds:
		match c.op:
			"wall":
				for w: Dictionary in c.walls:
					_wall(w, parts)
			"plant":
				if c.kind in Flora.PLACED:
					trees[c.id] = [c.kind, c.at]
				else:
					for d: Array in c.dabs:
						parts.append([Part.DRUM, _disc(d[0], d[1]), Color(0.85, 0.6, 0.7) if c.kind == "flowers" else Color(0.32, 0.56, 0.22)])
			"tree":
				if trees.has(c.group) and c.has("at"):
					trees[c.group][1] = c.at
			"show":
				for g: int in c.plants:
					trees.erase(g)
			"path":
				var points: PackedVector3Array = c.points
				for i in _runs(points, false):
					parts.append([Part.BLOCK, _span(points[i.x], points[i.y], c.half_widths[i.x] * 2.0, 0.1), SURFACES[c.surface]])
			"ground":
				if c.kind == Ground.Kind.STONE:
					for s: Vector4 in c.stamps:
						parts.append([Part.DRUM, _disc(Vector3(s.x, 0, s.y), s.z), STONE])
			"ponds":
				for g: Vector2i in c.get("put", {}):
					var xz := Terrain.grid_xz(g)
					parts.append([Part.DRUM, _disc(Vector3(xz.x, c.put[g], xz.y), POND), WATER])
			"boulder":
				parts.append([Part.BALL, Transform3D(Basis.from_scale(Vector3(1.2, 0.8, 1.0) * c.scale), c.at), ROCK])
			"stairs":
				parts.append([Part.BLOCK, _span(c.a, c.b, c.width, 0.3), STONE])
			"season":
				season = c.index
	for t: Array in trees.values():
		var at: Vector3 = t[1]
		if t[0] == "tree":
			parts.append([Part.DRUM, Transform3D(Basis.from_scale(Vector3(0.4, 2.0, 0.4)), at + Vector3.UP), TIMBER])
			parts.append([Part.CONE, Transform3D(Basis.from_scale(Vector3(3.0, 4.5, 3.0)), at + Vector3.UP * 4.0), LEAVES])
		else:
			parts.append([Part.BALL, Transform3D(Basis.from_scale(Vector3(1.6, 1.2, 1.6)), at + Vector3.UP * 0.5), LEAVES])
	var low := Vector3.INF
	var high := -Vector3.INF
	for p: Array in parts:
		var box: AABB = p[1] * AABB(-Vector3.ONE * 0.5, Vector3.ONE)
		low = low.min(box.position)
		high = high.max(box.end)
	var centre := Vector3.ZERO if parts.is_empty() else Vector3((low.x + high.x) * 0.5, low.y, (low.z + high.z) * 0.5)
	var radius := LEAST * 0.5
	if not parts.is_empty():
		radius = maxf(radius, Vector2(high.x - low.x, high.z - low.z).length() * 0.5 + 1.0)
	var colour: Color = Palette.SEASONS[season].swatch
	return {"parts": parts, "centre": centre, "radius": radius, "ground": colour}


## A wall line as a block a RUN along; a house as one block under its roof.
static func _wall(w: Dictionary, parts: Array) -> void:
	var points: PackedVector3Array = w.points
	var rise: float = w.get("rise", 0.0)
	if w.closed and w.has("roof"):
		var roof: Dictionary = w.roof
		var low := INF
		for p in points:
			low = minf(low, p.y)
		if roof.kind == RoofLayout.Kind.CONE:
			var c: Vector3 = roof.center
			var r: float = roof.radius
			parts.append([Part.DRUM, Transform3D(Basis.from_scale(Vector3(r * 2.0, w.height, r * 2.0)), Vector3(c.x, low + rise + w.height * 0.5, c.z)), STONE])
			parts.append([Part.CONE, Transform3D(Basis.from_scale(Vector3(r * 2.4, roof.pitch, r * 2.4)), Vector3(c.x, low + rise + w.height + roof.pitch * 0.5, c.z)), ROOF])
			return
		var along := points[1] - points[0]
		var across := points[2] - points[1] if points.size() > 2 else Vector3(-along.z, 0, along.x)
		along.y = 0.0
		across.y = 0.0
		var mid := Vector3.ZERO
		for p in points:
			mid += p
		mid /= points.size()
		var yaw := atan2(-along.z, along.x)
		var basis := Basis(Vector3.UP, yaw)
		var size := Vector3(along.length(), w.height, across.length())
		var base := Vector3(mid.x, low + rise, mid.z)
		parts.append([Part.BLOCK, Transform3D(basis.scaled_local(size), base + Vector3.UP * size.y * 0.5), _finish(w)])
		var pitch: float = roof.pitch
		parts.append([Part.PRISM, Transform3D(basis.scaled_local(Vector3(size.x + 0.4, maxf(pitch, 0.2), size.z + 0.4)) * Basis(Vector3.UP, PI * 0.5), base + Vector3.UP * (size.y + maxf(pitch, 0.2) * 0.5)), ROOF])
		return
	var tall: float = w.height
	var thick := 0.15 if w.fence else 0.6
	for i in _runs(points, w.closed):
		var a := points[i.x]
		var b := points[i.y]
		var t := _span(a, b, thick, tall)
		t.origin.y += rise + tall * 0.5
		parts.append([Part.BLOCK, t, TIMBER if w.fence else _finish(w)])


static func _finish(w: Dictionary) -> Color:
	match w.get("finish", WallLayout.Finish.BARE):
		WallLayout.Finish.PLASTER, WallLayout.Finish.TIMBER:
			return Color(0.9, 0.86, 0.76)
		WallLayout.Finish.BOARDS_ACROSS, WallLayout.Finish.BOARDS_UPRIGHT:
			return TIMBER
	return STONE


## [from, to] index pairs a RUN or so apart along `points`, the last back to the first when `closed`.
static func _runs(points: PackedVector3Array, closed: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var from := 0
	var gone := 0.0
	for i in range(1, points.size()):
		gone += points[i].distance_to(points[i - 1])
		if gone >= RUN or i == points.size() - 1:
			out.append(Vector2i(from, i))
			from = i
			gone = 0.0
	if closed and points.size() > 2:
		out.append(Vector2i(points.size() - 1, 0))
	return out


## A block from `a` to `b`, `wide` across and `tall` high, its middle on the line.
static func _span(a: Vector3, b: Vector3, wide: float, tall: float) -> Transform3D:
	var d := b - a
	var flat := Vector2(d.x, d.z).length()
	var basis := Basis(Vector3.UP, atan2(-d.z, d.x)) * Basis(Vector3.BACK, atan2(d.y, flat))
	return Transform3D(basis.scaled_local(Vector3(maxf(d.length(), 0.1), tall, wide)), (a + b) * 0.5)


static func _disc(at: Vector3, radius: float) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(radius * 2.0, 0.08, radius * 2.0)), at + Vector3.UP * 0.04)


## The miniature of `lay`, RADIUS across on a rim of `rim`, its ground at y 0.
static func build(lay: Dictionary, rim: Color) -> Node3D:
	_ready_meshes()
	var root := Node3D.new()
	root.name = "Diorama"
	var k: float = RADIUS / lay.radius
	var centre: Vector3 = lay.centre
	var by_part := {}
	for p: Array in lay.parts:
		(by_part.get_or_add(p[0], []) as Array).append(p)
	var base := Transform3D(Basis.from_scale(Vector3(RADIUS * 2.0, RADIUS * 0.1, RADIUS * 2.0)), Vector3.DOWN * RADIUS * 0.05)
	var edge := Transform3D(Basis.from_scale(Vector3(RADIUS * 2.12, RADIUS * 0.22, RADIUS * 2.12)), Vector3.DOWN * RADIUS * 0.12)
	root.add_child(_blocks(Part.DRUM, [[Part.DRUM, edge, rim], [Part.DRUM, base, lay.ground]], 1.0, Vector3.ZERO))
	for part: int in by_part:
		root.add_child(_blocks(part, by_part[part], k, centre))
	return root


static func _blocks(part: int, list: Array, k: float, centre: Vector3) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _meshes[part]
	mm.instance_count = list.size()
	var scale := Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3.ZERO)
	for i in list.size():
		var t: Transform3D = list[i][1]
		t.origin -= centre
		mm.set_instance_transform(i, scale * t)
		mm.set_instance_color(i, list[i][2])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _ready_meshes() -> void:
	if not _meshes.is_empty():
		return
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.9
	var box := BoxMesh.new()
	var prism := PrismMesh.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.radial_segments = 8
	cone.rings = 1
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 8
	ball.rings = 4
	var drum := CylinderMesh.new()
	drum.top_radius = 0.5
	drum.bottom_radius = 0.5
	drum.radial_segments = 16
	drum.rings = 1
	_meshes.assign([box, prism, cone, ball, drum])
