extends SceneTree

## Headless checks of windows, doors, lanterns, flags, chimneys and fences, as layouts and through the tools:
## godot4 --headless --path game --script ../tests/test_fittings.gd

var failures := 0
var main: Node


func _initialize() -> void:
	_a_window_cuts_its_opening()
	_a_low_window_reaches_the_ground_as_a_door()
	_neighbours_fuse()
	_a_window_stands_over_a_door()
	_windows_keep_clear()
	_windows_on_two_courses_stay_apart()
	_the_lintel_course_is_cut()
	_a_new_window_never_closes_another()
	_windows_fuse_across_a_loop_seam()
	_flags_keep_their_colour()
	_a_house_takes_windows()
	_lanterns_hang_off_the_face()
	_flags_fly_from_open_tops()
	_a_fence_is_posts_and_rails()
	_a_gate_in_a_fence()
	_fences_never_arch_over_plants()
	_chimneys_clear_the_ridge()
	_a_tower_flies_a_flag()
	_ivy_keeps_out_of_windows()
	_fittings_are_deterministic()
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_in_the_glade.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _wall(length: float, height: float, windows: Array[Vector2], arches: Array[float] = []) -> WallLayout:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(length, 0, 0)]
	w.height = height
	w.windows = windows
	w.arches = arches
	w.build(_flat)
	return w


func _kind(w: Variant, kind: String) -> Array:
	var list: Array = w.stones if w is WallLayout else w.tiles
	return list.filter(func(s): return s.kind == kind)


## Coursed stones that reach into an opening's clear span.
func _intruders(w: WallLayout, o: Dictionary) -> Array:
	return w.stones.filter(func(s): return (s.kind == "block" or s.kind == "mortar") and s.y > o.sill + 0.05 and s.y < o.head - 0.05 and absf(s.s - o.s) < o.half + s.size.x * 0.5 - 0.02)


func _a_window_cuts_its_opening() -> void:
	var w := _wall(8.0, 2.7, [Vector2(4.0, 1.5)])
	_check(w.openings.size() == 1, "one window opens, got %d" % w.openings.size())
	if w.openings.is_empty():
		return
	var o := w.openings[0]
	_check(not o.door and o.lights == 1, "a window at 1.5 m is a single window")
	_check(o.sill > 0.6 and o.head <= w.height - w.course_height() + 0.01, "sill %.2f and head %.2f leave a lintel course under the top" % [o.sill, o.head])
	_check(is_equal_approx(fmod(o.sill + 1e-4, w.course_height()), 1e-4), "the sill sits on a course joint")
	_check(_intruders(w, o).is_empty(), "no coursed stone fills the window")
	for k in ["glass", "frame", "lintel", "sill", "plaster"]:
		_check(not _kind(w, k).is_empty(), "a window has a %s" % k)
	var lintel: Dictionary = _kind(w, "lintel")[0]
	_check(lintel.size.x > o.half * 2.0 and lintel.y > o.head, "the lintel spans the opening above its head")


func _a_low_window_reaches_the_ground_as_a_door() -> void:
	var w := _wall(8.0, 2.7, [Vector2(4.0, 0.8)])
	_check(w.openings.size() == 1 and w.openings[0].door, "a click low on the wall makes a door")
	if w.openings.is_empty():
		return
	var o := w.openings[0]
	_check(o.sill == 0.0 and o.head >= 1.9, "a door runs from the ground to %.2f" % o.head)
	_check(_intruders(w, o).is_empty(), "no coursed stone fills the door")
	_check(_kind(w, "door").size() >= 3 and _kind(w, "sill").is_empty(), "a door is planks with no sill")


func _neighbours_fuse() -> void:
	var w := _wall(8.0, 2.7, [Vector2(3.6, 1.5), Vector2(4.4, 1.5)])
	_check(w.openings.size() == 1 and w.openings[0].lights == 2, "two windows side by side fuse into one opening of two lights")
	_check(_kind(w, "mullion").size() == 1, "a mullion stands between the lights")
	if not w.openings.is_empty():
		_check(absf(w.openings[0].s - 4.0) < 0.01 and _intruders(w, w.openings[0]).is_empty(), "the fused opening is clear around its middle")
	var doors := _wall(8.0, 2.7, [Vector2(3.6, 0.8), Vector2(4.4, 0.8)])
	_check(doors.openings.size() == 1 and doors.openings[0].lights == 2 and doors.openings[0].door, "two doors side by side make a double door")
	var apart := _wall(8.0, 2.7, [Vector2(2.4, 1.5), Vector2(5.6, 1.5)])
	_check(apart.openings.size() == 2, "windows far apart stay two, got %d" % apart.openings.size())
	var mixed := _wall(8.0, 2.7, [Vector2(3.6, 1.5), Vector2(4.4, 0.8)])
	_check(mixed.openings.size() == 1, "a door does not fuse with a window, and they cannot share the span: %d openings" % mixed.openings.size())


func _a_window_stands_over_a_door() -> void:
	var w := _wall(8.0, 4.2, [Vector2(4.0, 0.8), Vector2(4.0, 3.0)])
	_check(w.openings.size() == 2, "a window over a door, %d openings" % w.openings.size())
	for o in w.openings:
		_check(_intruders(w, o).is_empty(), "the %s at %.2f is clear" % ["door" if o.door else "window", o.sill])


func _windows_keep_clear() -> void:
	_check(_wall(8.0, 2.7, [Vector2(0.5, 1.5)]).openings.is_empty(), "no window in a wall's end pier")
	_check(_wall(8.0, 2.7, [Vector2(4.0, 1.5)], [4.0]).openings.is_empty(), "no window in an arch")
	_check(_wall(8.0, 2.7, [Vector2(4.0, 2.5)]).openings.is_empty(), "no window above the top")
	_check(_wall(8.0, 2.7, [Vector2(4.0, 2.25)]).openings.is_empty(), "no window whose head reaches the top, leaving no course for its lintel")
	_check(_wall(8.0, 1.2, [Vector2(4.0, 1.0)]).openings.is_empty(), "a wall too low for a door takes none")
	var w := _wall(8.0, 2.7, [Vector2(4.0, 1.5)])
	w.height = 1.5
	w.build(_flat)
	_check(w.openings.is_empty(), "lowering the wall under a window closes it")
	w.height = 2.7
	w.build(_flat)
	_check(w.openings.size() == 1, "raising it again opens it")


func _house() -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(8, 0, 0), 5.0)
	w.closed = true
	w.roofed = true
	w.top = WallLayout.Top.CAP
	w.height = 2.4
	return w


func _windows_on_two_courses_stay_apart() -> void:
	var w := _wall(8.0, 4.2, [Vector2(4.0, 1.5), Vector2(4.0, 2.7)])
	_check(w.openings.size() == 2 and w.openings.all(func(o): return o.lights == 1), "windows one above the other stay two single windows: %s" % [w.openings])


func _the_lintel_course_is_cut() -> void:
	var w := _wall(8.0, 2.7, [Vector2(4.0, 1.5)])
	var o := w.openings[0]
	var reach: float = o.half + WallLayout.LINTEL_EAR
	var under := w.stones.filter(func(s): return (s.kind == "block" or s.kind == "mortar") and s.y > o.head and s.y < o.head + w.course_height() and absf(s.s - o.s) < reach + s.size.x * 0.5 - 0.02)
	_check(under.is_empty(), "the lintel's course is cut for it, %d coursed stones in its way" % under.size())


func _a_new_window_never_closes_another() -> void:
	var w := _wall(8.0, 2.7, [Vector2(4.0, 1.5)])
	_check(w.window_fits(Vector2(6.0, 1.5)), "a window clear of the first fits")
	_check(w.window_fits(Vector2(4.8, 1.5)), "a window beside the first fuses with it")
	_check(not w.window_fits(Vector2(3.4, 1.85)), "a window a course up, overlapping the first, would close it, so it does not fit")


func _windows_fuse_across_a_loop_seam() -> void:
	var w := WallLayout.new()
	w.points = WallLayout.circle(Vector3.ZERO, 2.5)
	w.closed = true
	w.height = 4.5
	w.build(_flat)
	w.windows = [Vector2(0.2, 2.0), Vector2(w.length() - 0.3, 2.0)]
	w.build(_flat)
	_check(w.openings.size() == 1 and w.openings[0].lights == 2, "two windows either side of a tower's seam fuse: %s" % [w.openings])
	if w.openings.size() == 1:
		_check(absf(w.offset(w.openings[0].s, 0.0) + 0.05) < 0.01, "the fused opening is centred between them, across the seam: s=%.2f" % w.openings[0].s)
		_check(_intruders(w, w.openings[0]).is_empty(), "the opening across the seam is clear")


func _flags_keep_their_colour() -> void:
	var w := _wall(8.0, 2.7, [])
	w.flags = [2.0, 6.0]
	w.build(_flat)
	var before := w.cloths.map(func(c): return c.color)
	w.lanterns = [Vector3(4.0, 1.5, 1.0)]
	w.windows = [Vector2(4.0, 0.8)]
	w.height = 3.0
	w.build(_flat)
	_check(w.cloths.map(func(c): return c.color) == before, "a flag keeps its colour while its wall is raised, lit and given a door")


func _a_house_takes_windows() -> void:
	var w := _house()
	w.windows = [Vector2(2.0, 1.5), Vector2(4.0, 0.8), Vector2(8.0, 1.5)]
	w.build(_flat)
	_check(w.openings.size() == 2, "a house takes a window and a door on its long wall, not one on its corner: %d" % w.openings.size())
	_check(w.openings.any(func(o): return o.door), "the house's door")


func _lanterns_hang_off_the_face() -> void:
	var w := _wall(8.0, 2.7, [Vector2(5.0, 1.5)])
	w.lanterns = [Vector3(2.5, 1.6, 1.0), Vector3(2.5, 1.6, -1.0), Vector3(5.0, 1.6, 1.0), Vector3(1.0, 0.3, 1.0)]
	w.build(_flat)
	_check(w.flames.size() == 2, "lanterns hang on both faces, not in the window nor down at the ground: %d flames" % w.flames.size())
	var out := Vector3(0, 0, -1)
	for f in w.flames:
		var off := absf(f.origin.dot(out))
		_check(off > WallLayout.THICKNESS * 0.5 + 0.15, "a flame hangs %.2f m out from the centre plane, clear of the face" % off)
		_check(absf(f.origin.y - 1.6 - 0.055) < 0.2 and absf(f.origin.x - 2.5) < 0.01, "a flame at %s" % f.origin)
	if w.flames.size() == 2:
		_check(signf(w.flames[0].origin.z) != signf(w.flames[1].origin.z), "the two lanterns are on opposite faces")
	_check(_kind(w, "iron").size() >= 4, "lanterns hang from iron arms")
	var arched := _wall(8.0, 2.7, [], [4.0])
	arched.lanterns = [Vector3(4.6, 1.6, 1.0)]
	arched.build(_flat)
	_check(arched.flames.is_empty(), "no lantern in an arch")


func _flags_fly_from_open_tops() -> void:
	var w := _wall(8.0, 2.7, [])
	w.flags = [4.0]
	w.build(_flat)
	_check(w.cloths.size() == 1 and _kind(w, "pole").size() == 1, "a flag on the wall's top")
	if w.cloths.size() == 1:
		_check(w.cloths[0].xform.origin.y > w.height + 1.0, "the cloth flies above the top, at %.2f" % w.cloths[0].xform.origin.y)
	var h := _house()
	h.flags = [2.0]
	h.build(_flat)
	_check(h.cloths.is_empty(), "no flag on a roofed wall's top")


func _fence(length: float, arches: Array[float] = []) -> WallLayout:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(length, 0, 0)]
	w.fence = true
	w.height = WallLayout.FENCE_HEIGHT
	w.arches = arches
	w.windows = [Vector2(length * 0.5, 1.5)]
	w.build(_flat)
	return w


func _a_fence_is_posts_and_rails() -> void:
	var w := _fence(8.0)
	_check(_kind(w, "post").size() == 6, "an 8 m fence has 6 posts, got %d" % _kind(w, "post").size())
	_check(_kind(w, "rail").size() == 10, "two rails in each of 5 bays, got %d" % _kind(w, "rail").size())
	_check(_kind(w, "block").is_empty() and _kind(w, "pier").is_empty() and _kind(w, "cap").is_empty(), "no stone in a fence")
	_check(w.openings.is_empty(), "no windows in a fence")
	for p in _kind(w, "post"):
		var top: float = p.xform.origin.y + p.size.y * 0.5
		_check(top > WallLayout.FENCE_HEIGHT - 0.1 and top < WallLayout.FENCE_HEIGHT + 0.15, "a post's top at %.2f" % top)
	w.lanterns = [Vector3(3.0, 1.0, 1.0)]
	w.build(_flat)
	_check(w.flames.size() == 1 and absf(w.flames[0].origin.x - 3.2) < 0.01, "a lantern on a fence stands on the nearest post, at %s" % (w.flames[0].origin if w.flames.size() else null))
	w.lanterns = [Vector3(3.0, 1.0, 1.0), Vector3(3.6, 1.0, 1.0)]
	w.build(_flat)
	_check(w.flames.size() == 1, "two lanterns for one post light it once, %d flames" % w.flames.size())


func _a_gate_in_a_fence() -> void:
	var w := _fence(8.0, [4.0])
	_check(w.live_arches == [4.0], "a crossing opens a gate in the fence")
	var tall := _kind(w, "post").filter(func(p): return p.size.y > WallLayout.FENCE_HEIGHT + 0.5)
	_check(tall.size() == 2, "two tall gate posts, got %d" % tall.size())
	_check(_kind(w, "gate").size() == 9, "a bent wooden arch over the gate")
	_check(_kind(w, "rail").all(func(r): return absf(r.s - 4.0) > WallLayout.ARCH_HALF), "no rail across the gate")
	_check(_kind(w, "post").all(func(p): return absf(p.s - 4.0) > WallLayout.ARCH_HALF), "no post in the gate")
	_check(_fence(8.0, [0.6]).live_arches.is_empty(), "no gate at a fence's very end")


func _fences_never_arch_over_plants() -> void:
	var stroke: Array[Vector3] = [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(8, 0, 0)]
	var plants := PackedVector3Array([Vector3(4, 0, 0.1)])
	var walls := WallPlan.new([], plants, 1).pieces(stroke, _flat)
	var plan := WallPlan.new([], plants, 1)
	plan.fence = true
	var fences := plan.pieces(stroke, _flat)
	_check(walls.size() == 1 and walls[0].arches.size() == 1, "a wall arches over the plant")
	_check(fences.size() == 1 and fences[0].fence and fences[0].arches.is_empty() and is_equal_approx(fences[0].height, WallLayout.FENCE_HEIGHT), "a fence goes by it, low and unarched")


func _gable() -> RoofLayout:
	var r := RoofLayout.new()
	r.corners = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(8, 0, 0), 5.0)
	r.base = 2.5
	r.pitch = 2.0
	return r


func _chimneys_clear_the_ridge() -> void:
	var r := _gable()
	r.chimneys = [Vector2(2.0, 1.2), Vector2(40.0, -40.0)]
	r.build()
	var stack := _kind(r, "chimney")
	_check(stack.size() > 8, "two chimneys of stacked stones, %d stones" % stack.size())
	var top: float = stack.reduce(func(m, s): return maxf(m, s.xform.origin.y), 0.0)
	_check(top > r.base + r.pitch + 0.6, "a chimney clears the ridge: top %.2f over ridge %.2f" % [top, r.base + r.pitch])
	_check(_kind(r, "pot").size() == 4, "two pots on each chimney")
	var spot := r.chimney_spot(Vector2(40.0, -40.0))
	_check(absf(spot.x) <= r.ridge_length() * 0.5 - RoofLayout.STACK_WIDTH + 0.001 and absf(spot.y) <= r.half_span() - RoofLayout.STACK_WIDTH + 0.001, "a chimney placed off the roof is pulled back onto it: %s" % spot)
	var f := r.frame()
	var p: Vector3 = f.mid + f.along * 2.0 + f.across * 1.2 + Vector3.UP
	_check(r.spot_of(p).distance_to(Vector2(2.0, 1.2)) < 0.001, "a point on the roof maps back to its chimney spot")


func _a_tower_flies_a_flag() -> void:
	var r := RoofLayout.new()
	r.kind = RoofLayout.Kind.CONE
	r.radius = 2.0
	r.base = 4.5
	r.pitch = 3.0
	r.build()
	_check(r.cloths.is_empty() and _kind(r, "pole").is_empty(), "a bare cone has a finial and no flag")
	r.flag = true
	r.build()
	_check(r.cloths.size() == 1 and _kind(r, "pole").size() == 1, "a flagged cone flies one flag")
	if r.cloths.size() == 1:
		_check(r.cloths[0].xform.origin.y > r.base + r.pitch + 1.0, "the flag flies above the cone's tip")


func _ivy_keeps_out_of_windows() -> void:
	var w := _wall(10.0, 3.0, [Vector2(3.0, 0.8), Vector2(6.5, 1.6)])
	_check(w.openings.size() == 2, "a door and a window for the ivy to avoid")
	var leaves := IvyLayout.grow(w.snapshot())
	_check(leaves.size() > 50, "ivy grows on the wall, %d leaves" % leaves.size())
	for l in leaves:
		for o in w.openings:
			if absf(l.s - o.s) < o.half - 0.05 and l.y > o.sill + 0.05 and l.y < o.head - 0.05:
				_check(false, "a leaf at s=%.2f y=%.2f grows over the %s" % [l.s, l.y, "door" if o.door else "window"])
				return


func _fittings_are_deterministic() -> void:
	var make := func() -> WallLayout:
		var w := _wall(9.0, 3.0, [Vector2(3.0, 0.8), Vector2(6.0, 1.6), Vector2(6.8, 1.6)])
		w.lanterns = [Vector3(4.5, 1.5, 1.0)]
		w.flags = [4.5]
		w.build(_flat)
		return w
	var a: WallLayout = make.call()
	var b: WallLayout = make.call()
	_check(a.stones.size() == b.stones.size() and range(a.stones.size()).all(func(i): return a.stones[i].xform.is_equal_approx(b.stones[i].xform)), "the same wall lays the same fittings")


## Through the tools, in the glade.
func _in_the_glade() -> void:
	var walls: Array[Wall] = main.tool.walls
	var fit: FittingTool = main.fitting_tool
	var history: History = main.history
	await _play([
		{"op": "place", "x": 0, "z": 12},
		{"op": "wall", "points": [[-8, 0], [-3, 0], [2, 0]], "seconds": 0.3},
		{"op": "house", "a": [8, 0], "b": [14, 0], "seconds": 0.2},
		{"op": "tower", "points": [[-14, 8], [-12.5, 6], [-10.5, 6.5], [-10, 8.5], [-11.5, 10.2], [-13.6, 9.8], [-14, 8]], "seconds": 0.5, "hold": 0.6},
		{"op": "fence", "points": [[-6, 8], [0, 8], [5, 8]], "seconds": 0.3},
	])
	_check(walls.size() == 4, "a wall, a house, a tower and a fence stand: %d" % walls.size())
	if walls.size() != 4:
		_done()
		return
	var wall := walls[0]
	var house := walls[1]
	var tower := walls[2]
	var fence := walls[3]
	_check(fence.layout.fence and not wall.layout.fence, "the fence tool drew a fence")
	_check(fence.layout.live_arches.is_empty() and wall.layout.live_arches.size() == 1, "a fence over open ground opens no arch where a long wall does")

	var face := wall.layout.frame_at(2.5)
	var normal: Vector3 = face.tangent.cross(Vector3.UP)
	var on_face: Vector3 = face.point + Vector3.UP * 1.5
	var lantern_spot: Vector3 = wall.layout.frame_at(7.6).point + Vector3.UP * 1.5
	var t := fit.aim(Hand.Tool.DECORATIONS, lantern_spot + normal * 3.0, -normal)
	_check(t.get("what") == "lantern" and t.wall == wall and t.side == 1.0 and absf(t.s - 7.6) < 0.3 and absf(t.y - 1.5) < 0.15, "decorations pointed at a wall's face hang a lantern there: %s" % t)
	_check(fit.aim(Hand.Tool.DECORATIONS, on_face - normal * 3.0, normal).get("side") == -1.0, "from the other side, on the other face")
	var near_top: Vector3 = face.point + Vector3.UP * (wall.layout.height - 0.1)
	_check(fit.aim(Hand.Tool.DECORATIONS, near_top + normal * 3.0, -normal).get("what") == "flag", "at a wall's top they fly a flag")
	var w_aim := fit.aim(Hand.Tool.WINDOWS, on_face + normal * 3.0, -normal)
	_check(w_aim.get("what") == "window", "windows pointed at a wall open a window")
	var ridge: Vector3 = house.roof.frame().mid + Vector3.UP * (house.roof.pitch * 0.5)
	_check(fit.aim(Hand.Tool.DECORATIONS, ridge + house.roof.frame().across * 1.2 + Vector3.UP * 6.0, Vector3.DOWN).get("what") == "chimney", "on a house's roof, a chimney")
	_check(fit.aim(Hand.Tool.DECORATIONS, tower.roof.frame().mid + Vector3.UP * 12.0, Vector3.DOWN).get("what") == "tower_flag", "on a tower's roof, a flag")
	_check(fit.aim(Hand.Tool.WINDOWS, ridge + Vector3.UP * 6.0, Vector3.DOWN).is_empty(), "windows do nothing on a roof")
	var post := fence.layout.frame_at(3.0)
	var post_n: Vector3 = post.tangent.cross(Vector3.UP)
	_check(fit.aim(Hand.Tool.DECORATIONS, post.point + Vector3.UP * 0.8 + post_n * 3.0, -post_n).get("what") == "lantern", "on a fence, a lantern")
	_check(fit.aim(Hand.Tool.WINDOWS, post.point + Vector3.UP * 0.8 + post_n * 3.0, -post_n).is_empty(), "no windows in a fence")
	_check(main.tool.pick_wall(post.point + Vector3.UP * 0.8 + post_n * 3.0, -post_n).get("wall") == fence, "a ray through the fence and on into the wall behind picks the fence")
	fit.fit(fit.aim(Hand.Tool.DECORATIONS, post.point + Vector3.UP * 0.8 + post_n * 3.0, -post_n))
	_check(fence.layout.flames.size() == 1, "a press hangs a lantern on the fence")
	var beside: Vector3 = fence.layout.frame_at(3.7).point + Vector3.UP * 0.8
	fit.fit(fit.aim(Hand.Tool.DECORATIONS, beside + post_n * 3.0, -post_n))
	_check(fence.layout.flames.is_empty() and fence.layout.lanterns.is_empty(), "a press farther along the same post takes it away")

	var steps := history.undo_stack.size()
	fit.fit(w_aim)
	_check(wall.layout.openings.size() == 1 and history.undo_stack.size() == steps + 1, "a press opens a window, one undo step")
	fit.fit(fit.aim(Hand.Tool.WINDOWS, on_face + face.tangent * 0.8 + normal * 3.0, -normal))
	_check(wall.layout.openings.size() == 1 and wall.layout.openings[0].lights == 2, "a press beside it fuses a second light into it")
	fit.fit(fit.aim(Hand.Tool.WINDOWS, on_face + normal * 3.0, -normal))
	_check(wall.layout.windows.size() == 1 and wall.layout.openings.size() == 1 and wall.layout.openings[0].lights == 1, "a press on a light closes that light")
	var on_arch := wall.layout.point_at(wall.layout.live_arches[0]) + Vector3.UP * 1.0
	var before := history.undo_stack.size()
	fit.fit(fit.aim(Hand.Tool.WINDOWS, on_arch + normal * 3.0, -normal))
	_check(history.undo_stack.size() == before and wall.layout.windows.size() == 1, "a window that cannot open in an arch is not placed and leaves no step")
	history.undo()
	_check(wall.layout.openings[0].lights == 2, "undo brings the closed light back")
	history.undo()
	history.undo()
	_check(wall.layout.openings.is_empty() and wall.layout.windows.is_empty(), "undo closes the windows")
	history.redo()
	_check(wall.layout.openings.size() == 1, "redo opens one again")

	fit.fit(t)
	_check(wall.layout.flames.size() == 1, "a press hangs the lantern")
	fit.place_lights()
	var lit := fit.get_children().filter(func(n): return n is OmniLight3D and n.visible)
	_check(lit.size() == 1 and lit[0].global_position.is_equal_approx(wall.layout.flames[0].origin), "a real light shines from the lantern")
	fit.fit(t)
	_check(wall.layout.flames.is_empty(), "a second press takes the lantern away")
	history.undo()
	_check(wall.layout.flames.size() == 1, "undo hangs it again")

	fit.fit({"what": "chimney", "wall": house, "at": Vector2(1.0, 1.0)})
	_check(house.roof.chimneys.size() == 1 and not _kind(house.roof, "chimney").is_empty(), "a chimney stands on the house")
	house.layout.height += WallLayout.COURSE * 2.0
	house.rebuild()
	_check(not _kind(house.roof, "chimney").is_empty() and _kind(house.roof, "chimney").reduce(func(m, s): return maxf(m, s.xform.origin.y), 0.0) > house.roof.base + house.roof.pitch, "raising the house carries its chimney up with the roof")
	fit.fit({"what": "tower_flag", "wall": tower})
	_check(tower.roof.flag and tower.roof.cloths.size() == 1, "a flag flies from the tower")
	history.undo()
	_check(not tower.roof.flag, "undo lowers it")

	await _play([{"op": "pave", "points": [[1.5, 12], [1.5, 4], [1.5, -4]], "radius": 0.6, "seconds": 0.3}])
	_check(fence.layout.live_arches.size() == 1 and _kind(fence.layout, "gate").size() == 9, "a path through the fence opens a wooden gate")
	history.undo()
	_check(fence.layout.live_arches.is_empty(), "undoing the path closes the gate")
	_done()


func _done() -> void:
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
