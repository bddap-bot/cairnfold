class_name StylePass
extends CompositorEffect

## Draws a photo style over a camera's finished view, before tonemapping: the view through `tone`, its strokes laid
## first where `reach` is above zero. The mobile renderer gives effects no storage images, so the view is drawn into a
## copy and back.

## Samples a quadrant's side takes, whatever the reach.
const SAMPLES := 3

## Rows map linear rgb to rgb.
var tone := Basis.IDENTITY
## Of the view's height, the strokes' length.
var reach := 0.0

var _rd: RenderingDevice
var _shader: RID
var _sampler: RID
## Framebuffer format -> pipeline.
var _pipelines := {}
var _copy: RID
var _copy_size := Vector2i.ZERO
var _copy_format := -1


func _init(row_tone := Basis.IDENTITY, row_reach := 0.0) -> void:
	tone = row_tone
	reach = row_reach
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	RenderingServer.call_on_render_thread(_start)


func _start() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	_shader = _rd.shader_create_from_spirv((preload("res://src/photo_style.glsl") as RDShaderFile).get_spirv())
	var s := RDSamplerState.new()
	s.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	s.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	s.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	s.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(s)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		RenderingServer.call_on_render_thread(_free.bind(_rd, _pipelines.values() + [_copy, _sampler, _shader]))


static func _free(rd: RenderingDevice, rids: Array) -> void:
	for rid: RID in rids:
		if rid.is_valid():
			rd.free_rid(rid)


func _render_callback(_type: int, data: RenderData) -> void:
	if _rd == null or not _shader.is_valid():
		return
	var buffers := data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var styled := PackedFloat32Array()
	for row in 3:
		var v: Vector3 = tone[row]
		styled.append_array([v.x, v.y, v.z, 0.0])
	var texels := maxf(reach * size.y, 1.0)
	styled.append_array([texels / size.x, texels / size.y, float(SAMPLES) if reach > 0.0 else 0.0, 0.0])
	var copied := PackedFloat32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0])
	for view in buffers.get_view_count():
		var colour := buffers.get_color_layer(view)
		_keep_copy(size, _rd.texture_get_format(colour).format)
		_draw(colour, _copy, styled.to_byte_array())
		_draw(_copy, colour, copied.to_byte_array())


func _keep_copy(size: Vector2i, format: int) -> void:
	if _copy.is_valid() and size == _copy_size and format == _copy_format:
		return
	if _copy.is_valid():
		_rd.free_rid(_copy)
	var f := RDTextureFormat.new()
	f.width = size.x
	f.height = size.y
	f.format = format as RenderingDevice.DataFormat
	f.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
	_copy = _rd.texture_create(f, RDTextureView.new())
	_copy_size = size
	_copy_format = format


func _draw(from: RID, to: RID, push: PackedByteArray) -> void:
	var fb := FramebufferCacheRD.get_cache_multipass([to], [], 1)
	var format := _rd.framebuffer_get_format(fb)
	if not _pipelines.has(format):
		var blend := RDPipelineColorBlendState.new()
		blend.attachments = [RDPipelineColorBlendStateAttachment.new()]
		_pipelines[format] = _rd.render_pipeline_create(_shader, format, RenderingDevice.INVALID_FORMAT_ID, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
			RDPipelineRasterizationState.new(), RDPipelineMultisampleState.new(), RDPipelineDepthStencilState.new(), blend)
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = 0
	u.add_id(_sampler)
	u.add_id(from)
	var list := _rd.draw_list_begin(fb, RenderingDevice.DRAW_IGNORE_COLOR_ALL)
	_rd.draw_list_bind_render_pipeline(list, _pipelines[format])
	_rd.draw_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(_shader, 0, [u]), 0)
	_rd.draw_list_set_push_constant(list, push, push.size())
	_rd.draw_list_draw(list, false, 1, 3)
	_rd.draw_list_end()
