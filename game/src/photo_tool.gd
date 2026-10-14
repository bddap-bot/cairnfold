class_name PhotoTool
extends Node3D

## For a hand holding the camera: the camera on the controller shows what its lens sees on the screen on its
## back, and the trigger takes the photo, saved as a PNG. The shot stays on the screen a moment after.

const PREVIEW := Vector2i(256, 192)
## The preview redraws on one frame in this many: a second view of the garden costs its draw calls again.
const PREVIEW_EVERY := 3
const PHOTO := Vector2i(1600, 1200)
const FOV := 55.0
const HOLD := 1.2
const SCREEN := Vector2(0.048, 0.036)
## Where the screen and the lens sit on the camera model (ToolModels._camera), from the controller.
const SCREEN_AT := Hand.TOP + Vector3(0, 0.024, 0.0141)
const LENS_AT := Hand.TOP + Vector3(0, 0.024, -0.03)

signal taken(path: String)

var rig: Rig
var folder := "user://photos"
var _buttons: Array[Buttons] = []
var _preview: SubViewport
var _photo: SubViewport
var _screen: MeshInstance3D
var _screen_mat := StandardMaterial3D.new()
var _frame := 0
var _held := 0.0
var _saving := -1


func _init(player: Rig) -> void:
	rig = player
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))
	_preview = _viewport(PREVIEW, Viewport.MSAA_DISABLED)
	_photo = _viewport(PHOTO, Viewport.MSAA_4X)
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_mat.albedo_texture = _preview.get_texture()
	var quad := QuadMesh.new()
	quad.size = SCREEN
	_screen = MeshInstance3D.new()
	_screen.mesh = quad
	_screen.material_override = _screen_mat
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_screen.visible = false


func _viewport(size: Vector2i, msaa: Viewport.MSAA) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.msaa_3d = msaa
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = 0.05
	cam.far = 400.0
	vp.add_child(cam)
	add_child(vp)
	return vp


func holder() -> Hand:
	for h in rig.hands:
		if h.tool == Hand.Tool.CAMERA and rig.aim_hand != h and not h.picking:
			return h
	return null


func _process(delta: float) -> void:
	var hand := holder()
	_show_screen(hand)
	if hand != null:
		_held = maxf(_held - delta, 0.0)
		if _held == 0.0:
			_screen_mat.albedo_texture = _preview.get_texture()
			_screen_mat.albedo_color = Color.WHITE
			_frame = (_frame + 1) % PREVIEW_EVERY
			if _frame == 0:
				_aim(_preview, lens(hand))
				_preview.render_target_update_mode = SubViewport.UPDATE_ONCE
		else:
			_screen_mat.albedo_color = Color.WHITE.lerp(Color(2.5, 2.5, 2.5), clampf((_held - HOLD + 0.15) / 0.15, 0.0, 1.0))
		if _buttons[rig.hands.find(hand)].pressed("trigger_click") and _saving < 0:
			shoot(hand)
	for b in _buttons:
		b.latch()


func _show_screen(hand: Hand) -> void:
	if hand == null:
		_screen.visible = false
		return
	if _screen.get_parent() != hand:
		if _screen.get_parent() != null:
			_screen.get_parent().remove_child(_screen)
		hand.add_child(_screen)
		_screen.position = SCREEN_AT
	_screen.visible = true


## Where the lens is and which way it looks: along the controller's aim, level side to side so the
## horizon stays straight however the wrist rolls.
static func lens(hand: Node3D) -> Transform3D:
	var t := hand.global_transform
	var fwd := -t.basis.z.normalized()
	var up := Vector3.UP if absf(fwd.y) < 0.99 else -t.basis.y
	return Transform3D(Basis.looking_at(fwd, up), t * LENS_AT)


func _aim(vp: SubViewport, at: Transform3D, fov := FOV) -> void:
	var cam: Camera3D = vp.get_child(0)
	cam.global_transform = at
	cam.fov = fov


## Takes a photo through the hand's lens and saves it; the screen holds the shot for a moment.
func shoot(hand: Hand) -> void:
	var img := await render(lens(hand))
	_screen_mat.albedo_texture = _photo.get_texture()
	_held = HOLD
	hand.trigger_haptic_pulse(&"haptic", 0.0, 0.4, 0.04, 0.0)
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(Time.get_datetime_string_from_system().replace(":", "-") + ".png")
	var n := 1
	while FileAccess.file_exists(path):
		n += 1
		path = folder.path_join("%s-%d.png" % [Time.get_datetime_string_from_system().replace(":", "-"), n])
	var file := ProjectSettings.globalize_path(path)
	_saving = WorkerThreadPool.add_task(func() -> void: img.save_png(file))
	while not WorkerThreadPool.is_task_completed(_saving):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(_saving)
	_saving = -1
	print("photo: ", path)
	taken.emit(path)


## The garden seen from `at`, rendered once at photo size. The pixels come back from the GPU a frame or two
## later instead of stalling the frame that asked for them.
func render(at: Transform3D, fov := FOV) -> Image:
	_aim(_photo, at, fov)
	_photo.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var rd := RenderingServer.get_rendering_device()
	var tex := RenderingServer.texture_get_rd_texture(_photo.get_texture().get_rid())
	var got := []
	rd.texture_get_data_async(tex, 0, func(data: PackedByteArray) -> void: got.append(data))
	while got.is_empty():
		await get_tree().process_frame
	var fmt := rd.texture_get_format(tex)
	assert(fmt.format == RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM or fmt.format == RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB, "photo format %d" % fmt.format)
	var img := Image.create_from_data(fmt.width, fmt.height, false, Image.FORMAT_RGBA8, got[0])
	img.convert(Image.FORMAT_RGB8)
	return img
