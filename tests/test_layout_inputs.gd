extends SceneTree

var failures := 0


func _init() -> void:
	var wall := WallLayout.new()
	wall.points = [Vector3.ZERO, Vector3(6, 0, 0)]
	wall.build(func(_x: float, _z: float) -> float: return 0.0)
	var roof := RoofLayout.new()
	roof.corners = WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0)
	roof.build()
	_check(wall.same_inputs(wall.inputs()), "laid wall output does not change its inputs")
	_check(roof.same_inputs(roof.inputs()), "laid roof output and derived footprint do not change its inputs")
	_changes(wall, {
		"points": [Vector3.ZERO, Vector3(7, 0, 0)], "height": 4.0,
		"seed": 19, "closed": true, "top": WallLayout.Top.COPE, "cover": WallLayout.Cover.ROOF,
		"fence": true, "plaster": true, "gable_end": WallLayout.GableEnd.STEPS, "openings": [Vector4(2, 1, 0, 1)], "lanterns": [Vector3(2, 1, 1)],
		"flags": [2.0], "ruins": [Vector2(2, 3)], "supports": [Massing.new()],
		"resting": [Massing.new()], "joined": [Massing.new()], "older": [Massing.new()], "storey_floors": true,
	})
	_changes(roof, {
		"kind": RoofLayout.Kind.CONE, "center": Vector3(1, 0, 1), "radius": 3.0,
		"pitch": 3.0, "curve": 0.5, "seed": 19, "chimneys": [Vector2(1, 1)], "flag": true, "thatch": true,
	})
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _changes(layout: RefCounted, changes: Dictionary) -> void:
	for field in changes:
		var copy: RefCounted = layout.inputs()
		if copy.get(field) is Array:
			copy.get(field).assign(changes[field])
		else:
			copy.set(field, changes[field])
		_check(not layout.same_inputs(copy) and not copy.same_inputs(layout), "%s invalidates reuse in either direction" % field)
		_check(copy.same_inputs(copy.inputs()), "%s survives an independent worker copy" % field)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
