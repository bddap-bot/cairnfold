extends "res://../tests/support/suite.gd"

var dir := ""
var now := 1_800_000_000


func _run() -> void:
	_backups_keep_each_age_through_hours_of_building()
	_backups_after_a_pause_give_the_last_garden()
	dir = OS.get_user_data_dir().path_join("cairnfold-shelf-%d" % OS.get_process_id())
	boot_main({"garden": dir})
	await process_frame
	main.world.limit = INF
	main.world.shelf.clock = func() -> int: return now
	await process_frame
	_starting_builds_rebuild_whole()
	_dioramas_show_the_builds()
	await _picking_gardens_and_backups()
	_a_full_shelf_offers_no_new_garden()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	finish()


## An edit a minute for four hours: each age is offered a backup at most a backup's spacing past it, from a handful of files.
func _backups_keep_each_age_through_hours_of_building() -> void:
	var times := []
	var most := 0
	var late := {}
	for step in range(0, 4 * 3600, 60):
		var t := now + step
		if times.is_empty() or t - times.back() >= Shelf.EVERY:
			times.append(t)
			times = Shelf.kept(times, t)
		most = maxi(most, times.size())
		var offered := Shelf.offer(times, t)
		for minutes in Shelf.BACKUPS:
			var window := Shelf.EVERY if minutes * 60 < Shelf.SPAN else Shelf.SPAN + Shelf.EVERY
			if step < minutes * 60 + window:
				continue
			var age: int = t - offered.get(minutes, -INF)
			if age < minutes * 60 or age > minutes * 60 + window:
				late[minutes] = [step, age]
	check(late.is_empty(), "through four hours of building each age is offered a backup that old or a little older: %s" % late)
	check(most <= 8, "at most eight backups are kept at once, not one per five minutes: %d" % most)


func _backups_after_a_pause_give_the_last_garden() -> void:
	var times := []
	for step in range(0, 1800, Shelf.EVERY):
		times.append(now + step)
		times = Shelf.kept(times, now + step)
	var later := now + 1800 + 3 * 3600
	var offered := Shelf.offer(Shelf.kept(times, later), later)
	check(offered.get(5) == times.back(), "after a long pause, five minutes back is the garden as it was last left: %s" % offered)
	check(offered.values().size() == Shelf.kept(times, later).size() and offered.values().size() == 2, "the session's first backup stays for the longer ages, and none is offered twice: %s" % offered)


func _starting_builds_rebuild_whole() -> void:
	var world := main.world
	for name: String in Shelf.STARTS:
		var snap := Shelf.start(name, world.terrain, world.format())
		check(world.restore_whole(snap), "starting build %s rebuilds whole" % name)
		check(world.state.walls.size() >= 1 and _trees() >= 2, "starting build %s stands houses and trees: %d walls, %d trees" % [name, world.state.walls.size(), _trees()])
	world.restore({"format": world.format(), "seq": 0, "cmds": []})


func _dioramas_show_the_builds() -> void:
	var world := main.world
	var lay := Diorama.layout(Shelf.start("hamlet", world.terrain, world.format()).cmds)
	var count := {}
	for p: Array in lay.parts:
		count[p[0]] = count.get(p[0], 0) + 1
	check(count.get(Diorama.Part.BLOCK) == 3 and count.get(Diorama.Part.PRISM) == 3, "the hamlet's diorama has its three houses under three roofs: %s" % count)
	check(count.get(Diorama.Part.CONE, 0) >= 2 and count.get(Diorama.Part.BALL, 0) >= 1, "and its trees and bush: %s" % count)
	var built := Diorama.build(lay, Color.GRAY)
	var drawn: Array = built.find_children("*", "MultiMeshInstance3D", false, false)
	check(drawn.size() == count.size() + 1, "a diorama draws its ground and one batch a kind of part: %d" % drawn.size())
	var box := AABB()
	for mi: MultiMeshInstance3D in drawn:
		for i in mi.multimesh.instance_count:
			box = box.merge(AABB(mi.multimesh.get_instance_transform(i).origin, Vector3.ZERO))
	check(box.size.x <= Diorama.RADIUS * 2.2 and box.size.z <= Diorama.RADIUS * 2.2, "the garden fits its diorama: %s" % box)
	built.free()
	var empty := Diorama.layout([])
	check(empty.parts.is_empty(), "a blank garden's diorama is only meadow")
	var wall := wall_data({"points": PackedVector3Array([Vector3(-40, 0, 0), Vector3(40, 0, 0)]), "height": 2.0})
	var wide := Diorama.layout([{"op": "wall", "walls": [wall]}])
	check(wide.radius > 40.0, "a long wall's diorama is wide enough for it: %.1f m" % wide.radius)


func _picking_gardens_and_backups() -> void:
	var world := main.world
	var shelf := world.shelf
	var people: SessionWheel = main.rig.right.people
	check(shelf.dir == dir and shelf.current == 1 and world.save_path == shelf.path(1), "a played garden is the shelf's first")
	main.flora_tool.place("tree", world.terrain.ground(3, -4))
	await _kept()
	check(FileAccess.file_exists(shelf.path(1)) and shelf.backups.get(1, []).size() == 1, "its first change is kept and backed up")
	now += Shelf.EVERY + 60
	main.flora_tool.place("tree", world.terrain.ground(-3, -4))
	await _kept()
	check(shelf.backups[1].size() == 2, "a change five minutes on is backed up again")
	now += Shelf.EVERY
	var choices := people.choices("gardens")
	check(choices.slice(0, 3) == ["garden:1", "backup:5", "backup:10"], "the shelf opens on this garden, then its backups 5 and 10 minutes back: %s" % [choices])
	check(choices.slice(-4) == ["new"] + Shelf.STARTS.map(func(s: String) -> String: return "start:" + s), "then a new garden and the starting builds: %s" % [choices])
	people.activate("backup:10")
	await _opened()
	check(_trees() == 1, "going back ten minutes takes away the tree planted since: %d trees" % _trees())
	var newest: Variant = Shelf.read(shelf.backup_path(1, shelf.backups[1].back()))
	check(shelf.backups[1].size() == 3 and newest is Dictionary and newest.cmds.filter(func(c: Dictionary) -> bool: return c.op == "plant").size() == 2, "and the garden it was is backed up first, so it can be had again")
	people.activate("backup:5")
	await _opened()
	check(_trees() == 2, "which five minutes back now holds: %d trees" % _trees())
	people.activate("new")
	await _opened()
	check(shelf.current == 2 and _trees() == 0 and world.state.walls.is_empty(), "a new garden is blank")
	people.activate("start:hamlet")
	await _opened()
	check(shelf.current == 3 and world.state.walls.size() == 3, "a starting build opens as a garden of its own: %d walls" % world.state.walls.size())
	var trees := _trees()
	main.flora_tool.place("tree", world.terrain.ground(-12, 4))
	await _kept()
	check(_trees() == trees + 1, "and takes what is built on it: %d trees" % _trees())
	var again := Shelf.open(dir)
	check(again.gardens == [1, 2, 3] and again.current == 3, "the shelf reads back as it was kept, on the garden open: %s, %d" % [again.gardens, again.current])
	people.activate("garden:2")
	await _opened()
	main.flora_tool.place("tree", world.terrain.ground(5, 5))
	await until(func() -> bool: return main.world.answered(), "the change is in the garden")
	people.activate("garden:1")
	await _opened()
	check(shelf.current == 1 and _trees() == 2 and world.state.walls.is_empty(), "the first garden is picked back as it was left")
	var left: Variant = Shelf.read(shelf.path(2))
	check(left is Dictionary and left.cmds.size() == 1, "a change made just before leaving a garden is kept in it, not in the next")
	var broken: Dictionary = Shelf.read(shelf.path(3))
	broken.cmds.append({"op": "plant", "kind": "no such plant", "seed": 1, "seq": 1, "by": 1})
	Main.replace_file(ProjectSettings.globalize_path(shelf.path(3)), var_to_bytes(broken))
	people.activate("garden:3")
	await _opened()
	check(FileAccess.file_exists(shelf.path(3) + ".bad") and shelf.current == 3, "a garden that opens only in part has its file moved aside before it is kept again")
	people.activate("garden:1")
	await _opened()
	now += 3600
	check(people.choices("gardens").has("backup:60"), "an hour on, the shelf offers this garden an hour back: %s" % [people.choices("gardens")])
	var icon := people.icon("backup:5")
	check(icon != null and icon.find_children("*", "MultiMeshInstance3D", false, false).size() >= 2, "a backup shows as a diorama of its garden")
	icon.free()


func _a_full_shelf_offers_no_new_garden() -> void:
	var shelf := main.world.shelf
	var people: SessionWheel = main.rig.right.people
	while not shelf.full():
		shelf.gardens.append(shelf.fresh())
	var choices := people.choices("gardens")
	check(not "new" in choices and not choices.any(func(c: String) -> bool: return c.begins_with("start:")), "a full shelf offers no new garden: %s" % [choices])
	check(choices.size() == Shelf.MOST + shelf.offered().size(), "but every garden on it: %d" % choices.size())


func _kept() -> void:
	await until(func() -> bool: return main.world.answered(), "the change is in the garden")
	await flushed()


func _opened() -> void:
	await until(func() -> bool: return main.world.idle(), "the garden opens")
	await flushed()


func _trees() -> int:
	return main.world.state.groups.values().filter(func(g: Dictionary) -> bool: return g.kind == "tree").size()
