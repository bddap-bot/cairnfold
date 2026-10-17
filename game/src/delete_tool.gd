class_name DeleteTool
extends Node3D

## Takes things away, for whichever hand holds it. Its beam strikes the first wall, tree or bush along it, else the
## ground. Held, the trigger is an eraser for everything the beam passes over in one stroke: along a wall, the
## stretch it swept breaks away into a ruin, stepped down to a gap at its foot with fallen stones (a tap breaks a
## short gap); a tree or bush it strikes goes, and so does the path or stone ground it meets, giving back the ground
## under it; elsewhere on the ground it mows the grass and flowers under the brush ring, the meadow's own as well
## as painted ones, raggedly at the ring's edge. Ruins and taken plants show as the beam passes; the whole stroke
## goes to the garden as one command when the trigger lets go, so one undo puts it all back. A sweep that would
## leave a wall nothing worth standing, or one on a fence, house or tower, takes the whole of it.
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
## Between frames a stroke takes what rays this far apart where they strike meet, so a quick swipe skips nothing.
const STEP := 0.5
const MAX_STEPS := 32

var rig: Rig
var walls: WallTool
var flora: Flora
var world: World
var _buttons: Array[Buttons] = []
var _rings: Array[MeshInstance3D] = []
## Strokes under way, by whoever holds the trigger (a hand, or the driver): {walls, wall, moved, plants, marks, ray}.
## `walls` holds by wall id the stretches swept along it, Vector2(from, to) unwrapped round a loop, and `moved` those
## walls swept since last shown; `wall` is the sweep along the wall the beam is on, {wall, id, span, at, last};
## `plants` the plants taken; `marks` the ops taking paths and stone strokes, by id; `ray` the last ray, [origin,
## dir, where it struck].
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
		_buttons.append(Buttons.new(h).watch(["tool"]))
		_rings.append(FloraTool.ring(TINT))
		add_child(_rings[-1])


## Whether `hand`, or with none any hand, has a cut or charge under way.
func busy(hand: Hand = null) -> bool:
	if hand != null:
		return _cuts.has(hand) or _charges.has(hand)
	return not _cuts.is_empty() or not _charges.is_empty()


func _process(delta: float) -> void:
	for k in _buttons.size():
		var b := _buttons[k]
		var hand: Hand = b.hand
		_rings[k].visible = false
		var live := hand.tool == Hand.Tool.DELETE and rig.aim_hand != hand and hand.get_has_tracking_data()
		var t := hand.global_transform
		if _cuts.has(hand):
			if live and b.held("tool"):
				var target := hold(hand, t.origin, -t.basis.z)
				hand.point(target.get("point"), TINT)
				if target.has("mow"):
					FloraTool.put_ring(_rings[k], target.point, target.mow)
			else:
				let_go(hand)
		elif _charges.has(hand):
			if live and b.held("tool"):
				if charge(hand, t.origin, -t.basis.z, delta):
					hand.point(t.origin - t.basis.z * ORB_REACH, TINT)
			else:
				cancel(hand)
		elif live and b.pressed("tool") and sky(-t.basis.z):
			charge(hand, t.origin, -t.basis.z, delta)
		elif live:
			if b.pressed("tool"):
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
## meets nothing. It passes through the plants in `taken`, which a stroke has already taken.
func aim(origin: Vector3, dir: Vector3, taken := {}) -> Dictionary:
	var ground: Variant = Terrain.raycast(origin, dir, REACH)
	var reach: float = (ground - origin).dot(dir) if ground != null else REACH
	var pick := walls.pick_wall(origin, dir)
	var solid := flora.solid_hit(origin, dir, reach, taken)
	if not pick.is_empty() and (solid.is_empty() or pick.along <= solid.along):
		return {"wall": pick.wall, "s": pick.s, "point": pick.point}
	if not solid.is_empty():
		return {"plants": solid.plants, "point": solid.point}
	if ground == null:
		return {}
	if Ground.laid_bare(ground.x, ground.z) >= 0.5:
		return {"laid": true, "point": ground}
	return {"mow": FloraTool.brush_radius(origin, ground), "point": ground}


## Starts `who`'s stroke. Strokes still growing grow at once, so it takes plants not yet grown under it.
func press(who: Object, origin: Vector3, dir: Vector3) -> void:
	flora.grow_now()
	_cuts[who] = {"walls": {}, "wall": {}, "plants": {}, "marks": {}, "moved": {}}
	var target := _stroke(_cuts[who], origin, dir)
	_cuts[who].ray = [origin, dir, target.get("point", origin + dir)]
	_preview(_cuts[who])


## The trigger is still held by `who`, its ray now from `origin` along `dir`: takes what the rays since the last
## one meet into the stroke and returns what this one aims at (see `aim`).
func hold(who: Object, origin: Vector3, dir: Vector3) -> Dictionary:
	var cut: Dictionary = _cuts.get(who, {})
	if cut.is_empty():
		return {}
	var was: Array = cut.ray
	var far := Vector3(aim(origin, dir, cut.plants).get("point", origin + dir))
	var n := clampi(ceili(far.distance_to(was[2]) / STEP), 1, MAX_STEPS)
	var target := {}
	for i in range(1, n + 1):
		var k := float(i) / n
		target = _stroke(cut, was[0].lerp(origin, k), was[1].normalized().slerp(dir.normalized(), k))
	cut.ray = [origin, dir, target.get("point", origin + dir)]
	_preview(cut)
	return target


func _stroke(cut: Dictionary, origin: Vector3, dir: Vector3) -> Dictionary:
	var target := aim(origin, dir, cut.plants)
	var on: Wall = cut.wall.get("wall")
	if on != null:
		var hit := sweep(cut, origin, dir)
		if target.get("wall") == on:
			target.point = hit.get("point", target.point)
		elif hit.get("distance", INF) >= WallTool.WALL_PICK:
			cut.wall = {}
	if target.has("wall"):
		if target.wall != cut.wall.get("wall"):
			begin(cut, target.wall, target.s)
	elif target.has("plants"):
		for p: Flora.Plant in target.plants:
			p.draw(false)
			cut.plants[p] = true
	elif target.has("laid"):
		var id := Ground.mark_at(target.point.x, target.point.z)
		if id >= 0:
			cut.marks[id] = "unpath" if world.state.paths.has(id) else "unground"
	elif target.has("mow"):
		_mow(cut, target.point, target.mow)
	return target


## Shows the plants under a ring at `at` taken, on this machine only, until the stroke's command comes back. Plants
## parted to nothing by a path or stone are left, so lifting that brings them back.
func _mow(cut: Dictionary, at: Vector3, radius: float) -> void:
	for p in flora.plants_near(at, radius):
		var reach := radius * (1.0 - RAGGED * float(hash(p.anchor) % 1024) / 1024.0)
		if not cut.plants.has(p) and Vector2(p.anchor.x - at.x, p.anchor.z - at.z).length() < reach and not Flora.on_path(p.anchor):
			p.draw(false)
			cut.plants[p] = true


func _show(plants: Array) -> Dictionary:
	var by_group := {}
	for p: Flora.Plant in plants:
		by_group.get_or_add(p.group, []).append(p.index)
	for g in by_group:
		by_group[g] = PackedInt32Array(by_group[g])
	return {"op": "show", "plants": by_group, "on": false}


## Starts erasing wall `w` at arc length `s`, a stretch of its own beside any the stroke swept before.
func begin(cut: Dictionary, w: Wall, s: float) -> void:
	cut.wall = {"wall": w, "id": w.id, "span": cut.walls.get_or_add(w.id, []).size(), "at": s, "last": s}
	cut.walls[w.id].append(Vector2(s, s))
	cut.moved[w.id] = true


## Follows a ray along the wall being erased; returns where on the wall the ray is nearest and how near (see
## `Wall.ray_distance`), or {} when the wall is gone.
func sweep(cut: Dictionary, origin: Vector3, dir: Vector3) -> Dictionary:
	var on: Dictionary = cut.wall
	var w: Wall = on.wall
	if not _standing(w):
		cut.walls.erase(on.id)
		cut.wall = {}
		return {}
	var hit := w.ray_distance(origin, dir)
	on.at += w.layout.offset(hit.s, on.last)
	on.last = hit.s
	var span: Vector2 = cut.walls[w.id][on.span]
	cut.walls[w.id][on.span] = Vector2(minf(span.x, on.at), maxf(span.y, on.at))
	cut.moved[w.id] = true
	return hit


func _standing(w: Wall) -> bool:
	return is_instance_valid(w) and walls.find(w.id) == w and world.state.walls.has(w.id)


## Sends the stroke as one command: the plants taken, the paths and stone lifted, and per wall a reshape breaking
## the swept stretches away, or the whole wall when nothing would stand. Walls and plants are drawn as the garden
## has them again once the command is settled.
func let_go(who: Object) -> void:
	var cut: Dictionary = _cuts.get(who, {})
	_cuts.erase(who)
	if cut.is_empty():
		return
	var plants: Array = cut.plants.keys()
	var cmds := [] if plants.is_empty() else [_show(plants)]
	var swept: Array[int] = []
	for id: int in cut.walls:
		if walls.find(id) == null or not world.state.walls.has(id):
			continue
		swept.append(id)
		var ruins := _ruins(id, cut.walls[id])
		if ruins.is_empty():
			cmds.append({"op": "unwall", "ids": PackedInt32Array([id])})
		elif ruins != Array(world.state.walls[id].ruins):
			cmds.append({"op": "reshape", "id": id, "data": {"ruins": PackedVector2Array(ruins)}})
	for id: int in cut.marks:
		cmds.append({"op": cut.marks[id], "id": id})
	var settle := func() -> void:
		for id in swept:
			walls.settle(id)
		for p: Flora.Plant in plants:
			p.draw(p.shown())
	if cmds.is_empty():
		settle.call()
	else:
		world.submit({"op": "batch", "cmds": cmds.slice(0, Commands.MAX_BATCH)}, settle)


## Wall `id`'s ruins as the garden has them once the stretches `spans` break away (unwrapped round a loop), or
## none when the whole wall goes. A fence, house or tower goes whole.
func _ruins(id: int, spans: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var w := walls.find(id)
	if w.layout.fence or w.roof != null:
		return out
	var total := w.layout.length()
	var left: Array[Vector2] = []
	left.assign(Array(world.state.walls[id].ruins))
	for span: Vector2 in spans:
		left = WallLayout.ruins_after(left, total, w.layout.closed, span.x, span.y)
	if left.size() == 1 and left[0] == Vector2(0.0, total):
		return out
	return left


## Shows the walls the stroke moved on broken as it would leave them, on this machine only, until its command
## comes back: once a frame, however many rays the frame took.
func _preview(cut: Dictionary) -> void:
	for id: int in cut.moved:
		var w := walls.find(id)
		if w == null or not world.state.walls.has(id) or w.layout.fence or w.roof != null:
			continue
		var ruins := _ruins(id, cut.walls[id])
		if ruins.is_empty():
			ruins.append(Vector2(0.0, w.layout.length()))
		if ruins != w.layout.ruins:
			w.layout.ruins = ruins
			w.rebuild(false)
	cut.moved.clear()
