extends "res://../tests/support/suite.gd"

## A build style's miniature never waits on its build: the wheel gets it at once and the worker fills it.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(Warmup.new([]))
	var roof := ToolModels.style(PaletteTool.Restyle.ROOF, WallTool.RoofStyle.THATCHED, WallLayout.Finish.BARE)
	root.add_child(roof)
	check(roof.get_child_count() == 0, "the first roof miniature comes back before its build")
	# Frames run unthrottled here, faster than the worker builds; the limit only turns a deadlock into a failure.
	var deadline := Time.get_ticks_msec() + 60000
	while roof.get_child_count() == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	var made := ToolModels._style(PaletteTool.Restyle.ROOF, WallTool.RoofStyle.THATCHED, WallLayout.Finish.BARE, false, false, false, false)
	check(roof.get_child_count() > 0 and roof.get_child_count() == made.get_child_count(), "the worker fills it with the pieces a build on the frame lays")
	made.free()
	var again := ToolModels.style(PaletteTool.Restyle.ROOF, WallTool.RoofStyle.THATCHED, WallLayout.Finish.BARE)
	check(again.get_child_count() == roof.get_child_count(), "once built, it comes back whole")
	again.free()
	var gone := ToolModels.style(PaletteTool.Restyle.TOP, 0, WallLayout.Finish.PLASTER)
	gone.free()
	ToolModels.prepare_styles()
	await frames(10)
	ToolModels.stop_styles()
	roof.queue_free()
	finish()
