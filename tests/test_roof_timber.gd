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
			var copy := roof.inputs()
			copy.adopt(roof)
			check(copy.timber_faces == roof.timber_faces, "worker handoff retains framing")
			roof.pitch = 2.0
			roof.build()
			check(roof.timber_faces.is_empty(), "pulling to pitched removes flat framing")
	var a := WallLayout.new()
	a.closed = true
	a.height = 3.0
	a.points = WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0)
	a.resample(func(_x: float, _z: float): return 0.0)
	var r := RoofLayout.new()
	r.corners = a.points
	r.pitch = 0.0
	r.base = a.samples[0].y + a.height + WallLayout.CAP
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
	wing.resample(func(_x: float, _z: float): return 0.0)
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
	var mesh := Wall._faces_mesh(original, true)
	check(mesh.get_surface_count() == 1, "all framing has one draw surface")
	finish()
