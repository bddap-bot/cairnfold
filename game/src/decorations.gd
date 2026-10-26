class_name Decorations
extends Node3D

## Decorations on open ground share a batch per square cell this wide.
const CELL := 16.0

var world: World
var walls: WallTool
## Each standing decoration's place as its build was laid (`xform`), which its build's carry moves it from (`carry`),
## its `bounds`, and its `flames` there.
var placed := {}
## The batches by key, a decoration's place and its lanterns' look (Lamps.lantern): its house's id, its ground cell, or,
## for one held or swept, its id as a String, so it stands alone; each its `node` and the `sig` it was laid from.
var _batches := {}
var _shown := {}
## Decorations a hand carries, as it shows them; moving one moves its node alone.
var _held := {}
var _stamp := {}
## Decorations a delete sweep has taken, hidden until it lets go; the beam passes through them.
var _swept := {}
## Every decoration's flames where they burn, and the light each casts (Lamps.lantern).
var flames := PackedVector3Array()
var lights := PackedColorArray()
## The string a stroke of the decorations tool hangs: the one the style wheel let go on a string last.
var string_style := DecorationLayout.named("Lantern string")


func _init(garden: World, builder: WallTool) -> void:
	world = garden
	walls = builder


## Lays the decorations again where they changed. A house's, or open ground's in one cell, are one batch, since a draw
## per piece costs more than its triangles; only a batch whose pieces changed is laid again.
func sync() -> void:
	var stamp := [world.state.decorations.duplicate(true), world.terrain.revision, _shown.duplicate(true), _held.keys(), _swept.keys()]
	for w in walls.walls:
		stamp.append([w.id, w.layout.laid, w.paint.duplicate()])
	if _stamp.get("value") == stamp:
		return
	_stamp.value = stamp
	var groups := {}
	var frames := {}
	var shown := {}
	for id in world.state.decorations:
		var d: Dictionary = world.state.decorations[id].merged(_shown.get(id, {}), true).merged(_held.get(id, {}), true)
		var x: Variant = frame(d)
		if x == null:
			continue
		var wall := walls.find(d.wall)
		var alone := _held.has(id) or _swept.has(id)
		var at: Variant = str(id) if alone else d.wall if wall != null else Vector2i((Vector2(x.origin.x, x.origin.z) / CELL).floor())
		var group: Array = groups.get_or_add([at, d.lantern], [])
		group.append([id, d.style, d.seed, rise(d), d.mount, span(d), d.get("drop", Vector2.ZERO), wall.paint.duplicate() if wall != null else null, Transform3D.IDENTITY if alone else x])
		frames[id] = x
		shown[id] = d
	var was := placed
	placed = {}
	for key in _batches.keys():
		if groups.get(key) != _batches[key].sig:
			_batches[key].node.free()
			_batches.erase(key)
	for key in groups:
		if _batches.has(key):
			for e in groups[key]:
				placed[e[0]] = was[e[0]]
			continue
		var batch := DecorationLayout.new()
		for e in groups[key]:
			var layout := laid(shown[e[0]])
			if e[7] != null:
				for part in layout.parts:
					part.color = Wall._painted_as(part, e[7])
			var x: Transform3D = frames[e[0]]
			var bounds := DecorationLayout.strung(e[5]) if e[4] == "span" else layout.bounds
			placed[e[0]] = {"xform": x, "bounds": bounds, "flames": PackedVector3Array(layout.flames.map(func(f: Transform3D) -> Vector3: return x * f.origin))}
			batch.add(layout, e[8])
		var n := ToolModels.decoration(batch, key[1])
		n.visible = not (key[0] is String and _swept.has(int(key[0])))
		add_child(n)
		_batches[key] = {"node": n, "sig": groups[key]}
	_place()


## Stands each batch where its house now is, a decoration standing alone where it is, and gathers their flames.
func _place() -> void:
	for key in _batches:
		var w: Wall = walls.find(key[0]) if key[0] is int else null
		_batches[key].node.transform = world_xform(int(key[0])) if key[0] is String else w.transform if w != null else Transform3D.IDENTITY
	flames.clear()
	lights.clear()
	for id in placed:
		var w := _wall_of(id)
		var g := Lamps.light_of(world.state.decorations.get(id, {}).merged(_shown.get(id, {}), true).get("lantern", 0))
		for f in placed[id].flames:
			flames.append(w.transform * f if w != null else f)
			lights.append(g)


## Where decoration `id` stands now, its build's carry included.
func world_xform(id: int) -> Transform3D:
	var w := _wall_of(id)
	return (w.transform if w != null else Transform3D.IDENTITY) * placed[id].xform


func _wall_of(id: int) -> Wall:
	return walls.find(_held.get(id, world.state.decorations.get(id, {})).get("wall", -1))


## Decoration `d` laid about its frame.
func laid(d: Dictionary) -> DecorationLayout:
	var layout := DecorationLayout.new()
	layout.build(d.style, d.seed, rise(d), d.mount, span(d), d.get("drop", Vector2.ZERO))
	return layout


## Where a decoration stands, or null where its surface is gone: on the ground; a string at its first end, facing
## across its span; at a house's foot, out from the wall at `s` on `side`, on the ground or the top of a build the
## house stands on; or, for furniture, at `at` in its house's plan (`plan`), turned `turn` from its ridge, on its floor
## or on a flat roof's deck, so it moves, turns, grows and rises with the house.
func frame(d: Dictionary) -> Variant:
	if d.mount == "span":
		var run: Vector3 = d.to - d.at
		return Transform3D(Basis(Vector3.UP, atan2(-run.z, run.x)), d.at)
	if d.wall < 0:
		return Transform3D(Basis(Vector3.UP, d.turn), Vector3(d.at.x, world.terrain.height_at(d.at.x, d.at.z), d.at.z))
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
	at.y = maxf(world.terrain.height_at(at.x, at.z), w.layout.rest(at.x, at.z))
	return FittingTool._facing(at, normal)


## A string's span from its first end to its second in its frame, or zero for any other decoration.
static func span(d: Dictionary) -> Vector3:
	if d.mount != "span":
		return Vector3.ZERO
	var run: Vector3 = d.to - d.at
	return Vector3(Vector2(run.x, run.z).length(), run.y, 0.0)


## A house's plan on the ground plane: its middle, and its ridge and across it, each scaled to the half span from the
## middle to its inner faces, so (1, 0, 1) is the corner and furniture keeps its share of the room when it is resized.
static func plan(w: Wall) -> Transform3D:
	var r := w.roof
	var f := r.frame()
	var inner := r.half_span() - WallLayout.THICKNESS
	var half := Vector2(inner, inner) if r.kind == RoofLayout.Kind.CONE else Vector2(r.ridge_length() * 0.5 - WallLayout.THICKNESS * 0.5, inner)
	return Transform3D(Basis(f.along * half.x, Vector3.UP, f.across * half.y), Vector3(f.mid.x, 0.0, f.mid.z))


## Moves the decorations on `w` with its stones, as it is carried from where it was laid.
func carry(_w: Wall) -> void:
	_place()


## Whether decoration `id` burns a flame.
func lit(id: int) -> bool:
	return placed.has(id) and not placed[id].flames.is_empty()


func targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in placed:
		if not world.state.decorations.has(id) or _swept.has(id):
			continue
		var x := world_xform(id)
		var d: Dictionary = world.state.decorations[id]
		var b: AABB = placed[id].bounds
		out.append({"decoration": id, "fitting": true, "what": "decoration", "index": id, "value": d, "bounds": x * b, "box": b, "inverse": x.affine_inverse(), "wall": walls.find(d.wall), "on_roof": false})
	return out


func show_reshaped(id: int, data: Dictionary) -> void:
	_shown[id] = data
	sync()


## Shows decoration `id` as `d` while a hand carries it: taken out of its batch once, its own node then moves.
func show_held(id: int, d: Dictionary) -> void:
	_held[id] = d
	sync()
	var x: Variant = frame(d)
	if not placed.has(id) or x == null:
		return
	var was: Transform3D = placed[id].xform
	placed[id].flames = PackedVector3Array(Array(placed[id].flames).map(func(f: Vector3) -> Vector3: return x * (was.affine_inverse() * f)))
	placed[id].xform = x
	_place()


func sweep(id: int) -> void:
	_swept[id] = true
	sync()


## Shows a swept decoration again on the next sync, by when the garden has taken it or kept it.
func unsweep(id: int) -> void:
	_swept.erase(id)


func settle(id: int) -> void:
	_held.erase(id)
	_shown.erase(id)
	sync()


func rise(d: Dictionary) -> float:
	var w := walls.find(d.wall)
	if w == null or d.mount != "foundation":
		return 0.6
	var x: Transform3D = frame(d)
	return maxf(0.1, w.layout.point_at(d.s).y - x.origin.y)
