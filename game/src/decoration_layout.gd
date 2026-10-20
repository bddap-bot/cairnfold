class_name DecorationLayout
extends RefCounted

## One catalogue for placement, style choices and geometry. The stored style never changes on reload.
const STYLES := [
	{"name": "Planter", "mount": "foundation"},
	{"name": "Bench", "mount": "foundation"},
	{"name": "Rain barrel", "mount": "foundation"},
	{"name": "Woodpile", "mount": "foundation"},
	{"name": "Steps", "mount": "foundation"},
	{"name": "Gatepost lantern", "mount": "foundation"},
	{"name": "Bracket lantern", "mount": "foundation"},
	{"name": "Standing torch", "mount": "ground"},
	{"name": "Campfire", "mount": "ground"},
]
const WOOD := Color(0.30, 0.19, 0.10)
const STONE := Color(0.53, 0.51, 0.44)
const IRON := Color(0.12, 0.13, 0.14)
var parts: Array[Dictionary] = []
var flames: Array[Transform3D] = []
var flowers: Array[Transform3D] = []
var bounds := AABB()


static func options(mount: String) -> Array[int]:
	var out: Array[int] = []
	for i in STYLES.size():
		if STYLES[i].mount == mount:
			out.append(i)
	return out


static func choose(mount: String, seed: int) -> int:
	var choices := options(mount)
	return choices[posmod(seed, choices.size())]


func box(at: Vector3, size: Vector3, color: Color, kind: String, turn := 0.0) -> void:
	var x := Transform3D(Basis(Vector3.UP, turn).scaled_local(size), at)
	parts.append({"xform": x, "color": color, "kind": kind, "ao": 1.0, "variant": 0})
	var b := x * AABB(Vector3.ONE * -0.5, Vector3.ONE)
	bounds = b if parts.size() == 1 else bounds.merge(b)


func build(style: int, seed: int, rise := 0.6) -> void:
	parts.clear()
	flames.clear()
	flowers.clear()
	match style:
		0:
			box(Vector3(0, 0.18, 0.33), Vector3(1.1, 0.32, 0.5), WOOD, "board")
			box(Vector3(0, 0.35, 0.33), Vector3(0.96, 0.04, 0.36), Color(0.12, 0.09, 0.06), "")
			for i in 5:
				flowers.append(Transform3D(Basis().scaled(Vector3.ONE * 1.2), Vector3((i - 2) * 0.19, 0.36, 0.33 + sin(i * 2.1) * 0.09)))
			bounds = bounds.expand(Vector3(0, 0.9, 0.6))
		1:
			for x in [-0.52, 0.52]:
				for z in [0.16, 0.52]:
					box(Vector3(x, 0.22, z), Vector3(0.1, 0.44, 0.1), WOOD, "board")
			for z in [0.16, 0.34, 0.52]:
				box(Vector3(0, 0.47, z), Vector3(1.35, 0.09, 0.15), WOOD.lightened(0.15), "board")
			for y in [0.66, 0.85]:
				box(Vector3(0, y, 0.10), Vector3(1.35, 0.14, 0.07), WOOD, "board")
		2:
			for i in 10:
				var a := i * TAU / 10
				box(Vector3(sin(a) * 0.28, 0.42, 0.4 + cos(a) * 0.28), Vector3(0.19, 0.8, 0.08), WOOD.lightened(0.02 * (i % 3)), "board", a)
				for y in [0.15, 0.68]:
					box(Vector3(sin(a) * 0.30, y, 0.4 + cos(a) * 0.30), Vector3(0.20, 0.055, 0.035), IRON, "iron", a)
			box(Vector3(0, 0.74, 0.4), Vector3(0.44, 0.025, 0.44), Color(0.15, 0.27, 0.3), "")
		3:
			for row in 3:
				for col in 4 - row:
					box(Vector3((col - (3 - row) * 0.5) * 0.24, 0.13 + row * 0.21, 0.4), Vector3(0.21, 0.21, 0.65), WOOD, "board", sin(seed + col) * 0.04)
		4:
			var count := clampi(ceili(rise / 0.2), 1, 24)
			for i in count:
				var height := maxf(0.1, rise) * (count - i) / count
				box(Vector3(0, height * 0.5, 0.18 + i * 0.3), Vector3(1.2, height, 0.32), STONE, "block")
		5:
			for i in 4:
				box(Vector3(0, 0.12 + i * 0.23, 0.35), Vector3(0.38, 0.22, 0.38), STONE, "block", 0.035 * (i % 2))
			box(Vector3(0, 0.95, 0.35), Vector3(0.48, 0.1, 0.48), STONE, "block")
			lantern(Vector3(0, 1.08, 0.35))
		6:
			box(Vector3(0, 0.9, 0.04), Vector3(0.08, 0.45, 0.08), IRON, "iron")
			box(Vector3(0, 1.08, 0.25), Vector3(0.055, 0.055, 0.5), IRON, "iron")
			lantern(Vector3(0, 0.85, 0.47))
		7:
			box(Vector3(0, 0.65, 0), Vector3(0.09, 1.3, 0.09), WOOD, "board")
			box(Vector3(0, 1.27, 0), Vector3(0.16, 0.22, 0.16), IRON, "iron")
			flame(Vector3(0, 1.47, 0), Vector3(0.13, 0.3, 0.13))
		8:
			for i in 9:
				var a := i * TAU / 9
				box(Vector3(sin(a) * 0.45, 0.1, cos(a) * 0.45), Vector3(0.25, 0.2, 0.22), STONE, "block", a)
			for i in 3:
				box(Vector3(0, 0.14 + i * 0.05, 0), Vector3(0.16, 0.16, 0.65), WOOD, "board", i * TAU / 3)
			for i in 3:
				flame(Vector3((i - 1) * 0.12, 0.38, 0), Vector3(0.14, 0.38 + i * 0.04, 0.14))


func lantern(at: Vector3) -> void:
	box(at + Vector3.UP * 0.19, Vector3(0.22, 0.05, 0.22), IRON, "iron")
	box(at - Vector3.UP * 0.07, Vector3(0.18, 0.04, 0.18), IRON, "iron")
	flame(at + Vector3.UP * 0.05, Vector3(0.12, 0.22, 0.12))


func flame(at: Vector3, size: Vector3) -> void:
	flames.append(Transform3D(Basis().scaled(size), at))
	bounds = bounds.merge(AABB(at - size * 0.5, size))
