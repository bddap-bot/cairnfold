extends "res://../tests/support/suite.gd"

## The sun's and the moon's discs stay round wherever they sit in a wide headset view: measured as the angles
## the eye sees, not the flat image's pixels, a disc at the view's edge is as wide toward the centre as across.
## Needs a renderer, so scripts/test.sh runs it on the desktop one:
## godot4 --path game --xr-mode off --script ../tests/gpu_disc.gd [-- OUT_DIR]

const SIZE := 512
## About a Quest's field of view across one eye.
const FOV := 100.0
## Degrees off the view's axis each disc is seen at: centre, the right edge, and toward a corner.
const PLACES := [Vector2(0, 0), Vector2(42, 0), Vector2(30, -30)]


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
	var eye := Camera3D.new()
	eye.fov = FOV
	eye.far = Look.DISC_DISTANCE * 2.0
	view.add_child(eye)
	for which in [["sun", Look.SUN_DISC, 0.0], ["moon", Look.MOON_DISC, 1.0]]:
		var disc := Look._disc(which[1], which[2])
		disc.material_override.set_shader_parameter("tint", Color.WHITE)
		view.add_child(disc)
		for off: Vector2 in PLACES:
			var toward := (Basis(Vector3.UP, deg_to_rad(-off.x)) * Basis(Vector3.RIGHT, deg_to_rad(off.y)) * Vector3.FORWARD).normalized()
			disc.position = toward * Look.DISC_DISTANCE
			for _i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var image := view.get_texture().get_image()
			var name := "%s_%d_%d" % [which[0], off.x, off.y]
			if out != "":
				image.save_png(out.path_join(name + ".png"))
			var span := _span(image, eye, toward)
			var round := span.x / span.y
			print("%s: %.2f° toward the centre, %.2f° across, ratio %.3f" % [name, span.x, span.y, round])
			check(span.y > 0.5 and absf(round - 1.0) < 0.04, "%s is round (ratio %.3f)" % [name, round])
		disc.queue_free()
	view.queue_free()
	await process_frame
	finish()


## The lit disc's extent in degrees as the eye sees it, along the line from the view's centre through `toward`
## and across it: each bright pixel's ray, measured as angles about `toward`.
func _span(image: Image, eye: Camera3D, toward: Vector3) -> Vector2:
	var radial := (toward - Vector3.FORWARD * toward.dot(Vector3.FORWARD))
	radial = radial.normalized() if radial.length() > 1e-4 else Vector3.RIGHT
	radial = (radial - toward * radial.dot(toward)).normalized()
	var across := toward.cross(radial)
	var peak := 0.0
	for y in SIZE:
		for x in SIZE:
			peak = maxf(peak, image.get_pixel(x, y).get_luminance())
	var lo := Vector2(INF, INF)
	var hi := -lo
	for y in SIZE:
		for x in SIZE:
			if image.get_pixel(x, y).get_luminance() < peak * 0.5:
				continue
			var ray := eye.project_ray_normal(Vector2(x + 0.5, y + 0.5))
			var a := Vector2(atan2(ray.dot(radial), ray.dot(toward)), atan2(ray.dot(across), ray.dot(toward)))
			lo = lo.min(a)
			hi = hi.max(a)
	return (hi - lo) * (180.0 / PI)
