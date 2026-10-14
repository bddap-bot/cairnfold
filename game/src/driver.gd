class_name Driver
extends Node

## Plays a JSON list of steps through the same rig and tool entry points the controllers use.

var main: Node
var steps: Array


func _init(owner: Node, path: String) -> void:
	main = owner
	steps = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(steps is Array, "script %s is not a JSON array" % path)


func _ready() -> void:
	_run()


func _run() -> void:
	for step in steps:
		print("driver: ", step)
		await call("_" + step.op, step)
	print("driver: done")


func _wait(s: Dictionary) -> void:
	await get_tree().create_timer(s.seconds).timeout


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
	var tool: WallTool = main.tool
	var path := _path(s)
	tool.begin_stroke(path[0])
	var frames := maxi(1, ceili(s.get("seconds", 2.0) * 60.0))
	for f in frames:
		await get_tree().process_frame
		tool.extend_stroke(_along(path, float(f + 1) / frames))
	tool.end_stroke()


func _lift_wall(s: Dictionary) -> void:
	var w: Wall = main.tool.walls[s.index]
	w.layout.height = s.height
	w.rebuild()


func _arch(s: Dictionary) -> void:
	main.tool.toggle_arch(main.tool.walls[s.index], s.s)


func _paint(s: Dictionary) -> void:
	var flora_tool: FloraTool = main.flora_tool
	flora_tool.set_mode(FloraTool.Mode[s.mode.to_upper()])
	var path := _path(s)
	var t := 0.0
	var seconds: float = s.get("seconds", 2.0)
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		flora_tool.paint(_along(path, minf(t / seconds, 1.0)), s.radius, dt)


func _tree(s: Dictionary) -> void:
	main.flora_tool.plant_tree(_spot(s, s.x, s.z))


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
