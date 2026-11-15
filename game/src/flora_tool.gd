class_name FloraTool
extends Node3D

## A stone stroke begun on stone paints the ground back to meadow, and the plants under it stand up again.

## Plants per square metre per second of painting.
const RATES := {Hand.Tool.FLOWERS: 12.0, Hand.Tool.GRASS: 30.0, Hand.Tool.MOSS: 12.0}
const PLACES := {Hand.Tool.TREES: "tree", Hand.Tool.BUSHES: "bush"}
const TINTS := {Hand.Tool.MOSS: Color(0.4, 0.65, 0.15, 0.6), Hand.Tool.PATH: Color(0.78, 0.58, 0.35, 0.6), Hand.Tool.FLOWERS: Color(1.0, 0.82, 0.9, 0.6), Hand.Tool.GRASS: Color(0.78, 1.0, 0.55, 0.6), Hand.Tool.TREES: Color(0.85, 1.0, 0.8, 0.6), Hand.Tool.BUSHES: Color(0.85, 1.0, 0.8, 0.6), Hand.Tool.BOULDER: Color(0.9, 0.88, 0.82, 0.6), Hand.Tool.STONE: Color(0.9, 0.88, 0.82, 0.6)}
const RADIUS_PER_METRE := 0.15
const MIN_RADIUS := 0.3
const MAX_RADIUS := 3.0
## Seconds, and a fraction of the brush radius moved: a held ground brush stamps again after either.
const STAMP_EVERY := 0.1
const STAMP_MOVE := 0.3

signal planted


class Brush:
	var hand: Hand
	var ring: MeshInstance3D
	## The hold's ghost plants; the seed and dabs, sent as one command on release, grow the same plants on every
	## machine.
	var stroke: Array[Flora.Plant] = []
	var kind := ""
	var dabs := []
	var count := 0
	var rng := RandomNumberGenerator.new()
	var looks := RandomNumberGenerator.new()
	var ground: Ground.Stroke
	var meadow := false
	## As the budget counts it (Budget.reach).
	var reached := Image.create(Ground.SIZE, Ground.SIZE, false, Image.FORMAT_L8)
	var since_stamp := 0.0
	var last_stamp := Vector3.INF
	var owed := 0.0
	var drawing_path := false
	var full := false
	## Shown here alone. rock_from and rock_hand are its and the hand's pose when taken up; rock_gain is metres of
	## boulder per metre of hand.
	var rock: Boulders.Boulder
	var rock_from := Transform3D()
	var rock_hand := Transform3D()
	var rock_gain := 1.0


var rig: Rig
var flora: Flora
var paths: Paths
var world: World
var brushes: Array[Brush] = []
## Where the grass feels the left hand while it is untracked; desktop scripts hold it in the grass.
var stand_in := Flora.NO_HAND
var _ghost_strokes := 0
## Hidden once the garden has grown their plants. A connection, not an await: a coroutine still waiting when the tool
## is freed leaks its script.
var _settled: Array = []


func _init(player: Rig, plants: Flora, ways: Paths, garden: World) -> void:
	rig = player
	flora = plants
	paths = ways
	world = garden
	world.restored.connect(_forget)
	flora.grown.connect(_hide_settled)
	for h in rig.hands:
		var b := Brush.new()
		b.hand = h
		b.ring = ring(Color(1, 1, 1, 0.6))
		add_child(b.ring)
		brushes.append(b)


## Radius 1 until `put_ring` scales it.
static func ring(tint: Color, segments := 32, inner := 0.96) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = 1.0
	torus.rings = segments
	torus.ring_segments = 4
	var out := MeshInstance3D.new()
	out.mesh = torus
	out.material_override = Meshes.glow(tint)
	out.top_level = true
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out.visible = false
	return out


static func put_ring(r: MeshInstance3D, at: Vector3, radius: float, lift := 0.04) -> void:
	r.visible = true
	r.global_transform = Transform3D(Basis().scaled(Vector3(radius, 1.0, radius)), at + Vector3.UP * lift)


## A null `hand` asks about any hand.
func busy(hand: Hand = null) -> bool:
	return brushes.any(func(b: Brush) -> bool: return (hand == null or b.hand == hand) and (b.drawing_path or b.ground != null or not b.dabs.is_empty() or b.rock != null))


func _ground_held() -> bool:
	return brushes.any(func(b: Brush) -> bool: return b.ground != null)


func brush(hand: Hand) -> Brush:
	for b in brushes:
		if b.hand == hand:
			return b
	return null


func _process(delta: float) -> void:
	flora.part(rig.left.global_position if rig.left.tracked() else stand_in, _reach(rig.right))
	for b in brushes:
		_handle(b, delta)


func _handle(b: Brush, delta: float) -> void:
	var held := b.hand.tool
	b.ring.visible = false
	# A stroke no button holds is a demo script's: the hand's own aim neither extends nor ends it.
	if busy(b.hand) and not b.hand.buttons.held("tool") and not b.hand.buttons.released("tool"):
		return
	if not TINTS.has(held) or rig.aim_hand == b.hand:
		end_stroke(b)
		return
	if b.hand.buttons.released("tool"):
		end_stroke(b)
	if not b.hand.tracked():
		return
	var hand := b.hand.global_transform
	if b.rock != null:
		carry_boulder(b, hand)
		return
	var hit: Variant = world.terrain.raycast(hand.origin, -hand.basis.z)
	if held == Hand.Tool.MOSS:
		var solid := flora.solid_hit(hand.origin, -hand.basis.z, hand.origin.distance_to(hit) if hit != null else 30.0)
		if not solid.is_empty() and solid.plants[0].pool == flora.trunks:
			b.hand.point(solid.point, TINTS[held])
			end_stroke(b)
			if b.hand.buttons.pressed("tool"):
				coat_tree(solid.plants[0], b.hand)
			return
	var drowned: bool = hit != null and PLACES.has(held) and Water.drowned(world.terrain, hit)
	b.hand.point(hit, Hand.REFUSED if drowned else TINTS[held])
	if hit == null:
		end_stroke(b)
		return
	if drowned:
		if b.hand.buttons.pressed("tool"):
			Cues.play(Cues.Act.REFUSED, hit, b.hand)
		return
	if PLACES.has(held):
		world.preview(b.hand, Budget.plants(PLACES[held], 1))
		if b.hand.buttons.pressed("tool"):
			place(PLACES[held], hit, b.hand)
		return
	if held == Hand.Tool.BOULDER:
		world.preview(b.hand, World.units_for("boulders", {"scale": 1.0}))
		if b.hand.buttons.pressed("tool"):
			take_boulder(b, hit)
		return
	var radius := brush_radius(hand.origin, hit)
	if held == Hand.Tool.PATH:
		radius = clampf(radius, PathLayout.HALF_WIDTH.x, PathLayout.HALF_WIDTH.y)
	put_ring(b.ring, hit, radius)
	if held == Hand.Tool.PATH:
		if b.hand.buttons.pressed("tool") and not paths.busy() and not _ground_held():
			begin_path(b, hit, radius)
		elif b.hand.buttons.held("tool") and b.drawing_path:
			extend_path(hit, radius, b.hand)
	elif b.hand.buttons.held("tool"):
		if b.hand.buttons.pressed("tool"):
			b.meadow = paints_meadow(held, hit, world.marks)
		paint(b, hit, radius, delta)


static func _reach(hand: XRController3D) -> Vector3:
	return hand.global_position if hand.tracked() else Flora.NO_HAND


static func paints_meadow(tool: Hand.Tool, at: Vector3, marks: Ground) -> bool:
	return tool == Hand.Tool.STONE and marks.stone(at.x, at.z) > 0.5


static func brush_radius(hand: Vector3, hit: Variant) -> float:
	if hit == null:
		return MIN_RADIUS
	return clampf(hand.distance_to(hit) * RADIUS_PER_METRE, MIN_RADIUS, MAX_RADIUS)


func paint(b: Brush, center: Vector3, radius: float, delta: float) -> void:
	if b.hand.tool == Hand.Tool.STONE:
		_lay_ground(b, Ground.Kind.MEADOW if b.meadow else Ground.Kind.STONE, center, radius, delta)
		return
	var kind := "moss" if b.hand.tool == Hand.Tool.MOSS else "grass" if b.hand.tool == Hand.Tool.GRASS else "flowers"
	b.owed += RATES[b.hand.tool] * PI * radius * radius * delta
	var n := mini(int(b.owed), Commands.MAX_STROKE)
	b.owed -= int(b.owed)
	var painted := b.count if b.kind == kind else 0
	world.preview(b.hand, Budget.plants(kind, painted))
	if n == 0 or b.full:
		return
	# A hold paints up to the budget and no further: past it, plants stop coming and the hand feels why.
	if not Budget.fits(world.units, Budget.plants(kind, painted + n)):
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
	if kind == Ground.Kind.STONE:
		world.preview(b.hand, Budget.stone(b.reached))
	if paths.busy() or (b.ground == null and _ground_held()) or (b.ground != null and b.since_stamp < STAMP_EVERY and center.distance_to(b.last_stamp) < radius * STAMP_MOVE):
		return
	if kind == Ground.Kind.STONE:
		if b.full:
			return
		var trial := b.reached.duplicate() as Image
		Budget.reach(Vector4(center.x, center.z, radius * 0.4, radius * 0.8), trial)
		if not Budget.fits(world.units, Budget.stone(trial)):
			b.full = true
			world.cap(b.hand)
			return
		b.reached = trial
	if b.ground == null:
		b.ground = Ground.Stroke.new(kind, Ground.style)
		world.marks.hold(b.ground)
	b.since_stamp = 0.0
	b.last_stamp = center
	if b.ground.add(world.marks, center.x, center.z, radius * 0.4, radius * 0.8):
		planted.emit()
		Cues.play(Cues.Act.STONE_PAINT, center, b.hand)


func end_stroke(b: Brush) -> void:
	b.full = false
	if b.drawing_path:
		end_path(b)
	set_boulder(b)
	_send_ground(b)
	_send_plants(b)


func _send_plants(b: Brush) -> void:
	var cmd := {"op": "plant", "kind": b.kind, "seed": b.rng.seed, "dabs": b.dabs}
	var ghost := b.stroke
	b.stroke = []
	b.dabs = []
	b.kind = ""
	if not cmd.dabs.is_empty():
		_ghost_strokes += 1
		world.submit(cmd, _lay.bind(ghost), b.hand)


## The stroke stays shown until its command comes back.
func _send_ground(b: Brush) -> void:
	var stroke := b.ground
	b.ground = null
	b.reached.fill(Color.BLACK)
	if stroke == null:
		return
	if stroke.stamps.is_empty():
		world.marks.release(stroke)
		return
	var cmd := {"op": "ground", "kind": int(stroke.kind), "stamps": stroke.stamps}
	if stroke.kind == Ground.Kind.STONE:
		cmd.style = stroke.style
	world.submit(cmd, world.marks.release.bind(stroke), b.hand)


## Called once the command settles: its plants grow in the garden now, or it was turned down.
func _lay(ghost: Array[Flora.Plant]) -> void:
	_settled.append(ghost)
	if not flora.growing():
		_hide_settled()


func _hide_settled() -> void:
	var settled := _settled
	_settled = []
	for ghost: Array in settled:
		_ghost_strokes -= 1
		if _ghost_strokes == 0 and not busy():
			flora.clear_ghosts()
			continue
		# Hiding a stroke's ghost a plant at a time took 17 ms for a 1900-plant stroke on a Quest 2; clearing them is one call.
		for p: Flora.Plant in ghost:
			if p != null:
				p.set_shown(false)


func _forget() -> void:
	for b in brushes:
		b.stroke = []
		b.dabs = []
		b.kind = ""
		b.ground = null
		b.drawing_path = false
		if b.rock != null:
			b.rock.queue_free()
			b.rock = null
	paths.forget()
	flora.clear_ghosts()


func begin_path(b: Brush, at: Vector3, radius: float) -> void:
	b.drawing_path = true
	paths.begin(at, radius)
	planted.emit()
	Cues.play(Cues.Act.PATH_LAY, at, b.hand)


func extend_path(at: Vector3, radius: float, hand: Hand = null) -> void:
	var laid := paths.extend(at, radius)
	planted.emit()
	if laid:
		Cues.play(Cues.Act.PATH_LAY, at, hand)


## The path's stones and worn ground stay as drawn until the command comes back.
func end_path(b: Brush) -> void:
	b.drawing_path = false
	var ghost := paths.end()
	if not ghost.is_empty():
		world.submit(ghost.data.merged({"op": "path"}), paths.drop.bind(ghost), b.hand)
	planted.emit()


func coat_tree(trunk: Flora.Plant, hand: Hand) -> void:
	world.submit({"op": "tree", "group": trunk.group, "index": trunk.index, "moss": true}, Callable(), hand)


func take_boulder(b: Brush, at: Vector3, shape := randi(), scale := 1.0) -> void:
	b.rock = world.boulders.ghost(_boulder(at, Quaternion.IDENTITY, shape, scale))
	b.rock_from = b.rock.pose()
	b.rock_hand = b.hand.global_transform
	b.rock_gain = Hand.reach_gain(b.rock_hand.origin.distance_to(at))


func carry_boulder(b: Brush, hand: Transform3D) -> void:
	b.rock.hold(Boulders.carried(b.rock_from, b.rock_hand, hand, b.rock_gain), b.rock.size)


## The boulder keeps the turn it was held at and the depth it was pushed into the ground.
func set_boulder(b: Brush) -> void:
	var rock := b.rock
	b.rock = null
	if rock == null:
		return
	var pose := rock.pose()
	var turn := pose.basis.get_rotation_quaternion().normalized()
	place_boulder(pose.origin, b.hand, rock.shape.seed, rock.size, turn, rock, BoulderLayout.sink(rock.shape, turn, rock.size, pose.origin, world.terrain.height_at))


## `sink` is in unit-boulder metres (BoulderLayout.rest). The style is the one the style wheel let go last; `ghost`
## rests there until the command comes back.
func place_boulder(at: Vector3, hand: Hand = null, shape := randi(), scale := 1.0, turn := Quaternion.IDENTITY, ghost: Boulders.Boulder = null, sink := 0.0) -> void:
	var cmd := _boulder(at, turn.normalized(), shape, scale, sink)
	var from_y := ghost.position.y if ghost != null else -INF
	if ghost != null:
		ghost.appear(cmd)
	if world.fits(cmd):
		if ghost != null:
			ghost.landed(from_y, hand)
		else:
			Cues.play(Cues.Act.BOULDER_PLACE, at, hand, 0.0, scale)
	world.submit(cmd, ghost.queue_free if ghost != null else Callable(), hand)


func _boulder(at: Vector3, turn: Quaternion, shape: int, scale: float, sink := 0.0) -> Dictionary:
	return {"op": "boulder", "at": world.terrain.ground(at.x, at.z), "turn": turn, "sink": sink, "seed": shape, "scale": scale, "paint": world.wall_tool.paint.duplicate(), "style": Ground.style}


func place(kind: String, at: Vector3, hand: Hand = null, shape := randi()) -> void:
	var cmd := {"op": "plant", "kind": kind, "seed": shape, "at": at}
	world.submit_cued(cmd, Cues.Act.TREE_PLANT, at, hand)
	planted.emit()
