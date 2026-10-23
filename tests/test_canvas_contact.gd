extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


func pose(tip: Vector3, basis := Basis()) -> Transform3D:
	return Transform3D(basis, tip - basis * ToolModels.BRUSH_TIP)

func _run() -> void:
	var contact := CanvasContact.new()
	contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, 0.1)), false)
	var bent := contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, -0.3)), false)
	var tip: Vector3 = bent.pose * ToolModels.BRUSH_TIP
	check(tip.z >= -CanvasContact.BEND - 0.0001 and tip.z < -CanvasContact.BEND + 0.001, "brush stops at bend limit: %s" % tip)
	check(bent.hard and bent.pressure > 0.98 and absf(tip.z + bent.bend) < 0.0001, "bent bristles end on the sheet, fully pressed")
	var brush := ToolModels.brush(Brushwork.Brush.BIG)
	ToolModels.bend(brush, Brushwork.Brush.BIG, Vector3(0, 0, bent.bend))
	var hair: Node3D = brush.get_node("tip")
	var end := hair.transform * Vector3(0, 0.013, 0)
	check((end - ToolModels.BRUSH_TIP).distance_to(Vector3(0, 0, bent.bend)) < 0.0001, "visible bristles bend to contact")
	brush.free()
	contact.reset()
	contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, 0.1)), true)
	var stick := contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, -0.3)), true)
	tip = stick.pose * ToolModels.BRUSH_TIP
	check(tip.z >= ToolModels.CHARCOAL_RADIUS and tip.z < 0.007, "charcoal stops at sheet: %s" % tip)
	contact.reset()
	contact.move(Transform3D.IDENTITY, pose(Vector3(0.9, 0, -0.02)), true)
	var edge := contact.move(Transform3D.IDENTITY, pose(Vector3(0.6, 0, -0.02)), true)
	tip = edge.pose * ToolModels.BRUSH_TIP
	check(tip.x >= Brushwork.METRES.x * 0.5 + ToolModels.CHARCOAL_RADIUS, "charcoal stops at canvas edge: %s" % tip)
	contact.reset()
	var sideways := Basis(Vector3.UP, PI * 0.5)
	contact.move(Transform3D.IDENTITY, pose(Vector3(-0.125, 0, 0.1), sideways), true)
	var side := contact.move(Transform3D.IDENTITY, pose(Vector3(-0.125, 0, -0.1), sideways), true)
	check(side.on and side.side > 0.99, "side contact covers the length of a parallel stick")
	for angle in [PI * 0.5 - 0.06, PI * 0.5 + 0.06, PI]:
		contact.reset()
		var rotation := Basis(Vector3.UP, angle)
		var lift := maxf(-rotation.z.z * ToolModels.CHARCOAL_LENGTH, 0.0)
		contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, lift + 0.1), rotation), true)
		var tilted := contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, lift - 0.03), rotation), true)
		check(tilted.on and tilted.pressure > 0.99, "either end and shallow side contact stay pressed at angle %f" % angle)
	contact.reset()
	contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, 0.1), sideways), false)
	var flat_brush := contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, -0.1), sideways), false)
	check((flat_brush.pose * ToolModels.BRUSH_TIP).z >= 0.007, "a sideways brush shaft stays outside the canvas")
	var data := {"medium": Brushwork.Medium.CHARCOAL, "brush": Brushwork.Brush.STICK, "load": 1.0}
	var stroker := Brushwork.Stroker.new(data)
	var tap := stroker.add([Vector2(0.3, 0.3), 0.8, 0.0, 0, 0.0])
	for i in 100:
		check(stroker.add([Vector2(0.3, 0.3), 0.8, 0.0, 6, 0.0]).is_empty(), "stationary pressure deposits no additional charcoal")
	var drag := stroker.add([Vector2(0.4, 0.3), 0.8, 0.0, 30, 0.0])
	var deposited := 0.0
	for i in range(0, drag.size(), Brushwork.DAB):
		deposited += drag[i + 5]
	check(tap[5] < deposited * 0.01, "tap much fainter than same-pressure drag: %f vs %f" % [tap[5], deposited])
	var totals := []
	for pieces in [1, 1000]:
		var sampled := Brushwork.Stroker.new(data)
		sampled.add([Vector2(0.3, 0.3), 0.8, 0.0, 0, 0.0])
		var total := 0.0
		for j in range(1, pieces + 1):
			var dabs := sampled.add([Vector2(0.3 + 0.1 * j / pieces, 0.3), 0.8, 0.0, 1, 0.0])
			for k in range(0, dabs.size(), Brushwork.DAB):
				total += dabs[k + 5]
		totals.append(total)
	check(absf(totals[0] - totals[1]) < 0.01, "deposition follows distance, not sample count: %s" % [totals])
	var packed := Brushwork.pack(Vector2(0.3, 0.3), 0.8, 0.6, 6, 1.0)
	var sample := Brushwork.unpack(packed, 0)
	check(sample[4] == 1.0 and sample[3] == 6, "stroke command retains contact angle and tick")
	var side_dab := Brushwork.Stroker.new(data).add(sample)
	check(side_dab[2] > tap[2] * 10.0 and side_dab[4] < side_dab[2] * 0.1, "side footprint longer than tip with a narrow width")
	check(side_dab == Brushwork.Stroker.new(data).add(Brushwork.unpack(packed, 0)), "peer replay produces identical contact footprint")
	finish()
