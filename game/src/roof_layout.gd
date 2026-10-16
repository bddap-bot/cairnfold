class_name RoofLayout
extends RefCounted

## Lays the tiles of a roof resting on a closed wall: a gable over a house's rectangle or a cone over a
## round tower. Pitch is the ridge's rise above the wall top; curvature bows the slopes out (positive)
## or sags them into swept eaves (negative). At pitch 0 the roof is a flat stone deck inside the walls,
## whose top style rims it. A gable carries chimneys; a cone can fly a flag from its top. Thatched, the slopes
## are a thick coat of overlapping straw courses instead, rolled over the eaves and verges under a block-cut ridge.
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
## A point this near under a deck still stands on it: a ray's hit on the deck can fall a hair short of it.
const ON_DECK := 0.01
const BED_LAP := 0.2
const CURVE := 1.0
const PROFILE_STEPS := 8
const STACK_WIDTH := 0.66

## The clay roof tiles are laid in, before each roof's hue and each tile's variation.
const CLAY := Color(0.72, 0.4, 0.28)
## Combed reed as laid, and the grey-brown it weathers toward.
const STRAW := Color(0.6, 0.45, 0.25)
const WEATHERED := Color(0.42, 0.38, 0.32)
## How far the coat's outer face stands off the roof's surface, and how far its lumps rise and sink from that.
const COAT := 0.32
const LUMPS := 0.05
## Thatch overhangs further than tiles: its eaves and verges round over the walls.
const THATCH_EAVE := 0.25
const THATCH_VERGE := 0.2
## The ridge's band down each side: how far it stands proud of the coat and how far down the slope it reaches; then
## how far apart the points cut along its lower edge stand and how far down they reach.
const BAND := Vector2(0.13, 0.62)
const POINT := Vector2(0.7, 0.28)
## The steepest slope (as its tangent) whose coat is carried up to meet the other's over the ridge; the roll over the
## crest, how far past it each side and how far above.
const CREST := 2.5
const ROLL := Vector2(0.12, 0.16)
## The coat's mesh: the most its rows lie apart, and how many steps round its rounded edges.
const COAT_STEP := 0.12
const EDGE_STEPS := 5
const HAZEL := Color(0.45, 0.36, 0.24)
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
## Laid from the wall it rests on, like `base`: its gable ends rise past the slopes in crow steps, so the tiles stop
## inside them.
var stepped := false
## Straw instead of tiles; a flat deck stays stone.
var thatch := false

var tiles: Array[Dictionary] = []
## A thatched roof's coat, as Mesh arrays, and the slabs standing in for it in shadows and bounce light.
var coat: Array = []
var slabs: Array[Dictionary] = []
## Plain mortar boxes bedding a deck's flags, so its joints show mortar rather than the floor below.
var mortar: Array[Dictionary] = []
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
	r.thatch = thatch
	return r


func same_inputs(other: RoofLayout) -> bool:
	return (kind == other.kind and center == other.center and radius == other.radius
		and pitch == other.pitch and curve == other.curve and seed == other.seed
		and chimneys == other.chimneys and flag == other.flag and thatch == other.thatch)


## Takes what `built` laid, as if `build` had run here.
func adopt(built: RoofLayout) -> void:
	base = built.base
	corners = built.corners
	tiles = built.tiles
	coat = built.coat
	slabs = built.slabs
	mortar = built.mortar
	cloths = built.cloths
	faces = built.faces
	gable_faces = built.gable_faces
	stepped = built.stepped
	bounds = built.bounds


## A pulled pitch as the roof takes it: below FLAT_SNAP it lands flat, else on the nearest `step`.
static func snap_pitch(p: float, step: float) -> float:
	p = clampf(p, PITCH.x, PITCH.y)
	return 0.0 if p < FLAT_SNAP else snappedf(p, step)


func flat() -> bool:
	return pitch <= 0.0


## Height of the deck that `p` stands on, or -INF: a pitched roof, a point beside the house, or one below
## the deck, inside the house under it.
func deck_under(p: Vector3) -> float:
	return base if flat() and p.y >= base - ON_DECK and over(p.x, p.z) else -INF


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


## Whether the ground point (x, z) lies under the roof, between the walls' outer faces.
func over(x: float, z: float) -> bool:
	var f := frame()
	var d := Vector3(x - f.mid.x, 0.0, z - f.mid.z)
	if kind == Kind.CONE:
		return d.length() <= half_span()
	return absf(d.dot(f.across)) <= half_span() and absf(d.dot(f.along)) <= ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5


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
	return 0.0 if flat() else -WallLayout.THICKNESS * 0.5 if stepped else GABLE_OVERHANG


func thatched() -> bool:
	return thatch and not flat()


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
	coat = []
	slabs.clear()
	mortar.clear()
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
	if thatch:
		_lay_thatch(rng)
	else:
		var rows := _rows()
		for i in rows.size():
			var row := rows[i]
			if kind == Kind.GABLE:
				_lay_gable_row(row, 0.5 if i % 2 == 1 else 0.0, hue, rng)
			else:
				_lay_cone_row(row, hue, rng)
		if kind == Kind.GABLE:
			_lay_ridge(hue, rng)
	var top := pitch + coat_rise()
	if kind == Kind.GABLE:
		for c in chimneys:
			_lay_chimney(chimney_spot(c), rng)
	elif flag:
		_fly_flag(f.mid + Vector3.UP * top)
	else:
		_add(Transform3D(Basis().scaled(Vector3(0.16, 0.5, 0.16)), f.mid + Vector3.UP * (top + 0.2)), "finial", Color(0.6, 0.56, 0.5), 1.0)


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


## One flag of the deck, `size` across its top, a hair smaller for the joint and a hair tilted, on a mortar bed
## reaching past it into its neighbours' so no gap, rounded corners' included, opens onto the floor below.
func _slab(at: Vector3, basis: Basis, size: Vector2, rng: RandomNumberGenerator) -> void:
	var b := basis * Basis.from_euler(Vector3(rng.randf_range(-0.01, 0.01), rng.randf_range(-0.02, 0.02), rng.randf_range(-0.01, 0.01)))
	var color := WallLayout.stone_color(rng) * rng.randf_range(0.86, 0.98)
	_add(Transform3D(b.scaled_local(Vector3(size.x - 0.025, SLAB.y, size.y - 0.025)), at + Vector3.UP * rng.randf_range(-0.006, 0.006)), "deck", color, 0.9)
	var bed := Vector3(size.x + BED_LAP, SLAB.y * 0.7, size.y + BED_LAP)
	mortar.append({"xform": Transform3D(basis.scaled_local(bed), at + Vector3.UP * (SLAB.y * 0.2 - bed.y * 0.5)), "color": WallLayout.MORTAR, "kind": "mortar", "ao": 0.8})


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
	var top := maxf(pitch + 0.7, surface + 1.0) + coat_rise()
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
		var slope := slope_at(x)
		out.append({"x": x, "y": rise(1.0 - x / hs), "slope": slope})
		x -= ROW * cos(slope)
	return out


## The slope's angle `x` out from the ridge (or axis), rising toward it.
func slope_at(x: float) -> float:
	var hs := half_span()
	x = maxf(x, 0.01)
	return atan((rise(1.0 - (x - 0.01) / hs) - rise(1.0 - x / hs)) / 0.01)


## How far out from the ridge a point `d` up the slope from `x` lies (down it for negative `d`), no further in than the ridge.
func _along(x: float, d: float) -> float:
	var steps := maxi(1, ceili(absf(d) / 0.05))
	for i in steps:
		x = maxf(0.0, x - d / steps * cos(slope_at(x)))
	return x


func _lay_gable_row(row: Dictionary, stagger: float, hue: float, rng: RandomNumberGenerator) -> void:
	var f := frame()
	var length := ridge_length() + WallLayout.THICKNESS + gable_overhang() * 2.0
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
	var length := ridge_length() + WallLayout.THICKNESS + gable_overhang() * 2.0
	var n := maxi(1, ceili(length / 0.32))
	for i in n:
		var t := (i + 0.5) / n - 0.5
		var p: Vector3 = f.mid + f.along * t * length + Vector3.UP * (pitch + 0.04)
		var basis := Basis(f.along, Vector3.UP, f.across).scaled_local(Vector3(length / n * 1.02, 0.14, 0.26))
		_add(Transform3D(basis, p), "ridge", _clay(hue, rng) * 0.88, 0.95)


func _tile(p: Vector3, basis: Basis, hue: float, rng: RandomNumberGenerator, width := 1.0) -> void:
	var b := basis.rotated(basis.x, -0.05) * Basis.from_euler(Vector3(0.0, rng.randf_range(-0.04, 0.04), rng.randf_range(-0.03, 0.03)))
	_add(Transform3D(b.scaled_local(Vector3(TILE.x * width, TILE.y, TILE.z)), p), "tile", _clay(hue, rng), 1.0)


## How far the thatch's outer face stands above the ridge: the coat and its band, measured square to the slopes there.
func coat_rise() -> float:
	return _crest().y + ROLL.y if thatched() else 0.0


## Where the coat's top row ends over the ridge (or apex), each slope's outer face carried on up toward the other's,
## as Vector2(how far out from the ridge, how high over it). On a slope steeper than CREST allows the faces stop short
## of meeting, under the roll.
func _crest() -> Vector2:
	var s := slope_at(0.0)
	var depth := COAT + BAND.x
	var up := depth * minf(tan(s), CREST)
	return Vector2(depth * sin(s) - up * cos(s), depth * cos(s) + up * sin(s))


## The straw coat, one mesh in Mesh arrays (unindexed triangles; a vertex's tangent is the way its straw runs): a
## blanket COAT deep over the slopes, lumpy, rounded over the eaves and verges onto an underside, under a block-cut
## ridge pinned by hazel liggers on a gable or a crown on a cone. Each roof weathers its own way; its ridge, renewed
## more often, less. Slabs inside the coat stand in for it in shadows and bounce light, which read boxes.
func _lay_thatch(rng: RandomNumberGenerator) -> void:
	var weather := rng.randf_range(0.0, 0.55)
	var lumps := FastNoiseLite.new()
	lumps.seed = seed
	lumps.frequency = 0.8
	var c := Coat.new()
	c.straw = STRAW.lerp(WEATHERED, weather)
	c.ridge = STRAW.lerp(WEATHERED, weather * 0.3)
	c.moss = weather * 1.4
	c.lumps = lumps
	if kind == Kind.GABLE:
		_coat_gable(c)
	else:
		_coat_cone(c)
	coat = c.arrays()


## A gable's coat: each slope a grid from the ridge to past the eave and past both verges, its edges rounded under, then
## the ridge's roll, the liggers on its band, and the slabs.
func _coat_gable(c: Coat) -> void:
	var f := frame()
	var reach := ridge_length() * 0.5 + (0.0 if stepped else WallLayout.THICKNESS * 0.5 + THATCH_VERGE)
	var ts := _edged(_spaced(-reach, reach, COAT_STEP))
	var xs := _coat_rows()
	for side in [-1.0, 1.0]:
		var out: Vector3 = f.across * side
		c.grid(ts.size(), xs.size(), func(i: int, j: int) -> Array:
			var t: float = ts[i].x
			return _coat_node(f.mid + f.along * t, out, f.along * signf(t), t, xs[j].x, ts[i].y, xs[j].y, c))
		var under := _spaced(half_span() - 0.1, eave() + THATCH_EAVE, COAT_STEP * 2.0)
		var ends := _spaced(0.0, eave() + THATCH_EAVE, COAT_STEP * 2.0)
		var lengthwise := _spaced(-reach, reach, COAT_STEP * 2.0)
		c.grid(lengthwise.size(), under.size(), func(i: int, j: int) -> Array:
			return _under_node(f.mid + f.along * lengthwise[i], out, under[j]))
		for end in ([] if stepped else [-1.0, 1.0]):
			var gable := _spaced(ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5 - 0.05, reach, COAT_STEP)
			c.grid(gable.size(), ends.size(), func(i: int, j: int) -> Array:
				return _under_node(f.mid + f.along * end * gable[i], out, ends[j]))
		_coat_liggers(f.mid, out, f.along, reach)
		_coat_slabs(f.mid, out, f.along, reach * 2.0, c)
	_ridge_roll(c, f.mid, f.along, f.across, reach)


func _coat_cone(c: Coat) -> void:
	var f := frame()
	var xs := _coat_rows()
	var n := maxi(24, ceili(TAU * (eave() + THATCH_EAVE) / (COAT_STEP * 1.5)))
	var points := maxi(6, roundi(TAU * BAND.y / POINT.x))
	c.grid(n + 1, xs.size(), func(i: int, j: int) -> Array:
		var a := TAU * i / n
		var out := Vector3(cos(a), 0.0, sin(a))
		return _coat_node(f.mid, out, Vector3.ZERO, float(i) / n * points * POINT.x, xs[j].x, 0.0, xs[j].y, c))
	var under := _spaced(half_span() - 0.1, eave() + THATCH_EAVE, COAT_STEP * 2.0)
	c.grid(n + 1, under.size(), func(i: int, j: int) -> Array:
		var a := TAU * i / n
		return _under_node(f.mid, Vector3(cos(a), 0.0, sin(a)), under[j]))
	_knob(c, f.mid)
	for k in 8:
		var a := TAU * k / 8.0
		var out := Vector3(cos(a), 0.0, sin(a))
		_coat_slabs(f.mid, out, out.cross(Vector3.UP), TAU * eave() / 8.0, c)


## Rows down a slope as Vector2(distance out from the ridge, how far round the eave's edge): close together about the
## band's cut, the last EDGE_STEPS turning under the eave.
func _coat_rows() -> PackedVector2Array:
	var out := PackedVector2Array()
	var cut := _along(0.0, -BAND.y)
	var tip := _along(0.0, -(BAND.y + POINT.y))
	var x := 0.0
	var end := eave() + THATCH_EAVE
	while x < end:
		out.append(Vector2(x, 0.0))
		x += COAT_STEP * (0.3 if x > cut - 0.1 and x < tip + 0.06 else 1.0)
	out.append(Vector2(end, 0.0))
	for k in EDGE_STEPS:
		out.append(Vector2(end, PI * (k + 1) / EDGE_STEPS))
	return out


## Evenly from `a` to `b`, at most `step` apart.
static func _spaced(a: float, b: float, step: float) -> PackedFloat32Array:
	var n := maxi(1, ceili((b - a) / step))
	var out := PackedFloat32Array()
	for i in n + 1:
		out.append(lerpf(a, b, float(i) / n))
	return out


## `ts` as Vector2(where, how far round the edge), with EDGE_STEPS more turning under at each end.
static func _edged(ts: PackedFloat32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in EDGE_STEPS:
		out.append(Vector2(ts[0], PI * (EDGE_STEPS - k) / EDGE_STEPS))
	for t in ts:
		out.append(Vector2(t, 0.0))
	for k in EDGE_STEPS:
		out.append(Vector2(ts[-1], PI * (k + 1) / EDGE_STEPS))
	return out


## The coat's depth at `along` (metres along the ridge, or round a cone at its band) and `x` out from the ridge, over
## the roof's surface at `at`: lumpy, and thicker under the ridge's band, whose lower edge is cut into points.
func _depth(along: float, x: float, at: Vector3, c: Coat) -> float:
	var down := _down(x)
	var phase := absf(fposmod(along / POINT.x, 1.0) * 2.0 - 1.0)
	var cut := BAND.y + POINT.y * (1.0 - phase)
	var band := 1.0 - smoothstep(cut - 0.02, cut + 0.02, down)
	var shaggy := smoothstep(cut, cut + 0.3, down)
	return COAT + BAND.x * band + LUMPS * c.lumps.get_noise_3d(at.x * 1.3, down * 1.7, at.z * 1.3) * shaggy


## How far down the slope from the ridge (or apex) a point `x` out lies.
func _down(x: float) -> float:
	var hs := half_span()
	var d := 0.0
	var steps := maxi(1, ceili(x / 0.1))
	var y0 := rise(1.0)
	for i in steps:
		var x1 := x * (i + 1) / steps
		var y1 := rise(1.0 - x1 / hs)
		d += Vector2(x / steps, y1 - y0).length()
		y0 = y1
	return d


## A node of the coat: [position, normal, the way the straw runs, colour]. `on` is the ridge (or apex) below it, `out`
## the way down the slope, `x` how far out; `a` and `b` how far it has turned under the end (toward `end`) and the eave.
func _coat_node(on: Vector3, out: Vector3, end: Vector3, along: float, x: float, a: float, b: float, c: Coat) -> Array:
	var s := slope_at(x)
	var n := out * sin(s) + Vector3.UP * cos(s)
	var fall := out * cos(s) - Vector3.UP * sin(s)
	var base := on + out * x + Vector3.UP * rise(1.0 - x / half_span())
	var depth := _depth(along, x, base, c)
	if x == 0.0:
		base -= fall * depth * minf(tan(s), CREST)
	var turn := minf(PI, Vector2(a, b).length())
	var away := (end * a + fall * b).normalized() if turn > 0.0 else Vector3.ZERO
	var p := base + n * depth * 0.5 + (n * cos(turn) + away * sin(turn)) * depth * 0.5
	var band := depth > COAT + BAND.x * 0.5
	var colour := (c.ridge if band else c.straw) * (1.0 + 0.08 * c.lumps.get_noise_3d(base.x * 0.5, 40.0, base.z * 0.5))
	colour.a = 0.0 if band else c.moss
	if turn > PI * 0.5:
		colour = Color(colour.r * 0.7, colour.g * 0.7, colour.b * 0.7, 0.0)
	return [p, n * cos(turn) + away * sin(turn), n.cross(away) if turn > 0.0 else fall, colour]


## A node of the coat's underside, on the roof's surface `x` out, facing down.
func _under_node(on: Vector3, out: Vector3, x: float) -> Array:
	var s := slope_at(x)
	var fall := out * cos(s) - Vector3.UP * sin(s)
	var p := on + out * x + Vector3.UP * rise(1.0 - x / half_span())
	return [p, -(out * sin(s) + Vector3.UP * cos(s)), fall, Color(STRAW.r * 0.45, STRAW.g * 0.45, STRAW.b * 0.45, 0.0)]


## The roll capping a gable's ridge over the crest, straw running along it, its ends rounded; below its widest it reaches
## down into the coats.
func _ridge_roll(c: Coat, mid: Vector3, along: Vector3, across: Vector3, reach: float) -> void:
	var crest := _crest()
	var wide := crest.x + ROLL.x
	var deep := ROLL.y + wide * tan(slope_at(0.0))
	var centre := mid + Vector3.UP * (pitch + crest.y)
	var ts := _spaced(-reach + 0.05, reach - 0.05, COAT_STEP * 2.0)
	var around := 16
	c.grid(ts.size() + 2, around + 1, func(i: int, j: int) -> Array:
		var k := clampi(i - 1, 0, ts.size() - 1)
		var shrink := 0.0 if i > 0 and i <= ts.size() else 1.0
		var t := ts[k] + signf(ts[k]) * shrink * 0.05
		var a := TAU * j / around
		var tall := ROLL.y if sin(a) > 0.0 else deep
		var r := Vector2(cos(a) * wide, sin(a) * tall) * (1.0 - shrink * 0.6)
		var n := (across * cos(a) / wide + Vector3.UP * sin(a) / tall).normalized()
		if shrink > 0.0:
			n = (n + along * signf(t)).normalized()
		return [centre + along * t + across * r.x + Vector3.UP * r.y, n, along, c.ridge * 0.97])


## A cone's crown: a knob of straw over the crest, reaching down into the coat.
func _knob(c: Coat, apex: Vector3) -> void:
	var crest := _crest()
	var wide := crest.x + ROLL.x + 0.04
	var deep := ROLL.y + wide * tan(slope_at(0.0))
	var centre := apex + Vector3.UP * (pitch + crest.y)
	c.grid(17, 13, func(i: int, j: int) -> Array:
		var a := TAU * i / 16.0
		var e := PI * 0.5 - PI * j / 12.0
		var tall := ROLL.y if e > 0.0 else deep
		var dir := Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e))
		var p := centre + Vector3(dir.x * wide, dir.y * tall, dir.z * wide)
		return [p, Vector3(dir.x / wide, dir.y / tall, dir.z / wide).normalized(), Vector3(cos(a), 0.0, sin(a)), c.ridge])


## Two hazel liggers along a gable's band, a little proud of it, holding it down.
func _coat_liggers(mid: Vector3, out: Vector3, along: Vector3, reach: float) -> void:
	for d in [0.16, BAND.y - 0.12]:
		var x := _along(0.0, -d)
		var basis := _slope_basis(out, slope_at(x))
		var at := mid + out * x + Vector3.UP * rise(1.0 - x / half_span()) + basis.y * (COAT + BAND.x + 0.01)
		_add(Transform3D(basis.scaled_local(Vector3(2.0 * reach - 0.3, 0.035, 0.035)), at), "ligger", HAZEL, 1.0)


## Slabs down a slope of `width` along `along`, inside the coat: what shadows and the bounce light see of it.
func _coat_slabs(mid: Vector3, out: Vector3, along: Vector3, width: float, c: Coat) -> void:
	var end := eave() + THATCH_EAVE
	var xs := _spaced(0.0, end, 0.9)
	for i in xs.size() - 1:
		var x := (xs[i] + xs[i + 1]) * 0.5
		var s := slope_at(x)
		var basis := Basis(along.normalized(), out * sin(s) + Vector3.UP * cos(s), out * cos(s) - Vector3.UP * sin(s))
		var length := (xs[i + 1] - xs[i]) / cos(s)
		var at := mid + out * x + Vector3.UP * rise(1.0 - x / half_span()) + basis.y * COAT * 0.4
		slabs.append({"xform": Transform3D(basis.scaled_local(Vector3(width, COAT * 0.8, length)), at), "color": c.straw, "kind": "thatch", "ao": 1.0})


## Builds the coat's triangles: grids of nodes ([position, normal, straw direction, colour]) joined into quads, each
## triangle wound to face its nodes' normals.
class Coat:
	var straw: Color
	var ridge: Color
	var moss := 0.0
	var lumps: FastNoiseLite
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var colours := PackedColorArray()

	func grid(n: int, m: int, node: Callable) -> void:
		var nodes: Array[Array] = []
		for i in n:
			var row: Array = []
			for j in m:
				row.append(node.call(i, j))
			nodes.append(row)
		for i in n - 1:
			for j in m - 1:
				_quad(nodes[i][j], nodes[i + 1][j], nodes[i + 1][j + 1], nodes[i][j + 1])

	func _quad(a: Array, b: Array, c: Array, d: Array) -> void:
		_tri(a, b, c)
		_tri(a, c, d)

	func _tri(a: Array, b: Array, c: Array) -> void:
		var facing: Vector3 = a[1] + b[1] + c[1]
		var cross: Vector3 = (b[0] - a[0]).cross(c[0] - a[0])
		if cross.length_squared() < 1e-10:
			return
		for v in ([a, b, c] if cross.dot(facing) < 0.0 else [a, c, b]):
			verts.append(v[0])
			normals.append(v[1])
			tangents.append_array([v[2].x, v[2].y, v[2].z, 1.0])
			colours.append(v[3])

	func arrays() -> Array:
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_TANGENT] = tangents
		out[Mesh.ARRAY_COLOR] = colours
		return out


## Keeps the coat's triangles and slabs `kept` takes, by their middles.
func keep_coat(kept: Callable) -> void:
	slabs.assign(slabs.filter(func(s: Dictionary) -> bool: return kept.call(s.xform.origin)))
	if coat.is_empty():
		return
	var verts: PackedVector3Array = coat[Mesh.ARRAY_VERTEX]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	out[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	out[Mesh.ARRAY_TANGENT] = PackedFloat32Array()
	out[Mesh.ARRAY_COLOR] = PackedColorArray()
	for i in range(0, verts.size(), 3):
		if not kept.call((verts[i] + verts[i + 1] + verts[i + 2]) / 3.0):
			continue
		for k in 3:
			out[Mesh.ARRAY_VERTEX].append(verts[i + k])
			out[Mesh.ARRAY_NORMAL].append(coat[Mesh.ARRAY_NORMAL][i + k])
			out[Mesh.ARRAY_COLOR].append(coat[Mesh.ARRAY_COLOR][i + k])
			out[Mesh.ARRAY_TANGENT].append_array(coat[Mesh.ARRAY_TANGENT].slice((i + k) * 4, (i + k) * 4 + 4))
	coat = out


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


## The gable ends between the end walls' tops and the slopes, as triangles: each end's outer and inner face, flush
## with a plaster wall's, wound to face out of the wall (Godot's front faces turn clockwise), since a face's lighting
## reads the air half a metre before it.
func gables() -> PackedVector3Array:
	var tris := PackedVector3Array()
	if kind != Kind.GABLE or flat():
		return tris
	var f := frame()
	var prof := profile(PROFILE_STEPS)
	var hs := half_span()
	var faces_at := WallLayout.THICKNESS * 0.5 - WallLayout.PLASTER_INSET
	for end in [-1.0, 1.0]:
		for face in [-1.0, 1.0]:
			var facing: Vector3 = f.along * end * face
			var at: Vector3 = f.mid + f.along * end * ridge_length() * 0.5 + facing * faces_at
			for side in [-1.0, 1.0]:
				var out: Vector3 = f.across * side
				for i in prof.size() - 1:
					if prof[i].x >= hs:
						break
					var x1 := minf(prof[i + 1].x, hs)
					var a: Vector3 = at + out * prof[i].x
					var b: Vector3 = at + out * x1
					var top := Vector3.UP * rise(1.0 - x1 / hs)
					_facing(tris, facing, a, a + Vector3.UP * prof[i].y, b + top)
					if top.y > 0.0:
						_facing(tris, facing, a, b + top, b)
	return tris


static func _facing(tris: PackedVector3Array, facing: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	tris.append_array([a, b, c] if (b - a).cross(c - a).dot(facing) < 0.0 else [a, c, b])


## Nearest distance along a ray to the roof, or INF.
func ray_hit(origin: Vector3, dir: Vector3) -> float:
	return _nearest(origin, dir, faces)


## Nearest distance along a ray to a gable end, or INF.
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
