extends "res://../tests/support/suite.gd"

## Headless checks of windows, doors, lanterns, flags, chimneys and fences, as layouts and through the tools:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_fittings.gd

## A wall lays in under a hundred frames; seventy times that is a wall that never settles.
const SETTLE_FRAMES := 3600

var terrain: Terrain:
	get:
		return main.world.terrain


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
	_every_flag_triangle_faces_its_normal()
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
	_each_fitting_stands_alone()
	boot_main()
	_in_the_glade.call_deferred()


func _wall(length: float, height: float, windows: Array[Vector2], arches: Array[float] = []) -> WallLayout:
	return straight_wall(length, height, arches, 1, windows)


func _kind(w: Variant, kind: String) -> Array:
	var list: Array = w.stones if w is WallLayout else w.tiles
	return list.filter(func(s): return s.kind == kind)


## Coursed stones that reach into an opening's clear span.
func _intruders(w: WallLayout, o: Dictionary) -> Array:
	return w.stones.filter(func(s): return (s.kind == "block" or s.kind == "mortar") and s.y > o.sill + 0.05 and s.y < o.head - 0.05 and absf(s.s - o.s) < o.half + s.size.x * 0.5 - 0.02)


func _a_window_cuts_its_opening() -> void:
	var w := _wall(8.0, 2.7, [Vector2(4.0, 1.5)])
	check(w.apertures.size() == 1, "one window opens, got %d" % w.apertures.size())
	if w.apertures.is_empty():
		return
	var o := w.apertures[0]
	check(not o.door and o.lights == 1, "a window at 1.5 m is a single window")
	check(o.sill > 0.6 and o.head <= w.height - w.course_height() + 0.01, "sill %.2f and head %.2f leave a lintel course under the top" % [o.sill, o.head])
	check(is_equal_approx(fmod(o.sill + 1e-4, w.course_height()), 1e-4), "the sill sits on a course joint")
	check(_intruders(w, o).is_empty(), "no coursed stone fills the window")
	for k in ["glass", "frame", "lintel", "sill", "plaster"]:
		check(not _kind(w, k).is_empty(), "a window has a %s" % k)
	var lintel: Dictionary = _kind(w, "lintel")[0]
	check(lintel.size.x > o.half * 2.0 and lintel.y > o.head, "the lintel spans the opening above its head")
	var set_back := (_kind(w, "glass") + _kind(w, "frame")).all(func(p): return is_equal_approx(p.xform.origin.z, -WallLayout.THICKNESS * 0.12))
	check(set_back, "the casement's glass, frame and bars lie in one plane, none sunk behind the glass")
	var rect := func(p: Dictionary) -> Rect2: return Rect2(p.s - p.size.x * 0.5, p.y - p.size.y * 0.5, p.size.x, p.size.y)
	var deep := _kind(w, "frame").filter(func(p): return is_equal_approx(p.size.z, 0.08))
	var crossing := 0
	for i in deep.size():
		for j in i:
			if rect.call(deep[i]).intersection(rect.call(deep[j])).get_area() > 1e-6:
				crossing += 1
	check(deep.size() == 4 and crossing == 0, "the casement's stiles and rails meet without overlapping faces: %d of %d overlap" % [crossing, deep.size()])
	var surround := _kind(w, "plaster").all(func(p): return is_equal_approx(absf(p.xform.origin.z) - p.size.z * 0.5, WallLayout.THICKNESS * 0.5 - WallLayout.PLASTER_INSET))
	check(surround, "the plaster surround lies on a plastered face")


func _a_low_window_reaches_the_ground_as_a_door() -> void:
	var w := _wall(8.0, 2.7, [Vector2(4.0, 0.8)])
	check(w.apertures.size() == 1 and w.apertures[0].door, "a click low on the wall makes a door")
	if w.apertures.is_empty():
		return
	var o := w.apertures[0]
	check(o.sill == 0.0 and o.head >= 1.9, "a door runs from the ground to %.2f" % o.head)
	check(_intruders(w, o).is_empty(), "no coursed stone fills the door")
	check(_kind(w, "door").size() >= 3 and _kind(w, "sill").is_empty(), "a door is planks with no sill")
	check((_kind(w, "door") + _kind(w, "iron")).all(func(p): return is_equal_approx(p.xform.origin.z, -WallLayout.THICKNESS * 0.15)), "a door's planks and straps lie in one plane")


func _neighbours_fuse() -> void:
	var w := _wall(8.0, 2.7, [Vector2(3.6, 1.5), Vector2(4.4, 1.5)])
	check(w.apertures.size() == 1 and w.apertures[0].lights == 2, "two windows side by side fuse into one opening of two lights")
	check(_kind(w, "mullion").size() == 1, "a mullion stands between the lights")
	if not w.apertures.is_empty():
		check(absf(w.apertures[0].s - 4.0) < 0.01 and _intruders(w, w.apertures[0]).is_empty(), "the fused opening is clear around its middle")
	var doors := _wall(8.0, 2.7, [Vector2(3.6, 0.8), Vector2(4.4, 0.8)])
	check(doors.apertures.size() == 1 and doors.apertures[0].lights == 2 and doors.apertures[0].door, "two doors side by side make a double door")
	var apart := _wall(8.0, 2.7, [Vector2(2.4, 1.5), Vector2(5.6, 1.5)])
	check(apart.apertures.size() == 2, "windows far apart stay two, got %d" % apart.apertures.size())
	var mixed := _wall(8.0, 2.7, [Vector2(3.6, 1.5), Vector2(4.4, 0.8)])
	check(mixed.apertures.size() == 1, "a door does not fuse with a window, and they cannot share the span: %d openings" % mixed.apertures.size())


func _a_window_stands_over_a_door() -> void:
	var w := _wall(8.0, 4.2, [Vector2(4.0, 0.8), Vector2(4.0, 3.0)])
	check(w.apertures.size() == 2, "a window over a door, %d openings" % w.apertures.size())
	for o in w.apertures:
		check(_intruders(w, o).is_empty(), "the %s at %.2f is clear" % ["door" if o.door else "window", o.sill])


func _windows_keep_clear() -> void:
	check(_wall(8.0, 2.7, [Vector2(0.5, 1.5)]).apertures.is_empty(), "no window in a wall's end pier")
	check(_wall(8.0, 2.7, [Vector2(4.0, 1.5)], [4.0]).apertures.all(func(o): return o.style == WallLayout.Family.ARCHWAY), "no window in an arch")
	check(_wall(8.0, 2.7, [Vector2(4.0, 2.5)]).apertures.is_empty(), "no window above the top")
	check(_wall(8.0, 2.7, [Vector2(4.0, 2.25)]).apertures.is_empty(), "no window whose head reaches the top, leaving no course for its lintel")
	check(_wall(8.0, 1.2, [Vector2(4.0, 1.0)]).apertures.is_empty(), "a wall too low for a door takes none")
	var w := _wall(8.0, 2.7, [Vector2(4.0, 1.5)])
	w.height = 1.5
	w.build(Terrain.flat)
	check(w.apertures.is_empty(), "lowering the wall under a window closes it")
	w.height = 2.7
	w.build(Terrain.flat)
	check(w.apertures.size() == 1, "raising it again opens it")


func _house() -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(8, 0, 0), 5.0)
	w.closed = true
	w.cover = WallLayout.Cover.ROOF
	w.top = WallLayout.Top.CAP
	w.height = 2.4
	return w


func _windows_on_two_courses_stay_apart() -> void:
	var w := _wall(8.0, 4.2, [Vector2(4.0, 1.5), Vector2(4.0, 2.7)])
	check(w.apertures.size() == 2 and w.apertures.all(func(o): return o.lights == 1), "windows one above the other stay two single windows: %s" % [w.apertures])


func _the_lintel_course_is_cut() -> void:
	var w := _wall(8.0, 2.7, [Vector2(4.0, 1.5)])
	var o := w.apertures[0]
	var reach: float = o.half + WallLayout.LINTEL_EAR
	var under := w.stones.filter(func(s): return s.kind == "block" and s.y > o.head and s.y < o.head + w.course_height() and absf(s.s - o.s) < reach + s.size.x * 0.5 - 0.02)
	check(under.is_empty(), "the lintel's course is cut for it, %d coursed stones in its way" % under.size())
	var behind := w.stones.filter(func(s): return s.kind == "mortar" and s.y > o.head and s.y < o.head + w.course_height() and absf(s.s - o.s) < o.half)
	check(not behind.is_empty() and behind.all(func(s): return s.y - s.size.y * 0.5 >= o.head + WallLayout.JOINT - 0.001 and s.size.z < WallLayout.THICKNESS), "mortar runs on behind the lintel, inside it and off the head: %s" % [behind])


func _a_new_window_never_closes_another() -> void:
	var w := _wall(8.0, 2.7, [Vector2(4.0, 1.5)])
	check(w.opening_fits(Vector4(6.0, 1.5, 0, 1), w.openings), "a window clear of the first fits")
	check(w.opening_fits(Vector4(4.8, 1.5, 0, 1), w.openings), "a window beside the first fuses with it")
	check(not w.opening_fits(Vector4(3.4, 1.85, 0, 1), w.openings), "a window a course up, overlapping the first, would close it, so it does not fit")


func _windows_fuse_across_a_loop_seam() -> void:
	var w := WallLayout.new()
	w.points = WallLayout.circle(Vector3.ZERO, 2.5)
	w.closed = true
	w.height = 4.5
	w.build(Terrain.flat)
	w.openings = [Vector4(0.2, 2.0, 0, 1), Vector4(w.length() - 0.3, 2.0, 0, 1)]
	w.build(Terrain.flat)
	check(w.apertures.size() == 1 and w.apertures[0].lights == 2, "two windows either side of a tower's seam fuse: %s" % [w.apertures])
	if w.apertures.size() == 1:
		check(absf(w.offset(w.apertures[0].s, 0.0) + 0.05) < 0.01, "the fused opening is centred between them, across the seam: s=%.2f" % w.apertures[0].s)
		check(_intruders(w, w.apertures[0]).is_empty(), "the opening across the seam is clear")
	for start in [w.length() - 0.4, w.length() - 1.1, 0.3]:
		w.openings = [Vector4(start, 2.0, 0, 1), Vector4(start + 0.7, 2.0, 0, 1), Vector4(fposmod(start + 1.4, w.length()), 2.0, 0, 1)]
		w.build(Terrain.flat)
		check(w.apertures.size() == 1 and w.apertures[0].lights == 3, "three windows in a row fuse into one of three lights, starting at s=%.2f by the seam: %s" % [start, w.apertures])
		if w.apertures.size() == 1:
			check(absf(w.offset(w.apertures[0].s, start + 0.7)) < 0.01, "and it is centred on the middle one")
	var low := WallLayout.new()
	low.points = WallLayout.circle(Vector3.ZERO, 0.7)
	low.closed = true
	low.height = 4.5
	low.build(Terrain.flat)
	var spaced: Array[Vector4] = [Vector4(0.0, 1.5, 0, 1), Vector4(0.7, 1.5, 0, 1)]
	for k in 5:
		spaced.append(Vector4(1.3 + 0.6 * k, 3.3, 0, 1))
	low.openings = spaced
	low.build(Terrain.flat)
	check(low.apertures.any(func(o): return o.lights == 2 and o.sill < 1.5), "a pair on one course fuses whatever stands on the course above: %s" % [low.apertures])


func _flags_keep_their_colour() -> void:
	var w := _wall(8.0, 2.7, [])
	w.flags = [2.0, 6.0]
	w.build(Terrain.flat)
	var before := w.cloths.map(func(c): return c.color)
	w.lanterns = [Vector3(4.0, 1.5, 1.0)]
	w.openings = [Vector4(4.0, 0.8, 0, 1)]
	w.height = 3.0
	w.build(Terrain.flat)
	check(w.cloths.map(func(c): return c.color) == before, "a flag keeps its colour while its wall is raised, lit and given a door")


func _a_house_takes_windows() -> void:
	var w := _house()
	w.openings = [Vector4(2.0, 1.5, 0, 1), Vector4(4.0, 0.8, 0, 1), Vector4(8.0, 1.5, 0, 1)]
	w.build(Terrain.flat)
	check(w.apertures.size() == 2, "a house takes a window and a door on its long wall, not one on its corner: %d" % w.apertures.size())
	check(w.apertures.any(func(o): return o.door), "the house's door")


func _lanterns_hang_off_the_face() -> void:
	var w := _wall(8.0, 2.7, [Vector2(5.0, 1.5)])
	w.lanterns = [Vector3(2.5, 1.6, 1.0), Vector3(2.5, 1.6, -1.0), Vector3(5.0, 1.6, 1.0), Vector3(1.0, 0.3, 1.0)]
	w.build(Terrain.flat)
	check(w.flames.size() == 2, "lanterns hang on both faces, not in the window nor down at the ground: %d flames" % w.flames.size())
	var out := Vector3(0, 0, -1)
	for f in w.flames:
		var off := absf(f.origin.dot(out))
		check(off > WallLayout.THICKNESS * 0.5 + 0.15, "a flame hangs %.2f m out from the centre plane, clear of the face" % off)
		check(absf(f.origin.y - 1.6 - 0.055) < 0.2 and absf(f.origin.x - 2.5) < 0.01, "a flame at %s" % f.origin)
	if w.flames.size() == 2:
		check(signf(w.flames[0].origin.z) != signf(w.flames[1].origin.z), "the two lanterns are on opposite faces")
	check(_kind(w, "iron").size() >= 4, "lanterns hang from iron arms")
	var arched := _wall(8.0, 2.7, [], [4.0])
	arched.lanterns = [Vector3(4.6, 1.6, 1.0)]
	arched.build(Terrain.flat)
	check(arched.flames.is_empty(), "no lantern in an arch")


func _flags_fly_from_open_tops() -> void:
	var w := _wall(8.0, 2.7, [])
	w.flags = [4.0]
	w.build(Terrain.flat)
	check(w.cloths.size() == 1 and _kind(w, "pole").size() == 1, "a flag on the wall's top")
	if w.cloths.size() == 1:
		check(w.cloths[0].xform.origin.y > w.height + 1.0, "the cloth flies above the top, at %.2f" % w.cloths[0].xform.origin.y)
	var h := _house()
	h.flags = [2.0]
	h.build(Terrain.flat)
	check(h.cloths.is_empty(), "no flag on a roofed wall's top")


func _fence(length: float, arches: Array[float] = []) -> WallLayout:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(length, 0, 0)]
	w.fence = true
	w.height = WallLayout.FENCE_HEIGHT
	w.openings.append_array(arches.map(WallLayout.archway))
	w.openings.append(Vector4(length * 0.5, 1.5, 0, 1))
	w.build(Terrain.flat)
	return w


func _a_fence_is_posts_and_rails() -> void:
	var w := _fence(8.0)
	check(_kind(w, "post").size() == 6, "an 8 m fence has 6 posts, got %d" % _kind(w, "post").size())
	check(_kind(w, "rail").size() == 10, "two rails in each of 5 bays, got %d" % _kind(w, "rail").size())
	check(_kind(w, "block").is_empty() and _kind(w, "pier").is_empty() and _kind(w, "cap").is_empty(), "no stone in a fence")
	check(w.apertures.is_empty(), "no windows in a fence")
	for p in _kind(w, "post"):
		var top: float = p.xform.origin.y + p.size.y * 0.5
		check(top > WallLayout.FENCE_HEIGHT - 0.1 and top < WallLayout.FENCE_HEIGHT + 0.15, "a post's top at %.2f" % top)
	w.lanterns = [Vector3(3.0, 1.0, 1.0)]
	w.build(Terrain.flat)
	check(w.flames.size() == 1 and absf(w.flames[0].origin.x - 3.2) < 0.01, "a lantern on a fence stands on the nearest post, at %s" % (w.flames[0].origin if w.flames.size() else null))
	w.lanterns = [Vector3(3.0, 1.0, 1.0), Vector3(3.6, 1.0, 1.0)]
	w.build(Terrain.flat)
	check(w.flames.size() == 1, "two lanterns for one post light it once, %d flames" % w.flames.size())


func _a_gate_in_a_fence() -> void:
	var w := _fence(8.0, [4.0])
	check(w.archways() == [4.0], "a crossing opens a gate in the fence")
	var tall := _kind(w, "post").filter(func(p): return p.size.y > WallLayout.FENCE_HEIGHT + 0.5)
	check(tall.size() == 2, "two tall gate posts, got %d" % tall.size())
	check(_kind(w, "gate").size() == 9, "a bent wooden arch over the gate")
	check(_kind(w, "rail").all(func(r): return absf(r.s - 4.0) > WallLayout.ARCH_HALF), "no rail across the gate")
	check(_kind(w, "post").all(func(p): return absf(p.s - 4.0) > WallLayout.ARCH_HALF), "no post in the gate")
	check(_fence(8.0, [0.6]).archways().is_empty(), "no gate at a fence's very end")


func _fences_never_arch_over_plants() -> void:
	var stroke: Array[Vector3] = [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(8, 0, 0)]
	var plants := PackedVector3Array([Vector3(4, 0, 0.1)])
	var walls := WallPlan.new([], plants, 1).pieces(stroke, Terrain.flat)
	var plan := WallPlan.new([], plants, 1)
	plan.fence = true
	var fences := plan.pieces(stroke, Terrain.flat)
	check(walls.size() == 1 and walls[0].openings.size() == 1, "a wall arches over the plant")
	check(fences.size() == 1 and fences[0].fence and fences[0].openings.is_empty() and is_equal_approx(fences[0].height, WallLayout.FENCE_HEIGHT), "a fence goes by it, low and unarched")


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
	check(stack.size() > 8, "two chimneys of stacked stones, %d stones" % stack.size())
	var top: float = stack.reduce(func(m, s): return maxf(m, s.xform.origin.y), 0.0)
	check(top > r.base + r.pitch + 0.6, "a chimney clears the ridge: top %.2f over ridge %.2f" % [top, r.base + r.pitch])
	check(_kind(r, "pot").size() == 4, "two pots on each chimney")
	var spot := r.chimney_spot(Vector2(40.0, -40.0))
	check(absf(spot.x) <= r.ridge_length() * 0.5 - RoofLayout.STACK_WIDTH + 0.001 and absf(spot.y) <= r.half_span() - RoofLayout.STACK_WIDTH + 0.001, "a chimney placed off the roof is pulled back onto it: %s" % spot)
	var f := r.frame()
	var p: Vector3 = f.mid + f.along * 2.0 + f.across * 1.2 + Vector3.UP
	check(r.spot_of(p).distance_to(Vector2(2.0, 1.2)) < 0.001, "a point on the roof maps back to its chimney spot")


func _a_tower_flies_a_flag() -> void:
	var r := RoofLayout.new()
	r.kind = RoofLayout.Kind.CONE
	r.radius = 2.0
	r.base = 4.5
	r.pitch = 3.0
	r.build()
	check(r.cloths.is_empty() and _kind(r, "pole").is_empty(), "a bare cone has a finial and no flag")
	r.flag = true
	r.build()
	check(r.cloths.size() == 1 and _kind(r, "pole").size() == 1, "a flagged cone flies one flag")
	if r.cloths.size() == 1:
		check(r.cloths[0].xform.origin.y > r.base + r.pitch + 1.0, "the flag flies above the cone's tip")


func _ivy_keeps_out_of_windows() -> void:
	var w := _wall(10.0, 3.0, [Vector2(3.0, 0.8), Vector2(6.5, 1.6)])
	check(w.apertures.size() == 2, "a door and a window for the ivy to avoid")
	var leaves := IvyLayout.grow(w.snapshot())
	check(leaves.size() > 50, "ivy grows on the wall, %d leaves" % leaves.size())
	for l in leaves:
		for o in w.apertures:
			if absf(l.s - o.s) < o.half - 0.05 and l.y > o.sill + 0.05 and l.y < o.head - 0.05:
				check(false, "a leaf at s=%.2f y=%.2f grows over the %s" % [l.s, l.y, "door" if o.door else "window"])
				return


func _fittings_are_deterministic() -> void:
	var make := func() -> WallLayout:
		var w := _wall(9.0, 3.0, [Vector2(3.0, 0.8), Vector2(6.0, 1.6), Vector2(6.8, 1.6)])
		w.lanterns = [Vector3(4.5, 1.5, 1.0)]
		w.flags = [4.5]
		w.build(Terrain.flat)
		return w
	var a: WallLayout = make.call()
	var b: WallLayout = make.call()
	check(a.stones.size() == b.stones.size() and range(a.stones.size()).all(func(i): return a.stones[i].xform.is_equal_approx(b.stones[i].xform)), "the same wall lays the same fittings")


## Through the tools, in the glade.
func _in_the_glade() -> void:
	await process_frame
	# Fixture geometry exceeds capacity; test_budget covers the shared limit.
	main.world.bounded = false
	var walls: Array[Wall] = main.tool.walls
	var fit: FittingTool = main.fitting_tool
	var world: World = main.world
	var steps_now := func() -> int: return world.stacks.get(world.me(), {"undo": []}).undo.size()
	await play([
		{"op": "place", "x": 0, "z": 12},
		{"op": "wall", "points": [[-8, 0], [-3, 0], [2, 0]], "seconds": 0.3},
		{"op": "house", "at": [11.0, 0.0], "size": [6.0, 3.7], "seconds": 0.2},
	])
	world.submit({"op": "wall", "walls": [_tower(terrain.ground(-12, 8), 2.0)]})
	await play([
		{"op": "fence", "points": [[-6, 8], [0, 8], [5, 8]], "seconds": 0.3},
	])
	check(walls.size() == 4, "a wall, a house, a tower and a fence stand: %d" % walls.size())
	if walls.size() != 4:
		_done()
		return
	var wall := walls[0]
	var house := walls[1]
	var tower := walls[2]
	var fence := walls[3]
	check(fence.layout.fence and not wall.layout.fence, "the fence tool drew a fence")
	check(fence.layout.archways().is_empty() and wall.layout.archways().is_empty(), "fences and long walls over open ground stay solid")
	var middle_s := wall.layout.length() * 0.5
	var mid := wall.layout.frame_at(middle_s)
	var mid_n: Vector3 = mid.tangent.cross(Vector3.UP)
	var in_arch: Vector3 = mid.point + Vector3.UP * 1.0
	var arch_hand: Hand = main.rig.right
	arch_hand.tool = Hand.Tool.ARCH
	arch_hand.held_still = true
	arch_hand.global_transform = Transform3D(Basis.looking_at(-mid_n), in_arch + mid_n * 3.0)
	await _drawn(wall, "an arch held at the wall")
	var arch_steps: int = steps_now.call()
	check(wall.layout.archways().size() == 1 and Array(world.state.walls[wall.id].openings).is_empty() and steps_now.call() == arch_steps, "a hand holding the arch at a wall shows an archway cut there, and the garden has none yet")
	Buttons.injected["%s/trigger_click" % arch_hand.tracker] = true
	await process_frame
	Buttons.injected.erase("%s/trigger_click" % arch_hand.tracker)
	await _drawn(wall, "an arch pressed into the wall")
	check(world.state.walls[wall.id].openings.size() == 1 and wall.layout.archways().size() == 1 and steps_now.call() == arch_steps + 1, "a press cuts the archway, one undo step")
	check(fit.command(fit.aim(Hand.Tool.ARCH, in_arch + mid_n * 3.0, -mid_n)).data.keys() == ["openings"], "the arch changes the shared opening list, so the wall keeps its material")
	arch_hand.tool = Hand.Tool.WALLS
	arch_hand.held_still = false
	await _drawn(wall, "the arch put away")
	var crowding: Vector3 = wall.layout.frame_at(middle_s + 2.0).point + Vector3.UP * 1.0
	check(not _fit(fit, fit.aim(Hand.Tool.ARCH, crowding + mid_n * 3.0, -mid_n)) and steps_now.call() == arch_steps + 1, "an arch too near another is not cut and leaves no step")
	check(_fit(fit, fit.aim(Hand.Tool.ARCH, in_arch + mid_n * 3.0, -mid_n)) and Array(world.state.walls[wall.id].openings).is_empty() and wall.layout.archways().is_empty(), "a press on the arch fills it")
	_undo(world)
	check(world.state.walls[wall.id].openings.size() == 1 and wall.layout.archways().size() == 1, "undo opens it again")

	var face := wall.layout.frame_at(2.5)
	var normal: Vector3 = face.tangent.cross(Vector3.UP)
	var window_center := WallLayout.COURSE * 4.0 + WallLayout.WINDOW_TALL * 0.5
	var on_face: Vector3 = face.point + Vector3.UP * window_center
	var lantern_spot: Vector3 = wall.layout.frame_at(7.6).point + Vector3.UP * 1.5
	var t := fit.aim(Hand.Tool.DECORATIONS, lantern_spot + normal * 3.0, -normal)
	check(t.get("what") == "lantern" and t.wall == wall and t.side == 1.0 and absf(t.s - 7.6) < 0.3 and absf(t.y - 1.5) < 0.15, "decorations pointed at a wall's face hang a lantern there: %s" % t)
	check(fit.aim(Hand.Tool.DECORATIONS, on_face - normal * 3.0, normal).get("side") == -1.0, "from the other side, on the other face")
	var near_top: Vector3 = face.point + Vector3.UP * (wall.layout.height - 0.1)
	check(fit.aim(Hand.Tool.DECORATIONS, near_top + normal * 3.0, -normal).get("what") == "flag", "at a wall's top they fly a flag")
	var w_aim := fit.aim(Hand.Tool.WINDOWS, on_face + normal * 3.0, -normal)
	check(w_aim.get("what") == "opening", "windows pointed at a wall open a window")
	var down := (Vector3.DOWN + normal * 0.3).normalized()
	var ground_aim := fit.aim(Hand.Tool.WINDOWS, on_face + normal * 3.0, down)
	var astray := fit.ghost_of(ground_aim, on_face + normal * 3.0, down, terrain.raycast(on_face + normal * 3.0, down))
	check(ground_aim.is_empty() and not astray.fits, "aimed at the ground, a ghost hangs there unplaced")
	check(not _fit(fit, ground_aim), "a press at the ground places nothing and says so")
	var ridge: Vector3 = house.roof.frame().mid + Vector3.UP * (house.roof.pitch * 0.5)
	check(fit.aim(Hand.Tool.DECORATIONS, ridge + house.roof.frame().across * 1.2 + Vector3.UP * 6.0, Vector3.DOWN).get("what") == "chimney", "on a house's roof, a chimney")
	check(fit.aim(Hand.Tool.DECORATIONS, tower.roof.frame().mid + Vector3.UP * 12.0, Vector3.DOWN).get("what") == "tower_flag", "on a tower's roof, a flag")
	check(fit.aim(Hand.Tool.WINDOWS, ridge + Vector3.UP * 6.0, Vector3.DOWN).get("what") == "dormer" and fit.aim(Hand.Tool.WINDOWS, tower.roof.frame().mid + Vector3.UP * 12.0, Vector3.DOWN).is_empty(), "windows on a house's roof open a dormer, on a tower's nothing")
	var corners := house.layout.points
	var middle: Vector3 = corners.reduce(func(m, c): return m + c / corners.size(), Vector3.ZERO)
	var missed := []
	for k in 41:
		var side := house.layout.frame_at(corners[0].distance_to(corners[1]) * (0.1 + 0.02 * k))
		var out: Vector3 = side.tangent.cross(Vector3.UP)
		out *= signf((side.point - middle).dot(out))
		for slant in [-3.0, 3.0]:
			var spot: Vector3 = side.point + Vector3.UP * (1.2 + 0.1 * (k % 6))
			var from: Vector3 = spot + out * 3.8 + side.tangent * slant - Vector3.UP * 0.1
			var into := fit.aim(Hand.Tool.WINDOWS, from, (spot - from).normalized())
			if Vector2(into.point.x - spot.x, into.point.z - spot.z).length() > 0.5:
				missed.append([spot, into.point])
	check(missed.is_empty(), "a hand aimed slantwise at a house's side opens a window in that side, not one behind it: %s" % [missed])
	var post := fence.layout.frame_at(3.0)
	var post_n: Vector3 = post.tangent.cross(Vector3.UP)
	check(fit.aim(Hand.Tool.DECORATIONS, post.point + Vector3.UP * 0.8 + post_n * 3.0, -post_n).get("what") == "lantern", "on a fence, a lantern")
	check(fit.aim(Hand.Tool.WINDOWS, post.point + Vector3.UP * 0.8 + post_n * 3.0, -post_n).is_empty(), "no windows in a fence")
	check(fit.aim(Hand.Tool.ARCH, post.point + Vector3.UP * 0.8 + post_n * 3.0, -post_n).is_empty() and fit.aim(Hand.Tool.ARCH, ridge + Vector3.UP * 6.0, Vector3.DOWN).is_empty(), "the arch cuts nothing in a fence or a roof")
	check(main.tool.pick_building(post.point + Vector3.UP * 0.8 + post_n * 3.0, -post_n).get("wall") == fence, "a ray through the fence and on into the wall behind picks the fence")
	_fit(fit, fit.aim(Hand.Tool.DECORATIONS, post.point + Vector3.UP * 0.8 + post_n * 3.0, -post_n))
	check(fence.layout.flames.size() == 1, "a press hangs a lantern on the fence")
	var beside: Vector3 = fence.layout.frame_at(3.7).point + Vector3.UP * 0.8
	_fit(fit, fit.aim(Hand.Tool.DECORATIONS, beside + post_n * 3.0, -post_n))
	check(fence.layout.flames.is_empty() and fence.layout.lanterns.is_empty(), "a press farther along the same post takes it away")

	var steps: int = steps_now.call()
	var hand: Hand = main.rig.right
	hand.tool = Hand.Tool.WINDOWS
	hand.held_still = true
	hand.global_transform = Transform3D(Basis.looking_at(-normal), on_face + normal * 3.0)
	var shown := await _drawn(wall, "windows held at the wall")
	check(wall.layout.apertures.size() == 2 and world.state.walls[wall.id].openings.size() == 1 and steps_now.call() == steps, "a hand holding windows at a wall shows it opened, and the garden has no window yet")
	hand.global_transform = Transform3D(Basis.looking_at(-normal), on_face + Vector3.UP * 0.05 + normal * 3.0)
	check(await _drawn(wall, "windows moved within the opening") == shown, "a hand moved within the opening it shows keeps the wall it showed")
	Buttons.injected["%s/trigger_click" % hand.tracker] = true
	await process_frame
	Buttons.injected.erase("%s/trigger_click" % hand.tracker)
	check(wall.layout.apertures.size() == 2 and steps_now.call() == steps + 1, "a press opens a window, one undo step")
	check(await _drawn(wall, "a window pressed into the wall") == shown, "the opened wall is drawn as it was shown before the press, stone for stone and leaf for leaf")
	hand.global_transform = Transform3D(Basis.looking_at(-normal), on_face + face.tangent * 0.8 + normal * 3.0)
	await _drawn(wall, "windows aimed beside the window")
	check(wall.layout.apertures.size() == 2 and wall.layout.apertures[0].lights == 2 and steps_now.call() == steps + 1, "aimed beside it, the wall shows the two fused")
	hand.tool = Hand.Tool.WALLS
	hand.held_still = false
	check(await _drawn(wall, "windows put away") == shown and wall.layout.apertures[0].lights == 1, "put away, the wall is drawn as the garden has it again, as it was shown before the press")
	_fit(fit, fit.aim(Hand.Tool.WINDOWS, on_face + face.tangent * 0.8 + normal * 3.0, -normal))
	check(wall.layout.apertures.size() == 2 and wall.layout.apertures[0].lights == 2, "a press beside it fuses a second light into it")
	_fit(fit, fit.aim(Hand.Tool.WINDOWS, on_face + normal * 3.0, -normal))
	check(wall.layout.openings.size() == 2 and wall.layout.apertures.size() == 2 and wall.layout.apertures[0].lights == 1, "a press on a light closes that light")
	var on_arch := wall.layout.point_at(wall.layout.archways()[0]) + Vector3.UP * 1.0
	var before: int = steps_now.call()
	_fit(fit, fit.aim(Hand.Tool.WINDOWS, on_arch + normal * 3.0, -normal))
	check(steps_now.call() == before + 1 and wall.layout.openings.size() == 1 and wall.layout.archways().is_empty(), "the same opening tool removes an archway")
	_undo(world)
	check(wall.layout.archways().size() == 1, "undo restores the archway through the opening list")
	_undo(world)
	check(wall.layout.apertures[0].lights == 2, "undo brings the closed light back")
	_undo(world)
	_undo(world)
	check(wall.layout.apertures.size() == 1 and wall.layout.openings.size() == 1 and wall.layout.archways().size() == 1, "undo closes the windows")
	_redo(world)
	check(wall.layout.apertures.size() == 2, "redo opens one again")

	_fit(fit, t)
	check(wall.layout.flames.size() == 1, "a press hangs the lantern")
	fit.light_lanterns()
	fit.lamps.finish()
	var flame := wall.layout.flames[0].origin
	check(fit.lamps.at(flame.x, flame.z, 0) > 0.3, "the lantern lights the ground under it: %.2f" % fit.lamps.at(flame.x, flame.z, 0))
	check(fit.lamps.at(flame.x + 12.0, flame.z, 0) == 0.0, "and not beyond its reach")
	var high := Lamps.shine(PackedVector3Array([Vector3(0.5, 6.0, 0.5)]), Bounce.grounds(terrain.read(Terrain.ALL)))
	var under := Bounce.column(0.5, 0.5)
	var floor_light := high[0][(under.y * Bounce.CELLS + under.x) * 4] / 255.0 * Lamps.ENCODE
	check(floor_light > 0.05, "a lantern hung 6 m up still lights the floor: %.2f" % floor_light)
	_fit(fit, t)
	check(wall.layout.flames.is_empty(), "a second press takes the lantern away")
	_undo(world)
	check(wall.layout.flames.size() == 1, "undo hangs it again")

	_chimney_ghost_is_the_chimney(fit, world, house)
	await play([{"op": "house", "at": [30.0, -30.0], "size": [6.0, 4.0], "turn": 30, "seconds": 0.2}])
	_chimney_ghost_is_the_chimney(fit, world, walls[-1])
	_fit(fit, {"what": "chimney", "wall": house, "at": Vector2(1.0, 1.0)})
	check(house.roof.chimneys.size() == 1 and not _kind(house.roof, "chimney").is_empty(), "a chimney stands on the house")
	house.layout.height += WallLayout.COURSE * 2.0
	house.rebuild()
	house.lay_now()
	check(not _kind(house.roof, "chimney").is_empty() and _kind(house.roof, "chimney").reduce(func(m, s): return maxf(m, s.xform.origin.y), 0.0) > house.roof.base + house.roof.pitch, "raising the house carries its chimney up with the roof")
	_fit(fit, {"what": "tower_flag", "wall": tower})
	check(tower.roof.flag and tower.roof.cloths.size() == 1, "a flag flies from the tower")
	_undo(world)
	check(not tower.roof.flag, "undo lowers it")

	await play([{"op": "pave", "points": [[1.5, 12], [1.5, 4], [1.5, -4]], "radius": 0.6, "seconds": 0.3}])
	check(fence.layout.archways().size() == 1 and _kind(fence.layout, "gate").size() == 9, "a path through the fence opens a wooden gate")
	var gate: Vector3 = fence.layout.point_at(fence.layout.archways()[0]) + Vector3.UP * 0.8
	check(not _fit(fit, {"what": "opening", "style": WallLayout.Family.ARCHWAY, "y": 0.0, "wall": fence, "s": fence.layout.archways()[0], "point": gate}) and fence.layout.archways().size() == 1, "the arch leaves a path's gate to the path")
	_undo(world)
	check(fence.layout.archways().is_empty(), "undoing the path closes the gate")
	var cut := PackedVector4Array(world.state.walls[wall.id].openings)
	world.restore(world.snapshot())
	_lay_walls()
	var reloaded: Wall = main.tool.find(wall.id)
	check(cut.size() == 2 and PackedVector4Array(world.state.walls[wall.id].openings) == cut and reloaded.layout.archways().size() == 1, "a save keeps the cut arch")
	await _a_ruin_flies_no_flag(fit, world)
	_shared_opening_cap(reloaded)
	_done()


func _a_ruin_flies_no_flag(fit: FittingTool, world: World) -> void:
	var stood: Array = world.state.walls.keys()
	world.submit({"op": "wall", "walls": [wall_data({"points": PackedVector3Array([terrain.ground(-14, -30), terrain.ground(-2, -30)]), "seed": 3, "ruins": PackedVector2Array([Vector2(3.0, 5.0)])})]})
	for f in 3:
		await process_frame
	var ruin: Wall = main.tool.walls.filter(func(w: Wall) -> bool: return not w.id in stood)[0]
	_lay_walls()
	check(ruin.layout.broken(4.0) and not ruin.layout.broken(9.5, 0.3), "the ruined wall stands, broken at 4 m and whole at 9.5 m")
	check(not _fit(fit, {"what": "flag", "wall": ruin, "s": 4.0}) and Array(world.state.walls[ruin.id].flags).is_empty(), "a flag pressed onto a ruined stretch is refused, not stored unflown")
	check(_fit(fit, {"what": "flag", "wall": ruin, "s": 9.5}) and Array(world.state.walls[ruin.id].flags).any(func(e): return is_equal_approx(e, 9.5)) and ruin.layout.cloths.size() == 1, "beside the ruin a flag flies as ever")


func _shared_opening_cap(w: Wall) -> void:
	var fit: FittingTool = main.fitting_tool
	var world: World = main.world
	var before: Dictionary = world.state.walls[w.id].duplicate(true)
	var full := PackedVector4Array()
	for i in Commands.MAX_FITTINGS:
		full.append(Vector4(2.0 + i * 3.0, float(i % 2) * 1.5, i % 2, 1.0 + i % 3))
	world.state.walls[w.id].openings = full
	for style in WallLayout.Family.values():
		check(not fit._change(w, false, "openings", Vector4(1, 0, style, 1), -1, true).ok, "the same cap refuses every door style")
		check(fit._change(w, false, "openings", Vector4(1, 0, style, 1), 0, true).ok, "the cap still allows removal")
	var data := before.duplicate(true)
	data.openings = full
	check(Commands._wall(data) != null, "the command accepts the shared cap")
	data.openings.append(WallLayout.archway(200))
	check(Commands._wall(data) == null, "the command rejects one more opening")
	data.openings = PackedVector4Array([Vector4(2, 0, 0.5, 1)])
	check(Commands._wall(data) == null, "the command rejects an unknown door style")
	data.openings = PackedVector4Array([WallLayout.archway(2.0, WallLayout.MIN_SIZE)])
	check(Commands._wall(data) != null, "the command accepts a pet door")
	data.openings = PackedVector4Array([WallLayout.archway(2.0, WallLayout.MIN_SIZE - 0.01)])
	check(Commands._wall(data) == null, "the command rejects an opening smaller than a pet door")
	data.openings = PackedVector3Array([Vector3(2, 0, 1)])
	check(Commands._wall(data) == null, "the command rejects openings without their size")
	data.fence = true
	data.flags = PackedFloat32Array()
	data.clutter = PackedVector4Array()
	data.openings = PackedVector4Array([WallLayout.archway(2.0)])
	var gate := Commands._wall(data) != null
	data.openings = PackedVector4Array([WallLayout.archway(2.0, 2.0)])
	check(gate and Commands._wall(data) == null, "a fence's gates are a path's, at a doorway's size")
	world.state.walls[w.id] = before


## A tower as a garden built before keeps one: no tool draws one any more.
static func _tower(center: Vector3, radius: float) -> Dictionary:
	return {
		"points": PackedVector3Array(WallLayout.circle(center, radius)), "height": 4.5, "seed": 5,
		"closed": true, "top": WallLayout.Top.CAP, "fence": false, "openings": PackedVector4Array(), "lanterns": PackedVector3Array(),
		"flags": PackedFloat32Array(), "ruins": PackedVector2Array(), "finish": WallLayout.Finish.BARE, "wear": 0.0, "foundation": 0, "planks": false, "rise": 0.0, "gable_end": 0, "on": PackedInt32Array(), "paint": Palette.plain(),
		"roof": {"kind": RoofLayout.Kind.CONE, "center": center, "radius": radius, "pitch": 3.2, "curve": 0.0, "seed": 5, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "hatches": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false},
	}


## A press of the fitting tool, and the walls it changed laid, for a test reading them at once.
func _fit(fit: FittingTool, target: Dictionary) -> bool:
	var placed := fit.fit(target)
	_lay_walls()
	return placed


## A chimney's ghost low on `house`'s slope against the chimney a press there lays: as tall, its pots where the real
## pots stand.
func _chimney_ghost_is_the_chimney(fit: FittingTool, world: World, house: Wall) -> void:
	house.lay_now()
	var r := house.roof
	var low: Vector3 = house.transform * (r.frame().mid + r.frame().across * r.half_span() * 0.7) + Vector3.UP * 8.0
	var aimed := fit.aim(Hand.Tool.DECORATIONS, low, Vector3.DOWN)
	check(aimed.get("what") == "chimney", "aimed at a slope, a chimney: %s" % aimed.get("what"))
	if aimed.get("what") != "chimney":
		return
	var ghost := fit.ghost_of(aimed, low, Vector3.DOWN, null)
	fit._show_ghost(0, ghost, 1.0)
	check(fit._ghosts[0].chimney.get_meta(&"shape", []) == ghost.get("shape"), "the chimney ghost shown is the one laid for its spot")
	var box := AABB(Vector3.ONE * -0.5, Vector3.ONE)
	var shown: Array = ToolModels.fitting_parts("chimney", r, ghost.spot, ghost.index).parts.map(func(p: Dictionary) -> Dictionary: return {"kind": p.kind, "box": ghost.xform * p.xform * box})
	_fit(fit, aimed)
	house.lay_now()
	var laid: Array = r.tiles.filter(func(t): return t.kind in ["chimney", "pot"]).map(func(t: Dictionary) -> Dictionary: return {"kind": t.kind, "box": house.transform * t.xform * box})
	var top := func(parts: Array) -> float: return parts.reduce(func(m: float, p: Dictionary) -> float: return maxf(m, p.box.end.y), -INF)
	check(absf(top.call(shown) - top.call(laid)) < 0.026, "a chimney's ghost low on the slope stands as tall as the chimney it places: %.2f for %.2f" % [top.call(shown), top.call(laid)])
	var pots := func(parts: Array) -> Array: return parts.filter(func(p): return p.kind == "pot").map(func(p): return p.box.get_center())
	var near: bool = pots.call(laid).all(func(c: Vector3) -> bool: return pots.call(shown).any(func(g: Vector3) -> bool: return Vector2(g.x - c.x, g.z - c.z).length() < 0.03))
	check(pots.call(shown).size() == 2 and near, "the ghost's pots stand where the chimney's do on a house turned %.0f degrees" % rad_to_deg(house.roof.frame().along.signed_angle_to(Vector3.RIGHT, Vector3.UP)))
	_undo(world)


func _undo(world: World) -> void:
	world.undo()
	_lay_walls()


func _redo(world: World) -> void:
	world.redo()
	_lay_walls()


## Every buffer `w` draws once its stones and ivy are laid. A wall that lays on and on, as one a hand's preview keeps
## reshaping does, fails `step` and ends the run where it stalled.
func _drawn(w: Wall, step: String) -> Array:
	for f in 3:
		await process_frame
	for f in SETTLE_FRAMES:
		if not w.laying() and w._ivy_task < 0:
			return w._parts.duplicate(true)
		await process_frame
	check(false, "%s: the wall still lays %d frames on" % [step, SETTLE_FRAMES])
	_done()
	while true:
		await process_frame
	return []


func _lay_walls() -> void:
	for w: Wall in main.tool.walls:
		w.lay_now()


func _each_fitting_stands_alone() -> void:
	for what in ToolModels.FITTING_PARTS:
		var m := ToolModels.fitting(what)
		var laid: int = m.find_children("*", "MultiMeshInstance3D", true, false).reduce(func(n, mmi): return n + mmi.multimesh.instance_count, 0)
		check(laid > 0, "the %s's model has its parts" % what)
		m.free()


func _done() -> void:
	finish()


func _every_flag_triangle_faces_its_normal() -> void:
	var a := Fittings._flag_mesh().surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var against := 0
	for t in range(0, v.size(), 3):
		var front := (v[t + 2] - v[t]).cross(v[t + 1] - v[t])
		for k in 3:
			if front.dot(n[t + k]) <= 0.0:
				against += 1
	check(v.size() == 48 and against == 0, "every flag triangle winds as its normal faces, so none is drawn as its back face")
