extends SceneTree

class EyeCapture extends CompositorEffect:
	signal captured(images: Array, size: Vector2i, matrices: Array)
	var pending := false

	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
		access_resolved_color = true

	func _render_callback(_type: int, data: RenderData) -> void:
		if not pending:
			return
		pending = false
		var buffers: RenderSceneBuffersRD = data.get_render_scene_buffers()
		var rd := RenderingServer.get_rendering_device()
		var texture := buffers.get_color_texture()
		print("shadows: size=", buffers.get_internal_size(), " views=", buffers.get_view_count())
		var images := []
		var matrices := []
		var scene := data.get_render_scene_data()
		var transform := scene.get_cam_transform()
		for v in buffers.get_view_count():
			var matrix := scene.get_view_projection(v) * Projection(transform.affine_inverse())
			var columns := []
			for c in 4:
				var col: Vector4 = matrix[c]
				columns.append([col.x, col.y, col.z, col.w])
			matrices.append(columns)
		for eye in buffers.get_view_count():
			var source := RDShaderSource.new()
			source.source_compute = """#version 450
layout(local_size_x=8, local_size_y=8) in;
layout(set=0,binding=0) uniform sampler2DArray source;
layout(set=0,binding=1,std430) restrict writeonly buffer Pixels { vec4 pixels[]; };
layout(push_constant,std430) uniform Params { ivec4 dimensions; };
void main() {
 ivec2 p=ivec2(gl_GlobalInvocationID.xy);
 if(any(greaterThanEqual(p,dimensions.xy))) return;
 pixels[p.y*dimensions.x+p.x]=texelFetch(source,ivec3(p,dimensions.z),0);
}
"""
			var shader := rd.shader_create_from_spirv(rd.shader_compile_spirv_from_source(source))
			var pipeline := rd.compute_pipeline_create(shader)
			var size := buffers.get_internal_size()
			var output := rd.storage_buffer_create(size.x * size.y * 16)
			var sampler := rd.sampler_create(RDSamplerState.new())
			var input := RDUniform.new()
			input.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			input.binding = 0
			input.add_id(sampler)
			input.add_id(texture)
			var target := RDUniform.new()
			target.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			target.binding = 1
			target.add_id(output)
			var uniforms := rd.uniform_set_create([input, target], shader, 0)
			var list := rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(list, pipeline)
			rd.compute_list_bind_uniform_set(list, uniforms, 0)
			rd.compute_list_set_push_constant(list, PackedInt32Array([size.x, size.y, eye, 0]).to_byte_array(), 16)
			rd.compute_list_dispatch(list, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
			rd.compute_list_end()
			images.append(rd.buffer_get_data(output))
			for rid in [uniforms, sampler, output, pipeline, shader]:
				rd.free_rid(rid)
		captured.emit.call_deferred(images, buffers.get_internal_size(), matrices)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var effect := EyeCapture.new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [effect]
	main.rig.head.compositor = compositor
	await create_timer(3).timeout
	main.world.submit({"op": "season", "index": 4})
	assert(main.world.palette.season == 4, "The shadow fixture must be winter")
	var steps := [
		{"op": "wall", "points": [[-8, -18], [8, -18]], "seconds": 1.0},
		{"op": "house", "at": [9, -24], "size": [6, 4], "turn": 0, "seconds": 1.0},
	]
	var driver := Driver.new(main, steps)
	main.add_child(driver)
	await driver.finished
	main.world.submit({"op": "plant", "kind": "tree", "seed": 7948,
		"at": Vector3(-6, Terrain.height_at(-6, -25), -25)})
	main.quality.pin = Quality.START
	var settings := {"fov": main.metrics.info.get("eye_fov_deg", []), "sun": str(main.look.sun.basis), "head": str(main.rig.head.transform)}
	print("shadows: ", JSON.stringify(settings))
	var scene := OS.get_environment("NESTCOMBE_SHADOW_SCENE")
	var eye := Vector3(0, Terrain.height_at(0, 20) + 2, 20)
	var facing := Vector3.FORWARD
	var yaws := [-40, -30, -20, -10, 0, 10, 20, 30, 40]
	if scene == "hill":
		eye = Vector3(0, Terrain.height_at(0, -40) + 2, -40)
		yaws = [-40, 0, 40]
	elif scene == "tree":
		eye = Vector3(-6, Terrain.height_at(-6, -20) + 1.4, -20)
		facing = Vector3(-6, Terrain.height_at(-6, -25) + 4, -25) - eye
		main.quality.pin = 14
		yaws = [-20, 0, 20]
	var folder := OS.get_environment("NESTCOMBE_SHADOW_OUT")
	assert(not folder.is_empty(), "Set NESTCOMBE_SHADOW_OUT to the capture directory")
	DirAccess.make_dir_recursive_absolute(folder)
	if OS.get_environment("NESTCOMBE_SHADOW_BASELINE") == "1":
		main.look.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		main.look.sun.directional_shadow_max_distance = 45.0
		main.look.sun.directional_shadow_split_1 = 6.0 / 45.0
		main.look.sun.directional_shadow_fade_start = 0.8
		main.look.sun.shadow_blur = 1.5
	for shadow in ["current"]:
		for yaw in yaws:
			var direction := Basis(Vector3.UP, deg_to_rad(float(yaw))) * facing
			for frame in 45:
				main.view(eye, eye + direction, false)
				await process_frame
			effect.pending = true
			var captured: Array = await effect.captured
			var actual: Vector3 = main.rig.head.global_position
			var metadata := {"matrices": captured[2], "head": [actual.x, actual.y, actual.z], "yaw": yaw, "shadow": shadow}
			var meta := FileAccess.open(folder.path_join("shadow-%s-yaw-%d.json" % [shadow, yaw]), FileAccess.WRITE)
			meta.store_string(JSON.stringify(metadata))
			meta.close()
			var images: Array = captured[0]
			var size: Vector2i = captured[1]
			for i in images.size():
				var img := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBAF, images[i])
				img.convert(Image.FORMAT_RGBA8)
				img.linear_to_srgb()
				img.save_png(folder.path_join("shadow-%s-yaw-%d-eye-%d.png" % [shadow, yaw, i]))
			print("shadows: saved shadow=", shadow, " yaw=", yaw, " eye=", main.rig.head.global_transform)
	main.rig.head.compositor = null
	main.finish()
