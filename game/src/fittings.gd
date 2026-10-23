class_name Fittings
extends Node3D

## What a wall carries that is not stone: lantern flames, the glow they hang in the air, and flags waving.

const HALO := 1.1

## Made as the game loads, as Wall's roof materials are: a shader made on first use stalls a frame.
static var _flame := _flame_material()
## A glow in the air has no colour of its own for an icon to draw (Hand.unlit).
static var _halo := _shaded("res://src/halo.gdshader", Color.TRANSPARENT)
static var _cloth := _shaded("res://src/cloth.gdshader")
static var _box := BoxMesh.new()
static var _disc := _halo_disc()
static var _strip := _flag_mesh()

var _flames := Masonry.Kind.new(_box, _flame, true, false, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF).instance()
var _halos := Masonry.Kind.new(_disc, _halo, true, false, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF).instance()
var _cloths := Masonry.Kind.new(_strip, _cloth, true, false, GeometryInstance3D.SHADOW_CASTING_SETTING_ON).instance()


static func _flame_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.8, 0.5)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.68, 0.32)
	m.emission_energy_multiplier = 2.4
	return m


static func _shaded(shader: String, icon_colour := Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader)
	m.set_meta("icon_colour", icon_colour)
	return m


static func _halo_disc() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * HALO
	return q


func _init() -> void:
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
