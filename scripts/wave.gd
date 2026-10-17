extends SceneTree

## Converts CMU 141_16's recorded hands to controller aim poses. No pose is authored here.
## godot4 --headless --path game --script ../scripts/wave.gd
const SOURCE := "res://../third_party/cmu-wave/"


func rotation(degrees: Array) -> Basis:
	return Basis(Vector3.BACK, deg_to_rad(degrees[2])) * Basis(Vector3.UP, deg_to_rad(degrees[1])) * Basis(Vector3.RIGHT, deg_to_rad(degrees[0]))


func _initialize() -> void:
	var bones := {}
	var parents := {}
	var section := ""
	var bone := {}
	for line in FileAccess.get_file_as_string(SOURCE + "141.asf").split("\n"):
		var words := line.strip_edges().split(" ", false)
		if words.is_empty():
			continue
		if words[0].begins_with(":"):
			section = words[0]
		if section == ":bonedata":
			match words[0]:
				"begin": bone = {"dof": []}
				"name": bone.name = words[1]
				"direction": bone.direction = Vector3(float(words[1]), float(words[2]), float(words[3]))
				"length": bone.length = float(words[1])
				"axis": bone.axis = rotation([float(words[1]), float(words[2]), float(words[3])])
				"dof": bone.dof = Array(words.slice(1))
				"end": bones[bone.name] = bone
		elif section == ":hierarchy" and words.size() > 1:
			for child in words.slice(1):
				parents[child] = words[0]
	var frames: Array[Dictionary] = []
	for line in FileAccess.get_file_as_string(SOURCE + "141_16.amc").split("\n"):
		var words := line.strip_edges().split(" ", false)
		if words.is_empty() or words[0].begins_with("#") or words[0].begins_with(":"):
			continue
		if words.size() == 1:
			frames.append({})
		else:
			frames[-1][words[0]] = Array(words.slice(1)).map(func(v: String) -> float: return float(v))
	var animation := Animation.new()
	animation.length = (frames.size() - 1) / 120.0
	for side in ["left", "right"]:
		for type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
			var track := animation.add_track(type)
			animation.track_set_path(track, NodePath(side))
	var scale := 0.0
	for i in frames.size():
		var f := frames[i]
		var r: Array = f.root
		var poses := {"root": Transform3D(rotation(r.slice(3)), Vector3(r[0], r[1], r[2]))}
		for name: String in parents:
			var b: Dictionary = bones[name]
			var angles := [0.0, 0.0, 0.0]
			for j in b.dof.size():
				angles[["rx", "ry", "rz"].find(b.dof[j])] = f[name][j]
			var basis: Basis = poses[parents[name]].basis * b.axis * rotation(angles) * b.axis.inverse()
			poses[name] = Transform3D(basis, poses[parents[name]].origin + basis * b.direction * b.length)
		var head: Vector3 = poses.head.origin
		if i == 0:
			var floor_y := minf(poses.ltoes.origin.y, poses.rtoes.origin.y)
			scale = Rig.EYE / (head.y - floor_y)
		# ASF faces +Z. Remove the actor's heading; the player's yaw supplies it in game.
		var forward: Vector3 = poses.root.basis * Vector3.BACK
		var level := Basis(Vector3.UP, atan2(forward.x, forward.z))
		var facing := Basis(Vector3.UP, PI) * level.inverse()
		for s in 2:
			var name: String = ["lhand", "rhand"][s]
			var hand: Transform3D = poses[name]
			# T-pose hands point outward, palms down. This changes the coordinate frame to
			# a controller's -Z aim, with its inward palm; it does not change the motion.
			var aim := hand.basis * Basis.looking_at(bones[name].direction, Vector3.BACK)
			animation.position_track_insert_key(s * 2, i / 120.0, facing * (hand.origin - head) * scale)
			animation.rotation_track_insert_key(s * 2 + 1, i / 120.0, (facing * aim).get_rotation_quaternion())
	var error := ResourceSaver.save(animation, "res://animations/wave.tres")
	print("wave: %d captured frames at 120 Hz, %.3f seconds; save %d" % [frames.size(), animation.length, error])
	quit(error)
