extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var item := HeldItem.new()
	item.terrain = Terrain.new()
	root.add_child(item)
	for tool in Hand.Tool.values():
		if tool in [Hand.Tool.NONE, Hand.Tool.EASEL, Hand.Tool.BOOK]:
			continue
		var s := [HeldItem.Kind.TOOL, tool, Transform3D(Basis(), Hand.TOP), Color.WHITE, 0.0, 0, true, Vector3.ZERO]
		check(HeldItem.valid(s), "wheel tool accepted")
		item.show_state(s)
		check(item.model != null and item.model.get_child_count() > 0, "wheel tool builds its actual model")
		check(item.feeds() == (tool == Hand.Tool.SEEDS), "only seeds feed animals")
		check(item.replaces_hand(), "a held tool is drawn in place of the holder's hand")
	var long := [HeldItem.Kind.TOOL, Hand.Tool.STYLE, Transform3D(Basis().scaled(Vector3.ONE * Hand.HELD[Hand.Tool.STYLE] * 1.1), Hand.TOP), Color.WHITE, 0.0, 0, false, Vector3.ZERO]
	check(HeldItem.valid(long), "a wand held as long as a hand's tool, popping in, is accepted")
	for kind in Brushwork.Brush.values():
		var s := [HeldItem.Kind.BRUSH, kind, Transform3D(), Color(0.2, 0.3, 0.7), 0.8, 0, false, Vector3.ZERO]
		check(HeldItem.valid(s), "painting implement accepted")
		item.show_state(s)
		check(item.model != null, "painting implement builds")
		if not Brushwork.is_stick(kind):
			var mat: ShaderMaterial = item.model.get_node("tip").material_override
			check(mat.get_shader_parameter("paint_colour") == s[3] and is_equal_approx(mat.get_shader_parameter("load"), s[4]), "loaded paint reaches actual bristles")
		if not Brushwork.is_stick(kind):
			var model := item.model
			var tip := model.get_node("tip") as MeshInstance3D
			var relaxed := tip.transform
			var bent := s.duplicate()
			bent[7] = Vector3(0.004, 0, 0.008)
			check(HeldItem.valid(bent) and not HeldItem.same(s, bent), "bend changes travel through held state")
			item.show_state(bent)
			check(item.model == model and not tip.transform.is_equal_approx(relaxed), "remote bend deforms existing bristles without rebuilding")
			item.show_state(s)
			check(tip.transform.is_equal_approx(relaxed), "leaving canvas restores remote bristles")
			var wiped := s.duplicate()
			wiped[4] = 0.25
			check(not HeldItem.same(s, wiped), "a rag wipe changes the reliable held state")
			item.show_state(wiped)
			check(item.model == model and is_equal_approx((tip.material_override as ShaderMaterial).get_shader_parameter("load"), 0.25), "remote rag load updates existing bristles")
		var bad_bend := s.duplicate()
		bad_bend[7] = Vector3(NAN, 0, 0)
		check(not HeldItem.valid(bad_bend), "nonfinite bend rejected")
		bad_bend[7] = Vector3.ONE
		check(not HeldItem.valid(bad_bend), "bend beyond physical limit rejected")
		var invalid := s.duplicate()
		invalid[1] = 999
		check(not HeldItem.valid(invalid), "unknown implement rejected")
		invalid = s.duplicate()
		invalid[4] = NAN
		check(not HeldItem.valid(invalid), "nonfinite load rejected")
	var bird := [HeldItem.Kind.BIRD, 0, BirdCarry.HOLD, Color.WHITE, 0.0, 0, false, Vector3.ZERO]
	check(HeldItem.valid(bird), "remote bird descriptor accepted")
	item.show_state(bird)
	check(item.model is Conure and not item.feeds(), "remote carry shows bird without offering seeds")
	check(not item.replaces_hand(), "a bird perches on the carrier's hand")
	var old := item.model
	item.show_state(bird)
	check(item.model == old, "unchanged bird state preserves model")
	item.show_state([])
	check(item.model == null and not item.feeds() and not item.replaces_hand(), "empty hand removes model and feeding target")
	check(not HeldItem.valid([0]) and not HeldItem.valid([0, 0, "bad", Color.WHITE, 0.0, 0, false]), "malformed state rejected")
	var shut := [HeldItem.Kind.BOOK, 0, Book.local(0.0), Color.WHITE, 0.0, 0, false, Vector3.ZERO]
	item.show_state(shut)
	var prop := item.model
	for page in [1, 2, 1, 0]:
		var turned := shut.duplicate()
		turned[1] = page
		item.show_state(turned)
		check(item.model == prop and not (prop as Book)._turn.is_empty() and (prop as Book)._turn.to == page, "a peer's book turns to page %d as theirs does, not rebuilt there" % page)
	var leaps := shut.duplicate()
	leaps[1] = 4
	item.show_state(leaps)
	check(item.model == prop and (prop as Book).at == 4, "a jump of more than a leaf lands at once")
	check(not prop.is_processing(), "and a peer's book costs nothing a frame once still")
	item.show_state([])
	item.queue_free()
	await process_frame
	finish()
