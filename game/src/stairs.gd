class_name Stairs
extends Node3D

var masonry: Masonry
var layouts := {}
var _growing := {}

func _init(shared: Masonry) -> void:
	masonry = shared

func put(id: int, data: Dictionary) -> void:
	var layout := StairLayout.new()
	layout.build(data)
	layouts[id] = layout
	var shown := Stones.new()
	shown.lay(layout.stones)
	shown.reveal(0)
	add_child(shown)
	_growing[id] = {"node": shown, "count": 0.0, "shown": -1}

func take(id: int) -> void:
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
			var wall := WallLayout.new()
			wall.stones = layout.stones
			var packed := Wall.pack(wall, Wall.kinds(), Palette.plain())
			var parts: Array[Dictionary] = []
			for k in Wall.Part.size():
				parts.append(packed.chunks.get(k, {}))
			masonry.place(-1000000 - id, parts)
			growth.node.queue_free()
			_growing.erase(id)

func laying() -> bool:
	return not _growing.is_empty()

## The nearest stone of any stairs along a ray short of `reach`, as {stair, point, along}, or empty.
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
			var hit: Variant = AABB(-Vector3.ONE * 0.5, Vector3.ONE).intersects_ray(inverse * origin, inverse.basis * direction)
			if hit != null:
				var point: Vector3 = x * hit
				var distance := origin.distance_to(point)
				if distance < reach:
					reach = distance
					best = {"stair": id, "point": point, "along": distance}
	return best


## The highest tread under `p` no more than a step above it, or -INF.
func floor_under(p: Vector3) -> float:
	var y := -INF
	for layout: StairLayout in layouts.values():
		var t := layout.surface(p)
		if t <= p.y + StairLayout.RISE:
			y = maxf(y, t)
	return y
