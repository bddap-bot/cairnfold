class_name Driver
extends Node

## Plays a JSON list of steps through the same rig and tool entry points the controllers use.
## A step marked "background" starts and the next one follows at once, as a camera glides while a wall is drawn.
## Each step starts once the garden's builds are laid, so it reads them as built.

signal finished

## The parts of the scene `layer` hides, as demo/meadow-layers.json prices the bare meadow; "all" hides every one.
## "mountains" are the ranges and whatever lies between them and the meadow.
const LAYERS := ["terrain", "grass", "flowers", "trees", "mountains", "sky", "sun_disc", "sun", "shadows", "masonry", "camera_previews", "ambient", "fog", "post", "msaa", "water", "hands", "ceilings"]

var main: Node
var steps: Array
var _eye := Vector3.ZERO
var _at := Vector3.FORWARD
var _waiting := {}
## What `layer` hid: each property it turned off, by object and property, and the value it had before.
var _hidden := {}
## The share of their area the builds a `sized` step lays take: walls farther apart, a village over a smaller disc,
## paths shorter.
var _area := 1.0


func _init(owner: Node, script: Array) -> void:
	main = owner
	steps = script


static func read(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Array, "script %s is not a JSON array" % path)
	return parsed


func _ready() -> void:
	_run()


func _run() -> void:
	for step in steps:
		await _standing()
		print("driver: ", step)
		if step.get("background", false):
			call("_" + step.op, step)
		else:
			await call("_" + step.op, step)
	await _standing()
	print("driver: done")
	finished.emit()


func _exit_tree() -> void:
	if not _waiting.is_empty():
		push_error("driver: until %s timed out" % _waiting)


func _standing() -> void:
	while main.world.stairs.laying() or main.tool.walls.any(func(w: Wall) -> bool: return w.laying()):
		await get_tree().process_frame


func _wait(s: Dictionary) -> void:
	await get_tree().create_timer(s.seconds).timeout


## Holds a control of `device` (default the Frame; see Controls.DEVICES) for `seconds`, as the controller
## would feed it.
func _press(s: Dictionary) -> void:
	var control: String = s.button
	var device: String = s.get("device", "frame")
	hold(device, control, true)
	await get_tree().create_timer(s.get("seconds", 0.1)).timeout
	hold(device, control, false)
	await get_tree().process_frame
	await get_tree().process_frame


## Holds or lets go of a device's control: a stick direction moves the stick that way.
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


## Rests a finger on a control of `device` (default the Frame) for `seconds` without pressing it, as on a controller of
## `profile` (default the Touch's) whatever the runtime binds; "capture" saves the view before lifting it.
func _rest(s: Dictionary) -> void:
	var to: Array = Controls.DEVICES[s.get("device", "frame")][s.button]
	var touch: String = Controls.TOUCHES.keys().filter(func(t: String) -> bool: return to[1] in Controls.TOUCHES[t])[0]
	var key := "%s/%s" % [to[0], touch]
	Hand.injected_profile = s.get("profile", "/interaction_profiles/oculus/touch_controller")
	Buttons.injected[key] = true
	await get_tree().create_timer(s.get("seconds", 1.0)).timeout
	if s.has("capture"):
		await main.capture(s.capture)
	Buttons.injected.erase(key)
	await _frames(2)


## Takes a tool from a hand's wheel as a player does: hold the wheel button, sweep the hand through each
## level of the tool's path, let go; "none" lets go at the centre, emptying the hand. An untracked hand is moved itself; a tracked one sweeps by injected
## reach. "capture" saves a view at the opening and at each level reached, as "<capture>-<level>",
## "popping" one the frame after the pick.
func _pick(s: Dictionary) -> void:
	var hand: Hand = _hand(s)
	var key := "%s/%s" % [hand.tracker, Controls.input("wheel", hand.tracker)]
	var tree := hand.inventory()
	var leaf: Variant = s.get("action", Hand.Tool.get(str(s.get("tool", "none")).to_upper(), Hand.Tool.NONE))
	var path: Array[int] = ToolWheel.paths(tree).get(leaf, [] as Array[int])
	var start := hand.global_position
	var reach := func(p: Vector2) -> void:
		Hand.injected_reach[hand.tracker] = p
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


## Holds both controllers in front of the head, `left` and `right` in head space, tops tipped toward the eye,
## then turned `turn` degrees about the vertical (180 points them back at the head) and rolled `roll` degrees.
func _hands(s: Dictionary) -> void:
	var head: Transform3D = main.rig.head.global_transform
	for side in ["left", "right"]:
		if not s.has(side):
			continue
		var hand: Hand = main.rig.left if side == "left" else main.rig.right
		var at: Vector3 = head * Vector3(s[side][0], s[side][1], s[side][2])
		var fwd := -head.basis.z
		var b := Basis.looking_at(fwd, Vector3.UP).rotated(head.basis.x, deg_to_rad(s.get("tip", 35.0)))
		b = Basis(Vector3.UP, deg_to_rad(s.get("turn", 0.0))) * b
		hand.global_transform = Transform3D(b * Basis(Vector3.BACK, deg_to_rad(s.get("roll", 0.0))), at)
		hand.held_still = true
	await get_tree().process_frame


## Plays both hands through a script in the picture book's form (Lessons.PAGES: `keys` posing each hand in head space
## as the head stands when it begins, `press` holding actions, over `length` seconds), as a player's controllers would,
## then lets go of everything it held. A hand's key may point it `toward` a spot in place of an `aim`: [right, up, ahead]
## metres from the ground under the head, as "relative" builds are placed, so it meets them however high the head is.
## "capture" saves the view at each of the `shots` seconds given; `tools` hands each hand that tool first.
func _gesture(s: Dictionary) -> void:
	for side in s.get("tools", {}):
		(main.rig.left if side == "left" else main.rig.right).tool = Lessons.tool(s.tools[side])
	var head: Transform3D = main.rig.head.global_transform
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var ground := Terrain.ground(head.origin.x, head.origin.z)
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
	while t <= s.length:
		for side in Lessons.hands(s):
			var hand: Hand = main.rig.left if side == "left" else main.rig.right
			hand.held_still = true
			hand.global_transform = head * Lessons.frame(Lessons.pose(s, side, t))
		for p in s.press:
			var key := "%s_hand/%s" % [p.hand, Controls.input(p.action, p.hand + "_hand")]
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
		Buttons.injected.erase("%s_hand/%s" % [p.hand, Controls.input(p.action, p.hand + "_hand")])
	await _frames(2)


## Holds `hand` beside the head, holding `tool`, pointing at `at` in the garden.
func _point(s: Dictionary) -> void:
	var hand := _holding(s, Hand.Tool[s.tool.to_upper()])
	var head: Transform3D = main.rig.head.global_transform
	var from := head * Vector3(0.18 if s.get("hand", "right") == "right" else -0.18, -0.25, -0.3)
	var at := Vector3(s.at[0], s.at[1], s.at[2])
	hand.global_transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)
	hand.held_still = true
	await _frames(2)


func _frames(n: int) -> void:
	for f in n:
		await get_tree().process_frame


func _hand(s: Dictionary) -> Hand:
	return main.rig.left if s.get("hand", "right") == "left" else main.rig.right


## The step's hand, handed `tool` first, as a player picks it before using it.
func _holding(s: Dictionary, tool: Hand.Tool) -> Hand:
	var hand := _hand(s)
	hand.tool = tool
	return hand


func _place(s: Dictionary) -> void:
	main.rig.place(_spot(s, s.x, s.z), s.get("lift", 0.0))


func _teleport(s: Dictionary) -> void:
	main.rig.teleport(_spot(s, s.x, s.z), s.get("lift", 0.0))
	await get_tree().create_timer(s.get("seconds", 2.0)).timeout


## Shows or hides the gaze marker and logs the gaze pose for `seconds`.
func _gaze(s: Dictionary) -> void:
	var gaze: Gaze = main.rig.gaze
	gaze.show_marker(s.get("on", true))
	var t := 0.0
	while t < s.get("seconds", 0.0):
		print("gaze: tracked ", gaze.get_has_tracking_data(), " ", gaze.global_transform)
		await get_tree().create_timer(0.5).timeout
		t += 0.5


static func aim_pose(head: Transform3D, dir: Array) -> Transform3D:
	var along: Vector3 = head.basis * Vector3(dir[0], dir[1], dir[2])
	return Transform3D(Basis.looking_at(along, Vector3.UP), head * Vector3(-0.2, -0.35, -0.25))


## Teleports as a player does with any tool: the left hand points beside the head along `dir` (relative
## to the head's facing) with its stick pushed `stick` forward for `seconds`, optionally captures the aimed view, from
## the `watch` pose (a `view` step's keys) if given, then lets go.
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
	if s.has("capture"):
		await main.capture(s.capture)
	Hand.injected_sticks.erase(rig.left.tracker)
	await get_tree().create_timer(s.get("settle", 2.0)).timeout


func _wall(s: Dictionary) -> void:
	_lay_plaster(s)
	await _stroke(s, Hand.Tool.WALLS)


## Walls and houses a step lays are plaster with `plaster`, else stone, as if the style tool had last turned a face to it.
func _lay_plaster(s: Dictionary) -> void:
	main.tool.plaster = s.get("plaster", false)
	main.tool.timber_style = int(s.get("timber_style", 0))


func _fence(s: Dictionary) -> void:
	await _stroke(s, Hand.Tool.FENCE)


## With `capture`, saves the view `capture_at` of the way through the stroke, the wall half drawn.
func _stroke(s: Dictionary, held: Hand.Tool) -> void:
	var tool: WallTool = main.tool
	var m := tool.mason(_holding(s, held))
	var path := _path(s)
	var first := _target(s, path[0])
	tool.begin_stroke(m, first.point, first.on)
	var frames := maxi(1, ceili(s.get("seconds", 2.0) * 60.0))
	var shot := ceili(frames * s.get("capture_at", 0.6)) if s.has("capture") else -1
	for f in frames:
		await get_tree().process_frame
		tool.extend_stroke(m, _along(path, float(f + 1) / frames))
		if f == shot:
			await main.capture(s.capture)
	tool.end_stroke(m)


## The house tool's trigger: a square house put up at `at`, `size` [along, across], its front turned `turn` degrees
## from the x axis (the head's right with "relative"), raised `rise` metres on its plinth; with "round", the tower
## tool's, a round tower `size` [across, across]. Put up at `from` (default `at`) turned `turn_from` (default `turn`), a
## grip then carries it there over `seconds`, raising it as it goes; else "seconds" waits that long after. With "capture",
## `shots` views named after it are saved at even steps of the carry, the last just before letting go.
func _house(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var round: bool = s.get("round", false)
	_holding(s, Hand.Tool.TOWER if round else Hand.Tool.HOUSE)
	_lay_plaster(s)
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
	tool.build([tool.new_house(put, PackedInt32Array([on]) if on >= 0 else PackedInt32Array())])
	if not carried:
		await get_tree().create_timer(s.get("seconds", 0.0)).timeout
		return
	for f in 600:
		if tool.walls.size() > count:
			break
		await get_tree().process_frame
	if tool.walls.size() == count:
		push_error("driver: the house put up at %s never stood" % put.center)
		return
	tool.take_build(tool.walls[-1])
	var start: Dictionary = tool.held_at.duplicate()
	var frames := maxi(1, ceili(s.get("seconds", 2.0) * 60.0))
	var shots: int = s.get("shots", 3) if s.has("capture") else 0
	var taken := 0
	for f in frames:
		await get_tree().process_frame
		var k := float(f + 1) / frames
		var to := start.duplicate()
		to.center = start.center.lerp(at.center, k)
		to.yaw = lerp_angle(start.yaw, at.yaw, k)
		to.rise = snappedf(at.rise * k, WallLayout.COURSE)
		tool.stand_build(to)
		if taken < shots and f + 1 >= frames * (taken + 1) / shots:
			taken += 1
			await get_tree().create_timer(0.4).timeout
			await main.capture("%s-%d" % [s.capture, taken])
	if tool.held != null:
		tool.end_build()


## Holds the built house `index` (or under `at`) as hands would and over `seconds` moves it by `move` [x, z] metres,
## turns it `turn` degrees, sizes it to `size` [along its ridge, across it] (a tower to `size[0]` across), raises it
## `rise` metres onto its plinth, its walls to `height` and its roof to `pitch`, `curve` and `overhang`; then lets go.
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
	for k in ["rise", "height", "pitch", "curve", "overhang"]:
		end[k] = s.get(k, start[k])
	var frames := maxi(1, ceili(s.get("seconds", 1.0) * 60.0))
	for f in frames:
		await get_tree().process_frame
		var k := float(f + 1) / frames
		var to := start.duplicate()
		to.center = start.center.lerp(end.center, k)
		to.yaw = lerp_angle(start.yaw, end.yaw, k)
		to.size = start.size.lerp(end.size, k)
		for key in ["rise", "height", "pitch", "curve", "overhang"]:
			to[key] = lerpf(start[key], end[key], k)
		tool.stand_build(to)
	if tool.held != null:
		tool.end_build()


func _turn(s: Dictionary, x: float, z: float, degrees: float) -> float:
	var t := deg_to_rad(degrees)
	return WallTool.angle(_spot(s, x + cos(t), z + sin(t)) - _spot(s, x, z))


## Shapes the roof of build `index`: its `pitch` and `curve` as a grip pulls them, its eaves `overhang` metres past the
## walls, its `deck` ("stone" or "wood") and its `dormers`, each [metres along the ridge, across it].
func _roof(s: Dictionary) -> void:
	var w: Wall = main.tool.walls[s.index]
	var r := w.roof
	r.pitch = RoofLayout.snap_pitch(s.get("pitch", r.pitch), WallTool.ROOF_STEP)
	r.curve = clampf(s.get("curve", r.curve), -RoofLayout.CURVE, RoofLayout.CURVE)
	r.overhang = clampf(snappedf(s.get("overhang", r.overhang), WallTool.ROOF_STEP), 0.0, r.reach())
	var roof := {"pitch": r.pitch, "curve": r.curve, "overhang": r.overhang}
	if s.has("deck"):
		roof["deck"] = int(RoofLayout.Deck[s.deck.to_upper()])
	if s.has("dormers"):
		roof["dormers"] = PackedVector2Array(s.dormers.map(func(d: Array) -> Vector2: return Vector2(d[0], d[1])))
	main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"roof": roof}})


func _top(s: Dictionary) -> void:
	var w: Wall = main.tool.walls[s.index]
	if w.roof == null or w.roof.flat():
		main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"top": int(WallLayout.Top[s.style.to_upper()])}})


## Turns the gable ends of the house `index` (or under `at`) to `style`: wall, boards or steps.
func _gable(s: Dictionary) -> void:
	main.world.submit({"op": "reshape", "of": "walls", "id": _wall_of(s).id, "data": {"gable_end": int(WallLayout.GableEnd[s.style.to_upper()])}})


## With `gable` (wall, boards or steps), houses laid after take that style of gable end.
func _lay_gables(s: Dictionary) -> void:
	if s.has("gable"):
		main.tool.gable_end = WallLayout.GableEnd[s.gable.to_upper()]


func _lift_wall(s: Dictionary) -> void:
	var w := _wall_of(s)
	main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"height": float(s.height)}})


## Holds wall `index` (or the one under `at`), a house too, as two hands would, and draws them `metres` apart upright
## then back `times` times, `seconds` a pull: its height, or with "roof" a house's ridge.
func _grip(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var w := _wall_of(s)
	var frames := maxi(1, ceili(s.get("seconds", 1.0) * 60.0))
	for n in int(s.get("times", 1)):
		var metres: float = s.get("metres", 1.0) * (1.0 if n % 2 == 0 else -1.0)
		tool.take_build(w)
		var start: Dictionary = tool.held_at.duplicate()
		for f in frames:
			await get_tree().process_frame
			var up := metres * smoothstep(0.0, 1.0, float(f + 1) / frames)
			var to := start.duplicate()
			if s.get("roof", false):
				to.pitch = RoofLayout.snap_pitch(start.pitch + up, WallTool.ROOF_STEP)
			else:
				to.height = maxf(start.height + snappedf(up, WallLayout.COURSE), WallLayout.MIN_HEIGHT)
			tool.stand_build(to)
		if tool.held != null:
			tool.end_build()
		await _standing()


## Grips the meadow's tree `tree`, or with `x`, `z` the tree standing nearest there, near its top with both hands 2 m
## apart, as two hands do, and spreads them `metres` farther over `seconds` (negative closes them), sizing it by their
## span; "capture" saves the view at the end of the pull.
func _grow(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var flora: Flora = main.flora_tool.flora
	var trunk: Flora.Plant
	if s.has("tree"):
		trunk = flora.groups[0][flora.meadow_trees()[s.tree]]
	else:
		var spot := Vector3(s.x, 0.0, s.z)
		for parts in flora.solids():
			var p: Flora.Plant = parts[0]
			if p.pool == flora.trunks and (trunk == null or Vector3(p.anchor.x, 0, p.anchor.z).distance_to(spot) < Vector3(trunk.anchor.x, 0, trunk.anchor.z).distance_to(spot)):
				trunk = p
	var at := trunk.foot() + Vector3.UP * flora.top_of(trunk) * 0.8
	var mid: Vector3 = at + Vector3.BACK * 2.0
	var right := tool.mason(main.rig.right)
	var left := tool.mason(main.rig.left)
	for m: WallTool.Mason in [right, left]:
		m.hand.global_position = mid + Vector3.RIGHT * (1.0 if m == right else -1.0)
		tool.begin_grow(m, trunk, m.hand.global_transform, at)
	var frames := maxi(1, ceili(s.get("seconds", 1.0) * 60.0))
	for f in frames:
		await get_tree().process_frame
		var half: float = 1.0 + s.metres * 0.5 * smoothstep(0.0, 1.0, float(f + 1) / frames)
		tool.drag_pair(left, mid + Vector3.RIGHT * half, mid + Vector3.LEFT * half)
	if s.has("capture"):
		await main.capture(s.capture)
	tool.end_grow(left)
	tool.end_grow(right)


## Grips the boulder placed `boulder` before the last (0 the last) from `reach` metres off (1.5 without), as a hand
## does, and over `seconds` moves the hand by `move` [x, y, z] metres while turning it by `turn` [x, y, z] degrees,
## then lets go; "capture" saves the view before letting go.
func _carry(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var ids: Array = main.world.state.boulders.keys()
	var b: Boulders.Boulder = main.boulders.find(ids[ids.size() - 1 - int(s.get("boulder", 0))])
	var m := tool.mason(_hand(s))
	var from := Transform3D(Basis(), b.position + Vector3.BACK * (b.shape.reach() * b.size + s.get("reach", 1.5)))
	var rock: Dictionary = main.boulders.pick(from.origin, -from.basis.z)
	tool.begin_grow(m, b, from, rock.get("point", b.position))
	var move: Array = s.get("move", [0, 0, 0])
	var turn: Array = s.get("turn", [0, 0, 0])
	var frames := maxi(1, ceili(s.get("seconds", 1.0) * 60.0))
	for f in frames:
		await get_tree().process_frame
		var k := smoothstep(0.0, 1.0, float(f + 1) / frames)
		var basis := Basis.from_euler(Vector3(deg_to_rad(turn[0]), deg_to_rad(turn[1]), deg_to_rad(turn[2])) * k)
		m.sizing.follow.call(m, Transform3D(basis, from.origin + Vector3(move[0], move[1], move[2]) * k))
	if s.has("capture"):
		await main.capture(s.capture)
	tool.end_grow(m)


## Grips the boulder placed `boulder` before the last (0 the last) with both hands, as two hands do, and over `seconds`
## spreads them from `from` metres apart to `to`, sizing it by their span, then lets go; with `follow` [x, y, z] the view
## looks at it from that offset times its size, so it holds the frame as it grows.
func _spread(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var ids: Array = main.world.state.boulders.keys()
	var b: Boulders.Boulder = main.boulders.find(ids[ids.size() - 1 - int(s.get("boulder", 0))])
	var right := tool.mason(main.rig.right)
	var left := tool.mason(main.rig.left)
	var mid := b.position + Vector3.BACK * (b.shape.reach() * b.size + 1.5)
	var from: float = s.get("from", 0.6)
	var to: float = s.to
	for m: WallTool.Mason in [right, left]:
		m.hand.global_position = mid + Vector3.RIGHT * from * (0.5 if m == right else -0.5)
		tool.begin_grow(m, b, m.hand.global_transform, b.position)
	var frames := maxi(1, ceili(s.get("seconds", 1.0) * 60.0))
	for f in frames:
		await get_tree().process_frame
		var span := from * pow(to / from, smoothstep(0.0, 1.0, float(f + 1) / frames))
		tool.drag_pair(left, mid + Vector3.RIGHT * span * 0.5, mid + Vector3.LEFT * span * 0.5)
		if s.has("follow"):
			var at := b.position + Vector3.UP * b.shape.axes.y * b.size * 0.5
			main.view(at + Lessons._v(s.follow) * b.size, at, false)
	tool.end_grow(left)
	tool.end_grow(right)


## Every wall standing now again, shifted by `offset` [x, z], one each `every` seconds, applied as the host's commands
## reach a visitor: checked, then played.
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
		var cmd := Commands.clean({"op": "wall", "ids": PackedInt32Array([id]), "walls": [w], "seq": world.seq + 1, "by": 0}, world.state, true)
		assert(not cmd.is_empty(), "arrive: the shifted wall is not a command a visitor would apply")
		world.seq = cmd.seq
		world._timed(cmd)
		id += 1
		await get_tree().create_timer(s.get("every", 0.5)).timeout


## The wall a step names: by `index` in build order, or the one under the ground point `at` [x, z].
func _wall_of(s: Dictionary) -> Wall:
	if s.has("at"):
		return main.tool.pick_building(_spot(s, s.at[0], s.at[1]) + Vector3.UP * 2.0, Vector3.DOWN).wall
	return main.tool.walls[s.index]


## A press of the windows or decorations tool on wall `index` (-1 the last drawn), as `FittingTool.aim`
## would find it: `what` is opening, lantern, flag, chimney, dormer or tower_flag; `s` and `y` place it on the wall,
## `style` and `size` shape an opening, `side` picks a lantern's face, `at` a chimney's or dormer's spot along and across the ridge.
## A decoration with `from` is aimed as the hand would from there toward `at`, turned `turn` degrees if given: furniture
## on a floor or a flat roof.
func _fit(s: Dictionary) -> void:
	if s.what == "decoration":
		var w: Wall = main.tool.walls[s.index] if s.has("index") else null
		var at := w.layout.point_at(float(s.get("s", 0.0))) if w != null else Vector3(float(s.get("x", 0.0)), 0, float(s.get("z", 0.0)))
		var target := {"what": "decoration", "wall": w, "point": at, "s": float(s.get("s", 0.0)), "side": float(s.get("side", 1.0)), "turn": float(s.get("turn", 0.0))}
		if s.has("from"):
			var eye := Vector3(s.from[0], s.from[1], s.from[2])
			target = main.fitting_tool.aim(Hand.Tool.DECORATIONS, eye, (Vector3(s.at[0], s.at[1], s.at[2]) - eye).normalized())
			if s.has("turn"):
				target.turn = deg_to_rad(s.turn)
		if s.has("style"):
			target.style = int(s.style)
		main.fitting_tool.fit(target)
		return
	var target := {"what": s.what, "wall": main.tool.walls[s.index], "s": s.get("s", 0.0), "y": s.get("y", 0.0), "style": s.get("style", WallLayout.DoorStyle.PLAIN), "size": s.get("size", 1.0), "side": s.get("side", 1.0)}
	if s.has("at"):
		target.at = Vector2(s.at[0], s.at[1])
	main.fitting_tool.fit(target)


## A stroke of `tool` along `points`; stone in `style` (StoneStyles' index) when given, as if the style wheel last let go there.
func _paint(s: Dictionary) -> void:
	if s.has("style"):
		Ground.style = s.style
	var flora_tool: FloraTool = main.flora_tool
	var b := flora_tool.brush(main.rig.left if s.get("hand", "left") == "left" else main.rig.right)
	b.hand.tool = Hand.Tool[s.tool.to_upper()]
	if s.has("tree") and b.hand.tool == Hand.Tool.MOSS:
		var flora := flora_tool.flora
		var trees := flora.placed("tree")
		flora_tool.coat_tree(trees[int(s.tree)][0], b.hand)
		return
	var path := _path(s)
	b.meadow = FloraTool.paints_meadow(b.hand.tool, _along(path, 0.0))
	var t := 0.0
	var seconds: float = s.get("seconds", 2.0)
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		flora_tool.paint(b, _along(path, minf(t / seconds, 1.0)), s.radius, dt)
	flora_tool.end_stroke(b)


## A stroke of the path tool from `hand` (left by default); `radius` is half the path's width.
func _pave(s: Dictionary) -> void:
	var flora_tool: FloraTool = main.flora_tool
	var b := flora_tool.brush(main.rig.left if s.get("hand", "left") == "left" else main.rig.right)
	b.hand.tool = Hand.Tool.DIRT_PATH
	var path := _path(s)
	var mid := path[0].lerp(path[-1], 0.5)
	for i in path.size():
		path[i] = Terrain.ground(lerpf(mid.x, path[i].x, _area), lerpf(mid.z, path[i].z, _area))
	flora_tool.begin_path(b, path[0], s.radius)
	var frames := maxi(1, ceili(s.get("seconds", 2.0) * 60.0))
	for f in frames:
		await get_tree().process_frame
		flora_tool.extend_path(_along(path, float(f + 1) / frames), s.radius)
		if s.has("capture") and f == int(frames * s.get("capture_at", 0.5)):
			await get_tree().create_timer(0.2).timeout
			await main.capture(s.capture)
	flora_tool.end_path(b)


## Grabs the ground at x, z and pulls it `lift` metres over `seconds` (negative digs), as a grip on the ground does.
func _sculpt(s: Dictionary) -> void:
	var tool: GroundGrab = main.ground_grab
	var hand := _hand(s)
	tool.begin(hand, _spot(s, s.x, s.z), s.get("radius", GroundGrab.MIN_RADIUS))
	var t := 0.0
	var seconds: float = s.get("seconds", 1.0)
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		tool.pull(hand, s.lift * smoothstep(0.0, 1.0, minf(t / seconds, 1.0)))
		tool.follow(hand, dt)
	tool.end_stroke(hand)


## Desktop only, where no hand is tracked: holds a hand `at` [x, height above the ground, z] for `seconds`, optionally capturing the view.
func _touch(s: Dictionary) -> void:
	main.flora_tool.stand_in = _spot(s, s.at[0], s.at[2]) + Vector3.UP * s.at[1]
	await get_tree().create_timer(s.get("seconds", 1.0)).timeout
	if s.has("capture"):
		await main.capture(s.capture)
	main.flora_tool.stand_in = Flora.NO_HAND


## Digs a hollow at x, z, deeper the more `seconds` (as a grip pressing the ground), and fills it to its brim
## (`Water.brim`), so the pond stays in it.
func _dig(s: Dictionary) -> void:
	var depth := clampf(0.7 * s.get("seconds", 1.5), 0.45, 1.3)
	var radius := maxf(2.8, depth * GroundGrab.SPREAD)
	await _sculpt({"x": s.x, "z": s.z, "lift": -depth, "radius": 2.8, "seconds": 0.3, "relative": s.get("relative", false), "hand": s.get("hand", "right")})
	await get_tree().process_frame
	await _pond({"x": s.x, "z": s.z, "brim": radius, "relative": s.get("relative", false), "hand": s.get("hand", "right")})


## Pulls the trigger of the pond tool pointed at the ground at x, z: the hollow beside it fills to that height. With
## `brim`, a hollow pressed at x, z out to that radius fills to its brim (`Water.brim`).
func _pond(s: Dictionary) -> void:
	var at := _spot(s, s.x, s.z)
	if s.has("brim"):
		at.y = Water.brim(at.x, at.z, s.brim)
	var hand := _hand(s)
	var was := hand.tool
	main.water_tool.fill(_holding(s, Hand.Tool.POND), at)
	await get_tree().process_frame
	await get_tree().process_frame
	hand.tool = was


## Sweeps the right hand along `points` at `y` metres above the pond at the first point, as if trailing it through.
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
		await get_tree().process_frame
		t += get_process_delta_time()
	main.rig.right.position = Vector3.ZERO


func _tree(s: Dictionary) -> void:
	main.flora_tool.place("tree", _spot(s, s.x, s.z), null, s.get("seed", randi()))


func _bush(s: Dictionary) -> void:
	main.flora_tool.place("bush", _spot(s, s.x, s.z), null, s.get("seed", randi()))


## Sets a boulder down at `x`, `z`, of shape `seed` (a new one without) and `scale` (1 without); in `style`
## (StoneStyles' index) when given, as if the style wheel last let go there.
func _boulder(s: Dictionary) -> void:
	if s.has("style"):
		Ground.style = s.style
	main.flora_tool.place_boulder(_spot(s, s.x, s.z), null, int(s.get("seed", randi())), float(s.get("scale", 1.0)))


## Points the delete tool straight down at a ground spot from `height` metres up and presses once: a tap.
func _delete(s: Dictionary) -> void:
	var tool: DeleteTool = main.delete_tool
	tool.press(self, _spot(s, s.x, s.z) + Vector3.UP * s.get("height", 2.0), Vector3.DOWN)
	tool.let_go(self)
	await get_tree().process_frame


## Holds the delete tool's trigger pointed along `dir` (relative to the head's facing; up at the sky by default) for
## `seconds`, saving the view as `capture` at `capture_at` seconds; let go short of DeleteTool.WIPE_HOLD, nothing wipes.
func _wipe(s: Dictionary) -> void:
	var tool: DeleteTool = main.delete_tool
	var d: Array = s.get("dir", [0, 2, -1])
	var t := 0.0
	var shot := not s.has("capture")
	while t < s.seconds:
		var head: Transform3D = main.rig.head.global_transform
		if not tool.charge(self, head * Vector3(0.2, -0.3, -0.3), head.basis * Vector3(d[0], d[1], d[2]), get_process_delta_time()):
			break
		if not shot and t >= s.get("capture_at", 0.0):
			shot = true
			await main.capture(s.capture)
		await get_tree().process_frame
		t += get_process_delta_time()
	tool.cancel(self)
	await get_tree().process_frame


## Holds the delete tool's trigger, pointing straight down from `height` metres over each point of `points` in turn
## across `seconds`, then lets go: along a wall it erases, over the ground it mows. With `index` instead, it sweeps
## that wall in build order from fraction `from` of its length to `to`, wherever the head stands.
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
			point.y = Terrain.height_at(point.x, point.z)
			tool.hold(self, point + up, Vector3.DOWN)
			await get_tree().process_frame
			t += get_process_delta_time()
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


## Fills a disc at once with parallel walls (see StressLayout) of one height, their ivy fully grown.
func _stress(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var m := tool.mason(_holding(s, Hand.Tool.FENCE if s.get("fence", false) else Hand.Tool.WALLS))
	_lay_plaster(s)
	var rows := StressLayout.walls(s.radius, s.spacing / sqrt(_area))
	var start := Time.get_ticks_usec()
	for row in rows:
		tool.begin_stroke(m, Terrain.ground(row[0].x, row[0].y))
		for i in range(1, row.size()):
			tool.extend_stroke(m, Terrain.ground(row[i].x, row[i].y))
		var before := tool.walls.size()
		tool.end_stroke(m)
		for w in tool.walls.slice(before):
			main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"height": float(s.height)}})
			w.ivy_age = INF
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	var stones := 0
	for w in tool.walls:
		stones += w.layout.stones.size()
	print("stress: %d walls, %.0f m, %d stones, laid in %.0f ms" % [tool.walls.size(), StressLayout.length(rows), stones, ms])


## Hangs a lantern every `every` metres along each wall within `radius` of the centre, alternating faces.
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


## Fills every painted and placed flora pool to capacity within `radius` of `at` (x, z; the centre by default), or only those `pools` names
## (grass, flowers, trees, bushes), the trees taking each species in turn at `scale` (1 without). They are not build commands, so the frame budget
## does not count them.
func _fill_flora(s: Dictionary) -> void:
	var flora: Flora = main.flora_tool.flora
	var pools: Array = s.get("pools", ["grass", "flowers", "trees", "bushes", "moss"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var at: Array = s.get("at", [0, 0])
	var centre := Vector3(at[0], 0, at[1])
	for i in Flora.PAINTED_GRASS if "grass" in pools else 0:
		flora.add_grass(_scatter(rng, s.radius, centre), rng)
	for i in Flora.PAINTED_FLOWERS if "flowers" in pools else 0:
		flora.add_flower(_scatter(rng, s.radius, centre), rng)
	for i in Flora.PAINTED_MOSS if "moss" in pools else 0:
		flora.add_moss(_scatter(rng, s.radius, centre), rng)
	for i in Flora.PLACED_TREES if "trees" in pools else 0:
		var species := i % FloraLayout.Species.size()
		var parts := flora.add_tree(_scatter(rng, s.radius, centre), rng.randi(), species)
		if not parts.is_empty():
			flora.set_look(parts[0], species, clampf(s.get("scale", 1.0), FloraLayout.SCALES.x, FloraLayout.SCALES.y))
	for i in Flora.PLACED_BUSHES if "bushes" in pools else 0:
		flora.add_bush(_scatter(rng, s.radius, centre), rng)


## Measures distant flora in the same scene, off or on: the flowers' triangles and the grass the ground paints.
func _flora_far(s: Dictionary) -> void:
	var flora: Flora = main.flora_tool.flora
	var on: bool = s.get("mode", "on") != "off"
	for pool: Flora.Pool in [flora.flowers, flora.ghost_flowers]:
		pool.far_live.visible = on
	flora.ground_mat.set_shader_parameter(&"far_grass", on)

## Hides one of LAYERS, or shows it again, so a scene measures what it costs against the same view without it.
## Grass is every blade, the meadow's and painted; the ground paints its grass either way. Trees count their bushes,
## which share their crowns' material.
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


## Each [object, property, value hiding it] that hides `name`.
func _layer_parts(name: String) -> Array[Array]:
	var flora: Flora = main.flora_tool.flora
	var look: Look = main.look
	var out: Array[Array] = []
	var materials: Array[Material] = []
	match name:
		"terrain":
			materials = [flora.ground_mat]
		"grass":
			materials = [flora.grass_mat]
		"flowers":
			materials = [flora.flower_mat, flora.flower_far]
		"trees":
			materials = [flora.trunks.live.material_override, flora.foliage.live.material_override]
		"mountains":
			for n in look.get_children():
				if n is MeshInstance3D and n != look.disc:
					out.append([n, "visible", false])
		"sky":
			out.append([look.env, "background_mode", Environment.BG_COLOR])
		"sun_disc":
			out.append([look.disc, "visible", false])
		"sun":
			out.append([look.sun, "visible", false])
		"shadows":
			for step: Quality.Step in Quality.ladder:
				out.append([step, "shadows", false])
		"masonry":
			out.append([main.tool.masonry, "visible", false])
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
		"ceilings":
			for n: Node3D in main.get_tree().get_nodes_in_group(&"roof_ceilings"):
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


## Fills a disc at once with a grid of houses, `spacing` apart, every other one turned a quarter; with `storeys`,
## each stands that many high, with `wings`, a wing crosses each house, with `gable`, their gable ends take it, and
## with `thatch`, their roofs are thatched. With `roofs`, a list the houses take in turn, each house's roof is laid as
## its entry has it: `pitch` (0 flat), `deck` and `top` ("stone" or "wood"; a WallLayout.Top), `dormers` on each slope,
## `overhang`, and `storeys` high, each storey above the first `upper` times the size of the one under it.
func _village(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var start := Time.get_ticks_usec()
	var r: float = s.radius * sqrt(_area)
	var step: float = s.spacing
	_lay_gables(s)
	_lay_plaster(s)
	main.tool.thatch = s.get("thatch", false)
	var k := 0
	for z in range(-int(r / step), int(r / step) + 1):
		for x in range(-int(r / step), int(r / step) + 1):
			var c := Vector2(x, z) * step
			if c.length() > r - step * 0.5:
				continue
			k += 1
			var yaw := PI * 0.5 * (k % 2)
			var at := Terrain.ground(c.x, c.y)
			var on := PackedInt32Array()
			var entry: Dictionary = s.roofs[k % s.roofs.size()] if s.has("roofs") else {}
			var size := Vector2(0.7, 0.44) * step
			for storey in int(entry.get("storeys", s.get("storeys", 1))):
				var stance := WallTool.stance(at, yaw)
				stance.size = size
				stance.height = s.get("height", WallTool.HOUSE_HEIGHT)
				stance.curve = s.get("curve", 0.0)
				stance.pitch = entry.get("pitch", s.get("pitch", WallTool.pitch_for(stance)))
				var house := tool.new_house(stance, on)
				_dress_roof(house, entry, size)
				tool.build([house])
				size *= entry.get("upper", 1.0)
				tool.walls[-1].ivy_age = INF
				on = PackedInt32Array([tool.walls[-1].id])
			if s.get("wings", false):
				var wing := at + Vector3.RIGHT.rotated(Vector3.UP, yaw) * step * 0.2
				wing = Terrain.ground(wing.x, wing.z)
				var wing_at := WallTool.stance(wing, yaw)
				wing_at.size = Vector2(0.3, 0.6) * step
				wing_at.curve = s.get("curve", 0.0)
				wing_at.pitch = s.get("pitch", WallTool.pitch_for(wing_at))
				tool.build([tool.new_house(wing_at)])
				tool.walls[-1].ivy_age = INF
	print("village: %d buildings in %.0f ms" % [k, (Time.get_ticks_usec() - start) / 1000.0])


## Lays `house`'s roof and top, `size` [along, across], as a village's `roofs` entry has them.
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
		main.world.submit({"op": "unwall", "ids": PackedInt32Array([w.id])})
	await get_tree().process_frame


static func _scatter(rng: RandomNumberGenerator, radius: float, centre := Vector3.ZERO) -> Vector3:
	return FloraLayout.brush(centre, radius, 1, rng, Terrain.height_at)[0]


## The port of the garden a script visits: its `port`, else the --host-port launch argument.
func _host_port(s: Dictionary) -> int:
	return int(s.get("port", main.args.get("host-port", Session.PORT)))


## Joins the garden hosted at `address` on the host's port, as picking its figure does, until that garden has arrived.
func _join(s: Dictionary) -> void:
	var arrived := _arrival()
	main.session.join(s.get("address", "127.0.0.1"), _host_port(s))
	await _arrived(arrived)


## Set once the next garden arrives, so a step after a visit works in the garden visited, however late it comes.
func _arrival() -> Array:
	var arrived := [false]
	main.world.loaded.connect(func() -> void:
		if main.session.visiting.is_empty():
			push_error("driver: went home instead of arriving")
		else:
			arrived[0] = true, CONNECT_ONE_SHOT)
	return arrived


func _arrived(arrived: Array) -> void:
	while not arrived[0]:
		await get_tree().process_frame


## Joins through the same wheel sweep and release as a player.
func _visit(s: Dictionary) -> void:
	var home: bool = s.get("home", false)
	var arrived := [true] if home else _arrival()
	var key := "home"
	if not home:
		var keys: Array = main.session.nearby.keys().filter(func(x: String) -> bool: return x.ends_with(":%d" % _host_port(s)))
		assert(not keys.is_empty(), "the requested garden has not been discovered")
		key = "join:" + str(keys[0])
	await _pick({"action": key})
	await _arrived(arrived)


## Flat mode: holds the flat-screen control `action` (see Controls.FLAT) for `seconds`, and at least two frames so a slow
## frame cannot swallow the press, as its key or button would.
func _flat(s: Dictionary) -> void:
	var action: String = "flat_" + s.action
	Input.action_press(action)
	await _frames(2)
	await get_tree().create_timer(s.get("seconds", 0.1)).timeout
	Input.action_release(action)
	await _frames(2)


## Turns the view to `at`, or to the figure of the host's garden with "figure", or to the eyes of the first other
## player with "player".
func _face(s: Dictionary) -> void:
	var to: Vector3
	if s.get("player", false):
		to = (main.session.avatars.values()[0] as Avatar).eyes.origin
	else:
		to = Vector3(s.at[0], s.at[1], s.at[2])
	main.view(main.rig.head.global_position, to, false)
	await _frames(2)


## Waits until the garden has applied command `seq`, `players` share it, `worn` of them show their own avatar files,
## `previewed` avatar files (this player's own included) stand ready for the picker, `swimming` fish have come, with `fed`
## something eats from a held dish (`Main.fed`: "hand" this player's, "dish" another player's as shown here), the
## `digests` named have been written to the capture directory (by any player), or with "heard" the host's beacon is
## heard, for at most `seconds`. Without `seconds` the wait has no limit: how long another player takes to start and
## catch up is the machine's load, not the script's.
func _until(s: Dictionary) -> void:
	var dir := str(main.args.get("capture-dir", "user://captures"))
	var t := 0.0
	_waiting = s
	while t < s.get("seconds", INF):
		var w: World = main.world
		var worn: int = main.session.avatars.values().filter(func(a: Avatar) -> bool: return a.source != "").size()
		var digested: bool = s.get("digests", []).all(func(n: String) -> bool: return FileAccess.file_exists(dir.path_join(n + ".json")))
		var selected: bool = not s.has("avatar") or (main.session.avatar == s.avatar and worn == 0 and main.session._looks.values().all(func(v: Array) -> bool: return v[0] == int(s.avatar)))
		if selected and w.seq >= s.get("seq", 0) and main.session.players() >= s.get("players", 0) and worn >= s.get("worn", 0) and main.session.previews.values().filter(func(p: PackedScene) -> bool: return p != null).size() >= s.get("previewed", 0) and main.fish.swimming.size() >= s.get("swimming", 0) and (not s.has("fed") or main.fed(s.fed == "dish") > 0) and digested and (not s.get("heard", false) or main.session.nearby.keys().any(func(k: String) -> bool: return k.ends_with(":%d" % _host_port(s)))):
			_waiting = {}
			return
		await get_tree().process_frame
		t += get_process_delta_time()
	_waiting = {}
	push_error("driver: until %s timed out" % s)


## Writes `World.digest`, where the sun stands, how many other players' avatars stand here and the hashes of their own files, and how many eat from held dishes, to `name`.json in the capture
## directory, for comparing machines.
func _digest(s: Dictionary) -> void:
	var path: String = str(main.args.get("capture-dir", "user://captures")).path_join(s.name + ".json")
	var out: Dictionary = main.world.digest()
	if s.get("ground", false):
		var h: Vector3 = main.rig.head.global_position
		out.ground = {"feet": main.rig.global_position.y, "terrain": Terrain.height_at(h.x, h.z), "head": h.y, "x": h.x, "z": h.z}
	out.sun = main.look.time
	out.avatars = main.session.avatars.values().filter(func(a: Avatar) -> bool: return a.visible).size()
	out.avatar_choices = main.session._looks.values().map(func(v: Array) -> int: return v[0])
	out.avatar_choices.append(main.session.avatar)
	out.avatar_choices.sort()
	out.worn = main.session.avatars.values().map(func(a: Avatar) -> String: return a.source).filter(func(k: String) -> bool: return k != "")
	out.fed = {"hand": main.fed(false), "dish": main.fed(true)}
	out.handfuls = main.feed_tool.handfuls.filter(func(h: Handful) -> bool: return h.landed()).map(func(h: Handful) -> Array: return [h.position.x, h.position.y, h.position.z])
	out.frenzy = main.fish.frenzy()
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(out, " ", true))
	print("driver: digest ", path)


## Samples a connected, settled session; ENet counters exclude discovery and IP/UDP headers.
## Frame processing time is Godot's elapsed main-thread time, not whole-process CPU usage.
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
	var path: String = str(main.args.get("capture-dir", "user://captures")).path_join(s.name + ".json")
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(out, " ", true))
	print("driver: network sample ", path)


## Takes a photo with the camera in `hand` (right by default), or with `tool` "selfie" the selfie camera, wherever its lens
## points, as pulling its trigger does, and waits until it is saved. With "view", the same lens's view as the headset draws it is captured
## first under that name, to set beside the photo.
func _photo(s: Dictionary) -> void:
	var hand := _holding(s, Hand.Tool[str(s.get("tool", "camera")).to_upper()])
	if s.has("view"):
		await main.capture(s.view, false, PhotoTool.lens(hand))
	await main.photo_tool.shoot(hand)


## Throws a handful of seeds from the dish in `hand` (right by default), or from `from` ([x, height over the ground, z]),
## at `velocity`, as pulling its trigger while swinging the hand at `velocity` does.
func _toss(s: Dictionary) -> void:
	var a: Array = s.get("velocity", [0, 0, 0])
	var v := Vector3(a[0], a[1], a[2])
	var f: Array = s.get("from", [])
	if f.size() == 3:
		main.feed_tool.throw(Vector3(f[0], f[1] + Terrain.height_at(f[0], f[2]), f[2]), v)
		return
	var hand := _holding(s, Hand.Tool.SEEDS)
	main.feed_tool.throw(main.feed_tool.dish(hand), main.feed_tool.launch(hand, v))


## Turns the sky as a player does, until the sun stands at `time` (0 dawn, 1 dusk) over `seconds`: `hand`
## (right by default) beside the head grips open sky high off the sun's arc and turns its aim about the arc.
func _sun(s: Dictionary) -> void:
	var hand := _hand(s)
	var was := hand.global_transform
	var still := hand.held_still
	var axis := Daylight.RISE.cross(Daylight.ARC_UP)
	var grab := Daylight.toward_sun(0.5).rotated(Daylight.RISE, 0.25)
	var turn := Daylight.angle(s.time) - Daylight.angle(main.look.time)
	var head: Transform3D = main.rig.head.global_transform
	hand.held_still = true
	hand.global_transform = Transform3D(Basis.looking_at(grab), head * Vector3(0.18 if hand == main.rig.right else -0.18, -0.25, -0.3))
	var grip := "%s/%s" % [hand.tracker, Controls.input("grab", hand.tracker)]
	Buttons.injected[grip] = true
	await _frames(2)
	var seconds: float = s.get("seconds", 2.0)
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += minf(get_process_delta_time(), seconds / 8.0)
		hand.global_basis = Basis.looking_at(grab.rotated(axis, turn * smoothstep(0.0, 1.0, minf(t / seconds, 1.0))))
	await _frames(2)
	Buttons.injected.erase(grip)
	await _frames(2)
	hand.global_transform = was
	hand.held_still = still


## The colour picker aimed from `from` (the head by default) at `at`, each [x, height above the ground, z], which must
## land on `element` (meadow, stone, roof, wood or plaster; the meadow needs no aim): opens its wheel on `hand`, twists
## to `swatch` over `seconds`, optionally captures the view with the wheel open, then lets go.
func _colour(s: Dictionary) -> void:
	var tool: PaletteTool = main.palette_tool
	var element: Palette.Element = Palette.Element[s.element.to_upper()]
	var target := tool.colour_target(element, Vector3.ZERO)
	if s.has("at"):
		target = tool.aim(_dial_from(s), _dial_dir(s))
	if target.get("element") != element:
		push_error("driver: colour aimed at %s, not %s" % [target, s.element])
		return
	await _dial(s, _holding(s, Hand.Tool.COLOUR), target, s.swatch)


## The style tool's trigger held on what it finds from `from` toward `at`, as `PaletteTool.aim_style` does
## (`restyle` names what that must be: gable, roof, top, face, rail or tree), twisted round to choice `pick` over
## `seconds` and let go, as `colour` does.
## With `tree`, it is aimed instead at the meadow's own tree of that number, across its crown from `side` metres away.
func _style(s: Dictionary) -> void:
	var tool: PaletteTool = main.palette_tool
	var target := tool.aim_style(_dial_from(s), _dial_dir(s)) if not s.has("tree") else {}
	if s.has("tree"):
		var flora: Flora = main.flora_tool.flora
		var trunk: Flora.Plant = flora.groups[0][flora.meadow_trees()[s.tree]]
		var crown := trunk.foot() + Vector3.UP * 2.5
		var from := crown + Vector3(0, 1, s.get("side", 6.0))
		target = tool.aim_style(from, (crown - from).normalized())
	if target.get("restyle") != PaletteTool.Restyle[s.restyle.to_upper()]:
		push_error("driver: style aimed at %s, not %s" % [target, s.restyle])
		return
	await _dial(s, _holding(s, Hand.Tool.STYLE), target, s.pick)


func _dial_from(s: Dictionary) -> Vector3:
	return _spot(s, s.from[0], s.from[2]) + Vector3.UP * s.from[1] if s.has("from") else main.rig.head.global_position


func _dial_dir(s: Dictionary) -> Vector3:
	return (_spot(s, s.at[0], s.at[2]) + Vector3.UP * s.at[1] - _dial_from(s)).normalized()


func _dial(s: Dictionary, hand: Hand, target: Dictionary, to: int) -> void:
	var tool: PaletteTool = main.palette_tool
	tool.open(hand, target)
	var from: int = tool.wheels[hand].start
	var turn := (to - from) * Palette.TWIST_STEP
	var t := 0.0
	var seconds: float = s.get("seconds", 1.0)
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		tool.twist(hand, turn * minf(t / seconds, 1.0))
	if s.has("capture"):
		await main.capture(s.capture)
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
	main.view(_eye, _at, false)
	await get_tree().process_frame


## Moves the view from the last `view` or `glide` to this one's `eye` and `at` over `seconds`, easing in and out.
func _glide(s: Dictionary) -> void:
	var pose := _pose(s)
	if pose.is_empty():
		return
	var from: Array[Vector3] = [_eye, _at]
	var seconds: float = s.seconds
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, minf(t / seconds, 1.0))
		_eye = from[0].lerp(pose[0], k)
		_at = from[1].lerp(pose[1], k)
		main.view(_eye, _at, false)


## A step's `eye` and `at`. With "subject", they are in the frame of the first node in that group (or its
## `index`th), as it stands now. With "ground", their heights count from the ground under each. With "toward",
## `at` is offset from the node in that group nearest the eye, so a view can turn to an animal that has moved
## without the eye moving.
func _pose(s: Dictionary) -> Array[Vector3]:
	var eye := Vector3(s.eye[0], s.eye[1], s.eye[2])
	var at := Vector3(s.at[0], s.at[1], s.at[2])
	if s.has("subject"):
		var found := get_tree().get_nodes_in_group(s.subject)
		if found.is_empty():
			push_error("driver: nothing in %s to view" % s.subject)
			return []
		var frame: Transform3D = found[s.get("index", 0)].global_transform
		if s.get("ground", false):
			frame.origin.y = 0.0
		eye = frame * eye
		at = frame * at
	if s.get("ground", false):
		eye.y += Terrain.height_at(eye.x, eye.z)
		at.y += Terrain.height_at(at.x, at.z)
	if s.has("toward"):
		var found := get_tree().get_nodes_in_group(s.toward)
		if found.is_empty():
			push_error("driver: nothing in %s to look toward" % s.toward)
			return []
		var eye_at: Vector3 = eye + (main.rig.head.global_position if s.get("relative", false) else Vector3.ZERO)
		found.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(eye_at) < b.global_position.distance_to(eye_at))
		at += found[0].global_position
	return [eye, at]


## Moves the eye from `from` to `to` over `seconds`, looking `ahead` metres further along the way at `look` height.
func _walk(s: Dictionary) -> void:
	var from := Vector3(s.from[0], s.from[1], s.from[2])
	var to := Vector3(s.to[0], s.to[1], s.to[2])
	var dir := (to - from).normalized()
	var t := 0.0
	var seconds := float(s.seconds)
	while t < seconds:
		var eye := from.lerp(to, t / seconds)
		var at: Vector3 = eye + dir * float(s.get("ahead", 10.0))
		at.y = float(s.get("look", 0.0)) + Terrain.height_at(at.x, at.z)
		eye.y += Terrain.height_at(eye.x, eye.z)
		main.view(eye, at, false)
		await get_tree().process_frame
		t += get_process_delta_time()


## Sets an easel up at `x`, `z`, facing the head (or the ground point `facing`), as the easel tool's trigger does.
func _easel(s: Dictionary) -> void:
	var at := _spot(s, s.x, s.z)
	var toward: Vector3 = _spot(s, s.facing[0], s.facing[1]) if s.has("facing") else main.rig.head.global_position
	main.easel_tool.place(at, Easels.facing(at, toward), _hand(s))
	await _frames(2)


## The easel a step works at: its `easel`th by age, the newest by default.
func _easel_of(s: Dictionary) -> Easels.Easel:
	var ids: Array = main.easels.easels.keys()
	ids.sort()
	return main.easels.find(ids[s.get("easel", -1)])


## Holds `hand` so its brush's tip is at `tip`, the brush pointing along `along`, turned `roll` about it.
func _tip_at(hand: Hand, tip: Vector3, along: Vector3, up: Vector3, roll := 0.0) -> void:
	var basis := Basis.looking_at(along, up).rotated(along.normalized(), roll)
	hand.global_transform = Transform3D(basis, tip - basis * ToolModels.BRUSH_TIP)
	hand.held_still = true


## A grip at the easel's tray, as a player's hand closing there: takes a brush from the pot ("small", "big",
## "flat"), the charcoal ("stick"), or a palette, the watercolour box ("box") or the oil palette ("palette"), which
## stays in the hand until a `set_down`. With `preview`, approaches the handle without closing the grip.
func _take(s: Dictionary) -> void:
	var hand := _hand(s)
	var e := _easel_of(s)
	var at: Vector3
	match s.what:
		"box":
			at = e.palettes[Brushwork.Medium.WATER].global_position
		"palette":
			at = e.palettes[Brushwork.Medium.OIL].global_position
		"stick":
			at = e.stick.global_transform * Easels.grip(Brushwork.Brush.STICK)
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
	hand.held_still = true
	var key := "%s/grip_click" % hand.tracker
	Buttons.injected[key] = true
	await _frames(2)
	Buttons.injected.erase(key)
	await _frames(2)


## A grip by the hand holding a palette, wherever that hand is, sends the palette back to its rest on the tray; done
## once it rests there.
func _set_down(s: Dictionary) -> void:
	var hand := _hand(s)
	hand.held_still = true
	var key := "%s/grip_click" % hand.tracker
	Buttons.injected[key] = true
	await _frames(2)
	Buttons.injected.erase(key)
	while not main.easel_tool.returning.is_empty():
		await _frames(1)
	await _frames(1)


## Checks that `hand` holds `what` (as EaselTool.holding names it) once its brush has had time to show, and that
## the brush it shows is the one it holds.
func _holds(s: Dictionary) -> void:
	var hand := _hand(s)
	await get_tree().create_timer(Hand.POP * 2.0).timeout
	var p: EaselTool.Painter = main.easel_tool.painter(hand)
	var now := EaselTool.holding(p)
	assert(now == s.what, "driver: %s holds %s, not %s" % [hand.tracker, now, s.what])
	var shown: Array = p.models.keys().filter(func(k: Brushwork.Brush) -> bool: return p.models[k].visible)
	var brush := hand.tool == Hand.Tool.EASEL and p.palette == null
	assert(shown == ([p.brush] if brush else []), "driver: %s holding %s shows brushes %s" % [hand.tracker, now, shown])


## Checks that every palette on the easel rests at its place on the tray, as this machine sees it, once those set
## down have arrived.
func _rests(s: Dictionary) -> void:
	var e := _easel_of(s)
	await _frames(1)
	while not main.easel_tool.returning.is_empty():
		await _frames(1)
	for kit: Brushwork.Medium in e.palettes:
		var node: Node3D = e.palettes[kit]
		var held: bool = main.easel_tool.painters.any(func(p: EaselTool.Painter) -> bool: return p.palette == e and p.kit == kit)
		assert(held or (not node.top_level and node.transform.is_equal_approx(Transform3D(Basis(), Easels.KITS[kit]))), "driver: the %s palette is not at its rest" % Brushwork.Medium.keys()[kit].to_lower())


## Holds the palette-holding hand where a painter holds it: beside the canvas, `at` in the easel's frame.
func _hold(s: Dictionary) -> void:
	var e := _easel_of(s)
	var hand := _hand(s)
	hand.global_transform = Transform3D(e.global_basis, e.global_transform * Vector3(s.at[0], s.at[1], s.at[2]))
	hand.held_still = true
	await _frames(2)


## Dips the brush in `hand` into the jar, or pigment `index` of the watercolour box ("pan") or the oil palette ("oil"),
## wherever that palette is, pushed `depth` metres on through it, and lifts it out.
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
	_tip_at(hand, into + Vector3.UP * 0.08, (Vector3.DOWN - e.global_basis.z * 0.6).normalized(), -e.global_basis.z)
	await _frames(2)
	_tip_at(hand, into, (Vector3.DOWN - e.global_basis.z * 0.6).normalized(), -e.global_basis.z)
	await _frames(3)
	_tip_at(hand, into + Vector3.UP * 0.08, (Vector3.DOWN - e.global_basis.z * 0.6).normalized(), -e.global_basis.z)
	await _frames(2)


## A brushstroke on the oil palette's open board, wherever the palette is, through `points` [x, z, pressure] (x toward
## the paint, z across, both -1..1 of the board's half size) over `seconds`: the tip comes down onto the first, presses
## as hard as each point says, and lifts off the last.
func _mix(s: Dictionary) -> void:
	var hand := _hand(s)
	var e := _easel_of(s)
	var board: Transform3D = e.palettes[Brushwork.Medium.OIL].global_transform
	var on := func(p: Array, up: float) -> Vector3:
		var depth: float = Easels.BOARD_TOP + EaselTool.CONTACT - p[2] * EaselTool.PRESS_DEPTH
		return board * Vector3(p[0] * Easels.PALETTE_SIZE.x * 0.5, depth + up, p[1] * Easels.PALETTE_SIZE.y * 0.5)
	var pts: Array = s.points
	_tip_at(hand, on.call(pts[0], 0.06), -board.basis.y, -board.basis.x)
	await _frames(2)
	var frames := maxi(1, ceili(s.get("seconds", 1.0) * 60.0))
	for f in frames + 1:
		var k := float(f) / frames * (pts.size() - 1)
		var i := mini(floori(k), pts.size() - 2) if pts.size() > 1 else 0
		var a: Array = pts[i]
		var b: Array = pts[mini(i + 1, pts.size() - 1)]
		var t := k - i
		_tip_at(hand, on.call([lerpf(a[0], b[0], t), lerpf(a[1], b[1], t), lerpf(a[2], b[2], t)], 0.0), -board.basis.y, -board.basis.x)
		await _frames(1)
	_tip_at(hand, on.call(pts[-1], 0.06), -board.basis.y, -board.basis.x)
	await _frames(2)


## A brushstroke on the canvas through `points` [u, v, pressure] (u across, v down, both 0..1) over `seconds`: the
## tip comes in from off the canvas, presses as hard as each point says, and lifts off at the end. A flat brush is
## turned `roll` degrees.
func _brush(s: Dictionary) -> void:
	var hand := _hand(s)
	hand.tool = Hand.Tool.EASEL
	var e := _easel_of(s)
	var frame := e.canvas_frame()
	var roll := deg_to_rad(s.get("roll", 0.0))
	var direction := frame.basis * (Basis(Vector3.UP, deg_to_rad(s.get("tilt", 0.0))) * Vector3.FORWARD)
	var on := func(p: Array, out: float) -> Vector3:
		var depth: float = EaselTool.CONTACT - p[2] * EaselTool.PRESS_DEPTH
		return frame * Vector3((p[0] - 0.5) * Brushwork.METRES.x, (0.5 - p[1]) * Brushwork.METRES.y, depth + out)
	var pts: Array = s.points
	var before := frame.affine_inverse() * hand.global_position
	before.z = 0.6
	hand.global_position = frame * before
	await _frames(2)
	_tip_at(hand, on.call(pts[0], 0.4), direction, frame.basis.y, roll)
	await _frames(2)
	_tip_at(hand, on.call(pts[0], 0.05), direction, frame.basis.y, roll)
	await _frames(2)
	var frames := maxi(1, ceili(s.get("seconds", 1.0) * 60.0))
	for f in frames + 1:
		var k := float(f) / frames * (pts.size() - 1)
		var i := mini(floori(k), pts.size() - 2) if pts.size() > 1 else 0
		var a: Array = pts[i]
		var b: Array = pts[mini(i + 1, pts.size() - 1)]
		var t := k - i
		_tip_at(hand, on.call([lerpf(a[0], b[0], t), lerpf(a[1], b[1], t), lerpf(a[2], b[2], t)], 0.0), direction, frame.basis.y, roll)
		await _frames(1)
	if s.has("capture"):
		print("brush contact: tracked %s, visible %s" % [e.on_canvas(hand.global_transform * ToolModels.BRUSH_TIP), e.on_canvas(hand.body.global_transform * ToolModels.BRUSH_TIP)])
		await main.capture(s.capture)
	_tip_at(hand, on.call(pts[-1], 0.05), direction, frame.basis.y, roll)
	await _frames(2)


## Takes the canvas's sheet in `hand` and pulls it `pull` metres off (enough tears it away), then lets go.
func _sheet(s: Dictionary) -> void:
	var hand := _hand(s)
	var e := _easel_of(s)
	var frame := e.canvas_frame()
	var key := "%s/grip_click" % hand.tracker
	hand.global_transform = Transform3D(frame.basis * Basis(Vector3.UP, PI), frame * Vector3(0, -0.3, 0.05))
	hand.held_still = true
	Buttons.injected[key] = true
	await _frames(1)
	var frames := maxi(1, ceili(s.get("seconds", 0.6) * 60.0))
	for f in frames:
		hand.global_transform = Transform3D(frame.basis * Basis(Vector3.UP, PI), frame * Vector3(0, -0.3, 0.05 + s.get("pull", 0.4) * (f + 1) / frames))
		await _frames(1)
	if s.has("capture"):
		await main.capture(s.capture)
	Buttons.injected.erase(key)
	await _frames(2)


## Puts a fresh sheet up on the easel, paints `strokes` strokes of `painting` on it, and waits until the canvas has
## replayed them as a kept painting.
func _painting(s: Dictionary) -> void:
	var e := _easel_of(s)
	main.world.submit({"op": "sheet", "easel": e.id, "strokes": []})
	for stroke: Dictionary in painting(int(s.strokes)):
		main.world.submit({"op": "paint", "easel": e.id, "stroke": stroke})
	await _frames(2)
	main.easels.repaint(e.id, main.world.state.easels[e.id].strokes)
	await _caught_up(s)


## Waits until the easel's canvas has caught up with its painting.
func _caught_up(s: Dictionary) -> void:
	var e := _easel_of(s)
	while e.canvas.catching_up():
		await _frames(1)


## `n` watercolour strokes across the canvas, half a second each, a third of a second apart: a kept painting as
## benches and tests replay it.
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


## Desktop only: holds `hand` at `at`, pointing along `aim`, rolled `roll` degrees, all in head space, as a lesson poses it.
func _hold_pose(s: Dictionary) -> void:
	var hand := _hand(s)
	hand.global_transform = main.rig.head.global_transform * Lessons.frame({"at": Lessons._v(s.at), "aim": Lessons._v(s.aim).normalized(), "roll": s.get("roll", 0.0)})
	hand.held_still = true
	await _frames(2)


## Renders page `page`'s live picture alone at `size`, stepping it at 30 Hz and saving it at each of `times` as
## "<name>-<time>", so its loop can be read frame by frame; with "see_through", its controllers' shells half clear.
func _lesson_frames(s: Dictionary) -> void:
	var scene := LessonScene.new(int(s.page), s.get("see_through", false))
	scene.size = Vector2i(s.get("size", [768, 576])[0], s.get("size", [768, 576])[1])
	scene.manual = true
	add_child(scene)
	scene.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var dir: String = main.args.get("capture-dir", "user://captures")
	for at in s.times:
		while scene.t + 1.0 / 30.0 <= at:
			scene.advance(1.0 / 30.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := dir.path_join("%s-%04.1f.png" % [s.name, at])
		scene.get_texture().get_image().save_png(path)
		print("capture: ", path)
	scene.queue_free()


## Prints what the held book's live pages cost the GPU over `seconds`, from the renderer's timestamps around each
## viewport: each page's render and their share of a frame, beside the garden's own view.
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


## Looks at the held book's middle from `eye`, metres from it along the player's right, up and back.
func _view_book(s: Dictionary) -> void:
	var b: Book = main.book
	var shut := b.at == 0 and b._turn.is_empty()
	var mid := b.global_transform * Vector3(Book.W * 0.5 if shut else 0.0, 0.0, 0.0)
	_eye = mid + main.rig.global_basis * Lessons._v(s.eye)
	_at = mid
	main.view(_eye, _at, false)
	await get_tree().process_frame


## The picture book in the hand holding it: "open" it, "turn" a leaf on or "back", then wait `seconds`.
func _book(s: Dictionary) -> void:
	var b: Book = main.book
	match s.do:
		"open":
			b.open()
		"turn":
			b.turn(1)
		"back":
			b.turn(-1)
	await get_tree().create_timer(s.get("seconds", 1.0)).timeout


func _capture(s: Dictionary) -> void:
	await main.capture(s.name, s.get("screen", false))


func _quit(_s: Dictionary) -> void:
	main.finish()


## With "relative", x is metres to the head's right and z metres ahead of it, so a script works whichever way the headset faces.
func _spot(s: Dictionary, x: float, z: float) -> Vector3:
	if not s.get("relative", false):
		return Terrain.ground(x, z)
	var head: Node3D = main.rig.head
	var fwd := -head.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var p := head.global_position + right * x + fwd * z
	return Terrain.ground(p.x, p.z)


## What the walls tool builds on at a ground spot: with "on", what a hand pointing straight down from above it
## hits, a build's top or the ground; else the ground.
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


## The ground point `fraction` of the way along `path`.
static func _along(path: Array[Vector3], fraction: float) -> Vector3:
	var d := 0.0
	for i in path.size() - 1:
		d += path[i].distance_to(path[i + 1])
	d *= fraction
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if d <= seg:
			var p := path[i].lerp(path[i + 1], d / seg if seg > 0.0 else 0.0)
			p.y = Terrain.height_at(p.x, p.z)
			return p
		d -= seg
	return path[-1]


## Holds the quality ladder at `step`, or with "fit" at the fixed table's calibration step (Budget.fit_step);
## without one, the governor walks it again.
func _quality(s: Dictionary) -> void:
	var step: Variant = s.get("step", -1)
	main.quality.pin = Budget.fit_step() if step is String and step == "fit" else int(step)


func _label(s: Dictionary) -> void:
	main.metrics.info.label = s.name


## Lays the `build` steps over the bare meadow as large as this headset holds them: while the dearest of `views` reads
## over the governor's line, the meadow is bared and they are laid again over the share of their area that
## would bring it under, so every phase of demo/costs.json is measured at the refresh rate, on any headset, from one
## script.
func _sized(s: Dictionary) -> void:
	var line: float = (1000.0 / Budget.REFRESH_HZ * Quality.Governor.LINE) * 0.95
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


## The viewport's mean GPU time a frame from `view`, once it has settled.
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


## Back to the bare meadow, as a long hold of the delete tool leaves it.
func _bare(_s: Dictionary) -> void:
	main.world.submit({"op": "wipe"})
	await _frames(3)


## With `bounded` false the garden takes builds past the frame budget, as the stress scene must; true holds it again.
func _budget(s: Dictionary) -> void:
	main.world.bounded = s.bounded


func _units(_s: Dictionary) -> void:
	print("budget: %s units %s ms %.3f fill %.3f" % [main.metrics.info.label, JSON.stringify(main.world.units), Budget.cost_ms(main.world.units), main.world.fill()])


func _stairs(s: Dictionary) -> void:
	var hand: Hand = main.rig.right
	hand.tool = Hand.Tool.STAIRS
	main.world.stairs.rail = s.get("rail", "stone")
	var a := Vector3(s.a[0], s.a[1], s.a[2])
	var b := Vector3(s.b[0], s.b[1], s.b[2])
	if s.get("ground", false):
		a.y += Terrain.height_at(a.x, a.z)
		b.y += Terrain.height_at(b.x, b.z)
	if s.get("on", false):
		a = _target(s, Terrain.ground(a.x, a.z)).point
		b = _target(s, Terrain.ground(b.x, b.z)).point
	main.stair_tool.begin(hand, a)
	var frames := maxi(1, int(s.get("seconds", 1.0) * 30.0))
	for i in frames:
		main.stair_tool.extend(hand, a.lerp(b, float(i + 1) / frames))
		await get_tree().create_timer(1.0 / 30.0).timeout
	main.stair_tool.end(hand)


## Fills the stair allowance without changing whether later scripted builds are bounded.
func _stair_field(_s: Dictionary) -> void:
	main.world.submit({"op": "wipe"})
	await _sculpt({"x": 5.0, "z": -6.0, "lift": 2.0, "seconds": 0.2})
	await _pave({"points": [[5, -2.5], [5, -6]], "radius": 0.8, "seconds": 0.2})
	var placed := 0
	for row in 9:
		for col in 9:
			var a := Terrain.ground((col - 4) * 3.5, (row - 4) * 6.0)
			var d := {"a": a, "b": a + Vector3(0, 2.4, -4), "width": 1.2, "rail": "stone" if col % 2 == 0 else "wood", "seed": row * 9 + col, "paint": Palette.plain(), "on": PackedInt32Array()}
			if col % 3 == 1:
				d.b = a + Vector3(0, 3, -1)
			elif col % 3 == 2:
				d.b = a + Vector3(0, 0, -4)
			if not Budget.fits(main.world.units, main.world.change_of({"op": "stairs", "stairs": d})):
				print("stairs: budget full at %d builds, fill %.3f" % [placed, main.world.fill()])
				return
			main.world.submit({"op": "stairs", "stairs": d})
			placed += 1
			await get_tree().process_frame
	assert(false, "stair field did not fill the budget")


## Four rigged eaters (the largest visiting band), with the same clips on both sides of the CPU measurement.
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
		var at := Terrain.ground(12.0 + i * 1.8, 0)
		dish.position = at + Vector3(0, 0.25 if i == 3 else [0.4, 0.8, 1.05][i], 0)
		animal.position = at
		animal.position.z += Hand.TOP.z + animal.neck.stand_off(animal, dish)
		animal.eat(dish.position.y - at.y, 0.0)
		animal.neck.offer = dish
		animal.neck.amount = 1.0
		animals.append(animal)
		dishes.append(dish)
	var elapsed := 0.0
	var samples: Array[float] = []
	var solving: bool = s.get("solve", true)
	while elapsed < s.get("seconds", 10.0):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		for dish in dishes:
			dish.position.z = sin(elapsed * 0.7) * 0.02
		var start := Time.get_ticks_usec()
		if solving:
			for animal in animals:
				animal.neck._process_modification()
		samples.append((Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	print("neck_cost: solve=%s, four animals, %d frames, CPU median %.4f ms, p95 %.4f ms, max %.4f ms" % [solving, samples.size(), samples[samples.size() / 2], samples[int(samples.size() * 0.95)], samples[-1]])
	for animal in animals:
		animal.queue_free()
	for dish in dishes:
		dish.queue_free()


## Publishes the holder's actual models for another process to compare with what its network peer renders.
func _held_snapshot(s: Dictionary) -> void:
	await get_tree().create_timer(Hand.POP * 3.0).timeout
	var items := [HeldItem.describe(main.rig.left, main.easel_tool, main.book), HeldItem.describe(main.rig.right, main.easel_tool, main.book)]
	if s.get("loaded", false):
		assert(items[1].size() == 8 and items[1][0] == HeldItem.Kind.BRUSH and items[1][4] > 0.5, "capture holds a loaded brush")
	var path: String = str(main.args.get("capture-dir", "user://captures")).path_join(s.name)
	FileAccess.open(path + ".held", FileAccess.WRITE).store_var([multiplayer.get_unique_id(), items])
	FileAccess.open(path + ".json", FileAccess.WRITE).store_string(JSON.stringify({"held": items.map(HeldItem.label)}))


func _remote_holds(s: Dictionary) -> void:
	var path: String = str(main.args.get("capture-dir", "user://captures")).path_join(s.name)
	var expected: Array = FileAccess.open(path + ".held", FileAccess.READ).get_var()
	var elapsed := 0.0
	while elapsed < 30.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if not main.session.held.has(expected[0]):
			continue
		var pair: Array = main.session.held[expected[0]]
		var matches := true
		for side in 2:
			var item: HeldItem = pair[side]
			matches = matches and HeldItem.same(item.state, expected[1][side])
			if item.state.is_empty():
				matches = matches and item.model == null
			else:
				matches = matches and item.model != null and item.model.is_visible_in_tree() and item.model.transform.is_equal_approx(item.state[2])
				matches = matches and item.transform.is_equal_approx((main.session.avatars[expected[0]] as Avatar).hands[side])
				if item.state[0] == HeldItem.Kind.BRUSH and item.state[1] != Brushwork.Brush.STICK:
					var tip := (item.model.get_node("tip") as MeshInstance3D).material_override as StandardMaterial3D
					matches = matches and tip.albedo_color.is_equal_approx(item.state[3])
		if matches:
			print("held: peer sees %s in the other player's hands" % str(expected[1].map(HeldItem.label)))
			return
	assert(false, "remote held models differ from holder: " + s.name)


## The maximum seven peers' fourteen held models, close enough to fill the view, through the live renderer.
func _held_cost(s: Dictionary) -> void:
	var items: Array[HeldItem] = []
	var eye: Transform3D = main.rig.head.global_transform
	for i in (Session.MAX_PLAYERS - 1) * 2:
		var item := HeldItem.new()
		add_child(item)
		item.global_transform = eye * Transform3D(Basis(), Vector3((i % 7 - 3) * 0.2, (i / 7 - 0.5) * 0.35, -0.8))
		items.append(item)
	var states: Array = []
	for tool in Hand.Tool.values():
		if tool not in [Hand.Tool.NONE, Hand.Tool.EASEL, Hand.Tool.BOOK]:
			states.append([HeldItem.Kind.TOOL, tool, Transform3D(Basis(), Hand.TOP), Color.WHITE, 0.0, 0, false])
	states.append([HeldItem.Kind.PALETTE, Brushwork.Medium.OIL, Transform3D(), Color.WHITE, 0.0, 1, false])
	states.append([HeldItem.Kind.PALETTE, Brushwork.Medium.WATER, Transform3D(), Color.WHITE, 0.0, 1, false])
	for brush in Brushwork.Brush.values():
		states.append([HeldItem.Kind.BRUSH, brush, Transform3D(), Color(0.15, 0.3, 0.65), 1.0, 0, false])
	states.append([HeldItem.Kind.BOOK, 1, Book.local(1.0), Color.WHITE, 0.0, 0, false])
	if s.get("birds", false):
		states = [[HeldItem.Kind.BIRD, 0, BirdCarry.HOLD, Color.WHITE, 0.0, 0, false, Vector3.ZERO]]
	for state in states:
		for item in items:
			item.show_state(state)
			if s.get("without_cup", false) and item.model is Conure:
				for child in item.model.get_children():
					(child as Node3D).hide()
		await get_tree().create_timer(0.1).timeout
		var name := HeldItem.label(state) + ("-without-cup" if s.get("without_cup", false) else "")
		var label := {"op": "label", "name": "held/" + name.replace(" ", "-")}
		print("driver: ", label)
		await _label(label)
		await get_tree().create_timer(s.get("seconds", 3.0)).timeout
	await _label({"name": "-"})
	for item in items:
		item.queue_free()


## Offers seeds beside an existing bird, waits for earned trust, then closes the grip.
func _befriend(s: Dictionary) -> void:
	var h := _hand(s)
	var flock: Birds = main.wildlife.birds
	var elapsed := 0.0
	while flock.birds.is_empty() and elapsed < 240.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	assert(not flock.birds.is_empty(), "no conure arrived")
	var available := flock.birds.filter(func(b: Birds.Bird) -> bool: return not b.carried)
	assert(not available.is_empty(), "no free bird")
	var bird: Birds.Bird = available[0]
	while bird.state != Birds.State.PERCH and elapsed < 260.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	assert(bird.state == Birds.State.PERCH, "bird did not land")
	h.tool = Hand.Tool.SEEDS
	h.held_still = true
	h.global_transform = Transform3D(Basis.IDENTITY, bird.node.global_position + Vector3(0.2, -0.15, 0.2))
	elapsed = 0.0
	while elapsed < 90.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var fed := flock.birds.filter(func(b: Birds.Bird) -> bool: return b.node.hand == h and b.state == Birds.State.FEED and b.affection >= BirdCarry.TRUST)
		if not fed.is_empty():
			bird = fed[0]
			break
	if bird.node.hand != h or bird.affection < BirdCarry.TRUST or bird.state != Birds.State.FEED:
		push_error("bird did not feed and trust hand")
		main.finish()
		return
	Buttons.injected["%s/%s" % [h.tracker, Controls.input("grab", h.tracker)]] = true
	await _frames(30)
	if h.carried != bird.node:
		push_error("grip did not pick up fed bird")
		main.finish()
		return
	print("conure: feeding earned trust, grip carries bird")


## Carries the bird to the canvas and sweeps its feathers across it, then lifts away.
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
		await get_tree().process_frame
		approach += get_process_delta_time()
		h.global_transform = from.interpolate_with(target, smoothstep(0.0, 0.6, approach))
	await _frames(2)
	var seconds: float = s.get("seconds", 3.0)
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		var along := t / seconds
		h.global_transform = Transform3D(basis, frame * Vector3(lerpf(-0.25, 0.25, along), along * 0.18, 0.018) - basis * (BirdCarry.HOLD.origin + Conure.BODY))
	h.global_position += frame.basis.z * 0.2
	await _frames(30)
	print("conure: wet canvas smear submitted")


func _view_held(s: Dictionary) -> void:
	var h := _hand(s)
	assert(h.carried != null)
	h.global_transform = Transform3D(Basis.IDENTITY, Terrain.ground(1.5, 2.0) + Vector3.UP * 1.4)
	await _frames(30)
	var at := h.carried.global_position + Vector3.UP * 0.07
	var hand_pose := h.global_transform
	main.view(at + Vector3(0.25, 0.13, -0.36), at, false)
	h.global_transform = hand_pose
	await _frames(30)


func _release_bird(s: Dictionary) -> void:
	var h := _hand(s)
	Buttons.injected.erase("%s/%s" % [h.tracker, Controls.input("grab", h.tracker)])
	await _frames(2)
	assert(h.carried == null, "bird must leave the hand when grip releases")
