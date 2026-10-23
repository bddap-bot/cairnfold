class_name BirdCarry
extends Node

const TRUST := 8.0
const REACH := 0.14
const HOLD := Transform3D(Basis.IDENTITY, Vector3(0, 0.018, 0.025))

var birds: Birds
var painting: EaselTool
var grips: Array[Buttons] = []
var held := {}


func _init(rig: Rig, flock: Birds, paint: EaselTool) -> void:
	birds = flock
	painting = paint
	process_priority = -5
	for h in rig.hands:
		grips.append(Buttons.new(h).watch(["grab"]))


func _process(delta: float) -> void:
	for buttons in grips:
		var h := buttons.hand
		if held.has(h):
			if not buttons.held("grab") or not h.tracked():
				release(h)
			else:
				var b: Birds.Bird = held[h].bird
				h.hold()
				b.node.global_transform = b.node.global_transform.interpolate_with(h.body.global_transform * HOLD, 1.0 - exp(-delta * 18.0))
				_smear(h, b)
		elif buttons.pressed("grab") and h.tracked() and not h.picking and not h.taken() and h.tool in [Hand.Tool.NONE, Hand.Tool.SEEDS]:
			for b in birds.birds:
				if take(h, b):
					break
		buttons.latch()


func take(h: Hand, b: Birds.Bird) -> bool:
	if held.has(h) or b.carried or b.affection < TRUST or b.state not in [Birds.State.PERCH, Birds.State.FEED, Birds.State.PECK, Birds.State.SHOULDER]:
		return false
	if b.node.global_position.distance_to(h.body.global_position) > REACH:
		return false
	birds.wildlife.release(b)
	birds.let_go_shoulder(b)
	b.carried = true
	b.node.hand = h
	h.carried = b.node
	h.close_wheel()
	h.tool = Hand.Tool.NONE
	h.hold()
	var palm := cup()
	b.node.add_child(palm)
	var p := EaselTool.Painter.new()
	p.hand = h
	p.brush = Brushwork.Brush.FLAT
	p.medium = Brushwork.Medium.SMEAR
	p.colour = Vector3.ZERO
	p.strength = 0.0
	p.load = 1.0
	held[h] = {"bird": b, "cup": palm, "painter": p}
	return true


func release(h: Hand) -> void:
	if not held.has(h):
		return
	var entry: Dictionary = held[h]
	painting.end_stroke(entry.painter)
	entry.cup.queue_free()
	var b: Birds.Bird = entry.bird
	b.carried = false
	h.carried = null
	held.erase(h)
	birds._off_hand(b)


func _smear(h: Hand, b: Birds.Bird) -> void:
	var p: EaselTool.Painter = held[h].painter
	var at := b.node.global_transform * Conure.BODY
	for e: Easels.Easel in painting.easels.easels.values():
		var uv := e.on_canvas(at)
		if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0 or uv.z < -0.015 or uv.z > 0.045:
			continue
		if not p.stroke.is_empty() and p.stroke.easel != e:
			painting.end_stroke(p)
		p.load = 1.0
		painting.touch(p, e, Vector2(uv.x, uv.y), clampf((0.045 - uv.z) / 0.04, 0.1, 1.0), 0.0)
		return
	painting.end_stroke(p)


## Curved fingers cradle the existing bird without squeezing its body.
static func cup() -> Node3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Meshes.ellipsoid(st, 0, Vector3(0, -0.004, 0.008), Vector3(0.035, 0.012, 0.04), Color.WHITE, 4, 10)
	for finger in 4:
		for joint in 3:
			var angle := float(joint) * 0.45
			var at := Vector3(0.025 + sin(angle) * 0.018, 0.006 + float(joint) * 0.012, float(finger) * 0.015 - 0.022)
			Meshes.ellipsoid(st, 0, at, Vector3(0.009, 0.009, 0.011), Color.WHITE, 3, 8)
	for joint in 3:
		var at := Vector3(-0.024 - joint * 0.005, 0.006 + joint * 0.009, 0.015 - joint * 0.007)
		Meshes.ellipsoid(st, 0, at, Vector3(0.011, 0.01, 0.012), Color.WHITE, 3, 8)
	st.index()
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.9, 0.84)
	mat.roughness = 0.7
	m.material_override = mat
	return m
