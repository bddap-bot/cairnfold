extends "res://../tests/support/suite.gd"


func _init() -> void:
	var wall := WallLayout.new()
	wall.points = [Vector3.ZERO, Vector3(6, 0, 0)]
	wall.build(Terrain.flat)
	var roof := RoofLayout.new()
	roof.corners = WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0)
	roof.build()
	check(wall.same_inputs(wall.inputs()), "laid wall output does not change its inputs")
	check(roof.same_inputs(roof.inputs()), "laid roof output and derived footprint do not change its inputs")
	_changes(wall, {
		"points": [Vector3.ZERO, Vector3(7, 0, 0)], "height": 4.0,
		"seed": 19, "closed": true, "top": WallLayout.Top.COPE, "cover": WallLayout.Cover.ROOF,
		"fence": true, "finish": WallLayout.Finish.BOARDS_UPRIGHT, "wear": 0.5, "foundation": WallLayout.Foundation.POSTS, "planks": true, "gable_end": WallLayout.GableEnd.STEPS, "openings": [Vector4(2, 1, 0, 1)], "lanterns": [Vector3(2, 1, 1)],
		"flags": [2.0], "ruins": [Vector2(2, 3)], "supports": [Massing.new()],
		"resting": [Massing.new()], "joined": [Massing.new()], "older": [Massing.new()],
	})
	_changes(roof, {
		"kind": RoofLayout.Kind.CONE, "center": Vector3(1, 0, 1), "radius": 3.0,
		"pitch": 3.0, "curve": 0.5, "seed": 19, "chimneys": [Vector2(1, 1)], "dormers": [Vector2(1, 1.5)], "hatches": [Vector2(0.5, 0.5)], "overhang": 0.8,
		"deck": RoofLayout.Deck.WOOD, "flag": true, "thatch": true,
	})
	finish()


func _changes(layout: RefCounted, changes: Dictionary) -> void:
	for field in changes:
		var copy: RefCounted = layout.inputs()
		if copy.get(field) is Array:
			copy.get(field).assign(changes[field])
		else:
			copy.set(field, changes[field])
		check(not layout.same_inputs(copy) and not copy.same_inputs(layout), "%s invalidates reuse in either direction" % field)
		check(copy.same_inputs(copy.inputs()), "%s survives an independent worker copy" % field)
