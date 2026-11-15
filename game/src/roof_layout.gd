class_name RoofLayout
extends RefCounted

enum Kind { GABLE, CONE }
enum Deck { STONE, WOOD }

const FLAG_ALONG := Vector3(1, 0, 0.4)
const OVERHANG := 0.3
const MAX_OVERHANG := 2.5
const GABLE_OVERHANG := 0.25
const ROW := 0.24
## TILE.z laps the two rows above, so every joint has a tile under it; the torching closes joints only from below.
const TILE := Vector3(0.27, 0.05, 0.6)
const NOSE := 0.18
const CONE_LAP := 0.25
const FLAT_SNAP := 0.4
const SLAB := Vector3(0.7, 0.1, 0.5)
## PLANK (width, thickness); JOIST (spacing, depth).
const PLANK := Vector2(0.18, 0.05)
const PLANK_GAP := 0.01
const PLANK_LENGTHS := Vector2(1.4, 3.2)
const JOIST := Vector2(0.6, 0.12)
const HATCH := 0.8
const HATCH_CLEAR := 0.15
const DORMER_HALF := 0.62
const DORMER_TALL := 0.9
const DORMER_PITCH := 0.42
const DORMER_EAVE := 0.12
const DORMER_CLEAR := 0.25
const DORMER_UNDER := 0.15
const DORMER_WINDOW := 0.3
const DORMER_SILL := 0.2
const DORMER_HEAD := 0.12
## (width, thickness).
const DORMER_BOARD := Vector2(0.16, 0.05)
const DECK_TUCK := 0.06
const DECK_DROP := 0.03
## A ray's hit on the deck can land a hair below it.
const ON_DECK := 0.01
const BED_LAP := 0.2
## Beyond this the pitched profile reverses at the ridge or eave and cuts through its supporting wall.
const CURVE := 4.0 / PI
const TORCHING_DROP := 0.04
## Half the bounce probes' spacing, read per vertex, and short enough that a joining build removes it with the tiles.
const TORCHING_PIECE := 0.5
const PROFILE_STEPS := 8
const STACK_WIDTH := 0.66
const RAFTER_SPACING := 0.65
const CEILING_BOARD := 0.24
const CEILING_DROP := DECK_DROP + SLAB.y * 1.1
const CEILING_DEPTH := 0.035
const CEILING_PIECE := 0.5

const CLAY := Color(0.72, 0.4, 0.28)
const STRAW := Color(0.6, 0.45, 0.25)
const WEATHERED := Color(0.42, 0.38, 0.32)
const DECK_TONE := Color(1.0, 0.84, 0.62)
const COAT := 0.32
const LUMPS := 0.05
const THATCH_EAVE := 0.25
const THATCH_VERGE := 0.2
## BAND (proud of the coat, reach down the slope); POINT (spacing, depth) of the points cut along its lower edge.
const BAND := Vector2(0.13, 0.62)
const POINT := Vector2(0.7, 0.28)
## CREST: the steepest slope (a tangent) whose coat is carried up to meet the other's. ROLL (past the crest, above it).
const CREST := 2.5
const ROLL := Vector2(0.12, 0.16)
const COAT_STEP := 0.12
## Past the stones' near distance: from the air COAT_STEP cost the Quest 2 1 ms over five roofs and looked the same.
const FAR_STEP := 0.36
const EDGE_STEPS := 5
const HAZEL := Color(0.45, 0.36, 0.24)
var kind := Kind.GABLE
var corners: Array[Vector3] = []
var center := Vector3.ZERO
## Cone only: to the wall's centre line.
var radius := 2.0
## The wall top's height; `foot` is what the walls stand on (-INF: unknown), which no eave reaches below.
var base := 0.0
var foot := -INF
## The ridge's rise above the wall top.
var pitch := 2.0
## > 0 bows the slopes out, < 0 sags them into swept eaves.
var curve := 0.0
var seed := 1
## Metres along the ridge from its middle, and across it.
var chimneys: Array[Vector2] = []
## As chimneys; y reaches the dormer's front.
var dormers: Array[Vector2] = []
## As chimneys; on a tower, x is east of its axis.
var hatches: Array[Vector2] = []
var overhang := OVERHANG
var deck := Deck.STONE
var flag := false
## Crow-stepped gable ends, taken from the wall: the tiles stop inside them.
var stepped := false
var thatch := false

var tiles: Array[Dictionary] = []
var coat: Array = []
var coat_far: Array = []
var _coat_pick: TriangleMesh
var slabs: Array[Dictionary] = []
var mortar: Array[Dictionary] = []
var cloths: Array[Dictionary] = []
var vents := PackedVector3Array()
var joined: Array[Massing] = []
var resting: Array[Massing] = []
var faces := PackedVector3Array()
var gable_faces := PackedVector3Array()
## Boards, plaster and stone stand out to the wall's face, whatever plane `gable_faces` backs them on.
var gable_pick := PackedVector3Array()
var torching_faces := PackedVector3Array()
var timber_faces := PackedVector3Array()
var bounds := AABB()


const INPUTS: Array[StringName] = [&"kind", &"center", &"radius", &"pitch", &"curve", &"seed", &"chimneys", &"dormers", &"hatches", &"overhang", &"deck", &"flag", &"thatch"]


## Copied so another thread can lay it.
func inputs() -> RoofLayout:
	var r := RoofLayout.new()
	for k in INPUTS:
		var v: Variant = get(k)
		r.set(k, v.duplicate() if v is Array else v)
	return r


func same_inputs(other: RoofLayout) -> bool:
	for k in INPUTS:
		if get(k) != other.get(k):
			return false
	return true


func data() -> Dictionary:
	return {"kind": int(kind), "center": center, "radius": radius, "pitch": pitch, "curve": curve, "seed": seed, "chimneys": PackedVector2Array(chimneys), "dormers": PackedVector2Array(dormers), "hatches": PackedVector2Array(hatches), "overhang": overhang, "deck": int(deck), "flag": flag, "thatch": thatch}


func set_data(d: Dictionary) -> void:
	for k in ["kind", "center", "radius", "pitch", "curve", "seed", "overhang", "deck", "flag", "thatch"]:
		set(k, d[k])
	for k in ["chimneys", "dormers", "hatches"]:
		(get(k) as Array).assign(Array(d[k]))


func adopt(built: RoofLayout) -> void:
	base = built.base
	foot = built.foot
	corners = built.corners
	tiles = built.tiles
	coat = built.coat
	coat_far = built.coat_far
	_coat_pick = built._coat_pick
	slabs = built.slabs
	mortar = built.mortar
	cloths = built.cloths
	vents = built.vents
	joined = built.joined
	resting = built.resting
	faces = built.faces
	gable_faces = built.gable_faces
	gable_pick = built.gable_pick
	torching_faces = built.torching_faces
	timber_faces = built.timber_faces
	stepped = built.stepped
	bounds = built.bounds


static func snap_pitch(p: float, step: float) -> float:
	return 0.0 if p < FLAT_SNAP else snappedf(p, step)


func flat() -> bool:
	return pitch <= 0.0


func deck_under(p: Vector3) -> float:
	if not flat() or kind != Kind.CONE and corners.size() < 4:
		return -INF
	var y := height_at(p.x, p.z)
	return y if p.y >= y - ON_DECK and over(p.x, p.z) else -INF


## `u`: 0 at the walls' outer faces, 1 at the ridge; below 0 (the overhang) it carries on straight.
func rise(u: float) -> float:
	if u < 0.0:
		return pitch * u * (1.0 + curve * 0.25 * PI)
	return pitch * (u + curve * 0.25 * sin(PI * u))


func height_at(x: float, z: float) -> float:
	var f := frame()
	var d := Vector3(x, 0.0, z) - Vector3(f.mid.x, 0.0, f.mid.z)
	var out := d.length() if kind == Kind.CONE else absf(d.dot(f.across))
	if flat():
		var reach := deck_reach()
		var across := maxf(0.0, 1.0 - pow(out / reach, 2.0))
		var along := 1.0
		if kind == Kind.GABLE:
			along = maxf(0.0, 1.0 - pow(d.dot(f.along) / deck_length(), 2.0))
		return base + curve * reach * 0.25 * across * along
	return base + rise(1.0 - out / half_span())


func over(x: float, z: float) -> bool:
	var f := frame()
	var d := Vector3(x - f.mid.x, 0.0, z - f.mid.z)
	if kind == Kind.CONE:
		return d.length() <= half_span()
	return absf(d.dot(f.across)) <= half_span() and absf(d.dot(f.along)) <= ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5


func half_span() -> float:
	var inner := radius if kind == Kind.CONE else corners[0].distance_to(corners[3]) * 0.5
	return inner + WallLayout.THICKNESS * 0.5


func ridge_length() -> float:
	return corners[0].distance_to(corners[1])


func deck_reach() -> float:
	return half_span() - WallLayout.THICKNESS + DECK_TUCK


func deck_length() -> float:
	return ridge_length() * 0.5 - WallLayout.THICKNESS * 0.5 + DECK_TUCK


func frame() -> Dictionary:
	if kind == Kind.CONE:
		return {"along": Vector3.RIGHT, "across": Vector3.BACK, "mid": Vector3(center.x, base, center.z)}
	var along := (corners[1] - corners[0])
	along.y = 0.0
	var across := (corners[3] - corners[0])
	across.y = 0.0
	var mid := (corners[0] + corners[2]) * 0.5
	return {"along": along.normalized(), "across": across.normalized(), "mid": Vector3(mid.x, base, mid.z)}


func eave() -> float:
	if flat():
		return half_span()
	return half_span() + minf(overhang, reach())


func reach() -> float:
	var fall := -rise(-1.0) / half_span()
	var down := base - foot
	return minf(MAX_OVERHANG, down / fall) if fall > 0.0 and is_finite(down) else MAX_OVERHANG


func eave_way(p: Vector3) -> Vector3:
	if flat():
		return Vector3.ZERO
	var f := frame()
	var d: Vector3 = p - f.mid
	d.y = 0.0
	if kind == Kind.CONE:
		return d.normalized() if d.length() > half_span() else Vector3.ZERO
	var across := d.dot(f.across)
	var inside := absf(d.dot(f.along)) <= ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5
	return f.across * signf(across) if absf(across) > half_span() and inside else Vector3.ZERO


func gable_overhang() -> float:
	return 0.0 if flat() else -WallLayout.THICKNESS * 0.5 if stepped else GABLE_OVERHANG


func thatched() -> bool:
	return thatch and not flat()


## Vector2(out from the ridge, height over base), ridge to eave.
func profile(steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var hs := half_span()
	for i in steps + 1:
		var x := eave() * i / steps
		out.append(Vector2(x, rise(1.0 - x / hs)))
	return out


func lining() -> PackedVector2Array:
	var hs := half_span()
	var steps := ceili(eave() / TORCHING_PIECE)
	var prof := profile(steps)
	while range(steps).any(func(i: int) -> bool: return (prof[i].y + prof[i + 1].y) * 0.5 - rise(1.0 - (prof[i].x + prof[i + 1].x) * 0.5 / hs) > TORCHING_DROP * 0.5):
		steps *= 2
		prof = profile(steps)
	return prof


## Slope area per unit of plan area out to the eave.
func stretch() -> float:
	if flat():
		return 1.0
	var p := profile(PROFILE_STEPS * 4)
	var run := 0.0
	var turned := 0.0
	for i in range(1, p.size()):
		var ds := p[i].distance_to(p[i - 1])
		run += ds
		turned += (p[i].x + p[i - 1].x) * ds
	var e := eave()
	return turned / (e * e) if kind == Kind.CONE else run / e


func build(gable_inset := WallLayout.PLASTER_INSET) -> void:
	faces = surface()
	gable_faces = gables(gable_inset)
	gable_pick = gables()
	torching_faces = torching()
	timber_faces = PackedVector3Array()
	bounds = AABB(faces[0], Vector3.ZERO)
	for p in faces + gable_pick:
		bounds = bounds.expand(p)
	tiles.clear()
	coat = []
	coat_far = []
	_coat_pick = null
	slabs.clear()
	mortar.clear()
	cloths.clear()
	vents.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hue := rng.randf_range(-0.04, 0.04)
	if flat():
		if deck == Deck.WOOD:
			_lay_boards(rng)
		else:
			_lay_deck(rng)
		_lay_ceiling()
		for i in hatches.size():
			if hatch_fits(hatches[i], hatches.slice(0, i)):
				rng.seed = hash([seed, "hatch", i])
				_lay_hatch(hatch_spot(hatches[i]), rng)
		for i in chimneys.size():
			_lay_chimney(chimney_spot(chimneys[i]), _chimney_rng(i))
		if flag:
			_fly_flag(flag_top())
		return
	if thatch:
		_lay_thatch(rng)
	else:
		var rows := _rows()
		for i in rows.size():
			var row := rows[i]
			rng.seed = hash([seed, "row", i])
			if kind == Kind.GABLE:
				if i == 0:
					_lay_gable_row(row, 0.5, hue, rng, TILE.y * 0.5)
					rng.seed = hash([seed, "row", i])
				_lay_gable_row(row, 0.5 if i % 2 == 1 else 0.0, hue, rng)
			else:
				_lay_cone_row(row, hue, rng)
		if kind == Kind.GABLE:
			rng.seed = hash([seed, "ridge"])
			_lay_ridge(hue, rng)
	if kind == Kind.GABLE:
		for i in chimneys.size():
			_lay_chimney(chimney_spot(chimneys[i]), _chimney_rng(i))
		for i in dormers.size():
			rng.seed = hash([seed, "dormer", i])
			_lay_dormer(dormers[i], hue, rng)
	elif flag:
		_fly_flag(flag_top())
	else:
		_add(Transform3D(Basis().scaled(Vector3(0.16, 0.5, 0.16)), flag_top() + Vector3.UP * 0.2), "finial", Color(0.6, 0.56, 0.5), 1.0)


## A rectangular bound, which also bounds a round ceiling's segments; each is charged as an existing timber.
func ceiling_units() -> int:
	if not flat():
		return 0
	var h := _ceiling_halves()
	var long := maxf(h.x, h.y)
	var wide := minf(h.x, h.y)
	return ceili(2.0 * wide / CEILING_BOARD) * ceili(2.0 * long / CEILING_PIECE) + ceili(2.0 * long / RAFTER_SPACING) * ceili(2.0 * wide / CEILING_PIECE)


## Strips are split so curved decks and merge exclusions use the covering's roof height and hiding queries.
func _lay_ceiling() -> void:
	var f := frame()
	var h := _ceiling_halves()
	var long := maxf(h.x, h.y)
	var wide := minf(h.x, h.y)
	var turned := h.x < h.y
	var along: Vector3 = f.across if turned else f.along
	var across: Vector3 = -f.along if turned else f.across
	var count := maxi(1, ceili(2.0 * wide / CEILING_BOARD))
	for i in count:
		var a := -wide + 2.0 * wide * i / count
		var b := -wide + 2.0 * wide * (i + 1) / count
		_ceiling_strip(across, -along, a, b, long, CEILING_DEPTH, CEILING_DROP)
	var depth := rafter_depth()
	var width := depth * 0.55
	count = maxi(1, ceili(2.0 * long / RAFTER_SPACING))
	for i in count:
		var x := -long + 2.0 * long * (i + 0.5) / count
		_ceiling_strip(along, across, x - width * 0.5, x + width * 0.5, wide, depth, CEILING_DROP + CEILING_DEPTH)


func _ceiling_halves() -> Vector2:
	var wide := half_span() - WallLayout.THICKNESS * 0.5
	return Vector2(wide if kind == Kind.CONE else ridge_length() * 0.5, wide)


func rafter_depth() -> float:
	var h := _ceiling_halves()
	return clampf(2.0 * minf(h.x, h.y) / 18.0, 0.14, 0.38)


func rafter_bottom(x: float, z: float) -> float:
	return height_at(x, z) - CEILING_DROP - CEILING_DEPTH - rafter_depth()


func _ceiling_strip(along: Vector3, across: Vector3, a: float, b: float, reach: float, depth: float, drop: float) -> void:
	var mid: Vector3 = frame().mid
	var ends := Vector2(reach, reach)
	if kind == Kind.CONE:
		ends = Vector2(sqrt(maxf(0.0, radius * radius - a * a)), sqrt(maxf(0.0, radius * radius - b * b)))
	var pieces := maxi(1, ceili(2.0 * maxf(ends.x, ends.y) / CEILING_PIECE))
	for i in pieces:
		var verts := PackedVector3Array()
		for c in 8:
			var x := a if (c & 1) == 0 else b
			var end := ends.x if (c & 1) == 0 else ends.y
			var z := end * (-1.0 + 2.0 * (i + ((c >> 2) & 1)) / pieces)
			var p := mid + along * x + across * z
			p.y = height_at(p.x, p.z) - drop - depth * (1 - ((c >> 1) & 1))
			verts.append(p)
		var sides := [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [0, 4, 6, 2], [1, 3, 7, 5]]
		for side in sides.size():
			if (side == 0 and i > 0) or (side == 1 and i < pieces - 1):
				continue
			for k in [0, 2, 1, 0, 3, 2]:
				timber_faces.append(verts[sides[side][k]])


func _fly_flag(at: Vector3) -> void:
	var parts := WallLayout.flag(at, FLAG_ALONG, WallLayout.flag_color(seed, 0.0))
	_add(parts.pole, "pole", WallLayout.POLE, 1.0)
	_add(parts.finial, "finial", WallLayout.FINIAL, 1.0)
	cloths.append(parts.cloth)


func _lay_deck(rng: RandomNumberGenerator) -> void:
	var f := frame()
	var reach := deck_reach()
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
	var long := deck_length()
	var basis := Basis(f.along, Vector3.UP, f.across)
	var z := -reach
	var row := 0
	while z < reach - 0.01:
		rng.seed = hash([seed, "deck", row])
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


func _lay_boards(rng: RandomNumberGenerator) -> void:
	var f := frame()
	var reach := deck_reach()
	var long := reach if kind == Kind.CONE else deck_length()
	var top: float = f.mid.y - DECK_DROP
	var basis := Basis(f.along, Vector3.UP, f.across)
	var j := -long + JOIST.x * 0.5
	while j < long:
		var half := sqrt(maxf(0.0, reach * reach - j * j)) if kind == Kind.CONE else reach
		if half > 0.05:
			var p := _on_deck(Vector3(f.mid.x, top - PLANK.y - JOIST.y * 0.5, f.mid.z) + f.along * j, basis)
			_add(Transform3D(p.basis.scaled_local(Vector3(0.08, JOIST.y, half * 2.0)), p.origin), "board", WallLayout.WOOD * rng.randf_range(0.6, 0.7), 0.7)
		j += JOIST.x
	var z := -reach
	var row := 0
	while z < reach - 0.01:
		rng.seed = hash([seed, "boards", row])
		var width := minf(PLANK.x, reach - z)
		var mid := z + width * 0.5
		var half := sqrt(maxf(0.0, reach * reach - mid * mid)) if kind == Kind.CONE else long
		var x := -half - rng.randf_range(0.0, PLANK_LENGTHS.x)
		while x < half - 0.01 and half > 0.02:
			var length := rng.randf_range(PLANK_LENGTHS.x, PLANK_LENGTHS.y)
			var a := maxf(x, -half)
			var b := minf(x + length, half)
			if b - a > 0.05:
				var p := _on_deck(Vector3(f.mid.x, top - PLANK.y * 0.5, f.mid.z) + f.along * ((a + b) * 0.5) + f.across * mid, basis)
				var tilt := p.basis * Basis.from_euler(Vector3(0.0, rng.randf_range(-0.006, 0.006), rng.randf_range(-0.008, 0.008)))
				var colour := WallLayout.WOOD * rng.randf_range(0.82, 1.08)
				_add(Transform3D(tilt.scaled_local(Vector3(b - a - PLANK_GAP, PLANK.y, width - PLANK_GAP)), p.origin + Vector3.UP * rng.randf_range(-0.004, 0.004)), "plank", colour, 0.9)
			x += length
		z += width
		row += 1


func _on_deck(at: Vector3, basis: Basis) -> Transform3D:
	if curve == 0.0:
		return Transform3D(basis, at)
	at.y += height_at(at.x, at.z) - base
	var dx := (height_at(at.x + 0.01, at.z) - height_at(at.x - 0.01, at.z)) / 0.02
	var dz := (height_at(at.x, at.z + 0.01) - height_at(at.x, at.z - 0.01)) / 0.02
	var normal := Vector3(-dx, 1.0, -dz).normalized()
	var across := (basis.x - normal * basis.x.dot(normal)).normalized()
	return Transform3D(Basis(across, normal, across.cross(normal)), at)


## The bed reaches into its neighbours' so no gap, rounded corners' included, opens onto the floor below.
func _slab(at: Vector3, basis: Basis, size: Vector2, rng: RandomNumberGenerator) -> void:
	var on := _on_deck(at, basis)
	at = on.origin
	basis = on.basis
	var b := basis * Basis.from_euler(Vector3(rng.randf_range(-0.01, 0.01), rng.randf_range(-0.02, 0.02), rng.randf_range(-0.01, 0.01)))
	var color := WallLayout.stone_color(rng) * DECK_TONE * rng.randf_range(0.86, 0.98)
	_add(Transform3D(b.scaled_local(Vector3(maxf(0.001, size.x - 0.025), SLAB.y, maxf(0.001, size.y - 0.025))), at + Vector3.UP * rng.randf_range(-0.006, 0.006)), "deck", color, 0.9)
	var bed := Vector3(size.x + BED_LAP, SLAB.y * 0.7, size.y + BED_LAP)
	mortar.append({"xform": Transform3D(basis.scaled_local(bed), at + Vector3.UP * (SLAB.y * 0.2 - bed.y * 0.5)), "color": WallLayout.MORTAR, "kind": "mortar", "ao": 0.8})


func chimney_spot(c: Vector2) -> Vector2:
	var along := maxf(0.0, ridge_length() * 0.5 - STACK_WIDTH)
	var across := maxf(0.0, half_span() - STACK_WIDTH)
	return Vector2(clampf(c.x, -along, along), clampf(c.y, -across, across))


func spot_of(p: Vector3) -> Vector2:
	var f := frame()
	var d: Vector3 = p - f.mid
	return Vector2(d.dot(f.along), d.dot(f.across))


func chimney_top(c: Vector2) -> float:
	return maxf(pitch + 0.7, spot_height(c) + 1.0) + coat_rise()


func spot_height(c: Vector2) -> float:
	return rise(1.0 - absf(c.y) / half_span())


func chimney_parts(c: Vector2, i: int) -> Array[Dictionary]:
	var r := inputs()
	r.corners = corners
	r.base = base
	r._lay_chimney(c, _chimney_rng(i))
	return r.tiles


func _chimney_rng(i: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "chimney", i])
	return rng


func _lay_chimney(c: Vector2, rng: RandomNumberGenerator) -> void:
	var f := frame()
	var stack: Vector3 = f.mid + f.along * c.x + f.across * c.y
	var y := spot_height(c) - 0.3
	var top := chimney_top(c)
	var basis := Basis(f.along, Vector3.UP, f.across)
	while y < top - 0.05:
		var h := minf(rng.randf_range(0.26, 0.34), top - y)
		var stone := WallLayout.stone_color(rng)
		var wobble := Basis.from_euler(Vector3(0.0, rng.randf_range(-0.04, 0.04), 0.0))
		_add(Transform3D((basis * wobble).scaled_local(Vector3(STACK_WIDTH, h, STACK_WIDTH)), stack + Vector3.UP * (y + h * 0.5)), "chimney", stone, 1.0)
		y += h
	_add(Transform3D(basis.scaled_local(Vector3(STACK_WIDTH + 0.14, 0.09, STACK_WIDTH + 0.14)), stack + Vector3.UP * (top + 0.045)), "chimney", Color(0.6, 0.56, 0.5), 1.0)
	for side in [-1.0, 1.0]:
		var pot: Vector3 = stack + f.along * side * STACK_WIDTH * 0.22 + Vector3.UP * (top + 0.21)
		_add(Transform3D(basis.scaled_local(Vector3(0.15, 0.24, 0.15)), pot), "pot", _clay(0.0, rng) * 0.9, 1.0)
		vents.append(pot + Vector3.UP * 0.14)


func hatch_spot(c: Vector2) -> Vector2:
	if not flat():
		return Vector2(NAN, NAN)
	var room := half_span() - WallLayout.THICKNESS * 0.5 - HATCH_CLEAR - HATCH * 0.5
	if kind == Kind.CONE:
		room -= HATCH * 0.5
		if room < 0.0:
			return Vector2(NAN, NAN)
		return c.limit_length(room)
	var along := ridge_length() * 0.5 - WallLayout.THICKNESS * 0.5 - HATCH_CLEAR - HATCH * 0.5
	if room < 0.0 or along < 0.0:
		return Vector2(NAN, NAN)
	return Vector2(clampf(c.x, -along, along), clampf(c.y, -room, room))


func hatch_fits(c: Vector2, placed: Array) -> bool:
	var spot := hatch_spot(c)
	if is_nan(spot.x):
		return false
	var clear := placed.all(func(o: Vector2) -> bool: return not hatches_meet(hatch_spot(o), spot))
	clear = clear and chimneys.all(func(k: Vector2) -> bool: return _square_apart(chimney_spot(k), spot, (HATCH + STACK_WIDTH) * 0.5 + 0.1))
	return clear and (not flag or _square_apart(Vector2.ZERO, spot, HATCH * 0.5 + 0.15))


static func hatches_meet(a: Vector2, b: Vector2) -> bool:
	return not _square_apart(a, b, HATCH + 0.2)


static func _square_apart(a: Vector2, b: Vector2, by: float) -> bool:
	return is_nan(a.x) or is_nan(b.x) or maxf(absf(a.x - b.x), absf(a.y - b.y)) >= by


func hatch_bounds(c: Vector2) -> Array:
	var spot := hatch_spot(c)
	if is_nan(spot.x):
		return []
	return [_hatch_frame(spot), AABB(Vector3(-HATCH * 0.5 - 0.06, -0.02, -HATCH * 0.5 - 0.06), Vector3(HATCH + 0.12, 0.14, HATCH + 0.12))]


func _hatch_frame(spot: Vector2) -> Transform3D:
	var f := frame()
	return _on_deck(f.mid + f.along * spot.x + f.across * spot.y + Vector3.UP * -DECK_DROP, Basis(f.along, Vector3.UP, f.across))


func _lay_hatch(spot: Vector2, rng: RandomNumberGenerator) -> void:
	var at := _hatch_frame(spot)
	var b := at.basis
	var curb := 0.07
	for side in [-1.0, 1.0]:
		_add(Transform3D(b.scaled_local(Vector3(HATCH + curb * 2.0, 0.08, curb)), at * Vector3(0.0, 0.04, side * (HATCH + curb) * 0.5)), "hatch", WallLayout.WOOD * rng.randf_range(0.6, 0.7), 0.9)
		_add(Transform3D(b.scaled_local(Vector3(curb, 0.08, HATCH)), at * Vector3(side * (HATCH + curb) * 0.5, 0.04, 0.0)), "hatch", WallLayout.WOOD * rng.randf_range(0.6, 0.7), 0.9)
	var boards := 4
	for i in boards:
		var z := -HATCH * 0.5 + HATCH * (i + 0.5) / boards
		_add(Transform3D(b.scaled_local(Vector3(HATCH - 0.01, 0.045, HATCH / boards - 0.012)), at * Vector3(0.0, 0.065, z)), "hatch", WallLayout.WOOD * rng.randf_range(0.8, 1.08), 0.9)
	for side in [-1.0, 1.0]:
		_add(Transform3D(b.scaled_local(Vector3(0.05, 0.012, HATCH * 0.8)), at * Vector3(side * HATCH * 0.28, 0.093, 0.0)), "iron", WallLayout.IRON, 1.0)
	_add(Transform3D(b.scaled_local(Vector3(0.1, 0.02, 0.03)), at * Vector3(0.0, 0.095, HATCH * 0.36)), "iron", WallLayout.IRON, 1.0)


func dormer_spot(c: Vector2) -> Vector2:
	var none := Vector2(NAN, NAN)
	if kind != Kind.GABLE or flat():
		return none
	var along := ridge_length() * 0.5 - WallLayout.THICKNESS * 0.5 - DORMER_HALF - DORMER_EAVE - DORMER_CLEAR
	var lo := _dormer_reach()
	var hi := half_span() - WallLayout.THICKNESS * 0.5
	if along < 0.0 or lo > hi:
		return none
	return Vector2(clampf(c.x, -along, along), (-1.0 if c.y < 0.0 else 1.0) * clampf(absf(c.y), lo, hi))


func dormer_fits(c: Vector2, placed: Array) -> bool:
	var spot := dormer_spot(c)
	if is_nan(spot.x):
		return false
	var apart := (DORMER_HALF + DORMER_EAVE) * 2.0 + DORMER_CLEAR
	return (placed.all(func(o: Vector2) -> bool: return spots_apart(dormer_spot(o), spot, apart))
		and chimneys.all(func(k: Vector2) -> bool: return spots_apart(chimney_spot(k), spot, DORMER_HALF + DORMER_EAVE + STACK_WIDTH)))


func clear_of_dormers(c: Vector2) -> bool:
	var spot := chimney_spot(c)
	return dormers.all(func(d: Vector2) -> bool: return spots_apart(spot, dormer_spot(d), DORMER_HALF + DORMER_EAVE + STACK_WIDTH))


static func spots_apart(a: Vector2, b: Vector2, apart: float) -> bool:
	return is_nan(a.x) or is_nan(b.x) or (a.y < 0.0) != (b.y < 0.0) or absf(a.x - b.x) >= apart - 0.001


func _dormer_reach() -> float:
	var hs := half_span()
	var under := pitch - DORMER_TALL - DORMER_PITCH - DORMER_UNDER
	if rise(1.0 - (hs - WallLayout.THICKNESS * 0.5) / hs) > under:
		return INF
	return out_at(under, hs)


func out_at(y: float, hs: float) -> float:
	var lo := 0.0
	var hi := hs
	for i in 24:
		var x := (lo + hi) * 0.5
		if rise(1.0 - x / hs) > y:
			lo = x
		else:
			hi = x
	return hi


func dormer_bounds(c: Vector2) -> Array:
	var spot := dormer_spot(c)
	if is_nan(spot.x):
		return []
	var f := frame()
	var out: Vector3 = f.across * signf(spot.y)
	var x := absf(spot.y)
	var lift := COAT if thatched() else 0.0
	var hs := half_span()
	var dormer_foot := rise(1.0 - x / hs) + lift
	var top := dormer_foot + DORMER_TALL + DORMER_PITCH + 0.15
	var back := x - out_at(dormer_foot + DORMER_TALL - lift, hs)
	var wide := DORMER_HALF + DORMER_EAVE
	var xform := Transform3D(Basis(f.along, Vector3.UP, out), f.mid + f.along * spot.x + out * x)
	return [xform, AABB(Vector3(-wide, dormer_foot - lift - 0.1, -back), Vector3(wide * 2.0, top - dormer_foot + lift + 0.1, back + DORMER_EAVE))]


## Vector2(square metres of boarded front and cheeks, of tiled roof).
func dormer_area(c: Vector2) -> Vector2:
	var spot := dormer_spot(c)
	if is_nan(spot.x):
		return Vector2.ZERO
	var x := absf(spot.y)
	var hs := half_span()
	var depth := x - out_at(rise(1.0 - x / hs) + DORMER_TALL, hs)
	var front := DORMER_HALF * 2.0 * (DORMER_TALL + DORMER_PITCH * 0.5)
	var slope := Vector2(DORMER_HALF + DORMER_EAVE, DORMER_PITCH * (1.0 + DORMER_EAVE / DORMER_HALF)).length()
	return Vector2(front + depth * DORMER_TALL, 2.0 * slope * (depth + DORMER_EAVE))


func dormer_windows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Not yet laid over its walls.
	if corners.size() < 4:
		return out
	var f := frame()
	for c in dormers:
		var spot := dormer_spot(c)
		if is_nan(spot.x):
			continue
		var facing: Vector3 = f.across * signf(spot.y)
		var x := absf(spot.y)
		var dormer_foot := rise(1.0 - x / half_span()) + (COAT if thatched() else 0.0)
		out.append({"at": f.mid + f.along * spot.x + facing * x + Vector3.UP * (dormer_foot + DORMER_SILL), "out": facing, "half": DORMER_WINDOW, "tall": DORMER_TALL - DORMER_HEAD - DORMER_SILL})
	return out


## Its pieces stand a little into the slope (on thatch, into the coat) so no gap opens where they meet it.
func _lay_dormer(c: Vector2, hue: float, rng: RandomNumberGenerator) -> void:
	var spot := dormer_spot(c)
	if is_nan(spot.x):
		return
	var f := frame()
	var hs := half_span()
	var out: Vector3 = f.across * signf(spot.y)
	var x := absf(spot.y)
	var lift := COAT if thatched() else 0.0
	var dormer_foot := rise(1.0 - x / hs) + lift
	var eave_y := dormer_foot + DORMER_TALL
	var ridge_y := eave_y + DORMER_PITCH
	var o: Vector3 = f.mid + f.along * spot.x + out * x
	var sill := dormer_foot + DORMER_SILL
	var head := eave_y - DORMER_HEAD
	var t := -DORMER_HALF
	while t < DORMER_HALF - 0.001:
		var w := minf(DORMER_BOARD.x, DORMER_HALF - t)
		# A board ends at the window's edge, else one half over it is cut whole and leaves a slot beside the frame.
		for edge in [-DORMER_WINDOW, DORMER_WINDOW]:
			if t < edge - 0.001:
				w = minf(w, edge - t)
		var m := t + w * 0.5
		var bottom := rise(1.0 - x / hs) - 0.12
		var top := eave_y + DORMER_PITCH * (1.0 - (absf(m) + w * 0.5) / DORMER_HALF)
		var spans: Array[Vector2] = [Vector2(bottom, top)]
		if absf(m) < DORMER_WINDOW:
			spans = [Vector2(bottom, sill), Vector2(head, top)]
		var colour := WallLayout.WOOD * rng.randf_range(0.82, 1.08)
		for span in spans:
			if span.y - span.x > 0.02:
				_add(Transform3D(Basis(f.along, Vector3.UP, out).scaled_local(Vector3(w - 0.012, span.y - span.x, DORMER_BOARD.y)), o + f.along * m + Vector3.UP * ((span.x + span.y) * 0.5) - out * DORMER_BOARD.y * 0.5), "board", colour, 0.95)
		t += w
	var back := out_at(eave_y - lift, hs)
	for end in [-1.0, 1.0]:
		var side: Vector3 = f.along * end
		var at := x
		while at > back + 0.001:
			var w := minf(DORMER_BOARD.x, at - back)
			var m := at - w * 0.5
			var bottom := rise(1.0 - m / hs) - 0.12
			if eave_y - bottom > 0.02:
				_add(Transform3D(Basis(out, Vector3.UP, side).scaled_local(Vector3(w - 0.012, eave_y - bottom, DORMER_BOARD.y)), f.mid + f.along * spot.x + side * (DORMER_HALF - DORMER_BOARD.y * 0.5) + out * m + Vector3.UP * ((bottom + eave_y) * 0.5)), "board", WallLayout.WOOD * rng.randf_range(0.82, 1.08), 0.95)
			at -= w
	for p in WallLayout.casement(DORMER_WINDOW * 2.0, head - sill, rng, Palette.SWATCHES[Palette.Element.GLOW][0]):
		_add(Transform3D(Basis(f.along, Vector3.UP, out).scaled_local(p.size), o - out * 0.08 + f.along * p.at.x + Vector3.UP * ((sill + head) * 0.5 + p.at.y)), p.kind, p.color, 1.0)
	_add(Transform3D(Basis(f.along, Vector3.UP, out).scaled_local(Vector3(DORMER_WINDOW * 2.0 + 0.16, 0.06, 0.14)), o + Vector3.UP * (sill - 0.03) + out * 0.02), "sill", WallLayout.stone_color(rng), 0.95)
	var slope := atan(DORMER_PITCH / DORMER_HALF)
	for end in [-1.0, 1.0]:
		var down: Vector3 = f.along * end
		var basis := _slope_basis(down, slope)
		var along := DORMER_HALF + DORMER_EAVE
		while along > 0.1:
			var y := ridge_y - along * tan(slope)
			var into := out_at(y - lift, hs) - 0.08
			var run := clampf(along / cos(slope) + NOSE, NOSE * 2.0, TILE.z)
			var a := x + DORMER_EAVE
			while a > into + 0.001:
				var w := minf(TILE.x, a - into)
				_tile(f.mid + f.along * spot.x + down * along + out * (a - w * 0.5) + Vector3.UP * (y + TILE.y * 0.5) + basis.z * (NOSE - run * 0.5), basis, hue, rng, w / TILE.x, run)
				a -= TILE.x
			along -= ROW * cos(slope)
	var ridge_back := out_at(ridge_y - lift, hs)
	var a := x + DORMER_EAVE
	while a > ridge_back + 0.001:
		var w := minf(0.32, a - ridge_back)
		_add(Transform3D(Basis(out, Vector3.UP, f.along).scaled_local(Vector3(w * 1.02, 0.14, 0.3)), f.mid + f.along * spot.x + out * (a - w * 0.5) + Vector3.UP * (ridge_y + 0.05)), "ridge", _clay(hue, rng) * 0.88, 0.95)
		a -= w


func _rows() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x := eave()
	var stop := 0.12 if kind == Kind.CONE else 0.0
	while x > stop:
		out.append(x)
		x -= ROW * cos(slope_at(x - ROW * cos(slope_at(x)) * 0.5))
	return out


func slope_at(x: float) -> float:
	var hs := half_span()
	x = maxf(x, 0.01)
	return atan((rise(1.0 - (x - 0.01) / hs) - rise(1.0 - x / hs)) / 0.01)


func _on_slope(mid: Vector3, out: Vector3, x: float) -> Vector3:
	return mid + out * x + Vector3.UP * rise(1.0 - x / half_span())


func _along(x: float, d: float) -> float:
	var steps := maxi(1, ceili(absf(d) / 0.05))
	for i in steps:
		x = maxf(0.0, x - d / steps * cos(slope_at(x)))
	return x


func _tiled_length() -> float:
	return ridge_length() + WallLayout.THICKNESS + gable_overhang() * 2.0


## The eave row lies on a staggered under-course, as nothing else lies under its joints.
func _lay_gable_row(row: float, stagger: float, hue: float, rng: RandomNumberGenerator, under := 0.0) -> void:
	var f := frame()
	var length := _tiled_length()
	var bed := _bed(row)
	var state := rng.state
	for side in [-1.0, 1.0]:
		rng.state = state
		var out: Vector3 = f.across * side
		var basis := _slope_basis(out, bed.slope)
		var x := -TILE.x * stagger
		while x < length - 0.001:
			var a := maxf(x, 0.0)
			var b := minf(x + TILE.x, length)
			var p: Vector3 = f.mid + f.along * ((a + b - length) * 0.5) + out * bed.at.x + Vector3.UP * bed.at.y + basis.y * (TILE.y * 0.5 - under)
			_tile(p, basis, hue, rng, (b - a) / TILE.x, bed.run)
			x += TILE.x


## Ring counts change, so joints cannot sit over the tiles below: each tile laps its neighbours by CONE_LAP instead.
func _lay_cone_row(row: float, hue: float, rng: RandomNumberGenerator) -> void:
	var f := frame()
	var n := maxi(4, ceili(TAU * row / TILE.x))
	var twist := rng.randf() * TAU
	var bed := _bed(row)
	for i in n:
		var a := twist + TAU * i / n
		var out := Vector3(cos(a), 0.0, sin(a))
		var basis := _slope_basis(out, bed.slope)
		_tile(f.mid + out * bed.at.x + Vector3.UP * bed.at.y + basis.y * TILE.y * 0.5, basis, hue, rng, TAU * row / n / TILE.x * (1.0 + CONE_LAP), bed.run)


static func _slope_basis(out: Vector3, slope: float) -> Basis:
	var down := (out * cos(slope) - Vector3.UP * sin(slope)).normalized()
	var x := Vector3.UP.cross(down).normalized()
	return Basis(x, down.cross(x), down)


func _lay_ridge(hue: float, rng: RandomNumberGenerator) -> void:
	var f := frame()
	var length := _tiled_length()
	var x := 0.0
	while x < length - 0.001:
		var width := minf(0.32, length - x)
		var p: Vector3 = f.mid + f.along * ((x + width * 0.5) - length * 0.5) + Vector3.UP * (pitch + 0.04)
		var basis := Basis(f.along, Vector3.UP, f.across).scaled_local(Vector3(width * 1.02, 0.14, 0.26))
		_add(Transform3D(basis, p), "ridge", _clay(hue, rng) * 0.88, 0.95)
		x += width


## On the chord from NOSE below the row's line to TILE.z up the curve, so neither end of a tile on a curved slope
## dips under the torching.
func _bed(row: float) -> Dictionary:
	var hs := half_span()
	var low := _along(row, -NOSE)
	var high := _along(low, TILE.z)
	var a := Vector2(low, rise(1.0 - low / hs))
	var b := Vector2(high, rise(1.0 - high / hs))
	var run := a.distance_to(b) if high <= 0.0 else TILE.z
	return {"at": (a + b) * 0.5, "slope": atan2(b.y - a.y, a.x - b.x), "run": run}


func _tile(p: Vector3, basis: Basis, hue: float, rng: RandomNumberGenerator, width: float, run: float) -> void:
	var b := basis.rotated(basis.x, -0.05) * Basis.from_euler(Vector3(0.0, rng.randf_range(-0.04, 0.04), rng.randf_range(-0.03, 0.03)))
	_add(Transform3D(b.scaled_local(Vector3(TILE.x * width, TILE.y, run)), p), "tile", _clay(hue, rng), 1.0)


func flag_top() -> Vector3:
	return frame().mid + Vector3.UP * (pitch + coat_rise())


func coat_rise() -> float:
	return _crest().y + ROLL.y if thatched() else 0.0


## Vector2(out from the ridge, over it).
func _crest() -> Vector2:
	var s := slope_at(0.0)
	var depth := COAT + BAND.x
	var up := depth * minf(tan(s), CREST)
	return Vector2(depth * sin(s) - up * cos(s), depth * cos(s) + up * sin(s))


## Unindexed triangles; a vertex's tangent is the way its straw runs. Slabs inside the coat stand in for it in
## shadows and bounce light, which read boxes.
func _lay_thatch(rng: RandomNumberGenerator) -> void:
	var weather := rng.randf_range(0.0, 0.55)
	var lumps := FastNoiseLite.new()
	lumps.seed = seed
	lumps.frequency = 0.8
	var straw := STRAW.lerp(WEATHERED, weather)
	for step in [COAT_STEP, FAR_STEP]:
		var c := Coat.new()
		c.step = step
		c.straw = straw
		c.ridge = STRAW.lerp(WEATHERED, weather * 0.3)
		c.moss = weather * 1.4
		c.lumps = lumps
		if kind == Kind.GABLE:
			_coat_gable(c)
		else:
			_coat_cone(c)
		if step == COAT_STEP:
			coat = c.arrays()
		else:
			coat_far = c.arrays()
	_pick_coat()
	var f := frame()
	if kind == Kind.GABLE:
		for side in [-1.0, 1.0]:
			_coat_liggers(f.mid, f.across * side, _coat_reach())
			_coat_slabs(f.mid, f.across * side, f.along, _coat_reach() * 2.0, straw)
	else:
		for k in 8:
			var a := TAU * k / 8.0
			var out := Vector3(cos(a), 0.0, sin(a))
			_coat_slabs(f.mid, out, out.cross(Vector3.UP), TAU * eave() / 8.0, straw)


func _coat_reach() -> float:
	return ridge_length() * 0.5 + (0.0 if stepped else WallLayout.THICKNESS * 0.5 + THATCH_VERGE)


func _under_rows(step: float) -> PackedFloat32Array:
	return _spaced(half_span() - 0.1, eave() + THATCH_EAVE, step * 2.0)


func _coat_gable(c: Coat) -> void:
	var f := frame()
	var reach := _coat_reach()
	var ts := _edged(_spaced(-reach, reach, c.step))
	var xs := _coat_rows(c.step)
	var under := _under_rows(c.step)
	var ends := _spaced(0.0, eave() + THATCH_EAVE, c.step * 2.0)
	var lengthwise := _spaced(-reach, reach, c.step * 2.0)
	for side in [-1.0, 1.0]:
		var out: Vector3 = f.across * side
		c.grid(ts.size(), xs.size(), func(i: int, j: int) -> Array:
			var t: float = ts[i].x
			return _coat_node(f.mid + f.along * t, out, f.along * signf(t), t, xs[j].x, ts[i].y, xs[j].y, c))
		c.grid(lengthwise.size(), under.size(), func(i: int, j: int) -> Array:
			return _under_node(f.mid + f.along * lengthwise[i], out, under[j]))
		for end in ([] if stepped else [-1.0, 1.0]):
			var gable := _spaced(ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5 - 0.05, reach, c.step)
			c.grid(gable.size(), ends.size(), func(i: int, j: int) -> Array:
				return _under_node(f.mid + f.along * end * gable[i], out, ends[j]))
	_ridge_roll(c, f.mid, f.along, f.across, reach)


func _coat_cone(c: Coat) -> void:
	var f := frame()
	var xs := _coat_rows(c.step)
	var n := maxi(24, ceili(TAU * (eave() + THATCH_EAVE) / (c.step * 1.5)))
	var points := maxi(6, roundi(TAU * BAND.y / POINT.x))
	c.grid(n + 1, xs.size(), func(i: int, j: int) -> Array:
		var a := TAU * i / n
		var out := Vector3(cos(a), 0.0, sin(a))
		return _coat_node(f.mid, out, Vector3.ZERO, float(i) / n * points * POINT.x, xs[j].x, 0.0, xs[j].y, c))
	var under := _under_rows(c.step)
	c.grid(n + 1, under.size(), func(i: int, j: int) -> Array:
		var a := TAU * i / n
		return _under_node(f.mid, Vector3(cos(a), 0.0, sin(a)), under[j]))
	_knob(c, f.mid)


## Vector2(out from the ridge, turn round the eave's edge).
func _coat_rows(step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cut := _along(0.0, -BAND.y)
	var tip := _along(0.0, -(BAND.y + POINT.y))
	var x := 0.0
	var end := eave() + THATCH_EAVE
	while x < end:
		out.append(Vector2(x, 0.0))
		x += step * (0.3 if x > cut - 0.1 and x < tip + 0.06 else 1.0)
	out.append(Vector2(end, 0.0))
	for k in EDGE_STEPS:
		out.append(Vector2(end, PI * (k + 1) / EDGE_STEPS))
	return out


static func _spaced(a: float, b: float, step: float) -> PackedFloat32Array:
	var n := maxi(1, ceili((b - a) / step))
	var out := PackedFloat32Array()
	for i in n + 1:
		out.append(lerpf(a, b, float(i) / n))
	return out


## Vector2(where, turn round the edge).
static func _edged(ts: PackedFloat32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in EDGE_STEPS:
		out.append(Vector2(ts[0], PI * (EDGE_STEPS - k) / EDGE_STEPS))
	for t in ts:
		out.append(Vector2(t, 0.0))
	for k in EDGE_STEPS:
		out.append(Vector2(ts[-1], PI * (k + 1) / EDGE_STEPS))
	return out


## `along`: metres along the ridge, or round a cone at its band.
func _depth(along: float, x: float, at: Vector3, c: Coat) -> float:
	var down := _down(x)
	var phase := absf(fposmod(along / POINT.x, 1.0) * 2.0 - 1.0)
	var cut := BAND.y + POINT.y * (1.0 - phase)
	var band := 1.0 - smoothstep(cut - 0.02, cut + 0.02, down)
	var shaggy := smoothstep(cut, cut + 0.3, down)
	return COAT + BAND.x * band + LUMPS * c.lumps.get_noise_3d(at.x * 1.3, down * 1.7, at.z * 1.3) * shaggy


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


## `a` and `b`: how far it has turned under the end (toward `end`) and under the eave.
func _coat_node(on: Vector3, out: Vector3, end: Vector3, along: float, x: float, a: float, b: float, c: Coat) -> Array:
	var s := slope_at(x)
	var n := out * sin(s) + Vector3.UP * cos(s)
	var fall := out * cos(s) - Vector3.UP * sin(s)
	var surface := _on_slope(on, out, x)
	var depth := _depth(along, x, surface, c)
	if x == 0.0:
		surface -= fall * depth * minf(tan(s), CREST)
	var turn := minf(PI, Vector2(a, b).length())
	var away := (end * a + fall * b).normalized() if turn > 0.0 else Vector3.ZERO
	var p := surface + n * depth * 0.5 + (n * cos(turn) + away * sin(turn)) * depth * 0.5
	var band := depth > COAT + BAND.x * 0.5
	var colour := (c.ridge if band else c.straw) * (1.0 + 0.08 * c.lumps.get_noise_3d(surface.x * 0.5, 40.0, surface.z * 0.5))
	colour.a = 0.0 if band else c.moss
	if turn > PI * 0.5:
		colour = Color(colour.r * 0.7, colour.g * 0.7, colour.b * 0.7, 0.0)
	return [p, n * cos(turn) + away * sin(turn), n.cross(away) if turn > 0.0 else fall, colour]


func _under_node(on: Vector3, out: Vector3, x: float) -> Array:
	var s := slope_at(x)
	var fall := out * cos(s) - Vector3.UP * sin(s)
	var p := _on_slope(on, out, x)
	return [p, -(out * sin(s) + Vector3.UP * cos(s)), fall, Color(STRAW.r * 0.45, STRAW.g * 0.45, STRAW.b * 0.45, 0.0)]


func _ridge_roll(c: Coat, mid: Vector3, along: Vector3, across: Vector3, reach: float) -> void:
	var crest := _crest()
	var wide := crest.x + ROLL.x
	var deep := ROLL.y + wide * tan(slope_at(0.0))
	var centre := mid + Vector3.UP * (pitch + crest.y)
	var ts := _spaced(-reach + 0.05, reach - 0.05, c.step * 2.0)
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


func _coat_liggers(mid: Vector3, out: Vector3, reach: float) -> void:
	for d in [0.16, BAND.y - 0.12]:
		var x := _along(0.0, -d)
		var basis := _slope_basis(out, slope_at(x))
		var at := _on_slope(mid, out, x) + basis.y * (COAT + BAND.x + 0.01)
		_add(Transform3D(basis.scaled_local(Vector3(2.0 * reach - 0.3, 0.035, 0.035)), at), "ligger", HAZEL, 1.0)


func _coat_slabs(mid: Vector3, out: Vector3, along: Vector3, width: float, straw: Color) -> void:
	var end := eave() + THATCH_EAVE
	var xs := _spaced(0.0, end, 0.9)
	for i in xs.size() - 1:
		var x := (xs[i] + xs[i + 1]) * 0.5
		var s := slope_at(x)
		var basis := Basis(along.normalized(), out * sin(s) + Vector3.UP * cos(s), out * cos(s) - Vector3.UP * sin(s))
		var length := (xs[i + 1] - xs[i]) / cos(s)
		var at := _on_slope(mid, out, x) + basis.y * COAT * 0.4
		var crown := at + basis.y * COAT * 0.4
		at.y = minf(at.y, height_at(crown.x, crown.z) + COAT - LUMPS - basis.y.y * COAT * 0.4)
		slabs.append({"xform": Transform3D(basis.scaled_local(Vector3(width, COAT * 0.8, length)), at), "color": straw, "kind": "thatch", "ao": 1.0})


## Nodes are [position, normal, straw direction, colour].
class Coat:
	var step := COAT_STEP
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


func keep_coat(kept: Callable) -> void:
	slabs.assign(slabs.filter(func(s: Dictionary) -> bool: return kept.call(s.xform.origin)))
	if coat.is_empty():
		return
	coat = _kept(coat, kept)
	coat_far = _kept(coat_far, kept)
	_pick_coat()


static func _kept(arrays: Array, kept: Callable) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
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
			out[Mesh.ARRAY_NORMAL].append(arrays[Mesh.ARRAY_NORMAL][i + k])
			out[Mesh.ARRAY_COLOR].append(arrays[Mesh.ARRAY_COLOR][i + k])
			out[Mesh.ARRAY_TANGENT].append_array(arrays[Mesh.ARRAY_TANGENT].slice((i + k) * 4, (i + k) * 4 + 4))
	return out


func _clay(hue: float, rng: RandomNumberGenerator) -> Color:
	var warm := rng.randf_range(-0.05, 0.05) + hue
	return Color(CLAY.r + warm, CLAY.g + warm * 0.4, CLAY.b - warm) * rng.randf_range(0.82, 1.08)


func _add(xform: Transform3D, what: String, color: Color, ao: float) -> void:
	tiles.append({"xform": xform, "color": color, "kind": what, "ao": ao, "variant": tiles.size() % 3})


func surface() -> PackedVector3Array:
	if flat() and curve != 0.0:
		return _deck_surface()
	var tris := PackedVector3Array()
	var f := frame()
	var prof := profile(PROFILE_STEPS)
	if kind == Kind.CONE:
		var seg := 16
		for k in seg:
			var a0 := _ring(k, seg)
			var a1 := _ring(k + 1, seg)
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


static func _ring(k: int, seg: int) -> Vector3:
	return Vector3(cos(TAU * k / seg), 0, sin(TAU * k / seg))


func _deck_surface() -> PackedVector3Array:
	var tris := PackedVector3Array()
	var f := frame()
	var n := PROFILE_STEPS
	if kind == Kind.CONE:
		for i in 16:
			var a := _ring(i, 16)
			var b := _ring(i + 1, 16)
			for j in n:
				var x := half_span() * j / n
				var y := half_span() * (j + 1) / n
				var points: Array[Vector3] = [f.mid + a * x, f.mid + b * x, f.mid + b * y, f.mid + a * y]
				_deck_quad(tris, points)
	else:
		var reach := Vector2(ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5, half_span())
		for i in n:
			for j in n:
				var points: Array[Vector3] = []
				for corner in [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]:
					var p: Vector2 = (corner * 2.0 / n - Vector2.ONE) * reach
					points.append(f.mid + f.along * p.x + f.across * p.y)
				_deck_quad(tris, points)
	return tris


func _deck_quad(tris: PackedVector3Array, points: Array[Vector3]) -> void:
	for i in points.size():
		points[i].y = height_at(points[i].x, points[i].z)
	if not points[0].is_equal_approx(points[1]):
		_facing(tris, Vector3.UP, points[0], points[1], points[2])
	_facing(tris, Vector3.UP, points[0], points[2], points[3])


static func _quad(tris: PackedVector3Array, mid: Vector3, d0: Vector3, d1: Vector3, p: Vector2, q: Vector2) -> void:
	var a := mid + d0 * p.x + Vector3.UP * p.y
	var b := mid + d1 * p.x + Vector3.UP * p.y
	var c := mid + d1 * q.x + Vector3.UP * q.y
	var d := mid + d0 * q.x + Vector3.UP * q.y
	if p.x > 0.0:
		tris.append_array([a, b, c])
	tris.append_array([a, c, d])


## The cap band runs down to the wall body: fitting caps under the eaves can shave them below the roof base. Both
## faces point out of the wall, into the air they read light from.
func gables(inset := WallLayout.PLASTER_INSET) -> PackedVector3Array:
	var tris := PackedVector3Array()
	if kind != Kind.GABLE or flat():
		return tris
	var f := frame()
	var prof := lining()
	var hs := half_span()
	var faces_at := WallLayout.THICKNESS * 0.5 - inset
	var down := Vector3.DOWN * WallLayout.CAP
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
					# A storey resting here hides the roof above this plane, not the band. Cut at the lining's breakpoints:
					# interior.gdshaderinc takes a triangle with every corner outside the room as outside everywhere.
					_facing(tris, facing, a + down, a, b)
					_facing(tris, facing, a + down, b, b + down)
					var top := Vector3.UP * rise(1.0 - x1 / hs)
					_facing(tris, facing, a, a + Vector3.UP * prof[i].y, b + top)
					if top.y > 0.0:
						_facing(tris, facing, a, b + top, b)
	return tris


static func _facing(tris: PackedVector3Array, facing: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	tris.append_array([a, b, c] if (b - a).cross(c - a).dot(facing) < 0.0 else [a, c, b])


func torching() -> PackedVector3Array:
	var tris := PackedVector3Array()
	if flat():
		return tris
	var f := frame()
	var prof := lining()
	var mid: Vector3 = f.mid + Vector3.DOWN * TORCHING_DROP
	var quads: Array[PackedVector3Array] = []
	if kind == Kind.CONE:
		var seg := maxi(16, ceili(TAU * eave() / TORCHING_PIECE))
		for k in seg:
			var a0 := _ring(k, seg)
			var a1 := _ring(k + 1, seg)
			for i in prof.size() - 1:
				var p := prof[i]
				var q := prof[i + 1]
				quads.append(PackedVector3Array([mid + a0 * p.x + Vector3.UP * p.y, mid + a1 * p.x + Vector3.UP * p.y, mid + a1 * q.x + Vector3.UP * q.y, mid + a0 * q.x + Vector3.UP * q.y]))
	else:
		# Stops inside the gable walls: under a verge it would show edge-on from beyond the gable end.
		var length := ridge_length()
		var n := maxi(1, ceili(length / TORCHING_PIECE))
		for side in [-1.0, 1.0]:
			var out: Vector3 = f.across * side
			for i in prof.size() - 1:
				var a: Vector3 = mid + out * prof[i].x + Vector3.UP * prof[i].y
				var b: Vector3 = mid + out * prof[i + 1].x + Vector3.UP * prof[i + 1].y
				for k in n:
					var p: Vector3 = f.along * length * (float(k) / n - 0.5)
					var q: Vector3 = f.along * length * (float(k + 1) / n - 0.5)
					quads.append(PackedVector3Array([a + p, a + q, b + q, b + p]))
	for c in quads:
		if not c[0].is_equal_approx(c[1]):
			_facing(tris, Vector3.DOWN, c[0], c[1], c[2])
		_facing(tris, Vector3.DOWN, c[0], c[2], c[3])
	return tris


func ray_hit(origin: Vector3, dir: Vector3) -> float:
	if thatched():
		var hit := _coat_pick.intersect_ray(origin, dir) if _coat_pick != null else {}
		return origin.distance_to(hit.position) if not hit.is_empty() else INF
	return _nearest(origin, dir, faces)


func gable_hit(origin: Vector3, dir: Vector3) -> float:
	return _nearest(origin, dir, gable_pick)


func _nearest(origin: Vector3, dir: Vector3, tris: PackedVector3Array) -> float:
	var best := INF
	if tris.is_empty() or bounds.grow(0.1).intersects_ray(origin, dir) == null:
		return best
	for i in range(0, tris.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, dir, tris[i], tris[i + 1], tris[i + 2])
		if hit != null and not WallLayout.hidden(hit, joined, resting):
			best = minf(best, origin.distance_to(hit))
	return best


## The coat stands past the tiled bed, so its own triangles are its pick surface.
func _pick_coat() -> void:
	_coat_pick = null
	var vertices: PackedVector3Array = coat[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return
	_coat_pick = TriangleMesh.new()
	_coat_pick.create_from_faces(vertices)
	for vertex in vertices:
		bounds = bounds.expand(vertex)
