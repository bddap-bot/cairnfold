class_name WallLayout
extends RefCounted

## Pure data, no nodes, so tests run headless.

enum Family { COTTAGE, ARCHWAY, ARCHED, SLIT, ROUND, CORNER }

enum Top { CRENEL, CAP, COPE, RAIL }
enum Cover { OPEN, ROOF, DECK }
enum GableEnd { WALL, BOARDS, STEPS }
enum Foundation { STONE, PLASTER, PILLARS, POSTS }
const STILTS: Array[Foundation] = [Foundation.PILLARS, Foundation.POSTS]
const FENCE_FOUNDATIONS: Array[Foundation] = [Foundation.STONE]
enum Finish { BARE, PLASTER, TIMBER, BOARDS_ACROSS, BOARDS_UPRIGHT }

const COURSE := 0.3
const LONGEST := 0.85
## No maximum: the budget charges height, and a plinth's rise, as wall.
const MIN_HEIGHT := 0.9
## FLAG (along, thick, across); PLANK (across, thick, shortest, longest).
const FLAG := Vector3(0.7, 0.08, 0.5)
const PLANK := Vector4(0.2, 0.05, 1.2, 2.6)
const FLOOR_JOINT := 0.012
const BED_DEPTH := FLOOR_JOINT * 0.25
## A floor on a build is the ceiling below: its beds take its flags' stone this much darker, not mortar.
const FLOOR_UNDERSIDE := 0.75
## Behind a worn patch's mortar, so no joint shows the floor.
const FLOOR_REACH := WORN_THICK * 0.5 - JOINT - 0.01
const FLOOR_KINDS: Array[String] = ["flagstone", "plank", "bed"]
## (spacing, inset from the walls' centre line, radius, fade)
const BARE_STAMP := Vector4(0.4, 0.15, 0.3, 0.1)
const STILT_SPAN := 1.8
const STILT_SPACING := 2.0
const PILLAR := 0.5
const POST := 0.24
## (width, height)
const BEAM := Vector2(0.3, 0.26)
const THICKNESS := 0.62
const CAP := 0.14
## (least, most) heights.
const COPE_TALL := Vector2(0.34, 0.42)
const COPE_SHORT := Vector2(0.22, 0.28)
const PARAPET := 0.34
## Height over the cap; RAIL_POSTS the widest post spacing; RAILS the rails' heights.
const RAILING := 0.9
const RAIL_POSTS := 1.4
const RAILS := Vector2(0.45, 0.86)
const SAMPLE := 0.2
const SINK := 0.12
## At size 1, as is SPRING; an opening's size scales them.
const ARCH_HALF := 0.75
const RING := 0.32
const SPRING := 1.5
const MIN_SIZE := 0.4
const END_CLEAR := 0.3
const ARCH_END := ARCH_HALF + RING + END_CLEAR
const CORNER_TURN := deg_to_rad(35.0)
const PIER := THICKNESS + 0.28
const ARCH_SPACING := (ARCH_HALF + RING) * 2.0
## Arches nearer than this share a pillar.
const ARCADE_GAP := ARCH_SPACING + 0.4
const ARCADE_PITCH := 2.3
## The share of a stone's width `Stones.mesh` keeps flat (its edge vertices stand 0.46 out, and lump): overlapped this
## far, stones meet face to face.
const MEET := 0.8
## A shoulder arc of `shoulder` * ARCH_HALF turning `turn` degrees from upright, then a crown arc of `crown` * it (none
## round); `pieces` wedges of `kind`, `ring` deep, per arc, mortarless to `meet`; a `capstone` sized `keystone`; posts
## `jamb` wide.
const ARCH_STYLES := [
	{"name": "stone", "shoulder": 1.0, "turn": 90.0, "crown": 1.0, "pieces": [5, 0], "ring": RING, "meet": MEET, "kind": "voussoir", "capstone": "keystone", "keystone": Vector3(0.34, RING * 1.15, THICKNESS * 1.1), "jamb": 0.0, "jitter": 0.015},
	{"name": "timber", "shoulder": 0.35, "turn": 60.0, "crown": 2.0, "pieces": [3, 2], "ring": TimberFrame.WIDTH, "meet": 1.0, "kind": "timber", "color": TimberFrame.OAK, "capstone": "timber", "keystone": Vector3(0.2, TimberFrame.WIDTH, THICKNESS * 1.04), "jamb": TimberFrame.WIDTH, "jitter": 0.0},
]
const WADE_UNDER := 0.1
const SWIM_CLEAR := 0.25
const SWIM_REACH := THICKNESS * 0.5 + SWIM_CLEAR
const FENCE_HEIGHT := 1.1
const FENCE_BOARD_TALL := 0.14
const FENCE_BOARDS: Array[float] = [0.0, 0.16, 0.32, 0.48, 0.64, 0.8, 0.96]
const FENCE_PALE := 0.12
const POST_SPACING := 1.6
const GATE_POST := 2.1
const WINDOW_HALF := 0.3
const WINDOW_TALL := 0.9
const DOOR_HALF := 0.5
const DOOR_TALL := 2.0
const DOOR_SILL := 0.6
const MULLION := 0.14
const FUSE := WINDOW_HALF * 2.0 + 0.5
const WINDOW_RING := 0.16
## Clears the coursed stones' jitter.
const RING_PROUD := 0.03
const CORNER_POST := 0.14
## At size 1. `mullion`: stone between fused lights; `door`: opens as a door low on a wall; `ring`: wedges head it;
## `dressed`: a lived-in house dresses it.
const LIGHTS := {
	Family.COTTAGE: {"half": WINDOW_HALF, "tall": WINDOW_TALL, "mullion": MULLION, "door": true, "ring": false, "dressed": true},
	Family.ARCHED: {"half": 0.3, "tall": 1.2, "mullion": WINDOW_RING * 2.0 + 0.06, "door": true, "ring": true, "dressed": true},
	Family.SLIT: {"half": 0.08, "tall": 1.2, "mullion": 0.6, "door": false, "ring": false, "dressed": false},
	Family.ROUND: {"half": 0.36, "tall": 0.72, "mullion": WINDOW_RING * 2.0 + 0.06, "door": false, "ring": true, "dressed": false},
	Family.CORNER: {"half": 0.6, "tall": WINDOW_TALL, "mullion": 0.0, "door": false, "ring": false, "dressed": false},
}
const WINDOW_FAMILIES: Array[Family] = [Family.COTTAGE, Family.ARCHED, Family.SLIT, Family.ROUND]
const CURTAINS: Array[Color] = [Color(0.66, 0.2, 0.17), Color(0.86, 0.8, 0.62), Color(0.24, 0.36, 0.52), Color(0.4, 0.5, 0.3), Color(0.72, 0.52, 0.22)]
const BLOOMS: Array[Color] = [Color(0.85, 0.2, 0.22), Color(0.95, 0.75, 0.2), Color(0.92, 0.55, 0.7), Color(0.6, 0.35, 0.8), Color(0.96, 0.94, 0.88)]
const LEAVES := Color(0.24, 0.42, 0.16)
const WASHING: Array[Color] = [Color(0.94, 0.93, 0.88), Color(0.55, 0.68, 0.84), Color(0.85, 0.5, 0.45), Color(0.9, 0.82, 0.5)]
const ROPE := Color(0.62, 0.56, 0.44)
const WASHING_ARM := 0.45
const LINTEL_EAR := 0.16
const LANTERN_OUT := 0.34
const LANTERN_REACH := THICKNESS * 0.5 + LANTERN_OUT
const FLAG_POLE := 1.7
const FLAG_RUN := 4.0
const FLAG_RUN_ROPE := 1.0
const FLAG_RUN_EVERY := 0.4
const FLAG_COLORS := [Color(0.62, 0.12, 0.1), Color(0.14, 0.24, 0.5), Color(0.82, 0.62, 0.18), Color(0.2, 0.38, 0.2)]
const POLE := Color(0.37, 0.26, 0.17)
const FINIAL := Color(0.7, 0.58, 0.3)
const WOOD := Color(0.46, 0.33, 0.21)
const IRON := Color(0.16, 0.15, 0.14)
## By day; at night `glow`.
const GLASS := Color(0.12, 0.17, 0.22)
const PLASTER := Color(0.86, 0.8, 0.68)
const STONE := Color(0.66, 0.61, 0.53)
const MORTAR := Color(0.32, 0.29, 0.25)
const TOP_TONE := Color(0.30, 0.32, 0.37)
const TOP_KINDS: Array[String] = ["cap", "cope", "merlon"]
## How far mortar stands back from the stones' faces.
const JOINT := 0.07
const PLASTER_INSET := 0.02
## (through the wall, tall)
const VERGE := Vector2(THICKNESS + 0.06, 0.24)
## (width, gap)
const BOARD := Vector2(0.2, 0.012)
## (shortest, longest).
const BOARD_RUN := Vector2(0.9, 1.8)
## The most the wall may turn under one straight plank or rail, so its ends keep to a curved face.
const BOARD_TURN := 0.12
const WALK_LANES := 3
## WORN_STEP: width the face is judged in; WORN_TUCK: how far worn stones run on under the plaster round a patch.
const WORN_STEP := 0.2
const WORN_PATCH := Vector2(1.6, 0.9)
const WORN_THICK := (THICKNESS - (PLASTER_INSET + 0.03) * 2.0) / 1.05
const WORN_TUCK := 0.04
const STEP_COURSES := 2
const TREAD := 0.2
const TOP_STEP := 0.35
## Lean-back range per course of a ruin's broken ends.
const RUIN_STEP := Vector2(0.03, 0.22)
const RUIN_LEAN := 1.6
const RUIN_JAG := 0.18
const RUBBLE_PER_METRE := 1.5
const MIN_GAP := 1.0
const MIN_STUB := 0.8
const PERCH_STEP := 0.16

var points: Array[Vector3] = []
var height := 2.6
## How far a loop's foot stands over its lowest ground, filled by its plinth.
var rise := 0.0
var seed := 1
var closed := false
var top := Top.CRENEL
var cover := Cover.OPEN
var fence := false
var finish := Finish.BARE
## 0 to 1.
var wear := 0.0
var foundation := Foundation.STONE
var planks := false
var gable_end := GableEnd.WALL
## Null for an open wall.
var gable: RoofLayout
## (arc length, click height over the foot, Family, size); size 1 is a doorway's.
var openings: Array[Vector4] = []
## (arc length, height over the foot, face ±1)
var lanterns: Array[Vector3] = []
## By arc length.
var flags: Array[float] = []
## See ClutterLayout.
var clutter: Array[Vector4] = []
## (from, to) by arc length.
var ruins: Array[Vector2] = []
## Builds under this one; `resting` stand on it, `joined` adjoin it (docs/design.md, "Buildings on buildings").
var supports: Array[Massing] = []
## `resample` keeps the samples while these match: laying them out reads the ground at every point.
var _sampled_from := []
var resting: Array[Massing] = []
var joined: Array[Massing] = []
## Of `joined`, the older builds: this one's floors yield to their rooms, so joined floors never overlap.
var older: Array[Massing] = []
# Above: what `build` reads (`inputs`); below: what it lays (`adopt`).

## `points` and `rise` may move on while a worker lays them.
var laid_points: Array[Vector3] = []
var laid_rise := 0.0
var samples: Array[Vector3] = []
var lengths: Array[float] = []
## Per sample, the ground's depth below the foot (a wall over a pond stands at the water); none under a loop on builds.
var depths := PackedFloat32Array()
var grounds := PackedFloat32Array()
## Per sample, the plinth's reach below the foot; none over stilts or under a loop on builds. Ivy roots there.
var plinths := PackedFloat32Array()
var bounds := Rect2()
var _segment_cells := {}
var _cells_for: Array[Vector3] = []
var _cells_made := {}
var _feet_for := []
var _feet := Vector2.ZERO
var stones: Array[Dictionary] = []
## Each eaves nest's place by clutter entry, kept since finding it again walks the stones round it.
var _hung := {}
## Stones shorten on a round loop so their outer ends stay closed.
var _stone_scale := 1.0
## Keys: `s`, `half`, `sill`, `head`, `door`, `lights` (panes side by side), `pane` (half-width), `mullion`, `ring`,
## `style` (Family), `size`.
var apertures: Array[Dictionary] = []
## Flames are unit boxes; cloths unit quads off their pole or line.
var flames: Array[Transform3D] = []
var cloths: Array[Dictionary] = []
## -INF and empty but for a house or tower.
var floor_y := -INF
var floor_outline := PackedVector2Array()
## Per course from the foot up.
var breaks: Array[PackedVector2Array] = []
## Bumped by every `build` or `adopt`, so what is worked out from the stones knows it is stale, even across layouts.
static var _laid_count := 0
var laid := 0


static func archway(s: float, size := 1.0) -> Vector4:
	return Vector4(s, 0.0, Family.ARCHWAY, size)


func archways() -> Array:
	return apertures.filter(func(o): return o.style == Family.ARCHWAY).map(func(o): return o.s)


func length() -> float:
	return lengths[-1] if lengths.size() > 0 else 0.0


func point_at(s: float) -> Vector3:
	var i := clampi(lengths.bsearch(s), 0, samples.size() - 1)
	return samples[i]


func spring(size := 1.0) -> float:
	return minf(floor_lift() + SPRING * size, _highest_spring(size))


func _highest_spring(size: float) -> float:
	return height - arch_rise(RING * size, size) - 0.3


func arch_style() -> Dictionary:
	return ARCH_STYLES[1 if TimberFrame.applies(self) else 0]


## The right half of the head, `out` beyond its opening: arcs `[centre, radius, from, to]` about the springing's
## middle, angles from level.
func arch_head(out: float, size := 1.0) -> Array:
	var style := arch_style()
	var turn := deg_to_rad(style.turn)
	var half := ARCH_HALF * size
	var r: float = half * style.shoulder
	var big: float = half * style.crown
	var shoulder := Vector2(half - r, 0.0)
	var crown := shoulder + Vector2(cos(turn), sin(turn)) * (r - big)
	var arcs := [[shoulder, r + out, 0.0, turn]]
	var top := acos(clampf(-crown.x / (big + out), -1.0, 1.0))
	if top - turn > 1e-4:
		arcs.append([crown, big + out, turn, top])
	return arcs


func arch_rise(out: float, size := 1.0) -> float:
	var last: Array = arch_head(out, size)[-1]
	return last[0].y + last[1] * sin(last[3])


## Judged as on level ground: a raised floor only caps the springing at the top, never refuses the arch.
func can_arch(size := 1.0) -> bool:
	return fence or _highest_spring(size) >= minf(0.9, SPRING * size) - 1e-4


## With `ring`, all the arch covers. The one outline both the arch and the wall's cut follow.
func opening(y: float, ring: bool, size := 1.0) -> float:
	if y < threshold():
		return -1.0
	var dy := y - spring(size)
	if dy < 0.0:
		return (ARCH_HALF + (arch_style().jamb if ring else 0.0)) * size
	for arc in arch_head(RING * size if ring else 0.0, size):
		if dy <= arc[0].y + arc[1] * sin(arc[3]):
			return arc[0].x + sqrt(maxf(arc[1] * arc[1] - (dy - arc[0].y) * (dy - arc[0].y), 0.0))
	return -1.0


## `water(x, z)`: the pond surface, below ground off a pond. `revision`: the ground revision both read, 0 if fixed.
func build(ground: Callable, water := Callable(), revision := 0) -> void:
	resample(ground, water, revision)
	laid_points = points.duplicate()
	laid_rise = rise
	if gable != null:
		seat(gable)
	_laid_count += 1
	laid = _laid_count
	stones.clear()
	_hung = {}
	flames.clear()
	cloths.clear()
	apertures.clear()
	floor_y = -INF
	floor_outline.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# Stones under the foot draw from their own stream, so water coming or going leaves the dry stones as they were.
	var wet := RandomNumberGenerator.new()
	wet.seed = hash([seed, "wet"])
	var total := length()
	if total < 0.3:
		return
	_level_floor(ground)
	apertures = openings_for(openings)
	if fence:
		_build_fence(rng)
		_hide()
		return
	_stone_scale = 1.0
	if closed and corners().is_empty():
		_stone_scale = clampf(total / TAU / 3.0, 0.45, 1.0)
	var faces := _face_spans()
	var bays := pillars()
	var pillar_tops := PackedFloat32Array()
	pillar_tops.resize(bays.size())
	var bands := []
	var sink := 0.0
	for d in depths:
		sink = maxf(sink, d)
	var open := stilt_span(foundation, laid_rise) if stilted() else 0.0
	for k in range(-ceili(sink / COURSE), courses()):
		var y0 := k * COURSE
		if y0 < 0.0 and y0 > -open - 1e-4 and not (foundation == Foundation.PILLARS and k == -1):
			continue
		var h := minf(COURSE, height - y0)
		var yc := y0 + h * 0.5
		var spans := [[0.0, total]] if k >= 0 else _over_bed(-y0 - COURSE)
		var lintels := PackedVector2Array()
		for o in apertures:
			if o.style == Family.ARCHWAY:
				# The narrowest across the band, so the band's stones meet the arch everywhere.
				var w := minf(opening(maxf(y0, threshold()), true, o.size), opening(y0 + h, true, o.size))
				if w > 0.0:
					spans = _cut(spans, o.s - w, o.s + w)
			else:
				for cut in light_cuts(o, y0, h):
					spans = _cut(spans, cut.x, cut.y)
				if o.ring == 0.0 and yc > o.head and yc < o.head + COURSE:
					lintels.append(Vector2(o.s - o.half, o.s + o.half))
		var filled := spans
		for l in lintels:
			spans = _cut(spans, l.x - LINTEL_EAR, l.y + LINTEL_EAR)
		for i in bays.size():
			if yc < bays[i].top:
				pillar_tops[i] = y0 + COURSE
				spans = _cut(spans, bays[i].s - bays[i].half, bays[i].s + bays[i].half)
				filled = _cut(filled, bays[i].s - bays[i].half, bays[i].s + bays[i].half)
		for b in breaks[maxi(k, 0)]:
			spans = _cut(spans, b.x, b.y)
			filled = _cut(filled, b.x, b.y)
		var stream := rng if k >= 0 else wet
		stream.seed = hash([seed, "course", k])
		var offset := (0.5 if posmod(k, 2) == 1 else 0.0) * stream.randf_range(0.3, 0.6)
		var worn := _worn(y0)
		var tucked := Array(worn).map(func(t: Vector2) -> Vector2: return t + Vector2(-WORN_TUCK, WORN_TUCK))
		var courses: Array = spans if not plaster_at(y0) else spans.reduce(func(out: Array, sp: Array) -> Array: return out + _pieces(sp[0], sp[1], tucked).filter(func(p: Array) -> bool: return p[2]), [])
		if boards_at(y0):
			courses = []
		for i in courses.size():
			var span: Array = courses[i]
			for face in faces.size():
				var a: float = maxf(span[0], faces[face].x)
				var b: float = minf(span[1], faces[face].y)
				stream.seed = hash([seed, "course", k, i, face])
				_lay_course(a, b, y0, h, offset, stream, THICKNESS if worn.is_empty() else WORN_THICK)
		bands.append([y0, h, filled, breaks[maxi(k, 0)], lintels, worn])
	_lay_mortar(bands)
	if boarded():
		rng.seed = hash([seed, "boards"])
		_lay_cladding(bands, faces, rng)
	for i in bays.size():
		rng.seed = hash([seed, "pillar", i])
		_lay_pillar(bays[i].s, bays[i].half, pillar_tops[i], rng, wet)
	for i in apertures.size():
		rng.seed = hash([seed, "opening", i])
		_lay_opening(apertures[i], rng, -ceili(sink / COURSE) * COURSE)
	rng.seed = hash([seed, "top"])
	if not TimberFrame.applies(self):
		_lay_top(rng)
	elif cover != Cover.ROOF:
		_lay_walk(rng)
	_lay_gables()
	TimberFrame.lay(self)
	var turns := corners()
	for i in turns.size():
		var s := turns[i]
		rng.seed = hash([seed, "pier", i])
		if not TimberFrame.applies(self) and not broken(s, PIER * 0.5):
			var window := _corner_window(s)
			_lay_pier(s, rng, wet, open if foundation == Foundation.POSTS else 0.0, Vector2(window.sill, window.head + COURSE) if not window.is_empty() else Vector2.ZERO)
	if open > 0.0:
		_lay_stilts(open, wet)
	_lay_rubble()
	if lived_in():
		_lay_lived_in()
	for l in lanterns:
		if lantern_fits(l.x, l.y):
			_lay_lantern(l.x, frame_at(l.x).point + Vector3.UP * l.y, _normal(l.x) * l.z, rng)
	var flying := flags.filter(flag_fits)
	for f in flying:
		var parts := flag(flag_foot(f), frame_at(f).tangent, flag_color(seed, f))
		_world(parts.pole, POLE, "pole", f)
		_world(parts.finial, FINIAL, "finial", f)
		cloths.append(parts.cloth)
	for run in flag_runs(flying, length(), closed):
		_lay_flag_run(run.x, run.y)
	for v in clutter:
		var x: Variant = clutter_frame(v, ground)
		if x != null:
			for part in ClutterLayout.parts(v, x, seed):
				_world(part.xform, part.color, part.kind, self.wrap(v.x))
				stones[-1].clutter = true
	_hide()
	_lay_floor()


const BOX: Array[Vector3] = [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5),
	Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5)]
const FIT_CLEAR := 0.005
const MIN_FIT := 0.06
const DECK_PIECES := ["deck", "plank", "board", "mortar"]
const TRIM_STEPS := 7


## In BOX order, ends cut as the stone shader cuts them (`ends`, turning about local y).
static func drawn_corners(st: Dictionary) -> Array[Vector3]:
	var x: Transform3D = st.xform
	var e: Vector2 = st.get("ends", Vector2.ZERO)
	var axis := x.basis.y.normalized()
	var run := (x.basis.x - axis * x.basis.x.dot(axis)).length()
	var out: Array[Vector3] = []
	for c in BOX:
		out.append(x * (c + Vector3.RIGHT * c.z * x.basis.z.length() * tan(e.x if c.x < 0.0 else e.y) / run))
	return out


## A steep slope falls past the faces below a proud stone's outer edge. Gable ends, up to their verge, stay as laid.
func fit_under(r: RoofLayout) -> void:
	if r.flat():
		return
	var kept: Array[Dictionary] = []
	for st in stones:
		var fitted := _fitted(st, r)
		if not fitted.is_empty():
			kept.append(fitted)
	stones = kept


func _fitted(st: Dictionary, r: RoofLayout) -> Dictionary:
	var fitted := st
	if st.y + st.size.y * 0.5 > height + CAP + FIT_CLEAR:
		return fitted
	for i in 4:
		var cut := _cut_under(r, fitted.xform)
		if cut <= 0.0:
			break
		var k := 1.0 - cut
		if k * fitted.size.y < MIN_FIT:
			return {}
		var x: Transform3D = fitted.xform
		fitted = fitted.duplicate()
		fitted.xform = Transform3D(Basis(x.basis.x, x.basis.y * k, x.basis.z), x.origin - x.basis.y * (1.0 - k) * 0.5)
		fitted.y -= fitted.size.y * (1.0 - k) * 0.5
		fitted.size = Vector3(fitted.size.x, fitted.size.y * k, fitted.size.z)
	return fitted


static func _cut_under(r: RoofLayout, x: Transform3D) -> float:
	var cut := 0.0
	for c in BOX:
		var p := x * c
		var over := p.y - r.height_at(p.x, p.z) + FIT_CLEAR
		if over > 0.0:
			cut = maxf(cut, 1.0 if c.y < 0.0 else over / x.basis.y.y)
	return cut


func hide_roof(r: RoofLayout) -> void:
	r.joined = joined.duplicate()
	r.resting = resting.duplicate()
	if joined.is_empty() and resting.is_empty():
		return
	r.tiles.assign(_trimmed(r.tiles, r))
	r.mortar.assign(_trimmed(r.mortar, r))
	r.cloths.assign(r.cloths.filter(func(c: Dictionary) -> bool: return not hides(c.xform.origin)))
	r.keep_coat(func(p: Vector3) -> bool: return not hides(p))
	r.gable_faces = _unhidden(r.gable_faces)
	r.gable_pick = _unhidden(r.gable_pick)
	r.torching_faces = _unhidden(r.torching_faces)
	r.timber_faces = _unhidden(r.timber_faces, r)


func _unhidden(tris: PackedVector3Array, ceiling: RoofLayout = null) -> PackedVector3Array:
	var kept := PackedVector3Array()
	for i in range(0, tris.size(), 3):
		var tri := tris.slice(i, i + 3)
		if ceiling != null:
			# A centroid cut drops half a beam end or board, exposing the bed behind it.
			var polygon := PackedVector3Array()
			for j in 3:
				var a := tri[j]
				var b := tri[(j + 1) % 3]
				var a_hidden := _roof_hidden(a, ceiling)
				var b_hidden := _roof_hidden(b, ceiling)
				if not a_hidden:
					polygon.append(a)
				if a_hidden != b_hidden:
					var outside := b if a_hidden else a
					var inside := a if a_hidden else b
					for k in TRIM_STEPS:
						var mid := outside.lerp(inside, 0.5)
						if _roof_hidden(mid, ceiling):
							inside = mid
						else:
							outside = mid
					polygon.append(outside)
			for j in range(1, polygon.size() - 1):
				kept.append_array(PackedVector3Array([polygon[0], polygon[j], polygon[j + 1]]))
		elif not hides((tri[0] + tri[1] + tri[2]) / 3.0):
			kept.append_array(tri)
	return kept


func _roof_hidden(p: Vector3, r: RoofLayout) -> bool:
	if not r.flat():
		return hides(p)
	var covered := hidden(p, [], resting)
	# Joined decks share one owner; a platform above still tests the piece's actual height.
	p.y = r.height_at(p.x, p.z)
	return covered or hidden(p + Vector3.UP * 0.001, joined, []) or hidden(p - Vector3.UP * 0.001, older, [])


## Deck pieces crossing a joined building's centre line are cut back to it, where its ceiling starts; inside an overlap
## only below the higher ceiling, since the deck above must still overlap to close the roof.
func _trimmed(pieces: Array[Dictionary], r: RoofLayout) -> Array[Dictionary]:
	var over: Array[Massing] = []
	if r.flat():
		over.assign(joined.filter(func(s: Massing) -> bool: return s.closed))
	var kept: Array[Dictionary] = []
	for piece in pieces:
		var x: Transform3D = piece.xform
		if _roof_hidden(x.origin, r):
			continue
		if piece.kind in DECK_PIECES:
			var interior := over.any(func(s: Massing) -> bool: return Massing.encloses(Vector2(x.origin.x, x.origin.z), s.inner))
			var within := func(p: Vector3) -> bool:
				if not interior:
					return over.any(func(s: Massing) -> bool: return Massing.encloses(Vector2(p.x, p.z), s.centre))
				return over.any(func(s: Massing) -> bool:
					var surface := Vector3(p.x, r.height_at(p.x, p.z) + 0.001, p.z)
					var top_y := s.roof.height_at(p.x, p.z) if s.roof != null else s.feet[0] + s.rise
					return s.holds(surface) and p.y < top_y - RoofLayout.CEILING_DROP)
			var cut := x
			# Faces first by their middles, so a piece crossing one wall is cut only across it; then a corner still reaching in
			# takes the smallest cut that clears it.
			for axis in [0, 2]:
				for side in [1.0, -1.0]:
					cut = _cut_back(cut, axis, side, [0.0], within)
			for k in 4:
				var least := cut
				var kept_share := 0.0
				for axis in [0, 2]:
					for side in [1.0, -1.0]:
						var c := _cut_back(cut, axis, side, [-0.5, 0.5], within)
						var share := c.basis[axis].length() / cut.basis[axis].length()
						if c != cut and share > kept_share:
							least = c
							kept_share = share
				if least == cut:
					break
				cut = least
			if cut != x:
				piece = piece.duplicate()
				piece.xform = cut
		kept.append(piece)
	return kept


func _cut_back(x: Transform3D, axis: int, side: float, across: Array, within: Callable) -> Transform3D:
	if not _face_within(x, axis, 0.5 * side, across, within):
		return x
	var clear := 0.0
	var inside := 0.5
	for i in TRIM_STEPS:
		var mid := (clear + inside) * 0.5
		if _face_within(x, axis, mid * side, across, within):
			inside = mid
		else:
			clear = mid
	var b := x.basis
	b[axis] *= 0.5 + clear
	return Transform3D(b, x.origin + x.basis[axis] * side * (clear - 0.5) * 0.5)


func _face_within(x: Transform3D, axis: int, at: float, across: Array, within: Callable) -> bool:
	for o: float in across:
		for y in [-0.5, 0.5]:
			var c := Vector3(0.0, y, 0.0)
			c[axis] = at
			c[2 - axis] = o
			var p := x * c
			if within.call(p):
				return true
	return false


func _hide() -> void:
	if joined.is_empty() and resting.is_empty():
		return
	var kept: Array[Dictionary] = []
	for st in stones:
		var x: Transform3D = st.xform
		if hidden(x.origin, [], resting):
			continue
		# A panel's middle can be inside a room while its top closes the corner above that room's bowed ceiling.
		var bottom := x.origin.y - x.basis.y.y * 0.5
		for other in joined:
			if not other.holds(x.origin):
				continue
			var ceiling := other.feet[0] + other.rise
			if other.roof != null:
				ceiling = INF
				var highest := other.roof.height_at(x.origin.x, x.origin.z)
				var framing := INF
				for p in drawn_corners(st):
					ceiling = minf(ceiling, other.roof.height_at(p.x, p.z))
					highest = maxf(highest, other.roof.height_at(p.x, p.z))
					framing = minf(framing, other.roof.rafter_bottom(p.x, p.z))
				# Standing above a joined flat ceiling, this wall carries on down past it as the beam its rafters end against.
				if closed and other.roof.flat() and highest < roof_base() - 0.001:
					ceiling = framing
			bottom = maxf(bottom, ceiling)
		var top_y := x.origin.y + x.basis.y.y * 0.5
		if bottom >= top_y:
			continue
		if bottom > x.origin.y - x.basis.y.y * 0.5:
			st = st.duplicate()
			var share := (top_y - bottom) / x.basis.y.y
			st.xform = Transform3D(Basis(x.basis.x, x.basis.y * share, x.basis.z), x.origin + x.basis.y * (1.0 - share) * 0.5)
			st.y += st.size.y * (1.0 - share) * 0.5
			st.size.y *= share
		kept.append(st)
	stones.assign(kept)
	flames.assign(flames.filter(func(x: Transform3D) -> bool: return not hides(x.origin)))
	cloths.assign(cloths.filter(func(c: Dictionary) -> bool: return not hides(c.xform.origin)))


func courses() -> int:
	return maxi(1, ceili(height / COURSE - 0.00001))


## A ruin draws from its own stream, so breaking one stretch leaves another's steps as they were.
func _break() -> void:
	var n := courses()
	breaks.resize(n)
	for k in n:
		breaks[k] = PackedVector2Array()
	for r in ruins:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed, snappedf(r.x, 0.01)])
		var lean := Vector2.ZERO
		var edge := r
		for k in n:
			edge = Vector2(minf(edge.x, r.x - lean.x - rng.randf() * RUIN_JAG), maxf(edge.y, r.y + lean.y + rng.randf() * RUIN_JAG))
			breaks[k].append(edge)
			lean = (lean + Vector2(rng.randf_range(RUIN_STEP.x, RUIN_STEP.y), rng.randf_range(RUIN_STEP.x, RUIN_STEP.y))).min(Vector2.ONE * RUIN_LEAN)


## Judged at the top, where a ruin is widest.
func broken(s: float, margin := 0.0) -> bool:
	if breaks.is_empty():
		return false
	for b in breaks[-1]:
		if absf(offset(s, (b.x + b.y) * 0.5)) < (b.y - b.x) * 0.5 + margin:
			return true
	return false


func standing(s: float) -> float:
	for k in breaks.size():
		for b in breaks[k]:
			if absf(offset(s, (b.x + b.y) * 0.5)) < (b.y - b.x) * 0.5:
				return k * COURSE
	return height


func floored() -> bool:
	return closed and not fence and cover != Cover.OPEN and points.size() > 2


func floor_under(p: Vector3) -> float:
	return floor_y if floor_y <= p.y + SINK and Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), floor_outline) else -INF


func walk_under(p: Vector3) -> float:
	var best := -INF
	var at := Vector2(p.x, p.z)
	if fence or (closed and cover != Cover.OPEN) or samples.size() < 2 or not bounds.grow(THICKNESS).has_point(at):
		return best
	var cells := segment_cells()
	var c := Vector2i((at / PathLayout.CELL).floor())
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for i: int in cells.get(c + Vector2i(dx, dz), []):
				var foot := _foot(at, i)
				if foot.y > THICKNESS * 0.5:
					continue
				var t := foot.x
				var stands := standing(lerpf(lengths[i], lengths[i + 1], t))
				if stands <= 0.0:
					continue
				var top := lerpf(samples[i].y, samples[i + 1].y, t) + stands + (top_rise() if stands >= height else 0.0)
				if top <= p.y + SINK and top > best and not hides(Vector3(p.x, top - SINK, p.z)):
					best = top
	return best


func feet() -> Vector2:
	var key := [samples, depths]
	if key != _feet_for:
		_feet_for = [samples.duplicate(), depths.duplicate()]
		var deepest := 0.0
		for d in depths:
			deepest = maxf(deepest, d)
		_feet = Vector2(INF, -INF)
		for q in samples:
			_feet = Vector2(minf(_feet.x, q.y - deepest), maxf(_feet.y, q.y))
	return _feet


func top_rise() -> float:
	return (COPE_TALL.x + COPE_TALL.y) * 0.5 if top == Top.COPE and cover != Cover.ROOF and not fence and not TimberFrame.applies(self) else CAP


func floor_hit(origin: Vector3, dir: Vector3) -> float:
	if dir.y >= 0.0:
		return INF
	var t := (floor_y - origin.y) / dir.y
	var at := origin + dir * t
	return t if t >= 0.0 and Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), floor_outline) else INF


func _level_floor(ground: Callable) -> void:
	var outer := _floor_bounds()
	if outer.is_empty():
		return
	var foot := samples[0].y + SINK
	floor_outline = Geometry2D.offset_polygon(ground_line(laid_points), -THICKNESS * 0.5)[0]
	var lowest := foot
	if supports.is_empty():
		lowest = maxf(lowest, _highest_ground(outer, ground))
	floor_y = lowest


## -INF for an open wall, whose arch opens all the way down, to a pond's bed.
func threshold() -> float:
	return floor_y - samples[0].y if floor_y != -INF else -INF


## A door's height counts from here, so a floor raised over higher ground inside takes nothing from it.
func floor_lift() -> float:
	return floor_y - samples[0].y - SINK if floor_y != -INF else 0.0


func half_thickness() -> float:
	return 0.1 if fence else THICKNESS * 0.5


static func ground_line(points: Variant) -> PackedVector2Array:
	var line := PackedVector2Array()
	for p: Vector3 in points:
		line.append(Vector2(p.x, p.z))
	return line


func _floor_bounds() -> PackedVector2Array:
	if not floored() or samples.is_empty() or laid_points.size() < 3:
		return PackedVector2Array()
	var line := ground_line(laid_points)
	var inner := Geometry2D.offset_polygon(line, -THICKNESS * 0.5)
	var outer := Geometry2D.offset_polygon(line, FLOOR_REACH)
	return outer[0] if not inner.is_empty() and not outer.is_empty() else PackedVector2Array()


## Its bed reaches down to the foot so it reads as a step at the door.
func _lay_floor() -> void:
	if floor_y == -INF:
		return
	var foot := samples[0].y + SINK
	var outer := _floor_bounds()
	var line := ground_line(laid_points)
	var along := (line[1] - line[0]).normalized()
	var across := along.orthogonal()
	var lo := INF
	var hi := -INF
	for q in outer:
		lo = minf(lo, q.dot(across))
		hi = maxf(hi, q.dot(across))
	var rng := RandomNumberGenerator.new()
	var row := 0
	var z := lo
	while z < hi - 0.01:
		rng.seed = hash([seed, "floor", 0, row])
		var depth := minf(PLANK.x if planks else FLAG.z, hi - z)
		var near := _chord(outer, along, across, z)
		var far := _chord(outer, along, across, z + depth)
		var a := maxf(near.x, far.x)
		var b := minf(near.y, far.y)
		var x := a - (rng.randf_range(0.0, PLANK.w) if planks else (FLAG.x * 0.5 if row % 2 == 1 else 0.0))
		while x < b - 0.01:
			var size := rng.randf_range(PLANK.z, PLANK.w) if planks else FLAG.x
			var middle := across * (z + depth * 0.5)
			var open := _floor_open(along, middle, maxf(x, a), minf(x + size, b), floor_y - (PLANK.y if planks else FLAG.y) * 0.5)
			if open.y - open.x > 0.05:
				_lay_floor_piece(along * (open.x + open.y) * 0.5 + middle, Vector2(open.y - open.x, depth), floor_y, foot - SINK, along, rng)
			x += size
		z += depth
		row += 1


## The bed's top lies BED_DEPTH under the pieces' tops: deeper, a joint seen off straight down shows its pieces' sides,
## lit as faces open to the horizon, and reads lighter than one seen from overhead.
func _lay_floor_piece(at: Vector2, size: Vector2, top_y: float, bottom: float, along: Vector2, rng: RandomNumberGenerator) -> void:
	var thick := PLANK.y if planks else FLAG.y
	var centre := Vector3(at.x, top_y - thick * 0.5, at.y)
	var x := Vector3(along.x, 0.0, along.y)
	var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP))
	var color := WOOD * rng.randf_range(0.78, 1.05) if planks else stone_color(rng) * rng.randf_range(0.86, 0.98)
	var piece := Transform3D(basis.scaled_local(Vector3(size.x - FLOOR_JOINT, thick, size.y - FLOOR_JOINT)), centre)
	stones.append({"xform": piece, "color": color, "kind": "plank" if planks else "flagstone", "s": 0.0, "y": 0.0, "size": Vector3(size.x, thick, size.y), "ao": 0.9, "variant": 0})
	var bed_top := top_y - BED_DEPTH
	var bed := Transform3D(basis.scaled_local(Vector3(size.x, bed_top - bottom, size.y)), Vector3(centre.x, (bed_top + bottom) * 0.5, centre.z))
	var bed_color := color * FLOOR_UNDERSIDE if not planks and not supports.is_empty() else MORTAR
	stones.append({"xform": bed, "color": bed_color, "kind": "bed", "s": 0.0, "y": 0.0, "size": bed.basis.get_scale(), "ao": 0.8, "variant": 0})


static func floor_stamps(points: Array) -> PackedVector4Array:
	var out := PackedVector4Array()
	var inside := Geometry2D.offset_polygon(ground_line(points), -BARE_STAMP.y)
	if inside.is_empty():
		return out
	var box := Rect2(inside[0][0], Vector2.ZERO)
	for q in inside[0]:
		box = box.expand(q)
	for j in range(floori(box.position.y / BARE_STAMP.x), ceili(box.end.y / BARE_STAMP.x) + 1):
		for i in range(floori(box.position.x / BARE_STAMP.x), ceili(box.end.x / BARE_STAMP.x) + 1):
			var q := Vector2(i, j) * BARE_STAMP.x
			if Geometry2D.is_point_in_polygon(q, inside[0]):
				out.append(Vector4(q.x, q.y, BARE_STAMP.z, BARE_STAMP.w))
	for q in inside[0]:
		out.append(Vector4(q.x, q.y, BARE_STAMP.z, BARE_STAMP.w))
	return out


## A piece reaching into an older room is cut at its edge: that room's floor reaches out under its cut-away wall by more
## than half a row's depth, so the two floors meet with no gap.
func _floor_open(along: Vector2, row: Vector2, x0: float, x1: float, y: float) -> Vector2:
	var hidden_at := func(x: float) -> bool:
		var q := along * x + row
		return hidden(Vector3(q.x, y, q.y), older, resting)
	var start: bool = hidden_at.call(x0)
	if start == hidden_at.call(x1):
		return Vector2(x0, x0) if start else Vector2(x0, x1)
	var lo := x0
	var hi := x1
	for i in 16:
		var mid := (lo + hi) * 0.5
		if hidden_at.call(mid) == start:
			lo = mid
		else:
			hi = mid
	return Vector2(hi, x1) if start else Vector2(x0, lo)


## A row on the outline's first edge needs that edge's own extent: the wall over it is cut away where a house joins.
static func _chord(outline: PackedVector2Array, along: Vector2, across: Vector2, z: float) -> Vector2:
	var out := Vector2(INF, -INF)
	for i in outline.size():
		var p := outline[i]
		var q := outline[(i + 1) % outline.size()]
		var zp := p.dot(across) - z
		var zq := q.dot(across) - z
		if (zp > 0.0 and zq > 0.0) or (zp < 0.0 and zq < 0.0):
			continue
		for x in [p.dot(along), q.dot(along)] if zp == zq else [p.lerp(q, zp / (zp - zq)).dot(along)]:
			out = Vector2(minf(out.x, x), maxf(out.y, x))
	return out


## The ground's triangles are flat, so its corners, edge crossings and the grid points within bound it.
static func _highest_ground(outline: PackedVector2Array, ground: Callable) -> float:
	var top := -INF
	var box := Rect2(outline[0], Vector2.ZERO)
	for k in outline.size():
		var a := outline[k] / Terrain.STEP
		var b := outline[(k + 1) % outline.size()] / Terrain.STEP
		box = box.expand(outline[k])
		var along: Array[float] = [0.0]
		for ends in [Vector2(a.x, b.x), Vector2(a.y, b.y), Vector2(a.x + a.y, b.x + b.y)]:
			if ends.x != ends.y:
				for n in range(ceili(minf(ends.x, ends.y)), floori(maxf(ends.x, ends.y)) + 1):
					along.append((n - ends.x) / (ends.y - ends.x))
		for t in along:
			var q := a.lerp(b, t) * Terrain.STEP
			top = maxf(top, Terrain.drawn(q.x, q.y, ground))
	for j in range(floori(box.position.y / Terrain.STEP), ceili(box.end.y / Terrain.STEP) + 1):
		for i in range(floori(box.position.x / Terrain.STEP), ceili(box.end.x / Terrain.STEP) + 1):
			var q := Vector2(i, j) * Terrain.STEP
			if Geometry2D.is_point_in_polygon(q, outline):
				top = maxf(top, ground.call(q.x, q.y))
	return top


func _lay_rubble() -> void:
	for r in ruins:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed, snappedf(r.x, 0.01), 1])
		for i in mini(int((r.y - r.x) * RUBBLE_PER_METRE * minf(height, 3.0) / 3.0) + 2, 40):
			var s := rng.randf_range(r.x, r.y)
			var size := Vector3(rng.randf_range(0.3, 0.6), rng.randf_range(0.16, 0.28), rng.randf_range(0.24, 0.42))
			var st := _stone(s, size.y * 0.4 - depth_at(s), size, rng, "rubble", 0.45, rng.randf_range(-0.5, 0.5))
			st.xform.origin += _normal(s) * rng.randf_range(-0.8, 0.8)
			stones.append(st)


## `lo` <= `hi`, unwrapped round a `closed` loop. Nothing standing is [Vector2(0, total)].
static func ruins_after(ruins: Array[Vector2], total: float, closed: bool, lo: float, hi: float) -> Array[Vector2]:
	if hi - lo < MIN_GAP:
		var mid := (lo + hi) * 0.5
		lo = mid - MIN_GAP * 0.5
		hi = mid + MIN_GAP * 0.5
	var out: Array[Vector2] = []
	var spans: Array[Vector2] = ruins.duplicate()
	if closed:
		if hi - lo >= total:
			out.append(Vector2(0.0, total))
			return out
		var a := fposmod(lo, total)
		var b := a + hi - lo
		spans.append(Vector2(a, minf(b, total)))
		if b > total:
			spans.append(Vector2(0.0, b - total))
	else:
		spans.append(Vector2(maxf(lo, 0.0), minf(hi, total)))
	spans.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var start := 0.0
	for sp in spans:
		if sp.x - start < MIN_STUB and not out.is_empty():
			out[-1].y = maxf(out[-1].y, sp.y)
		elif sp.x - start < MIN_STUB and not closed:
			out.append(Vector2(0.0, sp.y))
		else:
			out.append(sp)
		start = out[-1].y
	if out.is_empty():
		return out
	if not closed and total - out[-1].y < MIN_STUB:
		out[-1].y = total
	if closed and out.size() > 1 and total - out[-1].y + out[0].x < MIN_STUB:
		out[0].x = 0.0
		out[-1].y = total
	var left := total
	for sp in out:
		left -= sp.y - sp.x
	if left < MIN_STUB:
		out.assign([Vector2(0.0, total)])
	return out


func post_lantern_at(s: float) -> Vector3:
	return frame_at(s).point + Vector3.UP * (FENCE_HEIGHT + 0.25)


func flag_foot(s: float) -> Vector3:
	return frame_at(s).point + Vector3.UP * (height + CAP)


## Points to face +1, as ivy and lanterns call it.
func _normal(s: float) -> Vector3:
	return frame_at(s).tangent.cross(Vector3.UP)


func inner_side() -> float:
	if not closed or cover == Cover.OPEN:
		return 0.0
	var area := 0.0
	for i in samples.size():
		var a := samples[i]
		var b := samples[(i + 1) % samples.size()]
		area += a.x * b.z - b.x * a.z
	return signf(area)


func opening_for(w: Vector4) -> Dictionary:
	var c := COURSE
	var k := w.w
	var family := int(w.z)
	if family == Family.ARCHWAY:
		return {"s": w.x, "half": ARCH_HALF * k, "pane": ARCH_HALF * k, "mullion": 0.0, "ring": 0.0, "sill": maxf(threshold(), 0.0), "head": spring(k) + arch_rise(0.0, k) + arch_style().ring * k, "door": true, "style": Family.ARCHWAY, "lights": 1, "size": k}
	var light: Dictionary = LIGHTS[family]
	var s := w.x
	if family == Family.CORNER:
		var corner := corner_near(s)
		s = corner if not is_nan(corner) else s
	var ring := WINDOW_RING * k if light.ring else 0.0
	var mullion: float = light.mullion * k
	if opens_door(w):
		var bottom := maxf(threshold(), 0.0)
		return {"s": s, "half": DOOR_HALF * k, "pane": DOOR_HALF * k, "mullion": mullion, "ring": ring, "sill": bottom, "head": minf(roundf((bottom + DOOR_TALL * k) / c) * c, floorf((height + 0.01) / c) * c - c), "door": true, "lights": 1, "style": family, "size": k}
	var sill := maxf(roundf((w.y - light.tall * 0.5) / c), roundf(DOOR_SILL / c)) * c
	var tall: float = light.tall * k if family == Family.ROUND else roundf(light.tall * k / c) * c
	return {"s": s, "half": light.half * k, "pane": light.half * k, "mullion": mullion, "ring": ring, "sill": sill, "head": sill + tall, "door": false, "lights": 1, "style": family, "size": k}


static func opens_door(w: Vector4) -> bool:
	return int(w.z) == Family.ARCHWAY or LIGHTS[int(w.z)].door and w.y - LIGHTS[int(w.z)].tall * 0.5 < DOOR_SILL


static func lowest(family: int, size := 1.0) -> float:
	return DOOR_SILL + LIGHTS[family].tall * size * 0.5


func corner_near(s: float) -> float:
	var turns := corners()
	for c in turns:
		if _corner(c, turns) and absf(offset(s, c)) < PIER * 0.5:
			return c
	return NAN


static func light_centres(o: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in o.lights:
		out.append(o.s - o.half + o.pane * (2 * i + 1) + o.mullion * i)
	return out


func openings_for(placed: Array[Vector4]) -> Array[Dictionary]:
	placed = placed.duplicate()
	for a in _water_arches():
		if placed.size() < Commands.MAX_FITTINGS:
			placed.append(archway(a))
	var courses_of := {}
	var fused: Array[Dictionary] = []
	for w in placed:
		var o := opening_for(w)
		if o.style in [Family.ARCHWAY, Family.CORNER]:
			fused.append(o)
			continue
		var key := Vector3i(roundi(o.sill * 100.0), roundi(o.size * 100.0), o.style)
		courses_of.get_or_add(key, []).append(o)
	for row in courses_of.values():
		fused.append_array(_fuse(row))
	fused.sort_custom(func(a, b): return a.style == Family.ARCHWAY if (a.style == Family.ARCHWAY) != (b.style == Family.ARCHWAY) else a.s < b.s)
	var out: Array[Dictionary] = []
	for o in fused:
		if _opening_fits(o, out):
			out.append(o)
	out.sort_custom(func(a, b): return a.s < b.s)
	return out


func _fuse(row: Array) -> Array[Dictionary]:
	row.sort_custom(func(a, b): return a.s < b.s)
	if closed and row.size() > 1:
		# Round a loop, the row is read from just past its widest gap, so no run of openings straddles the seam.
		var n := row.size()
		var cut := 0
		var widest := -1.0
		for i in n:
			var gap := fposmod(row[(i + 1) % n].s - row[i].s, length())
			if gap > widest:
				widest = gap
				cut = (i + 1) % n
		row = row.slice(cut) + row.slice(0, cut)
	var out: Array[Dictionary] = []
	var first := 0.0
	var last := 0.0
	for o in row:
		var u: float = row[0].s + fposmod(o.s - row[0].s, length()) if closed else o.s
		if out.is_empty() or u - last >= FUSE * o.size:
			out.append(o)
			first = u
		else:
			var into: Dictionary = out[-1]
			into.lights += 1
			into.s = self.wrap((first + u) * 0.5)
			into.half = into.lights * into.pane + (into.lights - 1) * into.mullion * 0.5
		last = u
	return out


func _opening_fits(o: Dictionary, others: Array[Dictionary]) -> bool:
	var arched: bool = o.style == Family.ARCHWAY
	if arched:
		if not can_arch(o.size):
			return false
	elif fence or o.head + COURSE > height + 0.01 or (o.door and roundf(DOOR_TALL * o.size / COURSE) * COURSE + COURSE > height + 0.01):
		return false
	var edge := _edge(o)
	var side: float = o.half + edge + PIER * 0.5
	var end: float = o.half + edge + END_CLEAR if arched else side
	if broken(o.s, o.half + edge) or (not closed and (o.s < end or o.s > length() - end)):
		return false
	# Finding an open wall's bends walks every sample of it, and an arch in one needs none.
	if closed or not arched:
		var turns := corners()
		var own := func(c: float) -> bool: return o.style == Family.CORNER and absf(offset(o.s, c)) < 1e-3 and _corner(c, turns)
		if o.style == Family.CORNER and (TimberFrame.applies(self) or not turns.any(own)):
			return false
		if not turns.all(func(c): return own.call(c) or absf(offset(o.s, c)) > side):
			return false
	return others.all(func(e): return absf(offset(o.s, e.s)) >= o.half + e.half + edge + _edge(e) or (not arched and e.style != Family.ARCHWAY and (o.sill > e.head + e.ring + COURSE * 0.5 or e.sill > o.head + o.ring + COURSE * 0.5)))


static func _edge(o: Dictionary) -> float:
	return RING * o.size if o.style == Family.ARCHWAY else maxf(o.ring, LINTEL_EAR)


static func light_half(o: Dictionary, y: float, ring := false) -> float:
	var r: float = o.pane + (o.ring if ring else 0.0)
	if o.style == Family.ROUND:
		var dy: float = y - (o.sill + o.head) * 0.5
		return sqrt(r * r - dy * dy) if absf(dy) <= r else -1.0
	if y < o.sill or y > o.head + (o.ring if ring else 0.0):
		return -1.0
	if o.style != Family.ARCHED:
		return r
	var up: float = y - (o.head - o.pane)
	if up <= 0.0:
		return o.pane
	return sqrt(r * r - up * up) if up <= r else -1.0


## A ringed light's gap the level cut leaves is closed by the infill behind its ring (`_lay_ringed`).
static func light_cuts(o: Dictionary, y0: float, h: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var yc := y0 + h * 0.5
	if o.ring == 0.0:
		if yc > o.sill and yc < o.head:
			if o.style == Family.SLIT:
				for c in light_centres(o):
					out.append(Vector2(c - o.pane, c + o.pane))
			else:
				out.append(Vector2(o.s - o.half, o.s + o.half))
		return out
	var widest := -1.0
	var narrowest := INF
	for i in 9:
		var y := y0 + 0.001 + (h - 0.002) * i / 8.0
		widest = maxf(widest, light_half(o, y))
		narrowest = minf(narrowest, light_half(o, y, true))
	if o.style == Family.ROUND:
		var middle: float = (o.sill + o.head) * 0.5
		if middle > y0 and middle < y0 + h:
			widest = maxf(widest, o.pane)
	var w := maxf(widest, narrowest)
	if w > 0.0:
		for c in light_centres(o):
			out.append(Vector2(c - w, c + w))
	return out


func opening_at(s: float, y: float, arch_inset := 0.0) -> Dictionary:
	return _opening_in(apertures, s, y, arch_inset)


func open_at(s: float, y: float) -> bool:
	for o in apertures:
		if o.style == Family.ARCHWAY and absf(offset(s, o.s)) < (ARCH_HALF if fence else opening(y, false, o.size)):
			return true
	return false


func _opening_in(list: Array[Dictionary], s: float, y: float, arch_inset := 0.0) -> Dictionary:
	for o in list:
		if absf(offset(s, o.s)) < (opening(y, false, o.size) - arch_inset if o.style == Family.ARCHWAY else o.half + 0.05) and y > o.sill - 0.05 and y < o.head + 0.05:
			return o
	return {}


## An arch is placed at the foot but opens from the floor, which may stand above it, so it is found at its sill.
func _opening_of(list: Array[Dictionary], w: Vector4) -> Dictionary:
	return _opening_in(list, w.x, opening_for(w).sill if int(w.z) == Family.ARCHWAY else w.y)


func opening_fits(at: Vector4, placed: Array[Vector4]) -> bool:
	var before := openings_for(placed)
	var after := placed.duplicate()
	after.append(at)
	var now := openings_for(after)
	var added := _opening_of(now, at)
	return not added.is_empty() and added.style == at.z and placed.all(func(e): return _opening_of(before, e).is_empty() or not _opening_of(now, e).is_empty())


## To a hundredth; `at` must open at its own size.
func largest_fit(at: Vector4, placed: Array[Vector4], upto: float) -> float:
	var sized := func(k: float) -> Vector4: return Vector4(at.x, at.y, at.z, k)
	if opening_fits(sized.call(upto), placed):
		return upto
	if not opening_fits(at, placed):
		return NAN
	var lo := at.w
	for i in 12:
		var mid := (lo + upto) * 0.5
		if opening_fits(sized.call(mid), placed):
			lo = mid
		else:
			upto = mid
	return floorf(lo * 100.0) / 100.0


## None where the floor stands so high over the foot that `opens_door` reads a press there as a window's.
func path_doors(s: float, span: float, placed: Array[Vector4]) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var door := Vector4(s, maxf(threshold(), 0.0), Family.COTTAGE, MIN_SIZE)
	var standing: Array[Dictionary] = []
	standing.assign(openings_for(placed).filter(func(o: Dictionary) -> bool: return o.door))
	if not opens_door(door) or placed.size() >= Commands.MAX_FITTINGS or not _opening_of(standing, door).is_empty():
		return out
	var widest := largest_fit(door, placed, maxf(span / _door_width(1), MIN_SIZE))
	if is_nan(widest):
		return out
	var mullion: float = LIGHTS[Family.COTTAGE].mullion
	var lights := maxi(roundi((span / widest + mullion) / (DOOR_HALF * 2.0 + mullion)), 1)
	for n in range(lights, 1, -1):
		var k := maxf(floorf(minf(widest, span / _door_width(n)) * 100.0) / 100.0, MIN_SIZE)
		var run: Array[Vector4] = []
		# Lights nearer than FUSE fuse into one opening as wide as `_fuse` makes them, centred between the outermost.
		for i in n:
			run.append(Vector4(self.wrap(s + (i - (n - 1) * 0.5) * FUSE * k * 0.5), door.y, door.z, k))
		var rest: Array[Vector4] = placed + run.slice(1)
		var all: Array[Vector4] = placed + run
		if all.size() <= Commands.MAX_FITTINGS and opening_fits(run[0], rest) and _opening_in(openings_for(all), s, door.y).get("lights", 0) == n:
			return run
	door.w = widest
	out.append(door)
	return out


static func _door_width(lights: int) -> float:
	return lights * DOOR_HALF * 2.0 + (lights - 1) * LIGHTS[Family.COTTAGE].mullion


func placed_at(click: Vector4, placed: Array[Vector4]) -> int:
	var made := openings_for(placed)
	var o := _opening_of(made, click)
	var near := -1
	if o.is_empty():
		return near
	for i in placed.size():
		var e := placed[i]
		if _opening_of(made, e) == o and (near < 0 or absf(offset(e.x, click.x)) < absf(offset(placed[near].x, click.x))):
			near = i
	return near


func lantern_fits(s: float, y: float) -> bool:
	if fence:
		return true
	if broken(s, 0.3) or y < 0.9 or y > height - 0.2 or (not closed and (s < PIER or s > length() - PIER)):
		return false
	return apertures.all(func(o): return absf(offset(s, o.s)) > o.half + _edge(o) + (0.2 if o.style == Family.ARCHWAY else 0.15) or y > o.head + COURSE + 0.3 or y < o.sill - 0.3)


func flag_fits(s: float) -> bool:
	return not fence and cover != Cover.ROOF and not broken(s, 0.3) and (closed or (s > PIER * 0.5 and s < length() - PIER * 0.5))


func _lay_opening(o: Dictionary, rng: RandomNumberGenerator, bottom: float) -> void:
	match o.style:
		Family.ARCHWAY:
			_lay_arch(o.s, o.size, rng, maxf(bottom, threshold()))
			return
		Family.CORNER:
			_lay_corner_window(o, rng)
			return
	if o.ring > 0.0:
		_lay_ringed(o, rng)
		return
	var s: float = o.s
	var half: float = o.half
	var tall: float = o.head - o.sill
	var c := COURSE
	var wood := boarded()
	_part(s, o.head + c * 0.5, Vector3(half * 2.0 + LINTEL_EAR * 2.0, c, THICKNESS * 1.04), _trim(wood, rng), rng, "beam" if wood else "lintel")
	if not o.door:
		_lay_sill(o, rng)
	if o.style == Family.SLIT:
		_lay_slit(o, rng)
		return
	# The surround's back lies on a plaster wall's face, and its front stands proud of a stone one's.
	var back := THICKNESS * 0.5 - PLASTER_INSET
	var front := THICKNESS * 0.5 + 0.025
	var casing := WOOD if wood else PLASTER
	for face in [-1.0, 1.0]:
		for edge in [-1.0, 1.0]:
			_part(s + edge * (half + 0.09), o.sill + tall * 0.5, Vector3(0.18, tall, front - back), casing * rng.randf_range(0.94, 1.02), rng, "frame" if wood else "plaster", face * (back + front) * 0.5)
		if not o.door:
			_part(s, o.sill - 0.1, Vector3(half * 2.0 + 0.36, 0.14, front - back), casing * rng.randf_range(0.94, 1.02), rng, "frame" if wood else "plaster", face * (back + front) * 0.5)
	var light: float = o.pane * 2.0
	var centres := light_centres(o)
	for i in centres.size():
		var at := centres[i]
		if i > 0:
			_part(at - light * 0.5 - o.mullion * 0.5, o.sill + tall * 0.5, Vector3(o.mullion, tall, THICKNESS * 0.9), stone_color(rng), rng, "mullion")
		if o.door:
			_lay_door(at, o.sill, light, tall, rng)
		else:
			_lay_window(at, o.sill, light, tall, rng)


func _lay_slit(o: Dictionary, rng: RandomNumberGenerator) -> void:
	var tall: float = o.head - o.sill
	var c := COURSE
	var dressed := stone_color(rng) * 1.12
	for at in light_centres(o):
		_part(at, o.sill + tall * 0.5, Vector3(o.pane * 2.0, tall, 0.02), glow() * rng.randf_range(0.9, 1.1), rng, "glass", inner_side() * THICKNESS * 0.3)
		for k in roundi(tall / c):
			for side in [-1.0, 1.0]:
				var w := 0.3 if (k + (1 if side > 0.0 else 0)) % 2 == 0 else 0.18
				_part(at + side * (o.pane + w * 0.5), o.sill + c * (k + 0.5), Vector3(w, c - 0.02, THICKNESS * 1.03), dressed * rng.randf_range(0.95, 1.04), rng, "lintel")


func _lay_sill(o: Dictionary, rng: RandomNumberGenerator) -> void:
	var wood := boarded()
	_part(o.s, o.sill + 0.04, Vector3(o.half * 2.0 + 0.16, 0.08, THICKNESS + 0.1), _trim(wood, rng), rng, "beam" if wood else "sill")


static func _trim(wood: bool, rng: RandomNumberGenerator) -> Color:
	return TimberFrame.OAK * rng.randf_range(0.88, 1.12) if wood else stone_color(rng) * 1.05


func glow() -> Color:
	return Palette.SWATCHES[Palette.Element.GLOW][0] if floored() else Color.BLACK


func _lay_window(s: float, sill: float, w: float, tall: float, rng: RandomNumberGenerator, out := -THICKNESS * 0.12, face := INF) -> void:
	for p in casement(w, tall, rng, glow()):
		_part(s + p.at.x, sill + tall * 0.5 + p.at.y, p.size, p.color, rng, p.kind, out, 0.0, face)


## Each piece's `at` is (along the face, up) from the middle.
static func casement(w: float, tall: float, rng: RandomNumberGenerator, glow: Color) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"at": Vector2.ZERO, "size": Vector3(w - 0.02, tall - 0.02, 0.02), "color": glow * rng.randf_range(0.9, 1.1), "kind": "glass"}]
	for edge in [-1.0, 1.0]:
		out.append({"at": Vector2(edge * (w * 0.5 - 0.03), 0.0), "size": Vector3(0.06, tall, 0.08), "color": WOOD * rng.randf_range(0.85, 1.05), "kind": "frame"})
		out.append({"at": Vector2(0.0, edge * (tall * 0.5 - 0.03)), "size": Vector3(w - 0.12, 0.06, 0.08), "color": WOOD * rng.randf_range(0.85, 1.05), "kind": "frame"})
	out.append({"at": Vector2.ZERO, "size": Vector3(0.035, tall, 0.05), "color": WOOD, "kind": "frame"})
	out.append({"at": Vector2(0.0, tall * 0.08), "size": Vector3(w, 0.035, 0.05), "color": WOOD, "kind": "frame"})
	return out


func _lay_door(s: float, sill: float, w: float, tall: float, rng: RandomNumberGenerator) -> void:
	var planks := maxi(3, roundi(w / 0.2))
	var back := -THICKNESS * 0.15
	for i in planks:
		var at := s - w * 0.5 + w * (i + 0.5) / planks
		_part(at, sill + tall * 0.5, Vector3(w / planks - 0.012, tall - 0.02, 0.06), WOOD * rng.randf_range(0.75, 1.1), rng, "door", back)
	for y: float in [sill + 0.4, sill + tall - 0.45]:
		_part(s, y, Vector3(w - 0.08, 0.06, 0.08), IRON, rng, "iron", back)


func _lay_ringed(o: Dictionary, rng: RandomNumberGenerator) -> void:
	var round: bool = o.style == Family.ROUND
	var r: float = o.pane
	var ring: float = o.ring
	var depth := THICKNESS + RING_PROUD * 2.0
	var fill := _infill_depth()
	var wedge := {"kind": "voussoir", "jitter": 0.0}
	var mortared := _infill_kind()
	var middle: float = (o.sill + o.head) * 0.5 if round else o.head - r
	var tint := rng.randf_range(0.92, 1.06)
	if not o.door and not round:
		_lay_sill(o, rng)
	for at in light_centres(o):
		var arc := [Vector2.ZERO, r, -PI * 0.5 if round else 0.0, PI * 0.5]
		var pieces := 5 if round else 3
		for side in [-1.0, 1.0]:
			for j in pieces:
				var st := _voussoir(at, middle, side, arc, lerpf(arc[2], arc[3], float(j) / pieces), lerpf(arc[2], arc[3], float(j + 1) / pieces), 0.0, ring, depth, 0.012, wedge, rng)
				st.color = stone_color(rng) * tint
				stones.append(st)
				var high := sin(lerpf(arc[2], arc[3], float(j + 1) / pieces))
				var reach := ring + COURSE if high < 0.1 else minf(ring + COURSE, (height - middle) / high - r)
				_lay_infill(_voussoir(at, middle, side, arc, lerpf(arc[2], arc[3], float(j) / pieces), lerpf(arc[2], arc[3], float(j + 1) / pieces), 0.01, reach, fill, -0.02, mortared, rng))
		if o.door:
			_lay_round_door(at, o, middle, rng)
			continue
		if not round:
			_lay_window(at, o.sill, r * 2.0, middle - o.sill, rng)
		# One square pane fills the head or the round: its corners lie inside the ring.
		_part(at, middle if round else middle + r * 0.5, Vector3(r * 2.0, r * (2.0 if round else 1.0), 0.02), glow() * rng.randf_range(0.9, 1.1), rng, "glass", -THICKNESS * 0.12)
		_part(at, middle if round else middle + r * 0.5, Vector3(0.035, r * (2.0 if round else 1.0), 0.05), WOOD, rng, "frame", -THICKNESS * 0.12)
		if round:
			_part(at, middle, Vector3(r * 2.0, 0.035, 0.05), WOOD, rng, "frame", -THICKNESS * 0.12)


func _lay_round_door(at: float, o: Dictionary, middle: float, rng: RandomNumberGenerator) -> void:
	var r: float = o.pane
	var planks := maxi(3, roundi(r * 2.0 / 0.2))
	var back := -THICKNESS * 0.15
	for i in planks:
		var x := -r + r * 2.0 * (i + 0.5) / planks
		var edge := maxf(absf(x) - r / planks, 0.0)
		var top := middle + sqrt(r * r - edge * edge)
		_part(at + x, (o.sill + top) * 0.5, Vector3(r * 2.0 / planks - 0.012, top - o.sill - 0.01, 0.06), WOOD * rng.randf_range(0.75, 1.1), rng, "door", back)
	for y: float in [o.sill + 0.4, middle - 0.3]:
		_part(at, y, Vector3(r * 2.0 - 0.08, 0.06, 0.08), IRON, rng, "iron", back)


func _lay_corner_window(o: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := COURSE
	var corner: float = o.s
	var tall: float = o.head - o.sill
	var wood := boarded()
	var cap := THICKNESS * 0.5
	var reach: float = o.half + LINTEL_EAR
	var lip := (THICKNESS + 0.1) * 0.5
	var faces := [corner - o.half * 0.5, corner + o.half * 0.5]
	_part(corner + (cap - reach) * 0.5, o.head + c * 0.5, Vector3(reach + cap, c, THICKNESS * 1.04), _trim(wood, rng), rng, "beam" if wood else "lintel", 0.0, 0.0, faces[0])
	_part(corner + (reach + cap) * 0.5, o.head + c * 0.5, Vector3(reach - cap, c, THICKNESS * 1.04), _trim(wood, rng), rng, "beam" if wood else "lintel", 0.0, 0.0, faces[1])
	_part(corner + (lip - o.half - 0.08) * 0.5, o.sill + 0.04, Vector3(o.half + 0.08 + lip, 0.08, THICKNESS + 0.1), _trim(wood, rng), rng, "beam" if wood else "sill", 0.0, 0.0, faces[0])
	_part(corner + (o.half + 0.08 + lip) * 0.5, o.sill + 0.04, Vector3(o.half + 0.08 - lip, 0.08, THICKNESS + 0.1), _trim(wood, rng), rng, "beam" if wood else "sill", 0.0, 0.0, faces[1])
	_part(corner, o.sill + tall * 0.5, Vector3(CORNER_POST, tall, CORNER_POST), stone_color(rng), rng, "mullion")
	var w: float = o.half - CORNER_POST * 0.5
	for side in [-1.0, 1.0]:
		_lay_window(corner + side * (CORNER_POST * 0.5 + w * 0.5), o.sill, w, tall, rng, 0.0, faces[0 if side < 0.0 else 1])


func _corner_window(s: float) -> Dictionary:
	for o in apertures:
		if o.style == Family.CORNER and absf(offset(o.s, s)) < 1e-3:
			return o
	return {}


func lived_in() -> bool:
	return floored() and lives(openings, not supports.is_empty())


## Static: the budget asks it of a command.
static func lives(placed: Array, standing: bool) -> bool:
	return standing or placed.any(opens_door)


func _lay_lived_in() -> void:
	var out := -inner_side()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "lived"])
	var cloth: Color = CURTAINS[rng.randi() % CURTAINS.size()]
	var windows := apertures.filter(func(o: Dictionary) -> bool: return not o.door and LIGHTS[o.style].dressed)
	var hung := windows.filter(_washing_fits)
	var line: Dictionary = {} if hung.is_empty() else hung[rng.randi() % hung.size()]
	for i in windows.size():
		var o: Dictionary = windows[i]
		rng.seed = hash([seed, "lived", roundi(o.s * 100.0)])
		var top: float = o.head if o.style == Family.COTTAGE else o.head - o.pane
		var plane := -THICKNESS * 0.12 + out * 0.05
		for at in light_centres(o):
			for edge in [-1.0, 1.0]:
				var w: float = o.pane * 0.55
				_part(at + edge * (o.pane - w * 0.5), (o.sill + top) * 0.5 + 0.01, Vector3(w, top - o.sill - 0.04, 0.012), cloth * rng.randf_range(0.9, 1.05), rng, "curtain", plane)
			_part(at, top - 0.05, Vector3(o.pane * 2.0, 0.08, 0.02), cloth * 0.85, rng, "curtain", plane + out * 0.01)
		if rng.randf() < 0.75:
			_lay_flower_box(o, out, rng)
		if o == line:
			_lay_washing(o, out, rng)


func _lay_flower_box(o: Dictionary, out: float, rng: RandomNumberGenerator) -> void:
	var long: float = o.half * 2.0 + 0.1
	var off := out * (THICKNESS * 0.5 + 0.17)
	_part(o.s, o.sill - 0.02, Vector3(long, 0.18, 0.2), WOOD * rng.randf_range(0.8, 1.05), rng, "planter", off)
	_part(o.s, o.sill + 0.1, Vector3(long - 0.04, 0.08, 0.16), LEAVES * rng.randf_range(0.85, 1.1), rng, "leaf", off)
	var n := maxi(3, roundi(long / 0.13))
	for k in n:
		var at: float = o.s - long * 0.5 + long * (k + 0.5) / n
		_part(at, o.sill + 0.15 + rng.randf_range(0.0, 0.04), Vector3(0.07, 0.06, 0.07), BLOOMS[rng.randi() % BLOOMS.size()], rng, "bloom", off + out * rng.randf_range(-0.05, 0.05), 0.5)


func clutter_frame(v: Vector4, ground: Callable) -> Variant:
	if length() <= 0.0 or not closed and (v.x < 0.0 or v.x > length()) or broken(v.x, 0.4):
		return null
	var s := self.wrap(v.x)
	var f := frame_at(s)
	if not ClutterLayout.perched(int(v.w)):
		for o in apertures:
			if o.door and absf(offset(s, o.s)) < o.half + 0.3:
				return null
		var x := ClutterLayout.facing(f.point, f.tangent, v.y, THICKNESS * 0.5 + absf(v.y), v.z)
		x.origin.y = maxf(maxf(ground.call(x.origin.x, x.origin.z), rest(x.origin.x, x.origin.z)), floor_under(Vector3(x.origin.x, INF, x.origin.z)))
		return x
	if cover == Cover.OPEN:
		return Transform3D(Basis(Vector3.UP, v.z), f.point + Vector3.UP * (standing(s) + CAP))
	if _hung.has(v):
		return _hung[v]
	var face := ClutterLayout.facing(f.point, f.tangent, v.y, THICKNESS * 0.5, v.z)
	var out: Vector3 = f.tangent.cross(Vector3.UP).normalized() * (1.0 if v.y >= 0.0 else -1.0)
	var shape := ClutterLayout.parts(v, Transform3D.IDENTITY, seed)
	var placed := func(x: Transform3D) -> Array[Transform3D]:
		var out_parts: Array[Transform3D] = []
		for part in shape:
			out_parts.append(x * (part.xform as Transform3D))
		return out_parts
	var hung := func(by: float) -> Transform3D:
		var x := face.translated(out * by)
		x.origin.y += _under_roof(placed.call(x))
		return x
	var at: Transform3D = hung.call(0.0)
	var near: Array[Transform3D] = []
	for st in stones:
		if st.has("clutter") or (st.xform as Transform3D).origin.distance_to(at.origin) > (st.size as Vector3).length() * 0.5 + 1.0:
			continue
		# The nest clears the stones as fit_under leaves them under the roof, laid after it or not.
		var kept := _fitted(st, gable) if gable != null and not gable.flat() else st
		if not kept.is_empty():
			near.append(kept.xform)
	var off := func(by: float) -> float: return _off_stones(placed.call(hung.call(by)), near, out)
	# Each step out brings a sloped roof's underside lower, and the nest with it: past other stones, or clear of the one
	# that pushed it, back toward the wall.
	var clashed := 0.0
	var clear := 0.0
	for i in 8:
		var step: float = off.call(clear)
		if step <= 0.0:
			break
		clashed = clear
		clear += step
	for i in 6:
		var mid := (clashed + clear) * 0.5
		if off.call(mid) > 0.0:
			clashed = mid
		else:
			clear = mid
	_hung[v] = hung.call(clear)
	return _hung[v]


static func _off_stones(parts: Array[Transform3D], near: Array[Transform3D], out: Vector3) -> float:
	var off := 0.0
	for st in near:
		var reach := _reach(st)
		for part in parts:
			if part.origin.distance_to(st.origin) < reach + _reach(part):
				off = maxf(off, _clear_along(part, st, out))
	return off


static func _reach(x: Transform3D) -> float:
	return (x.basis.x.abs() + x.basis.y.abs() + x.basis.z.abs()).length() * 0.5


static func _clear_along(a: Transform3D, b: Transform3D, dir: Vector3) -> float:
	var axes: Array[Vector3] = []
	for i in 3:
		axes.append(a.basis[i])
		axes.append(b.basis[i])
	for i in 3:
		for j in 3:
			axes.append(a.basis[i].cross(b.basis[j]))
	var least := INF
	for axis in axes:
		if axis.length_squared() < 1e-10:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in BOX:
			var pa := (a * c).dot(axis)
			var pb := (b * c).dot(axis)
			lo = Vector2(minf(lo.x, pa), minf(lo.y, pb))
			hi = Vector2(maxf(hi.x, pa), maxf(hi.y, pb))
		if hi.x <= lo.y or hi.y <= lo.x:
			return 0.0
		var along := axis.dot(dir)
		if absf(along) > 1e-6 * axis.length():
			least = minf(least, (hi.y - lo.x) / along if along > 0.0 else (lo.y - hi.x) / along)
	return least


## Against the roof's underside, as `fit_under` cuts the stones, or the walls' top where no roof is seated.
func _under_roof(parts: Array[Transform3D]) -> float:
	var rise_by := INF
	for part in parts:
		for c in BOX:
			var p: Vector3 = part * c
			rise_by = minf(rise_by, (gable.height_at(p.x, p.z) if gable != null else roof_base()) - p.y)
	return rise_by


func roof_base() -> float:
	return samples[0].y + height + CAP


func seat(r: RoofLayout) -> void:
	r.base = roof_base()
	r.foot = stands_at()
	r.stepped = gable_kind() == GableEnd.STEPS
	if r.kind == RoofLayout.Kind.GABLE:
		r.corners = laid_points


func _washing_fits(o: Dictionary) -> bool:
	var reach: float = o.half + WASHING_ARM
	if not closed and (o.s - reach < 0.0 or o.s + reach > length()):
		return false
	var along: Vector3 = frame_at(o.s).tangent
	return [-1.0, 1.0].all(func(edge: float) -> bool: return frame_at(o.s + edge * reach).tangent.dot(along) > 0.99)


func _lay_washing(o: Dictionary, out: float, rng: RandomNumberGenerator) -> void:
	var y: float = o.head + 0.12
	var arm := 0.55
	var reach: float = o.half + WASHING_ARM
	var ends: Array[Vector3] = []
	for edge in [-1.0, 1.0]:
		var s: float = o.s + edge * reach
		var f := frame_at(s)
		var n: Vector3 = f.tangent.cross(Vector3.UP) * out
		var foot: Vector3 = f.point + Vector3.UP * y + n * THICKNESS * 0.5
		_world(Transform3D(Basis(n, Vector3.UP, n.cross(Vector3.UP)).scaled_local(Vector3(arm, 0.035, 0.035)), foot + n * arm * 0.5), IRON, "iron", s)
		ends.append(foot + n * arm)
	var sag := Vector3.DOWN * 0.08
	var mid := (ends[0] + ends[1]) * 0.5 + sag
	for pair in [[ends[0], mid], [mid, ends[1]]]:
		_between(pair[0], pair[1], Vector3(0.0, 0.012, 0.012), ROPE, "rope", o.s)
	var pieces := maxi(2, roundi(reach * 2.0 / 0.5))
	for k in pieces:
		var t := (k + 0.5) / pieces
		var at: Vector3 = ends[0].lerp(ends[1], t) + sag * (1.0 - absf(t * 2.0 - 1.0))
		var along := (ends[1] - ends[0]).normalized()
		var size := Vector2(rng.randf_range(0.22, 0.34), rng.randf_range(0.26, 0.42))
		var hang := Basis(Vector3.DOWN, along, Vector3.DOWN.cross(along)).scaled_local(Vector3(size.y, size.x, 1.0))
		cloths.append({"xform": Transform3D(hang, at), "color": WASHING[rng.randi() % WASHING.size()] * rng.randf_range(0.9, 1.05)})


## Stands on a post where `out` is zero.
func _lay_lantern(s: float, at: Vector3, out: Vector3, rng: RandomNumberGenerator) -> void:
	var hang := at + out * LANTERN_REACH
	if out.length() > 0.0:
		var arm := Basis(out, Vector3.UP, out.cross(Vector3.UP))
		_world(Transform3D(arm.scaled_local(Vector3(LANTERN_REACH + 0.04, 0.04, 0.04)), at + out * LANTERN_REACH * 0.5 + Vector3.UP * 0.32), IRON, "iron", s)
		_world(Transform3D(Basis().scaled(Vector3(0.02, 0.1, 0.02)), hang + Vector3.UP * 0.26), IRON, "iron", s)
	var turn := Basis(Vector3.UP, rng.randf() * TAU)
	_world(Transform3D(turn.scaled_local(Vector3(0.2, 0.05, 0.2)), hang + Vector3.UP * 0.19), IRON, "hood", s)
	_world(Transform3D(turn.scaled_local(Vector3(0.16, 0.035, 0.16)), hang - Vector3.UP * 0.07), IRON, "iron", s)
	flames.append(Transform3D(turn.scaled_local(Vector3(0.12, 0.22, 0.12)), hang + Vector3.UP * 0.055))


static func flag(foot: Vector3, along: Vector3, color: Color) -> Dictionary:
	var x := along.normalized()
	var cloth := Basis(x, Vector3.UP, x.cross(Vector3.UP)).scaled_local(Vector3(0.9, 0.55, 1.0))
	return {
		"pole": Transform3D(Basis().scaled(Vector3(0.05, FLAG_POLE, 0.05)), foot + Vector3.UP * FLAG_POLE * 0.5),
		"finial": Transform3D(Basis().scaled(Vector3.ONE * 0.09), foot + Vector3.UP * (FLAG_POLE + 0.04)),
		"cloth": {"xform": Transform3D(cloth, foot + Vector3.UP * (FLAG_POLE - 0.33) + x * 0.03), "color": color},
	}


## Each run as (its first flag's arc length, the next one's).
static func flag_runs(flags: Array, length: float, closed: bool) -> Array[Vector2]:
	var sorted := flags.duplicate()
	sorted.sort()
	var n := sorted.size()
	var out: Array[Vector2] = []
	for i in (n if closed else n - 1):
		var a: float = sorted[i]
		var b: float = sorted[(i + 1) % n]
		var gap := fposmod(b - a, length) if closed else b - a
		if gap > 0.0 and gap <= FLAG_RUN:
			out.append(Vector2(a, b))
	# Two flags on a loop are neighbours both ways round it; they join the shorter way alone.
	if closed and n == 2 and out.size() == 2:
		out.remove_at(0 if fposmod(sorted[1] - sorted[0], length) > fposmod(sorted[0] - sorted[1], length) else 1)
	return out


func _lay_flag_run(a: float, b: float) -> void:
	var ends: Array[Vector3] = []
	for s in [a, b]:
		ends.append(frame_at(s).point + Vector3.UP * (height + CAP + FLAG_RUN_ROPE))
	var span := ends[1] - ends[0]
	var pieces := 4
	for k in pieces:
		var p := ends[0] + DecorationLayout.hang_at(span, float(k) / pieces)
		var q := ends[0] + DecorationLayout.hang_at(span, float(k + 1) / pieces)
		_between(p, q, Vector3(0.0, 0.014, 0.014), ROPE, "rope", a)
	var along := (ends[1] - ends[0]).normalized()
	var hang := Basis(Vector3.DOWN, along, Vector3.DOWN.cross(along)).scaled_local(Vector3(0.3, 0.2, 1.0))
	var colours := [flag_color(seed, a), flag_color(seed, b)]
	var count := maxi(2, floori(ends[0].distance_to(ends[1]) / FLAG_RUN_EVERY))
	for k in count:
		cloths.append({"xform": Transform3D(hang, ends[0] + DecorationLayout.hang_at(span, (k + 0.5) / count)), "color": colours[k % 2]})


## Hashed from seed and place, so a flag keeps its colour through every other edit to its wall.
static func flag_color(wall_seed: int, s: float) -> Color:
	return FLAG_COLORS[posmod(hash([wall_seed, roundi(s * 100.0)]), FLAG_COLORS.size())]


func posts() -> Array[float]:
	var arched := archways()
	var total := length()
	var n := maxi(1, ceili(total / POST_SPACING))
	var out: Array[float] = []
	for i in n + 1:
		var s := total * i / n
		if arched.all(func(a): return absf(s - a) > ARCH_HALF + 0.4):
			out.append(s)
	return out


func nearest_post(s: float) -> float:
	var best := INF
	for p in posts():
		if absf(p - s) < absf(best - s):
			best = p
	return best if best != INF else s


func _build_fence(rng: RandomNumberGenerator) -> void:
	var arched := archways()
	var standing := posts()
	var gates: Array[float] = []
	for a in arched:
		gates.append_array([a - ARCH_HALF - 0.08, a + ARCH_HALF + 0.08])
	var all := standing + gates
	all.sort()
	for i in all.size():
		var s := all[i]
		var tall := FENCE_HEIGHT + (GATE_POST - FENCE_HEIGHT if gates.has(s) else 0.0)
		var d := depth_at(s)
		_part(s, (tall + 0.12 - d) * 0.5, Vector3(0.13, tall + 0.12 + d, 0.13) * rng.randf_range(0.92, 1.08), WOOD * rng.randf_range(0.8, 1.1), rng, "post", 0.0, 0.03)
		if i == 0:
			continue
		var prev := all[i - 1]
		if arched.any(func(a): return a > prev and a < s):
			continue
		if finish == Finish.BOARDS_ACROSS:
			for y in FENCE_BOARDS:
				_rail(prev, s, y + 0.12, Vector3(-0.12, FENCE_BOARD_TALL, 0.03), WOOD * rng.randf_range(0.8, 1.1), "board")
			continue
		for y: float in [0.45, 0.85]:
			_rail(prev, s, y + 0.12, Vector3(0.06, 0.08, 0.05), WOOD * rng.randf_range(0.8, 1.1))
		if finish == Finish.BOARDS_UPRIGHT:
			_lay_pales(prev, s, rng)
	for a in arched:
		var r := ARCH_HALF + 0.08
		var squash := 0.5
		var k := 9
		for i in k:
			var t := (i + 0.5) / k * PI
			var size := Vector3(PI * r / k * 1.2, 0.11, 0.1)
			stones.append(_stone(a - cos(t) * r, GATE_POST + 0.04 + sin(t) * r * squash, size, rng, "gate", 0.0, atan2(cos(t) * squash, sin(t))))
			stones[-1].color = WOOD * rng.randf_range(0.8, 1.05)
	if standing.is_empty():
		return
	var lit: Array[float] = []
	for l in lanterns:
		var s := nearest_post(l.x)
		if not lit.has(s):
			lit.append(s)
			_lay_lantern(s, post_lantern_at(s), Vector3.ZERO, rng)


func _lay_pales(a: float, b: float, rng: RandomNumberGenerator) -> void:
	var n := maxi(1, roundi((b - a - 0.13) / FENCE_PALE))
	var step := (b - a - 0.13) / n
	for i in n:
		var s := a + 0.065 + step * (i + 0.5)
		var tall := FENCE_HEIGHT - 0.05 + rng.randf_range(-0.02, 0.02)
		_part(s, 0.08 + tall * 0.5, Vector3(step - BOARD.y, tall, 0.025), WOOD * rng.randf_range(0.8, 1.1), rng, "board", 0.04)


static func stone_color(rng: RandomNumberGenerator) -> Color:
	var warm := rng.randf_range(-0.05, 0.05)
	return Color(STONE.r + warm, STONE.g, STONE.b - warm * 1.5) * rng.randf_range(0.82, 1.08)


## It keeps its depth: jittered like rubble, a glazing bar or strap sinks into the glass or plank behind it.
func _part(s: float, y: float, size: Vector3, color: Color, rng: RandomNumberGenerator, kind: String, out := 0.0, wobble := 0.0, face := INF) -> void:
	var st := _stone(s, y, size, rng, kind, wobble, 0.0, 0.0, face)
	st.xform.origin += _normal(s) * out
	st.color = color
	stones.append(st)


func _world(xform: Transform3D, color: Color, kind: String, s: float) -> void:
	stones.append({"xform": xform, "color": color, "kind": kind, "s": s, "y": xform.origin.y - frame_at(s).point.y, "size": xform.basis.get_scale(), "ao": 1.0, "variant": stones.size() % 3})


func _cut(spans: Array, lo: float, hi: float) -> Array:
	if closed and (lo < 0.0 or hi > length()):
		var shift := length() if lo < 0.0 else -length()
		spans = _cut_span(spans, lo + shift, hi + shift)
	return _cut_span(spans, lo, hi)


func _cut_span(spans: Array, lo: float, hi: float) -> Array:
	var out := []
	for s in spans:
		if hi <= s[0] or lo >= s[1]:
			out.append(s)
			continue
		if lo > s[0]:
			out.append([s[0], lo])
		if hi < s[1]:
			out.append([hi, s[1]])
	return out


func plaster_at(y: float) -> bool:
	return foundation == Foundation.PLASTER if y < 0.0 else plastered() and y > 0.0


func plastered() -> bool:
	return finish == Finish.PLASTER or finish == Finish.TIMBER


func _infill_depth() -> float:
	return THICKNESS - (PLASTER_INSET if plastered() else JOINT) * 2.0 - 0.004


func _infill_kind() -> Dictionary:
	return {"kind": "plaster" if plastered() else "mortar", "jitter": 0.0}


func _lay_infill(st: Dictionary) -> void:
	st.color = PLASTER if plastered() else MORTAR
	st.ao = 1.0 if plastered() else 0.8
	st.variant = 0
	stones.append(st)


func boarded() -> bool:
	return boards(finish)


static func boards(f: Finish) -> bool:
	return f == Finish.BOARDS_ACROSS or f == Finish.BOARDS_UPRIGHT


static func suits(f: Finish, is_fence: bool) -> bool:
	return not is_fence or f == Finish.BARE or boards(f)


static func foundations(d: Dictionary) -> Array[Foundation]:
	var out: Array[Foundation] = []
	out.assign(Foundation.values().filter(func(f: Foundation) -> bool: return (not d.fence or f in FENCE_FOUNDATIONS) and (d.closed or f not in STILTS)))
	return out


## The first course stays stone, as under plaster.
func boards_at(y: float) -> bool:
	return boarded() and y > 0.0


## Taken where a noise over the face is lowest, so the patches carry on from course to course.
func _worn(y: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if finish != Finish.PLASTER or wear <= 0.0 or y <= 0.0:
		return out
	var total := length()
	var n := maxi(1, ceili(total / WORN_STEP))
	var take := roundi(clampf(wear * (1.5 - y / height), 0.0, 1.0) * n)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.5
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	var order := range(n)
	var scores := order.map(func(i: int) -> float: return noise.get_noise_2d((i + 0.5) * total / n / WORN_PATCH.x, y / WORN_PATCH.y))
	order.sort_custom(func(a: int, b: int) -> bool: return scores[a] < scores[b] or scores[a] == scores[b] and a < b)
	var worn := PackedByteArray()
	worn.resize(n)
	for i in take:
		worn[order[i]] = 1
	var i := 0
	while i < n:
		var j := i
		while j < n and worn[j] == worn[i]:
			j += 1
		if worn[i] == 1:
			out.append(Vector2(i, j) * total / n)
		i = j
	return out


func _lay_course(a: float, b: float, y0: float, h: float, offset: float, rng: RandomNumberGenerator, thick := THICKNESS) -> void:
	var s := a
	var first := true
	while b - s > 0.001:
		var want := rng.randf_range(0.42, LONGEST) * _stone_scale
		if first:
			want = maxf(0.2, want * (1.0 - offset))
			first = false
		var l := minf(want, b - s)
		var hj := h * rng.randf_range(0.9, 1.04)
		var depth := thick * rng.randf_range(0.92, 1.05)
		_add(s + l * 0.5, y0 + h * 0.5, Vector3(l, hj, depth), rng, "block", 0.035)
		s += l


## Bands are `[y0, h, spans, broken, lintels, worn]`. Mortar stands JOINT back at open span ends and broken tops, and
## runs on behind a lintel. A panel runs straight between its cell's ends, mitred into the next (`ends`), so a curved face
## stays closed and shades round; one with the same ends as the panel below grows up instead of stacking on it.
func _lay_mortar(bands: Array, thick := THICKNESS) -> void:
	var gable_ends: Array[Vector2] = []
	if plastered() and gable_kind() == GableEnd.WALL:
		gable_ends = gable_spans()
	var cells := _cells()
	var turns := PackedFloat32Array()
	turns.resize(cells.size() + 1)
	for i in range(1, cells.size()):
		turns[i] = cells[i - 1].tangent.signed_angle_to(cells[i].tangent, Vector3.UP) * 0.5
	if closed and cells.size() > 1:
		turns[0] = cells[-1].tangent.signed_angle_to(cells[0].tangent, Vector3.UP) * 0.5
		turns[-1] = turns[0]
	var total := length()
	var panels := []
	var below := {}
	for j in bands.size():
		var y0: float = bands[j][0]
		if j > 0 and absf(y0 - bands[j - 1][0] - bands[j - 1][1]) > 1e-3:
			# Stilts stand in the courses skipped between: no panel grows up across them.
			below = {}
		var face := plaster_at(y0)
		var worn: PackedVector2Array = bands[j][5] if bands[j].size() > 5 else PackedVector2Array()
		var spans: Array = bands[j][2]
		var bare := _round(bands[j + 1][3] if j + 1 < bands.size() and bands[j + 1].size() > 3 and not face else PackedVector2Array())
		var heads := PackedVector2Array()
		for l: Vector2 in bands[j][4] if bands[j].size() > 4 else []:
			heads.append(l + Vector2(-JOINT, JOINT) * (0.0 if face else 1.0))
		heads = _round(heads)
		if not face:
			spans = spans.map(func(sp): return [sp[0] + (0.0 if closed and sp[0] < 0.001 else JOINT), sp[1] - (0.0 if closed and sp[1] > total - 0.001 else JOINT)])
		var wraps: bool = closed and spans.any(func(sp): return sp[0] < 0.001) and spans.any(func(sp): return sp[1] > total - 0.001)
		var here := {}
		for span in spans:
			for i in cells.size():
				var c: Dictionary = cells[i]
				var a := maxf(span[0], c.a)
				var b := minf(span[1], c.b)
				if b - a < 0.02:
					continue
				var left: bool = a - c.a < 0.001 and (a - span[0] > 0.001 or wraps and a < 0.001)
				var right: bool = c.b - b < 0.001 and (span[1] - b > 0.001 or wraps and b > total - 0.001)
				var ends := Vector2(clampf(-turns[i], -1.0, 1.0) if left else 0.0, clampf(turns[i + 1], -1.0, 1.0) if right else 0.0)
				for top in _pieces(a, b, bare):
					for piece in _pieces(top[0], top[1], heads):
						for patch in _pieces(piece[0], piece[1], Array(worn)):
							var plain: bool = face and not patch[2]
							var key := "%d %.3f %.3f %s %s" % [i, patch[0], patch[1], plain, face]
							var p: Dictionary = below.get(key, {})
							var e := Vector2(ends.x if patch[0] == a else 0.0, ends.y if patch[1] == b else 0.0)
							if p.is_empty() or p.ends != e or piece[2]:
								p = {"cell": c, "a": patch[0], "b": patch[1], "y0": y0 + (JOINT if piece[2] else 0.0), "face": plain, "worn": face and patch[2], "ends": e}
								panels.append(p)
							p.top = y0 + bands[j][1] + (-JOINT if top[2] else 0.02)
							# Infill seals the cap band; the gable mesh owns it on end walls.
							if cover != Cover.OPEN and is_equal_approx(y0 + bands[j][1], height):
								var mid: float = (patch[0] + patch[1]) * 0.5
								p.top = height if gable_ends.any(func(end: Vector2) -> bool: return mid >= end.x and mid <= end.y) else height + CAP
							here[key] = p
		below = here
	for p in panels:
		var c: Dictionary = p.cell
		var from: Vector3 = c.from.lerp(c.to, (p.a - c.a) / (c.b - c.a))
		var to: Vector3 = c.from.lerp(c.to, (p.b - c.a) / (c.b - c.a))
		var h: float = p.top - p.y0
		var size := Vector3(p.b - p.a, h, (WORN_THICK if p.worn else thick) - (PLASTER_INSET if p.face else JOINT) * 2.0)
		var basis := Basis(to - from, Vector3.UP * h, c.tangent.cross(Vector3.UP) * size.z)
		var y: float = p.y0 + h * 0.5
		stones.append({"xform": Transform3D(basis, (from + to) * 0.5 + Vector3.UP * y), "color": PLASTER if p.face else MORTAR, "kind": "plaster" if p.face else "mortar", "s": (p.a + p.b) * 0.5, "y": y, "size": size, "ao": 1.0 if plastered() or p.face else 0.8, "variant": 0, "ends": p.ends})


func _lay_run(a: float, b: float, y: float, size: Vector2, out: float, rng: RandomNumberGenerator) -> void:
	var s := a
	var want := rng.randf_range(0.3, 1.0) * BOARD_RUN.y
	while b - s > BOARD.y * 2.0:
		var l := straight(s, minf(want * _stone_scale, b - s))
		if b - s - l < BOARD.x and straight(s, b - s) == b - s:
			l = b - s
		_part(s + l * 0.5, y, Vector3(l - BOARD.y, size.x - BOARD.y, size.y), WOOD * rng.randf_range(0.85, 1.1), rng, "board", out)
		s += l
		want = rng.randf_range(BOARD_RUN.x, BOARD_RUN.y)


func straight(s: float, l: float) -> float:
	# A loop's corners are summed from its points, its lengths from its samples: a corner can fall a rounding either side
	# of its sample, which counts as the turn at the piece's end, never at its start.
	var first := clampi(lengths.bsearch(s + 1e-4, false), 1, samples.size() - 1)
	var last := Vector3(samples[first].x - samples[first - 1].x, 0.0, samples[first].z - samples[first - 1].z)
	var turn := 0.0
	for i in range(first, samples.size() - 1):
		if lengths[i] >= s + l - 1e-4:
			break
		var t := Vector3(samples[i + 1].x - samples[i].x, 0.0, samples[i + 1].z - samples[i].z)
		if t.length() < 1e-5:
			continue
		turn += absf(last.signed_angle_to(t, Vector3.UP))
		last = t
		if turn > BOARD_TURN:
			return lengths[i] - s
	return l


func _corner(s: float, turns: Array[float]) -> bool:
	return (closed or s > 0.001 and s < length() - 0.001) and turns.any(func(c: float) -> bool: return absf(c - s) < 0.001)


static func rows_of(h: float) -> int:
	return maxi(1, ceili(h / BOARD.x - 1e-3))


## The mortar laid behind the planks closes the gaps between them.
func _lay_cladding(bands: Array, faces: Array[Vector2], rng: RandomNumberGenerator) -> void:
	var deep := THICKNESS - PLASTER_INSET * 2.0
	var columns: Array[Dictionary] = []
	var below := {}
	var under := 0.0
	for band: Array in bands:
		var y0: float = band[0]
		var h: float = band[1]
		if not boards_at(y0):
			continue
		var here := {}
		var rows := rows_of(h)
		for span: Array in band[2]:
			for face in faces:
				var a := maxf(span[0], face.x)
				var b := minf(span[1], face.y)
				if b - a < BOARD.y * 2.0:
					continue
				if finish == Finish.BOARDS_ACROSS:
					for r in rows:
						rng.seed = hash([seed, "board", y0, r, a])
						_lay_run(a, b, y0 + h * (r + 0.5) / rows, Vector2(h / rows, deep), 0.0, rng)
					continue
				for i in range(floori(a / BOARD.x), ceili(b / BOARD.x)):
					var lo := maxf(a, i * BOARD.x)
					var hi := minf(b, (i + 1) * BOARD.x)
					if hi - lo < BOARD.y * 2.0:
						continue
					var key := Vector2(lo, hi)
					var column: Dictionary = below.get(key, {}) if absf(under - y0) < 1e-3 else {}
					if column.is_empty():
						column = {"a": lo, "b": hi, "y0": y0}
						columns.append(column)
					column.top = y0 + h
					here[key] = column
		below = here
		under = y0 + h
	for c in columns:
		rng.seed = hash([seed, "board", c.a, c.y0])
		_part((c.a + c.b) * 0.5, (c.y0 + c.top) * 0.5, Vector3(c.b - c.a - BOARD.y, c.top - c.y0, deep), WOOD * rng.randf_range(0.85, 1.1), rng, "board")


func _round(stretches: PackedVector2Array) -> Array:
	var out := []
	for b in stretches:
		for lap in ([-1.0, 0.0, 1.0] if closed else [0.0]):
			out.append(b + Vector2.ONE * lap * length())
	out.sort()
	return out


## Pieces `[from, to, is_bare]`.
static func _pieces(a: float, b: float, bare: Array) -> Array:
	var out := []
	var s := a
	for sp in bare:
		var lo := clampf(sp.x, s, b)
		var hi := clampf(sp.y, s, b)
		if hi - lo < 0.001:
			continue
		if lo > s:
			out.append([s, lo, false])
		out.append([lo, hi, true])
		s = hi
	if b > s:
		out.append([s, b, false])
	return out


## Keys: `a`, `b` in arc length, where they stand (`from`, `to`), and the level `tangent`.
func _cells() -> Array[Dictionary]:
	var total := length()
	var stops: Array[float] = [0.0, total]
	for s in corners():
		if s > 0.001 and s < total - 0.001:
			stops.append(s)
	stops.sort()
	var out: Array[Dictionary] = []
	for j in stops.size() - 1:
		var n := maxi(1, ceili((stops[j + 1] - stops[j]) / _stone_scale - 0.25))
		for m in n:
			var a := lerpf(stops[j], stops[j + 1], float(m) / n)
			var b := lerpf(stops[j], stops[j + 1], float(m + 1) / n)
			var from: Vector3 = frame_at(a).point
			var to: Vector3 = frame_at(minf(b, total - 0.0001) if closed else b).point
			var level := Vector3(to.x - from.x, 0.0, to.z - from.z)
			out.append({"a": a, "b": b, "from": from, "to": to, "tangent": level.normalized() if level.length() > 1e-5 else frame_at((a + b) * 0.5).tangent})
	return out


## Behind the wedges the infill closes the ring out to the outline, so the wall's level cut meets it with no gap.
func _lay_arch(a: float, size: float, rng: RandomNumberGenerator, bottom: float) -> void:
	var style := arch_style()
	var tint: Color = style.get("color", Color.WHITE) * rng.randf_range(0.88, 1.12)
	var ring: float = style.ring * size
	var jamb: float = style.jamb * size
	var spring_y := spring(size)
	var mortar := RING * size + JOINT
	var inner: float = 0.01 + ring * (1.0 - style.meet) * 0.5
	var depth := THICKNESS * 1.04
	var fill := _infill_depth()
	var head := arch_head(0.0, size)
	var crown: Array = head[-1]
	var key: Vector3 = style.keystone * Vector3(size, size, 1.0)
	var key_y := arch_rise(0.0, size) + ring * 0.5
	var key_half := atan(key.x * 0.5 / (crown[1] + ring * 0.5))
	var parts: Array[Dictionary] = []
	var infill: Array[Dictionary] = []
	var mortared := _infill_kind()
	for side in [-1.0, 1.0]:
		if jamb > 0.0:
			parts.append(_arch_part(a + side * (ARCH_HALF * size + jamb * 0.5), (bottom + spring_y) * 0.5, Vector3(jamb, spring_y - bottom, depth), 0.0, style, rng))
		for i in head.size():
			var arc: Array = head[i]
			var n: int = style.pieces[i]
			var to: float = arc[3] - (key_half if i == head.size() - 1 else 0.0)
			for j in n:
				parts.append(_voussoir(a, spring_y, side, arc, lerpf(arc[2], to, float(j) / n), lerpf(arc[2], to, float(j + 1) / n), 0.0, ring, depth, 0.0, style, rng))
			var m: int = ceili((arc[3] - arc[2]) / deg_to_rad(30.0))
			for j in m:
				infill.append(_voussoir(a, spring_y, side, arc, lerpf(arc[2], arc[3], float(j) / m), lerpf(arc[2], arc[3], float(j + 1) / m), inner, mortar, fill, -0.02, mortared, rng))
	if crown[3] < PI * 0.5 - 1e-3:
		infill.append(_crown_wedge(a, spring_y, crown, 0.0, arch_rise(0.0, size) + (inner + mortar) * 0.5, Vector3(0.0, mortar - inner, fill), -0.02, mortared, rng))
	for st in infill:
		_lay_infill(st)
	parts.append(_crown_wedge(a, spring_y, crown, key_half, key_y, key, 0.0, style.merged({"kind": style.capstone}, true), rng))
	for st in parts:
		if style.has("color"):
			st.color = tint
			st.variant = 0
		stones.append(st)


## Its joint lines stop `short` of where the `crown` arcs meet: in a pointed head these run through centres either side
## of the middle, so they part above its point.
func _crown_wedge(a: float, spring_y: float, crown: Array, short: float, y: float, size: Vector3, joint: float, style: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var joint_at: float = crown[3] - short
	var reach: float = crown[0].x + (y - crown[0].y) / tan(joint_at)
	return _wedge(_arch_part(a, spring_y + y, Vector3((2.0 * reach - joint) / style.get("meet", 1.0), size.y, size.z), 0.0, style, rng), PI * 0.5 - joint_at)


func _voussoir(a: float, spring_y: float, side: float, arc: Array, from: float, to: float, inner: float, outer: float, depth: float, joint: float, style: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var half := (to - from) * 0.5
	var t := from + half
	var mid: float = arc[1] + (inner + outer) * 0.5
	var at: Vector2 = arc[0] + Vector2(cos(t), sin(t)) * mid
	var st := _arch_part(a + side * at.x, spring_y + at.y, Vector3((2.0 * mid * tan(half) - joint) / style.get("meet", 1.0), outer - inner, depth), -side * (PI * 0.5 - t), style, rng)
	return _wedge(st, half)


## Turned so the shader's end cut (`ends`, turning about local y) tapers it.
func _wedge(st: Dictionary, turn: float) -> Dictionary:
	var x: Transform3D = st.xform
	st.xform = Transform3D(x.basis * Basis(Vector3.RIGHT, -PI * 0.5), x.origin)
	st.size = Vector3(st.size.x, st.size.z, st.size.y)
	st.ends = Vector2(-turn, turn)
	return st


func _arch_part(s: float, y: float, size: Vector3, roll: float, style: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	return _stone(s, y, size, rng, style.kind, 0.0, roll, style.jitter)


func offset(a: float, b: float) -> float:
	return fposmod(a - b + length() * 0.5, length()) - length() * 0.5 if closed else a - b


func wrap(s: float) -> float:
	return fposmod(s, length()) if closed else clampf(s, 0.0, length())


## `top` is the lower arch's springing, which the pillar rises to.
func pillars() -> Array[Dictionary]:
	var arched := apertures.filter(func(o): return o.style == Family.ARCHWAY)
	var out: Array[Dictionary] = []
	var n := arched.size()
	for i in range(0 if closed and n > 1 else 1, n):
		var prev: Dictionary = arched[(i + n - 1) % n]
		var next: Dictionary = arched[i]
		var gap := offset(next.s, prev.s)
		var k: float = (prev.size + next.size) * 0.5
		if gap > 0.0 and gap < ARCADE_GAP * k:
			out.append({"s": prev.s + (gap + prev.half - next.half) * 0.5, "half": (gap - prev.half - next.half) * 0.5, "top": minf(spring(prev.size), spring(next.size))})
	return out


func _lay_pillar(s: float, half: float, top_y: float, rng: RandomNumberGenerator, wet: RandomNumberGenerator) -> void:
	var w := half * 2.0
	var bed := maxf(maxf(depth_at(s - half), depth_at(s)), depth_at(s + half))
	_lay_footing(s, bed, Vector3(w - 0.1, 0.0, THICKNESS - 0.06), "pillar", wet)
	_add(s, 0.1, Vector3(w + 0.08, 0.2, THICKNESS + 0.1), rng, "pillar", 0.02)
	var y := 0.2
	while y < top_y - 0.25:
		var h := minf(rng.randf_range(0.34, 0.46), top_y - 0.18 - y)
		_add(s, y + h * 0.5, Vector3(w - 0.1, h, THICKNESS - 0.06), rng, "pillar", 0.02)
		y += h
	_add(s, top_y - 0.09, Vector3(w + 0.1, 0.18, THICKNESS + 0.1), rng, "pillar", 0.0)


static func stilt_span(kind: Foundation, rise: float) -> float:
	var span := minf(STILT_SPAN, snappedf(rise, COURSE) - COURSE)
	return span if kind in STILTS and span > 2.0 * COURSE - 1e-4 else 0.0


func stilted() -> bool:
	return supports.is_empty() and stilt_span(foundation, laid_rise) > 0.0


func stations() -> Array[float]:
	var total := Commands.length(points + [points[0]])
	var edges := corners()
	if edges.is_empty():
		edges.append(0.0)
	var out: Array[float] = []
	for i in edges.size():
		var a := edges[i]
		var b := edges[i + 1] if i + 1 < edges.size() else edges[0] + total
		var k := maxi(1, ceili((b - a) / STILT_SPACING - 1e-4))
		for j in k:
			out.append(fposmod(a + (b - a) * j / k, total))
	return out


func _lay_stilts(span: float, rng: RandomNumberGenerator) -> void:
	var at := stations()
	var piers: Array[float] = []
	if not TimberFrame.applies(self):
		piers = corners()
	var top := -COURSE if foundation == Foundation.PILLARS else -BEAM.y
	for i in at.size():
		var s := at[i]
		rng.seed = hash([seed, "stilt", i])
		var bottom := -minf(depth_at(s) + 0.05, span)
		if foundation == Foundation.POSTS:
			var a: Vector3 = frame_at(s).point
			var b: Vector3 = frame_at(at[(i + 1) % at.size()]).point
			var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
			var basis := Basis(along.normalized(), Vector3.UP, along.normalized().cross(Vector3.UP))
			_world(Transform3D(basis.scaled_local(Vector3(along.length() + POST, BEAM.y, BEAM.x)), (a + b) * 0.5 + Vector3.UP * -BEAM.y * 0.5), WOOD * rng.randf_range(0.8, 1.05), "beam", s)
			if top - bottom > 0.1:
				_part(s, (bottom + top) * 0.5, Vector3(POST, top - bottom, POST), WOOD * rng.randf_range(0.8, 1.05), rng, "post")
			continue
		if top - bottom < 0.02 or piers.any(func(c: float) -> bool: return absf(offset(s, c)) < 0.01):
			continue
		var base := minf(0.2, top - bottom)
		_add(s, bottom + base * 0.5, Vector3(PILLAR + 0.12, base, PILLAR + 0.12), rng, "pillar", 0.02)
		_lay_footing(s, -bottom - base, Vector3(PILLAR, 0.0, PILLAR), "pillar", rng, top)


func corners() -> Array[float]:
	var out: Array[float] = []
	if not closed:
		if length() > 0.0:
			out.assign([0.0] + _bends() + [length()])
		return out
	var n := points.size()
	var s := 0.0
	for i in n:
		var a := points[(i + n - 1) % n]
		var b := points[i]
		var c := points[(i + 1) % n]
		var into := Vector2(b.x - a.x, b.z - a.z)
		var out_of := Vector2(c.x - b.x, c.z - b.z)
		if into.length() > 1e-4 and out_of.length() > 1e-4 and absf(into.angle_to(out_of)) > CORNER_TURN:
			out.append(s)
		s += out_of.length()
	return out


func _bends() -> Array[float]:
	var out: Array[float] = []
	var reach := PIER * 0.5
	var turns := PackedFloat32Array()
	for s in lengths:
		var p: Vector3 = frame_at(s).point
		var into: Vector3 = p - frame_at(s - reach).point
		var out_of: Vector3 = frame_at(s + reach).point - p
		var ok := s > PIER and s < length() - PIER
		turns.append(absf(Vector2(into.x, into.z).angle_to(Vector2(out_of.x, out_of.z))) if ok else 0.0)
	for i in range(1, turns.size() - 1):
		if turns[i] > CORNER_TURN and turns[i] >= turns[i - 1] and turns[i] > turns[i + 1]:
			if out.is_empty() or lengths[i] - out[-1] > PIER:
				out.append(lengths[i])
	return out


func _face_spans() -> Array[Vector2]:
	var edges := corners()
	if edges.is_empty() or edges[0] > 0.0:
		edges.push_front(0.0)
	if edges[-1] < length():
		edges.append(length())
	var spans: Array[Vector2] = []
	for i in edges.size() - 1:
		spans.append(Vector2(edges[i], edges[i + 1]))
	return spans


func _lay_top(rng: RandomNumberGenerator) -> void:
	var faces := _face_spans()
	for face in faces.size():
		var spans := _standing([[faces[face].x, faces[face].y]])
		for i in spans.size():
			rng.seed = hash([seed, "top", face, i])
			_lay_top_span(spans[i][0], spans[i][1], rng)


## Under a pitched roof every top lies flat as a cap, flush with the faces, so the roof rests on its outer edges.
func _lay_top_span(a: float, total: float, rng: RandomNumberGenerator) -> void:
	var style := Top.CAP if cover == Cover.ROOF else top
	if style == Top.COPE:
		var s := a
		var tall := true
		while total - s > 0.001:
			var l := minf(rng.randf_range(0.11, 0.17), total - s)
			var h := rng.randf_range(COPE_TALL.x, COPE_TALL.y) if tall else rng.randf_range(COPE_SHORT.x, COPE_SHORT.y)
			_add(s + l * 0.5, height + h * 0.5, Vector3(l, h, THICKNESS * 0.86), rng, "cope", 0.06)
			tall = not tall
			s += l + 0.012
		return
	_lay_row(a, total, height + CAP * 0.5, Vector2(0.5, 0.95), Vector2(CAP, THICKNESS + (0.0 if cover == Cover.ROOF else 0.16)), "cap", rng)
	if style == Top.CAP and cover == Cover.DECK:
		_lay_parapet(a, total, rng)
	if style == Top.RAIL:
		_lay_railing(a, total, rng)
	if style != Top.CRENEL:
		return
	rng.seed = hash([rng.seed, "merlon"])
	var edge := a + 0.3
	while edge < total - 0.001:
		var width := minf(0.5, total - edge)
		_add(edge + width * 0.5, height + CAP + 0.24, Vector3(width, 0.48, THICKNESS * 0.8), rng, "merlon", 0.03)
		edge += 1.15


func _lay_walk(rng: RandomNumberGenerator) -> void:
	var faces := _face_spans()
	var turns := corners()
	var wide := THICKNESS + 0.16
	for face in faces.size():
		var spans := _standing([[faces[face].x, faces[face].y]])
		for i in spans.size():
			rng.seed = hash([seed, "walk", face, i])
			var a: float = spans[i][0]
			var b: float = spans[i][1]
			var ends := Vector2(wide * 0.5 if _corner(a, turns) else 0.0, wide * 0.5 if _corner(b, turns) else 0.0)
			for lane in WALK_LANES:
				_lay_run(a + ends.x, b - ends.y, height + CAP * 0.5, Vector2(CAP, wide / WALK_LANES - BOARD.y), ((lane + 0.5) / WALK_LANES - 0.5) * wide, rng)
			_lay_railing(a, b, rng, 0.08)
	for s in turns:
		if _corner(s, turns) and not broken(s, wide * 0.5):
			_part(s, height + CAP * 0.5, Vector3(wide, CAP, wide), WOOD * rng.randf_range(0.85, 1.1), rng, "board")


func gable_spans() -> Array[Vector2]:
	if gable == null or gable.kind != RoofLayout.Kind.GABLE or gable.flat() or cover != Cover.ROOF:
		return []
	var c := corners()
	if c.size() != 4:
		return []
	return [Vector2(c[1], c[2]), Vector2(c[3], length())]


func _lay_gables() -> void:
	var ends := gable_spans()
	var rng := RandomNumberGenerator.new()
	var base := height + CAP
	for i in ends.size():
		var end: Vector2 = ends[i]
		rng.seed = hash([seed, "gable", i])
		var mid: float = (end[0] + end[1]) * 0.5
		var hs: float = (end[1] - end[0] + THICKNESS) * 0.5
		match gable_kind():
			GableEnd.BOARDS:
				_lay_boards(mid, hs, base, rng)
				if not gable.thatch:
					_lay_verge(mid, hs, base, rng, "board")
			GableEnd.STEPS:
				_lay_crow_steps(mid, hs, base, rng)
			_:
				var rows: Array[Vector2] = []
				while not plastered() and gable.out_at((rows.size() + 1) * COURSE, hs) >= 0.2:
					rows.append(Vector2(rows.size(), gable.out_at((rows.size() + 1) * COURSE, hs)))
				_lay_gable_rows(mid, hs, base, rows, rng)
				if not TimberFrame.applies(self) and not gable.thatch:
					_lay_verge(mid, hs, base, rng, "cope")


## Rows are Vector2(course, half-width); the roof's infill closes what the slopes leave. Courses stop at the corners.
func _lay_gable_rows(mid: float, hs: float, base: float, rows: Array[Vector2], rng: RandomNumberGenerator) -> void:
	var h := COURSE
	var edge := hs - THICKNESS * 0.5
	var inset := 0.0 if plastered() else JOINT
	for row in rows:
		var y := base + row.x * h
		var half := minf(row.y, edge)
		var offset := (0.5 if posmod(courses() + int(row.x), 2) == 1 else 0.0) * rng.randf_range(0.3, 0.6)
		for span in _standing([[mid - half, mid + half]]):
			if not plastered():
				_lay_course(span[0], span[1], y, h, offset, rng)
			_lay_mortar([[y, h, [[span[0] + inset, span[1] - inset]]]])
		if row.y > hs - 0.01:
			for side in [-1.0, 1.0]:
				_part(mid + side * edge, y + h * 0.5, Vector3(THICKNESS, h, THICKNESS), PLASTER if plastered() else stone_color(rng), rng, "plaster" if plastered() else "block", 0.0, 0.0, mid)


## Each step is Vector3(half-width, first course, courses); above the first they stand inside the corners.
func crow_steps(hs: float) -> Array[Vector3]:
	var h := COURSE
	var steps: Array[Vector3] = []
	var k := 0
	var half := hs
	while half > TOP_STEP:
		var top := k + STEP_COURSES
		while gable.out_at(top * h, hs) > minf(half, hs - THICKNESS) - TREAD:
			top += 1
		steps.append(Vector3(half, k, top - k))
		k = top
		half = gable.out_at(k * h, hs)
	steps.append(Vector3(TOP_STEP, k, maxi(STEP_COURSES, ceili(gable.rise(1.0) / h) + 1 - k)))
	return steps


func gable_kind() -> GableEnd:
	return GableEnd.BOARDS if boarded() else gable_end


func gable_face(hs: float) -> float:
	if gable_kind() != GableEnd.STEPS:
		return hs * gable.pitch * (1.0 + gable.curve / PI)
	var out := 0.0
	for st in crow_steps(hs):
		out += 2.0 * st.x * st.z * COURSE
	return out


func _lay_crow_steps(mid: float, hs: float, base: float, rng: RandomNumberGenerator) -> void:
	var steps := crow_steps(hs)
	var rows: Array[Vector2] = []
	for st in steps:
		for c in range(st.y, st.y + st.z):
			rows.append(Vector2(c, st.x))
	_lay_gable_rows(mid, hs, base, rows, rng)
	for i in steps.size():
		var top := base + (steps[i].y + steps[i].z) * COURSE + CAP * 0.5
		var outer := steps[i].x + 0.06
		if i + 1 == steps.size():
			_add(mid, top, Vector3(outer * 2.0, CAP, THICKNESS + 0.12), rng, "cap", 0.0)
			break
		for side in [-1.0, 1.0]:
			_add(mid + side * (steps[i + 1].x + outer) * 0.5, top, Vector3(outer - steps[i + 1].x, CAP, THICKNESS + 0.12), rng, "cap", 0.0)


func _lay_boards(mid: float, hs: float, base: float, rng: RandomNumberGenerator) -> void:
	var x := -hs
	while x < hs - 0.05:
		var w := minf(BOARD.x, hs - x)
		var tall := gable.rise(1.0 - maxf(absf(x), absf(x + w)) / hs)
		if tall > 0.05 and not _standing([[mid + x, mid + x + w]]).is_empty():
			_part(mid + x + w * 0.5, base + tall * 0.5, Vector3(w - BOARD.y, tall, THICKNESS - PLASTER_INSET * 2.0), WOOD * rng.randf_range(0.85, 1.1), rng, "board", 0.0, 0.0, mid)
		x += w


func _lay_verge(mid: float, hs: float, base: float, rng: RandomNumberGenerator, kind: String) -> void:
	var ridge := Vector2(0.0, gable.rise(1.0))
	var up := Vector2(-0.01, gable.rise(1.0) - gable.rise(1.0 - 0.01 / hs)).normalized()
	var foot := ridge + up * 0.01 - up.orthogonal() * VERGE.y
	var apex := -foot.x if foot.x < 0.0 and foot.y > gable.rise(1.0 + foot.x / hs) else 0.0
	for side in [-1.0, 1.0]:
		var x := hs
		while x > apex + 0.05:
			var x1 := x
			var walked := 0.0
			var length := rng.randf_range(0.42, 0.6)
			while walked < length and x1 > apex:
				var next := maxf(x1 - 0.01, apex)
				walked += Vector2(x1 - next, gable.rise(1.0 - next / hs) - gable.rise(1.0 - x1 / hs)).length()
				x1 = next
			var hi := Vector2(x1, gable.rise(1.0 - x1 / hs))
			if hi.distance_to(Vector2(apex, gable.rise(1.0 - apex / hs))) < 0.25:
				x1 = apex
				hi = Vector2(apex, gable.rise(1.0 - apex / hs))
			var lo := Vector2(x, gable.rise(1.0 - x / hs))
			var run := hi - lo
			var at := (lo + hi) * 0.5 - run.orthogonal().normalized() * VERGE.y * 0.5
			if not _standing([[mid + side * at.x - 0.01, mid + side * at.x + 0.01]]).is_empty():
				var roll := atan(run.y / (run.x * side))
				var piece := _stone(mid + side * at.x, base + at.y, Vector3(run.length() + 0.02, VERGE.y, VERGE.x), rng, kind, 0.02, roll, 0.015, mid)
				if kind == "board":
					piece.color = WOOD * rng.randf_range(0.8, 0.95)
				stones.append(piece)
			x = x1


func _standing(spans: Array) -> Array:
	if not breaks.is_empty():
		for b in breaks[-1]:
			spans = _cut(spans, b.x, b.y)
	return spans


func _lay_parapet(a: float, total: float, rng: RandomNumberGenerator) -> void:
	rng.seed = hash([rng.seed, "parapet"])
	var y := height + CAP
	_lay_row(a, total, y + PARAPET * 0.5, Vector2(0.4, 0.75), Vector2(PARAPET, THICKNESS * 0.62), "block", rng)
	_lay_mortar([[y, PARAPET, [[a, total]]]], THICKNESS * 0.62)
	rng.seed = hash([rng.seed, "parapet-cap"])
	_lay_row(a, total, y + PARAPET + CAP * 0.4, Vector2(0.6, 1.0), Vector2(CAP * 0.8, THICKNESS * 0.74), "cap", rng)


func _lay_row(a: float, b: float, y: float, run: Vector2, size: Vector2, kind: String, rng: RandomNumberGenerator) -> void:
	var s := a
	while b - s > 0.001:
		var l := minf(rng.randf_range(run.x, run.y), b - s)
		_add(s + l * 0.5, y, Vector3(l, size.x, size.y), rng, kind, 0.02)
		s += l


func _lay_railing(a: float, total: float, rng: RandomNumberGenerator, inset := PIER * 0.5 + 0.03) -> void:
	rng.seed = hash([rng.seed, "railing"])
	var y := height + CAP
	var ends := Vector2(a, total) + Vector2(1.0, -1.0) * inset
	if ends.y - ends.x < 0.1:
		return
	var n := ceili((ends.y - ends.x) / RAIL_POSTS)
	var posts: Array[float] = []
	for i in n + 1:
		posts.append(lerpf(ends.x, ends.y, float(i) / n))
	for s in posts:
		_part(s, y + RAILING * 0.5, Vector3(0.1, RAILING, 0.1) * Vector3(rng.randf_range(0.92, 1.08), 1.0, rng.randf_range(0.92, 1.08)), WOOD * rng.randf_range(0.8, 1.1), rng, "post", 0.0, 0.02)
	for i in range(1, posts.size()):
		for h: float in [RAILS.x, RAILS.y]:
			_rail(posts[i - 1], posts[i], y + h, Vector3(0.04, 0.08 if h == RAILS.y else 0.06, 0.06), WOOD * rng.randf_range(0.8, 1.1))


func _rail(a: float, b: float, y: float, size: Vector3, color: Color, kind := "rail") -> void:
	var p: Vector3 = frame_at(a).point + Vector3.UP * y
	var q: Vector3 = frame_at(b).point + Vector3.UP * y
	_between(p, q, size, color, kind, (a + b) * 0.5)


## `size`: (overrun past the ends, depth, thickness).
func _between(p: Vector3, q: Vector3, size: Vector3, color: Color, kind: String, s: float) -> void:
	var x := (q - p).normalized()
	var z := x.cross(Vector3.UP).normalized()
	_world(Transform3D(Basis(x, z.cross(x), z).scaled_local(Vector3(p.distance_to(q) + size.x, size.y, size.z)), (p + q) * 0.5), color, kind, s)


## Over posts its footing stops `open` under the foot; it leaves out `gap`, the heights a corner window opens over.
func _lay_pier(s: float, rng: RandomNumberGenerator, wet: RandomNumberGenerator, open: float, gap: Vector2) -> void:
	_lay_footing(s, depth_at(s), Vector3(PIER, 0.0, PIER), "pier", wet, -open)
	var y := 0.0
	var top_y := height + CAP + (0.0 if cover == Cover.ROOF else 0.35)
	while y < top_y - 0.05:
		if gap != Vector2.ZERO and y >= gap.x - 0.05 and y < gap.y:
			y = gap.y
			continue
		var h := minf(rng.randf_range(0.36, 0.5), top_y - y)
		if gap != Vector2.ZERO and y < gap.x:
			h = minf(h, gap.x - y)
		_add(s, y + h * 0.5, Vector3(PIER, h, PIER) * rng.randf_range(0.97, 1.03), rng, "pier", 0.03)
		y += h
	if cover != Cover.ROOF:
		_add(s, top_y + 0.09, Vector3(PIER + 0.14, 0.18, PIER + 0.14), rng, "pier", 0.0)
		stones[-1].color *= TOP_TONE


func _lay_footing(s: float, depth: float, size: Vector3, kind: String, rng: RandomNumberGenerator, top := 0.0) -> void:
	var y := -depth
	while y < top - 0.05:
		var h := minf(rng.randf_range(0.34, 0.46), top - y)
		_add(s, y + h * 0.5, Vector3(size.x, h, size.z), rng, kind, 0.02)
		y += h


func _add(s: float, y: float, size: Vector3, rng: RandomNumberGenerator, kind: String, wobble: float) -> void:
	stones.append(_stone(s, y, size, rng, kind, wobble))


## Given a straight `face`'s arc length, it lies on that face's line carried on past its corners.
func _stone(s: float, y: float, size: Vector3, rng: RandomNumberGenerator, kind: String, wobble: float, roll := 0.0, jitter := 0.015, face := INF) -> Dictionary:
	var frame := frame_at(s)
	if is_finite(face):
		var line := frame_at(face)
		frame = {"point": line.point + line.tangent * (s - face), "tangent": line.tangent}
	var basis := Basis(frame.tangent, Vector3.UP, frame.tangent.cross(Vector3.UP)) * Basis(Vector3.BACK, roll)
	basis = basis * Basis.from_euler(Vector3(rng.randf_range(-wobble, wobble), rng.randf_range(-wobble, wobble) * 2.0, rng.randf_range(-wobble, wobble)))
	var origin: Vector3 = frame.point + Vector3.UP * y
	origin += basis.z * rng.randf_range(-jitter, jitter)
	var color := stone_color(rng)
	if kind in TOP_KINDS:
		color *= TOP_TONE
	return {"xform": Transform3D(basis.scaled_local(size), origin), "color": color, "kind": kind, "s": s, "y": y, "size": size, "ao": clampf(0.6 + (y + depth_at(s)) * 0.25, 0.6, 1.0), "variant": rng.randi() % 3}


func perches() -> PackedVector3Array:
	var out := PackedVector3Array()
	var tops: Array[Vector3] = []
	var fittings: Array[Vector3] = []
	for st in stones:
		var kind: String = st.kind
		var x: Transform3D = st.xform
		if kind in ["finial", "hood", "nest"]:
			out.append(x.origin + Vector3.UP * x.basis.y.length() * 0.5)
		if kind in ["pole", "iron", "finial", "hood"]:
			fittings.append(x.origin)
			continue
		if cover == Cover.ROOF or not (kind in ["cap", "cope", "merlon", "pier", "post"] or kind == "rail" and st.y > FENCE_HEIGHT * 0.6):
			continue
		var top := x.origin + x.basis.y * 0.5
		var run := x.basis.x
		var n := maxi(1, floori(run.length() / PERCH_STEP))
		for i in n:
			tops.append(top + run * ((i + 0.5) / n - 0.5))
	tops.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	var taken := {}
	for p in tops:
		var cell := Vector2i(floori(p.x / PERCH_STEP), floori(p.z / PERCH_STEP))
		var clear := true
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for q: Vector3 in taken.get(cell + Vector2i(dx, dz), []):
					if Vector2(q.x - p.x, q.z - p.z).length() < PERCH_STEP:
						clear = false
		if fittings.any(func(f: Vector3) -> bool: return Vector2(f.x - p.x, f.z - p.z).length() < 0.3):
			clear = false
		if clear:
			taken.get_or_add(cell, []).append(p)
			out.append(p)
	return out


## All `build` reads but `gable`: a wall lays its copy of the gable from its roof and compares the roof's own inputs.
const INPUTS: Array[StringName] = [&"points", &"height", &"rise", &"seed", &"closed", &"top", &"cover", &"fence", &"finish", &"wear", &"foundation", &"planks", &"gable_end", &"openings", &"lanterns", &"flags", &"clutter", &"ruins", &"supports", &"resting", &"joined", &"older"]


## To build on another thread while this one is edited.
func inputs() -> WallLayout:
	var w := WallLayout.new()
	for k in INPUTS:
		var v: Variant = get(k)
		w.set(k, v.duplicate() if v is Array else v)
	w.gable = gable
	return w


func same_inputs(other: WallLayout) -> bool:
	for k in INPUTS:
		if get(k) != other.get(k):
			return false
	return true


func set_data(d: Dictionary) -> void:
	for k in ["height", "rise", "seed", "closed", "top", "fence", "finish", "wear", "foundation", "planks", "gable_end"]:
		set(k, d[k])
	for k in ["points", "openings", "lanterns", "flags", "clutter", "ruins"]:
		(get(k) as Array).assign(Array(d[k]))


func adopt(built: WallLayout) -> void:
	_sampled_from = built._sampled_from
	laid_points = built.laid_points
	laid_rise = built.laid_rise
	gable = built.gable
	if built.samples != samples:
		_segment_cells = built._segment_cells
	samples = built.samples
	lengths = built.lengths
	depths = built.depths
	plinths = built.plinths
	grounds = built.grounds
	bounds = built.bounds
	stones = built.stones
	_hung = built._hung
	_stone_scale = built._stone_scale
	apertures = built.apertures
	flames = built.flames
	cloths = built.cloths
	breaks = built.breaks
	floor_y = built.floor_y
	floor_outline = built.floor_outline
	_laid_count += 1
	laid = _laid_count


## Without its stones, safe to read on another thread while this one is edited.
func snapshot() -> WallLayout:
	var w := WallLayout.new()
	w.seed = seed
	w.height = height
	w.closed = closed
	w.samples = samples.duplicate()
	w.lengths = lengths.duplicate()
	w.depths = depths.duplicate()
	w.plinths = plinths.duplicate()
	w.grounds = grounds.duplicate()
	w.bounds = bounds
	w.apertures = apertures.duplicate(true)
	w.breaks = breaks.duplicate()
	w.fence = fence
	w.finish = finish
	w.wear = wear
	w.foundation = foundation
	w.planks = planks
	w.cover = cover
	w.resting = resting.duplicate()
	w.joined = joined.duplicate()
	return w


func frame_at(s: float) -> Dictionary:
	var at := _segment(s)
	var i: int = at[0]
	var tan := samples[i] - samples[i - 1]
	tan.y = 0.0
	return {"point": samples[i - 1].lerp(samples[i], at[1]), "tangent": tan.normalized() if tan.length() > 1e-5 else Vector3.RIGHT}


func _segment(s: float) -> Array:
	if closed and lengths.size() > 1:
		s = fposmod(s, length())
	var i := clampi(lengths.bsearch(s), 1, samples.size() - 1)
	var l0 := lengths[i - 1]
	var l1 := lengths[i]
	return [i, 0.0 if l1 <= l0 else clampf((s - l0) / (l1 - l0), 0.0, 1.0)]


func depth_at(s: float) -> float:
	return _along(depths, s)


func ground_at(s: float) -> float:
	return _along(grounds, s)


func plinth_at(s: float) -> float:
	return _along(plinths, s)


func _along(per_sample: PackedFloat32Array, s: float) -> float:
	if per_sample.size() < 2:
		return 0.0
	var at := _segment(s)
	return lerpf(per_sample[at[0] - 1], per_sample[at[0]], at[1])


func _over_bed(drop: float) -> Array:
	var out := []
	var from := -1.0
	for i in samples.size():
		if depths[i] > drop and from < 0.0:
			from = lengths[maxi(i - 1, 0)]
		elif depths[i] <= drop and from >= 0.0:
			out.append([from, lengths[i]])
			from = -1.0
	if from >= 0.0:
		out.append([from, length()])
	return out


func _water_arches() -> Array[float]:
	var out: Array[float] = []
	if closed or fence:
		return out
	for span in _over_bed(WADE_UNDER):
		var between: float = maxf(span[1] - span[0] - ARCH_HALF * 2.0, 0.0)
		var n := floori(between / ARCH_SPACING) + 1
		var pitch := minf(between / (n - 1), ARCADE_PITCH) if n > 1 else 0.0
		var first: float = (span[0] + span[1] - pitch * (n - 1)) * 0.5
		for i in n:
			out.append(first + pitch * i)
	return out


func blocks_swim(a: Vector2, b: Vector2) -> bool:
	if fence or not bounds.grow(THICKNESS).intersects(Rect2(a, Vector2.ZERO).expand(b).grow(0.01)):
		return false
	# Only segments in the cells the step and its end's reach meet can stop it: a pond's dozens of swimmers ask each frame.
	var grid := segment_cells()
	var crossed := {}
	for c in PathLayout.cells_along(a, b):
		for i: int in grid.get(c, []):
			crossed[i] = true
	for i: int in crossed:
		var p := Vector2(samples[i].x, samples[i].z)
		var q := Vector2(samples[i + 1].x, samples[i + 1].z)
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, p, q)
		if hit != null and not _swims_through(lengths[i] + p.distance_to(hit)):
			return true
	var reach := SWIM_REACH
	var near := {}
	for c in PathLayout.cells_along(b - Vector2.ONE * reach, b + Vector2.ONE * reach):
		for i: int in grid.get(c, []):
			near[i] = true
	if near.is_empty():
		return false
	var ends := near.keys()
	ends.sort()
	var end := _nearest_s(b, ends)
	var at: Vector3 = frame_at(end).point
	return Vector2(at.x, at.z).distance_to(b) < reach and not _swims_through(end)


func _swims_through(s: float) -> bool:
	return broken(s, -SWIM_CLEAR) or apertures.any(func(o): return o.style == Family.ARCHWAY and absf(offset(s, o.s)) < o.half - SWIM_CLEAR)


func closest_s(p: Vector3) -> float:
	return _nearest_s(Vector2(p.x, p.z), range(samples.size() - 1))


func _nearest_s(at: Vector2, segments: Array) -> float:
	var best := INF
	var best_s := 0.0
	for i: int in segments:
		var foot := _foot(at, i)
		if foot.y < best:
			best = foot.y
			best_s = lerpf(lengths[i], lengths[i + 1], foot.x)
	return best_s


## (fraction along segment `i`, distance from `at`)
func _foot(at: Vector2, i: int) -> Vector2:
	var a := Vector2(samples[i].x, samples[i].z)
	var b := Vector2(samples[i + 1].x, samples[i + 1].z)
	var t := clampf((at - a).dot(b - a) / maxf((b - a).length_squared(), 1e-9), 0.0, 1.0)
	return Vector2(t, a.lerp(b, t).distance_to(at))


func segment_cells() -> Dictionary:
	if _segment_cells.is_empty() and samples.size() > 1:
		if samples != _cells_for:
			_cells_for = samples.duplicate()
			_cells_made = PathLayout.segment_grid(samples)
		_segment_cells = _cells_made
	return _segment_cells


## Piers choose the anchors; corner cutting only touches the spans between them.
func finish_stroke() -> void:
	if points.size() < 3:
		return
	var anchors: Array[int] = [0]
	for s in _bends():
		var p: Vector3 = frame_at(s).point
		var best := anchors[-1]
		var distance := INF
		for i in range(anchors[-1] + 1, points.size() - 1):
			var d := Vector2(points[i].x - p.x, points[i].z - p.z).length_squared()
			if d < distance:
				distance = d
				best = i
		if best > anchors[-1]:
			anchors.append(best)
	anchors.append(points.size() - 1)
	var result: Array[Vector3] = []
	for k in anchors.size() - 1:
		var span: Array[Vector3] = points.slice(anchors[k], anchors[k + 1] + 1)
		for _pass in 2:
			var filtered := span.duplicate()
			for i in range(1, span.size() - 1):
				filtered[i] = span[i - 1] * 0.25 + span[i] * 0.5 + span[i + 1] * 0.25
			span = filtered
		for _pass in 3:
			var cut: Array[Vector3] = [span[0]]
			for i in span.size() - 1:
				cut.append(span[i].lerp(span[i + 1], 0.25))
				cut.append(span[i].lerp(span[i + 1], 0.75))
			cut.append(span[-1])
			span = cut
		# Uniform arc-length spacing keeps the stored curve small and independent of hand speed.
		result.append(span[0])
		var remaining := SAMPLE
		for i in span.size() - 1:
			var a := span[i]
			var b := span[i + 1]
			var distance := a.distance_to(b)
			while distance >= remaining:
				a = a.lerp(b, remaining / distance)
				result.append(a)
				distance -= remaining
				remaining = SAMPLE
			remaining -= distance
		if result[-1].distance_to(span[-1]) < SAMPLE * 0.25:
			result.pop_back()
	result.append(points[-1])
	points = result


func resample(ground: Callable, water := Callable(), revision := 0) -> void:
	var key := [points.duplicate(), height, rise, foundation, seed, closed, top, fence, lanterns.duplicate(), ruins.duplicate(), supports.duplicate(), revision, ground, water]
	if key == _sampled_from:
		return
	_sampled_from = key
	samples.clear()
	lengths.clear()
	depths.clear()
	plinths.clear()
	grounds.clear()
	breaks.clear()
	bounds = Rect2()
	_segment_cells = {}
	if points.size() == 0:
		return
	if not fence:
		_break()
	var footing := ground
	if water.is_valid():
		footing = func(x: float, z: float) -> float: return maxf(ground.call(x, z), water.call(x, z))
	var held := _resample_curve(footing)
	var stilted := supports.is_empty() and stilt_span(foundation, rise) > 0.0
	for q in samples:
		grounds.append(ground.call(q.x, q.z))
		depths.append(0.0 if held else maxf(q.y - grounds[-1], 0.0))
		plinths.append(0.0 if stilted or held else maxf(q.y + SINK - maxf(footing.call(q.x, q.z), rest(q.x, q.z)), 0.0))
	bounds = Rect2(Vector2(samples[0].x, samples[0].z), Vector2.ZERO)
	for q in samples:
		bounds = bounds.expand(Vector2(q.x, q.z))


## True when the loop stands on a build's top.
func _resample_curve(ground: Callable) -> bool:
	var dense: Array[Vector3] = []
	var n := points.size()
	for i in n if closed else n - 1:
		var a := points[i]
		var b := points[(i + 1) % n]
		var count := maxi(1, ceili(a.distance_to(b) / SAMPLE))
		for j in count:
			dense.append(a.lerp(b, float(j) / count))
	dense.append(points[0] if closed else points[-1])
	var foot := INF
	var held := -INF
	if closed:
		# On the ground a loop stands level on its lowest ground, raised by `rise`; on other builds, on the highest top under it.
		for q in dense:
			foot = minf(foot, ground.call(q.x, q.z))
			held = maxf(held, rest(q.x, q.z))
		if held > -INF:
			foot = held
		else:
			foot += rise
	var acc := 0.0
	for i in dense.size():
		var q := dense[i]
		q.y = (foot if closed else maxf(ground.call(q.x, q.z), rest(q.x, q.z))) - SINK
		if i > 0:
			acc += Vector2(q.x - samples[-1].x, q.z - samples[-1].z).length()
		samples.append(q)
		lengths.append(acc)
	return held > -INF


func stands_at() -> float:
	return samples[0].y + SINK - (laid_rise if supports.is_empty() else 0.0)


func rest(x: float, z: float) -> float:
	var best := -INF
	for s in supports:
		best = maxf(best, s.rest(x, z))
	return best


func hides(p: Vector3) -> bool:
	return hidden(p, joined, resting)


static func hidden(p: Vector3, joins: Array[Massing], rests: Array[Massing]) -> bool:
	for s in joins:
		if s.holds(p):
			return true
	for s in rests:
		if s.covers(p):
			return true
	return false


static func circle(center: Vector3, radius: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := maxi(12, ceili(TAU * radius / 0.35))
	for i in n:
		var a := TAU * i / n
		out.append(center + Vector3(cos(a), 0.0, sin(a)) * radius)
	return out


static func rectangle(a: Vector3, b: Vector3, depth: float) -> Array[Vector3]:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var across := along.cross(Vector3.UP).normalized() * depth * 0.5
	return [a - across, b - across, b + across, a + across]


## Calls `each(sample, i, t)`, `t` of the way from point `i` to the next; `from` starts at that point.
static func smooth(stroke: Array[Vector3], each: Callable, from := 0) -> void:
	for i in range(from, stroke.size() - 1):
		var p0 := stroke[maxi(i - 1, 0)]
		var p3 := stroke[mini(i + 2, stroke.size() - 1)]
		var seg := maxi(1, int(ceil(stroke[i].distance_to(stroke[i + 1]) / SAMPLE)))
		for j in seg:
			var t := float(j) / seg
			each.call(_catmull(p0, stroke[i], stroke[i + 1], p3, t), i, t)
	if stroke.size() > 0:
		each.call(stroke[-1], stroke.size() - 1, 0.0)


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
