extends SceneTree

## Hands on a built house: one on its roof carries the house, two upright raise its ridge, two across bow its slopes and
## two on its eaves pull them out; what stands on it goes with it, and edits made to it meanwhile stay:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_roof_grab.gd

var main: Node
var failures := 0
var trackers: Array[XRControllerTracker] = []


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frames(count := 4) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	await process_frame
	# Fixture geometry exceeds capacity; test_budget covers the shared limit.
	main.world.bounded = false
	var driver := Driver.new(main, [{"op": "house", "at": [0, 0], "size": [6, 4], "seconds": 0.1}])
	main.add_child(driver)
	await driver.finished
	driver.queue_free()
	await _frames(30)
	var rig: Rig = main.rig
	for hand in rig.hands:
		var tracker := XRControllerTracker.new()
		tracker.name = hand.tracker
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
	await _body_and_ridge()
	await _eaves()
	await _storeys_ride_along()
	await _edits_made_meanwhile_stay()
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


## Poses `hand` `over` metres above the roof of `w` at `across` metres out from its ridge, pointing down at it.
func _over(hand: Hand, w: Wall, along: float, across: float, over := 2.0) -> void:
	var f: Dictionary = w.roof.frame()
	hand.global_transform = Transform3D(Basis.looking_at(Vector3(0.0001, -1, 0)), f.mid + f.along * along + f.across * across + Vector3.UP * (w.layout.height + w.roof.pitch + over))


func _body_and_ridge() -> void:
	var tool: WallTool = main.tool
	var w: Wall = tool.walls[0]
	var rig: Rig = main.rig
	var pitch: float = main.world.state.walls[w.id].roof.pitch
	var center: Vector3 = WallTool.house_of(main.world.state.walls[w.id]).center
	_over(rig.left, w, -0.5, 0.5)
	_over(rig.right, w, 0.5, 0.5)
	await _frames()
	Buttons.injected["left_hand/grip_click"] = true
	await _frames()
	_check(tool.held == w and tool.mason(rig.left).took_roof and tool.mason(rig.left).eave_out == Vector3.ZERO, "a grip on the roof takes the house, by its roof")
	rig.left.position.x -= 0.1
	await _frames()
	_check(w.roof.curve == 0.0 and tool.held_at.center.x < center.x - 0.05, "one hand sideways carries the house and cannot bow its roof: %s" % tool.held_at.center)
	Buttons.injected["right_hand/grip_click"] = true
	await _frames()
	_check(tool._holders.size() == 2 and tool._pair == WallTool.Pair.ROOF, "the second grip on the roof shapes the roof")
	var stands: Dictionary = tool.held_at.duplicate()
	Cues.pulsed.clear()
	var start := rig.right.position
	for spread in [0.3, 0.0, -0.3, -0.301]:
		rig.right.position = start + Vector3(spread, 0, 0)
		await _frames()
		_check(absf(w.roof.curve - spread * 2.0) < 0.0001, "spreading across bows it, signed: %s to %.3f" % [spread, w.roof.curve])
		_check(w.roof.pitch == pitch and tool.held_at.size == stands.size and tool.held_at.center == stands.center, "bowing keeps its pitch and footprint")
	for hand in rig.hands:
		_check(Cues.pulsed.get(Cues.Act.ROOF_SHAPE, {}).get(hand.get_instance_id(), 0) > 0, "the roof's shaping pulses both hands")
	rig.right.position = start + Vector3(0, 0.4, 0)
	await _frames()
	_check(w.roof.pitch > pitch + 0.3 and is_zero_approx(w.roof.curve) and tool.held_at.size == stands.size, "drawn apart upright they raise its ridge: %.2f to %.2f" % [pitch, w.roof.pitch])
	Buttons.injected.erase("right_hand/grip_click")
	await _frames()
	rig.right.position = start + Vector3(0, 3, 0)
	await _frames()
	Buttons.injected["right_hand/grip_click"] = true
	await _frames()
	rig.right.position = start
	await _frames()
	_check(w.roof.flat(), "brought together upright they lower it, all the way down snapping it flat")
	rig.right.position = start + Vector3(0.2, 0.1, 0)
	await _frames()
	var shaped := {"pitch": w.roof.pitch, "curve": w.roof.curve}
	Buttons.injected.erase("left_hand/grip_click")
	await _frames()
	_check(tool.held == w and tool._holders.size() == 1, "letting one hand go leaves the house in the other")
	Buttons.injected.erase("right_hand/grip_click")
	await _frames()
	var d: Dictionary = main.world.state.walls[w.id]
	_check(tool.held == null and is_equal_approx(d.roof.pitch, shaped.pitch) and is_equal_approx(d.roof.curve, shaped.curve), "letting go sets the roof in the garden: %s" % d.roof)
	await _frames()
	main.world.undo()
	await _frames()
	d = main.world.state.walls[w.id]
	_check(d.roof.curve == 0.0 and d.roof.pitch == pitch and WallTool.house_of(d).center.is_equal_approx(center), "one undo puts back the roof and where the house stood")
	for limit in [-RoofLayout.CURVE, RoofLayout.CURVE]:
		main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"roof": {"curve": limit}}})
		await _frames()
		_check(main.world.state.walls[w.id].roof.curve == limit, "curvature limit survives command validation and round trip")
	main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"roof": {"curve": 0.0}}})
	await _frames(30)


## Directive (relay): two hands on the eave edge pulling outward lengthen the overhang, inward shorten it.
func _eaves() -> void:
	var tool: WallTool = main.tool
	var w: Wall = tool.walls[0]
	var rig: Rig = main.rig
	var out := w.roof.half_span() + minf(w.roof.overhang, w.roof.reach()) * 0.6
	var overhang := w.roof.overhang
	_over(rig.left, w, 0.0, -out)
	_over(rig.right, w, 0.0, out)
	await _frames()
	Buttons.injected["left_hand/grip_click"] = true
	Buttons.injected["right_hand/grip_click"] = true
	await _frames()
	_check(tool._holders.size() == 2 and tool._pair == WallTool.Pair.EAVES, "grips on both eaves, past the walls, take the eaves")
	var across: Vector3 = w.roof.frame().across
	var left := rig.left.position
	var right := rig.right.position
	rig.left.position = left - across * 0.1
	rig.right.position = right + across * 0.1
	await _frames()
	var pulled := w.roof.overhang
	_check(pulled > overhang + 0.05 and w.roof.curve == 0.0, "pulled outward the eaves reach farther: %.2f to %.2f" % [overhang, pulled])
	rig.left.position = left + across * 0.03
	rig.right.position = right - across * 0.03
	await _frames()
	_check(w.roof.overhang < overhang, "pushed inward they draw back: %.2f" % w.roof.overhang)
	rig.left.position = left - across * 0.1
	rig.right.position = right + across * 0.1
	await _frames()
	Buttons.injected.clear()
	await _frames()
	_check(is_equal_approx(main.world.state.walls[w.id].roof.overhang, pulled), "letting go sets the eaves: %.2f" % main.world.state.walls[w.id].roof.overhang)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()


## A storey standing on a carried house, and a wall on that storey, ride along with it and are set where it is let go,
## one undo step; a grip that only trembles sends nothing.
func _storeys_ride_along() -> void:
	var tool: WallTool = main.tool
	var world: World = main.world
	await _play([
		{"op": "budget", "bounded": false},
		{"op": "house", "at": [20, -20], "size": [6, 5], "seconds": 0.2},
		{"op": "house", "at": [20, -20], "size": [4, 3.5], "seconds": 0.2, "on": true},
		{"op": "wall", "points": [[19, -20], [21, -20]], "seconds": 0.3, "on": true},
	])
	var walls: Array[Wall] = tool.walls
	var base := walls[-3]
	var upper := walls[-2]
	var top := walls[-1]
	_check(upper.on == PackedInt32Array([base.id]) and top.on.has(upper.id), "a storey stands on the house and a wall on the storey: %s" % [walls.slice(-4).map(func(w: Wall) -> Array: return [w.id, w.on, w.layout.closed])])
	var before := {}
	for w: Wall in [base, upper, top]:
		before[w.id] = world.state.walls[w.id].points
	tool.take_build(base)
	var nudged: Dictionary = tool.held_at.duplicate()
	nudged.center += Vector3(0.02, 0, 0.01)
	tool.stand_build(nudged)
	tool.end_build()
	await _frames()
	_check(world.state.walls[base.id].points == before[base.id] and world.state.walls[upper.id].points == before[upper.id], "a grip that only trembles leaves it where it stood, sending nothing")
	tool.take_build(base)
	_check(tool._held(upper) and tool._held(top), "what stands on it is held with it")
	var to: Dictionary = tool.held_at.duplicate()
	to.center += Vector3(3, 0, 1)
	to.yaw += 0.3
	tool.stand_build(to)
	await _frames()
	var moved := func(w: Wall) -> bool: return w.transform.basis.is_equal_approx(Basis(Vector3.UP, 0.3)) and not w.transform.origin.is_zero_approx()
	_check(moved.call(base) and moved.call(upper) and moved.call(top), "carried, the storey and the wall on it move with it as laid")
	tool.end_build()
	await _frames(30)
	var x := Transform3D(Basis(Vector3.UP, 0.3), Vector3.ZERO)
	var c0: Vector3 = WallTool.house_of({"points": before[base.id], "roof": world.state.walls[base.id].roof, "closed": true, "rise": 0.0, "height": 2.4}).center
	var expect := func(p: Vector3) -> Vector3:
		var q := Transform3D(Basis(Vector3.UP, 0.3), Vector3(to.center.x, 0, to.center.z)) * Transform3D(Basis(), -Vector3(c0.x, 0, c0.z)) * Vector3(p.x, 0, p.z)
		return Vector3(q.x, 0, q.z)
	var lands := func(id: int) -> bool:
		var now: PackedVector3Array = world.state.walls[id].points
		var was: PackedVector3Array = before[id]
		for i in was.size():
			var e: Vector3 = expect.call(was[i])
			if Vector2(now[i].x - e.x, now[i].z - e.z).length() > 0.01:
				return false
		return true
	_check(lands.call(base.id) and lands.call(upper.id) and lands.call(top.id), "let go, the house, its storey and the wall on that are all set where they were carried")
	_check(upper.on == PackedInt32Array([base.id]) and top.on.has(upper.id), "each still standing on the one under it")
	for i in 600:
		if [base, upper, top].all(func(w: Wall) -> bool: return w.transform.is_equal_approx(Transform3D.IDENTITY)):
			break
		await _frames(1)
	_check([base, upper, top].all(func(w: Wall) -> bool: return w.transform.is_equal_approx(Transform3D.IDENTITY)), "laid again where they stand, carried no more")
	world.undo()
	await _frames()
	_check([base, upper, top].all(func(w: Wall) -> bool: return world.state.walls[w.id].points == before[w.id]), "one undo puts all three back")
	world.redo()
	await _frames()
	_check(lands.call(base.id) and lands.call(upper.id), "redo carries them again")


## A window opened in a house while another hand carries it is still there when it is let go.
func _edits_made_meanwhile_stay() -> void:
	var tool: WallTool = main.tool
	var world: World = main.world
	await _play([{"op": "house", "at": [-20, -20], "size": [6, 4], "seconds": 0.2}])
	var w: Wall = tool.walls[-1]
	tool.take_build(w)
	var to: Dictionary = tool.held_at.duplicate()
	to.center += Vector3(2, 0, 0)
	tool.stand_build(to)
	await _play([{"op": "wait", "seconds": 0.1}, {"op": "fit", "what": "opening", "index": -1, "s": 3.0, "y": 1.0}, {"op": "wait", "seconds": 0.1}])
	_check(world.state.walls[w.id].openings.size() == 1, "a window opens in the house in hand")
	tool.end_build()
	await _frames()
	var d: Dictionary = world.state.walls[w.id]
	_check(d.openings.size() == 1 and absf(WallTool.house_of(d).center.x - to.center.x) < 0.01, "let go, it stands where it was carried with the window still in it: %s" % d.openings)
