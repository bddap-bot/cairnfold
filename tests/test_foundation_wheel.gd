extends "res://../tests/support/booted.gd"

const BELOW_FOOT := WallLayout.COURSE * 0.5
const AIM_FROM := Vector2(2.0, 0.4)


func _run() -> void:
	main.world.limit = INF
	await _a_fence_over_a_pond_offers_what_it_takes()
	await _every_wall_offers_what_it_takes()
	await _an_upper_storey_on_pillars_turns_to_stone()
	finish()


func _admitted(w: Wall) -> Array:
	var world := main.world
	return WallLayout.Foundation.values().filter(func(f: int) -> bool: return not Commands.clean({"op": "reshape", "of": "walls", "id": w.id, "data": {"foundation": f}}, world.state, false, world.terrain).is_empty())


func _offers_what_it_takes(w: Wall, what: String) -> void:
	var offered: Array = main.palette_tool.style_target(PaletteTool.Restyle.FOUNDATION, w, w.layout.point_at(0.0)).options
	check(offered == _admitted(w), "%s's foundation wheel offers exactly what the garden takes: %s for %s" % [what, offered, _admitted(w)])


func _a_fence_over_a_pond_offers_what_it_takes() -> void:
	await play([{"op": "dig", "x": 20, "z": 20, "seconds": 2.5}])
	await until(main.world.idle, "the pond fills")
	await play([{"op": "fence", "points": [[14, 20], [20, 20], [26, 20]], "seconds": 0.3}])
	await laid()
	var fence: Wall = main.tool.walls[-1]
	check(Array(fence.layout.depths).max() > BELOW_FOOT * 2.0, "the fence crosses the pond above its bed")
	var picker: PaletteTool = main.palette_tool
	var aimed := {}
	var s := WallLayout.SAMPLE
	while s < fence.layout.length() - WallLayout.SAMPLE and aimed.is_empty():
		var f := fence.layout.frame_at(s)
		var out: Vector3 = f.tangent.cross(Vector3.UP)
		for side in [1.0, -1.0]:
			var at: Vector3 = f.point + Vector3.DOWN * BELOW_FOOT
			var from: Vector3 = at + out * side * AIM_FROM.x + Vector3.UP * AIM_FROM.y
			var t := picker.aim_style(from, (at - from).normalized())
			if t.get("restyle") == PaletteTool.Restyle.FOUNDATION:
				aimed = t
		s += WallLayout.SAMPLE
	check(not aimed.is_empty(), "a style hand aimed under the water at a fence's foot opens its foundation wheel")
	if aimed.is_empty():
		return
	var refused := []
	for i in aimed.count:
		turn_picker(aimed, i)
		await frames(3)
		if main.world.state.walls[fence.id].foundation != aimed.options[i]:
			refused.append(WallLayout.Foundation.keys()[aimed.options[i]])
	check(refused.is_empty(), "every foundation the wheel offers a fence is one the fence takes: refused %s of %s" % [refused, aimed.options])
	_offers_what_it_takes(fence, "a fence")
	main.world.submit({"op": "wipe"})
	await frames(4)


func _every_wall_offers_what_it_takes() -> void:
	await play([
		{"op": "wall", "points": [[-8, -10], [-3, -10], [2, -10]], "seconds": 0.3},
		{"op": "house", "at": [-6.0, 0.0], "size": [6.0, 5.0], "seconds": 0.2},
	])
	await laid()
	_offers_what_it_takes(main.tool.walls[0], "an open wall")
	_offers_what_it_takes(main.tool.walls[1], "a house")
	main.world.submit({"op": "wipe"})
	await frames(4)


func _an_upper_storey_on_pillars_turns_to_stone() -> void:
	await play([
		{"op": "house", "at": [-6.0, 0.0], "size": [6.0, 5.0], "seconds": 0.2},
		{"op": "roof", "index": 0, "pitch": 0.0, "deck": "wood"},
		{"op": "house", "at": [-6.0, 0.0], "size": [3.4, 3.0], "seconds": 0.2, "on": true},
	])
	await laid()
	var upper: Wall = main.tool.walls[-1]
	var d: Dictionary = main.world.state.walls[upper.id]
	check(not d.on.is_empty() and d.foundation == WallLayout.Foundation.PILLARS, "a storey on a deck stands on it with the tool's pillars: on %s, %s" % [d.on, WallLayout.Foundation.keys()[d.foundation]])
	_offers_what_it_takes(upper, "an upper storey")
	var target := main.palette_tool.style_target(PaletteTool.Restyle.FOUNDATION, upper, upper.layout.point_at(0.0))
	turn_picker(target, target.options.find(WallLayout.Foundation.STONE) - target.options.find(WallLayout.Foundation.PILLARS))
	await frames(3)
	check(main.world.state.walls[upper.id].foundation == WallLayout.Foundation.STONE, "the storey's wheel turns its pillars to stone: %s" % WallLayout.Foundation.keys()[main.world.state.walls[upper.id].foundation])
