extends "res://../tests/support/suite.gd"

## A converted avatar's flat material is lit alike on its side toward the light and its side away, and no brighter
## than its cap however strong the light; a lit one is shaded by angle, and one lit through a ramp by its ramp at the
## half-Lambert term, its shade lent the albedo by its shadow tint; a glowing one glows its emission in the dark,
## over its glow's own colour where it overrides its base colour, and one glowing in a theme colour turning over time
## changes colour as it turns; a clear coat adds a highlight toward the light where its map, moved by a region, does
## not mask it off, and reflects the world's sky, or its fallback cubemap where the world has no reflection probe or it
## forces it, lit by the light its material takes unless it says otherwise, and as Poiyomi 9.2 blurs, weighs and
## occludes it where the coat is that version's; a matcap multiplies the colour by its texture where the view sees the
## surface's normal, on the view's right as Unity maps it, where its mask does not mask it off. Needs a renderer, so scripts/test.sh runs it on
## the desktop one: godot4 --path game --xr-mode off --script ../tests/gpu_avatar_lighting.gd

const SIZE := 96


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
	var shots := {}
	for model: String in ["flat", "lit", "ramp", "tinted"]:
		var avatar := _ball(model)
		view.add_child(avatar)
		for light: Vector2 in [Vector2(0.5, 0.0), Vector2(3.0, 0.0), Vector2(0.3, 0.2), Vector2(3.0, 0.2)]:
			sun.light_energy = light.x
			RenderingServer.global_shader_parameter_set(&"sun_light", Vector3.ONE * light.x)
			RenderingServer.global_shader_parameter_set(&"sky_ambient", light.y)
			env.ambient_light_color = Color.WHITE * light.y
			shots["%s %s" % [model, light]] = await _sides(view)
		avatar.queue_free()
	sun.light_energy = 1.0
	RenderingServer.global_shader_parameter_set(&"sun_light", Vector3.ONE)
	RenderingServer.global_shader_parameter_set(&"sky_ambient", 0.0)
	env.ambient_light_color = Color.BLACK
	for model: String in ["coat", "masked", "unmasked", "world", "fallback", "unlit fallback", "forced", "flat fallback", "sharp", "widened", "glancing", "occluded", "matcap", "matcap masked"]:
		ExpressionPlayer.world_reflects = model in ["coat", "masked", "unmasked", "world", "forced"]
		RenderingServer.global_shader_parameter_set(&"sun_light", Vector3.ONE * (0.1 if model == "occluded" else 1.0))
		var coated := _ball(model)
		view.add_child(coated)
		shots[model] = await _sides(view)
		coated.queue_free()
	ExpressionPlayer.world_reflects = true
	RenderingServer.global_shader_parameter_set(&"sun_light", Vector3.ONE)
	var glowing := _ball("glow")
	view.add_child(glowing)
	sun.light_energy = 0.0
	RenderingServer.global_shader_parameter_set(&"sun_light", Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"sky_ambient", 0.0)
	env.ambient_light_color = Color.BLACK
	shots["glow"] = await _sides(view)
	glowing.queue_free()
	var turning := _ball("theme")
	view.add_child(turning)
	await _sides(view)
	var reds := []
	for frame in 6:
		await process_frame
		await RenderingServer.frame_post_draw
		reds.append(_mean(view.get_texture().get_image(), SIZE * 5 / 8))
	turning.queue_free()
	print(shots)
	var flat_dim: Vector2 = shots["flat (0.5, 0.0)"]
	var flat_bright: Vector2 = shots["flat (3.0, 0.0)"]
	var flat_ambient: Vector2 = shots["flat (0.3, 0.2)"]
	var flat_both: Vector2 = shots["flat (3.0, 0.2)"]
	var lit: Vector2 = shots["lit (0.5, 0.0)"]
	check(absf(flat_dim.x - 0.5) < 0.04 and absf(flat_dim.x - flat_dim.y) < 0.03, "a flat material is lit by the whole light of 0.5 toward the light and away: %s" % flat_dim)
	check(absf(flat_bright.x - 0.8) < 0.06 and absf(flat_bright.x - flat_bright.y) < 0.03, "a flat material in light past its cap of 0.8 is lit at the cap: %s" % flat_bright)
	check(absf(flat_ambient.x - 0.5) < 0.04 and absf(flat_ambient.x - flat_ambient.y) < 0.03, "a flat material takes light 0.3 and ambient 0.2 whole, either side: %s" % flat_ambient)
	check(absf(flat_both.x - 0.8) < 0.06 and absf(flat_both.x - flat_both.y) < 0.03, "a flat material in light and ambient past its cap is lit at the cap: %s" % flat_both)
	check(lit.x > lit.y + 0.2, "a lit material is shaded by angle: %s" % lit)
	var ramp: Vector2 = shots["ramp (0.5, 0.0)"]
	check(absf(ramp.x - 0.4) < 0.05 and absf(ramp.y - 0.1) < 0.05, "a material lit through a ramp rising from 0 to 1 takes 0.8 and 0.2 of a light of 0.5 where the half-Lambert term is 0.8 and 0.2: %s" % ramp)
	var tinted: Vector2 = shots["tinted (0.5, 0.0)"]
	check(absf(tinted.x - 0.5) < 0.04 and absf(tinted.y - 0.5) < 0.04, "a white material whose shadow tint is whole is lit whole on its shaded side too: %s" % tinted)
	var glow: Vector2 = shots["glow"]
	check(absf(glow.x - 0.75) < 0.04 and absf(glow.y - 0.75) < 0.04, "a material glowing red 0.25 at strength 2 that overrides its base colour glows 0.5 over the half it replaces, 0.75, on both sides in the dark: %s" % glow)
	check(reds.min() < 0.05 and reds.max() > 0.6, "a glow in a theme colour whose hue turns a third a frame goes from red to none and back: %s" % [reds])
	var masked: Vector2 = shots["masked"]
	var coat: Vector2 = shots["coat"]
	check(coat.x > masked.x + 0.03 and absf(coat.y - masked.y) < 0.01, "a clear coat adds a highlight on the side toward the light and nothing away from it: %s over %s, its map masking it off" % [coat, masked])
	var unmasked: Vector2 = shots["unmasked"]
	check(unmasked.x > masked.x + 0.03 and absf(unmasked.y - masked.y) < 0.01, "a region moving the map's offset onto its unmasked texel draws the coat: %s" % unmasked)
	var matcap: Vector2 = shots["matcap"]
	check(matcap.x < 0.1 and matcap.y > 0.9, "a flat white material under a matcap multiplying it by black on the view's right and white on its left draws black on the right only: %s" % matcap)
	var matcap_masked: Vector2 = shots["matcap masked"]
	check(matcap_masked.x > 0.9 and matcap_masked.y > 0.9, "a matcap its slot's mask channel masks off leaves the material white whatever the other channels: %s" % matcap_masked)
	var world_lit: Vector2 = shots["world"]
	var fallback: Vector2 = shots["fallback"]
	var unlit: Vector2 = shots["unlit fallback"]
	var forced: Vector2 = shots["forced"]
	check(fallback.x > world_lit.x + 0.1 and absf(fallback.y - world_lit.y) < 0.01, "where the world has no reflection probe a coat reflects its fallback, lit by its material's light, so only toward the light: %s over the dark sky's %s" % [fallback, world_lit])
	check(unlit.x > world_lit.x + 0.1 and unlit.y > world_lit.y + 0.1, "a fallback its light does not light shows on both sides: %s" % unlit)
	var flat_fallback: Vector2 = shots["flat fallback"]
	check(flat_fallback.x > 0.86 and absf(flat_fallback.x - flat_fallback.y) < 0.03, "a flat material's fallback is lit by the main light it takes whole, either side: a quarter of 0.5 times 0.8 over its 0.8: %s" % flat_fallback)
	var sharp: Vector2 = shots["sharp"]
	var widened: Vector2 = shots["widened"]
	check(widened.y > sharp.y + 0.1, "Poiyomi 9.2 blurs what a mirror coat reflects where its surface curves, reaching the levels past the sharpest, which alone is dark here, as an earlier Poiyomi does not: %s over %s" % [widened, sharp])
	var glancing: Vector2 = shots["glancing"]
	check(glancing.y > widened.y + 0.0003, "its Fresnel strength raises what it reflects at a glance: %s at 1 over %s at 0" % [glancing, widened])
	var occluded: Vector2 = shots["occluded"]
	check(occluded.y < 0.5 * glancing.y and occluded.y > 0.0, "and its exposure occlusion dims it under a dim main light: %s" % occluded)
	check(forced.distance_to(fallback) < 0.01, "a coat forcing its fallback reflects it though the world has a probe: %s" % forced)
	view.queue_free()
	finish()


## A white ball whose looks light its one material `model`, flat capped at 0.8, through a ramp rising from 0 to 1 with
## no shadow tint ("ramp") or a whole one ("tinted"), or for "glow" lit by angle and glowing red
## 0.25 at strength 2 over a white emission map, overriding its base colour, as the avatar runtime opens it; for "theme"
## that red is a global theme colour whose hue turns twenty times a second; for "coat" lit by angle under a clear coat,
## "masked" reading its map's black texel, "unmasked" moved by a region onto its white one; for "world", "fallback",
## "unlit fallback" and "forced" a mirror coat reflecting alone, its fallback cubemap a uniform 0.5, lit by the
## material's light but for "unlit fallback", "forced" forcing it, "flat fallback" a flat material reflecting a quarter; for "sharp", "widened", "glancing" and
## "occluded" an unlit fallback dark in its sharpest level and 0.5 in the rest, under an earlier Poiyomi's coat,
## Poiyomi 9.2's at Fresnel strength 0, at 1, and at 1 with its exposure occlusion whole; for "matcap" flat and
## multiplied whole by a matcap in slot 1 white on its left half and black on its right under its mask's green channel,
## and "matcap masked" the same with that channel black and the others white.
func _ball(model: String) -> Node3D:
	var ball := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Ball"
	var sphere := SphereMesh.new()
	sphere.radial_segments = 48
	sphere.rings = 24
	var picture := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	picture.fill(Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(picture)
	var im := ImporterMesh.new()
	var arrays := sphere.get_mesh_arrays()
	arrays[Mesh.ARRAY_TEX_UV2] = arrays[Mesh.ARRAY_TEX_UV]
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat)
	var index := Image.create_empty(4, 4, false, Image.FORMAT_L8)
	index.fill(Color8(1, 1, 1))
	var light: Dictionary = {"flat": {"model": "flat", "cap": 0.8}, "matcap": {"model": "flat", "cap": 1.0}, "matcap masked": {"model": "flat", "cap": 1.0}, "ramp": {"model": "lit", "ramp": [0.0, 1.0], "shadowTint": 0.0}, "tinted": {"model": "lit", "ramp": [0.0, 1.0], "shadowTint": 1.0}, "flat fallback": {"model": "flat", "cap": 0.8}}.get(model, {"model": "lit"})
	var looks := {"index": index, "materials": [{"lighting": light}]}
	if model in ["glow", "theme"]:
		looks.materials[0].emission = {"color": [0.25, 0.0, 0.0], "strength": 2.0, "hue": 0.0, "shiftsHue": false, "replace": 1.0}
		looks.emission = picture
	if model == "theme":
		looks.materials[0].emission.theme = 0
		looks.materials[0].themes = [{"slot": 0, "hsv": [0.0, 1.0, 0.25], "exposure": 1.0, "hue": 0.0, "saturation": 0.0, "value": 0.0, "speed": 400.0}, null, null, null]
	var expressions := {"looks": looks}
	if model in ["coat", "masked", "unmasked"]:
		var map := Image.create_empty(2, 1, false, Image.FORMAT_RGBA8)
		map.set_pixel(0, 0, Color8(0, 255, 255, 255))
		map.set_pixel(1, 0, Color.WHITE)
		looks.clearcoatMaps = [map]
		looks.materials[0].clearcoat = {"strength": 1.0, "smoothness": 0.8, "reflection": 0.0, "specular": 1.0, "fresnel": 1.0, "gsaa": [0.15, 0.1], "specularTint": [1.0, 1.0, 1.0], "reflectionTint": [1.0, 1.0, 1.0], "st": [1.0, 1.0, 0.0, 0.0] if model == "coat" else [0.0, 0.0, 0.25, 0.5], "inverts": [false, false, false, false], "map": 0, "fallback": -1, "litFallback": true, "forceFallback": false, "fresnelStrength": null, "exposureOcclusion": 0.0}
		if model == "unmasked":
			expressions.merge({"parameters": [], "clips": [], "layers": [], "shown": [], "menu": [], "targets": [{"effect": {"look": [{"node": "Ball", "rect": [0, 0, 1, 1], "field": "clearcoatST", "slot": 2}]}, "default": 0.75}]})
	if model.begins_with("matcap"):
		var texture := Image.create_empty(2, 1, false, Image.FORMAT_RGBA8)
		texture.set_pixel(0, 0, Color.WHITE)
		texture.set_pixel(1, 0, Color.BLACK)
		var mask := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		mask.fill(Color(1, 0, 1, 1) if model == "matcap masked" else Color(0, 1, 0, 1))
		looks.matcaps = [texture]
		looks.matcapMasks = mask
		looks.materials[0].matcaps = [null, {"mode": "normal", "texture": 0, "color": [1.0, 1.0, 1.0, 1.0], "border": 0.5, "intensity": 1.0, "baseMix": 0.0, "replace": 0.0, "multiply": 1.0, "add": 0.0, "screen": 0.0, "mixed": 0.0, "lightAdd": 0.0, "emission": 0.0, "lightMask": 0.0, "hue": null, "circle": null}, null, null]
	if model in ["sharp", "widened", "glancing", "occluded"]:
		var cube := Image.create_empty(256, 896, false, Image.FORMAT_RGBA8)
		cube.fill_rect(Rect2i(0, 128, 256, 768), Color(1.0, 1.0, 1.0, 1.0 / 255.0))
		looks.clearcoatFallbacks = [cube]
		looks.materials[0].clearcoat = {"strength": 1.0, "smoothness": 1.0, "reflection": 1.0, "specular": 0.0, "fresnel": 1.0, "gsaa": [0.15, 0.1], "specularTint": [1.0, 1.0, 1.0], "reflectionTint": [1.0, 1.0, 1.0], "st": [1.0, 1.0, 0.0, 0.0], "inverts": [false, false, false, false], "map": -1, "fallback": 0, "litFallback": false, "forceFallback": false, "fresnelStrength": null if model == "sharp" else 1.0 if model in ["glancing", "occluded"] else 0.0, "exposureOcclusion": 1.0 if model == "occluded" else 0.0}
	if model in ["world", "fallback", "unlit fallback", "forced", "flat fallback"]:
		var cube := Image.create_empty(256, 896, false, Image.FORMAT_RGBA8)
		cube.fill(Color(1.0, 1.0, 1.0, 1.0 / 255.0))
		looks.clearcoatFallbacks = [cube]
		looks.materials[0].clearcoat = {"strength": 1.0, "smoothness": 1.0, "reflection": 0.25 if model == "flat fallback" else 1.0, "specular": 0.0, "fresnel": 0.0, "gsaa": [0.0, 0.0], "specularTint": [1.0, 1.0, 1.0], "reflectionTint": [1.0, 1.0, 1.0], "st": [1.0, 1.0, 0.0, 0.0], "inverts": [false, false, false, false], "map": -1, "fallback": 0, "litFallback": model != "unlit fallback", "forceFallback": model == "forced", "fresnelStrength": null, "exposureOcclusion": 0.0}
	Avatar._lit_looks(looks, [im])
	mesh.mesh = im.get_mesh()
	ball.add_child(mesh)
	ball.set_meta("expressions", expressions)
	ExpressionPlayer.prepare(ball)
	var player := ExpressionPlayer.new(ball)
	player.apply()
	ball.add_child(player)
	return ball


## The ball's mean linear red on its side toward the light and on its side away, once its pipeline has compiled.
func _sides(view: SubViewport) -> Vector2:
	var start := Time.get_ticks_msec()
	var sides := Vector2.ZERO
	while Time.get_ticks_msec() - start < HANG * 1000:
		await process_frame
		await RenderingServer.frame_post_draw
		var image := view.get_texture().get_image()
		sides = Vector2(_mean(image, SIZE * 5 / 8), _mean(image, SIZE * 3 / 8))
		if sides.x + sides.y > 0.0:
			return sides
	return sides


static func _mean(image: Image, x: int) -> float:
	var sum := 0.0
	var n := 0
	for y in range(SIZE * 7 / 16, SIZE * 9 / 16):
		for dx in range(-3, 4):
			sum += image.get_pixel(x + dx, y).srgb_to_linear().r
			n += 1
	return sum / n
