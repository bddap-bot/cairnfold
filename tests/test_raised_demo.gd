extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	boot_main()
	await process_frame
	await _demo()
	await _stress_ring()
	finish()


func _stilted(w: Wall) -> bool:
	return w.layout.stones.any(func(st: Dictionary) -> bool: return st.kind in ["post", "pillar"] and st.y < 0.0)


## `demo/raised.json` stands long and round houses on pillars and posts, and the style tool turns a plinth to pillars.
func _demo() -> void:
	for step: Dictionary in Driver.read("res://../demo/raised.json"):
		if step.op in ["quit"]:
			continue
		step.erase("capture")
		if step.op == "capture":
			continue
		await play([step])
	var walls: Array[Wall] = main.tool.walls
	for w in walls:
		w.lay_now()
	var kinds := {}
	for w in walls:
		if _stilted(w):
			kinds["%s %s" % ["round" if w.layout.corners().is_empty() else "long", WallLayout.Foundation.keys()[w.layout.foundation]]] = true
	check(kinds.size() == 4, "the demo raises long and round houses on pillars and on posts: %s" % kinds.keys())
	check(walls[-1].layout.foundation == WallLayout.Foundation.PILLARS and _stilted(walls[-1]), "the style tool turns the last house's plinth to pillars")
	await play([{"op": "clear"}])


## The stress scene's `raised/*` phases look over a ring of raised houses, long and round, every one on stilts.
func _stress_ring() -> void:
	var steps := Driver.read("res://../demo/stress.json")
	var first := steps.find_custom(func(s: Dictionary) -> bool: return s.get("name", "") == "raised/aerial")
	check(first >= 0 and steps.any(func(s: Dictionary) -> bool: return s.get("name", "") == "raised/ground"), "the stress scene has raised/aerial and raised/ground phases")
	if first < 0:
		return
	var village := village_before(steps, first)
	await play([steps[0], steps[village]])
	var walls: Array[Wall] = main.tool.walls
	var round := 0
	var long := 0
	for w in walls:
		w.lay_now()
		check(w.layout.rise > 0.0 and _stilted(w), "house %d stands raised on stilts" % w.id)
		check(Vector2(w.layout.points[0].x, w.layout.points[0].z).length() > 7.0, "house %d stands in the ring, not its middle" % w.id)
		if w.layout.corners().is_empty():
			round += 1
		else:
			long += 1
	check(round >= 4 and long >= 4, "the ring holds round houses and long ones: %d and %d" % [round, long])
	await play([{"op": "clear"}])
