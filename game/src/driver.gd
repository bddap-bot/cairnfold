class_name Driver
extends Node

## Plays a JSON list of steps through the same rig and tool entry points the controllers use.

## The Steam Frame's buttons as SteamVR delivers them to a game bound through the Touch or Index
## profiles (its frame_controller remapping): B, X and Y all arrive as right-hand B.
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
}

signal finished

var main: Node
var steps: Array


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
		print("driver: ", step)
		await call("_" + step.op, step)
	print("driver: done")
	finished.emit()


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


## Takes a tool from a hand's ring as a player does: hold the stick click, push toward the tool, let go.
## "capture" saves a view while the ring is open, "popping" one the frame after the pick.
func _pick(s: Dictionary) -> void:
	var hand: Hand = _hand(s)
	var key := "%s/primary_click" % hand.tracker
	Buttons.injected[key] = true
	await _frames(3)
	var i := Hand.MENU.find(Hand.Tool[s.tool.to_upper()])
	Hand.injected_sticks[hand.tracker] = Hand.ring_dir(i)
	await _frames(3)
	if s.has("capture"):
		await main.capture(s.capture)
	Buttons.injected.erase(key)
	await _frames(1)
	if s.has("popping"):
		await main.capture(s.popping)
	await _frames(1)
	Hand.injected_sticks.erase(hand.tracker)
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
	await get_tree().process_frame


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


## Points the teleport ray from beside the head along `dir` (relative to the head's facing), holds it for `seconds`, optionally captures the aimed view, then goes.
func _aim(s: Dictionary) -> void:
	var rig: Rig = main.rig
	var head := rig.head.global_transform
	var dir: Vector3 = head.basis * Vector3(s.dir[0], s.dir[1], s.dir[2])
	var pose := Transform3D(Basis.looking_at(dir, Vector3.UP), head * Vector3(-0.2, -0.35, -0.25))
	rig.air_reach = s.get("reach", rig.air_reach)
	var t := 0.0
	while t < s.get("seconds", 1.0):
		rig.aim(pose)
		await get_tree().process_frame
		t += get_process_delta_time()
	if s.has("capture"):
		await main.capture(s.capture)
	if rig.aim_ground != null:
		rig.teleport(rig.aim_ground, rig.aim_lift)
	rig.hide_markers()
	await get_tree().create_timer(s.get("settle", 2.0)).timeout


func _wall(s: Dictionary) -> void:
	await _stroke(s, Hand.Tool.WALLS)


func _fence(s: Dictionary) -> void:
	await _stroke(s, Hand.Tool.FENCE)


func _stroke(s: Dictionary, held: Hand.Tool) -> void:
	var tool: WallTool = main.tool
	var m := tool.mason(_holding(s, held))
	var path := _path(s)
	tool.begin_stroke(m, path[0])
	var frames := maxi(1, ceili(s.get("seconds", 2.0) * 60.0))
	for f in frames:
		await get_tree().process_frame
		tool.extend_stroke(m, _along(path, float(f + 1) / frames))
	tool.end_stroke(m)


## Draws a loop and keeps holding at its end until it snaps to a tower.
func _tower(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var m := tool.mason(_holding(s, Hand.Tool.WALLS))
	var path := _path(s)
	tool.begin_stroke(m, path[0])
	var frames := maxi(1, ceili(s.get("seconds", 2.0) * 60.0))
	for f in frames:
		await get_tree().process_frame
		tool.extend_stroke(m, _along(path, float(f + 1) / frames))
	var held := 0.0
	while held < s.get("hold", 0.6):
		await get_tree().process_frame
		held += get_process_delta_time()
		tool.extend_stroke(m, path[-1])
	tool.end_stroke(m)


## Both grips: the hands point at `a` and `b`, then move to `to_a` and `to_b` (pulling apart, twisting) over `seconds`.
func _house(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	main.rig.left.tool = Hand.Tool.WALLS
	main.rig.right.tool = Hand.Tool.WALLS
	var a := _spot(s, s.a[0], s.a[1])
	var b := _spot(s, s.b[0], s.b[1])
	var to_a := _spot(s, s.to_a[0], s.to_a[1]) if s.has("to_a") else a
	var to_b := _spot(s, s.to_b[0], s.to_b[1]) if s.has("to_b") else b
	tool.begin_house(a, b)
	var t := 0.0
	var seconds: float = s.get("seconds", 2.0)
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := minf(t / seconds, 1.0)
		tool.size_house(a.lerp(to_a, k), b.lerp(to_b, k))
	tool.end_house()


func _roof(s: Dictionary) -> void:
	var w: Wall = main.tool.walls[s.index]
	main.tool.shape_roof(w, s.get("pitch", w.roof.pitch), s.get("curve", w.roof.curve))
	main.world.submit({"op": "reshape", "id": w.id, "data": {"roof": {"pitch": w.roof.pitch, "curve": w.roof.curve}}})


func _top(s: Dictionary) -> void:
	var w: Wall = main.tool.walls[s.index]
	if w.roof != null:
		return
	while w.layout.top != WallLayout.Top[s.style.to_upper()]:
		main.tool.cycle_top(w)


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
	var t := 0.0
	var seconds: float = s.get("seconds", 2.0)
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		flora_tool.paint(b, _along(path, minf(t / seconds, 1.0)), s.radius, dt, s.get("meadow", false))
	flora_tool.end_stroke(b)


## A stroke of the path tool from `hand` (left by default); `radius` is half the path's width.
func _pave(s: Dictionary) -> void:
	var flora_tool: FloraTool = main.flora_tool
	var b := flora_tool.brush(main.rig.left if s.get("hand", "left") == "left" else main.rig.right)
	b.hand.tool = Hand.Tool.PATH
	var path := _path(s)
	flora_tool.begin_path(b, path[0], s.radius)
	var frames := maxi(1, ceili(s.get("seconds", 2.0) * 60.0))
	for f in frames:
		await get_tree().process_frame
		flora_tool.extend_path(_along(path, float(f + 1) / frames), s.radius)
	flora_tool.end_path(b)


## Grabs the ground at x, z and pulls it `lift` metres over `seconds` (negative digs), as a hand on the terrain tool does.
func _sculpt(s: Dictionary) -> void:
	var tool: TerrainTool = main.terrain_tool
	tool.begin(_spot(s, s.x, s.z), s.get("radius", TerrainTool.MIN_RADIUS))
	var t := 0.0
	var seconds: float = s.get("seconds", 1.0)
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		tool.pull(s.lift * smoothstep(0.0, 1.0, minf(t / seconds, 1.0)))
		tool.follow(dt)
	tool.end_stroke()


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


## Points the delete tool straight down at a ground spot from `height` metres up and presses once.
func _delete(s: Dictionary) -> void:
	var at := _spot(s, s.x, s.z)
	var tool: DeleteTool = main.delete_tool
	tool.take(tool.aim(at + Vector3.UP * s.get("height", 2.0), Vector3.DOWN))
	await get_tree().process_frame


## Fills a disc at once with parallel walls (see StressLayout) of one height, their ivy fully grown.
func _stress(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var m := tool.mason(_holding(s, Hand.Tool.WALLS))
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


## Fills every painted and placed flora pool to capacity within `radius` of the centre.
func _fill_flora(s: Dictionary) -> void:
	var flora: Flora = main.flora_tool.flora
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in Flora.PAINTED_GRASS:
		flora.add_grass(_scatter(rng, s.radius), rng)
	for i in Flora.PAINTED_FLOWERS:
		flora.add_flower(_scatter(rng, s.radius), rng)
	for i in Flora.PLACED_TREES:
		flora.add_tree(_scatter(rng, s.radius), rng)


## Fills a disc at once with a grid of houses and round towers, `spacing` apart, alternating.
func _village(s: Dictionary) -> void:
	var tool: WallTool = main.tool
	var m := tool.mason(_holding(s, Hand.Tool.WALLS))
	var start := Time.get_ticks_usec()
	var r: float = s.radius
	var step: float = s.spacing
	var k := 0
	for z in range(-int(r / step), int(r / step) + 1):
		for x in range(-int(r / step), int(r / step) + 1):
			var c := Vector2(x, z) * step
			if c.length() > r - step * 0.5:
				continue
			k += 1
			if k % 2 == 0:
				tool.begin_house(Terrain.ground(c.x - step * 0.35, c.y), Terrain.ground(c.x + step * 0.35, c.y))
				tool.end_house()
				tool.walls[-1].ivy_age = INF
			else:
				var at := Terrain.ground(c.x, c.y)
				tool.begin_stroke(m, at)
				tool.snap_tower(m, at, step * 0.25)
				tool.end_stroke(m)
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
	var at: Vector3 = tool.figures[k].global_position + Vector3.UP * VisitTool.SIZE * 0.9
	var from: Vector3 = main.rig.head.global_position + Vector3(0.2, -0.3, 0)
	hand.global_transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)
	await _frames(1)
	var key := "%s/trigger_click" % hand.tracker
	Buttons.injected[key] = true
	await _frames(2)
	Buttons.injected.erase(key)
	await _frames(2)


## Waits until the garden has applied command `seq`, `players` share it, or with "heard" the host's beacon is heard, for at most `seconds`.
func _until(s: Dictionary) -> void:
	var t := 0.0
	while t < s.get("seconds", 20.0):
		var w: World = main.world
		if w.seq >= s.get("seq", 0) and main.session.players() >= s.get("players", 0) and (not s.get("heard", false) or main.session.nearby.keys().any(func(k: String) -> bool: return k.ends_with(":%d" % _host_port(s)))):
			return
		await get_tree().process_frame
		t += get_process_delta_time()
	push_error("driver: until %s timed out" % s)


## Writes `World.digest`, and how many other players' avatars stand here, to `name`.json in the capture
## directory, for comparing machines.
func _digest(s: Dictionary) -> void:
	var path: String = str(main.args.get("capture-dir", "user://captures")).path_join(s.name + ".json")
	var out: Dictionary = main.world.digest()
	out.avatars = main.session.avatars.values().filter(func(a: Avatar) -> bool: return a.visible).size()
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(out, " ", true))
	print("driver: digest ", path)


## Drags the sun from where it stands to `time` (0 dawn, 1 dusk) over `seconds`.
func _sun(s: Dictionary) -> void:
	var tool: SunTool = main.sun_tool
	var from: float = main.look.time
	var t := 0.0
	var seconds: float = s.get("seconds", 2.0)
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		tool.drag(lerpf(from, s.time, smoothstep(0.0, 1.0, minf(t / seconds, 1.0))))


## The colour picker on `element` (meadow, stone, roof, wood or plaster): opens its wheel on `hand`, twists
## to `swatch` over `seconds`, optionally captures the view with the wheel open, then lets go.
func _colour(s: Dictionary) -> void:
	var tool: PaletteTool = main.palette_tool
	var hand := _holding(s, Hand.Tool.COLOUR)
	var element: Palette.Element = Palette.Element[s.element.to_upper()]
	tool.open(hand, element)
	var from: int = main.world.palette.picks[element]
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


## With "ground", eye and target heights count from the ground under each.
func _view(s: Dictionary) -> void:
	var eye := Vector3(s.eye[0], s.eye[1], s.eye[2])
	var at := Vector3(s.at[0], s.at[1], s.at[2])
	if s.get("ground", false):
		eye.y += Terrain.height_at(eye.x, eye.z)
		at.y += Terrain.height_at(at.x, at.z)
	main.view(eye, at, s.get("relative", false))
	await get_tree().process_frame


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


func _label(s: Dictionary) -> void:
	main.metrics.info.label = s.name
