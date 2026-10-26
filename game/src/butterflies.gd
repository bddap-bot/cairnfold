class_name Butterflies
extends Node3D

## Butterflies over the flowers the player has painted: a few fly in to a patch, flit from bloom to bloom
## and settle on them with their wings slowly opening and closing, scatter up and away when a hand or the
## head comes suddenly near, and leave once their patch is gone. All of them are one MultiMesh; the wingbeat is in its shader.
## Part of `Wildlife`, which decides when they come and where nobody is looking.

enum State { ARRIVE, FLIT, PERCH, FLEE, LEAVE }

const CAP := 24
## Painted flowers in bloom are grouped into square patches this wide; one with MIN_BLOOMS of them draws butterflies.
const PATCH := 3.0
const MIN_BLOOMS := 12
## Painted flowers looked at a frame, so regrouping them never costs one frame much.
const SCAN_PER_FRAME := 128
const PER_PATCH := Vector2i(2, 4)
const COLORS := [Color(0.86, 0.78, 0.36), Color(0.88, 0.52, 0.22), Color(0.42, 0.58, 0.86), Color(0.88, 0.88, 0.84), Color(0.64, 0.52, 0.86)]
const SIZE := Vector2(0.8, 1.2)
const FROM_DISTANCE := 14.0
const FROM_HEIGHT := 2.5
## How far off a leaving butterfly heads; it is let go sooner, once out of sight and LET_GO away.
const LEAVE_TO := 40.0
const LET_GO := 4.0
const SPEED := {State.ARRIVE: 1.4, State.FLIT: 0.6, State.FLEE: 2.4, State.LEAVE: 1.4}
const PERCH_FOR := Vector2(3.0, 10.0)
const FLEE_FOR := Vector2(4.0, 8.0)
const HOP := 1.5
## A hand or the head moving suddenly closer than this sends a butterfly off.
const SCATTER := 0.6
const CRUISE := 0.15
const BEAT_HZ := 9.0
const BASK_HZ := 0.5
## Wing angle about which a beat swings, and how far, in flight and perched.
const FLIGHT_WINGS := Vector2(0.3, 1.0)
const PERCH_WINGS := Vector2(0.65, 0.6)

var wildlife: Wildlife
var butterflies: Array[Butterfly] = []
## Each patch with enough blooms, by its cell, as (x, head height above the ground, z) per bloom.
var patches := {}
var rng := RandomNumberGenerator.new()
var crowd: Crowd
## The next painted slot to look at, or -1 to start over.
var _next := -1
var _filling := {}
var _bloom := 1.0
## What the patches were made from (`_inputs`), and what the pass under way started from: a pass starts only once they differ.
var _made_from := []
var _scanning := []


class Butterfly:
	var at := Vector3.ZERO
	var vel := Vector3.ZERO
	var state := State.ARRIVE
	var timer := 0.0
	var goal := Vector3.ZERO
	var patch := Vector2i.ZERO
	var phase := 0.0
	## 0 in flight, 1 perched; the wings ease between the two.
	var settled := 0.0
	var seed := 0.0
	var size := 1.0
	var color := Color.WHITE
	var yaw := 0.0
	## The height scale of the flower it makes for, and of the one it sits on, which it sways with.
	var goal_stalk := 0.0
	var stalk := 0.0
	## Drives the wander, so no two flutter alike.
	var clock := 0.0


func _init(home: Wildlife, seed: int) -> void:
	wildlife = home
	rng.seed = seed
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/butterfly.gdshader")
	crowd = Crowd.new(wildlife.terrain, Meshes.butterfly(), CAP, mat, true)
	add_child(crowd)


## Patches that no butterfly is staying at: where an arrival may be due.
func empty_patches() -> Array:
	var taken := {}
	for b in butterflies:
		if b.state != State.LEAVE:
			taken[b.patch] = true
	return patches.keys().filter(func(key: Vector2i) -> bool: return not taken.has(key))


func centre(key: Vector2i) -> Vector3:
	return wildlife.terrain.ground((key.x + 0.5) * PATCH, (key.y + 0.5) * PATCH)


## A few butterflies fly in to `key` from FROM_DISTANCE away along the level direction `from`.
func arrive(key: Vector2i, from: Vector3) -> void:
	var blooms: PackedVector3Array = patches[key]
	var start := centre(key) + from * FROM_DISTANCE + Vector3.UP * FROM_HEIGHT
	for i in mini(rng.randi_range(PER_PATCH.x, PER_PATCH.y), CAP - butterflies.size()):
		var b := Butterfly.new()
		b.patch = key
		b.seed = rng.randf() * 100.0
		b.size = rng.randf_range(SIZE.x, SIZE.y)
		b.color = COLORS[rng.randi() % COLORS.size()]
		b.phase = rng.randf() * TAU
		b.at = start + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.6, 0.6))
		_make_for(b, blooms[rng.randi() % blooms.size()])
		b.state = State.ARRIVE
		butterflies.append(b)


func tick(delta: float) -> void:
	_scan()
	for i in range(butterflies.size() - 1, -1, -1):
		var b := butterflies[i]
		b.clock += delta
		_think(b, delta)
		_move(b, delta)
		if b.state == State.LEAVE and wildlife._let_go(b.at, LET_GO):
			butterflies.remove_at(i)
	_upload()


## Looks over the next few painted flowers, and once all have been seen, makes the patches of those standing
## in bloom, above water and off paths, as the plant shader shows them.
func _scan() -> void:
	var pool := wildlife.flora.flowers
	if _next > pool.size():
		_next = -1
	if _next < 0:
		_scanning = _inputs()
		if _scanning == _made_from:
			return
		_filling = {}
		_bloom = wildlife.palette.bloom()
	_next = maxi(_next, pool.kept)
	var end := mini(_next + SCAN_PER_FRAME, pool.size())
	for i in range(_next, end):
		var p := pool.anchors[i]
		if p == Flora.Pool.GONE or FloraLayout.bloom_rank(p) >= _bloom or wildlife.marks.bare(p.x, p.z) > 0.5 or wildlife.water.pond_at(p.x, p.z) != null:
			continue
		var x := pool.plants[i].xform
		var key := Vector2i(floori(p.x / PATCH), floori(p.z / PATCH))
		if not _filling.has(key):
			_filling[key] = PackedVector3Array()
		_filling[key].append(Vector3(p.x, x.origin.y + x.basis.y.y * Meshes.FLOWER_HEIGHT, p.z))
	_next = end
	if _next < pool.size():
		return
	_made_from = _scanning
	patches.clear()
	for key in _filling:
		if _filling[key].size() >= MIN_BLOOMS:
			patches[key] = _filling[key]
	_next = -1
	for b in butterflies:
		if b.state != State.LEAVE and b.state != State.FLEE and patches.has(b.patch) and not _blooming(b):
			_flit(b)


## Everything a pass reads that can change: the flowers, the season's bloom, the marks, and the ground and water (`revision`).
func _inputs() -> Array:
	var pool := wildlife.flora.flowers
	return [pool.anchored, pool.size(), pool.kept, wildlife.palette.bloom(), wildlife.marks.rewears, wildlife.terrain.revision]


## Whether the bloom a butterfly makes for, or sits on, still stands in its patch.
func _blooming(b: Butterfly) -> bool:
	for p in patches[b.patch]:
		if absf(p.x - b.goal.x) < 1e-3 and absf(p.z - b.goal.z) < 1e-3:
			return true
	return false


func _make_for(b: Butterfly, bloom: Vector3) -> void:
	b.goal = Vector3(bloom.x, wildlife.terrain.height_at(bloom.x, bloom.z) + bloom.y + 0.01, bloom.z)
	b.goal_stalk = bloom.y / Meshes.FLOWER_HEIGHT


func _think(b: Butterfly, delta: float) -> void:
	if b.state == State.LEAVE:
		return
	if not patches.has(b.patch):
		_leave(b)
		return
	var fright := wildlife._startled(b.at, SCATTER)
	if b.state != State.FLEE and fright != null:
		b.state = State.FLEE
		b.timer = rng.randf_range(FLEE_FOR.x, FLEE_FOR.y)
		var off := b.at - fright.global_position
		off.y = 0.0
		b.goal = b.at + (off.normalized() + Vector3.UP * 1.2).normalized() * 3.0
	match b.state:
		State.ARRIVE, State.FLIT:
			if b.at.distance_to(b.goal) < 0.03:
				b.state = State.PERCH
				b.timer = rng.randf_range(PERCH_FOR.x, PERCH_FOR.y)
				b.at = b.goal
				b.vel = Vector3.ZERO
				b.stalk = b.goal_stalk
		State.PERCH, State.FLEE:
			if b.state == State.FLEE or not wildlife.asleep():
				b.timer -= delta
			if b.timer <= 0.0:
				_flit(b)


func _flit(b: Butterfly) -> void:
	var blooms: PackedVector3Array = patches[b.patch]
	var pick := blooms[rng.randi() % blooms.size()]
	for attempt in 8:
		var p := blooms[rng.randi() % blooms.size()]
		var d := Vector2(p.x - b.at.x, p.z - b.at.z).length()
		if d > 0.1 and d < HOP:
			pick = p
			break
	b.state = State.FLIT
	_make_for(b, pick)


func _leave(b: Butterfly) -> void:
	b.state = State.LEAVE
	b.goal = wildlife._unseen_point(b.at, LEAVE_TO, FROM_HEIGHT, Wildlife.LEAVE_SIGHT, rng)


## Flutters toward the goal on a wandering path that straightens as it closes in; perched, it only beats.
func _move(b: Butterfly, delta: float) -> void:
	var perched := b.state == State.PERCH
	b.settled = move_toward(b.settled, 1.0 if perched else 0.0, delta * 2.0)
	b.phase = fposmod(b.phase + TAU * lerpf(BEAT_HZ, BASK_HZ, b.settled) * delta, TAU)
	if perched:
		return
	var to := b.goal - b.at
	var d := to.length()
	var speed: float = SPEED[b.state]
	var wander := Vector3(sin(b.clock * 2.3 + b.seed), 0.6 * sin(b.clock * 3.7 + b.seed * 2.0), cos(b.clock * 1.9 + b.seed * 3.0))
	var want := to / maxf(d, 1e-4) * speed * clampf(d / 0.3, 0.2, 1.0) + wander * speed * 0.9 * clampf(d / 0.6, 0.0, 1.0)
	b.vel = b.vel.lerp(want, 1.0 - exp(-4.0 * delta))
	b.at += b.vel * delta
	if d > 0.4:
		b.at.y = maxf(b.at.y, wildlife.terrain.height_at(b.at.x, b.at.z) + CRUISE)
	if Vector2(b.vel.x, b.vel.z).length() > 0.05:
		b.yaw = lerp_angle(b.yaw, atan2(-b.vel.x, -b.vel.z), 1.0 - exp(-6.0 * delta))


func _upload() -> void:
	for i in butterflies.size():
		var b := butterflies[i]
		var wings := FLIGHT_WINGS.lerp(PERCH_WINGS, b.settled)
		var o := b.at + Vector3.UP * 0.012 * sin(b.phase) * (1.0 - b.settled)
		var x := Basis(Vector3.UP, b.yaw).scaled(Vector3.ONE * b.size)
		crowd.put(i, Transform3D(x, o), Color(b.phase, wings.y, wings.x, b.stalk * b.settled), b.color)
	crowd.upload(butterflies.size())
