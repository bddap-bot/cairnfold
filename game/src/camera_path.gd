class_name CameraPath
extends Camera3D

## A camera flown along authored keys (Main's --camera FILE), for re-rendering a replay from outside the player's head.
## The file is a JSON list of keys, each {"t": seconds of game time from the start, "eye": [x, y, z], "at": [x, y, z]}
## in the garden's space; see "Local play-session history" in docs/design.md.

var keys: Array
var _head: Camera3D
var _t := 0.0


func _init(path_keys: Array, head: Camera3D) -> void:
	keys = path_keys
	_head = head
	near = head.near
	cull_mask = Quality.VIEW_MASK


func _ready() -> void:
	make_current()
	_process(0.0)


## Game time, so a replay's frames, scaled to their recorded lengths, move the camera as the session's clock did.
func _process(delta: float) -> void:
	_t += delta
	far = _head.far
	global_transform = CameraPath.at(keys, _t)


## The keys in the file at `path`, ordered by time, or why it holds none a camera can follow.
static func read(path: String) -> Variant:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Array or parsed.is_empty():
		return "%s holds no list of camera keys" % path
	var out := []
	for k: Variant in parsed:
		var key: Variant = {"t": float(k.t), "eye": _vector(k.eye), "at": _vector(k.at)} if k is Dictionary and _number(k.get("t")) and k.has("eye") and k.has("at") else null
		if key == null or key.eye == null or key.at == null or (key.at - key.eye).cross(Vector3.UP).is_zero_approx():
			return "%s: a key needs a time \"t\" and an \"eye\" and an \"at\" of three numbers each, the eye neither at the point it looks at nor straight above or below it: %s" % [path, k]
		out.append(key)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	return out


static func _number(x: Variant) -> bool:
	return x is float or x is int


static func _vector(v: Variant) -> Variant:
	return Vector3(v[0], v[1], v[2]) if v is Array and v.size() == 3 and v.all(_number) else null


## The camera at time `t`: at a point on a curve through the keys' eyes, looking at one on a curve through their points
## looked at, holding before the first key and after the last.
static func at(path_keys: Array, t: float) -> Transform3D:
	var i := path_keys.bsearch_custom(t, func(k: Dictionary, s: float) -> bool: return k.t <= s)
	var a: Dictionary = path_keys[clampi(i - 1, 0, path_keys.size() - 1)]
	var b: Dictionary = path_keys[clampi(i, 0, path_keys.size() - 1)]
	var eye: Vector3 = a.eye
	var look: Vector3 = a.at
	if b.t > a.t and t > a.t:
		var before: Dictionary = path_keys[maxi(i - 2, 0)]
		var after: Dictionary = path_keys[mini(i + 1, path_keys.size() - 1)]
		var span: float = b.t - a.t
		var w := (t - float(a.t)) / span
		eye = a.eye.cubic_interpolate_in_time(b.eye, before.eye, after.eye, w, span, before.t - a.t, after.t - a.t)
		look = a.at.cubic_interpolate_in_time(b.at, before.at, after.at, w, span, before.t - a.t, after.t - a.t)
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
