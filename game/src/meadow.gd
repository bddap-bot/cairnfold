class_name Meadow
extends Node3D

const GRASS_CLUMPS := 22000
const GRASS_RADIUS := 36.0
const FLOWERS := 3200
const TREES := 46


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_ground()
	_grass(rng)
	_flowers(rng)
	_trees(rng)


func _ground() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/terrain.gdshader")
	mat.set_shader_parameter("detail", Look.detail_noise())
	var mi := MeshInstance3D.new()
	mi.mesh = Terrain.build_mesh()
	mi.material_override = mat
	add_child(mi)


func _grass(rng: RandomNumberGenerator) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/grass.gdshader")
	var patches := FastNoiseLite.new()
	patches.seed = 9
	patches.frequency = 0.06
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = Meshes.grass_clump(7, 1)
	mm.instance_count = GRASS_CLUMPS
	for i in GRASS_CLUMPS:
		var p := _scatter(rng, GRASS_RADIUS)
		var s := rng.randf_range(0.75, 1.25)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		mm.set_instance_transform(i, Transform3D(basis, p))
		var v := rng.randf_range(0.85, 1.1)
		mm.set_instance_color(i, Color(v, v, v))
		mm.set_instance_custom_data(i, Color(clampf(0.4 + patches.get_noise_2d(p.x, p.z) * 1.2, 0.0, 1.0), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _flowers(rng: RandomNumberGenerator) -> void:
	var palette := [Color(0.97, 0.96, 0.92), Color(1.0, 0.85, 0.25), Color(0.95, 0.62, 0.72), Color(0.72, 0.62, 0.95), Color(0.98, 0.45, 0.30)]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.8
	var kind := FastNoiseLite.new()
	kind.seed = 17
	kind.frequency = 0.08
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Meshes.flower(6)
	mm.instance_count = FLOWERS
	for i in FLOWERS:
		var p := _scatter(rng, GRASS_RADIUS * 0.95)
		while kind.get_noise_2d(p.z * 1.9, p.x * 1.9) < 0.05 and rng.randf() < 0.85:
			p = _scatter(rng, GRASS_RADIUS * 0.95)
		var k := int(clampf((kind.get_noise_2d(p.x, p.z) + 0.6) / 1.2, 0.0, 0.999) * palette.size())
		var s := rng.randf_range(0.7, 1.4)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		mm.set_instance_color(i, palette[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _trees(rng: RandomNumberGenerator) -> void:
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.roughness = 1.0
	leaf_mat.backlight_enabled = true
	leaf_mat.backlight = Color(0.25, 0.35, 0.08)
	var bark_mat := StandardMaterial3D.new()
	bark_mat.albedo_color = Color(0.36, 0.27, 0.2)
	bark_mat.roughness = 1.0
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.3
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 1
	var trunks: Array[Transform3D] = []
	var leaves: Array[Array] = []
	var greens := [Color(0.16, 0.34, 0.08), Color(0.24, 0.42, 0.1), Color(0.14, 0.30, 0.12), Color(0.32, 0.46, 0.12)]
	for t in TREES:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(24.0, 58.0)
		var base := Vector3(cos(ang) * r, 0, sin(ang) * r)
		base.y = Terrain.height_at(base.x, base.z) - 0.2
		var h := rng.randf_range(2.6, 4.8)
		trunks.append(Transform3D(Basis().scaled(Vector3(1, h, 1)), base + Vector3.UP * h * 0.5))
		var green: Color = greens[rng.randi() % greens.size()]
		var size := h * 0.62
		var crown := base + Vector3.UP * (h + size * 0.2)
		for b in rng.randi_range(6, 10):
			var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.8), rng.randf_range(-1, 1)) * size * 0.6
			var s := size * rng.randf_range(0.55, 0.85)
			leaves.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.85, s)), crown + off), green * rng.randf_range(0.9, 1.1)])
	for b in 60:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(14.0, 40.0)
		var p := Vector3(cos(ang) * r, 0, sin(ang) * r)
		p.y = Terrain.height_at(p.x, p.z) + 0.1
		var s := rng.randf_range(0.4, 0.9)
		leaves.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.7, s)), p), greens[rng.randi() % greens.size()] * 0.95])
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.mesh = trunk
	tm.instance_count = trunks.size()
	for i in trunks.size():
		tm.set_instance_transform(i, trunks[i])
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = tm
	tmi.material_override = bark_mat
	add_child(tmi)
	var lm := MultiMesh.new()
	lm.transform_format = MultiMesh.TRANSFORM_3D
	lm.use_colors = true
	lm.mesh = Meshes.blob(4)
	lm.instance_count = leaves.size()
	for i in leaves.size():
		lm.set_instance_transform(i, leaves[i][0])
		lm.set_instance_color(i, leaves[i][1])
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = lm
	lmi.material_override = leaf_mat
	add_child(lmi)


func _scatter(rng: RandomNumberGenerator, radius: float) -> Vector3:
	var r := sqrt(rng.randf()) * radius
	var a := rng.randf() * TAU
	var p := Vector3(cos(a) * r, 0, sin(a) * r)
	p.y = Terrain.height_at(p.x, p.z) - 0.02
	return p
