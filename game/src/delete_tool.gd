class_name DeleteTool
extends Node3D

## Takes things away, for whichever hand holds it. Its beam strikes the first wall, easel, boulder, tree or bush along it, else
## the ground. Held, the trigger is an eraser for everything the beam passes over in one stroke: along a wall, the
## stretch it swept breaks away into a ruin, stepped down to a gap at its foot with fallen stones (a tap breaks a
## short gap); an easel, boulder, tree or bush it strikes goes, and so does the path or stone ground it meets, giving back the ground
## under it; elsewhere on the ground it mows the grass and flowers under the brush ring, the meadow's own as well
## as painted ones, raggedly at the ring's edge. Ruins and taken plants show as the beam passes; the whole stroke
## goes to the garden as one command when the trigger lets go, so one undo puts it all back. A sweep that would
## leave a wall nothing worth standing, or one on a fence, house or tower, takes the whole of it.
## Held pointed up at the sky, the trigger charges a swelling orb and, once it is full, wipes the whole garden back
## to bare meadow; letting go or lowering the beam first lets it fade. Anyone in the garden can wipe it. Undo puts
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
## A beam on a wall whose end moves this far in a frame is breaking it, and is heard to.
const SWEEPING := 0.005

var rig: Rig
var walls: WallTool
var flora: Flora
var world: World
var _buttons: Array[Buttons] = []
var _rings: Array[MeshInstance3D] = []
## Strokes under way, by whoever holds the trigger (a hand, or the driver): {walls, wall, moved, plants, marks, easels,
## boulders, ray}.
## `walls` holds by wall id the stretches swept along it, Vector2(from, to) unwrapped round a loop, and `moved` those
## walls swept since last shown; `wall` is the sweep along the wall the beam is on, {wall, id, span, at, last};
## `plants` the plants taken; `marks` the tables of the stairs, paths and stone strokes taken, by id; `easels` and `boulders` those taken, by id;
## `ray` the last ray, [origin, dir, where it struck].
var _cuts := {}
## Wipes charging, by whoever holds the trigger up: {t, orb}.
var _charges := {}


func _init(player: Rig, builder: WallTool, plants: FloraTool, garden: World) -> void:
	rig = player
	walls = builder
	flora = plants.flora
	world = garden
	world.restored.connect(func() -> void:
		for cut: Dictionary in _cuts.values():
			for id: int in cut.get("decorations", {}):
				world.decorations.unsweep(id)
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
		var live := hand.tool == Hand.Tool.DELETE and rig.aim_hand != hand and hand.tracked()
		var t := hand.global_transform
		if _cuts.has(hand):
			if live and b.held("tool"):
				var target := hold(hand, t.origin, -t.basis.z)
				hand.point(target.get("point"), TINT)
				show_target(_rings[k], target, rig.head.global_position)
			else:
				let_go(hand)
		elif _charges.has(hand):
			if live and b.held("tool"):
				if charge(hand, t.origin, -t.basis.z, delta):
					hand.point(t.origin - t.basis.z * ORB_REACH, TINT)
			else:
				cancel(hand)
		elif live and b.pressed("tool") and sky(-t.basis.z) and aim(t.origin, -t.basis.z).is_empty():
			charge(hand, t.origin, -t.basis.z, delta)
		elif live:
			if b.pressed("tool"):
				press(hand, t.origin, -t.basis.z)
			else:
				var target := aim(t.origin, -t.basis.z)
				hand.point(target.get("point"), TINT)
				show_target(_rings[k], target, rig.head.global_position)
		b.latch()


func sky(dir: Vector3) -> bool:
	return dir.normalized().y > SKY


## Charges a wipe for `who` pointing from `origin` along `dir`, `delta` seconds more; at WIPE_HOLD it wipes the
## garden. Pointing below the sky lets the charge go. Whether it is still charging.
func charge(who: Object, origin: Vector3, dir: Vector3, delta: float) -> bool:
	if not sky(dir) or not aim(origin, dir).is_empty():
		cancel(who)
		return false
	if not _charges.has(who):
		_charges[who] = {"t": 0.0, "orb": _orb()}
	var c: Dictionary = _charges[who]
	c.t += delta
	var k: float = c.t / WIPE_HOLD
	var orb: MeshInstance3D = c.orb
	if c.t >= WIPE_HOLD:
		Cues.play(Cues.Act.WIPE, orb.global_position, who as XRController3D)
		cancel(who)
		world.submit({"op": "wipe"})
		return false
	Cues.play(Cues.Act.WIPE_CHARGE, orb.global_position, who as XRController3D, k)
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
	var orb := MeshInstance3D.new()
	orb.mesh = sphere
	orb.material_override = Meshes.glow(TINT)
	orb.top_level = true
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orb)
	return orb


## What a ray from `origin` along `dir` takes, with the `point` it meets: a wall and where along it, an easel, a tree
## or bush (`plants`), a boulder, path or stone ground (`laid`), or the ground to mow with a brush of radius `mow`; {}
## when it meets nothing. It passes through the plants in `taken`, which a stroke has already taken, and the easels and
## boulders by id in `gone`.
func aim(origin: Vector3, dir: Vector3, taken := {}, gone := {}) -> Dictionary:
	var hits := world.pick(origin, dir, {World.Kind.GROUND: REACH, World.Kind.EASEL: REACH, World.Kind.TARGET: REACH, World.Kind.BOULDER: REACH, World.Kind.PLANT: REACH, World.Kind.STAIRS: REACH}, taken.merged(gone), [World.Kind.EASEL, World.Kind.TARGET])
	if hits.is_empty():
		return {}
	var hit: Dictionary = hits.values().back()
	match hits.keys().back():
		World.Kind.STAIRS, World.Kind.TARGET:
			return hit
		World.Kind.PLANT:
			return {"plants": hit.plants, "point": hit.point}
		World.Kind.EASEL:
			return {"easel": hit.easel, "point": hit.point}
		World.Kind.BOULDER:
			return {"boulder": hit.boulder, "point": hit.point}
	if world.marks.laid_bare(hit.point.x, hit.point.z) >= 0.5:
		return {"laid": true, "point": hit.point}
	return {"mow": FloraTool.brush_radius(origin, hit.point), "point": hit.point}


## Starts `who`'s stroke. Strokes still growing grow at once, so it takes plants not yet grown under it.
func press(who: Object, origin: Vector3, dir: Vector3) -> void:
	var target := aim(origin, dir)
	if target.has("fitting") or target.get("rubble", false):
		_cuts[who] = {"single": target}
		return
	flora.grow_now()
	_cuts[who] = {"walls": {}, "wall": {}, "plants": {}, "marks": {}, "moved": {}, "easels": {}, "fittings": {}, "boulders": {}, "decorations": {}, "pieces": {}}
	target = _stroke(_cuts[who], origin, dir)
	_cuts[who].ray = [origin, dir, target.get("point", origin + dir)]
	_preview(_cuts[who])
	if _taken(_cuts[who]) > 0 or not _cuts[who].wall.is_empty():
		Cues.play(Cues.Act.DELETE_SWEEP, _cuts[who].ray[2], who as XRController3D)


## The trigger is still held by `who`, its ray now from `origin` along `dir`: takes what the rays since the last
## one meet into the stroke and returns what this one aims at (see `aim`).
func hold(who: Object, origin: Vector3, dir: Vector3) -> Dictionary:
	var cut: Dictionary = _cuts.get(who, {})
	if cut.is_empty():
		return {}
	if cut.has("single"):
		return cut.single if cut.single.has("decoration") or cut.single.has("path") or is_instance_valid(cut.single.wall) else {}
	var was: Array = cut.ray
	var aimed := aim(origin, dir, cut.plants, _gone(cut))
	var far := Vector3(aimed.get("point", origin + dir))
	var n := steps(far.distance_to(was[2]), aimed.get("mow", 0.0))
	var target := {}
	var taken := _taken(cut)
	for i in range(1, n + 1):
		var k := float(i) / n
		target = _stroke(cut, was[0].lerp(origin, k), was[1].normalized().slerp(dir.normalized(), k))
	cut.ray = [origin, dir, target.get("point", origin + dir)]
	_preview(cut)
	if _taken(cut) > taken or (not cut.wall.is_empty() and cut.ray[2].distance_to(was[2]) > SWEEPING):
		Cues.play(Cues.Act.DELETE_SWEEP, cut.ray[2], who as XRController3D)
	return target



static func _taken(cut: Dictionary) -> int:
	return cut.walls.size() + cut.plants.size() + cut.marks.size() + cut.easels.size() + cut.fittings.size() + cut.boulders.size() + cut.decorations.size() + cut.pieces.size()


static func _gone(cut: Dictionary) -> Dictionary:
	return cut.easels.merged(cut.boulders)


## How many rays a stroke takes between two where they strike `metres` apart: STEP apart, or over the ground half a
## mowing ring of `mow` metres apart, which every plant's ragged reach still covers, so a wide ring is not mown again
## and again in one swipe.
static func steps(metres: float, mow := 0.0) -> int:
	return clampi(ceili(metres / maxf(STEP, mow * 0.5)), 1, MAX_STEPS)


func _stroke(cut: Dictionary, origin: Vector3, dir: Vector3) -> Dictionary:
	var target := aim(origin, dir, cut.plants, _gone(cut))
	if target.has("decoration"):
		cut.decorations[target.decoration] = target
		world.decorations.sweep(target.decoration)
		return target
	if target.has("path"):
		var taken: Array = cut.pieces.get_or_add(target.path, [])
		if not taken.has(target.value):
			taken.append(target.value)
		return target
	if target.has("fitting"):
		# A sweep along a wall takes the clutter at its foot or on its top as it goes, and keeps on along the wall.
		var along: bool = target.key == "clutter" and cut.wall.get("wall") == target.wall
		if along:
			sweep(cut, origin, dir)
		else:
			cut.wall = {}
		var items: Array = cut.fittings.get_or_add(target.wall.id, [])
		if not items.any(func(item: Dictionary) -> bool: return item.key == target.key and item.value == target.value):
			items.append(target)
		return target
	# Rubble created by this stroke must not turn its partial teardown into a whole-wall delete.
	if target.get("rubble", false) and not cut.walls.has(target.wall.id):
		cut.wall = {}
		cut.walls[target.wall.id] = [Vector2(0.0, target.wall.layout.length())]
		cut.moved[target.wall.id] = true
		return target
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
	elif target.has("easel"):
		target.easel.visible = false
		cut.easels[target.easel.id] = target.easel
	elif target.has("boulder"):
		target.boulder.visible = false
		cut.boulders[target.boulder.id] = target.boulder
	elif target.has("plants"):
		for p: Flora.Plant in target.plants:
			p.draw(false)
			cut.plants[p] = true
	elif target.has("stair"):
		cut.marks[target.stair] = "stairs"
	elif target.has("laid"):
		var id := world.marks.mark_at(target.point.x, target.point.z)
		if id >= 0:
			cut.marks[id] = "paths" if world.state.paths.has(id) else "grounds"
	elif target.has("mow"):
		_mow(cut, target.point, target.mow)
	return target


## Shows the plants under a ring at `at` taken, on this machine only, until the stroke's command comes back. Plants
## parted to nothing by a path or stone are left, so lifting that brings them back.
func _mow(cut: Dictionary, at: Vector3, radius: float) -> void:
	for p in flora.plants_near(at, radius):
		var reach := radius * (1.0 - RAGGED * float(hash(p.anchor) % 1024) / 1024.0)
		if not cut.plants.has(p) and Vector2(p.anchor.x - at.x, p.anchor.z - at.z).length() < reach and not flora.on_path(p.anchor):
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
	if cut.has("single"):
		var target: Dictionary = cut.single
		var cmd := {}
		if target.get("rubble", false):
			if is_instance_valid(target.wall) and _standing(target.wall):
				cmd = {"op": "take", "of": "walls", "ids": PackedInt32Array([target.wall.id])}
		else:
			cmd = FittingTool.removal(world.state, target)
		if not cmd.is_empty():
			world.submit(cmd)
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
			cmds.append({"op": "take", "of": "walls", "ids": PackedInt32Array([id])})
		elif ruins != Array(world.state.walls[id].ruins):
			cmds.append({"op": "reshape", "of": "walls", "id": id, "data": {"ruins": PackedVector2Array(ruins)}})
	for id: int in cut.marks:
		cmds.append({"op": "take", "of": cut.marks[id], "ids": PackedInt32Array([id])})
	for id: int in cut.easels:
		if world.state.easels.has(id):
			cmds.append({"op": "take", "of": "easels", "ids": PackedInt32Array([id])})
	for item: Dictionary in cut.decorations.values():
		var cmd := FittingTool.removal(world.state, item)
		if not cmd.is_empty():
			cmds.append(cmd)
	for id: int in cut.pieces:
		if world.state.paths.has(id) and not cut.marks.has(id):
			var kept := PackedVector4Array(world.state.paths[id].clutter)
			for v: Vector4 in cut.pieces[id]:
				if kept.has(v):
					kept.remove_at(kept.find(v))
			cmds.append({"op": "reshape", "of": "paths", "id": id, "data": {"clutter": kept}})
	for id: int in cut.fittings:
		if not world.state.walls.has(id) or cmds.any(func(c: Dictionary) -> bool: return c.op == "take" and c.of == "walls" and id in c.ids):
			continue
		var data: Dictionary = world.state.walls[id].duplicate(true)
		var changed := {}
		for item: Dictionary in cut.fittings[id]:
			var cmd := FittingTool.removal({"walls": {id: data}}, item)
			if cmd.is_empty():
				continue
			if cmd.data.has("roof"):
				data.roof.merge(cmd.data.roof, true)
				changed.get_or_add("roof", {}).merge(cmd.data.roof, true)
			else:
				data.merge(cmd.data, true)
				changed.merge(cmd.data, true)
		if changed.is_empty():
			continue
		var existing := cmds.find_custom(func(c: Dictionary) -> bool: return c.op == "reshape" and c.get("of") == "walls" and c.id == id)
		if existing >= 0:
			cmds[existing].data.merge(changed, true)
		else:
			cmds.append({"op": "reshape", "of": "walls", "id": id, "data": changed})
	for id: int in cut.boulders:
		if world.state.boulders.has(id):
			cmds.append({"op": "take", "of": "boulders", "ids": PackedInt32Array([id])})
	var settle := func() -> void:
		for id in swept:
			walls.settle(id)
		for p: Flora.Plant in plants:
			p.draw(p.shown())
		for e: Node3D in cut.easels.values() + cut.boulders.values():
			if is_instance_valid(e):
				e.visible = true
		for id: int in cut.decorations:
			world.decorations.unsweep(id)
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


## The same ring used for mowing encloses a fitting, or the whole building a body hit would take.
func show_target(ring: MeshInstance3D, target: Dictionary, eye: Vector3) -> void:
	ring.visible = false
	if target.has("mow"):
		FloraTool.put_ring(ring, target.point, target.mow)
		return
	var bounds := target_bounds(target)
	if bounds.size == Vector3.ZERO:
		return
	var centre := bounds.get_center()
	var normal := (eye - centre).normalized()
	var x := Vector3.UP.cross(normal).normalized()
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	var z := x.cross(normal).normalized()
	var radius_x := 0.0
	var radius_z := 0.0
	var depth := 0.0
	for i in 8:
		depth = maxf(depth, (bounds.get_endpoint(i) - centre).dot(normal))
	var distance := eye.distance_to(centre)
	var plane := maxf(0.1, distance - depth - 0.04)
	for i in 8:
		var corner := bounds.get_endpoint(i) - centre
		var projection := plane / maxf(0.1, distance - corner.dot(normal))
		radius_x = maxf(radius_x, absf(corner.dot(x)) * projection)
		radius_z = maxf(radius_z, absf(corner.dot(z)) * projection)
	ring.global_transform = Transform3D(Basis(x * (radius_x + 0.08), normal, z * (radius_z + 0.08)), eye - normal * plane)
	ring.visible = true


func target_bounds(target: Dictionary) -> AABB:
	if target.has("fitting"):
		return target.bounds
	if target.has("wall"):
		var w: Wall = target.wall
		var bounds := w.pick_bounds
		if w.roof != null:
			bounds = bounds.expand(w.roof.frame().mid + Vector3.UP * w.roof.pitch)
		return bounds
	if target.has("stair") and world.stairs.layouts.has(target.stair):
		return world.stairs.layouts[target.stair].bounds
	return AABB()
