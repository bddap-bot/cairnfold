class_name StairLayout
extends RefCounted

enum Kind { FLIGHT, LADDER, LANDING }
const WIDTH := Vector2(0.6, 3.0)
const RISE := 0.2
## The deepest a tread runs, so a long, gentle flight climbs in many low steps rather than a few long ones.
const TREAD := 0.45
const LADDER_SLOPE := 1.5
const LEVEL := 0.08
const RAIL_HEIGHT := 0.85
## A flight's or landing's railings, as the style tool offers them.
const RAILS := ["stone", "wood", "none"]

var stones: Array[Dictionary] = []
var kind := Kind.FLIGHT
var treads: Array[Vector3] = []
## Everything laid, for a ray to skip the stones of a build it misses.
var bounds := AABB()
var _foot := Vector3.ZERO
var _along := Vector3.FORWARD
var _side := Vector3.RIGHT
var _run := 0.0
var _depth := 1.0
var _width := 0.0
var _paint: PackedInt32Array

static func classify(a: Vector3, b: Vector3) -> Kind:
	var run := Vector2(b.x - a.x, b.z - a.z).length()
	var rise := absf(b.y - a.y)
	if rise <= LEVEL:
		return Kind.LANDING
	return Kind.LADDER if rise > run * LADDER_SLOPE else Kind.FLIGHT

## Whether stairs `d` lay railings: a ladder never does.
static func railed(d: Dictionary) -> bool:
	return d.rail != "none" and classify(d.a, d.b) != Kind.LADDER

func build(d: Dictionary) -> void:
	stones.clear()
	treads.clear()
	var a: Vector3 = d.a
	var b: Vector3 = d.b
	if a.y > b.y:
		var swap := a
		a = b
		b = swap
	kind = classify(a, b)
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
	var rng := RandomNumberGenerator.new()
	rng.seed = d.seed
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
				_piece(Vector3(p.x, base + tall * 0.5, p.z), basis, Vector3(0.12, tall, 0.12), d.rail, rng)
			_beam(a + offset + Vector3.UP * RAIL_HEIGHT, b + offset + Vector3.UP * RAIL_HEIGHT, 0.12, d.rail, rng)
	_bound()


## The height of the tread over `p`, or NAN beside the flight or landing. A ladder is climbed, not walked: NAN.
func surface(p: Vector3) -> float:
	if kind == Kind.LADDER or treads.is_empty():
		return NAN
	var rel := p - _foot
	var s := rel.dot(_along)
	if s < 0.0 or s > _run or absf(rel.dot(_side)) > _width * 0.5:
		return NAN
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
	var y := (b - a).normalized()
	var x := y.cross(Vector3.UP).normalized()
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	_piece((a + b) * 0.5, Basis(x, y, x.cross(y)), Vector3(thickness, a.distance_to(b), thickness), material, rng)
