extends SceneTree

## Hands on a built house's roof: one carries the house, two upright raise its ridge, two across bow its slopes and two
## on its eaves pull them out: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_roof_grab.gd

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
	_check(tool.house == w and tool.mason(rig.left).took_roof and tool.mason(rig.left).eave_out == Vector3.ZERO, "a grip on the roof takes the house, by its roof")
	rig.left.position.x -= 0.1
	await _frames()
	_check(w.roof.curve == 0.0 and tool.house_at.center.x < center.x - 0.05, "one hand sideways carries the house and cannot bow its roof: %s" % tool.house_at.center)
	Buttons.injected["right_hand/grip_click"] = true
	await _frames()
	_check(tool._holders.size() == 2 and tool._pair == WallTool.Pair.ROOF, "the second grip on the roof shapes the roof")
	var stands: Dictionary = tool.house_at.duplicate()
	Cues.pulsed.clear()
	var start := rig.right.position
	for spread in [0.3, 0.0, -0.3, -0.301]:
		rig.right.position = start + Vector3(spread, 0, 0)
		await _frames()
		_check(absf(w.roof.curve - spread * 2.0) < 0.0001, "spreading across bows it, signed: %s to %.3f" % [spread, w.roof.curve])
		_check(w.roof.pitch == pitch and tool.house_at.size == stands.size and tool.house_at.center == stands.center, "bowing keeps its pitch and footprint")
	for hand in rig.hands:
		_check(Cues.pulsed.get(Cues.Act.ROOF_SHAPE, {}).get(hand.get_instance_id(), 0) > 0, "the roof's shaping pulses both hands")
	rig.right.position = start + Vector3(0, 0.4, 0)
	await _frames()
	_check(w.roof.pitch > pitch + 0.3 and is_zero_approx(w.roof.curve) and tool.house_at.size == stands.size, "drawn apart upright they raise its ridge: %.2f to %.2f" % [pitch, w.roof.pitch])
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
	_check(tool.house == w and tool._holders.size() == 1, "letting one hand go leaves the house in the other")
	Buttons.injected.erase("right_hand/grip_click")
	await _frames()
	var d: Dictionary = main.world.state.walls[w.id]
	_check(tool.house == null and is_equal_approx(d.roof.pitch, shaped.pitch) and is_equal_approx(d.roof.curve, shaped.curve), "letting go sets the roof in the garden: %s" % d.roof)
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
