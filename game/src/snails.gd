class_name Snails
extends Node3D

## Pond-bed grazers, drawn as one MultiMesh sharing one mesh and material.
const CAP := 24
const PER_POND := 7
const CELLS_EACH := 8
const SPEED := 0.012
const DEPTH := 0.12
var wildlife: Wildlife
var rng := RandomNumberGenerator.new()
var crawling: Array[One] = []
var crowd: Crowd
var _due := {}
var _came := {}

class One extends Node3D:
	var pond: PondWater
	var heading := 0.0
	var turn := 0.0
	var phase := 0.0
	var shown := 0.0

func _init(home: Wildlife, seed: int) -> void:
	wildlife = home
	rng.seed = seed
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/snails.gdshader")
	crowd = Crowd.new(body(), CAP, mat)
	add_child(crowd)

static func body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Meshes.ellipsoid(st, 1, Vector3(0, 0.009, 0), Vector3(0.022, 0.009, 0.052), Color("9ebf85"), 7, 12)
	Meshes.ellipsoid(st, 1, Vector3(0, 0.021, -0.033), Vector3(0.019, 0.017, 0.019), Color("bdd39a"), 7, 12)
	Meshes.ellipsoid(st, 0, Vector3(0, 0.037, 0.012), Vector3(0.028, 0.031, 0.032), Color("c98b4d"), 7, 12)
	# Raised whorls on both sides remain legible from either side at hand distance.
	for side in [-1.0, 1.0]:
		for i in 48:
			for j in 5:
				for corner: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
					var t := float(corner.x) / 48.0
					var a := t * TAU * 2.15
					var r := 0.002 + 0.025 * t
					var at := Vector3(side * (0.029 * sqrt(maxf(0.0, 1.0 - pow(r / 0.034, 2.0)))), 0.039 + sin(a) * r, 0.012 + cos(a) * r)
					var v := TAU * corner.y / 5.0
					var n := Vector3(cos(v) * side, sin(v) * sin(a), sin(v) * cos(a))
					st.set_color(Color("71472f"))
					st.set_uv2(Vector2.ZERO)
					st.set_normal(n)
					st.add_vertex(at + n * 0.0016)
		Meshes.ellipsoid(st, 2, Vector3(side * 0.013, 0.043, -0.044), Vector3(0.0025, 0.022, 0.0025), Color("bdd39a"), 4, 6, Callable(), Basis(Vector3.UP, PI / 6.0))
		Meshes.ellipsoid(st, 2, Vector3(side * 0.013, 0.064, -0.044), Vector3.ONE * 0.004, Color("313f32"), 5, 8)
	return st.commit()

func _wet(p: PondWater, at: Vector3) -> bool:
	return wildlife.water.pond_at(at.x, at.z) == p and p.surface_y() - Terrain.height_at(at.x, at.z) >= DEPTH

func tick(delta: float) -> void:
	var ponds := wildlife.water.ponds
	for p in _came.keys():
		if not is_instance_valid(p) or not ponds.has(p):
			_came.erase(p)
	var have := {}
	var share := CAP / maxi(1, ponds.size())
	for i in range(crawling.size() - 1, -1, -1):
		var s := crawling[i]
		s.pond = wildlife.water.pond_at(s.position.x, s.position.z)
		var count: int = have.get(s.pond, 0)
		if s.pond == null or not _wet(s.pond, s.position) or count >= wanted(s.pond, share):
			crawling.remove_at(i)
			s.queue_free()
		else:
			have[s.pond] = count + 1
			_came[s.pond] = true
	var waiting := ponds.filter(func(p: PondWater) -> bool: return not _came.has(p) and p.surface_y() >= p.pond.level - 0.001)
	for p in wildlife._ripe(_due, waiting, Wildlife.ARRIVE_AFTER, delta, true, rng):
		_came[p] = true
	for p: PondWater in ponds:
		if not _came.has(p) or have.get(p, 0) >= wanted(p, share) or crawling.size() >= CAP:
			continue
		for attempt in 8:
			var xz := Terrain.grid_xz(p.pond.cells[rng.randi() % p.pond.cells.size()])
			var at := Terrain.ground(xz.x, xz.y)
			if not _wet(p, at):
				continue
			var s := One.new()
			s.pond = p
			s.position = at
			s.heading = rng.randf() * TAU
			s.phase = rng.randf() * TAU
			s.add_to_group("snails")
			add_child(s)
			crawling.append(s)
			break
	for i in crawling.size():
		var s := crawling[i]
		s.phase += delta
		s.turn -= delta
		if s.turn <= 0.0:
			s.turn = rng.randf_range(4.0, 10.0)
			s.heading += rng.randf_range(-0.6, 0.6)
		s.rotation.y = lerp_angle(s.rotation.y, s.heading, minf(delta, 1.0))
		var next := s.position - s.basis.z * SPEED * delta
		if _wet(s.pond, next) and wildlife._swims_clear(s.position, Vector2(next.x, next.z)):
			s.position = Terrain.ground(next.x, next.z)
		else:
			s.heading += PI * delta
		# Match the local bed slope; the soft foot fills the small gap between samples.
		var at := s.position
		var normal := Vector3(Terrain.height_at(at.x - 0.03, at.z) - Terrain.height_at(at.x + 0.03, at.z), 0.06, Terrain.height_at(at.x, at.z - 0.03) - Terrain.height_at(at.x, at.z + 0.03)).normalized()
		var right := normal.cross(s.basis.z).normalized()
		s.basis = Basis(right, normal, right.cross(normal))
		s.shown = minf(s.shown + delta / 1.5, 1.0)
		crowd.put(i, s.transform, Color(s.phase, s.shown, 0, 0))
	crowd.upload(crawling.size())

static func wanted(p: PondWater, share: int) -> int:
	return clampi(p.pond.cells.size() / CELLS_EACH, mini(1, share), mini(PER_POND, share))
