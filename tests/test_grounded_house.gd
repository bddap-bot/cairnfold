extends "res://../tests/support/suite.gd"


func _init() -> void:
	for ground in [Terrain.flat, _slope]:
		for round in [false, true]:
			for foundation in WallLayout.Foundation.values():
				for action in ["stretch", "lift"]:
					for rise in [0.0, 1.5]:
						_edit(ground, round, foundation, action, rise)
	finish()


func _slope(x: float, z: float) -> float:
	return 0.12 * x + 0.06 * z


func _layout(d: Dictionary, ground: Callable) -> WallLayout:
	var w := WallLayout.new()
	w.set_data(d)
	w.cover = WallLayout.Cover.ROOF
	w.build(ground)
	return w


func _edit(ground: Callable, round: bool, foundation: int, action: String, rise: float) -> void:
	var start := WallTool.stance(Vector3.ZERO, 0.0, round)
	start.grounded = true
	start.height = 2.4
	start.rise = rise
	var d := wall_data({"points": PackedVector3Array(WallTool.outline(start)), "height": start.height, "rise": rise,
		"closed": true, "foundation": foundation, "openings": PackedVector4Array([WallLayout.archway(2.0)]),
		"roof": {"kind": RoofLayout.Kind.CONE if round else RoofLayout.Kind.GABLE, "radius": start.size.x * 0.5,
			"center": start.center, "pitch": start.pitch, "curve": start.curve, "overhang": start.overhang,
			"chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "hatches": PackedVector2Array()}})
	var before := _layout(d, ground)
	var from: Array[Transform3D] = [Transform3D(Basis(), Vector3(-1, 1, 0)), Transform3D(Basis(), Vector3(1, 1, 0))]
	var to: Array[Transform3D] = [from[0], Transform3D(Basis(), Vector3(1, 3.4, 0))]
	var changed := WallTool.resize(start, from, to) if action == "stretch" else WallTool.carry(start, from[0], Transform3D(Basis(), from[0].origin + Vector3.UP * 2.4), 1.0)
	var after := _layout(World.reshaped(d, WallTool.reshape_house(d, changed)), ground)
	var label := "%s round=%s foundation=%s slope=%s" % [action, round, foundation, ground == _slope]
	var lifted := action == "lift"
	check(is_equal_approx(after.height, 2.4 if lifted else 4.8), label + ": lift keeps wall height; stretch grows it")
	check(is_equal_approx(after.rise, rise + 2.4 if lifted else rise), label + ": only lift changes floor elevation")
	var expected_floor := maxf(before.floor_y, before.samples[0].y + WallLayout.SINK + 2.4) if lifted else before.floor_y
	check(is_equal_approx(after.floor_y, expected_floor), label + ": floor follows lift and stays fixed under stretch")
	if not lifted:
		check(after.samples == before.samples and after.plinths == before.plinths and after.depths == before.depths, label + ": stretch keeps the terrain foundation fixed")
	check(is_equal_approx(after.samples[0].y + after.height, before.samples[0].y + before.height + 2.4), label + ": the roof seat rises by 2.4 m")
	check(is_equal_approx(after.apertures[0].sill + after.samples[0].y, after.floor_y), label + ": the doorway opens at the floor")
	if lifted:
		for station in after.stations():
			var foot: Vector3 = after.frame_at(station).point
			var lowest := INF
			for piece in after.stones:
				if piece.kind in ["block", "plaster", "pier", "pillar", "post"] and absf(after.offset(piece.s, station)) <= piece.size.x * 0.5 + 0.02:
					lowest = minf(lowest, piece.xform.origin.y - piece.size.y * 0.5)
			check(lowest <= ground.call(foot.x, foot.z) + 0.05, label + ": foundation reaches the terrain at every support station")
	for side in [-1.0, 1.0]:
		for along in [0.5, before.length() * 0.4, before.length() * 0.8]:
			var item := Vector4(along, side * 2.0, 0.0, ClutterLayout.style("Rain barrel"))
			var original: Variant = before.clutter_frame(item, ground)
			var placed: Variant = after.clutter_frame(item, ground)
			if placed == null:
				continue
			if Geometry2D.is_point_in_polygon(Vector2(placed.origin.x, placed.origin.z), after.floor_outline):
				check(is_equal_approx(placed.origin.y, after.floor_y), label + ": interior furniture stays on the floor")
			else:
				check(is_equal_approx(placed.origin.y, ground.call(placed.origin.x, placed.origin.z)), label + ": exterior furniture sits on its own terrain")
				check(placed == original, label + ": exterior furniture stays grounded after the edit")
	check(is_equal_approx(after.floor_under(Vector3(0, after.floor_y + 1.6, 0)), after.floor_y), label + ": walking uses the floor")
