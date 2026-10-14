class_name PhotoTool
extends Node3D

## For a hand holding the camera: the screen on the back of the camera model (ToolModels._camera) shows what
## its lens sees, and the trigger takes the photo, saved as a PNG. The shot stays on the screen a moment after.

const PREVIEW_SIZE := Vector2i(256, 192)
## The preview redraws on one frame in this many, a third of the frames paying for a second, small view.
const PREVIEW_EVERY := 3
const PREVIEW_FAR := 60.0
const PHOTO_SIZE := Vector2i(1600, 1200)
const FOV := 55.0
const SHOT_HOLD := 1.2
const DARK := Color(0.06, 0.06, 0.07)

var rig: Rig
var folder := "user://photos"
var _buttons: Array[Buttons] = []
var _preview: SubViewport
var _photo: SubViewport
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
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))
	ToolModels.camera_screen().albedo_color = DARK


func _viewport(size: Vector2i, msaa: Viewport.MSAA, far: float) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.msaa_3d = msaa
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = 0.05
	cam.far = far
	vp.add_child(cam)
	add_child(vp)
	return vp


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
	if held.is_empty():
		screen.albedo_texture = null
		screen.albedo_color = DARK
	elif _shot_left > 0.0:
		screen.albedo_texture = _photo.get_texture()
		screen.albedo_color = Color.WHITE.lerp(Color(2.5, 2.5, 2.5), clampf((_shot_left - SHOT_HOLD + 0.15) / 0.15, 0.0, 1.0))
	else:
		if _preview == null:
			_preview = _viewport(PREVIEW_SIZE, Viewport.MSAA_DISABLED, PREVIEW_FAR)
		screen.albedo_texture = _preview.get_texture()
		screen.albedo_color = Color.WHITE
		_frame = (_frame + 1) % PREVIEW_EVERY
		if _frame == 0:
			_aim(_preview, lens(_eye if held.has(_eye) else held[0]))
			_preview.render_target_update_mode = SubViewport.UPDATE_ONCE
	for h in held:
		if _buttons[rig.hands.find(h)].pressed("trigger_click") and not _busy:
			shoot(h)
	for b in _buttons:
		b.latch()


## Where the lens is and which way it looks: along the controller's aim, level side to side so the
## horizon stays straight however the wrist rolls. Turned almost straight up or down there is no horizon,
## and the top of the controller takes over as up.
static func lens(hand: Node3D) -> Transform3D:
	var t := hand.global_transform
	var fwd := -t.basis.z.normalized()
	var up := Vector3.UP.lerp(t.basis.y, smoothstep(0.95, 0.999, absf(fwd.y)))
	if up.cross(fwd).length() < 1e-3:
		up = t.basis.y
	return Transform3D(Basis.looking_at(fwd, up), t * (Hand.TOP + ToolModels.CAMERA_LENS))


func _aim(vp: SubViewport, at: Transform3D, fov := FOV) -> void:
	var cam: Camera3D = vp.get_child(0)
	cam.global_transform = at
	cam.fov = fov


## Takes a photo through the hand's lens and saves it; the screen holds the shot for a moment. Returns
## where it was saved, or "" if it could not be taken.
func shoot(hand: Hand) -> String:
	hand.trigger_haptic_pulse(&"haptic", 0.0, 0.4, 0.04, 0.0)
	_eye = hand
	var img := await render(lens(hand))
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
	var saved := await save(img, path)
	_reserved.erase(path)
	if saved != OK:
		push_error("photo: could not write %s: %s" % [path, error_string(saved)])
		return ""
	print("photo: ", path)
	return path


## Writes `img` as a PNG on a worker thread: encoding a photo-sized image takes longer than a frame.
func save(img: Image, path: String) -> Error:
	var file := ProjectSettings.globalize_path(path)
	var saved := [ERR_BUG]
	var task := WorkerThreadPool.add_task(func() -> void: saved[0] = img.save_png(file))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return saved[0]


## The garden seen from `at`, rendered once at photo size, one render at a time. The pixels come back from
## the GPU a frame or two later instead of stalling the frame that asked for them.
func render(at: Transform3D, fov := FOV) -> Image:
	var rd := RenderingServer.get_rendering_device()
	if rd == null or not is_inside_tree():
		push_error("photo: no renderer to take it with")
		return null
	while _busy:
		await get_tree().process_frame
	_busy = true
	if _photo == null:
		_photo = _viewport(PHOTO_SIZE, Viewport.MSAA_4X, 400.0)
	_aim(_photo, at, fov)
	_photo.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var tex := RenderingServer.texture_get_rd_texture(_photo.get_texture().get_rid())
	var got := []
	rd.texture_get_data_async(tex, 0, func(data: PackedByteArray) -> void: got.append(data))
	while got.is_empty():
		await get_tree().process_frame
	_busy = false
	var fmt := rd.texture_get_format(tex)
	if fmt.format != RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM and fmt.format != RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
		push_error("photo: the view came back in format %d, not RGBA8" % fmt.format)
		return null
	var img := Image.create_from_data(fmt.width, fmt.height, false, Image.FORMAT_RGBA8, got[0])
	img.convert(Image.FORMAT_RGB8)
	return img
