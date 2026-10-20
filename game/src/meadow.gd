class_name Meadow
extends Node3D

## Every meadow grows from this seed, so a garden is its build commands.
const SEED := 5
const GRASS_CLUMPS := 22000
const GRASS_RADIUS := 36.0
const FLOWERS := 3200
const TREES := 46
const BUSHES := 60
## The terrain shader's ground colours.
const GROUND := {&"earth": Color(0.45, 0.38, 0.27)}
## The grass's colours (meadow.gdshaderinc), which the meadow's ground takes too.
const GRASS := {&"root_color": Color(0.10, 0.24, 0.06), &"tip_lush": Color(0.45, 0.68, 0.18), &"tip_dry": Color(0.80, 0.78, 0.34), &"cool_clump": Color(0.82, 0.96, 0.90), &"warm_clump": Color(1.10, 1.02, 0.82)}

var flora: Flora


func _init(plants: Flora) -> void:
	flora = plants


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_ground()
	_plants(rng)


func _ground() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/terrain.gdshader")
	mat.set_shader_parameter("detail", Look.detail_noise())
	StoneStyles.apply(mat)
	for k in GROUND:
		mat.set_shader_parameter(k, GROUND[k])
	for k in GRASS:
		mat.set_shader_parameter(k, GRASS[k])
	var mi := MeshInstance3D.new()
	mi.mesh = Terrain.build_mesh()
	Terrain.lift(mi, Terrain.bounds())
	mi.material_override = mat
	add_child(mi)


func _plants(rng: RandomNumberGenerator) -> void:
	for i in GRASS_CLUMPS:
		flora.add_grass(_scatter(rng, GRASS_RADIUS), rng)
	for i in FLOWERS:
		var p := _scatter(rng, GRASS_RADIUS * 0.95)
		while not FloraLayout.flowery(p) and rng.randf() < 0.85:
			p = _scatter(rng, GRASS_RADIUS * 0.95)
		flora.add_flower(p, rng)
	for t in TREES:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(24.0, 58.0)
		flora.add_tree(Terrain.ground(cos(ang) * r, sin(ang) * r), rng.randi())
	for b in BUSHES:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(14.0, 40.0)
		flora.add_bush(Terrain.ground(cos(ang) * r, sin(ang) * r), rng)
	flora.keep()


func _scatter(rng: RandomNumberGenerator, radius: float) -> Vector3:
	return FloraLayout.brush(Vector3.ZERO, radius, 1, rng, Terrain.height_at)[0]

