extends "res://../tests/support/suite.gd"

## A ray meets a wall where it would were every stretch of it tested, whatever stretches the pick skips: along a hilly
## wall, rising or falling, from beside it, behind it or inside it, through arches or not:
## godot4 --headless --path game --script ../tests/test_wall_ray_skip.gd


class EveryStretch extends Wall:
	func ray_hit(origin: Vector3, dir: Vector3, through_arches := false) -> Dictionary:
		if not _ruin_pick.is_empty():
			return _ruin_hit(origin, dir)
		var best := {}
		var n := layout.samples.size()
		for i in n if layout.closed else n - 1:
			best = _stretch_hit(i, origin, dir, through_arches, best, Vector2.ZERO)
		return best


func _initialize() -> void:
	var hills := func(x: float, z: float) -> float: return sin(x * 0.3) * 2.0 + cos(z * 0.2) * 1.5
	var layouts: Array[WallLayout] = []
	var ring := WallLayout.new()
	ring.points = WallLayout.circle(Vector3.ZERO, 12.0)
	ring.closed = true
	layouts.append(ring)
	var open := WallLayout.new()
	var points: Array[Vector3] = []
	for i in 30:
		points.append(Vector3(i * 1.3 - 20, 0, sin(i * 0.4) * 6.0))
	open.points = points
	open.height = 1.6
	layouts.append(open)
	var fence := WallLayout.new()
	fence.points = [Vector3(-5, 0, -5), Vector3(5, 0, 8), Vector3(9, 0, -3)] as Array[Vector3]
	fence.fence = true
	layouts.append(fence)
	var arched := WallLayout.new()
	arched.points = [Vector3(-8, 0, 3), Vector3(8, 0, 4)] as Array[Vector3]
	arched.openings.append_array([4.0, 10.0].map(WallLayout.archway))
	layouts.append(arched)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var differ := []
	var hits := 0
	for l in layouts:
		l.resample(hills)
		l.build(hills)
		var skipping := Wall.new(1, null, Terrain.new())
		skipping.layout = l
		var every := EveryStretch.new(1, null, Terrain.new())
		every.layout = l
		for k in 5000:
			var o := Vector3(rng.randf_range(-25, 25), rng.randf_range(-1.0, 5.0), rng.randf_range(-25, 25))
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 0.6), rng.randf_range(-1, 1))
			var m := rng.randi() % (l.samples.size() - 1)
			var q := l.samples[m]
			if k % 3 == 1:
				o = q + Vector3(rng.randf_range(-6, 6), rng.randf_range(0.0, 2.5), rng.randf_range(-6, 6))
				d = q + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, 2.0), rng.randf_range(-0.5, 0.5)) - o
			elif k % 3 == 2:
				var along := l.samples[m + 1] - q
				o = q + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.5, 4.0), rng.randf_range(-0.6, 0.6))
				d = Vector3(along.x, 0, along.z).normalized() * signf(rng.randf() - 0.5) + Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.1, 0.1))
			if k % 50 == 0:
				d = Vector3(rng.randf_range(-1e-4, 1e-4), -1, rng.randf_range(-1e-4, 1e-4))
			d = d.normalized()
			var arches := k % 2 == 0
			var got := skipping.ray_hit(o, d, arches)
			var want := every.ray_hit(o, d, arches)
			hits += int(not want.is_empty())
			if got != want and differ.size() < 5:
				differ.append([var_to_str(o), var_to_str(d), arches, got, want])
		skipping.free()
		every.free()
	check(hits > 2000, "the rays meet the walls often: %d" % hits)
	check(differ.is_empty(), "a ray skipping stretches meets the wall where every stretch tested does: %s" % [differ])
	finish()
