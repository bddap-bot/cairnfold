extends SceneTree

var failures := 0


func _init() -> void:
	_wall_growth_keeps_interior_stones()
	_edge_stones_grow_without_splitting()
	_height_keeps_lower_courses()
	_openings_keep_their_courses()
	_house_faces_keep_their_stones()
	_square_keeps_ridge()
	_roof_growth_keeps_tiles()
	_flat_roof_growth_keeps_slabs()
	_wall_tops_keep_their_pieces()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _wall(length: float, height: float) -> WallLayout:
	var w := WallLayout.new()
	w.points = [Vector3.ZERO, Vector3(length, 0, 0)]
	w.height = height
	w.seed = 17
	w.build(func(_x, _z): return 0.0)
	return w


func _wall_growth_keeps_interior_stones() -> void:
	var a := _wall(5.0, 2.4)
	for length in [5.2, 5.4, 5.8, 6.0]:
		var b := _wall(length, 2.4)
		for stone in a.stones:
			if stone.kind != "block" or stone.s > 3.0:
				continue
			_check(b.stones.any(func(s): return s.kind == stone.kind and s.color == stone.color and s.variant == stone.variant and s.xform.is_equal_approx(stone.xform)), "extending the far end preserves each interior stone")
		for stone in a.stones:
			if stone.kind == "pier" and stone.s == 0.0:
				_check(b.stones.has(stone), "extending the far end preserves the first pier")


func _height_keeps_lower_courses() -> void:
	var a := _wall(5.0, 2.549)
	for height in [2.551, 2.7, 2.701, 3.0]:
		var b := _wall(5.0, height)
		for stone in a.stones:
			if stone.kind == "block" and stone.y < 2.4:
				_check(b.stones.has(stone), "raising a wall preserves its lower courses")


func _square_keeps_ridge() -> void:
	var a := WallTool.footprint(Vector3.ZERO, 0.0, Vector2(4.501, 4.5))
	var b := WallTool.footprint(Vector3.ZERO, 0.0, Vector2(4.499, 4.5))
	_check((a.b - a.a).normalized().dot((b.b - b.a).normalized()) > 0.999, "two millimetres through square cannot turn the ridge")


func _roof(length: float) -> RoofLayout:
	var r := RoofLayout.new()
	r.corners = WallLayout.rectangle(Vector3.ZERO, Vector3(length, 0, 0), 4.5)
	r.build()
	return r


func _roof_growth_keeps_tiles() -> void:
	var a := _roof(5.0)
	for length in [5.2, 5.4, 5.8, 6.0]:
		var b := _roof(length)
		for tile in a.tiles:
			if tile.kind != "tile" or tile.xform.origin.x > 4.5:
				continue
			_check(b.tiles.any(func(t): return t.kind == tile.kind and t.color == tile.color and t.xform.is_equal_approx(tile.xform)), "extending the roof preserves interior tiles on both slopes")


func _edge_stones_grow_without_splitting() -> void:
	var previous := _wall(5.0, 0.9)
	for i in 20:
		var next := _wall(5.0 + (i + 1) * 0.02, 0.9)
		for stone in previous.stones:
			if stone.kind != "block":
				continue
			var start: float = stone.s - stone.size.x * 0.5
			var same := next.stones.filter(func(s): return s.kind == "block" and is_equal_approx(s.y, stone.y) and absf(s.s - s.size.x * 0.5 - start) < 0.0001)
			_check(not same.is_empty() and same[0].size.x >= stone.size.x - 0.0001, "a growing edge stone cannot split and shrink")
		previous = next


func _flat_roof_growth_keeps_slabs() -> void:
	var a := _roof(5.0)
	a.pitch = 0.0
	a.build()
	var b := _roof(5.2)
	b.pitch = 0.0
	b.build()
	for slab in a.tiles:
		if slab.kind == "deck" and slab.xform.origin.x < 4.0:
			_check(b.tiles.any(func(s): return s.kind == slab.kind and s.color == slab.color and s.xform.is_equal_approx(slab.xform)), "extending a flat roof preserves interior slabs")
	for i in 20:
		var r := _roof(5.0 + i * 0.01)
		r.pitch = 0.0
		r.build()
		var frame := r.frame()
		for slab in r.tiles:
			if slab.kind == "deck":
				_check(slab.xform.basis.x.dot(frame.along) > 0.0 and slab.xform.basis.z.dot(frame.across) > 0.0, "clipped flat roof slabs cannot turn inside out")


func _openings_keep_their_courses() -> void:
	var w := _wall(8.0, 3.0)
	w.arches = [2.0]
	w.windows = [Vector2(5.5, 1.65)]
	w.build(func(_x, _z): return 0.0)
	var opening := w.openings.duplicate(true)
	var ring := w.stones.filter(func(s): return s.kind == "voussoir" or s.kind == "keystone")
	w.height = 3.15
	w.points[1].x = 8.2
	w.build(func(_x, _z): return 0.0)
	_check(w.openings == opening, "a window stays on its course when the wall grows")
	for stone in ring:
		_check(w.stones.any(func(s): return s.kind == stone.kind and s.color == stone.color and s.variant == stone.variant and s.xform.is_equal_approx(stone.xform)), "growth elsewhere cannot reshuffle an arch ring")


func _wall_tops_keep_their_pieces() -> void:
	for deck in [false, true]:
		var a := _wall(5.0, 2.4)
		a.top = WallLayout.Top.CAP if deck else WallLayout.Top.CRENEL
		a.cover = WallLayout.Cover.DECK if deck else WallLayout.Cover.OPEN
		a.build(func(_x, _z): return 0.0)
		var b := a.inputs()
		b.points[1].x = 6.0
		b.build(func(_x, _z): return 0.0)
		for stone in a.stones:
			if stone.y > a.height and stone.s < 3.0:
				_check(b.stones.any(func(s): return s.kind == stone.kind and s.color == stone.color and s.xform.is_equal_approx(stone.xform)), "extending the wall preserves its interior top pieces")
	for style in [WallLayout.Top.CRENEL, WallLayout.Top.COPE]:
		var kind := "merlon" if style == WallLayout.Top.CRENEL else "cope"
		var previous := _wall(5.0, 2.4)
		previous.top = style
		previous.build(func(_x, _z): return 0.0)
		for i in 40:
			var next := _wall(5.0 + (i + 1) * 0.02, 2.4)
			next.top = style
			next.build(func(_x, _z): return 0.0)
			for stone in next.stones:
				if stone.kind != kind:
					continue
				var start: float = stone.s - stone.size.x * 0.5
				var existed := previous.stones.any(func(s): return s.kind == kind and absf(s.s - s.size.x * 0.5 - start) < 0.0001)
				_check(existed or stone.size.x <= 0.0201, "a new edge top stone grows instead of appearing whole")
			previous = next


func _house_faces_keep_their_stones() -> void:
	var layouts := []
	for length in [5.0, 5.2]:
		var w := WallLayout.new()
		w.points = WallLayout.rectangle(Vector3.ZERO, Vector3(length, 0, 0), 4.5)
		w.closed = true
		w.height = 2.4
		w.build(func(_x, _z): return 0.0)
		layouts.append(w)
	var checked := 0
	for stone in layouts[0].stones:
		if stone.kind == "block" and stone.xform.origin.x < 0.1 and stone.s > 14.5:
			checked += 1
			_check(layouts[1].stones.any(func(s): return s.kind == stone.kind and s.color == stone.color and s.xform.is_equal_approx(stone.xform)), "stretching another side preserves the unchanged end wall")
	_check(checked > 30, "the unchanged end wall comparison covers several courses")
