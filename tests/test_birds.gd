extends SceneTree

## Headless checks of conures: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_birds.gd

const STEP := 1.0 / 30.0
const AWAY := Vector3(0, -50, 0)

var failures := 0


func _initialize() -> void:
	# Walls draw their seeds from the global generator.
	seed(1)
	Terrain.install()
	await process_frame
	_no_tool_places_a_bird()
	_wall_tops_are_perches()
	_plumages()
	await _carry()
	await _they_come_after_the_ducks_and_leave_with_the_perches()
	await _a_perch_taken_away_sends_them_elsewhere()
	await _with_no_room_they_leave()
	await _a_reshape_carries_them_with_their_perch()
	_torso_lags_the_head()
	await _shoulder()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _no_tool_places_a_bird() -> void:
	for key: String in Hand.Tool.keys():
		_check(not key in ["BIRD", "BIRDS", "CONURE", "CONURES"], "no hand tool %s" % key)
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with("_tool.gd") or f in ["hand.gd", "buttons.gd"]:
			var code := FileAccess.get_file_as_string("res://src/" + f)
			_check(not code.contains("Birds") and not code.contains("onure"), "%s reaches no bird" % f)
	_check(FileAccess.get_file_as_string("res://src/wildlife.gd").count("Birds.new(") == 1, "Wildlife alone makes the birds")
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with(".gd") and f not in ["birds.gd", "conure.gd", "held_item.gd"]:
			_check(not FileAccess.get_file_as_string("res://src/" + f).contains("Conure.new("), "%s makes no conure" % f)


## Every plumage colours each patch, the first stays iridescent, and a conure wears the one it is given.
func _plumages() -> void:
	_check(Conure.PLUMAGES.keys()[0] == "iridescent", "the first plumage is the iridescent one")
	for name: String in Conure.PLUMAGES:
		var hexes: Array = Conure.PLUMAGES[name]
		_check(hexes.size() == Conure.Patch.size(), "%s colours every patch" % name)
		for i in hexes.size():
			_check(Color.html_is_valid(hexes[i]) or (name == "iridescent" and i != Conure.Patch.BILL), "%s patch %d is a colour" % [name, i])
	var image := Conure.palette().get_image()
	_check(image.get_size() == Vector2i(Conure.Patch.size(), Conure.PLUMAGES.size()), "one palette row per plumage")
	var seen := {}
	for seed in 40:
		var conure := Conure.new(0.0, seed % Conure.PLUMAGES.size())
		seen[conure.get_instance_shader_parameter("plumage")] = true
		conure.free()
	_check(seen.size() == Conure.PLUMAGES.size(), "a conure wears the plumage it is given")


## A wall's perches stand on its top: on the cap, on merlons, on piers, on a fence's top rail and posts; none
## beside a flag, none on a roofed wall.
func _wall_tops_are_perches() -> void:
	for top in WallLayout.Top.values():
		var w := WallLayout.new()
		w.points.assign([Vector3(0, 0, 0), Vector3(6, 0, 0)])
		w.top = top
		w.flags.assign([3.0])
		w.build(func(_x: float, _z: float) -> float: return 0.0)
		var perches := w.perches()
		var low := INF
		var high := -INF
		var by_flag := 0
		for p in perches:
			var up: float = p.y - w.frame_at(p.x).point.y
			low = minf(low, up)
			high = maxf(high, up)
			by_flag += int(absf(p.x - 3.0) < 0.25)
		_check(perches.size() > 20, "a 6 m wall has perches along its top, %d" % perches.size())
		_check(low >= w.height + 0.05 and high <= w.height + 1.2, "they stand on its top: %.2f to %.2f up a wall %.2f tall" % [low, high, w.height])
		_check(by_flag == 0, "none beside the flag")
	var f := WallLayout.new()
	f.points.assign([Vector3(0, 0, 0), Vector3(6, 0, 0)])
	f.fence = true
	f.build(func(_x: float, _z: float) -> float: return 0.0)
	var rails := f.perches()
	_check(rails.size() > 20 and Array(rails).all(func(p: Vector3) -> bool: return p.y - f.frame_at(p.x).point.y > 0.85 and p.y - f.frame_at(p.x).point.y < WallLayout.FENCE_HEIGHT + 0.2), "a fence's perches are on its top rail and posts")
	var roofed := WallLayout.new()
	roofed.points.assign([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 3), Vector3(0, 0, 3)])
	roofed.closed = true
	roofed.cover = WallLayout.Cover.ROOF
	roofed.build(func(_x: float, _z: float) -> float: return 0.0)
	_check(roofed.perches().is_empty(), "a roofed house has no perches")


class Glade:
	var rig: Rig
	var world: World
	var flora: Flora
	var tool: WallTool
	var terrain: GroundGrab
	var wildlife: Wildlife

	func birds() -> Array[Birds.Bird]:
		return wildlife.birds.birds


func _glade(seed: int) -> Glade:
	var g := Glade.new()
	g.rig = Rig.new()
	root.add_child(g.rig)
	g.world = World.new()
	root.add_child(g.world)
	var paths := Paths.new()
	root.add_child(paths)
	g.flora = Flora.new()
	root.add_child(g.flora)
	g.flora.keep()
	g.tool = WallTool.new(g.rig, g.world, g.flora, paths)
	root.add_child(g.tool)
	g.tool.set_process(false)
	g.terrain = GroundGrab.new(g.rig, g.world)
	g.terrain.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(g.terrain)
	var water := Water.new([])
	g.terrain.reshaped.connect(g.tool.reground)
	root.add_child(water)
	g.world.attach(g.tool, g.flora, paths, g.terrain, water)
	var hands: Array[Node3D] = []
	hands.assign(g.rig.hands)
	await process_frame
	g.wildlife = Wildlife.new(water, g.flora, g.tool, Palette.new(), g.rig.head, hands, seed)
	root.add_child(g.wildlife)
	g.wildlife.set_process(false)
	for h in g.rig.hands:
		h.global_position = AWAY
	return g


## Ticks the wildlife without frames, the walls' stones and perches first laid as they stand, so what the
## animals see does not hang on how far a worker thread got.
func _run(g: Glade, seconds: float, each := Callable()) -> void:
	_lay(g)
	for i in int(seconds / STEP):
		g.wildlife.tick(STEP)
		if each.is_valid():
			each.call()


func _lay(g: Glade) -> void:
	for w in g.tool.walls:
		w.perches(true)


## As `_run`, a frame at a time, so walls lay their stones again as they would in play.
func _play(g: Glade, seconds: float, each := Callable()) -> void:
	for i in int(seconds / STEP):
		await process_frame
		_lay(g)
		g.wildlife.tick(STEP)
		if each.is_valid():
			each.call()


func _teardown(g: Glade) -> void:
	g.wildlife.free()
	for w in g.tool.walls:
		w.free()
	for n: Node in [g.terrain, g.tool, g.flora, g.world, g.rig]:
		n.queue_free()
	await process_frame


## Runs until a flock has come and every bird of it perches, or `seconds` have passed.
func _until_perched(g: Glade, seconds: float) -> void:
	_lay(g)
	for i in int(seconds / STEP):
		g.wildlife.tick(STEP)
		if g.birds().size() >= Birds.FLOCK.x and g.birds().all(func(b: Birds.Bird) -> bool: return b.state == Birds.State.PERCH):
			return


func _draw_wall(tool: WallTool, a: Vector3, b: Vector3) -> Wall:
	var m: WallTool.Mason = tool.masons[0]
	tool.begin_stroke(m, Terrain.ground(a.x, a.z))
	for i in 31:
		var p := a.lerp(b, i / 30.0)
		tool.extend_stroke(m, Terrain.ground(p.x, p.z))
	tool.end_stroke(m)
	return tool.walls[-1]


## Every bird that disappears was out of the viewer's sight in its last frame.
func _watch_vanishing(g: Glade, seen: Dictionary) -> Callable:
	return func() -> void:
		var now := {}
		for b in g.birds():
			now[b] = g.wildlife._in_sight(b.node.position)

		for b in seen:
			if not now.has(b) and seen[b]:
				_check(false, "a bird vanished in sight")
		seen.clear()
		seen.merge(now)


## Whether `at` is on top of a standing wall, or on the surface of a planted tree's crown and inside none of its blobs.
func _on_perch(g: Glade, at: Vector3) -> bool:
	for w in g.tool.walls:
		var s := w.layout.closest_s(at)
		var foot: Vector3 = w.layout.frame_at(s).point
		if Vector2(at.x - foot.x, at.z - foot.z).length() < WallLayout.THICKNESS and at.y > foot.y + w.layout.height and at.y < foot.y + w.layout.height + 1.0:
			return true
	for parts: Array in g.flora.placed("tree"):
		var trunk: Flora.Plant = parts[0]
		var ground := Terrain.height_at(trunk.anchor.x, trunk.anchor.z)
		if Vector2(at.x - trunk.anchor.x, at.z - trunk.anchor.z).length() > 4.0 or at.y < ground + 2.0:
			continue
		var nearest := INF
		for blob: Flora.Plant in parts.slice(1):
			var x := blob.xform
			x.origin.y += ground
			nearest = minf(nearest, (x.affine_inverse() * at).length())
		if nearest >= 0.6 and nearest < 1.4:
			return true
	return false


func _they_come_after_the_ducks_and_leave_with_the_perches() -> void:
	var g := await _glade(3)
	_run(g, 300.0)
	_check(g.birds().is_empty(), "a garden without perches draws no conures")

	g.world.submit({"op": "plant", "kind": "tree", "seed": 7, "at": Terrain.ground(-2.5, -9)})
	var wall := _draw_wall(g.tool, Vector3(0, 0, -7), Vector3(5, 0, -8))
	await process_frame
	_check(g.flora.placed("tree").size() == 1 and g.tool.walls.size() == 1 and wall.finished, "a planted tree and a finished wall")
	_check(g.rig.head.global_position.direction_to(Terrain.ground(1, -8)).dot(-g.rig.head.global_basis.z) > Wildlife.SIGHT, "the viewer looks at them")
	_run(g, 200.0)
	_check(g.birds().is_empty(), "no conure comes before the ducks")

	var duck := Duck.new(false, 0.0)
	g.wildlife.families.append(Wildlife.Family.new(duck))
	g.wildlife.tick(STEP)
	g.wildlife.families.clear()
	duck.free()
	_check(g.wildlife.ducks_came, "a duck coming counts")

	var seen := {}
	var vanishing := _watch_vanishing(g, seen)
	var appeared := [false]
	var first := func() -> void:
		vanishing.call()
		if not appeared[0] and not g.birds().is_empty():
			appeared[0] = true
			for b in g.birds():
				_check(not g.wildlife._in_sight(b.node.position), "a conure first appears out of sight")
	_run(g, Wildlife.ARRIVE_AFTER.x - 1.0, first)
	_check(g.birds().is_empty(), "no conure before its time")
	_run(g, Wildlife.ARRIVE_AFTER.y - Wildlife.ARRIVE_AFTER.x + 2.0, first)
	_check(g.birds().size() >= Birds.FLOCK.x and g.birds().size() <= Birds.FLOCK.y, "a pair or a trio flies in, %d" % g.birds().size())

	var states := {}
	var off_perch := [0.0]
	var watch := func() -> void:
		vanishing.call()
		for b in g.birds():
			states[b.state] = true
			if b.state == Birds.State.PERCH and not _on_perch(g, b.node.position):
				off_perch[0] = maxf(off_perch[0], 1.0)
			if b.preening > 0.0:
				states["preen"] = true
	_run(g, 240.0, watch)
	_check(g.birds().size() >= Birds.FLOCK.x and g.birds().size() <= Birds.CAP, "they stay while there are perches")
	_check(off_perch[0] == 0.0, "every perched conure stands on a wall top or a crown")
	for s in [Birds.State.PERCH, Birds.State.HOP, Birds.State.FLY, Birds.State.PECK, "preen"]:
		_check(states.has(s), "they %s" % (s if s is String else Birds.State.keys()[s].to_lower()))

	var perched: Birds.Bird = null
	for i in 600:
		for b in g.birds():
			if b.state == Birds.State.PERCH:
				perched = b
		if perched != null:
			break
		_run(g, STEP)
	_check(perched != null, "a conure sits on its perch")
	await _a_calm_approach_lets_him_close(g, perched, vanishing)
	await _a_sudden_move_startles_it_a_short_way(g, perched, vanishing)
	await _seeds_held_out_draw_one_onto_the_hand(g, vanishing)
	_two_hands_with_seeds_feed_two(g, vanishing)
	_another_players_dish_draws_one(g, vanishing)

	g.world.undo()
	g.world.undo()
	await process_frame
	_check(g.flora.placed("tree").is_empty() and g.tool.walls.is_empty(), "the tree and the wall are gone")
	_run(g, 120.0, vanishing)
	_check(g.birds().all(func(b: Birds.Bird) -> bool: return b.state == Birds.State.SHOULDER), "the conures leave once no perch stands, but for one riding your shoulder")
	g.rig.under = true
	_run(g, 120.0, vanishing)
	_check(g.birds().is_empty(), "and that one leaves too once sent off it")
	g.rig.under = false
	_run(g, 200.0)
	_check(g.birds().is_empty(), "and none come back without one")
	await _teardown(g)


## A hand or a head moved from `from` to `to` at `speed` metres a second, a tick at a time.
func _move(g: Glade, n: Node3D, from: Vector3, to: Vector3, speed: float, each := Callable()) -> void:
	var steps := maxi(int(from.distance_to(to) / speed / STEP), 1)
	for i in steps + 1:
		n.global_position = from.lerp(to, float(i) / steps)
		_run(g, STEP, each)


## A hand brought slowly right up to a perched conure, then a face: it stays, turned to watch, and steps aside
## only from the face, a hop along its perch.
func _a_calm_approach_lets_him_close(g: Glade, b: Birds.Bird, each: Callable) -> void:
	var hand: Node3D = g.rig.hands[0]
	var at := b.node.position
	var side := Vector3(0.7, 0.3, 0.7).normalized()
	var start := at + side * Birds.WATCH * 0.9
	hand.global_position = start
	_run(g, 1.0, each)
	var left := [false]
	var watching := func() -> void:
		each.call()
		left[0] = left[0] or b.state != Birds.State.PERCH
	_move(g, hand, start, at + side * 0.06, 0.3, watching)
	_check(not left[0], "a hand coming slowly right up to a conure leaves it on its perch")
	_run(g, 4.0, watching)
	_check(not left[0] and b.node.position == at, "held still beside it, it stays, %.2f m from the hand" % b.node.position.distance_to(hand.global_position))
	var facing := -b.node.global_basis.z
	var to_hand := hand.global_position - at
	_check(Vector2(facing.x, facing.z).normalized().dot(Vector2(to_hand.x, to_hand.z).normalized()) > 0.9, "and turns to watch it")
	_move(g, hand, hand.global_position, AWAY.lerp(at, 0.99), 0.4, each)
	hand.global_position = AWAY
	_run(g, 0.5, each)

	for i in 600:
		if b.state == Birds.State.PERCH:
			break
		_run(g, STEP, each)
	at = b.node.position
	var head: Node3D = g.rig.head
	var home := head.global_position
	var centre := at + Conure.BODY
	var early := [false]
	var leaning := func() -> void:
		each.call()
		var eye := (at + Conure.BODY).distance_to(head.global_position)
		early[0] = early[0] or (eye > Birds.SHUFFLE and b.state != Birds.State.PERCH)
	_move(g, head, centre + Vector3(0, 0.1, Birds.WATCH * 0.9), centre + Vector3(0, 0.02, 0.05), 0.3, leaning)
	_check(not early[0], "a face leaning in slowly startles it not until it is about to touch")
	_run(g, 1.0, each)
	var off := (b.node.position + Conure.BODY).distance_to(head.global_position)
	var hopped := b.node.position.distance_to(at)
	var along := b.state == Birds.State.PERCH and hopped > 0.0 and hopped < b.site.hop()
	var away := b.state != Birds.State.LEAVE and hopped > 0.0 and hopped <= Birds.STARTLE_TO.y
	_check(off > Birds.SHUFFLE and (along or away), "it shuffles aside along its perch, or with no room flies a short way, %.2f m, to %.2f m from the eye" % [hopped, off])
	_check(off - 0.07 > Rig.NEAR, "so the eye's near clip never cuts it")
	head.global_position = home
	_run(g, 1.0, each)


## A hand jerked at a perched conure: it flies off a short way to a perch, in sight, and stays in the garden.
func _a_sudden_move_startles_it_a_short_way(g: Glade, b: Birds.Bird, each: Callable) -> void:
	for i in 300:
		if b.state == Birds.State.PERCH:
			break
		_run(g, STEP, each)
	var hand: Node3D = g.rig.hands[0]
	var at := b.node.position
	hand.global_position = at + Vector3(1.2, 0.2, 0)
	_run(g, 1.0, each)
	_move(g, hand, hand.global_position, at + Vector3(0.3, 0.1, 0), 3.0, each)
	_run(g, STEP * 2, each)
	_check(b.state == Birds.State.FLY, "a sudden hand startles it up, state %s" % Birds.State.keys()[b.state])
	var from := hand.global_position
	_run(g, 4.0, each)
	var moved := b.node.position.distance_to(at)
	_check(b.state != Birds.State.LEAVE and b in g.birds(), "it stays in the garden")
	_check(moved <= Birds.STARTLE_TO.y + 0.01 and b.node.position.distance_to(from) > Birds.STARTLE, "a short way off, %.2f m, out of reach" % moved)
	_check(g.wildlife._in_sight(b.node.position), "and in sight")
	hand.global_position = AWAY
	_run(g, 1.0, each)


## A hand held out with seeds draws one conure onto it, one at a time, once it has stood looking at whoever holds
## them and at the hand a while; it eats on as long as the hand holds them out, carried slowly too, and a jerk sends it
## off a short way. Put away, the seeds keep nobody.
func _seeds_held_out_draw_one_onto_the_hand(g: Glade, each: Callable) -> void:
	var hand: Hand = g.rig.right
	var head: Node3D = g.rig.head
	var perch := g.birds()[0].spot
	hand.global_transform = Transform3D(Basis(Vector3.UP, 0.4), perch + Vector3(1.5, -0.4, 1.0))
	hand.held_still = true
	hand.tool = Hand.Tool.SEEDS
	var on: Array[Birds.Bird] = []
	var flew := [0]
	var decided := {}
	var eating := func() -> void:
		each.call()
		on.assign(g.birds().filter(func(b: Birds.Bird) -> bool: return b.state == Birds.State.FEED))
		flew[0] = maxi(flew[0], g.birds().filter(func(b: Birds.Bird) -> bool: return b.node.hand == hand).size())
		for b in g.birds():
			if b.state != Birds.State.DECIDE:
				continue
			var d: Dictionary = decided.get_or_add(b, {"at": b.node.position, "for": 0.0, "moved": 0.0, "head": 0.0, "hand": 0.0})
			d["for"] += STEP
			d.moved = maxf(d.moved, b.node.position.distance_to(d.at))
			if b.node._gaze.z > 0.9:
				var aim := b.node.transform.basis * (Basis(Vector3.UP, b.node._gaze.x) * Basis(Vector3.RIGHT, b.node._gaze.y) * Vector3.FORWARD)
				var eye := b.node.position + b.node.transform.basis * Conure.NECK
				d.head = maxf(d.head, aim.dot(eye.direction_to(head.global_position)))
				d.hand = maxf(d.hand, aim.dot(eye.direction_to(hand.global_position)))
	for i in int(40.0 / STEP):
		_run(g, STEP, eating)
		if not on.is_empty():
			break
	_check(on.size() == 1 and flew[0] == 1, "one conure comes to the seeds, %d" % on.size())
	if on.is_empty():
		return
	var b := on[0]
	var d: Dictionary = decided.get(b, {})
	_check(d.get("for", 0.0) >= Birds.DECIDE_FOR.x - STEP and d.get("for", 0.0) <= Birds.DECIDE_FOR.y + STEP, "it stood deciding a while first, %.2f s" % d.get("for", 0.0))
	_check(d.get("moved", 1.0) < 0.001, "where it stood")
	_check(d.get("head", 0.0) > 0.95 and d.get("hand", 0.0) > 0.95, "looking at whoever holds the seeds and at the hand, %.2f and %.2f" % [d.get("head", 0.0), d.get("hand", 0.0)])
	g.wildlife.calls._since["click"] = INF
	var cue_before: int = Cues.asked.get(Cues.Act.HAND_PECK, 0)
	b.node.event(Cues.Act.HAND_PECK)
	_check(g.wildlife.calls._since["click"] == 0.0 and Cues.asked.get(Cues.Act.HAND_PECK, 0) == cue_before + 1, "one hand peck event plays both the seed click and its pulse")
	g.wildlife.calls._since["click"] = INF
	g.wildlife.birds._voice(b, "FEED", 100.0)
	_check(is_inf(g.wildlife.calls._since["click"]), "feeding chatter has no independent seed-click timer")
	var pecks := [0]
	var watch_peck := func(act: Cues.Act) -> void:
		if act == Cues.Act.HAND_PECK:
			pecks[0] += 1
	b.node.animation_event.connect(watch_peck)
	var pecks_before: int = Cues.asked.get(Cues.Act.HAND_PECK, 0)
	_run(g, 6.0, eating)
	_check(pecks[0] > 0 and Cues.asked.get(Cues.Act.HAND_PECK, 0) - pecks_before == pecks[0], "mounted pecks each produce one cue, without a second feeding timer")
	b.node.animation_event.disconnect(watch_peck)
	var spot := hand.global_transform * Wildlife.ON_HAND
	_check(b.node.position.distance_to(spot) < 0.001, "and stands on the hand behind them")
	var stayed := [true]
	_run(g, Birds.appetite.eats_for.y * 3.0, func() -> void:
		eating.call()
		stayed[0] = stayed[0] and b.state == Birds.State.FEED)
	_check(stayed[0], "it stays on the hand while the seeds are held out, %.0f s" % (Birds.appetite.eats_for.y * 3.0))
	var start := hand.global_position
	_move(g, hand, start, start + Vector3(-0.3, 0.1, 0.2), 0.25, eating)
	_check(b.state == Birds.State.FEED and b.node.position.distance_to(hand.global_transform * Wildlife.ON_HAND) < 0.001, "carried slowly, it rides along eating")
	for speed in [0.5, 1.0, 1.5]:
		var peak := [0.0]
		_move(g, hand, hand.global_position, hand.global_position + Vector3(0.4, 0, 0), speed, func() -> void:
			eating.call()
			peak[0] = maxf(peak[0], g.wildlife._speed.get(hand, 0.0)))
		_check(b.state == Birds.State.FEED, "normal gesture/light flick %.1f m/s keeps the bird" % speed)
		print("motion: %.1f m/s gesture, smoothed peak %.3f, old release=%s new release=%s" % [speed, peak[0], peak[0] > Wildlife.CALM, b.state != Birds.State.FEED])
		_run(g, 0.5, eating)
	var pivot := hand.global_position - Vector3(0.4, 0, 0)
	for i in 30:
		hand.global_transform = Transform3D(Basis(Vector3.UP, i * PI / 60.0), pivot + Vector3(0.4, 0, 0).rotated(Vector3.UP, i * PI / 60.0))
		_run(g, STEP, eating)
	_check(b.state == Birds.State.FEED, "90 degree turn with arm extended keeps the bird")
	print("motion: 90 degree turn in 1 s, new release=", b.state != Birds.State.FEED)
	var flick_peak := [0.0]
	_move(g, hand, hand.global_position, hand.global_position + Vector3(0.4, 0.3, 0), 3.0, func() -> void:
		eating.call()
		flick_peak[0] = maxf(flick_peak[0], g.wildlife._speed.get(hand, 0.0)))
	print("motion: 3.0 m/s deliberate flick, smoothed peak %.3f, old release=%s new release=%s" % [flick_peak[0], flick_peak[0] > Wildlife.CALM, b.state != Birds.State.FEED])
	_run(g, STEP * 2, eating)
	_check(b.state == Birds.State.FLY and b.node.hand == null, "jerked, the hand sends it off")
	_run(g, 4.0, each)
	_check(b in g.birds() and b.state != Birds.State.LEAVE, "to a perch nearby, staying, state %s" % Birds.State.keys()[b.state])
	_check(not g.wildlife._eaters.has(hand) or g.wildlife._eaters[hand] != b, "and lets the hand go")
	hand.tool = Hand.Tool.WALLS
	_run(g, 1.0, each)
	_check(g.birds().all(func(b: Birds.Bird) -> bool: return b.node.hand == null), "seeds put away keep nobody")
	hand.held_still = false
	hand.global_position = AWAY


## Seeds held out in both hands: a conure stands on each, both at once, and both stay.
func _two_hands_with_seeds_feed_two(g: Glade, each: Callable) -> void:
	var perch := g.birds()[0].spot
	var sides := [Vector3(1.0, -0.4, 1.0), Vector3(-1.0, -0.4, 1.0)]
	for i in 2:
		var hand: Hand = g.rig.hands[i]
		hand.global_transform = Transform3D(Basis(Vector3.UP, 0.4), perch + sides[i])
		hand.held_still = true
		hand.tool = Hand.Tool.SEEDS
	var on := func() -> Array:
		return g.rig.hands.map(func(h: Hand) -> int: return g.birds().filter(func(b: Birds.Bird) -> bool: return b.state == Birds.State.FEED and b.node.hand == h).size())
	for i in int(120.0 / STEP):
		_run(g, STEP, each)
		if on.call() == [1, 1]:
			break
	_check(on.call() == [1, 1], "a conure on each hand at once, %s" % [on.call()])
	var both := [true]
	_run(g, 30.0, func() -> void:
		each.call()
		both[0] = both[0] and on.call() == [1, 1])
	_check(both[0], "and both stay")
	for h: Hand in g.rig.hands:
		h.tool = Hand.Tool.WALLS
		h.held_still = false
		h.global_position = AWAY
	_run(g, 4.0, each)


## Another player's dish held out, as `Session` shows it in their avatar's hand, draws a conure onto it as a hand here
## does; hidden again, it keeps nobody.
func _another_players_dish_draws_one(g: Glade, each: Callable) -> void:
	var dish := Dish.new()
	root.add_child(dish)
	g.wildlife.dishes.append(dish)
	dish.visible = true
	dish.global_transform = Transform3D(Basis(Vector3.UP, 0.4), g.birds()[0].spot + Vector3(1.5, -0.4, 1.0))
	dish.eyes = dish.global_position + Vector3(0.3, 0.5, 0.4)
	var on := func() -> Array[Birds.Bird]:
		return g.birds().filter(func(b: Birds.Bird) -> bool: return b.state == Birds.State.FEED and b.node.hand == dish)
	var looked := [0.0]
	for i in int(120.0 / STEP):
		_run(g, STEP, each)
		for b in g.birds():
			if b.state == Birds.State.DECIDE and b.node.hand == dish and b.node._gaze.z > 0.9:
				var aim := b.node.transform.basis * (Basis(Vector3.UP, b.node._gaze.x) * Basis(Vector3.RIGHT, b.node._gaze.y) * Vector3.FORWARD)
				looked[0] = maxf(looked[0], aim.dot((b.node.position + b.node.transform.basis * Conure.NECK).direction_to(dish.eyes)))
		if not on.call().is_empty():
			break
	_check(on.call().size() == 1, "a conure comes to another player's dish, %d" % on.call().size())
	_check(looked[0] > 0.95, "having looked at that player first, %.2f" % looked[0])
	_run(g, 2.0, each)
	if not on.call().is_empty():
		var b: Birds.Bird = on.call()[0]
		_check(b.node.position.distance_to(dish.global_transform * Wildlife.ON_HAND) < 0.001, "and stands on that hand behind the seeds")
	dish.visible = false
	_run(g, 1.0, each)
	_check(g.birds().all(func(b: Birds.Bird) -> bool: return b.node.hand != dish), "hidden, the dish keeps nobody")
	g.wildlife.dishes.erase(dish)
	dish.free()
	_run(g, 4.0, each)


## A wall taken away under perched conures, with another perch standing: from the next frame none counts on
## the wall, none perches in the air, and they settle on what stands.
func _a_perch_taken_away_sends_them_elsewhere() -> void:
	var g := await _glade(5)
	g.wildlife.ducks_came = true
	var first := _draw_wall(g.tool, Vector3(0, 0, -7), Vector3(5, 0, -8))
	_until_perched(g, Wildlife.ARRIVE_AFTER.y + 30.0)
	_check(g.birds().size() >= Birds.FLOCK.x and g.birds().all(func(b: Birds.Bird) -> bool: return b.state == Birds.State.PERCH), "conures perch on the only wall")
	var second := _draw_wall(g.tool, Vector3(-9, 0, -6), Vector3(-4, 0, -8))
	await process_frame
	await _play(g, 1.5)
	_check(g.wildlife.birds.sites.size() == 2, "a second wall to perch on, %d sites" % g.wildlife.birds.sites.size())
	g.world.submit({"op": "unwall", "ids": PackedInt32Array([first.id])})
	await process_frame
	await process_frame
	_check(not is_instance_valid(first), "the first wall is gone")
	g.wildlife.tick(STEP)
	_check(g.birds().all(func(b: Birds.Bird) -> bool: return b.site == null or b.site.standing()), "from the next frame no conure counts on the wall taken away")
	var off := [0, 0]
	await _play(g, 12.0, func() -> void:
		for b in g.birds():
			if b.state == Birds.State.PERCH:
				off[int(_on_perch(g, b.node.position))] += 1)
	_check(off[0] == 0, "no conure perches where the wall stood, %d frames" % off[0])
	_check(g.birds().size() >= Birds.FLOCK.x and g.birds().all(func(b: Birds.Bird) -> bool: return b.state != Birds.State.LEAVE), "they stay, with a wall still standing")
	_check(off[1] > 0, "and settle on it")
	await _teardown(g)


## A site with the one point to stand on.
class OnePoint extends Birds.Site:
	var at := Vector3.ZERO

	func standing() -> bool:
		return true

	func points() -> PackedVector3Array:
		return PackedVector3Array([at])


## Arrivals never share a point, and a bird whose perch is gone, with no room left elsewhere, flies off rather
## than staying in the air.
func _with_no_room_they_leave() -> void:
	var g := await _glade(6)
	var birds := g.wildlife.birds
	var one := OnePoint.new()
	one.at = Terrain.ground(0, -6) + Vector3.UP * 2.0
	birds.sites.assign([one])
	birds.arrive()
	_check(g.birds().size() == 1, "a flock coming to one free point brings one bird, %d" % g.birds().size())
	for i in int(10.0 / STEP):
		birds.tick(STEP)
	var b: Birds.Bird = g.birds()[0] if not g.birds().is_empty() else null
	_check(b != null and b.state == Birds.State.PERCH, "it perches")
	if b != null:
		var lost := Birds.Bird.new()
		lost.node = Conure.new(0.0, 0)
		birds.add_child(lost.node)
		lost.node.position = one.at + Vector3(1, 0, 0)
		lost.state = Birds.State.PERCH
		lost.site = Birds.WallSite.new(null)
		lost.spot = lost.node.position
		birds.birds.append(lost)
		birds.sites.assign([one])
		birds._flutter(lost)
		_check(lost.state == Birds.State.LEAVE, "a bird whose perch is gone and finds no room leaves, state %d" % lost.state)
	await _teardown(g)


## Ground pulled up under a perched flock: once the wall is laid on it again they stand on its top as it now
## is, and on the crown over the ground now under the tree.
func _a_reshape_carries_them_with_their_perch() -> void:
	var g := await _glade(3)
	g.wildlife.ducks_came = true
	g.world.submit({"op": "plant", "kind": "tree", "seed": 7, "at": Terrain.ground(-2.5, -9)})
	_draw_wall(g.tool, Vector3(0, 0, -7), Vector3(5, 0, -8))
	await process_frame
	_until_perched(g, Wildlife.ARRIVE_AFTER.y + 30.0)
	_check(g.birds().any(func(b: Birds.Bird) -> bool: return b.state == Birds.State.PERCH), "conures perch")
	g.terrain.begin(g.terrain.rig.right, Terrain.ground(1, -8), 8.0)
	g.terrain.pull(g.terrain.rig.right, 1.5)
	g.terrain.end_stroke(g.terrain.rig.right)
	_run(g, 1.0)
	await _play(g, 4.0)
	var off := [0, 0]
	await _play(g, 6.0, func() -> void:
		for b in g.birds():
			if b.state == Birds.State.PERCH:
				off[1] += 1
				if not _on_perch(g, b.node.position):
					off[0] += 1)
	_check(off[1] > 0 and off[0] == 0, "perched conures stand on the wall top or crown as they are after the reshape, %d of %d frames off" % off)
	await _teardown(g)


func _carry() -> void:
	var g := await _glade(24)
	var easels := Easels.new()
	root.add_child(easels)
	var painting := EaselTool.new(g.rig, easels, g.world)
	root.add_child(painting)
	painting.set_process(false)
	var carry := BirdCarry.new(g.rig, g.wildlife.birds, painting)
	root.add_child(carry)
	carry.set_process(false)
	var h := g.rig.right
	h.held_still = true
	h.global_position = Vector3(0, 1.0, 0)
	h.tool = Hand.Tool.SEEDS
	var b := Birds.Bird.new()
	b.node = Conure.new(0, 0)
	g.wildlife.birds.add_child(b.node)
	g.wildlife.birds.birds.append(b)
	b.node.global_position = h.global_position
	b.state = Birds.State.FEED
	b.node.hand = h
	g.wildlife.claim(h, b)
	_check(not carry.take(h, b), "unfed bird refuses pickup")
	for i in 250:
		g.wildlife.birds._to_hand(b, STEP)
	_check(b.affection == BirdCarry.TRUST, "feeding earns trust")
	_check(carry.take(h, b), "fed bird accepts gentle pickup")
	_check(h.carried == b.node and h.tool == Hand.Tool.NONE, "carry is not a wheel tool")
	Buttons.injected["%s/%s" % [h.tracker, Controls.input("grab", h.tracker)]] = true
	h.global_position += Vector3(5, 2, 1)
	for i in 120:
		carry._process(STEP)
		g.wildlife.birds.tick(STEP)
	_check(b.node.global_position.distance_to(h.body.global_transform * BirdCarry.HOLD.origin) < 0.001, "bird follows carried hand without a flick departure")
	var description := HeldItem.describe(h, painting, null)
	_check(HeldItem.valid(description) and description[0] == HeldItem.Kind.BIRD, "carried bird uses shared remote descriptor")
	Buttons.injected.clear()
	carry._process(STEP)
	_check(h.carried == null and not b.carried and b.node.hand == null, "letting go clears ownership")
	_check(b.state in [Birds.State.FLY, Birds.State.LEAVE], "release flies rather than falls")


## The torso stays put while the head turns within a neck's reach, and follows once it turns further.
func _torso_lags_the_head() -> void:
	_check(is_equal_approx(Torso.follow(NAN, Basis(Vector3.UP, 0.4)), 0.4), "a first look sets the torso under the head")
	_check(Torso.follow(0.0, Basis(Vector3.UP, 1.0)) == 0.0, "a head turned aside leaves the torso")
	_check(is_equal_approx(Torso.follow(0.0, Basis(Vector3.UP, -1.6)), -1.6 + Torso.TURN), "a head turned past a neck's reach brings the torso round")
	_check(is_equal_approx(Torso.follow(3.0, Basis(Vector3.UP, -3.0)), 3.0), "the torso turns the short way round")


## A conure that trusts you comes to the outer edge of your shoulder, out of sight ahead and in sight turned to it; it
## rides teleports and snap turns, a hand brushed at it or your head under water sends it off to come back later, and
## it can be taken from there like any carried conure. Peers get it as a held model standing on the shoulder.
func _shoulder() -> void:
	var g := await _glade(31)
	_draw_wall(g.tool, Vector3(-1.5, 0, -3), Vector3(1.5, 0, -3))
	_lay(g)
	var flock := g.wildlife.birds
	flock.look()
	flock.arrive()
	_until_perched(g, 30.0)
	_check(g.birds().size() >= 2, "a flock perched on the wall")
	if g.birds().size() < 2:
		await _teardown(g)
		return
	var b: Birds.Bird = g.birds()[0]
	var shy := g.birds().slice(1)
	_check(not _until_shouldered(g, b, 30.0), "a conure that does not trust you keeps off your shoulder")
	b.affection = BirdCarry.TRUST
	_check(_until_shouldered(g, b, 60.0), "a conure that trusts you comes to your shoulder")
	_check(shy.all(func(o: Birds.Bird) -> bool: return o.shoulder < 0), "only the trusting one rides")
	var rig := g.rig
	_check(rig.shoulders[b.shoulder] == b.node, "the rig knows who rides its shoulder")
	_check(_on_its_shoulder(g, b) < 0.01, "it stands on the shoulder, %.3f m off" % _on_its_shoulder(g, b))
	var outer: float = (rig.torso().affine_inverse() * b.node.global_position).x * (1.0 if b.shoulder == 1 else -1.0)
	_check(outer > 0.18, "it stands out at the shoulder's edge, %.2f m from the neck" % outer)
	_check(_off_view(rig, b) > deg_to_rad(50.0), "looking ahead it is out of view, %.0f° off" % rad_to_deg(_off_view(rig, b)))
	var ahead := rig.head.transform
	rig.head.transform.basis = Basis.from_euler(Vector3(-0.6, Torso.TURN * (-1.0 if b.shoulder == 1 else 1.0), 0))
	_tick(g, 0.5)
	_check(_off_view(rig, b) < deg_to_rad(35.0), "turned to it and looking down it is in view, %.0f° off" % rad_to_deg(_off_view(rig, b)))
	_check(_on_its_shoulder(g, b) < 0.01, "turning the head leaves it on the shoulder")
	rig.head.transform = ahead
	_tick(g, 0.5)
	var worst := 0.0
	rig.snap_turn(Rig.SNAP)
	for i in 10:
		_tick(g, STEP)
		worst = maxf(worst, _on_its_shoulder(g, b))
	rig.place(rig.head.global_position + Vector3(2.5, 0, 1.5) - Vector3.UP * rig.head.global_position.y, 0.0)
	for i in 10:
		_tick(g, STEP)
		worst = maxf(worst, _on_its_shoulder(g, b))
	_check(b.state == Birds.State.SHOULDER and worst < 0.02, "it rides snap turns and teleports, %.3f m off at worst" % worst)

	var description := HeldItem.perched(rig, b.shoulder)
	_check(HeldItem.valid(description) and description[0] == HeldItem.Kind.BIRD and description[5] == 1, "peers get a shoulder conure as a held model")
	var seen := HeldItem.new()
	root.add_child(seen)
	seen.show_state(description)
	var bare := Conure.new(0.0, 0)
	_check(seen.model is Conure and seen.model.get_child_count() == bare.get_child_count(), "the peers' shoulder conure stands without the hand's cup")
	bare.free()
	seen.free()
	_check(HeldItem.perched(rig, 1 - b.shoulder).is_empty(), "the other shoulder is bare")

	var h := rig.right
	var at := b.node.global_position + Conure.BODY
	for i in 20:
		h.global_position = at + Vector3(0.1 if i % 2 else -0.1, 0, 0)
		_tick(g, STEP)
		if b.shoulder < 0:
			break
	h.global_position = AWAY
	_check(b.shoulder < 0 and b.state in [Birds.State.FLY, Birds.State.LEAVE] and rig.shoulders.all(func(c: Conure) -> bool: return c == null), "a hand brushed at it shoos it off")
	_check(_until_shouldered(g, b, Birds.AWAY_FOR.y + 60.0), "a shooed conure that still trusts you comes back later")

	rig.under = true
	_tick(g, STEP)
	_check(b.shoulder < 0 and rig.shoulders.all(func(c: Conure) -> bool: return c == null), "your head under water sends it off")
	_check(not _until_shouldered(g, b, Birds.AWAY_FOR.y + 10.0), "it keeps off while you are under water")
	rig.under = false
	_check(_until_shouldered(g, b, 60.0), "it comes back once you are out of the water")

	var easels := Easels.new()
	root.add_child(easels)
	var painting := EaselTool.new(rig, easels, g.world)
	root.add_child(painting)
	painting.set_process(false)
	var carry := BirdCarry.new(rig, flock, painting)
	root.add_child(carry)
	carry.set_process(false)
	h.tool = Hand.Tool.NONE
	h.held_still = true
	h.global_position = b.node.global_position + Vector3(0, 0.03, 0)
	_check(carry.take(h, b), "a conure on your shoulder can be taken in the hand")
	_check(b.shoulder < 0 and rig.shoulders.all(func(c: Conure) -> bool: return c == null), "taken, it leaves the shoulder free")
	carry.release(h)
	_check(b.state in [Birds.State.FLY, Birds.State.LEAVE], "let go, it flies")
	h.global_position = AWAY
	for n: Node in [carry, painting, easels]:
		n.free()
	await _teardown(g)


func _tick(g: Glade, seconds: float) -> void:
	for i in maxi(1, int(seconds / STEP)):
		g.wildlife.tick(STEP)


## Ticks until `b` stands on a shoulder, or `seconds` pass; whether it does.
func _until_shouldered(g: Glade, b: Birds.Bird, seconds: float) -> bool:
	for i in int(seconds / STEP):
		_lay(g)
		g.wildlife.tick(STEP)
		if b.state == Birds.State.SHOULDER:
			return true
	return false


func _on_its_shoulder(g: Glade, b: Birds.Bird) -> float:
	return b.node.global_position.distance_to(Birds._shoulder_at(g.rig, b.shoulder).origin) if b.shoulder >= 0 else INF


## How far off the middle of the view the bird's body is.
func _off_view(rig: Rig, b: Birds.Bird) -> float:
	var eyes := rig.head.global_transform
	return (-eyes.basis.z).angle_to(b.node.global_transform * Conure.BODY - eyes.origin)
