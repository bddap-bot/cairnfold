extends SceneTree

## Headless checks of thatched roofs: godot4 --headless --path game --script ../tests/test_thatch.gd
## Directive (verbatim): "Thatched roofs I want them as an option."

var failures := 0


func _init() -> void:
	_thatch_covers_every_roof_shape()
	_thatch_follows_a_resized_house()
	_a_thatched_gable_has_no_stone_verge()
	_thatch_is_part_of_the_build_command()
	_the_budget_counts_thatch()
	_thatch_is_painted_as_thatch()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _flat(_x: float, _z: float) -> float:
	return 0.0


## A house or tower and its roof laid as a Wall lays them: [WallLayout, RoofLayout].
func _built(points: Array[Vector3], kind: RoofLayout.Kind, pitch: float, curve: float, radius := 2.0, thatch := true) -> Array:
	var w := WallLayout.new()
	w.points = points
	w.closed = true
	w.height = 2.4
	w.top = WallLayout.Top.CAP
	w.cover = WallLayout.Cover.ROOF
	var r := RoofLayout.new()
	r.kind = kind
	r.center = Vector3(1, 0, 1)
	r.radius = radius
	r.pitch = pitch
	r.curve = curve
	r.seed = 7
	r.thatch = thatch
	w.gable = r
	w.build(_flat)
	Wall.pack_roof(w, r, Wall.kinds(), Palette.plain())
	return [w, r]


func _gabled(length: float, depth: float, pitch: float, curve := 0.0, thatch := true) -> Array:
	return _built(WallLayout.rectangle(Vector3.ZERO, Vector3(length, 0, 0), depth), RoofLayout.Kind.GABLE, pitch, curve, 2.0, thatch)


func _towered(radius: float, pitch: float, curve := 0.0) -> Array:
	return _built(WallLayout.circle(Vector3(1, 0, 1), radius), RoofLayout.Kind.CONE, pitch, curve, radius)


func _of(r: RoofLayout, kind: String) -> Array:
	return r.tiles.filter(func(t): return t.kind == kind)


## The coat's triangles, bucketed by the half-metre ground cells their bounds cross, for casting rays at it.
class Coat:
	var verts: PackedVector3Array
	var cells := {}

	func _init(r: RoofLayout) -> void:
		verts = r.coat[Mesh.ARRAY_VERTEX] if not r.coat.is_empty() else PackedVector3Array()
		for i in range(0, verts.size(), 3):
			var box := AABB(verts[i], Vector3.ZERO).expand(verts[i + 1]).expand(verts[i + 2])
			for x in range(floori(box.position.x * 2.0), floori(box.end.x * 2.0) + 1):
				for z in range(floori(box.position.z * 2.0), floori(box.end.z * 2.0) + 1):
					var k := Vector2i(x, z)
					if not cells.has(k):
						cells[k] = PackedInt32Array()
					cells[k].append(i)

	## How far along the segment from `a` to `b` it first meets the coat, or INF. A segment through an edge two
	## triangles share can slip between them, so a miss is tried again a hair to either side.
	func hit(a: Vector3, b: Vector3) -> float:
		var d := _hit(a, b)
		for nudge in [Vector3(0.002, 0.0, 0.001), Vector3(-0.001, 0.0, -0.002)]:
			if d == INF:
				d = _hit(a + nudge, b + nudge)
		return d

	func _hit(a: Vector3, b: Vector3) -> float:
		var seen := {}
		var best := INF
		var lo := Vector2i(floori(minf(a.x, b.x) * 2.0), floori(minf(a.z, b.z) * 2.0))
		var hi := Vector2i(floori(maxf(a.x, b.x) * 2.0), floori(maxf(a.z, b.z) * 2.0))
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.y, hi.y + 1):
				for i in cells.get(Vector2i(x, z), PackedInt32Array()):
					if seen.has(i):
						continue
					seen[i] = true
					var p: Variant = Geometry3D.segment_intersects_triangle(a, b, verts[i], verts[i + 1], verts[i + 2])
					if p != null:
						best = minf(best, a.distance_to(p))
		return best


## Points on the roof's surface out to its eaves, from the ridge or axis to past the walls' outer faces at a gable's
## ends, each as [point, normal, down the slope, along the ridge (or round the cone)].
func _surface(r: RoofLayout, xs := PackedFloat32Array()) -> Array:
	var out := []
	var f := r.frame()
	var hs := r.half_span()
	if xs.is_empty():
		var steps := ceili(r.eave() / 0.2)
		for i in steps + 1:
			xs.append(r.eave() * i / steps)
	var frames := []
	if r.kind == RoofLayout.Kind.CONE:
		for k in 36:
			var dir := Vector3(cos(TAU * k / 36), 0, sin(TAU * k / 36))
			frames.append([f.mid, dir, dir.cross(Vector3.UP)])
	else:
		var reach := r.ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5 + 0.1
		var n := ceili(2.0 * reach / 0.25)
		for side in [-1.0, 1.0]:
			for j in n + 1:
				frames.append([f.mid + f.along * (-reach + 2.0 * reach * j / n), f.across * side, f.along])
	for fr in frames:
		for x in xs:
			var s := r.slope_at(x)
			var dir: Vector3 = fr[1]
			out.append([fr[0] + dir * x + Vector3.UP * r.rise(1.0 - x / hs), dir * sin(s) + Vector3.UP * cos(s), dir * cos(s) - Vector3.UP * sin(s), fr[2]])
	return out


## Straw wherever the roof is: a ray down onto any point of it meets the coat's outer face, a coat's depth up; one
## down onto the ridge meets straw above the slopes' meeting; one in under the eave or a verge meets its rounded edge
## before the wall; and one up from under the overhang meets its underside.
func _covered(r: RoofLayout, what: String) -> void:
	var coat := Coat.new(r)
	_check(coat.verts.size() > 600 and _of(r, "tile").is_empty() and _of(r, "ridge").is_empty(), "%s: thatched in straw, no tiles: %d triangles" % [what, coat.verts.size() / 3])
	var thin := []
	for p in _surface(r):
		var d := coat.hit(p[0] + p[1] * 1.5, p[0] + p[1] * 0.01)
		if 1.5 - d < RoofLayout.COAT - RoofLayout.LUMPS - 0.02:
			thin.append(p[0])
	_check(thin.is_empty(), "%s: the coat lies a coat deep over the whole roof; thin or bare at %d of its points, the first %s" % [what, thin.size(), thin[0] if not thin.is_empty() else null])
	var f := r.frame()
	var top := r.base + r.pitch
	var ridge := [f.mid] if r.kind == RoofLayout.Kind.CONE else range(-10, 11).map(func(k: int) -> Vector3: return f.mid + f.along * r.ridge_length() * 0.5 * k / 10.0)
	for p: Vector3 in ridge:
		var d := coat.hit(Vector3(p.x, top + 3.0, p.z), Vector3(p.x, top, p.z))
		if 3.0 - d < RoofLayout.COAT:
			_check(false, "%s: straw stands %.2f over the ridge at %s" % [what, 3.0 - d, p])
			return
	var hs := r.half_span()
	var edge := r.eave() + RoofLayout.THATCH_EAVE
	var eaves := _surface(r, PackedFloat32Array([hs])).filter(func(p: Array) -> bool: return r.kind == RoofLayout.Kind.CONE or absf(p[3].dot(p[0] - f.mid)) < r.ridge_length() * 0.5)
	_check(eaves.size() >= 10, "%s: probed along its eaves" % what)
	for p in eaves:
		var foot: Vector3 = p[0]
		var lifted: Vector3 = foot + p[1] * RoofLayout.COAT * 0.5
		if coat.hit(lifted + p[2] * ((edge - hs) / cos(r.slope_at(hs)) + 0.6), lifted) == INF:
			_check(false, "%s: a ray in under the eave at %s meets no straw before the wall" % [what, foot])
			return
		if coat.hit(foot - Vector3.UP * 0.6 + p[2] * 0.15, foot + p[2] * 0.15 + Vector3.UP * 0.01) == INF:
			_check(false, "%s: no underside over the eave at %s" % [what, foot])
			return
	if r.kind == RoofLayout.Kind.GABLE:
		var end := r.ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5
		for x in [0.3, hs * 0.5, hs - 0.1]:
			for e in [-1.0, 1.0]:
				var foot: Vector3 = f.mid + f.along * e * end + f.across * x + Vector3.UP * r.rise(1.0 - x / hs)
				var lifted := foot + Vector3.UP * RoofLayout.COAT * 0.5
				if coat.hit(lifted + f.along * e * (RoofLayout.THATCH_VERGE + 0.6), lifted) == INF:
					_check(false, "%s: a ray in at the verge at %s meets no straw before the gable" % [what, foot])
					return


func _thatch_covers_every_roof_shape() -> void:
	for g in [[6.0, 4.0, 1.68, 0.0], [6.0, 4.0, 5.0, 0.0], [6.0, 4.0, 2.0, 0.8], [6.0, 4.0, 2.0, -0.8], [2.4, 2.4, 1.0, 0.0], [3.0, 2.4, 6.0, 0.0], [14.0, 7.0, 6.0, 0.0], [14.0, 7.0, 0.5, 0.0]]:
		var built := _gabled(g[0], g[1], g[2], g[3])
		_covered(built[1], "a %.1f×%.1f gable at pitch %.2f, curve %.1f" % g)
		_under_the_coat(built[0], built[1], "the %.1f×%.1f gable at pitch %.2f" % [g[0], g[1], g[2]])
	for c in [[1.2, 1.9, 0.0], [3.5, 6.0, 0.0], [2.0, 3.2, -0.6], [2.0, 3.2, 0.8]]:
		var built := _towered(c[0], c[1], c[2])
		_covered(built[1], "a %.1f m cone at pitch %.1f, curve %.1f" % c)
		_under_the_coat(built[0], built[1], "the %.1f m cone" % c[0])
		var crown := _of(built[1], "finial")
		_check(crown.size() == 1 and crown[0].xform.origin.y > built[1].base + c[1] + built[1].coat_rise(), "its finial stands clear of the straw")


## No stone of the walls reaches through the coat anywhere under the roof, and the slabs standing in for the coat in
## shadows and bounce light lie inside it.
func _under_the_coat(w: WallLayout, r: RoofLayout, what: String) -> void:
	var f := r.frame()
	var hs := r.half_span()
	var depth := func(p: Vector3) -> float:
		var d := Vector3(p.x - f.mid.x, 0.0, p.z - f.mid.z)
		var out := d.length() if r.kind == RoofLayout.Kind.CONE else absf(d.dot(f.across))
		if out > r.eave() or (r.kind == RoofLayout.Kind.GABLE and absf(d.dot(f.along)) > r.ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5):
			return -INF
		return (p.y - r.base - r.rise(1.0 - out / hs)) * cos(r.slope_at(out))
	for s in w.stones:
		var x: Transform3D = s.xform
		for c in [Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5)]:
			var p: Vector3 = x * c
			if depth.call(p) > RoofLayout.COAT - RoofLayout.LUMPS - 0.02:
				_check(false, "%s: a %s's corner at %s stands %.2f out of the slope, through the coat" % [what, s.kind, p, depth.call(p)])
				return
	_check(not r.slabs.is_empty(), "%s: slabs stand in for the coat" % what)
	for slab in r.slabs:
		var x: Transform3D = slab.xform
		var crown: Vector3 = x.origin + x.basis.y * 0.5
		if depth.call(crown) > RoofLayout.COAT - RoofLayout.LUMPS:
			_check(false, "%s: a slab's top at %s stands out of the coat" % [what, crown])
			return


func _thatch_follows_a_resized_house() -> void:
	var at := {"center": Vector3(0, 0, 0), "yaw": 0.0, "size": Vector2(6, 4), "round": false}
	var d := {"points": PackedVector3Array(WallTool.outline(at)), "closed": true, "arches": PackedFloat32Array(), "windows": PackedVector2Array(),
		"lanterns": PackedVector3Array(), "flags": PackedFloat32Array(),
		"roof": {"kind": RoofLayout.Kind.GABLE, "center": Vector3.ZERO, "radius": 2.0, "pitch": 1.68, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array(), "flag": false, "thatch": true}}
	for size in [Vector2(12, 4), Vector2(6, 8), Vector2(2.4, 2.4), Vector2(14, 7)]:
		var to := WallTool.house_of(d)
		to.size = size
		var change := WallTool.reshape_house(d, to)
		_check(not change.roof.has("thatch"), "a resize leaves the roof's covering as it is")
		var roof: Dictionary = d.roof.merged(change.roof, true)
		var points: Array[Vector3] = []
		points.assign(Array(change.points))
		var built := _built(points, RoofLayout.Kind.GABLE, roof.pitch, roof.curve, 2.0, roof.thatch)
		_covered(built[1], "a house resized to %s" % size)
	var tower := {"points": PackedVector3Array(WallLayout.circle(Vector3(2, 0, 2), 2.0)), "closed": true, "arches": PackedFloat32Array(), "windows": PackedVector2Array(),
		"lanterns": PackedVector3Array(), "flags": PackedFloat32Array(),
		"roof": {"kind": RoofLayout.Kind.CONE, "center": Vector3(2, 0, 2), "radius": 2.0, "pitch": 3.2, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array(), "flag": false, "thatch": true}}
	var wider := WallTool.house_of(tower)
	wider.size = Vector2(6, 6)
	var grown: Dictionary = tower.roof.merged(WallTool.reshape_house(tower, wider).roof, true)
	_covered(_towered(grown.radius, grown.pitch)[1], "a tower widened to 6 m")


func _a_thatched_gable_has_no_stone_verge() -> void:
	var tiled: WallLayout = _gabled(6.0, 4.0, 2.0, 0.0, false)[0]
	var thatched: WallLayout = _gabled(6.0, 4.0, 2.0)[0]
	var verge := func(w: WallLayout) -> int: return w.stones.filter(func(s): return s.kind == "cope" and s.y > w.height + WallLayout.CAP).size()
	_check(verge.call(tiled) >= 8 and verge.call(thatched) == 0, "the thatch rolls over the gable's rakes in place of a stone verge: %d tiled, %d thatched" % [verge.call(tiled), verge.call(thatched)])
	var courses := func(w: WallLayout) -> Array: return w.stones.filter(func(s): return s.kind == "block" and s.y > w.height + WallLayout.CAP)
	_check(courses.call(thatched) == courses.call(tiled), "and the gable's stones stay the same beneath either covering")


func _thatch_is_part_of_the_build_command() -> void:
	var r := RoofLayout.new()
	var copy := r.inputs()
	copy.thatch = true
	_check(not copy.same_inputs(r), "a thatched roof is another roof")
	var d := {"points": PackedVector3Array(WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0)), "height": 2.4, "arches": PackedFloat32Array(),
		"seed": 3, "closed": true, "top": int(WallLayout.Top.CAP), "fence": false, "windows": PackedVector2Array(), "lanterns": PackedVector3Array(),
		"flags": PackedFloat32Array(), "ruins": PackedVector2Array(), "plaster": false, "on": PackedInt32Array(), "paint": Palette.plain(),
		"roof": {"kind": int(RoofLayout.Kind.GABLE), "center": Vector3.ZERO, "radius": 2.0, "pitch": 2.0, "curve": 0.0, "seed": 3, "chimneys": PackedVector2Array(), "flag": false, "thatch": false}}
	_check(Commands._wall(d) != null, "a tiled house is a valid build")
	d.roof.thatch = true
	_check(Commands._wall(d) != null and Commands._wall(d).roof.thatch, "and a thatched one")
	_check(Commands._reshape({"roof": {"thatch": false}}, Commands._wall(d)).roof == {"thatch": false}, "a reshape tiles it again")
	d.roof.thatch = 1
	_check(Commands._wall(d) == null, "a covering that is not a yes or no is refused")
	d.roof.erase("thatch")
	_check(Commands._wall(d) != null and Commands._wall(d).roof.thatch == false, "a roof saved before thatch existed is tiled")


func _the_budget_counts_thatch() -> void:
	var d := {"points": WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0), "closed": true, "height": 2.4, "fence": false, "plaster": false,
		"lanterns": [], "flags": [], "roof": {"kind": RoofLayout.Kind.GABLE, "radius": 2.0, "pitch": 2.0, "curve": 0.0, "chimneys": [], "flag": false, "thatch": true}}
	var plan := (6.0 + WallLayout.THICKNESS + 2.0 * RoofLayout.GABLE_OVERHANG) * (4.0 + WallLayout.THICKNESS + 2.0 * RoofLayout.OVERHANG)
	var thatched := Budget.wall(d)
	_check(is_equal_approx(thatched.get("thatch_m2", 0.0), plan) and not thatched.has("roof_m2"), "a thatched house counts the ground its roof covers as thatch: %s" % thatched)
	d.roof.thatch = false
	_check(is_equal_approx(Budget.wall(d).get("roof_m2", 0.0), plan) and not Budget.wall(d).has("thatch_m2"), "a tiled one as roof")
	d.roof.thatch = true
	d.points = WallLayout.rectangle(Vector3.ZERO, Vector3(12, 0, 0), 4.0)
	_check(Budget.wall(d).thatch_m2 > thatched.thatch_m2 * 1.8, "a house twice as long counts nearly twice the thatch")
	d.roof.pitch = 0.0
	_check(Budget.wall(d).has("roof_m2") and not Budget.wall(d).has("thatch_m2"), "pushed flat it is a stone deck")
	_check(Budget.FRAME_COSTS.has("thatch_m2") and "thatch_m2" in Budget.UNITS, "thatch has its own measured cost")


func _thatch_is_painted_as_thatch() -> void:
	var r: RoofLayout = _gabled(6.0, 4.0, 2.0)[1]
	_check(Palette.code("thatch") == Palette.Element.THATCH and Palette.SWATCHES[Palette.Element.THATCH][0] == RoofLayout.STRAW, "straw takes the thatch swatches, laid in straw")
	var colours: PackedColorArray = r.coat[Mesh.ARRAY_COLOR]
	var mean := Color(0, 0, 0)
	for c in colours:
		mean += c / colours.size()
	_check(mean.r > mean.g and mean.g > mean.b and mean.b < 0.35, "it reads as straw: %s" % mean)
	var other := RoofLayout.new()
	other.corners = r.corners
	other.base = r.base
	other.pitch = r.pitch
	other.thatch = true
	other.seed = 8
	other.build()
	_check(other.coat[Mesh.ARRAY_COLOR][0] != colours[0], "each roof weathers its own way")
