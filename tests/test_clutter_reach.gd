extends "res://../tests/support/booted.gd"


func _run() -> void:
	main.world.limit = INF
	await play([{"op": "pave", "points": [[-14, 30], [0, 30], [14, 30]], "radius": PathLayout.HALF_WIDTH.y, "seconds": 0.3}])
	await frames(3)
	var world: World = main.world
	var id: int = world.state.paths.keys()[0]
	var path: Dictionary = world.state.paths[id]
	var lined: PackedVector4Array = path.clutter
	check(not lined.is_empty() and Array(path.half_widths).max() >= PathLayout.HALF_WIDTH.y - 0.01, "the widest path gathers things beside it: %d at %.2f m" % [lined.size(), Array(path.half_widths).max()])
	if lined.is_empty():
		finish()
		return
	var side := signf(lined[0].y)
	await play([{"op": "clutter", "path": 0, "piece": 0, "move": [0.0, 0.0, 20.0 * side], "seconds": 0.3}])
	await frames(3)
	var carried: PackedVector4Array = world.state.paths[id].clutter
	check(carried.size() == lined.size() and absf(carried[0].y) > absf(lined[0].y) + 1.0, "a hand carries a piece out from the widest path as far as it goes, and the garden keeps it there: %s to %s" % [lined[0], carried[0]])
	finish()
