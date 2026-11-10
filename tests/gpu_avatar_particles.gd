extends "res://../tests/support/suite.gd"

## Avatar particles draw where their emitter is, in the material a target chooses, and a mesh system draws its mesh.
## Needs a renderer, so scripts/test.sh runs it on the desktop one:
## godot4 --path game --xr-mode off --script ../tests/gpu_avatar_particles.gd [-- OUT_DIR]

const Fixture = preload("res://../tests/test_avatar_particles.gd")
const SIZE := 128


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else ""
	var view := SubViewport.new()
	view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	var world := WorldEnvironment.new()
	world.environment = env
	view.add_child(world)
	var eye := Camera3D.new()
	view.add_child(eye)
	eye.look_at_from_position(Vector3(0, 0, 1), Vector3.ZERO)
	var sk := Skeleton3D.new()
	sk.add_bone("emitter")
	view.add_child(sk)
	var f := Fixture.file("opaque")
	f.systems[0].bursts[0].count.scale = [200.0, 200.0]
	f.systems[0].max = 400
	f.systems[0].loop = true
	f.systems[0].color = {"min": [[1, 1, 1, 1]], "max": [[1, 1, 1, 1]]}
	f.systems[0].renderer.materials[0].color = [1, 0, 0, 1]
	var model := Node3D.new()
	model.set_meta("expressions", {"parameters": [], "targets": [{"effect": {"particle": {"system": 0, "field": "material"}}, "default": 0.0}]})
	var player := ExpressionPlayer.new(model)
	var particles := AvatarParticles.new(Fixture.read(f), sk, player)
	view.add_child(particles)
	var red := func(c: Color) -> bool: return c.r > 0.5 and c.g < 0.2 and c.b < 0.2
	var start := Time.get_ticks_msec()
	while not red.call(await _shot(view, "", 0, 0)):
		if Time.get_ticks_msec() - start > HANG * 1000:
			check(false, "the burst is drawn red, its material's tint, once its pipeline compiles")
			break
	var burst := await _shot(view, out, 0, 0)
	var edge := await _shot(view, "", SIZE / 2 - 6, SIZE / 2 - 6)
	player.state.outputs[0] = 1.0
	var swapped := await _shot(view, out, 0, 0)
	print("burst %s, its edge %s, swapped %s" % [burst, edge, swapped])
	check(red.call(burst), "the burst draws in its material's tint where its emitter is: %s" % burst)
	check(edge.get_luminance() < 0.05, "and nothing a view's width away: %s" % edge)
	check(swapped.b > 0.5 and swapped.r < 0.2, "the material target turns it to its second, blue material: %s" % swapped)
	particles.queue_free()
	var mesh := Fixture.file("opaque")
	mesh.meshes = [{"positions": [-0.5, 0, 0, 0.5, 0, 0, 0, 1, 0, -0.5, 0, 0, 0, 1, 0, 0.5, 0, 0], "indices": [0, 1, 2, 3, 4, 5]}]
	mesh.systems[0].loop = true
	mesh.systems[0].renderer.mode = "mesh"
	mesh.systems[0].renderer.mesh = 0
	mesh.systems[0].renderer.align = "world"
	mesh.systems[0].size = {"min": [1.0], "max": [1.0], "scale": [0.6, 0.6]}
	mesh.systems[0].color = {"min": [[0, 1, 0, 1]], "max": [[0, 1, 0, 1]]}
	var grown := AvatarParticles.new(Fixture.read(mesh), sk, null)
	view.add_child(grown)
	var green := func(c: Color) -> bool: return c.g > 0.5 and c.r < 0.2
	start = Time.get_ticks_msec()
	while not green.call(await _shot(view, "", 0, SIZE / 8)):
		if Time.get_ticks_msec() - start > HANG * 1000:
			break
	var grass := await _shot(view, out, 0, SIZE / 8)
	var below := await _shot(view, "", 0, -SIZE / 8)
	check(green.call(grass) and below.get_luminance() < 0.05, "a mesh system draws its triangle standing up from the emitter: %s above, %s below" % [grass, below])
	view.queue_free()
	player.free()
	model.free()
	finish()


## The mean colour of a patch at `x`, `y` from the middle of the view, a frame on.
func _shot(view: SubViewport, out: String, x: int, y: int) -> Color:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	if out != "":
		image.save_png(out.path_join("particles-%d.png" % Time.get_ticks_usec()))
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for py in range(SIZE / 2 - 4 - y, SIZE / 2 + 4 - y):
		for px in range(SIZE / 2 - 4 + x, SIZE / 2 + 4 + x):
			sum += image.get_pixel(px, py)
			n += 1
	return sum / n
