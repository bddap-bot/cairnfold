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
		var half := 0.1 if layout.fence else WallLayout.THICKNESS * 0.5
		for i in n if layout.closed else n - 1:
			var j := (i + 1) % n
			var a := layout.samples[i]
			var b := layout.samples[j]
			var edge := b - a
			var length := Vector2(edge.x, edge.z).length()
			if length < 1e-6:
				continue
			var x := Vector3(edge.x, 0, edge.z) / length
			var z := x.cross(Vector3.UP)
			var slope := edge.y / length
			var offset := origin - a
			var ox := offset.dot(x)
			var dx := dir.dot(x)
			var local := Vector3(ox, offset.y - slope * ox, offset.dot(z))
			var direction := Vector3(dx, dir.y - slope * dx, dir.dot(z))
			var under := maxf(layout.depths[i], layout.depths[j]) if layout.depths.size() == n else 0.0
			var height := layout.height + layout.top_rise()
			var box := AABB(Vector3(0, -under, -half), Vector3(length, height + under, half * 2.0))
			var hit: Variant = local if box.has_point(local) else box.intersects_ray(local, direction)
			if hit == null:
				continue
			var t: float = (hit - local).dot(direction) / direction.length_squared()
			if layout.hides(origin + dir * t):
				continue
			if t >= best.get("along", INF):
				continue
			var end := layout.lengths[j] if j > 0 else layout.length()
			var arched := through_arches and _open(i, end, length, local + direction * t)
			if arched:
				var open := func(at: float) -> bool: return _open(i, end, length, local + direction * at)
				t = _first_solid(open, t, _exit(box, local, direction))
				if t == INF or layout.hides(origin + dir * t):
					continue
			if t < best.get("along", INF):
				var at: Vector3 = local + direction * t
				var face := Rig.box_normal(box, at)
				var side := arched or Rig.side(x * face.x + (Vector3.UP - x * slope) * face.y + z * face.z)
				best = {"along": t, "point": origin + dir * t, "s": lerpf(layout.lengths[i], end, clampf(at.x / length, 0.0, 1.0)), "distance": 0.0, "side": side}
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
