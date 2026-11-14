class_name Driver
extends Node

## Plays a JSON list of steps through the same entry points the controllers use.

signal finished

const SETTLED_S := 1.0
const SETTLE_MAX_S := 5.0
## Flow texel-steps a frame while `painting` replays: a thousand times Budget.PAINT_STEPS, under a second on a Quest 2.
const SETUP_STEPS := 3.0e8
const LAYERS := ["terrain", "grass", "flowers", "trees", "mountains", "sky", "stars", "sun_disc", "sun", "shadows", "masonry", "ivy", "moss", "boulders", "camera_previews", "ambient", "fog", "post", "msaa", "water", "hands", "self", "ceilings", "underfoot", "eyes", "flames", "halos", "smoke", "wildlife", "shy", "interior"]

var main: Main
var steps: Array
var _capped := false
var _eye := Vector3.ZERO
var _at := Vector3.FORWARD
var failed := false
var _waiting := {}
var _hidden := {}
## The share of their area the builds a `sized` step lays take.
var _area := 1.0
var _stood: Array[Avatar] = []
var _figures_read: Array[PackedScene] = []
var _figure_path := ""
var _files := true
var _figure_springs := true
var _figure_expressions := true
var _still := false
var _particles := false
var _posing := false
var _posed_usec := 0
var _posed_frames := 0
var _flora_units := {}
var _stood_beasts: Array[Beast] = []
## Left to the controllers, an unworn headset's idle hands put the book and the beam in view or out of it from
## run to run, about 2 ms of a Quest 2's GPU time.
const HELD := [{"hand": "left", "at": [-0.06, -0.3, -0.34], "aim": [0.15, -0.55, -1.0]}, {"hand": "right", "at": [0.3, -0.55, -0.15], "aim": [0, -1, -0.3]}]
## A quarter hour, as a share of a day.
const SUN_MISS := 1.0 / 96.0
## Right-hand spots in head space, the left mirrored: the grip takes whatever box holds the hand, whichever way it aims.
const SKY_SPOTS := [Vector3(0.18, -0.25, -0.3), Vector3(0.18, 0.1, -0.2), Vector3(0.0, 0.3, 0.0), Vector3(0.45, -0.1, 0.0)]
## Radians off the sun's arc, nearest first.
const SKY_OFF_ARC := [0.25, -0.25, 0.6, -0.6, 1.0, -1.0]
const SKY_AIMS := 12


func _init(owner: Main, script: Array) -> void:
	main = owner
	steps = script


static func read(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Array, "script %s is not a JSON array" % path)
	return parsed


func _ready() -> void:
	main.world.capped.connect(_on_capped)
	_run()


func _on_capped(_hand: XRController3D) -> void:
	_capped = true


## The steps before it must fit the frame budget; those after it may build until the budget stops them.
func _all_fit(_s: Dictionary) -> void:
	await _until({"answered": true})
	if _capped:
		_fail("the frame budget turned down a step before all_fit")


func _run() -> void:
	for step: Dictionary in steps:
		for s: Dictionary in [step] + step.get("build", []):
			if not has_method("_" + s.op):
				_fail("no op %s" % s.op)
	await _drawing()
	if main.get_viewport().use_xr:
		for s in HELD:
			await _hold_pose(s)
	for step in steps:
		if failed:
			break
		await _standing()
		print("driver: ", step)
		if step.get("background", false):
			call("_" + step.op, step)
		else:
			await call("_" + step.op, step)
	if not failed:
		await _standing()
	print("driver: failed" if failed else "driver: done")
	finished.emit()


## The steps after a failed one would run on a garden it did not make, so none run.
func _fail(why: String) -> void:
	push_error("driver: " + why)
	failed = true


func _exit_tree() -> void:
	if not _waiting.is_empty():
		push_error("driver: until %s timed out" % _waiting)


## A headset runs the main loop for seconds before its session draws a frame, and the frame it starts in carries
## that whole wait as its delta, which would end the first timer at once.
func _drawing() -> void:
	if not main.get_viewport().use_xr:
		return
	while main.xr.get_session_state() not in [OpenXRInterface.SESSION_STATE_SYNCHRONIZED, OpenXRInterface.SESSION_STATE_VISIBLE, OpenXRInterface.SESSION_STATE_FOCUSED]:
		await get_tree().process_frame
	await get_tree().process_frame
	while get_process_delta_time() > 0.25:
		await get_tree().process_frame


func _standing() -> void:
	while main.world.stairs.laying() or main.tool.walls.any(func(w: Wall) -> bool: return w.laying()):
		await get_tree().process_frame


func _wait(s: Dictionary) -> void:
	await get_tree().create_timer(s.seconds, true, false, true).timeout


func _press(s: Dictionary) -> void:
	var control: String = s.button
	var device: String = s.get("device", "frame")
	hold(device, control, true)
	await get_tree().create_timer(s.get("seconds", 0.1)).timeout
	hold(device, control, false)
	await _frames(2)


static func hold(device: String, control: String, on: bool) -> void:
	var to: Array = Controls.DEVICES[device][control]
	if Hand.FLICKS.has(to[1]):
		if on:
			Hand.injected_sticks[to[0]] = Hand.FLICKS[to[1]]
		else:
			Hand.injected_sticks.erase(to[0])
	elif on:
		Buttons.injected["%s/%s" % to] = true
	else:
		Buttons.injected.erase("%s/%s" % to)


func _pick(s: Dictionary) -> void:
	if s.get("bare", false):
		await _pick_bare(s)
		return
	var hand: Hand = _hand(s)
	var key := Controls.key("wheel", hand.tracker)
	var tree := hand.inventory()
	var leaf: Variant = _tool(s)
	if s.has("action"):
		leaf = SessionWheel.LEAVES.filter(func(l: String) -> bool: return hand.people.choices(l).has(s.action)).front()
	var path: Array[int] = ToolWheel.paths(tree).get(leaf, [] as Array[int])
	var start := hand.global_position
	var reach := func(p: Vector2) -> void:
		Hand.injected_reach[hand.tracker] = p
	# Setting the player down, dressing, or refitting after a change of avatar closes the wheel.
	while main.rig._pending != null or main.session.dressing() or absf(main.rig.fit() / main.rig.world_scale - 1.0) > Rig.REFIT:
		await get_tree().process_frame
	Buttons.injected[key] = true
	await _frames(3)
	if s.has("capture"):
		await _frames(6)
		await main.capture("%s-0" % s.capture)
	var from := Vector2.ZERO
	var level := 0
	for to in ToolWheel.sweep(tree, path):
		level += 1
		for f in 6:
			reach.call(from.lerp(to, (f + 1) / 6.0))
			await _frames(1)
		from = to
		if s.has("capture"):
			await _frames(6)
			await main.capture("%s-%d" % [s.capture, level])
	if s.has("action"):
		await _twist_dial(hand, hand.people.choices(leaf).find(s.action))
		if s.has("capture"):
			await _frames(6)
			await main.capture("%s-dial" % s.capture)
	if s.get("seconds", 0.0) > 0.0:
		await get_tree().create_timer(s.seconds).timeout
	Buttons.injected.erase(key)
	await _frames(1)
	if s.has("popping"):
		await main.capture(s.popping)
	await _frames(1)
	Hand.injected_reach.erase(hand.tracker)
	if not hand.get_has_tracking_data():
		hand.global_position = start
	await _frames(2)


## Flat poses the hand every frame, so there the mouse turns the twist.
func _twist_dial(hand: Hand, to: int) -> void:
	var n := hand.dial.choices.size()
	var steps := posmod(to - hand.dial.start, n)
	if steps > n / 2:
		steps -= n
	var from := hand.global_basis
	for f in 12:
		var degrees := steps * Dial.step(n) * (f + 1) / 12.0
		if main.flat != null:
			main.flat._twist = degrees
		else:
			hand.global_basis = Basis(-from.z, deg_to_rad(degrees)) * from
		await _frames(1)
	await _frames(2)


func _pick_bare(s: Dictionary) -> void:
	var hand: Hand = _hand(s)
	var left: bool = hand == main.rig.left
	var head: Transform3D = main.rig.head.global_transform
	var palm := head * Lessons.frame({"at": Vector3(-0.2 if left else 0.2, -0.3, -0.4), "aim": Vector3(0, -0.35, -1), "roll": 0.0})
	var leaf: Variant = _tool(s)
	var path: Array[int] = ToolWheel.paths(hand.inventory()).get(leaf, [] as Array[int])
	Hand.injected_joints[hand.tracker] = HandShape.make(palm, left, "")
	await _frames(2)
	Hand.injected_joints[hand.tracker] = HandShape.make(palm, left, "middle")
	await _frames(3)
	var wheel := hand.wheel_frame()
	var from := Vector2.ZERO
	for to in ToolWheel.sweep(hand.inventory(), path):
		for f in 6:
			var p := from.lerp(to, (f + 1) / 6.0)
			Hand.injected_joints[hand.tracker] = HandShape.make(Transform3D(palm.basis, wheel * Vector3(p.x, p.y, 0)), left, "middle")
			await _frames(1)
		from = to
	Hand.injected_joints[hand.tracker] = HandShape.make(Transform3D(palm.basis, wheel * Vector3(from.x, from.y, 0)), left, "")
	await _frames(2)
	Hand.injected_joints.erase(hand.tracker)
	await _frames(2)


func _hands(s: Dictionary) -> void:
	var head: Transform3D = main.rig.head.global_transform
	for side in ["left", "right"]:
		if not s.has(side):
			continue
		var hand: Hand = _side(side)
		var at: Vector3 = head * Vector3(s[side][0], s[side][1], s[side][2])
		var fwd := -head.basis.z
		var b := Basis.looking_at(fwd, Vector3.UP).rotated(head.basis.x, deg_to_rad(s.get("tip", 35.0)))
		hand.global_transform = Transform3D(b * Basis(Vector3.BACK, deg_to_rad(s.get("roll", 0.0))), at)
		hand.held_still = true
	await get_tree().process_frame


## A key's `toward` replaces its `aim`: [right, up, ahead] metres from the ground under the head, so it meets
## "relative" builds however high the head is.
func _gesture(s: Dictionary) -> void:
	for side in s.get("tools", {}):
		_side(side).tool = Lessons.tool(s.tools[side])
	var head: Transform3D = main.rig.head.global_transform
	var fwd := _ahead()
	var ground := main.world.terrain.ground(head.origin.x, head.origin.z)
	var body := Transform3D(Basis(fwd.cross(Vector3.UP), Vector3.UP, -fwd), ground)
	s = s.duplicate(true)
	for k: Dictionary in s.keys:
		for side in ["left", "right"]:
			if k.has(side) and k[side].has("toward"):
				var at: Vector3 = head * Lessons._v(k[side].at)
				var aim: Vector3 = head.basis.inverse() * (body * Lessons._v(k[side].toward) - at)
				k[side].aim = [aim.x, aim.y, aim.z]
	var shots: Array = s.get("shots", [])
	var t := 0.0
	var bare: bool = s.get("bare", false)
	while t <= s.length:
		for side in Lessons.hands(s):
			var hand: Hand = _side(side)
			if bare:
				Hand.injected_joints[hand.tracker] = Lessons.bare(s, side, head, t)
				continue
			hand.held_still = true
			hand.global_transform = head * Lessons.frame(Lessons.pose(s, side, t))
		for p in (s.press if not bare else []):
			var key := Controls.key(p.action, p.hand + "_hand")
			if Lessons.held(s, p.hand, p.action, t):
				Buttons.injected[key] = true
			else:
				Buttons.injected.erase(key)
		await get_tree().process_frame
		if s.has("capture") and not shots.is_empty() and t >= shots[0]:
			await main.capture("%s-%d" % [s.capture, s.shots.size() - shots.size()])
			shots = shots.slice(1)
		t += get_process_delta_time()
	for p in s.press:
		Buttons.injected.erase(Controls.key(p.action, p.hand + "_hand"))
	if bare:
		for side in Lessons.hands(s):
			var tracker := side + "_hand"
			Hand.injected_joints[tracker] = HandShape.make(Hand.injected_joints[tracker][HandShape.PALM], side == "left", "")
		await _frames(1)
		Hand.injected_joints.clear()
	await _frames(2)


## As an unworn headset lying tilted would not, so a scripted view sees what a standing player would. It reads the
## head as tracked now, so a script waits for tracking to start before it.
func _level(_s: Dictionary) -> void:
	var head: Transform3D = main.rig.head.global_transform
	var ahead := -head.basis.z
	var flat := Vector3(ahead.x, 0.0, ahead.z)
	if flat.length() < 0.01:
		flat = head.basis.y if ahead.y < 0.0 else -head.basis.y
		flat.y = 0.0
	var turn := Basis.looking_at(flat.normalized(), Vector3.UP) * head.basis.orthonormalized().inverse()
	main.rig.global_transform = Transform3D(turn, head.origin - turn * head.origin) * main.rig.global_transform
	await _frames(2)


func _point(s: Dictionary) -> void:
	var hand := _holding(s, Hand.Tool[s.tool.to_upper()])
	var head: Transform3D = main.rig.head.global_transform
	var beside := Vector3(0.18 if s.get("hand", "right") == "right" else -0.18, -0.25, -0.3)
	var from := head * (Lessons._v(s.from) if s.has("from") else beside)
	var at := Lessons._v(s.at)
	hand.global_transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)
	hand.held_still = true
	await _frames(2)


func _frames(n: int) -> void:
	for f in n:
		await get_tree().process_frame


func _tick() -> float:
	await get_tree().process_frame
	return get_process_delta_time()


func _shot(s: Dictionary) -> void:
	if s.has("capture"):
		await main.capture(s.capture)


func _over(s: Dictionary, default: float, step: Callable) -> void:
	var seconds: float = s.get("seconds", default)
	var t := 0.0
	while true:
		var dt := await _tick()
		t += dt
		if seconds - t < dt * 0.5:
			await step.call(1.0)
			return
		await step.call(t / seconds)


func _hand(s: Dictionary, side := "right") -> Hand:
	return _side(s.get("hand", side))


static func _tool(s: Dictionary) -> Hand.Tool:
	return Lessons.tool(s.get("tool", "none"))


func _side(side: String) -> Hand:
	if side not in ["left", "right"]:
		_fail("no hand %s" % side)
	return main.rig.left if side == "left" else main.rig.right


func _holding(s: Dictionary, tool: Hand.Tool) -> Hand:
	var hand := _hand(s)
	hand.tool = tool
	return hand


func _place(s: Dictionary) -> void:
	main.rig.place(_spot(s, s.x, s.z), s.get("lift", 0.0))


func _teleport(s: Dictionary) -> void:
	main.rig.teleport(_spot(s, s.x, s.z), s.get("lift", 0.0))
	await get_tree().create_timer(s.get("seconds", 2.0)).timeout


func _gaze(s: Dictionary) -> void:
	var gaze: Gaze = main.rig.gaze
	gaze.show_marker(s.get("on", true))
	var t := 0.0
	while t < s.get("seconds", 0.0):
		print("gaze: tracked ", gaze.get_has_tracking_data(), " ", gaze.global_transform)
		await get_tree().create_timer(0.5).timeout
		t += 0.5


static func aim_pose(head: Transform3D, dir: Array) -> Transform3D:
	var along: Vector3 = head.basis * Lessons._v(dir)
	return Transform3D(Basis.looking_at(along, Vector3.UP), head * Vector3(-0.2, -0.35, -0.25))


func _aim(s: Dictionary) -> void:
	var rig: Rig = main.rig
	rig.left.global_transform = aim_pose(rig.head.global_transform, s.dir)
	Hand.injected_sticks[rig.left.tracker] = Vector2(0, 1)
	while rig.aim_hand == null:
		await get_tree().process_frame
	Hand.injected_sticks[rig.left.tracker] = Vector2(0, s.get("stick", 1.0))
	await get_tree().create_timer(s.get("seconds", 1.0)).timeout
	if s.has("watch"):
		await _view(s.watch)
	await _shot(s)
	Hand.injected_sticks.erase(rig.left.tracker)
	await get_tree().create_timer(s.get("settle", 2.0)).timeout


func _wall(s: Dictionary) -> void:
	_lay_materials(s)
	await _stroke(s, Hand.Tool.WALLS)


func _lay_materials(s: Dictionary) -> void:
	var finish := WallLayout.Finish[String(s.get("finish", "bare")).to_upper()] as WallLayout.Finish
	main.tool.finish = finish
	main.tool.wear = s.get("wear", 0.0)
	main.tool.fence_finish = finish if WallLayout.suits(finish, true) else WallLayout.Finish.BARE
	main.tool.planks = s.get("planks", false)
	main.tool.foundation = WallLayout.Foundation[String(s.get("foundation", "pillars")).to_upper()]


func _fence(s: Dictionary) -> void:
	_lay_materials(s)
	await _stroke(s, Hand.Tool.FENCE)


func _stroke(s: Dictionary, held: Hand.Tool) -> void:
	var tool: WallTool = main.tool
	var m := tool.mason(_holding(s, held))
	var path := _path(s)
	var first := _target(s, path[0])
	tool.begin_stroke(m, first.point, first.on)
	var shot := [s.has("capture")]
	await _over(s, 2.0, func(k: float) -> void:
		tool.extend_stroke(m, _along(path, k))
		if shot[0] and k >= s.get("capture_at", 0.6):
			shot[0] = false
			await main.capture(s.capture))
	tool.end_stroke(m)


func _house(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var round: bool = s.get("round", false)
	_holding(s, Hand.Tool.TOWER if round else Hand.Tool.HOUSE)
	_lay_materials(s)
	var x: float = s.at[0]
	var z: float = s.at[1]
	var at := WallTool.stance(_spot(s, x, z), _turn(s, x, z, s.get("turn", 0.0)), round)
	if s.has("size"):
		at.size = Vector2(s.size[0], s.size[1])
		at.pitch = WallTool.pitch_for(at)
	at.rise = snappedf(s.get("rise", 0.0), WallLayout.COURSE)
	var carried := s.has("from") or s.has("turn_from") or s.has("capture")
	var put := at.duplicate()
	if carried:
		var from: Array = s.get("from", s.at)
		put.center = _spot(s, from[0], from[1])
		put.yaw = _turn(s, from[0], from[1], s.get("turn_from", s.get("turn", 0.0)))
		put.rise = 0.0
	var on: int = _target(s, put.center).on
	_lay_gables(s)
	var count := tool.walls.size()
	var house := tool.new_house(put, PackedInt32Array([on]) if on >= 0 else PackedInt32Array())
	if s.has("seed"):
		house.layout.seed = int(s.seed)
		house.roof.seed = int(s.seed)
	if s.has("windows") and not round:
		_open_windows(house, int(s.windows), on < 0)
	tool.build([house])
	if not carried:
		await get_tree().create_timer(s.get("seconds", 0.0)).timeout
		return
	for f in 600:
		if tool.walls.size() > count:
			break
		await get_tree().process_frame
	if tool.walls.size() == count:
		_fail("the house put up at %s never stood" % put.center)
		return
	tool.take_build(tool.walls[-1])
	var start: Dictionary = tool.held_at.duplicate()
	var shots: int = s.get("shots", 3) if s.has("capture") else 0
	var taken := [0]
	await _over(s, 2.0, func(k: float) -> void:
		var to := start.duplicate()
		to.center = start.center.lerp(at.center, k)
		to.yaw = lerp_angle(start.yaw, at.yaw, k)
		to.rise = snappedf(at.rise * k, WallLayout.COURSE)
		tool.stand_build(to)
		while taken[0] < shots and k >= float(taken[0] + 1) / shots:
			taken[0] += 1
			await get_tree().create_timer(0.4).timeout
			await main.capture("%s-%d" % [s.capture, taken[0]]))
	if tool.held != null:
		tool.end_build()


## `size` is [along its ridge, across it], a tower's `size[0]` across.
func _resize(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	tool.take_build(_wall_of(s))
	var start: Dictionary = tool.held_at.duplicate()
	var end := start.duplicate()
	var move: Array = s.get("move", [0, 0])
	end.center = start.center + Vector3(move[0], 0.0, move[1])
	end.yaw = start.yaw + deg_to_rad(s.get("turn", 0.0))
	if s.has("size"):
		end.size = Vector2(s.size[0], s.size[0] if start.round else s.size[1])
	var keys := ["rise", "height"].filter(func(k: String) -> bool: return start.has(k))
	for k: String in keys:
		end[k] = s.get(k, start[k])
	await _over(s, 1.0, func(k: float) -> void:
		var to := start.duplicate()
		to.center = start.center.lerp(end.center, k)
		to.yaw = lerp_angle(start.yaw, end.yaw, k)
		if start.has("size"):
			to.size = start.size.lerp(end.size, k)
		for key: String in keys:
			to[key] = lerpf(start[key], end[key], k)
		tool.stand_build(to))
	if tool.held != null:
		tool.end_build()


func _turn(s: Dictionary, x: float, z: float, degrees: float) -> float:
	var t := deg_to_rad(degrees)
	return WallTool.angle(_spot(s, x + cos(t), z + sin(t)) - _spot(s, x, z))


## Each of `hatches` is [metres along the ridge, across it].
func _roof(s: Dictionary) -> void:
	var w := _wall_of(s)
	var r := w.roof
	r.pitch = RoofLayout.snap_pitch(s.get("pitch", r.pitch), WallTool.ROOF_STEP)
	r.curve = clampf(s.get("curve", r.curve), -RoofLayout.CURVE, RoofLayout.CURVE)
	r.overhang = clampf(snappedf(s.get("overhang", r.overhang), WallTool.ROOF_STEP), 0.0, r.reach())
	var roof := {"pitch": r.pitch, "curve": r.curve, "overhang": r.overhang}
	if s.has("deck"):
		roof["deck"] = int(RoofLayout.Deck[s.deck.to_upper()])
	if s.has("hatches"):
		roof["hatches"] = PackedVector2Array(s.hatches.map(func(d: Array) -> Vector2: return Vector2(d[0], d[1])))
	main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"roof": roof}})


## So a phase measures thatch against the same houses tiled.
func _thatch(_s: Dictionary) -> void:
	for id: int in main.world.state.walls:
		if main.world.state.walls[id].has("roof"):
			main.world.submit({"op": "reshape", "of": "walls", "id": id, "data": {"roof": {"thatch": true}}})


func _top(s: Dictionary) -> void:
	var w := _wall_of(s)
	if w.roof == null or w.roof.flat():
		main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"top": int(WallLayout.Top[s.style.to_upper()])}})


func _gable(s: Dictionary) -> void:
	main.world.submit({"op": "reshape", "of": "walls", "id": _wall_of(s).id, "data": {"gable_end": int(WallLayout.GableEnd[s.style.to_upper()])}})


func _lay_gables(s: Dictionary) -> void:
	if s.has("gable"):
		main.tool.gable_end = WallLayout.GableEnd[s.gable.to_upper()]


func _lift_wall(s: Dictionary) -> void:
	main.world.submit({"op": "reshape", "of": "walls", "id": _wall_of(s).id, "data": {"height": float(s.height)}})


func _grip(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var w := _wall_of(s)
	for n in int(s.get("times", 1)):
		var metres: float = s.get("metres", 1.0) * (1.0 if n % 2 == 0 else -1.0)
		tool.take_build(w)
		var start: Dictionary = tool.held_at.duplicate()
		await _over(s, 1.0, func(k: float) -> void:
			var up := metres * smoothstep(0.0, 1.0, k)
			var to := start.duplicate()
			if s.get("roof", false):
				to.pitch = RoofLayout.snap_pitch(start.pitch + up, WallTool.ROOF_STEP)
			else:
				to.height = maxf(start.height + snappedf(up, WallLayout.COURSE), WallLayout.MIN_HEIGHT)
			tool.stand_build(to))
		if tool.held != null:
			tool.end_build()
		await _standing()


func _grow(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var flora: Flora = main.flora_tool.flora
	var trunk := _trunk(s)
	var at := trunk.foot() + Vector3.UP * flora.top_of(trunk) * 0.8
	var mid: Vector3 = at + Vector3.BACK * 2.0
	var right := tool.mason(main.rig.right)
	var left := tool.mason(main.rig.left)
	for m: WallTool.Mason in [right, left]:
		m.hand.global_position = mid + Vector3.RIGHT * (1.0 if m == right else -1.0)
		tool.begin_grow(m, trunk, m.hand.global_transform, at)
	await _over(s, 1.0, func(k: float) -> void:
		var half: float = 1.0 + s.metres * 0.5 * smoothstep(0.0, 1.0, k)
		tool.drag_pair(left, mid + Vector3.RIGHT * half, mid + Vector3.LEFT * half))
	await _shot(s)
	tool.end_grow(left)
	tool.end_grow(right)


func _trunk(s: Dictionary) -> Flora.Plant:
	var flora: Flora = main.flora_tool.flora
	if s.has("tree"):
		return flora.groups[0][flora.meadow_trees[s.tree]]
	var trunk: Flora.Plant
	var spot := Vector3(s.x, 0.0, s.z)
	for parts in flora.solids():
		var p: Flora.Plant = parts[0]
		if p.pool == flora.trunks and (trunk == null or Vector3(p.anchor.x, 0, p.anchor.z).distance_to(spot) < Vector3(trunk.anchor.x, 0, trunk.anchor.z).distance_to(spot)):
			trunk = p
	return trunk


func _carry(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var m := tool.mason(_hand(s))
	var from: Transform3D
	if s.has("x"):
		var trunk := _trunk(s)
		var at := trunk.foot() + Vector3.UP * 1.2
		from = Transform3D(Basis(), at + Vector3.BACK * 1.5)
		tool.begin_grow(m, trunk, from, at)
	else:
		var ids: Array = main.world.state.boulders.keys()
		var b: Boulders.Boulder = main.boulders.find(ids[ids.size() - 1 - int(s.get("boulder", 0))])
		from = Transform3D(Basis(), b.position + Vector3.BACK * (b.shape.reach() * b.size + 1.5))
		var rock: Dictionary = main.boulders.pick(from.origin, -from.basis.z)
		tool.begin_grow(m, b, from, rock.get("point", b.position))
	var move: Array = s.get("move", [0, 0, 0])
	var turn: Array = s.get("turn", [0, 0, 0])
	await _over(s, 1.0, func(done: float) -> void:
		var k := smoothstep(0.0, 1.0, done)
		var basis := Basis.from_euler(Vector3(deg_to_rad(turn[0]), deg_to_rad(turn[1]), deg_to_rad(turn[2])) * k)
		m.sizing.follow.call(m, Transform3D(basis, from.origin + Lessons._v(move) * k)))
	await _shot(s)
	tool.end_grow(m)


func _clutter(s: Dictionary) -> void:
	var target := _clutter_target(s)
	if target.is_empty():
		_fail("clutter: no piece %s" % s)
		return
	var tool: WallTool = main.tool
	var at: Vector3 = target.bounds.get_center()
	target.point = at
	if s.get("take", false):
		main.fitting_tool.fit(target)
		return
	var from := Transform3D(Basis(), at + Vector3(0.0, 0.3, 0.3))
	var first := tool.mason(main.rig.right)
	tool.begin_grow(first, tool._fitting_grip(target), from, at)
	var m := first
	if s.get("copy", false):
		m = tool.mason(main.rig.left)
		tool.begin_grow(m, tool._fitting_grip(target), from, at)
	var move: Array = s.get("move", [0, 0, 0])
	var turn := deg_to_rad(float(s.get("turn", 0.0)))
	await _over(s, 1.0, func(done: float) -> void:
		var k := smoothstep(0.0, 1.0, done)
		m.sizing.follow.call(m, Transform3D(Basis(Vector3.UP, turn * k), from.origin + Lessons._v(move) * k)))
	await _shot(s)
	tool.end_grow(m)
	if m != first:
		tool.end_grow(first)


func _clutter_target(s: Dictionary) -> Dictionary:
	var targets: Array[Dictionary] = []
	if s.has("path"):
		var paths: Paths = main.tool.paths
		paths.lay_now()
		var id: int = paths.ids[paths.layouts[s.path]]
		targets.assign(FittingTool.path_targets(paths, main.world.terrain.height_at).filter(func(t: Dictionary) -> bool: return t.path == id))
	else:
		var w: Wall = main.tool.walls[s.get("wall", -1)]
		w.lay_now()
		targets.assign(FittingTool.targets(w).filter(func(t: Dictionary) -> bool: return t.what == "clutter"))
	var k: int = s.get("piece", 0)
	return targets[k] if k < targets.size() else {}


func _cluttered(s: Dictionary) -> void:
	var styles := ["Bench", "Rain barrel", "Crates", "Flower box", "Carved pumpkin", "Anvil", "Market stall"].map(DecorationLayout.named)
	var tally := {"pieces": 0, "full": false}
	var k := 0
	for w: Wall in main.tool.walls:
		var d: Dictionary = main.world.state.walls.get(w.id, {})
		if d.is_empty() or d.fence or not d.on.is_empty():
			continue
		w.lay_now()
		var outward := 1.0 if w.layout.inner_side() <= 0.0 else -1.0
		var list := PackedVector4Array(d.clutter)
		var at: float = s.every * 0.5
		while at < w.layout.length() and list.size() < ClutterLayout.MOST:
			var v := Vector4(at, outward * float(s.out), 0.0, styles[k % styles.size()])
			if w.layout.clutter_frame(v, main.world.terrain.height_at) != null:
				list.append(v)
				k += 1
			at += s.every
		var added: int = list.size() - d.clutter.size()
		if added > 0 and _lit({"op": "reshape", "of": "walls", "id": w.id, "data": {"clutter": list}}, tally):
			tally.pieces += added
	print("stress: %d pieces of clutter more, fill %.3f%s" % [tally.pieces, main.world.fill(), ", the budget full" if tally.full else ""])


## What a garden costs without clutter.
func _uncluttered(_s: Dictionary) -> void:
	for of in ["walls", "paths"]:
		for id: int in main.world.state[of]:
			if not main.world.state[of][id].clutter.is_empty():
				main.world.submit({"op": "reshape", "of": of, "id": id, "data": {"clutter": PackedVector4Array()}})


func _arrive(s: Dictionary) -> void:
	var world: World = main.world
	var walls: Array = world.state.walls.values()
	var shift := Vector3(s.offset[0], 0.0, s.offset[1])
	var id: int = world.state.walls.keys().max() + 1
	for d: Dictionary in walls:
		var w := d.duplicate(true)
		var points := PackedVector3Array()
		for p in w.points:
			points.append(p + shift)
		w.points = points
		w.on = PackedInt32Array()
		if w.has("roof"):
			w.roof.center += shift
		var cmd := Commands.clean({"op": "wall", "ids": PackedInt32Array([id]), "walls": [w], "seq": world.seq + 1, "by": 0}, world.state, true, world.terrain)
		assert(not cmd.is_empty(), "arrive: the shifted wall is not a command a visitor would apply")
		world.seq = cmd.seq
		world._timed(cmd)
		id += 1
		await get_tree().create_timer(s.get("every", 0.5)).timeout


static func largest(tool: WallTool) -> Wall:
	var best: Wall
	var area := 0.0
	for w: Wall in tool.walls:
		var at := WallTool.house_of(tool.world.state.walls[w.id])
		var a: float = 0.0 if at.is_empty() or not w.on.is_empty() else at.size.x * at.size.y
		if a > area:
			best = w
			area = a
	return best


func _wall_of(s: Dictionary) -> Wall:
	if s.get("largest", false):
		return largest(main.tool)
	if s.has("at"):
		return main.tool.pick_building(_spot(s, s.at[0], s.at[1]) + Vector3.UP * 2.0, Vector3.DOWN).wall
	return main.tool.walls[s.index]


func _fit(s: Dictionary) -> void:
	if s.what == "decoration":
		var w: Wall = main.tool.walls[s.index] if s.has("index") else null
		var at := w.layout.point_at(float(s.get("s", 0.0))) if w != null else Vector3(float(s.get("x", 0.0)), 0, float(s.get("z", 0.0)))
		var target := {"what": "decoration", "wall": w, "point": at, "s": float(s.get("s", 0.0)), "side": float(s.get("side", 1.0)), "turn": float(s.get("turn", 0.0))}
		if s.has("from"):
			var eye := Lessons._v(s.from)
			target = main.fitting_tool.aim(Hand.Tool.DECORATIONS, eye, (Lessons._v(s.at) - eye).normalized())
			if s.has("turn"):
				target.turn = deg_to_rad(s.turn)
		if s.has("style"):
			target.style = DecorationLayout.named(s.style) if s.style is String else int(s.style)
		target.lantern = int(s.get("lantern", 0))
		main.fitting_tool.fit(target)
		return
	var target := {"what": s.what, "wall": largest(main.tool) if s.get("largest", false) else main.tool.walls[s.index], "s": s.get("s", 0.0), "y": s.get("y", 0.0), "style": s.get("style", WallLayout.Family.COTTAGE), "size": s.get("size", 1.0), "side": s.get("side", 1.0)}
	if s.has("at"):
		target.at = Vector2(s.at[0], s.at[1])
	main.fitting_tool.fit(target)
	if s.has("lantern"):
		main.world.submit({"op": "reshape", "of": "walls", "id": target.wall.id, "data": {"paint": {Palette.Element.LANTERN: int(s.lantern)}}})


func _string(s: Dictionary) -> void:
	var ends: Array[Dictionary] = []
	for end: Array in [s.a, s.b]:
		ends.append({"point": Lessons._v(end)} if end.size() == 3 else {"what": "decoration", "mount": "ground", "point": main.world.terrain.ground(end[0], end[1])})
	var cmd := main.fitting_tool.string_command(ends[0], ends[1], int(s.get("seed", 1)), DecorationLayout.named(s.get("style", "Lantern string")), int(s.get("lantern", 0)))
	if cmd.is_empty():
		print("string: none hangs from %s to %s" % [s.a, s.b])
		return
	main.world.submit(cmd)


func _paint(s: Dictionary) -> void:
	var flora_tool: FloraTool = main.flora_tool
	var b := flora_tool.brush(_hand(s, "left"))
	b.hand.tool = Hand.Tool[s.tool.to_upper()]
	if s.has("tree") and b.hand.tool == Hand.Tool.MOSS:
		var flora := flora_tool.flora
		var trees := flora.placed("tree")
		flora_tool.coat_tree(trees[int(s.tree)][0], b.hand)
		return
	var path := _path(s)
	b.meadow = FloraTool.paints_meadow(b.hand.tool, _along(path, 0.0), main.world.marks)
	await _over(s, 2.0, func(k: float) -> void: flora_tool.paint(b, _along(path, k), s.radius, get_process_delta_time()))
	flora_tool.end_stroke(b)


## `radius` is half the path's width.
func _pave(s: Dictionary) -> void:
	var flora_tool: FloraTool = main.flora_tool
	var b := flora_tool.brush(_hand(s, "left"))
	b.hand.tool = Hand.Tool.PATH
	flora_tool.paths.surface = PathLayout.Surface[String(s.get("surface", "dirt")).to_upper()]
	var path := _path(s)
	var mid := path[0].lerp(path[-1], 0.5)
	for i in path.size():
		path[i] = main.world.terrain.ground(lerpf(mid.x, path[i].x, _area), lerpf(mid.z, path[i].z, _area))
	flora_tool.begin_path(b, path[0], s.radius)
	var shot := [s.has("capture")]
	await _over(s, 2.0, func(k: float) -> void:
		flora_tool.extend_path(_along(path, k), s.radius)
		if shot[0] and k >= s.get("capture_at", 0.5):
			shot[0] = false
			await get_tree().create_timer(0.2).timeout
			await main.capture(s.capture))
	flora_tool.end_path(b)


func _sculpt(s: Dictionary) -> void:
	var tool: GroundGrab = main.ground_grab
	var hand := _hand(s)
	tool.begin(hand, _spot(s, s.x, s.z), s.get("radius", GroundGrab.MIN_RADIUS))
	await _over(s, 1.0, func(k: float) -> void:
		tool.pull(hand, s.lift * smoothstep(0.0, 1.0, k))
		tool.follow(hand, get_process_delta_time()))
	tool.end_stroke(hand)


## Desktop only, where no hand is tracked.
func _touch(s: Dictionary) -> void:
	main.flora_tool.stand_in = _spot(s, s.at[0], s.at[2]) + Vector3.UP * s.at[1]
	await get_tree().create_timer(s.get("seconds", 1.0)).timeout
	await _shot(s)
	main.flora_tool.stand_in = Flora.NO_HAND


func _dig(s: Dictionary) -> void:
	var depth := GroundGrab.dig_depth(s.get("seconds", 1.5))
	var radius := GroundGrab.reach(2.8, depth)
	await _sculpt({"x": s.x, "z": s.z, "lift": -depth, "radius": 2.8, "seconds": 0.3, "relative": s.get("relative", false), "hand": s.get("hand", "right")})
	await get_tree().process_frame
	await _pond({"x": s.x, "z": s.z, "brim": radius, "relative": s.get("relative", false), "hand": s.get("hand", "right")})


## Returns once the fill is sent to the garden, so `World.idle` then means its water is in.
func _pond(s: Dictionary) -> void:
	var at := _spot(s, s.x, s.z)
	if s.has("brim"):
		at.y = Water.brim(main.world.terrain, at.x, at.z, s.brim)
	var hand := _hand(s)
	var was := hand.tool
	main.water_tool.fill(_holding(s, Hand.Tool.POND), at)
	await _frames(2)
	while main.water_tool.pouring():
		await get_tree().process_frame
	hand.tool = was


func _wade(s: Dictionary) -> void:
	var path := _path(s)
	var pond: PondWater = main.water.pond_at(path[0].x, path[0].z)
	assert(pond != null, "wade: no pond at %s" % path[0])
	var y: float = pond.surface_y() + s.get("y", 0.0)
	var t := 0.0
	var seconds: float = s.get("seconds", 2.0)
	while t < seconds:
		var p := _along(path, minf(t / seconds, 1.0))
		main.rig.right.global_position = Vector3(p.x, y, p.z)
		t += await _tick()
	main.rig.right.position = Vector3.ZERO


func _tree(s: Dictionary) -> void:
	main.flora_tool.place("tree", _spot(s, s.x, s.z), null, s.get("seed", randi()))


func _bush(s: Dictionary) -> void:
	main.flora_tool.place("bush", _spot(s, s.x, s.z), null, s.get("seed", randi()))


func _boulder(s: Dictionary) -> void:
	if s.has("style"):
		Ground.style = s.style
	main.flora_tool.place_boulder(_spot(s, s.x, s.z), null, int(s.get("seed", randi())), float(s.get("scale", 1.0)))


func _delete(s: Dictionary) -> void:
	var tool: DeleteTool = main.delete_tool
	tool.press(self, _spot(s, s.x, s.z) + Vector3.UP * s.get("height", 2.0), Vector3.DOWN)
	tool.let_go(self)
	await get_tree().process_frame


## Let go short of DeleteTool.WIPE_HOLD, nothing wipes.
func _wipe(s: Dictionary) -> void:
	var tool: DeleteTool = main.delete_tool
	var d: Array = s.get("dir", [0, 2, -1])
	var t := 0.0
	var shot := not s.has("capture")
	while t < s.seconds:
		var head: Transform3D = main.rig.head.global_transform
		if not tool.charge(self, head * Vector3(0.2, -0.3, -0.3), head.basis * Lessons._v(d), get_process_delta_time()):
			break
		if not shot and t >= s.get("capture_at", 0.0):
			shot = true
			await main.capture(s.capture)
		t += await _tick()
	tool.cancel(self)
	await get_tree().process_frame


## Along a wall it erases, over the ground it mows.
func _erase(s: Dictionary) -> void:
	var tool: DeleteTool = main.delete_tool
	var path := _path(s) if s.has("points") else _stretch(main.tool.walls[s.index].layout, s.from, s.to)
	var up: Vector3 = Vector3.UP * float(s.get("height", 6.0))
	tool.press(self, path[0] + up, Vector3.DOWN)
	var length := 0.0
	for i in path.size() - 1:
		length += path[i].distance_to(path[i + 1])
	var secs: float = s.get("seconds", 0.5)
	var t := 0.0
	for i in path.size() - 1:
		var duration := secs * path[i].distance_to(path[i + 1]) / maxf(length, 0.001)
		while t < duration:
			var point := path[i].lerp(path[i + 1], t / duration)
			point.y = main.world.terrain.height_at(point.x, point.z)
			tool.hold(self, point + up, Vector3.DOWN)
			t += await _tick()
		# A late frame must not skip a turn in the scripted gesture.
		tool.hold(self, path[i + 1] + up, Vector3.DOWN)
		t -= duration
	tool.let_go(self)
	await get_tree().process_frame


static func _stretch(layout: WallLayout, from: float, to: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 9:
		out.append(layout.frame_at(layout.length() * lerpf(from, to, i / 8.0)).point)
	return out


## The rows straddle the centre line, so a viewer at the centre stands between two of them.
func _stress(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var m := tool.mason(_holding(s, Hand.Tool.FENCE if s.get("fence", false) else Hand.Tool.WALLS))
	_lay_materials(s)
	var radius: float = s.radius
	var spacing: float = s.spacing / sqrt(_area)
	var rows: Array[PackedVector2Array] = []
	var length := 0.0
	var z := -(floorf(radius / spacing - 0.5) + 0.5) * spacing
	while z < radius:
		var half := sqrt(radius * radius - z * z)
		if half >= 1.0:
			var row := PackedVector2Array()
			var n := maxi(1, ceili(half))
			for i in n + 1:
				row.append(Vector2(lerpf(-half, half, float(i) / n), z))
			rows.append(row)
			length += row[0].distance_to(row[-1])
		z += spacing
	var start := Time.get_ticks_usec()
	for row in rows:
		tool.begin_stroke(m, main.world.terrain.ground(row[0].x, row[0].y))
		for i in range(1, row.size()):
			tool.extend_stroke(m, main.world.terrain.ground(row[i].x, row[i].y))
		var before := tool.walls.size()
		tool.end_stroke(m)
		for w in tool.walls.slice(before):
			main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"height": float(s.height)}})
			w.ivy_age = INF
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	var stones := 0
	for w in tool.walls:
		stones += w.layout.stones.size()
	print("stress: %d walls, %.0f m, %d stones, laid in %.0f ms" % [tool.walls.size(), length, stones, ms])


func _lanterns(s: Dictionary) -> void:
	var hung := 0
	for w: Wall in main.tool.walls:
		var layout := w.layout
		var after := PackedVector3Array(layout.lanterns)
		var t := 0.5
		while t < layout.length() and after.size() < Commands.MAX_FITTINGS:
			var p := layout.point_at(t)
			if Vector2(p.x, p.z).length() < s.radius and layout.lantern_fits(t, 2.0):
				after.append(Vector3(t, 2.0, 1.0 if hung % 2 == 0 else -1.0))
				hung += 1
			t += s.every
		if after.size() > layout.lanterns.size():
			main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"lanterns": after}})
	print("stress: %d lanterns" % hung)


func _lights(s: Dictionary) -> void:
	var houses: Array = main.tool.walls.filter(func(w: Wall) -> bool: return w.roof != null and w.layout.closed)
	var looks := Palette.count(Palette.Element.LANTERN)
	var tally := {"strings": 0, "lanterns": 0, "chimneys": 0, "full": false}
	for w: Wall in houses:
		w.lay_now()
		if w.roof.kind != RoofLayout.Kind.GABLE:
			continue
		var stacks := PackedVector2Array(w.roof.chimneys)
		var x: float = -w.roof.ridge_length() * 0.5 + s.every * 0.5
		while x < w.roof.ridge_length() * 0.5 and stacks.size() < Commands.MAX_CHIMNEYS:
			var spot := w.roof.chimney_spot(Vector2(x, 0.0))
			if w.roof.clear_of_dormers(spot) and Array(stacks).all(func(c: Vector2) -> bool: return c.distance_to(spot) > RoofLayout.STACK_WIDTH + 0.3):
				stacks.append(spot)
			x += s.every
		var hung := stacks.size() - w.roof.chimneys.size()
		if hung > 0 and _lit({"op": "reshape", "of": "walls", "id": w.id, "data": FittingGrip.data("chimneys", FittingGrip.packed("chimneys", Array(stacks)), true)}, tally):
			tally.chimneys += hung
	for i in houses.size():
		var w: Wall = houses[i]
		var layout := w.layout
		var after := PackedVector3Array(layout.lanterns)
		var t := 0.5
		while t < layout.length() and after.size() < Commands.MAX_FITTINGS:
			if layout.lantern_fits(t, 2.0):
				after.append(Vector3(t, 2.0, 1.0 if after.size() % 2 == 0 else -1.0))
			t += s.every
		var hung := after.size() - layout.lanterns.size()
		if _lit({"op": "reshape", "of": "walls", "id": w.id, "data": {"lanterns": after, "paint": {Palette.Element.LANTERN: (i * 7) % looks}}}, tally):
			tally.lanterns += hung
	var corners := houses.map(func(w: Wall) -> PackedVector3Array:
		var out := PackedVector3Array()
		for p in w.layout.points:
			out.append(w.transform * (p + Vector3.UP * w.layout.height))
		return out)
	for i in houses.size():
		for j in range(i + 1, houses.size()):
			var a := _middle(corners[i])
			var b := _middle(corners[j])
			if Vector2(a.x - b.x, a.z - b.z).length() <= s.within:
				_hang({"point": _nearest(corners[i], b)}, {"point": _nearest(corners[j], a)}, (i * 7) % looks, tally)
	var r: float = s.radius
	var row := 0
	while (row + 1) / 2 * s.rows <= r and not tally.full:
		var z: float = (row + 1) / 2 * s.rows * (1 if row % 2 else -1)
		var x := -sqrt(maxf(r * r - z * z, 0.0))
		while x + s.span <= sqrt(maxf(r * r - z * z, 0.0)) and not tally.full:
			var a := main.world.terrain.ground(x, z)
			var b := main.world.terrain.ground(x + s.span, z)
			var clear := func(c: PackedVector3Array) -> bool:
				var mid := _middle(c)
				var at := Vector2(mid.x, mid.z)
				return Geometry2D.get_closest_point_to_segment(at, Vector2(x, z), Vector2(x + s.span, z)).distance_to(at) > Vector2(c[0].x, c[0].z).distance_to(at) + 0.5
			if corners.all(clear):
				_hang({"what": "decoration", "mount": "ground", "point": a}, {"what": "decoration", "mount": "ground", "point": b}, (row * 5) % looks, tally)
			x += s.span
		row += 1
	print("stress: %d smoking chimneys, %d lanterns, %d strings on %d houses, fill %.3f%s" % [tally.chimneys, tally.lanterns, tally.strings, houses.size(), main.world.fill(), ", the budget full" if tally.full else ""])


func _hang(from: Dictionary, to: Dictionary, look: int, tally: Dictionary) -> void:
	var cmd := main.fitting_tool.string_command(from, to, tally.strings + 1, DecorationLayout.named("Flag string" if tally.strings % 2 else "Lantern string"), look)
	if not cmd.is_empty() and _lit(cmd, tally):
		tally.strings += 1


func _lit(cmd: Dictionary, tally: Dictionary) -> bool:
	if tally.full or not Budget.fits(main.world.units, main.world.change_of(cmd)):
		tally.full = true
		return false
	main.world.submit(cmd)
	return true


static func _middle(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in points:
		sum += p
	return sum / points.size()


static func _nearest(points: PackedVector3Array, to: Vector3) -> Vector3:
	var best := points[0]
	for p in points:
		if p.distance_to(to) < best.distance_to(to):
			best = p
	return best


## Flora are not build commands, so the frame budget does not count them; the next units line carries the units
## they would count as, for scripts/costs.py.
func _fill_flora(s: Dictionary) -> void:
	var flora: Flora = main.flora_tool.flora
	var pools: Array = s.get("pools", ["grass", "flowers", "trees", "bushes", "moss"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var at: Array = s.get("at", [0, 0])
	var centre := Vector3(at[0], 0, at[1])
	for i in mini(s.get("count", Flora.PAINTED_GRASS), Flora.PAINTED_GRASS) if "grass" in pools else 0:
		flora.add_grass(_scatter(rng, s.radius, centre), rng)
	for i in mini(s.get("count", Flora.PAINTED_FLOWERS), Flora.PAINTED_FLOWERS) if "flowers" in pools else 0:
		flora.add_flower(_scatter(rng, s.radius, centre), rng)
	for i in mini(s.get("count", Flora.PAINTED_MOSS), Flora.PAINTED_MOSS) if "moss" in pools else 0:
		flora.add_moss(_scatter(rng, s.radius, centre), rng)
	for i in mini(s.get("count", Flora.PLACED_TREES), Flora.PLACED_TREES) if "trees" in pools else 0:
		var species := i % FloraLayout.Species.size()
		var parts := flora.add_tree(_scatter(rng, s.radius, centre), rng.randi(), species)
		if not parts.is_empty():
			flora.set_look(parts[0], species, clampf(s.get("scale", 1.0), FloraLayout.SCALES.x, FloraLayout.SCALES.y))
	for i in mini(s.get("count", Flora.PLACED_BUSHES), Flora.PLACED_BUSHES) if "bushes" in pools else 0:
		flora.add_bush(_scatter(rng, s.radius, centre), rng)
	_flora_units = {}
	for pool: String in pools:
		var fill: Array = {"grass": ["grass", Flora.PAINTED_GRASS], "flowers": ["flower", Flora.PAINTED_FLOWERS], "moss": ["moss", Flora.PAINTED_MOSS], "trees": ["tree", Flora.PLACED_TREES], "bushes": ["bush", Flora.PLACED_BUSHES]}[pool]
		_flora_units[fill[0]] = mini(s.get("count", fill[1]), fill[1])


func _flora_far(s: Dictionary) -> void:
	var flora: Flora = main.flora_tool.flora
	var on: bool = s.get("mode", "on") != "off"
	for pool: Flora.Pool in [flora.flowers, flora.ghost_flowers]:
		pool.far_live.visible = on
	for mat in flora.ground_mats:
		mat.set_shader_parameter(&"far_grass", on)

## Trees count their bushes, which share their crowns' material; the ground paints its grass either way.
func _layer(s: Dictionary) -> void:
	var on: bool = s.get("mode", "on") != "off"
	for name: String in LAYERS if s.name == "all" else [s.name]:
		for off: Array in _layer_parts(name):
			var key := "%d.%s" % [off[0].get_instance_id(), off[1]]
			if on and _hidden.has(key):
				off[0].set(off[1], _hidden[key])
				_hidden.erase(key)
			elif not on and not _hidden.has(key):
				_hidden[key] = off[0].get(off[1])
				off[0].set(off[1], off[2])


func _layer_parts(name: String) -> Array[Array]:
	var flora: Flora = main.flora_tool.flora
	var look: Look = main.look
	var out: Array[Array] = []
	var materials: Array[Material] = []
	match name:
		"terrain":
			materials.assign(flora.ground_mats)
		"grass":
			materials = [flora.grass_mat]
		"flowers":
			materials = [flora.flower_mat, flora.flower_far]
		"trees":
			materials = [flora.trunks.material, flora.foliage.material]
		"mountains":
			for n in look.get_children():
				if n is MeshInstance3D and n != look.disc and n != look.moon_disc:
					out.append([n, "visible", false])
		"stars":
			out.append([look.sky_mat, "shader_parameter/stars", 0.0])
		"sky":
			out.append([look.env, "background_mode", Environment.BG_COLOR])
		"sun_disc":
			out.append([look.disc, "visible", false])
			out.append([look.moon_disc, "visible", false])
		"sun":
			out.append([look.sun, "visible", false])
		"shadows":
			for step: Quality.Step in Quality.ladder:
				out.append([step, "shadows", false])
		"masonry":
			out.append([main.tool.masonry, "visible", false])
		"ivy":
			materials = [Wall.kinds()[Wall.Part.IVY].material]
		"moss":
			materials = [flora.moss.material]
		"boulders":
			out.append([main.boulders, "visible", false])
		"camera_previews":
			out.append([main.photo_tool, "process_mode", Node.PROCESS_MODE_DISABLED])
		"fog":
			out.append([look.env, "fog_enabled", false])
		"ambient":
			out.append([look.env, "ambient_light_source", Environment.AMBIENT_SOURCE_DISABLED])
		"post":
			out.append([look.env, "adjustment_enabled", false])
		"msaa":
			out.append([main.get_viewport(), "msaa_3d", Viewport.MSAA_DISABLED])
		"water":
			out.append([main.water, "visible", false])
		"hands":
			for h: Node3D in main.rig.hands:
				out.append([h, "visible", false])
		"self":
			out.append([main.rig.head, "cull_mask", main.rig.head.cull_mask & ~Quality.EYES_LAYER])
		"underfoot":
			for n: Node3D in main.rig._underfoot.get_children():
				out.append([n, "visible", false])
		"eyes":
			out.append([main.hand_stop, "eyes", false])
		"ceilings":
			for n: Node3D in main.get_tree().get_nodes_in_group(&"roof_ceilings"):
				out.append([n, "visible", false])
		"flames":
			materials = [Fittings._flame]
		"halos":
			materials = [Fittings._halo]
		"smoke":
			materials = [Smoke._material]
		"interior":
			out.append([main.look.interior, "masked", false])
		"wildlife":
			out.append([main.wildlife, "visible", false])
			out.append([main.wildlife.fish, "visible", false])
		"shy":
			for kind in main.wildlife.shy():
				out.append([kind, "visible", false])
		_ when name.begins_with("part/"):
			var bits := name.split("/")
			var kind: int = Wall.Part[bits[1].to_upper()]
			var near := bits.size() < 3 or bits[2] == "near"
			var far := bits.size() < 3 or bits[2] == "far"
			for m in main.find_children("*", "Node3D", true, false):
				if m is Masonry:
					for n: GeometryInstance3D in (m as Masonry).parts(kind, near, far):
						out.append([n, "visible", false])
		"wall_meshes":
			for w in main.find_children("*", "Node3D", true, false):
				for n in w.get_children() if w is Wall else []:
					if n is MeshInstance3D:
						out.append([n, "visible", false])
		_:
			assert(false, "layer: no layer %s" % name)
	for n in main.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.material_override == null or g.material_override not in materials:
			continue
		if g is MultiMeshInstance3D:
			out.append([(g as MultiMeshInstance3D).multimesh, "visible_instance_count", 0])
		else:
			out.append([g, "visible", false])
	return out


func _village(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var start := Time.get_ticks_usec()
	var r: float = s.radius * sqrt(_area)
	var step: float = s.spacing
	_lay_gables(s)
	_lay_materials(s)
	main.tool.thatch = s.get("thatch", false)
	var stood := tool.walls.size()
	var k := 0
	var fronts: Array[Dictionary] = []
	for z in range(-int(r / step), int(r / step) + 1):
		for x in range(-int(r / step), int(r / step) + 1):
			var c := Vector2(x, z) * step
			if c.length() > r - step * 0.5 or c.length() < s.get("inner", 0.0) * sqrt(_area):
				continue
			k += 1
			var yaw := PI * 0.5 * (k % 2)
			var at := main.world.terrain.ground(c.x, c.y)
			var on := PackedInt32Array()
			var entry: Dictionary = s.roofs[k % s.roofs.size()] if s.has("roofs") else {}
			var size := Vector2(0.7, 0.44) * step
			for storey in int(entry.get("storeys", s.get("storeys", 1))):
				var round: bool = entry.get("round", false)
				var stance := WallTool.stance(at, yaw, round)
				stance.size = Vector2.ONE * size.y if round else size
				stance.height = WallTool.HOUSE_HEIGHT
				stance.curve = s.get("curve", 0.0)
				stance.rise = entry.get("rise", 0.0) if on.is_empty() else 0.0
				stance.pitch = entry.get("pitch", s.get("pitch", WallTool.pitch_for(stance)))
				var house := tool.new_house(stance, on)
				house.layout.foundation = WallLayout.Foundation[String(entry.get("foundation", "pillars")).to_upper()]
				_dress_roof(house, entry, size)
				if s.get("windows", false) and not round:
					_open_windows(house, k + storey, on.is_empty())
				if not main.world.fits({"op": "wall", "walls": [house.data()]}):
					house.free()
					main.world.cap(null)
					break
				tool.build([house])
				if s.has("doors") and on.is_empty():
					var front := house.layout.points[0].lerp(house.layout.points[1], 0.5)
					fronts.append({"at": front, "out": ((front - at) * Vector3(1, 0, 1)).normalized(), "half": s.doors[k % s.doors.size()]})
				size *= entry.get("upper", 1.0)
				tool.walls[-1].ivy_age = INF
				on = PackedInt32Array([tool.walls[-1].id])
			if s.get("wings", false):
				var wing := at + Vector3.RIGHT.rotated(Vector3.UP, yaw) * step * 0.2
				wing = main.world.terrain.ground(wing.x, wing.z)
				var wing_at := WallTool.stance(wing, yaw)
				wing_at.size = Vector2(0.3, 0.6) * step
				wing_at.curve = s.get("curve", 0.0)
				wing_at.pitch = s.get("pitch", WallTool.pitch_for(wing_at))
				var wing_house := tool.new_house(wing_at)
				if main.world.fits({"op": "wall", "walls": [wing_house.data()]}):
					tool.build([wing_house])
					tool.walls[-1].ivy_age = INF
				else:
					wing_house.free()
					main.world.cap(null)
	for n in fronts.size():
		var f := fronts[n]
		var path := PathLayout.new()
		path.seed = n + 1
		for i in 9:
			var p: Vector3 = f.at + f.out * lerpf(2.2, -1.0, i / 8.0)
			path.add(main.world.terrain.ground(p.x, p.z), f.half)
		main.world.submit(path.data().merged({"op": "path"}))
	print("village: %d buildings in %.0f ms" % [tool.walls.size() - stood, (Time.get_ticks_usec() - start) / 1000.0])


func _open_windows(house: Wall, k: int, ground: bool) -> void:
	var p := house.layout.points
	var front := Vector2(p[1].x - p[0].x, p[1].z - p[0].z).length()
	var end := Vector2(p[2].x - p[1].x, p[2].z - p[1].z).length()
	var family := WallLayout.WINDOW_FAMILIES[k % WallLayout.WINDOW_FAMILIES.size()]
	var y := WallLayout.lowest(family) + 0.15
	var openings := PackedVector4Array()
	if ground:
		openings.append(Vector4(front * 0.5, 0.0, WallLayout.Family.COTTAGE if k % 2 == 0 else WallLayout.Family.ARCHED, 1.0))
	for at in [front * 0.2, front * 0.8, front + end * 0.5, front * 1.5 + end - 0.45, front * 1.5 + end + 0.45, front * 2.0 + end * 1.5]:
		openings.append(Vector4(at, y, family, 1.0))
	openings.append(Vector4(front + end, WallLayout.lowest(WallLayout.Family.CORNER) + 0.15, WallLayout.Family.CORNER, 1.0))
	house.layout.openings.assign(Array(openings))
	if house.roof.flat():
		house.roof.hatches.assign([Vector2.ZERO])


func _dress_roof(house: Wall, entry: Dictionary, size: Vector2) -> void:
	var r := house.roof
	r.deck = RoofLayout.Deck[entry.get("deck", "stone").to_upper()]
	r.overhang = entry.get("overhang", RoofLayout.OVERHANG)
	house.layout.top = WallLayout.Top[entry.get("top", "cap").to_upper()]
	var n := int(entry.get("dormers", 0))
	r.dormers.clear()
	for side in ([-1.0, 1.0] if n > 0 else []):
		for i in n:
			r.dormers.append(Vector2(((i + 0.5) / n - 0.5) * (size.x - 1.2), side * size.y))


func _clear(_s: Dictionary) -> void:
	for w in main.tool.walls.duplicate():
		main.world.submit({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])})
	await get_tree().process_frame


func _scatter(rng: RandomNumberGenerator, radius: float, centre: Vector3) -> Vector3:
	return FloraLayout.brush(centre, radius, 1, rng, main.world.terrain.height_at)[0]


func _host_port(s: Dictionary) -> int:
	return int(s.get("port", main.args.get("host-port", Session.PORT)))


func _join(s: Dictionary) -> void:
	var arrived := _arrival()
	main.session.join(s.get("address", "127.0.0.1"), _host_port(s))
	await _arrived(arrived)


## Connected before the visit, so a step after it works in the garden visited however late it comes.
func _arrival() -> Array:
	var arrived := [false]
	main.world.loaded.connect(func() -> void:
		if main.session.visiting.is_empty():
			_fail("went home instead of arriving")
		else:
			arrived[0] = true, CONNECT_ONE_SHOT)
	return arrived


func _arrived(arrived: Array) -> void:
	while not arrived[0] and not failed:
		await get_tree().process_frame


func _visit(s: Dictionary) -> void:
	var home: bool = s.get("home", false)
	var arrived := [true] if home else _arrival()
	var key := "home"
	if not home:
		var keys: Array = main.session.nearby.keys().filter(func(x: String) -> bool: return x.ends_with(":%d" % _host_port(s)))
		assert(not keys.is_empty(), "the requested garden has not been discovered")
		key = "join:" + str(keys[0])
	await _pick({"action": key})
	assert(not home or main.session.visiting.is_empty(), "driver: the wheel's home left this player visiting")
	await _arrived(arrived)


## At least two frames, so a slow frame cannot swallow the press.
func _flat(s: Dictionary) -> void:
	var action: String = "flat_" + s.action
	Input.action_press(action)
	await _frames(2)
	await get_tree().create_timer(s.get("seconds", 0.1)).timeout
	Input.action_release(action)
	await _frames(2)


## Prices other players' avatars on one headset with no network in the way.
func _figures(s: Dictionary) -> void:
	if not _stood.is_empty():
		print("figures: %d %s avatars %s, %.1f us per avatar pose and %.1f solving its constraints over %d frames" % [_stood.size(), _stood[0].source if _stood[0].source else "built-in", "lying and sitting in turn" if _posing else "standing", float(_posed_usec) / maxi(_posed_frames * _stood.size(), 1), float(Constraints.spent_usec) / maxi(_posed_frames * _stood.size(), 1), _posed_frames])
	for a in _stood:
		a.queue_free()
	_stood.clear()
	_posing = s.get("posture", false)
	_figure_springs = s.get("springs", true)
	_figure_expressions = s.get("expressions", true)
	_still = s.get("still", false)
	_particles = s.get("particles", false)
	_posed_usec = 0
	_posed_frames = 0
	Constraints.spent_usec = 0
	var path: String = s.get("file", "")
	var scene: PackedScene = Avatar.built_in(0)
	_figure_path = path
	_figures_read.clear()
	for i in s.spots.size():
		var at: Array = s.spots[i]
		if path and (s.get("apart", false) or i == 0):
			var result := {}
			main.session._read(PackedByteArray(), path if path.is_absolute_path() else Main.player_path(path), func(_hash: String, _bytes: PackedByteArray, loaded: PackedScene) -> void: result.scene = loaded)
			while not result.has("scene"):
				await get_tree().process_frame
			scene = result.scene
			if scene == null:
				print("figures: %s is past this device's limits, so its figures stand as built-ins, as its player would" % path)
				scene = Avatar.built_in(0)
				_figure_path = ""
		_figures_read.append(scene)
		var foot := main.world.terrain.ground(at[0], at[1])
		# Read after the file is: the step may start drawing files while it reads, and figures stood then are priced once.
		_files = main.quality.files()
		_stood.append(_stand(i, Transform3D(Basis.looking_at(Vector3(-foot.x, 0, -foot.z)), foot)))


func _stand(i: int, at: Transform3D) -> Avatar:
	var a := Avatar.drawn(_figures_read[i], Color.WHITE, _figure_path, _figure_path != "" and main.quality.admit(_figures_read[i]))
	a.transform = at
	a.simulate_springs = _figure_springs and not _still
	if _posing:
		a.ground = func(w: Vector3) -> float: return main.rig.floor_under.call(w)
	if a.particles != null:
		a.particles.unswitched = _particles
	main.add_child(a)
	if a.expressions != null and not (_figure_expressions and not _still):
		a.expressions.process_mode = Node.PROCESS_MODE_DISABLED
	if _still:
		a.stand()
		a.set_process(false)
	return a


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var start := Time.get_ticks_usec()
	if not _stood.is_empty() and main.quality.files() != _files:
		_files = main.quality.files()
		print("driver: figures stood again, %s, %.1f us per avatar pose before over %d frames" % ["each in its file where the headroom takes it" if _files else "as built-in bodies", float(_posed_usec) / maxi(_posed_frames * _stood.size(), 1), _posed_frames])
		_posed_usec = 0
		_posed_frames = 0
		for i in _stood.size():
			var was := _stood[i]
			_stood[i] = _stand(i, was.transform)
			was.queue_free()
	if _still:
		return
	for i in _stood.size():
		var eyes := Transform3D(Basis.IDENTITY, Vector3(0, _stood[i].eye_height, 0))
		if _posing:
			var held := Posture.held(1 + (int(t / 1.2) + i) % (Posture.poses.size() - 1), _stood[i].eye_height)
			_stood[i].pose(held[0], held[1], held[2])
		else:
			var sway := 0.1 * sin(t * 2.0 + i)
			_stood[i].pose(eyes, eyes * Avatar.AT_SIDES[0].translated(Vector3(0, sway, -0.3)), eyes * Avatar.AT_SIDES[1].translated(Vector3(0, -sway, -0.3)))
	if not _stood.is_empty():
		_posed_usec += Time.get_ticks_usec() - start
		_posed_frames += 1


func _face(s: Dictionary) -> void:
	var to: Vector3
	if s.get("player", false):
		to = (main.session.avatars.values()[0] as Avatar).eyes.origin
	else:
		to = Lessons._v(s.at)
	main.view(main.rig.head.global_position, to)
	await _frames(2)


## A flock comes to a dish on its own only a minute or two after the ducks, so `fed` brings one near. Without
## `seconds` the wait has no limit: how long another player takes to start and catch up is the machine's load.
func _until(s: Dictionary) -> void:
	var dir := str(main.args.get("capture-dir", "user://captures"))
	var t := 0.0
	_waiting = s
	while t < s.get("seconds", INF):
		var w: World = main.world
		var worn: int = main.session.avatars.values().filter(func(a: Avatar) -> bool: return a.source != "").size()
		var digested: bool = s.get("digests", []).all(func(n: String) -> bool: return FileAccess.file_exists(dir.path_join(n + ".json")))
		var selected: bool = not s.has("avatar") or (main.session.avatar == s.avatar and worn == 0 and main.session._looks.values().all(func(v: Array) -> bool: return v[0] == int(s.avatar)))
		var files_ready: bool = s.get("files", []).all(func(f: String) -> bool: return main.session.files.get(f, {}).get("scene") != null)
		var wearing: bool = not s.has("wearing") or (main.session.worn_key != "" and main.session.worn_key == main.session.files.get(s.wearing, {}).get("key", ""))
		var digested_seq := _digested_seq(dir.path_join(s.seq_of + ".json")) if s.has("seq_of") else 0
		var answered: bool = not s.get("answered", false) or w.answered()
		if files_ready and wearing and selected and digested_seq >= 0 and w.seq >= digested_seq and answered and w.seq >= s.get("seq", 0) and main.session.players() >= s.get("players", 0) and worn >= s.get("worn", 0) and main.session.previews.values().filter(func(p: PackedScene) -> bool: return p != null).size() >= s.get("previewed", 0) and main.wildlife.fish.swimming.size() >= s.get("swimming", 0) and (not s.has("fed") or main.wildlife.feeding(s.fed == "dish") > 0) and (not s.get("frenzy", false) or _frenzied()) and digested and (not s.get("heard", false) or main.session.nearby.keys().any(func(k: String) -> bool: return k.ends_with(":%d" % _host_port(s)))):
			_waiting = {}
			return
		# A flock lands anywhere along its perch, maybe out of sight of the seeds, so one already full is left to come over.
		if s.has("fed") and main.wildlife.birds.birds.size() < Birds.CAP:
			for o in main.wildlife.offers():
				if o is Dish if s.fed == "dish" else o is Hand:
					_flock_near(o.global_position, Birds.appetite.notice)
		t += await _tick()
	_waiting = {}
	_fail("until %s timed out" % s)


## -1 while the digest has not been written whole.
static func _digested_seq(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return int(d.seq) if d is Dictionary and d.has("seq") else -1


func _frenzied() -> bool:
	var f := main.wildlife.fish.frenzy()
	return f[1] > 0 and f[0] == f[1]


func _write_capture(name: String, out: Dictionary) -> String:
	var path: String = main.capture_path(name + ".json")
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(out, " ", true))
	return path


## For comparing machines.
func _digest(s: Dictionary) -> void:
	var out: Dictionary = main.world.digest()
	if s.get("ground", false):
		var h: Vector3 = main.rig.head.global_position
		out.ground = {"feet": main.rig.global_position.y, "terrain": main.world.terrain.height_at(h.x, h.z), "head": h.y, "x": h.x, "z": h.z, "yaw": rad_to_deg(main.rig.global_rotation.y), "held": [Hand.Tool.keys()[main.rig.left.tool], Hand.Tool.keys()[main.rig.right.tool]]}
	out.sun = main.look.time
	out.avatars = main.session.avatars.values().filter(func(a: Avatar) -> bool: return a.visible).size()
	out.avatar_choices = main.session._looks.values().map(func(v: Array) -> int: return v[0])
	out.avatar_choices.append(main.session.avatar)
	out.avatar_choices.sort()
	out.worn = main.session.avatars.values().map(func(a: Avatar) -> String: return a.source).filter(func(k: String) -> bool: return k != "")
	out.postures = main.session.avatars.values().map(func(a: Avatar) -> String: return Posture.poses[a.posture.target].name)
	out.fed = {"hand": main.wildlife.feeding(false), "dish": main.wildlife.feeding(true)}
	out.handfuls = main.feed_tool.handfuls.filter(func(h: Handful) -> bool: return h.landed()).map(func(h: Handful) -> Array: return [h.position.x, h.position.y, h.position.z])
	out.frenzy = main.wildlife.fish.frenzy()
	print("driver: digest ", _write_capture(s.name, out))


## ENet counters exclude discovery and IP/UDP headers; frame times are Godot's main-thread time, not process CPU.
func _network_sample(s: Dictionary) -> void:
	var peer: ENetMultiplayerPeer = multiplayer.multiplayer_peer
	var connection := peer.host
	connection.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	connection.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var start := Time.get_ticks_usec()
	var start_unix := Time.get_unix_time_from_system()
	var frames := 0
	var process_ms := 0.0
	var physics_ms := 0.0
	var players: int = main.session.players()
	while Time.get_ticks_usec() - start < s.get("seconds", 10.0) * 1000000.0:
		await get_tree().process_frame
		assert(main.session.players() == players, "peer left during network sample")
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		frames += 1
	var seconds := (Time.get_ticks_usec() - start) / 1000000.0
	var out := {"name": s.name, "players": players, "seconds": seconds, "frames": frames,
		"start_unix": start_unix, "end_unix": Time.get_unix_time_from_system(),
		"tx_bytes_s": connection.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA) / seconds,
		"rx_bytes_s": connection.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA) / seconds,
		"process_ms_frame": process_ms / frames, "physics_ms_frame": physics_ms / frames}
	print("driver: network sample ", _write_capture(s.name, out))


func _photo(s: Dictionary) -> void:
	var hand := _holding(s, Hand.Tool[str(s.get("tool", "camera")).to_upper()])
	if s.has("view"):
		await main.capture(s.view, false, PhotoTool.lens(hand))
	await main.photo_tool.shoot(hand)


func _video(s: Dictionary) -> void:
	var hand := _holding(s, Hand.Tool[str(s.get("tool", "camera")).to_upper()])
	var key := Controls.key("tool", hand.tracker)
	Buttons.injected[key] = true
	await get_tree().create_timer(s.seconds).timeout
	Buttons.injected.erase(key)
	await main.photo_tool.recorded


func _toss(s: Dictionary) -> void:
	var v := Lessons._v(s.get("velocity", [0, 0, 0]))
	var f: Array = s.get("from", [])
	if f.size() == 3:
		main.feed_tool.throw(Vector3(f[0], f[1] + main.world.terrain.height_at(f[0], f[2]), f[2]), v)
		return
	var hand := _holding(s, Hand.Tool.SEEDS)
	main.feed_tool.throw(main.feed_tool.dish(hand), main.feed_tool.launch(hand, v))


## `time` is a share of the day, 0 midnight and 0.5 noon, reached the short way round.
func _sun(s: Dictionary) -> void:
	var hand := _hand(s)
	var was := hand.global_transform
	var still := hand.held_still
	var axis := Daylight.RISE.cross(Daylight.ARC_UP)
	var turn := wrapf(Daylight.angle(s.time) - Daylight.angle(main.look.time), -PI, PI)
	var open: Variant = _open_sky(hand, axis)
	if open == null:
		_fail("sun: no open sky round the head to grip")
		return
	var pose := open as Transform3D
	var grab := -pose.basis.z
	hand.held_still = true
	hand.global_transform = pose
	var grip := Controls.key("grab", hand.tracker)
	Buttons.injected[grip] = true
	await _frames(2)
	var seconds: float = s.get("seconds", 2.0)
	var t := 0.0
	while t < seconds:
		t += minf(await _tick(), seconds / 8.0)
		hand.global_basis = Basis.looking_at(grab.rotated(axis, turn * smoothstep(0.0, 1.0, minf(t / seconds, 1.0))))
	await _frames(2)
	Buttons.injected.erase(grip)
	await _frames(2)
	hand.global_transform = was
	hand.held_still = still
	var missed := absf(wrapf(main.look.time - s.time, -0.5, 0.5))
	if missed > SUN_MISS:
		_fail("sun turned to %.4f, not %.4f" % [main.look.time, s.time])


func _open_sky(hand: Hand, axis: Vector3) -> Variant:
	var head: Transform3D = main.rig.head.global_transform
	var side := 1.0 if hand == main.rig.right else -1.0
	for spot: Vector3 in SKY_SPOTS:
		var at := head * (spot * Vector3(side, 1, 1))
		for off: float in SKY_OFF_ARC:
			for i in SKY_AIMS:
				var dir := Daylight.toward_sun(0.5).rotated(Daylight.RISE, off).rotated(axis, TAU * i / SKY_AIMS)
				if main.sky_tool.opens(at, dir) and main.tool.grip_hits(at, dir, INF).is_empty():
					return Transform3D(Basis.looking_at(dir), at)
	return null


func _colour(s: Dictionary) -> void:
	var tool: PaletteTool = main.palette_tool
	var element: Palette.Element = Palette.Element[s.element.to_upper()]
	var target := tool.colour_target(element, Vector3.ZERO)
	if s.get("largest", false):
		target = tool.aim(largest(main.tool).roof.center + Vector3.UP * 20.0, Vector3.DOWN)
	elif s.has("at"):
		target = tool.aim(_dial_from(s), _dial_dir(s))
	if target.get("element") != element:
		_fail("colour aimed at %s, not %s" % [target, s.element])
		return
	await _dial(s, _holding(s, Hand.Tool.COLOUR), target, s.swatch)


func _tap(s: Dictionary) -> void:
	var tool: PaletteTool = main.palette_tool
	var hand := _holding(s, Hand.Tool.COLOUR)
	var target := tool.aim(_dial_from(s), _dial_dir(s))
	if target.is_empty():
		tool.tap(hand, "", -1)
	else:
		tool.open(hand, target)
		tool.close(hand)
	await get_tree().process_frame


func _style(s: Dictionary) -> void:
	var tool: PaletteTool = main.palette_tool
	var restyle: PaletteTool.Restyle = PaletteTool.Restyle[s.restyle.to_upper()]
	var target := tool.aim_style(_dial_from(s), _dial_dir(s)) if s.has("at") else {}
	if s.has("index"):
		var w := _wall_of(s)
		target = tool.style_target(restyle, w, w.layout.point_at(w.layout.length() * 0.5) + Vector3.UP * w.layout.height * 0.5)
	if s.has("tree"):
		var crown := _trunk(s).foot() + Vector3.UP * 2.5
		var from := crown + Vector3(0, 1, 6)
		target = tool.aim_style(from, (crown - from).normalized())
	if target.get("restyle") != restyle:
		_fail("style aimed at %s, not %s" % [target, s.restyle])
		return
	await _dial(s, _holding(s, Hand.Tool.STYLE), target, s.pick)


func _dial_from(s: Dictionary) -> Vector3:
	return _spot(s, s.from[0], s.from[2]) + Vector3.UP * s.from[1] if s.has("from") else main.rig.head.global_position


func _dial_dir(s: Dictionary) -> Vector3:
	return (_spot(s, s.at[0], s.at[2]) + Vector3.UP * s.at[1] - _dial_from(s)).normalized()


func _dial(s: Dictionary, hand: Hand, target: Dictionary, to: int) -> void:
	var tool: PaletteTool = main.palette_tool
	tool.open(hand, target)
	var from: int = tool.wheels[hand].dial.start
	var turn := (to - from) * Dial.step(target.count)
	await _over(s, 1.0, func(k: float) -> void: tool.twist(hand, turn * k))
	await _shot(s)
	tool.close(hand)
	await get_tree().process_frame


func _music(s: Dictionary) -> void:
	main.sound.play_from(s.section)


func _view(s: Dictionary) -> void:
	var pose := _pose(s)
	if pose.is_empty():
		return
	var origin: Vector3 = main.rig.head.global_position if s.get("relative", false) else Vector3.ZERO
	_eye = pose[0] + origin
	_at = pose[1] + (Vector3.ZERO if s.has("toward") else origin)
	main.view(_eye, _at)
	# A view is a cut, as a teleport is: no animal takes it for the player moving suddenly.
	main.rig.jumped.emit()
	await get_tree().process_frame


func _glide(s: Dictionary) -> void:
	var pose := _pose(s)
	if pose.is_empty():
		return
	var from: Array[Vector3] = [_eye, _at]
	await _over(s, s.seconds, func(k: float) -> void:
		var eased := smoothstep(0.0, 1.0, k)
		_eye = from[0].lerp(pose[0], eased)
		_at = from[1].lerp(pose[1], eased)
		main.view(_eye, _at))


## With "toward", `at` is offset from the node in that group nearest the eye, so a view can turn to an animal
## that has moved without the eye moving.
func _pose(s: Dictionary) -> Array[Vector3]:
	var eye := Lessons._v(s.eye)
	var at := Lessons._v(s.at)
	if s.has("subject"):
		var found := get_tree().get_nodes_in_group(s.subject)
		if found.is_empty():
			_fail("nothing in %s to view" % s.subject)
			return []
		var frame: Transform3D = found[s.get("index", 0)].global_transform
		if s.get("ground", false):
			frame.origin.y = 0.0
		eye = frame * eye
		at = frame * at
	if s.get("ground", false):
		eye.y += main.world.terrain.height_at(eye.x, eye.z)
		at.y += main.world.terrain.height_at(at.x, at.z)
	if s.has("toward"):
		var found := get_tree().get_nodes_in_group(s.toward)
		if found.is_empty():
			_fail("nothing in %s to look toward" % s.toward)
			return []
		var eye_at: Vector3 = eye + (main.rig.head.global_position if s.get("relative", false) else Vector3.ZERO)
		found.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(eye_at) < b.global_position.distance_to(eye_at))
		at += found[0].global_position
	return [eye, at]


func _walk(s: Dictionary) -> void:
	var from := Lessons._v(s.from)
	var to := Lessons._v(s.to)
	var dir := (to - from).normalized()
	var t := 0.0
	var seconds := float(s.seconds)
	while t < seconds:
		var eye := from.lerp(to, t / seconds)
		var at: Vector3 = eye + dir * float(s.get("ahead", 10.0))
		at.y = float(s.get("look", 0.0)) + main.world.terrain.height_at(at.x, at.z)
		eye.y += main.world.terrain.height_at(eye.x, eye.z)
		main.view(eye, at)
		t += await _tick()


func _easel(s: Dictionary) -> void:
	var at := _spot(s, s.x, s.z)
	var toward := _toward(s)
	main.easel_tool.place(at, Easels.facing(at, toward), _hand(s))
	await _frames(2)


func _mirror(s: Dictionary) -> void:
	if s.get("away", false):
		main.mirror_tool.clear()
	else:
		var at := _spot(s, s.x, s.z)
		main.mirror_tool.stand_at(at, _toward(s))
	await _frames(2)


func _easel_of(s: Dictionary) -> Easels.Easel:
	var ids: Array = main.easels.easels.keys()
	ids.sort()
	return main.easels.find(ids[s.get("easel", -1)])


func _tip_at(hand: Hand, tip: Vector3, along: Vector3, up: Vector3, roll := 0.0) -> void:
	var basis := Basis.looking_at(along, up).rotated(along.normalized(), roll)
	hand.global_transform = Transform3D(basis, tip - basis * ToolModels.BRUSH_TIP) * ToolModels.hold(main.easel_tool.painter(hand).brush).affine_inverse()
	hand.held_still = true


func _take(s: Dictionary) -> void:
	var hand := _hand(s)
	var e := _easel_of(s)
	var at: Vector3
	match s.what:
		"box":
			at = e.palettes[Brushwork.Medium.WATER].global_position
		"palette":
			at = e.palettes[Brushwork.Medium.OIL].global_position
		_:
			var kind: Brushwork.Brush = Brushwork.Brush[s.what.to_upper()]
			at = e.brushes[kind].global_transform * Easels.grip(kind)
	if s.get("preview", false):
		var offset := e.global_basis * Vector3(0, 0.04, 0.07)
		hand.global_transform = Transform3D(Basis.looking_at(-offset), at + offset)
		hand.held_still = true
		await _frames(2)
		return
	hand.global_transform = Transform3D(e.global_basis * Basis(Vector3.RIGHT, -0.6), at)
	await _squeeze(hand)
	await _frames(2)


func _set_down(s: Dictionary) -> void:
	await _squeeze(_hand(s))
	while not main.easel_tool.returning.is_empty():
		await _frames(1)
	await _frames(1)


func _squeeze(hand: Hand) -> void:
	hand.held_still = true
	var key := Controls.key("grab", hand.tracker)
	Buttons.injected[key] = true
	await _frames(2)
	Buttons.injected.erase(key)


func _holds(s: Dictionary) -> void:
	var hand := _hand(s)
	await get_tree().create_timer(Hand.POP * 2.0).timeout
	var p: EaselTool.Painter = main.easel_tool.painter(hand)
	var now := EaselTool.holding(p)
	assert(now == s.what, "driver: %s holds %s, not %s" % [hand.tracker, now, s.what])
	var shown: Array = p.models.keys().filter(func(k: Brushwork.Brush) -> bool: return p.models[k].visible)
	var brush := hand.tool == Hand.Tool.EASEL and p.palette == null
	assert(shown == ([p.brush] if brush else []), "driver: %s holding %s shows brushes %s" % [hand.tracker, now, shown])


func _rests(s: Dictionary) -> void:
	var e := _easel_of(s)
	await _frames(1)
	while not main.easel_tool.returning.is_empty():
		await _frames(1)
	for kit: Brushwork.Medium in e.palettes:
		var node: Node3D = e.palettes[kit]
		var held: bool = main.easel_tool.painters.any(func(p: EaselTool.Painter) -> bool: return p.palette == e and p.kit == kit)
		assert(held or (not node.top_level and node.transform.is_equal_approx(Transform3D(Basis(), Easels.KITS[kit]))), "driver: the %s palette is not at its rest" % Brushwork.Medium.keys()[kit].to_lower())


func _hold(s: Dictionary) -> void:
	var e := _easel_of(s)
	var hand := _hand(s)
	hand.global_transform = Transform3D(e.global_basis, e.global_transform * Lessons._v(s.at))
	hand.held_still = true
	await _frames(2)


func _rag_wipe(s: Dictionary) -> void:
	var hand := _hand(s)
	var e := _easel_of(s)
	var at := Easels.RAG.get_center()
	var start := at + Vector3(-0.08, 0, 0)
	var end := start if s.get("dab", false) else at + Vector3(0.08, 0, 0)
	var path := [start + Vector3.UP * 0.08, start, end, end + Vector3.UP * 0.08]
	var steps := maxi(2, int(s.get("frames", 12)))
	for i in s.get("times", 1):
		for j in path.size() - 1:
			for k in steps:
				_tip_at(hand, e.tray(path[j].lerp(path[j + 1], float(k) / (steps - 1))), Vector3.DOWN, -e.global_basis.z)
				await _frames(1)


func _dip(s: Dictionary) -> void:
	var hand := _hand(s)
	var e := _easel_of(s)
	var into: Vector3
	match s.what:
		"jar":
			into = e.tray(Easels.JAR + Vector3(0, Easels.JAR_SIZE.y * 0.4, 0))
		_:
			var kit: Brushwork.Medium = EaselTool.PAINTS.find_key(s.what)
			into = e.palettes[kit].global_transform * (Easels.well(kit, s.index) - Vector3(0, s.get("depth", 0.0), 0))
	var along := (Vector3.DOWN - e.global_basis.z * 0.6).normalized()
	var up := -e.global_basis.z
	_tip_at(hand, into + Vector3.UP * 0.08, along, up)
	await _frames(2)
	_tip_at(hand, into, along, up)
	await _frames(3)
	_tip_at(hand, into + Vector3.UP * 0.08, along, up)
	await _frames(2)


## `points` are [x toward the paint, z across, pressure], x and z -1..1 of the palette's half size.
func _mix(s: Dictionary) -> void:
	await _brushstroke(s, true)


## `points` are [u across, v down, pressure], u and v 0..1.
func _brush(s: Dictionary) -> void:
	await _brushstroke(s, false)


func _brushstroke(s: Dictionary, palette: bool) -> void:
	var hand := _hand(s)
	hand.tool = Hand.Tool.EASEL
	var e := _easel_of(s)
	var frame := e.frame(palette)
	var roll := deg_to_rad(s.get("roll", 0.0))
	var direction := frame.basis * (Basis(Vector3.UP, deg_to_rad(s.get("tilt", 0.0))) * Vector3.FORWARD)
	var kind := main.easel_tool.painter(hand).brush
	var face: float = Brushwork.STICKS[kind].x if Brushwork.is_stick(kind) else 0.0
	var on := func(p: Array, out: float) -> Vector3:
		var depth: float = face - p[2] * Brushwork.PRESS_DEPTH
		var at := Vector2(p[0], -p[1]) * Easels.PALETTE_SIZE * 0.5 if palette else Vector2(p[0] - 0.5, 0.5 - p[1]) * Brushwork.METRES
		return frame * Vector3(at.x, at.y, depth + out)
	var pts: Array = s.points
	var before := frame.affine_inverse() * hand.global_position
	before.z = 0.6
	hand.global_position = frame * before
	await _frames(2)
	_tip_at(hand, on.call(pts[0], 0.4), direction, frame.basis.y, roll)
	await _frames(2)
	_tip_at(hand, on.call(pts[0], 0.05), direction, frame.basis.y, roll)
	await _frames(2)
	var along := func(done: float) -> void:
		var k := done * (pts.size() - 1)
		var i := mini(floori(k), pts.size() - 2) if pts.size() > 1 else 0
		var a: Array = pts[i]
		var b: Array = pts[mini(i + 1, pts.size() - 1)]
		var t := k - i
		_tip_at(hand, on.call([lerpf(a[0], b[0], t), lerpf(a[1], b[1], t), lerpf(a[2], b[2], t)], 0.0), direction, frame.basis.y, roll)
	along.call(0.0)
	await _over(s, 1.0, along)
	await _frames(1)
	if s.has("capture"):
		var hold := ToolModels.hold(kind)
		print("brush contact: tracked %s, visible %s" % [frame.affine_inverse() * hand.global_transform * hold * ToolModels.BRUSH_TIP, frame.affine_inverse() * hand.body.global_transform * hold * ToolModels.BRUSH_TIP])
		await main.capture(s.capture)
	_tip_at(hand, on.call(pts[-1], 0.05), direction, frame.basis.y, roll)
	await _frames(2)


## The hand stays at the sheet two frames before the pull: a step begun after this frame's EaselTool._process would
## otherwise move it out of reach before the grip was read, and the first frame's await resumes before it runs.
func _sheet(s: Dictionary) -> void:
	var hand := _hand(s)
	var e := _easel_of(s)
	var frame := e.canvas_frame()
	var key := Controls.key("grab", hand.tracker)
	hand.global_transform = Transform3D(frame.basis * Basis(Vector3.UP, PI), frame * Vector3(0, -0.3, 0.05))
	hand.held_still = true
	Buttons.injected[key] = true
	await _frames(2)
	if main.easel_tool.painter(hand).peel != e:
		Buttons.injected.erase(key)
		_fail("sheet: %s at easel %d's canvas gripped no sheet" % [hand.tracker, e.id])
		return
	await _over(s, 0.6, func(k: float) -> void:
		hand.global_transform = Transform3D(frame.basis * Basis(Vector3.UP, PI), frame * Vector3(0, -0.3, 0.05 + s.get("pull", 0.4) * k)))
	await _frames(1)
	await _shot(s)
	Buttons.injected.erase(key)
	await _frames(2)


## The replay is setup, run at SETUP_STEPS a frame: at the frame's own flow budget ten strokes take 2794 frames.
func _painting(s: Dictionary) -> void:
	var e := _easel_of(s)
	main.world.submit({"op": "sheet", "easel": e.id, "strokes": []})
	for stroke: Dictionary in painting(int(s.strokes)):
		main.world.submit({"op": "paint", "easel": e.id, "stroke": stroke})
	for stroke: Dictionary in daubs(int(s.get("palette", 0))):
		main.world.submit({"op": "paint", "easel": e.id, "palette": true, "stroke": stroke})
	await _frames(2)
	var steps := Canvas.steps
	Canvas.steps = SETUP_STEPS
	main.easels.repaint(e.id, main.world.state.easels[e.id].strokes)
	main.easels.repaint(e.id, main.world.state.easels[e.id].palette, true)
	await _caught_up(s)
	Canvas.steps = steps


func _undo(_s: Dictionary) -> void:
	main.world.undo()
	await _frames(1)


func _redo(_s: Dictionary) -> void:
	main.world.redo()
	await _frames(1)


func _caught_up(s: Dictionary) -> void:
	var e := _easel_of(s)
	while e.canvas.catching_up() or e.board.catching_up():
		await _frames(1)


static func painting(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var out := []
	for k in n:
		var samples := PackedInt32Array()
		var from := Vector2(rng.randf_range(0.05, 0.6), rng.randf_range(0.05, 0.95))
		var to := from + Vector2(rng.randf_range(0.2, 0.35), rng.randf_range(-0.05, 0.05))
		for i in 15:
			samples.append_array(Brushwork.pack(from.lerp(to, i / 14.0), 0.8, 0.0, 0 if i == 0 else 2))
		var c: Color = Brushwork.PIGMENTS[1 + k % (Brushwork.PIGMENTS.size() - 1)]
		out.append({"medium": Brushwork.Medium.WATER, "brush": Brushwork.Brush.BIG, "colour": Brushwork.absorbance(c), "strength": 0.8, "load": 1.0, "gap": 20, "samples": samples})
	return out


static func daubs(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var out := []
	for k in n:
		var samples := PackedInt32Array()
		var at := Vector2(rng.randf_range(-0.6, 0.75), rng.randf_range(-0.55, 0.55)) * Easels.PALETTE_SIZE * 0.5
		var heading := rng.randf() * TAU
		for i in 12:
			var point := at + Vector2.from_angle(heading + i * 0.25) * i * 0.004
			samples.append_array(Brushwork.pack(point / Canvas.metres_of(Easels.BOARD) + Vector2(0.5, 0.5), 0.9, 0.0, 0 if i == 0 else 2))
		var c: Color = Brushwork.PIGMENTS[k % Brushwork.PIGMENTS.size()]
		out.append({"medium": Brushwork.Medium.OIL, "brush": Brushwork.Brush.BIG, "colour": Brushwork.absorbance(c), "strength": 1.0, "load": 1.0, "gap": 0, "samples": samples})
	return out


func _wear(s: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(s.file) if s.has("file") else PackedByteArray()
	var scene := Avatar.read(bytes) if s.has("file") else null
	assert(scene != null or not s.has("file"), "driver: %s is not an avatar within the limits" % s.get("file"))
	main.session.put_on.call_deferred(scene, Session.sha256(bytes) if s.has("file") else "", bytes, int(s.get("avatar", 0)), Color(s.get("tint", "#d9824b")))
	await _frames(2)


## Desktop only. `lift` is an adult's metres, sized as the pose is.
func _posture(s: Dictionary) -> void:
	var rig: Rig = main.rig
	var which := Posture.poses.find_custom(func(q: Dictionary) -> bool: return q.name == s.pose)
	var eye_height: float = rig.body.eye_height if rig.body else Rig.EYE
	var points := Posture.held(which, eye_height)
	var eyes := points[0]
	var held: Array[Transform3D] = [points[1], points[2]]
	var x := float(s.get("x", 0.0))
	var z := float(s.get("z", 0.0))
	var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(s.get("yaw", 0.0))), Vector3(x, float(s.get("y", main.world.terrain.height_at(x, z))) + s.get("lift", 0.0) * eye_height / Rig.EYE, z))
	var to: Array[Transform3D] = [frame * eyes, frame * held[0], frame * held[1]]
	var from: Array[Transform3D] = [rig.head.global_transform, rig.left.global_transform, rig.right.global_transform]
	var seconds := float(s.get("seconds", 0.0))
	var t := 0.0
	while true:
		var k := smoothstep(0.0, 1.0, minf(t / seconds, 1.0)) if seconds > 0.0 else 1.0
		rig.head.global_transform = from[0].interpolate_with(to[0], k)
		for i in 2:
			rig.hands[i].global_transform = from[i + 1].interpolate_with(to[i + 1], k)
			rig.hands[i].held_still = true
		if k >= 1.0:
			break
		t += await _tick()
	await _frames(2)


func _markers(_s: Dictionary) -> void:
	var balls: Array[MeshInstance3D] = []
	for c: Color in [Color.RED, Color.GREEN, Color.BLUE, Color.RED]:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.albedo_color = c
		var mi := MeshInstance3D.new()
		if balls.size() < 3:
			mi.mesh = ToolModels.sphere(0.035, 0.07)
		else:
			var stalk := BoxMesh.new()
			stalk.size = Vector3(0.012, 0.012, 0.2)
			mi.mesh = stalk
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		balls.append(mi)
		add_child(mi)
	while is_inside_tree():
		var shown: Array = main.session.avatars.values().filter(func(a: Avatar) -> bool: return a.visible)
		for mi in balls:
			mi.visible = not shown.is_empty()
		if not shown.is_empty():
			var a: Avatar = shown[0]
			balls[0].global_position = a.eyes.origin
			balls[1].global_position = a.hands[0].origin
			balls[2].global_position = a.hands[1].origin
			balls[3].global_transform = a.eyes * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.1))
		await get_tree().process_frame


func _hold_pose(s: Dictionary) -> void:
	var hand := _hand(s)
	hand.global_transform = main.rig.head.global_transform * Lessons.frame({"at": Lessons._v(s.at), "aim": Lessons._v(s.aim).normalized(), "roll": s.get("roll", 0.0)})
	hand.held_still = true
	await _frames(2)


func _page_cost(s: Dictionary) -> void:
	var b: Book = main.book
	var rd := RenderingServer.get_rendering_device()
	var pages := {}
	for page in b.scenes:
		RenderingServer.viewport_set_measure_render_time(b.scenes[page].get_viewport_rid(), true)
		pages[str(b.scenes[page].get_viewport_rid().get_id())] = page
	var main_id := str(get_viewport().get_viewport_rid().get_id())
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var renders: Array[float] = []
	var views: Array[float] = []
	var total := 0.0
	var frames := 0
	var t := 0.0
	while t < s.seconds:
		await RenderingServer.frame_post_draw
		frames += 1
		var begin := {}
		for i in rd.get_captured_timestamps_count():
			var n := rd.get_captured_timestamp_name(i)
			var id := n.trim_prefix("vp_begin_").trim_prefix("vp_end_")
			if n.begins_with("vp_begin_"):
				begin[id] = rd.get_captured_timestamp_gpu_time(i)
			elif begin.has(id):
				var ms: float = (rd.get_captured_timestamp_gpu_time(i) - begin[id]) / 1e6
				if pages.has(id):
					renders.append(ms)
					total += ms
				elif id == main_id:
					views.append(ms)
		t += get_process_delta_time()
	renders.sort()
	views.sort()
	print("page_cost: %d frames, %d page renders, %.3f ms GPU a page render (median), %.3f ms a frame for the pages, the garden's view %.3f ms (median)" % [frames, renders.size(),
		renders[renders.size() / 2] if not renders.is_empty() else 0.0, total / maxi(frames, 1), views[views.size() / 2] if not views.is_empty() else 0.0])


func _book(s: Dictionary) -> void:
	var b: Book = main.book
	match s.do:
		"open":
			b.open()
		"turn":
			b.turn(1)
		"back":
			b.turn(-1)
		_:
			_fail("book: no %s" % s.do)
	await get_tree().create_timer(s.get("seconds", 1.0)).timeout


func _capture(s: Dictionary) -> void:
	await main.capture(s.name, s.get("screen", false))


func _quit(_s: Dictionary) -> void:
	main.finish()


## "relative" makes a script work whichever way the headset faces.
func _spot(s: Dictionary, x: float, z: float) -> Vector3:
	if not s.get("relative", false):
		return main.world.terrain.ground(x, z)
	var fwd := _ahead()
	var p := main.rig.head.global_position + fwd.cross(Vector3.UP) * x + fwd * z
	return main.world.terrain.ground(p.x, p.z)


func _ahead() -> Vector3:
	var fwd := -main.rig.head.global_basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD


func _toward(s: Dictionary) -> Vector3:
	return _spot(s, s.facing[0], s.facing[1]) if s.has("facing") else main.rig.head.global_position


func _target(s: Dictionary, p: Vector3) -> Dictionary:
	if s.get("on", false):
		var hit: Dictionary = main.tool.aim(p + Vector3.UP * 60.0, Vector3.DOWN)
		if not hit.is_empty():
			return hit
	return {"point": p, "on": -1}


func _path(s: Dictionary) -> Array[Vector3]:
	var path: Array[Vector3] = []
	for p in s.points:
		path.append(_spot(s, p[0], p[1]))
	return path


func _along(path: Array[Vector3], fraction: float) -> Vector3:
	var d := 0.0
	for i in path.size() - 1:
		d += path[i].distance_to(path[i + 1])
	d *= fraction
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if d <= seg:
			var p := path[i].lerp(path[i + 1], d / seg if seg > 0.0 else 0.0)
			p.y = main.world.terrain.height_at(p.x, p.z)
			return p
		d -= seg
	return path[-1]


## Without `step`, the governor walks the ladder again.
func _quality(s: Dictionary) -> void:
	var step: Variant = s.get("step", -1)
	if step is String:
		main.quality.pin = {"fit": Budget.fit_step(), "held": main.quality.step()}[step]
	else:
		main.quality.pin = int(step)
	print("driver: quality pinned at %d" % main.quality.pin)


## The Mobile renderer reads XR_FB_foveation's density map only with the view's VRS mode at XR.
func _antialias(s: Dictionary) -> void:
	var vp: Viewport = main.get_viewport()
	if s.has("msaa"):
		vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}[int(s.msaa)]
	if s.has("screen"):
		vp.screen_space_aa = {"none": Viewport.SCREEN_SPACE_AA_DISABLED, "fxaa": Viewport.SCREEN_SPACE_AA_FXAA, "smaa": Viewport.SCREEN_SPACE_AA_SMAA}[s.screen]
	if s.has("foveation") and main.xr != null and main.metrics.info.xr:
		vp.vrs_mode = Viewport.VRS_XR if int(s.foveation) > 0 else Viewport.VRS_DISABLED
		main.xr.foveation_level = int(s.foveation)
		print("driver: foveation %d supported %s" % [main.xr.foveation_level, main.xr.is_foveation_supported()])
	if s.has("unshaded"):
		vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED if s.unshaded else Viewport.DEBUG_DRAW_DISABLED


## After a late frame the runtime keeps every other refresh for a while, and a phase opened on that measures the
## setup before it (a whole village laid at once, which no player does), not its own frames.
func _label(s: Dictionary) -> void:
	var metrics: Metrics = main.metrics
	if s.name != "-" and metrics.late_at_us >= 0:
		var start: int = metrics.clock.call()
		var now := start
		while now - metrics.late_at_us < SETTLED_S * 1e6 and now - start < SETTLE_MAX_S * 1e6:
			await get_tree().process_frame
			now = metrics.clock.call()
		if now > start:
			print("driver: %s opens after %.1f s waiting for on-time frames%s" % [s.name, (now - start) / 1e6, "" if now - metrics.late_at_us >= SETTLED_S * 1e6 else ", still late"])
	metrics.info.label = s.name


func _logged_label(name: String) -> void:
	var label := {"op": "label", "name": name}
	print("driver: ", label)
	await _label(label)


## So every phase of demo/costs.json is measured at the refresh rate, on any headset, from one script.
func _sized(s: Dictionary) -> void:
	var line := Budget.line_ms() * 0.95
	var base: Array[float] = []
	for v: Dictionary in s.views:
		base.append(await _gpu_ms(v))
	for attempt in 4:
		for b: Dictionary in s.build:
			await call("_" + b.op, b)
		await _standing()
		var share := 1.0
		var read: Array[float] = []
		for i in s.views.size():
			read.append(await _gpu_ms(s.views[i]))
			if read[i] > line:
				share = minf(share, maxf(line - base[i], 0.0) / (read[i] - base[i]))
		print("sized: area %.3f, %s ms over the bare %s" % [_area, read, base])
		if share == 1.0 or attempt == 3:
			break
		_area *= clampf(share * 0.9, 0.1, 0.9)
		await _bare({})
	_area = 1.0


func _gpu_ms(view: Dictionary) -> float:
	await _view(view)
	await get_tree().create_timer(1.5).timeout
	var sum := 0.0
	var n := 0
	var until := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		if main.quality.fresh:
			sum += main.quality.frame_ms
			n += 1
	return sum / n if n > 0 else 0.0


func _bare(_s: Dictionary) -> void:
	main.world.submit({"op": "wipe"})
	await _frames(3)


func _budget(s: Dictionary) -> void:
	main.world.limit = s.get("fill", 1.0) if s.bounded else INF


func _units(_s: Dictionary) -> void:
	print("budget: %s units %s ms %.3f fill %.3f flora %s" % [main.metrics.info.label, JSON.stringify(main.world.units), Budget.cost_ms(main.world.units), main.world.fill(), JSON.stringify(_flora_units)])
	_flora_units = {}


func _stairs(s: Dictionary) -> void:
	var hand: Hand = main.rig.right
	hand.tool = Hand.Tool.STAIRS
	main.world.stairs.rail = s.get("rail", "stone")
	var a := Lessons._v(s.a)
	var b := Lessons._v(s.b)
	if s.get("ground", false):
		a.y += main.world.terrain.height_at(a.x, a.z)
		b.y += main.world.terrain.height_at(b.x, b.z)
	if s.get("on", false):
		a = _target(s, main.world.terrain.ground(a.x, a.z)).point
		b = _target(s, main.world.terrain.ground(b.x, b.z)).point
	main.stair_tool.begin(hand, a, s.get("width", StairTool.WIDTH))
	var frames := maxi(1, int(s.get("seconds", 1.0) * 30.0))
	for i in frames:
		main.stair_tool.extend(hand, a.lerp(b, float(i + 1) / frames))
		await get_tree().create_timer(1.0 / 30.0).timeout
	main.stair_tool.end(hand)


## Leaves whether later scripted builds are bounded as it was.
func _stair_field(_s: Dictionary) -> void:
	main.world.submit({"op": "wipe"})
	await _sculpt({"x": 5.0, "z": -6.0, "lift": 2.0, "seconds": 0.2})
	await _pave({"points": [[5, -2.5], [5, -6]], "radius": 0.8, "seconds": 0.2})
	var placed := 0
	for row in 9:
		for col in 9:
			var a := main.world.terrain.ground((col - 4) * 3.5, (row - 4) * 6.0)
			var d := {"a": a, "b": a + Vector3(0, 2.4, -4), "width": 1.2, "sag": 0.0, "rail": "stone" if col % 2 == 0 else "wood", "seed": row * 9 + col, "paint": Palette.plain(), "on": PackedInt32Array()}
			if col % 3 == 1:
				d.b = a + Vector3(0, 3, -1)
			elif col % 3 == 2:
				d.b = a + Vector3(0, 0, -4)
			if not Budget.fits(main.world.units, main.world.change_of(d.merged({"op": "stairs"}))):
				print("stairs: budget full at %d builds, fill %.3f" % [placed, main.world.fill()])
				return
			main.world.submit(d.merged({"op": "stairs"}))
			placed += 1
			await get_tree().process_frame
	assert(false, "stair field did not fill the budget")


## Four eaters, the largest visiting band, built a second before the phase opens: all four in one frame is a late
## frame no visiting band makes, since animals come one at a time.
func _neck_cost(s: Dictionary) -> void:
	var animals: Array[Beast] = []
	var dishes: Array[Dish] = []
	for i in 4:
		var animal := Beast.new(Beast.Kind.FOX if i == 3 else Beast.Kind.DEER, 1.0, i * 0.2)
		add_child(animal)
		animal.set_process(false)
		animal.neck.active = false
		var dish := Dish.new()
		add_child(dish)
		dish.visible = true
		var at := main.world.terrain.ground(12.0 + i * 1.8, 0)
		dish.position = at + Vector3(0, 0.25 if i == 3 else [0.4, 0.8, 1.05][i], 0)
		animal.position = at
		animal.position.z += Hand.TOP.z + animal.neck.stand_off(animal, dish)
		animal.eat(dish.position.y - at.y, 0.0)
		animal.neck.offer = dish
		animal.neck.amount = 1.0
		animals.append(animal)
		dishes.append(dish)
	await get_tree().create_timer(1.0).timeout
	await _logged_label(s.label)
	var elapsed := 0.0
	var samples: Array[float] = []
	var solving: bool = s.get("solve", true)
	while elapsed < s.get("seconds", 10.0):
		elapsed += await _tick()
		for dish in dishes:
			dish.position.z = sin(elapsed * 0.7) * 0.02
		var start := Time.get_ticks_usec()
		if solving:
			for animal in animals:
				animal.neck._process_modification()
		samples.append((Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	print("neck_cost: solve=%s, four animals, %d frames, CPU median %.4f ms, p95 %.4f ms, max %.4f ms" % [solving, samples.size(), samples[samples.size() / 2], samples[int(samples.size() * 0.95)], samples[-1]])
	await _logged_label("-")
	for animal in animals:
		animal.queue_free()
	for dish in dishes:
		dish.queue_free()


func _held_snapshot(s: Dictionary) -> void:
	await get_tree().create_timer(Hand.POP * 3.0).timeout
	var items := main.session.held_items()
	if s.get("loaded", false):
		assert(items[1].size() == 8 and items[1][0] == HeldItem.Kind.BRUSH and items[1][4] > 0.0, "capture holds a loaded brush")
	var path: String = main.capture_path(s.name)
	FileAccess.open(path + ".held", FileAccess.WRITE).store_var([multiplayer.get_unique_id(), items])
	FileAccess.open(path + ".json", FileAccess.WRITE).store_string(JSON.stringify({"held": items.map(HeldItem.label)}))


func _remote_holds(s: Dictionary) -> void:
	var path: String = main.capture_path(s.name)
	var expected: Array = FileAccess.open(path + ".held", FileAccess.READ).get_var()
	var elapsed := 0.0
	while elapsed < 30.0:
		elapsed += await _tick()
		if not main.session.held.has(expected[0]):
			continue
		var pair: Array = main.session.held[expected[0]]
		var matches := true
		var avatar: Avatar = main.session.avatars[expected[0]]
		for side in 4:
			var item: HeldItem = pair[side]
			matches = matches and HeldItem.same(item.state, expected[1][side])
			if item.state.is_empty():
				matches = matches and item.model == null
			else:
				matches = matches and item.model != null and item.model.is_visible_in_tree() and item.model.transform.is_equal_approx(item.state[2])
				matches = matches and item.transform.is_equal_approx(avatar.hands[side] if side < 2 else Torso.frame(avatar.eyes, avatar.torso))
				matches = matches and (side >= 2 or avatar.folded(side) == item.replaces_hand())
				if item.state[0] == HeldItem.Kind.BRUSH and not Brushwork.is_stick(item.state[1]):
					var tip := (item.model.get_node("tip") as MeshInstance3D).material_override as ShaderMaterial
					var colour: Color = tip.get_shader_parameter("paint_colour")
					matches = matches and colour.is_equal_approx(item.state[3]) and is_equal_approx(tip.get_shader_parameter("load"), item.state[4])
		if matches:
			print("held: peer sees %s in the other player's hands and on their shoulders" % str(expected[1].map(HeldItem.label)))
			return
	assert(false, "remote held models differ from holder: " + s.name)


static func held_states(birds: bool = false) -> Array:
	if birds:
		return [[HeldItem.Kind.BIRD, 0, BirdCarry.HOLD, Color.WHITE, 0.0, 0, false, Vector3.ZERO]]
	var states: Array = []
	for tool in Hand.Tool.values():
		if tool not in Hand.UNMODELLED:
			states.append([HeldItem.Kind.TOOL, tool, Transform3D(Basis(), Hand.TOP), Color.WHITE, 0.0, 0, false, Vector3.ZERO])
	states.append([HeldItem.Kind.PALETTE, Brushwork.Medium.OIL, Transform3D(), Color.WHITE, 0.0, 1, false, Vector3.ZERO])
	states.append([HeldItem.Kind.PALETTE, Brushwork.Medium.WATER, Transform3D(), Color.WHITE, 0.0, 1, false, Vector3.ZERO])
	for brush in Brushwork.Brush.values():
		states.append([HeldItem.Kind.BRUSH, brush, Transform3D(), Color(0.15, 0.3, 0.65), 1.0, 0, false, Vector3.ZERO])
	states.append([HeldItem.Kind.BOOK, 1, Book.local(1.0), Color.WHITE, 0.0, 0, false, Vector3.ZERO])
	return states


func _held_cost(s: Dictionary) -> void:
	var items: Array[HeldItem] = []
	var eye: Transform3D = main.rig.head.global_transform
	for i in (Session.MAX_PLAYERS - 1) * 2:
		var item := HeldItem.new()
		item.terrain = main.world.terrain
		add_child(item)
		item.global_transform = eye * Transform3D(Basis(), Vector3((i % 7 - 3) * 0.2, (i / 7 - 0.5) * 0.35, -0.8))
		items.append(item)
	var states := held_states(s.get("birds", false))
	for state in states:
		assert(HeldItem.valid(state), "invalid stress state: " + HeldItem.label(state))
		for item in items:
			item.show_state(state)
			item.visible = s.get("shown", true)
		# Every item's models are built in one frame, which no player does, and the runtime runs at half rate for a
		# moment after it.
		await get_tree().create_timer(1.0).timeout
		await _shot(s)
		var name := HeldItem.label(state)
		await _logged_label(s.get("label", "held/" + name.replace(" ", "-")))
		await get_tree().create_timer(s.get("seconds", 3.0)).timeout
		await _logged_label("-")
	for item in items:
		item.queue_free()


func _befriend(s: Dictionary) -> void:
	var h := _hand(s)
	var flock: Birds = main.wildlife.birds
	var elapsed := 0.0
	while flock.birds.is_empty() and elapsed < 240.0:
		elapsed += await _tick()
	assert(not flock.birds.is_empty(), "no conure arrived")
	var available := flock.birds.filter(func(b: Birds.Bird) -> bool: return not b.carried)
	assert(not available.is_empty(), "no free bird")
	var bird: Birds.Bird = available[0]
	while bird.state != Birds.State.PERCH and elapsed < 260.0:
		elapsed += await _tick()
	assert(bird.state == Birds.State.PERCH, "bird did not land")
	h.tool = Hand.Tool.SEEDS
	h.held_still = true
	h.global_transform = Transform3D(Basis.IDENTITY, bird.node.global_position + Vector3(0.2, -0.15, 0.2))
	elapsed = 0.0
	while elapsed < 90.0:
		elapsed += await _tick()
		var fed := flock.birds.filter(func(b: Birds.Bird) -> bool: return b.node.hand == h and b.state == Birds.State.FEED and b.affection >= BirdCarry.TRUST)
		if not fed.is_empty():
			bird = fed[0]
			break
	if bird.node.hand != h or bird.affection < BirdCarry.TRUST or bird.state != Birds.State.FEED:
		_fail("bird did not feed and trust hand")
		return
	Buttons.injected[Controls.key("grab", h.tracker)] = true
	await _frames(30)
	if h.carried != bird.node:
		_fail("grip did not pick up fed bird")
		return
	print("conure: feeding earned trust, grip carries bird")


func _shoulder_bird(s: Dictionary) -> void:
	var flock: Birds = main.wildlife.birds
	var elapsed := 0.0
	var head := main.rig.head.global_position
	while elapsed < 120.0:
		_flock_near(head, Birds.FOLLOW_FROM)
		if s.get("trust", false):
			for b in flock.birds:
				if b.state == Birds.State.PERCH:
					b.affection = BirdCarry.TRUST
		var side: int = main.rig.shoulders.find_custom(func(c: Conure) -> bool: return c != null)
		if side >= 0:
			print("conure: rides the player's shoulder")
			if s.get("look", false):
				var yaw: float = main.rig.torso().basis.get_euler().y - main.rig.global_basis.get_euler().y
				main.rig.head.transform.basis = Basis.from_euler(Vector3(-0.6, yaw + Torso.TURN * (1.0 if side == 0 else -1.0), 0))
			return
		var was := elapsed
		elapsed += await _tick()
		if was < 20.0 and elapsed >= 20.0:
			for b in flock.birds:
				print("conure: %s, affection %.2f, away %.1f s, %.1f m off, asleep %s, head under water %s" % [Birds.State.keys()[b.state], b.affection, b.away, b.node.position.distance_to(main.rig.head.global_position), main.wildlife.asleep(), main.rig.under])
	assert(false, "no conure came to the shoulder")


## A conure bound within `reach` may perch farther off before it comes.
func _flock_near(at: Vector3, reach: float) -> void:
	var flock: Birds = main.wildlife.birds
	if flock.birds.any(func(b: Birds.Bird) -> bool: return b.to.distance_to(at) < reach):
		return
	flock.look()
	var nearest: Birds.Site = null
	var best := reach
	for site in flock.sites:
		for p in site.points():
			if p.distance_to(at) < best:
				best = p.distance_to(at)
				nearest = site
	assert(nearest != null, "no perch within %.1f m of %s for a conure" % [reach, at])
	flock.arrive(nearest)


func _bird_smear(s: Dictionary) -> void:
	var h := _hand(s)
	assert(h.carried != null, "no held bird")
	var e := _easel_of(s)
	var frame := e.canvas_frame()
	var basis := frame.basis
	var from := h.global_transform
	var target := Transform3D(basis, frame * Vector3(-0.25, 0, 0.09) - basis * (BirdCarry.HOLD.origin + Conure.BODY))
	var approach := 0.0
	while approach < 0.6:
		approach += await _tick()
		h.global_transform = from.interpolate_with(target, smoothstep(0.0, 0.6, approach))
	await _frames(2)
	await _over(s, 3.0, func(along: float) -> void: h.global_transform = Transform3D(basis, frame * Vector3(lerpf(-0.25, 0.25, along), along * 0.18, 0.018) - basis * (BirdCarry.HOLD.origin + Conure.BODY)))
	h.global_position += frame.basis.z * 0.2
	await _frames(30)
	print("conure: wet canvas smear submitted")


## The paired fixture's way of taking the bird alone out of a view.
func _bird_shown(s: Dictionary) -> void:
	var h := _hand(s)
	assert(h.carried != null, "no held bird")
	h.carried.visible = s.shown
	await _frames(2)


func _view_held(s: Dictionary) -> void:
	var h := _hand(s)
	assert(h.carried != null)
	h.global_transform = Transform3D(Basis.IDENTITY, main.world.terrain.ground(1.5, 2.0) + Vector3.UP * 1.4)
	await _frames(30)
	var at := h.carried.global_position + Vector3.UP * 0.07
	var hand_pose := h.global_transform
	main.view(at + Vector3(0.25, 0.13, -0.36), at)
	h.global_transform = hand_pose
	await _frames(30)


## So the views of them do not hang on when they happen to come.
func _shy(_s: Dictionary) -> void:
	main.wildlife.birds.look()
	main.wildlife.squirrels.look()
	for kind in main.wildlife.shy():
		kind.fill()
	await get_tree().process_frame


## The same animals in the same places every run, so a fixed view frames the same scene however the roamers walk.
func _beasts(s: Dictionary) -> void:
	for a in _stood_beasts:
		a.queue_free()
	_stood_beasts.clear()
	var roamers: Roamers = main.wildlife.roamers
	if not s.has("deer") and not s.has("fox"):
		roamers.held = false
		return
	roamers.hold()
	var facing := main.world.terrain.ground(s.facing[0], s.facing[1])
	for kind: Beast.Kind in Beast.GROUPS:
		var spots: Array = s.get(Beast.GROUPS[kind], [])
		for i in spots.size():
			var at := main.world.terrain.ground(spots[i][0], spots[i][1])
			if not main.wildlife.standable(at):
				_fail("%s %d at %s has no ground to stand on" % [Beast.GROUPS[kind], i, at])
				return
			var a := Beast.new(kind, 1.0, i * 0.3)
			roamers.add_child(a)
			a.position = at
			Wildlife._face(a, facing - at, 1.0)
			_stood_beasts.append(a)


## So the views of them do not hang on when they happen to come.
func _roamers(_s: Dictionary) -> void:
	var roamers: Roamers = main.wildlife.roamers
	for kind: Beast.Kind in Roamers.FIRST:
		while get_tree().get_nodes_in_group(Beast.GROUPS[kind]).is_empty():
			if not roamers.bands.any(func(b: Grazers.Band) -> bool: return (b.animals[0] as Beast).kind == kind):
				roamers.arrive(kind)
			await get_tree().process_frame


func _release_bird(s: Dictionary) -> void:
	var h := _hand(s)
	Buttons.injected.erase(Controls.key("grab", h.tracker))
	await _frames(2)
	assert(h.carried == null, "bird must leave the hand when grip releases")


func _spring_avatar(s: Dictionary) -> Avatar:
	return main.session.avatars.values()[0] if s.get("remote", false) else main.rig.body


func _spring_grab(s: Dictionary) -> void:
	var remote: bool = s.get("remote", false)
	var avatar := _spring_avatar(s)
	var chain := _chain(avatar, s)
	if chain < 0:
		_fail("spring: no chain to grab")
		return
	await _pick({"hand": "right", "tool": "none"})
	var hand := main.rig.right
	hand.held_still = true
	hand.global_position = avatar.springs.tip(chain)
	await get_tree().create_timer(0.3).timeout
	var key := Controls.key("grab", hand.tracker)
	Buttons.injected[key] = true
	var mine := [main.session.multiplayer.get_unique_id(), 1]
	var deadline := Time.get_ticks_msec() + 5000
	var held: Variant = null
	while held == null and Time.get_ticks_msec() < deadline:
		held = avatar.spring_holders.find_key(mine)
		await get_tree().process_frame
	if held == null:
		Buttons.injected.erase(key)
		_fail("spring: owner did not accept grip")
		return
	chain = held
	var from := hand.global_position
	var move := Lessons._v(s.move)
	var elapsed := 0.0
	var seconds: float = s.get("seconds", 3.0)
	var travelled := 0.0
	while elapsed < seconds:
		elapsed += await _tick()
		hand.global_position = from + move * sin(minf(elapsed / seconds, 1.0) * PI * 0.5)
		travelled = maxf(travelled, from.distance_to(avatar.springs.tip(chain)))
	Buttons.injected.erase(key)
	await get_tree().create_timer(1.0).timeout
	if travelled < 0.025:
		_fail("spring: grip did not move the tip")
	print("spring: %s grip travelled %.4f m and released" % ["remote" if remote else "wearer", travelled])


func _spring_watch(s: Dictionary) -> void:
	var seconds: float = s.get("seconds", 60.0)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	var held := false
	var moved := 0.0
	var first := Vector3.ZERO
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var active := main.rig.body.spring_holders.values().any(func(holder: Array) -> bool: return holder[0] != main.session.multiplayer.get_unique_id())
		if active:
			var tip: Vector3 = main.rig.body.springs.tip(0)
			if not held:
				first = tip
			moved = maxf(moved, tip.distance_to(first))
			held = true
		elif held:
			print("spring: wearer observed remote grab, %.4f m movement, release" % moved)
			if moved < 0.025:
				_fail("spring: a remote grab moved the tip only %.4f m" % moved)
			return
	_fail("spring: wearer never observed a remote grab and release")


func _spring_sway(s: Dictionary) -> void:
	var springs = main.rig.body.springs
	var contacts := 0
	var native := 0
	var eye := main.rig.head.global_position
	var ahead := -main.rig.head.global_basis.z
	var elapsed := 0.0
	var seconds: float = s.get("seconds", 3.0)
	while elapsed < seconds:
		elapsed += await _tick()
		var offset := Vector3(sin(elapsed * TAU) * 0.3, 0, 0)
		main.view(eye + offset, eye + offset + ahead)
		for c: int in springs.chains.size():
			if springs.touches(c, 0.002):
				contacts += 1
				if springs.chains[c].native_active:
					native += 1
	main.view(eye, eye + ahead)
	print("spring: sway held chains on their declared colliders for %d chain-frames, %d on native springs" % [contacts, native])
	if contacts == 0:
		_fail("spring: sway never contacted the declared collider")
	if springs.chains.any(func(chain: Dictionary) -> bool: return chain.native != null) and native == 0:
		_fail("spring: native springs never met their declared collider")


func _spring_ready(_s: Dictionary) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	var held := false
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if main.session.avatars.is_empty():
			continue
		var avatar: Avatar = main.session.avatars.values()[0]
		if not avatar.spring_holders.is_empty():
			held = true
		elif held:
			await get_tree().create_timer(1.0).timeout
			return
	_fail("spring: peer never observed wearer grip and release")


func _chain(avatar: Avatar, s: Dictionary) -> int:
	if avatar.springs == null:
		return -1
	var named: Variant = s.get("chain", 0)
	if named is String:
		for c in avatar.springs.chains.size():
			var first: Variant = avatar.springs.chains[c].joints[0].node
			if first is Avatar.SkeletonBone and first.skeleton.get_bone_name(first.bone) == named:
				return c
		return -1
	return int(named) if int(named) < avatar.springs.chains.size() else -1


func _spring_view(s: Dictionary) -> void:
	await get_tree().create_timer(2.0).timeout
	var avatar: Avatar = main.session.avatars.values()[0]
	var middle := (avatar.eyes.origin + avatar.springs.tip(_chain(avatar, s))) * 0.5
	main.view(middle - avatar.eyes.basis.x * 0.8, middle)
	await _frames(2)


func _expression(s: Dictionary) -> void:
	if s.get("fixture", false):
		main.rig.wear(Avatar.open(preload("res://demo/expressions.gd").scene(), Color.WHITE, "expression-demo"))
		main.rig.body.expressions.state.restore({"Hat": 0.0, "Size": 0.5, "Colour": 0.0, "Tone": 0.0, "Decal": 0.0})
		await _frames(2)
		return
	var hand := _hand(s)
	var button := Controls.key("wheel", hand.tracker)
	var tree := hand.inventory()
	Hand.injected_reach[hand.tracker] = Vector2.ZERO
	Buttons.injected[button] = true
	await _frames(2)
	for p in ToolWheel.sweep(tree, ToolWheel.paths(tree)[s.get("slot", "expressions")]):
		Hand.injected_reach[hand.tracker] = p
		await _frames(2)
	if s.get("slot", "expressions") == "expressions":
		Hand.injected_reach[hand.tracker] = Vector2.ZERO
	await _frames(2)
	for index: int in s.get("controls", []):
		Hand.injected_reach[hand.tracker] = ToolWheel.ring_dirs()[index] * ToolWheel.RADIUS
		await _frames(1)
		if hand.expressions != null and (hand._wheel == null or hand._wheel.chosen() == null):
			Hand.injected_reach[hand.tracker] = Vector2.ZERO
		await _frames(2)
	var puppet := hand.expressions != null and not hand.expressions.state.turning().is_empty()
	if puppet:
		Buttons.injected.erase(button)
		await _frames(2)
	var from := hand.global_basis
	if s.has("twist"):
		for f in 30:
			hand.global_basis = Basis(-from.z, deg_to_rad(float(s.twist) * (f + 1) / 30.0)) * from
			await _frames(1)
	if s.has("stick"):
		Hand.injected_sticks["right_hand"] = Vector2(s.stick[0], s.stick[1])
	if s.has("label"):
		await _label({"name": s.label})
	await get_tree().create_timer(s.get("seconds", 1.0)).timeout
	await _shot(s)
	if puppet:
		Buttons.injected[button] = true
		await _frames(2)
	Buttons.injected.erase(button)
	await _frames(2)
	Hand.injected_reach.erase(hand.tracker)
	Hand.injected_sticks.erase("right_hand")
	hand.global_basis = from
	await _frames(2)


func _spring_poke(s: Dictionary) -> void:
	var avatar := _spring_avatar(s)
	var index := _chain(avatar, s)
	if index < 0:
		_fail("spring: no chain to poke")
		return
	var chain: Dictionary = avatar.springs.chains[index]
	await _pick({"hand": "right", "tool": "none"})
	var hand := main.rig.right
	hand.held_still = true
	var through: Vector3 = chain.joints[chain.joints.size() / 2].node.global_position
	var rest := avatar.springs.tip(index)
	var seconds: float = s.get("seconds", 4.0)
	var elapsed := 0.0
	var moved := 0.0
	while elapsed < seconds:
		hand.global_position = through - avatar.eyes.basis.x * 0.03 - avatar.eyes.basis.z * 0.15 * cos(elapsed / seconds * 2.0 * TAU)
		elapsed += await _tick()
		moved = maxf(moved, rest.distance_to(avatar.springs.tip(index)))
	hand.global_position = through - avatar.eyes.basis.x * 0.4
	await get_tree().create_timer(1.0).timeout
	print("spring: poke moved the tip %.4f m" % moved)
	if moved < 0.02:
		_fail("spring: poke did not move the tip")
