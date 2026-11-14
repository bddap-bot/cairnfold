class_name Gait
extends RefCounted

## Feet for a body tracked only at the head and hands. Lengths count in leg lengths or standing hip heights, so every
## avatar steps alike at its own size. Positions are in the avatar's pose space.

const STRIDE_LEGS := 0.35
const TURN := deg_to_rad(40.0)
const STEP_SECONDS := 0.3
const LIFT_LEGS := 0.1
## A step this near its place would not widen the support.
const SETTLED_LEGS := 0.05
const REACH_HEIGHTS := 1.04
## Out from the ankle's ground point: half width, forward to the toes, back to the heel.
const SOLE_LEGS := Vector3(0.08, 0.28, 0.1)
const JUMP_LEGS := 1.5
const HANG_HEIGHTS := 1.25
const FOLLOW := 10.0

class Foot:
	## The ankle's ground point, lifted mid-step.
	var at := Vector3.ZERO
	var yaw := 0.0
	var down := false
	## 0 to 1 into a step; negative while planted.
	var t := -1.0
	var from := Vector3.ZERO
	var from_yaw := 0.0

## Steps for balance; false leaves only the distance and turn rule.
var balance := true
var feet: Array[Foot] = [Foot.new(), Foot.new()]
var leg := 1.0
var height := 1.0
var _hips := Vector3.ZERO
var _placed := false
var _velocity := Vector3.ZERO
var _support := PackedVector2Array()


func _init(leg_length: float, hips_height: float) -> void:
	leg = leg_length
	height = hips_height


## `places` are each foot's place relative to the centre of mass `center`.
func update(hips: Vector3, center: Vector3, yaw: float, places: Array[Vector3], floor: Callable, delta: float) -> void:
	var moved := Vector2(hips.x - _hips.x, hips.z - _hips.z).length()
	var jumped := not _placed or moved > JUMP_LEGS * leg
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
		if f.down and hips.y - f.at.y > HANG_HEIGHTS * height:
			f.down = false
			f.t = -1.0
		elif not f.down:
			_set_down(f, _place(center, places[s]), yaw, floor)
	var f: Foot = feet[0] if feet[0].t >= 0.0 else feet[1] if feet[1].t >= 0.0 else null
	if f == null:
		var s := _to_step(center, yaw, places)
		if s < 0:
			return
		f = feet[s]
		f.t = 0.0
		f.from = f.at
		f.from_yaw = f.yaw
		_support.clear()
	var place := _place(center, places[0 if f == feet[0] else 1]) + _velocity * STEP_SECONDS
	var g: float = floor.call(Vector3(place.x, hips.y - 0.4 * height, place.z))
	if not is_finite(g) or hips.y - g > HANG_HEIGHTS * height:
		f.down = false
		f.t = -1.0
		return
	var to := Vector3(place.x, g, place.z)
	f.t = minf(f.t + delta / STEP_SECONDS, 1.0)
	var k := smoothstep(0.0, 1.0, f.t)
	f.at = f.from.lerp(to, k) + Vector3.UP * LIFT_LEGS * leg * sin(PI * f.t)
	f.yaw = lerp_angle(f.from_yaw, yaw, k)
	if f.t >= 1.0:
		f.at = to
		f.t = -1.0


## The foot to step now, or -1.
func _to_step(center: Vector3, yaw: float, places: Array[Vector3]) -> int:
	if not feet[0].down or not feet[1].down:
		return -1
	var off: Array[float] = []
	for s in 2:
		var p := _place(center, places[s])
		off.append(Vector2(feet[s].at.x - p.x, feet[s].at.z - p.z).length() / leg)
	var order := [0, 1] if off[0] >= off[1] else [1, 0]
	if balance and off[order[0]] > SETTLED_LEGS and not supported(center):
		return order[0]
	for s: int in order:
		var out_of_reach := off[s] > SETTLED_LEGS and _hips.distance_to(feet[s].at) > REACH_HEIGHTS * height
		if off[s] > STRIDE_LEGS or out_of_reach or absf(angle_difference(feet[s].yaw, yaw)) > TURN:
			return s
	return -1


func supported(center: Vector3) -> bool:
	if _support.is_empty():
		var corners := PackedVector2Array()
		for f in feet:
			var b := Basis(Vector3.UP, f.yaw)
			for c: Vector2 in [Vector2(-SOLE_LEGS.x, -SOLE_LEGS.y), Vector2(SOLE_LEGS.x, -SOLE_LEGS.y), Vector2(SOLE_LEGS.x, SOLE_LEGS.z), Vector2(-SOLE_LEGS.x, SOLE_LEGS.z)]:
				var p := f.at + b * Vector3(c.x, 0.0, c.y) * leg
				corners.append(Vector2(p.x, p.z))
		_support = Geometry2D.convex_hull(corners)
	return Geometry2D.is_point_in_polygon(Vector2(center.x, center.z), _support)


static func _place(center: Vector3, off: Vector3) -> Vector3:
	return Vector3(center.x + off.x, center.y, center.z + off.z)


func _set_down(f: Foot, p: Vector3, yaw: float, floor: Callable) -> void:
	_support.clear()
	var g: float = floor.call(Vector3(p.x, _hips.y - 0.4 * height, p.z))
	f.t = -1.0
	f.yaw = yaw
	f.down = is_finite(g) and _hips.y - g <= HANG_HEIGHTS * height
	if f.down:
		f.at = Vector3(p.x, g, p.z)
