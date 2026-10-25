class_name PhotoTool
extends Node3D

## For a hand holding the camera: the screen on the back of the camera model (ToolModels._camera) shows what
## its lens sees, unmirrored for the selfie camera too, so the screen and the photo match. A tap of the trigger takes a
## photo, saved as a PNG that says where and how it was taken (PhotoMeta); the shot stays on the screen a moment after.
## Held, the trigger records a video of what that camera's screen shows, with the game's sound, until let go. The player's own avatar stands in the lens's view while a camera is
## held, and in no other.
##
## A photo is drawn as well as this game can draw: whatever the headset's step on the quality ladder, it sees
## Quality.FULL_LAYER instead of LADDER_LAYER (every plant, stone and leaf whole at every distance, and a sun whose
## shadows reach the garden's edge in four splits), at PHOTO_SIZE with 8x MSAA, a shadow atlas of PHOTO_SHADOWS and
## the foliage's finest blobs. A view capture (Main.capture) is drawn as the eyes see it.

signal recorded(path: String)

const PREVIEW_SIZE := Vector2i(256, 192)
## Previews redraw one at a time, on one frame in this many: two cameras held take turns, and a camera recording takes
## every turn, its video's frames, so a second camera costs the frame nothing more (each preview draws the garden again).
const PREVIEW_EVERY := 3
const PHOTO_SIZE := Vector2i(3200, 2400)
const PHOTO_MSAA := Viewport.MSAA_8X
const PHOTO_SHADOWS := 8192
const VIEW_SIZE := Vector2i(1600, 1200)
const FOV := 55.0
const SHOT_HOLD := 1.2
const DARK := Color(0.06, 0.06, 0.07)
const CAMERAS: Array[Hand.Tool] = [Hand.Tool.CAMERA, Hand.Tool.SELFIE]
## A trigger held this long records instead of taking a photo on release.
const HOLD := 0.3
## While recording, the camera's preview is drawn at this size and every drawing is a frame of the video.
const VIDEO_SIZE := Vector2i(640, 480)
const VIDEO_FPS := 24
const VIDEO_QUALITY := 0.8
## Frames read back but not yet written, past which a frame is dropped rather than queued: writing never
## holds up play, and a dropped frame's time goes to the next one.
const VIDEO_QUEUE := 6

var rig: Rig
var folder := Main.photos_folder()
## Whose blobs a photo draws finest, if any.
var flora: Flora
## Returns what a photo records of the garden around it: {"about": Dictionary, "world": World.snapshot's bytes or none},
## taken when the shutter is pressed: the garden changes on while the photo is drawn and written.
var scene := func() -> Dictionary: return {"about": {}, "world": PackedByteArray()}
var _buttons: Array[Buttons] = []
## Per hand that has held a camera, its preview's view.
var _previews := {}
var _photo: SubViewport
var _view: SubViewport
var _frame := 0
var _turn := 0
## Per hand, how much longer its screen holds the shot it took.
var _shots := {}
var _busy := false
## Photo paths chosen but not yet written, so two quick shots never share one.
var _reserved := {}
var _pressed_for: Array[float] = []
var _clip: Avi
## The hand recording, and the camera it holds, while a video records.
var _clip_hand: Hand
var _clip_tool: Hand.Tool
var _clip_path := ""
var _clip_time := 0.0
var _clip_slot := -1
var _owed := 0
var _sound: AudioEffectCapture
var _heard := PackedByteArray()
## The frame last written, which the worker writes again for a frame time no drawing came back for.
var _last_jpg := PackedByteArray()
var _queue: Array[Dictionary] = []
var _reading := 0
var _writing := -1


func _init(player: Rig) -> void:
	rig = player
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["tool"]))
		_pressed_for.append(-1.0)


## Godot draws a frame whose pipelines are still compiling without the photo sun's shadows, and the photo sun lights
## no other view, so a session's first photo came out shadowless (docs/shadows.md). A photo's view is drawn once as
## the game loads to compile them.
func _ready() -> void:
	if RenderingServer.get_rendering_device() == null:
		return
	var vp := _viewport(PREVIEW_SIZE, PHOTO_MSAA)
	_aim(vp, rig.head.global_transform, FOV, Quality.PHOTO_MASK)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	vp.queue_free()


func _viewport(size: Vector2i, msaa: Viewport.MSAA) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.msaa_3d = msaa
	vp.use_occlusion_culling = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = Rig.NEAR
	cam.far = rig.far()
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
		_view = _viewport(VIEW_SIZE, get_viewport().msaa_3d)
	return _view


## What a photo is drawn with, as its PNG records it.
static func settings() -> Dictionary:
	return {"size": [PHOTO_SIZE.x, PHOTO_SIZE.y], "msaa": 1 << PHOTO_MSAA, "shadow_atlas": PHOTO_SHADOWS, "shadow_splits": 4,
		"shadow_reach_m": Look.SHADOW_REACH, "blob_detail": Quality.ladder[0].blob_detail, "reach": "whole garden",
		"mesh_lod": "off", "anisotropy": 16}


func holders() -> Array[Hand]:
	var out: Array[Hand] = []
	for h in rig.hands:
		if h.tool in CAMERAS and rig.aim_hand != h and not h.picking:
			out.append(h)
	return out


func _process(delta: float) -> void:
	var held := holders()
	for h in _shots:
		_shots[h] = maxf(_shots[h] - delta, 0.0)
	_write()
	if _clip_hand != null:
		_clip_time += delta
		_heard.append_array(_take_sound())
		if not held.has(_clip_hand) or _clip_hand.tool != _clip_tool or _clip.full:
			stop()
	if rig.body != null:
		rig.body.visible = not held.is_empty()
	if _photo != null and not _busy and _shots.values().all(func(left: float) -> bool: return left == 0.0):
		_photo.queue_free()
		_photo = null
	_frame = (_frame + 1) % PREVIEW_EVERY
	var drawing: Hand = null
	if _frame == 0 and not held.is_empty():
		_turn += 1
		drawing = _clip_hand if held.has(_clip_hand) else held[_turn % held.size()]
	for i in rig.hands.size():
		var h := rig.hands[i]
		for t in CAMERAS:
			if not held.has(h) or t != h.tool:
				_show(screen(h, t), null, DARK)
		if not held.has(h):
			continue
		var left: float = _shots.get(h, 0.0)
		if left > 0.0 and _photo != null and h != _clip_hand:
			_show(screen(h, h.tool), _photo.get_texture(), Color.WHITE.lerp(Color(2.5, 2.5, 2.5), clampf((left - SHOT_HOLD + 0.15) / 0.15, 0.0, 1.0)))
			continue
		var preview: SubViewport = _previews.get(h)
		if preview == null:
			preview = _viewport(VIDEO_SIZE if h == _clip_hand else PREVIEW_SIZE, Viewport.MSAA_DISABLED)
			_previews[h] = preview
		_show(screen(h, h.tool), preview.get_texture(), Color.WHITE)
		if h == drawing:
			_aim(preview, lens(h), FOV, Quality.VIEW_MASK)
			preview.render_target_update_mode = SubViewport.UPDATE_ONCE
			if h == _clip_hand:
				_grab(preview)
	for h in held:
		var i := rig.hands.find(h)
		var b := _buttons[i]
		if b.pressed("tool"):
			_pressed_for[i] = 0.0
		elif b.held("tool") and _pressed_for[i] >= 0.0:
			_pressed_for[i] += delta
			if _pressed_for[i] >= HOLD and _clip == null:
				record(h)
		elif b.released("tool") and _pressed_for[i] >= 0.0:
			if _clip_hand == h:
				stop()
			elif _pressed_for[i] < HOLD and not _busy:
				shoot(h)
			_pressed_for[i] = -1.0
	for i in _buttons.size():
		if not _buttons[i].held("tool"):
			_pressed_for[i] = -1.0
		_buttons[i].latch()


## The screen of `hand`'s camera model for `tool`.
static func screen(hand: Hand, tool: Hand.Tool) -> StandardMaterial3D:
	return ToolModels.screen(hand.model(tool))


static func _show(on: StandardMaterial3D, tex: Texture2D, tint: Color) -> void:
	on.albedo_texture = tex
	on.albedo_color = tint


## Where the lens is and which way it looks: as the controller is turned, roll included, as a camera held in the hand;
## a selfie camera's looks back along the controller at the holder.
static func lens(hand: Node3D) -> Transform3D:
	var t := hand.global_transform
	var basis := t.basis.orthonormalized()
	if hand is Hand and (hand as Hand).tool == Hand.Tool.SELFIE:
		return Transform3D(basis * Basis(Vector3.UP, PI), t * (Hand.TOP + ToolModels.SELFIE_LENS))
	return Transform3D(basis, t * (Hand.TOP + ToolModels.CAMERA_LENS))


func _aim(vp: SubViewport, at: Transform3D, fov: float, mask: int) -> void:
	var cam: Camera3D = vp.get_child(0)
	cam.global_transform = at
	cam.fov = fov
	cam.cull_mask = mask
	if rig.body != null and rig.body.visible and mask & Quality.SELF_LAYER:
		rig.pose_body()


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
	var at := lens(hand)
	Cues.play(Cues.Act.PHOTO, at.origin, hand)
	var around: Dictionary = scene.call()
	var img := await render(at, FOV, Quality.PHOTO_MASK)
	if img == null:
		return ""
	for h in _shots:
		_shots[h] = 0.0
	_shots[hand] = SHOT_HOLD
	var path := _reserve("png")
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


## A new file under `folder` named by the date and time.
func _reserve(ext: String) -> String:
	DirAccess.make_dir_recursive_absolute(folder)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := folder.path_join("%s.%s" % [stamp, ext])
	var n := 1
	while FileAccess.file_exists(path) or _reserved.has(path):
		n += 1
		path = folder.path_join("%s-%d.%s" % [stamp, n, ext])
	_reserved[path] = true
	return path


## Starts recording through the hand's lens into a video file beside the photos. That camera's preview grows to
## VIDEO_SIZE and keeps its pace, one frame in PREVIEW_EVERY, and each drawing is read back and handed to a worker
## thread to be written; the game's sound is taken from the master bus as it plays.
func record(hand: Hand) -> void:
	_clip_path = _reserve("avi")
	_clip = Avi.open(ProjectSettings.globalize_path(_clip_path), VIDEO_SIZE, VIDEO_FPS, roundi(AudioServer.get_mix_rate()))
	if _clip == null:
		push_error("video: could not write %s: %s" % [_clip_path, error_string(FileAccess.get_open_error())])
		_reserved.erase(_clip_path)
		_clip_path = ""
		return
	Cues.play(Cues.Act.VIDEO_START, hand.global_position, hand)
	_clip_hand = hand
	_clip_tool = hand.tool
	_clip_time = 0.0
	_clip_slot = -1
	_last_jpg = PackedByteArray()
	_owed = 0
	_heard = PackedByteArray()
	_sound = AudioEffectCapture.new()
	_sound.buffer_length = 1.0
	AudioServer.add_bus_effect(0, _sound)
	_shots[hand] = 0.0
	if _previews.has(hand):
		(_previews[hand] as SubViewport).size = VIDEO_SIZE
	ToolModels.button(hand.model(_clip_tool)).emission = ToolModels.RECORDING


## Stops recording and finishes the file once every frame read back is written. Returns where it was
## saved, or "" if it could not be.
func stop() -> String:
	var hand := _clip_hand
	if hand == null:
		return ""
	Cues.play(Cues.Act.VIDEO_STOP, hand.global_position, hand)
	_clip_hand = null
	ToolModels.button(hand.model(_clip_tool)).emission = Color.BLACK
	if _previews.has(hand):
		(_previews[hand] as SubViewport).size = PREVIEW_SIZE
	while _reading > 0:
		await get_tree().process_frame
	_heard.append_array(_take_sound())
	_queue.append({"sound": _heard, "repeats": _owed + maxi(roundi(_clip_time * VIDEO_FPS) - _clip_slot - 1, 0)})
	_heard = PackedByteArray()
	AudioServer.remove_bus_effect(0, _effect_index())
	_sound = null
	while _writing != -1 or not _queue.is_empty():
		await get_tree().process_frame
	var path := _clip_path
	var closed := [ERR_BUG]
	var clip := _clip
	var task := WorkerThreadPool.add_task(func() -> void: closed[0] = clip.close())
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_reserved.erase(path)
	_clip = null
	_clip_path = ""
	if closed[0] != OK:
		push_error("video: could not write %s: %s" % [path, error_string(closed[0])])
		path = ""
	else:
		print("video: ", path, " ", clip.frames, " frames")
	recorded.emit(path)
	return path


func _effect_index() -> int:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _sound:
			return i
	return -1


func _take_sound() -> PackedByteArray:
	if _sound == null:
		return PackedByteArray()
	return _sound.get_buffer(_sound.get_frames_available()).to_byte_array()


## Reads back what `preview` draws this frame as the video's frame for the moment it shows, repeated over any frame
## times since the last, as when play drops below the refresh rate.
func _grab(preview: SubViewport) -> void:
	var slot := roundi(_clip_time * VIDEO_FPS)
	var repeats := slot - _clip_slot
	if repeats <= 0:
		return
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return
	_clip_slot = slot
	repeats += _owed
	_owed = 0
	_reading += 1
	await RenderingServer.frame_post_draw
	var tex := RenderingServer.texture_get_rd_texture(preview.get_texture().get_rid())
	var fmt := rd.texture_get_format(tex)
	rd.texture_get_data_async(tex, 0, func(data: PackedByteArray) -> void:
		_reading -= 1
		if _queue.size() >= VIDEO_QUEUE:
			_owed += repeats
			return
		_queue.append({"pixels": data, "size": Vector2i(fmt.width, fmt.height), "repeats": repeats, "sound": _heard})
		_heard = PackedByteArray())


## Hands what is queued to one worker task at a time, so frames reach the file in order.
func _write() -> void:
	if _writing != -1 and WorkerThreadPool.is_task_completed(_writing):
		WorkerThreadPool.wait_for_task_completion(_writing)
		_writing = -1
	if _writing != -1 or _queue.is_empty():
		return
	var batch := _queue
	_queue = []
	var clip := _clip
	_writing = WorkerThreadPool.add_task(func() -> void:
		for item in batch:
			if not item.sound.is_empty():
				clip.sound(item.sound)
			if item.has("pixels"):
				var img := Image.create_from_data(item.size.x, item.size.y, false, Image.FORMAT_RGBA8, item.pixels)
				img.convert(Image.FORMAT_RGB8)
				_last_jpg = img.save_jpg_to_buffer(VIDEO_QUALITY)
			if not _last_jpg.is_empty():
				for r in item.repeats:
					clip.frame(_last_jpg))


static func _floats(v: Variant) -> Array:
	return [v.x, v.y, v.z] if v is Vector3 else [v.x, v.y, v.z, v.w]


## The lens a photo's `about` was taken through.
static func lens_of(about: Dictionary) -> Transform3D:
	var p: Array = about.camera.position
	var q: Array = about.camera.rotation
	return Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), Vector3(p[0], p[1], p[2]))


## Writes `img` as a PNG on a worker thread, with `about` and `world` written into it when `about` is given (PhotoMeta):
## converting and encoding a photo-sized image takes longer than a frame.
func save(img: Image, path: String, about: Variant = null, world := PackedByteArray()) -> Error:
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
		Metrics.note("photo: drawn at its finest")
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
