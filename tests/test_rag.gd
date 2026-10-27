extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await play([{"op": "place", "x": 0, "z": 4}, {"op": "easel", "x": 0, "z": 2}])
	var e: Easels.Easel = main.easels.easels.values()[0]
	var tool := main.easel_tool
	var act: int = Cues.Act.get("BRUSH_WIPE", -1)
	check(act >= 0, "a rag wipe has its own Cues action")
	if act >= 0:
		check(Cues.TABLE[act].sound == "" and Cues.TABLE[act].feel == [0.3, 0.045, 1, 0.0], "a wipe is one distinct silent pulse")
	for hand in [main.rig.left, main.rig.right]:
		var p := tool.painter(hand)
		p.brush = Brushwork.Brush.BIG
		p.colour = Brushwork.absorbance(Brushwork.PIGMENTS[3])
		p.strength = 1.0
		for medium in [Brushwork.Medium.OIL, Brushwork.Medium.WATER]:
			p.medium = medium
			p.load = 1.0
			var at := Easels.RAG.get_center()
			var above := at + Vector3.UP * 0.1
			var calls: int = Cues.asked.get(act, 0)
			var pulses: int = Cues.pulsed.get(act, {}).get(hand.get_instance_id(), 0)
			tool._wipe(p, e, e.tray(above))
			tool._wipe(p, e, e.tray(at))
			check(is_equal_approx(p.load, 0.75), "a straight dab unloads a quarter in medium %d" % medium)
			check(Cues.asked.get(act, 0) == calls + 1 and Cues.pulsed.get(act, {}).get(hand.get_instance_id(), 0) == pulses + 1, "the dab pulses only its hand")
			tool._wipe(p, e, e.tray(at + Vector3(0.05, 0, 0)))
			tool._wipe(p, e, e.tray(at))
			check(is_equal_approx(p.load, 0.75) and Cues.asked.get(act, 0) == calls + 1, "press and drag unloads only once before lifting")
			tool._wipe(p, e, e.tray(above))
			tool._wipe(p, e, e.tray(at))
			check(is_equal_approx(p.load, 0.5), "lifting rearms the next dab")
			check(e.rag.get_shader_parameter("stained"), "a successful dab stains the cloth")
			tool._wipe(p, e, e.tray(above))
			p.load = 1.0
			var skim := at + Vector3(0, 0.008, 0)
			tool._wipe(p, e, e.tray(skim))
			check(p.load == 1.0, "a shallow stationary touch does not unload")
			tool._wipe(p, e, e.tray(skim + Vector3(0.04, 0, 0)))
			check(is_equal_approx(p.load, 0.75), "a lateral wipe also unloads without a deep dab")
			tool._wipe(p, e, e.tray(above))
			p.load = 1.0
			var front := Vector3(at.x, Easels.TRAY_Y - 0.04, Easels.TRAY.end.z + 0.003)
			tool._wipe(p, e, e.tray(front))
			check(is_equal_approx(p.load, 0.75), "a dab into the hanging cloth unloads too")
			tool._wipe(p, e, e.tray(above))
			p.load = 1.0
			tool._wipe(p, e, e.tray(front + Vector3(0, 0, 0.04)))
			check(p.load == 1.0, "air in front of the hanging cloth does not unload")
			for load in [0.25, 0.15, 0.1, 0.0]:
				p.load = load
				calls = Cues.asked.get(act, 0)
				tool.wipe(p, e)
				check(is_equal_approx(p.load, minf(load, 0.15)), "wiping respects the floor without adding paint at %s" % load)
				check(Cues.asked.get(act, 0) == calls + (1 if load > 0.15 else 0), "only removed load pulses at %s" % load)
		p.brush = Brushwork.Brush.STICK
		p.load = 1.0
		var calls: int = Cues.asked.get(act, 0)
		tool.wipe(p, e)
		check(p.load == 1.0 and Cues.asked.get(act, 0) == calls, "charcoal neither unloads nor pulses")
	check(is_equal_approx(Easels.RAG.position.y, Easels.TRAY_Y + Easels.LIP.x), "the wiping surface rests on the lip with no air gap")
	var vertices: PackedVector3Array = Easels.rag_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for yaw in [0.0, 1.4]:
		for height in [0.0, 1.5]:
			var frame := Transform3D(Basis(Vector3.UP, yaw), Vector3(2, height, 3))
			for x in [Easels.RAG.position.x, Easels.RAG.end.x]:
				for edge in [Vector3(x, Easels.TRAY_Y + 0.0005, Easels.RAG.position.z - 0.035), Vector3(x, Easels.TRAY_Y + Easels.LIP.x + 0.0005, Easels.TRAY.end.z)]:
					var near := INF
					for vertex in vertices:
						near = minf(near, (frame * vertex).distance_to(frame * edge))
					check(near <= 0.0006, "cloth meets tray and lip at raised/turned easels")
	finish()
