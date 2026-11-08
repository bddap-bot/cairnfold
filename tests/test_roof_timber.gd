extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for kind in RoofLayout.Kind.values():
		for curve in [-1.0, 0.0, 1.0]:
			var roof := RoofLayout.new()
			roof.kind = kind
			roof.corners = WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0)
			roof.radius = 2.0
			roof.pitch = 0.0
			roof.curve = curve
			roof.base = 3.0
			roof.build()
			check(not roof.timber_faces.is_empty(), "every flat roof has framing")
			for p in roof.timber_faces:
				check(p.y < roof.height_at(p.x, p.z) - RoofLayout.DECK_DROP - RoofLayout.SLAB.y, "wood remains below the deck")
				check(roof.over(p.x, p.z), "wood stays within walls")
			var job := roof.inputs()
			job.base = roof.base
			job.corners = roof.corners
			job.build()
			var shown := roof.inputs()
			shown.adopt(job)
			check(shown.timber_faces == roof.timber_faces, "worker handoff retains framing")
			roof.pitch = 2.0
			roof.build()
			check(roof.timber_faces.is_empty(), "pulling to pitched removes flat framing")
	var a := WallLayout.new()
	a.closed = true
	a.height = 3.0
	a.points = WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0)
	a.resample(Terrain.flat)
	var r := RoofLayout.new()
	r.corners = a.points
	r.pitch = 0.0
	r.base = a.roof_base()
	r.build()
	var other := Massing.of(a, r)
	a.joined = [other]
	var original := r.timber_faces.duplicate()
	var original_beds := r.mortar.size()
	var original_tiles := r.tiles.size()
	a.hide_roof(r)
	check(r.mortar.size() == original_beds and r.tiles.size() == original_tiles, "older roof keeps the deck and bed that seal its ceiling")
	check(r.timber_faces == original, "older roof keeps its ceiling under an equal-height join")
	a.older = [other]
	r.build()
	a.hide_roof(r)
	check(r.timber_faces.size() < original.size(), "newer roof yields its overlap to the older ceiling")
	var wing := WallLayout.new()
	wing.closed = true
	wing.height = a.height + 0.08
	wing.points = WallLayout.rectangle(Vector3(3, 0, -1), Vector3(6, 0, -1), 4.0)
	wing.resample(Terrain.flat)
	var higher := Massing.of(wing, null)
	a.joined = [higher]
	a.older = []
	r.build()
	var beds := r.mortar.size()
	a.hide_roof(r)
	check(r.mortar.size() > 0 and r.mortar.size() < beds, "offset join removes only the overlapping mortar")
	for bed in r.mortar:
		check(not a.hides(bed.xform.origin), "joined ceiling has no hidden mortar bed blocking its boards")
	var deck := r.mortar + r.tiles.filter(func(t: Dictionary) -> bool: return t.kind == "deck")
	var straddling := 0
	for piece in deck:
		var under := 0
		for c in WallLayout.BOX:
			var p: Vector3 = piece.xform * c
			if Massing.encloses(Vector2(p.x, p.z), higher.centre):
				under += 1
		check(under == 0, "no deck piece hangs under the higher joined ceiling")
		if absf(piece.xform.origin.x - 3.0) < 0.6:
			straddling += 1
	check(straddling > 0, "deck pieces at the higher wall's line are cut back, not taken away")
	# At this ground height the two ways of summing a flush ceiling's height round apart.
	var raised := func(_x: float, _z: float) -> float: return 2.58
	var low := WallLayout.new()
	low.closed = true
	low.height = 5.4
	low.points = a.points
	low.resample(raised)
	var flush := RoofLayout.new()
	flush.corners = low.points
	flush.pitch = 0.0
	flush.base = low.roof_base()
	var beside := WallLayout.new()
	beside.closed = true
	beside.height = 5.4
	beside.points = WallLayout.rectangle(Vector3(3, 0, -1), Vector3(9, 0, -1), 4.0)
	beside.joined = [Massing.of(low, flush)]
	beside.build(raised)
	var room: Massing = beside.joined[0]
	var under := beside.stones.filter(func(st: Dictionary) -> bool:
		var x: Transform3D = st.xform
		return room.holds(x.origin) and x.origin.y - x.basis.y.y * 0.5 < flush.base - 0.01)
	check(under.is_empty(), "a wall joined to a flush flat ceiling keeps no beam below it")
	var mesh := Wall._faces_mesh(original, true)
	check(mesh.get_surface_count() == 1, "all framing has one draw surface")
	finish()
