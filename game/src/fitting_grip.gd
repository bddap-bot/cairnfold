class_name FittingGrip
extends RefCounted

## A placed fitting a grip holds: entry `index` of the list `key` on `wall` (or its roof, `on_roof`), or of path
## `path`'s clutter, or decoration `decoration`. A grip on a piece of clutter another hand holds is a `copy` of it, which
## its build takes as one more entry. Where a hand carries it is pure data, worked out here from where it stood and how
## far the hand moved.

## A carried fitting moves by steps this long and turns by steps this wide, so a wall is laid again only as the fitting
## moves on by a step, and a hand's tremor leaves it where it stood.
const STEP := 0.05
const TURN_STEP := deg_to_rad(5.0)

var wall: Wall
var decoration := -1
var path := -1
var key := ""
var index := -1
var on_roof := false
var copy := false
## A piece of clutter as it was taken, and as the hand shows it now.
var start := Vector4()
var shown := Vector4()


## A wall's `reshape` data setting its list `key`, or its roof's, to `list`.
static func data(key: String, list: Variant, on_roof: bool) -> Dictionary:
	return {"roof": {key: list}} if on_roof else {key: list}


## `list` as the garden stores list `key`.
static func packed(key: String, list: Array) -> Variant:
	return type_convert(list, {"openings": TYPE_PACKED_VECTOR4_ARRAY, "lanterns": TYPE_PACKED_VECTOR3_ARRAY, "flags": TYPE_PACKED_FLOAT32_ARRAY}.get(key, TYPE_PACKED_VECTOR2_ARRAY))


## Openings alone have a size for two hands to set.
func sized() -> bool:
	return key == "openings"


## How far a hand moving `by` and turning `turn` carries a fitting: by whole steps.
static func step(by: Vector3, turn: float) -> Array:
	return [by.snapped(Vector3.ONE * STEP), snappedf(turn, TURN_STEP)]


## Arc length on `l` of a point at `s` carried `by` across the ground.
static func slid(l: WallLayout, s: float, by: Vector3) -> float:
	if is_zero_approx(by.x) and is_zero_approx(by.z):
		return s
	var p: Vector3 = l.frame_at(s).point + Vector3(by.x, 0.0, by.z)
	var near := l.closest_s(p)
	var g := l.frame_at(near)
	return l.wrap(near + (p - g.point).dot(g.tangent))


## Where fitting `v` from list `key` stands carried `by` on wall `w`: an opening, lantern or flag along the wall, a window
## and a lantern up and down it too while a door keeps to its floor and a corner window to its corner; a chimney,
## dormer or trapdoor over the roof.
static func moved(w: Wall, key: String, v: Variant, by: Vector3) -> Variant:
	var l := w.layout
	match key:
		"openings":
			var o: Vector4 = v
			var door: bool = l.opening_for(o).door
			var y := o.y if door else maxf(o.y + by.y, WallLayout.lowest(int(o.z), o.w))
			return Vector4(o.x if o.z == WallLayout.Family.CORNER else slid(l, o.x, by), y, o.z, o.w)
		"lanterns":
			var e: Vector3 = v
			if l.fence:
				return Vector3(l.nearest_post(slid(l, e.x, by)), e.y, e.z)
			return Vector3(slid(l, e.x, by), e.y + by.y, e.z)
		"flags":
			return slid(l, v, by)
	var f := w.roof.frame()
	var c: Vector2 = v + Vector2(by.dot(f.along), by.dot(f.across))
	match key:
		"chimneys":
			return w.roof.chimney_spot(c)
		"hatches":
			return w.roof.hatch_spot(c)
	return w.roof.dormer_spot(c)


## Piece `v` of a build's clutter (ClutterLayout) carried `by` and turned `turn`: along its build by the move's run
## along `tangent` there, out from it or back by the move across, kept `least` to `most` out, and turned with the hand.
static func shifted(v: Vector4, tangent: Vector3, by: Vector3, turn: float, least: float, most: float) -> Vector4:
	var side := 1.0 if v.y >= 0.0 else -1.0
	var out := tangent.cross(Vector3.UP).normalized() * side
	return Vector4(v.x + by.dot(tangent), side * clampf(absf(v.y) + by.dot(out), least, most), wrapf(v.z + turn, -PI, PI), v.w)


## Whether this and `other` hold clutter of one build.
func beside(other: FittingGrip) -> bool:
	return key == "clutter" and other.key == "clutter" and path == other.path and wall == other.wall


## Whether fitting `v` from list `key` stands on `w` beside `others`, the rest of its list, as the tools that place
## them check it; `openings` are the openings standing beside it, paths' arches included.
static func fits(w: Wall, key: String, v: Variant, others: Array, openings: Array[Vector4]) -> bool:
	var l := w.layout
	match key:
		"openings":
			return l.opening_fits(v, openings)
		"lanterns":
			return l.lantern_fits(v.x, v.y)
		"flags":
			return l.flag_fits(v)
		"chimneys":
			return not is_nan(v.x) and w.roof.clear_of_dormers(v)
		"hatches":
			return w.roof.hatch_fits(v, others)
	return not is_nan(v.x) and w.roof.dormer_fits(v, others)


## Decoration `d` carried `by` and turned `turn` about the vertical: along its wall at a house's foot, across the ground,
## or across its floor or deck in its house's plan (`Decorations.plan`), keeping to the floor it stands on; a string
## carried whole, untouched by the turn.
static func carried(d: Dictionary, w: Wall, by: Vector3, turn: float) -> Dictionary:
	var out := d.duplicate()
	var flat := Vector3(by.x, 0.0, by.z)
	match d.mount:
		"foundation":
			out.s = slid(w.layout, d.s, by)
			return out
		"ground":
			out.at = d.at + flat
		"span":
			out.at = d.at + flat
			out.to = d.to + flat
			return out
		_:
			if flat.is_zero_approx():
				out.turn = d.turn + turn
				return out
			var x := Decorations.plan(w)
			var at: Vector3 = x.affine_inverse() * ((x * Vector3(d.at.x, 0.0, d.at.z)) + flat)
			out.at = Vector3(at.x, d.at.y, at.z)
	out.turn = d.turn + turn
	return out
