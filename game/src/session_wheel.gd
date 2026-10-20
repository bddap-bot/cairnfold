class_name SessionWheel
extends RefCounted

const PAGE := 4
const TAG_FONT := 48
const TAG_PIXEL := 0.00012
const PICTURE := 0.012
const GAP := 0.002
var session: Session


func _init(people: Session) -> void:
	session = people


func avatars() -> Array:
	var out: Array = []
	for i in Avatar.BUILT_IN.size():
		out.append("avatar:%d" % i)
	if not session.avatar_file.is_empty():
		out.append("avatar:file")
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


## Each deeper fan holds a bounded page and another fan for the remainder.
static func pages(items: Array) -> Array:
	if items.size() <= PAGE:
		return items
	var out := items.slice(0, PAGE - 1)
	out.append(pages(items.slice(PAGE - 1)))
	return out


func activate(key: String) -> void:
	if key.begins_with("avatar:"):
		session.choose_avatar(key.trim_prefix("avatar:"))
	elif key == "name":
		session.me.pick()
	elif key == "home":
		session.go_home()
	elif key.begins_with("join:"):
		var garden: Dictionary = session.nearby.get(key.trim_prefix("join:"), {})
		if garden.get("joins", false):
			session.join(garden.address, garden.port)


func figure(key: String) -> Node3D:
	if key == "home":
		var home := _home()
		home.scale = Vector3.ONE * 0.25
		return home
	var root := Node3D.new()
	if key == "empty":
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.012
		mesh.outer_radius = 0.018
		ring.mesh = mesh
		ring.rotation.x = PI * 0.5
		root.add_child(ring)
		return root
	var garden := {"avatar": session.avatar, "colour": session.colour, "wears": "", "joins": true}
	var tag := ""
	if key.begins_with("join:"):
		tag = key.trim_prefix("join:")
		garden = session.nearby.get(tag, garden)
	elif key == "name":
		tag = "name"
	elif key == "avatar:file":
		garden.wears = session.avatar_file.key
	elif key.begins_with("avatar:"):
		garden.avatar = key.trim_prefix("avatar:").to_int()
	var wears: String = garden.get("wears", "")
	var scene: PackedScene = session.avatar_file.scene if key == "avatar:file" else session.look(wears, garden.avatar)
	var a := Avatar.open(scene, garden.colour, wears if session.previews.has(wears) else "")
	a.name = "Figure"
	a.stand()
	a.rotation.y = PI
	a.scale = Vector3.ONE * 0.032
	root.add_child(a)
	if not garden.joins:
		var cross := Label3D.new()
		cross.text = "×"
		cross.pixel_size = 0.001
		cross.position.y = 0.04
		root.add_child(cross)
	if tag != "":
		var info := _tag(tag)
		_retag(root, info[0], info[1], info[2])
	return root


func _tag(k: String) -> Array:
	var me := session.me
	if k == "name":
		return [me.name, null, me.shared]
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
	tag.rotation.y = 0.0
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

