class_name Snails
extends Shy

## Pond-bed grazers gliding along the bed of a filled pond, turning at its banks and walls.
const CAP := 24
const PER_POND := 7
const CELLS_EACH := 8
const SPEED := 0.012
const DEPTH := 0.12


func _init(home: Wildlife, seed: int) -> void:
	super(home, seed, body(), "res://src/snails.gdshader", CAP, "snails")


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


func habitats() -> Dictionary:
	var ponds := wildlife.water.ponds
	var out := {}
	for p: PondWater in ponds:
		if p.full():
			out[p] = Wildlife._pond_quota(p, ponds.size(), CAP, CELLS_EACH, PER_POND)
	return out


## Snails come by night as by day.
func active() -> bool:
	return true


## One comes to a wet point of the bed, out of sight where it finds one there.
func arrive(home: Object) -> One:
	var spot := Vector3.INF
	for attempt in 8:
		var xz := Terrain.grid_xz(home.pond.cells[rng.randi() % home.pond.cells.size()])
		var at := wildlife.terrain.ground(xz.x, xz.y)
		if _wet(home, at):
			spot = at
			if not wildlife._in_sight(at):
				break
	if spot == Vector3.INF:
		return null
	var s := One.new()
	s.position = spot
	s.yaw = rng.randf() * TAU
	s.clock = rng.randf() * TAU
	return s


func _wet(p: PondWater, at: Vector3) -> bool:
	return wildlife.water.pond_at(at.x, at.z) == p and p.surface_y() - wildlife.terrain.height_at(at.x, at.z) >= DEPTH


func think(s: One, delta: float) -> void:
	s.pose = Color(s.clock, s.shown, 0, 0)
	if s.leaving:
		return
	if not _wet(s.home, s.position):
		s.leaving = true
		leave(s)
		return
	s.timer -= delta
	if s.timer <= 0.0:
		s.timer = rng.randf_range(4.0, 10.0)
		s.yaw += rng.randf_range(-0.6, 0.6)
	s.rotation.y = lerp_angle(s.rotation.y, s.yaw, minf(delta, 1.0))
	var t := s.transform
	var next := t.origin - t.basis.z * SPEED * delta
	if _wet(s.home, next) and wildlife._swims_clear(t.origin, Vector2(next.x, next.z), s.home):
		t.origin = Vector3(next.x, wildlife.terrain.height_at(next.x, next.z), next.z)
	else:
		s.yaw += PI * delta
	# Match the local bed slope; the soft foot fills the small gap between samples.
	t.basis = upright(wildlife.terrain.up_at(t.origin, 0.03), t.basis.z)
	s.transform = t
