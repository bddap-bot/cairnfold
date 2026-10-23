class_name Decorations
extends Node3D

var world: World
var walls: WallTool
var nodes := {}
## Each decoration's place as its build was laid, which its build's carry moves it from (`carry`), and its flames there.
var _frames := {}
var _flames := {}
var _shown := {}
## Decorations a hand carries, as it shows them; moving one moves its node alone.
var _held := {}
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
	_frames.clear()
	_flames.clear()
	for id in world.state.decorations:
		var d: Dictionary = world.state.decorations[id].merged(_shown.get(id, {}), true).merged(_held.get(id, {}), true)
		var x: Variant = frame(d)
		if x == null:
			continue
		var layout := DecorationLayout.new()
		layout.build(d.style, d.seed, rise(d), d.mount)
		var wall := walls.find(d.wall)
		if wall != null:
			for part in layout.parts:
				part.color = Wall._painted_as(part, wall.paint)
		var n := ToolModels.decoration(layout, d.seed)
		n.transform = (wall.transform if wall != null else Transform3D.IDENTITY) * x
		n.set_meta(&"bounds", layout.bounds)
		add_child(n)
		nodes[id] = n
		_frames[id] = x
		_flames[id] = PackedVector3Array(layout.flames.map(func(f: Transform3D) -> Vector3: return x * f.origin))
	_gather()


## Where a decoration stands, or null where its surface is gone: on the ground; at a house's foot, out from the wall
## at `s` on `side`, on the ground or the top of a build the house stands on; or, for furniture, at `at` in its
## house's plan (`plan`), turned `turn` from its ridge, on its floor or on a flat roof's deck, so it moves, turns, grows
## and rises with the house.
func frame(d: Dictionary) -> Variant:
	if d.wall < 0:
		return Transform3D(Basis(Vector3.UP, d.turn), Vector3(d.at.x, Terrain.height_at(d.at.x, d.at.z), d.at.z))
	var w := walls.find(d.wall)
	if w == null:
		return null
	var mount: String = d.mount
	if mount != "foundation":
		if w.roof == null or w.layout.floor_y == -INF:
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
		return Transform3D(Basis(Vector3.UP, turn), Vector3(p.x, l.floor_y, p.z))
	var f := w.layout.frame_at(d.s)
	var normal: Vector3 = f.tangent.cross(Vector3.UP) * d.side
	var at: Vector3 = f.point + normal * (WallLayout.THICKNESS * 0.5 + 0.02)
	at.y = maxf(Terrain.height_at(at.x, at.z), w.layout.rest(at.x, at.z))
	return FittingTool._facing(at, normal)


## A house's plan on the ground plane: its middle, and its ridge and across it, each scaled to the half span from the
## middle to its inner faces, so (1, 0, 1) is the corner and furniture keeps its share of the room when it is resized.
static func plan(w: Wall) -> Transform3D:
	var r := w.roof
	var f := r.frame()
	var inner := r.half_span() - WallLayout.THICKNESS
	var half := Vector2(inner, inner) if r.kind == RoofLayout.Kind.CONE else Vector2(r.ridge_length() * 0.5 - WallLayout.THICKNESS * 0.5, inner)
	return Transform3D(Basis(f.along * half.x, Vector3.UP, f.across * half.y), Vector3(f.mid.x, 0.0, f.mid.z))


## Moves the decorations on `w` with its stones, as it is carried from where it was laid.
func carry(w: Wall) -> void:
	for id in nodes:
		if world.state.decorations.has(id) and world.state.decorations[id].wall == w.id:
			nodes[id].transform = w.transform * _frames[id]
	_gather()


func _gather() -> void:
	flames.clear()
	for id in _flames:
		var w := walls.find(world.state.decorations.get(id, {}).get("wall", -1))
		for f in _flames[id]:
			flames.append(w.transform * f if w != null else f)


func targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in nodes:
		var n: Node3D = nodes[id]
		# One a delete sweep has taken is hidden, and its beam passes through it.
		if not world.state.decorations.has(id) or not n.visible:
			continue
		var d: Dictionary = world.state.decorations[id]
		var b: AABB = n.get_meta(&"bounds")
		out.append({"decoration": id, "fitting": true, "what": "decoration", "index": id, "value": d, "bounds": n.transform * b, "box": b, "inverse": n.transform.affine_inverse(), "wall": walls.find(d.wall), "on_roof": false})
	return out


func show_reshaped(id: int, data: Dictionary) -> void:
	_shown[id] = data
	sync()


## Shows decoration `id` as `d` while a hand carries it: its node moves, nothing is laid again.
func show_held(id: int, d: Dictionary) -> void:
	_held[id] = d
	var x: Variant = frame(d)
	if not nodes.has(id) or x == null:
		return
	var wall := walls.find(d.wall)
	nodes[id].transform = (wall.transform if wall != null else Transform3D.IDENTITY) * x
	var layout_flames: PackedVector3Array = _flames.get(id, PackedVector3Array())
	var was: Transform3D = _frames[id]
	_flames[id] = PackedVector3Array(Array(layout_flames).map(func(f: Vector3) -> Vector3: return x * (was.affine_inverse() * f)))
	_frames[id] = x
	_gather()


func settle(id: int) -> void:
	_held.erase(id)
	_shown.erase(id)
	_stamp.clear()
	sync()


func rise(d: Dictionary) -> float:
	var w := walls.find(d.wall)
	if w == null or d.mount != "foundation":
		return 0.6
	var x: Transform3D = frame(d)
	return maxf(0.1, w.layout.point_at(d.s).y - x.origin.y)
