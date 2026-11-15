class_name StairLayout
extends RefCounted

enum Kind { FLIGHT, LADDER, LANDING, BRIDGE }
## (least, most); at the least a bridge is a single rope.
const WIDTH := Vector2(0.6, 3.0)
const RISE := 0.2
## The deepest tread, so a long gentle flight climbs in many low steps rather than a few long ones.
const TREAD := 0.45
const LADDER_SLOPE := 1.5
const LEVEL := 0.08
const RAIL_HEIGHT := 0.85
## In the style tool's order.
const RAILS := ["stone", "wood", "rope", "none"]
## Metres of mid-span sag per metre spanned, within SAG_LEAST and SAG_MOST.
const SAG := 0.07
const SAG_MOST := 2.0
const SAG_LEAST := 0.03
const HANG_CLEAR := 1.0
const HANG_SLOPE := 0.3
const HANG_LEAST := 2.0
const HANG_KEEP := 0.15
const LIP := 0.3
const PLANK_PITCH := 0.22
## (depth along the bridge, thickness).
const PLANK := Vector2(0.18, 0.045)
const ROPE := 0.04
const HEMP := Color(0.56, 0.47, 0.33)

var stones: Array[Dictionary] = []
## What a ray meets: the stones, but a bridge's deck with no gaps between its planks.
var solids: Array[Dictionary] = []
var kind := Kind.FLIGHT
var treads: Array[Vector3] = []
var bounds := AABB()
var _foot := Vector3.ZERO
var _along := Vector3.FORWARD
var _side := Vector3.RIGHT
var _run := 0.0
var _depth := 1.0
var _width := 0.0
var _paint: PackedInt32Array
var _rise := 0.0
var _sag := 0.0

static func classify(d: Dictionary) -> Kind:
	if d.sag > 0.0:
		return Kind.BRIDGE
	var run := Vector2(d.b.x - d.a.x, d.b.z - d.a.z).length()
	var rise := absf(d.b.y - d.a.y)
	if rise <= LEVEL:
		return Kind.LANDING
	return Kind.LADDER if rise > run * LADDER_SLOPE else Kind.FLIGHT

static func railed(d: Dictionary) -> bool:
	return d.rail != "none" and can_rail(d)

static func can_rail(d: Dictionary) -> bool:
	return classify(d) != Kind.LADDER and not single(d)

static func single(d: Dictionary) -> bool:
	return classify(d) == Kind.BRIDGE and d.width <= WIDTH.x + 0.001

static func spans(a: Vector3, b: Vector3) -> bool:
	var run := Vector2(b.x - a.x, b.z - a.z).length()
	return run >= HANG_LEAST and absf(b.y - a.y) <= run * HANG_SLOPE

static func sag_fits(a: Vector3, b: Vector3, sag: float) -> bool:
	return sag == 0.0 or spans(a, b) and sag >= SAG_LEAST and sag <= minf(Vector2(b.x - a.x, b.z - a.z).length() * SAG, SAG_MOST) + 0.001

## The sag, 0 where it stands as stairs. `under(p)`: the top of ground or build at or below p; `water(x, z)`: the pond
## surface, below ground off a pond.
static func sag_over(a: Vector3, b: Vector3, width: float, under: Callable, water: Callable) -> float:
	if not spans(a, b):
		return 0.0
	var run := Vector2(b.x - a.x, b.z - a.z).length()
	var side := Vector3(b.x - a.x, 0, b.z - a.z).normalized().cross(Vector3.UP) * width * 0.5
	var room := SAG_MOST
	var wet_middle := false
	var clear_middle := true
	var n := maxi(8, ceili(run / 0.4))
	for i in range(1, n):
		var t := float(i) / n
		var middle := t > 0.25 and t < 0.75
		for offset in [Vector3.ZERO, side, -side]:
			var p: Vector3 = a.lerp(b, t) + offset
			var dry: float = under.call(p)
			var wet: float = water.call(p.x, p.z)
			var top := maxf(dry, wet)
			if p.y < top - (0.0 if middle else LIP):
				return 0.0
			if middle:
				wet_middle = wet_middle or wet > dry
				clear_middle = clear_middle and p.y - dry >= HANG_CLEAR
			elif p.y - top < HANG_KEEP:
				continue
			room = minf(room, (p.y - top - HANG_KEEP) / (4.0 * t * (1.0 - t)))
	if not wet_middle and not clear_middle:
		return 0.0
	return clampf(minf(run * SAG, room), SAG_LEAST, SAG_MOST)

func build(d: Dictionary) -> void:
	stones.clear()
	treads.clear()
	solids = stones
	var a: Vector3 = d.a
	var b: Vector3 = d.b
	if a.y > b.y:
		var swap := a
		a = b
		b = swap
	kind = classify(d)
	var run := Vector2(b.x - a.x, b.z - a.z).length()
	var rise := b.y - a.y
	var along := Vector3(b.x - a.x, 0, b.z - a.z).normalized() if run > 0.001 else Vector3.FORWARD
	var side := along.cross(Vector3.UP)
	var basis := Basis(side, Vector3.UP, -along)
	var width: float = d.width
	_foot = a
	_along = along
	_side = side
	_run = run
	_width = width
	_paint = d.paint
	_rise = rise
	_sag = d.sag
	var rng := RandomNumberGenerator.new()
	rng.seed = d.seed
	if kind == Kind.BRIDGE:
		_bridge(d, basis, rng)
		_bound()
		return
	if kind == Kind.LADDER:
		var n := maxi(1, ceili(rise / 0.28))
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			treads.append(p)
			_piece(p, basis, Vector3(width, 0.09, 0.12), "wood", rng)
		for sign_x: float in [-1.0, 1.0]:
			_beam(a + side * width * sign_x * 0.5, b + side * width * sign_x * 0.5 + (b - a).normalized() * 0.5, 0.11, "wood", rng)
		_bound()
		return
	var n := maxi(maxi(1, ceili(run / TREAD)), ceili(rise / RISE) if kind == Kind.FLIGHT else 0)
	var depth := run / n
	_depth = depth
	var columns := maxi(1, ceili(width / 0.5))
	for i in n:
		var p := a + along * (i + 0.5) * depth
		p.y = lerpf(a.y, b.y, float(i + 1) / n)
		treads.append(p)
		var height := maxf(p.y - a.y, 0.12)
		for col in columns:
			var centre := p + side * ((col + 0.5) / columns - 0.5) * width
			centre.y -= height * 0.5
			_piece(centre, basis, Vector3(width / columns - 0.015, height, depth + 0.02), "stone", rng)
	if railed(d):
		var posts := maxi(1, ceili(run / 1.0))
		for sign_x: float in [-1.0, 1.0]:
			var offset: Vector3 = side * (width * 0.5 - 0.06) * sign_x
			for i in posts + 1:
				var p := a.lerp(b, float(i) / posts) + offset
				var under := floori((float(i) / posts * run - 0.06) / depth)
				var base := a.y if under < 0 else treads[mini(under, n - 1)].y
				var tall := p.y + RAIL_HEIGHT - base
				_piece(Vector3(p.x, base + tall * 0.5, p.z), basis, Vector3(0.12, tall, 0.12), "wood" if d.rail == "rope" else d.rail, rng)
			if d.rail == "rope":
				_rope(a + offset + Vector3.UP * RAIL_HEIGHT, b + offset + Vector3.UP * RAIL_HEIGHT, ROPE, rng)
			else:
				_beam(a + offset + Vector3.UP * RAIL_HEIGHT, b + offset + Vector3.UP * RAIL_HEIGHT, 0.12, d.rail, rng)
	_bound()


## `t` runs from the lower end (0) to the upper (1).
func deck(t: float) -> Vector3:
	return _foot + _along * _run * t + Vector3.UP * (_rise * t - _sag * 4.0 * t * (1.0 - t))


func _bridge(d: Dictionary, basis: Basis, rng: RandomNumberGenerator) -> void:
	var single_rope := single(d)
	var edges: Array[float] = [0.0]
	if not single_rope:
		edges.assign([-(_width * 0.5 - 0.08), _width * 0.5 - 0.08])
	var n := maxi(2, ceili(_run / PLANK_PITCH))
	_depth = _run / n
	var deck_boxes: Array[Dictionary] = []
	for i in n:
		var t := (i + 0.5) / n
		treads.append(deck(t))
		if single_rope:
			continue
		var chord := deck(t + 0.5 / n) - deck(t - 0.5 / n)
		var slope := chord.normalized()
		var up := _side.cross(slope).normalized()
		var tilt := Basis(_side, up, -slope).rotated(up, rng.randf_range(-0.04, 0.04))
		var plank := Vector3(_width * rng.randf_range(0.96, 1.0), PLANK.y, PLANK.x * rng.randf_range(0.85, 1.0))
		var at := deck(t) - up * PLANK.y * 0.5 + _side * rng.randf_range(-0.02, 0.02)
		_piece(at, tilt, plank, "wood", rng)
		deck_boxes.append({"xform": Transform3D(Basis(_side, up, -slope).scaled_local(Vector3(_width, PLANK.y, chord.length())), deck(t) - up * PLANK.y * 0.5), "kind": "rail"})
	var planks := stones.size()
	var under := Vector3.DOWN * (0.0 if single_rope else PLANK.y + ROPE * 0.5)
	for edge in edges:
		_strung(func(t: float) -> Vector3: return deck(t) + _side * edge + under, ROPE * (1.5 if single_rope else 1.0), rng)
	var rails := railed(d)
	var anchor := "stone" if d.rail == "stone" else "wood"
	for end in [0.0, 1.0]:
		for edge in edges:
			var top := deck(end) + _side * edge
			var tall := (RAIL_HEIGHT if rails else 0.4) + 0.4
			var post := Vector3(0.32, tall, 0.32) if anchor == "stone" else Vector3(0.12, tall, 0.12)
			_piece(top + Vector3.UP * (tall * 0.5 - 0.4), basis, post, anchor, rng)
	var bays := maxi(1, ceili(_run / 1.2))
	if rails:
		for edge in edges:
			var rail := func(t: float) -> Vector3: return deck(t) + _side * edge + Vector3.UP * RAIL_HEIGHT
			if d.rail == "wood":
				for i in range(1, bays):
					var foot := deck(float(i) / bays) + _side * edge
					_piece(foot + Vector3.UP * RAIL_HEIGHT * 0.5, basis, Vector3(0.1, RAIL_HEIGHT, 0.1), "wood", rng)
				for i in bays:
					_beam(rail.call(float(i) / bays), rail.call(float(i + 1) / bays), 0.1, "wood", rng)
				continue
			_strung(rail, ROPE, rng)
			for i in range(1, bays * 2):
				var t := float(i) / (bays * 2)
				_rope(rail.call(t), deck(t) + _side * edge + under, ROPE * 0.6, rng)
				if d.rail == "rope" and i % 2 == 0:
					var foot := deck(t) + _side * edge
					_piece(foot + Vector3.UP * RAIL_HEIGHT * 0.5, basis, Vector3(0.09, RAIL_HEIGHT, 0.09), "wood", rng)
	deck_boxes.append_array(stones.slice(planks))
	solids = deck_boxes


func _strung(along: Callable, thickness: float, rng: RandomNumberGenerator) -> void:
	var n := maxi(2, ceili(_run / 0.5))
	for i in n:
		_rope(along.call(float(i) / n), along.call(float(i + 1) / n), thickness, rng)


## NAN beside the flight, landing or bridge, and on a ladder, which is climbed, not walked.
func surface(p: Vector3) -> float:
	if kind == Kind.LADDER or treads.is_empty():
		return NAN
	var rel := p - _foot
	var s := rel.dot(_along)
	if s < 0.0 or s > _run or absf(rel.dot(_side)) > _width * 0.5:
		return NAN
	if kind == Kind.BRIDGE:
		return deck(s / _run).y
	return treads[clampi(int(s / _depth), 0, treads.size() - 1)].y


func _bound() -> void:
	bounds = AABB()
	for i in stones.size():
		var box: AABB = stones[i].xform * AABB(-Vector3.ONE * 0.5, Vector3.ONE)
		bounds = box if i == 0 else bounds.merge(box)

func _piece(at: Vector3, basis: Basis, size: Vector3, material: String, rng: RandomNumberGenerator) -> void:
	var kind := "block" if material == "stone" else "rail"
	var element: Palette.Element = Palette.KINDS[kind]
	var color := Color(0.62, 0.58, 0.5) if material == "stone" else Color(0.42, 0.27, 0.14)
	stones.append({"xform": Transform3D(basis.scaled_local(size), at), "color": color * Palette.tint(element, _paint[element]) * rng.randf_range(0.88, 1.05), "ao": 0.9, "variant": 0, "kind": kind})

func _beam(a: Vector3, b: Vector3, thickness: float, material: String, rng: RandomNumberGenerator) -> void:
	_piece((a + b) * 0.5, _lengthwise(a, b), Vector3(thickness, a.distance_to(b), thickness), material, rng)

## Rope keeps its hemp whatever the paint, as iron and flags keep theirs.
func _rope(a: Vector3, b: Vector3, thickness: float, rng: RandomNumberGenerator) -> void:
	var size := Vector3(thickness, a.distance_to(b) + thickness, thickness)
	stones.append({"xform": Transform3D(_lengthwise(a, b).scaled_local(size), (a + b) * 0.5), "color": HEMP * rng.randf_range(0.9, 1.05), "ao": 0.9, "variant": 0, "kind": "rope"})

static func _lengthwise(a: Vector3, b: Vector3) -> Basis:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.UP).normalized()
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	return Basis(x, y, x.cross(y))
