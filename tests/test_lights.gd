extends "res://../tests/support/suite.gd"

## Headless checks of lights, strings and smoke: lanterns' colours and brightnesses and the light they bake, a string's
## sag and what hangs from it, the commands a string takes, a stroke of the decorations tool hanging one, the colour and
## style tools on lanterns and strings, lanterns standing on the ground, flags along a wall joining into runs, chimney
## smoke, demo/lights.json and the stress scene's lights/* phases:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_lights.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_looks()
	_baked()
	_sag()
	_strung()
	_commands()
	_runs()
	_vents()
	boot_main()
	await process_frame
	main.world.bounded = false
	await _stroke()
	await _coloured()
	await _smoking()
	await _demo()
	await _stress()
	finish()


func _span(style := "Lantern string", to := Vector3(8, 3, 0)) -> Dictionary:
	return {"op": "decoration", "wall": -1, "mount": "span", "at": Vector3(0, 3, 0), "to": to, "drop": Vector2(DecorationLayout.POLE, 0.0), "s": 0.0, "side": 1.0, "turn": 0.0, "seed": 2, "style": DecorationLayout.named(style), "lantern": 0}


func _rgb(layers: Array[PackedByteArray], x: float, z: float, layer: int) -> Vector3:
	var c := Bounce.column(x, z)
	var p := (c.y * Bounce.CELLS + c.x) * 4
	return Vector3(layers[layer][p], layers[layer][p + 1], layers[layer][p + 2]) / 255.0 * Lamps.ENCODE


func _looks() -> void:
	var colours := Palette.GLOWS.size()
	check(Palette.count(Palette.Element.LANTERN) == colours * 3, "a lantern burns in each glow colour at three brightnesses: %d" % Palette.count(Palette.Element.LANTERN))
	check(Lamps.light_of(0) == Palette.GLOWS[0] and Palette.swatch(Palette.Element.LANTERN, 0) == Palette.GLOWS[0], "a lantern as laid burns lit in the first glow colour")
	var strength := func(look: int) -> float: return Lamps.light_of(look).r + Lamps.light_of(look).g + Lamps.light_of(look).b
	for c in colours:
		check(strength.call(c * 3 + 1) > strength.call(c * 3) and strength.call(c * 3) > strength.call(c * 3 + 2), "colour %d: bright outshines lit, lit outshines dim" % c)
	var green := Lamps.light_of(4 * 3)
	check(green.g > green.r and green.g > green.b, "a green lantern's light is green: %s" % green)
	check(Commands._decoration(_span().merged({"lantern": Palette.count(Palette.Element.LANTERN)}, true)) == null and Commands._decoration(_span().merged({"lantern": -1}, true)) == null, "no lantern swatch past the last")


func _baked() -> void:
	var ground := Bounce.grounds(Terrain.new().read(Terrain.ALL))
	var flame := PackedVector3Array([Vector3(0.5, 1.8, 0.5)])
	var lit := _rgb(Lamps.shine(flame, ground), 0.5, 2.5, 0)
	var plain := _rgb(Lamps.shine(flame, ground, [], PackedColorArray([Lamps.light_of(0)])), 0.5, 2.5, 0)
	check(lit.is_equal_approx(plain), "a lantern given no light burns lit in the first colour")
	var bright := _rgb(Lamps.shine(flame, ground, [], PackedColorArray([Lamps.light_of(1)])), 0.5, 2.5, 0)
	var dim := _rgb(Lamps.shine(flame, ground, [], PackedColorArray([Lamps.light_of(2)])), 0.5, 2.5, 0)
	check(bright.x > lit.x * 1.8 and dim.x < lit.x * 0.6 and dim.x > 0.0, "the light baked grows with brightness: dim %.2f, lit %.2f, bright %.2f" % [dim.x, lit.x, bright.x])
	var blue := _rgb(Lamps.shine(flame, ground, [], PackedColorArray([Lamps.light_of(6 * 3)])), 0.5, 2.5, 0)
	check(blue.z > blue.x and lit.x > lit.z, "a blue lantern lights the ground blue where an amber one lights it amber: %s, %s" % [blue, lit])


func _sag() -> void:
	var span := Vector3(10, 0, 0)
	check(DecorationLayout.hang_at(span, 0.0).is_zero_approx() and DecorationLayout.hang_at(span, 1.0).is_equal_approx(span), "a string meets both its ends")
	var lowest := INF
	var at := 0.0
	for i in 101:
		var y := DecorationLayout.hang_at(span, i / 100.0).y
		if y < lowest:
			lowest = y
			at = i / 100.0
	check(is_equal_approx(at, 0.5) and is_equal_approx(lowest, -DecorationLayout.sag(span)), "it sags lowest at its middle: %.2f at %.2f" % [lowest, at])
	check(is_equal_approx(DecorationLayout.sag(span), 10.0 * DecorationLayout.SAG), "ten metres across sag %.2f" % (10.0 * DecorationLayout.SAG))
	check(DecorationLayout.sag(Vector3(4, 0, 0)) < DecorationLayout.sag(span), "a shorter string sags less")
	check(DecorationLayout.sag(Vector3(0.3, 0, 0)) == DecorationLayout.SAG_LEAST and DecorationLayout.sag(Vector3(30, 0, 0)) == DecorationLayout.SAG_MOST, "between its least and most sag")
	var rising := Vector3(10, 2, 0)
	check(is_equal_approx(DecorationLayout.hang_at(rising, 0.5).y, 1.0 - DecorationLayout.sag(rising)), "a rising string sags below the line between its ends")
	check(is_equal_approx(DecorationLayout.sag(rising), DecorationLayout.sag(span)), "its sag follows its span across the ground")


func _strung() -> void:
	var span := Vector3(8, 0, 0)
	var lanterns := DecorationLayout.new()
	lanterns.build(DecorationLayout.named("Lantern string"), 2, 0.6, "span", span, Vector2(DecorationLayout.POLE, 0.0))
	check(lanterns.flames.size() == floori(8.0 / DecorationLayout.LANTERN_EVERY), "a lantern every %.1f m: %d" % [DecorationLayout.LANTERN_EVERY, lanterns.flames.size()])
	check(lanterns.flames.all(func(f: Transform3D) -> bool: return f.origin.y < DecorationLayout.hang_at(span, f.origin.x / span.x).y - 0.15), "each hangs under the rope")
	var ropes := lanterns.parts.filter(func(p: Dictionary) -> bool: return p.kind == "rope")
	var off := 0.0
	for p: Dictionary in ropes:
		off = maxf(off, absf(p.xform.origin.y - DecorationLayout.hang_at(span, p.xform.origin.x / span.x).y))
	check(ropes.size() >= 10 and off < 0.03, "its rope follows the sag: %d pieces, off by %.3f" % [ropes.size(), off])
	var poles := lanterns.parts.filter(func(p: Dictionary) -> bool: return p.kind == "board")
	check(poles.size() == 1 and absf(poles[0].xform.origin.x) < 0.01, "a pole under the end on the ground, none under the end tied to a build")
	var foot: Vector3 = poles[0].xform * Vector3(0, -0.5, 0)
	check(absf(foot.y + DecorationLayout.POLE) < 0.01, "the pole stands on the ground: foot at %.2f" % foot.y)
	var flags := DecorationLayout.new()
	flags.build(DecorationLayout.named("Flag string"), 2, 0.6, "span", span, Vector2.ZERO)
	var cloth := flags.parts.filter(func(p: Dictionary) -> bool: return p.kind == "")
	check(flags.flames.is_empty() and cloth.size() == floori(8.0 / DecorationLayout.FLAG_EVERY), "a flag every %.2f m and no flame: %d" % [DecorationLayout.FLAG_EVERY, cloth.size()])
	var hung := cloth.all(func(p: Dictionary) -> bool:
		var top: Vector3 = p.xform * Vector3(0.5, 0.5, 0)
		return absf(top.y - DecorationLayout.hang_at(span, top.x / span.x).y) < 0.02)
	check(hung, "each flag hangs from its corner on the rope")
	var colours := {}
	for p in cloth:
		colours[p.color] = true
	check(colours.size() >= 3 and cloth[0].color != cloth[1].color, "neighbouring flags differ in colour: %d colours" % colours.size())
	var again := DecorationLayout.new()
	again.build(DecorationLayout.named("Flag string"), 2, 0.6, "span", span, Vector2.ZERO)
	check(again.parts == flags.parts, "the same string lays the same pieces")
	check(Budget.decoration(_span()).fitting > Budget.decoration(_span("Lantern string", Vector3(3, 3, 0))).fitting, "a longer string is charged more")


func _commands() -> void:
	check(Commands._decoration(_span()) != null and Commands._decoration(_span("Flag string")) != null, "a string of lanterns or flags is a valid command")
	check(Commands._decoration(_span("Lantern string", Vector3(1, 3, 0))) == null, "a string shorter than %.1f m across is refused" % DecorationLayout.SPAN_LEAST)
	check(Commands._decoration(_span("Lantern string", Vector3(DecorationLayout.SPAN_MOST + 1.0, 3, 0))) == null, "and one longer than %.0f m" % DecorationLayout.SPAN_MOST)
	check(Commands._decoration(_span("Lantern string", Vector3(3, 7, 0))) == null, "and one climbing too steeply")
	check(Commands._decoration(_span("Present")) == null, "a present hangs on no span")
	check(Commands._decoration(_span().merged({"mount": "ground"}, true)) == null, "a string stands nowhere but on a span")
	var bare := _span()
	bare.erase("to")
	check(Commands._decoration(bare) == null, "a span without its far end is refused")
	check(Commands._decoration(_span().merged({"drop": Vector2(DecorationLayout.POLE + 0.5, 0)}, true)) == null, "no pole taller than %.1f m" % DecorationLayout.POLE)
	var ground := _span("Lantern").merged({"mount": "ground"}, true)
	check(Commands._decoration(ground) == null, "a decoration on the ground carries no far end")
	ground.erase("to")
	ground.erase("drop")
	check(Commands._decoration(ground) != null, "a lantern stands on the ground")


func _runs() -> void:
	check(WallLayout.flag_runs([1.0, 3.5, 6.0], 10.0, false) == [Vector2(1.0, 3.5), Vector2(3.5, 6.0)], "three flags close along a wall join into two runs")
	check(WallLayout.flag_runs([6.0, 1.0], 10.0, false).is_empty(), "two far apart stay apart")
	check(WallLayout.flag_runs([1.0, 10.0], 12.0, true) == [Vector2(10.0, 1.0)], "on a loop they join across its seam, the shorter way")
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(10, 0, 0)]
	w.height = 2.4
	w.top = WallLayout.Top.CAP
	w.seed = 3
	w.flags = [1.0, 3.5, 6.0]
	w.build(Terrain.flat)
	var ropes := w.stones.filter(func(p: Dictionary) -> bool: return p.kind == "rope")
	var pennants := w.cloths.size() - 3
	check(ropes.size() == 8 and pennants == 2 * floori(2.5 / WallLayout.FLAG_RUN_EVERY), "each run a rope between the poles hung with pennants: %d ropes, %d pennants" % [ropes.size(), pennants])
	var pole: Dictionary = w.stones.filter(func(p: Dictionary) -> bool: return p.kind == "pole")[0]
	var top: float = pole.xform.origin.y - WallLayout.FLAG_POLE * 0.5 + WallLayout.FLAG_RUN_ROPE
	var middle: Array = ropes.filter(func(p: Dictionary) -> bool: return absf(p.xform.origin.x - 2.25) < 0.5)
	check(ropes.all(func(p: Dictionary) -> bool: return p.xform.origin.y < top and p.xform.origin.y > top - 0.2) and not middle.is_empty(), "the ropes hang from the poles and sag between them: %s under %.2f" % [ropes.map(func(p: Dictionary) -> float: return p.xform.origin.y), top])
	var apart := WallLayout.new()
	apart.points = w.points
	apart.height = 2.4
	apart.top = WallLayout.Top.CAP
	apart.flags = [1.0, 8.0]
	apart.build(Terrain.flat)
	check(apart.stones.all(func(p: Dictionary) -> bool: return p.kind != "rope") and apart.cloths.size() == 2, "flags far apart fly alone")
	var d := wall_data({"points": PackedVector3Array(w.points), "flags": PackedFloat32Array([1.0, 3.5, 6.0])})
	var far := wall_data({"points": PackedVector3Array(w.points), "flags": PackedFloat32Array([1.0, 5.5, 9.9])})
	check(Budget.wall(d).fitting == Budget.wall(far).fitting + 2, "each run is charged as a fitting")


func _vents() -> void:
	var r := RoofLayout.new()
	r.corners = [Vector3(-2, 0, -1.5), Vector3(2, 0, -1.5), Vector3(2, 0, 1.5), Vector3(-2, 0, 1.5)]
	r.chimneys = [Vector2(0.8, 0.0)]
	r.build()
	check(r.vents.size() == 2, "a chimney smokes from both its pots: %d" % r.vents.size())
	var top := r.base + r.chimney_top(r.chimney_spot(r.chimneys[0]))
	check(Array(r.vents).all(func(v: Vector3) -> bool: return v.y > top + 0.3), "the smoke rises from the mouths of the pots")
	r.chimneys = []
	r.build()
	check(r.vents.is_empty(), "a roof without a chimney does not smoke")


## A stroke of the decorations tool from one point on the ground to another hangs a string on poles between them; a
## press and release on one point places a present. The style tool turns a string to flags, the colour tool its
## lanterns' colour, and delete and undo take it away.
func _stroke() -> void:
	var world: World = main.world
	var fit: FittingTool = main.fitting_tool
	var hand: Hand = main.rig.right
	var i := main.rig.hands.find(hand)
	var eye := Vector3(0, 1.7, 8)
	var aim_at := func(x: float, z: float) -> Dictionary:
		var at := world.terrain.ground(x, z)
		return fit.aim(Hand.Tool.DECORATIONS, eye, (at - eye).normalized())
	var a: Dictionary = aim_at.call(-3.0, 2.0)
	var b: Dictionary = aim_at.call(3.0, 2.0)
	check(a.get("mount") == "ground" and b.get("mount") == "ground", "both ends aim at the ground")
	var stroke := fit.string_command(a, b, 7, DecorationLayout.named("Lantern string"), 0)
	check(not stroke.is_empty() and stroke.drop == Vector2.ONE * DecorationLayout.POLE, "a stroke between them hangs a string on two poles")
	check(stroke.at.is_equal_approx(a.point + Vector3.UP * DecorationLayout.POLE), "tied at the top of the first pole")
	check(fit.string_command(a, aim_at.call(-2.5, 2.0), 7, DecorationLayout.named("Lantern string"), 0).is_empty(), "a stroke too short hangs nothing")
	fit._starts[i] = a
	fit._let_go(i, hand, stroke, b)
	var spans: Array = world.state.decorations.keys().filter(func(id: int) -> bool: return world.state.decorations[id].mount == "span")
	check(spans.size() == 1 and fit._starts[i] == null, "letting go of the stroke hangs it")
	if spans.is_empty():
		return
	var id: int = spans[0]
	world.decorations.sync()
	check(world.state.decorations[id].style == DecorationLayout.named("Lantern string") and world.decorations.lit(id), "a string of lanterns by default, its lanterns burning")
	var before: int = world.state.decorations.size()
	a.seed = 5
	fit._starts[i] = a
	fit._let_go(i, hand, {}, a)
	check(world.state.decorations.size() == before + 1 and world.state.decorations.values().back().style == DecorationLayout.PRESENT and world.state.decorations.values().back().seed == 5, "a press let go where it went down places the present its preview showed")
	world.undo()
	fit.light_lanterns()
	fit.lamps.finish()
	var mid: Vector3 = (stroke.at + stroke.to) * 0.5
	check(fit.lamps.at(mid.x, mid.z, 0) > 0.1, "the string's lanterns light the ground under it: %.2f" % fit.lamps.at(mid.x, mid.z, 0))
	var on := world.decorations.world_xform(id) * (world.decorations.placed[id].bounds as AABB).get_center()
	var look := Vector3(mid.x, on.y + 0.5, mid.z + 3.0)
	var styled := main.palette_tool.aim_style(look, (on - look).normalized())
	check(styled.get("id") == id and styled.get("options") == DecorationLayout.standing("span"), "the style tool on a string offers the strings alone: %s" % [styled.get("options")])
	main.palette_tool.open(hand, styled)
	main.palette_tool.wheels[hand].dial.pick = styled.options.find(DecorationLayout.named("Flag string"))
	main.palette_tool.close(hand)
	check(world.state.decorations[id].style == DecorationLayout.named("Flag string") and world.decorations.string_style == DecorationLayout.named("Flag string"), "it turns the string to flags, and strings hung after take flags")
	world.undo()
	world.decorations.sync()
	var coloured := main.palette_tool.aim(look, (on - look).normalized())
	check(coloured.get("element") == Palette.Element.LANTERN and coloured.get("of") == "decorations" and coloured.get("id") == id, "the colour tool on a string of lanterns picks their colour: %s" % coloured)
	main.palette_tool.open(hand, coloured)
	main.palette_tool.wheels[hand].dial.pick = 13
	main.palette_tool.close(hand)
	check(world.state.decorations[id].lantern == 13 and main.tool.paint[Palette.Element.LANTERN] == 13, "its lanterns burn in the swatch let go, as lanterns hung after do")
	world.decorations.sync()
	check(world.decorations.lights.has(Lamps.light_of(13)), "and cast its light")
	main.tool.paint[Palette.Element.LANTERN] = 0
	world.decorations.string_style = DecorationLayout.named("Lantern string")
	check(main.delete_tool.aim(look, (on - look).normalized()).get("decoration") == id, "the delete tool picks the string")
	world.undo()
	world.undo()
	check(not world.state.decorations.has(id), "undo takes the string away")
	world.submit(stroke)
	var kept := world.snapshot()
	world.restore(kept)
	check(world.state.decorations.values().any(func(d: Dictionary) -> bool: return d.get("to") == stroke.to), "save and restore keep a string")
	await play([{"op": "bare"}])


## The colour tool on a wall's lantern colours every lantern on the wall, flame and light; a lantern stands on the
## ground in its own colour.
func _coloured() -> void:
	var world: World = main.world
	var fit: FittingTool = main.fitting_tool
	var hand: Hand = main.rig.right
	await play([{"op": "wall", "points": [[-4, 0], [4, 0]], "seconds": 0.3}, {"op": "fit", "what": "lantern", "index": 0, "s": 2.0, "y": 1.6, "side": 1}, {"op": "fit", "what": "lantern", "index": 0, "s": 6.0, "y": 1.6, "side": 1}])
	var w: Wall = main.tool.walls[0]
	w.lay_now()
	var target := FittingTool.targets(w).filter(func(t: Dictionary) -> bool: return t.what == "lantern")
	check(target.size() == 2, "two lanterns hang on the wall")
	var at: Vector3 = target[0].bounds.get_center()
	var eye := at + Vector3(0, 0.3, 2.5)
	var aimed := main.palette_tool.aim(eye, (at - eye).normalized())
	check(aimed.get("element") == Palette.Element.LANTERN and aimed.get("of") == "walls" and aimed.get("id") == w.id, "the colour tool on a lantern picks its wall's lanterns' colour: %s" % aimed)
	check(aimed.get("count") == Palette.count(Palette.Element.LANTERN), "on a wheel of every colour and brightness")
	main.palette_tool.open(hand, aimed)
	main.palette_tool.wheels[hand].dial.pick = 9
	main.palette_tool.close(hand)
	w.lay_now()
	check(world.state.walls[w.id].paint[Palette.Element.LANTERN] == 9 and w.paint[Palette.Element.LANTERN] == 9, "the wall's lanterns take the swatch")
	check(w._fittings._flames.multimesh.instance_count == 2 and w._fittings.look == 9, "both its flames burn in it")
	fit.light_lanterns()
	check(fit.lamps._lights.count(Lamps.light_of(9)) == 2, "and both cast its light")
	main.tool.paint[Palette.Element.LANTERN] = 0
	world.undo()
	w.lay_now()
	check(w._fittings.look == 0, "undo burns them as before")
	await play([{"op": "fit", "what": "decoration", "x": 0, "z": 5, "style": "Lantern", "lantern": 12}, {"op": "fit", "what": "decoration", "x": 3, "z": 5, "style": "Lamp post", "lantern": 1}])
	var standing: Array = world.state.decorations.values().filter(func(d: Dictionary) -> bool: return d.mount == "ground")
	check(standing.size() == 2 and standing.any(func(d: Dictionary) -> bool: return d.style == DecorationLayout.named("Lantern") and d.lantern == 12), "a lantern stands on the ground in its colour")
	world.decorations.sync()
	fit.light_lanterns()
	fit.lamps.finish()
	var c := Bounce.column(0.0, 5.0)
	var px := fit.lamps._layers[0].get_pixel(c.x, c.y)
	check(px.g > px.r and px.g > px.b, "and lights the ground beside it green: %s" % px)
	await play([{"op": "bare"}])


## A house's chimney smokes, and stops when it is taken away.
func _smoking() -> void:
	await play([{"op": "house", "at": [0, 0], "size": [5, 4], "seconds": 0.3}, {"op": "fit", "what": "chimney", "index": 0, "at": [1.0, 0.0]}])
	var w: Wall = main.tool.walls[0]
	w.lay_now()
	check(w._smoke.visible and w._smoke.multimesh.instance_count == 2 * Smoke.PUFFS, "a chimney's pots smoke: %d puffs" % w._smoke.multimesh.instance_count)
	var vents := w.roof.vents
	check(vents.size() == 2 and Array(vents).all(func(v: Vector3) -> bool: return w._smoke.custom_aabb.has_point(v) and w._smoke.custom_aabb.has_point(v + Vector3.UP * Smoke.RISE)), "drawn from their mouths as high as it rises")
	main.world.undo()
	w.lay_now()
	check(not w._smoke.visible, "taken away, the chimney smokes no more")
	await play([{"op": "bare"}])


func _demo() -> void:
	var steps := Driver.read("res://../demo/lights.json").filter(func(s: Dictionary) -> bool: return s.op != "capture")
	await play(steps.slice(0, steps.find_custom(func(s: Dictionary) -> bool: return s.op == "view")))
	var world: World = main.world
	for w in main.tool.walls:
		w.lay_now()
	var garden: Array = world.state.decorations.values()
	var strings := garden.filter(func(d: Dictionary) -> bool: return d.mount == "span")
	check(strings.any(func(d: Dictionary) -> bool: return d.style == DecorationLayout.named("Lantern string")) and strings.any(func(d: Dictionary) -> bool: return d.style == DecorationLayout.named("Flag string")), "the demo hangs strings of lanterns and of flags")
	check(strings.any(func(d: Dictionary) -> bool: return d.drop == Vector2.ZERO), "one tied between builds")
	var standing := garden.filter(func(d: Dictionary) -> bool: return d.style in [DecorationLayout.named("Lantern"), DecorationLayout.named("Lamp post")])
	var looks := {}
	for d in standing:
		looks[d.lantern] = true
	check(looks.has(0) and looks.has(1) and looks.has(2), "lanterns standing on the ground at each brightness")
	check(looks.size() >= 5, "and in colours: %s" % [looks.keys()])
	var wall: Wall = main.tool.walls[0]
	check(wall.layout.flags.size() == 3 and wall.layout.stones.any(func(p: Dictionary) -> bool: return p.kind == "rope"), "its flags along the wall join into runs")
	check(wall.paint[Palette.Element.LANTERN] != 0, "the wall's lanterns burn in a colour")
	var house: Wall = main.tool.walls[1]
	check(house.roof.chimneys.size() == 2 and house._smoke.multimesh.instance_count == 4 * Smoke.PUFFS, "the house's two chimneys smoke")
	var sun: Dictionary = steps.filter(func(s: Dictionary) -> bool: return s.op == "sun")[0]
	check(sun.time > 0.75 and sun.time < 0.8, "it renders them at dusk: %.3f" % sun.time)
	await play([{"op": "bare"}])


## The lights/* phases: three houses, with chimneys along their ridges, lanterns round them and strings between them and
## in rows across the meadow, until the frame budget is full.
func _stress() -> void:
	var steps := Driver.read("res://../demo/stress.json")
	var aerial := steps.find_custom(func(s: Dictionary) -> bool: return s.get("name", "") == "lights/aerial")
	check(aerial >= 0 and steps.any(func(s: Dictionary) -> bool: return s.get("name", "") == "lights/ground"), "the stress scene has lights/aerial and lights/ground phases")
	if aerial < 0:
		return
	var wiped := aerial
	while steps[wiped].op != "bare":
		wiped -= 1
	var lit := steps.slice(wiped, aerial).filter(func(s: Dictionary) -> bool: return s.op in ["bare", "house", "lights", "sun"])
	check(lit.any(func(s: Dictionary) -> bool: return s.op == "sun" and s.time > 0.75 and s.time < 0.8), "at dusk")
	await play([steps[0]] + lit)
	var world: World = main.world
	var strings: Array = world.state.decorations.values().filter(func(d: Dictionary) -> bool: return d.mount == "span")
	var lanterns := 0
	var chimneys := 0
	for w: Wall in main.tool.walls:
		lanterns += w.layout.lanterns.size()
		chimneys += w.roof.chimneys.size() if w.roof != null else 0
	check(strings.size() >= 4 and lanterns >= 20 and chimneys >= 6, "smoking chimneys, lanterns and strings: %d chimneys, %d lanterns, %d strings" % [chimneys, lanterns, strings.size()])
	var more := main.fitting_tool.string_command({"what": "decoration", "mount": "ground", "point": world.terrain.ground(-6, 20)}, {"what": "decoration", "mount": "ground", "point": world.terrain.ground(0, 20)}, 99, DecorationLayout.named("Lantern string"), 0)
	check(not Budget.fits(world.units, world.change_of(more)), "until no other string fits the budget: fill %.3f" % world.fill())
