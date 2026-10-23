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
static var _lapping: AudioStreamOggVorbis

var pond: PondLayout.Pond
var _filled := 0.0
var _mat := ShaderMaterial.new()
var _ripples: Array[Vector4] = []
var _next := 0
var _live := 0
var _lap := AudioStreamPlayer3D.new()


## Godot compiles a shader when a material first takes it, 10 ms on the Frame and a late frame as the first pond
## fills, so `Water` calls this before any is dug and `get_rid` compiles it here.
static func prepare() -> void:
	if _shader != null:
		return
	_shader = load("res://src/water.gdshader")
	_shader.get_rid()
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
	_lapping = load("res://audio/lap.ogg")
	_lapping.loop = true


func _init() -> void:
	prepare()
	_mat.shader = _shader
	_mat.set_shader_parameter("waves", _waves)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	_ripples.resize(RIPPLES)
	_mat.set_shader_parameter("ripples", _ripples)
	_lap.stream = _lapping
	_lap.unit_size = 2.5
	_lap.max_distance = 30.0
	add_child(_lap)


func _ready() -> void:
	_lap.play(randf() * _lap.stream.get_length())


func show_pond(p: PondLayout.Pond) -> void:
	pond = p
	mesh = sheet(quads(p))
	position = Vector3(0, p.level, 0)
	var mid := Terrain.grid_xz(p.bottom)
	_lap.position = Vector3(mid.x, 0, mid.y)
	_lap.volume_db = -14.0 + clampf(linear_to_db(p.cells.size() / 12.0), -6.0, 4.0)
	_mat.set_shader_parameter("level", p.level)
	_set_drop()
	set_process(true)


## Quads over every grid cell with a wet corner and the rest on its shore: they reach each shore and no
## further, and never over a hollow that only touches the pond at a corner. Each run of such cells along a row is
## one quad, so a lake's mesh grows with its rows, not its area. Worked out once a pond and kept on it; reads no
## shared state, so any thread may run it.
static func quads(p: PondLayout.Pond) -> PackedVector3Array:
	if not p.quads.is_empty():
		return p.quads
	var area := p.box.grow(1)
	var w := area.size.x
	var ours := PackedByteArray()
	ours.resize(w * area.size.y)
	for g in p.cells + p.shore:
		ours[(g.y - area.position.y) * w + g.x - area.position.x] = 1
	var squares := PackedByteArray()
	squares.resize(ours.size())
	for g in p.cells:
		var k := (g.y - area.position.y) * w + g.x - area.position.x
		for s in [-w - 1, -w, -1, 0]:
			if ours[k + s] and ours[k + s + 1] and ours[k + s + w] and ours[k + s + w + 1]:
				squares[k + s] = 1
	var verts := PackedVector3Array()
	for j in area.size.y:
		var i := 0
		while i < w:
			if not squares[j * w + i]:
				i += 1
				continue
			var from := i
			while i < w and squares[j * w + i]:
				i += 1
			var a := Terrain.grid_xz(area.position + Vector2i(from, j))
			var b := Terrain.grid_xz(area.position + Vector2i(i, j + 1))
			verts.append_array([Vector3(a.x, 0, a.y), Vector3(b.x, 0, a.y), Vector3(a.x, 0, b.y), Vector3(b.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(a.x, 0, b.y)])
	p.quads = verts
	return verts


## The surface `quads` lays, flat at height 0.
static func sheet(verts: PackedVector3Array) -> ArrayMesh:
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
