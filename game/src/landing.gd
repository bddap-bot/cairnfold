class_name Landing
extends MultiMeshInstance3D

## The destination halo: where a teleport will set the player down. One MultiMesh of a few small pieces placed and
## animated wholly in its shader about the node's origin, at the node's scale; it plays from the start each time it
## appears.

## The halo this build draws, chosen before export; the rest are kept to compare in a headset.
enum Style { FLOWERS, FIREFLIES, DANDELION, TOADSTOOLS, PETALS, GHOST, FOOTPRINTS, SUNBEAM, BUBBLE }
const LOOK := Style.TOADSTOOLS
## Each look's shader and how many pieces it draws; the ghost draws the player's own avatar instead.
const LOOKS := {
	Style.FLOWERS: ["res://src/landing_flowers.gdshader", 13],
	Style.FIREFLIES: ["res://src/landing_fireflies.gdshader", 22],
	Style.DANDELION: ["res://src/landing_dandelion.gdshader", 22],
	Style.TOADSTOOLS: ["res://src/landing_toadstools.gdshader", 9],
	Style.PETALS: ["res://src/landing_petals.gdshader", 25],
	Style.GHOST: ["res://src/landing_ghost.gdshader", 0],
	Style.FOOTPRINTS: ["res://src/landing_footprints.gdshader", 2],
	Style.SUNBEAM: ["res://src/landing_sunbeam.gdshader", 14],
	Style.BUBBLE: ["res://src/landing_bubble.gdshader", 9],
}
## Reaches every piece of every look at scale 1, so the halo culls as a whole.
const REACH := Vector3(0.8, 4.2, 0.8)

var _look: Style
var _mat := ShaderMaterial.new()
## The player's own avatar standing where they will, for the ghost; or null.
var _ghost: Avatar
var _clock := 0.0


func _init(look := LOOK) -> void:
	_look = look
	var spec: Array = LOOKS[look]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = toadstool() if look == Style.TOADSTOOLS else QuadMesh.new()
	mm.instance_count = spec[1]
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	multimesh = mm
	_mat.shader = load(spec[0])
	_mat.set_shader_parameter("count", spec[1])
	material_override = _mat
	custom_aabb = AABB(-REACH * Vector3(1, 0.2, 1), REACH * Vector3(2, 1.2, 2))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	visible = false


## Shows the halo at `at`, `size` times its own size and turned to face `ahead`, starting it over if it was hidden.
func put(at: Vector3, size: float, ahead: Vector3) -> void:
	if not visible:
		_clock = 0.0
		visible = true
	var yaw := atan2(-ahead.x, -ahead.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at)
	_mat.set_shader_parameter("base", at.y)
	_mat.set_shader_parameter("size", size)


## The ghost look stands a copy of `a`, the player's avatar, at the target, drawn in the ghost's light.
func wear(a: Avatar) -> void:
	if _look != Style.GHOST:
		return
	if _ghost != null:
		_ghost.queue_free()
	_ghost = Avatar.open(a.scene, Color.WHITE)
	_ghost.stand()
	for m: GeometryInstance3D in _ghost.find_children("*", "GeometryInstance3D", true, false):
		m.material_override = _mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)


func _process(delta: float) -> void:
	if visible:
		_clock += delta
		_mat.set_shader_parameter("clock", _clock)


## A toadstool 1 tall: a domed cap a little wider than it is high over a pale stem, coloured by vertex, the cap red.
static func toadstool() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var rows := [[0.0, 0.12, 0.0], [0.62, 0.09, 0.0], [0.6, 0.42, 1.0], [0.78, 0.36, 1.0], [0.95, 0.22, 1.0], [1.0, 0.0, 1.0]]
	for r in rows.size() - 1:
		for s in sides:
			var quad := []
			for c: Vector2i in [Vector2i(r, s), Vector2i(r + 1, s), Vector2i(r + 1, s + 1), Vector2i(r, s + 1)]:
				var row: Array = rows[c.x]
				var a := TAU * c.y / sides
				quad.append([Vector3(cos(a) * row[1], row[0], sin(a) * row[1]), row[2]])
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color(1, 1, 1, quad[k][1]))
				st.add_vertex(quad[k][0])
	return st.commit()
