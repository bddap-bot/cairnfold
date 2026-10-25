class_name PhotoMeta

## Where and how a photo was taken, written into its PNG and read back. Any PNG reader shows `Software`; the rest is
## an iTXt chunk keyed `nestcombe` holding JSON (`about`), and, when it fits in WORLD_MAX, the whole garden as World
## keeps it (World.snapshot), zstd-packed in a private chunk, so the photo can be opened as the garden it shows.

const KEY := "nestcombe"
const WORLD_CHUNK := "neSt"
## Bytes of packed garden a photo carries at most; a bigger garden is left out and `about.world` says why.
const WORLD_MAX := 4 << 20
## The largest unpacked garden read back, so a damaged or hostile photo cannot ask for any amount of memory.
const RAW_MAX := 64 << 20
const _SIGNATURE := [137, 80, 78, 71, 13, 10, 26, 10]


## `png` with `about` and, if it fits, `world` (var_to_bytes of World.snapshot) written into it. Sets `about.world` to
## what became of the garden: "embedded" with its packed size, or "left out" and why.
static func embed(png: PackedByteArray, about: Dictionary, world := PackedByteArray()) -> PackedByteArray:
	var packed := PackedByteArray()
	if world.is_empty():
		about.world = {"left out": "no garden given"}
	else:
		packed = _u32(world.size()) + world.compress(FileAccess.COMPRESSION_ZSTD)
		if packed.size() > WORLD_MAX:
			about.world = {"left out": "%d bytes packed, over %d" % [packed.size(), WORLD_MAX]}
			packed = PackedByteArray()
		else:
			about.world = {"embedded": packed.size()}
	var end := png.size() - 12
	assert(png.slice(end + 4, end + 8).get_string_from_ascii() == "IEND", "a PNG ends with IEND")
	var out := png.slice(0, end)
	out.append_array(_chunk("tEXt", ("Software".to_ascii_buffer() + PackedByteArray([0]) + ("Nestcombe " + str(about.get("build", ""))).to_utf8_buffer())))
	out.append_array(_chunk("iTXt", KEY.to_ascii_buffer() + PackedByteArray([0, 0, 0, 0, 0]) + JSON.stringify(about, "", false).to_utf8_buffer()))
	if not packed.is_empty():
		out.append_array(_chunk(WORLD_CHUNK, packed))
	out.append_array(png.slice(end))
	return out


## What `png` says of itself: {"about": Dictionary, "world": the garden or null}, or {} if it is no PNG this game
## wrote. A chunk whose checksum is wrong is ignored.
static func read(png: PackedByteArray) -> Dictionary:
	if png.size() < 8 or Array(png.slice(0, 8)) != _SIGNATURE:
		return {}
	var out := {}
	var at := 8
	while at + 12 <= png.size():
		var size := _read_u32(png, at)
		if at + 12 + size > png.size():
			break
		var type := png.slice(at + 4, at + 8)
		var data := png.slice(at + 8, at + 8 + size)
		at += 12 + size
		if _read_u32(png, at - 4) != crc32(type + data):
			continue
		match type.get_string_from_ascii():
			"iTXt":
				var key := KEY.to_ascii_buffer() + PackedByteArray([0, 0, 0, 0, 0])
				if data.slice(0, key.size()) == key:
					var about: Variant = JSON.parse_string(data.slice(key.size()).get_string_from_utf8())
					if about is Dictionary:
						out.about = about
			WORLD_CHUNK:
				var raw_size := _read_u32(data, 0) if data.size() > 4 else 0
				if raw_size > 0 and raw_size <= RAW_MAX:
					var raw := data.slice(4).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
					out.world = bytes_to_var(raw) if raw.size() == raw_size else null
	if not out.has("about"):
		return {}
	out.get_or_add("world", null)
	return out


## PNG's CRC-32, read off the trailer of the gzip stream the engine packs `data` into: a chunk a megabyte long sums in
## native code instead of a byte at a time.
static func crc32(data: PackedByteArray) -> int:
	var gz := data.compress(FileAccess.COMPRESSION_GZIP)
	return gz.decode_u32(gz.size() - 8)


## A 16-bit greyscale PNG `size` large of `samples`, two big-endian bytes a pixel row by row, saying `comment` of itself.
## Godot writes no PNG deeper than 8 bits. Each chunk's CRC (crc32) packs it once more, so this costs two deflates.
static func gray16(size: Vector2i, samples: PackedByteArray, comment: String) -> PackedByteArray:
	var row := size.x * 2
	var lines := PackedByteArray()
	for y in size.y:
		lines.append(0)
		lines.append_array(samples.slice(y * row, (y + 1) * row))
	var out := PackedByteArray(_SIGNATURE)
	out.append_array(_chunk("IHDR", _u32(size.x) + _u32(size.y) + PackedByteArray([16, 0, 0, 0, 0])))
	out.append_array(_chunk("tEXt", "Comment".to_ascii_buffer() + PackedByteArray([0]) + comment.to_utf8_buffer()))
	out.append_array(_chunk("IDAT", lines.compress(FileAccess.COMPRESSION_DEFLATE)))
	out.append_array(_chunk("IEND", PackedByteArray()))
	return out


static func _chunk(type: String, data: PackedByteArray) -> PackedByteArray:
	var t := type.to_ascii_buffer()
	return _u32(data.size()) + t + data + _u32(crc32(t + data))


static func _u32(n: int) -> PackedByteArray:
	return PackedByteArray([(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF])


static func _read_u32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]
