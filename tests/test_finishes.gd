extends "res://../tests/support/suite.gd"

## Headless checks of wall finishes: worn plaster, timber framing on an open wall, planks across and upright on walls
## and houses, and planked fences, laid around windows, doors and arches; through the style tool's face wheel and the
## garden's command; charged by the budget; and played in demo/finishes.json and the stress scene's finishes/* phases:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_finishes.gd

const FACE_KINDS := ["block", "plaster", "mortar", "board", "timber"]

var world: World


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	main.world.bounded = false
	world = main.world
	_finishes_clear_every_opening()
	_plaster_wears_back_to_the_stones()
	_planks_lie_across_or_upright()
	_no_slivers_at_corners()
	_timber_walls_are_framed_and_railed()
	_ruined_timber_walls_break()
	_fences_take_planks()
	_commands_check_finishes()
	_budget_charges_each_finish()
	_the_face_wheel_turns_every_finish()
	await _demo()
	await _stress_village()
	finish()


## A house, or a bent open wall, with a window, a door and an arch, faced in `finish` worn by `wear`.
static func _built(finish: WallLayout.Finish, wear: float, closed: bool, seed := 3) -> WallLayout:
	var w := WallLayout.new()
	if closed:
		w.points.assign(WallLayout.rectangle(Vector3.ZERO, Vector3(8, 0, 0), 5.0))
		w.closed = true
		w.cover = WallLayout.Cover.ROOF
		w.top = WallLayout.Top.CAP
	else:
		w.points.assign([Vector3.ZERO, Vector3(5, 0, 1.5), Vector3(12, 0, 0)] as Array[Vector3])
	w.height = 4.2
	w.seed = seed
	w.finish = finish
	w.wear = wear
	w.openings.assign([Vector4(1.6, 1.6, WallLayout.Family.COTTAGE, 1), Vector4(4.2, 0.0, WallLayout.Family.COTTAGE, 1), WallLayout.archway(17.0 if closed else 9.0)])
	w.build(Terrain.flat)
	return w


## How far into the opening `o` a face piece reaches, along the wall and up, after `margin`: positive both ways where it
## stands in it, judged on its box's corners as laid, so a brace or an arch's wedge counts as it is turned. An arch's
## opening is its outline at the box's middle height.
static func _into(w: WallLayout, piece: Dictionary, o: Dictionary, margin: float) -> Vector2:
	var x: Transform3D = piece.xform
	var f := w.frame_at(piece.s)
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for corner in WallLayout.BOX:
		var p: Vector3 = x * corner
		var at := Vector2(w.offset(piece.s, o.s) + (p - x.origin).dot(f.tangent), p.y - f.point.y)
		lo = lo.min(at)
		hi = hi.max(at)
	var half: float = w.opening((lo.y + hi.y) * 0.5, false, o.size) if o.style == WallLayout.Family.ARCHWAY else o.half
	var top: float = w.spring(o.size) + w.arch_rise(0.0, o.size) if o.style == WallLayout.Family.ARCHWAY else o.head
	return Vector2(minf(hi.x, half) - maxf(lo.x, -half), minf(hi.y, top) - maxf(lo.y, o.sill)) - Vector2.ONE * margin


## No piece of any face (stone, plaster, mortar, plank or timber) stands in a window, a door or an arch, on a house or a
## bent open wall, in every finish the face wheel offers; each finish lays what it is, and the same inputs lay the same.
func _finishes_clear_every_opening() -> void:
	for closed in [false, true]:
		for face: Vector2 in PaletteTool.FACES:
			var finish := int(face.x) as WallLayout.Finish
			var w := _built(finish, face.y, closed)
			var name := "%s %s worn %.2f" % ["house" if closed else "wall", WallLayout.Finish.keys()[finish], face.y]
			check(w.apertures.size() == 3, "%s: its window, door and arch all fit: %d" % [name, w.apertures.size()])
			var kinds := {}
			for piece in w.stones:
				kinds[piece.kind] = true
				if not piece.kind in FACE_KINDS or piece.y < 0.0:
					continue
				for o in w.apertures:
					var into := _into(w, piece, o, 0.03)
					if into.x > 0.0 and into.y > 0.0:
						check(false, "%s: a %s at %.2f, %.2f stands %.2f into the opening at %.2f" % [name, piece.kind, piece.s, piece.y, minf(into.x, into.y), o.s])
						break
			match finish:
				WallLayout.Finish.BARE:
					check(kinds.has("block") and not kinds.has("board") and not kinds.has("timber"), "%s: laid in stone" % name)
				WallLayout.Finish.PLASTER:
					check(kinds.has("plaster") and not kinds.has("timber") and not kinds.has("board"), "%s: laid in plaster" % name)
				WallLayout.Finish.TIMBER:
					check(kinds.has("plaster") and kinds.has("timber"), "%s: plaster framed in timber" % name)
				_:
					check(kinds.has("board") and not kinds.has("plaster"), "%s: laid in planks" % name)
			var again := w.inputs()
			again.build(Terrain.flat)
			check(again.stones == w.stones, "%s: the same inputs lay the same pieces" % name)


## Worn plaster shows the stones behind it over about as much of the face above its foot as it is worn, more of it low
## on the wall than high, in patches that carry on up from course to course; the stones stand back behind the plaster's
## face, and mortar, not plaster, lies behind them.
func _plaster_wears_back_to_the_stones() -> void:
	var shares: Array[float] = []
	for wear in [0.0, 0.25, 0.5, 0.75]:
		var w := WallLayout.new()
		w.points.assign([Vector3.ZERO, Vector3(16, 0, 0)] as Array[Vector3])
		w.height = 4.5
		w.seed = 11
		w.finish = WallLayout.Finish.PLASTER
		w.wear = wear
		w.build(Terrain.flat)
		var c := w.course_height()
		var above := func(st: Dictionary) -> bool: return st.y > c
		var stones := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "block" and above.call(st))
		var plaster := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "plaster" and above.call(st))
		var mortar := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "mortar" and above.call(st))
		var bare := 0.0
		for m in mortar:
			bare += m.size.x * m.size.y
		var face := w.length() * (w.height - c)
		shares.append(bare / face)
		var name := "plaster worn %.2f" % wear
		if wear == 0.0:
			check(stones.is_empty() and mortar.is_empty(), "%s: no stone shows above the foot" % name)
			continue
		check(absf(bare / face - wear) < 0.12, "%s: worn back over %.2f of the face" % [name, bare / face])
		var deepest := 0.0
		for st in stones:
			deepest = maxf(deepest, st.size.z * 0.5)
		check(deepest < WallLayout.THICKNESS * 0.5 - WallLayout.PLASTER_INSET - 0.02, "%s: the stones stand back behind the plaster's face, %.3f from the middle" % [name, deepest])
		var low := 0.0
		var high := 0.0
		for m in mortar:
			if m.y < w.height * 0.5:
				low += m.size.x * m.size.y
			else:
				high += m.size.x * m.size.y
		check(low > high, "%s: worn more low on the wall than high: %.1f and %.1f m²" % [name, low, high])
		for st in stones:
			if not mortar.any(func(m: Dictionary) -> bool: return absf(m.s - st.s) < m.size.x * 0.5 + st.size.x * 0.5 + WallLayout.WORN_TUCK and absf(m.y - st.y) < m.size.y * 0.5):
				check(false, "%s: a stone at %.2f, %.2f shows with no worn patch behind it" % [name, st.s, st.y])
				break
		var kept := 0.0
		var worn := 0.0
		var y := c
		while y + c < w.height:
			var here := w._worn(y)
			var up := w._worn(y + c)
			for a in here:
				worn += a.y - a.x
				for b in up:
					kept += maxf(0.0, minf(a.y, b.y) - maxf(a.x, b.x))
			y += c
		check(kept / worn > wear + 0.1, "%s: worn patches carry on up the courses, %.2f of each course's under the next's" % [name, kept / worn])
	for i in range(1, shares.size()):
		check(shares[i] > shares[i - 1], "more wear shows more stone: %s" % [shares])
	var raised := _built(WallLayout.Finish.PLASTER, 0.75, true)
	raised.foundation = WallLayout.Foundation.PLASTER
	raised.rise = 1.2
	raised.build(Terrain.flat)
	check(not raised.stones.any(func(st: Dictionary) -> bool: return st.kind == "block" and st.y < 0.0), "a plaster plinth under worn plaster stays whole")


## Planks laid across lie level, longer than tall, staggered from row to row; laid upright they stand taller than wide,
## side by side. Either way they cover the face above the foot but for the openings, over a stone foot course, and the
## openings' heads and sills are oak.
func _planks_lie_across_or_upright() -> void:
	for finish in [WallLayout.Finish.BOARDS_ACROSS, WallLayout.Finish.BOARDS_UPRIGHT]:
		for closed in [false, true]:
			var w := _built(finish, 0.0, closed)
			var name := "%s %s" % ["house" if closed else "wall", WallLayout.Finish.keys()[finish]]
			var c := w.course_height()
			var boards := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "board" and st.y < w.height)
			check(not boards.is_empty(), "%s: planks are laid" % name)
			var across := boards.all(func(b: Dictionary) -> bool: return b.size.y < WallLayout.BOARD.x) and boards.filter(func(b: Dictionary) -> bool: return b.size.x > b.size.y).size() > boards.size() * 0.9
			var upright := boards.all(func(b: Dictionary) -> bool: return b.size.y > b.size.x and b.size.x <= WallLayout.BOARD.x)
			check(across if finish == WallLayout.Finish.BOARDS_ACROSS else upright, "%s: every plank lies %s" % [name, "across" if finish == WallLayout.Finish.BOARDS_ACROSS else "upright"])
			check(boards.all(func(b: Dictionary) -> bool: return b.y - b.size.y * 0.5 > c - 0.01), "%s: the planks start over the stone foot course" % name)
			check(boards.all(func(b: Dictionary) -> bool: return b.size.x > WallLayout.BOARD.y), "%s: no plank is a sliver" % name)
			check(w.stones.any(func(st: Dictionary) -> bool: return st.kind == "block" and st.y < c), "%s: the foot course stays stone" % name)
			check(not w.stones.any(func(st: Dictionary) -> bool: return st.kind == "block" and st.y > c and st.y < w.height), "%s: no stone course above the foot" % name)
			check(not w.stones.any(func(st: Dictionary) -> bool: return st.kind in ["lintel", "sill"]), "%s: no stone head or sill" % name)
			check(w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "beam").size() >= 3, "%s: oak heads and sills" % name)
			var area := 0.0
			for b in boards:
				area += (b.size.x + WallLayout.BOARD.y) * (b.size.y + (WallLayout.BOARD.y if finish == WallLayout.Finish.BOARDS_ACROSS else 0.0))
			var holes := 0.0
			for o in w.apertures:
				holes += o.half * 2.0 * (o.head - maxf(o.sill, c))
			var face := w.length() * (w.height - c) - holes
			check(area > face * 0.85 and area < face * 1.08, "%s: the planks cover the face but the openings: %.1f of %.1f m²" % [name, area, face])
			if closed:
				var gabled := w.inputs()
				gabled.gable_end = WallLayout.GableEnd.STEPS
				var r := RoofLayout.new()
				r.corners = gabled.points
				r.pitch = 2.0
				gabled.gable = r
				gabled.build(Terrain.flat)
				var up := gabled.stones.filter(func(st: Dictionary) -> bool: return st.y > gabled.height + WallLayout.CAP and st.kind in ["board", "block", "plaster", "step"])
				check(not up.is_empty() and up.all(func(st: Dictionary) -> bool: return st.kind == "board"), "%s: its gable ends are boarded, whatever they were turned to" % name)
			if finish == WallLayout.Finish.BOARDS_ACROSS:
				var joints := {}
				for b in boards:
					joints[snappedf(b.s - b.size.x * 0.5, 0.05)] = joints.get(snappedf(b.s - b.size.x * 0.5, 0.05), 0) + 1
				check(joints.values().max() < boards.size() / 4, "%s: joints are staggered, at most %d at one place" % [name, joints.values().max()])


## Planked across, houses of many sizes lay no sliver of a plank at a corner, wherever their corners fall a rounding
## either side of a sample.
func _no_slivers_at_corners() -> void:
	var slivers := 0
	for k in 20:
		var w := WallLayout.new()
		w.points.assign(WallLayout.rectangle(Vector3(k * 0.37, 0, k * 0.11), Vector3(k * 0.37 + 5.0 + k * 0.13, 0, k * 0.11 + k * 0.07), 3.0 + k * 0.09))
		w.closed = true
		w.cover = WallLayout.Cover.ROOF
		w.height = 3.0
		w.seed = k
		w.finish = WallLayout.Finish.BOARDS_ACROSS
		w.build(Terrain.flat)
		slivers += w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "board" and st.size.x < 0.05).size()
	check(slivers == 0, "no plank laid across twenty houses is a sliver: %d are" % slivers)


## An open wall framed in timber carries its frame on both faces, posts at each end and rails broken at every post,
## each member on the wall's line where it curves; its walk is boarded in WALK_LANES runs under a wooden railing, and a
## player stands on the boards. A house's frame stays on its outer face.
func _timber_walls_are_framed_and_railed() -> void:
	var w := WallLayout.new()
	var arc: Array[Vector3] = []
	for i in 9:
		arc.append(Vector3(cos(i / 8.0 * PI) * 6.0, 0.0, -sin(i / 8.0 * PI) * 6.0))
	w.points.assign(arc)
	w.height = 3.0
	w.seed = 5
	w.finish = WallLayout.Finish.TIMBER
	w.openings.assign([Vector4(6.0, 1.5, 0, 1)])
	w.build(Terrain.flat)
	var beams := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "timber")
	var sides := {}
	var off_line := 0
	for b in beams:
		var f := w.frame_at(b.s)
		var out: float = (b.xform.origin - f.point).dot(f.tangent.cross(Vector3.UP))
		sides[signf(out)] = sides.get(signf(out), 0) + 1
		if absf(absf(out) - (WallLayout.THICKNESS * 0.5 - WallLayout.PLASTER_INSET + TimberFrame.DEPTH * 0.35)) > 0.08:
			off_line += 1
	check(sides.get(1.0, 0) == sides.get(-1.0, 0) and sides.get(1.0, 0) > 20, "the frame stands on both faces alike: %s" % sides)
	check(off_line == 0, "every member lies on the face where the wall curves: %d off it" % off_line)
	check(TimberFrame.count({"points": PackedVector3Array(w.points), "closed": false, "height": w.height, "finish": WallLayout.Finish.TIMBER, "fence": false, "gable_end": 0, "openings": PackedVector4Array(w.openings)}) == beams.size(), "the budget counts the members on both faces: %d" % beams.size())
	var walk := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "board" and st.y > w.height)
	var posts := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "post" and st.y > w.height)
	var rails := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "rail")
	check(walk.size() >= WallLayout.WALK_LANES * 4, "the walk is boarded: %d planks" % walk.size())
	check(posts.size() >= 8 and rails.size() >= posts.size(), "the walk is railed in wood: %d posts, %d rails" % [posts.size(), rails.size()])
	var bowed := 0
	var out_of := func(p: Vector3) -> float:
		var f := w.frame_at(w.closest_s(p))
		return (p - f.point).dot(f.tangent.cross(Vector3.UP))
	for piece in walk + beams:
		var x: Transform3D = piece.xform
		var middle: float = out_of.call(x.origin)
		for end in [x.origin - x.basis.x * 0.5, x.origin + x.basis.x * 0.5]:
			if absf(out_of.call(end) - middle) > 0.03:
				bowed += 1
	check(bowed == 0, "every plank and member keeps to the curved wall, its ends within 3 cm of its middle's line: %d off" % bowed)
	check(not w.stones.any(func(st: Dictionary) -> bool: return st.kind in ["cap", "merlon", "cope", "pier"]), "no stone top or pier on a timber-framed wall")
	var mid: Vector3 = w.frame_at(w.length() * 0.5).point
	check(is_equal_approx(w.walk_under(mid + Vector3.UP * 5.0), mid.y + w.height + WallLayout.CAP), "a player stands on the walk's planks")
	var house := _built(WallLayout.Finish.TIMBER, 0.0, true)
	var inner := house.inner_side()
	check(house.stones.filter(func(st: Dictionary) -> bool: return st.has("beam") and st.y < house.height).all(func(b: Dictionary) -> bool:
		var f := house.frame_at(b.beam.face)
		return (b.xform.origin - f.point).dot(f.tangent.cross(Vector3.UP)) * inner < 0.0), "a house's frame stays on its outer face")


## An eraser's ruin takes the frame, walk and railing with the wall's courses where it breaks the wall away.
func _ruined_timber_walls_break() -> void:
	var w := WallLayout.new()
	w.points.assign([Vector3.ZERO, Vector3(12, 0, 0)] as Array[Vector3])
	w.height = 3.0
	w.finish = WallLayout.Finish.TIMBER
	w.ruins.assign([Vector2(5.0, 7.0)] as Array[Vector2])
	w.build(Terrain.flat)
	var gap: Vector2 = w.breaks[-1][0]
	var inside := w.stones.filter(func(st: Dictionary) -> bool: return st.kind in ["timber", "board", "post", "rail"] and st.s > gap.x + 0.1 and st.s < gap.y - 0.1)
	check(inside.is_empty(), "nothing of the frame or walk stands in the ruin's gap %s: %s" % [gap, inside.map(func(st: Dictionary) -> String: return "%s at %.2f" % [st.kind, st.s])])


## A fence takes planks: across, boards between its posts in place of the rails; upright, planks on its rails. A gate
## stays open under its arch.
func _fences_take_planks() -> void:
	var counts := {}
	for finish in [WallLayout.Finish.BARE, WallLayout.Finish.BOARDS_ACROSS, WallLayout.Finish.BOARDS_UPRIGHT]:
		var w := WallLayout.new()
		w.points.assign([Vector3.ZERO, Vector3(10, 0, 0)] as Array[Vector3])
		w.fence = true
		w.height = WallLayout.FENCE_HEIGHT
		w.finish = finish
		w.openings.assign([WallLayout.archway(5.0)])
		w.build(Terrain.flat)
		var name: String = WallLayout.Finish.keys()[finish]
		var rails := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "rail")
		var boards := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "board")
		counts[name] = [rails.size(), boards.size()]
		check(w.stones.any(func(st: Dictionary) -> bool: return st.kind == "post") and w.stones.any(func(st: Dictionary) -> bool: return st.kind == "gate"), "%s fence: posts and a gate stand" % name)
		var gate := WallLayout.ARCH_HALF + 0.08
		check(not (rails + boards).any(func(st: Dictionary) -> bool: return absf(st.s - 5.0) < gate - 0.05), "%s fence: nothing closes the gate" % name)
		match finish:
			WallLayout.Finish.BARE:
				check(boards.is_empty() and not rails.is_empty(), "a bare fence is railed")
			WallLayout.Finish.BOARDS_ACROSS:
				check(rails.is_empty() and boards.all(func(b: Dictionary) -> bool: return is_equal_approx(b.size.y, WallLayout.FENCE_BOARD_TALL)), "planks across stand between the posts in the rails' place")
				check(boards.size() > counts.BARE[0] * 3, "planks across close the fence: %d against %d rails" % [boards.size(), counts.BARE[0]])
			WallLayout.Finish.BOARDS_UPRIGHT:
				check(rails.size() == counts.BARE[0] and boards.size() > 40 and boards.all(func(b: Dictionary) -> bool: return b.size.y > WallLayout.FENCE_HEIGHT * 0.8), "upright planks stand on the rails")


## The garden's command takes a finish and its wear, turns down wear on any finish but plaster, plaster or timber on a
## fence, and an unknown finish; a coned tower stays stone.
func _commands_check_finishes() -> void:
	var d := wall_data({"points": PackedVector3Array([Vector3.ZERO, Vector3(6, 0, 0)]), "seed": 2, "finish": WallLayout.Finish.PLASTER, "wear": 0.5})
	var clean: Variant = Commands._wall(d)
	check(clean != null and clean.finish == WallLayout.Finish.PLASTER and clean.wear == 0.5, "worn plaster passes")
	for bad in [{"finish": WallLayout.Finish.TIMBER, "wear": 0.5}, {"finish": WallLayout.Finish.BOARDS_ACROSS, "wear": 0.25}, {"wear": 1.5}, {"wear": -0.1}, {"finish": WallLayout.Finish.size()}, {"finish": -1}, {"wear": 1}]:
		check(Commands._wall(d.merged(bad, true)) == null, "turned down: %s" % bad)
	for finish in WallLayout.Finish.values():
		var fence := d.merged({"fence": true, "finish": finish, "wear": 0.0}, true)
		var ok: bool = finish in [WallLayout.Finish.BARE, WallLayout.Finish.BOARDS_ACROSS, WallLayout.Finish.BOARDS_UPRIGHT]
		check((Commands._wall(fence) != null) == ok, "a fence %s %s" % ["takes" if ok else "turns down", WallLayout.Finish.keys()[finish]])
	var tower := wall_data({"points": PackedVector3Array(WallLayout.circle(Vector3.ZERO, 2.0)), "closed": true, "seed": 2, "finish": WallLayout.Finish.PLASTER, "wear": 0.5, "roof": {"kind": RoofLayout.Kind.CONE, "center": Vector3.ZERO, "radius": 2.0, "pitch": 1.5, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "hatches": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}})
	var cone: Variant = Commands._wall(tower)
	check(cone != null and cone.finish == WallLayout.Finish.BARE and cone.wear == 0.0, "a coned tower stays stone")


## Worn plaster counts as plaster and the stone it shows; a planked wall as its planks over a plaster-priced backing, a
## planked fence as its planks besides its posts; timber framing its members. Each charge matches what is laid.
func _budget_charges_each_finish() -> void:
	var d := wall_data({"points": PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0)]), "seed": 2, "height": 3.0})
	var area := 30.0
	check(is_equal_approx(Budget.wall(d.merged({"finish": WallLayout.Finish.PLASTER, "wear": 0.5}, true)).wall_m2, area * 0.5), "worn plaster charges the stone it shows")
	check(is_equal_approx(Budget.wall(d.merged({"finish": WallLayout.Finish.PLASTER, "wear": 0.5}, true)).plaster_m2, area), "and its plaster")
	for finish in [WallLayout.Finish.BOARDS_ACROSS, WallLayout.Finish.BOARDS_UPRIGHT]:
		for fence in [false, true]:
			var planked := d.merged({"finish": finish, "fence": fence, "height": WallLayout.FENCE_HEIGHT if fence else 3.0, "openings": PackedVector4Array([Vector4(5, 1.5, 0, 1)] if not fence else [])}, true)
			var units := Budget.wall(planked)
			var w := WallLayout.new()
			w.set_data(planked)
			w.build(Terrain.flat)
			var laid := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "board").size()
			var name := "%s %s" % ["fence" if fence else "wall", WallLayout.Finish.keys()[finish]]
			check(units.get("timber", 0) >= laid and units.get("timber", 0) < laid * 1.4 + 4, "%s: charges its planks as laid: %d for %d" % [name, units.get("timber", 0), laid])
			check(units.has("fence_m2") if fence else is_equal_approx(units.get("plaster_m2", 0.0), area) and not units.has("wall_m2"), "%s: and the face behind them: %s" % [name, units])
	var arc := PackedVector3Array()
	for i in 13:
		arc.append(Vector3(cos(i / 12.0 * PI) * 4.0, 0.0, sin(i / 12.0 * PI) * 4.0))
	for shape: Dictionary in [{"points": arc, "closed": false}, {"points": PackedVector3Array(WallLayout.circle(Vector3.ZERO, 2.0)), "closed": true}]:
		for finish in [WallLayout.Finish.BOARDS_ACROSS, WallLayout.Finish.BOARDS_UPRIGHT, WallLayout.Finish.TIMBER]:
			var curved := d.merged(shape, true).merged({"finish": finish, "ruins": PackedVector2Array([Vector2(3.0, 4.0)]) if not shape.closed else PackedVector2Array()}, true)
			var w := WallLayout.new()
			w.set_data(curved)
			w.build(Terrain.flat)
			var laid := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "board" or st.kind == "timber").size()
			check(Budget.wall(curved).get("timber", 0) >= laid, "a %s %s charges at least the %d pieces it lays: %d" % ["loop" if shape.closed else "curved wall", WallLayout.Finish.keys()[finish], laid, Budget.wall(curved).get("timber", 0)])
	check(Budget.wall(d.merged({"fence": true}, true)).has("fence_m2") and not Budget.wall(d.merged({"fence": true}, true)).has("timber"), "a railed fence counts as fence")
	var framed := d.merged({"finish": WallLayout.Finish.TIMBER}, true)
	var frame := WallLayout.new()
	frame.set_data(framed)
	frame.build(Terrain.flat)
	var members := frame.stones.filter(func(st: Dictionary) -> bool: return st.kind == "timber").size()
	var walk := frame.stones.filter(func(st: Dictionary) -> bool: return st.kind == "board").size()
	var charged: int = Budget.wall(framed).get("timber", 0)
	check(charged >= members + walk and charged < members + walk * 1.4 + 4, "a timber-framed wall charges the members it lays on both faces and its walk's planks: %d for %d and %d" % [charged, members, walk])


## The style tool's face wheel on an open wall offers every finish, worn plaster at each amount; on a fence rails and
## planks; turned, the garden takes it, walls laid after take it and an undo puts it back.
func _the_face_wheel_turns_every_finish() -> void:
	world._order({"op": "wall", "walls": [wall_data({"points": PackedVector3Array([Terrain.ground(-30, 20), Terrain.ground(-22, 20)]), "seed": 3})]}, 1)
	var id := world.seq * Commands.MAX_PIECES
	var picker: PaletteTool = main.palette_tool
	var target := picker.style_target(PaletteTool.Restyle.FACE, main.tool.find(id), Vector3.ZERO)
	check(target.count == PaletteTool.FACES.size(), "an open wall offers every finish: %d" % target.count)
	for pick in target.count:
		picker.open(main.rig.right, target)
		picker.twist(main.rig.right, (pick - picker.wheels[main.rig.right].start) * Palette.twist_step(target.count))
		picker.close(main.rig.right)
		var face: Vector2 = PaletteTool.FACES[target.options[pick]]
		check(world.state.walls[id].finish == int(face.x) and world.state.walls[id].wear == face.y, "the wheel turns the wall to %s worn %.2f" % [WallLayout.Finish.keys()[int(face.x)], face.y])
		check(main.tool.finish == int(face.x) and main.tool.wear == face.y, "walls laid after take %s worn %.2f" % [WallLayout.Finish.keys()[int(face.x)], face.y])
	world._order({"op": "undo"}, world.me())
	var before: Vector2 = PaletteTool.FACES[target.options[target.count - 2]]
	check(world.state.walls[id].finish == int(before.x), "an undo puts the finish before back")
	var walls_finish := main.tool.finish
	world._order({"op": "wall", "walls": [wall_data({"points": PackedVector3Array([Terrain.ground(-30, 26), Terrain.ground(-22, 26)]), "seed": 4, "fence": true, "height": WallLayout.FENCE_HEIGHT})]}, 1)
	var fence := world.seq * Commands.MAX_PIECES
	var f: Wall = main.tool.find(fence)
	f.lay_now()
	var mid: Dictionary = f.layout.frame_at(4.0)
	var aim := picker.aim_style(mid.point + Vector3.UP * 0.7 + mid.tangent.cross(Vector3.UP) * 3.0, -mid.tangent.cross(Vector3.UP))
	check(aim.get("restyle") == PaletteTool.Restyle.FACE and aim.get("count") == 3, "a fence's face wheel offers rails and planks: %s" % aim.get("count"))
	_turn(aim, 2)
	check(world.state.walls[fence].finish == WallLayout.Finish.BOARDS_UPRIGHT and main.tool.fence_finish == WallLayout.Finish.BOARDS_UPRIGHT, "the fence takes upright planks, and fences after")
	check(main.tool.finish == walls_finish, "a fence's finish leaves walls' alone")
	world.restore({"seq": 0, "cmds": []})


func _turn(target: Dictionary, steps: int) -> void:
	var picker: PaletteTool = main.palette_tool
	picker.open(main.rig.right, target)
	picker.twist(main.rig.right, Palette.twist_step(target.count) * steps)
	picker.close(main.rig.right)


## demo/finishes.json lays every finish on houses, walls and fences.
func _demo() -> void:
	for step: Dictionary in Driver.read("res://../demo/finishes.json"):
		if step.op == "quit":
			continue
		step.erase("capture")
		if step.op == "capture":
			continue
		await play([step])
	var seen := {}
	for w: Wall in main.tool.walls:
		seen["%s %s" % ["fence" if w.layout.fence else "house" if w.layout.closed else "wall", WallLayout.Finish.keys()[w.layout.finish]]] = true
		if w.layout.wear > 0.0:
			seen["worn"] = true
	for want in ["house PLASTER", "house TIMBER", "house BOARDS_ACROSS", "house BOARDS_UPRIGHT", "wall PLASTER", "wall TIMBER", "wall BOARDS_ACROSS", "wall BOARDS_UPRIGHT", "fence BOARDS_ACROSS", "fence BOARDS_UPRIGHT", "worn"]:
		check(seen.has(want), "the demo lays %s: %s" % [want, seen.keys()])
	await play([{"op": "clear"}])


## The stress scene's finishes/* phases look over the stress village in the finish over its stones the budget charges
## most for (the bare stone village stands in its village/* phases).
func _stress_village() -> void:
	var steps := Driver.read("res://../demo/stress.json")
	var first := steps.find_custom(func(s: Dictionary) -> bool: return s.get("name", "") == "finishes/aerial")
	check(first >= 0 and steps.any(func(s: Dictionary) -> bool: return s.get("name", "") == "finishes/ground"), "the stress scene has finishes/aerial and finishes/ground phases")
	if first < 0:
		return
	var village := first
	while steps[village].op != "village":
		village -= 1
	var costs := {}
	for face: Vector2 in PaletteTool.FACES:
		if face.x == WallLayout.Finish.BARE:
			continue
		var step: Dictionary = steps[village].duplicate(true)
		step.finish = WallLayout.Finish.keys()[int(face.x)].to_lower()
		step.wear = face.y
		await play([steps[0], step])
		var units := {}
		for w: Wall in main.tool.walls:
			Budget.add(units, Budget.wall(w.data()))
		costs[face] = Budget.cost_ms(units)
		await play([{"op": "clear"}])
	var dearest: Vector2 = costs.keys().reduce(func(a: Vector2, b: Vector2) -> Vector2: return a if costs[a] >= costs[b] else b)
	print("finishes: the village's budget by finish %s" % costs)
	var stressed := Vector2(WallLayout.Finish[String(steps[village].get("finish", "bare")).to_upper()], steps[village].get("wear", 0.0))
	check(stressed == dearest, "the stress village stands in its costliest finish %s: %s" % [dearest, stressed])
