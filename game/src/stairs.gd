class_name Stairs
extends Node3D

var masonry: Masonry
var layouts := {}
## The railings new flights and landings are laid with: the style last turned to on this machine.
var rail := "stone"
var _growing := {}
var _data := {}

func _init(shared: Masonry) -> void:
	masonry = shared

func put(id: int, data: Dictionary) -> void:
	_data[id] = data
	var layout := StairLayout.new()
	layout.build(data)
	layouts[id] = layout
	var shown := Stones.new()
	shown.lay(layout.stones)
	shown.reveal(0)
	add_child(shown)
	_growing[id] = {"node": shown, "count": 0.0, "shown": -1}

func take(id: int) -> void:
	_data.erase(id)
	layouts.erase(id)
	if _growing.has(id):
		_growing[id].node.queue_free()
		_growing.erase(id)
	masonry.remove(-1000000 - id)

func _process(delta: float) -> void:
	for id: int in _growing.keys():
		var growth: Dictionary = _growing[id]
		var layout: StairLayout = layouts[id]
		growth.count += delta * 80.0
		var n := mini(int(growth.count), layout.stones.size())
		if n == growth.shown:
			continue
		growth.shown = n
		growth.node.reveal(n)
		if n == layout.stones.size():
			_place(id)

## Lays stairs as the garden has them again, whole at once.
func settle(id: int) -> void:
	show_reshaped(id, {})

## Lays stairs whole as a reshape with `data` would leave them, through the layout that lays the reshape itself.
func show_reshaped(id: int, data: Dictionary) -> void:
	var layout := StairLayout.new()
	layout.build(World.reshaped(_data[id], data))
	layouts[id] = layout
	_place(id)

func _place(id: int) -> void:
	var wall := WallLayout.new()
	wall.stones = layouts[id].stones
	var packed := Wall.pack(wall, Wall.kinds(), Palette.plain())
	var parts: Array[Dictionary] = []
	for k in Wall.Part.size():
		parts.append(packed.chunks.get(k, {}))
	masonry.place(-1000000 - id, parts)
	if _growing.has(id):
		_growing[id].node.queue_free()
		_growing.erase(id)

func laying() -> bool:
	return not _growing.is_empty()

## The nearest stone of any stairs along a ray short of `reach`, as {stair, point, along, kind, side} (the stone's,
## `side` whether a side of it was struck), or empty.
func pick(origin: Vector3, direction: Vector3, reach: float) -> Dictionary:
	var best := {}
	for id: int in layouts:
		var layout: StairLayout = layouts[id]
		var near: Variant = layout.bounds.intersects_ray(origin, direction)
		if near == null and not layout.bounds.has_point(origin) or near != null and origin.distance_to(near) >= reach:
			continue
		for piece: Dictionary in layout.stones:
			var x: Transform3D = piece.xform
			var inverse := x.affine_inverse()
			var box := AABB(-Vector3.ONE * 0.5, Vector3.ONE)
			var hit: Variant = box.intersects_ray(inverse * origin, inverse.basis * direction)
			if hit != null:
				var point: Vector3 = x * hit
				var distance := origin.distance_to(point)
				if distance < reach:
					reach = distance
					var side := Rig.side(inverse.basis.transposed() * Rig.box_normal(box, hit))
					best = {"stair": id, "point": point, "along": distance, "kind": piece.kind, "side": side}
	return best


## The highest tread under `p` no more than a step above it, or -INF.
func floor_under(p: Vector3) -> float:
	var y := -INF
	for layout: StairLayout in layouts.values():
		var t := layout.surface(p)
		if t <= p.y + StairLayout.RISE:
			y = maxf(y, t)
	return y
