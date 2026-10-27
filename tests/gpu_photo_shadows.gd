extends "res://../tests/support/suite.gd"

## A photo taken while the headset's rung has the sun's shadows off still has its own sun's cast shadows: shot from the
## same spot, it is darker where a shadow falls than the same shot with the photo sun's shadows off. Needs a
## RenderingDevice, so scripts/test.sh runs it on the desktop renderer:
## godot4 --path game --xr-mode off --script ../tests/gpu_photo_shadows.gd

## The share of the photo a cast shadow must darken.
const SHADED := 0.02


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	if RenderingServer.get_rendering_device() == null:
		check(false, "no RenderingDevice; run on the desktop renderer")
		finish()
		return
	await play([
		{"op": "place", "x": 0, "z": 14},
		{"op": "house", "at": [0, 0], "size": [6, 4], "seconds": 0.3},
	])
	var shadowless := range(Quality.ladder.size()).filter(func(i: int) -> bool: return not Quality.ladder[i].shadows)
	check(not shadowless.is_empty(), "the ladder has a rung without the sun's shadows")
	if shadowless.is_empty():
		finish()
		return
	var look: Look = main.look
	for n: int in [shadowless[0], shadowless[-1]]:
		main.quality.pin = n
		await until(func() -> bool: return not look.sun.shadow_enabled, "rung %d turns the sun's shadows off" % n)
		var at := Transform3D.IDENTITY.looking_at(Vector3(0, 1, 0) - Vector3(9, 6, 12), Vector3.UP)
		at.origin = Vector3(9, 6 + main.world.terrain.height_at(9, 12), 12)
		var lit := await main.photo_tool.render(at, PhotoTool.FOV, Quality.PHOTO_MASK)
		var casts := look.photo_sun.shadow_enabled
		look.photo_sun.shadow_enabled = false
		var flat := await main.photo_tool.render(at, PhotoTool.FOV, Quality.PHOTO_MASK)
		look.photo_sun.shadow_enabled = casts
		var share := _darker(lit, flat)
		print("rung %d: the photo is darker than without its sun's shadows on %.1f%% of it" % [n, share * 100.0])
		check(share >= SHADED, "a photo at rung %d has cast shadows: darker on %.1f%% of it than without them, not %.0f%%" % [n, share * 100.0, SHADED * 100.0])
	finish()


## The share of `a`'s pixels at most four fifths as bright as `b`'s, sampled on a grid.
static func _darker(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_size() != b.get_size():
		return 0.0
	var n := 0
	var dark := 0
	for y in range(0, a.get_height(), 8):
		for x in range(0, a.get_width(), 8):
			n += 1
			dark += int(a.get_pixel(x, y).get_luminance() <= 0.8 * b.get_pixel(x, y).get_luminance())
	return float(dark) / n
