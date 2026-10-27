class_name Replay
extends RefCounted

## One frame of what the player's devices gave the game, as a replay needs it (PlayLog keeps it beside the metrics):
## the frame's delta, then the head's pose, then for each hand of HANDS its controller's pose (`Hand.controller`, before
## any reach throws the hand out), its stick (`Hand.stick`), each of its INPUTS held or not (`Buttons.down`) as bit i of
## a u16, and its FLAGS as bits of a u8 (`reaches` as `Hand.reaches` reads it, so a scripted hand replays held as it
## was). Poses are in the play space, the basis's three columns then the origin, each number as the engine holds it, so
## a replay puts the head and hands exactly where they were: every number little-endian float32 but the delta, a
## float64, and the two masks. A frame is HEAD then a HAND per hand, as Python's struct lays them out, FRAME_BYTES in
## all. Only what reaches `Hand` is kept: a flat-screen session's keys and mouse are not.
const HEAD := "<d12f"
const HAND := "<12f2fHB"
const HANDS := ["left_hand", "right_hand"]
const FLAGS := ["tracked", "bare", "reaches"]
const DELTA_BYTES := 8
const POSE_BYTES := 48
const HAND_BYTES := POSE_BYTES + 8 + 2 + 1
const FRAME_BYTES := DELTA_BYTES + POSE_BYTES + 2 * HAND_BYTES
static var _inputs := {}


## The inputs the controls table reads on hand `tracker`, in the order their bits take.
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


## How a frame is laid out, for a reader of the record.
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
		out.append_array(_pose_bytes(h.controller))
		out.append_array(PackedFloat32Array([s.x, s.y]).to_byte_array())
		out.append_array(PackedByteArray([held & 0xff, held >> 8, int(h.tracked()) | int(h.bare) << 1 | int(h.reaches()) << 2]))
	return out


## A pose's basis columns and origin as float32 bytes, which `pose` reads back.
static func _pose_bytes(t: Transform3D) -> PackedByteArray:
	var b := t.basis
	var o := t.origin
	return PackedFloat32Array([b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]).to_byte_array()


## The pose `frame` wrote at byte `at` of `raw`.
static func pose(raw: PackedByteArray, at: int) -> Transform3D:
	var v: Array[Vector3] = []
	for k in 4:
		v.append(Vector3(raw.decode_float(at + 12 * k), raw.decode_float(at + 12 * k + 4), raw.decode_float(at + 12 * k + 8)))
	return Transform3D(Basis(v[0], v[1], v[2]), v[3])


## Frame `i` of `raw` (`frame`'s bytes end to end): its "delta", "head" pose and per hand of HANDS its "pose",
## "stick", "held" (each of its inputs, by name, held or not) and its FLAGS by name.
static func unpack(raw: PackedByteArray, i: int) -> Dictionary:
	var at := i * FRAME_BYTES
	var out := {"delta": raw.decode_double(at), "head": pose(raw, at + DELTA_BYTES), "hands": []}
	for h in HANDS.size():
		var o := at + DELTA_BYTES + POSE_BYTES + h * HAND_BYTES
		var mask := raw.decode_u16(o + POSE_BYTES + 8)
		var bits := raw.decode_u8(o + POSE_BYTES + 10)
		var held := {}
		var names := inputs(HANDS[h])
		for b in names.size():
			held[names[b]] = mask & 1 << b != 0
		var flags := {}
		for b in FLAGS.size():
			flags[FLAGS[b]] = bits & 1 << b != 0
		out.hands.append({"pose": pose(raw, o), "stick": Vector2(raw.decode_float(o + POSE_BYTES), raw.decode_float(o + POSE_BYTES + 4)),
			"held": held, "flags": flags})
	return out


## The frames a record's "input" event holds, decoded back to the bytes `frame` wrote.
static func frames(event: Dictionary) -> PackedByteArray:
	return Marshalls.base64_to_raw(event.data).decompress(int(event.bytes), FileAccess.COMPRESSION_DEFLATE)


## The messages a record's "net" event holds (PlayLog.heard), each [frame, from, whose, call, args].
static func messages(event: Dictionary) -> Array:
	var args: Array = bytes_to_var(Marshalls.base64_to_raw(event.data).decompress(int(event.bytes), FileAccess.COMPRESSION_DEFLATE))
	var out := []
	for i in event.messages.size():
		var m: Array = event.messages[i]
		out.append([int(m[0]), int(m[1]), int(m[2]), str(m[3]), args[i]])
	return out


## The session a record holds, from every chunk of it in the folder of `path`, any one of them: its "session" id, its "seeds", the
## "garden" it started in, every frame's input as "frames" (`frame`'s bytes end to end) and every message it heard as
## "messages" (`messages`'), oldest first. With "error" instead, why this build cannot replay it whole.
static func read(path: String) -> Dictionary:
	var folder := path.get_base_dir()
	var session := path.get_file().get_basename().rsplit("-", true, 1)[0]
	var names := Array(DirAccess.get_files_at(folder)).filter(func(f: String) -> bool: return f.begins_with(session + "-") and f.ends_with(".jsonl"))
	names.sort()
	var out := {"session": session, "frames": PackedByteArray(), "messages": []}
	var inputs := []
	var nets := []
	var layout: Variant = JSON.parse_string(JSON.stringify(layout()))
	for name in names:
		for line in FileAccess.get_file_as_string(folder.path_join(name)).split("\n", false):
			var e: Variant = JSON.parse_string(line)
			if not e is Dictionary:
				continue
			match e.get("event"):
				"start":
					if e.revision != Main.revision():
						return {"error": "%s was recorded by build %s, this is %s" % [path, e.revision, Main.revision()]}
					if e.input != layout:
						return {"error": "%s lays its frames out as this build does not" % path}
				"replay":
					out.seeds = e.seeds
					out.garden = bytes_to_var(Marshalls.base64_to_raw(e.save).decompress(int(e.save_bytes), FileAccess.COMPRESSION_DEFLATE))
				"input":
					inputs.append(e)
				"net":
					nets.append(e)
	if not out.has("seeds"):
		return {"error": "%s holds no seeds and starting garden: the ring dropped them, or it is no record" % path}
	inputs.sort_custom(func(a, b) -> bool: return a.first < b.first)
	nets.sort_custom(func(a, b) -> bool: return a.first < b.first)
	for e in inputs:
		if int(e.first) * FRAME_BYTES != out.frames.size():
			return {"error": "%s lost frames %d to %d" % [path, out.frames.size() / FRAME_BYTES, int(e.first) - 1]}
		out.frames.append_array(frames(e))
	for e in nets:
		if int(e.first) != out.messages.size():
			return {"error": "%s lost messages %d to %d" % [path, out.messages.size(), int(e.first) - 1]}
		out.messages.append_array(messages(e))
	return out
