extends "res://../tests/support/suite.gd"


func _init() -> void:
	var raw: Array[Vector3] = []
	for i in 41:
		raw.append(Vector3(-9 + i * 0.45, 0, -3 + 2 * sin(i * PI / 40) + 0.065 * sin(i * 2.3)))
	var plan := WallPlan.new([], PackedVector3Array(), 42)
	var before := plan.pieces(raw, Terrain.flat)[0]
	var after := plan.pieces(raw, Terrain.flat, true)[0]
	check(after.points[0] == raw[0] and after.points[-1] == raw[-1], "endpoints stay exact")
	check(_roughness(after) < _roughness(before) * 0.6, "curvature jitter reduced: %s -> %s" % [_roughness(before), _roughness(after)])
	check(after.corners().size() == 2, "a gentle curve has only end piers")
	var stable := after.points.duplicate()
	after.resample(Terrain.flat)
	after.build(Terrain.flat)
	check(after.points == stable, "downstream lays do not smooth again")
	var corner: Array[Vector3] = []
	for i in 11:
		corner.append(Vector3(i * 0.4, 0, 0))
	for i in range(1, 11):
		corner.append(Vector3(4, 0, i * 0.4))
	var bent := plan.pieces(corner, Terrain.flat, true)[0]
	check(bent.points.has(Vector3(4, 0, 0)), "sharp corner stays at drawn vertex")
	check(bent.corners().size() == 3, "sharp corner keeps its pier")
	for p in bent.points:
		check(is_zero_approx(p.z) or is_equal_approx(p.x, 4), "corner legs stay straight")
	var long_stroke: Array[Vector3] = []
	for i in 499:
		long_stroke.append(Vector3(i * 0.45, 0, 0.02 * sin(i)))
	var long_wall := plan.pieces(long_stroke, Terrain.flat, true)[0]
	check(long_wall.points.size() <= Commands.MAX_POINTS, "maximum-length committed stroke fits schema")
	print("smoothing: roughness %.5f -> %.5f; points %d -> %d; max-stroke points %d" % [_roughness(before), _roughness(after), before.points.size(), after.points.size(), long_wall.points.size()])
	finish()


func _roughness(w: WallLayout) -> float:
	var total := 0.0
	var previous := 0.0
	for i in range(1, 90):
		var s := w.length() * i / 90.0
		var a: Vector3 = w.point_at(s) - w.point_at(s - 0.2)
		var b: Vector3 = w.point_at(s + 0.2) - w.point_at(s)
		var turn := Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))
		total += absf(turn - previous)
		previous = turn
	return total


