class_name PondWater
extends MeshInstance3D

## One pond's surface: flat quads at its level over the grid cells around its wet points, tinted by the
## depth of the ground below (read in the shader), rippling where a hand breaks it and lapping softly.

const FILL := 1.8
const RIPPLES := 12
const RIPPLE_LIFE := 1.5
## A moving hand rings at most this often, so two hands never outrun the ripple slots.
const RIPPLE_EVERY := RIPPLE_LIFE * 2.0 / RIPPLES

static var _shader: Shader
static var _waves: NoiseTexture2D

var pond: PondLayout.Pond
var _filled := 0.0
var _mat := ShaderMaterial.new()
var _ripples: Array[Vector4] = []
var _next := 0
var _live := 0
var _lap := AudioStreamPlayer3D.new()


func _init() -> void:
	if _shader == null:
		_shader = load("res://src/water.gdshader")
		var n := FastNoiseLite.new()
		n.seed = 31
		n.frequency = 0.03
		n.fractal_octaves = 3
		_waves = NoiseTexture2D.new()
		_waves.width = 256
		_waves.height = 256
		_waves.seamless = true
		_waves.as_normal_map = true
		_waves.bump_strength = 6.0
		_waves.generate_mipmaps = true
		_waves.noise = n
	_mat.shader = _shader
	_mat.set_shader_parameter("waves", _waves)
	_mat.set_shader_parameter("breakup", Look.detail_noise())
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	_ripples.resize(RIPPLES)
	_mat.set_shader_parameter("ripples", _ripples)
	_lap.stream = load("res://audio/lap.ogg")
	(_lap.stream as AudioStreamOggVorbis).loop = true
	_lap.unit_size = 2.5
	_lap.max_distance = 30.0
	add_child(_lap)


func _ready() -> void:
	_lap.play(randf() * _lap.stream.get_length())


func show_pond(p: PondLayout.Pond) -> void:
	pond = p
	mesh = _sheet(p)
	position = Vector3(0, p.level, 0)
	var mid := Terrain.grid_xz(p.bottom)
	_lap.position = Vector3(mid.x, 0, mid.y)
	_lap.volume_db = -14.0 + clampf(linear_to_db(p.cells.size() / 12.0), -6.0, 4.0)
	_mat.set_shader_parameter("level", p.level)
	_set_drop()
	set_process(true)


## Quads over every grid cell with a wet corner and the rest on its shore: they reach each shore and no
## further, and never over a hollow that only touches the pond at a corner.
static func _sheet(p: PondLayout.Pond) -> ArrayMesh:
	var ours := {}
	for g in p.cells + p.shore:
		ours[g] = true
	var squares := {}
	for g in p.cells:
		for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
			var s: Vector2i = g + o
			if ours.has(s) and ours.has(s + Vector2i(1, 0)) and ours.has(s + Vector2i(0, 1)) and ours.has(s + Vector2i.ONE):
				squares[s] = true
	var verts := PackedVector3Array()
	for s: Vector2i in squares:
		var a := Terrain.grid_xz(s)
		var b := a + Vector2.ONE * Terrain.STEP
		verts.append_array([Vector3(a.x, 0, a.y), Vector3(b.x, 0, a.y), Vector3(a.x, 0, b.y), Vector3(b.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(a.x, 0, b.y)])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _process(delta: float) -> void:
	if _filled < 1.0:
		_filled = minf(_filled + delta / FILL, 1.0)
		_set_drop()
	if _live > 0:
		_live = 0
		for i in RIPPLES:
			var r := _ripples[i]
			if r.w > 0.0:
				r.z += delta
				r.w = r.w if r.z < RIPPLE_LIFE else 0.0
				_ripples[i] = r
				_live += int(r.w > 0.0)
		_mat.set_shader_parameter("ripples", _ripples)
	set_process(_filled < 1.0 or _live > 0)


## A new pond rises from its bottom.
func _set_drop() -> void:
	var drop := pow(1.0 - _filled, 3.0) * pond.depth
	_mat.set_shader_parameter("drop", drop)
	position.y = pond.level - drop


func ripple(at: Vector3, strength: float) -> void:
	_ripples[_next] = Vector4(at.x, at.z, 0.0, strength)
	_next = (_next + 1) % RIPPLES
	_live += 1
	_mat.set_shader_parameter("ripples", _ripples)
	set_process(true)


func surface_y() -> float:
	return position.y
