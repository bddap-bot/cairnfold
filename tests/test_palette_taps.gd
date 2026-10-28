extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await play([{"op": "place", "x": 0, "z": 4}, {"op": "easel", "x": 0, "z": 2}])
	var tool := main.easel_tool
	var e: Easels.Easel = main.easels.easels.values()[0]
	var blue := Brushwork.absorbance(Brushwork.PIGMENTS[5])
	var yellow := Brushwork.absorbance(Brushwork.PIGMENTS[1])
	for hand in [main.rig.left, main.rig.right]:
		var p := tool.painter(hand)
		for kit: Brushwork.Medium in e.palettes:
			tool._take_brush(p, Brushwork.Brush.BIG, e)
			var source: Vector3 = e.palettes[kit].global_transform * Easels.well(kit, 5)
			var lifted := source + Vector3.UP * 0.1
			for tap in range(1, 13):
				tool._dip(p, lifted)
				tool._dip(p, source)
				check(is_equal_approx(p.load, minf(1.0, tap * 0.1)), "%s tap %d loads %d%%, capped at 100%%: %s" % [EaselTool.PAINTS[kit], tap, tap * 10, p.load])
				check(p.colour.is_equal_approx(blue), "repeated blue taps retain blue")
				var held := p.load
				for frame in 20:
					tool._dip(p, source)
				check(is_equal_approx(p.load, held), "holding contact adds nothing")
				check(is_equal_approx(p.tip.get_shader_parameter("load"), held), "bristles display the actual load")
			for held: float in [0.0, 0.02, 0.2, 0.5, 0.95, 1.0]:
				p.medium = kit
				p.strength = 1.0
				p.load = held
				p.colour = blue
				tool._dip(p, lifted)
				tool._dip(p, e.palettes[kit].global_transform * Easels.well(kit, 1))
				var expected := (blue * held + yellow * 0.1) / (held + 0.1)
				check(p.colour.distance_to(expected) < 1e-4, "%s mixes %.2f blue with 0.1 yellow by load" % [EaselTool.PAINTS[kit], held])
				check(is_equal_approx(p.load, minf(1.0, held + 0.1)), "mixed load is capped")
			tool._take_brush(p, Brushwork.Brush.BIG, e)
			for tap in 5:
				tool._dip(p, lifted)
				tool._dip(p, source)
			tool._dip(p, lifted)
			tool._dip(p, e.palettes[kit].global_transform * Easels.well(kit, 1))
			check(is_equal_approx(p.load, 0.6) and p.colour.distance_to((blue * 5.0 + yellow) / 6.0) < 1e-4, "five blue taps and one yellow give 60%, five parts blue to one yellow")
		tool.dip(p, "jar")
		p.strength = 0.0
		tool.dip(p, "pan5")
		check(p.load == 1.0 and p.colour.is_equal_approx(blue), "pigment colours a full brush of clean water without unloading it")
	finish()
