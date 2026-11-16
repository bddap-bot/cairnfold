class_name Avatar
extends Node3D

## A file past the limits below is refused, never decimated: its meshes keep every triangle their author made.

const ExpressionMixer = preload("res://addons/avatar_workshop/expression_mixer.gd")
const SpringRuntime = preload("res://addons/avatar_workshop/spring_runtime.gd")
const SkeletonBone = preload("res://addons/avatar_workshop/skeleton_bone.gd")

const OUTLINE := preload("res://src/avatar_outline.gdshader")
const OUTLINE_CUT := preload("res://src/avatar_outline_cut.gdshader")
const BUILT_IN: Array[String] = ["res://avatars/pebble.vrm", "res://avatars/acorn.vrm", "res://avatars/hood.vrm"]
## A Quest 2 read held up to 19.5 bytes a file byte, the low-memory killer taking background apps but never the game.
## Decoded pixels cost time, not memory, so they set no floor (docs/multiplayer.md, "Limits").
const FLOOR_BYTES := 100 << 20
const READ_BYTES_PER_BYTE := 20
const READ_LOW := 512 << 20
const UNCAPPED := 1e4
const POST_ROW := 2
const HEAD_ROWS := 3
## As many points as the shader reads.
const RAMP := 16
## A board row's height.
const ICON_SIDE_PX := 44.0
const COAT_ROWS := 7
const MATCAP_ROWS := 6
## Poiyomi's slots.
const MATCAPS := 4
const TOON_ROWS := 8
## Poiyomi's clear coat face on: Unity's dielectric specular, in gamma space.
const DIELECTRIC := 0.220916301
## "clearcoatFallbacks": FALLBACK_LEVELS latitude-longitude levels FALLBACK_SIDE wide, half as tall, stacked top down;
## linear light = RGB * alpha * FALLBACK_RANGE, which keeps a lamp far past white in eight bits.
const FALLBACK_SIDE := 256
const FALLBACK_LEVELS := 7
const FALLBACK_RANGE := 128.0
## The material index changes only at the edges of cells many texels wide.
const INDEX_SIDE := 2048
## What a Quest 2's game and seven heavy avatars need besides textures: it leaves each the 8.4 million texels seven ran
## at, not the twice that which ran out of memory (docs/multiplayer.md, "Limits").
const MEMORY_FLOOR := 1700 << 20
## Counts definition joints, terminal nodes included.
const MAX_SPRING_JOINTS := 60
## The 60 Hz steps a PhysBone takes before the controller's first state reaches it. Three fit the SDK's simulation: a
## chain that state switches off then rests a mean 0.07 cm from where the SDK holds it, against 0.46 cm with no step,
## 0.11 with two and 0.25 with five.
const STARTUP_STEPS := 3
## A file asking for more has every system's share cut alike (ParticleDefinition.read).
const MAX_PARTICLE_SYSTEMS := 64
const MAX_PARTICLES := 10000
const MAX_PARTICLE_VERTICES := 250000
## Measured before any decode: a beacon makes every Quest nearby read the file, and blank images decode for seconds.
const MAX_IMAGES := 256
## WebP's widest, within a GPU texture's 16384 px; the memory budget, not this, sets the side each is held at.
const MAX_IMAGE_SIDE := 16383
## The widest image the Quest 2 decoded behind MEMORY_FLOOR; a larger one is whole in memory before it shrinks.
const UNGATED_DECODE_PIXELS := 4096 * 4096
## Blend shapes times vertices moved: a few MB can name thousands of sparse blend shapes, each held whole once read.
const MAX_BLEND_VERTICES := 4000000
const DATA := {"humanoid": {}, "eyes": Vector3(0, 0.06, 0), "forward": Vector3.BACK, "look": {"type": Vrm.BONE, "ranges": [Vector2(90, 10), Vector2(90, 10), Vector2(90, 10), Vector2(90, 10)], "shapes": {}}, "springs": {"springs": [], "colliders": []}}
const FACING := Basis(Vector3.UP, PI)
const NEEDS: Array[String] = ["hips", "head", "leftHand", "rightHand"]
## Body frame, forward -Z: down, out to the side, a little back.
const ELBOW := Vector3(0.5, -1.0, 0.4)
const BEND := 0.4
const LOOK := deg_to_rad(20.0)
const CROUCH_BEND := 1.2
const MAX_BEND := 1.2
## In leg lengths: a leg straight at rest has no slack, so the shin's skin stretches to keep a foot down before it lifts.
const STRETCH := 0.06
const CENTER := 0.3
## So an arm a recording held straight still bends one way.
const ELBOW_HINT := 0.3
## Parents first, as _blend reads them.
const BODY: Array[String] = ["hips", "spine", "chest", "upperChest", "neck", "leftShoulder", "rightShoulder", "leftUpperLeg", "leftLowerLeg", "leftFoot", "leftToes", "rightUpperLeg", "rightLowerLeg", "rightFoot", "rightToes"]
const PARENT := {
	"spine": "hips", "chest": "spine", "upperChest": "chest", "neck": "upperChest", "head": "neck",
	"leftShoulder": "upperChest", "rightShoulder": "upperChest", "leftUpperLeg": "hips", "rightUpperLeg": "hips",
	"leftLowerLeg": "leftUpperLeg", "rightLowerLeg": "rightUpperLeg", "leftFoot": "leftLowerLeg", "rightFoot": "rightLowerLeg",
	"leftToes": "leftFoot", "rightToes": "rightFoot",
}
## Not zero, so normals keep their directions.
const GONE := Basis(Vector3(1e-6, 0, 0), Vector3(0, 1e-6, 0), Vector3(0, 0, 1e-6))
const AT_SIDES: Array[Transform3D] = [Transform3D(Basis(Vector3.RIGHT, -1.2), Vector3(-0.3, -0.65, 0.05)), Transform3D(Basis(Vector3.RIGHT, -1.2), Vector3(0.3, -0.65, 0.05))]

## Thumb to little, palm outward; BENDS, the radians each bone turns as its finger closes.
const FINGERS := [["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"], ["IndexProximal", "IndexIntermediate", "IndexDistal"], ["MiddleProximal", "MiddleIntermediate", "MiddleDistal"], ["RingProximal", "RingIntermediate", "RingDistal"], ["LittleProximal", "LittleIntermediate", "LittleDistal"]]
const BENDS := [[0.3, 0.5, 0.8], [1.3, 1.6, 1.1], [1.4, 1.6, 1.1], [1.4, 1.6, 1.1], [1.4, 1.5, 1.0]]

class Joint:
	var bone: int
	## Model space, as `at` is.
	var rest: Transform3D
	var at: Transform3D
	## The nearest placed bone above; nothing between them moves, so a pose finds the frame without walking the skeleton.
	var base: Joint
	var offset: Transform3D

## upper and lower are null on a limb without them.
class Limb:
	var upper: Joint
	var lower: Joint
	var end: Joint
	var upper_length: float
	var lower_length: float
	## Body frame.
	var bend: Vector3
	var upper_bind: Basis
	var lower_bind: Basis

	func _init(up: Joint, low: Joint, to: Joint, facing: Basis, bend_at_rest: Vector3) -> void:
		bend = bend_at_rest
		upper = up
		lower = low
		end = to
		if not upper:
			return
		var u := upper.rest.origin
		var l := lower.rest.origin
		var e := end.rest.origin
		upper_length = l.distance_to(u)
		lower_length = e.distance_to(l)
		upper_bind = Avatar._frame(facing * (l - u), bend_at_rest).transposed() * facing * upper.rest.basis
		lower_bind = Avatar._frame(facing * (e - l), bend_at_rest).transposed() * facing * lower.rest.basis

class Arm extends Limb:
	## From Hand.palm's frame.
	var grip: Basis
	## Hand-bone space: halfway along the middle metacarpal, where a hand closes round a controller's grip.
	var palm := Vector3.ZERO

	func wrist(at: Transform3D) -> Transform3D:
		var b := at.basis * grip
		return Transform3D(b, at.origin - b * palm)

class Leg extends Limb:
	## Body frame, under the standing centre of mass; `ankle` is its height over the floor.
	var place: Vector3
	var ankle: float

## A built-in's path, or the hash of a player's own file.
var source := ""
var scene: PackedScene
var tint: Color
var eye_height := 0.0
var eyes := Transform3D.IDENTITY
var hands: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var curls := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
## Per hand: [bone, rest rotation, curl axis in bone space, closed angle, finger].
var _fingers: Array = [[], []]
var palms: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var look := Vector3.FORWARD
var torso := NAN
var gait: Gait
var ground := Callable()
var posture := Posture.new()
## A built-in standing in for an undrawn file: its springs are not the file's, which the wearer streams by number.
var stand_in := false
var springs: SpringRuntime
## The chains of `springs` whose PhysBone a switch had off when `_budget` last chose.
var _springs_off := {}
## `movers` of the chains of `springs`.
var _moved_by: Array = []
var simulate_springs := true
var local := false
var expressions: ExpressionPlayer
var particles: AvatarParticles
var spring_holders := {}
var _model: Node3D
var _skeleton: Skeleton3D
var _joints := {}
var _facing: Basis
var _eye_to_head: Transform3D
var _hips: Joint
var _tops: Array[Joint] = []
var _head: Joint
var _arms: Array[Arm] = []
var _legs: Array[Leg] = []
## _body_parent: nearest humanoid parent's index in _body, -1 for the hips; _turns: per Posture.poses, per joint.
var _body: Array[Joint] = []
var _body_parent := PackedInt32Array()
var _head_parent := 0
var _turns: Array[Array] = []
## Null standing.
var _upper_turns: Array[Array] = []
var _alone: Array[Array] = []
## The pose last shown alone, its bones keeping their turns so only the hips move; -1 none; -2 standing, rests restored.
var _settled := -1
var _unposed := 0.0
## _eyes: left then right, empty unless it looks by bone; _shapes: per Vrm.LOOKS, [mesh, blend shape, weight]s.
var _look_type := Vrm.BONE
var _ranges: Array[Vector2] = []
var _eyes: Array[Joint] = []
var _shapes: Array = []
## Held: a mesh frees its own materials before its render instance, whose teardown then reads them.
var _tints: Array[Material] = []


## Read before the garden and avatars load: later, the game's own memory counts twice against MEMORY_FLOOR.
static var launch_memory := available_memory()
## Since the metrics last took them.
static var springs_us := 0
static var _built_in := {}
static var _reading := 0
static var _reading_lock := Mutex.new()


static func built_in(i: int) -> PackedScene:
	var path := BUILT_IN[posmod(i, BUILT_IN.size())]
	if not _built_in.has(path):
		_built_in[path] = read(FileAccess.get_file_as_bytes(path))
	return _built_in[path]


## Tens to hundreds of milliseconds, so a player's file is read on a worker thread. `unlimited` only for the
## converter's check of a file for another renderer.
static func read(bytes: PackedByteArray, unlimited := false, available := available_memory()) -> PackedScene:
	if not unlimited and weight(bytes.size()) > reads(available - _reading):
		return _too_heavy(bytes.size(), available - _reading)
	var images := Vrm.images(bytes)
	if images.size() > MAX_IMAGES or images.any(func(image: Dictionary) -> bool: return maxi(image.size.x, image.size.y) > MAX_IMAGE_SIDE):
		print("avatar: refused: %d images, past %d or one wider than %d" % [images.size(), MAX_IMAGES, MAX_IMAGE_SIDE])
		return null
	var pixels := Vrm.pixels(images)
	var heavy := weight(bytes.size())
	var held := memory_to_read(heavy) - READ_LOW
	_reading_lock.lock()
	var room := available - _reading
	var admitted := unlimited or heavy <= reads(room)
	if admitted:
		_reading += held
	_reading_lock.unlock()
	if not admitted:
		return _too_heavy(bytes.size(), room)
	var decoded := [0]
	var budget := texture_budget()
	# Each image decoded must be the one Vrm.images measured in its place, or the budget would be another file's.
	var fits := func(size: Vector2i) -> bool:
		decoded[0] += 1
		return decoded[0] <= images.size() and (unlimited or decodes(size, budget)) and size == images[decoded[0] - 1].size
	var start := Time.get_ticks_usec()
	var textures := texture_bytes(images)
	var shrink := shrink_for(textures, budget)
	var root := Vrm.read(bytes, fits, shape, func(img: Image, layer: String) -> void: hold(img, layer, shrink))
	var scene := model(root) if root != null else null
	_reading_lock.lock()
	_reading -= held
	_reading_lock.unlock()
	print("avatar: read %.1f MB in %d ms, %d images of %.1f Mpx; textures %.0f MB held 1/%d wide in a %.0f MB budget of %.0f MB available at launch, %.0f MB now" % [bytes.size() / 1048576.0, (Time.get_ticks_usec() - start) / 1000, images.size(), pixels / 1e6, textures / 1048576.0, shrink, budget / 1048576.0, launch_memory / 1048576.0, available_memory() / 1048576.0])
	return scene


static func _too_heavy(size: int, room: int) -> PackedScene:
	print("avatar: refused: %.1f MB is past what %.0f MB of memory reads" % [size / 1048576.0, room / 1048576.0])
	return null


static func reads(available: int) -> float:
	return maxf(1.0, float(available - READ_LOW) / (READ_BYTES_PER_BYTE * FLOOR_BYTES))


static func weight(size: int) -> float:
	return float(size) / FLOOR_BYTES


static func max_bytes() -> int:
	return int(reads(available_memory()) * FLOOR_BYTES)


static func memory_to_read(weight: float) -> int:
	return ceili(weight * READ_BYTES_PER_BYTE * FLOOR_BYTES) + READ_LOW


static func decodes(size: Vector2i, budget: int) -> bool:
	return size.x * size.y <= UNGATED_DECODE_PIXELS or size.x * size.y * 4 <= budget


static func texture_budget() -> int:
	return maxi(launch_memory - MEMORY_FLOOR, 0) / (Session.MAX_PLAYERS - 1)


## Godot reports none on Android.
static func available_memory() -> int:
	var counted := meminfo_available()
	return counted if counted >= 0 else int(OS.get_memory_info().get("available", 0))


## /proc/meminfo reports no length, so only a fixed-size read gets it. Android lets no Godot file open it.
static func meminfo_available() -> int:
	var lines := PackedStringArray()
	var f := FileAccess.open("/proc/meminfo", FileAccess.READ)
	if f != null:
		lines = f.get_buffer(1 << 16).get_string_from_utf8().split("\n")
	else:
		var java: JavaClass = JavaClassWrapper.wrap("java.io.RandomAccessFile")
		var file: Variant = java.call("RandomAccessFile", "/proc/meminfo", "r") if java != null else null
		while file != null:
			var line: Variant = file.call("readLine")
			if not line is String:
				file.call("close")
				break
			lines.append(line)
	for line in lines:
		if line.begins_with("MemAvailable:"):
			return line.split(" ", false)[1].to_int() * 1024
	return -1


static func shrink_for(bytes: int, budget: int) -> int:
	var shrink := 1
	while bytes / (shrink * shrink) > budget and shrink < MAX_IMAGE_SIDE:
		shrink *= 2
	return shrink


const UNSHRUNK := ["icons", "index"]


static func texture_bytes(images: Array[Dictionary]) -> int:
	var shrunk: Array[Dictionary] = []
	shrunk.assign(images.filter(func(image: Dictionary) -> bool: return image.layer not in UNSHRUNK))
	return Vrm.pixels(shrunk) * 4 * 4 / 3


## `root` carries the importer's metas (Vrm), DATA filling the rest. Frees `root` either way.
static func model(root: Node3D) -> PackedScene:
	if root.has_meta("expressions") and not ExpressionDefinition.valid(root.get_meta("expressions")):
		print("avatar: refused: its expressions are not ones this reads")
		root.free()
		return null
	for key: String in DATA:
		if not root.has_meta(key):
			root.set_meta(key, DATA[key].duplicate(true) if DATA[key] is Dictionary else DATA[key])
	_on_one_skeleton(root)
	_switched_off(root)
	_rank_springs(root)
	var bones: Dictionary = root.get_meta("humanoid")
	var drawn := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if _shown(mi, root):
			drawn += triangles(mi.mesh as ArrayMesh)
	var missing := NEEDS.filter(func(b: String) -> bool: return not bones.has(b))
	if not missing.is_empty() or not _outlined(root):
		if not missing.is_empty():
			print("avatar: refused: no %s bone on its skeleton" % ", ".join(missing))
		root.free()
		return null
	for n in root.find_children("*", "", true, false):
		n.owner = root
	ExpressionPlayer.prepare(root)
	var particles := ParticleDefinition.read(root.get_meta("particles", {}))
	root.remove_meta("particles")
	if not particles.is_empty():
		root.set_meta("particle_systems", particles)
	var scene := PackedScene.new()
	scene.pack(root)
	scene.set_meta("colour", root.get_meta("colour", Color.WHITE))
	scene.set_meta("triangles", drawn)
	root.free()
	return scene


static func triangles(mesh: ArrayMesh) -> int:
	var n := 0
	if mesh == null:
		return n
	for i in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(i) == Mesh.PRIMITIVE_TRIANGLES:
			var indices := mesh.surface_get_array_index_len(i)
			n += (indices if indices > 0 else mesh.surface_get_array_len(i)) / 3
	return n


static func _outlined(root: Node3D) -> bool:
	var marked: Array[BaseMaterial3D] = []
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if _marked(m) and not m in marked:
				marked.append(m)
	if marked.is_empty():
		return true
	var looks: Variant = (root.get_meta("expressions", {}) as Dictionary).get("looks")
	if not looks is Dictionary or not looks.get("outline") is Image:
		push_error("avatar: a material is outlined but the looks carry no outline layer")
		return false
	var texture := ImageTexture.create_from_image(looks.outline)
	for m in marked:
		var hull := ShaderMaterial.new()
		hull.shader = OUTLINE_CUT if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else OUTLINE
		hull.set_shader_parameter("outline", texture)
		hull.set_shader_parameter("width", float(looks.outlineWidth))
		hull.set_shader_parameter("picture", m.albedo_texture)
		hull.set_shader_parameter("colour", m.albedo_color)
		hull.set_shader_parameter("mirror_mask", Quality.MIRROR_MASK)
		hulled(m, hull)
	return true


static func _marked(m: Material) -> bool:
	return m is BaseMaterial3D and (m.get_meta("extras", {}) as Dictionary).get("outline", false)


## On a Quest 2 a hull costs 0.6 to 0.8 ms a heavy avatar, toon shading 1.65 to 4.28 ms (docs/design.md).
static var outlines := true
static var toon := true
static var _cuts: Array[WeakRef] = []


static func hulled(m: Material, hull: ShaderMaterial) -> void:
	m.set_meta("hull", hull)
	_cuttable(m)


static func tooned(m: ShaderMaterial, plain: Shader) -> void:
	m.set_meta("shaders", [plain, m.shader])
	_cuttable(m)


static func _cuttable(m: Material) -> void:
	_cut(m)
	_cuts = _cuts.filter(func(w: WeakRef) -> bool: return w.get_ref() != null and w.get_ref() != m)
	_cuts.append(weakref(m))


static func _cut(m: Material) -> void:
	if m.has_meta("hull"):
		m.next_pass = m.get_meta("hull") if outlines else null
	if m.has_meta("shaders"):
		var shader: Shader = m.get_meta("shaders")[1 if toon else 0]
		if (m as ShaderMaterial).shader != shader:
			(m as ShaderMaterial).shader = shader


static func show_outlines(on: bool) -> void:
	outlines = on
	_cut_all()


static func show_toon(on: bool) -> void:
	toon = on
	_cut_all()


static func _cut_all() -> void:
	for w in _cuts:
		var m: Material = w.get_ref()
		if m != null:
			_cut(m)


## For each of `chains`, per segment, the springs of `switched` that move it, by index.
static func movers(chains: Array, switched: Array) -> Array:
	var bones: Array = switched.map(func(s: Dictionary) -> Dictionary:
		var out := {}
		for j: Variant in s.joints:
			out[int(j)] = true
		return out)
	return chains.map(func(chain: Dictionary) -> Array:
		var joints: Array = chain.joints
		var segments := []
		for i in joints.size():
			var segment := [joints[i].node] if i + 1 == joints.size() else [joints[i].node, joints[i + 1].node]
			segments.append(range(bones.size()).filter(func(s: int) -> bool: return segment.all(func(n: Variant) -> bool: return bones[s].has(n))))
		return segments)


## The chains that are off, by index into `moved_by` (`movers`): every segment moved by a switched spring and by none
## that `on` says, by its index, is on, as two PhysBones may take turns on one bone, each reaching its own end.
static func stopped(moved_by: Array, on: Array) -> Dictionary:
	var out := {}
	for c in moved_by.size():
		var segments: Array = moved_by[c]
		if not segments.is_empty() and segments.all(func(by: Array) -> bool: return not by.is_empty() and not by.any(func(s: int) -> bool: return on[s])):
			out[c] = true
	return out


static func _switched_off(root: Node3D) -> void:
	var data: Dictionary = root.get_meta("expressions", {})
	var saved: Array[float] = []
	saved.assign((data.get("targets", []) as Array).map(func(t: Dictionary) -> float: return float(t.get("default", 0.0))))
	var on := func(s: Dictionary) -> bool: return ExpressionPlayer.shows(saved, s.when)
	var colliders := {}
	for s: Dictionary in data.get("colliders", []):
		if not on.call(s):
			colliders[int(s.collider)] = true
	var springs: Dictionary = root.get_meta("springs")
	var switched: Array = data.get("springs", [])
	var off := stopped(movers(springs.springs, switched), switched.map(on))
	springs.springs = range(springs.springs.size()).filter(func(c: int) -> bool: return not off.has(c)).map(func(c: int) -> Dictionary: return springs.springs[c])
	for chain: Dictionary in springs.springs:
		chain.colliders = (chain.colliders as Array).filter(func(c: int) -> bool: return not colliders.has(c))


## Readies every chain for `running`: "length" is metres root to tip at rest, the sway a joint buys, and "drawn_by"
## the meshes whose skin or carrier a joint of it moves. A bone only chains that do not run at start move rests at its
## "settled" rotation (UnityAvatar.settle), as VRChat, running them all, shows it, its joint keeping the "authored"
## one to swing about once it runs. One the controller's first state switches off keeps its authored rest, which
## `_prime` runs it from. A file with no menu keeps only the chains that run: nothing can change the choice.
static func _rank_springs(root: Node3D) -> void:
	var springs: Dictionary = root.get_meta("springs")
	var waiting := _still_at_start(root)
	var chains: Array = SpringRuntime.unshadowed(springs.springs)
	var bones: Dictionary = root.get_meta("humanoid")
	var sk := root.get_node_or_null(str(bones.get("hips", "")).get_slice(":", 0)) as Skeleton3D
	var marks := _mesh_bones(root, sk) if sk else {}
	var shown := {}
	for c in chains.size():
		var chain: Dictionary = chains[c]
		var at: Array = chain.joints.map(func(j: Dictionary) -> int: return _bone(sk, bones.get("spring_%d" % j.node)))
		var by: Array[NodePath] = []
		for mi: MeshInstance3D in marks:
			if at.any(func(b: int) -> bool: return marks[mi].has(b)):
				by.append(root.get_path_to(mi))
				if _shown(mi, root):
					shown[c] = true
		chain.drawn_by = by
		var metres: float = chain.get("end_length", 0.0)
		for i in range(1, at.size()):
			if at[i] >= 0 and at[i - 1] >= 0:
				metres += sk.get_bone_global_rest(at[i]).origin.distance_to(sk.get_bone_global_rest(at[i - 1]).origin)
		chain.length = metres
	var run := running(chains, func(c: int) -> bool: return shown.has(c))
	var moving := {}
	for i: int in run:
		for joint: Dictionary in chains[i].joints:
			moving[joint.node] = true
	var authored := {}
	for i in chains.size():
		if run.has(i):
			continue
		for joint: Dictionary in chains[i].joints:
			var bone := _bone(sk, bones.get("spring_%d" % joint.node))
			if not moving.has(joint.node) and not waiting.has(joint.node) and joint.has("settled") and bone >= 0:
				var rest := sk.get_bone_rest(bone)
				if not authored.has(bone):
					authored[bone] = rest.basis.get_rotation_quaternion()
				joint.authored = authored[bone]
				sk.set_bone_rest(bone, Transform3D(Basis(joint.settled as Quaternion).scaled_local(rest.basis.get_scale()), rest.origin))
	springs.springs = chains if root.has_meta("expressions") else range(chains.size()).filter(func(i: int) -> bool: return run.has(i)).map(func(i: int) -> Dictionary: return chains[i])


## The indices of `chains` that run: none `off` holds; of the rest those `drawn` says by index draw a shown mesh first,
## then the longest, a skirt panel of four joints outranking a strand of ten hanging a tenth as far, while their joints
## fit MAX_SPRING_JOINTS.
static func running(chains: Array, drawn: Callable, off := {}) -> Dictionary:
	var order: Array = range(chains.size()).filter(func(c: int) -> bool: return not off.has(c))
	var shown := {}
	for c: int in order:
		shown[c] = drawn.call(c)
	order.sort_custom(func(x: int, y: int) -> bool: return shown[x] if shown[x] != shown[y] else chains[x].length > chains[y].length)
	var run := {}
	var joints := 0
	for i: int in order:
		var size: int = chains[i].joints.size()
		if joints + size <= MAX_SPRING_JOINTS:
			run[i] = true
			joints += size
	return run


## Chooses again which chains run, from the meshes the menu shows and the PhysBones it has switched on: a chain a
## switch reveals takes the joints of the chains that switch hides, and a chain left out holds the pose it stopped in.
## A chain whose PhysBone is switched on again swings about the pose it was left in, as VRChat's does, so each time it
## is switched off and on it rests where it last sagged to.
func _budget() -> void:
	if springs == null:
		return
	var sources: Array = springs.chains.map(func(chain: Dictionary) -> Dictionary: return chain.source)
	var off := _off(expressions.state.outputs) if expressions != null else {}
	var drawn := func(c: int) -> bool:
		return (sources[c].drawn_by as Array).any(func(p: NodePath) -> bool: return _shown(_model.get_node(p), _model))
	var run := running(sources, drawn, off)
	springs.idle.clear()
	for i in springs.chains.size():
		if not run.has(i):
			springs.idle[i] = true
		if _springs_off.has(i) and not off.has(i):
			for joint: Dictionary in springs.chains[i].joints:
				springs.set_rest(joint.node, joint.node.transform)
	_springs_off = off


## The chains of `springs` whose PhysBone the expression `outputs` switch off.
func _off(outputs: Array[float]) -> Dictionary:
	var switched: Array = _model.get_meta("expressions", {}).get("springs", [])
	if switched.is_empty():
		return {}
	if _moved_by.is_empty():
		_moved_by = movers(springs.chains.map(func(chain: Dictionary) -> Dictionary: return chain.source), switched)
	return stopped(_moved_by, switched.map(func(s: Dictionary) -> bool: return ExpressionPlayer.shows(outputs, s.when)))


## Readies `springs`, just made. A joint `_rank_springs` rested at its settled rotation swings about its authored one.
## The chains the controller's first state switches off take STARTUP_STEPS, as VRChat runs every PhysBone before that
## state reaches it: such a chain then rests clear of the colliders its authored pose overlaps.
func _prime() -> void:
	for chain: Dictionary in springs.chains:
		for joint: Dictionary in chain.joints:
			if joint.has("authored"):
				var rest: Transform3D = joint.rest
				springs.set_rest(joint.node, Transform3D(Basis(joint.authored as Quaternion).scaled_local(rest.basis.get_scale()), rest.origin))
	var data: Dictionary = _model.get_meta("expressions", {})
	if (data.get("springs", []) as Array).is_empty():
		return
	var start := ExpressionState.new(data)
	start.advance(0.0)
	_springs_off = _off(start.outputs)
	if _springs_off.is_empty():
		return
	springs.idle.clear()
	for i in springs.chains.size():
		if not _springs_off.has(i):
			springs.idle[i] = true
	for step in STARTUP_STEPS:
		springs.advance(SpringRuntime.STEP)
	springs.idle.clear()


static func _still_at_start(root: Node3D) -> Dictionary:
	var data: Dictionary = root.get_meta("expressions", {})
	var switched: Array = data.get("springs", [])
	if switched.is_empty():
		return {}
	var start := ExpressionState.new(data)
	start.advance(0.0)
	var still := {}
	var running := {}
	for s: Dictionary in switched:
		var on := ExpressionPlayer.shows(start.outputs, s.when)
		for j: Variant in s.joints:
			(running if on else still)[int(j)] = true
	for j: int in running:
		still.erase(j)
	return still


static func _bone(sk: Skeleton3D, path: Variant) -> int:
	return sk.find_bone((path as NodePath).get_concatenated_subnames()) if sk and path is NodePath else -1


## A file Vrm.read reads keeps in a skin only the binds its mesh weights (Vrm.Skins); another may bind more, and its
## chains then rank by length alone.
## Each mesh, shown or not, to the bones that move it: those its skin binds or its carrier rides, and their parents.
static func _mesh_bones(root: Node3D, sk: Skeleton3D) -> Dictionary:
	var out := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var drawn := {}
		var mark := func(bone: int) -> void:
			while bone >= 0 and not drawn.has(bone):
				drawn[bone] = true
				bone = sk.get_bone_parent(bone)
		if mi.skin != null and mi.get_node_or_null(mi.skeleton) == sk:
			for bind in mi.skin.get_bind_count():
				mark.call(Meshes.bind_bone(mi.skin, bind, sk))
		var carrier := mi.get_parent()
		while carrier != root and not (carrier is BoneAttachment3D and carrier.get_parent() == sk):
			carrier = carrier.get_parent()
		if carrier != root:
			mark.call((carrier as BoneAttachment3D).bone_idx)
		if not drawn.is_empty():
			out[mi] = drawn
	return out


## The model is outside the scene tree, where is_visible_in_tree is false.
static func _shown(node: Node, root: Node) -> bool:
	while node != root:
		if node is Node3D and not (node as Node3D).visible:
			return false
		node = node.get_parent()
	return true


## A pose moves only the skeleton holding the hips.
static func _on_one_skeleton(model: Node3D) -> void:
	var bones: Dictionary = model.get_meta("humanoid")
	var hips: Variant = bones.get("hips")
	var skeleton := str(hips).get_slice(":", 0) if hips is NodePath and (hips as NodePath).get_subname_count() == 1 else ""
	if skeleton == "" or not model.get_node_or_null(skeleton) is Skeleton3D:
		bones.clear()
		return
	var sk: Skeleton3D = model.get_node(skeleton)
	for b: String in bones.keys():
		var path: NodePath = bones[b]
		if str(path).get_slice(":", 0) != skeleton or path.get_subname_count() != 1 or sk.find_bone(path.get_concatenated_subnames()) < 0:
			bones.erase(b)


## Past RenderingServer.MAX_MESH_SURFACES the renderer drops a mesh's remaining surfaces.
static func shape(state: GLTFState) -> bool:
	var blended := 0
	for gm in state.get_meshes():
		for i in gm.mesh.get_surface_count():
			blended += gm.mesh.get_blend_shape_count() * (gm.mesh.get_surface_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	if blended > MAX_BLEND_VERTICES:
		print("avatar: refused: blend shapes over %d vertices, past %d" % [blended, MAX_BLEND_VERTICES])
		return false
	for gm in state.get_meshes():
		gm.mesh = _merged(gm.mesh)
		if gm.mesh.get_surface_count() > RenderingServer.MAX_MESH_SURFACES:
			print("avatar: refused: a mesh of %d materials, past the %d one mesh draws" % [gm.mesh.get_surface_count(), RenderingServer.MAX_MESH_SURFACES])
			return false
	for m in state.get_materials():
		if m is BaseMaterial3D:
			_plain(m)
	var expressions: Variant = Vrm.expressions(state)
	var looks: Variant = expressions.get("looks", {}) if expressions is Dictionary else {}
	if expressions is Dictionary and not ExpressionDefinition.valid(expressions):
		print("avatar: refused: its expressions are not ones this reads")
		return false
	if looks.has("materials") and not looks.get("index") is Image:
		push_error("avatar: the looks name materials without the material index they are drawn by")
		return false
	var shadows: Array = looks.get("materials", []).map(func(m: Dictionary) -> Variant: return m.lighting.get("shadow")).filter(func(shadow: Variant) -> bool: return shadow != null)
	if not shadows.is_empty() and not looks.get("shade") is Image or shadows.any(func(shadow: Dictionary) -> bool: return shadow.get("second") != null) and not looks.get("shade2") is Image:
		push_error("avatar: the looks give a material a toon shadow without the shade layers it is drawn by")
		return false
	var swaps := {}
	var animated := {}
	var nodes := state.get_nodes()
	for target: Variant in expressions.get("targets", []) if expressions is Dictionary else []:
		var effect: Variant = target.get("effect")
		if effect is Dictionary and effect.has("material"):
			var node := int(effect.material.node) if effect.material.node is float or effect.material.node is int else -1
			if node >= 0 and node < nodes.size() and nodes[node].mesh >= 0:
				(swaps.get_or_add(state.get_meshes()[nodes[node].mesh].mesh, []) as Array).append_array(effect.material.choices)
		elif effect is Dictionary and effect.has("look"):
			for region: Dictionary in effect.look:
				(animated.get_or_add(str(region.get("field", "decal")), []) as Array).append(region.get("rect"))
	_lit_looks(looks, state.get_meshes().map(func(gm: GLTFMesh) -> ImporterMesh: return gm.mesh), swaps, animated)
	return true


## The table's layout is expression.gdshaderinc's, whose row constants must match; one column per index entry: a -1
## grazing reflectance marks a Poiyomi coat before 9.2, a -1 fallback Unity's grey. An emission in a global theme
## colour, or one an `animated` look field may light, is drawn even where it rests black.
static func _lit_looks(looks: Dictionary, meshes: Array, swaps := {}, animated := {}) -> void:
	var materials: Array = looks.get("materials", [])
	var drawn := PackedByteArray()
	drawn.resize(256)
	var coats := materials.filter(func(m: Dictionary) -> bool: return m.get("clearcoat") is Dictionary).size()
	var maps: int = (looks.get("clearcoatMaps", []) as Array).size() if looks.get("clearcoatMaps") is Array else 0
	var matcapped := materials.filter(func(m: Dictionary) -> bool: return not _drawn_matcaps(m).is_empty()).size()
	var tooned := materials.filter(_toon).size()
	var rows := HEAD_ROWS + RAMP + (COAT_ROWS if coats + matcapped + tooned > 0 else 0) + (1 + MATCAPS * MATCAP_ROWS if matcapped + tooned > 0 else 0) + (TOON_ROWS if tooned > 0 else 0)
	var table := Image.create_empty(materials.size() + 1, rows, false, Image.FORMAT_RGBAF)
	var textures := (looks.get("matcaps", []) as Array).size()
	var fallbacks: int = (looks.get("clearcoatFallbacks", []) as Array).size() if looks.get("clearcoatFallbacks") is Array else 0
	var posted: Array = animated.get("lightAdd", []) + animated.get("brightness", [])
	for k in materials.size():
		if posted.any(func(r: Variant) -> bool: return ExpressionPlayer.same_rect(r, materials[k].get("rect", []))):
			drawn[k + 1] |= LOOKED
		if not _drawn_matcaps(materials[k]).is_empty():
			drawn[k + 1] |= LOOKED
			_matcap_rows(table, k + 1, materials[k], textures)
		if _toon(materials[k]):
			drawn[k + 1] |= LOOKED | TOON
			_toon_rows(table, k + 1, materials[k])
		var coat: Variant = materials[k].get("clearcoat")
		if coat is Dictionary:
			drawn[k + 1] |= LOOKED | COATED | (FORCES_FALLBACK if coat.forceFallback else 0)
			var st: Array = coat.st
			var inverts: Array = coat.inverts
			var row := HEAD_ROWS + RAMP
			table.set_pixel(k + 1, row, Color(coat.strength, coat.smoothness, coat.reflection, coat.specular))
			table.set_pixel(k + 1, row + 1, Color(st[0], st[1], st[2], st[3]))
			table.set_pixel(k + 1, row + 2, Color(coat.specularTint[0], coat.specularTint[1], coat.specularTint[2], coat.fresnel))
			table.set_pixel(k + 1, row + 3, Color(coat.reflectionTint[0], coat.reflectionTint[1], coat.reflectionTint[2], coat.map if coat.map < maps else -1))
			table.set_pixel(k + 1, row + 4, Color(float(inverts[0]), float(inverts[1]), float(inverts[2]), float(inverts[3])))
			var strength: Variant = coat.fresnelStrength
			table.set_pixel(k + 1, row + 5, Color(coat.gsaa[0], coat.gsaa[1], -1.0 if strength == null else DIELECTRIC + lerpf(DIELECTRIC, 1.0, strength) * 0.5, coat.exposureOcclusion))
			table.set_pixel(k + 1, row + 6, Color(coat.fallback if coat.fallback >= 0 and coat.fallback < fallbacks else fallbacks, float(coat.litFallback), float(coat.forceFallback)))
		var light: Dictionary = materials[k].lighting
		var head := Color(0, 0, 0, 0)
		if light.model == "flat":
			drawn[k + 1] |= LOOKED
			head = Color(1.0, float(light.get("cap", UNCAPPED)), 0.0)
		elif light.has("ramp"):
			drawn[k + 1] |= LOOKED
			head = Color(2.0, float(light.get("cap", UNCAPPED)), float(light.get("shadowTint", 0.0)))
			var ramp: Array = light.ramp
			for i in RAMP:
				var at := i * (ramp.size() - 1) / (RAMP - 1.0)
				table.set_pixel(k + 1, HEAD_ROWS + i, Color(lerpf(ramp[floori(at)], ramp[ceili(at)], at - floorf(at)), 0.0, 0.0))
		var glow: Variant = materials[k].get("emission") if looks.has("emission") else null
		if glow is Dictionary:
			head.a = float(glow.strength)
			var lit: bool = glow.color.any(func(c: Variant) -> bool: return float(c) > 0.0) and (head.a > 0.0 or animated.has("emission"))
			if lit or glow.get("theme") != null:
				drawn[k + 1] |= LOOKED
				table.set_pixel(k + 1, 1, Color(glow.color[0], glow.color[1], glow.color[2], float(glow.get("replace", 0.0))))
		table.set_pixel(k + 1, 0, head)
	if drawn.count(0) == drawn.size():
		return
	var index: Image = looks.index
	var texels := index.get_data()
	var size := index.get_size()
	var looked := {"light_index": ImageTexture.create_from_image(index), "lighting": ImageTexture.create_from_image(table)}
	var copies := {}
	for im: ImporterMesh in meshes:
		var shows := _shows(im, [[1, 1, 0, 0]] + swaps.get(im, []), drawn, texels, size)
		if shows == 0:
			continue
		for i in im.get_surface_count():
			var m := im.get_surface_material(i)
			if m == null:
				continue
			var drawn_as := [m, shows]
			if not copies.has(drawn_as):
				var copy: Material = m.duplicate()
				for key: String in looked:
					copy.set_meta(key, looked[key])
				if shows & COATED:
					copy.set_meta("clearcoat", true)
				if shows & TOON:
					copy.set_meta("toon", true)
				if shows & FORCES_FALLBACK:
					copy.set_meta("coat_forces_fallback", true)
				copies[drawn_as] = copy
			im.set_surface_material(i, copies[drawn_as])


const LOOKED := 1
const COATED := 2
const TOON := 4
const FORCES_FALLBACK := 8


## Each of `moves` is [scale x, scale y, offset x, offset y] in the atlas.
static func _shows(im: ImporterMesh, moves: Array, drawn: PackedByteArray, texels: PackedByteArray, size: Vector2i) -> int:
	var shows := 0
	for i in im.get_surface_count():
		var uvs: Variant = im.get_surface_arrays(i)[Mesh.ARRAY_TEX_UV]
		for moved: Array in moves:
			for uv: Vector2 in uvs if uvs is PackedVector2Array else PackedVector2Array():
				var at := Vector2i(((uv * Vector2(moved[0], moved[1]) + Vector2(moved[2], moved[3])) * Vector2(size)).floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
				shows |= drawn[texels[at.y * size.x + at.x]]
				if shows == LOOKED | COATED | TOON | FORCES_FALLBACK:
					return shows
	return shows


static func _toon(m: Dictionary) -> bool:
	var rim: Variant = m.get("rim")
	var rim_shade: Variant = m.get("rimShade")
	return m.lighting.get("shadow") is Dictionary and m.lighting.model == "flat" or rim is Dictionary and float(rim.strength) > 0.0 or rim_shade is Dictionary and float(rim_shade.strength) > 0.0


static func _toon_rows(table: Image, column: int, m: Dictionary) -> void:
	var row := HEAD_ROWS + RAMP + COAT_ROWS + 1 + MATCAPS * MATCAP_ROWS
	var shadow: Variant = m.lighting.get("shadow")
	if shadow is Dictionary and m.lighting.model == "flat":
		table.set_pixel(column, row, Color(shadow.border, shadow.blur, shadow.strength, 1.0))
		var second: Variant = shadow.get("second")
		if second is Dictionary:
			table.set_pixel(column, row + 1, Color(second.border, second.blur, second.weight, 0.0))
		var edge: Variant = shadow.get("edge")
		if edge is Dictionary:
			table.set_pixel(column, row + 2, Color(edge.color[0], edge.color[1], edge.color[2], edge["range"]))
	var rim: Variant = m.get("rim")
	var rim_shade: Variant = m.get("rimShade")
	var reach := Color(0.0, 0.0, 0.0, rim_shade.strength if rim_shade is Dictionary else 0.0)
	if rim is Dictionary:
		table.set_pixel(column, row + 3, Color(rim.color[0], rim.color[1], rim.color[2], rim.strength))
		table.set_pixel(column, row + 4, Color(rim.main, rim.border, rim.blur, rim.power))
		reach = Color(rim.lit, rim.shadowMask, float(rim.backface), reach.a)
	table.set_pixel(column, row + 5, reach)
	if rim_shade is Dictionary:
		table.set_pixel(column, row + 6, Color(rim_shade.color[0], rim_shade.color[1], rim_shade.color[2], rim_shade.power))
		table.set_pixel(column, row + 7, Color(rim_shade.border, rim_shade.blur, 0.0, 0.0))


## A matcap at zero in all of these leaves its material as it is.
const DRAWN_BY := ["replace", "multiply", "add", "screen", "mixed", "lightAdd", "emission"]


static func _drawn_matcaps(m: Dictionary) -> Array:
	var matcaps: Array = m.get("matcaps", [])
	return range(matcaps.size()).filter(func(k: int) -> bool: return matcaps[k] is Dictionary and DRAWN_BY.any(func(f: String) -> bool: return matcaps[k][f] != 0.0))


static func _matcap_rows(table: Image, column: int, m: Dictionary, textures: int) -> void:
	var row := HEAD_ROWS + RAMP + COAT_ROWS
	var slots := _drawn_matcaps(m)
	table.set_pixel(column, row, Color(slots.size(), 0.0, 0.0, 0.0))
	for k in slots.size():
		var c: Dictionary = m.matcaps[slots[k]]
		var at := row + 1 + k * MATCAP_ROWS
		table.set_pixel(column, at, Color(c.color[0], c.color[1], c.color[2], c.color[3]))
		table.set_pixel(column, at + 1, Color(float(c.texture) if c.texture != null and c.texture < textures else -1.0, 1.0 if c.mode == "reflection" else 0.0, c.border, c.intensity))
		table.set_pixel(column, at + 2, Color(c.replace, c.multiply, c.add, c.screen))
		table.set_pixel(column, at + 3, Color(c.mixed, c.baseMix, c.lightAdd + c.emission, c.lightMask))
		table.set_pixel(column, at + 4, Color(c.hue.shift, c.hue.space, c.hue.select, 1.0) if c.hue != null else Color(0, 0, 0, 0))
		table.set_pixel(column, at + 5, Color(1.0, c.circle.border, c.circle.blur, slots[k]) if c.circle != null else Color(0, 0, 0, slots[k]))


## glTF doubleSided is Unity's Cull Off: a strap modelled facing inward shows only so. Per-pixel lighting, normal maps
## and emission each cost the Quest 2 GPU time over every pixel an avatar covers.
static func _plain(m: BaseMaterial3D) -> void:
	# Avatars stand in the garden's light: an unlit (toon) surface would glow at night.
	if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		m.roughness = 1.0
		m.metallic = 0.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.normal_enabled = false
	m.normal_texture = null
	m.emission_enabled = false
	m.emission_texture = null
	m.cull_mode = BaseMaterial3D.CULL_DISABLED if m.cull_mode == BaseMaterial3D.CULL_DISABLED else BaseMaterial3D.CULL_BACK
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if m.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS if (m.get_meta("extras", {}) as Dictionary).get("depthWrite", false) else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	elif m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR


static func hold(img: Image, layer: String, shrink: int) -> void:
	if layer == "index":
		img.convert(Image.FORMAT_L8)
		var big := maxi(img.get_width(), img.get_height())
		if big > INDEX_SIDE:
			img.resize(img.get_width() * INDEX_SIDE / big, img.get_height() * INDEX_SIDE / big, Image.INTERPOLATE_NEAREST)
	elif layer == "icons":
		var side := maxf(img.get_width(), img.get_height())
		if side > ICON_SIDE_PX:
			img.resize(maxi(roundi(img.get_width() * ICON_SIDE_PX / side), 1), maxi(roundi(img.get_height() * ICON_SIDE_PX / side), 1), Image.INTERPOLATE_LANCZOS)
	else:
		if layer != "":
			img.convert(Image.FORMAT_RGBA8)
		scale_down(img, shrink, layer != "hueMask")


static func scale_down(img: Image, shrink: int, mipmapped := true) -> void:
	if shrink > 1:
		img.resize(maxi(1, img.get_width() / shrink), maxi(1, img.get_height() / shrink), Image.INTERPOLATE_LANCZOS)
	if mipmapped and not img.has_mipmaps():
		img.generate_mipmaps()


static func _merged(im: ImporterMesh) -> ImporterMesh:
	var groups := {}
	for i in im.get_surface_count():
		if im.get_surface_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := im.get_surface_arrays(i)
		var n: int = arrays[Mesh.ARRAY_VERTEX].size()
		if arrays[Mesh.ARRAY_INDEX] == null:
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(range(n))
		var shapes := Meshes.surface_shapes(im, i)
		var key := [im.get_surface_material(i), im.get_surface_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS, arrays.map(func(a: Variant) -> bool: return a == null)]
		var at: Array = groups.get_or_add(key, [])
		if at.is_empty():
			at.append_array([arrays, im.get_surface_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS, im.get_surface_name(i), shapes])
			continue
		Meshes.join(at[0], arrays)
		for k in shapes.size():
			Meshes.join(at[3][k], shapes[k])
	var out := Meshes.shaped_like(im)
	for key: Array in groups:
		var g: Array = groups[key]
		out.add_surface(Mesh.PRIMITIVE_TRIANGLES, g[0], g[3], {}, key[0], g[2], g[1])
	return out


## A file the headset cannot afford (Quality.admit) shows as a built-in body in its colour, as VRChat does.
static func drawn(scene: PackedScene, tint: Color, from: String, whole: bool, body := 0) -> Avatar:
	var a := open(scene, tint, from) if whole or from == "" else open(built_in(body), scene.get_meta("colour", Color.WHITE), from)
	a.stand_in = not (whole or from == "")
	a.add_to_group(Contacts.BODIES)
	return a


static func open(scene: PackedScene, tint: Color, from := "") -> Avatar:
	var a := Avatar.new()
	a.source = from
	a.scene = scene
	a.tint = tint
	a._model = scene.instantiate()
	a.add_child(a._model)
	a._facing = FACING if (a._model.get_meta("forward") as Vector3).z > 0.0 else Basis.IDENTITY
	var bones: Dictionary = a._model.get_meta("humanoid")
	a._skeleton = a._model.get_node(str(bones.hips).get_slice(":", 0))
	a._skeleton.reset_bone_poses()
	if a._model.has_meta("constraints"):
		a._skeleton.add_child(Constraints.new(a._model.get_meta("constraints"), a._skeleton))
	var at := Meshes.relative(a._skeleton, a._model)
	for b: String in bones:
		var j := Joint.new()
		j.bone = a._skeleton.find_bone((bones[b] as NodePath).get_concatenated_subnames())
		j.rest = at * a._skeleton.get_bone_global_rest(j.bone)
		j.at = j.rest
		a._joints[b] = j
	a._hips = a._joints.hips
	a._head = a._joints.head
	# Both VRM versions give the eyes from the head bone in the model's axes, as a head bone turned at rest does not.
	var eye_at := a._head.rest.origin + (a._model.get_meta("eyes") as Vector3)
	a.eye_height = eye_at.y
	a._eye_to_head = Transform3D(a._facing, eye_at).affine_inverse() * a._head.rest
	var look: Dictionary = a._model.get_meta("look")
	a._look_type = look.type
	a._ranges.assign(look.ranges)
	if a._look_type == Vrm.BONE and a._joints.has("leftEye") and a._joints.has("rightEye"):
		a._eyes = [a._joints.leftEye, a._joints.rightEye]
	for dir: String in Vrm.LOOKS:
		var sets := []
		for b: Array in look.shapes.get(dir, []):
			var mi := a._model.get_node(b[0]) as MeshInstance3D
			if b[1] < mi.get_blend_shape_count():
				sets.append([mi, b[1], b[2]])
		a._shapes.append(sets)
	var names: Array[String] = []
	for b in BODY:
		if a._joints.has(b):
			names.append(b)
			a._body.append(a._joints[b])
			a._body_parent.append(names.find(a._parent_of(b)) if b != "hips" else -1)
	a._head_parent = names.find(a._parent_of("head"))
	for p in Posture.poses:
		a._turns.append(names.map(func(b: String) -> Quaternion: return p.turns.get(b, Quaternion.IDENTITY)))
		a._upper_turns.append(["leftUpperArm", "rightUpperArm"].map(func(b: String) -> Variant: return p.turns.get(b)))
	for k in Posture.poses.size():
		a._alone.append(a._blend([k], [Quaternion.IDENTITY], PackedFloat32Array()))
	var placed: Array[Joint] = a._body.duplicate()
	placed.append(a._head)
	for top: int in a._skeleton.get_parentless_bones():
		if top != a._hips.bone:
			var j := Joint.new()
			j.bone = top
			j.rest = at * a._skeleton.get_bone_global_rest(top)
			j.at = j.rest
			a._find_base(j, [])
			a._tops.append(j)
	placed.append_array(a._tops)
	for s in 2:
		var side: String = ["left", "right"][s]
		var hand: Joint = a._joints[side + "Hand"]
		var from_bone: Joint = a._joints.get(side + "LowerArm", a._joints.get(side + "UpperArm"))
		var along := a._facing * (hand.rest.origin - from_bone.rest.origin) if from_bone else Vector3(1 - 2 * s, 0, 0)
		var limbed := a._joints.has(side + "UpperArm") and a._joints.has(side + "LowerArm")
		# The arm's bend is solved in the body's frame, so the body's turn cancels from its binds.
		var arm := Arm.new(a._joints[side + "UpperArm"] if limbed else null, a._joints[side + "LowerArm"] if limbed else null, hand, a._facing, Vector3.BACK)
		# A VRM rests in T-pose, palms down; a hand holding a controller points along it, palm inward.
		var held := _frame(Vector3.FORWARD, Vector3(signf(along.x), 0, 0) * -1.0) * _frame(along, Vector3.DOWN).transposed()
		arm.grip = held * a._facing * hand.rest.basis
		var knuckle: Joint = a._joints.get(side + "MiddleProximal")
		if knuckle:
			arm.palm = hand.rest.affine_inverse() * hand.rest.origin.lerp(knuckle.rest.origin, 0.5)
		if limbed:
			arm.bend = ELBOW * Vector3(signf((a._facing * (hand.rest.origin - arm.upper.rest.origin)).x), 1, 1)
			placed.append_array([arm.upper, arm.lower])
		placed.append(hand)
		a._arms.append(arm)
		var leg_bones: Array = [side + "UpperLeg", side + "LowerLeg", side + "Foot"].map(func(n: String) -> Joint: return a._joints.get(n))
		if not leg_bones.has(null):
			var leg := Leg.new(leg_bones[0], leg_bones[1], leg_bones[2], a._facing, Vector3.FORWARD)
			leg.place = a._facing * (leg.end.rest.origin - a._hips.rest.origin) * Vector3(1, 0, 1)
			leg.ankle = leg.end.rest.origin.y
			placed.append_array(leg_bones)
			a._legs.append(leg)
	for s in 2:
		a._fingers[s] = a._finger_bones(["left", "right"][s])
	if a._legs.size() == 2:
		a.gait = Gait.new(a._legs[0].upper_length + a._legs[0].lower_length, a._hips.rest.origin.y)
	placed.append_array(a._eyes)
	for j: Joint in a._joints.values():
		a._find_base(j, placed)
	a._dress(a._model, tint)
	if a._model.has_meta("expressions"):
		a.expressions = ExpressionPlayer.new(a._model)
		a.expressions.switched.connect(a._budget)
		a.add_child(a.expressions)
	if a._model.has_meta("particle_systems"):
		a.particles = AvatarParticles.new(a._model.get_meta("particle_systems"), a._skeleton, a.expressions)
		a.add_child(a.particles)
	return a


func listened() -> Variant:
	return expressions.contacts.listened(expressions.state.outputs, local) if expressions != null and expressions.contacts.receives() else {}


func contact_senders(tags: Variant = null) -> Array:
	var senders := []
	if not is_visible_in_tree():
		return senders
	var joint := func(name: String) -> Variant: return bone(name).origin if _joints.has(name) else null
	if expressions == null or not expressions.contacts.carries_body:
		senders = Contacts.body_senders(joint, eye_height * global_transform.basis.get_scale().y, self, tags)
	if expressions != null:
		senders.append_array(expressions.contacts.senders(expressions.state.outputs, self, tags))
	return senders


func _finger_bones(side: String) -> Array:
	var out := []
	for f in FINGERS.size():
		var names: Array = (FINGERS[f] as Array).filter(func(n: String) -> bool: return _joints.has(side + n))
		if names.size() < 2:
			continue
		var along: Vector3 = _joints[side + names[-1]].rest.origin - _joints[side + names[0]].rest.origin
		var axis := along.cross(Vector3.DOWN if f > 0 else _across(side) + Vector3.DOWN * 0.5).normalized()
		if not axis.is_finite() or axis.is_zero_approx():
			continue
		for n: String in names:
			var j: Joint = _joints[side + n]
			out.append([j.bone, _skeleton.get_bone_rest(j.bone).basis.get_rotation_quaternion(), (j.rest.basis.orthonormalized().inverse() * axis).normalized(), BENDS[f][FINGERS[f].find(n)], f])
	return out


func _across(side: String) -> Vector3:
	if not (_joints.has(side + "IndexProximal") and _joints.has(side + "LittleProximal")):
		return Vector3.DOWN
	return (_joints[side + "LittleProximal"].rest.origin - _joints[side + "IndexProximal"].rest.origin).normalized()


## 0 straight to 1 closed; the left hand's thumb to little, then the right's (`Hand.curls`).
func curl(by: PackedFloat32Array) -> void:
	if by == curls:
		return
	curls = by.duplicate()
	for s in 2:
		for b: Array in _fingers[s]:
			_skeleton.set_bone_pose_rotation(b[0], (b[1] as Quaternion) * Quaternion(b[2], b[3] * by[s * 5 + b[4]]))


func _parent_of(b: String) -> String:
	var p: String = PARENT[b]
	while not _joints.has(p):
		p = PARENT[p]
	return p


## A pose places the joints parents first, so each one's base is already where this pose puts it.
func _find_base(j: Joint, placed: Array[Joint]) -> void:
	var b := _skeleton.get_bone_parent(j.bone)
	var t := Transform3D.IDENTITY
	while b >= 0:
		for p in placed:
			if p.bone == b:
				j.base = p
				j.offset = t
				return
		t = _skeleton.get_bone_rest(b) * t
		b = _skeleton.get_bone_parent(b)
	j.offset = Meshes.relative(_skeleton, _model) * t


static func _frame(along: Vector3, toward: Vector3) -> Basis:
	var x := along.normalized()
	var y := (toward - x * toward.dot(x)).normalized()
	return Basis(x, y, x.cross(y))


static func _frame_of(j: Joint) -> Transform3D:
	return j.base.at * j.offset if j.base else j.offset


func _get_joint(j: Joint) -> Transform3D:
	return _frame_of(j) * _skeleton.get_bone_pose(j.bone)


func _turn_tops(head: Vector3, body: Basis) -> void:
	var at := head - body * _head.rest.origin
	var floor_y := _feet_floor()
	if is_finite(floor_y):
		at.y = floor_y
	for j in _tops:
		_place(j, Transform3D(body, at) * j.rest)


func _place(j: Joint, xform: Transform3D) -> void:
	_skeleton.set_bone_pose(j.bone, _frame_of(j).affine_inverse() * xform)
	j.at = xform


func bone(name: String) -> Transform3D:
	return global_transform * _get_joint(_joints[name])


## For the wearer's eyes: every vertex the head moves is drawn at the eyes, so what joins it to the body is seen edge
## on. Swaying meshes are left out: the eyes already see them.
func headless() -> Array[MeshInstance3D]:
	var head := {}
	for b in _skeleton.get_bone_count():
		var up := b
		while up >= 0 and up != _head.bone:
			up = _skeleton.get_bone_parent(up)
		if up >= 0:
			head[b] = true
	var seen := swaying()
	var out: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or mi.skin == null or mi.get_node_or_null(mi.skeleton) != _skeleton or mi in seen:
			continue
		var skin: Skin = mi.skin.duplicate()
		for i in skin.get_bind_count():
			if head.has(Meshes.bind_bone(skin, i, _skeleton)):
				skin.set_bind_bone(i, _head.bone)
				skin.set_bind_name(i, _skeleton.get_bone_name(_head.bone))
				skin.set_bind_pose(i, Transform3D(GONE, _eye_to_head.affine_inverse().origin))
		var copy: MeshInstance3D = mi.duplicate()
		copy.skin = skin
		mi.add_sibling(copy)
		out.append(copy)
	return out


func swaying() -> Array[MeshInstance3D]:
	var swings := {}
	for chain: Dictionary in _model.get_meta("springs").springs:
		for joint: Dictionary in chain.joints:
			var j: Joint = _joints.get("spring_" + str(joint.node))
			if j:
				swings[_skeleton.get_bone_name(j.bone)] = true
	var out: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin and mi.skin.get_bind_count() > 0 and mi.get_node_or_null(mi.skeleton) == _skeleton and range(mi.skin.get_bind_count()).map(func(i: int) -> int: return Meshes.bind_bone(mi.skin, i, _skeleton)).all(func(b: int) -> bool: return b >= 0 and swings.has(_skeleton.get_bone_name(b))):
			out.append(mi)
	return out


## No shadows: a shadow pass would double avatars' draw calls.
func _dress(n: Node, tint: Color) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = Quality.PEOPLE_LAYER
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D and m.resource_name.begins_with("tint"):
				var t: StandardMaterial3D = m.duplicate()
				t.albedo_color = tint
				_tints.append(t)
				mi.set_surface_override_material(i, t)
	for c in n.get_children():
		_dress(c, tint)


## In this node's space, hands as Hand.body, `toward` in the eyes' frame; every player solves the rest alike from the
## same streamed pose.
func pose(at: Transform3D, l: Transform3D, r: Transform3D, toward := Vector3.FORWARD) -> void:
	eyes = at
	hands[0] = l
	hands[1] = r
	look = toward
	torso = Torso.follow(torso, at.basis)
	if ground.is_valid():
		posture.update(at, l.origin, r.origin, _floor, get_process_delta_time(), eye_height / Rig.EYE)
	var turn := Basis(Vector3.UP, torso)
	var head := at * _eye_to_head
	var poles: Array[Vector3] = [turn * _arms[0].bend, turn * _arms[1].bend]
	if posture.weights[Posture.STANDING] == 1.0:
		_stand_up(at, head, turn)
	else:
		poles = _lie(head)
	_place(_head, head)
	_look(head)
	for s in 2:
		var arm := _arms[s]
		var grip := arm.wrist(hands[s] * palms[s])
		if arm.upper:
			_bend(arm, grip.origin, poles[s])
		_place(arm.end, grip)

	if springs == null and is_inside_tree():
		var nodes := {}
		for name: String in _joints:
			if name.begins_with("spring_"):
				nodes[int(name.trim_prefix("spring_"))] = SkeletonBone.new(_skeleton, _joints[name].bone)
		springs = SpringRuntime.new(_model.get_meta("springs"), nodes)
		_prime()
		_budget()
		if expressions != null:
			expressions.springs = springs
		# The native springs join the skeleton's modifiers; constraints solve after them.
		var solver := Constraints.of(_skeleton)
		if solver != null:
			_skeleton.move_child(solver, -1)


func _stand_up(at: Transform3D, head: Transform3D, turn: Basis) -> void:
	if _settled != -2:
		for j in _body:
			_skeleton.set_bone_pose(j.bone, _skeleton.get_bone_rest(j.bone))
		_settled = -2
	var body := turn * _facing
	var floor_y := _feet_floor()
	var down := asin(clampf(at.basis.z.normalized().y, -1.0, 1.0))
	var crouch := clampf(1.0 - (at.origin.y - floor_y) / eye_height, 0.0, 1.0) if is_finite(floor_y) else 0.0
	var bent := Basis(turn * Vector3.RIGHT, -minf(BEND * maxf(down - LOOK, 0.0) + CROUCH_BEND * crouch, MAX_BEND))
	var model := Transform3D(bent * body, head.origin - bent * body * _head.rest.origin)
	_turn_tops(head.origin, body)
	_place(_hips, model * _hips.rest)
	for j in _body.slice(1):
		j.at = _get_joint(j)
	if gait:
		_stand(model, Transform3D(body, head.origin - body * _head.rest.origin), turn)


## Returns each arm's elbow pole.
func _lie(head: Transform3D) -> Array[Vector3]:
	var shown: Array[int] = []
	var yaws: Array[Quaternion] = []
	for k in posture.weights.size():
		if posture.weights[k] > 0.0:
			shown.append(k)
			yaws.append(Quaternion(Vector3.UP, torso if k == Posture.STANDING else posture.yaws[k]))
	var lone := shown.size() == 1
	var body: Array[Transform3D] = _alone[shown[0]] if lone else _blend(shown, yaws, posture.weights)
	var frame := Transform3D(Basis(yaws[0]) if lone else Basis.IDENTITY, Vector3.ZERO)
	frame.origin = head.origin - frame.basis * body[-1].origin
	var turned := Quaternion.IDENTITY
	var weighed := 0.0
	for n in shown.size():
		var w: float = posture.weights[shown[n]]
		turned = turned.slerp(yaws[n], w / (weighed + w))
		weighed += w
	_turn_tops(head.origin, Basis(turned) * _facing)
	for i in _body.size():
		if lone and _settled == shown[0] and i > 0:
			_body[i].at = frame * body[i]
		else:
			_place(_body[i], frame * body[i])
	_settled = shown[0] if lone else -1
	var poles: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	for s in 2:
		var arm := _arms[s]
		if not arm.upper:
			continue
		for n in shown.size():
			var elbow := yaws[n] * arm.bend.normalized()
			var upper: Variant = _upper_turns[shown[n]][s]
			if upper != null:
				elbow = elbow * ELBOW_HINT + yaws[n] * (upper as Quaternion) * (_facing * (arm.lower.rest.origin - arm.upper.rest.origin)).normalized()
			poles[s] += elbow * posture.weights[shown[n]]
	return poles


## Hips at the origin; the last is where the neck carries the head.
func _blend(shown: Array[int], yaws: Array[Quaternion], weights: PackedFloat32Array) -> Array[Transform3D]:
	var turns: Array[Quaternion] = []
	turns.resize(_body.size())
	var out: Array[Transform3D] = []
	out.resize(_body.size() + 1)
	for i in _body.size():
		var q := yaws[0] * (_turns[shown[0]][i] as Quaternion)
		if shown.size() > 1:
			q *= weights[shown[0]]
			for n in range(1, shown.size()):
				var more := yaws[n] * (_turns[shown[n]][i] as Quaternion)
				q += more * (weights[shown[n]] * signf(more.dot(q)))
			q = q.normalized()
		turns[i] = q
		var p := _body_parent[i]
		var at := Vector3.ZERO if p < 0 else out[p].origin + turns[p] * (_facing * (_body[i].rest.origin - _body[p].rest.origin))
		out[i] = Transform3D(Basis(q) * _facing * _body[i].rest.basis, at)
	out[-1] = Transform3D(Basis.IDENTITY, out[_head_parent].origin + turns[_head_parent] * (_facing * (_head.rest.origin - _body[_head_parent].rest.origin)))
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_VISIBILITY_CHANGED:
		process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED


func _process(delta: float) -> void:
	_unposed += delta
	if springs != null and simulate_springs:
		step_springs(delta)


func step_springs(delta: float) -> void:
	var start := Time.get_ticks_usec()
	springs.advance(delta)
	springs_us += Time.get_ticks_usec() - start


## As VRM lookAt: an eye looking toward its own side maps by the outer range, toward the nose by the inner.
func _look(head: Transform3D) -> void:
	var yaw := rad_to_deg(atan2(look.x, -look.z))
	var pitch := rad_to_deg(atan2(look.y, Vector2(look.x, look.z).length()))
	var v := _mapped(_ranges[3] if pitch > 0.0 else _ranges[2], pitch)
	for s in _eyes.size():
		var outward := (yaw < 0.0) == (s == 0)
		var h := _mapped(_ranges[1] if outward else _ranges[0], yaw)
		var turn := _facing * Basis(Vector3.UP, -deg_to_rad(h)) * Basis(Vector3.RIGHT, deg_to_rad(v)) * _facing.inverse()
		var rest := _eyes[s].rest
		_place(_eyes[s], head * _head.rest.affine_inverse() * Transform3D(turn * rest.basis, rest.origin))
	if _look_type != Vrm.EXPRESSION:
		return
	# As UniVRM does, expressions take the outer horizontal map both ways.
	var h := _mapped(_ranges[1], yaw)
	var weights := [maxf(-h, 0.0), maxf(h, 0.0), maxf(v, 0.0), maxf(-v, 0.0)]
	var sums := ExpressionMixer.mix(weights, _shapes)
	for mk: Array in sums:
		(mk[0] as MeshInstance3D).set_blend_shape_value(mk[1], sums[mk])


static func _mapped(r: Vector2, angle: float) -> float:
	return clampf(angle, -r.x, r.x) / r.x * r.y


## `side` 0 left, 1 right; until the next `pose`.
func fold(side: int) -> void:
	var at := _get_joint(_arms[side].end)
	_place(_arms[side].end, Transform3D(at.basis.scaled_local(Vector3.ONE * 0.001), at.origin))


func folded(side: int) -> bool:
	return _get_joint(_arms[side].end).basis.get_scale().x < 0.01


## An arm too short still puts its hand on the controller, where held things are; the forearm's skin stretches after it.
func _bend(limb: Limb, to: Vector3, pole: Vector3) -> Vector3:
	var root := _get_joint(limb.upper).origin
	var a := limb.upper_length
	var b := limb.lower_length
	var reach := to - root
	var c := clampf(reach.length(), absf(a - b) + 0.001, a + b - 0.0001)
	var u := reach.normalized() if reach.length() > 0.001 else pole.normalized()
	var p := (pole - u * pole.dot(u)).normalized()
	var cos_a := (a * a + c * c - b * b) / (2.0 * a * c)
	var middle := root + u * a * cos_a + p * a * sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var end := root + u * c
	_place(limb.upper, Transform3D(_frame(middle - root, p) * limb.upper_bind, root))
	_place(limb.lower, Transform3D(_frame(end - middle, p) * limb.lower_bind, middle))
	return end


## The centre of mass is the upright body's, so one bending keeps its balance, knees forward as its hips go back.
func _stand(model: Transform3D, upright: Transform3D, turn: Basis) -> void:
	var places: Array[Vector3] = []
	for leg in _legs:
		places.append(turn * leg.place)
	gait.update(_hips.at.origin, upright * _hips.rest.origin.lerp(_head.rest.origin, CENTER), torso, places, _floor, _unposed)
	_unposed = 0.0
	for s in 2:
		var leg := _legs[s]
		var foot := gait.feet[s]
		if not foot.down:
			for j: Joint in [leg.upper, leg.lower, leg.end]:
				_place(j, model * j.rest)
			continue
		var yaw := Basis(Vector3.UP, foot.yaw)
		var ankle := foot.at + Vector3.UP * leg.ankle
		var reached := _bend(leg, ankle, yaw * leg.bend)
		_place(leg.end, Transform3D(yaw * _facing * leg.end.rest.basis, ankle if reached.distance_to(ankle) < STRETCH * gait.leg else reached))


## -INF where nothing stands under it.
func _floor(p: Vector3) -> float:
	if not ground.is_valid():
		return 0.0
	var to := global_transform if is_inside_tree() else transform
	var w := to * p
	return (to.affine_inverse() * Vector3(w.x, ground.call(w), w.z)).y


func _feet_floor() -> float:
	var y := NAN
	for f in gait.feet if gait else []:
		if f.down and f.t < 0.0:
			y = f.at.y if is_nan(y) else minf(y, f.at.y)
	return y


func stand() -> void:
	var at := Transform3D(Basis.IDENTITY, Vector3(0, eye_height, 0))
	pose(at, at * AT_SIDES[0], at * AT_SIDES[1])
