extends SceneTree

## A build style's miniature never waits on its build: the wheel gets it at once and the worker fills it.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _run() -> void:
	root.add_child(Warmup.new([]))
	var roof := ToolModels.style(PaletteTool.Restyle.ROOF, WallTool.RoofStyle.THATCHED, false)
	root.add_child(roof)
	check(roof.get_child_count() == 0, "the first roof miniature comes back before its build")
	# Frames run unthrottled here, faster than the worker builds; the limit only turns a deadlock into a failure.
	var until := Time.get_ticks_msec() + 60000
	while roof.get_child_count() == 0 and Time.get_ticks_msec() < until:
		await process_frame
	var made := ToolModels._style(PaletteTool.Restyle.ROOF, WallTool.RoofStyle.THATCHED, false, false, false, false)
	check(roof.get_child_count() > 0 and roof.get_child_count() == made.get_child_count(), "the worker fills it with the pieces a build on the frame lays")
	made.free()
	var again := ToolModels.style(PaletteTool.Restyle.ROOF, WallTool.RoofStyle.THATCHED, false)
	check(again.get_child_count() == roof.get_child_count(), "once built, it comes back whole")
	again.free()
	var gone := ToolModels.style(PaletteTool.Restyle.TOP, 0, true)
	gone.free()
	ToolModels.prepare_styles()
	for i in 10:
		await process_frame
	ToolModels.stop_styles()
	roof.queue_free()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
