class_name Beast
extends Node3D

## A deer or a fox: a CC0 model rigged and animated by hand (`res://animals/sources.json`), its surfaces merged
## into one mesh coloured per vertex, so each animal is one draw call. Every animal of a kind shares that mesh and
## one material; each has its own skeleton and animation player, and shows each motion with one of its own clips.

enum Kind { DEER, FOX }

const SCENES := {Kind.DEER: "res://animals/deer.glb", Kind.FOX: "res://animals/fox.glb"}
const GROUPS := {Kind.DEER: &"deer", Kind.FOX: &"fox"}
const SHADER := "res://src/beast.gdshader"
const IDLE_CLIPS := ["Idle", "Idle_2"]
const EAT_CLIP := "Eating"
const CLIPS := {
	Kind.DEER: {Grazers.Motion.GRAZE: "Eating", Grazers.Motion.STEP: "Walk", Grazers.Motion.WALK: "Walk", Grazers.Motion.RUN: "Gallop"},
	Kind.FOX: {Grazers.Motion.GRAZE: "Idle_2_HeadLow", Grazers.Motion.STEP: "Walk", Grazers.Motion.WALK: "Walk", Grazers.Motion.RUN: "Gallop"},
}
## Scale of the imported model for an animal of size 1, which stands a doe 1.4 m to the ears and a fox 0.5 m.
const SCALE := {Kind.DEER: 0.32, Kind.FOX: 0.13}
## Ground covered in one cycle of the walk and of the gallop at size 1, so the hooves and paws keep their place.
const STRIDE := {Kind.DEER: {"Walk": 1.05, "Gallop": 2.6}, Kind.FOX: {"Walk": 0.62, "Gallop": 1.5}}
## From the middle of the body to its rim, at size 1: how near two stand.
const RADIUS := {Kind.DEER: 0.6, Kind.FOX: 0.3}
const FADE := 0.35

static var _shared := {}

var kind: Kind
var size := 1.0
var player: AnimationPlayer
var _clip := ""
## What `Roamers` has this animal doing, until when, and where to.
var state := Grazers.State.ENTER
var timer := 0.0
var goal := Vector3.ZERO
## How long until it goes for food again; the hand it eats from is `hand`.
var full := 0.0
var hand: Node3D
## How long until, cornered, it looks again for a way to run.
var retry := 0.0
## Calm spells it has had near a person standing still, each letting one come nearer before it runs.
var calm := 0.0


static func prepare() -> void:
	for k in SCENES:
		_share(k)


static func _share(k: Kind) -> Dictionary:
	if not _shared.has(k):
		var scene: PackedScene = load(SCENES[k])
		var probe := scene.instantiate()
		var mi: MeshInstance3D = probe.find_children("*", "MeshInstance3D")[0]
		var player: AnimationPlayer = probe.find_children("*", "AnimationPlayer")[0]
		for clip in IDLE_CLIPS + [EAT_CLIP] + CLIPS[k].values():
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER)
		_shared[k] = {"scene": scene, "mesh": _merged(mi.mesh), "material": mat}
		probe.free()
	return _shared[k]


## One surface of `mesh` with each of its surfaces' albedo carried in the vertex colour, linear as the shader reads it.
static func _merged(mesh: Mesh) -> ArrayMesh:
	var kept := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var format: int = mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	for i in mesh.get_surface_count():
		assert(mesh.surface_get_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS == format)
		var arrays := mesh.surface_get_arrays(i)
		var base: int = 0 if out[Mesh.ARRAY_VERTEX] == null else out[Mesh.ARRAY_VERTEX].size()
		var colours := PackedColorArray()
		colours.resize(arrays[Mesh.ARRAY_VERTEX].size())
		colours.fill((mesh.surface_get_material(i) as BaseMaterial3D).albedo_color.srgb_to_linear())
		arrays[Mesh.ARRAY_COLOR] = colours
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for j in indices.size():
			indices[j] += base
		arrays[Mesh.ARRAY_INDEX] = indices
		for a in kept:
			assert(arrays[a] != null)
			if out[a] == null:
				out[a] = arrays[a]
			else:
				out[a].append_array(arrays[a])
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, format)
	return merged


func _init(of: Kind, scale_by: float, phase: float) -> void:
	kind = of
	size = scale_by
	add_to_group(GROUPS[kind])
	var shared := _share(kind)
	var model: Node3D = shared.scene.instantiate()
	# The import hangs a node on every bone end, each moved with its bone every frame; nothing here uses them.
	for n in model.find_children("*", "BoneAttachment3D"):
		n.free()
	var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D")[0]
	mi.mesh = shared.mesh
	mi.material_override = shared.material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.scale = Vector3.ONE * SCALE[kind] * size
	model.rotation.y = PI
	add_child(model)
	player = model.find_children("*", "AnimationPlayer")[0]
	_play(IDLE_CLIPS[0])
	player.seek(phase * player.current_animation_length, true)


func _play(clip: String, pace := 1.0) -> void:
	player.speed_scale = pace
	if clip == _clip:
		return
	_clip = clip
	player.play(clip, FADE)


func pose(m: Grazers.Motion, _delta: float) -> void:
	if m != Grazers.Motion.IDLE:
		_play(CLIPS[kind][m])
	elif _clip in IDLE_CLIPS:
		player.speed_scale = 1.0
	else:
		_play(IDLE_CLIPS[randi() % IDLE_CLIPS.size()])


## Moves `distance` this tick showing `m`, a walk or gallop paced to the ground covered so the feet keep their place.
func walked(m: Grazers.Motion, distance: float, delta: float) -> void:
	if distance <= 0.0 or delta <= 0.0:
		return
	var clip: String = CLIPS[kind][m]
	var cycle := player.get_animation(clip).length
	_play(clip, clampf(distance / delta * cycle / (STRIDE[kind][clip] * size), 0.3, 2.0))


func eat(_height: float, _delta: float) -> void:
	_play(EAT_CLIP)


func radius() -> float:
	return RADIUS[kind] * size
