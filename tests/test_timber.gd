extends "res://../tests/support/suite.gd"


func _init() -> void:
	var wall := Wall.new(1, null)
	wall.layout.points = WallLayout.rectangle(Vector3.ZERO, Vector3(7, 0, 0), 5.0)
	wall.layout.closed = true
	wall.layout.plaster = true
	wall.layout.height = 4.5
	wall.layout.openings = [Vector4(1.8, 1.5, 0, 1), Vector4(5, 0.4, 0, 1), Vector4(9.5, 1.5, 0, 1), Vector4(14, 3, 0, 1), Vector4(14.7, 3, 0, 1)]
	wall.roof = RoofLayout.new()
	var original := wall.data()
	for size in [Vector2(7, 5), Vector2(12, 4), Vector2(4, 9)]:
		var shape := WallTool.house_of(original)
		shape.size = size
		var d := original.duplicate(true)
		var resized := WallTool.reshape_house(original, shape)
		var roof: Dictionary = d.roof.duplicate(true)
		roof.merge(resized.roof, true)
		d.merge(resized, true)
		d.roof = roof
		wall.set_data(d)
		var w := wall.layout
		w.gable = wall.roof
		w.cover = WallLayout.Cover.ROOF
		w.build(Terrain.flat)
		var parts := w.stones.filter(func(p): return p.kind == "timber")
		check(parts.size() > 30, "timber frames walls and gables")
		check(TimberFrame.count(d) == parts.size(), "budget counts the exact generated members after resize")
		check(w.inputs().timber_style == 0 and w.same_inputs(w.inputs()), "worker inputs retain pattern")
		var copy := w.inputs()
		copy.build(Terrain.flat)
		check(copy.stones == w.stones, "layout and colour deterministic")
		for c in w.corners():
			check(parts.any(func(p): return absf(absf(w.offset(p.beam.a.x, c)) - 0.23) < 0.001 and is_equal_approx(p.beam.a.x, p.beam.b.x) and p.beam.a.y < 0.5 and p.beam.b.y > w.height), "full-height corner post survives resize")
		for o in w.apertures:
			for sign_x in [-1, 1]:
				check(parts.any(func(p): return absf(p.s - (o.s + sign_x * (o.half + 0.1252))) < 0.01 and absf(p.xform.basis.x.normalized().y) > 0.99), "opening jamb stud follows resized opening")
			for y: float in [o.head + 0.1252, o.sill - 0.1252]:
				if y < w.course_height():
					continue
				check(parts.any(func(p): return absf(p.y - y) < 0.01 and absf(p.s - o.s) < 0.01 and p.size.x >= o.half * 2.0), "opening head and sill rails follow resized opening")
			for p in parts:
				var frame := w.frame_at(p.beam.face)
				if absf(o.s - p.beam.face) > _side_half(w, p.beam.face):
					continue
				var polygon := PackedVector2Array()
				for corner in [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)]:
					var at: Vector3 = p.xform * corner - frame.point
					polygon.append(Vector2(p.beam.face + at.dot(frame.tangent), at.y))
				var hole := PackedVector2Array([Vector2(o.s-o.half, o.sill), Vector2(o.s+o.half, o.sill), Vector2(o.s+o.half, o.head), Vector2(o.s-o.half, o.head)])
				check(Geometry2D.intersect_polygons(polygon, hole).is_empty(), "rendered timber volume never intersects a window or door")
		check(parts.any(func(p): return p.y > w.height + 0.5), "gable has framing")
		var stone := w.inputs()
		stone.plaster = false
		stone.build(Terrain.flat)
		check(stone.stones.all(func(p): return p.kind != "timber"), "stone houses unchanged")
	var plain := original.duplicate(true)
	plain.timber_style = -1
	check(TimberFrame.count(plain) == 0 and not Budget.wall(plain).has("timber"), "explicit plain plaster has no timber charge")
	var charge := Budget.wall(original)
	check(charge.timber > 0 and Budget.cost_ms({"timber": charge.timber}) > 0, "timber is charged separately")
	check(not Budget.fits({"timber": Budget.CAPACITY_MS * 1000.0 / Budget.TIMBER_US}, {"timber": 1}), "a timber member cannot exceed the remaining frame budget")
	var paint := Palette.plain()
	paint[Palette.Element.PLASTER] = 2
	paint[Palette.Element.TIMBER] = 3
	var timber := {"kind": "timber", "color": TimberFrame.OAK}
	check(Wall._painted_as(timber, paint).is_equal_approx(Palette.swatch(Palette.Element.TIMBER, 3)), "timber uses its own oak family")
	check(PaletteTool.styles(PaletteTool.Restyle.FACE) == 3, "stone, plain plaster and timber are selectable")
	wall.free()
	finish()

func _side_half(w: WallLayout, mid: float) -> float:
	var corners := w.corners()
	corners.append(w.length())
	for i in 4:
		if mid > corners[i] and mid < corners[i+1]:
			return (corners[i+1] - corners[i]) * 0.5
	return 0.0
