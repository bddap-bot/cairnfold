extends SceneTree

## Headless checks of the ranges round the garden: godot4 --headless --path game --script ../tests/test_mountains.gd

const GARDEN_CORNER := Terrain.SIZE * 0.5 * sqrt(2.0)
## Two eyes 64 mm apart see a point this far off within a fortieth of a degree of each other: as far as the sky.
const STEREO_FAR := 140.0

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := Mountains.arrays(false)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	_the_ranges_read_as_far_from_anywhere_in_the_garden(verts)
	_the_eye_and_the_sun_reach_past_them(verts)
	_every_face_faces_the_garden(verts, normals, indices)
	_slopes_shade_smoothly_and_ridges_crisply(verts, normals, indices)
	_the_sun_rises_and_sets_through_a_pass()
	_they_cost_a_few_thousand_triangles(verts, indices)
	var l := Mountains.arrays(true)
	_every_face_faces_the_garden(l[Mesh.ARRAY_VERTEX], l[Mesh.ARRAY_NORMAL], l[Mesh.ARRAY_INDEX])
	_the_lake_stands_under_the_meadow_and_over_the_feet(l[Mesh.ARRAY_VERTEX])
	_the_lake_reaches_past_the_first_ridge()
	_the_water_mirrors_the_ridges_as_they_stand()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _flat(p: Vector3) -> float:
	return Vector2(p.x, p.z).length()


func _the_ranges_read_as_far_from_anywhere_in_the_garden(verts: PackedVector3Array) -> void:
	var nearest := INF
	for p in verts:
		if _flat(p) > GARDEN_CORNER + 1.0:
			nearest = minf(nearest, _flat(p))
	_check(nearest - GARDEN_CORNER > STEREO_FAR, "past the meadow, the ground stands %.0f m from the garden's corner" % (nearest - GARDEN_CORNER))


func _the_eye_and_the_sun_reach_past_them(verts: PackedVector3Array) -> void:
	var farthest := 0.0
	for p in verts:
		farthest = maxf(farthest, Vector3(_flat(p) + GARDEN_CORNER, p.y, 0).length())
	_check(Look.DISC_DISTANCE > farthest, "the sun's disc stands in front of a ridge %.0f m off" % farthest)
	_check(Rig.FAR > Look.DISC_DISTANCE * 1.05, "the eye's far clip cuts the sun's disc")


func _front(verts: PackedVector3Array, indices: PackedInt32Array, i: int) -> Vector3:
	return (verts[indices[i + 2]] - verts[indices[i]]).cross(verts[indices[i + 1]] - verts[indices[i]]).normalized()


func _every_face_faces_the_garden(verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	var away := 0
	for i in range(0, indices.size(), 3):
		var front := _front(verts, indices, i)
		if front.dot(Mountains.SEEN_FROM - verts[indices[i]]) <= 0.0:
			away += 1
		for k in 3:
			if front.dot(normals[indices[i + k]]) <= 0.0:
				away += 1
	_check(away == 0, "%d triangles or their corners' normals face away from the garden" % away)


## Corners of faces folding sharper than the crease never share a normal, so the ridges and crags keep their edge,
## while most corners round a point share one, so the slopes between shade smoothly.
func _slopes_shade_smoothly_and_ridges_crisply(verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	var crease := cos(deg_to_rad(Mountains.CREASE))
	var corners_at := {}
	for i in indices.size():
		var p := verts[indices[i]]
		if not corners_at.has(p):
			corners_at[p] = []
		corners_at[p].append(i)
	var shared := 0
	var crisp := 0
	var blurred := 0
	for p: Vector3 in corners_at:
		for i: int in corners_at[p]:
			for j: int in corners_at[p]:
				if i / 3 >= j / 3:
					continue
				var sharp := _front(verts, indices, i - i % 3).dot(_front(verts, indices, j - j % 3)) < crease
				crisp += 1 if sharp else 0
				if indices[i] == indices[j]:
					shared += 1
					blurred += 1 if sharp else 0
	_check(blurred == 0, "%d corners smooth over a sharp fold" % blurred)
	_check(crisp > 0, "no fold is sharp enough to keep an edge")
	_check(shared > 4 * crisp, "%d corner pairs share a normal, %d keep an edge" % [shared, crisp])
	_check(verts.size() < indices.size() / 2, "%d vertices for %d corners" % [verts.size(), indices.size()])


func _the_sun_rises_and_sets_through_a_pass() -> void:
	var eye := Vector3(0, Terrain.base_at(0, 0) + Look.STANDING, 0)
	var noises := Mountains.RANGES.map(Mountains.noise_for)
	for rising in [true, false]:
		var first := -1.0
		for i in 1001:
			var t := i / 1000.0 if rising else 1.0 - i / 1000.0
			var toward := Daylight.toward_sun(t)
			if toward.y <= 0.0:
				continue
			var az := atan2(toward.z, toward.x)
			var clear := true
			for k in Mountains.RANGES.size():
				var r: Dictionary = Mountains.RANGES[k]
				var top := Vector3(cos(az) * r.radius, Mountains.foot_high(false) + Mountains.ridge(r, noises[k], az), sin(az) * r.radius)
				clear = clear and toward.y > (top - eye).normalized().y
			if clear:
				first = Daylight.elevation(t)
				break
		_check(first > 0.0 and first < 8.0, "the sun first clears the ridges at %.1f° %s" % [first, "rising" if rising else "setting"])


func _they_cost_a_few_thousand_triangles(verts: PackedVector3Array, indices: PackedInt32Array) -> void:
	_check(indices.size() / 3 < 6000, "the ranges take %d triangles" % (indices.size() / 3))
	print("mountains: %d triangles, %d vertices" % [indices.size() / 3, verts.size()])


## The water stays under every point of the meadow's edge, so it never floods the garden, and over the bank's foot and
## every range's foot, so it meets the bank and the ranges with no ground between.
func _the_lake_stands_under_the_meadow_and_over_the_feet(verts: PackedVector3Array) -> void:
	var half := Terrain.SIZE * 0.5
	var lowest := INF
	for i in Terrain.VERTS:
		for p in [Vector2(-half + i, -half), Vector2(-half + i, half), Vector2(-half, -half + i), Vector2(half, -half + i)]:
			lowest = minf(lowest, Terrain.base_at(p.x, p.y))
	_check(Mountains.LAKE < lowest - 0.5, "the lake at %.1f m floods the meadow's edge at %.1f m" % [Mountains.LAKE, lowest])
	var dry := 0
	for p in verts:
		var out := maxf(absf(p.x), absf(p.z)) - half
		if out > 1.0 and out < Mountains.BANK + 1.0:
			dry += 1 if p.y >= Mountains.LAKE else 0
	_check(Mountains.foot_high(true) < Mountains.LAKE, "the ranges' feet stand at %.1f m, over the lake" % Mountains.foot_high(true))
	_check(dry == 0, "%d points of the bank's foot stand out of the water" % dry)


func _the_lake_reaches_past_the_first_ridge() -> void:
	var water: PackedVector3Array = Mountains.lake_arrays()[Mesh.ARRAY_VERTEX]
	var reach := INF
	for p in water:
		_check(is_equal_approx(p.y, Mountains.LAKE), "water at %.2f m, not the lake's %.2f m" % [p.y, Mountains.LAKE])
		if _flat(p) > Terrain.SIZE:
			reach = minf(reach, _flat(p))
	_check(reach > Mountains.RANGES[0].radius, "the water stops %.0f m out, short of the first ridge" % reach)
	_check(water.size() / 3 < 400, "the lake takes %d triangles" % (water.size() / 3))


func _the_water_mirrors_the_ridges_as_they_stand() -> void:
	var img := Mountains.ridge_image()
	var top: float = Mountains.RANGES[Mountains.RANGES.size() - 1].high
	var worst := 0.0
	for k in Mountains.RANGES.size():
		var r: Dictionary = Mountains.RANGES[k]
		var noise := Mountains.noise_for(r)
		for i in range(0, Mountains.RIDGE_SAMPLES, 7):
			var az := TAU * i / Mountains.RIDGE_SAMPLES
			var mirrored: float = img.get_pixel(i, 0)[k] * top + Mountains.LAKE
			worst = maxf(worst, absf(mirrored - Mountains.foot_high(true) - Mountains.ridge(r, noise, az)))
	_check(worst < 0.05, "the mirrored ridge strays %.2f m from the ridge" % worst)
