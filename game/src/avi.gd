class_name Avi
extends RefCounted

## A video file of JPEG frames and stereo float sound, written as it goes; `close` fills in the counts and
## the index. Plain AVI stops at 1 GiB, so a frame or sound that would pass it is refused and `full` set.

const LIMIT := 1 << 30
const HEADER := 12 + 12 + 64 + 12 + 64 + 48 + 12 + 64 + 26 + 12
## Bytes a sound frame takes: two channels of 32-bit float.
const SOUND_BLOCK := 8

var size: Vector2i
var fps: int
var rate: int
var frames := 0
var sound_bytes := 0
var full := false
var _file: FileAccess
## On Android a file in shared storage is written through java.io, as Main.write_bytes writes a photo.
var _java: JavaObject
var _at := 0
var _failed := false
var _index := StreamPeerBuffer.new()
var _largest := 0


static func open(path: String, frame_size: Vector2i, frames_per_second: int, mix_rate: int) -> Avi:
	var avi := Avi.new()
	avi.size = frame_size
	avi.fps = frames_per_second
	avi.rate = mix_rate
	if OS.has_feature("android") and path.begins_with(Main.photos_folder()):
		avi._java = JavaClassWrapper.wrap("java.io.RandomAccessFile").RandomAccessFile(path, "rw")
		if avi._java == null or JavaClassWrapper.get_exception() != null:
			return null
	else:
		avi._file = FileAccess.open(path, FileAccess.WRITE)
		if avi._file == null:
			return null
	avi._write(avi._header())
	return avi


func frame(jpg: PackedByteArray) -> bool:
	if _chunk("00dc", jpg):
		frames += 1
		return true
	return false


func sound(pcm: PackedByteArray) -> bool:
	if _chunk("01wb", pcm):
		sound_bytes += pcm.size()
		return true
	return false


func close() -> Error:
	var end := _at
	var tail := StreamPeerBuffer.new()
	tail.put_data("idx1".to_ascii_buffer())
	tail.put_u32(_index.get_size())
	tail.put_data(_index.data_array)
	_write(tail.data_array)
	var length := _at
	if _java != null:
		_java.seek(0)
	else:
		_file.seek(0)
	_write(_header(end - HEADER + 4, length - 8))
	if _java != null:
		_java.close()
		_failed = _failed or JavaClassWrapper.get_exception() != null
	else:
		_failed = _failed or _file.get_error() != OK
		_file.close()
	return ERR_FILE_CANT_WRITE if _failed else OK


func _write(bytes: PackedByteArray) -> void:
	if _java != null:
		_java.write(bytes)
		_failed = _failed or JavaClassWrapper.get_exception() != null
	else:
		_failed = _failed or not _file.store_buffer(bytes)
	_at += bytes.size()


func _chunk(id: String, data: PackedByteArray) -> bool:
	if _at + 9 + data.size() + _index.get_size() + 24 > LIMIT:
		full = true
		return false
	var head := StreamPeerBuffer.new()
	head.put_data(id.to_ascii_buffer())
	head.put_u32(data.size())
	_index.put_data(id.to_ascii_buffer())
	_index.put_u32(0x10)
	_index.put_u32(_at - HEADER + 4)
	_index.put_u32(data.size())
	_write(head.data_array)
	_write(data)
	if data.size() % 2:
		_write(PackedByteArray([0]))
	_largest = maxi(_largest, data.size())
	return true


## The headers up to the 'movi' list's id, the same length however far the file has got.
func _header(movi := 4, riff := HEADER - 8) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	var rect := [[16, 0], [16, 0], [16, size.x], [16, size.y]]
	_put(b, ["RIFF", riff, "AVI ", "LIST", 4 + 64 + 12 + 64 + 48 + 12 + 64 + 26, "hdrl"])
	_put(b, ["avih", 56, roundi(1e6 / fps), _largest * fps + rate * SOUND_BLOCK, 0, 0x10, frames, 0, 2, _largest + 8])
	_put(b, [size.x, size.y, 0, 0, 0, 0])
	_put(b, ["LIST", 4 + 64 + 48, "strl", "strh", 56, "vids", "MJPG", 0, [16, 0], [16, 0], 0])
	_put(b, [1, fps, 0, frames, _largest + 8, 0xffffffff, 0] + rect)
	_put(b, ["strf", 40, 40, size.x, size.y, [16, 1], [16, 24], "MJPG", size.x * size.y * 3, 0, 0, 0, 0])
	_put(b, ["LIST", 4 + 64 + 26, "strl", "strh", 56, "auds", 0, 0, [16, 0], [16, 0], 0])
	_put(b, [SOUND_BLOCK, rate * SOUND_BLOCK, 0, sound_bytes >> 3, rate, 0xffffffff, SOUND_BLOCK] + rect)
	_put(b, ["strf", 18, [16, 3], [16, 2], rate, rate * SOUND_BLOCK, [16, SOUND_BLOCK], [16, 32], [16, 0]])
	_put(b, ["LIST", movi, "movi"])
	return b.data_array


## Each field in turn: a string as its ASCII bytes, an int as 32 bits, [16, n] as 16.
static func _put(b: StreamPeerBuffer, fields: Array) -> void:
	for f in fields:
		if f is String:
			b.put_data(f.to_ascii_buffer())
		elif f is Array:
			b.put_u16(f[1])
		else:
			b.put_u32(f)
