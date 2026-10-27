extends SceneTree

## Converts CMU recordings (LICENSE-CMU) into what avatars play, authoring no pose: trial 141_16's recorded hands
## into controller aim poses for the flat-screen wave (animations/wave.tres), and single recorded frames of people
## lying and sitting into body poses (animations/poses.json), each bone's turn from the recording's T-pose as it was
## captured.
## godot4 --headless --path game --script ../scripts/mocap.gd
const SOURCE := "res://../third_party/cmu/"
## Each pose: its name, the trial, the frame as the AMC file numbers it, whether it is the recording mirrored left for
## right, and whether it sits on a support with the feet on lower ground.
const POSES := [
	["back", "140_08", 1, false, false],
	["side", "140_03", 1, false, false],
	["side, mirrored", "140_03", 1, true, false],
	["front", "140_01", 1, false, false],
	["sitting, hands forward", "82_05", 1, false, false],
	["sitting, leaning back", "82_05", 2197, false, false],
	["sitting on a ledge", "14_31", 721, false, true],
]
## The recording's bone for each humanoid bone a pose turns. The head and hands follow tracking instead; the upper
## arm is kept to say which way the elbow points.
const BONES := {
	"hips": "root", "spine": "lowerback", "chest": "upperback", "upperChest": "thorax", "neck": "lowerneck",
	"leftShoulder": "lclavicle", "leftUpperArm": "lhumerus", "leftUpperLeg": "lfemur", "leftLowerLeg": "ltibia",
	"leftFoot": "lfoot", "leftToes": "ltoes",
	"rightShoulder": "rclavicle", "rightUpperArm": "rhumerus", "rightUpperLeg": "rfemur", "rightLowerLeg": "rtibia",
	"rightFoot": "rfoot", "rightToes": "rtoes",
}
## The recordings face +Z; a Godot camera, and so a standing player, looks down -Z.
const TURN := Basis(Vector3.UP, PI)


func rotation(degrees: Array) -> Basis:
	return Basis(Vector3.BACK, deg_to_rad(degrees[2])) * Basis(Vector3.UP, deg_to_rad(degrees[1])) * Basis(Vector3.RIGHT, deg_to_rad(degrees[0]))


## An ASF skeleton: {bones: name -> {direction, length, axis, dof}, parents: name -> parent}.
func skeleton(file: String) -> Dictionary:
	var bones := {}
	var parents := {}
	var section := ""
	var bone := {}
	for line in FileAccess.get_file_as_string(SOURCE + file).split("\n"):
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
	return {"bones": bones, "parents": parents}


## An AMC file's frames, each bone name to its channel values.
func frames(file: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in FileAccess.get_file_as_string(SOURCE + file).split("\n"):
		var words := line.strip_edges().split(" ", false)
		if words.is_empty() or words[0].begins_with("#") or words[0].begins_with(":"):
			continue
		if words.size() == 1:
			out.append({})
		else:
			out[-1][words[0]] = Array(words.slice(1)).map(func(v: String) -> float: return float(v))
	return out


## Each bone in one frame: its turn from the T-pose, at the bone's far end. An empty frame is the T-pose.
func posed(skel: Dictionary, f: Dictionary) -> Dictionary:
	var r: Array = f.get("root", [0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var poses := {"root": Transform3D(rotation(r.slice(3)), Vector3(r[0], r[1], r[2]))}
	for name: String in skel.parents:
		var b: Dictionary = skel.bones[name]
		var angles := [0.0, 0.0, 0.0]
		for j in b.dof.size() if f.has(name) else 0:
			angles[["rx", "ry", "rz"].find(b.dof[j])] = f[name][j]
		var basis: Basis = poses[skel.parents[name]].basis * b.axis * rotation(angles) * b.axis.inverse()
		poses[name] = Transform3D(basis, poses[skel.parents[name]].origin + basis * b.direction * b.length)
	return poses


## Where the eyes are taken to be: the middle of the recorded head, looking as it faces (the camera's -Z).
func eyes(skel: Dictionary, poses: Dictionary) -> Transform3D:
	var head: Transform3D = poses.head
	return Transform3D(head.basis * TURN, (poses[skel.parents.head].origin + head.origin) * 0.5)


func _initialize() -> void:
	var error := _wave()
	if error == OK:
		error = _poses()
	quit(error)


func _wave() -> Error:
	var skel := skeleton("141.asf")
	var recorded := frames("141_16.amc")
	var animation := Animation.new()
	animation.length = (recorded.size() - 1) / 120.0
	for side in ["left", "right"]:
		for type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
			var track := animation.add_track(type)
			animation.track_set_path(track, NodePath(side))
	var scale := 0.0
	for i in recorded.size():
		var poses := posed(skel, recorded[i])
		var head: Vector3 = poses.head.origin
		if i == 0:
			var floor_y := minf(poses.ltoes.origin.y, poses.rtoes.origin.y)
			scale = Rig.EYE / (head.y - floor_y)
		# Remove the actor's heading; the player's yaw supplies it in game.
		var forward: Vector3 = poses.root.basis * Vector3.BACK
		var level := Basis(Vector3.UP, atan2(forward.x, forward.z))
		var facing := TURN * level.inverse()
		for s in 2:
			var name: String = ["lhand", "rhand"][s]
			var hand: Transform3D = poses[name]
			# T-pose hands point outward, palms down. This changes the coordinate frame to
			# a controller's -Z aim, with its inward palm; it does not change the motion.
			var aim := hand.basis * Basis.looking_at(skel.bones[name].direction, Vector3.BACK)
			animation.position_track_insert_key(s * 2, i / 120.0, facing * (hand.origin - head) * scale)
			animation.rotation_track_insert_key(s * 2 + 1, i / 120.0, (facing * aim).get_rotation_quaternion())
	var error := ResourceSaver.save(animation, "res://animations/wave.tres")
	print("wave: %d captured frames at 120 Hz, %.3f seconds; save %d" % [recorded.size(), animation.length, error])
	return error


## Each pose as poses.json keeps it, in metres on a floor at y = 0, its heading removed and the actor turned to face
## -Z: `bones`, each humanoid bone's turn from the T-pose as a quaternion [x, y, z, w]; `eyes`, the eyes' basis
## columns then origin; `hands`, the left and right hands; `seat`, for a pose on a support, the hips' height, else 0.
func _poses() -> Error:
	var out := []
	var skeletons := {}
	var recordings := {}
	for p: Array in POSES:
		var subject: String = p[1].get_slice("_", 0)
		if not skeletons.has(subject):
			skeletons[subject] = skeleton(subject + ".asf")
		if not recordings.has(p[1]):
			recordings[p[1]] = frames(p[1] + ".amc")
		var skel: Dictionary = skeletons[subject]
		var rest := posed(skel, {})
		var scale: float = Rig.EYE / (eyes(skel, rest).origin.y - minf(rest.ltoes.origin.y, rest.rtoes.origin.y))
		var poses := posed(skel, recordings[p[1]][p[2] - 1])
		if p[3]:
			poses = _mirrored(poses)
		var floor_y: float = poses.values().reduce(func(m: float, t: Transform3D) -> float: return minf(m, t.origin.y), INF)
		var at := eyes(skel, poses)
		var forward := at.basis * Vector3.FORWARD
		var flat: Vector3 = Vector3(forward.x, 0, forward.z) if Vector2(forward.x, forward.z).length() > 0.3 else (poses.head.origin - poses.root.origin) * Vector3(1, 0, 1)
		# The heading the eyes face, or along the body from the hips to the head while they look up or down, turned to -Z.
		var level := Basis(Vector3.UP, atan2(-flat.x, -flat.z)).inverse()
		var place := func(v: Vector3) -> Vector3: return level * Vector3(v.x - at.origin.x, (v.y - floor_y), v.z - at.origin.z) * scale
		var bones := {}
		for b: String in BONES:
			var q := (level * (poses[BONES[b]] as Transform3D).basis * TURN).get_rotation_quaternion()
			bones[b] = [q.x, q.y, q.z, q.w]
		var e := Transform3D(level * at.basis, place.call(at.origin))
		var hands := [place.call(poses.lhand.origin), place.call(poses.rhand.origin)]
		out.append({
			"name": p[0], "trial": p[1], "frame": p[2], "mirrored": p[3], "bones": bones,
			"eyes": [e.basis.x.x, e.basis.x.y, e.basis.x.z, e.basis.y.x, e.basis.y.y, e.basis.y.z, e.basis.z.x, e.basis.z.y, e.basis.z.z, e.origin.x, e.origin.y, e.origin.z],
			"hands": hands.map(func(v: Vector3) -> Array: return [v.x, v.y, v.z]),
			"seat": (poses.root.origin.y - floor_y) * scale if p[4] else 0.0,
		})
		print("poses: %s from %s frame %d%s: eyes %.2f m up" % [p[0], p[1], p[2], ", mirrored" if p[3] else "", e.origin.y])
	var f := FileAccess.open("res://animations/poses.json", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(out, "\t") + "\n")
	return OK


## The same frame with left and right swapped, reflected through the actor's middle (the YZ plane in T-pose).
func _mirrored(poses: Dictionary) -> Dictionary:
	var m := Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3.BACK)
	var out := {}
	for name: String in poses:
		var other := name
		if name.begins_with("l") and poses.has("r" + name.substr(1)) and name != "lowerback" and name != "lowerneck":
			other = "r" + name.substr(1)
		elif name.begins_with("r") and poses.has("l" + name.substr(1)) and name != "root":
			other = "l" + name.substr(1)
		var t: Transform3D = poses[name]
		out[other] = Transform3D(m * t.basis * m, m * t.origin)
	return out
