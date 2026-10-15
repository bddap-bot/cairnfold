extends SceneTree

var failures := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

func _flat(_x: float, _z: float) -> float:
	return 0.0

func _init() -> void:
	for closed in [false, true]:
		for cover in [WallLayout.Cover.OPEN, WallLayout.Cover.ROOF, WallLayout.Cover.DECK]:
			var stone := WallLayout.new()
			stone.points.assign(WallLayout.rectangle(Vector3(-3, 0, 0), Vector3(3, 0, 0), 4.0) if closed else [Vector3.ZERO, Vector3(12, 0, 0)] as Array[Vector3])
			stone.closed = closed
			stone.cover = cover
			stone.height = 4.5
			stone.arches = [6.0]
			stone.windows = [Vector2(2, 1.6), Vector2(10, 0.4)]
			stone.build(_flat)
			var plaster := stone.inputs()
			plaster.plaster = true
			plaster.build(_flat)
			_check(plaster.inputs().plaster and plaster.snapshot().plaster, "workers preserve plaster")
			_check(not plaster.same_inputs(stone), "material invalidates cached layout")
			_check(plaster.live_arches == stone.live_arches and plaster.openings == stone.openings, "same arches, windows and doors")
			_check(plaster.stones.size() < stone.stones.size(), "plaster replaces stones instead of overlaying them")
			var packed := Wall.pack(plaster, Wall.kinds())
			var old := Wall.pack(stone, Wall.kinds())
			_check(packed.stone.size() < old.stone.size() and packed.shadow.size() <= old.shadow.size(), "fewer stone vertices and shadow instances")
			_check(packed.mortar.size() == old.mortar.size(), "no extra box instances")
			for panel in plaster.stones.filter(func(s): return s.kind == "plaster"):
				_check(panel.y > plaster.course_height(), "stone base retained")
				for o in plaster.openings:
					_check(not (panel.y > o.sill and panel.y < o.head and absf(panel.s - o.s) < o.half), "plaster does not fill an opening")
			print("plaster: closed=%s cover=%d pieces %d -> %d" % [closed, cover, stone.stones.size(), plaster.stones.size()])
	var wall := Wall.new(1, null)
	wall.layout.points = [Vector3.ZERO, Vector3(8, 0, 0)]
	wall.layout.plaster = true
	var data := wall.data()
	var clean: Variant = Commands._wall(data)
	_check(clean != null and clean.plaster, "commands preserve plaster")
	var restored := Wall.new(2, null)
	restored.set_data(clean)
	_check(restored.layout.plaster, "saved plaster restores")
	data.erase("plaster")
	_check(not Commands._wall(data).plaster, "old gardens remain stone")
	data.plaster = "yes"
	_check(Commands._wall(data) == null, "reject malformed material")
	wall.free()
	restored.free()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
