class_name DecorationLayout
extends RefCounted

## One catalogue for placement, style choices and geometry. The stored style never changes on reload.
## Every style but the strings stands on every mount but a span, and a new one is a present the style tool turns into
## the rest; a string hangs on a span alone, between the two points a stroke of the decorations tool joins.
const STYLES := [
	{"name": "Present"},
	{"name": "Planter"},
	{"name": "Bench"},
	{"name": "Rain barrel"},
	{"name": "Woodpile"},
	{"name": "Steps"},
	{"name": "Gatepost lantern"},
	{"name": "Standing torch"},
	{"name": "Campfire"},
	{"name": "Chair"},
	{"name": "Table"},
	{"name": "Settle"},
	{"name": "Bed"},
	{"name": "Shelf"},
	{"name": "Rug"},
	{"name": "Stool"},
	{"name": "Chest"},
	{"name": "Potted plant"},
	{"name": "Candle stand"},
	{"name": "Table and chairs"},
	{"name": "Garden bench"},
	{"name": "Trough planter"},
	{"name": "Parasol"},
	{"name": "String lights"},
	{"name": "Lantern"},
	{"name": "Lamp post"},
	{"name": "Crates"},
	{"name": "Market stall"},
	{"name": "Anvil"},
	{"name": "Flower box"},
	{"name": "Carved pumpkin"},
	{"name": "Bird nest"},
	{"name": "Lantern string", "string": true},
	{"name": "Flag string", "string": true},
]
const PRESENT := 0
## The surface a decoration stands on: at a house's "foundation", on the "ground", on a house's "floor" or on a flat
## roof's "deck"; or the "span" a string hangs across, from `at` to `to`, each end on a pole `drop` tall or tied where
## it is.
const MOUNTS := ["foundation", "ground", "floor", "deck", "span"]
## A string's sag a metre of its span across the ground, its least, and its most.
const SAG := 0.07
const SAG_LEAST := 0.05
const SAG_MOST := 1.0
## The span across the ground a string hangs over, least and most, and the steepest it climbs, rise over run.
const SPAN_LEAST := 1.5
const SPAN_MOST := 20.0
const SPAN_STEEPEST := 1.0
## How tall a pole stands under a string's end on the ground.
const POLE := 2.6
## Along a string, a lantern hangs every LANTERN_EVERY and a flag every FLAG_EVERY metres.
const LANTERN_EVERY := 1.1
const FLAG_EVERY := 0.34
const WOOD := Color(0.30, 0.19, 0.10)
## Furniture: indoors, under dim light, it wants a paler wood than the weathered outdoor pieces.
const OAK := Color(0.54, 0.38, 0.22)
const STONE := Color(0.53, 0.51, 0.44)
const IRON := Color(0.12, 0.13, 0.14)
const LINEN := Color(0.86, 0.82, 0.72)
const CLAY := Color(0.62, 0.33, 0.2)
const SOIL := Color(0.12, 0.09, 0.06)
const WAX := Color(0.93, 0.88, 0.74)
const PAPER := Color(0.62, 0.12, 0.14)
const RIBBON := Color(0.9, 0.78, 0.4)
const PUMPKIN := Color(0.86, 0.42, 0.08)
const STALK := Color(0.28, 0.36, 0.12)
## A carved face is glass: it glows at night in its build's glow colour, as windows do.
const CANDLE := Color(0.95, 0.62, 0.2)
const TWIG := Color(0.38, 0.27, 0.15)
const EGG := Color(0.72, 0.84, 0.86)
const PRODUCE: Array[Color] = [Color(0.72, 0.12, 0.1), Color(0.86, 0.6, 0.12), Color(0.36, 0.56, 0.18), Color(0.5, 0.22, 0.44)]
## Cloth: rugs, blankets and canvas take one of these by seed.
const DYES: Array[Color] = [Color(0.55, 0.16, 0.12), Color(0.17, 0.27, 0.48), Color(0.66, 0.5, 0.16), Color(0.24, 0.4, 0.26)]
var parts: Array[Dictionary] = []
var flames: Array[Transform3D] = []
## Each flower: its `xform` and `color`.
var flowers: Array[Dictionary] = []
## Where the style tool's own model is drawn flat, as on a present's lid.
var pictures: Array[Transform3D] = []
var bounds := AABB()


## A box `size` centred `at`, turned `turn` about the vertical and then leaning `tilt` about its own width, its
## front (+z) dropping for a positive tilt.
func box(at: Vector3, size: Vector3, color: Color, kind: String, turn := 0.0, tilt := 0.0) -> void:
	_part(Transform3D((Basis(Vector3.UP, turn) * Basis(Vector3.RIGHT, tilt)).scaled_local(size), at), color, kind)


## A beam `thick` square from `a` to `b`.
func beam(a: Vector3, b: Vector3, thick: float, color: Color, kind: String) -> void:
	var x := Transform3D(Basis.looking_at(b - a, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.BACK), (a + b) * 0.5)
	_part(x.scaled_local(Vector3(thick, thick, a.distance_to(b))), color, kind)


func _part(x: Transform3D, color: Color, kind: String) -> void:
	parts.append({"xform": x, "color": color, "kind": kind, "ao": 1.0, "variant": 0})
	var b := x * AABB(Vector3.ONE * -0.5, Vector3.ONE)
	bounds = b if parts.size() == 1 else bounds.merge(b)


## The style named `name`, or -1.
static func named(name: String) -> int:
	for k in STYLES.size():
		if STYLES[k].name == name:
			return k
	return -1


## Whether `style` stands on `mount`: a string on a span, and every other style anywhere else.
static func stands(style: int, mount: String) -> bool:
	return STYLES[style].get("string", false) == (mount == "span")


## The styles that stand on `mount`, in the order of STYLES.
static func standing(mount: String) -> Array:
	return range(STYLES.size()).filter(func(k: int) -> bool: return stands(k, mount))


## How far a string across `span` (from its first end to its second) sags below the line between them at its middle.
static func sag(span: Vector3) -> float:
	return clampf(SAG * Vector2(span.x, span.z).length(), SAG_LEAST, SAG_MOST)


## Where a string across `span` hangs a share `t` of the way along it from its first end: a parabola through both ends.
static func hang_at(span: Vector3, t: float) -> Vector3:
	return span * t + Vector3.DOWN * 4.0 * sag(span) * t * (1.0 - t)


## The room a string across `span` takes about its rope and what hangs from it, poles left out, in its frame.
static func strung(span: Vector3) -> AABB:
	var low := minf(0.0, span.y) - sag(span) - 0.55
	return AABB(Vector3(0.0, low, -0.2), Vector3(span.x, maxf(0.0, span.y) + 0.2 - low, 0.4))


## Style `style` as it stands on `mount`: backed against the wall at a house's foundation, a string from its first end
## across `span` with the poles `drop` under its ends, else centred where it is put.
func build(style: int, seed: int, rise := 0.6, mount := "ground", span := Vector3.ZERO, drop := Vector2.ZERO) -> void:
	parts.clear()
	flames.clear()
	flowers.clear()
	pictures.clear()
	var dye := DYES[posmod(seed, DYES.size())]
	match STYLES[style].name:
		"Present":
			box(Vector3(0, 0.17, 0), Vector3(0.42, 0.34, 0.42), PAPER, "")
			for turn in [0.0, PI * 0.5]:
				box(Vector3(0, 0.17, 0), Vector3(0.43, 0.345, 0.07), RIBBON, "", turn)
			for side in [-1.0, 1.0]:
				box(Vector3(0.13 + side * 0.05, 0.37, -0.13), Vector3(0.1, 0.05, 0.04), RIBBON, "", side * 0.6)
			pictures.append(Transform3D(Basis().scaled(Vector3(5.5, 0.4, 5.5)), Vector3(-0.02, 0.346, 0.02)))
		"Planter":
			box(Vector3(0, 0.18, 0.33), Vector3(1.1, 0.32, 0.5), WOOD, "board")
			box(Vector3(0, 0.35, 0.33), Vector3(0.96, 0.04, 0.36), Color(0.12, 0.09, 0.06), "")
			for i in 5:
				flower(Transform3D(Basis().scaled(Vector3.ONE * 1.2), Vector3((i - 2) * 0.19, 0.36, 0.33 + sin(i * 2.1) * 0.09)), seed)
			bounds = bounds.expand(Vector3(0, 0.9, 0.6))
		"Bench":
			for x in [-0.52, 0.52]:
				for z in [0.16, 0.52]:
					box(Vector3(x, 0.22, z), Vector3(0.1, 0.44, 0.1), WOOD, "board")
			for z in [0.16, 0.34, 0.52]:
				box(Vector3(0, 0.47, z), Vector3(1.35, 0.09, 0.15), WOOD.lightened(0.15), "board")
			for y in [0.66, 0.85]:
				box(Vector3(0, y, 0.10), Vector3(1.35, 0.14, 0.07), WOOD, "board")
		"Rain barrel":
			for i in 10:
				var a := i * TAU / 10
				box(Vector3(sin(a) * 0.28, 0.42, 0.4 + cos(a) * 0.28), Vector3(0.19, 0.8, 0.08), WOOD.lightened(0.02 * (i % 3)), "board", a)
				for y in [0.15, 0.68]:
					box(Vector3(sin(a) * 0.30, y, 0.4 + cos(a) * 0.30), Vector3(0.20, 0.055, 0.035), IRON, "iron", a)
			box(Vector3(0, 0.74, 0.4), Vector3(0.44, 0.025, 0.44), Color(0.15, 0.27, 0.3), "")
		"Woodpile":
			for row in 3:
				for col in 4 - row:
					box(Vector3((col - (3 - row) * 0.5) * 0.24, 0.13 + row * 0.21, 0.4), Vector3(0.21, 0.21, 0.65), WOOD, "board", sin(seed + col) * 0.04)
		"Steps":
			var count := clampi(ceili(rise / 0.2), 1, 24)
			for i in count:
				var height := maxf(0.1, rise) * (count - i) / count
				box(Vector3(0, height * 0.5, 0.18 + i * 0.3), Vector3(1.2, height, 0.32), STONE, "block")
		"Gatepost lantern":
			for i in 4:
				box(Vector3(0, 0.12 + i * 0.23, 0.35), Vector3(0.38, 0.22, 0.38), STONE, "block", 0.035 * (i % 2))
			box(Vector3(0, 0.95, 0.35), Vector3(0.48, 0.1, 0.48), STONE, "block")
			lantern(Vector3(0, 1.08, 0.35))
		"Standing torch":
			box(Vector3(0, 0.65, 0), Vector3(0.09, 1.3, 0.09), WOOD, "board")
			box(Vector3(0, 1.27, 0), Vector3(0.16, 0.22, 0.16), IRON, "iron")
			flame(Vector3(0, 1.47, 0), Vector3(0.13, 0.3, 0.13))
		"Campfire":
			for i in 9:
				var a := i * TAU / 9
				box(Vector3(sin(a) * 0.45, 0.1, cos(a) * 0.45), Vector3(0.25, 0.2, 0.22), STONE, "block", a)
			for i in 3:
				box(Vector3(0, 0.14 + i * 0.05, 0), Vector3(0.16, 0.16, 0.65), WOOD, "board", i * TAU / 3)
			for i in 3:
				flame(Vector3((i - 1) * 0.12, 0.38, 0), Vector3(0.14, 0.38 + i * 0.04, 0.14))

		"Chair":
			_chair(Vector3.ZERO, 0.0)
		"Table":
			box(Vector3(0, 0.74, 0), Vector3(1.3, 0.06, 0.8), OAK.lightened(0.12), "board")
			for x in [-0.56, 0.56]:
				for z in [-0.31, 0.31]:
					box(Vector3(x, 0.355, z), Vector3(0.07, 0.71, 0.07), OAK, "board")
		"Settle":
			box(Vector3(0, 0.44, 0), Vector3(1.3, 0.06, 0.34), OAK.lightened(0.12), "board")
			for x in [-0.55, 0.55]:
				box(Vector3(x, 0.21, 0), Vector3(0.06, 0.42, 0.3), OAK, "board")
			box(Vector3(0, 0.8, -0.16), Vector3(1.3, 0.66, 0.05), OAK, "board")
		"Bed":
			box(Vector3(0, 0.18, 0), Vector3(1.0, 0.26, 2.0), OAK, "board")
			box(Vector3(0, 0.37, 0), Vector3(0.92, 0.12, 1.9), LINEN, "")
			box(Vector3(0, 0.44, 0.3), Vector3(0.98, 0.05, 1.3), dye, "")
			box(Vector3(0, 0.48, -0.7), Vector3(0.6, 0.1, 0.3), LINEN.lightened(0.08), "")
			box(Vector3(0, 0.5, -0.98), Vector3(1.04, 1.0, 0.07), OAK, "board")
		"Shelf":
			box(Vector3(0, 0.8, -0.15), Vector3(1.0, 1.6, 0.04), OAK, "board")
			for x in [-0.48, 0.48]:
				box(Vector3(x, 0.8, 0.0), Vector3(0.04, 1.6, 0.34), OAK, "board")
			for y in [0.3, 0.8, 1.3]:
				box(Vector3(0, y, 0.0), Vector3(0.92, 0.04, 0.32), OAK.lightened(0.12), "board")
			box(Vector3(-0.2, 0.95, 0.0), Vector3(0.36, 0.26, 0.2), dye, "")
			box(Vector3(0.22, 0.42, 0.0), Vector3(0.18, 0.2, 0.18), CLAY, "")
			box(Vector3(0.12, 1.42, 0.0), Vector3(0.5, 0.2, 0.22), DYES[posmod(seed + 1, DYES.size())], "")
		"Rug":
			box(Vector3(0, 0.008, 0), Vector3(1.8, 0.016, 1.2), dye, "")
			box(Vector3(0, 0.012, 0), Vector3(1.5, 0.016, 0.9), DYES[posmod(seed + 2, DYES.size())].lightened(0.15), "")
		"Stool":
			box(Vector3(0, 0.46, 0), Vector3(0.34, 0.05, 0.34), OAK.lightened(0.12), "board")
			for i in 3:
				var a := i * TAU / 3.0
				box(Vector3(sin(a) * 0.1, 0.22, cos(a) * 0.1), Vector3(0.045, 0.46, 0.045), OAK, "board", a, -0.16)
		"Chest":
			box(Vector3(0, 0.22, 0), Vector3(0.8, 0.44, 0.48), OAK, "board")
			box(Vector3(0, 0.49, 0), Vector3(0.84, 0.1, 0.52), OAK.lightened(0.12), "board")
			for x in [-0.26, 0.26]:
				box(Vector3(x, 0.27, 0), Vector3(0.05, 0.56, 0.54), IRON, "iron")
		"Potted plant":
			box(Vector3(0, 0.17, 0), Vector3(0.34, 0.34, 0.34), CLAY, "")
			box(Vector3(0, 0.345, 0), Vector3(0.28, 0.02, 0.28), SOIL, "")
			for i in 3:
				flower(Transform3D(Basis(Vector3.UP, i * 2.1).scaled(Vector3.ONE * 1.5), Vector3(sin(i * 2.1) * 0.07, 0.35, cos(i * 2.1) * 0.07)), seed)
			bounds = bounds.expand(Vector3(0, 1.0, 0))
		"Candle stand":
			box(Vector3(0, 0.03, 0), Vector3(0.3, 0.06, 0.3), IRON, "iron")
			box(Vector3(0, 0.66, 0), Vector3(0.05, 1.24, 0.05), IRON, "iron")
			box(Vector3(0, 1.29, 0), Vector3(0.2, 0.04, 0.2), IRON, "iron")
			box(Vector3(0, 1.37, 0), Vector3(0.06, 0.12, 0.06), WAX, "")
			flame(Vector3(0, 1.49, 0), Vector3(0.07, 0.14, 0.07))
		"Table and chairs":
			box(Vector3(0, 0.03, 0), Vector3(0.45, 0.06, 0.45), IRON, "iron")
			box(Vector3(0, 0.38, 0), Vector3(0.07, 0.7, 0.07), IRON, "iron")
			box(Vector3(0, 0.74, 0), Vector3(0.8, 0.05, 0.8), OAK.lightened(0.12), "board")
			for side in [-1.0, 1.0]:
				_chair(Vector3(0.72 * side, 0, 0), -side * PI * 0.5)
		"Garden bench":
			box(Vector3(0, 0.44, 0), Vector3(1.4, 0.06, 0.4), OAK.lightened(0.12), "board")
			for x in [-0.62, 0.62]:
				box(Vector3(x, 0.32, -0.02), Vector3(0.07, 0.64, 0.44), IRON, "iron")
			box(Vector3(0, 0.78, -0.2), Vector3(1.4, 0.36, 0.05), OAK.lightened(0.12), "board", 0.0, -0.18)
		"Trough planter":
			box(Vector3(0, 0.22, 0), Vector3(1.2, 0.44, 0.42), OAK, "board")
			box(Vector3(0, 0.445, 0), Vector3(1.1, 0.02, 0.34), SOIL, "")
			for i in 5:
				flower(Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3.ONE * 1.3), Vector3((i - 2) * 0.21, 0.45, sin(i * 2.1) * 0.08)), seed)
			bounds = bounds.expand(Vector3(0, 1.1, 0))
		"Parasol":
			box(Vector3(0, 0.06, 0), Vector3(0.44, 0.12, 0.44), STONE, "block")
			box(Vector3(0, 1.1, 0), Vector3(0.05, 2.2, 0.05), OAK, "board")
			for i in 4:
				var a := i * TAU / 4.0
				var cloth := dye if i % 2 == 0 else LINEN
				box(Vector3(sin(a) * 0.52, 1.96, cos(a) * 0.52), Vector3(1.5, 0.03, 1.08), cloth, "", a, 0.42)
			box(Vector3(0, 2.24, 0), Vector3(0.08, 0.1, 0.08), OAK, "board")
		"String lights":
			var hang: Array[Vector3] = []
			for i in 7:
				var x := lerpf(-1.25, 1.25, i / 6.0)
				hang.append(Vector3(x, 2.05 - 0.28 * (1.0 - pow(x / 1.25, 2.0)), 0))
			for x in [-1.25, 1.25]:
				box(Vector3(x, 1.06, 0), Vector3(0.07, 2.12, 0.07), OAK, "board")
			for i in 6:
				beam(hang[i], hang[i + 1], 0.02, IRON, "iron")
			for i in range(1, 6):
				flame(hang[i] - Vector3.UP * 0.07, Vector3(0.06, 0.09, 0.06))
		"Lantern":
			box(Vector3(0, 0.02, 0), Vector3(0.26, 0.04, 0.26), IRON, "iron")
			for corner in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
				box(Vector3(corner.x * 0.1, 0.19, corner.y * 0.1), Vector3(0.025, 0.32, 0.025), IRON, "iron")
			lantern(Vector3(0, 0.18, 0))
			box(Vector3(0, 0.44, 0), Vector3(0.12, 0.08, 0.02), IRON, "iron")
		"Lamp post":
			box(Vector3(0, 0.1, 0), Vector3(0.36, 0.2, 0.36), STONE, "block")
			box(Vector3(0, 1.2, 0), Vector3(0.08, 2.0, 0.08), IRON, "iron")
			box(Vector3(0, 2.22, 0), Vector3(0.14, 0.04, 0.14), IRON, "iron")
			lantern(Vector3(0, 2.36, 0))
			box(Vector3(0, 2.62, 0), Vector3(0.06, 0.08, 0.06), IRON, "iron")
		"Crates":
			for i in 3:
				var at := Vector3(-0.27 + 0.54 * i, 0.25, sin(seed + i) * 0.04) if i < 2 else Vector3(-0.02, 0.75, 0.0)
				var turn := sin(seed * 1.7 + i) * 0.12 + (0.35 if i == 2 else 0.0)
				box(at, Vector3(0.5, 0.5, 0.5), WOOD.lightened(0.2 + 0.04 * i), "board", turn)
				box(at, Vector3(0.52, 0.08, 0.52), WOOD, "board", turn)
		"Market stall":
			box(Vector3(0, 0.45, 0.1), Vector3(1.8, 0.9, 0.7), WOOD.lightened(0.1), "board")
			box(Vector3(0, 0.92, 0.12), Vector3(1.9, 0.06, 0.8), OAK.lightened(0.12), "board")
			for x in [-0.88, 0.88]:
				for z in [-0.3, 0.5]:
					box(Vector3(x, 1.1, z), Vector3(0.08, 2.2 - (z + 0.3) * 0.35, 0.08), WOOD, "board")
			for i in 4:
				box(Vector3(-0.72 + 0.48 * i, 2.05, 0.15), Vector3(0.49, 0.03, 1.15), dye if i % 2 == 0 else LINEN, "", 0.0, 0.24)
			for i in 3:
				box(Vector3(-0.55 + 0.55 * i, 1.02, 0.18), Vector3(0.42, 0.14, 0.42), PRODUCE[posmod(seed + i, PRODUCE.size())], "")
		"Anvil":
			box(Vector3(0, 0.26, 0), Vector3(0.42, 0.52, 0.42), WOOD.lightened(0.08), "board")
			box(Vector3(0, 0.6, 0), Vector3(0.16, 0.16, 0.3), IRON, "iron")
			box(Vector3(0, 0.74, -0.04), Vector3(0.2, 0.12, 0.52), IRON, "iron")
			box(Vector3(0, 0.75, 0.3), Vector3(0.1, 0.08, 0.18), IRON, "iron", 0.0, 0.22)
			box(Vector3(0.08, 0.83, -0.12), Vector3(0.04, 0.04, 0.3), WOOD, "board", 0.6)
		"Flower box":
			box(Vector3(0, 0.17, 0), Vector3(1.0, 0.34, 0.34), WOOD.lightened(0.12), "planter")
			box(Vector3(0, 0.36, 0), Vector3(0.94, 0.06, 0.28), WallLayout.LEAVES, "leaf")
			for i in 6:
				box(Vector3(-0.4 + 0.16 * i, 0.43, sin(seed + i * 2.3) * 0.07), Vector3(0.09, 0.07, 0.09), WallLayout.BLOOMS[posmod(seed + i, WallLayout.BLOOMS.size())], "bloom", i * 0.7)
		"Carved pumpkin":
			for i in 3:
				box(Vector3(0, 0.2, 0), Vector3(0.44 - 0.06 * absi(i - 1), 0.36 + 0.04 * (1 - absi(i - 1)), 0.44 - 0.06 * absi(i - 1)), PUMPKIN.darkened(0.08 * i), "", i * PI / 6.0)
			box(Vector3(0, 0.42, 0), Vector3(0.05, 0.1, 0.05), STALK, "", 0.3, 0.2)
			for x in [-0.09, 0.09]:
				box(Vector3(x, 0.26, 0.205), Vector3(0.07, 0.06, 0.02), CANDLE, "glass", 0.0, 0.0)
			box(Vector3(0, 0.14, 0.205), Vector3(0.2, 0.05, 0.02), CANDLE, "glass")
		"Bird nest":
			for i in 7:
				var a := i * TAU / 7.0
				box(Vector3(sin(a) * 0.11, 0.05, cos(a) * 0.11), Vector3(0.16, 0.07, 0.05), TWIG.lightened(0.06 * (i % 3)), "", a + 0.4, 0.3)
			box(Vector3(0, 0.025, 0), Vector3(0.18, 0.04, 0.18), TWIG.darkened(0.3), "nest")
			for i in 3:
				box(Vector3(sin(i * 2.1) * 0.04, 0.07, cos(i * 2.1) * 0.04), Vector3(0.045, 0.04, 0.055), EGG, "", i * 1.1)
		"Lantern string", "Flag string":
			_string(span, drop, seed, STYLES[style].name == "Lantern string")

	if mount == "span":
		return
	var shift := Vector3(-bounds.get_center().x, 0.0, -bounds.position.z + 0.04 if mount == "foundation" else -bounds.get_center().z)
	for part in parts:
		part.xform.origin += shift
	for list: Array[Transform3D] in [flames, pictures]:
		for i in list.size():
			list[i].origin += shift
	for f in flowers:
		f.xform.origin += shift
	bounds.position += shift


## A rope across `span` sagging as `hang_at` has it, on a wooden pole under each end `drop` stands on, hung with
## lanterns or with flags, each a square hung from its corner in the flag colour after the last.
func _string(span: Vector3, drop: Vector2, seed: int, lanterns: bool) -> void:
	var run := span.length()
	if run == 0.0:
		return
	var n := maxi(2, ceili(run / 0.6))
	for i in n:
		beam(hang_at(span, float(i) / n), hang_at(span, float(i + 1) / n), 0.02, WallLayout.ROPE, "rope")
	for end in 2:
		var tall := drop[end]
		if tall > 0.0:
			var at := span * end
			box(at + Vector3.DOWN * (tall * 0.5 - 0.06), Vector3(0.09, tall + 0.12, 0.09), WOOD, "board")
	var every := LANTERN_EVERY if lanterns else FLAG_EVERY
	var count := maxi(1, floori(run / every))
	var across := Vector3(span.x, 0.0, span.z).normalized().cross(Vector3.UP)
	var turn := atan2(across.x, across.z)
	for k in count:
		var at := hang_at(span, (k + 0.5) / count)
		if lanterns:
			box(at + Vector3.DOWN * 0.07, Vector3(0.015, 0.14, 0.015), IRON, "iron")
			lantern(at + Vector3.DOWN * 0.33)
		else:
			var diamond := Basis(Vector3.UP, turn) * Basis(Vector3.BACK, PI * 0.25)
			_part(Transform3D(diamond.scaled_local(Vector3(0.2, 0.2, 0.012)), at + Vector3.DOWN * 0.141), WallLayout.FLAG_COLORS[posmod(seed + k, WallLayout.FLAG_COLORS.size())], "")


func _chair(at: Vector3, turn: float) -> void:
	var b := Basis(Vector3.UP, turn)
	for x in [-0.18, 0.18]:
		for z in [-0.18, 0.18]:
			box(at + b * Vector3(x, 0.22, z), Vector3(0.05, 0.44, 0.05), OAK, "board", turn)
	box(at + b * Vector3(0, 0.46, 0), Vector3(0.44, 0.05, 0.44), OAK.lightened(0.12), "board", turn)
	box(at + b * Vector3(0, 0.76, -0.2), Vector3(0.42, 0.56, 0.05), OAK, "board", turn)


func lantern(at: Vector3) -> void:
	box(at + Vector3.UP * 0.19, Vector3(0.22, 0.05, 0.22), IRON, "iron")
	box(at - Vector3.UP * 0.07, Vector3(0.18, 0.04, 0.18), IRON, "iron")
	flame(at + Vector3.UP * 0.05, Vector3(0.12, 0.22, 0.12))


func flower(x: Transform3D, seed: int) -> void:
	flowers.append({"xform": x, "color": FloraLayout.FLOWER_COLORS[posmod(seed + flowers.size(), FloraLayout.FLOWER_COLORS.size())]})


## Lays `other`'s parts, flames, flowers and pictures into this one, placed by `x`.
func add(other: DecorationLayout, x: Transform3D) -> void:
	for p in other.parts:
		parts.append(p.merged({"xform": x * p.xform}, true))
	for f in other.flames:
		flames.append(x * f)
	for f in other.flowers:
		flowers.append({"xform": x * f.xform, "color": f.color})
	for p in other.pictures:
		pictures.append(x * p)


func flame(at: Vector3, size: Vector3) -> void:
	flames.append(Transform3D(Basis().scaled(size), at))
	bounds = bounds.merge(AABB(at - size * 0.5, size))
