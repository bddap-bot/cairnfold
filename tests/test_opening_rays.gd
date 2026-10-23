extends "res://../tests/support/suite.gd"

## Headless checks that the teleport and placement rays pass through a wall's or fence's open arch to what lies beyond
## it and still stop on the stone round it, while a grip or a delete into the arch takes the arch: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_opening_rays.gd


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	main.rig.set_process(false)
	var world: World = main.world
	world.load_from(OS.get_temp_dir().path_join("nestcombe-opening-rays-%d.garden" % OS.get_process_id()))
	_through(world, false, 1.0)
	_through(world, false, 1.25)
	_through(world, true, 1.0)
	_closed_openings(world)
	finish()


func _wall(world: World, fence: bool, openings: Array) -> Wall:
	var d := wall_data({"points": PackedVector3Array([Terrain.ground(10, -30), Terrain.ground(16, -30)]), "height": WallLayout.FENCE_HEIGHT if fence else 2.6, "seed": 3, "fence": fence, "openings": PackedVector4Array(openings)})
	world._order({"op": "wall", "walls": [d]}, 1)
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	return w


## A ray from 3 m before the wall that crosses its middle `up` above the foot at arc length `s`, aimed at the ground
## 4 m past it, `slant` of that along the wall, or `level`, as [origin, dir, foot, out].
func _ray(w: Wall, s: float, up: float, slant := 0.0, level := false) -> Array:
	var f := w.layout.frame_at(s)
	var out: Vector3 = f.tangent.cross(Vector3.UP).normalized()
	var through: Vector3 = f.point + Vector3.UP * (WallLayout.SINK + up)
	var beyond: Vector3 = out * 4.0 + f.tangent * slant * 4.0
	var target := through + beyond if level else Terrain.ground(through.x + beyond.x, through.z + beyond.z)
	var dir := (target - through).normalized()
	return [through - dir * 3.0 / dir.dot(out), dir, f.point, out]


## How far past the wall's middle `p` lies.
func _past(p: Variant, ray: Array) -> float:
	return -INF if p == null else (p - ray[2]).dot(ray[3])


func _through(world: World, fence: bool, size: float) -> void:
	var what := "%s arch of size %.1f" % ["a fence's" if fence else "a wall's", size]
	var w := _wall(world, fence, [WallLayout.archway(3.0, size)])
	check(w.layout.archways().size() == 1, "%s opens" % what)
	if w.layout.archways().is_empty():
		world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)
		return
	var ray := _ray(w, 3.0, 0.8 * size)
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var solid: Variant = main.rig.solid_hit.call(origin, dir, 30.0).get("point")
	check(_past(solid, ray) > WallLayout.THICKNESS * 0.5 or solid == null, "the teleport ray passes through %s: stopped at %s, %.2f past its middle" % [what, solid, _past(solid, ray)])
	main.rig.aim(Transform3D(Basis.looking_at(dir, Vector3.UP), origin))
	check(_past(main.rig.aim_ground, ray) > 1.0, "the teleport lands past %s: %s" % [what, main.rig.aim_ground])
	var place: Dictionary = main.fitting_tool.aim(Hand.Tool.DECORATIONS, origin, dir)
	check(place.get("mount") == "ground" and _past(place.get("point"), ray) > 3.0, "a decoration is placed on the ground past %s: %s %s" % [what, place.get("what"), place.get("point")])
	if not fence:
		var grab: Dictionary = FittingTool.pick_target(main.tool, origin, dir, true)
		check(grab.get("what") == "opening" and grab.get("wall") == w, "a grip into %s takes the arch: %s" % [what, grab.get("what", grab.get("surface"))])
		var erase: Dictionary = main.delete_tool.aim(origin, dir)
		check(erase.get("what") == "opening" and erase.get("wall") == w, "a delete into %s takes the arch: %s" % [what, erase.get("what", erase.get("surface"))])
		var jamb := _ray(w, 3.0 + w.layout.opening(0.8 * size, false, size) - 0.1, 0.8 * size, 0.4)
		var at: Variant = main.rig.solid_hit.call(jamb[0], jamb[1], 30.0).get("point")
		check(at != null and absf(_past(at, jamb)) < WallLayout.THICKNESS * 0.5 + 0.01, "a slant ray into %s stops on its jamb: %s" % [what, at])
		var crown := _ray(w, 3.0, w.layout.spring(size) + w.layout.arch_rise(0.0, size) + 0.05 - WallLayout.SINK, 0.0, true)
		var ring: Variant = main.rig.solid_hit.call(crown[0], crown[1], 30.0).get("point")
		check(ring != null and absf(_past(ring, crown) + WallLayout.THICKNESS * 0.5) < 0.05, "a level ray just over %s's crown stops on its ring: %s" % [what, ring])
	var beside := _ray(w, 0.8 if fence else 1.0, 0.8 * size)
	var stone: Variant = main.rig.solid_hit.call(beside[0], beside[1], 30.0).get("point")
	check(fence or (stone != null and absf(_past(stone, beside) + WallLayout.THICKNESS * 0.5) < 0.05), "the teleport ray stops on %s's face beside the arch: %s" % [what, stone])
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)


## A door's planks and a window's glass close their openings: rays stop on them, and pick them.
func _closed_openings(world: World) -> void:
	var w := _wall(world, false, [Vector4(1.6, 0.0, WallLayout.DoorStyle.PLAIN, 1.0), Vector4(4.4, 1.4, WallLayout.DoorStyle.PLAIN, 1.0)])
	check(w.layout.apertures.size() == 2, "a door and a window open: %d" % w.layout.apertures.size())
	for o in w.layout.apertures:
		var ray := _ray(w, o.s, (o.sill + o.head) * 0.5)
		var solid: Variant = main.rig.solid_hit.call(ray[0], ray[1], 30.0).get("point")
		check(solid != null and _past(solid, ray) < 0.0, "the teleport ray stops at a %s: %s" % ["door" if o.door else "window", solid])
		var pick: Dictionary = main.fitting_tool.aim(Hand.Tool.WINDOWS, ray[0], ray[1])
		check(pick.get("what") == "opening" and pick.get("fitting", false), "a %s is picked where it closes its opening: %s" % ["door" if o.door else "window", pick])
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)
