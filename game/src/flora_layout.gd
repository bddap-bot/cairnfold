class_name FloraLayout
extends RefCounted

## Where grass, flowers, bushes and trees go and how each looks. The meadow and the
## left-hand brush both place plants through here. Pure data: no nodes, so tests run headless.

const FLOWER_COLORS := [Color(0.97, 0.96, 0.92), Color(1.0, 0.85, 0.25), Color(0.95, 0.62, 0.72), Color(0.72, 0.62, 0.95), Color(0.98, 0.45, 0.30)]
const BLOBS := 8
const GREENS := [Color(0.16, 0.34, 0.08), Color(0.24, 0.42, 0.1), Color(0.14, 0.30, 0.12), Color(0.32, 0.46, 0.12)]

static var _patches: FastNoiseLite
static var _kinds: FastNoiseLite


static func _noise(seed: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = frequency
	return n


## How dry the grass tips are at a ground point, 0 lush to 1 straw.
static func dryness(p: Vector3) -> float:
	if _patches == null:
		_patches = _noise(9, 0.06)
	return clampf(0.4 + _patches.get_noise_2d(p.x, p.z) * 1.2, 0.0, 1.0)


## Flowers come in single-colour drifts, so a painted patch matches the meadow's around it.
static func flower_color(p: Vector3) -> Color:
	if _kinds == null:
		_kinds = _noise(17, 0.08)
	var k := int(clampf((_kinds.get_noise_2d(p.x, p.z) + 0.6) / 1.2, 0.0, 0.999) * FLOWER_COLORS.size())
	return FLOWER_COLORS[k]


## Whether the meadow's flower drifts favour a ground point.
static func flowery(p: Vector3) -> bool:
	if _kinds == null:
		flower_color(p)
	return _kinds.get_noise_2d(p.z * 1.9, p.x * 1.9) >= 0.05


static func grass(p: Vector3, rng: RandomNumberGenerator) -> Transform3D:
	var s := rng.randf_range(0.75, 1.25)
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), p)


static func flower(p: Vector3, rng: RandomNumberGenerator) -> Transform3D:
	var s := rng.randf_range(0.7, 1.4)
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p)


## `count` points spread over a disc of `radius` around `center`, each set into the ground.
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
