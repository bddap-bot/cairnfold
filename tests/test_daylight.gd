extends SceneTree

## Headless checks of time of day, seasons and the colour picker, as data and through the tools:
## godot4 --headless --path game --script ../tests/test_daylight.gd

var failures := 0
var main: Node


func _initialize() -> void:
	_the_sun_rises_and_sets()
	_the_sky_turns_about_the_arc()
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


func _the_sky_turns_about_the_arc() -> void:
	for i in 21:
		var t := i / 20.0
		_check(absf(wrapf(Daylight.turn_of(Daylight.toward_sun(t)) - Daylight.angle(t), -PI, PI)) < 1e-4, "the sun at %.2f stands as far round as its hour" % t)
	var axis := Daylight.RISE.cross(Daylight.ARC_UP)
	var d := Vector3(0.3, 0.6, -0.5).normalized()
	_check(absf(Daylight.turn_of(d.rotated(axis, 0.4)) - Daylight.turn_of(d) - 0.4) < 1e-4, "turning a direction about the arc's axis turns it as far round")
	_check(absf(Daylight.turn_of(d + axis * 0.5) - Daylight.turn_of(d)) < 1e-4, "moving along the axis turns nothing")


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
	for e in Palette.SWATCHES:
		_check(Palette.tint(e, 0) == Color.WHITE, "%s keeps its laid colour" % Palette.Element.keys()[e])
	var g := Palette.globals(Palette.new().season)
	_check(g.season_meadow.w == 0.0 and g.season_foliage.w == 0.0 and g.season_bloom == 1.0, "summer is the meadow as tuned")
	var want: Color = Palette.SWATCHES[Palette.Element.ROOF][1]
	var base: Color = Palette.SWATCHES[Palette.Element.ROOF][0]
	_check((base * Palette.tint(Palette.Element.ROOF, 1)).is_equal_approx(want), "a swatch scales the laid colour onto it")
	var paint := Palette.plain()
	_check(Palette.valid(paint), "plain paint is paint")
	paint[Palette.Element.ROOF] = Palette.count(Palette.Element.ROOF)
	_check(not Palette.valid(paint), "a swatch off the wheel is not")
	paint = Palette.plain()
	paint[Palette.Element.MEADOW] = 1
	_check(not Palette.valid(paint), "nor is a season in a build's paint")


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
	coped.ruins = [Vector2(2.0, 3.5)]
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
	var deck := RoofLayout.new()
	deck.corners = roof.corners
	deck.pitch = 0.0
	deck.build()
	for s in wall.stones + coped.stones + fence.stones + roof.tiles + deck.tiles:
		kinds[s.kind] = true
	for k in kinds:
		_check(Palette.KINDS.has(k) != kept.has(k), "a laid %s is either painted with a material or kept on purpose" % k)
	for k in Palette.KINDS:
		_check(kinds.has(k), "%s is a kind something lays" % k)
	var want := {
		Palette.Element.STONE: ["block", "mortar", "voussoir", "keystone", "pillar", "cope", "cap", "merlon", "pier", "lintel", "sill", "mullion", "chimney", "rubble"],
		Palette.Element.ROOF: ["tile", "ridge"],
		Palette.Element.WOOD: ["post", "rail", "gate", "frame", "door", "pole"],
		Palette.Element.PLASTER: ["plaster"],
	}
	for e in want:
		for k in want[e]:
			_check(Palette.code(k) == e, "a laid %s is painted with %s, got code %s" % [k, Palette.Element.keys()[e], Palette.code(k)])
	for k in kept:
		_check(Palette.code(k) == 0.0, "a laid %s keeps its colour" % k)
	var packed := Wall.pack(wall, Wall.kinds(), Palette.plain())
	var stride := Wall.kinds()[Wall.Part.STONE].stride()
	var codes := {}
	for i in range(0, packed.stone.size(), stride):
		codes[packed.stone[i + 17]] = true
	_check(codes.has(float(Palette.Element.STONE)) and codes.has(float(Palette.Element.WOOD)) and codes.has(0.0), "a wall's packed parts carry their materials' codes, which a repaint scales by: %s" % [codes.keys()])
	var paint := Palette.plain()
	paint[Palette.Element.WOOD] = 3
	var painted := Wall.pack(wall, Wall.kinds(), paint)
	var tinted := true
	for i in range(0, packed.stone.size(), stride):
		var was := Color(packed.stone[i + 12], packed.stone[i + 13], packed.stone[i + 14])
		var now := Color(painted.stone[i + 12], painted.stone[i + 13], painted.stone[i + 14])
		var expect := was * Palette.tint(Palette.Element.WOOD, 3) if packed.stone[i + 17] == Palette.Element.WOOD else was
		tinted = tinted and now.is_equal_approx(expect)
	_check(tinted and painted.paint == paint, "a wall packed in its paint scales its wood onto the swatch and leaves the rest")
	var door: Dictionary = wall.stones.filter(func(s): return s.kind == "door")[0]
	_check(Stones.custom(door) == Color(door.ao, Palette.Element.WOOD, 0, 0), "a laid door carries its occlusion and wood's code to its shader")
	_check(Stones.custom({"ao": 0.85}) == Color(0.85, 0, 0, 0), "paving, with no kind, keeps its colour")


func _shaders_read_the_codes_and_globals_palette_writes() -> void:
	var inc := FileAccess.get_file_as_string("res://src/palette.gdshaderinc")
	_check(FileAccess.get_file_as_string("res://src/plaster.gdshader").contains("instance uniform vec3 tint"), "a gable takes its build's plaster per instance")
	for name in Palette.globals(0):
		_check(ProjectSettings.has_setting("shader_globals/" + name) and inc.contains("global uniform") and inc.contains(" %s;" % name), "%s is a declared shader global" % name)


## Directive (verbatim): "If I make one wall somewhere, and then I make another wall elsewhere, and I select the color
## on the first wall, it changes the color on the other wall too. I'd like color to be per wall instead of global"
func _per_build(face: Vector3, walls: Array[Wall], roof: Dictionary) -> void:
	var tool: PaletteTool = main.palette_tool
	var world: World = main.world
	var first := walls[0]
	var house := walls[1]
	var other := walls[3]
	for w in walls:
		w.lay_now()
	var first_was := first._parts[Wall.Part.STONE].duplicate()
	var other_was := other._parts[Wall.Part.STONE].duplicate()
	var steps: int = world.stacks.get(world.me(), {"undo": []}).undo.size()
	var at := face
	await _play([{"op": "colour", "hand": "left", "element": "stone", "swatch": 2, "seconds": 0.2, "from": _above(at + Vector3(0, 0, 3)), "at": _above(at)}])
	var stone := Palette.Element.STONE
	_check(world.state.walls[first.id].paint[stone] == 2 and tool.wheels.is_empty(), "a twist to the third swatch on the first wall keeps it there")
	_check(world.state.walls[other.id].paint[stone] == 0 and world.state.walls[house.id].paint[stone] == 0, "the other wall and the house keep their stone")
	_check(world.stacks[world.me()].undo.size() == steps + 1, "a pick is one undo step")
	_check(_scaled_by(first_was, first._parts[Wall.Part.STONE], Palette.tint(stone, 2)), "the first wall's stones are drawn in the new swatch")
	_check(other._parts[Wall.Part.STONE] == other_was, "the other wall's stones are drawn as they were")
	var top: Vector3 = roof.mid
	await _play([{"op": "colour", "hand": "left", "element": "roof", "swatch": 3, "seconds": 0.2, "from": _above(top + Vector3.UP * 12.0), "at": _above(top)}])
	_check(world.state.walls[house.id].paint[Palette.Element.ROOF] == 3, "the house's roof takes the fourth swatch")
	var end: Vector3 = roof.mid + roof.along * (house.roof.ridge_length() * 0.5 + 4.0) + Vector3.UP * house.roof.pitch * 0.35
	var gable: Vector3 = end - roof.along
	await _play([{"op": "colour", "hand": "left", "element": "plaster", "swatch": 1, "seconds": 0.2, "from": _above(end), "at": _above(gable)}])
	var t := Palette.tint(Palette.Element.PLASTER, 1)
	_check(house._gables.get_instance_shader_parameter(&"tint") == Vector3(t.r, t.g, t.b), "the house's gables take its plaster")
	await _play([{"op": "colour", "hand": "left", "element": "meadow", "swatch": 4, "seconds": 0.2}])
	_check(Palette.globals(world.palette.season).season_bloom == 0.0, "winter takes the flowers")

	var snap := world.snapshot().duplicate(true)
	_check(snap.cmds.filter(func(c: Dictionary) -> bool: return c.op == "season").size() == 1, "a joiner's snapshot carries the season")
	await _play([{"op": "press", "button": "dpad_down"}, {"op": "press", "button": "dpad_down"}, {"op": "press", "button": "dpad_down"}, {"op": "press", "button": "dpad_down"}])
	_check(world.palette.season == Palette.SUMMER and world.state.walls.values().all(func(d: Dictionary) -> bool: return d.paint == Palette.plain()), "undo takes every pick back")
	_check(_scaled_by(first_was, first._parts[Wall.Part.STONE], Color.WHITE), "the first wall's stones are drawn as laid again")
	await _play([{"op": "press", "button": "dpad_up"}])
	_check(world.state.walls[first.id].paint[stone] == 2 and world.state.walls[other.id].paint[stone] == 0, "redo paints the first wall again, and only it")

	var first_id := first.id
	world.submit({"op": "unwall", "ids": PackedInt32Array([first_id])})
	_check(not world.state.walls.has(first_id), "the painted wall is deleted")
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(world.state.walls.get(first_id, {}).get("paint", Palette.plain())[stone] == 2, "undoing the delete brings it back in its colour")
	var back := main.tool.find(first_id) as Wall
	back.lay_now()
	_check(back != null and _scaled_by(first_was, back._parts[Wall.Part.STONE], Palette.tint(stone, 2)), "and draws it so")

	_check(main.tool.paint[stone] == 2 and main.tool.paint[Palette.Element.ROOF] == 3, "the swatches last picked are the ones new builds take")
	var before: Array = world.state.walls.keys()
	await _play([{"op": "wall", "points": [[-8, -12], [2, -12]], "seconds": 0.3}])
	var fresh: Array = world.state.walls.keys().filter(func(id: int) -> bool: return not id in before)
	_check(fresh.size() == 1 and world.state.walls[fresh[0]].paint[stone] == 2, "a new wall is laid in the stone last picked")

	var left: Hand = main.rig.left
	tool.open(left, tool.aim(face + Vector3(0, 0, 3), Vector3.FORWARD))
	tool.twist(left, Palette.TWIST_STEP * 0.0)
	var steps_now: int = world.stacks[world.me()].undo.size()
	tool.close(left)
	_check(world.stacks[world.me()].undo.size() == steps_now, "a wheel let go on the swatch the build already has sends nothing")
	var house_id := house.id
	world.restore(snap)
	_check(world.palette.season == 4 and world.state.walls[first_id].paint[stone] == 2 and world.state.walls[house_id].paint[Palette.Element.ROOF] == 3, "a garden rebuilt from its snapshot keeps each build's colours")
	var off := Palette.plain()
	off[Palette.Element.ROOF] = Palette.count(Palette.Element.ROOF)
	_check(Commands.clean({"op": "reshape", "id": house_id, "data": {"paint": off}}, world.state, false).is_empty(), "a swatch off the wheel is refused")


## `p` as a driver step aims at it.
func _above(p: Vector3) -> Array:
	return [p.x, p.y - Terrain.height_at(p.x, p.z), p.z]


## Whether each piece of `now` is the one in `was` with its stone's colour scaled by `tint`.
func _scaled_by(was: PackedFloat32Array, now: PackedFloat32Array, tint: Color) -> bool:
	var stride := Wall.kinds()[Wall.Part.STONE].stride()
	if was.size() != now.size() or was.is_empty():
		return false
	for i in range(0, was.size(), stride):
		var k := tint if was[i + 17] == Palette.Element.STONE else Color.WHITE
		if not (Color(was[i + 12], was[i + 13], was[i + 14]) * k).is_equal_approx(Color(now[i + 12], now[i + 13], now[i + 14])):
			return false
	return true


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
		{"op": "house", "at": [11.0, 0.0], "size": [6.0, 3.7], "seconds": 0.2},
		{"op": "fence", "points": [[-8, 6], [-2, 6]], "seconds": 0.3},
		{"op": "fit", "what": "window", "index": 0, "s": 2.5, "y": 1.5},
		{"op": "wall", "points": [[-8, -6], [2, -6]], "seconds": 0.3},
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

	await _per_build(face, walls, f)

	var look: Look = main.look
	var sky: SkyTool = main.sky_tool
	var grab := Daylight.toward_sun(look.time).rotated(Vector3.UP, deg_to_rad(40.0))
	sky.take(main.rig.right, grab)
	sky.aim(grab)
	_check(absf(look.time - Daylight.DEFAULT) < 1e-4, "grabbing the sky does not jump it")
	var axis := Daylight.RISE.cross(Daylight.ARC_UP)
	var sun_at := Daylight.toward_sun(look.time)
	sky.aim(grab.rotated(axis, 0.3))
	_check(absf(Daylight.angle(look.time) - Daylight.angle(Daylight.DEFAULT) - 0.3) < 1e-4, "the sky turns as far as the pointer")
	_check(Daylight.toward_sun(look.time).is_equal_approx(sun_at.rotated(axis, 0.3)), "the sun turns with it")
	for k in range(1, 8):
		sky.aim(grab.rotated(axis, k * 0.5))
	_check(look.time == 1.0, "past dusk the sky waits")
	for k in range(6, 0, -1):
		sky.aim(grab.rotated(axis, k * 0.5))
	sky.aim(grab.rotated(axis, 0.3))
	_check(absf(Daylight.angle(look.time) - Daylight.angle(Daylight.DEFAULT) - 0.3) < 1e-4, "and the grabbed point is under the pointer again when it comes back")
	sky.holder = null
	await _play([{"op": "sun", "time": 0.9, "seconds": 0.2}])
	_check(absf(look.time - 0.9) < 1e-4, "the sky is turned to late afternoon")
	_check((-look.sun.global_basis.z).is_equal_approx(-Daylight.toward_sun(0.9)), "the sunlight shines from where the sun stands")
	_check(look.sun.light_energy < Daylight.light(0.5).energy, "the evening sun is weaker")
	look.set_time(0.9)
	await create_timer(Look.SKY_EVERY * 2.0).timeout
	var sky_sun: Vector3 = look.sky_mat.get_shader_parameter("sun_dir")
	_check(sky_sun.is_equal_approx(Daylight.toward_sun(0.9)), "the sky catches up with the sun once it rests")
	_check(look.sun.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_ONLY, "moving the light leaves the sky's radiance alone")
	_done()


func _done() -> void:
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
