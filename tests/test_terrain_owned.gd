extends "res://../tests/support/suite.gd"

## Headless checks that the ground belongs to its World: a stroke's live hump is this player's preview, which no
## default query sees and which counts no change to the garden, and two Worlds in one process keep their own heights
## and marks: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_terrain_owned.gd


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await _a_command_mid_stroke_stands_on_the_garden()
	_two_worlds_keep_their_own_ground()
	finish()


func _a_command_mid_stroke_stands_on_the_garden() -> void:
	var world := main.world
	var terrain := world.terrain
	world.restore({"seq": 0, "cmds": []})
	var garden := terrain.height_at(3, -2)
	var revision := terrain.revision
	var shown := terrain.shown_revision
	main.ground_grab.begin(main.rig.right, Vector3(3, garden, -2), 3.0)
	main.ground_grab.pull(main.rig.right, 2.0)
	check(is_equal_approx(terrain.height_at(3, -2), garden), "a height query reads the garden, not the live hump")
	check(is_equal_approx(terrain.shown_at(3, -2), garden + 2.0), "the shown ground carries the hump (%s)" % terrain.shown_at(3, -2))
	check(terrain.revision == revision and terrain.shown_revision > shown, "a hump moves the shown ground, not the garden's")
	world.submit({"op": "boulder", "at": Vector3(3, garden, -2), "turn": Quaternion.IDENTITY, "sink": 0.0, "seed": 17, "scale": 1.0, "paint": Palette.plain(), "style": 0})
	await process_frame
	world.flush()
	var b: Boulders.Boulder = main.boulders.boulders.values()[0]
	check(is_equal_approx(b.ground.y, garden), "a boulder command applied mid-stroke seats on the garden, as every peer seats it (%s)" % b.ground.y)
	main.ground_grab.drop()
	world.restore({"seq": 0, "cmds": []})


func _two_worlds_keep_their_own_ground() -> void:
	var a := World.new()
	var b := World.new()
	var cells := Rect2i(10, 10, 2, 2)
	a.terrain.write(cells, PackedFloat32Array([5.0, 5.0, 5.0, 5.0]))
	check(a.terrain.read(cells) == PackedFloat32Array([5.0, 5.0, 5.0, 5.0]), "a World's write lands in its ground")
	check(b.terrain.read(cells) == _base(cells), "another World's ground is untouched")
	var mark := Ground.Stroke.new(Ground.Kind.STONE)
	mark.stamps.append(Vector4(0, 0, 2, 0.5))
	a.marks.lay(mark, 1)
	a.marks.settle()
	check(a.marks.stone(0, 0) > 0.5 and b.marks.stone(0, 0) == 0.0, "a mark laid in one World is not in the other")
	a.free()
	b.free()


static func _base(cells: Rect2i) -> PackedFloat32Array:
	var all := Terrain.base_heights()
	var out := PackedFloat32Array()
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			out.append(all[j * Terrain.VERTS + i])
	return out
