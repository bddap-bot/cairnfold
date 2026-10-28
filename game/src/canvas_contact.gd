class_name CanvasContact
extends RefCounted

const BEND := 0.012
const STEP := 0.004
const SKIN := 0.001
## The canvas's sheet and the board behind it, as wide, high and deep as `fit` takes.
const SHEET := Vector3(Brushwork.METRES.x, Brushwork.METRES.y, 0.032)
var previous := Vector3.INF
## The surface met: its paint's size in metres, the solid under it (wide, high, deep) and whether that is an oval.
var metres := Brushwork.METRES
var solid_size := SHEET
var oval := false
var basis := Basis()
var stick := false
var box := AABB()
var axis := Vector3.ZERO
var shaft_box := AABB()
var hit_box := AABB()


func reset() -> void:
	previous = Vector3.INF


## Meets a surface whose paint is `paint` metres across, lying on a solid `solid` wide, high and deep, with `round` an
## oval inside that; the canvas's sheet until told otherwise.
func fit(paint: Vector2, solid: Vector3, round := false) -> void:
	reset()
	metres = paint
	solid_size = solid
	oval = round


## Where a brush of `kind`, held at `tracked` (its own frame, as `ToolModels.brush` builds it), meets the surface whose
## frame is `frame` (x along it, y up it, z out of its face), stopped at its face.
func move(frame: Transform3D, tracked: Transform3D, kind: Brushwork.Brush) -> Dictionary:
	var local := frame.affine_inverse() * tracked
	stick = Brushwork.is_stick(kind)
	var radius: float = Brushwork.STICKS[kind].x if stick else 0.0
	var length: float = Brushwork.STICKS[kind].y if stick else 0.255
	var sheet := AABB(Vector3(-solid_size.x * 0.5, -solid_size.y * 0.5, -solid_size.z), solid_size)
	box = sheet.grow(radius)
	if not stick:
		# The bristles bend BEND into the face before the ferrule stops; a thin board still stops it a sweep's steps deep.
		box.position.z = minf(box.position.z, -BEND - STEP * 2.0)
		box.end = Vector3(box.end.x, box.end.y, -BEND)
	shaft_box = sheet.grow(0.0075)
	axis = local.basis.z * length
	var target := local * ToolModels.BRUSH_TIP
	var from := previous
	# A tool clear in front of the sheet is free, however the last stop caught it: wedged on a back corner, every sweep
	# from there would stop at once.
	if from == Vector3.INF or target.z > 0.0 and not solid(target):
		from = target
		if solid(from):
			from.z = maxf(box.end.z, shaft_box.end.z if not stick else box.end.z) + maxf(0.0, -axis.z) + SKIN
	elif solid(from):
		# A rotation into the sheet keeps the last clear orientation until translation frees it.
		local.basis = basis
		axis = basis.z * length
		target = local * ToolModels.BRUSH_TIP
	var at := HandStop.resolve(from, target, solid, normal, STEP)
	previous = at
	basis = local.basis
	local.origin = at - local.basis * ToolModels.BRUSH_TIP
	var near := at
	var side := 0.0
	if stick:
		var tilt := absf(axis.normalized().z)
		side = clampf(1.0 - tilt / 0.12, 0.0, 1.0)
		near += axis * (0.5 if tilt < 0.001 else (0.5 * side if axis.z >= 0.0 else 1.0 - 0.5 * side))
		near.z -= radius
	var height := at.z + minf(axis.z, 0.0) - radius if stick else near.z
	var on := _over(near, sheet) and height <= SKIN and height >= -BEND - SKIN
	var bend := clampf(-near.z, 0.0, BEND) if not stick and on else 0.0
	var pressure := Brushwork.pressure(radius - target.z - minf(axis.z, 0.0) if stick else -target.z)
	var across := axis if stick else local.basis.x
	var angle := atan2(-across.y, across.x)
	return {"pose": frame * local, "point": frame * Vector3(near.x, near.y, 0), "uv": Vector2(near.x / metres.x + 0.5, 0.5 - near.y / metres.y), "on": on, "pressure": pressure, "bend": bend, "hard": on and (stick or pressure > 0.999), "angle": angle, "side": side}


func hit(p: Vector3) -> Variant:
	hit_box = box
	if box.has_point(p) and _over(p, box):
		return p
	if stick:
		return _on(box.intersects_segment(p, p + axis))
	hit_box = shaft_box
	var start := p + axis.normalized() * 0.026
	return start if shaft_box.has_point(start) and _over(start, shaft_box) else _on(shaft_box.intersects_segment(start, p + axis))


## Whether `p` lies over the face of `b`, within its oval for a round surface.
func _over(p: Vector3, b: AABB) -> bool:
	var half := Vector2(b.size.x, b.size.y) * 0.5
	var at := Vector2(p.x, p.y) - Vector2(b.get_center().x, b.get_center().y)
	if absf(at.x) > half.x or absf(at.y) > half.y:
		return false
	return not oval or (at / half).length_squared() <= 1.0


func _on(point: Variant) -> Variant:
	return point if point != null and _over(point, hit_box) else null


func solid(p: Vector3) -> bool:
	return hit(p) != null


func normal(p: Vector3) -> Vector3:
	var point: Variant = hit(p)
	if point == null:
		return Vector3.ZERO
	var best := INF
	var facing := Vector3.ZERO
	for i in 3:
		for end in 2:
			var distance: float = absf(point[i] - (hit_box.end[i] if end else hit_box.position[i]))
			if distance < best:
				best = distance
				facing = Vector3.ZERO
				facing[i] = 1.0 if end else -1.0
	return facing
