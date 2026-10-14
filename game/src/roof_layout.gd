class_name RoofLayout
extends RefCounted

## Lays the tiles of a roof resting on a closed wall: a gable over a house's rectangle or a cone over a
## round tower. Pitch is the ridge's rise above the wall top; curvature bows the slopes out (positive)
## or sags them into swept eaves (negative). Pure data, like WallLayout.

enum Kind { GABLE, CONE }

const OVERHANG := 0.3
const GABLE_OVERHANG := 0.25
const ROW := 0.24
const TILE := Vector3(0.27, 0.05, 0.36)
const PITCH := Vector2(0.4, 6.0)
const CURVE := 1.0
const PROFILE_STEPS := 8

var kind := Kind.GABLE
## For a gable, the corners from WallLayout.rectangle: the ridge runs along the first side's direction.
var corners: Array[Vector3] = []
## For a cone: the axis on the ground and the radius of the wall's centre line.
var center := Vector3.ZERO
var radius := 2.0
## Height of the wall top the roof rests on.
var base := 0.0
var pitch := 2.0
var curve := 0.0
var seed := 1

var tiles: Array[Dictionary] = []
## The surface triangles from the last build, kept for pointing.
var faces := PackedVector3Array()
var bounds := AABB()


## Rise above the wall top at `u`, 0 at the walls' outer faces and 1 at the ridge; below 0 (the overhang) it carries on straight.
func rise(u: float) -> float:
	if u < 0.0:
		return pitch * u * (1.0 + curve * 0.25 * PI)
	return pitch * (u + curve * 0.25 * sin(PI * u))


## Distance from the ridge (or axis) out to the walls' outer faces, where the roof rests.
func half_span() -> float:
	var inner := radius if kind == Kind.CONE else corners[0].distance_to(corners[3]) * 0.5
	return inner + WallLayout.THICKNESS * 0.5


func ridge_length() -> float:
	return corners[0].distance_to(corners[1])


## Ridge axis, across axis and the centre of the footprint, on the ground plane at the wall top.
func frame() -> Dictionary:
	if kind == Kind.CONE:
		return {"along": Vector3.RIGHT, "across": Vector3.BACK, "mid": Vector3(center.x, base, center.z)}
	var along := (corners[1] - corners[0])
	along.y = 0.0
	var across := (corners[3] - corners[0])
	across.y = 0.0
	var mid := (corners[0] + corners[2]) * 0.5
	return {"along": along.normalized(), "across": across.normalized(), "mid": Vector3(mid.x, base, mid.z)}


## Horizontal distance out from the ridge (or axis) at which the eave ends.
func eave() -> float:
	return half_span() + OVERHANG


## Points down one slope, from the ridge out to the eave: Vector2(distance out, height above base).
func profile(steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var hs := half_span()
	for i in steps + 1:
		var x := eave() * i / steps
		out.append(Vector2(x, rise(1.0 - x / hs)))
	return out


func build() -> void:
	faces = surface()
	bounds = AABB(faces[0], Vector3.ZERO)
	for p in faces:
		bounds = bounds.expand(p)
	tiles.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hue := rng.randf_range(-0.04, 0.04)
	var rows := _rows()
	for i in rows.size():
		var row := rows[i]
		if kind == Kind.GABLE:
			_lay_gable_row(row, 0.5 if i % 2 == 1 else 0.0, hue, rng)
		else:
			_lay_cone_row(row, hue, rng)
	if kind == Kind.GABLE:
		_lay_ridge(hue, rng)
	else:
		var f := frame()
		_add(Transform3D(Basis().scaled(Vector3(0.16, 0.5, 0.16)), f.mid + Vector3.UP * (pitch + 0.2)), "finial", Color(0.6, 0.56, 0.5), 1.0)


## Tile rows as {x, y, slope}, eave first, spaced along the curved slope.
func _rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hs := half_span()
	var x := eave()
	var stop := 0.12 if kind == Kind.CONE else 0.08
	while x > stop:
		var y := rise(1.0 - x / hs)
		var dy := (rise(1.0 - (x - 0.01) / hs) - y) / 0.01
		out.append({"x": x, "y": y, "slope": atan(dy)})
		var step := ROW * cos(atan(dy))
		x -= step
	return out


func _lay_gable_row(row: Dictionary, stagger: float, hue: float, rng: RandomNumberGenerator) -> void:
	var f := frame()
	var length := ridge_length() + WallLayout.THICKNESS + GABLE_OVERHANG * 2.0
	var n := maxi(1, ceili(length / TILE.x))
	for side in [-1.0, 1.0]:
		var out: Vector3 = f.across * side
		var basis := _slope_basis(out, row.slope)
		for i in n + (1 if stagger > 0.0 else 0):
			var t := (i + 0.5 - stagger) / n - 0.5
			var width := 1.0
			if absf(t) > 0.5 - 0.5 / n + 1e-4:
				width = 0.5
				t = signf(t) * (0.5 - 0.25 / n)
			var p: Vector3 = f.mid + f.along * t * length + out * row.x + Vector3.UP * (row.y + TILE.y * 0.5)
			_tile(p, basis, hue, rng, width * length / n / TILE.x)


func _lay_cone_row(row: Dictionary, hue: float, rng: RandomNumberGenerator) -> void:
	var f := frame()
	var n := maxi(4, ceili(TAU * row.x / TILE.x))
	var twist := rng.randf() * TAU
	for i in n:
		var a := twist + TAU * i / n
		var out := Vector3(cos(a), 0.0, sin(a))
		var basis := _slope_basis(out, row.slope)
		var width := minf(1.0, TAU * row.x / n / TILE.x * 1.08)
		_tile(f.mid + out * row.x + Vector3.UP * (row.y + TILE.y * 0.5), basis, hue, rng, width)


## A tile's frame on a slope facing `out`: x along the row, y off the roof, z down the slope.
static func _slope_basis(out: Vector3, slope: float) -> Basis:
	var down := (out * cos(slope) - Vector3.UP * sin(slope)).normalized()
	var x := Vector3.UP.cross(down).normalized()
	return Basis(x, down.cross(x), down)


func _lay_ridge(hue: float, rng: RandomNumberGenerator) -> void:
	var f := frame()
	var length := ridge_length() + WallLayout.THICKNESS + GABLE_OVERHANG * 2.0
	var n := maxi(1, ceili(length / 0.32))
	for i in n:
		var t := (i + 0.5) / n - 0.5
		var p: Vector3 = f.mid + f.along * t * length + Vector3.UP * (pitch + 0.04)
		var basis := Basis(f.along, Vector3.UP, f.across).scaled_local(Vector3(length / n * 1.02, 0.14, 0.26))
		_add(Transform3D(basis, p), "ridge", _clay(hue, rng) * 0.88, 0.95)


func _tile(p: Vector3, basis: Basis, hue: float, rng: RandomNumberGenerator, width := 1.0) -> void:
	var b := basis.rotated(basis.x, -0.05) * Basis.from_euler(Vector3(0.0, rng.randf_range(-0.04, 0.04), rng.randf_range(-0.03, 0.03)))
	_add(Transform3D(b.scaled_local(Vector3(TILE.x * width, TILE.y, TILE.z)), p), "tile", _clay(hue, rng), 1.0)


func _clay(hue: float, rng: RandomNumberGenerator) -> Color:
	var warm := rng.randf_range(-0.05, 0.05) + hue
	return Color(0.72 + warm, 0.4 + warm * 0.4, 0.28 - warm) * rng.randf_range(0.82, 1.08)


func _add(xform: Transform3D, what: String, color: Color, ao: float) -> void:
	tiles.append({"xform": xform, "color": color, "kind": what, "ao": ao, "variant": tiles.size() % 3})


## The roof's surface as triangles, eave to ridge, for pointing at it.
func surface() -> PackedVector3Array:
	var tris := PackedVector3Array()
	var f := frame()
	var prof := profile(PROFILE_STEPS)
	if kind == Kind.CONE:
		var seg := 16
		for k in seg:
			var a0 := Vector3(cos(TAU * k / seg), 0, sin(TAU * k / seg))
			var a1 := Vector3(cos(TAU * (k + 1) / seg), 0, sin(TAU * (k + 1) / seg))
			for i in prof.size() - 1:
				_quad(tris, f.mid, a0, a1, prof[i], prof[i + 1])
		return tris
	var half: Vector3 = f.along * (ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5 + GABLE_OVERHANG)
	for side in [-1.0, 1.0]:
		var out: Vector3 = f.across * side
		for i in prof.size() - 1:
			var a: Vector3 = f.mid + out * prof[i].x + Vector3.UP * prof[i].y
			var b: Vector3 = f.mid + out * prof[i + 1].x + Vector3.UP * prof[i + 1].y
			tris.append_array([a - half, a + half, b + half, a - half, b + half, b - half])
	return tris


static func _quad(tris: PackedVector3Array, mid: Vector3, d0: Vector3, d1: Vector3, p: Vector2, q: Vector2) -> void:
	var a := mid + d0 * p.x + Vector3.UP * p.y
	var b := mid + d1 * p.x + Vector3.UP * p.y
	var c := mid + d1 * q.x + Vector3.UP * q.y
	var d := mid + d0 * q.x + Vector3.UP * q.y
	tris.append_array([a, b, c, a, c, d])


## The two triangular gable ends between the end walls' tops and the slopes, as triangles.
func gables() -> PackedVector3Array:
	var tris := PackedVector3Array()
	if kind != Kind.GABLE:
		return tris
	var f := frame()
	var prof := profile(PROFILE_STEPS)
	var hs := half_span()
	for end in [-1.0, 1.0]:
		var at: Vector3 = f.mid + f.along * end * ridge_length() * 0.5
		for side in [-1.0, 1.0]:
			var out: Vector3 = f.across * side
			for i in prof.size() - 1:
				if prof[i].x >= hs:
					break
				var x1 := minf(prof[i + 1].x, hs)
				var a: Vector3 = at + out * prof[i].x
				var b: Vector3 = at + out * x1
				tris.append_array([a, a + Vector3.UP * prof[i].y, b + Vector3.UP * rise(1.0 - x1 / hs), a, b + Vector3.UP * rise(1.0 - x1 / hs), b])
	return tris


## Nearest distance along a ray to the roof, or INF.
func ray_hit(origin: Vector3, dir: Vector3) -> float:
	var best := INF
	if faces.is_empty() or bounds.grow(0.1).intersects_ray(origin, dir) == null:
		return best
	for i in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, dir, faces[i], faces[i + 1], faces[i + 2])
		if hit != null:
			best = minf(best, origin.distance_to(hit))
	return best
