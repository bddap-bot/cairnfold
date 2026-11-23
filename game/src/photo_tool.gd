class_name PhotoTool
extends Node3D

## Godot draws a viewport whole within one frame, and on a Quest 2 a photo's frame cannot stay under 50 ms (allocating
## 60-250 ms, drawing 40-80 ms of GPU, reading 50-70 ms), so the view fades to black (Rig.cover) meanwhile. A photo
## sees Quality.FULL_LAYER at any quality step; its MSAA steps down only where memory is short (photo_msaa).

signal recorded(path: String)

const PREVIEW_SIZE := Vector2i(256, 192)
## Previews redraw one at a time, one frame in this many, and a recording camera takes every turn, so a second
## camera costs nothing more.
const PREVIEW_EVERY := 3
const PHOTO_SIZE := Vector2i(3200, 2400)
const PHOTO_MSAA := Viewport.MSAA_8X
const PHOTO_SHADOWS := 8192
const PHOTO_FADE := 0.05
## Colour and depth bytes per sample per pixel: Godot keeps every MSAA sample in memory, so at 8x the photo's view
## took 515 MB more on a Quest 2 (docs/design.md, "A photo's memory").
const SAMPLE_BYTES := 8
## Share of the reported available memory a photo's buffers may take. Taking 515 of 546 MB stalled the game 1.1 s
## while the system killed apps, and the headset's shell drew in its place; 515 of 1043 MB drew on.
const PHOTO_MEMORY_SHARE := 0.5
const VIEW_SIZE := Vector2i(1600, 1200)
const FOV := 55.0
const SHOT_HOLD := 1.2
const DARK := Color(0.06, 0.06, 0.07)
const CAMERAS: Array[Hand.Tool] = [Hand.Tool.CAMERA, Hand.Tool.SELFIE]
const RECORD_HOLD_SECONDS := 0.3
const VIDEO_SIZE := Vector2i(640, 480)
const VIDEO_FPS := 24
const VIDEO_QUALITY := 0.8
## Fraction of a photo's frame a paint surface facing the lens must cover to be what the photo is of.
const SUBJECT := 0.25
## Past this many frames awaiting write, a frame is dropped and its time goes to the next: writing never holds up play.
const VIDEO_QUEUE := 6
## Metres from a camera's body within which the other hand's grip takes its style dial.
const DIAL_REACH := 0.1
## Metres over the camera's body a grip let go lays the style over the whole view; lower, it leaves the lens alone.
const OVER_VIEW := 0.18
## The dial grows this much while a grip let go would lay its style over the whole view.
const OVER_SIZE := 1.4
const CARD := Vector2(0.04, 0.03)

var rig: Rig
var folder := Main.photos_folder()
## What every camera's lens draws through, and the eyes too while `over_view`.
var style := PhotoStyle.Kind.PLAIN
var over_view := false
var flora: Flora
var easels: Easels
## Called when the shutter is pressed, since the garden changes while the photo is drawn: {"about": Dictionary,
## "world": World.snapshot's bytes, maybe empty}.
var scene := func() -> Dictionary: return {"about": {}, "world": PackedByteArray()}
## Hand -> its preview's SubViewport.
var _previews := {}
var _photo: SubViewport
var _view: SubViewport
var _frame := 0
var _turn := 0
## Hand -> seconds its screen still holds the shot.
var _shots := {}
var _busy := false
var _covered_at_msec := 0
var _photo_msaa := PHOTO_MSAA
## Paths chosen but not yet written, so two quick shots never share one.
var _reserved := {}
var _pressed_for: Array[float] = []
var _clip: Avi
var _clip_hand: Hand
var _clip_tool: Hand.Tool
var _clip_path := ""
var _clip_time := 0.0
var _clip_slot := -1
var _owed := 0
var _sound: AudioEffectCapture
var _heard := PackedByteArray()
## Written again for a frame time no drawing came back for.
var _last_jpg := PackedByteArray()
var _queue: Array[Dictionary] = []
var _reading := 0
var _writing := -1
## The hand turning the style dial and the camera whose dial it holds.
var _turner: Hand
var _turned: Hand
var _dial: Dial


func _init(player: Rig) -> void:
	# Before the tools that take a grip as it is pressed, so a grip at a camera turns its dial and nothing else.
	process_priority = -1
	rig = player
	for h in rig.hands:
		_pressed_for.append(-1.0)


## Godot draws a frame whose pipelines are still compiling without the photo sun's shadows, so a session's first photo
## came out shadowless (docs/shadows.md): a photo's and a canvas's flat view are drawn at load to compile them.
func _ready() -> void:
	if RenderingServer.get_rendering_device() == null:
		return
	var vp := _photo_view(PREVIEW_SIZE)
	_aim(vp, rig.head.global_transform, FOV, Quality.PHOTO_MASK)
	var flat := Canvas.flat([null, null, null], false, Vector2i(8, 8))
	add_child(flat)
	await _draw_complete(vp, true)
	vp.queue_free()
	flat.queue_free()


func _viewport(size: Vector2i, msaa: Viewport.MSAA) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.msaa_3d = msaa
	vp.use_occlusion_culling = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.near = Rig.NEAR
	cam.far = rig.far()
	vp.add_child(cam)
	add_child(vp)
	return vp


func _photo_view(size: Vector2i, msaa := PHOTO_MSAA) -> SubViewport:
	var vp := _viewport(size, msaa)
	vp.mesh_lod_threshold = 0.0
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	vp.use_debanding = true
	return vp


func _view_viewport() -> SubViewport:
	if _view == null:
		_view = _viewport(VIEW_SIZE, get_viewport().msaa_3d)
	return _view


static func photo_msaa(available: int) -> Viewport.MSAA:
	var msaa := PHOTO_MSAA
	while msaa > Viewport.MSAA_DISABLED and PHOTO_SIZE.x * PHOTO_SIZE.y * (1 << msaa) * SAMPLE_BYTES > available * PHOTO_MEMORY_SHARE:
		msaa = (msaa - 1) as Viewport.MSAA
	return msaa


static func settings(msaa := PHOTO_MSAA) -> Dictionary:
	return {"size": [PHOTO_SIZE.x, PHOTO_SIZE.y], "msaa": 1 << msaa, "shadow_atlas": PHOTO_SHADOWS, "shadow_splits": 4,
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
	_turn_dial(held)
	for h in _shots:
		_shots[h] = maxf(_shots[h] - delta, 0.0)
	_write()
	if _clip_hand != null:
		_clip_time += delta
		_heard.append_array(_take_sound())
		if not held.has(_clip_hand) or _clip_hand.tool != _clip_tool or _clip.full:
			stop()
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
			if _previews.has(h):
				PhotoStyle.dress((_previews[h] as SubViewport).get_child(0), PhotoStyle.Kind.PLAIN, Quality.VIEW_MASK)
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
			_aim(preview, lens(h), FOV, Quality.VIEW_MASK, style)
			preview.render_target_update_mode = SubViewport.UPDATE_ONCE
			if h == _clip_hand:
				_grab(preview)
	for h in held:
		var i := rig.hands.find(h)
		var b := h.buttons
		if b.pressed("tool"):
			_pressed_for[i] = 0.0
		elif b.held("tool") and _pressed_for[i] >= 0.0:
			_pressed_for[i] += delta
			if _pressed_for[i] >= RECORD_HOLD_SECONDS and _clip == null:
				record(h)
		elif b.released("tool") and _pressed_for[i] >= 0.0:
			if _clip_hand == h:
				stop()
			elif _pressed_for[i] < RECORD_HOLD_SECONDS and not _busy:
				shoot(h)
			_pressed_for[i] = -1.0
	for i in rig.hands.size():
		if not rig.hands[i].buttons.held("tool"):
			_pressed_for[i] = -1.0


## The eyes draw through `kind` too while `view`, switched only as a choice is let go: a view changing as the wrist
## turns would flash.
func wear(kind: PhotoStyle.Kind, view: bool) -> void:
	style = kind
	over_view = view
	PhotoStyle.dress(rig.head, kind if view else PhotoStyle.Kind.PLAIN, rig.head.cull_mask)


func view_style() -> PhotoStyle.Kind:
	return style if over_view else PhotoStyle.Kind.PLAIN


func body(camera: Hand) -> Vector3:
	return camera.global_transform * Hand.TOP


## The other hand's grip at a held camera takes its dial: twisting turns the style, live on every lens, and letting go
## raised over the camera lays it over the whole view as well, lower takes it off.
func _turn_dial(held: Array[Hand]) -> void:
	if _turner != null:
		var raised := _turner.global_position.y - body(_turned).y > OVER_VIEW
		if not held.has(_turned) or not _turner.tracked():
			style = _dial.start as PhotoStyle.Kind
			_close_dial()
		elif not _turner.buttons.held("grab"):
			_close_dial()
			wear(style, raised)
		else:
			_turner.hold()
			if _dial.twist(_turner, _dial.wrist(_turner)):
				style = _dial.pick as PhotoStyle.Kind
			_dial.size = OVER_SIZE if raised else 1.0
			_dial.follow(_turner)
		return
	for h in rig.hands:
		if held.has(h) or not h.buttons.pressed("grab") or h.taken() or h.picking or not h.tracked():
			continue
		for camera in held:
			if h.global_position.distance_to(body(camera)) <= DIAL_REACH:
				_open_dial(h, camera)
				return


func _open_dial(hand: Hand, camera: Hand) -> void:
	_turner = hand
	_turned = camera
	hand.hold()
	_dial = Dial.new()
	add_child(_dial)
	var cards: Array[Node3D] = []
	for kind: PhotoStyle.Kind in PhotoStyle.Kind.values():
		cards.append(card(kind))
	_dial.open(hand, cards, style)


func _close_dial() -> void:
	for c in _dial.release():
		c.queue_free()
	_dial = null
	_turner = null
	_turned = null


## A small print of a meadow under a sky in `kind`'s colours, for the eyes alone: the camera's screen shows the style
## at the top on the lens's own view.
static func card(kind: PhotoStyle.Kind) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = CARD
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/style_card.gdshader")
	var tone: Variant = PhotoStyle.TONES[kind]
	mat.set_shader_parameter(&"tone", tone if tone != null else Basis.IDENTITY)
	mat.set_shader_parameter(&"strokes", kind == PhotoStyle.Kind.PAINTERLY)
	mat.set_shader_parameter(&"lift", PhotoStyle.LIFT if kind == PhotoStyle.Kind.SCULPTURE else 0.0)
	var m := MeshInstance3D.new()
	m.mesh = quad
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.layers = Quality.EYES_LAYER
	return m


static func screen(hand: Hand, tool: Hand.Tool) -> StandardMaterial3D:
	return ToolModels.screen(hand.model(tool))


static func _show(on: StandardMaterial3D, tex: Texture2D, tint: Color) -> void:
	on.albedo_texture = tex
	on.albedo_color = tint


static func lens(hand: Node3D) -> Transform3D:
	var t := hand.global_transform
	var basis := t.basis.orthonormalized()
	if hand is Hand and (hand as Hand).tool == Hand.Tool.SELFIE:
		return Transform3D(basis * Basis(Vector3.UP, PI), t * (Hand.TOP + ToolModels.SELFIE_LENS))
	return Transform3D(basis, t * (Hand.TOP + ToolModels.CAMERA_LENS))


func _aim(vp: SubViewport, at: Transform3D, fov: float, mask: int, kind := PhotoStyle.Kind.PLAIN) -> void:
	var cam: Camera3D = vp.get_child(0)
	cam.global_transform = at
	cam.fov = fov
	PhotoStyle.dress(cam, kind, mask)
	if rig.body != null and rig.body.visible and mask & Quality.SELF_LAYER:
		rig.pose_body()


func render_screen(at: Transform3D) -> Image:
	var vp := _viewport(PREVIEW_SIZE, Viewport.MSAA_DISABLED)
	_aim(vp, at, FOV, Quality.VIEW_MASK, style)
	await _draw_complete(vp)
	var img: Image = (await _read([vp])).pop_front()
	vp.queue_free()
	return img


## Returns where it was saved, or "" if it could not be taken.
func shoot(hand: Hand) -> String:
	var at := lens(hand)
	Cues.play(Cues.Act.PHOTO, at.origin, hand)
	var around: Dictionary = scene.call()
	var subjects := _subjects(at)
	var look := style
	var img := await render(at, FOV, Quality.PHOTO_MASK, look)
	if img == null:
		return ""
	var msaa := _photo_msaa
	var paintings: Array = []
	for subject: Array in subjects:
		var c: Canvas = subject[1]
		if is_instance_valid(c) and c.is_inside_tree():
			var painting := await _flatten(c)
			if not painting.is_empty():
				paintings.append([subject[0]] + painting)
	var path := _reserve("png")
	var about: Dictionary = around.about.duplicate()
	about.merge({"taken": Time.get_datetime_string_from_system(), "build": Main.revision(), "settings": settings(msaa),
		"camera": {"position": _floats(at.origin), "rotation": _floats(at.basis.get_rotation_quaternion()), "fov": FOV},
		"style": PhotoStyle.named(look)})
	# The frame the reads land on copies them out of GPU memory (`_read`): it ends under the cover.
	await get_tree().process_frame
	rig.uncover()
	print("photo: the view was covered %d ms" % (Time.get_ticks_msec() - _covered_at_msec))
	for h in _shots:
		_shots[h] = 0.0
	_shots[hand] = SHOT_HOLD
	var saved := await save(img, path, about, around.world)
	_reserved.erase(path)
	if not _report(path, saved):
		return ""
	var counts := {}
	for painting: Array in paintings:
		var kind: String = painting[0]
		counts[kind] = counts.get(kind, 0) + 1
		var stem := "%s-%s-%d" % [path.get_basename(), kind, counts[kind]]
		var colour: Image = painting[1]
		var height: Image = painting[2]
		if colour != null:
			_report(stem + ".png", await save(colour, stem + ".png"))
		if height != null:
			_report(stem + "-height.png", await _store(stem + "-height.png", func() -> PackedByteArray:
				# canvas_flat.gdshader puts each sample's high byte in red, so RG8's bytes are PNG's big-endian samples.
				height.convert(Image.FORMAT_RG8)
				return PhotoMeta.gray16(height.get_size(), height.get_data(), "Height off the board: 0 to 65535 is 0 to %.2f mm" % (Canvas.TOP * 1000.0))))
	return path


func _report(path: String, saved: Error) -> bool:
	if saved != OK:
		push_error("photo: could not write %s: %s" % [path, error_string(saved)])
		return false
	print("photo: ", path)
	return true


## ["canvas" or "palette", Canvas] per surface the photo is of, by easel, oldest first.
func _subjects(at: Transform3D) -> Array:
	var out := []
	if easels == null or RenderingServer.get_rendering_device() == null:
		return out
	var ids := easels.easels.keys()
	ids.sort()
	for id: int in ids:
		var e := easels.find(id)
		if coverage(at, e.canvas_frame()) >= SUBJECT:
			out.append(["canvas", e.canvas])
		if coverage(at, e.board_mesh.global_transform, e.board.metres) >= SUBJECT:
			out.append(["palette", e.board])
	return out


## Colour and height are drawn on a frame after the photo's, which already costs its frame plenty; [] if the canvas
## was taken away before they were drawn.
func _flatten(canvas: Canvas) -> Array[Image]:
	var views: Array[SubViewport] = [canvas.flat_view(false), canvas.flat_view(true)]
	for vp in views:
		add_child(vp)
	await RenderingServer.frame_post_draw
	var out := await _read(views)
	for vp in views:
		vp.queue_free()
	return out if is_instance_valid(canvas) and canvas.is_inside_tree() and out.size() == views.size() else []


## Fraction of the frame covered, negative when the lens sees its back; `metres` is the surface's size in `frame`'s
## plane. Only what lies past the lens's near plane counts.
static func coverage(at: Transform3D, frame: Transform3D, metres := Brushwork.METRES) -> float:
	var h := metres * 0.5
	var seen := (at.affine_inverse() * frame) * PackedVector3Array([Vector3(-h.x, -h.y, 0), Vector3(h.x, -h.y, 0), Vector3(h.x, h.y, 0), Vector3(-h.x, h.y, 0)])
	var ahead := PackedVector2Array()
	var half := Vector2(float(PHOTO_SIZE.x) / PHOTO_SIZE.y, 1.0) * tan(deg_to_rad(FOV) * 0.5)
	for i in seen.size():
		var a := seen[i]
		var b := seen[(i + 1) % seen.size()]
		if a.z < -Rig.NEAR:
			ahead.append(Vector2(a.x, a.y) / (-a.z * half))
		if (a.z < -Rig.NEAR) != (b.z < -Rig.NEAR):
			var c := a.lerp(b, (-Rig.NEAR - a.z) / (b.z - a.z))
			ahead.append(Vector2(c.x, c.y) / (Rig.NEAR * half))
	if ahead.size() < 3:
		return 0.0
	var shot := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	var inside := 0.0
	for piece in Geometry2D.intersect_polygons(ahead, shot):
		inside += absf(_area(piece))
	return signf(_area(ahead)) * inside / 4.0


static func _area(polygon: PackedVector2Array) -> float:
	var twice := 0.0
	for i in polygon.size():
		twice += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return twice * 0.5


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


## Returns where it was saved, or "" if it could not be.
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
	AudioServer.remove_bus_effect(0, Soundscape.effect_index(0, _sound))
	_sound = null
	while _writing != -1 or not _queue.is_empty():
		await get_tree().process_frame
	var path := _clip_path
	var clip := _clip
	var closed: Error = await _on_worker(func() -> Error: return clip.close())
	_reserved.erase(path)
	_clip = null
	_clip_path = ""
	if closed != OK:
		push_error("video: could not write %s: %s" % [path, error_string(closed)])
		path = ""
	else:
		print("video: ", path, " ", clip.frames, " frames")
	recorded.emit(path)
	return path


func _take_sound() -> PackedByteArray:
	if _sound == null:
		return PackedByteArray()
	return _sound.get_buffer(_sound.get_frames_available()).to_byte_array()


## Repeats the frame over any frame times since the last, as when play drops below the refresh rate.
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


## One worker task at a time, so frames reach the file in order.
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


static func lens_of(about: Dictionary) -> Transform3D:
	var p: Array = about.camera.position
	var q: Array = about.camera.rotation
	return Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), Vector3(p[0], p[1], p[2]))


func save(img: Image, path: String, about: Variant = null, world := PackedByteArray()) -> Error:
	return await _store(path, func() -> PackedByteArray:
		img.convert(Image.FORMAT_RGB8)
		var png := img.save_png_to_buffer()
		return png if about == null else PhotoMeta.embed(png, about, world))


## Encoding a photo-sized image takes longer than a frame.
func _store(path: String, encode: Callable) -> Error:
	var file := ProjectSettings.globalize_path(path)
	return await _on_worker(func() -> Error: return Main.write_bytes(file, encode.call()))


## ERR_BUG if `work` fails to return.
func _on_worker(work: Callable) -> Error:
	var result := [ERR_BUG]
	var task := WorkerThreadPool.add_task(func() -> void: result[0] = work.call())
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return result[0]


## With Quality.FULL_LAYER in `mask`, returns with the view still covered for the caller to lift (Rig.uncover).
func render(at: Transform3D, fov: float, mask: int, kind := PhotoStyle.Kind.PLAIN) -> Image:
	var rd := RenderingServer.get_rendering_device()
	if rd == null or not is_inside_tree():
		push_error("photo: no renderer to take it with")
		return null
	while _busy:
		await get_tree().process_frame
	_busy = true
	if mask & Quality.FULL_LAYER == 0:
		var view := _view_viewport()
		_aim(view, at, fov, mask, kind)
		await _draw_complete(view)
		var seen: Image = (await _read([view])).pop_front()
		# Idle, it carves nothing (PhotoStyle.carve).
		_aim(view, at, fov, mask)
		_busy = false
		return seen
	if _photo == null:
		_photo_msaa = photo_msaa(OS.get_memory_info().available)
	# Drawing the full view again each frame its pipelines still compile took a Quest 2 185 ms a frame.
	var warm := _photo_view(PREVIEW_SIZE, _photo_msaa)
	_aim(warm, at, fov, mask, kind)
	await _draw_complete(warm, true)
	warm.queue_free()
	_covered_at_msec = Time.get_ticks_msec()
	while not rig.cover(PHOTO_FADE, "a photo"):
		await get_tree().process_frame
	# The photo's view is made under the cover and let go once the screen stops showing it: held, its buffers left
	# the system short enough of memory to page the engine's own code back in on the main thread (148 ms frames).
	if _photo == null:
		_photo = _photo_view(PHOTO_SIZE, _photo_msaa)
	var atlas: int = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")
	var bits: bool = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits")
	RenderingServer.directional_shadow_atlas_set_size(PHOTO_SHADOWS, bits)
	_aim(_photo, at, fov, mask, kind)
	await _draw_complete(_photo, true)
	RenderingServer.directional_shadow_atlas_set_size(atlas, bits)
	var img: Image = (await _read([_photo])).pop_front()
	_busy = false
	return img


## A viewport can finish a frame while its pipelines are still compiling; reading it then would save missing geometry
## or shadows.
func _draw_complete(vp: SubViewport, finest := false) -> void:
	while true:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_pre_draw
		var issued := Engine.get_frames_drawn()
		var undo := draw_finest() if finest else Callable()
		await RenderingServer.frame_post_draw
		if undo.is_valid():
			undo.call()
		while Engine.get_frames_drawn() <= issued:
			await get_tree().process_frame
		if Quality.nothing_skipped(vp.get_viewport_rid()):
			return


## Asynchronous, so the asking frame does not stall; the frame the pixels land on copies them out (`render`'s cover).
func _read(views: Array[SubViewport]) -> Array[Image]:
	var rd := RenderingServer.get_rendering_device()
	var got := {}
	var sizes: Array[Vector2i] = []
	for i in views.size():
		var tex := RenderingServer.texture_get_rd_texture(views[i].get_texture().get_rid())
		var fmt := rd.texture_get_format(tex)
		if fmt.format != RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM and fmt.format != RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
			push_error("photo: the view came back in format %d, not RGBA8" % fmt.format)
			return []
		sizes.append(Vector2i(fmt.width, fmt.height))
		rd.texture_get_data_async(tex, 0, func(data: PackedByteArray) -> void: got[i] = data)
	while got.size() < views.size():
		await get_tree().process_frame
	var out: Array[Image] = []
	for i in views.size():
		out.append(Image.create_from_data(sizes[i].x, sizes[i].y, false, Image.FORMAT_RGBA8, got[i]))
	return out


## The foliage's blobs are set finest after every script's turn, so the quality governor (Quality) does not undo them
## before the frame draws; the eyes see that frame drawn so too.
func draw_finest() -> Callable:
	var blobs := flora.blob_detail if flora != null else 0
	if flora != null:
		flora.blob_detail = Quality.ladder[0].blob_detail
	return func() -> void:
		if flora != null:
			flora.blob_detail = blobs
