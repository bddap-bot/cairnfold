class_name VisitTool
extends Node3D

## For a hand holding the visit tool: a small figure of each garden announced nearby stands in an arc in front of the
## player, in its host's avatar and colour, their own VRM once it has been fetched; point at one and pull the trigger
## to go there. While visiting, a small cairn stands among them: picking it goes home. Joining or going home puts the
## tool away, and the arc and its figures go with it; teleporting sets the arc down afresh where the player arrives.
## Under each figure its host's name, and with Steam their Steam picture, are the one text in the game
## (docs/design.md, "Requirements"). Without Steam the player's own figure stands nearer under their name, faint
## until they pick it to show it; picking again offers another. A garden of a build with other networked methods
## stands with a small X over it and cannot be picked.

const ARC := 1.3
const SPREAD := deg_to_rad(22.0)
const SIZE := 0.2
const PICK := 0.22
## Where a figure is pointed at: the middle of its body.
const AIM := Vector3.UP * SIZE * 1.6
const TINT := Color(1.0, 0.95, 0.8, 0.6)
const TAG_Y := 0.13
const TAG_FONT := 48
const TAG_PIXEL := 0.0006
const PICTURE := 0.06
const GAP := 0.012
const ME_AT := Vector3(-0.42, -0.12, -0.8)
const ME_SIZE := 0.7
const CROSS := 0.11
const CROSS_COLOUR := Color(0.62, 0.2, 0.16)

var rig: Rig
var session: Session
const HOME := "home"
const ME := "me"

## Figures by the garden they stand for: its "address:port" in `Session.nearby`, or HOME.
var figures := {}
var picked := ""
## What each figure's tag shows, so a tag is rebuilt only when its name or picture changes.
var _tags := {}
## The avatar each figure shows, so a figure is rebuilt only when its host's file arrives or changes.
var _dressed := {}
var _buttons: Array[Buttons] = []
var _holding := false


func _init(player: Rig, people: Session) -> void:
	rig = player
	session = people
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["tool"]))
	rig.placed.connect(_follow)


func holder() -> Hand:
	for h in rig.hands:
		if h.tool == Hand.Tool.VISIT and rig.aim_hand != h:
			return h
	return null


func _process(_delta: float) -> void:
	var hand := holder()
	if (hand != null) != _holding:
		_holding = hand != null
		visible = _holding
		if _holding:
			_face_player()
		else:
			_clear()
	if _holding:
		_lay_out()
		_point(hand)
	for b in _buttons:
		b.latch()


func _clear() -> void:
	for k in figures:
		figures[k].queue_free()
	figures.clear()
	_tags.clear()
	_dressed.clear()
	picked = ""


## A player who teleports leaves no figure standing behind: the arc is set down afresh where they arrive.
func _follow() -> void:
	_clear()
	if _holding:
		_face_player()


## The arc is set down in front of the player when they take the tool up, and stays put while held.
func _face_player() -> void:
	var head := rig.head.global_transform
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), head.origin + Vector3.DOWN * 0.45)


func _lay_out() -> void:
	var want := session.nearby.keys()
	if not session.visiting.is_empty():
		want.append(HOME)
	if not session.me.steam():
		want.append(ME)
	for k in figures.keys():
		if not want.has(k) or k != HOME and _dressed[k] != _look(k):
			figures[k].queue_free()
			figures.erase(k)
			_tags.erase(k)
			_dressed.erase(k)
	for k in want:
		if not figures.has(k):
			figures[k] = _home() if k == HOME else _figure(_garden(k))
			_dressed[k] = null if k == HOME else _look(k)
			add_child(figures[k])
		if k != HOME:
			var tag := _tag(k)
			if _tags.get(k) != tag:
				_tags[k] = tag
				_retag(figures[k], tag[0], tag[1], tag[2])
	want.erase(ME)
	if figures.has(ME):
		figures[ME].position = ME_AT
		figures[ME].rotation = Vector3(0, PI, 0)
	for i in want.size():
		var a := (i - (want.size() - 1) * 0.5) * SPREAD
		var f: Node3D = figures[want[i]]
		f.position = Vector3(sin(a) * ARC, 0, -cos(a) * ARC)
		f.rotation = Vector3(0, -a + PI, 0)


func _garden(k: String) -> Dictionary:
	return session.nearby[k] if k != ME else {"avatar": session.avatar, "colour": session.colour, "wears": session.worn_key, "joins": true}


func _look(k: String) -> PackedScene:
	var garden := _garden(k)
	return session.look(garden.get("wears", ""), garden.avatar)


func _figure(garden: Dictionary) -> Node3D:
	var root := Node3D.new()
	var wears: String = garden.get("wears", "")
	var a := Avatar.open(session.look(wears, garden.avatar), garden.colour, wears if session.previews.get(wears) else "")
	a.scale = Vector3.ONE * SIZE
	root.add_child(a)
	a.stand.call_deferred()
	if not garden.joins:
		root.add_child(_cross())
	return root


func _cross() -> Node3D:
	var root := Node3D.new()
	root.name = "Cross"
	root.position = AIM + Vector3.FORWARD * SIZE * 0.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CROSS_COLOUR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for z in [PI / 4, -PI / 4]:
		var bar := MeshInstance3D.new()
		bar.mesh = Meshes.rounded_box(0.4, 2, 41)
		bar.material_override = mat
		bar.scale = Vector3(CROSS, CROSS * 0.18, CROSS * 0.18)
		bar.rotation.z = z
		root.add_child(bar)
	return root


## [name, picture or null, shown to others] for a figure.
func _tag(k: String) -> Array:
	var me := session.me
	if k == ME:
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
	tag.position.y = TAG_Y
	tag.rotation.y = PI
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


func _point(hand: Hand) -> void:
	var t := hand.global_transform
	var origin := t.origin
	var dir := -t.basis.z
	picked = ""
	var best := PICK
	for k in figures:
		if not joinable(k):
			continue
		var c: Vector3 = figures[k].global_position + AIM
		var along := (c - origin).dot(dir)
		var d := (c - (origin + dir * along)).length()
		if along > 0.0 and d < best:
			best = d
			picked = k
	for k in figures:
		figures[k].scale = Vector3.ONE * (ME_SIZE if k == ME else 1.0) * (1.25 if k == picked else 1.0)
	hand.point(figures[picked].global_position + AIM if figures.has(picked) else null, TINT, ARC)
	if figures.has(picked) and _buttons[rig.hands.find(hand)].pressed("tool"):
		go(picked)


func joinable(k: String) -> bool:
	return k in [HOME, ME] or session.nearby[k].joins


func go(k: String) -> void:
	if not joinable(k):
		return
	if k == ME:
		session.me.pick()
	elif k == HOME:
		session.go_home()
		put_away()
	elif session.join(session.nearby[k].address, session.nearby[k].port):
		put_away()


## The hand holding the tool lets it go, so the arc closes once it has been used.
func put_away() -> void:
	for h in rig.hands:
		if h.tool == Hand.Tool.VISIT:
			h.tool = Hand.Tool.HANDS
