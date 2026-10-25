class_name Smoke
extends MultiMeshInstance3D

## Smoke rising from chimney pots: a few soft puffs a pot, each a quad that its shader (smoke.gdshader) turns to the eye
## and lifts, drifts downwind, swells and fades through its own share of the rise, so smoke costs the processor nothing
## once laid.

const PUFFS := 5
## How high and how far downwind the shader carries a puff before it is gone.
const RISE := 2.4
const DRIFT := 1.6

static var _material := _made()
static var _quad := QuadMesh.new()


static func _made() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://src/smoke.gdshader")
	m.set_shader_parameter("rise", RISE)
	m.set_shader_parameter("drift", DRIFT)
	m.set_meta("icon_colour", Color.TRANSPARENT)
	return m


func _init() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _quad
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Puffs rising from each of `vents`, each pot's set apart in phase so neighbours never puff together.
func lay(vents: PackedVector3Array) -> void:
	multimesh.instance_count = vents.size() * PUFFS
	var box := AABB()
	for v in vents.size():
		var lag := fposmod(vents[v].x * 0.37 + vents[v].z * 0.61, 1.0)
		for k in PUFFS:
			var i := v * PUFFS + k
			multimesh.set_instance_transform(i, Transform3D(Basis(), vents[v]))
			multimesh.set_instance_color(i, Color(1, 1, 1, fposmod(lag + float(k) / PUFFS, 1.0)))
		var reach := AABB(vents[v] - Vector3(DRIFT + 1.0, 0.5, DRIFT + 1.0), Vector3(DRIFT * 2.0 + 2.0, RISE + 1.5, DRIFT * 2.0 + 2.0))
		box = reach if v == 0 else box.merge(reach)
	custom_aabb = box
	visible = not vents.is_empty()
