extends SceneTree

var failures := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

func _flat(_x: float, _z: float) -> float:
	return 0.0

func _init() -> void:
	var wall := Wall.new(1, null)
	wall.layout.points = WallLayout.rectangle(Vector3.ZERO, Vector3(7, 0, 0), 5.0)
	wall.layout.closed = true
	wall.layout.plaster = true
	wall.layout.height = 4.5
	wall.layout.windows = [Vector2(1.8, 1.5), Vector2(5, 0.4), Vector2(9.5, 1.5), Vector2(14, 3), Vector2(14.7, 3)]
	wall.roof = RoofLayout.new()
	var original := wall.data()
	for style in TimberFrame.PATTERNS.size():
		for size in [Vector2(7, 5), Vector2(12, 4), Vector2(4, 9)]:
			var shape := WallTool.house_of(original)
			shape.size = size
			var d := original.duplicate(true)
			var resized := WallTool.reshape_house(original, shape)
			var roof: Dictionary = d.roof.duplicate(true)
			roof.merge(resized.roof, true)
			d.merge(resized, true)
			d.roof = roof
			d.timber_style = style
			wall.set_data(d)
			var w := wall.layout
			w.gable = wall.roof
			w.cover = WallLayout.Cover.ROOF
			w.build(_flat)
			var parts := w.stones.filter(func(p): return p.kind == "timber")
			_check(parts.size() > 30, "each pattern frames walls and gables")
			_check(TimberFrame.count(d) == parts.size(), "budget counts the exact generated members after resize")
			_check(w.inputs().timber_style == style and w.same_inputs(w.inputs()), "worker inputs retain pattern")
			var copy := w.inputs()
			copy.build(_flat)
			_check(copy.stones == w.stones, "layout and colour deterministic")
			for c in w.corners():
				_check(parts.any(func(p): return absf(absf(w.offset(p.beam.a.x, c)) - 0.23) < 0.001 and is_equal_approx(p.beam.a.x, p.beam.b.x) and p.beam.a.y < 0.5 and p.beam.b.y > w.height), "full-height corner post survives resize")
			for o in w.openings:
				for sign_x in [-1, 1]:
					_check(parts.any(func(p): return absf(p.s - (o.s + sign_x * (o.half + 0.1252))) < 0.01 and absf(p.xform.basis.x.normalized().y) > 0.99), "opening jamb stud follows resized opening")
				for y: float in [o.head + 0.1252, o.sill - 0.1252]:
					if y < w.course_height():
						continue
					_check(parts.any(func(p): return absf(p.y - y) < 0.01 and absf(p.s - o.s) < 0.01 and p.size.x >= o.half * 2.0), "opening head and sill rails follow resized opening")
				for p in parts:
					var frame := w.frame_at(p.beam.face)
					if absf(o.s - p.beam.face) > _side_half(w, p.beam.face):
						continue
					var polygon := PackedVector2Array()
					for corner in [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)]:
						var at: Vector3 = p.xform * corner - frame.point
						polygon.append(Vector2(p.beam.face + at.dot(frame.tangent), at.y))
					var hole := PackedVector2Array([Vector2(o.s-o.half, o.sill), Vector2(o.s+o.half, o.sill), Vector2(o.s+o.half, o.head), Vector2(o.s-o.half, o.head)])
					_check(Geometry2D.intersect_polygons(polygon, hole).is_empty(), "rendered timber volume never intersects a window or door")
			_check(parts.any(func(p): return p.y > w.height + 0.5), "gable has framing")
			var stone := w.inputs()
			stone.plaster = false
			stone.build(_flat)
			_check(stone.stones.all(func(p): return p.kind != "timber"), "stone houses unchanged")
			var other := stone.inputs()
			other.timber_style = (style + 1) % TimberFrame.PATTERNS.size()
			other.build(_flat)
			_check(stone.stones == other.stones, "pattern cannot change stone geometry or colour")
	var plain := original.duplicate(true)
	plain.timber_style = -1
	_check(TimberFrame.count(plain) == 0 and not Budget.wall(plain).has("timber"), "explicit plain plaster has no timber charge")
	var charge := Budget.wall(original)
	_check(charge.timber > 0 and Budget.cost_ms({"timber": charge.timber}, Budget.Device.QUEST_2) > 0, "timber is charged separately")
	_check(not Budget.fits({"timber": Budget.room_ms(Budget.Device.QUEST_2) * 1000.0 / Budget.TIMBER_US}, {"timber": 1}, [Budget.Device.QUEST_2]), "a timber member cannot exceed the remaining frame budget")
	var paint := Palette.plain()
	paint[Palette.Element.PLASTER] = 2
	paint[Palette.Element.TIMBER] = 3
	var timber := {"kind": "timber", "color": TimberFrame.OAK}
	_check(Wall._painted_as(timber, paint).is_equal_approx(Palette.swatch(Palette.Element.TIMBER, 3)), "timber uses its own oak family")
	_check(PaletteTool.styles(PaletteTool.Restyle.FACE) == 7, "all five patterns are selectable")
	wall.free()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)

func _side_half(w: WallLayout, mid: float) -> float:
	var corners := w.corners()
	corners.append(w.length())
	for i in 4:
		if mid > corners[i] and mid < corners[i+1]:
			return (corners[i+1] - corners[i]) * 0.5
	return 0.0
