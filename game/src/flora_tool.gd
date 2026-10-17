class_name FloraTool
extends Node3D

## Flowers, grass, stone, trees, bushes and paths, for whichever hand holds them: the trigger paints flowers, grass
## or stone ground where the hand points, plants a tree or bush there, or lays a path along the stroke. The brush
## widens with distance; painting a spot again thickens it, and a path is as wide as the brush. A stone
## stroke begun on stone paints the ground back to meadow instead, and the plants under it stand up again.

## Plants per square metre per second of painting.
const RATES := {Hand.Tool.FLOWERS: 12.0, Hand.Tool.GRASS: 30.0}
const PLACES := {Hand.Tool.TREES: "tree", Hand.Tool.BUSHES: "bush"}
const TINTS := {Hand.Tool.DIRT_PATH: Color(0.78, 0.58, 0.35, 0.6), Hand.Tool.FLOWERS: Color(1.0, 0.82, 0.9, 0.6), Hand.Tool.GRASS: Color(0.78, 1.0, 0.55, 0.6), Hand.Tool.TREES: Color(0.85, 1.0, 0.8, 0.6), Hand.Tool.BUSHES: Color(0.85, 1.0, 0.8, 0.6), Hand.Tool.PATH: Color(1.0, 0.9, 0.7, 0.6), Hand.Tool.STONE: Color(0.9, 0.88, 0.82, 0.6)}
const RADIUS_PER_METRE := 0.15
const MIN_RADIUS := 0.3
const MAX_RADIUS := 3.0
## A held ground brush stamps again after this long, or once it has moved this fraction of its radius.
const STAMP_EVERY := 0.1
const STAMP_MOVE := 0.3

signal planted


class Brush:
	var hand: Hand
	var buttons: Buttons
	var ring: MeshInstance3D
	## What the current trigger hold has painted, one build command on release: its ghost plants, and
	## the seed and dabs every machine grows the same plants from.
	var stroke: Array[Flora.Plant] = []
	var kind := ""
	var dabs := []
	var count := 0
	var rng := RandomNumberGenerator.new()
	var looks := RandomNumberGenerator.new()
	## The ground the current hold has painted, stone or meadow.
	var ground: Ground.Stroke
	## A stone hold begun on stone paints it back to meadow.
	var meadow := false
	var since_stamp := 0.0
	var last_stamp := Vector3.INF
	var owed := 0.0
	var paving := false
	## Whether this hold has reached the frame budget, and been told so.
	var full := false


var rig: Rig
var flora: Flora
var paths: Paths
var world: World
var brushes: Array[Brush] = []
## Where the grass feels the left hand while it is untracked; desktop scripts hold it in the grass.
var stand_in := Flora.NO_HAND
## Sent strokes still shown as ghosts.
var _sent := 0


func _init(player: Rig, plants: Flora, ways: Paths, garden: World) -> void:
	rig = player
	flora = plants
	paths = ways
	world = garden
	world.restored.connect(_forget)
	for h in rig.hands:
		var b := Brush.new()
		b.hand = h
		b.buttons = Buttons.new(h).watch(["tool"])
		b.ring = ring(Color(1, 1, 1, 0.6))
		add_child(b.ring)
		brushes.append(b)


## A brush's ring on the ground, of radius 1 until it is placed with `put_ring`.
static func ring(tint: Color) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.96
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = tint
	var out := MeshInstance3D.new()
	out.mesh = torus
	out.material_override = mat
	out.top_level = true
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out.visible = false
	return out


static func put_ring(r: MeshInstance3D, at: Vector3, radius: float) -> void:
	r.visible = true
	r.global_transform = Transform3D(Basis().scaled(Vector3(radius, 1.0, radius)), at + Vector3.UP * 0.04)


## Whether `hand`, or with none any hand, has a stroke under way.
func busy(hand: Hand = null) -> bool:
	return brushes.any(func(b: Brush) -> bool: return (hand == null or b.hand == hand) and (b.paving or b.ground != null or not b.dabs.is_empty()))


func _ground_held() -> bool:
	return brushes.any(func(b: Brush) -> bool: return b.ground != null)


func brush(hand: Hand) -> Brush:
	for b in brushes:
		if b.hand == hand:
			return b
	return null


func _process(delta: float) -> void:
	flora.part(rig.left.global_position if rig.left.get_has_tracking_data() else stand_in, _reach(rig.right))
	for b in brushes:
		_handle(b, delta)
		b.buttons.latch()


func _handle(b: Brush, delta: float) -> void:
	var held := b.hand.tool
	b.ring.visible = false
	# A stroke no button holds is a demo script's: the hand's own aim neither extends nor ends it.
	if busy(b.hand) and not b.buttons.held("tool") and not b.buttons.released("tool"):
		return
	if not TINTS.has(held) or rig.aim_hand == b.hand:
		end_stroke(b)
		return
	if b.buttons.released("tool"):
		end_stroke(b)
	if not b.hand.get_has_tracking_data():
		return
	var hand := b.hand.global_transform
	var hit: Variant = Terrain.raycast(hand.origin, -hand.basis.z)
	b.hand.point(hit, TINTS[held])
	if hit == null:
		end_stroke(b)
		return
	if PLACES.has(held):
		world.preview(b.hand, Budget.plants(PLACES[held], 1))
		if b.buttons.pressed("tool"):
			place(PLACES[held], hit, b.hand)
		return
	var radius := brush_radius(hand.origin, hit)
	if held in [Hand.Tool.PATH, Hand.Tool.DIRT_PATH]:
		radius = clampf(radius, PathLayout.HALF_WIDTH.x, PathLayout.HALF_WIDTH.y)
	put_ring(b.ring, hit, radius)
	if held in [Hand.Tool.PATH, Hand.Tool.DIRT_PATH]:
		if b.buttons.pressed("tool") and not paths.busy() and not _ground_held():
			begin_path(b, hit, radius)
		elif b.buttons.held("tool") and b.paving:
			extend_path(hit, radius, b.hand)
		if b.paving and paths.drawing != null:
			world.preview(b.hand, Budget.path({"points": paths.drawing.points, "half_widths": paths.drawing.half_widths}))
	elif b.buttons.held("tool"):
		if b.buttons.pressed("tool"):
			b.meadow = paints_meadow(held, hit)
		paint(b, hit, radius, delta)


static func _reach(hand: XRController3D) -> Vector3:
	return hand.global_position if hand.get_has_tracking_data() else Flora.NO_HAND


## A stone stroke begun on stone paints the ground back to meadow.
static func paints_meadow(tool: Hand.Tool, at: Vector3) -> bool:
	return tool == Hand.Tool.STONE and Ground.stone(at.x, at.z) > 0.5


static func brush_radius(hand: Vector3, hit: Variant) -> float:
	if hit == null:
		return MIN_RADIUS
	return clampf(hand.distance_to(hit) * RADIUS_PER_METRE, MIN_RADIUS, MAX_RADIUS)


## Paints with the hand's tool.
func paint(b: Brush, center: Vector3, radius: float, delta: float) -> void:
	if b.hand.tool == Hand.Tool.STONE:
		_lay_ground(b, Ground.Kind.MEADOW if b.meadow else Ground.Kind.STONE, center, radius, delta)
		return
	var kind := "grass" if b.hand.tool == Hand.Tool.GRASS else "flowers"
	b.owed += RATES[b.hand.tool] * PI * radius * radius * delta
	var n := mini(int(b.owed), Commands.MAX_STROKE)
	b.owed -= int(b.owed)
	world.preview(b.hand, Budget.plants(kind, b.count if b.kind == kind else 0))
	if n == 0 or b.full:
		return
	# A hold paints up to the budget and no further: past it, plants stop coming and the hand feels why.
	if not Budget.fits(world.units, Budget.plants(kind, (b.count if b.kind == kind else 0) + n), world.devices()):
		b.full = true
		world.cap(b.hand)
		return
	if b.kind != kind or b.dabs.size() >= Commands.MAX_DABS or b.count + n > Commands.MAX_STROKE:
		_send_plants(b)
	if b.dabs.is_empty():
		b.kind = kind
		b.count = 0
		b.rng.seed = randi()
		b.looks = Flora.looks(b.rng.seed)
	b.dabs.append([center, radius, n])
	b.count += n
	b.stroke.append_array(flora.dab(kind, center, radius, n, b.rng, b.looks))
	planted.emit()
	Cues.play(Cues.Act.FLORA_PAINT, center, b.hand)


## A live path keeps its own copy of the ground mask, so nothing stamps it while one is drawn. One ground
## stroke at a time, so a player's strokes reach the garden in the order they were painted.
func _lay_ground(b: Brush, kind: Ground.Kind, center: Vector3, radius: float, delta: float) -> void:
	if b.ground != null and (b.ground.kind != kind or b.ground.stamps.size() >= Commands.MAX_STAMPS):
		_send_ground(b)
	b.since_stamp += delta
	if paths.busy() or (b.ground == null and _ground_held()) or (b.ground != null and b.since_stamp < STAMP_EVERY and center.distance_to(b.last_stamp) < radius * STAMP_MOVE):
		return
	if b.ground == null:
		b.ground = Ground.Stroke.new(kind)
		Ground.hold(b.ground)
	b.since_stamp = 0.0
	b.last_stamp = center
	if b.ground.add(center.x, center.z, radius * 0.4, radius * 0.8):
		planted.emit()
		Cues.play(Cues.Act.STONE_PAINT, center, b.hand)


func end_stroke(b: Brush) -> void:
	b.full = false
	if b.paving:
		end_path(b)
	_send_ground(b)
	_send_plants(b)


func _send_plants(b: Brush) -> void:
	var cmd := {"op": "plant", "kind": b.kind, "seed": b.rng.seed, "dabs": b.dabs}
	var ghost := b.stroke
	b.stroke = []
	b.dabs = []
	b.kind = ""
	if not cmd.dabs.is_empty():
		_sent += 1
		world.submit(cmd, _lay.bind(ghost), b.hand)


## A painted stroke of stone (or meadow) goes to the garden; it stays shown until its command comes back.
func _send_ground(b: Brush) -> void:
	var stroke := b.ground
	b.ground = null
	if stroke == null:
		return
	if stroke.stamps.is_empty():
		Ground.release(stroke)
		return
	world.submit({"op": "ground", "kind": int(stroke.kind), "stamps": stroke.stamps}, Ground.release.bind(stroke), b.hand)


## A sent stroke is settled: its plants grow in the garden now, or it was turned down.
func _lay(ghost: Array[Flora.Plant]) -> void:
	if flora.growing():
		await flora.grown
	for p in ghost:
		if p != null:
			p.set_shown(false)
	_sent -= 1
	if _sent == 0 and not busy():
		flora.clear_ghosts()


func _forget() -> void:
	for b in brushes:
		b.stroke = []
		b.dabs = []
		b.kind = ""
		b.ground = null
		b.paving = false
	paths.forget()
	flora.clear_ghosts()


func begin_path(b: Brush, at: Vector3, radius: float) -> void:
	b.paving = true
	paths.begin(at, radius, "dirt" if b.hand.tool == Hand.Tool.DIRT_PATH else "cobble")
	planted.emit()
	Cues.play(Cues.Act.PATH_LAY, at, b.hand)


func extend_path(at: Vector3, radius: float, hand: Hand = null) -> void:
	var laid := paths.extend(at, radius)
	planted.emit()
	if laid:
		Cues.play(Cues.Act.PATH_LAY, at, hand)


## Sends the drawn path to the garden; its stones and worn ground stay as drawn until the command comes back.
func end_path(b: Brush) -> void:
	b.paving = false
	var ghost := paths.end()
	if not ghost.is_empty():
		world.submit({"op": "path", "path": ghost.data}, paths.drop.bind(ghost), b.hand)
	planted.emit()


func place(kind: String, at: Vector3, hand: Hand = null, shape := randi()) -> void:
	var cmd := {"op": "plant", "kind": kind, "seed": shape, "at": at}
	if world.fits(cmd):
		Cues.play(Cues.Act.TREE_PLANT, at, hand)
	world.submit(cmd, Callable(), hand)
	planted.emit()
