extends "res://../tests/support/suite.gd"

## A colour, a tone and a decal target each change what the expression fixture's hat looks like, as their material
## properties would in VRChat. Needs a renderer, so scripts/test.sh runs it on the desktop one:
## godot4 --path game --xr-mode off --script ../tests/gpu_expressions.gd [-- OUT_DIR]

const SIZE := 128


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else ""
	var view := SubViewport.new()
	view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var model := (preload("res://demo/expressions.gd").scene() as PackedScene).instantiate() as Node3D
	view.add_child(model)
	var player := ExpressionPlayer.new(model)
	model.add_child(player)
	var eye := Camera3D.new()
	view.add_child(eye)
	var light := DirectionalLight3D.new()
	view.add_child(light)
	await process_frame
	var top := (model.find_child("ExpressionHat", true, false) as Node3D).global_position
	eye.look_at_from_position(top + Vector3(0, 0.05, 0.6), top)
	light.look_at_from_position(top + Vector3(0, 1, 1), top)
	var bare := await _shot(view, player, 0, "", out)
	var start := Time.get_ticks_msec()
	while (await _shot(view, player, 1, "", "")).is_equal_approx(bare):
		if Time.get_ticks_msec() - start > HANG * 1000:
			check(false, "the hat is drawn once its pipeline compiles")
			finish()
			return
	var rest := await _shot(view, player, 1, "", out)
	var colour := await _shot(view, player, 1, "Colour", out)
	var tone := await _shot(view, player, 1, "Tone", out)
	var decal := await _shot(view, player, 1, "Decal", out)
	print("rest %s, colour %s, tone %s, decal %s" % [rest, colour, tone, decal])
	check(rest.r > rest.g * 3.0 and rest.r > rest.b * 3.0, "the hat rests red: %s" % rest)
	check(colour.b > rest.b * 3.0 and absf(colour.r - rest.r) < 0.1, "the colour target raises the hat's blue channel: %s" % colour)
	check(absf(tone.r - tone.g) < 0.05 and absf(tone.r - tone.b) < 0.05, "the tone target takes the hat's saturation away: %s" % tone)
	check(decal.b > rest.b * 3.0 and decal.r < rest.r * 0.8, "the decal target lays its blue stripes over the hat: %s" % decal)
	view.queue_free()
	finish()


## The mean colour at the middle of the view, the hat's place, with Hat at `hat` and only `parameter` of the three
## driven.
func _shot(view: SubViewport, player: ExpressionPlayer, hat: int, parameter: String, out: String) -> Color:
	player.state.put("Hat", hat)
	for p: String in ["Colour", "Tone", "Decal"]:
		player.state.put(p, 1.0 if p == parameter else 0.0)
	player.state.advance(0)
	player.apply()
	await process_frame
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	if out != "":
		image.save_png(out.path_join("%s.png" % (parameter if parameter != "" else "rest" if hat else "bare")))
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(SIZE * 3 / 8, SIZE * 5 / 8):
		for x in range(SIZE * 3 / 8, SIZE * 5 / 8):
			sum += image.get_pixel(x, y)
			n += 1
	return sum / n
