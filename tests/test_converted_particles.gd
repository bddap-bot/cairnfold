extends "res://../tests/support/suite.gd"

const Yaml = preload("res://../scripts/unity/yaml.gd")
const Assets = preload("res://../scripts/unity/assets.gd")
const Prefabs = preload("res://../scripts/unity/prefabs.gd")
const Materials = preload("res://../scripts/unity/materials.gd")
const UnityAvatar = preload("res://../scripts/unity_avatar.gd")
const Particles = preload("res://../scripts/unity/particles.gd")

const STEP := 1.0 / 60.0
const RADIUS := 0.5
const COUNT := 100
const ANGLE := 25.0
const CUTOFF := 0.3
const DISABLED := "  ShapeModule:\n    enabled: 0\n"
const PLAIN := "plain"


func _run() -> void:
	seed(1)
	var dir := ProjectSettings.globalize_path("user://converted-particles")
	DirAccess.make_dir_recursive_absolute(dir)
	var blends := _materials(dir)
	_each_shape_reads_and_emits_as_converted(dir)
	_each_blend_reads_and_draws_as_converted(dir, blends)
	_each_sub_emitter_event_reads_and_fires_as_converted(dir)
	finish()


func _materials(dir: String) -> Array[String]:
	var write := func(guid: String, text: String) -> void:
		FileAccess.open(dir.path_join(guid + ".mat"), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(guid + ".mat.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	var head := "Material:\n  m_Shader: {fileID: 211, guid: 0000000000000000f000000000000000, type: 0}\n  m_SavedProperties:\n    m_Floats:\n"
	var guids: Array[String] = []
	for pair: Array in Particles.BLENDS:
		var guid := "pair%d%d" % pair
		write.call(guid, head + "    - _SrcBlend: %d\n    - _DstBlend: %d\n" % pair)
		guids.append(guid)
	for mode in 3:
		var guid := "mode%d" % mode
		write.call(guid, head + "    - _Mode: %d\n    - _Cutoff: %s\n" % [mode, CUTOFF])
		guids.append(guid)
	write.call(PLAIN, head + "    - _SrcBlend: 5\n    - _DstBlend: 10\n")
	return guids


static func _system(k: int, shape: String, material: String, lifetime: float, subs: Array) -> String:
	var go := 10 * k + 1
	var text := """--- !u!1 &%d
GameObject:
  m_Name: System %d
  m_IsActive: 1
  m_Component:
  - component: {fileID: %d}
  - component: {fileID: %d}
  - component: {fileID: %d}
--- !u!4 &%d
Transform:
  m_GameObject: {fileID: %d}
  m_Father: {fileID: 2}
--- !u!198 &%d
ParticleSystem:
  m_GameObject: {fileID: %d}
  lengthInSec: 1
  looping: 0
  playOnAwake: 1
  moveWithTransform: 1
  InitialModule:
    enabled: 1
    startLifetime:
      minMaxState: 0
      scalar: %s
    startSpeed:
      minMaxState: 0
      scalar: 1
    maxNumParticles: %d
  EmissionModule:
    enabled: 1
    m_Bursts:
    - time: 0
      countCurve:
        minMaxState: 0
        scalar: %d
      cycleCount: 1
      repeatInterval: 0.01
      probability: 1
""" % [go, k, go + 1, go + 2, go + 3, go + 1, go, go + 2, go, lifetime, 4 * COUNT, COUNT if k == 1 else 3]
	text += shape
	if not subs.is_empty():
		text += "  SubModule:\n    enabled: 1\n    subEmitters:\n"
		for s: Array in subs:
			text += "    - emitter: {fileID: %d}\n      type: %d\n      properties: %d\n" % [10 * s[0] + 3, s[1], s[2]]
	text += """--- !u!199 &%d
ParticleSystemRenderer:
  m_GameObject: {fileID: %d}
  m_Enabled: 1
  m_Materials:
  - {fileID: 2100000, guid: %s, type: 2}
""" % [go + 3, go, material]
	return text


func _converted(dir: String, systems: Array[String]) -> Particles:
	var objs := Yaml.objects("""--- !u!1 &1
GameObject:
  m_Name: Avatar
  m_Component:
  - component: {fileID: 2}
--- !u!4 &2
Transform:
  m_GameObject: {fileID: 1}
  m_Father: {fileID: 0}
""" + "".join(systems))
	var sk := Skeleton3D.new()
	sk.add_bone("emitter")
	sk.set_meta("unity_bones", {1: 0})
	var rests: Array[Transform3D] = [Transform3D.IDENTITY]
	var found := UnityAvatar._particle_systems(objs, 2, {}, sk, rests)
	sk.free()
	return Particles.new(Prefabs.new(Assets.new(dir)), Materials.new(Assets.new(dir)), objs, found, UnityAvatar._paths(objs, 2), [])


func _simulated(particles: Particles, frames: int) -> Array:
	var read := ParticleDefinition.read({"systems": particles.systems, "meshes": particles.meshes, "images": particles.images})
	if read.is_empty():
		return [read, null, null]
	var sk := Skeleton3D.new()
	for system: Dictionary in particles.systems:
		sk.add_bone(system.node)
	root.add_child(sk)
	var p := AvatarParticles.new(read, sk, null)
	sk.add_child(p)
	for f in frames:
		p._process(STEP)
	return [read, p, sk]


static func live(p: AvatarParticles, system: int) -> int:
	var s: AvatarParticles.System = p._systems[system]
	var n := 0
	for i in s.births.size():
		if s.births[i] != AvatarParticles.UNBORN and p._now - s.births[i] < s.lives[i]:
			n += 1
	return n


static func _all(points: PackedVector3Array, holds: Callable) -> bool:
	return Array(points).all(holds)


static func _any(points: PackedVector3Array, holds: Callable) -> bool:
	return Array(points).any(holds)


func _emits_as(type: String, at: PackedVector3Array, heading: PackedVector3Array) -> bool:
	var within := func(v: Vector3) -> bool: return v.length() <= RADIUS + 1e-4
	var out := func(v: Vector3) -> bool: return v.length() > RADIUS / 4.0
	var forward := func(v: Vector3) -> bool: return v.is_equal_approx(Vector3.BACK)
	match type:
		"point":
			return _all(at, func(v: Vector3) -> bool: return v.is_zero_approx()) and _all(heading, forward)
		"sphere":
			return _all(at, within) and _any(at, func(v: Vector3) -> bool: return v.z < -RADIUS / 4.0) and _any(at, func(v: Vector3) -> bool: return v.z > RADIUS / 4.0)
		"hemisphere":
			return _all(at, within) and _all(at, func(v: Vector3) -> bool: return v.z >= -1e-4) and _any(at, out) and _any(heading, func(v: Vector3) -> bool: return v.z < 0.5)
		"cone":
			return _all(heading, func(v: Vector3) -> bool: return v.z >= cos(deg_to_rad(ANGLE)) - 1e-4) and _any(heading, func(v: Vector3) -> bool: return v.z < 0.999) and _all(at, func(v: Vector3) -> bool: return v.z >= -1e-4) and _any(at, out)
		"box":
			return _all(at, func(v: Vector3) -> bool: return absf(v.x) <= 0.5 and absf(v.y) <= 0.5 and absf(v.z) <= 0.5) and _any(at, func(v: Vector3) -> bool: return absf(v.z) > 0.1) and _all(heading, forward)
		"circle":
			return _all(at, within) and _all(at, func(v: Vector3) -> bool: return is_zero_approx(v.z)) and _any(at, func(v: Vector3) -> bool: return absf(v.y) > RADIUS / 4.0) and _all(heading, func(v: Vector3) -> bool: return is_zero_approx(v.z))
		"edge":
			return _all(at, func(v: Vector3) -> bool: return absf(v.x) <= RADIUS + 1e-4 and is_zero_approx(v.y) and is_zero_approx(v.z)) and _any(at, out) and _all(heading, func(v: Vector3) -> bool: return v.is_equal_approx(Vector3.UP))
	return false


func _each_shape_reads_and_emits_as_converted(dir: String) -> void:
	var modules: Array[String] = [DISABLED]
	for type: int in Particles.SHAPES:
		modules.append("  ShapeModule:\n    enabled: 1\n    type: %d\n    angle: %s\n    length: 1\n    radius:\n      value: %s\n" % [type, ANGLE, RADIUS])
	var produced := {}
	for module in modules:
		var particles := _converted(dir, [_system(1, module, PLAIN, 2.0, [])])
		var type: String = particles.systems[0].shape.type
		produced[type] = true
		var run := _simulated(particles, 2)
		check(not run[0].is_empty() and run[0].systems[0].shape.type == type, "a converted %s shape reads as one: %s" % [type, run[0].systems[0].shape.type if not run[0].is_empty() else null])
		if run[1] == null:
			continue
		var p: AvatarParticles = run[1]
		var s: AvatarParticles.System = p._systems[0]
		var place: Transform3D = run[0].systems[0].shape.matrix
		var born := range(s.births.size()).filter(func(i: int) -> bool: return s.births[i] != AvatarParticles.UNBORN)
		var at := PackedVector3Array(born.map(func(i: int) -> Vector3: return place.affine_inverse() * s.starts[i]))
		var headings := PackedVector3Array(born.map(func(i: int) -> Vector3: return (place.basis.inverse() * s.velocities[i]).normalized()))
		check(live(p, 0) == COUNT and _emits_as(type, at, headings), "a converted %s shape emits from where its kind does, %d particles" % [type, live(p, 0)])
		(run[2] as Node).free()
	var names := produced.keys()
	names.sort()
	var runtime := ParticleDefinition.SHAPES.duplicate()
	runtime.sort()
	check(names == runtime, "the converter writes every shape the reader keeps and no other: %s against %s" % [names, runtime])


func _each_blend_reads_and_draws_as_converted(dir: String, guids: Array[String]) -> void:
	var produced := {}
	for guid in guids:
		var particles := _converted(dir, [_system(1, DISABLED, guid, 2.0, [])])
		var blend: String = particles.systems[0].renderer.materials[0].blend
		produced[blend] = true
		var run := _simulated(particles, 0)
		check(not run[0].is_empty() and run[0].systems[0].renderer.materials[0].blend == blend, "a converted %s blend reads as one" % blend)
		if run[1] == null:
			continue
		var mat: ShaderMaterial = (run[1] as AvatarParticles)._systems[0].materials[0]
		var cutoff := CUTOFF if blend == "cutout" else 0.0
		check(mat.shader == AvatarParticles.SHADERS.get(blend) and is_equal_approx(float(mat.get_shader_parameter("cutoff")), cutoff), "a converted %s blend draws with its shader, cut at %s" % [blend, mat.get_shader_parameter("cutoff")])
		(run[2] as Node).free()
	var names := produced.keys()
	names.sort()
	var runtime := AvatarParticles.SHADERS.keys()
	runtime.sort()
	check(names == runtime, "the converter writes every blend the simulator draws and no other: %s against %s" % [names, runtime])


func _each_sub_emitter_event_reads_and_fires_as_converted(dir: String) -> void:
	var all := (1 << Particles.INHERITED.size()) - 1
	var particles := _converted(dir, [_system(1, DISABLED, PLAIN, 0.5, [[2, 0, all], [3, 2, 0], [4, 1, 0]]), _system(2, DISABLED, PLAIN, 2.0, []), _system(3, DISABLED, PLAIN, 2.0, []), _system(4, DISABLED, PLAIN, 2.0, [])])
	var subs: Array = particles.systems[0].get("subEmitters", [])
	check(subs.map(func(s: Dictionary) -> String: return s.on) == ["birth", "death"], "a birth and a death sub-emitter convert, a collision's is left out: %s" % [subs])
	if subs.size() != 2:
		return
	var run := _simulated(particles, 2)
	check(not run[0].is_empty() and run[0].systems[0].subEmitters == subs.map(func(s: Dictionary) -> Dictionary: return {"system": s.system, "on": s.on, "inherit": s.inherit}), "each converted sub-emitter reads as converted: %s" % [run[0].systems[0].subEmitters if not run[0].is_empty() else null])
	check(subs[0].inherit == Particles.INHERITED, "every inherited property converts: %s" % [subs[0].inherit])
	if run[1] == null:
		return
	var p: AvatarParticles = run[1]
	var born: int = subs[0].system
	var died: int = subs[1].system
	check(live(p, 0) == COUNT and live(p, born) == 3 * COUNT and live(p, died) == 0, "a birth sub-emitter fires as its parent's particles are born, a death one waits: %d %d" % [live(p, born), live(p, died)])
	for f in 40:
		p._process(STEP)
	check(live(p, 0) == 0 and live(p, died) == 3 * COUNT, "a death sub-emitter fires as its parent's particles die: %d" % live(p, died))
	check(live(p, 6 - born - died) == 3, "the system a collision would start emits its own burst alone: %d" % live(p, 6 - born - died))
	(run[2] as Node).free()
