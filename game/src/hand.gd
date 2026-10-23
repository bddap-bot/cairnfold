class_name Hand
extends XRController3D

## A controller and the tool it holds. Every tool's input code dispatches on `tool`, and the object held and the
## selection wheel show it, so they cannot disagree. A hand holding a tool is drawn as that tool alone; only an empty
## hand shows the controller.

enum Tool { WALLS, FLOWERS, GRASS, TREES, DELETE, POND, FENCE, WINDOWS, DECORATIONS, STONE, COLOUR, CAMERA, HOUSE, NONE, SEEDS, DIRT_PATH, STYLE, STAIRS, EASEL, TOWER, ARCH, BOOK, SELFIE, BUSHES, BOULDER, MOSS }

## The wheel's contents, clockwise from the top; an Array is a subtree, null an empty slot. Fixed, so every
## pick is a learnable motion.
const TREE := [
	[Tool.COLOUR, Tool.STYLE],
	[[Tool.CAMERA, Tool.SELFIE], Tool.SEEDS, Tool.EASEL],
	[Tool.FLOWERS, [Tool.GRASS, Tool.MOSS], [Tool.TREES, Tool.BUSHES], Tool.POND],
	["avatars", "friends", Tool.BOOK],
	Tool.DELETE,
	[Tool.DIRT_PATH, Tool.STONE, Tool.STAIRS],
	[Tool.WALLS, Tool.FENCE, Tool.WINDOWS, Tool.ARCH],
	[Tool.HOUSE, Tool.TOWER, Tool.DECORATIONS, Tool.BOULDER],
]
const TOP := Vector3(0, 0.0075, 0.045)
## How many times its size on the wheel a tool is held, so a wand or a spade is as long as a hand's.
const HELD := {Tool.STYLE: 3.0, Tool.DELETE: 3.0}
## A sight's colour while what the tool shows would not fit.
const REFUSED := Color(0.92, 0.3, 0.26, 0.75)
## Past this many metres from the eyes the mark where a hand points grows with distance, so it never shrinks to nothing.
const MARK_NEAR := 4.0
## The controller's front, where an empty hand's sight stands.
const CONTROLLER_TIP := Vector3(0, -0.01, -0.015)
const POP := 0.18
const HOT := 1.4
const IDLE := 0.8
## Tools that work by touch at arm's length: a hand holding one stays where the controller is.
const STAYS := [Tool.SEEDS, Tool.EASEL, Tool.CAMERA, Tool.SELFIE, Tool.BOOK]
## Tools with no model in the hand.
const UNMODELLED := [Tool.NONE, Tool.EASEL, Tool.BOOK]
## How far a wheel icon's model tips its top toward the eye.
const TILT := PI * 0.3
## Seconds between looks, while the wheel is closed, for an icon to build or free: one built per look keeps a person's
## figure changing, a friend arriving or an avatar chosen, to one figure's build in a frame.
const PREPARE_EVERY := 0.25
static var _disc: CylinderMesh
static var _icon_mats := {}

## The stick pushed one way, as the input named for it: past PUSH, along whichever way it is pushed most, it
## holds that way until it comes back inside LET_GO, so one flick is one input.
const FLICKS := {"primary_up": Vector2(0, 1), "primary_down": Vector2(0, -1), "primary_left": Vector2(-1, 0), "primary_right": Vector2(1, 0)}
const PUSH := 0.7
const LET_GO := 0.3

## Stick positions the driver injects, keyed by tracker.
static var injected_sticks := {}
## Hand positions in the wheel's plane the driver injects, keyed by tracker, in place of the hand's own.
static var injected_reach := {}
## Tracked hands' joints the driver injects, keyed by tracker, global, in place of the runtime's (`HandShape`).
static var injected_joints := {}
## A bare hand moved this far from where its little finger pinched pushes the stick all the way.
const STICK_REACH := 0.1

var carried: Node3D
## The controller's pose over the floor, which a reaching hand is thrown out from (`Reach`).
var controller := Transform3D()
## The driver holds the controller rather than the hand, which reaches from it as a tracked one does.
var held_reaches := false
var reach: Reach
## The pose this hand last set itself to: one the runtime or the driver did not move since.
var _placed := Transform3D()

var tool := Tool.WALLS:
	set(value):
		if tool != value and picking:
			close_wheel()
		tool = value
## The way the stick is flicked (a FLICKS key), or "".
var flick := ""
var picking := false
## The garden whose frame budget the hand's tool previews against.
var world: World
## What the hand's tool shows would not fit the frame budget: its sight shows it refused.
var capped := false
## The model held while the hand holds `t`.
func model(t: Tool) -> Node3D:
	return _models[t]


var _profile := ""
var flat_only := false
var people: SessionWheel:
	set(v):
		people = v
		_prepare_icons(-1)
		_warming = 2
var _wheel: ToolWheel
var _drawn_levels := 0
var _holding := false
## The driver holds this hand where tracking would put it. In a headset it names a pose the runtime does not have, so
## the controller's own pose stops moving the hand.
var held_still := false:
	set(v):
		held_still = v
		_follow()
## Played by its joints, not a controller (see "Tracked hands"): its pose is the palm's, its inputs its gesture's.
var bare := false
## What the bare hand's fingers make (`HandShape.read`), pressing the input `Controls.HAND` gives it.
var gesture := ""
## Where, in the rig, the bare hand's little finger pinched: the stick's centre.
var _stick_from := Vector3.ZERO
var _buttons: Buttons
## The hand as seen, with the tool on top: HandStop holds it at what the controller pushes into.
var body := Node3D.new()
var _shown := -1
var _leaving := -1
var _pop_t := POP
var _models: Array[Node3D] = []
var _wheel_root: Node3D
## Every wheel icon with the slot-index path to it (ToolWheel.paths), subtrees and their items alike.
var _icons: Array[Dictionary] = []
## Every icon the wheel could show, hidden until it does, by _icon_key.
var _built := {}
var _since_prepared := 0.0
## Frames left drawing every icon once, too small to see, so the renderer compiles their pipelines while the game
## loads: the first open compiled 21 in its frame and dropped it on a Quest 2.
var _warming := 0
var _controller := MeshInstance3D.new()
var _sight: Sight
var _dot: MeshInstance3D


func _init(tracker_name: String, held: Tool) -> void:
	tracker = tracker_name
	pose = &"aim"
	tool = held
	reach = Reach.new(tracker_name == "right_hand")
	process_priority = -10
	add_child(body)
	_controller.mesh = Meshes.rounded_box(0.3, 2, 7)
	_controller.scale = Vector3(0.05, 0.035, 0.11)
	_controller.position = HandStop.CENTRE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.9, 0.84)
	mat.roughness = 0.6
	_controller.material_override = mat
	body.add_child(_controller)
	for t in Tool.size():
		var m := Node3D.new() if t in UNMODELLED else ToolModels.build(t)
		m.position = TOP
		m.scale = Vector3.ZERO
		m.visible = false
		body.add_child(m)
		_models.append(m)
	_build_wheel()
	# Both sights stay until a headset playtest culls one: the right hand's is the ring, the left's the bead.
	_sight = Sight.new(tracker_name == "right_hand")
	body.add_child(_sight)
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	_dot = MeshInstance3D.new()
	_dot.mesh = dot
	_dot.material_override = _sight.material_override
	_dot.top_level = true
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dot)
	_buttons = Buttons.new(self).watch(["wheel"])


func _build_wheel() -> void:
	_wheel_root = Node3D.new()
	_wheel_root.top_level = true
	_wheel_root.visible = false
	add_child(_wheel_root)


## Draws every surface under `root` in the one icon look (icon.gdshaderinc), lit by nothing in the garden: a standard
## material gives its colour, picture and whether its vertex colours count (icon.gdshader); a shader material that paints
## its own surface names its twin in that look in its "icon_material" meta; any other draws its vertex colours, tinted
## by its "icon_colour" meta where it sets one, and not at all where that colour is clear.
static func unlit(root: Node) -> void:
	for g: GeometryInstance3D in root.find_children("*", "MeshInstance3D", true, false) + root.find_children("*", "MultiMeshInstance3D", true, false):
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mi := g as MeshInstance3D
		if g.material_override != null or mi == null:
			var mesh: Mesh = mi.mesh if mi != null else (g as MultiMeshInstance3D).multimesh.mesh
			g.material_override = _icon_material(g.material_override if g.material_override != null else mesh.surface_get_material(0), g)
		else:
			for i in mi.get_surface_override_material_count():
				mi.set_surface_override_material(i, _icon_material(mi.get_active_material(i), g))


static func _icon_material(mat: Material, g: GeometryInstance3D) -> ShaderMaterial:
	var look := {"colour": Color.WHITE, "use_vertex": true, "picture": null, "uv_scale": Vector2.ONE, "uv_offset": Vector2.ZERO}
	var base := mat as BaseMaterial3D
	if base != null:
		look = {"colour": base.albedo_color, "use_vertex": base.vertex_color_use_as_albedo, "picture": base.albedo_texture,
			"uv_scale": Vector2(base.uv1_scale.x, base.uv1_scale.y), "uv_offset": Vector2(base.uv1_offset.x, base.uv1_offset.y)}
	elif mat != null and mat.has_meta("icon_material"):
		return mat.get_meta("icon_material")
	elif mat != null:
		look.colour = mat.get_meta("icon_colour", Color.WHITE)
		g.visible = g.visible and look.colour.a > 0.0
	# Keyed by what it draws, not by the material it stands for, so a figure's own tints share and never pile up.
	var key := str(look.values())
	var out: ShaderMaterial = _icon_mats.get(key)
	if out == null:
		out = ShaderMaterial.new()
		out.shader = preload("res://src/icon.gdshader")
		for k in look:
			out.set_shader_parameter(k, look[k])
		_icon_mats[key] = out
	return out


func inventory() -> Array:
	var tree := TREE.duplicate(true)
	if people != null:
		tree[3] = [people.avatars(), people.friends(), Tool.BOOK]
	if flat_only:
		return [null, [Tool.CAMERA, Tool.SEEDS], null, tree[3], null, null, null, null]
	return tree


func close_wheel() -> void:
	_wheel = null
	picking = false
	_wheel_root.visible = false
	_clear_icons()


func _clear_icons() -> void:
	for e in _icons:
		e.node.visible = false
	_icons.clear()
	_drawn_levels = 0


func _build_icons(items: Array, centre: Vector2, dirs: Array[Vector2], prefix: Array[int]) -> void:
	for k in items.size():
		if items[k] == null:
			continue
		var at := centre + dirs[k] * ToolWheel.RADIUS
		var path := prefix.duplicate()
		path.append(k)
		var key := _icon_key(path, items[k])
		if not _built.has(key):
			_built[key] = _make_icon(items[k])
		var i: Node3D = _built[key]
		i.position = Vector3(at.x, at.y, 0)
		i.scale = Vector3.ZERO
		_icons.append({"path": path, "node": i})


func _warm() -> void:
	_warming -= 1
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_wheel_root.global_transform = Transform3D(cam.global_basis, cam.global_position - cam.global_basis.z * 0.5)
	_wheel_root.visible = _warming > 0
	for i: Node3D in _built.values():
		i.visible = _warming > 0
		i.scale = Vector3.ONE * 0.001


## Builds every icon the wheel could show now and frees those it no longer could, at most `budget` built (-1 for
## all): opening the wheel or reaching a subtree then builds nothing, where building took 20 to 134 ms a level on a
## Quest 2 and dropped frames.
func _prepare_icons(budget: int) -> void:
	var wanted := {}
	_wanted(inventory(), [] as Array[int], wanted)
	for key: String in _built.keys():
		if not wanted.has(key):
			_built[key].free()
			_built.erase(key)
	for key: String in wanted:
		if budget == 0:
			return
		if not _built.has(key):
			_built[key] = _make_icon(wanted[key])
			budget -= 1


func _wanted(items: Array, prefix: Array[int], out: Dictionary) -> void:
	for k in items.size():
		if items[k] == null:
			continue
		var path := prefix.duplicate()
		path.append(k)
		out[_icon_key(path, items[k])] = items[k]
		if items[k] is Array:
			_wanted(items[k], path, out)


## Where an icon sits and what it shows, which for a person's figure includes what it is drawn from.
func _icon_key(path: Array[int], item: Variant) -> String:
	return "%s %s %s" % [path, item, _signature(item)]


## What the people an icon draws are drawn from, through every subtree it shows in miniature.
func _signature(item: Variant) -> String:
	if people == null:
		return ""
	if item is String:
		return people.signature(item)
	if item is Array:
		return " ".join(item.map(_signature))
	return ""


func _make_icon(item: Variant) -> Node3D:
	var model := miniature(item, people.figure if people != null else Callable())
	var i := icon(model)
	if item is String and people != null:
		model.transform = Transform3D(Basis.IDENTITY, Vector3(0, -0.027, 0))
	unlit(i)
	i.scale = Vector3.ZERO
	i.visible = false
	_wheel_root.add_child(i)
	return i


## A tool's model, or a subtree's items in miniature, two by two, each drawn as its own icon draws it: a person by
## `figure` (SessionWheel.figure), or a generic figure without one, and a nested subtree in miniature again, `depth`
## levels down at most so a long page of friends stays a few figures to build.
static func miniature(item: Variant, figure := Callable(), depth := 2) -> Node3D:
	if item is String:
		if figure.is_valid():
			return figure.call(item)
		var generic := Node3D.new()
		ToolModels._figure(generic)
		return generic
	if not item is Array:
		return ToolModels.build(item)
	var model := Node3D.new()
	for j in mini(item.size(), 4):
		if item[j] is Array and depth <= 1:
			continue
		var mini := miniature(item[j], figure, depth - 1)
		mini.scale = Vector3.ONE * 0.5
		if item.size() > 1:
			mini.position = Vector3((j % 2 - 0.5) * 0.03, 0, (floorf(j * 0.5) - 0.5) * 0.03)
		model.add_child(mini)
	return model


## A wheel icon: `model` tipped toward the eye, as a controller's top is seen, on a pale disc facing the eye (+z) so
## it reads against the meadow at any hour.
static func icon(model: Node3D) -> Node3D:
	if _disc == null:
		_disc = CylinderMesh.new()
		_disc.top_radius = 0.034
		_disc.bottom_radius = 0.034
		_disc.height = 0.001
		_disc.radial_segments = 24
		_disc.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.86, 0.85, 0.8)
		_disc.material = mat
	var out := Node3D.new()
	var back := MeshInstance3D.new()
	back.mesh = _disc
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.025))
	out.add_child(back)
	model.transform = Transform3D(Basis(Vector3.RIGHT, TILT), Vector3(0, -0.012, 0))
	out.add_child(model)
	return out


## The open wheel's frame: x to the player's right, y the player's up, z toward the head.
func wheel_frame() -> Transform3D:
	return _wheel_root.global_transform


## The thumbstick as locomotion reads it; on a bare hand, the hand's own move (not where reach throws it) from where
## the little finger pinched.
func stick() -> Vector2:
	if injected_sticks.has(tracker):
		return injected_sticks[tracker]
	if not bare:
		return get_vector2("primary")
	if gesture != "little":
		return Vector2.ZERO
	var right := (get_parent() as Rig).head.global_basis.x
	right = Vector3(right.x, 0.0, right.z).normalized()
	var moved := (get_parent() as Node3D).global_basis * (controller.origin - _stick_from)
	return (Vector2(moved.dot(right), moved.dot(Vector3.UP.cross(right))) / STICK_REACH).limit_length(1.0)


## How many metres a thing pulled at `reach` metres moves per metre of hand, so far things keep up.
static func reach_gain(reach: float) -> float:
	return maxf(1.0, reach / 1.2)


func tracked() -> bool:
	return held_still or bare or get_has_tracking_data()


## Whether this hand reaches far by stretching (`Reach`), grabbing by touch, rather than by pointing.
func reaches() -> bool:
	return Reach.mode == Reach.Mode.GOGO and (held_reaches or not held_still)


## Where the grip looks for what it takes, from along the aim, and how far it looks: a reaching hand what it touches,
## before or after it, any other what it points at.
func grip_from() -> Vector3:
	return global_position + global_basis.z * Reach.TOUCH if reaches() else global_position


func grip_reach() -> float:
	return 2.0 * Reach.TOUCH if reaches() else INF


## Where the controller is in the garden.
func at_controller() -> Vector3:
	return (get_parent() as Node3D).global_transform * controller.origin


## Throws the hand out from the controller by `reach` while it holds a build tool or nothing; a pose the runtime or
## the driver set since the last frame is the controller's.
func _reach(delta: float) -> void:
	if transform != _placed:
		controller = transform
	var rig := get_parent() as Rig
	if rig != null and reaches() and tracked() and not picking and not _buttons.held("wheel") and not tool in STAYS:
		# Upright at the floor, so a script tipping the rig to level an unworn headset still measures across the ground.
		var floor := Transform3D(Basis(), rig.global_position)
		var to_floor := floor.affine_inverse()
		global_transform = floor * reach.project(to_floor * rig.global_transform * controller, to_floor * rig.head.global_transform, delta)
	else:
		reach.rest()
		transform = controller
	_placed = transform


## Whether it holds the seed dish out: animals eat from it, here and, through `Session`, in every other player's game.
func holds_seeds() -> bool:
	return tool == Tool.SEEDS and tracked() and not picking


## Tools call this each frame they point: the held tool's sight shows, and a mark where it meets `hit`. Both hide on
## frames nobody does.
func point(hit: Variant, tint: Color) -> void:
	if not tracked() or _holding:
		return
	_sight.visible = true
	_sight.tint(REFUSED if capped else tint)
	_dot.visible = hit != null
	if hit != null:
		var cam := get_viewport().get_camera_3d()
		var far := cam.global_position.distance_to(hit) if cam != null else 0.0
		_dot.global_transform = Transform3D(Basis().scaled(Vector3.ONE * maxf(1.0, far / MARK_NEAR)), hit)


## Whether the hand shows its sight this frame.
func aiming() -> bool:
	return _sight.visible


## Whether a tool already holds this hand this frame.
func taken() -> bool:
	return _holding or carried != null


func clear_pointer() -> void:
	_sight.visible = false
	_dot.visible = false


# A tool renews its hold each frame, so a cancelled gesture cannot leave a stale hidden pointer.
func hold() -> void:
	_holding = true
	clear_pointer()


func _process(delta: float) -> void:
	_read_hand()
	_reach(delta)
	_log_profile()
	_flick_input()
	_holding = false
	clear_pointer()
	if world != null:
		var with := world.fill(self)
		capped = with > 1.0 and with > world.fill() + 0.0001
	_select_input(delta)
	_buttons.latch()
	_show_tool(delta)


## Follows the hand's joints while the runtime reports them as the hand's own, or while it cannot say whose they are and
## reports no controller pose for this hand; otherwise the controller.
func _read_hand() -> void:
	var joints: Array = injected_joints.get(tracker, [])
	if joints.is_empty() and not held_still:
		joints = _runtime_joints()
	var was := bare
	bare = not joints.is_empty()
	if bare != was:
		print("controls: %s %s" % [tracker, "bare" if bare else "on its controller"])
		_follow()
	if not bare:
		gesture = ""
		return
	global_transform = joints[HandShape.PALM].orthonormalized()
	var g := HandShape.read(joints, gesture)
	if g == "little" and gesture != "little":
		_stick_from = position
	gesture = g


func _runtime_joints() -> Array:
	var side := "left" if tracker == &"left_hand" else "right"
	var t := XRServer.get_tracker("/user/hand_tracker/" + side) as XRHandTracker
	if t == null or not t.has_tracking_data or t.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER:
		return []
	if t.hand_tracking_source != XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED and _controller_posed():
		return []
	var origin := (get_parent() as Node3D).global_transform
	var out: Array[Transform3D] = []
	for j in HandShape.JOINTS:
		if not t.get_hand_joint_flags(j) & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID:
			return []
		out.append(origin * t.get_hand_joint_transform(j))
	return out


func _controller_posed() -> bool:
	var t := XRServer.get_tracker(tracker) as XRPositionalTracker
	var p := t.get_pose(&"aim") if t != null else null
	return p != null and p.has_tracking_data


## The controller's aim moves the hand unless the driver holds it or its joints do: then the hand follows a pose the
## runtime does not have, which stops the controller moving it.
func _follow() -> void:
	pose = &"held" if held_still else &"joints" if bare else &"aim"


func _flick_input() -> void:
	var s := stick()
	if flick != "":
		if s.length() < LET_GO:
			flick = ""
		return
	if s.length() <= PUSH:
		return
	for way in FLICKS:
		if s.dot(FLICKS[way]) >= s.length() * cos(PI / 4):
			flick = way


## The interaction profile the runtime bound this hand to, logged with the wheel's input on each change, so a
## device's log shows which of its controls the controls table landed on.
func _log_profile() -> void:
	var t := XRServer.get_tracker(tracker) as XRPositionalTracker
	var bound := t.profile if t != null else ""
	if bound != _profile:
		_profile = bound
		print("controls: %s on %s, wheel %s" % [tracker, _profile, Controls.input("wheel", tracker)])


## Hold the wheel button and the wheel opens where the hand is, facing the head; sweep the hand
## onto a tool, or onto a subtree and on into it; let go to take the tool the hand is on, or, on none, to hold nothing.
func _select_input(delta: float) -> void:
	if carried != null:
		return
	if _wheel == null:
		if _warming > 0:
			_warm()
		if not _buttons.pressed("wheel"):
			_since_prepared += delta
			if _since_prepared >= PREPARE_EVERY:
				_since_prepared = 0.0
				_prepare_icons(1)
			return
		if _warming > 0:
			_warming = 1
			_warm()
		_wheel = ToolWheel.new(inventory())
		Metrics.note("wheel: %s opened" % tracker)
		picking = true
		var cam := get_viewport().get_camera_3d()
		var head := cam.global_position if cam != null else global_position + global_basis.z
		var forward := -cam.global_basis.z if cam != null else -global_basis.z
		_wheel_root.global_transform = Transform3D(ToolWheel.facing(global_position, head, forward), global_position)
		_wheel_root.visible = true
		Cues.play(Cues.Act.WHEEL_OPEN, global_position, self)
	var p: Vector2 = injected_reach.get(tracker, Vector2.INF)
	if p == Vector2.INF:
		var local := _wheel_root.global_transform.affine_inverse() * global_position
		p = Vector2(local.x, local.y)
	var was: Array = [_wheel.levels.size(), _wheel.levels[-1].hot]
	_wheel.move(p)
	if _wheel.levels[-1].hot >= 0 and [_wheel.levels.size(), _wheel.levels[-1].hot] != was:
		Cues.play(Cues.Act.WHEEL_HOVER, global_position, self)
	_show_wheel(delta)
	if _buttons.released("wheel"):
		var pick: Variant = _wheel.chosen()
		if pick is String and people != null:
			people.activate(pick)
		else:
			tool = pick if pick != null else Tool.NONE
		Cues.play(Cues.Act.WHEEL_PICK, global_position, self)
		close_wheel()


## Hot icons grow; inside a subtree only the subtrees opened on the way to it and its items stay.
func _show_wheel(delta: float) -> void:
	var levels := _wheel.levels
	if _drawn_levels != levels.size():
		_clear_icons()
		var prefix: Array[int] = []
		for l in levels.size():
			if l < levels.size() - 2:
				prefix.append(levels[l].hot)
				continue
			var level: Dictionary = levels[l]
			var items: Array = level.items.duplicate()
			if l < levels.size() - 1:
				for j in items.size():
					if j != level.hot:
						items[j] = null
			_build_icons(items, level.centre, level.dirs, prefix)
			prefix.append(level.hot)
		_drawn_levels = levels.size()
	var k := 1.0 - exp(-delta * 20.0)
	var opened: Array[int] = []
	for l in levels.size() - 1:
		opened.append(levels[l].hot)
	for e in _icons:
		var path: Array[int] = e.path
		var node: Node3D = e.node
		var target := 0.0
		if path.size() == levels.size() and path.slice(0, -1) == opened:
			target = HOT if levels[-1].hot == path[-1] else IDLE
		elif path.size() < levels.size() and path == opened.slice(0, path.size()):
			target = IDLE
		node.scale = node.scale.lerp(Vector3.ONE * target, k)
		# Shrunk to nothing, an icon would still run its vertices.
		node.visible = target > 0.0 or node.scale.x > 0.01
		if not node.visible:
			node.scale = Vector3.ZERO


func _show_tool(delta: float) -> void:
	if tool != _shown:
		if _leaving >= 0:
			_models[_leaving].visible = false
		_leaving = _shown
		_shown = tool
		_pop_t = 0.0
		_models[_shown].visible = true
		_controller.visible = tool == Tool.NONE
		_sight.position = CONTROLLER_TIP if tool == Tool.NONE else TOP + ToolModels.tip(tool) * HELD.get(tool, 1.0)
	if _pop_t >= POP:
		return
	_pop_t = minf(_pop_t + delta, POP)
	var out := clampf(_pop_t / (POP * 0.4), 0.0, 1.0)
	if _leaving >= 0:
		_models[_leaving].scale = Vector3.ONE * (1.0 - out) * HELD.get(_leaving, 1.0)
		if out >= 1.0:
			_models[_leaving].visible = false
			_leaving = -1
	var k := clampf((_pop_t - POP * 0.3) / (POP * 0.7), 0.0, 1.0)
	var overshoot := 1.0 + 2.2 * pow(k - 1.0, 3) + 1.2 * pow(k - 1.0, 2)
	_models[_shown].scale = Vector3.ONE * overshoot * HELD.get(_shown, 1.0)
