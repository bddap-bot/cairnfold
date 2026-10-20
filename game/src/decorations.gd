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
		var n := layout.model(d.seed)
		n.transform = x
		n.set_meta(&"bounds", layout.bounds)
		add_child(n)
		nodes[id] = n
		for f in layout.flames:
			flames.append(x * f.origin)


func frame(d: Dictionary) -> Variant:
	if d.wall < 0:
		return Transform3D(Basis(Vector3.UP, d.turn), Vector3(d.at.x, Terrain.height_at(d.at.x, d.at.z), d.at.z))
	var w := walls.find(d.wall)
	if w == null:
		return null
	var f := w.layout.frame_at(d.s)
	var normal: Vector3 = f.tangent.cross(Vector3.UP) * d.side
	var at: Vector3 = f.point + normal * (WallLayout.THICKNESS * 0.5 + 0.02)
	at.y = Terrain.height_at(at.x, at.z)
	return FittingTool._facing(at, normal)


func targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in nodes:
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
	if w == null:
		return 0.6
	var x: Transform3D = frame(d)
	return maxf(0.1, w.layout.point_at(d.s).y - x.origin.y)
