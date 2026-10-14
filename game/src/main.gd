extends Node3D

var args := {}
var xr: OpenXRInterface
var rig: Rig
var world: World
var session: Session
var visit_tool: VisitTool
var _undo_buttons: Buttons
var tool: WallTool
var flora_tool: FloraTool
var delete_tool: DeleteTool
var fitting_tool: FittingTool
var terrain_tool: TerrainTool
var water: Water
var water_tool: WaterTool
var wildlife: Wildlife
var look: Look
var sun_tool: SunTool
var palette_tool: PaletteTool
var photo_tool: PhotoTool
var sound: Soundscape
var metrics: Metrics
var quality: Quality


func _ready() -> void:
	args = _parse(OS.get_cmdline_user_args())
	Terrain.install()
	Ground.install()
	look = Look.build(self)
	var flora := Flora.new()
	add_child(flora)
	add_child(Meadow.new(flora))
	rig = Rig.new()
	add_child(rig)
	world = World.new()
	add_child(world)
	var builds := Node3D.new()
	builds.name = "Builds"
	add_child(builds)
	var paths := Paths.new()
	builds.add_child(paths)
	flora_tool = FloraTool.new(rig, flora, paths, world)
	add_child(flora_tool)
	tool = WallTool.new(rig, world, flora, paths)
	builds.add_child(tool)
	fitting_tool = FittingTool.new(rig, tool, world)
	add_child(fitting_tool)
	delete_tool = DeleteTool.new(rig, tool, flora_tool, world)
	add_child(delete_tool)
	terrain_tool = TerrainTool.new(rig, world)
	terrain_tool.reshaped.connect(tool.reground)
	terrain_tool.reshaped.connect(rig.reground)
	add_child(terrain_tool)
	var hands: Array[Node3D] = []
	hands.assign(rig.hands)
	water = Water.new(hands)
	terrain_tool.reshaped.connect(water.reground)
	add_child(water)
	water_tool = WaterTool.new(rig, terrain_tool, water)
	add_child(water_tool)
	world.attach(tool, flora, paths, terrain_tool, water)
	palette_tool = PaletteTool.new(rig, tool, world)
	add_child(palette_tool)
	sun_tool = SunTool.new(rig, look, _editing)
	add_child(sun_tool)
	photo_tool = PhotoTool.new(rig)
	if args.has("capture-dir"):
		photo_tool.folder = str(args["capture-dir"]).path_join("photos")
	add_child(photo_tool)
	_undo_buttons = Buttons.new(rig.left).watch(["ax_button", "by_button"])
	session = Session.new(world, rig, int(args.get("avatar", -1)), int(args.get("port", Session.PORT)))
	add_child(session)
	visit_tool = VisitTool.new(rig, session)
	add_child(visit_tool)
	if args.has("join"):
		var at: PackedStringArray = str(args.join).split(":")
		session.join.call_deferred(at[0], int(at[1]) if at.size() > 1 else Session.PORT)
	wildlife = Wildlife.new(water, flora, tool, world.palette, rig.head, hands, int(args.get("seed", -1)), look)
	add_child(wildlife)
	sound = Soundscape.new(tool, flora_tool, water)
	add_child(sound)
	rig.place(Vector3(0, Terrain.height_at(0, 4), 4), 0.0)
	metrics = Metrics.new(args.get("metrics", ""))
	metrics.info = {"xr": _start_xr(), "label": "", "budget": Budget.info()}
	quality = Quality.new(xr if metrics.info.xr else null, flora)
	if args.has("quality"):
		quality.pin = int(args.quality)
	add_child(quality)
	metrics.quality = quality
	metrics.head = rig.head
	add_child(metrics)
	var garden: String = args.get("garden", "user://garden.save" if get_tree().current_scene == self and not args.has("script") else "")
	if garden != "":
		world.load_from(garden)
	if args.has("script"):
		add_child(Driver.new(self, Driver.read(args.script)))
	if args.has("quit-after"):
		get_tree().create_timer(float(args["quit-after"])).timeout.connect(finish)


## Left D-pad down undoes, up redoes; both wait while an edit is under way.
func _process(_delta: float) -> void:
	if not _editing():
		if _undo_buttons.pressed("ax_button"):
			world.undo()
		if _undo_buttons.pressed("by_button"):
			world.redo()
	_undo_buttons.latch()


func _editing() -> bool:
	return tool.busy() or flora_tool.busy() or terrain_tool.busy() or palette_tool.busy() or delete_tool.busy()


func _start_xr() -> bool:
	xr = XRServer.find_interface("OpenXR")
	if args.has("desktop") or xr == null or not xr.is_initialized():
		return false
	if args.has("render-scale"):
		xr.render_target_size_multiplier = float(args["render-scale"])
	var vp := get_viewport()
	vp.use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var rates := xr.get_available_display_refresh_rates()
	if args.has("refresh"):
		xr.display_refresh_rate = float(args.refresh)
	xr.session_begun.connect(_note_session)
	xr.session_stopping.connect(finish)
	xr.instance_exiting.connect(finish)
	print("xr: rates ", rates, " requested ", args.get("refresh", "runtime default"))
	return true


func _note_session() -> void:
	metrics.info.refresh_hz = xr.display_refresh_rate
	metrics.info.available_hz = Array(xr.get_available_display_refresh_rates())
	metrics.info.render_size = [xr.get_render_target_size().x, xr.get_render_target_size().y] if xr.has_method("get_render_target_size") else []
	metrics.info.render_scale = xr.render_target_size_multiplier
	metrics.info.eye_fov_deg = [_fov(xr.get_projection_for_view(0, 1.0, 0.05, 400.0)), _fov(xr.get_projection_for_view(1, 1.0, 0.05, 400.0))]
	metrics.info.eye_gaze = xr.is_eye_gaze_interaction_supported()
	metrics.info.play_area = {XRInterface.XR_PLAY_AREA_SITTING: "local", XRInterface.XR_PLAY_AREA_ROOMSCALE: "local floor", XRInterface.XR_PLAY_AREA_STAGE: "stage"}.get(xr.xr_play_area_mode, str(xr.xr_play_area_mode))
	print("xr: session at ", xr.display_refresh_rate, " Hz, eye gaze ", metrics.info.eye_gaze)


## Left, right, down and up half-angles of an eye's frustum.
static func _fov(p: Projection) -> Array:
	var deg := func(t: float) -> float: return snappedf(rad_to_deg(atan(t)), 0.1)
	return [deg.call((1.0 - p.z.x) / p.x.x), deg.call((1.0 + p.z.x) / p.x.x), deg.call((1.0 - p.z.y) / p.y.y), deg.call((1.0 + p.z.y) / p.y.y)]


## Put the head at `eye` looking at `at`; in a headset the play space moves under the tracked head instead.
func view(eye: Vector3, at: Vector3, relative: bool) -> void:
	if relative:
		eye += rig.head.global_position
		at += rig.head.global_position
	var want := Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye)
	if metrics.info.xr:
		rig.global_transform = want * rig.head.transform.affine_inverse()
	else:
		rig.head.global_transform = want


func capture(name: String) -> void:
	var dir: String = args.get("capture-dir", "user://captures")
	DirAccess.make_dir_recursive_absolute(dir)
	var img: Image
	if metrics.info.xr:
		img = await photo_tool.render(rig.head.global_transform, 90.0)
	else:
		await RenderingServer.frame_post_draw
		img = get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	print("capture: ", path)


func finish() -> void:
	metrics.flush()
	get_tree().quit()


static func _parse(raw: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < raw.size():
		var key := raw[i].trim_prefix("--")
		if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
			out[key] = raw[i + 1]
			i += 2
		else:
			out[key] = true
			i += 1
	return out
