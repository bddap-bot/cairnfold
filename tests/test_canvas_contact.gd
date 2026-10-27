extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


func pose(tip: Vector3, basis := Basis()) -> Transform3D:
	return Transform3D(basis, tip - basis * ToolModels.BRUSH_TIP)

func _run() -> void:
	var contact := CanvasContact.new()
	contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, 0.1)), Brushwork.Brush.BIG)
	var bent := contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, -0.3)), Brushwork.Brush.BIG)
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
	contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, 0.1)), Brushwork.Brush.STICK)
	var stick := contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, -0.3)), Brushwork.Brush.STICK)
	tip = stick.pose * ToolModels.BRUSH_TIP
	check(tip.z >= Brushwork.STICKS[Brushwork.Brush.STICK].x and tip.z < 0.007, "charcoal stops at sheet: %s" % tip)
	contact.reset()
	contact.move(Transform3D.IDENTITY, pose(Vector3(0.9, 0, -0.02)), Brushwork.Brush.STICK)
	var edge := contact.move(Transform3D.IDENTITY, pose(Vector3(0.6, 0, -0.02)), Brushwork.Brush.STICK)
	tip = edge.pose * ToolModels.BRUSH_TIP
	check(tip.x >= Brushwork.METRES.x * 0.5 + Brushwork.STICKS[Brushwork.Brush.STICK].x, "charcoal stops at canvas edge: %s" % tip)
	contact.reset()
	var sideways := Basis(Vector3.UP, PI * 0.5)
	contact.move(Transform3D.IDENTITY, pose(Vector3(-0.125, 0, 0.1), sideways), Brushwork.Brush.STICK)
	var side := contact.move(Transform3D.IDENTITY, pose(Vector3(-0.125, 0, -0.1), sideways), Brushwork.Brush.STICK)
	check(side.on and side.side > 0.99, "side contact covers the length of a parallel stick")
	for angle in [PI * 0.5 - 0.06, PI * 0.5 + 0.06, PI]:
		contact.reset()
		var rotation := Basis(Vector3.UP, angle)
		var lift := maxf(-rotation.z.z * Brushwork.STICKS[Brushwork.Brush.STICK].y, 0.0)
		contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, lift + 0.1), rotation), Brushwork.Brush.STICK)
		var tilted := contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, lift - 0.03), rotation), Brushwork.Brush.STICK)
		check(tilted.on and tilted.pressure > 0.99, "either end and shallow side contact stay pressed at angle %f" % angle)
	_pushing_in_presses_harder()
	_a_stick_pushed_in_lies_on_its_side()
	contact.reset()
	contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, 0.1), sideways), Brushwork.Brush.BIG)
	var flat_brush := contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, -0.1), sideways), Brushwork.Brush.BIG)
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
	check(side_dab[2] > tap[2] * 5.0 and side_dab[4] <= tap[2] * 1.01, "side footprint longer than tip with a narrow width: %s / %s" % [side_dab.slice(0, 5), tap.slice(0, 5)])
	var sent := {"medium": Brushwork.Medium.CHARCOAL, "brush": Brushwork.Brush.STICK, "colour": Vector3.ZERO, "strength": 1.0, "load": 1.0, "gap": 0, "samples": packed}
	var arrived: Variant = Brushwork.clean(bytes_to_var(var_to_bytes(sent)))
	check(arrived != null and Brushwork.Stroker.new(arrived).add(Brushwork.unpack(arrived.samples, 0)) == side_dab, "peer replay produces identical contact footprint")
	finish()


## How far a tool is pushed past the canvas is how hard it presses, by one curve for the stick's tip, its side and a
## brush: a graze presses lightly, a push of `Brushwork.PRESS_DEPTH` fully, and the stick seen in the hand stays on the
## canvas's face however far the hand goes.
func _pushing_in_presses_harder() -> void:
	var lean := Basis(Vector3.RIGHT, -PI * 0.25)
	var tools := {"tip": [Brushwork.Brush.THICK_STICK, lean], "side": [Brushwork.Brush.THIN_STICK, Basis(Vector3.UP, PI * 0.5)], "brush": [Brushwork.Brush.BIG, Basis()]}
	for what: String in tools:
		var kind: Brushwork.Brush = tools[what][0]
		var basis: Basis = tools[what][1]
		var radius: float = Brushwork.STICKS[kind].x if Brushwork.is_stick(kind) else 0.0
		var lowest := minf(0.0, (basis.z * (Brushwork.STICKS[kind].y if Brushwork.is_stick(kind) else 0.0)).z) - radius
		var pressures := []
		for depth in [0.001, Brushwork.PRESS_DEPTH * 0.5, Brushwork.PRESS_DEPTH, Brushwork.PRESS_DEPTH * 3.0]:
			var contact := CanvasContact.new()
			contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, 0.1 - lowest), basis), kind)
			var pushed := contact.move(Transform3D.IDENTITY, pose(Vector3(0, 0, -depth - lowest), basis), kind)
			pressures.append(pushed.pressure)
			check(pushed.on, "the %s touches pushed %.3f m in" % [what, depth])
			if Brushwork.is_stick(kind):
				var seen: float = (pushed.pose * ToolModels.BRUSH_TIP).z + lowest
				check(seen > -0.0015, "the %s seen pushed %.3f m in stays on the canvas's face: %.4f" % [what, depth, seen])
		check(pressures[0] < 0.1, "the %s grazing presses lightly: %s" % [what, pressures])
		check(pressures[0] < pressures[1] and pressures[1] < pressures[2], "the %s presses harder the farther it is pushed: %s" % [what, pressures])
		check(pressures[2] > 0.999 and pressures[3] > 0.999, "the %s presses fully at the press depth and past it: %s" % [what, pressures])


## A stick held as a hand holds it and laid on its side, pushed in: a wrist rolled either way about the aim keeps its side
## on the canvas, since a stick leaned off the aim sweeps a cone the canvas is tangent to, and turned about the canvas's
## facing through half a turn its mark turns with it.
func _a_stick_pushed_in_lies_on_its_side() -> void:
	for kind: Brushwork.Brush in Brushwork.STICKS:
		var length: float = Brushwork.STICKS[kind].y
		var hold := ToolModels.hold(kind)
		var flat := Basis.looking_at(Vector3.LEFT, Vector3.BACK)
		var stick := Transform3D(flat, Vector3(-length * 0.5, 0, Brushwork.STICKS[kind].x) - flat * ToolModels.BRUSH_TIP)
		var hand := stick * hold.affine_inverse()
		for roll in [-20.0, 0.0, 20.0]:
			var rolled := Transform3D(hand.basis * Basis(Vector3.FORWARD, deg_to_rad(roll)), hand.origin)
			var contact := CanvasContact.new()
			contact.move(Transform3D.IDENTITY, (rolled * hold).translated(Vector3(0, 0, 0.1)), kind)
			var lying := 0
			var turning := 0
			for i in 13:
				var held := (Transform3D(Basis(Vector3.BACK, PI * i / 12.0)) * rolled * hold).translated(Vector3(0, 0, -Brushwork.PRESS_DEPTH))
				var c := contact.move(Transform3D.IDENTITY, held, kind)
				if c.on and c.side > 0.7:
					lying += 1
				if absf(Brushwork.turn(atan2(-held.basis.z.y, held.basis.z.x), c.angle)) < 0.05:
					turning += 1
			var name: String = Brushwork.Brush.keys()[kind]
			check(lying == 13, "the %s rolled %.0f degrees and pushed in lies on its side: %d of 13" % [name, roll, lying])
			check(turning == 13, "the %s rolled %.0f degrees turns its mark as it turns: %d of 13" % [name, roll, turning])
