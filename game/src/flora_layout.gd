class_name FloraLayout
extends RefCounted

## Where grass, flowers, bushes and trees go and how each looks; the meadow and the left-hand brush both place plants through here.

## White, butter, peach, pale pink, rose, lavender, violet, cornflower, sky; dim enough that full sun leaves them coloured.
const FLOWER_COLORS := [
	Color(0.86, 0.85, 0.80), Color(0.80, 0.58, 0.14), Color(0.80, 0.40, 0.24),
	Color(0.78, 0.40, 0.52), Color(0.66, 0.20, 0.38), Color(0.48, 0.34, 0.72),
	Color(0.34, 0.20, 0.58), Color(0.20, 0.30, 0.72), Color(0.30, 0.48, 0.76),
]
## Flowers of one colour grow together in clumps about this wide, so a stroke paints a few colours in patches.
const FLOWER_CLUMP := 1.3
const BLOBS := 8
const GRASS_CLUMP := 0.7
const CLUMP_LEAN := 0.5
const GREENS := [Color(0.16, 0.34, 0.08), Color(0.24, 0.42, 0.1), Color(0.14, 0.30, 0.12), Color(0.32, 0.46, 0.12)]

static var _patches := _noise(9, 0.06)
static var _beds := _noise(17, 0.08)


static func _noise(seed: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = frequency
	return n


## How dry the grass tips are at a ground point, 0 lush to 1 straw.
static func dryness(p: Vector3) -> float:
	return clampf(0.4 + _patches.get_noise_2d(p.x, p.z) * 1.2, 0.0, 1.0)


static func flower_color(p: Vector3) -> Color:
	var k := int(clump_trait(clump(p, FLOWER_CLUMP), Trait.COLOUR, FLOWER_CLUMP) * FLOWER_COLORS.size())
	return FLOWER_COLORS[mini(k, FLOWER_COLORS.size() - 1)]


## Where a flower stands in the order the seasons take them: one blooms while its rank is under the season's
## share in bloom (plant.gdshaderinc reads it from the instance).
static func bloom_rank(p: Vector3) -> float:
	return _hash(floori(p.x * 64.0), floori(p.z * 64.0), Trait.BLOOM)


## Where a grass clump stands in the order distance thins the meadow: the higher its rank, the nearer the eye it
## goes (grass.gdshader reads it from the instance).
static func thin_rank(p: Vector3) -> float:
	return _hash(floori(p.x * 64.0), floori(p.z * 64.0), Trait.THIN)


static func flowery(p: Vector3) -> bool:
	return _beds.get_noise_2d(p.z * 1.9, p.x * 1.9) >= 0.05


enum Trait { X, Z, HEIGHT, FACING, TINT, COLOUR, BLOOM, THIN }


## The centre of the clump a ground point belongs to: the nearest of one jittered point per `size` cell.
## Grass clumps share height, facing and tint, so the meadow grows in tufts rather than an even carpet.
static func clump(p: Vector3, size: float) -> Vector3:
	var ci := floori(p.x / size)
	var cj := floori(p.z / size)
	var best := Vector3.ZERO
	var best_d := INF
	for j in range(cj - 1, cj + 2):
		for i in range(ci - 1, ci + 2):
			var c := Vector3((i + _hash(i, j, Trait.X)) * size, 0.0, (j + _hash(i, j, Trait.Z)) * size)
			var d := Vector2(p.x - c.x, p.z - c.z).length_squared()
			if d < best_d:
				best_d = d
				best = c
	return best


## A clump's 0..1 value for one trait, the same for every plant in it; `size` is the one its centre came from.
static func clump_trait(centre: Vector3, t: Trait, size: float) -> float:
	return _hash(floori(centre.x / size), floori(centre.z / size), t)


static func _hash(i: int, j: int, k: int) -> float:
	return fposmod(sin(i * 127.1 + j * 311.7 + k * 74.7) * 43758.5453, 1.0)


## A grass clump mesh at `p` in the clump centred at `c`: its height and facing with some scatter, its tips leaning out from the centre.
static func grass(p: Vector3, c: Vector3, rng: RandomNumberGenerator) -> Transform3D:
	var s := rng.randf_range(0.8, 1.15)
	var h := s * lerpf(0.65, 1.45, clump_trait(c, Trait.HEIGHT, GRASS_CLUMP)) * rng.randf_range(0.9, 1.1)
	var basis := Basis(Vector3.UP, clump_trait(c, Trait.FACING, GRASS_CLUMP) * TAU + rng.randf_range(-0.7, 0.7)).scaled(Vector3(s, h, s))
	basis.y += Vector3(p.x - c.x, 0.0, p.z - c.z) * (CLUMP_LEAN * h / GRASS_CLUMP)
	return Transform3D(basis, p)


static func flower(p: Vector3, rng: RandomNumberGenerator) -> Transform3D:
	var s := rng.randf_range(0.7, 1.4)
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p)


static func brush(center: Vector3, radius: float, count: int, rng: RandomNumberGenerator, ground: Callable) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in count:
		var r := sqrt(rng.randf()) * radius
		var a := rng.randf() * TAU
		var x := center.x + cos(a) * r
		var z := center.z + sin(a) * r
		out.append(Vector3(x, ground.call(x, z) - 0.02, z))
	return out


## A tree on the ground point `at`: a trunk (a unit-height cylinder scaled up) and its foliage blobs as [transform, colour].
static func tree(at: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var base := at - Vector3.UP * 0.2
	var h := rng.randf_range(2.6, 4.8)
	var green: Color = GREENS[rng.randi() % GREENS.size()]
	var size := h * 0.62
	var crown := base + Vector3.UP * (h + size * 0.2)
	var blobs := []
	for b in BLOBS:
		var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.8), rng.randf_range(-1, 1)) * size * 0.6
		var s := size * rng.randf_range(0.55, 0.85)
		blobs.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.85, s)), crown + off), green * rng.randf_range(0.9, 1.1)])
	return {"trunk": Transform3D(Basis().scaled(Vector3(1, h, 1)), base + Vector3.UP * h * 0.5), "blobs": blobs}


static func bush(at: Vector3, rng: RandomNumberGenerator) -> Array:
	var s := rng.randf_range(0.4, 0.9)
	return [Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.7, s)), at + Vector3.UP * 0.1), GREENS[rng.randi() % GREENS.size()] * 0.95]
