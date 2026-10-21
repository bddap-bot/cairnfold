extends SceneTree

## Headless checks of the frame budget: what the garden counts follows every placement and deletion, an edit that
## would take it past the budget is turned down whole, and deleting makes room again:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_budget.gd

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
	await _a_joined_quest_2_holds_the_garden_to_its_own_budget()
	await _counts_follow_placements_and_deletions()
	await _an_edit_past_the_budget_is_turned_down_and_deleting_makes_room()
	await _a_capped_edit_is_heard_felt_and_shown()
	await _painting_stops_at_the_budget()
	await _the_bar_shows_the_share()
	_each_headset_is_fitted_where_its_budget_holds()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _each_headset_is_fitted_where_its_budget_holds() -> void:
	var frame := Quality.ladder[Budget.fit_step(Budget.Device.FRAME)]
	_check(frame.shadows and frame.scale_3d == 1.0, "the Frame is fitted on a step with shadows at full resolution")
	var below := Quality.ladder[Budget.fit_step(Budget.Device.FRAME) + 1]
	_check(not below.shadows or below.scale_3d != 1.0, "and on the last such step")
	_check(Budget.fit_step(Budget.Device.QUEST_2) == Quality.ladder.size() - 1, "the Quest 2 is fitted at the bottom")


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()


func _settled() -> void:
	for i in 3:
		await process_frame
	main.flora_tool.flora.grow_now()


## What the garden holds, counted afresh from its state rather than kept command by command.
func _recount() -> Dictionary:
	var out := {}
	for d: Dictionary in world.state.walls.values():
		Budget.add(out, Budget.wall(d))
	for d: Dictionary in world.state.paths.values():
		Budget.add(out, Budget.path(d))
	for g in world.state.groups:
		for p: Flora.Plant in world.flora.groups[g]:
			if p != null and not world.state.groups[g].hidden.has(p.index):
				var u := world.flora.unit_of(p)
				if u != "" and g != 0:
					Budget.add(out, {u: 1})
	if not world.state.ponds.is_empty():
		out.pond = world.state.ponds.size()
	return out


func _same(a: Dictionary, b: Dictionary) -> bool:
	for k in Budget.UNITS:
		if not is_equal_approx(snappedf(a.get(k, 0.0), 0.001), snappedf(b.get(k, 0.0), 0.001)):
			return false
	return true


static func _wall(from: Vector2, to: Vector2, height: float) -> Dictionary:
	var points := PackedVector3Array()
	for i in 9:
		var p := from.lerp(to, i / 8.0)
		points.append(Terrain.ground(p.x, p.y))
	return {"points": points, "height": height, "seed": 7, "closed": false, "top": 0,
		"fence": false, "openings": PackedVector4Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(),
		"ruins": PackedVector2Array(), "plaster": false, "plinth_plaster": false, "rise": 0.0, "gable_end": 0, "timber_style": 0, "on": PackedInt32Array(), "paint": Palette.plain()}


## Submits a wall command and waits for it to settle; whether it went into the garden.
func _build(walls: Array) -> bool:
	var before: int = world.state.walls.size()
	var settled := [false]
	world.submit({"op": "wall", "walls": walls}, func() -> void: settled[0] = true, main.rig.right)
	_check(settled[0], "a wall command settles at once on the host")
	await _settled()
	return world.state.walls.size() > before


func _counts_follow_placements_and_deletions() -> void:
	var meadow := world.units.duplicate()
	_check(meadow.is_empty(), "the meadow's own plants are the base and count nothing: %s" % meadow)
	for on: Budget.Device in Budget.COSTS:
		_check(Budget.room_ms(on) > 0.0 and Budget.fits(meadow, {"wall_m2": 1.0}, [on]), "a fresh garden has room to build on %s" % Budget.Device.keys()[on])
	_check(_same(world.units, _recount()), "a fresh garden counts what it holds")
	world._order({"op": "tree", "group": 0, "index": world.flora.meadow_trees()[0], "scale": 2.0}, world.me())
	_check(world.units.is_empty(), "a meadow tree stays in the base when resized: %s" % world.units)
	world._order({"op": "undo"}, world.me())
	_check(world.units.is_empty(), "and shrunk back counts nothing again: %s" % world.units)
	await _play([
		{"op": "place", "x": 0, "z": 8},
		{"op": "wall", "points": [[-6, -2], [-1, -3]], "seconds": 0.3},
		{"op": "tree", "x": -6, "z": 4},
		{"op": "paint", "tool": "flowers", "points": [[6, 4], [7, 4]], "radius": 1.0, "seconds": 0.3},
		{"op": "pave", "points": [[3.5, -6], [3.5, 1]], "radius": 0.8, "seconds": 0.3},
		{"op": "dig", "x": 10, "z": -8, "seconds": 0.5},
	])
	await _settled()
	_check(world.units.get("wall_m2", 0.0) > 0.0 and not world.units.has("path_m2") and world.units.get("pond", 0) == 1, "walls, ponds and reserved path steps count: %s" % world.units)
	_check(world.units.get("tree", 0) == 1 and world.units.get("flower", 0) > 0, "a planted tree and painted flowers count: %s" % world.units)
	var planted: int = world.state.groups.keys().filter(func(g: int) -> bool: return world.state.groups[g].kind == "tree")[0]
	var before_resize := world.units.duplicate()
	for scale in [FloraLayout.SCALES.x, 2.0, FloraLayout.SCALES.y]:
		var resize := {"op": "tree", "group": planted, "index": 0, "scale": scale}
		_check(world.change_of(resize).is_empty(), "resizing predicts no extra charge")
		world._order(resize, world.me())
		_check(is_equal_approx(world.state.groups[planted].scale.get(0, 1.0), scale), "the resize was accepted before undoing it")
		_check(_same(world.units, before_resize) and _same(world.units, _recount()), "resizing keeps the planted tree charged once")
		world._order({"op": "undo"}, world.me())
		_check(_same(world.units, before_resize), "undoing a resize preserves its charge")
	_check(_same(world.units, _recount()), "what the garden counts matches what it holds: %s against %s" % [world.units, _recount()])
	var wall_id: int = world.state.walls.keys()[0]
	var wall_units := Budget.wall(world.state.walls[wall_id])
	var with_wall := world.units.duplicate()
	world.submit({"op": "unwall", "ids": PackedInt32Array([wall_id])})
	await _settled()
	_check(is_equal_approx(world.units.get("wall_m2", 0.0), with_wall.wall_m2 - wall_units.wall_m2), "deleting a wall frees what it counted")
	await _play([{"op": "delete", "x": -6, "z": 4, "height": 3.0}])
	await _settled()
	_check(not world.units.has("tree"), "deleting the tree frees it: %s" % world.units)
	_check(_same(world.units, _recount()), "after deletions the count still matches the garden")
	for i in 8:
		world.undo()
		await _settled()
	_check(_same(world.units, _recount()), "undo and redo keep the count matching the garden")
	await _play([{"op": "bare"}])
	await _settled()
	_check(_same(world.units, _recount()) and not world.units.has("wall_m2") and not world.units.has("flower"), "a wipe leaves nothing counted but the bare meadow: %s" % world.units)
	world.undo()
	await _settled()
	_check(_same(world.units, _recount()), "undoing the wipe counts the garden it brings back")
	await _play([{"op": "bare"}])
	await _settled()


func _an_edit_past_the_budget_is_turned_down_and_deleting_makes_room() -> void:
	var on := world.devices()
	var piece := _wall(Vector2(-6, -20), Vector2(6, -20), 4.5)
	var share := Budget.fill(Budget.wall(piece), on)
	_check(share > 0.02 and share < 0.3, "one test wall takes a measurable share: %.3f" % share)
	var too_big := [_wall(Vector2(-40, 30), Vector2(40, 30), 9.0), _wall(Vector2(-40, 34), Vector2(40, 34), 9.0), _wall(Vector2(-40, 38), Vector2(40, 38), 9.0)]
	var before := world.units.duplicate()
	_check(not await _build(too_big), "a build past the whole budget is turned down")
	_check(_same(world.units, before), "a turned-down build counts nothing")
	var built := 0
	for i in 40:
		var at := -30.0 + i * 3.0
		if not await _build([_wall(Vector2(-6, at), Vector2(6, at), 4.5)]):
			break
		built += 1
	_check(built > 0 and built < 40, "walls go up until the budget is full: %d" % built)
	_check(world.fill() <= 1.0, "the garden never passes its budget: %.3f" % world.fill())
	_check(world.fill() + share > 1.0, "the wall turned down would have passed it: %.3f + %.3f" % [world.fill(), share])
	var full := world.units.duplicate()
	var last: int = world.state.walls.keys().max()
	world.submit({"op": "unwall", "ids": PackedInt32Array([last])})
	await _settled()
	_check(world.fill() < Budget.fill(full, on), "deleting a wall frees its share")
	_check(await _build([_wall(Vector2(-6, -50), Vector2(6, -50), 4.5)]), "the room it freed takes another wall")
	var tall_id: int = world.state.walls.keys().max()
	world.submit({"op": "reshape", "of": "walls", "id": tall_id, "data": {"height": 9.0}})
	await _settled()
	_check(world.state.walls[tall_id].height == 4.5, "pulling a wall taller than the budget allows is turned down")
	await _play([{"op": "bare"}])
	await _settled()


## Directive (verbatim): "When something doesn't work because of the frame cap, I think it should be obvious to the
## player. I think maybe we can do that by embiggening the little bar that represents frame cap and shaking it around
## and making a little sound, like a [grunt ]sound".
func _a_capped_edit_is_heard_felt_and_shown() -> void:
	var hand: Hand = main.rig.right
	hand.tool = Hand.Tool.WALLS
	var bar: BudgetBar = null
	for c in hand.get_children():
		if c is BudgetBar:
			bar = c
	var capped := [null]
	world.capped.connect(func(h: XRController3D) -> void: capped[0] = h, CONNECT_ONE_SHOT)
	var grunts: int = Cues.asked.get(Cues.Act.CAPPED, 0)
	var too_big := [_wall(Vector2(-40, 30), Vector2(40, 30), 9.0), _wall(Vector2(-40, 34), Vector2(40, 34), 9.0), _wall(Vector2(-40, 38), Vector2(40, 38), 9.0)]
	_check(not await _build(too_big), "a build past the whole budget is turned down")
	_check(capped[0] == hand, "the hand that tried it is the one capped")
	_check(Cues.asked.get(Cues.Act.CAPPED, 0) == grunts + 1, "the frame cap grunts once")
	await process_frame
	_check(bar.scale.x > 1.5, "its bar jumps up: %.2f" % bar.scale.x)
	for i in 60:
		await process_frame
	_check(is_equal_approx(bar.scale.x, 1.0), "and settles back: %.2f" % bar.scale.x)
	var change := {}
	for w: Dictionary in too_big:
		Budget.add(change, Budget.wall(w))
	for i in 3:
		world.preview(hand, change)
		await process_frame
	_check(hand.capped and bar.scale.x > 1.1, "a preview that will not fit shows refused before it is let go: %.2f" % bar.scale.x)
	for i in 3:
		await process_frame
	_check(not hand.capped, "and stops once nothing over is shown")


func _painting_stops_at_the_budget() -> void:
	for i in 40:
		var at := -30.0 + i * 3.0
		if not await _build([_wall(Vector2(-6, at), Vector2(6, at), 4.5)]):
			break
	var walls: Array = world.state.walls.keys()
	world.submit({"op": "unwall", "ids": PackedInt32Array([walls.max()])})
	await _settled()
	await _play([{"op": "paint", "tool": "flowers", "points": [[-20, 20], [20, 20]], "radius": 3.0, "seconds": 6.0}])
	await _settled()
	_check(world.fill() <= 1.0, "a long paint stroke stops at the budget: %.3f" % world.fill())
	_check(world.units.get("flower", 0) > 0, "it painted up to it")


func _the_bar_shows_the_share() -> void:
	var bars := []
	for h in main.rig.hands:
		for c in h.get_children():
			if c is BudgetBar:
				bars.append(c)
	_check(bars.size() == 2, "each controller carries a bar")
	for i in 60:
		await process_frame
	for b: BudgetBar in bars:
		var shown: float = b.material_override.get_shader_parameter("fill")
		_check(absf(shown - world.fill()) < 0.01, "the bar shows the garden's share: %.3f against %.3f" % [shown, world.fill()])


func _a_joined_quest_2_holds_the_garden_to_its_own_budget() -> void:
	var meadow := world.units.duplicate()
	await _play([{"op": "place", "x": 0, "z": 8}, {"op": "house", "at": [0, 0], "size": [2.4, 2.4], "seconds": 0.3}])
	_check(world.state.walls.size() == 1, "the solo host can place a small stone house")
	var house := Budget.add(world.units.duplicate(), meadow, -1.0)
	var branches: Array[Node] = []
	var peers: Array[ENetMultiplayerPeer] = []
	var worlds: Array[World] = []
	for i in 2:
		var branch := Node.new()
		root.add_child(branch)
		set_multiplayer(SceneMultiplayer.new(), branch.get_path())
		var w := World.new()
		branch.add_child(w)
		w.units = world.units.duplicate()
		branches.append(branch)
		worlds.append(w)
		peers.append(ENetMultiplayerPeer.new())
	var host := worlds[0]
	var guest := worlds[1]
	var own := Budget.device()
	var solo := host.fill()
	_check(host.devices() == [own], "a solo garden is held to its own headset")
	_check(peers[0].create_server(0) == OK, "the budget test host opens ENet")
	host.multiplayer.multiplayer_peer = peers[0]
	_check(peers[1].create_client("127.0.0.1", peers[0].host.get_local_port()) == OK, "the visitor connects")
	guest.multiplayer.multiplayer_peer = peers[1]
	for i in 600:
		await process_frame
		if host.multiplayer.get_peers().size() == 1 and guest.multiplayer.get_peers().size() == 1:
			break
	for i in 30:
		await process_frame
	guest._device.rpc_id(1, Budget.Device.QUEST_2)
	for i in 30:
		await process_frame
	var both := [own, Budget.Device.QUEST_2]
	print("budget-coop: house %s; meadow %.6f -> %.6f; house %.6f -> %.6f; garden %.6f -> %.6f" % [house,
		Budget.fill(meadow, [own]), Budget.fill(meadow, both), Budget.fill(house, [own]), Budget.fill(house, both), solo, host.fill()])
	_check(Budget.Device.QUEST_2 in host.devices(), "the host holds the garden to the Quest 2 that joined: %s" % [host.devices()])
	_check(is_equal_approx(host.fill(), Budget.fill(host.units, both)), "the bar prices the garden against the visitor's table")
	_check(Budget.fits(host.units, house, host.devices()) == Budget.fits(host.units, house, both),
		"a second house fits only if it fits the visitor's headset too")
	for peer in peers:
		peer.close()
	host.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	guest.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_check(host.devices() == [own], "once the visitor leaves, the garden is held to the host's headset alone")
	for branch in branches:
		branch.queue_free()
	world.undo()
	await _settled()
