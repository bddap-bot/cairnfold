class_name VisitTool
extends Node3D

## For a hand holding the visit tool: a small figure of each garden announced nearby stands in an arc in
## front of the player, in its host's avatar and colour; point at one and pull the trigger to go there.
## While visiting, a small cairn stands among them: picking it goes home.

const ARC := 1.3
const SPREAD := deg_to_rad(22.0)
const SIZE := 0.2
const PICK := 0.22
const TINT := Color(1.0, 0.95, 0.8, 0.6)

var rig: Rig
var session: Session
const HOME := "home"

## Figures by the garden they stand for: its "address:port" in `Session.nearby`, or HOME.
var figures := {}
var picked := ""
var _buttons: Array[Buttons] = []
var _holding := false


func _init(player: Rig, people: Session) -> void:
	rig = player
	session = people
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))


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
	if _holding:
		_lay_out()
		_point(hand)
	for b in _buttons:
		b.latch()


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
	for k in figures.keys():
		if not want.has(k):
			figures[k].queue_free()
			figures.erase(k)
	for k in want:
		if not figures.has(k):
			figures[k] = _home() if k == HOME else _figure(session.nearby[k])
			add_child(figures[k])
	for i in want.size():
		var a := (i - (want.size() - 1) * 0.5) * SPREAD
		var f: Node3D = figures[want[i]]
		f.position = Vector3(sin(a) * ARC, 0, -cos(a) * ARC)
		f.rotation = Vector3(0, -a + PI, 0)


func _figure(garden: Dictionary) -> Node3D:
	var root := Node3D.new()
	var a := Avatar.open(Avatar.BUILT_IN[garden.avatar], garden.colour)
	a.scale = Vector3.ONE * SIZE
	root.add_child(a)
	a.stand.call_deferred()
	return root


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
		var c: Vector3 = figures[k].global_position + Vector3.UP * SIZE * 0.9
		var along := (c - origin).dot(dir)
		var d := (c - (origin + dir * along)).length()
		if along > 0.0 and d < best:
			best = d
			picked = k
	for k in figures:
		figures[k].scale = Vector3.ONE * (1.25 if k == picked else 1.0)
	hand.point(figures[picked].global_position + Vector3.UP * SIZE * 0.9 if figures.has(picked) else null, TINT, ARC)
	if figures.has(picked) and _buttons[rig.hands.find(hand)].pressed("trigger_click"):
		go(picked)


func go(k: String) -> void:
	if k == HOME:
		session.go_home()
	else:
		session.join(session.nearby[k].address, session.nearby[k].port)
