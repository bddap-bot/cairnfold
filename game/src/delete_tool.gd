class_name DeleteTool
extends Node3D

## Takes things away, for whichever hand holds it. Its beam strikes the first wall, tree or bush along it, else the
## ground. On a wall the trigger is an eraser: held, its beam sweeps along the wall, and the stretch it swept breaks
## away into a ruin, stepped down to a gap at its foot with fallen stones; a tap breaks a short gap. The ruin shows
## as it is swept and goes to the garden when the trigger lets go. A sweep that would leave nothing worth standing,
## or one on a fence, house or tower, takes the whole of it. A press on a tree or bush takes it, and one on a path
## or stone ground takes that path or stroke, giving back the ground under it. Elsewhere on the ground the trigger
## mows: held, it takes the grass and flowers under the brush ring as it sweeps, the meadow's own as well as
## painted ones, raggedly at the ring's edge; they go to the garden when the trigger lets go.
## Held pointed up at the sky, the trigger charges a swelling orb and, once it is full, wipes the whole garden back
## to bare meadow; letting go or lowering the beam first lets it fade. Only the garden's host can wipe it. Undo puts
## any of it back, a wipe in one step.

const TINT := Color(1.0, 0.7, 0.62, 0.6)
const REACH := 80.0
## How far in from the ring's edge, as a fraction of its radius, mowing may stop short: each plant has its own reach.
const RAGGED := 0.3
const WIPE_HOLD := 2.0
## A beam this far up (the sine of its elevation) points at the sky.
const SKY := 0.6
const ORB_REACH := 5.0
const ORB_RADIUS := 1.2

var rig: Rig
var walls: WallTool
var flora: Flora
var world: World
var _buttons: Array[Buttons] = []
var _rings: Array[MeshInstance3D] = []
## Holds under way, by whoever holds the trigger (a hand, or the driver): a sweep along a wall, {wall, from, to,
## at, last, whole} with `from` and `to` unwrapped round a loop, or a mow, {mown}, the plants it has taken so far.
var _cuts := {}
## Wipes charging, by whoever holds the trigger up: {t, orb}.
var _charges := {}


func _init(player: Rig, builder: WallTool, plants: FloraTool, garden: World) -> void:
	rig = player
	walls = builder
	flora = plants.flora
	world = garden
	world.restored.connect(func() -> void:
		_cuts.clear()
		for who in _charges.keys():
			cancel(who))
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))
		_rings.append(FloraTool.ring(TINT))
		add_child(_rings[-1])


func busy() -> bool:
	return not _cuts.is_empty() or not _charges.is_empty()


func _process(delta: float) -> void:
	for k in _buttons.size():
		var b := _buttons[k]
		var hand: Hand = b.hand
		_rings[k].visible = false
		var live := hand.tool == Hand.Tool.DELETE and rig.aim_hand != hand and hand.get_has_tracking_data()
		var t := hand.global_transform
		if _cuts.has(hand):
			if live and b.held("trigger_click"):
				var at := hold(hand, t.origin, -t.basis.z)
				hand.point(at, TINT)
				if _cuts[hand].has("mown"):
					FloraTool.put_ring(_rings[k], at, FloraTool.brush_radius(t.origin, at))
			else:
				let_go(hand)
		elif _charges.has(hand):
			if live and b.held("trigger_click"):
				if charge(hand, t.origin, -t.basis.z, delta):
					hand.point(t.origin - t.basis.z * ORB_REACH, TINT)
			else:
				cancel(hand)
		elif live and b.pressed("trigger_click") and sky(-t.basis.z):
			charge(hand, t.origin, -t.basis.z, delta)
		elif live:
			if b.pressed("trigger_click"):
				press(hand, t.origin, -t.basis.z)
			else:
				var target := aim(t.origin, -t.basis.z)
				hand.point(target.get("point"), TINT)
				if target.has("mow"):
					FloraTool.put_ring(_rings[k], target.point, target.mow)
		b.latch()


func sky(dir: Vector3) -> bool:
	return dir.normalized().y > SKY


## Charges a wipe for `who` pointing from `origin` along `dir`, `delta` seconds more; at WIPE_HOLD it wipes the
## garden. Pointing below the sky lets the charge go. Whether it is still charging.
func charge(who: Object, origin: Vector3, dir: Vector3, delta: float) -> bool:
	if not sky(dir) or not world.multiplayer.is_server():
		cancel(who)
		return false
	if not _charges.has(who):
		_charges[who] = {"t": 0.0, "orb": _orb()}
	var c: Dictionary = _charges[who]
	c.t += delta
	if c.t >= WIPE_HOLD:
		cancel(who)
		world.submit({"op": "wipe"})
		return false
	var k: float = c.t / WIPE_HOLD
	var orb: MeshInstance3D = c.orb
	orb.global_position = origin + dir.normalized() * ORB_REACH
	orb.scale = Vector3.ONE * maxf(k * k, 0.01)
	(orb.material_override as StandardMaterial3D).albedo_color = Color(TINT, lerpf(0.15, 0.85, k))
	return true


func cancel(who: Object) -> void:
	var c: Dictionary = _charges.get(who, {})
	_charges.erase(who)
	if c.has("orb"):
		c.orb.queue_free()


func _orb() -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = ORB_RADIUS
	sphere.height = ORB_RADIUS * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = TINT
	var orb := MeshInstance3D.new()
	orb.mesh = sphere
	orb.material_override = mat
	orb.top_level = true
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orb)
	return orb


## What a ray from `origin` along `dir` takes, with the `point` it meets: a wall and where along it, a tree or
## bush (`plants`), path or stone ground (`laid`), or the ground to mow with a brush of radius `mow`; {} when it
## meets nothing.
func aim(origin: Vector3, dir: Vector3) -> Dictionary:
	var ground: Variant = Terrain.raycast(origin, dir, REACH)
	var reach: float = (ground - origin).dot(dir) if ground != null else REACH
	var pick := walls.pick_wall(origin, dir)
	var solid := flora.solid_hit(origin, dir, reach)
	if not pick.is_empty() and (solid.is_empty() or pick.along <= solid.along):
		return {"wall": pick.wall, "s": pick.s, "point": pick.point}
	if not solid.is_empty():
		return {"plants": solid.plants, "point": solid.point}
	if ground == null:
		return {}
	if Ground.laid_bare(ground.x, ground.z) >= 0.5:
		return {"laid": true, "point": ground}
	return {"mow": FloraTool.brush_radius(origin, ground), "point": ground}


func press(who: Object, origin: Vector3, dir: Vector3) -> void:
	var target := aim(origin, dir)
	if target.has("wall"):
		begin(who, target.wall, target.s)
		return
	if target.has("plants"):
		_take(target.plants)
		return
	if target.has("laid"):
		var id := Ground.mark_at(target.point.x, target.point.z)
		if id >= 0:
			world.submit({"op": "unpath" if world.state.paths.has(id) else "unground", "id": id})
			return
	if target.has("point"):
		_cuts[who] = {"mown": {}}
		_mow(_cuts[who], target.point, FloraTool.brush_radius(origin, target.point))


## The trigger is still held by `who`, its ray now from `origin` along `dir`; returns where the beam meets what it
## is taking.
func hold(who: Object, origin: Vector3, dir: Vector3) -> Vector3:
	var cut: Dictionary = _cuts.get(who, {})
	if not cut.has("mown"):
		return sweep(who, origin, dir)
	var ground: Variant = Terrain.raycast(origin, dir, REACH)
	if ground == null:
		return origin + dir
	_mow(cut, ground, FloraTool.brush_radius(origin, ground))
	return ground


## Shows the plants under a ring at `at` taken, on this machine only, until the mow's command comes back. Plants
## parted to nothing by a path or stone are left, so lifting that brings them back.
func _mow(cut: Dictionary, at: Vector3, radius: float) -> void:
	for p in flora.plants_near(at, radius):
		var reach := radius * (1.0 - RAGGED * float(hash(p.anchor) % 1024) / 1024.0)
		if not cut.mown.has(p) and Vector2(p.anchor.x - at.x, p.anchor.z - at.z).length() < reach and not Flora.on_path(p.anchor):
			p.draw(false)
			cut.mown[p] = true


func _take(plants: Array, done := Callable()) -> void:
	var by_group := {}
	for p: Flora.Plant in plants:
		by_group.get_or_add(p.group, []).append(p.index)
	for g in by_group:
		by_group[g] = PackedInt32Array(by_group[g])
	world.submit({"op": "show", "plants": by_group, "on": false}, done)


## Starts erasing wall `w` at arc length `s`. A fence, house or tower is taken whole, so it shows no ruin.
func begin(who: Object, w: Wall, s: float) -> void:
	_cuts[who] = {"wall": w, "from": s, "to": s, "at": s, "last": s, "whole": w.layout.fence or w.roof != null}
	_preview(_cuts[who])


## Follows a ray along the wall being erased and returns the point on it the ray is nearest.
func sweep(who: Object, origin: Vector3, dir: Vector3) -> Vector3:
	var cut: Dictionary = _cuts.get(who, {})
	var w: Wall = cut.get("wall")
	if w == null or not is_instance_valid(w) or walls.find(w.id) != w:
		_cuts.erase(who)
		return origin + dir
	var hit := w.ray_distance(origin, dir)
	cut.at += w.layout.offset(hit.s, cut.last)
	cut.last = hit.s
	cut.from = minf(cut.from, cut.at)
	cut.to = maxf(cut.to, cut.at)
	_preview(cut)
	return hit.point


## Sends what was taken: the mown plants, or for a wall a reshape breaking the swept stretch away, or the whole
## wall when nothing would stand. Mown plants are drawn as the garden has them again once their hide is settled.
func let_go(who: Object) -> void:
	var cut: Dictionary = _cuts.get(who, {})
	_cuts.erase(who)
	if cut.has("mown"):
		var mown: Array = cut.mown.keys()
		if not mown.is_empty():
			_take(mown, func() -> void:
				for p: Flora.Plant in mown:
					p.draw(p.shown()))
		return
	var w: Wall = cut.get("wall")
	if w == null or not is_instance_valid(w) or walls.find(w.id) != w:
		return
	var ruins := _ruins(cut)
	if ruins.is_empty():
		world.submit({"op": "unwall", "ids": PackedInt32Array([w.id])}, walls.settle.bind(w.id))
	elif ruins == Array(world.state.walls[w.id].ruins):
		walls.settle(w.id)
	else:
		world.submit({"op": "reshape", "id": w.id, "data": {"ruins": PackedVector2Array(ruins)}}, walls.settle.bind(w.id))


## The wall's ruins once the sweep breaks away, or none when the whole wall goes.
func _ruins(cut: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if cut.whole:
		return out
	var w: Wall = cut.wall
	var standing: Array[Vector2] = []
	standing.assign(Array(world.state.walls[w.id].ruins))
	var total := w.layout.length()
	var left := WallLayout.ruins_after(standing, total, w.layout.closed, cut.from, cut.to)
	if left.size() == 1 and left[0] == Vector2(0.0, total):
		return out
	return left


## Shows the wall broken as the sweep would leave it, on this machine only, until its command comes back.
func _preview(cut: Dictionary) -> void:
	if cut.whole:
		return
	var w: Wall = cut.wall
	var ruins := _ruins(cut)
	if ruins.is_empty():
		ruins.append(Vector2(0.0, w.layout.length()))
	if ruins != w.layout.ruins:
		w.layout.ruins = ruins
		w.rebuild(false)
