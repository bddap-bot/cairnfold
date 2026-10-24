extends "res://../tests/support/suite.gd"


func _hill(x: float, z: float) -> float:
	return 0.15 * x + 0.3 * sin(z)


## Each plaster panel's mitred end meets the next panel's start edge to edge, turned the same way, on a curve over a slope.
func _continuous() -> void:
	var w := WallLayout.new()
	var arc: Array[Vector3] = []
	for i in 13:
		var t := i / 12.0 * PI
		arc.append(Vector3(cos(t) * 5.0, 0.0, sin(t) * 5.0))
	w.points.assign(arc)
	w.height = 3.0
	w.finish = WallLayout.Finish.PLASTER
	w.build(_hill)
	var panels := w.stones.filter(func(s): return s.kind == "plaster")
	check(panels.size() > 3, "a curved plaster wall lays panels")
	var joints := 0
	for a in panels:
		if a.ends.y == 0.0:
			continue
		var x: Transform3D = a.xform
		var edge := x.origin + x.basis.x * 0.5 - x.basis.y * 0.5
		var next := panels.filter(func(b): return (b.xform.origin - b.xform.basis.x * 0.5 - b.xform.basis.y * 0.5).distance_to(edge) < 0.001)
		check(next.size() == 1, "a panel's end meets the next panel's start at %.2f" % a.s)
		if next.size() == 1:
			check(is_equal_approx(next[0].ends.x, -a.ends.y), "the joint turns both panels to one bisector at %.2f" % a.s)
			joints += 1
	check(joints >= panels.size() - 1, "every panel but the last is mitred into the next")


func _init() -> void:
	_continuous()
	for closed in [false, true]:
		for cover in [WallLayout.Cover.OPEN, WallLayout.Cover.ROOF, WallLayout.Cover.DECK]:
			var stone := WallLayout.new()
			stone.points.assign(WallLayout.rectangle(Vector3(-3, 0, 0), Vector3(3, 0, 0), 4.0) if closed else [Vector3.ZERO, Vector3(12, 0, 0)] as Array[Vector3])
			stone.closed = closed
			stone.cover = cover
			stone.height = 4.5
			stone.openings.assign([6.0].map(WallLayout.archway))
			stone.openings.append_array([Vector4(2, 1.6, 0, 1), Vector4(10, 0.4, 0, 1)])
			stone.build(Terrain.flat)
			var plaster := stone.inputs()
			plaster.finish = WallLayout.Finish.PLASTER
			plaster.build(Terrain.flat)
			check(plaster.inputs().finish == WallLayout.Finish.PLASTER and plaster.snapshot().finish == WallLayout.Finish.PLASTER, "workers preserve plaster")
			check(not plaster.same_inputs(stone), "material invalidates cached layout")
			check(plaster.archways() == stone.archways() and plaster.apertures == stone.apertures, "same arches, windows and doors")
			check(plaster.stones.size() < stone.stones.size(), "plaster replaces stones instead of overlaying them")
			var packed := Wall.pack(plaster, Wall.kinds(), Palette.plain())
			var old := Wall.pack(stone, Wall.kinds(), Palette.plain())
			check(packed.stone.size() < old.stone.size() and packed.shadow.size() <= old.shadow.size(), "fewer stone vertices and shadow instances")
			check(packed.mortar.size() <= old.mortar.size() * 2, "plaster splits from the footing's mortar, no finer")
			for panel in plaster.stones.filter(func(s): return s.kind == "plaster"):
				check(panel.y > plaster.course_height(), "stone base retained")
				for o in plaster.apertures:
					check(not (panel.y > o.sill and panel.y < o.head and absf(panel.s - o.s) < (plaster.opening(panel.y, false) if o.style == WallLayout.Family.ARCHWAY else o.half)), "plaster does not fill an opening")
			print("plaster: closed=%s cover=%d pieces %d -> %d" % [closed, cover, stone.stones.size(), plaster.stones.size()])
	var wall := Wall.new(1, null)
	wall.layout.points = [Vector3.ZERO, Vector3(8, 0, 0)]
	wall.layout.finish = WallLayout.Finish.PLASTER
	wall.layout.wear = 0.5
	var data := wall.data()
	var clean: Variant = Commands._wall(data)
	check(clean != null and clean.finish == WallLayout.Finish.PLASTER and clean.wear == 0.5, "commands preserve plaster and its wear")
	var restored := Wall.new(2, null)
	restored.set_data(clean)
	check(restored.layout.finish == WallLayout.Finish.PLASTER and restored.layout.wear == 0.5, "saved plaster restores worn")
	data.erase("finish")
	check(Commands._wall(data) == null, "a wall without a material is rejected")
	data.finish = "plaster"
	check(Commands._wall(data) == null, "reject malformed material")
	wall.free()
	restored.free()
	finish()
