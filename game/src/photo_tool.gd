class_name PhotoTool
extends Node3D

## For a hand holding the camera: the screen on the back of the camera model (ToolModels._camera) shows what
## its lens sees, and the trigger takes the photo, saved as a PNG that says where and how it was taken (PhotoMeta).
## The shot stays on the screen a moment after. The player's own avatar stands in the lens's view while a camera is
## held, and in no other.
##
## A photo is drawn as well as this game can draw: whatever the headset's step on the quality ladder, it sees
## Quality.FULL_LAYER instead of LADDER_LAYER (every plant, stone and leaf whole at every distance, and a sun whose
## shadows reach the garden's edge in four splits), at PHOTO_SIZE with 8x MSAA, a shadow atlas of PHOTO_SHADOWS and
## the foliage's finest blobs. A view capture (Main.capture) is drawn as the eyes see it.

const PREVIEW_SIZE := Vector2i(256, 192)
## The preview redraws on one frame in this many, a third of the frames paying for a second, small view.
const PREVIEW_EVERY := 3
const PHOTO_SIZE := Vector2i(3200, 2400)
const PHOTO_MSAA := Viewport.MSAA_8X
const PHOTO_SHADOWS := 8192
const VIEW_SIZE := Vector2i(1600, 1200)
const FOV := 55.0
const SHOT_HOLD := 1.2
const DARK := Color(0.06, 0.06, 0.07)

var rig: Rig
var folder := Main.photos_folder()
## Whose blobs a photo draws finest, if any.
var flora: Flora
## Returns what a photo records of the garden around it: {"about": Dictionary, "world": World.snapshot or null}.
var scene := func() -> Dictionary: return {"about": {}, "world": null}
var _buttons: Array[Buttons] = []
var _preview: SubViewport
var _photo: SubViewport
var _view: SubViewport
var _frame := 0
var _shot_left := 0.0
var _busy := false
## The hand whose lens the screen shows: the last to shoot while it still holds a camera.
var _eye: Hand
## Photo paths chosen but not yet written, so two quick shots never share one.
var _reserved := {}


func _init(player: Rig) -> void:
	rig = player
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["tool"]))
	ToolModels.camera_screen().albedo_color = DARK


func _viewport(size: Vector2i, msaa: Viewport.MSAA) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.msaa_3d = msaa
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = Rig.NEAR
	cam.far = Rig.FAR
	vp.add_child(cam)
	add_child(vp)
	return vp


## The photo's view, made when a shot needs it and let go once the screen stops showing it: its 8x MSAA buffers are
## the size of several headset views.
func photo_viewport() -> SubViewport:
	if _photo == null:
		_photo = _viewport(PHOTO_SIZE, PHOTO_MSAA)
		_photo.mesh_lod_threshold = 0.0
		_photo.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
		_photo.use_debanding = true
	return _photo


func _view_viewport() -> SubViewport:
	if _view == null:
		_view = _viewport(VIEW_SIZE, Viewport.MSAA_4X)
	return _view


## What a photo is drawn with, as its PNG records it.
static func settings() -> Dictionary:
	return {"size": [PHOTO_SIZE.x, PHOTO_SIZE.y], "msaa": 1 << PHOTO_MSAA, "shadow_atlas": PHOTO_SHADOWS, "shadow_splits": 4,
		"shadow_reach_m": Look.SHADOW_REACH, "blob_detail": Quality.ladder[0].blob_detail, "reach": "whole garden",
		"mesh_lod": "off", "anisotropy": 16}


func holders() -> Array[Hand]:
	var out: Array[Hand] = []
	for h in rig.hands:
		if h.tool == Hand.Tool.CAMERA and rig.aim_hand != h and not h.picking:
			out.append(h)
	return out


func _process(delta: float) -> void:
	var held := holders()
	_shot_left = maxf(_shot_left - delta, 0.0)
	var screen := ToolModels.camera_screen()
	if rig.body != null:
		rig.body.visible = not held.is_empty()
	if _shot_left == 0.0 and not _busy and _photo != null:
		screen.albedo_texture = null
		_photo.queue_free()
		_photo = null
	if held.is_empty():
		screen.albedo_texture = null
		screen.albedo_color = DARK
	elif _shot_left > 0.0:
		screen.albedo_texture = _photo.get_texture()
		screen.albedo_color = Color.WHITE.lerp(Color(2.5, 2.5, 2.5), clampf((_shot_left - SHOT_HOLD + 0.15) / 0.15, 0.0, 1.0))
	else:
		if _preview == null:
			_preview = _viewport(PREVIEW_SIZE, Viewport.MSAA_DISABLED)
		screen.albedo_texture = _preview.get_texture()
		screen.albedo_color = Color.WHITE
		_frame = (_frame + 1) % PREVIEW_EVERY
		if _frame == 0:
			_aim(_preview, lens(_eye if held.has(_eye) else held[0]), FOV, Quality.VIEW_MASK)
			_preview.render_target_update_mode = SubViewport.UPDATE_ONCE
	for h in held:
		if _buttons[rig.hands.find(h)].pressed("tool") and not _busy:
			shoot(h)
	for b in _buttons:
		b.latch()


## Where the lens is and which way it looks: as the controller is turned, roll included, as a camera held in the hand.
static func lens(hand: Node3D) -> Transform3D:
	var t := hand.global_transform
	return Transform3D(t.basis.orthonormalized(), t * (Hand.TOP + ToolModels.CAMERA_LENS))


func _aim(vp: SubViewport, at: Transform3D, fov: float, mask: int) -> void:
	var cam: Camera3D = vp.get_child(0)
	cam.global_transform = at
	cam.fov = fov
	cam.cull_mask = mask
	if rig.body != null and rig.body.visible and mask & Rig.SELF_LAYER:
		rig.pose_body(holders())


## The view the camera's screen would show from `at`, drawn once by a viewport made as the screen's is.
func render_screen(at: Transform3D) -> Image:
	var vp := _viewport(PREVIEW_SIZE, Viewport.MSAA_DISABLED)
	_aim(vp, at, FOV, Quality.VIEW_MASK)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


## Takes a photo through the hand's lens and saves it; the screen holds the shot for a moment. Returns
## where it was saved, or "" if it could not be taken.
func shoot(hand: Hand) -> String:
	hand.trigger_haptic_pulse(&"haptic", 0.0, 0.4, 0.04, 0.0)
	_eye = hand
	var at := lens(hand)
	var around: Dictionary = scene.call()
	var img := await render(at, FOV, Quality.PHOTO_MASK)
	if img == null:
		return ""
	_shot_left = SHOT_HOLD
	DirAccess.make_dir_recursive_absolute(folder)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := folder.path_join(stamp + ".png")
	var n := 1
	while FileAccess.file_exists(path) or _reserved.has(path):
		n += 1
		path = folder.path_join("%s-%d.png" % [stamp, n])
	_reserved[path] = true
	var about: Dictionary = around.about.duplicate()
	about.merge({"taken": Time.get_datetime_string_from_system(), "build": Main.revision(), "settings": settings(),
		"camera": {"position": _floats(at.origin), "rotation": _floats(at.basis.get_rotation_quaternion()), "fov": FOV}})
	var saved := await save(img, path, about, around.world)
	_reserved.erase(path)
	if saved != OK:
		push_error("photo: could not write %s: %s" % [path, error_string(saved)])
		return ""
	print("photo: ", path)
	return path


static func _floats(v: Variant) -> Array:
	return [v.x, v.y, v.z] if v is Vector3 else [v.x, v.y, v.z, v.w]


## The lens a photo's `about` was taken through.
static func lens_of(about: Dictionary) -> Transform3D:
	var p: Array = about.camera.position
	var q: Array = about.camera.rotation
	return Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), Vector3(p[0], p[1], p[2]))


## Writes `img` as a PNG on a worker thread, with `about` and `world` written into it when `about` is given (PhotoMeta):
## converting and encoding a photo-sized image takes longer than a frame.
func save(img: Image, path: String, about: Variant = null, world: Variant = null) -> Error:
	var file := ProjectSettings.globalize_path(path)
	var saved := [ERR_BUG]
	var task := WorkerThreadPool.add_task(func() -> void:
		img.convert(Image.FORMAT_RGB8)
		var png := img.save_png_to_buffer()
		saved[0] = Main.write_bytes(file, png if about == null else PhotoMeta.embed(png, about, world)))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return saved[0]


## The garden seen from `at` by a camera seeing `mask`'s layers, rendered once, one render at a time: as a photo when
## `mask` sees Quality.FULL_LAYER (see the top of this file), else as the eyes see it at VIEW_SIZE. The pixels come back
## from the GPU a frame or two later instead of stalling the frame that asked for them.
func render(at: Transform3D, fov: float, mask: int) -> Image:
	var rd := RenderingServer.get_rendering_device()
	if rd == null or not is_inside_tree():
		push_error("photo: no renderer to take it with")
		return null
	while _busy:
		await get_tree().process_frame
	_busy = true
	var full := mask & Quality.FULL_LAYER != 0
	var vp := photo_viewport() if full else _view_viewport()
	_aim(vp, at, fov, mask)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if full:
		await RenderingServer.frame_pre_draw
		var undo := draw_finest()
		await RenderingServer.frame_post_draw
		undo.call()
	else:
		await RenderingServer.frame_post_draw
	var tex := RenderingServer.texture_get_rd_texture(vp.get_texture().get_rid())
	var got := []
	rd.texture_get_data_async(tex, 0, func(data: PackedByteArray) -> void: got.append(data))
	while got.is_empty():
		await get_tree().process_frame
	_busy = false
	var fmt := rd.texture_get_format(tex)
	if fmt.format != RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM and fmt.format != RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
		push_error("photo: the view came back in format %d, not RGBA8" % fmt.format)
		return null
	return Image.create_from_data(fmt.width, fmt.height, false, Image.FORMAT_RGBA8, got[0])


## For the one frame a photo is drawn in, what the eyes' views share with it: the shadow atlas and the foliage's
## blobs, set for the photo before the frame draws; returns what puts them back. Set after every script's turn, so the
## quality governor (Quality) does not undo them first. The eyes see that frame drawn so too.
func draw_finest() -> Callable:
	var atlas: int = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")
	var bits: bool = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits")
	RenderingServer.directional_shadow_atlas_set_size(PHOTO_SHADOWS, bits)
	var blobs := flora.blob_detail if flora != null else 0
	if flora != null:
		flora.blob_detail = Quality.ladder[0].blob_detail
	return func() -> void:
		RenderingServer.directional_shadow_atlas_set_size(atlas, bits)
		if flora != null:
			flora.blob_detail = blobs
