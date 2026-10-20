class_name HandStop
extends Node

## The hands you see stop at what is solid, as in Half-Life: Alyx: the tracked controller carries on into a wall,
## the ground, a roof, a trunk or an animal while its hand stays at the surface, slides along it and catches up as
## soon as the way back is clear. Tools keep aiming, pointing and grabbing from the tracked controller. What the
## hand touches it feels through one table, FEEL: a first touch pulses with how fast the hand came in, and moving
## along a surface, or through leaves and water, which the hand passes, plays that surface's grain.

enum Surface { NONE, GROUND, STONE, PLASTER, WOOD, TILE, BARK, LEAVES, WATER, WOOL, DOWN, FEATHERS }

## Per surface: `hard`, the first touch's strength; `leave`, the pulse on leaving it; `grain`, metres moved between
## ticks; `amp`, a tick's amplitude, varied by up to `rough` of itself; `tick`, a tick's seconds; `still`, the speed in
## m/s below which moving along or through it plays no grain. Water asks for a quick stroke before it ticks, so a hand
## resting or drifting under the surface feels nothing.
const FEEL := {
	Surface.GROUND: {"hard": 0.5, "leave": 0.0, "grain": 0.06, "amp": 0.035, "rough": 0.4, "tick": 0.008, "still": 0.05},
	Surface.STONE: {"hard": 1.0, "leave": 0.0, "grain": 0.025, "amp": 0.07, "rough": 0.7, "tick": 0.005, "still": 0.05},
	Surface.PLASTER: {"hard": 0.9, "leave": 0.0, "grain": 0.06, "amp": 0.03, "rough": 0.15, "tick": 0.005, "still": 0.05},
	Surface.WOOD: {"hard": 0.8, "leave": 0.0, "grain": 0.08, "amp": 0.08, "rough": 0.1, "tick": 0.01, "still": 0.05},
	Surface.TILE: {"hard": 0.9, "leave": 0.0, "grain": 0.13, "amp": 0.1, "rough": 0.05, "tick": 0.014, "still": 0.05},
	Surface.BARK: {"hard": 0.8, "leave": 0.0, "grain": 0.04, "amp": 0.08, "rough": 0.5, "tick": 0.008, "still": 0.05},
	Surface.LEAVES: {"hard": 0.25, "leave": 0.0, "grain": 0.05, "amp": 0.025, "rough": 0.6, "tick": 0.008, "still": 0.05},
	Surface.WATER: {"hard": 0.12, "leave": 0.025, "grain": 0.1, "amp": 0.012, "rough": 0.3, "tick": 0.012, "still": 0.5},
	Surface.WOOL: {"hard": 0.2, "leave": 0.0, "grain": 0.07, "amp": 0.03, "rough": 0.3, "tick": 0.025, "still": 0.05},
	Surface.DOWN: {"hard": 0.15, "leave": 0.0, "grain": 0.04, "amp": 0.02, "rough": 0.3, "tick": 0.015, "still": 0.05},
	Surface.FEATHERS: {"hard": 0.15, "leave": 0.0, "grain": 0.025, "amp": 0.015, "rough": 0.5, "tick": 0.008, "still": 0.05},
}
## Animals join this group, each with its `coat`.
const CRITTERS := &"critters"
## The hand body as a ball, in the controller's space: its box's centre and roughly its half-thickness.
const CENTRE := Vector3(0, -0.01, 0.04)
const RADIUS := 0.03
## The sweep samples no coarser than this, finer than any wall, roof, trunk or animal, then bisects to the surface.
const STEP := 0.04
const BISECT := 5
const SLIDES := 3
## How far past a stop the surface's facing is read, well over the bisection's last step.
const PROBE := 0.002
## A hand held further than this from its controller lets go and jumps back to it.
const BREAK := 1.0
## How much wider than a frame's sweep the world round a hand is gathered, so a moving hand keeps it a while.
const SPARE := 0.2
const ROOF_SHELL := 0.14
const FENCE_HALF := 0.06

var _rig: Rig
var _walls: WallTool
var _flora: Flora
var _boulders: Boulders
## Per hand, where its ball was last frame, in the rig's space so locomotion carries it along.
var _held: Array[Vector3] = []
var _feels: Array[Feel] = []
var _gathered: Array[Near] = []
var _stamps: Array[Vector4i] = []


func _init(player: Rig, walls: WallTool, plants: Flora, rocks: Boulders = null) -> void:
	_rig = player
	_walls = walls
	_flora = plants
	_boulders = rocks
	for h in _rig.hands:
		_held.append(Vector3.INF)
		_feels.append(Feel.new())
		_gathered.append(null)
		_stamps.append(Vector4i.ZERO)


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var critters := get_tree().get_nodes_in_group(CRITTERS)
	for i in _rig.hands.size():
		var hand: Hand = _rig.hands[i]
		if not hand.tracked():
			_held[i] = Vector3.INF
			hand.body.position = Vector3.ZERO
			continue
		var to := hand.global_transform * CENTRE
		var from := to if _held[i] == Vector3.INF else _rig.global_transform * _held[i]
		if from.distance_to(to) > BREAK:
			from = to
		var box := AABB(from, Vector3.ZERO).expand(to).grow(RADIUS + STEP)
		var near := _near_for(i, box)
		near.focus(box, critters.filter(func(c: Critter) -> bool: return c.hand != hand))
		var at := resolve(from, to, near.solid, near.normal)
		_held[i] = _rig.global_transform.affine_inverse() * at
		hand.body.global_position = hand.global_position + (at - to)
		var touched := near.touch(at.move_toward(to, 0.01)) if at.distance_to(to) > 1e-3 else Surface.NONE
		var pulse := _feels[i].step(now, delta, touched, near.passing(at), from.distance_to(to), from.distance_to(at))
		if pulse.x > 0.0:
			Cues.feel(hand, [pulse.x, pulse.y, 1, 0.0])


## The world round `box` for hand `i`: what was gathered last time while the box stays inside the region it was
## gathered for and nothing built or planted since, else gathered afresh for a region SPARE wider.
func _near_for(i: int, box: AABB) -> Near:
	var stamp := Vector4i(WallLayout._laid_count, _walls.walls.size() if _walls != null else 0, _flora.changes if _flora != null else 0, _boulders.changes if _boulders != null else 0)
	if _gathered[i] == null or _stamps[i] != stamp or not _gathered[i].region.encloses(box):
		_gathered[i] = Near.gather(_walls, _flora, box.grow(SPARE), _boulders)
		_stamps[i] = stamp
	return _gathered[i]


## Where a ball moving from `from` toward `to` comes to rest: `to` if the way is clear, else at the first surface it
## meets and then slid along it, the rest of the move turned along the surface's `normal`, a few times over to
## settle into corners. A ball that starts inside something is let go, so a build raised round a hand, or an animal
## walking into it, cannot trap it.
static func resolve(from: Vector3, to: Vector3, solid: Callable, normal: Callable) -> Vector3:
	if solid.call(from):
		return to
	var at := _sweep(from, to, solid)
	var pushed := to - from
	for i in SLIDES:
		if at == to:
			break
		var n: Vector3 = normal.call(at + pushed.normalized() * PROBE)
		var rest := to - at
		pushed = rest - n * minf(rest.dot(n), 0.0)
		if n == Vector3.ZERO or pushed.length_squared() < 1e-6:
			break
		var target := at + pushed
		at = _sweep(at, target, solid)
		if at == target:
			break
	return at


static func _sweep(from: Vector3, to: Vector3, solid: Callable) -> Vector3:
	var n := maxi(1, ceili(from.distance_to(to) / STEP))
	for k in range(1, n + 1):
		if not solid.call(from.lerp(to, float(k) / n)):
			continue
		var lo := float(k - 1) / n
		var hi := float(k) / n
		for j in BISECT:
			var mid := (lo + hi) * 0.5
			if solid.call(from.lerp(to, mid)):
				hi = mid
			else:
				lo = mid
		return from.lerp(to, lo)
	return to


## A hand's pulses from what it touches each frame: the surface it is held at, or else the one it passes through. A
## touch after the hand has been clear a moment pulses with its approach speed and the surface's hardness, and leaving
## it pulses its `leave` once; moving on plays the surface's grain. Each pulse is [amplitude, seconds], 0 for none.
class Feel:
	## Clear this long before a contact counts as a new touch, so a hand resting at a surface does not buzz.
	const CLEAR := 0.12
	## The closest two ticks come, so a fast slide stays a texture.
	const GAP := 0.025
	const SPEED_FULL := 1.5
	var _on := Surface.NONE
	var _clear_since := -INF
	var _last := -INF
	var _travel := 0.0
	## What leaving the surface last touched still owes, paid once so a hand bobbing at a pond's top pulses once.
	var _leave := 0.0
	var _rng := RandomNumberGenerator.new()

	## `approach` is how far the controller moved this frame, `slid` how far the hand you see did.
	func step(now: float, delta: float, held_at: Surface, passing: Surface, approach: float, slid: float) -> Vector2:
		var on := held_at if held_at != Surface.NONE else passing
		var out := Vector2.ZERO
		var dt := maxf(delta, 1e-3)
		if on == Surface.NONE:
			if _on != Surface.NONE:
				_clear_since = now
				if _leave > 0.0:
					out = Vector2(_leave, 0.02)
					_leave = 0.0
		elif _on == Surface.NONE and now - _clear_since >= CLEAR:
			out = Vector2(lerpf(0.08, 0.5, clampf(approach / dt / SPEED_FULL, 0.0, 1.0)) * FEEL[on].hard, 0.02)
			_travel = 0.0
			_leave = FEEL[on].leave
		elif slid / dt > FEEL[on].still:
			var feel: Dictionary = FEEL[on]
			_travel += slid
			if _travel >= feel.grain and now - _last >= GAP:
				_travel = fmod(_travel, feel.grain)
				var k := clampf(slid / dt / SPEED_FULL, 0.4, 1.0)
				out = Vector2(feel.amp * k * (1.0 + feel.rough * _rng.randf_range(-1.0, 1.0)), feel.tick)
		_on = on
		if out.x > 0.0:
			_last = now
		return out


## The world within a box, gathered once a frame per hand so each test along the sweep checks only the few pieces
## of wall, roof, tree and animal that can be there.
class Near:
	## The box gathered round.
	var region: AABB
	var walls: Array[Piece] = []
	var _gathered_walls: Array[Piece] = []
	var roofs: Array[RoofLayout] = []
	## Trunks as [world-to-mesh transform, cylinder, scale].
	var trunks: Array[Array] = []
	## Foliage and animals as [world-to-mesh transform, mesh box, surface].
	var leaves: Array[Array] = []
	var animals: Array[Array] = []
	var boulders: Array[Boulders.Boulder] = []
	var facing := Vector3.UP

	static func gather(on: WallTool, plants: Flora, box: AABB, rocks: Boulders = null) -> Near:
		var near := Near.new()
		near.region = box
		var flat := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		if on != null:
			for w in on.walls:
				if not w.pick_bounds.has_volume() or not w.pick_bounds.intersects(box):
					continue
				if w.roof != null:
					near.roofs.append(w.roof)
				near._add_wall(w.layout, flat)
		near._gathered_walls = near.walls.duplicate()
		if plants != null:
			for parts in plants.solids_in(flat):
				for part: Flora.Plant in parts:
					var at := part.xform.translated(Vector3.UP * Terrain.base_at(part.anchor.x, part.anchor.z))
					if part.pool.mesh is CylinderMesh:
						near.trunks.append([at.affine_inverse(), part.pool.mesh, at.basis.get_scale()])
					else:
						near.leaves.append([at.affine_inverse(), part.pool.mesh.get_aabb(), Surface.LEAVES])
		if rocks != null:
			for b: Boulders.Boulder in rocks.boulders.values():
				if AABB(b.transform.origin, Vector3.ZERO).grow(b.shape.reach() * b.size + RADIUS).intersects(box):
					near.boulders.append(b)
		return near

	## Narrows the walls tested to those reaching `box`, a frame's sweep, and gathers the animals there, which move.
	func focus(box: AABB, critters: Array) -> void:
		var flat := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		walls.clear()
		for w in _gathered_walls:
			if w.reach.intersects(flat):
				walls.append(w)
		animals.clear()
		for c: Critter in critters:
			if c.is_visible_in_tree() and c.mesh != null and (c.global_transform * c.mesh.get_aabb()).grow(RADIUS).intersects(box):
				animals.append([c.global_transform.affine_inverse(), c.mesh.get_aabb(), c.coat])

	## The pieces of `l` reaching into `flat`. Arc length bounds how far apart two samples stand, so a sample far
	## from `flat` skips every one after it that cannot be nearer: a long wall costs a few steps, not one per sample.
	func _add_wall(l: WallLayout, flat: Rect2) -> void:
		var half := FENCE_HALF if l.fence else WallLayout.THICKNESS * 0.5
		var reach := flat.grow(half + RADIUS)
		var n := l.samples.size()
		var lengths := l.lengths
		var i := 0
		while i < n - 1:
			var gap := _off(l.samples[i], reach)
			if gap <= lengths[i + 1] - lengths[i]:
				walls.append(Piece.new(l, i, i + 1, half))
				i += 1
			else:
				i = maxi(i + 1, lengths.bsearch(lengths[i] + gap) - 1)
		if l.closed and n > 1 and _off(l.samples[n - 1], reach) <= Vector2(l.samples[0].x - l.samples[n - 1].x, l.samples[0].z - l.samples[n - 1].z).length():
			walls.append(Piece.new(l, n - 1, 0, half))

	## How far outside `r` the ground point under `p` lies, along x or z whichever is further.
	static func _off(p: Vector3, r: Rect2) -> float:
		return maxf(maxf(r.position.x - p.x, p.x - r.end.x), maxf(maxf(r.position.y - p.z, p.z - r.end.y), 0.0))

	func solid(p: Vector3) -> bool:
		return touch(p) != Surface.NONE

	## Which way the surface faces whose inside holds `p`, or zero outside everything solid.
	func normal(p: Vector3) -> Vector3:
		return facing if touch(p, true) != Surface.NONE else Vector3.ZERO

	## What solid thing a ball at `p` is in, or NONE; `with_facing` leaves the way its surface faces in `facing`.
	func touch(p: Vector3, with_facing := false) -> Surface:
		if p.y - RADIUS < Terrain.height_at(p.x, p.z):
			if with_facing:
				facing = _slope(p, Terrain.height_at)
			return Surface.STONE if Ground.stone(p.x, p.z) > 0.5 else Surface.GROUND
		for w in walls:
			if _in_wall(p, w, with_facing):
				var l := w.layout
				return Surface.WOOD if l.fence else (Surface.PLASTER if l.plaster else Surface.STONE)
		for r in roofs:
			var below := p.y - r.height_at(p.x, p.z) + ROOF_SHELL * 0.5
			if r.over(p.x, p.z) and absf(below) < ROOF_SHELL * 0.5 + RADIUS:
				if with_facing:
					facing = _slope(p, r.height_at) * signf(below + 1e-6)
				return Surface.STONE if r.flat() else Surface.TILE
		for t in trunks:
			var inv: Transform3D = t[0]
			var local := inv * p
			var c: CylinderMesh = t[1]
			var s: Vector3 = t[2]
			if absf(local.y) > c.height * 0.5 + RADIUS / s.y:
				continue
			var r := lerpf(c.bottom_radius, c.top_radius, clampf(local.y / c.height + 0.5, 0.0, 1.0)) + RADIUS / maxf(minf(s.x, s.z), 1e-3)
			if local.x * local.x + local.z * local.z < r * r:
				if with_facing:
					facing = (inv.basis.transposed() * Vector3(local.x, 0.0, local.z)).normalized()
				return Surface.BARK
		for b in boulders:
			var local := b.transform.affine_inverse() * p
			var l := local.length()
			if l < 1e-6 or l < b.shape.radius(local / l) + RADIUS / b.size:
				if with_facing:
					facing = Boulders.facing(b, p)
				return Surface.STONE
		return _in_ellipsoids(p, animals, with_facing)

	## Up from a height field at (p.x, p.z), tipped with its slope.
	static func _slope(p: Vector3, height: Callable) -> Vector3:
		var e := 0.02
		var dx: float = height.call(p.x + e, p.z) - height.call(p.x - e, p.z)
		var dz: float = height.call(p.x, p.z + e) - height.call(p.x, p.z - e)
		return Vector3(-dx, 2.0 * e, -dz).normalized()

	## What a ball at `p` passes through: leaves or pond water, or NONE.
	func passing(p: Vector3) -> Surface:
		if p.y < Terrain.water_at(p.x, p.z):
			return Surface.WATER
		return _in_ellipsoids(p, leaves)

	## The surface of the first of `of` whose mesh box's inscribed ellipsoid holds `p`.
	func _in_ellipsoids(p: Vector3, of: Array[Array], with_facing := false) -> Surface:
		for t in of:
			var inv: Transform3D = t[0]
			var box: AABB = t[1]
			var half := box.size * 0.5
			var q := (inv * p - box.get_center()) / half
			if q.length_squared() < 1.0:
				if with_facing:
					facing = (inv.basis.transposed() * (q / half)).normalized()
				return t[2]
		return Surface.NONE

	func _in_wall(p: Vector3, w: Piece, with_facing: bool) -> bool:
		if not w.reach.has_point(Vector2(p.x, p.z)):
			return false
		var u := clampf(((p.x - w.a.x) * w.ab.x + (p.z - w.a.y) * w.ab.y) * w.inv_len2, 0.0, 1.0)
		var off := Vector2(p.x - w.a.x - w.ab.x * u, p.z - w.a.y - w.ab.y * u)
		var reach := w.half + RADIUS
		if off.length_squared() >= reach * reach:
			return false
		var l := w.layout
		var s := lerpf(w.s0, w.s1, u)
		var y := p.y - lerpf(w.y0, w.y1, u) - WallLayout.SINK
		var top := WallLayout.FENCE_HEIGHT if l.fence else l.standing(s) + WallLayout.CAP
		if y > top + RADIUS or y < -WallLayout.SINK - 2.0:
			return false
		if not l.opening_at(s, y).is_empty():
			return false
		for arch in l.live_arches:
			if absf(l.offset(s, arch)) < l.opening(y, false) - RADIUS:
				return false
		if with_facing:
			var side := off if off.length_squared() > 1e-8 else Vector2(-w.ab.y, w.ab.x)
			facing = Vector3.UP if top + RADIUS - y < reach - off.length() else Vector3(side.x, 0.0, side.y).normalized()
		return true


## A straight piece of a wall's ground curve, between two of its samples.
class Piece:
	var layout: WallLayout
	var a: Vector2
	var ab: Vector2
	var inv_len2: float
	var y0: float
	var y1: float
	var s0: float
	var s1: float
	var half: float
	## Where the ground point of a ball touching it can lie.
	var reach: Rect2

	func _init(l: WallLayout, i: int, j: int, half_thickness: float) -> void:
		layout = l
		var p := l.samples[i]
		var q := l.samples[j]
		a = Vector2(p.x, p.z)
		ab = Vector2(q.x - p.x, q.z - p.z)
		inv_len2 = 1.0 / maxf(ab.length_squared(), 1e-9)
		y0 = p.y
		y1 = q.y
		s0 = l.lengths[i]
		s1 = l.lengths[j] if j > 0 else l.length()
		half = half_thickness
		reach = Rect2(a, Vector2.ZERO).expand(a + ab).grow(half + RADIUS)
