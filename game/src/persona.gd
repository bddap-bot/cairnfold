class_name Persona
extends RefCounted

## Nothing identifying rides the beacon: Steam friends match its random key through rich presence, and without
## Steam a name goes out only once picked (docs/multiplayer.md, "Finding each other").

const MAX_NAME := 24
const PICTURE := 64
const ASK_EVERY := 1.0
const KEY := "garden"
const FRIENDS := 4
const FIRST: PackedStringArray = ["Mossy", "Quiet", "Amber", "Dusky", "Bramble", "Willow", "Sunny", "Misty", "Clover", "Pebble", "Hazel", "Thistle", "Rowan", "Fern", "Meadow", "Cobble", "Dappled", "Gentle", "Russet", "Honey", "Slate", "Hollow", "Briar", "Linden"]
const SECOND: PackedStringArray = ["Wren", "Finch", "Otter", "Badger", "Heron", "Robin", "Hare", "Vole", "Lark", "Moth", "Newt", "Plover", "Stoat", "Thrush", "Dormouse", "Kestrel", "Bee", "Toad", "Swift", "Owl", "Snail", "Dunnock", "Martin", "Shrew"]

var name := ""
var shared := false
## Empty for scripts and tests, which never write it.
var keep := ""
var _steam: Object
var _app := 0
var _pictures := {}
var _asked := {}
var _keys := {}
var _keys_at := -INF
var _names := {}


## `app` 0 starts no Steam.
func _init(chosen := "", app := 0, keep_at := "", seed := 0) -> void:
	keep = keep_at
	if app > 0 and Engine.has_singleton("Steam"):
		var steam := Engine.get_singleton("Steam")
		var started: Dictionary = steam.steamInitEx(app, true)
		if int(started.get("status", -1)) == 0:
			_steam = steam
			_app = app
		else:
			print("persona: no Steam (%s)" % started.get("verbal", ""))
	if not chosen.is_empty():
		name = clean(chosen)
	elif not keep.is_empty() and FileAccess.file_exists(keep):
		name = clean(FileAccess.get_file_as_string(keep))
	shared = not name.is_empty()
	if name.is_empty():
		name = suggest(seed)


func steam() -> bool:
	return _steam != null


static func clean(raw: String) -> String:
	var out := ""
	for c in raw.strip_edges():
		var u := c.unicode_at(0)
		out += " " if u < 32 or (u >= 127 and u < 160) else c
	return " ".join(out.split(" ", false)).left(MAX_NAME).strip_edges()


static func suggest(seed: int) -> String:
	var h := absi(hash(seed))
	return "%s %s" % [FIRST[h % FIRST.size()], SECOND[(h / FIRST.size()) % SECOND.size()]]


func pick() -> void:
	if shared:
		var was := name
		while name == was:
			name = suggest(randi())
	shared = true
	if not keep.is_empty():
		Main.replace_file(keep, name.to_utf8_buffer())


func offer(key: int) -> void:
	if _steam:
		_steam.setRichPresence(KEY, str(key))


## 0 unless this account or a Steam friend in this game offers `key`.
func steam_id(key: int) -> int:
	if _steam == null:
		return 0
	var now := Time.get_ticks_msec() / 1000.0
	if not _keys.has(key) and now - _keys_at >= ASK_EVERY:
		_keys_at = now
		var ids: Array[int] = [_steam.getSteamID()]
		for i in _steam.getFriendCount(FRIENDS):
			var id: int = _steam.getFriendByIndex(i, FRIENDS)
			if int(_steam.getFriendGamePlayed(id).get("id", 0)) == _app:
				ids.append(id)
		for id in ids:
			var offered: String = _steam.getFriendRichPresence(id, KEY)
			if offered.is_valid_int():
				_keys[offered.to_int()] = id
	return _keys.get(key, 0)


func steam_name(id: int) -> String:
	if not _names.has(id):
		_names[id] = clean(_steam.getPersonaName() if id == _steam.getSteamID() else _steam.getFriendPersonaName(id))
	return _names[id]


## null until this machine's Steam has it.
func picture(id: int) -> Texture2D:
	if _pictures.has(id):
		return _pictures[id]
	var now := Time.get_ticks_msec() / 1000.0
	if now - _asked.get(id, -INF) < ASK_EVERY:
		return null
	_asked[id] = now
	var handle: int = _steam.getMediumFriendAvatar(id)
	if handle <= 0:
		_steam.requestUserInformation(id, false)
		return null
	var size: Dictionary = _steam.getImageSize(handle)
	var rgba: Dictionary = _steam.getImageRGBA(handle)
	var w := int(size.get("width", 0))
	var h := int(size.get("height", 0))
	var data: PackedByteArray = rgba.get("buffer", PackedByteArray())
	if not rgba.get("success", false) or w <= 0 or data.size() != w * h * 4:
		return null
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	if w != PICTURE:
		image.resize(PICTURE, PICTURE, Image.INTERPOLATE_BILINEAR)
	_pictures[id] = ImageTexture.create_from_image(image)
	return _pictures[id]
