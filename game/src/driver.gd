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
	w.rebuild()


func _top(s: Dictionary) -> void:
	var w: Wall = main.tool.walls[s.index]
	if w.roof != null:
		return
	while w.layout.top != WallLayout.Top[s.style.to_upper()]:
		main.tool.cycle_top(w)


func _lift_wall(s: Dictionary) -> void:
	var w: Wall = main.tool.walls[s.index]
	w.layout.height = s.height
	w.rebuild()


func _arch(s: Dictionary) -> void:
	main.tool.toggle_arch(main.tool.walls[s.index], s.s)


## A press of the windows or decorations tool on wall `index` (-1 the last drawn), as `FittingTool.aim` would find it: `what` is
## window, lantern, flag, chimney or tower_flag; `s` and `y` place it on the wall, `side` picks a lantern's
## face, `at` a chimney's spot along and across the ridge.
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
		flora_tool.paint(b, _along(path, minf(t / seconds, 1.0)), s.radius, dt)
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


func _music(s: Dictionary) -> void:
	main.sound.play_from(s.section)


func _view(s: Dictionary) -> void:
	main.view(Vector3(s.eye[0], s.eye[1], s.eye[2]), Vector3(s.at[0], s.at[1], s.at[2]), s.get("relative", false))
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
