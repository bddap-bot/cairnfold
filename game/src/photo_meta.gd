class_name PhotoMeta

## `Software` for any PNG reader; JSON `about` in an iTXt keyed KEY; the garden as u32 raw size + zstd in WORLD_CHUNK.

const KEY := "cairnfold"
const WORLD_CHUNK := "neSt"
## Bytes, packed.
const WORLD_MAX := 4 << 20
## Bytes unpacked, so a damaged or hostile photo cannot ask for any amount of memory.
const RAW_MAX := 64 << 20
const _SIGNATURE := [137, 80, 78, 71, 13, 10, 26, 10]


## `world` is var_to_bytes(World.snapshot). Sets `about.world` to {"embedded": bytes} or {"left out": why}.
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
	out.append_array(_text("Software", "Cairnfold " + str(about.get("build", ""))))
	out.append_array(_chunk("iTXt", _itxt_head() + JSON.stringify(about, "", false).to_utf8_buffer()))
	if not packed.is_empty():
		out.append_array(_chunk(WORLD_CHUNK, packed))
	out.append_array(png.slice(end))
	return out


## {"about", "world" or null}, or {} for a PNG this game did not write.
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
				var key := _itxt_head()
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


## Off the gzip trailer, so a megabyte chunk sums in native code instead of a byte at a time.
static func crc32(data: PackedByteArray) -> int:
	var gz := data.compress(FileAccess.COMPRESSION_GZIP)
	return gz.decode_u32(gz.size() - 8)


## `samples` two big-endian bytes a pixel, row by row. Godot writes no PNG deeper than 8 bits.
static func gray16(size: Vector2i, samples: PackedByteArray, comment: String) -> PackedByteArray:
	var row := size.x * 2
	var lines := PackedByteArray()
	for y in size.y:
		lines.append(0)
		lines.append_array(samples.slice(y * row, (y + 1) * row))
	var out := PackedByteArray(_SIGNATURE)
	out.append_array(_chunk("IHDR", _u32(size.x) + _u32(size.y) + PackedByteArray([16, 0, 0, 0, 0])))
	out.append_array(_text("Comment", comment))
	out.append_array(_chunk("IDAT", lines.compress(FileAccess.COMPRESSION_DEFLATE)))
	out.append_array(_chunk("IEND", PackedByteArray()))
	return out


static func _chunk(type: String, data: PackedByteArray) -> PackedByteArray:
	var t := type.to_ascii_buffer()
	return _u32(data.size()) + t + data + _u32(crc32(t + data))


static func _text(keyword: String, text: String) -> PackedByteArray:
	return _chunk("tEXt", keyword.to_ascii_buffer() + PackedByteArray([0]) + text.to_utf8_buffer())


## KEY, its null, then compression flag 0, method 0, no language, no translated keyword.
static func _itxt_head() -> PackedByteArray:
	return KEY.to_ascii_buffer() + PackedByteArray([0, 0, 0, 0, 0])


static func _u32(n: int) -> PackedByteArray:
	return PackedByteArray([(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF])


static func _read_u32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]
