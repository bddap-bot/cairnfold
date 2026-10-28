class_name Shy
extends Node3D

## Small animals that keep their distance: frogs at the ponds (`Frogs`), grass snakes in the grass beside them
## (`Snakes`), squirrels at planted trees (`Squirrels`) and owls on the perches at night (`Owls`). Each kind comes to
## habitats of its own, a while after one appears and where nobody is looking, and goes when its habitat does. One that
## a person comes toward within its `flight`, or moves suddenly near within its `startle`, gets away its own way; a
## person standing still, or teleporting, sends none off. A kind is one `Crowd`, its motions in its vertex shader, each
## animal's pose written as four numbers of custom data. Part of `Wildlife`.

## How long one takes to grow in as it comes, or to fade as it goes where it cannot walk off.
const FADE := 1.5
const LET_GO := 6.0

var wildlife: Wildlife
var rng := RandomNumberGenerator.new()
var crowd: Crowd
var animals: Array[One] = []
var cap := 0
var after := Wildlife.ARRIVE_AFTER
var _due := {}
var kind := ""
## The hands and head moving faster than still this tick: no one else comes toward anything or startles it.
var _moving: Array[Node3D] = []


## Each animal stands where it is drawn, in its kind's group, so a demo's view can find it.
class One extends Node3D:
	## The habitat it came to: a pond, a tree's trunk, or the perches.
	var home: Object
	var yaw := 0.0
	var state := 0
	var timer := 0.0
	var from := Vector3.ZERO
	var goal := Vector3.ZERO
	## How far through a hop or a flight from `from` to `goal`, and how long the whole of it takes.
	var t := 0.0
	var span := 1.0
	var clock := 0.0
	var shown := 0.0
	var leaving := false
	## Gone where it cannot walk off, as a frog under water: it fades instead.
	var fading := false
	var pose := Color()


func _init(home: Wildlife, seed: int, mesh: Mesh, shader: String, most: int, group: String) -> void:
	wildlife = home
	kind = group
	rng.seed = seed
	cap = most
	var mat := ShaderMaterial.new()
	mat.shader = load(shader)
	crowd = Crowd.new(wildlife.terrain, mesh, cap, mat)
	add_child(crowd)


## How many of the kind each habitat standing now is to have, by habitat.
func habitats() -> Dictionary:
	return {}


## Whether arrivals' waits count down now.
func active() -> bool:
	return true


## One of the kind coming to `home`, or null where it finds no place there.
func arrive(_home: Object) -> One:
	return null


func think(_a: One, _delta: float) -> void:
	pass


## Sets it on its way out of sight, or to fade, its habitat gone or its hours over.
func leave(a: One) -> void:
	a.fading = true


## Every habitat standing gets its full count now, as arrivals would bring it in their own time.
func fill() -> void:
	var homes := habitats()
	for h in homes:
		for i in homes[h] - animals.filter(func(a: One) -> bool: return a.home == h and not a.leaving).size():
			if animals.size() >= cap:
				return
			_come(arrive(h), h)


func _come(a: One, h: Object) -> void:
	if a == null:
		return
	a.home = h
	a.add_to_group(kind)
	add_child(a)
	animals.append(a)


func tick(delta: float) -> void:
	_moving.assign(wildlife._watched().filter(func(n: Node3D) -> bool: return not wildlife.still(n)))
	var homes := habitats()
	var have := {}
	for a in animals:
		if not a.leaving and (not homes.has(a.home) or have.get(a.home, 0) >= homes[a.home]):
			a.leaving = true
			leave(a)
		if not a.leaving:
			have[a.home] = have.get(a.home, 0) + 1
	var short := homes.keys().filter(func(h: Object) -> bool: return have.get(h, 0) < homes[h])
	for h in wildlife._ripe(_due, short, after, delta, active() and animals.size() < cap, rng):
		_due.erase(h)
		if animals.size() >= cap:
			break
		_come(arrive(h), h)
	for i in range(animals.size() - 1, -1, -1):
		var a := animals[i]
		a.clock += delta
		a.shown = move_toward(a.shown, 0.0 if a.fading else 1.0, delta / FADE)
		think(a, delta)
		if a.leaving and ((a.fading and a.shown <= 0.0) or (not a.fading and wildlife._let_go(a.position, LET_GO))):
			animals.remove_at(i)
			a.queue_free()
	for i in animals.size():
		crowd.put(i, animals[i].transform, animals[i].pose)
	crowd.upload(animals.size())


## A hand or the head coming toward `at` within `flight` across the ground, or moving suddenly within `startle`, or null.
func wary(at: Vector3, flight: float, startle: float) -> Node3D:
	for n in _moving:
		var p := n.global_position
		var off := Vector2(p.x - at.x, p.z - at.z).length()
		if (off < startle and wildlife.sudden(n)) or (off < flight and wildlife.approaching(n, at)):
			return n
	return null


## The level way from `n` to `at`.
static func away(at: Vector3, n: Node3D) -> Vector3:
	var off := Vector3(at.x - n.global_position.x, 0, at.z - n.global_position.z)
	return off.normalized() if off.length() > 1e-3 else Vector3.FORWARD


static func heading(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## Upright on the ground at `at`, facing `yaw`, leaning with the slope under it.
func standing(at: Vector3, yaw: float) -> Basis:
	var t := wildlife.terrain
	var up := Vector3(t.height_at(at.x - 0.1, at.z) - t.height_at(at.x + 0.1, at.z), 0.2, t.height_at(at.x, at.z - 0.1) - t.height_at(at.x, at.z + 0.1)).normalized()
	var back := Basis(Vector3.UP, yaw).z
	var right := up.cross(back).normalized()
	return Basis(right, up, right.cross(up))


## The head or the hand nearest `at` across the ground, or null beyond `reach`.
func nearest(at: Vector3, reach: float) -> Node3D:
	var best: Node3D = null
	for n in wildlife._watched():
		var p := n.global_position
		var off := Vector2(p.x - at.x, p.z - at.z).length()
		if off < reach:
			reach = off
			best = n
	return best
