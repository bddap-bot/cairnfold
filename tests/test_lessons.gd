extends SceneTree

## Each picture-book page's script (Lessons.PAGES), played through the real hands into a garden, does what its
## picture shows, and every action it presses is still a control: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_lessons.gd

## The left hand holding the book open to read, in head space.
var held_book := Lessons.frame({"at": Vector3(-0.06, -0.3, -0.34), "aim": Vector3(0.15, -0.55, -1.0).normalized(), "roll": 0.0})

var failures := 0
var main: Node
var trackers: Array[XRControllerTracker] = []
var effects := {}


func _initialize() -> void:
	# These grips point at what they take: the reach they check is the pointing grab, until a playtest keeps one.
	Reach.mode = Reach.Mode.AIM
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# Fixture geometry exceeds capacity; test_budget covers the shared limit.
	main.world.bounded = false
	await _frames(3)
	var rig: Rig = main.rig
	_check(rig.left.tool == Hand.Tool.BOOK and main.book.at == 0, "the player starts with the book shut in the left hand")
	for hand in rig.hands:
		var tracker := XRControllerTracker.new()
		tracker.name = hand.tracker
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
	_every_press_is_a_control()
	for i in Lessons.PAGES.size():
		var page: Dictionary = Lessons.PAGES[i]
		await _fresh()
		if page.has("setup"):
			await _play(page.setup)
		var before := _read(page)
		await _replay(page)
		await _frames(30)
		call("_check_" + page.effect, page, before)
	await _shut_book_turns_nothing()
	await _sweeps_turn_one_leaf_each_way()
	for t in trackers:
		XRServer.remove_tracker(t)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


## Every action a page presses is in the controls table for that hand, every tool it names is a tool, and every
## effect has a check here: a control renamed or moved fails until its page is redrawn.
func _every_press_is_a_control() -> void:
	for page in Lessons.PAGES:
		for p in page.press:
			var ok: bool = Controls.ACTIONS.has(p.action) and Controls.ACTIONS[p.action].has(p.hand + "_hand")
			_check(ok, "page %s presses %s on the %s hand, a control" % [page.effect, p.action, p.hand])
		for side in page.get("tools", {}):
			_check(Hand.Tool.has(page.tools[side].to_upper()), "page %s holds %s, a tool" % [page.effect, page.tools[side]])
		_check(has_method("_check_" + page.effect), "page %s has a check" % page.effect)


## Back where a player spawns, the garden bare, the hands holding what they start with.
func _fresh() -> void:
	Buttons.injected.clear()
	Hand.injected_sticks.clear()
	main.world.submit({"op": "wipe"})
	main.rig.place(Vector3(0, Terrain.height_at(0, 4), 4), 0.0)
	main.rig.rotation = Vector3.ZERO
	main.look.set_time(Daylight.DEFAULT)
	main.rig.left.tool = Hand.Tool.BOOK
	main.rig.right.tool = Hand.Tool.WALLS
	var book: Book = main.book
	book.at = 0
	book._turn.clear()
	await _frames(20)


## Plays `page` through the real hands: each frame poses them where the page does, in the head's frame as it stood
## when the page began, and holds the actions it holds there.
func _replay(page: Dictionary) -> void:
	var head: Transform3D = main.rig.head.global_transform
	for side in page.get("tools", {}):
		_hand(side).tool = Lessons.tool(page.tools[side])
	var t := 0.0
	while t <= page.length:
		for side in Lessons.hands(page):
			_hand(side).global_transform = head * Lessons.frame(Lessons.pose(page, side, t))
		for p in page.press:
			var tracker: String = p.hand + "_hand"
			var input := Controls.input(p.action, tracker)
			var on := Lessons.held(page, p.hand, p.action, t)
			if Hand.FLICKS.has(input):
				if on:
					Hand.injected_sticks[tracker] = Hand.FLICKS[input]
				else:
					Hand.injected_sticks.erase(tracker)
			elif on:
				Buttons.injected["%s/%s" % [tracker, input]] = true
			else:
				Buttons.injected.erase("%s/%s" % [tracker, input])
		_watch(page)
		await process_frame
		t += 1.0 / 60.0
	Buttons.injected.clear()
	Hand.injected_sticks.clear()


func _hand(side: String) -> Hand:
	return main.rig.left if side == "left" else main.rig.right


## What a page's check compares against, read before it plays.
func _read(page: Dictionary) -> Dictionary:
	var rig: Rig = main.rig
	var f := rig.head.global_transform * Lessons.frame(Lessons.pose(page, "right", 0.0)) if "right" in Lessons.hands(page) else Transform3D.IDENTITY
	var ground: Variant = Terrain.raycast(f.origin, -f.basis.z)
	effects = {"least_walls": main.tool.walls.size()}
	return {"at": rig.global_position, "walls": main.tool.walls.size(), "time": main.look.time,
		"ground": ground, "height": Terrain.height_at(ground.x, ground.z) if ground != null else 0.0,
		"state": var_to_str(main.world.state.walls), "trees": main.flora_tool.flora.placed("tree").size()}


func _watch(_page: Dictionary) -> void:
	effects.least_walls = mini(effects.least_walls, main.tool.walls.size())


func _check_tool(page: Dictionary, _before: Dictionary) -> void:
	_check(main.rig.right.tool == Lessons.tool(page.to), "holding the wheel button and moving down picks %s: holds %s" % [page.to, Hand.Tool.keys()[main.rig.right.tool]])


func _check_teleport(_page: Dictionary, before: Dictionary) -> void:
	var moved: float = Vector2(main.rig.global_position.x, main.rig.global_position.z).distance_to(Vector2(before.at.x, before.at.z))
	_check(moved > 2.0, "the left stick held forward and let go teleports: moved %.1f m" % moved)


func _check_undo(_page: Dictionary, before: Dictionary) -> void:
	_check(before.walls == 1 and effects.least_walls == 0, "the left lower face button undoes the wall: %d to %d" % [before.walls, effects.least_walls])
	_check(main.tool.walls.size() == 1, "the right lower face button redoes it: %d walls" % main.tool.walls.size())


func _check_hill(_page: Dictionary, before: Dictionary) -> void:
	_check(before.ground != null, "the hill page points at the ground")
	if before.ground == null:
		return
	var rise: float = Terrain.height_at(before.ground.x, before.ground.z) - before.height
	_check(rise > 0.3, "the grip on the ground, the hand raised, pulls a hill: %.2f m" % rise)


func _check_sky(_page: Dictionary, before: Dictionary) -> void:
	var turned := absf(angle_difference(Daylight.angle(main.look.time), Daylight.angle(before.time)))
	_check(turned > 0.2, "the grip on the sky, the pointer swept, turns the sky: %.2f rad" % turned)


func _check_colour(_page: Dictionary, before: Dictionary) -> void:
	_check(main.tool.walls.size() == before.walls and before.walls > 0, "the colour page has a house to colour")
	_check(var_to_str(main.world.state.walls) != before.state, "the trigger held on the house, the wrist twisted, recolours it")


func _check_house(_page: Dictionary, before: Dictionary) -> void:
	_check(main.tool.walls.size() == before.walls and before.walls == 1 and main.tool.held == null, "the house page's grips leave the one house it has: %d walls" % main.tool.walls.size())
	if main.tool.walls.size() != 1:
		return
	var was := WallTool.house_of(str_to_var(before.state).values()[0])
	var house := WallTool.house_of(main.world.state.walls.values()[0])
	_check(Vector2(house.center.x - was.center.x, house.center.z - was.center.z).length() > 0.4, "the right grip carries it: %s to %s" % [was.center, house.center])
	_check(house.size.x > was.size.x + 0.5 or house.size.y > was.size.y + 0.5, "the left grip joining and the hands spreading stretch it: %s" % house.size)
	_check(house.height > was.height + 0.5, "drawn apart upright, they make it taller: %.1f to %.1f m" % [was.height, house.height])


func _check_wipe(_page: Dictionary, before: Dictionary) -> void:
	_check(before.walls == 1 and before.trees == 1, "the wipe page's garden has a wall and a tree")
	_check(main.tool.walls.is_empty() and main.flora_tool.flora.placed("tree").is_empty(), "the delete trigger held at the sky for its whole hold wipes the garden")


## A hand passing a shut book's pages turns nothing; touching its cover opens it.
func _shut_book_turns_nothing() -> void:
	await _fresh()
	var book: Book = main.book
	var rig: Rig = main.rig
	rig.left.global_transform = rig.head.global_transform * held_book
	await _frames(30)
	var cover := rig.left.global_transform * Book.local(0.0) * Vector3(Book.W * 0.5, Book.leaves_t() + 0.01, 0)
	rig.right.global_transform = Transform3D(Basis.IDENTITY, cover + Vector3(0.3, 0.3, 0.3))
	await _frames(5)
	_check(book.at == 0, "a hand away from the shut book leaves it shut")
	rig.right.global_transform = Transform3D(Basis.IDENTITY, cover)
	await _frames(int(Book.OPEN_S * 60) + 10)
	_check(book.at == 1, "the right hand touching the cover opens the book at its first page: leaf %d" % book.at)
	_check(not book.faces_in_view().is_empty(), "the open book in view renders its pages")
	var facing := rig.head.global_transform
	rig.head.global_basis = facing.basis.rotated(Vector3.UP, PI)
	_check(book.faces_in_view().is_empty(), "the head looking away from the book stops its pages")
	rig.head.global_transform = facing
	rig.left.tool = Hand.Tool.WALLS
	await _frames(30)
	_check(not book.visible and book.faces_in_view().is_empty(), "taking another tool tucks the book away and stops its pages")
	rig.left.tool = Hand.Tool.BOOK
	await _frames(30)
	_check(book.visible and book.at == 1, "the wheel's book brings it back where it was left")


## Either hand's sweep turns by its direction wherever it starts on the spread, one leaf a sweep: the stroke back
## from a turn, the hand still on the pages, leaves it turned. Back from the first page shuts the book.
func _sweeps_turn_one_leaf_each_way() -> void:
	var book: Book = main.book
	var rig: Rig = main.rig
	rig.right.global_position = rig.head.global_position + Vector3(1, 1, 1)
	await _fresh()
	rig.left.global_transform = rig.head.global_transform * held_book
	book.at = 3
	await _sweep([[0.2, 0.12], [0.12, 0.03], [-0.05, 0.03], [0.12, 0.03], [0.2, 0.12]])
	_check(book.at == 4, "a leftward sweep and the stroke back over the pages turn one leaf on: leaf %d" % book.at)
	await _sweep([[-0.2, 0.12], [-0.12, 0.03], [0.05, 0.03], [0.06, 0.12]])
	_check(book.at == 3, "a rightward sweep from the left page turns back: leaf %d" % book.at)
	book.at = 1
	await _sweep([[0.02, 0.12], [0.03, 0.03], [0.14, 0.03], [0.16, 0.12]])
	await _frames(int(Book.TURN_S * 60) + 10)
	_check(book.at == 0, "a rightward sweep on the first page shuts the book: leaf %d" % book.at)


## Moves the right hand through `xy` in the open book's frame (x across the spread, y off the page), half a second a
## leg, then lets the turn finish.
func _sweep(xy: Array) -> void:
	var rig: Rig = main.rig
	for i in xy.size() - 1:
		for f in 30:
			var p := Vector2(xy[i][0], xy[i][1]).lerp(Vector2(xy[i + 1][0], xy[i + 1][1]), f / 30.0)
			rig.right.global_transform = Transform3D(Basis.IDENTITY, rig.left.global_transform * Book.local(1.0) * Vector3(p.x, p.y, 0.0))
			await process_frame
	await _frames(int(Book.TURN_S * 60) + 10)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
