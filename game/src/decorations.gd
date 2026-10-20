class_name Decorations
extends Node3D

var world: World
var walls: WallTool
var nodes := {}
var _shown := {}
var _stamp := {}
var flames := PackedVector3Array()


func _init(garden: World, builder: WallTool) -> void:
	world = garden
	walls = builder


func sync() -> void:
	var stamp := [world.state.decorations.duplicate(true), Terrain.revision, _shown.duplicate(true)]
	for w in walls.walls:
		stamp.append([w.id, w.layout.laid, w.paint.duplicate()])
	if _stamp.get("value") == stamp:
		return
	_stamp.value = stamp
	for n in nodes.values():
		n.free()
	nodes.clear()
	flames.clear()
	for id in world.state.decorations:
		var d: Dictionary = world.state.decorations[id].merged(_shown.get(id, {}), true)
		var x: Variant = frame(d)
		if x == null:
			continue
		var layout := DecorationLayout.new()
		layout.build(d.style, d.seed, rise(d))
		var wall := walls.find(d.wall)
		if wall != null:
			for part in layout.parts:
				part.color = Wall._painted_as(part, wall.paint)
		var n := ToolModels.decoration(layout, d.seed)
		n.transform = x
		n.set_meta(&"bounds", layout.bounds)
		add_child(n)
		nodes[id] = n
		for f in layout.flames:
			flames.append(x * f.origin)


## Where a decoration stands, or null where its surface is gone: on the ground; at a house's foot, out from the wall
## at `s` on `side`; or, for furniture, at `at` in its house's plan (`plan`), turned `turn` from its ridge, on the floor
## nearest `at.y` over its lowest or on a flat roof's deck, so it moves, turns, grows and rises with the house.
func frame(d: Dictionary) -> Variant:
	if d.wall < 0:
		return Transform3D(Basis(Vector3.UP, d.turn), Vector3(d.at.x, Terrain.height_at(d.at.x, d.at.z), d.at.z))
	var w := walls.find(d.wall)
	if w == null:
		return null
	var mount := DecorationLayout.mount_of(d.style)
	if mount != "foundation":
		if w.roof == null or w.layout.floors.is_empty():
			return null
		var x := plan(w)
		var p: Vector3 = x * Vector3(d.at.x, 0.0, d.at.z)
		var turn: float = d.turn + atan2(-x.basis.x.z, x.basis.x.x)
		var l := w.layout
		if mount == "deck":
			if not w.roof.flat() or not w.roof.over(p.x, p.z):
				return null
			return Transform3D(Basis(Vector3.UP, turn), Vector3(p.x, w.roof.height_at(p.x, p.z), p.z))
		if not Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), l.floor_outline):
			return null
		var best := l.floors[0]
		for y in l.floors:
			if absf(y - l.floors[0] - d.at.y) < absf(best - l.floors[0] - d.at.y):
				best = y
		return Transform3D(Basis(Vector3.UP, turn), Vector3(p.x, best, p.z))
	var f := w.layout.frame_at(d.s)
	var normal: Vector3 = f.tangent.cross(Vector3.UP) * d.side
	var at: Vector3 = f.point + normal * (WallLayout.THICKNESS * 0.5 + 0.02)
	at.y = Terrain.height_at(at.x, at.z)
	return FittingTool._facing(at, normal)


## A house's plan on the ground plane: its middle, and its ridge and across it, each scaled to the half span from the
## middle to its inner faces, so (1, 0, 1) is the corner and furniture keeps its share of the room when it is resized.
static func plan(w: Wall) -> Transform3D:
	var r := w.roof
	var f := r.frame()
	var inner := r.half_span() - WallLayout.THICKNESS
	var half := Vector2(inner, inner) if r.kind == RoofLayout.Kind.CONE else Vector2(r.ridge_length() * 0.5 - WallLayout.THICKNESS * 0.5, inner)
	return Transform3D(Basis(f.along * half.x, Vector3.UP, f.across * half.y), Vector3(f.mid.x, 0.0, f.mid.z))


func targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in nodes:
		if not world.state.decorations.has(id):
			continue
		var n: Node3D = nodes[id]
		var d: Dictionary = world.state.decorations[id]
		var b: AABB = n.get_meta(&"bounds")
		out.append({"decoration": id, "fitting": true, "what": "decoration", "index": id, "value": d, "bounds": n.transform * b, "box": b, "inverse": n.transform.affine_inverse(), "wall": walls.find(d.wall), "on_roof": false})
	return out


func show_reshaped(id: int, data: Dictionary) -> void:
	_shown[id] = data
	sync()


func settle(id: int) -> void:
	_shown.erase(id)
	_stamp.clear()
	sync()


func rise(d: Dictionary) -> float:
	var w := walls.find(d.wall)
	if w == null or DecorationLayout.mount_of(d.style) != "foundation":
		return 0.6
	var x: Transform3D = frame(d)
	return maxf(0.1, w.layout.point_at(d.s).y - x.origin.y)
