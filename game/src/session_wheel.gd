class_name SessionWheel
extends RefCounted

const PAGE := 4
const TAG_FONT := 48
const TAG_PIXEL := 0.00012
const PICTURE := 0.012
const GAP := 0.002
var session: Session
static var _ghost_mat: StandardMaterial3D


func _init(people: Session) -> void:
	session = people


func avatars() -> Array:
	var out: Array = []
	for i in Avatar.BUILT_IN.size():
		out.append("avatar:%d" % i)
	var files := session.files.keys().filter(func(f: String) -> bool: return session.files[f].scene != null)
	files.sort()
	for f in files:
		out.append("file:" + f)
	if not session.me.steam():
		out.append("name")
	return pages(out)


func friends() -> Array:
	var keys := session.nearby.keys()
	keys.sort()
	var out: Array = []
	for key in keys:
		out.append("join:" + key)
	if out.is_empty():
		out.append("empty")
	if not session.visiting.is_empty():
		out.push_front("home")
	return pages(out)


## The middle continuation is horizontal, so arbitrarily many pages zig-zag in the same reach.
static func pages(items: Array) -> Array:
	if items.size() <= PAGE:
		return items
	return [items[0], pages(items.slice(2)), items[1]]


func activate(key: String) -> void:
	if key.begins_with("avatar:"):
		session.choose_avatar(key.trim_prefix("avatar:").to_int())
	elif key.begins_with("file:"):
		session.wear_file(key.trim_prefix("file:"))
	elif key == "name":
		session.me.pick()
	elif key == "home":
		session.go_home()
	elif key.begins_with("join:"):
		var garden: Dictionary = session.nearby.get(key.trim_prefix("join:"), {})
		if garden.get("joins", false):
			session.join(garden.address, garden.port)


## What the icon of `item`, a person's key or a subtree, is drawn from: a wheel keeping its icons builds one again when
## this changes.
func signature(item: Variant) -> String:
	if item is Array:
		var whom := " ".join(item.map(signature))
		return whom + " " + _worn() + " " + signature(_worn()) if item == avatars() else whom
	if not item is String:
		return ""
	var key: String = item
	if key.begins_with("avatar:"):
		return str([session.colour, ""])
	if key.begins_with("file:"):
		return str([session.colour, _file(key).get("key", "")])
	if key == "name":
		return str([session.avatar, session.colour, _tag(key)])
	if key.begins_with("join:"):
		var tag := key.trim_prefix("join:")
		var garden: Dictionary = session.nearby.get(tag, {})
		var wears: String = garden.get("wears", "")
		return str([garden.get("avatar"), garden.get("colour"), wears, session.previews.has(wears), garden.get("joins"), _tag(tag)])
	return ""


## The icon of `item`: a person's key as their figure (`figure`); the avatars as who you are now, alone in a hand
## mirror, since picking one changes you; the gardens to join as a gate with the nearby players behind it, since picking
## one takes you through; anything else null.
func icon(item: Variant) -> Node3D:
	if item is String:
		return figure(item)
	if not item is Array:
		return null
	if item == avatars():
		return _mirror()
	if item == friends():
		return _gate()
	return null


## The avatar key this player wears now.
func _worn() -> String:
	for f: String in session.files:
		if session.worn_key != "" and session.files[f].get("key") == session.worn_key:
			return "file:" + f
	return "avatar:%d" % session.avatar


func _mirror() -> Node3D:
	const SIZE := 0.55
	var root := Node3D.new()
	var frame := Node3D.new()
	frame.scale = Vector3.ONE * SIZE
	ToolModels.mirror(frame)
	root.add_child(frame)
	var me := _person(_worn())
	me.scale *= 0.5
	me.position = (ToolModels.MIRROR_CENTRE - Vector3(0, ToolModels.MIRROR_GLASS.y * 0.4, -0.004)) * SIZE
	root.add_child(me)
	return root


func _gate() -> Node3D:
	const WIDTH := 0.036
	var root := Node3D.new()
	ToolModels.gate(root, WIDTH)
	var keys := session.nearby.keys()
	keys.sort()
	keys = keys.slice(0, 3)
	for i in keys.size():
		var who := _person("join:" + keys[i])
		who.scale *= 0.5
		who.position = Vector3((i - (keys.size() - 1) * 0.5) * 0.011, 0, -0.012 - 0.004 * (i % 2))
		root.add_child(who)
	return root


func figure(key: String) -> Node3D:
	if key == "home":
		var home := _home()
		home.scale = Vector3.ONE * 0.25
		return home
	var root := Node3D.new()
	root.add_child(_person(key))
	if key == "empty":
		_ghost(root.get_child(0))
	if not _garden(key).joins:
		var cross := Label3D.new()
		cross.text = "×"
		cross.pixel_size = 0.001
		cross.position.y = 0.04
		root.add_child(cross)
	var tag := key.trim_prefix("join:") if key.begins_with("join:") else "name" if key == "name" else ""
	if tag != "":
		var info := _tag(tag)
		_retag(root, info[0], info[1], info[2])
	return root


## The look of whoever `key` names: {avatar, colour, wears, joins}.
func _garden(key: String) -> Dictionary:
	var garden := {"avatar": session.avatar, "colour": session.colour, "wears": "", "joins": true}
	if key.begins_with("join:"):
		garden = session.nearby.get(key.trim_prefix("join:"), garden)
	elif key.begins_with("file:"):
		garden.wears = _file(key).get("key", "")
	elif key.begins_with("avatar:"):
		garden.avatar = key.trim_prefix("avatar:").to_int()
	return garden


func _file(key: String) -> Dictionary:
	return session.files.get(key.trim_prefix("file:"), {}) if key.begins_with("file:") else {}


## The avatar `key` names, standing and facing the player, untagged.
func _person(key: String) -> Avatar:
	var garden := _garden(key)
	var wears: String = garden.get("wears", "")
	var scene: PackedScene = _file(key).get("scene") if _file(key).get("scene") != null else session.look(wears, garden.avatar)
	var a := Avatar.open(scene, garden.colour, wears if session.previews.has(wears) else "")
	a.name = "Figure"
	a.stand()
	a.rotation.y = PI
	a.scale = Vector3.ONE * 0.032
	return a


## A figure as a faint, colourless outline of one: the place a person would stand, with no one in it.
static func _ghost(figure: Node3D) -> void:
	if _ghost_mat == null:
		_ghost_mat = Meshes.glow(Color(0.25, 0.25, 0.28, 0.45))
	Meshes.ghostly(figure, _ghost_mat)


func _tag(k: String) -> Array:
	var me := session.me
	if k == "name":
		return [me.name, null, me.shared]
	if not session.nearby.has(k):
		return ["", null, true]
	var garden: Dictionary = session.nearby[k]
	var id := me.steam_id(garden.key)
	if id and _copied(garden.key):
		return ["", null, true]
	if id:
		return [me.steam_name(id), me.picture(id), true]
	return [garden.name, null, true]


## A key that two gardens announce: anyone on the network can copy a friend's, so neither is named.
func _copied(key: int) -> bool:
	return session.nearby.values().filter(func(g: Dictionary) -> bool: return g.key == key).size() > 1


## A name, after the picture when there is one, in a row centred under the figure and facing the player.
func _retag(root: Node3D, who: String, picture: Texture2D, shown: bool) -> void:
	var old := root.get_node_or_null("Tag")
	if old:
		root.remove_child(old)
		old.queue_free()
	if who.is_empty():
		return
	var tag := Node3D.new()
	tag.name = "Tag"
	tag.position.y = -0.008
	root.add_child(tag)
	var label := Label3D.new()
	label.text = who
	label.font_size = TAG_FONT
	label.pixel_size = TAG_PIXEL
	label.outline_size = 10
	label.outline_modulate = Color(0.12, 0.1, 0.08, 0.7)
	label.modulate = Color(1.0, 0.96, 0.86, 1.0 if shown else 0.45)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var width := ThemeDB.fallback_font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT).x * TAG_PIXEL
	var left := -(width + (PICTURE + GAP if picture else 0.0)) * 0.5
	if picture:
		var sprite := Sprite3D.new()
		sprite.texture = picture
		sprite.pixel_size = PICTURE / picture.get_width()
		sprite.shaded = false
		sprite.position.x = left + PICTURE * 0.5
		tag.add_child(sprite)
		left += PICTURE + GAP
	label.position.x = left
	tag.add_child(label)


## Three stones stacked: your own garden.
func _home() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.74, 0.7, 0.62)
	mat.roughness = 0.9
	var y := 0.0
	for i in 3:
		var s := Vector3(0.16, 0.08, 0.13) * (1.0 - i * 0.22)
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.rounded_box(0.4, 2, 31 + i)
		mi.material_override = mat
		mi.scale = s
		mi.position = Vector3(0, y + s.y * 0.5, 0)
		mi.rotation.y = i * 0.7
		root.add_child(mi)
		y += s.y * 0.9
	return root

