class_name Fittings
extends Node3D

## What a wall carries that is not stone: lantern flames, the glow they hang in the air, and flags waving.

const HALO := 1.1

static var _flame: StandardMaterial3D
static var _halo: ShaderMaterial
static var _cloth: ShaderMaterial
static var _box := BoxMesh.new()
static var _disc := QuadMesh.new()
static var _strip := _flag_mesh()

var _flames := _instances(_box)
var _halos := _instances(_disc)
var _cloths := _instances(_strip)


func _init() -> void:
	if _flame == null:
		_disc.size = Vector2.ONE * HALO
		_flame = StandardMaterial3D.new()
		_flame.albedo_color = Color(1.0, 0.8, 0.5)
		_flame.emission_enabled = true
		_flame.emission = Color(1.0, 0.68, 0.32)
		_flame.emission_energy_multiplier = 2.4
		_halo = ShaderMaterial.new()
		_halo.shader = load("res://src/halo.gdshader")
		_cloth = ShaderMaterial.new()
		_cloth.shader = load("res://src/cloth.gdshader")
	_flames.material_override = _flame
	_halos.material_override = _halo
	_cloths.material_override = _cloth
	for mmi in [_flames, _halos]:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mmi in [_flames, _halos, _cloths]:
		add_child(mmi)


func lay(flames: Array[Transform3D], cloths: Array[Dictionary]) -> void:
	var fm := _flames.multimesh
	var hm := _halos.multimesh
	fm.instance_count = flames.size()
	hm.instance_count = flames.size()
	for i in flames.size():
		fm.set_instance_transform(i, flames[i])
		fm.set_instance_color(i, _flame.albedo_color)
		hm.set_instance_transform(i, Transform3D(Basis(), flames[i].origin))
	var cm := _cloths.multimesh
	cm.instance_count = cloths.size()
	for i in cloths.size():
		cm.set_instance_transform(i, cloths[i].xform)
		cm.set_instance_color(i, cloths[i].color)
	_flames.visible = not flames.is_empty()
	_halos.visible = not flames.is_empty()
	_cloths.visible = not cloths.is_empty()


## Draws every part in `mat`, without the glow round the flames.
func ghostly(mat: Material) -> void:
	for mmi in [_flames, _cloths]:
		mmi.material_override = mat
	_halos.hide()
	_halos.multimesh.instance_count = 0


static func _instances(mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


## A cloth strip from the pole (x = 0) out to x = 1, y from -0.5 to 0.5, cut into columns so it can wave. Each triangle
## winds as its normal faces: one wound against it is drawn as its back face, its normal flipped away, hard black on the Quest.
static func _flag_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 8
	for i in cols:
		var x0 := float(i) / cols
		var x1 := float(i + 1) / cols
		for p in [Vector2(x0, -0.5), Vector2(x1, 0.5), Vector2(x1, -0.5), Vector2(x0, -0.5), Vector2(x0, 0.5), Vector2(x1, 0.5)]:
			st.set_normal(Vector3.BACK)
			st.set_uv(Vector2(p.x, 0.5 - p.y))
			st.add_vertex(Vector3(p.x, p.y, 0.0))
	return st.commit()
