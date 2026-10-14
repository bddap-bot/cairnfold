extends SceneTree

## Headless checks of time of day, seasons and the colour picker, as data and through the tools:
## godot4 --headless --path game --script ../tests/test_daylight.gd

var failures := 0
var main: Node


func _initialize() -> void:
	_the_sun_rises_and_sets()
	_a_ray_drags_the_sun_to_where_it_points()
	_light_follows_the_sun()
	_the_default_hour_keeps_the_tuned_look()
	_first_swatches_are_the_laid_colours()
	_the_default_palette_changes_nothing()
	_five_seasons()
	_twisting_wraps_round_the_wheel()
	_every_laid_kind_is_painted_or_kept()
	_shaders_read_the_codes_and_globals_palette_writes()
	_a_clockwise_twist_counts_up()
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_in_the_glade.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _the_sun_rises_and_sets() -> void:
	_check(Daylight.elevation(0.0) < -5.0 and Daylight.elevation(1.0) < -5.0, "the sun is under the horizon at 0 (%.1f°) and 1 (%.1f°)" % [Daylight.elevation(0.0), Daylight.elevation(1.0)])
	var noon := Daylight.elevation(0.5)
	_check(absf(noon - (90.0 - rad_to_deg(Daylight.TILT))) < 0.5, "the noon sun stands %.1f° high" % noon)
	var prev := -INF
	for i in 21:
		var e := Daylight.elevation(i / 40.0)
		_check(e > prev, "the morning sun climbs at %.3f" % (i / 40.0))
		prev = e
	for i in range(21, 41):
		var e := Daylight.elevation(i / 40.0)
		_check(e < prev, "the afternoon sun sinks at %.3f" % (i / 40.0))
		prev = e
	_check(Daylight.toward_sun(0.1).x < 0.0 and Daylight.toward_sun(0.9).x > 0.0, "it rises on the left and sets on the right")
	_check(Daylight.toward_sun(0.5).z < 0.0, "at noon it stands in front of the starting view")


func _a_ray_drags_the_sun_to_where_it_points() -> void:
	for i in 21:
		var t := i / 20.0
		_check(absf(Daylight.time_toward(Daylight.toward_sun(t)) - t) < 1e-4, "pointing at the sun at %.2f finds %.2f" % [t, t])
	var off := (Daylight.toward_sun(0.4) + Vector3(0, 0, 0.3)).normalized()
	_check(absf(Daylight.time_toward(off) - 0.4) < 0.03, "a ray beside the arc drags the sun to the nearest hour")
	_check(Daylight.time_toward(Vector3(-1, -0.6, 0).normalized()) == 0.0, "a ray below the rising point holds dawn")
	_check(Daylight.time_toward(Vector3(1, -0.6, 0).normalized()) == 1.0, "a ray below the setting point holds dusk")
	var nadir := -Daylight.RISE.cross(Daylight.ARC_UP).cross(Daylight.RISE).normalized()
	_check(Daylight.time_toward(nadir.rotated(Daylight.RISE.cross(Daylight.ARC_UP), deg_to_rad(5.0))) == 0.0 and Daylight.time_toward(nadir.rotated(Daylight.RISE.cross(Daylight.ARC_UP), deg_to_rad(-5.0))) == 1.0, "under the ground the sun goes to whichever end is nearer")


func _light_follows_the_sun() -> void:
	_check(Daylight.light(0.0).energy == 0.0 and Daylight.light(1.0).energy == 0.0, "no sunlight with the sun down")
	var prev := -1.0
	for i in 21:
		var l := Daylight.light(i / 40.0)
		_check(l.energy >= prev, "sunlight grows through the morning at %.3f" % (i / 40.0))
		prev = l.energy
	var dusk := Daylight.light(0.97)
	var noon := Daylight.light(0.5)
	_check(dusk.sun.b < noon.sun.b * 0.6 and dusk.horizon.r > dusk.horizon.b, "the low sun and horizon run warm")
	_check(Daylight.light(0.0).zenith.get_luminance() < noon.zenith.get_luminance() * 0.4, "the sky darkens with the sun down")
	_check(absf(Daylight.light(0.3).energy - Daylight.light(0.7).energy) < 1e-3, "mirror hours light alike")


func _the_default_hour_keeps_the_tuned_look() -> void:
	var l := Daylight.light(Daylight.DEFAULT)
	var tuned := Basis.from_euler(Vector3(deg_to_rad(-34.0), deg_to_rad(-150.0), 0.0)).z
	_check(Daylight.toward_sun(Daylight.DEFAULT).distance_to(tuned) < 0.01, "the default sun stands where the meadow was tuned: %s, not %s" % [tuned, Daylight.toward_sun(Daylight.DEFAULT)])
	_check(absf(l.energy - 1.7) < 0.05 and (l.sun as Color).is_equal_approx(Color(1.0, 0.93, 0.80)), "the default sun is the tuned warm one")


func _first_swatches_are_the_laid_colours() -> void:
	_check(Palette.SWATCHES[Palette.Element.WOOD][0] == WallLayout.WOOD, "wood's first swatch is the laid wood")
	_check(Palette.SWATCHES[Palette.Element.PLASTER][0] == WallLayout.PLASTER, "plaster's first swatch is the laid plaster")
	var rng := RandomNumberGenerator.new()
	var sum := Color(0, 0, 0, 0)
	for i in 4000:
		sum += WallLayout.stone_color(rng)
	sum /= 4000.0
	var stone: Color = Palette.SWATCHES[Palette.Element.STONE][0]
	_check(absf(sum.r - stone.r * 0.95) < 0.02 and absf(sum.g - stone.g * 0.95) < 0.02 and absf(sum.b - stone.b * 0.95) < 0.02, "stone's first swatch is the laid stone (mean %s)" % sum)


func _the_default_palette_changes_nothing() -> void:
	var g := Palette.new().globals()
	for e in ["stone", "roof", "wood", "plaster"]:
		_check(g["tint_" + e] == Vector3.ONE, "%s keeps its laid colour" % e)
	_check(g.season_meadow.w == 0.0 and g.season_foliage.w == 0.0 and g.season_bloom == 1.0, "summer is the meadow as tuned")
	var p := Palette.new()
	p.picks[Palette.Element.ROOF] = 1
	var want: Color = Palette.SWATCHES[Palette.Element.ROOF][1]
	var base: Color = Palette.SWATCHES[Palette.Element.ROOF][0]
	var tint: Vector3 = p.globals().tint_roof
	_check(Vector3(base.r, base.g, base.b) * tint == Vector3(want.r, want.g, want.b), "a pick scales the laid colour onto its swatch")


func _five_seasons() -> void:
	_check(Palette.count(Palette.Element.MEADOW) == 5, "five seasons")
	var winter: Dictionary = Palette.SEASONS[-1]
	_check(winter.bloom == 0.0 and winter.meadow.a > 0.5 and winter.meadow.get_luminance() > 0.8, "winter whitens the meadow with nothing in bloom")
	for e in Palette.SWATCHES:
		_check(Palette.count(e) >= 6, "%s has %d swatches" % [Palette.Element.keys()[e], Palette.count(e)])


func _twisting_wraps_round_the_wheel() -> void:
	var n := Palette.count(Palette.Element.ROOF)
	_check(Palette.twisted(Palette.Element.ROOF, 0, Palette.TWIST_STEP) == 1, "one step clockwise is the next swatch")
	_check(Palette.twisted(Palette.Element.ROOF, 0, -Palette.TWIST_STEP) == n - 1, "one step back wraps to the last")
	_check(Palette.twisted(Palette.Element.ROOF, 2, Palette.TWIST_STEP * 0.4) == 2, "a small twist stays put")


func _every_laid_kind_is_painted_or_kept() -> void:
	var kept := ["glass", "iron", "finial", "pot"]
	var kinds := {}
	var wall := WallLayout.new()
	wall.points = [Vector3(0, 0, 0), Vector3(16, 0, 0)]
	wall.height = 3.0
	wall.windows = [Vector2(3.0, 1.5), Vector2(3.8, 1.5), Vector2(6.5, 0.8)]
	wall.arches = [10.5, 12.8]
	wall.flags = [1.5]
	wall.lanterns = [Vector3(8.5, 1.6, 1.0)]
	wall.build(_flat)
	var coped := WallLayout.new()
	coped.points = [Vector3(0, 0, -4), Vector3(6, 0, -4)]
	coped.top = WallLayout.Top.COPE
	coped.build(_flat)
	var fence := WallLayout.new()
	fence.fence = true
	fence.height = WallLayout.FENCE_HEIGHT
	fence.points = [Vector3(0, 0, 4), Vector3(8, 0, 4)]
	fence.arches = [4.0]
	fence.build(_flat)
	var roof := RoofLayout.new()
	roof.kind = RoofLayout.Kind.GABLE
	roof.corners = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	roof.chimneys = [Vector2(0.3, 0.5)]
	roof.build()
	for s in wall.stones + coped.stones + fence.stones + roof.tiles:
		kinds[s.kind] = true
	for k in kinds:
		_check(Palette.KINDS.has(k) != kept.has(k), "a laid %s is either painted with a material or kept on purpose" % k)
	for k in Palette.KINDS:
		_check(kinds.has(k), "%s is a kind something lays" % k)
	var want := {
		Palette.Element.STONE: ["block", "mortar", "voussoir", "keystone", "pillar", "cope", "cap", "merlon", "pier", "lintel", "sill", "mullion", "chimney"],
		Palette.Element.ROOF: ["tile", "ridge"],
		Palette.Element.WOOD: ["post", "rail", "gate", "frame", "door", "pole"],
		Palette.Element.PLASTER: ["plaster"],
	}
	for e in want:
		for k in want[e]:
			_check(Palette.code(k) == e, "a laid %s is painted with %s, got code %s" % [k, Palette.Element.keys()[e], Palette.code(k)])
	for k in kept:
		_check(Palette.code(k) == 0.0, "a laid %s keeps its colour" % k)
	var packed := Wall.pack(wall, Wall.kinds())
	var stride := Wall.kinds()[Wall.Part.STONE].stride()
	var codes := {}
	for i in range(0, packed.stone.size(), stride):
		codes[packed.stone[i + 17]] = true
	_check(codes.has(float(Palette.Element.STONE)) and codes.has(float(Palette.Element.WOOD)) and codes.has(0.0), "a wall's packed parts carry their materials' codes for the chunked draw: %s" % [codes.keys()])
	var door: Dictionary = wall.stones.filter(func(s): return s.kind == "door")[0]
	_check(Stones.custom(door) == Color(door.ao, Palette.Element.WOOD, 0, 0), "a laid door carries its occlusion and wood's code to its shader")
	_check(Stones.custom({"ao": 0.85}) == Color(0.85, 0, 0, 0), "paving, with no kind, keeps its colour")


func _shaders_read_the_codes_and_globals_palette_writes() -> void:
	var inc := FileAccess.get_file_as_string("res://src/palette.gdshaderinc")
	for e in Palette.SWATCHES:
		var name: String = Palette.Element.keys()[e].to_lower()
		_check(inc.contains("c == %d ? tint_%s" % [e, name]), "the stone shader reads code %d as %s's tint" % [e, name])
	for name in Palette.new().globals():
		_check(ProjectSettings.has_setting("shader_globals/" + name) and inc.contains("global uniform") and inc.contains(" %s;" % name), "%s is a declared shader global" % name)


func _a_clockwise_twist_counts_up() -> void:
	var start := Basis.looking_at(Vector3(0.3, -0.2, -1.0))
	var fwd := -start.z
	var turned := Basis(fwd, deg_to_rad(40.0)) * start
	_check(absf(PaletteTool._roll(start, turned) - 40.0) < 0.1, "a 40° turn clockwise, seen along the hand, reads %.1f" % PaletteTool._roll(start, turned))


func _in_the_glade() -> void:
	var tool: PaletteTool = main.palette_tool
	var walls: Array[Wall] = main.tool.walls
	await _play([
		{"op": "place", "x": 0, "z": 12},
		{"op": "wall", "points": [[-8, 0], [-3, 0], [2, 0]], "seconds": 0.3},
		{"op": "house", "a": [8, 0], "b": [14, 0], "seconds": 0.2},
		{"op": "fence", "points": [[-8, 6], [-2, 6]], "seconds": 0.3},
		{"op": "fit", "what": "window", "index": 0, "s": 2.5, "y": 1.5},
	])
	var wall: WallLayout = walls[0].layout
	var house: Wall = walls[1]
	var face := wall.point_at(2.0) + Vector3(0, 1.0, 0)
	_check(tool.aim(face + Vector3(0, 0, 3), Vector3.FORWARD).get("element") == Palette.Element.STONE, "the picker on a wall's face paints stone")
	if not wall.openings.is_empty():
		var o: Dictionary = wall.openings[0]
		var at := wall.point_at(o.s) + Vector3(0, (o.sill + o.head) * 0.5, 0)
		_check(tool.aim(at + Vector3(0, 0, 3), Vector3.FORWARD).get("element") == Palette.Element.WOOD, "the picker on a window paints woodwork")
	else:
		_check(false, "the window opened")
	var f: Dictionary = house.roof.frame()
	_check(tool.aim(f.mid + Vector3.UP * 12.0, Vector3.DOWN).get("element") == Palette.Element.ROOF, "the picker on a roof paints its tiles")
	var end: Vector3 = f.mid + f.along * (house.roof.ridge_length() * 0.5 + 4.0) + Vector3.UP * house.roof.pitch * 0.35
	_check(tool.aim(end, -f.along).get("element") == Palette.Element.PLASTER, "the picker on a gable end paints plaster")
	var post := walls[2].layout.point_at(3.0) + Vector3(0, 0.6, 0)
	_check(tool.aim(post + Vector3(0, 0, 3), Vector3.FORWARD).get("element") == Palette.Element.WOOD, "the picker on a fence paints woodwork")
	_check(tool.aim(Vector3(0, 20, 22), Vector3.DOWN).get("element") == Palette.Element.MEADOW, "the picker on the meadow picks the season")
	_check(tool.aim(Vector3(0, 2, 22), Vector3.UP).is_empty(), "the picker on the sky does nothing")

	var world: World = main.world
	var steps: int = world.stacks.get(world.me(), {"undo": []}).undo.size()
	await _play([{"op": "colour", "hand": "left", "element": "roof", "swatch": 3, "seconds": 0.2}])
	_check(world.palette.picks[Palette.Element.ROOF] == 3 and tool.wheels.is_empty(), "a twist to the fourth swatch keeps it")
	_check(world.stacks[world.me()].undo.size() == steps + 1, "a pick is one undo step")
	await _play([{"op": "colour", "hand": "left", "element": "meadow", "swatch": 4, "seconds": 0.2}])
	_check(world.palette.globals().season_bloom == 0.0, "winter takes the flowers")
	var snap := world.snapshot()
	var colours: Array = snap.cmds.filter(func(c: Dictionary) -> bool: return c.op == "palette")
	_check(colours.size() == 2, "a joiner's snapshot carries the two picks: %s" % [colours])
	await _play([{"op": "press", "button": "dpad_down"}, {"op": "press", "button": "dpad_down"}])
	_check(world.palette.picks == Palette.new().picks, "undo takes both picks back: %s" % [world.palette.picks])
	await _play([{"op": "press", "button": "dpad_up"}])
	_check(world.palette.picks[Palette.Element.ROOF] == 3, "redo paints the roofs again")
	var left: Hand = main.rig.left
	tool.open(left, Palette.Element.STONE)
	world.submit({"op": "palette", "element": Palette.Element.STONE, "index": 2})
	tool.twist(left, Palette.TWIST_STEP * 2.0)
	var before: int = world.stacks[world.me()].undo.size()
	tool.close(left)
	_check(world.stacks[world.me()].undo.size() == before and world.palette.picks[Palette.Element.STONE] == 2, "a wheel let go on the swatch the garden already has sends nothing")
	world.restore(snap)
	_check(world.palette.picks[Palette.Element.MEADOW] == 4 and world.palette.picks[Palette.Element.ROOF] == 3, "a garden rebuilt from its snapshot keeps its colours")
	_check(Commands.clean({"op": "palette", "element": Palette.Element.ROOF, "index": Palette.count(Palette.Element.ROOF)}, world.state, false).is_empty(), "a swatch off the wheel is refused")

	var look: Look = main.look
	var sun: SunTool = main.sun_tool
	_check(sun.aims_at_sun(Daylight.toward_sun(look.time)) and not sun.aims_at_sun(Daylight.toward_sun(look.time).rotated(Vector3.UP, deg_to_rad(15.0))), "only a hand pointed at the sun takes it")
	var beside := Daylight.toward_sun(look.time).rotated(Vector3.UP, deg_to_rad(4.0))
	sun.take(main.rig.right, beside)
	sun.drag(Daylight.time_toward(beside) + sun._offset)
	_check(absf(look.time - Daylight.DEFAULT) < 1e-4, "taking the sun beside its disc does not jump it")
	_check(main.rig.right.holds_sun, "the hand holding the sun keeps its grip from other tools")
	sun.let_go()
	_check(not main.rig.right.holds_sun, "letting go of the sun frees the grip")
	await _play([{"op": "sun", "time": 0.9, "seconds": 0.2}])
	_check(absf(look.time - 0.9) < 1e-4, "the sun is dragged to late afternoon")
	_check((-look.sun.global_basis.z).is_equal_approx(-Daylight.toward_sun(0.9)), "the sunlight shines from where the sun stands")
	_check(look.sun.light_energy < Daylight.light(0.5).energy, "the evening sun is weaker")
	look.set_time(1.0)
	var where := Daylight.toward_sun(1.0)
	_check(sun.aims_at_sun(Vector3(where.x, 0.02, where.z).normalized()), "a sun gone down is taken where it set")
	look.set_time(0.9)
	await create_timer(Look.SKY_EVERY * 2.0).timeout
	var sky_sun: Vector3 = look.sky_mat.get_shader_parameter("sun_dir")
	_check(sky_sun.is_equal_approx(Daylight.toward_sun(0.9)), "the sky catches up with the sun once it rests")
	_check(look.sun.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_ONLY, "moving the light leaves the sky's radiance alone")
	_done()


func _done() -> void:
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
