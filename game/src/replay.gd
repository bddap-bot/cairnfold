class_name Replay
extends RefCounted

## One frame of what the player's devices gave the game, as a replay needs it (PlayLog keeps it beside the metrics):
## the frame's delta, then the head's pose, then for each hand of HANDS its controller's pose (`Hand.controller`, before
## any reach throws the hand out), its stick (`Hand.stick`), each of its INPUTS held or not (`Buttons.down`) as bit i of
## a u16, and its FLAGS as bits of a u8. Poses are in the play space, position then rotation quaternion (x, y, z, w);
## every number little-endian float32 but the two masks: a frame is HEAD then a HAND per hand, as Python's struct lays
## them out, FRAME_BYTES in all. Only what reaches `Hand` is kept: a flat-screen session's keys and mouse are not.
const HEAD := "<f7f"
const HAND := "<7f2fHB"
const HANDS := ["left_hand", "right_hand"]
const FLAGS := ["tracked", "bare"]
const POSE_BYTES := 28
const HAND_BYTES := POSE_BYTES + 8 + 2 + 1
const FRAME_BYTES := 4 + POSE_BYTES + 2 * HAND_BYTES
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
	var out := PackedByteArray()
	out.resize(FRAME_BYTES)
	out.encode_float(0, delta)
	_pose(out, 4, head.transform)
	for i in HANDS.size():
		var h: Hand = hands[i]
		var at := 4 + POSE_BYTES + i * HAND_BYTES
		_pose(out, at, h.controller)
		var s := h.stick()
		out.encode_float(at + POSE_BYTES, s.x)
		out.encode_float(at + POSE_BYTES + 4, s.y)
		var held := 0
		var names := inputs(h.tracker)
		for b in names.size():
			if Buttons.down(h, names[b]):
				held |= 1 << b
		out.encode_u16(at + POSE_BYTES + 8, held)
		out.encode_u8(at + POSE_BYTES + 10, int(h.tracked()) | int(h.bare) << 1)
	return out


static func _pose(out: PackedByteArray, at: int, t: Transform3D) -> void:
	var q := t.basis.get_rotation_quaternion()
	var values := [t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w]
	for k in values.size():
		out.encode_float(at + 4 * k, values[k])


## The frames a record's "input" event holds, decoded back to the bytes `frame` wrote.
static func frames(event: Dictionary) -> PackedByteArray:
	return Marshalls.base64_to_raw(event.data).decompress(int(event.bytes), FileAccess.COMPRESSION_DEFLATE)
