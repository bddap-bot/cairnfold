extends "res://../tests/support/suite.gd"

## A house let go after a stretch or a carry lays again; until the glade draws the new lay, the house must still show it
## whole. The glade is held still here, as a busy frame's flush budget holds it on a headset.

static func _luma(image: Image, box: Rect2) -> float:
	var size := Vector2(image.get_size())
	var from := Vector2i((box.position * size).round())
	var to := Vector2i((box.end * size).round())
	var sum := 0.0
	for y in range(from.y, to.y):
		for x in range(from.x, to.x):
			sum += image.get_pixel(x, y).get_luminance()
	return sum / ((to.x - from.x) * (to.y - from.y))


func _run() -> void:
	root.mesh_lod_threshold = 0.0
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await play([{"op": "budget", "bounded": false}, {"op": "place", "x": 0, "z": 14}, {"op": "house", "at": [0, 0], "size": [5, 5], "seed": 1, "seconds": 0.1}])
	await laid()
	await light_settled(0.4)
	main.look.set_process(true)
	await play(["wildlife", "shy", "grass", "flowers", "ivy"].map(func(n: String) -> Dictionary: return {"op": "layer", "name": n, "mode": "off"}))
	await play([{"op": "view", "eye": [0, 2.0, 15], "at": [0, 1.8, 0], "ground": true}])
	var wall := Rect2(0.4, 0.5, 0.2, 0.15)
	var before := await drawn()
	var stretch := func(start: Dictionary, k: float) -> Dictionary:
		return start.merged({"size": start.size.lerp(Vector2(11, 5), k)}, true)
	var stretched := await _let_go("stretched", stretch, wall, before)
	var carry := func(start: Dictionary, k: float) -> Dictionary:
		return start.merged({"center": start.center + Vector3(-1.5, 0, -1) * k, "yaw": start.yaw + 0.3 * k}, true)
	await _let_go("carried", carry, wall, stretched)
	var move := func(start: Dictionary, k: float) -> Dictionary:
		return start.merged({"center": start.center + Vector3(-1.5, 0, -1) * k}, true)
	await _taken_again(move)
	finish()


## Holds the house, moves it to `to(start, k)` over the hold, lets go, and compares the house as the glade waits with the
## house once the glade draws it, which it returns.
func _let_go(what: String, to: Callable, wall: Rect2, before: Image) -> Image:
	var tool: WallTool = main.tool
	tool.take_build(tool.walls[0])
	var start: Dictionary = tool.held_at.duplicate()
	for i in 30:
		tool.stand_build(to.call(start, (i + 1) / 30.0))
		await process_frame
	var held := await drawn()
	var glade: Masonry = tool.masonry
	glade.process_mode = Node.PROCESS_MODE_DISABLED
	tool.end_build()
	await laid()
	await until(func() -> bool: return not tool._settling.has(tool.walls[0].id), "the %s house settles" % what)
	await frames(2)
	var waiting := await drawn()
	glade.process_mode = Node.PROCESS_MODE_INHERIT
	await until(func() -> bool: return glade.drawn(tool.walls[0].get_instance_id()), "the glade draws the %s house" % what)
	await frames(2)
	var settled := await drawn()
	var apart := pixels_apart(waiting, settled, 0.25)
	var share := float(apart) / (settled.get_width() * settled.get_height())
	check(share < 0.01, "the %s house shows its new lay while the glade waits: %.3f of the view apart" % [what, share])
	for shown: Array in [[held, _luma(before, wall), "before the hold"], [waiting, _luma(settled, wall), "once drawn"]]:
		var l := _luma(shown[0], wall)
		check(absf(l - shown[1]) < 0.3 * shown[1], "the %s house's wall keeps its light: %.3f against %.3f %s" % [what, l, shown[1], shown[2]])
	return settled


## Let go and taken again before the lay the let-go started lands: carried on, the house keeps its stones on it.
func _taken_again(to: Callable) -> void:
	var tool: WallTool = main.tool
	var w: Wall = tool.walls[0]
	tool.take_build(w)
	tool.stand_build(to.call(tool.held_at.duplicate(), 1.0))
	tool.end_build()
	await until(func() -> bool: return w._build_task >= 0, "the let-go house lays")
	tool.take_build(w)
	var start: Dictionary = tool.held_at.duplicate()
	for i in 30:
		tool.stand_build(to.call(start, (i + 1) / 30.0))
		await process_frame
	await until(func() -> bool: return not w.laying(), "the lay lands in hand")
	for i in 10:
		tool.stand_build(to.call(start, 1.0))
		await process_frame
	var held := await drawn()
	tool.end_build()
	await laid()
	await until(func() -> bool: return not tool._settling.has(w.id) and tool.masonry.drawn(w.get_instance_id()), "the house settles")
	await frames(2)
	var settled := await drawn()
	var share := float(pixels_apart(held, settled, 0.25)) / (settled.get_width() * settled.get_height())
	check(share < 0.01, "a house taken again as it lays carries its stones: %.3f of the view apart from where it settles" % share)
