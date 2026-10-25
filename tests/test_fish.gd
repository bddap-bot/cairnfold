extends "res://../tests/support/suite.gd"

## Headless checks of fish: godot4 --headless --path game --script ../tests/test_fish.gd

const GladeBase = preload("res://../tests/support/glade.gd")
const STEP := 1.0 / 30.0


func _initialize() -> void:
	await process_frame
	_faces_out()
	await _they_swim_in_the_ponds()
	finish()


## The fish draws see-through, so a face turned from the eye would show its inside over its outside: it draws only
## faces turned to the eye, its body is closed with every face turned out, and each fin is a face either way up.
func _faces_out() -> void:
	check(not (load("res://src/fish.gdshader") as Shader).code.contains("cull_"), "a fish draws only the faces turned to the eye")
	var arrays := Fish.body().surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var key := func(p: Vector3) -> String: return str(Vector3i((p * 1e5).round()))
	var edges := {}
	var fins := {}
	for t in range(0, v.size(), 3):
		var front := (v[t + 2] - v[t]).cross(v[t + 1] - v[t])
		if front.length() < 1e-9:
			continue
		check(front.dot(n[t] + n[t + 1] + n[t + 2]) > 0.0, "triangle %d faces the way its normals do" % (t / 3))
		if uv[t].x == 1.0:
			var corners := [key.call(v[t]), key.call(v[t + 1]), key.call(v[t + 2])]
			corners.sort()
			fins.get_or_add(str(corners), []).append(signf(front.y))
			continue
		check(front.dot((v[t] + v[t + 1] + v[t + 2]) / 3.0) > 0.0, "body triangle %d faces out" % (t / 3))
		for k in 3:
			var edge := "%s>%s" % [key.call(v[t + k]), key.call(v[t + (k + 1) % 3])]
			edges[edge] = edges.get(edge, 0) + 1
	for edge: String in edges:
		var back := "%s>%s" % [edge.get_slice(">", 1), edge.get_slice(">", 0)]
		check(edges[edge] == 1 and edges.get(back, 0) == 1, "the body is closed, edge %s met once each way" % edge)
	check(fins.size() == 6, "six fin faces, found %d" % fins.size())
	for f: String in fins:
		check(fins[f].size() == 2 and 1.0 in fins[f] and -1.0 in fins[f], "fin %s is a face either way up" % f)


func _run(wildlife: Wildlife, seconds: float, feed: FeedTool = null, each := Callable()) -> void:
	for i in int(seconds / STEP):
		if feed != null:
			feed.tick(STEP)
		wildlife.tick(STEP)
		if each.is_valid():
			each.call()


## A handful thrown on the pond sends every fish in it darting in under the seeds; they rise to take them, rippling the
## water, until none is left, and then scatter back to cruising. A throw lands alike wherever it is played from its seed.
func _seeds_on_the_water_draw_every_fish(wildlife: Wildlife, feed: FeedTool, water: Water) -> void:
	_run(wildlife, Fish.DART_FOR + 3.0)
	var fish := wildlife.fish
	var pond := water.ponds[0]
	var mine := fish.swimming.filter(func(f: Fish.One) -> bool: return f.pond == pond)
	var mid := Terrain.grid_xz(pond.pond.bottom)
	var s := feed.toss(Vector3(mid.x, pond.surface_y() + 1.2, mid.y), Vector3(0.2, 0.5, 0.1), 11)
	var heard := Cues.asked.duplicate()
	var fed := {}
	var rose := [false]
	var fast := [0.0]
	_run(wildlife, 8.0, feed)
	check(s.landed() and pond == water.pond_at(s.position.x, s.position.z), "the seeds come down on the pond")
	check(Cues.asked.get(Cues.Act.PLOP, 0) - heard.get(Cues.Act.PLOP, 0) == 1, "with a plop")
	_run(wildlife, 20.0, feed, func() -> void:
		for f: Fish.One in mine:
			if f.feeding:
				fed[f] = true
				fast[0] = maxf(fast[0], f.speed)
			rose[0] = rose[0] or f.at.y > pond.pond.level - Fish.NIBBLE_AT - 1e-3)
	check(not mine.is_empty() and fed.size() == mine.size(), "every fish of the pond swarms the seeds, %d of %d" % [fed.size(), mine.size()])
	check(fast[0] > Fish.CRUISE * 3.0, "darting in, %.2f m/s" % fast[0])
	check(rose[0], "and rising to the surface to take them")
	check(s.left() == 0, "the seeds are eaten, %d left" % s.left())
	check(Cues.asked.get(Cues.Act.NIBBLE, 0) > heard.get(Cues.Act.NIBBLE, 0), "with a nibble as they are taken")
	check(fish.swimming.all(func(f: Fish.One) -> bool: return not f.feeding), "then the fish scatter back to cruising")
	check(_in_water(fish, water), "every fish still in the water")
	_run(wildlife, 4.0, feed)
	check(mine.all(func(f: Fish.One) -> bool: return f.speed < Fish.CRUISE * 1.5 and f.pitch == 0.0), "and calm, swimming level")
	var a := Handful.new(water, water.terrain)
	var b := Handful.new(water, water.terrain)
	root.add_child(a)
	root.add_child(b)
	a.toss(Vector3(mid.x, pond.surface_y() + 1.2, mid.y), Vector3(0.4, 1.0, 0.2), 5)
	b.toss(Vector3(mid.x, pond.surface_y() + 1.2, mid.y), Vector3(0.4, 1.0, 0.2), 5)
	for i in int(8.0 / STEP):
		a.tick(STEP)
	var t := 0.0
	while t < 8.0:
		var dt := 0.1 if int(t * 10.0) % 2 else 0.23
		b.tick(dt)
		t += dt
	var apart := a.position.distance_to(b.position)
	for i in Handful.GRAINS:
		apart = maxf(apart, a._at[i].distance_to(b._at[i]))
	check(a.landed() and b.landed() and apart < 0.001, "one throw lands the same grains however a loaded machine's frames fall, %.4f m at most" % apart)
	a.queue_free()
	b.queue_free()


func _in_water(fish: Fish, water: Water) -> bool:
	return fish.swimming.all(func(f: Fish.One) -> bool:
		var p := water.pond_at(f.at.x, f.at.z)
		return p != null and f.at.y < p.surface_y() and f.at.y > water.terrain.height_at(f.at.x, f.at.z))


func _they_swim_in_the_ponds() -> void:
	var world := World.new()
	world.terrain.install()
	var rig := Rig.new(world.terrain)
	root.add_child(rig)
	root.add_child(world)
	var grab := GroundGrab.new(rig, world)
	root.add_child(grab)
	var water := Water.new(world.terrain, [])
	root.add_child(water)
	var tool := WaterTool.new(rig, world)
	root.add_child(tool)
	var flora := Flora.new(world.terrain, world.marks)
	root.add_child(flora)
	var paths := Paths.new()
	paths.terrain = world.terrain
	paths.marks = world.marks
	root.add_child(paths)
	world.attach(null, flora, paths, grab, water)
	var palette := Palette.new()
	var hand := Node3D.new()
	root.add_child(hand)
	hand.global_position = Vector3(0, 30, 0)
	var hands: Array[Node3D] = [hand]
	await process_frame
	var wildlife := Wildlife.new(world.terrain, world.marks, water, flora, null, palette, rig.head, hands, 3)
	root.add_child(wildlife)
	var feed := FeedTool.new(rig, water, world.terrain)
	feed.set_process(false)
	root.add_child(feed)
	wildlife.handfuls = feed.handfuls
	wildlife.set_process(false)
	var fish := wildlife.fish

	wildlife.tick(STEP)
	check(fish.swimming.size() == 0 and fish.crowd.multimesh.visible_instance_count == 0, "no pond, no fish")

	await GladeBase.dig(tool, 3, -4)
	await GladeBase.dig(tool, 4.5, -4)
	water.ponds[0]._process(PondWater.FILL)
	_run(wildlife, Wildlife.ARRIVE_AFTER.x - 1.0)
	check(fish.swimming.is_empty(), "a filled pond has no fish at first")
	_run(wildlife, Wildlife.ARRIVE_AFTER.y - Wildlife.ARRIVE_AFTER.x + Fish.FADE + 1.5)
	var n := fish.swimming.size()
	check(n >= 1 and n <= Fish.PER_POND, "a pond has a few fish, %d" % n)
	check(n >= 1 and fish.swimming.all(func(f: Fish.One) -> bool: return f.shown >= 1.0), "a while later they have come, faded in")
	check(fish.crowd.multimesh.visible_instance_count == n, "each is drawn")
	check(_in_water(fish, water), "under the surface, over the ground")

	var start := fish.swimming.map(func(f: Fish.One) -> Vector3: return f.at)
	var kept := true
	var tail_first := 0.0
	for i in int(60.0 / STEP):
		var was: Array = fish.swimming.map(func(f: Fish.One) -> Vector3: return f.at)
		wildlife.tick(STEP)
		kept = kept and _in_water(fish, water)
		for k in mini(was.size(), fish.swimming.size()):
			var f := fish.swimming[k]
			var moved := Vector2(f.at.x - was[k].x, f.at.z - was[k].z)
			if moved.dot(Vector2(sin(f.heading), cos(f.heading))) < 0.0:
				tail_first += moved.length()
	check(kept, "a minute on, every one has stayed in the water")
	check(tail_first < 0.01, "none swims tail first, %.2f m in all" % tail_first)
	var moved := 0.0
	var now := fish.swimming
	for i in now.size():
		moved += now[i].at.distance_to(start[i])
	check(moved / now.size() > 0.3, "and they swim about, %.2f m on average" % (moved / now.size()))

	var one: Fish.One = now[0]
	hand.global_position = one.at + Vector3(0.1, 0.05, 0)
	wildlife.tick(STEP)
	wildlife.tick(STEP)
	check(one.speed > Fish.CRUISE * 2.0, "a hand coming near makes a fish dart, %.2f m/s" % one.speed)
	var from := one.at
	for i in int(Fish.DART_FOR / STEP):
		wildlife.tick(STEP)
	check(one.at.distance_to(hand.global_position) > from.distance_to(hand.global_position), "away from it")
	check(_in_water(fish, water), "and still in the water")
	await _seeds_on_the_water_draw_every_fish(wildlife, feed, water)
	hand.global_position = one.at + Vector3(0.1, 0.05, 0)
	_run(wildlife, 0.5)
	_run(wildlife, 3.0)
	check(one.speed < Fish.CRUISE * 1.5, "a hand held still beside one frightens it no more, %.2f m/s" % one.speed)
	hand.global_position = Vector3(0, 30, 0)

	await GladeBase.dig(tool, 5.8, -4.2)
	water.ponds[0]._process(PondWater.FILL)
	var kept_on := true
	for i in int(5.0 / STEP):
		wildlife.tick(STEP)
		kept_on = kept_on and _in_water(fish, water)
	check(kept_on and not fish.swimming.is_empty(), "a pond dug wider keeps its fish in its water")

	await GladeBase.dig(tool, -6, 5)
	check(fish.swimming.all(func(f: Fish.One) -> bool: return f.pond != water.ponds[-1]), "none in a pond still filling")
	water.ponds[-1]._process(PondWater.FILL)
	_run(wildlife, Fish.FADE)
	check(fish.swimming.all(func(f: Fish.One) -> bool: return f.pond != water.ponds[-1]), "nor at once in one filled")
	_run(wildlife, Wildlife.ARRIVE_AFTER.y)
	check(fish.swimming.any(func(f: Fish.One) -> bool: return f.pond == water.ponds[-1]), "a second pond has its own fish a while after")
	check(_in_water(fish, water), "every fish in water")
	check(fish.swimming.size() <= Fish.CAP, "never more than the cap, %d" % fish.swimming.size())
