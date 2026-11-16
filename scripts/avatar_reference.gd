extends SceneTree

## Replays a reference recording for compare.py to score, under a display:
## godot4 --path game --xr-mode off --fixed-fps 60 --script ../scripts/avatar_reference.gd -- REF AVATAR.vrm OUT
## Humanoid bones take poses.tsv's poses from before Unity's dynamics ran, so the body under test stands in Unity's pose.

const WARM_MS := 3000
const WARM_CAP_MS := 60000
## The recorded avatar faces +Z in Unity's axes and in these, X mirrored.
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3.BACK)
## A player's pose space looks down -Z, so the avatar stands turned around in the recorded root.
const TURN := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)

var _out := ""
var _root := Node3D.new()
var _sun := DirectionalLight3D.new()
var _avatar: Avatar
var _skeleton: Skeleton3D
var _eyes_from_head := Transform3D.IDENTITY
var _grips: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
var _tips := {}
var _tips_file: FileAccess
var _notes: Array[String] = []
## [frame, bone, pose in the root's Godot space], in frame order.
var _moves: Array[Array] = []
var _moved := 0
## Bone to the pose it last moved to (null before its first), parents first: _drive sets them in this order.
var _held := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(0)
	Budget.frame_deadline = false
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("usage: avatar_reference.gd -- REF AVATAR.vrm OUT")
		quit(2)
		return
	var ref := args[0]
	_out = args[2]
	DirAccess.make_dir_recursive_absolute(_out.path_join("render"))
	var track := _rows(ref.path_join("track.tsv")).slice(1)
	var steps := {}
	var window := Vector2i()
	for s in _rows(ref.path_join("steps.tsv")):
		steps[int(s[1])] = s[5] if s.size() > 5 else ""
		if s[4] == "motion":
			window.x = int(s[1])
		elif s[4] == "settle":
			window.y = int(s[1]) + int(s[2])
	var renders := {}
	for r in _rows(ref.path_join("renders.tsv")):
		renders[int(r[1])] = r[0]
	var view := _stage(JSON.parse_string(FileAccess.get_file_as_string(ref.path_join("camera.json"))))
	_root.transform = _unity(track[0][1])
	var scene := Avatar.read(FileAccess.get_file_as_bytes(args[1]))
	if scene == null:
		_notes.append("avatar refused: Avatar.read returned null")
	else:
		_wear(scene)
		_read_poses(ref)
		await _warm(view)
	var matched := []
	var unmatched := []
	for c in _rows(ref.path_join("chains.tsv")).slice(1):
		var leaf: String = c[0].get_slice("|", 1).get_file().get_slice("#", 0)
		# The reference's tip is the PhysBone's endpoint where it has one, which the importer makes a bone of its own.
		var bone := _bone(leaf)
		var end := _bone(leaf + " endpoint")
		if end >= 0 and _skeleton.get_bone_parent(end) == bone:
			bone = end
		(matched if bone >= 0 else unmatched).append(c[0])
		if bone >= 0:
			_tips[c[0]] = bone
	var menu := FileAccess.open(_out.path_join("menu.tsv"), FileAccess.WRITE)
	if _avatar != null and _avatar.expressions != null and not _avatar.expressions.state.data.get("menu", []).is_empty():
		_list(menu, _avatar.expressions.state.data.get("menu", []), "")
	else:
		_notes.append("no expression menu: every control reads as absent")
	menu.close()
	_tips_file = FileAccess.open(_out.path_join("tips.tsv"), FileAccess.WRITE)
	var names := _names(steps.values())
	var last := -1
	for row in track:
		await process_frame
		if last >= window.x and last < window.y:
			_record(last)
		last = int(row[0])
		_drive(row)
		if _avatar != null and _avatar.expressions != null and steps.has(last):
			for assignment: String in str(steps[last]).split(",", false):
				_avatar.expressions.state.put(names.get(assignment.get_slice("=", 0), assignment.get_slice("=", 0)), assignment.get_slice("=", 1).to_float())
		if renders.has(last):
			view.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var image := view.get_texture().get_image()
			image.convert(Image.FORMAT_RGB8)
			image.save_png(_out.path_join(renders[last]))
	await process_frame
	if last >= window.x and last < window.y:
		_record(last)
	_tips_file.close()
	var git := []
	OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "HEAD"], git)
	var meta := {"runtime": "Cairnfold", "source_revision": str(git[0]).strip_edges() if not git.is_empty() else "", "avatar": args[1], "matched_tips": matched, "unmatched_tips": unmatched, "notes": _notes}
	FileAccess.open(_out.path_join("meta.json"), FileAccess.WRITE).store_string(JSON.stringify(meta, "\t") + "\n")
	quit()


## Godot compiles a surface's pipeline in the background on first draw and leaves the surface out until it is ready,
## so a render soon after a piece first shows would miss it.
func _warm(view: SubViewport) -> void:
	var hidden: Array[Node3D] = []
	for node: Node3D in _avatar.find_children("*", "Node3D", true, false):
		if not node.visible:
			node.visible = true
			hidden.append(node)
	var held := _root.process_mode
	_root.process_mode = Node.PROCESS_MODE_DISABLED
	var last := PackedByteArray()
	var start := Time.get_ticks_msec()
	var still := start
	while Time.get_ticks_msec() - still < WARM_MS:
		if Time.get_ticks_msec() - start > WARM_CAP_MS:
			_notes.append("warm-up still changing after %d ms" % WARM_CAP_MS)
			break
		view.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var drawn := view.get_texture().get_image().get_data()
		if drawn != last:
			last = drawn
			still = Time.get_ticks_msec()
	_root.process_mode = held
	for node in hidden:
		node.visible = false


func _stage(camera: Dictionary) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(int(camera.width), int(camera.height))
	view.own_world_3d = true
	# The harness draws with MSAA, so a sub-pixel edge such as a toon outline shades part of a pixel.
	view.msaa_3d = Viewport.MSAA_4X
	_notes.append("drawn with 4x MSAA where the reference draws 2x: lavapipe draws no 2x")
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(view)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _grey(camera.background)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _grey(camera.ambient)
	var world := WorldEnvironment.new()
	world.environment = env
	view.add_child(world)
	view.add_child(_root)
	var eye := Camera3D.new()
	eye.fov = camera.fov_vertical
	eye.cull_mask = Quality.VIEW_MASK
	var p: Array = camera.position
	# A Unity camera looks down its +Z, a Godot one down its -Z.
	eye.transform = Transform3D(_turn(camera.rotation_euler) * Basis(Vector3.UP, PI), MIRROR * Vector3(p[0], p[1], p[2]))
	_root.add_child(eye)
	_sun.light_energy = camera.light_intensity
	_sun.basis = Basis.looking_at(_turn(camera.light_euler) * Vector3.BACK)
	_root.add_child(_sun)
	var ambient := _grey(camera.ambient).srgb_to_linear()
	var sky := Vector3(ambient.r, ambient.g, ambient.b)
	RenderingServer.global_shader_parameter_set(&"sun_light", Vector3.ONE * _sun.light_energy)
	RenderingServer.global_shader_parameter_set(&"sky_zenith", sky)
	RenderingServer.global_shader_parameter_set(&"sky_horizon", sky)
	RenderingServer.global_shader_parameter_set(&"sky_ambient", 1.0)
	# The harness clears to a colour with no skybox, so Unity has no reflection probe to give a clear coat.
	ExpressionPlayer.world_reflects = false
	return view


static func _grey(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])


## Unity's Euler degrees, applied Z, then X, then Y.
static func _turn(euler: Array) -> Basis:
	var q := Quaternion.from_euler(Vector3(deg_to_rad(euler[0]), deg_to_rad(euler[1]), deg_to_rad(euler[2])))
	return Basis(Quaternion(q.x, -q.y, -q.z, q.w))


## `px,py,pz,qx,qy,qz,qw` in Unity's axes.
static func _unity(field: String) -> Transform3D:
	var v := field.split_floats(",")
	return Transform3D(Basis(Quaternion(v[3], -v[4], -v[5], v[6])), Vector3(-v[0], v[1], v[2]))


func _wear(scene: PackedScene) -> void:
	_avatar = Avatar.open(scene, Color.WHITE)
	# Worn as a player wears their own, so its contacts touch its own senders as they do in the recording.
	_avatar.local = true
	_avatar.add_to_group(Contacts.BODIES)
	_avatar.transform = TURN
	_root.add_child(_avatar)
	_avatar.stand()
	_skeleton = _avatar.find_child("Skeleton3D", true, false)
	var local := _avatar.global_transform.affine_inverse()
	var eyes := Transform3D(Basis.IDENTITY, Vector3(0, _avatar.eye_height, 0))
	_eyes_from_head = (local * _avatar.bone("head")).affine_inverse() * eyes
	for s in 2:
		var hand := local * _avatar.bone(["leftHand", "rightHand"][s])
		_grips[s] = hand.basis.inverse() * (eyes * Avatar.AT_SIDES[s]).basis


## -1 for none. Names compare without case or punctuation, since the importer sanitises them.
func _bone(unity_name: String) -> int:
	if _skeleton == null:
		return -1
	var want := _plain(unity_name)
	for b in _skeleton.get_bone_count():
		if _plain(_skeleton.get_bone_name(b)) == want:
			return b
	return -1


static func _plain(name: String) -> String:
	var out := ""
	for c in name.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


func _drive(row: PackedStringArray) -> void:
	_root.transform = _unity(row[1])
	RenderingServer.global_shader_parameter_set(&"sun_toward", _root.basis * _sun.basis.z)
	if _avatar == null:
		return
	var aims: Array[Transform3D] = []
	for s in 2:
		var hand := TURN * _unity(row[3 + s])
		aims.append(Transform3D(hand.basis * _grips[s], hand.origin))
	_avatar.pose(TURN * _unity(row[2]) * _eyes_from_head, aims[0], aims[1])
	var frame := int(row[0])
	while _moved < _moves.size() and _moves[_moved][0] <= frame:
		_held[_moves[_moved][1]] = _moves[_moved][2]
		_moved += 1
	var from_root := _skeleton.global_transform.affine_inverse() * _root.global_transform
	for b: int in _held:
		if _held[b] != null:
			var at := from_root * (_held[b] as Transform3D)
			at.basis = at.basis.orthonormalized().scaled_local(_skeleton.get_bone_global_rest(b).basis.get_scale())
			_skeleton.set_bone_global_pose(b, at)


## drivers.tsv names bones by Unity's HumanBodyBones, as VRM 0 does.
func _read_poses(ref: String) -> void:
	var model := _skeleton.get_parent()
	while not model.has_meta("humanoid"):
		model = model.get_parent()
	var humanoid: Dictionary = model.get_meta("humanoid")
	var driven := {}
	for row: PackedStringArray in _rows(ref.path_join("drivers.tsv")).slice(1):
		for role: String in row[1].split(","):
			if not role.begins_with("humanoid:"):
				continue
			var unity := role.trim_prefix("humanoid:")
			unity = unity[0].to_lower() + unity.substr(1)
			var name: String = Vrm.THUMBS_0X.get(unity, unity)
			if humanoid.has(name):
				driven[row[0]] = _skeleton.find_bone((humanoid[name] as NodePath).get_concatenated_subnames())
	var order := driven.keys()
	order.sort_custom(func(x: String, y: String) -> bool: return x.count("/") < y.count("/"))
	for path: String in order:
		_held[driven[path]] = null
	var poses := FileAccess.open(ref.path_join("poses.tsv"), FileAccess.READ)
	while poses != null and not poses.eof_reached():
		var f := poses.get_line().split("\t")
		if f.size() > 3 and f[1] == "root" and driven.has(f[2]):
			_moves.append([int(f[0]), driven[f[2]], _unity(f[3])])
	var posed := {}
	for m in _moves:
		posed[m[1]] = true
	if posed.is_empty():
		_notes.append("hips not driven: the recording poses no humanoid bone, so the body hangs from the tracked head")
	else:
		_notes.append("humanoid bones placed as recorded: %d" % posed.size())


func _record(frame: int) -> void:
	if _tips.is_empty():
		return
	var to_root := _root.global_transform.affine_inverse() * _skeleton.global_transform
	for tip: String in _tips:
		var p := MIRROR * (to_root * _skeleton.get_bone_global_pose(_tips[tip]).origin)
		_tips_file.store_line("%d\t%s\t%f\t%f\t%f" % [frame, tip, p.x, p.y, p.z])


static func _rows(path: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		out.append(line.split("\t"))
	return out


func _list(file: FileAccess, controls: Array, prefix: String) -> void:
	for c: Dictionary in controls:
		var path: String = c.name if prefix.is_empty() else prefix + "/" + c.name
		file.store_string("%s\t%s\n" % [path, c.type])
		_list(file, c.get("controls", []), path)


func _names(assignments: Array) -> Dictionary:
	var names := {}
	if _avatar == null or _avatar.expressions == null:
		return names
	var numbered := RegEx.create_from_string("^VF\\d+_(.+)$")
	var defined: Dictionary = _avatar.expressions.state.definitions
	var by_rest := {}
	for name: String in defined:
		var m := numbered.search(name)
		if m != null:
			by_rest[m.get_string(1)] = name if not by_rest.has(m.get_string(1)) else ""
	for step: String in assignments:
		for assignment: String in step.split(",", false):
			var key := assignment.get_slice("=", 0)
			var m := numbered.search(key)
			if defined.has(key) or m == null or names.has(key):
				continue
			if by_rest.get(m.get_string(1), "") != "":
				names[key] = by_rest[m.get_string(1)]
			else:
				names[key] = key
				_notes.append("no parameter numbered otherwise for %s" % key)
	return names
