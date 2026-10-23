extends SceneTree

## Headless checks that the style tool can aim at a roofed house that undoing a wipe brought back, before and after
## its stones are laid again: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_roof_restore.gd

var failures := 0
var main: Node
var world: World


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	world = main.world
	var d := Driver.new(main, [
		{"op": "place", "x": 0, "z": 8},
		{"op": "pick", "hand": "right", "tool": "house"},
		{"op": "house", "at": [-4, -2], "size": [5, 4], "seconds": 0.5},
	])
	main.add_child(d)
	await d.finished
	d.queue_free()
	world.submit({"op": "wipe"})
	world.submit({"op": "undo"})
	var house: Wall = main.tool.walls[0]
	_check(house.laying() and house.roof.kind == RoofLayout.Kind.GABLE, "the house comes back roofed, its stones still being laid")
	var picker: PaletteTool = main.palette_tool
	var from := Vector3(-4, 15, 3)
	var dir := (Vector3(-4, 3, -2) - from).normalized()
	_check(FittingTool.targets(house).is_empty(), "nothing on it can be aimed at before its stones are laid")
	picker.aim_style(from, dir)
	house.lay_now()
	_check(picker.aim_style(from, dir).get("restyle") == PaletteTool.Restyle.ROOF, "once laid, the style tool aims at its roof")
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
