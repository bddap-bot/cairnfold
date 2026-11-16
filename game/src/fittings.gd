class_name Fittings
extends Node3D

const HALO_M := 1.1

## Made at load, as Wall's roof materials are: a shader made on first use stalls a frame.
static var _flame := _shaded(preload("res://src/flame.gdshader"))
## A glow in the air has no colour of its own for an icon to draw (Hand.unlit).
static var _halo := _shaded(preload("res://src/halo.gdshader"), Color.TRANSPARENT)
static var _cloth := _shaded(preload("res://src/cloth.gdshader"))
static var _box := BoxMesh.new()
static var _disc := _halo_disc()
static var _strip := _flag_mesh()

var _flames := Masonry.Kind.new(_box, _flame, true, false, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF).instance()
var _halos := Masonry.Kind.new(_disc, _halo, true, false, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF).instance()
var _cloths := Masonry.Kind.new(_strip, _cloth, true, false, GeometryInstance3D.SHADOW_CASTING_SETTING_ON).instance()
## Palette.Element.LANTERN swatch index.
var look := 0


static func _shaded(shader: Shader, icon_colour := Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_meta("icon_colour", icon_colour)
	return m


static func _halo_disc() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * HALO_M
	return q


func _init() -> void:
	for mmi in [_flames, _halos, _cloths]:
		add_child(mmi)


func lay(flames: Array[Transform3D], cloths: Array[Dictionary], burning := 0) -> void:
	var fm := _flames.multimesh
	var hm := _halos.multimesh
	fm.instance_count = flames.size()
	hm.instance_count = flames.size()
	look = burning
	var strength: float = Lamps.STRENGTHS[look % Lamps.STRENGTHS.size()]
	var flame := Basis().scaled(Vector3.ONE * pow(strength, 0.25))
	var halo := Basis().scaled(Vector3.ONE * sqrt(strength))
	var colour := Palette.swatch(Palette.Element.LANTERN, look)
	var glow := Color(Palette.GLOWS[look / Lamps.STRENGTHS.size()], sqrt(strength) * 0.5)
	for i in flames.size():
		fm.set_instance_transform(i, Transform3D(flame * flames[i].basis, flames[i].origin))
		fm.set_instance_color(i, colour)
		hm.set_instance_transform(i, Transform3D(halo, flames[i].origin))
		hm.set_instance_color(i, glow)
	var cm := _cloths.multimesh
	cm.instance_count = cloths.size()
	for i in cloths.size():
		cm.set_instance_transform(i, cloths[i].xform)
		cm.set_instance_color(i, cloths[i].color)
	_flames.visible = not flames.is_empty()
	_halos.visible = not flames.is_empty()
	_cloths.visible = not cloths.is_empty()


func ghostly(mat: Material) -> void:
	for mmi in [_flames, _cloths]:
		mmi.material_override = mat
	_halos.hide()
	_halos.multimesh.instance_count = 0


## Pole at x = 0, out to x = 1, y -0.5 to 0.5. A triangle wound against its normal draws flipped: black on the Quest.
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
