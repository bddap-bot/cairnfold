class_name Replay
extends RefCounted

## A frame, as Python's struct lays out HEAD then a HAND per hand of HANDS: the delta, the head's pose, then per hand its
## pose, stick, `inputs` held as bit i of a u16, FLAGS as bits of a u8, and its palm's pose in the hand's own space.
## Other poses are in play space, basis columns then origin, little-endian float32 as the engine holds them, so a replay
## puts head and hands exactly. Only what reaches `Hand` is kept: not a flat-screen session's keys and mouse.
const HEAD := "<d12f"
const HAND := "<12f2fHB12f"
const HANDS := ["left_hand", "right_hand"]
const FLAGS := ["tracked", "bare"]
const CHECK_EVERY := 60
const DELTA_BYTES := 8
const POSE_BYTES := 48
const HAND_BYTES := POSE_BYTES + 8 + 2 + 1 + POSE_BYTES
const FRAME_BYTES := DELTA_BYTES + POSE_BYTES + 2 * HAND_BYTES
static var _inputs := {}


## In the order their bits take.
static func inputs(tracker: String) -> Array:
	if not _inputs.has(tracker):
		var out := []
		for action in Controls.ACTIONS:
			var input: String = Controls.ACTIONS[action].get(tracker, "")
			if input != "" and not input in out:
				out.append(input)
		assert(out.size() <= 16, "a hand's inputs outgrow the frame's u16 mask")
		_inputs[tracker] = out
	return _inputs[tracker]


## Written into each record's metadata, so a reader decodes frames recorded by another build.
static func layout() -> Dictionary:
	var by_hand := {}
	for tracker in HANDS:
		by_hand[tracker] = inputs(tracker)
	return {"frame_bytes": FRAME_BYTES, "head": HEAD, "hand": HAND, "hands": HANDS, "inputs": by_hand, "flags": FLAGS}


static func frame(delta: float, head: Node3D, hands: Array[Hand]) -> PackedByteArray:
	var out := PackedFloat64Array([delta]).to_byte_array()
	out.append_array(_pose_bytes(head.transform))
	for i in HANDS.size():
		var h: Hand = hands[i]
		var held := 0
		var names := inputs(h.tracker)
		for b in names.size():
			if Buttons.down(h, names[b]):
				held |= 1 << b
		var s := h.stick()
		out.append_array(_pose_bytes(h.transform))
		out.append_array(PackedFloat32Array([s.x, s.y]).to_byte_array())
		out.append_array(PackedByteArray([held & 0xff, held >> 8, int(h.tracked()) | int(h.bare) << 1]))
		out.append_array(_pose_bytes(h.palm))
	return out


static func _pose_bytes(t: Transform3D) -> PackedByteArray:
	var b := t.basis
	var o := t.origin
	return PackedFloat32Array([b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]).to_byte_array()


static func pose(raw: PackedByteArray, at: int) -> Transform3D:
	var v: Array[Vector3] = []
	for k in 4:
		v.append(Vector3(raw.decode_float(at + 12 * k), raw.decode_float(at + 12 * k + 4), raw.decode_float(at + 12 * k + 8)))
	return Transform3D(Basis(v[0], v[1], v[2]), v[3])


## Frame `i` of `raw`: "delta", "head", and "hands" of "pose", "stick", "held" (input -> bool), "flags" (FLAGS name ->
## bool) and "palm". `names`: each hand's inputs in bit order as the record lists them, by default this build's.
static func unpack(raw: PackedByteArray, i: int, names := {}) -> Dictionary:
	var at := i * FRAME_BYTES
	var out := {"delta": raw.decode_double(at), "head": pose(raw, at + DELTA_BYTES), "hands": []}
	for h in HANDS.size():
		var o := at + DELTA_BYTES + POSE_BYTES + h * HAND_BYTES
		var mask := raw.decode_u16(o + POSE_BYTES + 8)
		var bits := raw.decode_u8(o + POSE_BYTES + 10)
		var held := {}
		var bits_of: Array = names.get(HANDS[h], inputs(HANDS[h]))
		for b in bits_of.size():
			held[bits_of[b]] = mask & 1 << b != 0
		var flags := {}
		for b in FLAGS.size():
			flags[FLAGS[b]] = bits & 1 << b != 0
		out.hands.append({"pose": pose(raw, o), "stick": Vector2(raw.decode_float(o + POSE_BYTES), raw.decode_float(o + POSE_BYTES + 4)),
			"held": held, "flags": flags, "palm": pose(raw, o + POSE_BYTES + 11)})
	return out


static func deflated(raw: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))


## `bytes` is the length before `deflated`.
static func inflated(data: String, bytes: Variant) -> PackedByteArray:
	return Marshalls.base64_to_raw(data).decompress(int(bytes), FileAccess.COMPRESSION_DEFLATE)


## Each [frame, from, whose, call, args], as PlayLog.heard keeps them.
static func messages(event: Dictionary) -> Array:
	var args: Array = bytes_to_var(inflated(event.data, event.bytes))
	var out := []
	for i in event.messages.size():
		var m: Array = event.messages[i]
		out.append([int(m[0]), int(m[1]), int(m[2]), str(m[3]), args[i]])
	return out


## `path` is any chunk of the session. Keys: "session", "revision", "seeds", "garden", "frames" (`frame`s end to end),
## "inputs" (`unpack`'s names), "messages", "checks" (digests, each with its "frame", oldest first), and "avatars", worn
## files' bytes by hash from the folder `avatars`, as the record keeps only hashes; {"error": why} if not replayable.
static func read(path: String, avatars := "") -> Dictionary:
	var folder := path.get_base_dir()
	var session := path.get_file().get_basename().rsplit("-", true, 1)[0]
	var names := Array(DirAccess.get_files_at(folder)).filter(func(f: String) -> bool: return f.begins_with(session + "-") and f.ends_with(".jsonl"))
	names.sort()
	var out := {"session": session, "frames": PackedByteArray(), "messages": [], "checks": []}
	var inputs := []
	var nets := []
	var frame_layout: Dictionary = JSON.parse_string(JSON.stringify(layout().merged({"inputs": null}, true)))
	for name in names:
		for line in FileAccess.get_file_as_string(folder.path_join(name)).split("\n", false):
			var e: Variant = JSON.parse_string(line)
			if not e is Dictionary:
				continue
			match e.get("event"):
				"start":
					if e.get("schema") != PlayLog.SCHEMA:
						return {"error": "%s is a record of schema %s, this build reads schema %d" % [path, e.get("schema"), PlayLog.SCHEMA]}
					if e.input.merged({"inputs": null}, true) != frame_layout:
						return {"error": "%s lays its frames out as this build does not under the same schema: a new frame takes a new PlayLog.SCHEMA" % path}
					if e.get("events") != Replayer.events():
						return {"error": "%s holds events and messages as this build does not deliver them: %s, this build %d" % [path, e.get("events"), Replayer.events()]}
					out.revision = e.revision
					out.inputs = e.input.inputs
				"replay":
					out.seeds = e.seeds
					out.garden = bytes_to_var(inflated(e.save, e.save_bytes))
				"input":
					inputs.append(e)
				"net":
					nets.append(e)
				"checks":
					out.checks.append_array(e.checks)
	if not out.has("seeds"):
		return {"error": "%s holds no seeds and starting garden: a chunk is missing, or it is no record" % path}
	inputs.sort_custom(func(a, b) -> bool: return a.first < b.first)
	nets.sort_custom(func(a, b) -> bool: return a.first < b.first)
	out.checks.sort_custom(func(a, b) -> bool: return a.frame < b.frame)
	if out.checks.any(func(c: Dictionary) -> bool: return c.has("garden") and not (c.has("heard") and c.has("turn"))):
		return {"error": "%s keeps its gardens without where among its messages and its frame each was kept, by which this build compares them" % path}
	for e in inputs:
		if int(e.first) * FRAME_BYTES != out.frames.size():
			return {"error": "%s lost frames %d to %d" % [path, out.frames.size() / FRAME_BYTES, int(e.first) - 1]}
		out.frames.append_array(inflated(e.data, e.bytes))
	for e in nets:
		if int(e.first) != out.messages.size():
			return {"error": "%s lost messages %d to %d" % [path, out.messages.size(), int(e.first) - 1]}
		out.messages.append_array(messages(e))
	out.avatars = {}
	var held := {}
	for m: Array in out.messages:
		if m[3] != "look" or not m[4][0] is Dictionary:
			continue
		if held.is_empty() and avatars != "":
			for f in DirAccess.get_files_at(avatars):
				if f.get_extension().to_lower() == "vrm":
					var bytes := Avatar.file_bytes(avatars.path_join(f))
					if not bytes.is_empty():
						held[Session.sha256(bytes)] = bytes
		if not held.has(m[4][0].sha256):
			return {"error": "%s wears avatar file %s, which %s does not hold: pass the avatars folder of the device that recorded it (--avatars)" % [path, m[4][0].sha256, "the folder " + avatars if avatars != "" else "no folder"]}
		out.avatars[m[4][0].sha256] = held[m[4][0].sha256]
	return out


## Each part game logic moves on its own, so a replay can say which diverged: "player" the play space, "wildlife" its
## nodes and every `rng` held there, "physics" every thrown handful's flight. The record keeps each part's `digest`.
static func check(main: Main) -> Dictionary:
	var wild := PackedFloat32Array()
	var drawn := PackedInt64Array()
	for n: Node in [main.wildlife] + main.wildlife.find_children("*", "", true, false):
		if n is Node3D:
			wild.append_array(_floats(n.transform))
		if n.get("rng") is RandomNumberGenerator:
			drawn.append(n.rng.state)
	var thrown := PackedFloat32Array()
	for h: Handful in main.feed_tool.handfuls:
		thrown.append_array(_floats(h.transform))
		thrown.append(h.age)
	return {"player": _floats(main.rig.transform).to_byte_array(), "wildlife": wild.to_byte_array() + drawn.to_byte_array(),
		"physics": thrown.to_byte_array()}


## Must match how PlayLog digests World's `kept` snapshot bytes.
static func garden(world: World) -> String:
	return digest(var_to_bytes(world.snapshot()))


static func digest(bytes: PackedByteArray) -> String:
	return Session.sha256(bytes).left(16)


static func _floats(t: Transform3D) -> PackedFloat32Array:
	return _pose_bytes(t).to_float32_array()
