extends "res://../tests/support/suite.gd"

## Headless checks of the standing mirror: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_mirror.gd
## What it shows needs a renderer; demo/mirror.json stands one on the desktop.

var terrain := Terrain.new()


func _initialize() -> void:
	terrain.install()
	await process_frame
	_the_mirror_sits_beside_the_cameras_on_the_wheel()
	_it_reflects_people_alone()
	_each_eye_sees_through_its_own_reflected_camera()
	await _the_trigger_stands_it_and_puts_it_away()
	finish()


func _the_mirror_sits_beside_the_cameras_on_the_wheel() -> void:
	var paths := ToolWheel.paths(Hand.TREE)
	check(paths.has(Hand.Tool.MIRROR) and paths[Hand.Tool.MIRROR].slice(0, -1) == paths[Hand.Tool.SELFIE].slice(0, -1), "the mirror opens from the cameras' entry: %s, %s" % [paths.get(Hand.Tool.MIRROR), paths[Hand.Tool.SELFIE]])
	var model := ToolModels.build(Hand.Tool.MIRROR)
	check(model.get_node_or_null("Glass") is MeshInstance3D, "the hand mirror has its glass")
	model.free()


func _it_reflects_people_alone() -> void:
	var a := Avatar.open(Avatar.built_in(0), Color.RED)
	var drawn := a.find_children("*", "VisualInstance3D", true, false)
	check(not drawn.is_empty() and drawn.all(func(v: VisualInstance3D) -> bool: return v.layers == Quality.PEOPLE_LAYER), "every avatar is drawn on the people's layer")
	check(Quality.MIRROR_MASK & Quality.PEOPLE_LAYER and Quality.MIRROR_MASK & Quality.SELF_LAYER, "the mirror sees every avatar, the player's own too")
	check(not Quality.MIRROR_MASK & (1 | Quality.LADDER_LAYER | Quality.FULL_LAYER), "and nothing of the garden")
	check(Quality.VIEW_MASK & Quality.PEOPLE_LAYER and Quality.PHOTO_MASK & Quality.PEOPLE_LAYER, "the eyes and photos still see people")
	check(not Quality.VIEW_MASK & Quality.MIRROR_LAYER and not Quality.PHOTO_MASK & Quality.MIRROR_LAYER, "the mirror's light lights no view but its own")
	var icon := Hand.icon(a)
	Hand.unlit(icon)
	check(a.find_children("*", "VisualInstance3D", true, false).all(func(v: VisualInstance3D) -> bool: return not v.layers & Quality.PEOPLE_LAYER), "a wheel's figure is no person the mirror reflects")
	icon.free()


func _each_eye_sees_through_its_own_reflected_camera() -> void:
	var size := Vector2(0.7, 1.05)
	for turn in [0.0, 0.8, -2.4]:
		var glass := Transform3D(Basis(Vector3.UP, turn) * Basis.from_scale(Vector3(size.x, size.y, 1)), Vector3(1, 1.2, -2))
		for eye: Vector3 in [Vector3(1, 1.6, -2) + Basis(Vector3.UP, turn) * Vector3(0, 0.4, 1.8), Vector3(1, 1.2, -2) + Basis(Vector3.UP, turn) * Vector3(-1.5, -0.6, 0.6)]:
			var view := MirrorTool.reflection(glass, eye)
			var n := glass.basis.z.normalized()
			var d := (eye - glass.origin).dot(n)
			check(view.at.origin.is_equal_approx(eye - 2.0 * d * n) and is_equal_approx(view.near, d), "its camera stands at the eye's reflection, its near plane on the glass")
			check(view.at.basis.is_equal_approx(view.at.basis.orthonormalized()), "an unscaled camera")
			var corners := {Vector2(-0.5, -0.5): Vector2(0.5, -0.5), Vector2(0.5, 0.5): Vector2(-0.5, 0.5)}
			for c: Vector2 in corners:
				var k: Vector3 = view.at.affine_inverse() * (glass * Vector3(c.x, c.y, 0))
				var framed: Vector2 = (Vector2(k.x, k.y) - view.offset) / size
				check(is_equal_approx(-k.z, view.near) and framed.is_equal_approx(corners[c]), "its frustum is the glass, left for right: %s at %s" % [c, framed])
			check(MirrorTool.reflection(glass, glass.origin - d * n).is_empty(), "an eye behind the glass sees no reflection")


func _the_trigger_stands_it_and_puts_it_away() -> void:
	var rig := Rig.new(terrain)
	root.add_child(rig)
	var tool := MirrorTool.new(rig, terrain)
	root.add_child(tool)
	await process_frame
	check(not tool.standing() and tool._views.is_empty(), "put away, it stands nowhere and holds no view")
	var key := "%s/%s" % [rig.right.tracker, Controls.input("tool", rig.right.tracker)]
	var press := func() -> void:
		Buttons.injected[key] = true
		await process_frame
		await process_frame
		Buttons.injected.erase(key)
		await process_frame
	rig.right.tool = Hand.Tool.MIRROR
	rig.right.held_still = true
	var foot := terrain.ground(0, -2.5)
	rig.right.global_transform = Transform3D(Basis.looking_at(foot - Vector3(0.2, 1.3, -0.3)), Vector3(0.2, 1.3, -0.3))
	await press.call()
	check(tool.standing() and tool.stand.global_position.distance_to(foot) < 0.05, "the trigger stands it where the hand points: %s" % tool.stand.global_position)
	var to_head := rig.head.global_position - tool.stand.global_position
	to_head.y = 0.0
	check(tool.glass().basis.z.normalized().dot(to_head.normalized()) > 0.99, "its glass turned to the player")
	check(tool._views.size() >= 1 and tool._views.all(func(vp: SubViewport) -> bool: return (vp.get_child(0) as Camera3D).cull_mask == Quality.MIRROR_MASK), "with a view of the people for each eye")
	var centre := tool.glass().origin
	check(tool.glass_hit(Vector3(0, 1.2, 0), centre - Vector3(0, 1.2, 0)) != null, "a hand pointing at its glass meets it")
	check(tool.glass_hit(Vector3(0, 1.2, 0), centre + tool.glass().basis.x * 0.6 - Vector3(0, 1.2, 0)) == null, "and past its rim does not")
	rig.right.global_transform = Transform3D(Basis.looking_at(centre - Vector3(0.2, 1.3, -0.3)), Vector3(0.2, 1.3, -0.3))
	await press.call()
	await process_frame
	check(not tool.standing() and tool._views.is_empty(), "the trigger on its glass puts it away, its views freed")
	rig.queue_free()
	tool.queue_free()
