extends "res://../tests/support/suite.gd"

## A converted avatar's toon looks as lilToon draws them: a flat grey ball lit from +X takes its first shade past its
## shadow's border and its second past the second's, the border where the border's half Lambert puts it, both turned by
## a menu's hue and moved by its colour as the albedo is; a rim brightens its silhouette alone, tinted by its rim tint
## layer, and on back faces only where it says so; an added matcap lays its top half where the ball faces up and its right half where it faces right,
## as Unity maps one, and a clip moving its intensity to nothing and its emission's strength off nothing takes the
## matcap away and lights the emission; and a reflection matcap lays its left half where the ball faces right, as
## Poiyomi reflects the view in Unity's axes, Godot's mirrored through X. Needs a renderer, so scripts/test.sh runs it on the desktop one:
## godot4 --path game --xr-mode off --script ../tests/gpu_avatar_toon.gd [-- OUT_DIR], which keeps each shot there.

const SIZE := 96
## The ball's radius in pixels: an orthographic view 2.4 high over a ball of radius 1.
const RADIUS := SIZE / 2.4
const BASE := Color(0.5, 0.5, 0.5)
const FIRST := Color(0.1, 0.1, 0.4)
const SECOND := Color(0.4, 0.1, 0.1)
const BORDER := 0.6
const SECOND_BORDER := 0.25
## The rim tint layer of the "tinted rim" ball, in linear light.
const TINT := Color(1.0, 0.25, 1.0)


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = env
	view.add_child(world)
	var eye := Camera3D.new()
	eye.projection = Camera3D.PROJECTION_ORTHOGONAL
	eye.size = 2.4
	eye.position = Vector3(0, 0, 3)
	eye.cull_mask = Quality.VIEW_MASK
	view.add_child(eye)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3.LEFT)
	view.add_child(sun)
	for name: String in ["sky_zenith", "sky_horizon"]:
		RenderingServer.global_shader_parameter_set(name, Vector3.ONE)
	RenderingServer.global_shader_parameter_set(&"sun_toward", Vector3.RIGHT)
	RenderingServer.global_shader_parameter_set(&"sun_light", Vector3.ONE)
	RenderingServer.global_shader_parameter_set(&"sky_ambient", 0.0)
	var shadow := {"border": BORDER, "blur": 0.1, "strength": 1.0, "second": {"border": SECOND_BORDER, "blur": 0.1, "weight": 1.0}, "edge": null}
	var rim := {"color": [0.0, 1.0, 0.0], "strength": 0.5, "main": 0.0, "border": 0.3, "blur": 0.2, "power": 1.5, "lit": 0.0, "shadowMask": 0.0, "backface": false}
	var rest := BASE.linear_to_srgb()
	var matcap := {"texture": 0, "mode": "normal", "border": 0.5, "color": [1.0, 1.0, 1.0, 1.0], "intensity": 1.0, "baseMix": 0.0, "replace": 0.0, "multiply": 0.0, "add": 1.0, "screen": 0.0, "mixed": 0.0, "lightAdd": 0.0, "emission": 0.0, "lightMask": 0.0, "hue": null, "circle": null, "theme": null}
	var shots := {}
	var moves := {"matcap": ["moved", [0.0, 1.0]], "turned": ["turned", [1.0 / 3.0]], "recoloured": ["recoloured", [1.0]]}
	for look: String in ["shadow", "rim", "tinted rim", "plain", "matcap", "reflection", "turned", "recoloured", "inside", "inside hidden", "inside shown"]:
		var entry := {"lighting": {"model": "flat", "cap": 1.0}}
		if look in ["shadow", "rim", "tinted rim", "turned", "recoloured", "inside", "inside hidden", "inside shown"]:
			entry.lighting.shadow = shadow
		if look in ["rim", "tinted rim", "inside hidden"]:
			entry.rim = rim
		if look == "inside shown":
			entry.rim = rim.merged({"backface": true}, true)
		var targets := []
		if look == "matcap":
			entry.matcaps = [matcap, null, null, null]
			entry.emission = {"color": [0.0, 0.0, 0.5], "strength": 0.0, "hue": 0.0, "shiftsHue": false}
			for field: String in ["matcapIntensity", "emission"]:
				targets.append({"effect": {"look": [{"node": "Ball", "rect": [0, 0, 1, 1], "field": field, "slot": 0}]}, "default": 1.0 if field == "matcapIntensity" else 0.0})
		if look == "reflection":
			entry.matcaps = [matcap.merged({"mode": "reflection"}, true), null, null, null]
		if look == "turned":
			targets.append({"effect": {"hue": [{"node": "Ball", "rect": [0, 0, 1, 1], "space": 1, "shift": 1}]}, "default": 0.0})
		if look == "recoloured":
			targets.append({"effect": {"color": [{"node": "Ball", "rect": [0, 0, 1, 1], "channel": 0, "color": [rest.r, rest.g, rest.b]}]}, "default": rest.r})
		var ball := _ball(entry, targets, look.begins_with("inside"), TINT if look == "tinted rim" else Color.WHITE)
		view.add_child(ball)
		shots[look] = await _shot(view)
		if moves.has(look):
			var player: ExpressionPlayer = ball.get_child(1)
			player.set_process(false)
			player.state.outputs.assign(moves[look][1])
			player.apply()
			await process_frame
			await RenderingServer.frame_post_draw
			shots[moves[look][0]] = view.get_texture().get_image()
		ball.queue_free()
	for look: String in shots:
		if not OS.get_cmdline_user_args().is_empty():
			(shots[look] as Image).save_png(OS.get_cmdline_user_args()[0].path_join(look + ".png"))
	var shaded: Image = shots.shadow
	var lit := _mean(shaded, 0.4, 0.7, 0.0)
	var first := _mean(shaded, -0.3, 0.0, 0.0)
	var second := _mean(shaded, -0.9, -0.7, 0.0)
	var crossing := _crossing(shaded, (BASE.r + FIRST.r) / 2.0)
	var expected := rad_to_deg(acos(2.0 * BORDER - 1.0))
	var measured := rad_to_deg(acos(clampf(crossing, -1.0, 1.0)))
	var rimmed: Image = shots.rim
	var edge := [_mean(rimmed, 0.88, 0.95, 0.0).g - _mean(shaded, 0.88, 0.95, 0.0).g, _mean(rimmed, -0.95, -0.88, 0.0).g - _mean(shaded, -0.95, -0.88, 0.0).g]
	var middle := _mean(rimmed, -0.4, 0.4, 0.0).g - _mean(shaded, -0.4, 0.4, 0.0).g
	var tinted := [_mean(shots["tinted rim"], 0.88, 0.95, 0.0).g - _mean(shaded, 0.88, 0.95, 0.0).g, _mean(shots["tinted rim"], -0.95, -0.88, 0.0).g - _mean(shaded, -0.95, -0.88, 0.0).g]
	var plain: Image = shots.plain
	var mapped: Image = shots.matcap
	var up := _mean(mapped, -0.1, 0.1, 0.6).r - _mean(plain, -0.1, 0.1, 0.6).r
	var down := _mean(mapped, -0.1, 0.1, -0.6).r - _mean(plain, -0.1, 0.1, -0.6).r
	var right := _mean(mapped, 0.5, 0.7, 0.0).b - _mean(plain, 0.5, 0.7, 0.0).b
	var left := _mean(mapped, -0.7, -0.5, 0.0).b - _mean(plain, -0.7, -0.5, 0.0).b
	var moved: Image = shots.moved
	var still := _mean(moved, -0.1, 0.1, 0.6).r - _mean(plain, -0.1, 0.1, 0.6).r
	var glowing := _mean(moved, -0.7, -0.5, 0.0).b - _mean(plain, -0.7, -0.5, 0.0).b
	var reflected: Image = shots.reflection
	var reflected_up := _mean(reflected, -0.1, 0.1, 0.6).r - _mean(plain, -0.1, 0.1, 0.6).r
	var reflected_right := _mean(reflected, 0.5, 0.7, 0.0).b - _mean(plain, 0.5, 0.7, 0.0).b
	var reflected_left := _mean(reflected, -0.7, -0.5, 0.0).b - _mean(plain, -0.7, -0.5, 0.0).b
	var turned: Image = shots.turned
	var turned_lit := _mean(turned, 0.4, 0.7, 0.0)
	var turned_first := _mean(turned, -0.3, 0.0, 0.0)
	var turned_second := _mean(turned, -0.9, -0.7, 0.0)
	var recoloured: Image = shots.recoloured
	var recoloured_lit := _mean(recoloured, 0.4, 0.7, 0.0)
	var recoloured_first := _mean(recoloured, -0.3, 0.0, 0.0)
	var inside: Image = shots.inside
	var hidden := [_mean(shots["inside hidden"], 0.88, 0.95, 0.0).g - _mean(inside, 0.88, 0.95, 0.0).g, _mean(shots["inside hidden"], -0.95, -0.88, 0.0).g - _mean(inside, -0.95, -0.88, 0.0).g]
	var shown := [_mean(shots["inside shown"], 0.88, 0.95, 0.0).g - _mean(inside, 0.88, 0.95, 0.0).g, _mean(shots["inside shown"], -0.95, -0.88, 0.0).g - _mean(inside, -0.95, -0.88, 0.0).g]
	print("lit %s, first shade %s, second shade %s, border at x %.3f: %.1f degrees from the light (expected %.1f); rim at the silhouette +%s green, mid-ball %+.4f, tinted +%s; matcap red up %+.3f down %+.3f, blue right %+.3f left %+.3f; moved: red up %+.3f, blue left %+.3f; reflection: red up %+.3f, blue right %+.3f left %+.3f; hue turned: lit %s, first %s, second %s; red raised: lit %s, first %s; back faces: hidden rim %s, shown %s" % [lit, first, second, crossing, measured, expected, edge, middle, tinted, up, down, right, left, still, glowing, reflected_up, reflected_right, reflected_left, turned_lit, turned_first, turned_second, recoloured_lit, recoloured_first, hidden, shown])
	check(_near(lit, BASE, 0.04), "the side toward the light keeps the base colour: %s" % lit)
	check(_near(first, FIRST, 0.04), "past the shadow's border the ball takes the first shade: %s" % first)
	check(_near(second, SECOND, 0.04), "past the second border it takes the second shade: %s" % second)
	check(absf(measured - expected) < 3.0, "the border falls %.1f degrees from the light, its half Lambert's %.1f" % [measured, expected])
	check(edge.all(func(g: float) -> bool: return g > 0.3) and absf(middle) < 0.01, "the rim brightens the silhouette, %s, and leaves the middle, %+.4f" % [edge, middle])
	check(range(2).all(func(k: int) -> bool: return absf(tinted[k] - edge[k] * TINT.g) < 0.03), "a rim tint layer scales the rim by its texel, %s against %s times %.2f" % [tinted, edge, TINT.g])
	check(up > 0.3 and absf(down) < 0.02 and right > 0.3 and absf(left) < 0.02, "the matcap's top half lies where the ball faces up and its right half where it faces right: up %+.3f, down %+.3f, right %+.3f, left %+.3f" % [up, down, right, left])
	check(absf(still) < 0.02 and absf(glowing - 0.5) < 0.04, "a clip taking the matcap's intensity to nothing takes it away, %+.3f, and one setting the emission's strength to one lights it 0.5 blue, %+.3f" % [still, glowing])
	check(reflected_up > 0.3 and reflected_left > 0.3 and absf(reflected_right) < 0.02, "a reflection matcap lays its top half where the ball faces up and its left half where it faces right: up %+.3f, right %+.3f, left %+.3f" % [reflected_up, reflected_right, reflected_left])
	check(_near(turned_lit, BASE, 0.04) and _near(turned_first, Color(FIRST.b, FIRST.g, FIRST.r), 0.04) and _near(turned_second, Color(SECOND.g, SECOND.r, SECOND.b), 0.04), "a menu hue turn of a third turns the shades as the albedo, blue to red and red to green: lit %s, first %s, second %s" % [turned_lit, turned_first, turned_second])
	check(_near(recoloured_lit, Color(1.0, BASE.g, BASE.b), 0.04) and _near(recoloured_first, Color(FIRST.r * 2.0, FIRST.g, FIRST.b), 0.04), "a menu colour doubling the albedo's red doubles the shade's: lit %s, first %s" % [recoloured_lit, recoloured_first])
	check(hidden.all(func(g: float) -> bool: return absf(g) < 0.01) and shown.all(func(g: float) -> bool: return g > 0.3), "a rim hidden on back faces leaves an inside-out ball's silhouette, %s, and one drawn there brightens it, %s" % [hidden, shown])
	view.queue_free()
	finish()


## A grey ball whose one material's looks entry is `entry`, its shade layers the two shades, its matcap red over its
## top half and blue over its right, its emission map and untinted colours white, animated by `targets`, as the avatar
## runtime opens it; `inverted`, drawn two-sided with its faces turned in, so the side in view is its back faces; its
## rim tint layer `tint` where its entry draws a rim.
func _ball(entry: Dictionary, targets: Array, inverted: bool, tint: Color) -> Node3D:
	var ball := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Ball"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	sphere.flip_faces = inverted
	var filled := func(c: Color) -> Image:
		var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(c.linear_to_srgb())
		return img
	var matcap := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			matcap.set_pixel(x, y, Color(1.0 if y < 8 else 0.0, 0.0, 1.0 if x >= 8 else 0.0))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(filled.call(BASE))
	if inverted:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays(), [], {}, mat)
	var index := Image.create_empty(4, 4, false, Image.FORMAT_L8)
	index.fill(Color8(1, 1, 1))
	var looks := {"index": index, "materials": [entry], "shade": filled.call(FIRST), "shade2": filled.call(SECOND), "matcaps": [matcap], "emission": filled.call(Color.WHITE)}
	if entry.has("rim"):
		looks.rimTint = filled.call(tint)
	check(ExpressionDefinition.looks_valid(looks), "the ball's looks are valid")
	var animated := {}
	for target: Dictionary in targets.filter(func(t: Dictionary) -> bool: return t.effect.has("look")):
		animated[target.effect.look[0].field] = true
	Avatar._lit_looks(looks, [im], {}, animated)
	mesh.mesh = im.get_mesh()
	ball.add_child(mesh)
	ball.set_meta("expressions", {"looks": looks, "parameters": [], "targets": targets, "clips": [], "layers": [], "shown": [], "menu": [], "untinted": {"image": filled.call(Color.WHITE), "cells": [[0, 0, 1, 1, 0, 0, 1, 1]]}})
	ExpressionPlayer.prepare(ball)
	ball.add_child(ExpressionPlayer.new(ball))
	return ball


## The view once the ball's pipeline has compiled and it draws.
func _shot(view: SubViewport) -> Image:
	var start := Time.get_ticks_msec()
	var image: Image
	while Time.get_ticks_msec() - start < HANG * 1000:
		await process_frame
		await RenderingServer.frame_post_draw
		image = view.get_texture().get_image()
		if _mean(image, -0.1, 0.1, 0.0).r > 0.0:
			break
	return image


## The pixel column at `x` across the ball (-1 to 1, its radius) and the row at `y` up it.
static func _pixel(x: float, y: float) -> Vector2i:
	return Vector2i(roundi(SIZE / 2.0 + x * RADIUS - 0.5), roundi(SIZE / 2.0 - y * RADIUS - 0.5))


## The mean linear colour over the pixels from `left` to `right` across the ball, three rows round `y` up it.
static func _mean(image: Image, left: float, right: float, y: float) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	var low := _pixel(left, y)
	var high := _pixel(right, y)
	for py in range(low.y - 1, low.y + 2):
		for px in range(low.x, high.x + 1):
			sum += image.get_pixel(px, py).srgb_to_linear()
			n += 1
	return sum / n


## Where across the ball's middle row its red first reaches `level` coming from the light, -1 to 1.
static func _crossing(image: Image, level: float) -> float:
	var row := _pixel(0.0, 0.0).y
	var last := image.get_pixel(_pixel(0.95, 0.0).x, row).srgb_to_linear().r
	for px in range(_pixel(0.95, 0.0).x - 1, _pixel(-0.95, 0.0).x, -1):
		var red := image.get_pixel(px, row).srgb_to_linear().r
		if red <= level:
			var at := float(px) + (level - red) / (last - red) if last != red else float(px)
			return (at + 0.5 - SIZE / 2.0) / RADIUS
		last = red
	return -1.0


static func _near(a: Color, b: Color, within: float) -> bool:
	return absf(a.r - b.r) < within and absf(a.g - b.g) < within and absf(a.b - b.b) < within
