class_name Beast
extends Node3D

## Surfaces merged into one vertex-coloured mesh shared by the kind, so each animal is one draw call.

enum Kind { DEER, FOX }

const SCENES := {Kind.DEER: preload("res://animals/deer.glb"), Kind.FOX: preload("res://animals/fox.glb")}
const GROUPS := {Kind.DEER: &"deer", Kind.FOX: &"fox"}
const SHADER := preload("res://src/beast.gdshader")
const IDLE_CLIPS := ["Idle", "Idle_2"]
const EAT_CLIP := "Eating"
const CLIPS := {
	Kind.DEER: {Grazers.Motion.GRAZE: "Eating", Grazers.Motion.STEP: "Walk", Grazers.Motion.WALK: "Walk", Grazers.Motion.RUN: "Gallop"},
	Kind.FOX: {Grazers.Motion.GRAZE: "Idle_2_HeadLow", Grazers.Motion.STEP: "Walk", Grazers.Motion.WALK: "Walk", Grazers.Motion.RUN: "Gallop"},
}
## Metres per model unit at size 1 (a doe 1.4 m to the ears, a fox 0.41 m at the shoulder); other lengths: model units.
const SCALE := {Kind.DEER: 0.32, Kind.FOX: 0.18}
const STRIDE := {Kind.DEER: {"Walk": 3.28125, "Gallop": 8.125}, Kind.FOX: {"Walk": 4.8, "Gallop": 11.5}}
const RADIUS := {Kind.DEER: 1.875, Kind.FOX: 2.3}
const FADE := 0.35
const SHUFFLE_SPEED := 0.05
## Foremost mesh point, in the head bone's rest space.
const MUZZLE := {Kind.DEER: Vector3(-0.001205, 0.009126, 0.000092), Kind.FOX: Vector3(0.001293, 0.007014, 0.000461)}

static var _shared := {}

var kind: Kind
var size := 1.0
var neck: NeckAim
var missed_food := 0.0
var player: AnimationPlayer
var _clip := ""
## Seeded by its phase so a seeded garden's animals idle the same each time.
var _rng := RandomNumberGenerator.new()
var state := Grazers.State.ENTER
var timer := 0.0
var goal := Vector3.ZERO
## Seconds until it goes for food again.
var full := 0.0
var hand: Node3D
var retry := 0.0
## Calm spells near a person standing still, each letting one come nearer before it runs.
var calm := 0.0


static func prepare() -> void:
	for k in SCENES:
		_share(k)


static func _share(k: Kind) -> Dictionary:
	if not _shared.has(k):
		var scene: PackedScene = SCENES[k]
		var probe := scene.instantiate()
		var mi: MeshInstance3D = probe.find_children("*", "MeshInstance3D")[0]
		var player: AnimationPlayer = probe.find_children("*", "AnimationPlayer")[0]
		for clip in IDLE_CLIPS + [EAT_CLIP] + CLIPS[k].values():
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		_shared[k] = {"scene": scene, "mesh": _merged(mi.mesh), "material": mat}
		probe.free()
	return _shared[k]


## Albedo goes in the vertex colour, linear as the shader reads it.
static func _merged(mesh: Mesh) -> ArrayMesh:
	var kept := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]
	var out := []
	var format: int = mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	for i in mesh.get_surface_count():
		assert(mesh.surface_get_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS == format)
		var arrays := mesh.surface_get_arrays(i)
		var colours := PackedColorArray()
		colours.resize(arrays[Mesh.ARRAY_VERTEX].size())
		colours.fill((mesh.surface_get_material(i) as BaseMaterial3D).albedo_color.srgb_to_linear())
		arrays[Mesh.ARRAY_COLOR] = colours
		for a in Mesh.ARRAY_MAX:
			if a in kept:
				assert(arrays[a] != null)
			else:
				arrays[a] = null
		if out.is_empty():
			out = arrays
		else:
			Meshes.join(out, arrays)
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, format)
	return merged


func _init(of: Kind, scale_by: float, phase: float) -> void:
	kind = of
	size = scale_by
	_rng.seed = hash(phase)
	add_to_group(GROUPS[kind])
	var shared := _share(kind)
	var model: Node3D = shared.scene.instantiate()
	# The import hangs a BoneAttachment3D on every bone end, updated every frame; nothing uses them.
	for n in model.find_children("*", "BoneAttachment3D"):
		n.free()
	var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D")[0]
	mi.mesh = shared.mesh
	mi.material_override = shared.material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.scale = Vector3.ONE * metres(kind, size)
	model.rotation.y = PI
	add_child(model)
	player = model.find_children("*", "AnimationPlayer")[0]
	_play(IDLE_CLIPS[0])
	player.seek(phase * player.current_animation_length, true)


func _ready() -> void:
	neck = NeckAim.new()
	neck.configure(find_children("*", "Skeleton3D", true, false)[0], MUZZLE[kind])


func _process(_delta: float) -> void:
	neck.offer = null
	if not Wildlife.in_hand(hand):
		return
	var food := NeckAim.food(hand)
	var distance := Vector2(global_position.x - food.x, global_position.z - food.z).length()
	if distance < neck.stand_off(self, hand) + 0.8:
		neck.offer = hand


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
		_play(IDLE_CLIPS[_rng.randi() % IDLE_CLIPS.size()])


func walked(m: Grazers.Motion, distance: float, delta: float) -> void:
	if delta <= 0.0 or distance / delta < SHUFFLE_SPEED:
		return
	var clip: String = CLIPS[kind][m]
	var cycle := player.get_animation(clip).length
	_play(clip, clampf(distance / delta * cycle / metres(kind, STRIDE[kind][clip] * size), 0.3, 2.0))


func eat(_height: float, _delta: float) -> void:
	_play(EAT_CLIP)


## A deer or a fox never lies down.
func upright() -> float:
	return 1.0


func radius() -> float:
	return metres(kind, RADIUS[kind] * size)


static func metres(k: Kind, units: float) -> float:
	return units * SCALE[k]
