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
const GROUND := {&"earth": Color(0.45, 0.38, 0.27), &"trodden": Color(0.52, 0.45, 0.33), &"tilled": Color(0.29, 0.21, 0.14), &"sand": Color(0.8, 0.71, 0.54)}
## Where on a blade, root to tip, the meadow's ground takes its colour (terrain.gdshader): the tone blades rise from, so
## their roots melt into the ground through thin grass instead of reading as dark tufts, and far blades converge on.
const CANOPY := 0.6
## The grass's colours (meadow.gdshaderinc), which the meadow's ground takes too.
const GRASS := {&"root_color": Color(0.10, 0.24, 0.06), &"tip_lush": Color(0.45, 0.68, 0.18), &"tip_dry": Color(0.80, 0.78, 0.34), &"cool_clump": Color(0.82, 0.96, 0.90), &"warm_clump": Color(1.10, 1.02, 0.82), &"canopy": CANOPY}

var flora: Flora
## How far from the eye, across the ground, a chunk steps to each coarser grid in Terrain.LODS.
const LOD_M: Array[float] = [24.0, 48.0]
## Each chunk of the ground: its MeshInstance3D, its rect across the ground and its mesh at each of Terrain.LODS.
var _chunks: Array[Array] = []
var _eye := Vector2.INF


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
	StoneStyles.apply(mat)
	for k in GROUND:
		mat.set_shader_parameter(k, GROUND[k])
	mat.set_shader_parameter(&"rock_steep", Terrain.ROCK)
	for k in GRASS:
		mat.set_shader_parameter(k, GRASS[k])
	# Opaque draws go in ascending render_priority: the ground draws after the plants and builds standing on it, so
	# what they cover fails the depth test unshaded, as the book's layers do.
	mat.render_priority = 1
	flora.paint_ground(mat)
	var box := flora.terrain.bounds()
	var bank := MeshInstance3D.new()
	bank.mesh = Terrain.bank_mesh()
	bank.material_override = mat
	flora.terrain.lift(bank, box)
	add_child(bank)
	for cj in Terrain.CHUNKS:
		for ci in Terrain.CHUNKS:
			var lods: Array[Mesh] = []
			for k in Terrain.LODS:
				lods.append(Terrain.chunk_mesh(ci, cj, k))
			var mi := MeshInstance3D.new()
			mi.mesh = lods[0]
			mi.material_override = mat
			var corner := Terrain.grid_xz(Vector2i(ci, cj) * Terrain.CHUNK)
			flora.terrain.lift(mi, AABB(Vector3(corner.x, box.position.y, corner.y), Vector3(Terrain.CHUNK * Terrain.STEP, box.size.y, Terrain.CHUNK * Terrain.STEP)))
			add_child(mi)
			_chunks.append([mi, Rect2(corner, Vector2.ONE * Terrain.CHUNK * Terrain.STEP), lods])


## Draws each chunk at the coarsest of Terrain.LODS its distance from the eye allows: past LOD_M[n], step n + 1.
func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := Vector2(camera.global_position.x, camera.global_position.z)
	if eye.distance_squared_to(_eye) < 1.0:
		return
	_eye = eye
	for c: Array in _chunks:
		var rect: Rect2 = c[1]
		var far := (eye.clamp(rect.position, rect.end) - eye).length()
		var level := 0
		while level < LOD_M.size() and far > LOD_M[level]:
			level += 1
		var mi: MeshInstance3D = c[0]
		if mi.mesh != c[2][level]:
			mi.mesh = c[2][level]


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
		flora.add_tree(flora.terrain.ground(cos(ang) * r, sin(ang) * r), rng.randi())
	for b in BUSHES:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(14.0, 40.0)
		flora.add_bush(flora.terrain.ground(cos(ang) * r, sin(ang) * r), rng)
	flora.keep()


func _scatter(rng: RandomNumberGenerator, radius: float) -> Vector3:
	return FloraLayout.brush(Vector3.ZERO, radius, 1, rng, flora.terrain.height_at)[0]

