extends SceneTree

## Headless checks of the ranges round the garden: godot4 --headless --path game --script ../tests/test_mountains.gd

const GARDEN_CORNER := Terrain.SIZE * 0.5 * sqrt(2.0)
## Two eyes 64 mm apart see a point this far off within a fortieth of a degree of each other: as far as the sky.
const STEREO_FAR := 140.0

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := Mountains.arrays()
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	_the_ranges_read_as_far_from_anywhere_in_the_garden(verts)
	_the_eye_and_the_sun_reach_past_them(verts)
	_every_face_faces_the_garden(verts, normals)
	_the_sun_rises_and_sets_through_a_pass()
	_they_cost_a_few_thousand_triangles(verts)
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


func _every_face_faces_the_garden(verts: PackedVector3Array, normals: PackedVector3Array) -> void:
	var away := 0
	for i in range(0, verts.size(), 3):
		var front := (verts[i + 2] - verts[i]).cross(verts[i + 1] - verts[i])
		if front.dot(Mountains.SEEN_FROM - verts[i]) <= 0.0 or front.dot(normals[i]) <= 0.0:
			away += 1
	_check(away == 0, "%d triangles face away from the garden" % away)


## Seen from the garden's centre, the sun clears every ridge while it is still low, morning and evening.
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
				var top := Vector3(cos(az) * r.radius, Mountains.PLAIN_HIGH + Mountains.ridge(r, noises[k], az), sin(az) * r.radius)
				clear = clear and toward.y > (top - eye).normalized().y
			if clear:
				first = Daylight.elevation(t)
				break
		_check(first > 0.0 and first < 8.0, "the sun first clears the ridges at %.1f° %s" % [first, "rising" if rising else "setting"])


func _they_cost_a_few_thousand_triangles(verts: PackedVector3Array) -> void:
	_check(verts.size() / 3 < 6000, "the ranges take %d triangles" % (verts.size() / 3))
