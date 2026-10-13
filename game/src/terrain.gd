class_name Terrain
extends RefCounted

const SIZE := 160.0
const STEP := 1.0

static var _noise: FastNoiseLite


static func noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 7
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.018
		_noise.fractal_octaves = 3
	return _noise


static func height_at(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var rolling := noise().get_noise_2d(x, z) * 1.6 + sin(x * 0.045) * cos(z * 0.06) * 0.7
	var rim := smoothstep(34.0, 75.0, r) * (9.0 + noise().get_noise_2d(z * 1.7, x * 1.7) * 6.0)
	return rolling + rim


static func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## First hit of a ray with the ground, or null.
static func raycast(origin: Vector3, dir: Vector3, max_dist := 80.0) -> Variant:
	var step := 0.25
	var prev := 0.0
	var t := 0.0
	while t <= max_dist:
		var p := origin + dir * t
		if p.y <= height_at(p.x, p.z):
			var lo := prev
			var hi := t
			for i in 12:
				var mid := (lo + hi) * 0.5
				var q := origin + dir * mid
				if q.y <= height_at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			return origin + dir * hi
		prev = t
		t += step * (1.0 + t * 0.03)
	return null


static func build_mesh() -> ArrayMesh:
	var n := int(SIZE / STEP)
	var half := SIZE * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tint := FastNoiseLite.new()
	tint.seed = 11
	tint.frequency = 0.05
	for j in n + 1:
		for i in n + 1:
			var x := -half + i * STEP
			var z := -half + j * STEP
			var y := height_at(x, z)
			var nrm := normal_at(x, z)
			var lush := clampf(0.5 + tint.get_noise_2d(x, z) * 0.9, 0.0, 1.0)
			st.set_color(Color(lush, clampf(1.0 - nrm.y * 1.4 + 0.25, 0.0, 1.0), 0.0))
			st.set_normal(nrm)
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, y, z))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	return st.commit()
