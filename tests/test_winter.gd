extends "res://../tests/support/suite.gd"

## Headless checks of lilypads and winter: godot4 --headless --path game --script ../tests/test_winter.gd

const GladeBase = preload("res://../tests/support/glade.gd")
const STEP := 1.0 / 30.0
static var winter := Palette.SEASONS.find_custom(func(s: Dictionary) -> bool: return s.winter)


func _initialize() -> void:
	await process_frame
	_only_winter_is_wintry()
	_snow_lies_on_what_faces_the_open_sky()
	_pads_float_on_deep_water()
	_broadleaves_shed_and_firs_keep()
	_boughs_stand_over_the_trunk()
	await _a_pond_floats_pads_and_freezes()
	finish()


func _only_winter_is_wintry() -> void:
	for i in Palette.SEASONS.size():
		check(Palette.globals(i).season_winter == (1.0 if i == winter else 0.0), "%s sets season_winter for winter alone" % Palette.SEASONS[i].name)


## Snow lies by palette.gdshaderinc's own `snow_cover`, evaluated here as the shaders evaluate it: on what faces up under
## the open sky, in winter alone; and the ground, a build's pieces and thatch each ask it with what they know of both.
func _snow_lies_on_what_faces_the_open_sky() -> void:
	var code := (load("res://src/palette.gdshaderinc") as ShaderInclude).code
	var found := RegEx.create_from_string("float snow_cover\\(float (\\w+), float (\\w+), float (\\w+)\\) {\\s*return ([^;]+);\\s*}").search(code)
	check(found != null, "the snow's cover is one expression")
	if found == null:
		return
	var cover := Expression.new()
	check(cover.parse(found.get_string(4), ["season_winter", found.get_string(1), found.get_string(2), found.get_string(3)]) == OK, "which parses")
	var at := func(season: float, up: float, sky: float, drift := 0.5) -> float: return cover.execute([season, up, sky, drift], self)
	check(at.call(1.0, 1.0, 1.0) == 1.0, "snow covers level ground under the open sky")
	check(at.call(1.0, 1.0, 1.0, 0.0) == 1.0 and at.call(1.0, 1.0, 1.0, 1.0) == 1.0, "whatever the drift")
	check(at.call(1.0, 0.77, 1.0) == 1.0, "and a roof pitched at 40 degrees")
	check(at.call(1.0, 0.0, 1.0) == 0.0 and at.call(1.0, 0.0, 1.0, 1.0) == 0.0, "none clings to a wall's face")
	check(at.call(1.0, -1.0, 1.0) == 0.0, "nor to the underside of an eave")
	check(at.call(1.0, 1.0, 0.0) == 0.0, "none lies on a floor inside a room")
	check(at.call(1.0, 1.0, 0.3) == 0.0, "nor on ground the builds around shelter")
	var steep: float = at.call(1.0, 0.5, 1.0, 0.2)
	var steep_drifted: float = at.call(1.0, 0.5, 1.0, 0.8)
	check(steep > 0.0 and steep < steep_drifted and steep_drifted < 1.0, "a steep slope holds some, more where it has drifted: %.2f, %.2f" % [steep, steep_drifted])
	check(at.call(0.0, 1.0, 1.0) == 0.0, "and no other season has any")
	var asks := {
		"res://src/terrain.gdshaderinc": "snow_cover(1.0 - s, sky_seen, d) * lying * (1.0 - TRODDEN * clamp(max(cover.r, max(cover.g, cover.a)), 0.0, 1.0))",
		"res://src/stone.gdshaderinc": "COLOR.a = snow_cover(up, 1.0 - room_in, 0.5) * (1.0 - glass);",
		"res://src/thatch.gdshader": "snowy = snow_cover(world_nrm.y, 1.0 - room_in, straw);",
		"res://src/moss.gdshader": "snow_cover(up - 0.25, bounce.a, patchiness) * (1.0 - wet)",
		"res://src/plant.gdshaderinc": "COLOR.rgb = mix(COLOR.rgb, SNOW, snow_cover(lump_up + 0.3, 1.0, hash(",
	}
	for path: String in asks:
		var shader: Resource = load(path)
		check(str(shader.get("code")).contains(asks[path]), "%s lays snow by its slope and the sky over it" % path.get_file())
	check((load("res://src/terrain.gdshaderinc") as ShaderInclude).code.contains("lying = smoothstep(0.02, -0.04, under - season_winter * ICE_RIM);"), "the ground's snow reaches under the ice's snowy rim, so no wet bank rings it")
	for path: String in ["res://src/stone.gdshaderinc", "res://src/thatch.gdshader"]:
		check(str(load(path).get("code")).contains("EMISSION += ALBEDO * snowy * (1.0 - bounce.a) * sky_ambient * mix(sky_horizon, sky_zenith, 0.8);"), "a snowed face of %s takes the whole sky's light" % path.get_file())
	var frozen := {
		"res://src/water.gdshader": ["slope *= 1.0 - season_winter;", "if (rippling && season_winter < 0.5) {", "col = mix(col, sheet, season_winter);", "foam *= 1.0 - season_winter;"],
		"res://src/fish.gdshader": ["ALBEDO = mix(mix(c, tint, 0.25), ICE, season_winter * 0.12);"],
		"res://src/lilypad.gdshader": ["* 0.03 * (1.0 - season_winter);", "ALBEDO = mix(leaf, SNOW, season_winter * "],
		"res://src/grass.gdshader": ["float buried = 1.0 - season_winter * (1.0 - weed);", "* stretch, wide) * buried;", "hand_right)) * size * buried, tip);", "VERTEX.y = mix(VERTEX.y, min(VERTEX.y, root.y + depth - under_ice), season_winter * weed);"],
	}
	for path: String in frozen:
		for line: String in frozen[path]:
			check((load(path) as Shader).code.contains(line), "%s freezes: %s" % [path.get_file(), line])


## A bowl dug `deep` under level ground about grid point (20, 20), `wide` grid steps across, inside a low bank that
## keeps its water from the ground around, filled to its brim.
func _bowl(deep: float, wide: float) -> Array:
	var window := Rect2i(0, 0, 41, 41)
	var heights := PackedFloat32Array()
	heights.resize(window.size.x * window.size.y)
	for j in window.size.y:
		for i in window.size.x:
			var d := Vector2(i - 20, j - 20).length() / wide
			heights[j * window.size.x + i] = -deep * maxf(1.0 - d * d, 0.0) + 0.3 * exp(-(d - 1.3) * (d - 1.3) * 4.0)
	var pond := PondLayout.fill(heights, window, Vector2i(20, 20))
	var ground := func(x: float, z: float) -> float:
		var g := ((Vector2(x, z) + Vector2.ONE * Terrain.SIZE * 0.5) / Terrain.STEP).clamp(Vector2.ZERO, Vector2(39.999, 39.999))
		var i := int(g.x)
		var j := int(g.y)
		var w := window.size.x
		return lerpf(lerpf(heights[j * w + i], heights[j * w + i + 1], g.x - i), lerpf(heights[(j + 1) * w + i], heights[(j + 1) * w + i + 1], g.x - i), g.y - j)
	return [pond, ground, func(x: float, z: float) -> float: return pond.level - ground.call(x, z)]


## PadLayout lays a pond's pads over water deep enough to root in, each whole on the water and clear of the rest, a
## few to a small pond and no more than PER_POND on a wide one, the same ones each time, kept as the pond is dug wider.
func _pads_float_on_deep_water() -> void:
	var small := _bowl(1.0, 3.0)
	var pond: PondLayout.Pond = small[0]
	check(pond != null and pond.cells.size() > 12, "a bowl three metres across holds a pond")
	var want := PadLayout.quota(pond.cells.size(), PadLayout.CAP)
	var pads := PadLayout.pads(pond, small[1], want)
	check(pads.size() >= 4 and pads.size() <= PadLayout.PER_POND, "a small pond floats a few pads, %d of %d" % [pads.size(), want])
	_check_afloat(pads, small[2], "the small pond's")
	var again := PadLayout.pads(pond, small[1], want)
	check(again.size() == pads.size() and range(pads.size()).all(func(i: int) -> bool: return again[i].at == pads[i].at and again[i].radius == pads[i].radius and again[i].turn == pads[i].turn), "laid the same every time")

	var wide := _bowl(1.0, 9.0)
	var lake: PondLayout.Pond = wide[0]
	var many := PadLayout.pads(lake, wide[1], PadLayout.quota(lake.cells.size(), PadLayout.CAP))
	check(many.size() == PadLayout.PER_POND, "a wide pond floats its full %d, %d" % [PadLayout.PER_POND, many.size()])
	_check_afloat(many, wide[2], "the wide pond's")
	var middle := Terrain.grid_xz(Vector2i(20, 20))
	var rafted := many.filter(func(p: PadLayout.Leaf) -> bool: return many.any(func(o: PadLayout.Leaf) -> bool: return o != p and o.at.distance_to(p.at) < 1.0))
	check(rafted.size() >= many.size() * 3 / 4, "most in rafts, %d of %d within a metre of another" % [rafted.size(), many.size()])
	check(many.all(func(p: PadLayout.Leaf) -> bool: return p.at.distance_to(middle) < 9.0), "all on the pond")

	for n: int in [1, 3, 7]:
		check(PadLayout.pads(lake, wide[1], n).size() == n, "a pond given %d of the cap floats %d" % [n, n])
	check(many.any(func(p: PadLayout.Leaf) -> bool: return not is_equal_approx(p.radius, many[0].radius)), "pads of several sizes")
	check(PadLayout.quota(1000, 5) == 5 and PadLayout.quota(3, 96) == 2 and PadLayout.quota(1000, 0) == 0, "the cap is shared out, a pad to every %d wet points" % PadLayout.CELLS_EACH)
	var shallow := func(x: float, z: float) -> float: return maxf(small[1].call(x, z), pond.level - PadLayout.MIN_DEPTH + 0.01)
	check(PadLayout.pads(pond, shallow, PadLayout.PER_POND).is_empty(), "water too shallow to root in floats none")


func _check_afloat(pads: Array[PadLayout.Leaf], depth: Callable, whose: String) -> void:
	for i in pads.size():
		var p := pads[i]
		check(depth.call(p.at.x, p.at.y) >= PadLayout.MIN_DEPTH, "%s pad %d lies over %.2f m of water" % [whose, i, depth.call(p.at.x, p.at.y)])
		check(p.radius >= PadLayout.RADIUS.x and p.radius <= PadLayout.RADIUS.y, "%s pad %d is a pad's size" % [whose, i])
		for k in 6:
			var rim := p.at + Vector2.from_angle(k * TAU / 6.0) * p.radius
			check(depth.call(rim.x, rim.y) >= PadLayout.RIM_DEPTH, "%s pad %d is whole on the water" % [whose, i])
		for j in i:
			check(pads[j].at.distance_to(p.at) >= pads[j].radius + p.radius + PadLayout.GAP, "%s pads %d and %d lie clear of each other" % [whose, j, i])


## A broadleaf's blobs are marked to fall for the winter and its trunk carries how far its boughs reach; a fir and a
## bush keep their leaves, and a fir shows no boughs. The leaf shader folds a shed blob away in winter alone.
func _broadleaves_shed_and_firs_keep() -> void:
	for species: FloraLayout.Species in FloraLayout.Species.values():
		var t := FloraLayout.tree(Vector3.ZERO, 5, species)
		var fir := species == FloraLayout.Species.FIR
		var name: String = FloraLayout.Species.keys()[species]
		check(t.blobs.all(func(b: Array) -> bool: return b[1].a == (FloraLayout.KEPT if fir else FloraLayout.SHED)), "%s %s its leaves" % [name, "keeps" if fir else "sheds"])
		check(is_equal_approx(t.bark.a, FloraLayout.BOUGH_SPREAD[species]) and (t.bark.a == 0.0) == fir, "%s's trunk carries its boughs' reach, %.2f" % [name, t.bark.a])
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	check(FloraLayout.bush(Vector3.ZERO, rng)[1].a == FloraLayout.KEPT, "a bush keeps its leaves")
	var code := (load("res://src/plant.gdshaderinc") as ShaderInclude).code
	check(code.contains("if (COLOR.a < 0.5 && season_winter > 0.5) {\n\t\tVERTEX = vec3(INSTANCE_CUSTOM.z, ground, INSTANCE_CUSTOM.w);"), "the leaf shader folds a shed blob to its tree's foot in winter")
	check(code.contains("if (along > bough_from) {\n\t\tVERTEX += (from_trunk - axis * along) * (length(axis) * COLOR.a / length(MODEL_MATRIX[0].xyz) - 1.0);"), "and the bark shader spreads what stands over the trunk's top by the reach its colour carries")


## The bare trunk is the trunk's own cylinder with boughs over its top: every bough vertex off the trunk's axis lies
## over BOUGH_FROM, where the shader spreads it, within a crown's unit reach and Flora's culling box.
func _boughs_stand_over_the_trunk() -> void:
	var trunk := ToolModels.cylinder(0.16, 0.3, 1.0, 8)
	var bare := Meshes.bare_trunk(trunk)
	var plain: PackedVector3Array = trunk.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
	var verts: PackedVector3Array = bare.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = bare.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	check(verts.slice(0, plain.size()) == plain, "the trunk stands as it does in leaf")
	check(plain.size() > 0 and Array(plain).all(func(v: Vector3) -> bool: return v.y < Meshes.BOUGH_FROM), "all of it under where boughs begin")
	var boughs := verts.slice(plain.size())
	check(boughs.size() > 100 and index.size() % 3 == 0 and Array(index).all(func(i: int) -> bool: return i < verts.size()), "with boughs over it, %d vertices" % boughs.size())
	var reach := 0.0
	var top := 0.0
	var spread := 0
	for v in boughs:
		var out := Vector2(v.x, v.z).length()
		if v.y > Meshes.BOUGH_FROM:
			spread += 1
			reach = maxf(reach, out)
			top = maxf(top, v.y)
		else:
			check(out < 0.05 and v.y > 0.3, "a bough leaves the trunk from its axis, inside its top, %s" % v)
	check(spread > boughs.size() / 2, "most of them spread")
	check(reach > 0.9 and reach < 1.25, "to the crown's edge, %.2f of its reach" % reach)
	check(top > 1.0 and top < 1.3, "and up through where the crown stood, %.2f" % top)


## A dug pond floats pads once it has filled; in winter it freezes: a hand rings no ripple from the ice, the fish swim on
## under it and leave seeds thrown on it alone, the pads stay, and the trees are drawn bare. Summer brings it all back.
func _a_pond_floats_pads_and_freezes() -> void:
	var world := World.new()
	world.terrain.install()
	var rig := Rig.new(world.terrain)
	root.add_child(rig)
	root.add_child(world)
	var grab := GroundGrab.new(rig, world)
	root.add_child(grab)
	var hand := Node3D.new()
	root.add_child(hand)
	hand.global_position = Vector3(0, 30, 0)
	var hands: Array[Node3D] = [hand]
	var water := Water.new(world.terrain, hands)
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
	await process_frame
	var wildlife := Wildlife.new(world.terrain, world.marks, water, flora, null, world.palette, rig.head, hands, 3)
	root.add_child(wildlife)
	var feed := FeedTool.new(rig, water, world.terrain)
	feed.set_process(false)
	root.add_child(feed)
	wildlife.handfuls = feed.handfuls
	wildlife.set_process(false)
	var pads := water.pads
	check(pads.count() == 0 and pads.multimesh.visible_instance_count == 0, "no pond, no pads")

	await GladeBase.dig(tool, 3, -4)
	await GladeBase.dig(tool, 4.5, -4)
	var pond := water.ponds[0]
	var n := pads.count()
	check(n >= 3 and n <= PadLayout.PER_POND and pads.multimesh.visible_instance_count == n, "a dug pond has pads, %d" % n)
	check(not pond.full() and range(n).all(func(i: int) -> bool: return pads._grown[pads.pad(i).at] == 0.0), "furled while it fills")
	pond._process(PondWater.FILL)
	pads._process(Pads.GROW * 0.5)
	check(range(n).all(func(i: int) -> bool: return is_equal_approx(pads._grown[pads.pad(i).at], 0.5)), "opening once it has")
	pads._process(Pads.GROW)
	check(range(n).all(func(i: int) -> bool: return pads._grown[pads.pad(i).at] == 1.0) and not pads.is_processing(), "and then lying open, at rest")
	var on_water := func() -> bool:
		return range(pads.count()).all(func(i: int) -> bool:
			var p := pads.pad(i)
			var under := water.pond_at(p.at.x, p.at.y)
			return under != null and is_equal_approx(pads.buffer[i * pads.stride + 7], under.pond.level + Pads.LIFT) and under.pond.level - world.terrain.height_at(p.at.x, p.at.y) >= PadLayout.MIN_DEPTH)
	check(on_water.call(), "each drawn on its pond's surface, over deep water")
	var before := range(n).map(func(i: int) -> Vector2: return pads.pad(i).at)
	await GladeBase.dig(tool, 5.8, -4.2)
	water.ponds[0]._process(PondWater.FILL)
	var kept := before.filter(func(at: Vector2) -> bool: return range(pads.count()).any(func(i: int) -> bool: return pads.pad(i).at == at))
	check(kept.size() >= before.size() - 2 and on_water.call(), "a pond dug wider keeps its pads, %d of %d" % [kept.size(), before.size()])
	check(kept.all(func(at: Vector2) -> bool: return pads._grown[at] == 1.0), "open as they were")
	pond = water.ponds[0]

	for i in int((Wildlife.ARRIVE_AFTER.y + Fish.FADE + 1.5) / STEP):
		wildlife.tick(STEP)
	var fish := wildlife.fish
	check(not fish.swimming.is_empty(), "and fish")
	var tree := flora.add_tree(world.terrain.ground(-6, 3), 4)
	await process_frame
	check(flora.trunks.drawn == flora.trunks.mesh and not Palette.wintry() and pond._lap.playing, "in summer a tree's trunk is drawn plain and the pond laps")
	check(flora.trunks.material.get_shader_parameter("bough_from") == Meshes.BOUGH_FROM, "the bark shader knows where boughs begin")
	var bare := flora._bare_trunk.get_aabb()
	var widest := 0.0
	for v: Vector3 in flora._bare_trunk.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		widest = maxf(widest, Vector2(v.x, v.z).length())
	check(flora.trunks.overhang >= bare.end.y - 0.5 and flora.trunks.overhang >= widest * FloraLayout.BOUGH_SPREAD.values().max(), "the box a trunk is culled by holds its boughs at their widest, %.2f trunk heights past it" % flora.trunks.overhang)
	var box := flora.trunks._box(tree[0].xform)
	var height := tree[0].xform.basis.y.length()
	check(box.size.x >= 2.0 * height * FloraLayout.BOUGH_SPREAD[FloraLayout.Species.OAK] and box.end.y >= tree[0].xform.origin.y + height * (bare.end.y - 0.0), "this oak's among them")
	var mid := Terrain.grid_xz(pond.pond.bottom)
	var dip := Vector3(mid.x, pond.surface_y(), mid.y)
	hand.global_position = dip
	await frames(2)
	check(pond._live > 0, "a hand dipped in the pond rings a ripple")
	hand.global_position = Vector3(0, 30, 0)
	pond._process(PondWater.RIPPLE_LIFE + 0.1)
	await frames(2)

	world.submit({"op": "season", "index": winter})
	await frames(2)
	check(Palette.wintry() and world.palette.season == winter, "winter comes")
	check(not pond._lap.playing, "the pond freezes over and its lapping stops")
	check(flora.trunks.drawn == flora._bare_trunk and flora.trunks.drawn != flora.trunks.mesh, "the trees are drawn bare")
	check(tree.slice(1).all(func(p: Flora.Plant) -> bool: return p.pool == flora.foliage and p.pool.colour_of(p.slot).a == FloraLayout.SHED), "an oak's blobs stand marked to be shed")
	check(pond._live == 0, "still")
	hand.global_position = dip
	await frames(2)
	hand.global_position = dip + Vector3(0.3, 0, 0)
	await frames(2)
	check(pond._live == 0, "a hand on the ice rings no ripple")
	hand.global_position = Vector3(0, 30, 0)
	check(pads.count() >= kept.size() and on_water.call(), "the pads stay, frozen in")
	var s := feed.toss(Vector3(mid.x, pond.surface_y() + 1.2, mid.y), Vector3(0.2, 0.5, 0.1), 11)
	var fed := [false]
	var swam := true
	var start := fish.swimming.map(func(f: Fish.One) -> Vector3: return f.at)
	for i in int(20.0 / STEP):
		feed.tick(STEP)
		wildlife.tick(STEP)
		fed[0] = fed[0] or fish.swimming.any(func(f: Fish.One) -> bool: return f.feeding)
		swam = swam and fish.swimming.all(func(f: Fish.One) -> bool:
			var p := water.pond_at(f.at.x, f.at.z)
			return p != null and f.at.y < p.surface_y() and f.at.y > world.terrain.height_at(f.at.x, f.at.z))
	check(s.landed() and not fed[0] and fish.frenzy()[1] == 0, "seeds thrown on the ice bring no fish up to feed")
	var moved := 0.0
	for i in mini(start.size(), fish.swimming.size()):
		moved += fish.swimming[i].at.distance_to(start[i])
	check(swam and not fish.swimming.is_empty() and moved / fish.swimming.size() > 0.1, "which swim on under the ice, %.2f m on average" % (moved / maxi(fish.swimming.size(), 1)))
	await GladeBase.dig(tool, -6, 5)
	check(not water.ponds[-1]._lap.playing, "a pond dug in winter freezes too")

	world.submit({"op": "season", "index": Palette.SUMMER})
	await frames(2)
	check(not Palette.wintry() and water.ponds.all(func(w: PondWater) -> bool: return w._lap.playing), "summer thaws them")
	check(flora.trunks.drawn == flora.trunks.mesh, "and the trees are in leaf again")
	hand.global_position = dip
	await frames(2)
	check(pond._live > 0, "a hand rings the water once more")
	feed.toss(Vector3(mid.x, pond.surface_y() + 1.2, mid.y), Vector3(0.2, 0.5, 0.1), 12)
	for i in int(12.0 / STEP):
		feed.tick(STEP)
		wildlife.tick(STEP)
		fed[0] = fed[0] or fish.swimming.any(func(f: Fish.One) -> bool: return f.feeding)
	check(fed[0], "and the fish rise to seeds again")
	hand.global_position = Vector3(0, 30, 0)
	wildlife.free()
	for node: Node in [feed, tool, grab, water, flora, paths, world, rig, hand]:
		node.queue_free()
	await process_frame
