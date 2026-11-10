extends "res://../tests/support/suite.gd"

## A curved tile roof seen from outside shows clay everywhere, never the torching under it: rays aimed at its slopes
## from above, from the side and slantwise along the ridge meet a tile first, on small and middling houses at steep
## pitches with the slopes bowed and sagged as far as a pull takes them.

const HouseLeaks = preload("res://../tests/support/house_leaks.gd")
const VIEWS := [Vector3(0, 1, 0), Vector3(0, 0.5, 1), Vector3(0, 0.5, -1), Vector3(1, 0.3, 0), Vector3(1, 0.3, 0.5), Vector3(1, 0.3, -0.5)]


func _run() -> void:
	var probes := 0
	for size in [Vector2(3, 2), Vector2(4, 3)]:
		for pitch in [3.0, 5.0]:
			for curve in [-RoofLayout.CURVE, -0.8, 0.8, RoofLayout.CURVE]:
				for seed_value in [1, 2]:
					probes += _case(size, pitch, curve, seed_value)
	print("tests: roof cover: %d probes" % probes)
	finish()


func _case(size: Vector2, pitch: float, curve: float, seed_value: int) -> int:
	var r := RoofLayout.new()
	r.pitch = pitch
	r.curve = curve
	r.seed = seed_value
	var w := WallLayout.new()
	w.seed = seed_value
	w.points = WallLayout.rectangle(Vector3.ZERO, Vector3(size.x, 0, 0), size.y)
	w.closed = true
	w.height = 2.4
	w.cover = WallLayout.Cover.ROOF
	w.gable = r
	w.build(Terrain.flat)
	var kinds := Wall.kinds()
	var packed := Wall.pack_roof(w, r, kinds, Palette.plain())
	var tiles := TriangleMesh.new()
	assert(tiles.create_from_faces(HouseLeaks.instances(packed.tiles, kinds[Wall.Part.TILE])))
	var torching := TriangleMesh.new()
	assert(torching.create_from_faces(r.torching_faces))
	var f := r.frame()
	var hs := r.half_span()
	var probes := 0
	var gaps := 0
	for side in [-1.0, 1.0]:
		for view: Vector3 in VIEWS:
			var dir: Vector3 = -(f.across * side * view.x + Vector3.UP * view.y + f.along * view.z).normalized()
			for i in 60:
				for j in 30:
					var p: Vector3 = f.mid + f.along * r.ridge_length() * 0.9 * (i / 59.0 - 0.5) + f.across * side * hs * (0.05 + 0.9 * j / 29.0)
					p.y = r.height_at(p.x, p.z)
					var from := p - dir * 5.0
					var under := torching.intersect_ray(from, dir)
					if under.is_empty():
						continue
					probes += 1
					var over := tiles.intersect_ray(from, dir)
					if over.is_empty() or from.distance_to(over.position) > from.distance_to(under.position):
						gaps += 1
	check(gaps == 0, "a %s house's roof at pitch %.1f, curve %.2f, seed %d shows torching through %d of %d rays" % [size, pitch, curve, seed_value, gaps, probes])
	return probes
