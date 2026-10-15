class_name Driver
extends Node

## Plays a JSON list of steps through the same rig and tool entry points the controllers use.
## A step marked "background" starts and the next one follows at once, as a camera glides while a wall is drawn.
## Each step starts once the garden's builds are laid, so it reads them as built.

## The Steam Frame's buttons as SteamVR delivers them to a game bound through the Touch or Index
## profiles (its frame_controller remapping): B, X and Y all arrive as right-hand B, View as left menu.
const FRAME_BUTTONS := {
	"A": ["right_hand", "ax_button"],
	"B": ["right_hand", "by_button"],
	"X": ["right_hand", "by_button"],
	"Y": ["right_hand", "by_button"],
	"dpad_down": ["left_hand", "ax_button"],
	"dpad_up": ["left_hand", "by_button"],
	"dpad_left": ["left_hand", "by_button"],
	"dpad_right": ["left_hand", "by_button"],
	"left_stick_click": ["left_hand", "primary_click"],
	"right_stick_click": ["right_hand", "primary_click"],
	"view": ["left_hand", "menu_button"],
	"left_trigger": ["left_hand", "trigger_click"],
	"right_trigger": ["right_hand", "trigger_click"],
}

signal finished

var main: Node
var steps: Array
var _eye := Vector3.ZERO
var _at := Vector3.FORWARD
var _waiting := {}


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
	while main.tool.walls.any(func(w: Wall) -> bool: return w.laying()):
		await get_tree().process_frame


func _wait(s: Dictionary) -> void:
	await get_tree().create_timer(s.seconds).timeout


## Holds a Frame button (see FRAME_BUTTONS) for `seconds`, through the same edges the controllers feed.
func _press(s: Dictionary) -> void:
	var key := "%s/%s" % FRAME_BUTTONS[s.button]
	Buttons.injected[key] = true
	await get_tree().create_timer(s.get("seconds", 0.1)).timeout
	Buttons.injected.erase(key)
	await get_tree().process_frame
	await get_tree().process_frame


## Takes a tool from a hand's wheel as a player does: hold the wheel button, sweep the hand through each
## level of the tool's path, let go. An untracked hand is moved itself; a tracked one sweeps by injected
## reach. "capture" saves a view at the opening and at each level reached, as "<capture>-<level>",
## "popping" one the frame after the pick.
func _pick(s: Dictionary) -> void:
	var hand: Hand = _hand(s)
	var key := "%s/%s" % [hand.tracker, Hand.WHEEL_BUTTON[hand.tracker]]
	var path: Array[int] = ToolWheel.paths(Hand.TREE)[Hand.Tool[s.tool.to_upper()]]
	var start := hand.global_position
	var reach := func(p: Vector2) -> void:
		if hand.get_has_tracking_data():
			Hand.injected_reach[hand.tracker] = p
		else:
			hand.global_position = hand.wheel_frame() * Vector3(p.x, p.y, 0)
	Buttons.injected[key] = true
	await _frames(3)
	if s.has("capture"):
		await _frames(6)
		await main.capture("%s-0" % s.capture)
	var from := Vector2.ZERO
	var level := 0
	for to in ToolWheel.sweep(Hand.TREE, path):
		level += 1
		for f in 6:
			reach.call(from.lerp(to, (f + 1) / 6.0))
			await _frames(1)
		from = to
		if s.has("capture"):
			await _frames(6)
			await main.capture("%s-%d" % [s.capture, level])
	Buttons.injected.erase(key)
	await _frames(1)
	if s.has("popping"):
		await main.capture(s.popping)
	await _frames(1)
	Hand.injected_reach.erase(hand.tracker)
	if not hand.get_has_tracking_data():
		hand.global_position = start
	await _frames(2)


## Desktop only: holds both controllers in front of the head, `left` and `right` in head space, tops tipped toward the eye.
func _hands(s: Dictionary) -> void:
	var head: Transform3D = main.rig.head.global_transform
	for side in ["left", "right"]:
		if not s.has(side):
			continue
		var hand: Hand = main.rig.left if side == "left" else main.rig.right
		var at: Vector3 = head * Vector3(s[side][0], s[side][1], s[side][2])
		var fwd := -head.basis.z
		hand.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP).rotated(head.basis.x, deg_to_rad(s.get("tip", 35.0))), at)
		hand.held_still = true
	await get_tree().process_frame


## Desktop only: holds `hand` beside the head, holding `tool`, pointing at `at` in the garden.
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


## Teleports as a player does with any tool: the left hand points beside the head along `dir` (relative
## to the head's facing) with its stick pushed `stick` forward for `seconds`, optionally captures the aimed view, from
## the `watch` pose (a `view` step's keys) if given, then lets go.
func _aim(s: Dictionary) -> void:
	var rig: Rig = main.rig
	var head := rig.head.global_transform
	var dir: Vector3 = head.basis * Vector3(s.dir[0], s.dir[1], s.dir[2])
	rig.left.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), head * Vector3(-0.2, -0.35, -0.25))
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
	await _stroke(s, Hand.Tool.PLASTER_WALLS if s.get("plaster", false) else Hand.Tool.WALLS)


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


## The house tool's carry: a square house taken up at `from` (default `at`) and set down at `at`, `size`
## [along, across], its front turned `turn` degrees from the x axis (the head's right with "relative"), from
## `turn_from` (default `turn`), moving there over `seconds`; with "round", A rounds it into a tower as it is taken up,
## `size` [across, across]. With "capture", `shots` views named after it are saved at even steps, the last just before letting go.
func _house(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	_holding(s, Hand.Tool.PLASTER_HOUSE if s.get("plaster", false) else Hand.Tool.HOUSE)
	var x: float = s.at[0]
	var z: float = s.at[1]
	var to := _spot(s, x, z)
	var from := _spot(s, s.from[0], s.from[1]) if s.has("from") else to
	var yaw := _turn(s, x, z, s.get("turn", 0.0))
	var yaw_from := _turn(s, x, z, s.get("turn_from", s.get("turn", 0.0)))
	var on: int = _target(s, from).on
	_lay_gables(s)
	tool.begin_house(from, yaw_from, s.get("plaster", false), PackedInt32Array([on]) if on >= 0 else PackedInt32Array())
	if s.get("round", false):
		tool.round_house(true)
	var taken_up: Vector2 = tool.house_at.size
	var size := Vector2(s.size[0], s.size[1]) if s.has("size") else taken_up
	var frames := maxi(1, ceili(s.get("seconds", 2.0) * 60.0))
	var shots: int = s.get("shots", 3) if s.has("capture") else 0
	var taken := 0
	for f in frames:
		await get_tree().process_frame
		var k := float(f + 1) / frames
		tool.place_house(from.lerp(to, k), lerp_angle(yaw_from, yaw, k), taken_up.lerp(size, k))
		if taken < shots and f + 1 >= frames * (taken + 1) / shots:
			taken += 1
			await get_tree().create_timer(0.4).timeout
			await main.capture("%s-%d" % [s.capture, taken])
	tool.end_house()


## Resizes the built house `index` (or under `at`) where it stands to `size` [along its ridge, across it], or a
## tower to `size[0]` across, over `seconds`, as two hands stretching it would.
func _resize(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	tool.begin_resize(_wall_of(s))
	var start: Dictionary = tool.resized_to.duplicate()
	var frames := maxi(1, ceili(s.get("seconds", 1.0) * 60.0))
	for f in frames:
		await get_tree().process_frame
		var to := start.duplicate()
		to.size = start.size.lerp(Vector2(s.size[0], s.size[0] if start.round else s.size[1]), float(f + 1) / frames)
		tool.drag_resize(to)
	tool.end_resize()


func _turn(s: Dictionary, x: float, z: float, degrees: float) -> float:
	var t := deg_to_rad(degrees)
	return WallTool.angle(_spot(s, x + cos(t), z + sin(t)) - _spot(s, x, z))


func _roof(s: Dictionary) -> void:
	var w: Wall = main.tool.walls[s.index]
	main.tool.shape_roof(w, s.get("pitch", w.roof.pitch), s.get("curve", w.roof.curve))
	main.world.submit({"op": "reshape", "id": w.id, "data": {"roof": {"pitch": w.roof.pitch, "curve": w.roof.curve}}})


func _top(s: Dictionary) -> void:
	var w: Wall = main.tool.walls[s.index]
	if w.roof != null and not w.roof.flat():
		return
	while w.layout.top != WallLayout.Top[s.style.to_upper()]:
		main.tool.cycle_top(w)


## Turns the gable ends of the house `index` (or under `at`) to `style`: wall, boards or steps.
func _gable(s: Dictionary) -> void:
	main.world.submit({"op": "reshape", "id": _wall_of(s).id, "data": {"gable_end": int(WallLayout.GableEnd[s.style.to_upper()])}})


## With `gable` (wall, boards or steps), houses laid after take that style of gable end.
func _lay_gables(s: Dictionary) -> void:
	if s.has("gable"):
		main.tool.gable_end = WallLayout.GableEnd[s.gable.to_upper()]


func _lift_wall(s: Dictionary) -> void:
	var w := _wall_of(s)
	main.world.submit({"op": "reshape", "id": w.id, "data": {"height": float(s.height)}})


## The wall a step names: by `index` in build order, or the one under the ground point `at` [x, z].
func _wall_of(s: Dictionary) -> Wall:
	if s.has("at"):
		return main.tool.pick_wall(_spot(s, s.at[0], s.at[1]) + Vector3.UP * 2.0, Vector3.DOWN).wall
	return main.tool.walls[s.index]


func _arch(s: Dictionary) -> void:
	main.tool.toggle_arch(main.tool.walls[s.index], s.s)


## A press of the windows or decorations tool on wall `index` (-1 the last drawn), as `FittingTool.aim`
## would find it: `what` is window, lantern, flag, chimney or tower_flag; `s` and `y` place it on the wall,
## `side` picks a lantern's face, `at` a chimney's spot along and across the ridge.
func _fit(s: Dictionary) -> void:
	var target := {"what": s.what, "wall": main.tool.walls[s.index], "s": s.get("s", 0.0), "y": s.get("y", 0.0), "side": s.get("side", 1.0)}
	if s.has("at"):
		target.at = Vector2(s.at[0], s.at[1])
	main.fitting_tool.fit(target)


func _paint(s: Dictionary) -> void:
	var flora_tool: FloraTool = main.flora_tool
	var b := flora_tool.brush(main.rig.left if s.get("hand", "left") == "left" else main.rig.right)
	b.hand.tool = Hand.Tool[s.tool.to_upper()]
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
	b.hand.tool = Hand.Tool.DIRT_PATH if s.get("style", "cobble") == "dirt" else Hand.Tool.PATH
	var path := _path(s)
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


## Holds the pond tool's trigger on the ground at x, z for `seconds`, as a hand digging there does.
func _dig(s: Dictionary) -> void:
	var tool: WaterTool = main.water_tool
	tool.begin(_holding(s, Hand.Tool.POND), _spot(s, s.x, s.z))
	var t := 0.0
	while t < s.get("seconds", 1.5):
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		tool.deepen(dt)
	tool.end()


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
	main.flora_tool.plant_tree(_spot(s, s.x, s.z))


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
	var m := tool.mason(_holding(s, Hand.Tool.FENCE if s.get("fence", false) else Hand.Tool.PLASTER_WALLS if s.get("plaster", false) else Hand.Tool.WALLS))
	var rows := StressLayout.walls(s.radius, s.spacing)
	var start := Time.get_ticks_usec()
	for row in rows:
		tool.begin_stroke(m, Terrain.ground(row[0].x, row[0].y))
		for i in range(1, row.size()):
			tool.extend_stroke(m, Terrain.ground(row[i].x, row[i].y))
		var before := tool.walls.size()
		tool.end_stroke(m)
		for w in tool.walls.slice(before):
			main.world.submit({"op": "reshape", "id": w.id, "data": {"height": float(s.height)}})
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
			main.world.submit({"op": "reshape", "id": w.id, "data": {"lanterns": after}})
	print("stress: %d lanterns" % hung)


## Fills every painted and placed flora pool to capacity within `radius` of the centre, or only those `pools` names
## (grass, flowers, trees). They are not build commands, so the frame budget does not count them.
func _fill_flora(s: Dictionary) -> void:
	var flora: Flora = main.flora_tool.flora
	var pools: Array = s.get("pools", ["grass", "flowers", "trees"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in Flora.PAINTED_GRASS if "grass" in pools else 0:
		flora.add_grass(_scatter(rng, s.radius), rng)
	for i in Flora.PAINTED_FLOWERS if "flowers" in pools else 0:
		flora.add_flower(_scatter(rng, s.radius), rng)
	for i in Flora.PLACED_TREES if "trees" in pools else 0:
		flora.add_tree(_scatter(rng, s.radius), rng)


## Fills a disc at once with a grid of houses, `spacing` apart, every other one turned a quarter; with `storeys`,
## each stands that many high, with `wings`, a wing crosses each house, and with `gable`, their gable ends take it.
func _village(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var start := Time.get_ticks_usec()
	var r: float = s.radius
	var step: float = s.spacing
	_lay_gables(s)
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
			for storey in s.get("storeys", 1):
				tool.begin_house(at, yaw, s.get("plaster", false), on)
				tool.place_house(at, yaw, Vector2(0.7, 0.44) * step)
				tool.end_house()
				tool.walls[-1].ivy_age = INF
				on = PackedInt32Array([tool.walls[-1].id])
			if s.get("wings", false):
				var wing := at + Vector3.RIGHT.rotated(Vector3.UP, yaw) * step * 0.2
				wing = Terrain.ground(wing.x, wing.z)
				tool.begin_house(wing, yaw, s.get("plaster", false))
				tool.place_house(wing, yaw, Vector2(0.3, 0.6) * step)
				tool.end_house()
				tool.walls[-1].ivy_age = INF
	print("village: %d buildings in %.0f ms" % [k, (Time.get_ticks_usec() - start) / 1000.0])


func _clear(_s: Dictionary) -> void:
	for w in main.tool.walls.duplicate():
		main.world.submit({"op": "unwall", "ids": PackedInt32Array([w.id])})
	await get_tree().process_frame


static func _scatter(rng: RandomNumberGenerator, radius: float) -> Vector3:
	return FloraLayout.brush(Vector3.ZERO, radius, 1, rng, Terrain.height_at)[0]


## The port of the garden a script visits: its `port`, else the --host-port launch argument.
func _host_port(s: Dictionary) -> int:
	return int(s.get("port", main.args.get("host-port", Session.PORT)))


## Joins the garden hosted at `address` on the host's port, as picking its figure does.
func _join(s: Dictionary) -> void:
	main.session.join(s.get("address", "127.0.0.1"), _host_port(s))
	await get_tree().process_frame


## Takes the visit tool in the right hand, points it at the figure of the host's garden (or at the home
## cairn with "home") and pulls the trigger.
func _visit(s: Dictionary) -> void:
	var tool: VisitTool = main.visit_tool
	var hand := _holding(s, Hand.Tool.VISIT)
	await _frames(2)
	var keys := tool.figures.keys()
	var k: String = VisitTool.HOME if s.get("home", false) else keys.filter(func(x: String) -> bool: return x.ends_with(":%d" % _host_port(s)))[0]
	var at: Vector3 = tool.figures[k].global_position + VisitTool.AIM
	var from: Vector3 = main.rig.head.global_position + Vector3(0.2, -0.3, 0)
	hand.global_transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)
	await _frames(1)
	var key := "%s/trigger_click" % hand.tracker
	Buttons.injected[key] = true
	await _frames(2)
	Buttons.injected.erase(key)
	await _frames(2)


## Waits until the garden has applied command `seq`, `players` share it, `worn` of them show their own avatar files, the
## `digests` named have been written to the capture directory (by any player), or with "heard" the host's beacon is
## heard, for at most `seconds`. Without them only the run's end stops the wait, reported as timed out: how long
## another player takes to start and catch up is the machine's load, not the script's.
func _until(s: Dictionary) -> void:
	var dir := str(main.args.get("capture-dir", "user://captures"))
	var t := 0.0
	_waiting = s
	while t < s.get("seconds", INF):
		var w: World = main.world
		var worn: int = main.session.avatars.values().filter(func(a: Avatar) -> bool: return a.source != "").size()
		var digested: bool = s.get("digests", []).all(func(n: String) -> bool: return FileAccess.file_exists(dir.path_join(n + ".json")))
		if w.seq >= s.get("seq", 0) and main.session.players() >= s.get("players", 0) and worn >= s.get("worn", 0) and digested and (not s.get("heard", false) or main.session.nearby.keys().any(func(k: String) -> bool: return k.ends_with(":%d" % _host_port(s)))):
			_waiting = {}
			return
		await get_tree().process_frame
		t += get_process_delta_time()
	_waiting = {}
	push_error("driver: until %s timed out" % s)


## Writes `World.digest`, how many other players' avatars stand here and the hashes of their own files, to `name`.json in the capture
## directory, for comparing machines.
func _digest(s: Dictionary) -> void:
	var path: String = str(main.args.get("capture-dir", "user://captures")).path_join(s.name + ".json")
	var out: Dictionary = main.world.digest()
	out.avatars = main.session.avatars.values().filter(func(a: Avatar) -> bool: return a.visible).size()
	out.worn = main.session.avatars.values().map(func(a: Avatar) -> String: return a.source).filter(func(k: String) -> bool: return k != "")
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


## Takes a photo with the camera in `hand` (right by default) wherever that hand points, as pulling its
## trigger does, and waits until it is saved.
func _photo(s: Dictionary) -> void:
	await main.photo_tool.shoot(_holding(s, Hand.Tool.CAMERA))


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
	var grip := "%s/grip_click" % hand.tracker
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
	var hand := _holding(s, Hand.Tool.COLOUR)
	var element: Palette.Element = Palette.Element[s.element.to_upper()]
	var target := {"element": element, "wall": null}
	if s.has("at"):
		var at: Vector3 = _spot(s, s.at[0], s.at[2]) + Vector3.UP * s.at[1]
		var origin: Vector3 = _spot(s, s.from[0], s.from[2]) + Vector3.UP * s.from[1] if s.has("from") else main.rig.head.global_position
		target = tool.aim(origin, (at - origin).normalized())
	if target.get("element") != element:
		push_error("driver: colour aimed at %s, not %s" % [target, s.element])
		return
	tool.open(hand, target)
	var from: int = tool.wheels[hand].start
	var to: int = s.swatch
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
	_at = pose[1] + origin
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


## A step's `eye` and `at`. With "ground", their heights count from the ground under each.
## With "subject", they are in the frame of the first node in that group, as it stands now.
func _pose(s: Dictionary) -> Array[Vector3]:
	var eye := Vector3(s.eye[0], s.eye[1], s.eye[2])
	var at := Vector3(s.at[0], s.at[1], s.at[2])
	if s.get("ground", false):
		eye.y += Terrain.height_at(eye.x, eye.z)
		at.y += Terrain.height_at(at.x, at.z)
	if s.has("subject"):
		var found := get_tree().get_nodes_in_group(s.subject)
		if found.is_empty():
			push_error("driver: nothing in %s to view" % s.subject)
			return []
		var frame: Transform3D = found[0].global_transform
		eye = frame * eye
		at = frame * at
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


func _capture(s: Dictionary) -> void:
	await main.capture(s.name)


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


## Holds the quality ladder at `step`; without one, the governor walks it again.
func _quality(s: Dictionary) -> void:
	main.quality.pin = int(s.get("step", -1))


func _label(s: Dictionary) -> void:
	main.metrics.info.label = s.name


## Back to the bare meadow, as a long hold of the delete tool leaves it.
func _bare(_s: Dictionary) -> void:
	main.world.submit({"op": "wipe"})
	await _frames(3)


## With `bounded` false the garden takes builds past the frame budget, as the stress scene must; true holds it again.
func _budget(s: Dictionary) -> void:
	main.world.bounded = s.bounded


## Prints what the garden's builds count as in the frame budget, and the share of it they take on each headset.
func _units(_s: Dictionary) -> void:
	var on := {}
	for d in Budget.Device.size():
		on[Budget.Device.keys()[d]] = snappedf(Budget.cost_ms(main.world.units, d), 0.01)
	print("budget: %s units %s ms %s fill %.3f" % [main.metrics.info.label, JSON.stringify(main.world.units), JSON.stringify(on), main.world.fill()])
