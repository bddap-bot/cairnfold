class_name Gait
extends RefCounted

## Where the two feet of a body tracked only at the head and hands stand: each stays planted where it was set down,
## and one steps at a time once the body's balance leaves the ground the feet cover, or, failing that, once a foot is
## left too far from its place under the body, turned too far from it, or out of the leg's reach. A move too far to walk, a teleport, sets both
## down at once, and with no floor in reach of the hips the feet hang. Distances count in leg lengths, so every avatar
## steps alike at its own size. Positions are in the avatar's pose space, ground heights from `floor`.

## A foot this far from its place under the body steps, however balanced.
const STRIDE := 0.35
const TURN := deg_to_rad(40.0)
const STEP_TIME := 0.3
const LIFT := 0.1
## A foot already this near its place does not step for balance: a step there would not widen the support.
const SETTLED := 0.05
## A foot further from the hips than this many of their standing heights is out of the leg's reach.
const REACH := 1.04
## A foot's sole, out from the ankle's ground point: half its width, its reach forward to the toes and back to the heel.
const SOLE := Vector3(0.08, 0.28, 0.1)
## A move further than this between two poses is a teleport.
const JUMP := 1.5
## Hips higher than this many of their standing heights over the floor leave the feet hanging.
const HANG := 1.25
## How fast the body's velocity, which a step leads by, follows the hips.
const FOLLOW := 10.0

class Foot:
	## The ankle's point on the floor, lifted while stepping.
	var at := Vector3.ZERO
	var yaw := 0.0
	var down := false
	## Into a step, 0 to 1; negative while planted.
	var t := -1.0
	var from := Vector3.ZERO
	var from_yaw := 0.0
	var to := Vector3.ZERO

## Steps for balance; false leaves only the distance and turn rule.
var balance := true
var feet: Array[Foot] = [Foot.new(), Foot.new()]
var leg := 1.0
## The hips' height over the floor standing.
var height := 1.0
var _hips := Vector3.ZERO
var _placed := false
var _velocity := Vector3.ZERO


func _init(leg_length: float, hips_height: float) -> void:
	leg = leg_length
	height = hips_height


## Moves the feet on by `delta` seconds under hips at `hips` turned `yaw`, the centre of mass at `center`; `places` are
## each foot's place under the centre of mass, relative to it.
func update(hips: Vector3, center: Vector3, yaw: float, places: Array[Vector3], floor: Callable, delta: float) -> void:
	var moved := Vector2(hips.x - _hips.x, hips.z - _hips.z).length()
	var jumped := not _placed or moved > JUMP * leg
	if not jumped and delta > 0.0:
		var v := (hips - _hips) / delta
		_velocity = _velocity.lerp(Vector3(v.x, 0.0, v.z), 1.0 - exp(-FOLLOW * delta))
	_hips = hips
	if jumped:
		_placed = true
		_velocity = Vector3.ZERO
		for s in 2:
			_set_down(feet[s], _place(center, places[s]), yaw, floor)
		return
	for s in 2:
		var f := feet[s]
		if f.down and hips.y - f.at.y > HANG * height:
			f.down = false
			f.t = -1.0
		elif not f.down:
			_set_down(f, _place(center, places[s]), yaw, floor)
	var stepping := feet.filter(func(f: Foot) -> bool: return f.t >= 0.0)
	if stepping.is_empty():
		var s := _to_step(center, yaw, places)
		if s < 0:
			return
		var f := feet[s]
		f.t = 0.0
		f.from = f.at
		f.from_yaw = f.yaw
		stepping = [f]
	var f: Foot = stepping[0]
	var place := _place(center, places[feet.find(f)]) + _velocity * STEP_TIME
	var g: float = floor.call(Vector3(place.x, hips.y - 0.4 * height, place.z))
	if not is_finite(g) or hips.y - g > HANG * height:
		f.down = false
		f.t = -1.0
		return
	f.to = Vector3(place.x, g, place.z)
	f.t = minf(f.t + delta / STEP_TIME, 1.0)
	var k := smoothstep(0.0, 1.0, f.t)
	f.at = f.from.lerp(f.to, k) + Vector3.UP * LIFT * leg * sin(PI * f.t)
	f.yaw = lerp_angle(f.from_yaw, yaw, k)
	if f.t >= 1.0:
		f.at = f.to
		f.t = -1.0


## The foot to step now, or -1.
func _to_step(center: Vector3, yaw: float, places: Array[Vector3]) -> int:
	if not feet.all(func(f: Foot) -> bool: return f.down):
		return -1
	var off: Array[float] = []
	for s in 2:
		var p := _place(center, places[s])
		off.append(Vector2(feet[s].at.x - p.x, feet[s].at.z - p.z).length() / leg)
	var order := [0, 1] if off[0] >= off[1] else [1, 0]
	if balance and not supported(center) and off[order[0]] > SETTLED:
		return order[0]
	for s: int in order:
		var out_of_reach := off[s] > SETTLED and _hips.distance_to(feet[s].at) > REACH * height
		if off[s] > STRIDE or out_of_reach or absf(angle_difference(feet[s].yaw, yaw)) > TURN:
			return s
	return -1


## Whether `center`, seen from above, lies over the ground the planted feet's soles cover between them.
func supported(center: Vector3) -> bool:
	var corners := PackedVector2Array()
	for f in feet:
		var b := Basis(Vector3.UP, f.yaw)
		for c: Vector2 in [Vector2(-SOLE.x, -SOLE.y), Vector2(SOLE.x, -SOLE.y), Vector2(SOLE.x, SOLE.z), Vector2(-SOLE.x, SOLE.z)]:
			var p := f.at + b * Vector3(c.x, 0.0, c.y) * leg
			corners.append(Vector2(p.x, p.z))
	return Geometry2D.is_point_in_polygon(Vector2(center.x, center.z), Geometry2D.convex_hull(corners))


static func _place(center: Vector3, off: Vector3) -> Vector3:
	return Vector3(center.x + off.x, center.y, center.z + off.z)


func _set_down(f: Foot, p: Vector3, yaw: float, floor: Callable) -> void:
	var g: float = floor.call(Vector3(p.x, _hips.y - 0.4 * height, p.z))
	f.t = -1.0
	f.yaw = yaw
	f.down = is_finite(g) and _hips.y - g <= HANG * height
	if f.down:
		f.at = Vector3(p.x, g, p.z)
