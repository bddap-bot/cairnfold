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
	main.rig.place(_ground(s.x, s.z), s.get("lift", 0.0))


func _teleport(s: Dictionary) -> void:
	main.rig.teleport(_ground(s.x, s.z), s.get("lift", 0.0))
	await get_tree().create_timer(s.get("seconds", 2.0)).timeout


func _wall(s: Dictionary) -> void:
	var pts: Array = s.points
	var tool: WallTool = main.tool
	tool.begin_stroke(_ground(pts[0][0], pts[0][1]))
	var path: Array[Vector3] = []
	for p in pts:
		path.append(_ground(p[0], p[1]))
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	var seconds: float = s.get("seconds", 2.0)
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		var p := _along(path, total * clampf(t / seconds, 0.0, 1.0))
		tool.extend_stroke(p)
	tool.end_stroke()


func _lift_wall(s: Dictionary) -> void:
	var w: Wall = main.tool.walls[s.index]
	w.layout.height = s.height
	w.rebuild()


func _arch(s: Dictionary) -> void:
	main.tool.toggle_arch(main.tool.walls[s.index], s.s)


func _view(s: Dictionary) -> void:
	main.view(Vector3(s.eye[0], s.eye[1], s.eye[2]), Vector3(s.at[0], s.at[1], s.at[2]), s.get("relative", false))
	await get_tree().process_frame


func _capture(s: Dictionary) -> void:
	await main.capture(s.name)


func _quit(_s: Dictionary) -> void:
	main.finish()


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, Terrain.height_at(x, z), z)


static func _along(path: Array[Vector3], d: float) -> Vector3:
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
