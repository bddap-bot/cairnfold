extends RefCounted

## XXH64 with seed 0, by which Unity names the objects it imports from a model since 2019: an object's file ID is the
## hash of "Type:<its type>-><its path><how many earlier objects share that path>".

const P1 := -7046029288634856825
const P2 := -4417276706812531889
const P3 := 1609587929392839161
const P4 := -8796714831421723037
const P5 := 2870177450012600261


static func hash64(data: PackedByteArray) -> int:
	var n := data.size()
	var at := 0
	var h: int
	if n >= 32:
		var v := [P1 + P2, P2, 0, -P1]
		while at + 32 <= n:
			for i in 4:
				v[i] = _round(v[i], data.decode_s64(at))
				at += 8
		h = _rotl(v[0], 1) + _rotl(v[1], 7) + _rotl(v[2], 12) + _rotl(v[3], 18)
		for i in 4:
			h = (h ^ _round(0, v[i])) * P1 + P4
	else:
		h = P5
	h += n
	while at + 8 <= n:
		h = _rotl(h ^ _round(0, data.decode_s64(at)), 27) * P1 + P4
		at += 8
	if at + 4 <= n:
		h = _rotl(h ^ (data.decode_u32(at) * P1), 23) * P2 + P3
		at += 4
	while at < n:
		h = _rotl(h ^ (data[at] * P5), 11) * P1
		at += 1
	h = (h ^ _shr(h, 33)) * P2
	h = (h ^ _shr(h, 29)) * P3
	return h ^ _shr(h, 32)


## The file ID Unity gives the model object of `type` at `path`, the `dupe`th to share both.
static func file_id(type: String, path: String, dupe: int) -> int:
	return hash64(("Type:%s->%s%d" % [type, path, dupe]).to_utf8_buffer())


static func _round(acc: int, input: int) -> int:
	return _rotl(acc + input * P2, 31) * P1


static func _rotl(x: int, r: int) -> int:
	return (x << r) | _shr(x, 64 - r)


static func _shr(x: int, r: int) -> int:
	return (x >> r) & ((1 << (64 - r)) - 1)
