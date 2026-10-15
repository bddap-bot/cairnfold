class_name RoofLayout
extends RefCounted

## Lays the tiles of a roof resting on a closed wall: a gable over a house's rectangle or a cone over a
## round tower. Pitch is the ridge's rise above the wall top; curvature bows the slopes out (positive)
## or sags them into swept eaves (negative). At pitch 0 the roof is a flat stone deck inside the walls,
## whose top style rims it. A gable carries chimneys; a cone can fly a flag from its top.
## Pure data, like WallLayout.

enum Kind { GABLE, CONE }

const OVERHANG := 0.3
const GABLE_OVERHANG := 0.25
const ROW := 0.24
const TILE := Vector3(0.27, 0.05, 0.36)
const PITCH := Vector2(0.0, 6.0)
## A pitch pulled below this lands flat.
const FLAT_SNAP := 0.4
const SLAB := Vector3(0.7, 0.1, 0.5)
## How far the deck runs in under the cap's inner lip, and how far below the cap's top it lies.
const DECK_TUCK := 0.06
const DECK_DROP := 0.03
const CURVE := 1.0
const PROFILE_STEPS := 8
const STACK_WIDTH := 0.66

## The clay roof tiles are laid in, before each roof's hue and each tile's variation.
const CLAY := Color(0.72, 0.4, 0.28)
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
## Chimneys on a gable: metres along the ridge from its middle and across it, toward a slope's eave.
var chimneys: Array[Vector2] = []
## A cone flies a flag from its top instead of a finial.
var flag := false

var tiles: Array[Dictionary] = []
var cloths: Array[Dictionary] = []
## The surface triangles from the last build, kept for pointing.
var faces := PackedVector3Array()
var gable_faces := PackedVector3Array()
var bounds := AABB()


## What the roof is laid from, copied to lay on another thread.
func inputs() -> RoofLayout:
	var r := RoofLayout.new()
	r.kind = kind
	r.center = center
	r.radius = radius
	r.pitch = pitch
	r.curve = curve
	r.seed = seed
	r.chimneys = chimneys.duplicate()
	r.flag = flag
	return r


func same_inputs(other: RoofLayout) -> bool:
	var a := inputs()
	var b := other.inputs()
	for p in a.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and a.get(p.name) != b.get(p.name):
			return false
	return true


## Takes what `built` laid, as if `build` had run here.
func adopt(built: RoofLayout) -> void:
	base = built.base
	corners = built.corners
	tiles = built.tiles
	cloths = built.cloths
	faces = built.faces
	gable_faces = built.gable_faces
	bounds = built.bounds


## A pulled pitch as the roof takes it: below FLAT_SNAP it lands flat, else on the nearest `step`.
static func snap_pitch(p: float, step: float) -> float:
	p = clampf(p, PITCH.x, PITCH.y)
	return 0.0 if p < FLAT_SNAP else snappedf(p, step)


func flat() -> bool:
	return pitch <= 0.0


## Rise above the wall top at `u`, 0 at the walls' outer faces and 1 at the ridge; below 0 (the overhang) it carries on straight.
func rise(u: float) -> float:
	if u < 0.0:
		return pitch * u * (1.0 + curve * 0.25 * PI)
	return pitch * (u + curve * 0.25 * sin(PI * u))


## Height of the roof's surface over the ground point (x, z).
func height_at(x: float, z: float) -> float:
	var f := frame()
	var d := Vector3(x, 0.0, z) - Vector3(f.mid.x, 0.0, f.mid.z)
	var out := d.length() if kind == Kind.CONE else absf(d.dot(f.across))
	return base + rise(1.0 - out / half_span())


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
	return half_span() + (0.0 if flat() else OVERHANG)


func gable_overhang() -> float:
	return 0.0 if flat() else GABLE_OVERHANG


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
	gable_faces = gables()
	bounds = AABB(faces[0], Vector3.ZERO)
	for p in faces + gable_faces:
		bounds = bounds.expand(p)
	tiles.clear()
	cloths.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hue := rng.randf_range(-0.04, 0.04)
	var f := frame()
	if flat():
		_lay_deck(rng)
		for c in chimneys:
			_lay_chimney(chimney_spot(c), rng)
		if flag:
			_fly_flag(f.mid)
		return
	var rows := _rows()
	for i in rows.size():
		var row := rows[i]
		if kind == Kind.GABLE:
			_lay_gable_row(row, 0.5 if i % 2 == 1 else 0.0, hue, rng)
		else:
			_lay_cone_row(row, hue, rng)
	if kind == Kind.GABLE:
		_lay_ridge(hue, rng)
		for c in chimneys:
			_lay_chimney(chimney_spot(c), rng)
	elif flag:
		_fly_flag(f.mid + Vector3.UP * pitch)
	else:
		_add(Transform3D(Basis().scaled(Vector3(0.16, 0.5, 0.16)), f.mid + Vector3.UP * (pitch + 0.2)), "finial", Color(0.6, 0.56, 0.5), 1.0)


func _fly_flag(foot: Vector3) -> void:
	var parts := WallLayout.flag(foot, Vector3(1, 0, 0.4), WallLayout.flag_color(seed, 0.0))
	_add(parts.pole, "pole", WallLayout.POLE, 1.0)
	_add(parts.finial, "finial", WallLayout.FINIAL, 1.0)
	cloths.append(parts.cloth)


## Stone flags paving the floor inside the walls at the cap's height: running-bond rows across a house,
## rings round a tower.
func _lay_deck(rng: RandomNumberGenerator) -> void:
	var f := frame()
	var reach := half_span() - WallLayout.THICKNESS + DECK_TUCK
	var y: float = f.mid.y - DECK_DROP - SLAB.y * 0.5
	if kind == Kind.CONE:
		_slab(Vector3(f.mid.x, y, f.mid.z), Basis(), Vector2(SLAB.z, SLAB.z), rng)
		var r := SLAB.z * 0.5
		while r < reach - 0.01:
			var depth := minf(SLAB.z, reach - r)
			var mid := r + depth * 0.5
			var n := maxi(6, ceili(TAU * mid / SLAB.x))
			var twist := rng.randf() * TAU
			for i in n:
				var a := twist + TAU * (i + 0.5) / n
				var out := Vector3(cos(a), 0.0, sin(a))
				var width := TAU * (r + depth) / n
				_slab(Vector3(f.mid.x, y, f.mid.z) + out * mid, Basis(Vector3.UP.cross(out), Vector3.UP, out), Vector2(width, depth), rng)
			r += depth
		return
	var long := ridge_length() * 0.5 - WallLayout.THICKNESS * 0.5 + DECK_TUCK
	var basis := Basis(f.along, Vector3.UP, f.across)
	var z := -reach
	var row := 0
	while z < reach - 0.01:
		var depth := minf(SLAB.z, reach - z)
		var x := -long - (SLAB.x * 0.5 if row % 2 == 1 else 0.0)
		while x < long - 0.01:
			var a := maxf(x, -long)
			var b := minf(x + SLAB.x, long)
			var c := (a + b) * 0.5
			_slab(Vector3(f.mid.x, y, f.mid.z) + f.along * c + f.across * (z + depth * 0.5), basis, Vector2(b - a, depth), rng)
			x += SLAB.x
		z += depth
		row += 1


## One flag of the deck, `size` across its top, a hair smaller for the joint and a hair tilted.
func _slab(at: Vector3, basis: Basis, size: Vector2, rng: RandomNumberGenerator) -> void:
	var b := basis * Basis.from_euler(Vector3(rng.randf_range(-0.01, 0.01), rng.randf_range(-0.02, 0.02), rng.randf_range(-0.01, 0.01)))
	var color := WallLayout.stone_color(rng) * rng.randf_range(0.86, 0.98)
	_add(Transform3D(b.scaled_local(Vector3(size.x - 0.025, SLAB.y, size.y - 0.025)), at + Vector3.UP * rng.randf_range(-0.006, 0.006)), "deck", color, 0.9)


## A chimney's place clamped onto the roof, clear of the gable ends and the eaves.
func chimney_spot(c: Vector2) -> Vector2:
	var along := maxf(0.0, ridge_length() * 0.5 - STACK_WIDTH)
	var across := maxf(0.0, half_span() - STACK_WIDTH)
	return Vector2(clampf(c.x, -along, along), clampf(c.y, -across, across))


## Where a point on the roof lies, as a chimney spot: along the ridge and across it.
func spot_of(p: Vector3) -> Vector2:
	var f := frame()
	var d: Vector3 = p - f.mid
	return Vector2(d.dot(f.along), d.dot(f.across))


## A stone stack rising from the slope to clear the ridge, with a cap slab and two clay pots.
func _lay_chimney(c: Vector2, rng: RandomNumberGenerator) -> void:
	var f := frame()
	var foot: Vector3 = f.mid + f.along * c.x + f.across * c.y
	var surface := rise(1.0 - absf(c.y) / half_span())
	var top := maxf(pitch + 0.7, surface + 1.0)
	var basis := Basis(f.along, Vector3.UP, f.across)
	var y := surface - 0.3
	while y < top - 0.05:
		var h := minf(rng.randf_range(0.26, 0.34), top - y)
		var stone := WallLayout.stone_color(rng)
		var wobble := Basis.from_euler(Vector3(0.0, rng.randf_range(-0.04, 0.04), 0.0))
		_add(Transform3D((basis * wobble).scaled_local(Vector3(STACK_WIDTH, h, STACK_WIDTH)), foot + Vector3.UP * (y + h * 0.5)), "chimney", stone, 1.0)
		y += h
	_add(Transform3D(basis.scaled_local(Vector3(STACK_WIDTH + 0.14, 0.09, STACK_WIDTH + 0.14)), foot + Vector3.UP * (top + 0.045)), "chimney", Color(0.6, 0.56, 0.5), 1.0)
	for side in [-1.0, 1.0]:
		_add(Transform3D(basis.scaled_local(Vector3(0.15, 0.24, 0.15)), foot + f.along * side * STACK_WIDTH * 0.22 + Vector3.UP * (top + 0.21)), "pot", _clay(0.0, rng) * 0.9, 1.0)


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
	return Color(CLAY.r + warm, CLAY.g + warm * 0.4, CLAY.b - warm) * rng.randf_range(0.82, 1.08)


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
	var half: Vector3 = f.along * (ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5 + gable_overhang())
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
	if p.x > 0.0:
		tris.append_array([a, b, c])
	tris.append_array([a, c, d])


## The two triangular gable ends between the end walls' tops and the slopes, as triangles.
func gables() -> PackedVector3Array:
	var tris := PackedVector3Array()
	if kind != Kind.GABLE or flat():
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
				var top := Vector3.UP * rise(1.0 - x1 / hs)
				tris.append_array([a, a + Vector3.UP * prof[i].y, b + top])
				if top.y > 0.0:
					tris.append_array([a, b + top, b])
	return tris


## Nearest distance along a ray to the roof, or INF.
func ray_hit(origin: Vector3, dir: Vector3) -> float:
	return _nearest(origin, dir, faces)


## Nearest distance along a ray to a plastered gable end, or INF.
func gable_hit(origin: Vector3, dir: Vector3) -> float:
	return _nearest(origin, dir, gable_faces)


func _nearest(origin: Vector3, dir: Vector3, tris: PackedVector3Array) -> float:
	var best := INF
	if tris.is_empty() or bounds.grow(0.1).intersects_ray(origin, dir) == null:
		return best
	for i in range(0, tris.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, dir, tris[i], tris[i + 1], tris[i + 2])
		if hit != null:
			best = minf(best, origin.distance_to(hit))
	return best
