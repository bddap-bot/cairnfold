extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	# These grips point at what they take: the reach they check is the pointing grab, until a playtest keeps one.
	Reach.mode = Reach.Mode.AIM
	boot_main()
	_run.call_deferred()


func _run() -> void:
	main.world.limit = INF
	await play([{"op": "house", "at": [0, 0], "size": [6, 5], "seconds": 0.2}])
	var w: Wall = main.tool.walls[0]
	w.lay_now()
	var missed := []
	for k in 50:
		var f := w.layout.frame_at(0.5 + k * 0.1)
		var out: Vector3 = f.tangent.cross(Vector3.UP)
		out *= signf((f.point - w.roof.frame().mid).dot(out))
		for height in [1.4, 1.8, 2.2]:
			var target: Vector3 = f.point + Vector3.UP * height
			var origin: Vector3 = f.point + out * 2.0 + f.tangent * 1.0 + Vector3.UP * 1.2
			var dir := (target - origin).normalized()
			var hit: Dictionary = main.fitting_tool.aim(Hand.Tool.DECORATIONS, origin, dir)
			if hit.get("what") != "lantern":
				missed.append([origin, dir, hit.get("what")])
	check(missed.is_empty(), "standing oblique wall rays offer lanterns: %s" % [missed.slice(0, 5)])
	var origin := Vector3(-0.3, w.layout.samples[0].y + 1.2, -4.5)
	var dir := Vector3(-0.431934, 0.259161, 0.863868).normalized()
	var surface: Dictionary = main.tool.pick_building(origin, dir)
	var contact := HandStop.Near.gather(main.world, AABB(surface.point - Vector3.ONE, Vector3.ONE * 2.0))
	check(contact.solid(surface.point + dir * 0.03), "touch stops on the same wall body")
	var teleported: Dictionary = main.rig.solid_hit.call(origin, dir, 30.0)
	check(not teleported.is_empty() and teleported.point.distance_to(surface.point) < 0.01, "teleport stops at the near wall surface")
	var target: Dictionary = main.fitting_tool.aim(Hand.Tool.DECORATIONS, origin, dir)
	check(target.get("what") == "lantern" and main.fitting_tool.fit(target), "the failing angle places a wall lantern")
	w.lay_now()
	check(w.layout.lanterns.size() == 1 and w.roof.chimneys.is_empty(), "a lantern is placed and no chimney is added")
	main.rig.right.tool = Hand.Tool.DECORATIONS
	main.rig.right.held_still = true
	main.rig.right.global_transform = Transform3D(Basis.looking_at(dir), origin)
	await _capture("wall-lantern", origin + Vector3.UP * 0.35, origin + dir * 3.0)
	await _overlapping_roofs()
	await _gable_ends_are_met_at_their_face()
	finish()


## The building ray meets a house's gable ends, wall faces and roof in every finish, gable end and roof covering, a gable
## end from outside and in at the face of the boards, plaster or stone laid on it, where the hand's dot shows.
func _gable_ends_are_met_at_their_face() -> void:
	await play([{"op": "house", "at": [0, -12], "size": [6, 5], "seconds": 0.2}])
	var w: Wall = main.tool.walls[-1]
	var face := WallLayout.THICKNESS * 0.5 - WallLayout.PLASTER_INSET - 0.01
	var missed := []
	for thatch in [false, true]:
		for finish in WallLayout.Finish.values():
			for gable_end in WallLayout.GableEnd.values():
				main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"finish": finish, "gable_end": gable_end, "roof": {"thatch": thatch}}})
				w.lay_now()
				var name := "finish %d, gable end %d, thatch %s" % [finish, gable_end, thatch]
				var f := w.roof.frame()
				var hs := w.roof.half_span()
				for end in [-1.0, 1.0]:
					var out: Vector3 = f.along * end
					var plane: Vector3 = f.mid + out * w.roof.ridge_length() * 0.5
					for x in [-0.4, 0.0, 0.4]:
						var on: Vector3 = plane + f.across * x * hs + Vector3.UP * w.roof.rise(1.0 - absf(x)) * 0.4
						for from in [3.0, -2.0]:
							var target := main.palette_tool.aim_style(on + out * from, -out * signf(from))
							var depth: float = (target.get("point", plane) - plane).dot(out * signf(from))
							if target.get("restyle") != PaletteTool.Restyle.GABLE or depth < face:
								missed.append("%s: gable %s %.1f, %s %.2f deep" % [name, "outside" if from > 0.0 else "inside", x, target.get("restyle"), depth])
				var below := w.layout.frame_at(w.layout.length() * 0.1)
				var across: Vector3 = below.tangent.cross(Vector3.UP)
				across *= signf((below.point - f.mid).dot(across))
				var wall := main.palette_tool.aim_style(below.point + Vector3.UP * 1.5 + across * 3.0, -across)
				var wall_depth: float = (wall.get("point", below.point) - below.point).dot(across)
				if wall.get("restyle") != PaletteTool.Restyle.FACE or wall_depth < face:
					missed.append("%s: wall face %s %.2f deep" % [name, wall.get("restyle"), wall_depth])
				var roof := main.palette_tool.aim_style(f.mid + f.across * hs * 0.5 + Vector3.UP * 12.0, Vector3.DOWN)
				if roof.get("restyle") != PaletteTool.Restyle.ROOF:
					missed.append("%s: roof %s" % [name, roof.get("restyle")])
	check(missed.is_empty(), "every gable end, wall face and roof meets the ray at its face: %d missed, %s" % [missed.size(), missed.slice(0, 6)])
	main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"finish": WallLayout.Finish.BOARDS_UPRIGHT, "gable_end": WallLayout.GableEnd.BOARDS, "roof": {"thatch": false}}})
	w.lay_now()
	var f := w.roof.frame()
	var on: Vector3 = f.mid + f.along * w.roof.ridge_length() * 0.5 + Vector3.UP * w.roof.rise(1.0) * 0.4
	var hand: Vector3 = on + f.along * 3.0 + f.across * 0.6 + Vector3.DOWN * 0.4
	main.rig.right.tool = Hand.Tool.STYLE
	main.rig.right.held_still = true
	main.rig.right.global_transform = Transform3D(Basis.looking_at(on - hand), hand)
	await _capture("wooden-gable", hand + f.across * 1.2 + f.along * 1.5 + Vector3.UP * 0.5, on)


func _capture(name: String, eye: Vector3, at: Vector3) -> void:
	if OS.get_environment("PICK_CAPTURE").is_empty():
		return
	var hand: Transform3D = main.rig.right.global_transform
	main.view(eye, at, false)
	main.rig.right.global_transform = hand
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("PICK_CAPTURE").path_join(name + ".png"))


func _overlapping_roofs() -> void:
	await play([{"op": "house", "at": [1, 0], "size": [6, 5], "foundation": "stone", "seconds": 0.2}])
	var near: Wall = main.tool.walls[-1]
	main.world.submit({"op": "reshape", "of": "walls", "id": near.id, "data": {"height": 6.0}})
	for wall: Wall in main.tool.walls:
		wall.lay_now()
	var far: Wall = main.tool.walls[0]
	var f := near.roof.frame()
	var spot: Vector3 = f.mid - f.along * (near.roof.ridge_length() * 0.5 + 0.4) + f.across * 0.8
	var origin := spot + Vector3.UP * 8.0
	var dir := Vector3.DOWN
	var near_t := near.roof.ray_hit(origin, dir)
	var far_t := far.roof.ray_hit(origin, dir)
	check(near_t < far_t and far_t < INF, "two roofs overlap along the test ray: %s before %s" % [near_t, far_t])
	var hit: Dictionary = main.tool.pick_building(origin, dir, true)
	check(hit.get("wall") == near and hit.get("surface") == "roof", "grab query hits the near roof")
	var fit: Dictionary = main.fitting_tool.aim(Hand.Tool.DECORATIONS, origin, dir)
	check(fit.get("wall") == near and fit.get("what") == "chimney", "decoration hits the near roof")
	var colour: Dictionary = main.palette_tool.aim(origin, dir)
	var style: Dictionary = main.palette_tool.aim_style(origin, dir)
	check(colour.get("id") == near.id and style.get("id") == near.id, "colour and style hit the near roof")
	var erased: Dictionary = main.delete_tool.aim(origin, dir)
	check(erased.get("wall") == near and erased.get("point", Vector3.INF).distance_to(origin + dir * near_t) < 0.01, "delete stops at the near roof surface")
	await _grab(near, origin)
	await _capture("overlapping-roofs", f.mid + Vector3(9, 7, 10), f.mid - Vector3.UP * 2.0)
	_foundation_and_deck(near)
	await _thatched_eave(near, far)


func _foundation_and_deck(w: Wall) -> void:
	var before := {"rise": w.layout.rise, "roof": {"pitch": w.roof.pitch}}
	main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"rise": 1.0, "roof": {"pitch": 0.0}}})
	w.lay_now()
	var s := w.layout.points[0].distance_to(w.layout.points[1]) + 1.3
	var f := w.layout.frame_at(s)
	var out: Vector3 = f.tangent.cross(Vector3.UP)
	out *= signf((f.point - w.roof.frame().mid).dot(out))
	var origin: Vector3 = f.point + Vector3.DOWN * 0.4 + out * 2.0
	var foundation: Dictionary = main.tool.pick_building(origin, -out)
	check(foundation.get("wall") == w and foundation.get("surface") == "wall" and foundation.point.y < f.point.y, "the raised foundation stops the building ray: hit %s, wanted %d at %s (foot %s, depth %s, rise %s)" % [foundation, w.id, origin, f.point, w.layout.depth_at(s), w.layout.rise])
	origin = w.roof.frame().mid + Vector3.UP * 8.0
	var deck: Dictionary = main.tool.pick_building(origin, Vector3.DOWN)
	check(deck.get("wall") == w and deck.get("surface") == "roof" and absf(deck.point.y - w.roof.height_at(origin.x, origin.z)) < 0.01, "the flat deck stops the ray above the lower roof")
	main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": before})
	w.lay_now()


func _thatched_eave(near: Wall, far: Wall) -> void:
	main.world.submit({"op": "reshape", "of": "walls", "id": far.id, "data": {"points": PackedVector3Array(WallLayout.rectangle(main.world.terrain.ground(-4, 0), main.world.terrain.ground(4, 0), 8.0))}})
	main.world.submit({"op": "reshape", "of": "walls", "id": near.id, "data": {"roof": {"thatch": true}}})
	for wall: Wall in main.tool.walls:
		wall.lay_now()
	var roof := near.roof
	var f := roof.frame()
	var origin: Vector3 = f.mid + f.across * (roof.eave() + RoofLayout.THATCH_EAVE * 0.5) + Vector3.UP * 5.0
	var mesh := TriangleMesh.new()
	mesh.create_from_faces(roof.coat[Mesh.ARRAY_VERTEX])
	var visible := mesh.intersect_ray(origin, Vector3.DOWN)
	check(not visible.is_empty() and far.roof.ray_hit(origin, Vector3.DOWN) < INF, "visible thatch eave overlaps a farther roof along the ray: visible %s far %s origin %s" % [visible, far.roof.ray_hit(origin, Vector3.DOWN), origin])
	if visible.is_empty():
		return
	var picked: Dictionary = main.tool.pick_building(origin, Vector3.DOWN, true)
	check(picked.get("wall") == near and picked.point.distance_to(visible.position) < 0.01, "the visible thatch eave occludes the farther roof")
	check(main.fitting_tool.aim(Hand.Tool.DECORATIONS, origin, Vector3.DOWN).get("wall") == near, "decorations stop on thatch beyond the tiled bed")
	check(main.palette_tool.aim_style(origin, Vector3.DOWN).get("id") == near.id, "style stops on the thatch eave")
	check(main.delete_tool.aim(origin, Vector3.DOWN).get("wall") == near, "delete stops on the thatch eave")
	var teleported: Dictionary = main.rig.solid_hit.call(origin, Vector3.DOWN, 30.0)
	check(not teleported.is_empty() and teleported.point.distance_to(visible.position) < 0.01, "teleport stops on the visible thatch")
	await _grab(near, origin)
	await _capture("thatch-overlapping-roofs", f.mid + Vector3(10, 6, 12), f.mid - Vector3.UP * 2.0)


func _grab(near: Wall, origin: Vector3) -> void:
	var hand: Hand = main.rig.right
	hand.tool = Hand.Tool.WALLS
	hand.held_still = false
	var tracker := XRControllerTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = &"right_hand"
	XRServer.add_tracker(tracker)
	tracker.set_pose(&"aim", main.rig.global_transform.affine_inverse() * Transform3D(Basis.looking_at(Vector3(0.0001, -1, 0)), origin), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	for frame in 3:
		await process_frame
	Buttons.injected["%s/%s" % [hand.tracker, Controls.input("grab", hand.tracker)]] = true
	for frame in 3:
		await process_frame
	check(main.tool.held == near and main.tool.mason(hand).took_roof, "grip grabs the near roof, not the roof behind it")
	Buttons.injected.clear()
	for frame in 3:
		await process_frame
	XRServer.remove_tracker(tracker)
