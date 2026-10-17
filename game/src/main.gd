class_name Main
extends Node3D

## How many mixes quitting waits for the audio thread to release the sounds that were playing: counted in mixes,
## not time, since a loaded machine mixes late. The time is only so a stalled audio driver cannot hold the quit.
const QUIT_WAIT_MIXES := 20
const QUIT_WAIT_MSEC := 10000

static var _quitting := false

var args := {}
var xr: OpenXRInterface
var rig: Rig
var world: World
var session: Session
var visit_tool: VisitTool
var _undo: Buttons
var _redo: Buttons
var tool: WallTool
var stair_tool: StairTool
var flora_tool: FloraTool
var delete_tool: DeleteTool
var fitting_tool: FittingTool
var ground_grab: GroundGrab
var water: Water
var water_tool: WaterTool
var wildlife: Wildlife
var look: Look
var sky_tool: SkyTool
var palette_tool: PaletteTool
var photo_tool: PhotoTool
var feed_tool: FeedTool
var sound: Soundscape
var metrics: Metrics
var quality: Quality
var hand_stop: HandStop
var flat: Flat


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
	world.stairs = Stairs.new(tool.masonry)
	builds.add_child(world.stairs)
	stair_tool = StairTool.new(rig, tool, world)
	add_child(stair_tool)
	tool.masonry.placed.connect(look.bounce.place)
	hand_stop = HandStop.new(rig, tool, flora)
	add_child(hand_stop)
	fitting_tool = FittingTool.new(rig, tool, world)
	add_child(fitting_tool)
	delete_tool = DeleteTool.new(rig, tool, flora_tool, world)
	add_child(delete_tool)
	ground_grab = GroundGrab.new(rig, world, _editing)
	ground_grab.reshaped.connect(tool.reground)
	add_child(ground_grab)
	var hands: Array[Node3D] = []
	hands.assign(rig.hands)
	water = Water.new(hands)
	ground_grab.reshaped.connect(water.reground)
	water.refilled.connect(tool.reground.bind(true))
	add_child(water)
	water_tool = WaterTool.new(rig, ground_grab, water)
	add_child(water_tool)
	world.attach(tool, flora, paths, ground_grab, water)
	for h in rig.hands:
		h.add_child(BudgetBar.new(world, h))
	palette_tool = PaletteTool.new(rig, tool, world)
	add_child(palette_tool)
	sky_tool = SkyTool.new(rig, look, _editing)
	add_child(sky_tool)
	photo_tool = PhotoTool.new(rig)
	if args.has("capture-dir"):
		photo_tool.folder = str(args["capture-dir"]).path_join("photos")
	add_child(photo_tool)
	_undo = Buttons.new(rig.left).watch(["undo"])
	_redo = Buttons.new(rig.right).watch(["redo"])
	var played := Session.played(args, get_tree().current_scene == self)
	var me := Persona.new(str(args.get("name", "")), int(args.get("steam-app", OS.get_environment("SteamAppId"))), "user://name" if played else "", hash(OS.get_unique_id()))
	session = Session.new(world, rig, int(args.get("avatar", -1)), int(args.get("port", Session.PORT if played else 0)), played, int(args.get("beacon-port", Session.BEACON_PORT)), me)
	session.folder = args.get("avatars", Main.player_path("avatars") if played else "")
	if played:
		DirAccess.make_dir_recursive_absolute(session.folder)
	add_child(session)
	visit_tool = VisitTool.new(rig, session)
	add_child(visit_tool)
	if args.has("join"):
		var at: PackedStringArray = str(args.join).split(":")
		session.join.call_deferred(at[0], int(at[1]) if at.size() > 1 else Session.PORT)
	wildlife = Wildlife.new(water, flora, tool, world.palette, rig.head, hands, int(args.get("seed", -1)), look)
	add_child(wildlife)
	feed_tool = FeedTool.new(rig, water)
	add_child(feed_tool)
	wildlife.scatters = feed_tool.scatters
	sound = Soundscape.new(tool, flora_tool, water)
	add_child(sound)
	rig.floor_under = func(p: Vector3) -> float: return maxf(tool.floor_under(p), world.stairs.floor_under(p))
	rig.solid_hit = func(origin: Vector3, dir: Vector3, reach: float) -> Variant:
		var build: Variant = tool.solid_hit(origin, dir, reach)
		var stair := world.stairs.pick(origin, dir, reach if build == null else origin.distance_to(build))
		return build if stair.is_empty() else stair.point
	rig.place(Vector3(0, Terrain.height_at(0, 4), 4), 0.0)
	metrics = Metrics.new(args.get("metrics", ""))
	metrics.info = {"xr": _start_xr(), "label": "", "budget": Budget.info()}
	metrics.info.flat = Main.flat_wanted(args, metrics.info.xr, played)
	if metrics.info.flat:
		flat = Flat.new(rig)
		add_child(flat)
	quality = Quality.new(xr if metrics.info.xr else null, flora, tool.masonry)
	if args.has("quality"):
		quality.pin = int(args.quality)
	add_child(quality)
	metrics.quality = quality
	metrics.head = rig.head
	metrics.world = world
	if get_tree().current_scene == self:
		metrics.play_log = PlayLog.open_enabled(args)
	metrics.context = func():
		var counts := {}
		for category in ["walls", "paths", "grounds", "groups"]:
			counts[category] = world.state[category].size()
		return {"garden_counts": counts, "masonry_instances": Array(tool.masonry.counts()),
			"tools": [Hand.Tool.keys()[rig.hands[0].tool], Hand.Tool.keys()[rig.hands[1].tool]],
			"visiting": not session.visiting.is_empty(), "players": session.players()}
	add_child(metrics)
	if played:
		move_to_player_paths()
	var garden: String = args.get("garden", player_path("garden.save") if played else "")
	if garden != "":
		world.load_from(garden)
	if args.has("script"):
		add_child(Driver.new(self, Driver.read(args.script)))
	if args.has("quit-after"):
		get_tree().create_timer(float(args["quit-after"])).timeout.connect(finish)
	get_tree().auto_accept_quit = false


func _process(_delta: float) -> void:
	if not _editing():
		if _undo.pressed("undo"):
			world.undo()
		if _redo.pressed("redo"):
			world.redo()
	_undo.latch()
	_redo.latch()


## Whether `hand`, or with none any hand, has an edit under way: a grip takes nothing from a hand mid-edit.
func _editing(hand: Hand = null) -> bool:
	return stair_tool.busy(hand) or tool.busy(hand) or flora_tool.busy(hand) or ground_grab.busy(hand) or palette_tool.busy(hand) or delete_tool.busy(hand)


## A game played without a headset comes up on the flat screen; a script or test asks for it by --flat.
static func flat_wanted(launch: Dictionary, in_xr: bool, played: bool) -> bool:
	return not in_xr and (launch.has("flat") or played and not launch.has("desktop"))


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
	if flat:
		rig.global_position += eye - rig.head.global_position
		flat.face(at)
	elif metrics.info.xr:
		rig.global_transform = want * rig.head.transform.affine_inverse()
	else:
		rig.head.global_transform = want


## With `screen`, saves the camera screen's view from the eyes instead: a headset's tracked hand points wherever
## the controller lies.
func capture(name: String, screen := false) -> void:
	var dir: String = args.get("capture-dir", "user://captures")
	DirAccess.make_dir_recursive_absolute(dir)
	var img: Image
	if screen:
		img = await photo_tool.render_screen(rig.head.global_transform)
	elif metrics.info.xr:
		img = await photo_tool.render(rig.head.global_transform, 90.0, rig.head.cull_mask)
	else:
		await RenderingServer.frame_post_draw
		img = get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	var saved := await photo_tool.save(img, path)
	if saved != OK:
		push_error("capture: could not write %s: %s" % [path, error_string(saved)])
		return
	print("capture: ", path)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		finish()


## The garden and the session log are written before the sounds wind down: a platform that asked us to
## quit may kill the process soon after.
func finish() -> void:
	world.flush()
	metrics.close()
	Main.quit(get_tree())


## A playback is freed on the main thread only after the audio thread has mixed its stop, so a sound
## still playing when the tree quits outlives the engine, its streams with it. Playbacks go in the order
## they were stopped, so a silent marker stopped last also waits out the sounds of nodes already freed.
## A 3D player hands a new playback to the audio thread on its next physics tick and holds it until then,
## even through stop().
## Where the player's `name` (a file or a folder) lives: in user data, except on Android, whose user data only the
## game can read and an uninstall erases with no way to copy it off; there it is in the app's external files folder,
## which a file manager or adb reaches.
static func player_path(name: String) -> String:
	if OS.has_feature("android"):
		var external := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP, false)
		if external != "":
			return external.path_join(name)
	return "user://" + name


## Moves the photos and the garden (with any `garden.save.new` or `.bad` beside it) an earlier build kept in user
## data to `player_path`.
static func move_to_player_paths() -> void:
	if player_path("") == "user://":
		return
	var moved := move_all("user://photos", player_path("photos"))
	for name in DirAccess.get_files_at("user://"):
		if name.begins_with("garden.save"):
			moved += int(move_file("user://" + name, player_path(name)))
	print("player data: moved %d to %s" % [moved, player_path("")])


## Moves every file in `from` into `to` and removes `from` once empty; see `move_file`. Returns how many moved.
static func move_all(from: String, to: String) -> int:
	if not DirAccess.dir_exists_absolute(from):
		return 0
	DirAccess.make_dir_recursive_absolute(to)
	var moved := 0
	for name in DirAccess.get_files_at(from):
		moved += int(move_file(from.path_join(name), to.path_join(name)))
	if DirAccess.get_files_at(from).is_empty() and DirAccess.get_directories_at(from).is_empty():
		DirAccess.remove_absolute(from)
	return moved


## Moves `src` to `dst`, or beside it as `dst.user-N` when `dst` already holds other bytes, so nothing stays behind.
## The copy lands under its name only whole, so a move cut short leaves the original to move again. Copies rather than
## renames: the two may sit on different filesystems.
static func move_file(src: String, dst: String) -> bool:
	if not FileAccess.file_exists(src):
		return false
	var base := dst
	var n := 0
	while FileAccess.file_exists(dst) and FileAccess.get_md5(dst) != FileAccess.get_md5(src):
		n += 1
		dst = "%s.user-%d" % [base, n]
	if not FileAccess.file_exists(dst):
		var part := dst + ".part"
		if DirAccess.copy_absolute(src, part) != OK or FileAccess.get_size(part) != FileAccess.get_size(src) \
				or DirAccess.rename_absolute(part, dst) != OK:
			DirAccess.remove_absolute(part)
			push_error("player data: could not move %s to %s" % [src, dst])
			return false
	DirAccess.remove_absolute(src)
	return true


static func quit(tree: SceneTree, code := 0) -> void:
	if _quitting:
		return
	_quitting = true
	var marker := AudioStreamPlayer.new()
	marker.stream = AudioStreamGenerator.new()
	tree.root.add_child(marker)
	marker.play()
	await tree.physics_frame
	await tree.process_frame
	var held: Array[WeakRef] = []
	for kind in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for p in tree.root.find_children("*", kind, true, false):
			if p.has_stream_playback():
				held.append(weakref(p.get_stream_playback()))
			p.stop()
	var playing := func() -> int: return held.filter(func(w: WeakRef) -> bool: return w.get_ref() != null).size()
	var until := Time.get_ticks_msec() + QUIT_WAIT_MSEC
	var mixes := 0
	var since := AudioServer.get_time_since_last_mix()
	while playing.call() > 0 and mixes < QUIT_WAIT_MIXES and Time.get_ticks_msec() < until:
		await tree.process_frame
		var now := AudioServer.get_time_since_last_mix()
		if now < since:
			mixes += 1
		since = now
	if playing.call() > 0:
		push_error("%d sounds still in use at exit" % playing.call())
	tree.quit(code)


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
