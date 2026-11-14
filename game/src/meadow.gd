class_name Meadow
extends Node3D

## Every meadow grows from this seed, so a garden is its build commands.
const SEED := 5
const GRASS_CLUMPS := 22000
const GRASS_RADIUS := 36.0
const FLOWERS := 3200
const TREES := 46
const BUSHES := 60
const GROUND := {&"earth": Color(0.45, 0.38, 0.27), &"trodden": Color(0.52, 0.45, 0.33), &"tilled": Color(0.29, 0.21, 0.14), &"sand": Color(0.8, 0.71, 0.54)}
## 0 root to 1 tip: the blade tone the ground takes (terrain.gdshader), so roots melt into it, not dark tufts.
const CANOPY := 0.6
const GRASS := {&"root_color": Color(0.10, 0.24, 0.06), &"tip_lush": Color(0.45, 0.68, 0.18), &"tip_dry": Color(0.80, 0.78, 0.34), &"cool_clump": Color(0.82, 0.96, 0.90), &"warm_clump": Color(1.10, 1.02, 0.82), &"canopy": CANOPY}

var flora: Flora
## Past LOD_M[n] from the eye across the ground, a chunk draws at Terrain.LODS[n + 1].
const LOD_M: Array[float] = [24.0, 48.0]
var _chunks: Array[Chunk] = []
var _eye := Vector2.INF
## terrain.gdshader where stone or a pond may show, terrain_plain elsewhere (docs/design.md, "The ground's two shaders").
var full: ShaderMaterial
var plain: ShaderMaterial
var _stone_seen := -1
var _water_seen := -1
var _wet := PackedByteArray()


class Chunk:
	var rect: Rect2
	var plain := MeshInstance3D.new()
	var full := MeshInstance3D.new()
	var parts: Array[Array] = []
	## Tiles drawn in `full` (1) or `plain` (0), one byte each, row by row.
	var marked := PackedByteArray()
	## Per Terrain.LODS level: [plain mesh, full mesh].
	var meshes: Array[Array] = []
	var level := 0

	func show(tiles: PackedByteArray) -> void:
		if tiles == marked and not meshes.is_empty():
			return
		marked = tiles
		var dry := tiles.duplicate()
		for t in dry.size():
			dry[t] = 1 - dry[t]
		meshes.clear()
		for p in parts:
			meshes.append([Terrain.part_mesh(p, dry), Terrain.part_mesh(p, marked)])
		step(level)

	func step(to: int) -> void:
		level = to
		plain.mesh = meshes[to][0]
		full.mesh = meshes[to][1]


func _init(plants: Flora) -> void:
	flora = plants


func _ready() -> void:
	# After every node that stamps the mask or fills a pond this frame, so a tile turns full the frame it shows them.
	process_priority = 1000
	_ground()
	_plants()


func _ground() -> void:
	full = _material("res://src/terrain.gdshader")
	plain = _material("res://src/terrain_plain.gdshader")
	var mats: Array[ShaderMaterial] = [full, plain]
	flora.paint_ground(mats)
	var box := flora.terrain.bounds()
	var bank := MeshInstance3D.new()
	bank.mesh = Terrain.bank_mesh()
	bank.material_override = full
	flora.terrain.lift(bank, box)
	add_child(bank)
	for cj in Terrain.CHUNKS:
		for ci in Terrain.CHUNKS:
			var c := Chunk.new()
			for k in Terrain.LODS:
				c.parts.append(Terrain.chunk_parts(ci, cj, k))
			var corner := Terrain.grid_xz(Vector2i(ci, cj) * Terrain.CHUNK)
			c.rect = Rect2(corner, Vector2.ONE * Terrain.CHUNK * Terrain.STEP)
			var lifted := AABB(Vector3(corner.x, box.position.y, corner.y), Vector3(c.rect.size.x, box.size.y, c.rect.size.y))
			for mi: MeshInstance3D in [c.plain, c.full]:
				mi.material_override = plain if mi == c.plain else full
				flora.terrain.lift(mi, lifted)
				add_child(mi)
			_chunks.append(c)
	_tile()


func _material(shader: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(shader)
	StoneStyles.apply(mat)
	for k in GROUND:
		mat.set_shader_parameter(k, GROUND[k])
	mat.set_shader_parameter(&"rock_steep", Terrain.ROCK)
	for k in GRASS:
		mat.set_shader_parameter(k, GRASS[k])
	# Opaque draws ascend by render_priority: ground drawn after what stands on it fails the depth test unshaded.
	mat.render_priority = 1
	return mat


func _tile() -> void:
	var marks := flora.marks
	var terrain := flora.terrain
	if marks.stone_revision == _stone_seen and terrain.water_revision == _water_seen:
		return
	_stone_seen = marks.stone_revision
	if terrain.water_revision != _water_seen:
		_wet = terrain.wet_tiles()
	_water_seen = terrain.water_revision
	var marked := _wet.duplicate()
	for t in marked.size():
		marked[t] |= marks.stone_tiles[t]
	for n in _chunks.size():
		var ci := n % Terrain.CHUNKS
		var cj := n / Terrain.CHUNKS
		var tiles := PackedByteArray()
		for b in Terrain.CHUNK_TILES:
			var row := (cj * Terrain.CHUNK_TILES + b) * Terrain.TILES + ci * Terrain.CHUNK_TILES
			tiles.append_array(marked.slice(row, row + Terrain.CHUNK_TILES))
		_chunks[n].show(tiles)


func _process(_delta: float) -> void:
	_tile()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := Vector2(camera.global_position.x, camera.global_position.z)
	if eye.distance_squared_to(_eye) < 1.0:
		return
	_eye = eye
	for c in _chunks:
		var far := (eye.clamp(c.rect.position, c.rect.end) - eye).length()
		var level := 0
		while level < LOD_M.size() and far > LOD_M[level]:
			level += 1
		if c.level != level:
			c.step(level)


func _plants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
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

