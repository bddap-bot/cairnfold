extends "res://../tests/support/booted.gd"


func _run() -> void:
	main.world.limit = INF
	await play([{"op": "dig", "x": 20, "z": 20, "seconds": 2.5}])
	await until(main.world.idle, "the pond fills")
	await play([{"op": "fence", "points": [[14, 20], [20, 20], [26, 20]], "seconds": 0.3}])
	await laid()
	var fence: Wall = main.tool.walls[-1]
	check(Array(fence.layout.depths).max() > 0.3, "the fence crosses the pond above its bed")
	var picker: PaletteTool = main.palette_tool
	var aimed := {}
	for k in 48:
		var f := fence.layout.frame_at(0.5 + k * 0.25)
		var out: Vector3 = f.tangent.cross(Vector3.UP)
		for side in [1.0, -1.0]:
			var at: Vector3 = f.point + Vector3.UP * -0.15
			var from: Vector3 = at + out * side * 2.0 + Vector3.UP * 0.4
			var t := picker.aim_style(from, (at - from).normalized())
			if t.get("restyle") == PaletteTool.Restyle.FOUNDATION:
				aimed = t
	check(not aimed.is_empty(), "a style hand aimed under the water at a fence's foot opens its foundation wheel")
	if aimed.is_empty():
		finish()
		return
	var refused := []
	for i in aimed.count:
		turn_picker(aimed, i)
		await frames(3)
		if main.world.state.walls[fence.id].foundation != aimed.options[i]:
			refused.append(WallLayout.Foundation.keys()[aimed.options[i]])
	check(refused.is_empty(), "every foundation the wheel offers a fence is one the fence takes: refused %s of %s" % [refused, aimed.options])
	finish()
