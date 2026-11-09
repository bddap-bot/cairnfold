extends "res://../tests/support/suite.gd"

## Headless checks of avatar particles (docs/particles.md): godot4 --headless --path game --script ../tests/test_avatar_particles.gd

const STEP := 1.0 / 60.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_malformed_files_are_refused()
	_bursts_feed_birth_sub_emitters()
	_switches_and_effects_drive_a_system()
	_rate_and_distance_emit_as_the_emitter_runs()
	_roundtrip()
	finish()


## A burst of four, each particle a birth sub-emitter's burst of three tinted by it; the sub-emitter draws nothing.
static func file(blend := "alpha") -> Dictionary:
	var constant := func(v: float) -> Dictionary: return {"min": [1.0], "max": [1.0], "scale": [v, v]}
	return {"images": [], "meshes": [], "systems": [
		{"node": "emitter", "duration": 1.0, "loop": false, "awake": true, "world": true, "max": 50, "lifetime": constant.call(2.0), "speed": constant.call(0.0), "size": constant.call(0.2),
			"color": {"min": [[1, 0, 0, 1]], "max": [[1, 0, 0, 1]]}, "bursts": [{"time": 0.0, "count": constant.call(4.0), "cycles": 1, "interval": 0.01, "probability": 1.0}],
			"shape": {"type": "sphere", "radius": 0.05, "thickness": 1.0}, "subEmitters": [{"system": 1, "on": "birth", "inherit": ["color"]}],
			"renderer": {"draw": true, "mode": "billboard", "materials": [{"color": [1, 1, 1, 1], "blend": blend}, {"color": [0, 0, 1, 1], "blend": blend}]}},
		{"node": "emitter", "sub": true, "duration": 1.0, "loop": false, "max": 50, "lifetime": constant.call(2.0), "speed": constant.call(0.0),
			"bursts": [{"time": 0.0, "count": constant.call(3.0), "cycles": 1, "interval": 0.01, "probability": 1.0}], "renderer": {"draw": false, "materials": []}},
	]}


static func read(f: Dictionary) -> Dictionary:
	return ParticleDefinition.read(f)


## A skeleton of one bone, "emitter", in the tree.
func skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.add_bone("emitter")
	root.add_child(sk)
	return sk


static func live(p: AvatarParticles, system: int) -> int:
	var s: AvatarParticles.System = p._systems[system]
	var n := 0
	for i in s.births.size():
		if s.births[i] != AvatarParticles.UNBORN and p._now - s.births[i] < s.lives[i]:
			n += 1
	return n


func _malformed_files_are_refused() -> void:
	check(not read(file()).is_empty(), "the fixture reads")
	check(read({"systems": "none"}).is_empty(), "systems that are not a list are refused")
	var unnamed := file()
	unnamed.systems[0].node = 7
	check(read(unnamed).is_empty(), "a system not naming its node is refused")
	var unseen := file()
	unseen.systems[0].renderer.materials[0].image = 3
	check(read(unseen).is_empty(), "a material naming an image the file lacks is refused")
	var bad_material := file()
	bad_material.systems[0].renderer.materials[0] = "red"
	check(read(bad_material).is_empty(), "a material that is not an object is refused")
	var bad_curve := file()
	bad_curve.systems[0].lifetime = {"min": [INF], "max": [1.0], "scale": [1, 1]}
	var d := read(bad_curve)
	check(not d.is_empty() and d.systems[0].lifetime.scale == [5.0, 5.0], "a malformed curve takes Unity's default: %s" % [d.systems[0].lifetime if not d.is_empty() else null])
	var many := file()
	many.systems[0].max = 1e9
	var capped: Array = read(many).systems
	check(capped[0].max + capped[1].max <= Avatar.MAX_PARTICLES and capped[0].max > 9000, "an avatar's particles are capped, each system's share cut alike: %d" % capped[0].max)
	var many_subs := file()
	many_subs.systems[0].subEmitters = range(8).map(func(_k: int) -> Dictionary: return {"system": 1, "on": "birth", "inherit": []})
	check((read(many_subs).systems[0].subEmitters as Array).size() == 8, "a system keeps the eight sub-emitters a footstep effect names")
	var looped := file()
	looped.systems[1].subEmitters = [{"system": 0, "on": "birth", "inherit": []}]
	var unlooped: Array = read(looped).systems
	check(unlooped[0].subEmitters.size() + unlooped[1].subEmitters.size() == 1 and int(unlooped[0].sub) + int(unlooped[1].sub) == 1, "of two systems naming each other, one keeps its sub-emitter: %s" % [unlooped.map(func(s: Dictionary) -> Array: return s.subEmitters)])
	var sub := file()
	sub.systems[0].subEmitters[0].system = 9
	check((read(sub).systems[0].subEmitters as Array).is_empty(), "a sub-emitter naming no system is left out")


func _bursts_feed_birth_sub_emitters() -> void:
	var sk := skeleton()
	var p := AvatarParticles.new(read(file()), sk, null)
	sk.add_child(p)
	p._process(STEP)
	check(live(p, 0) == 4, "the burst gives four particles: %d" % live(p, 0))
	p._process(STEP)
	check(live(p, 1) == 12, "each, the frame after its birth, gives its sub-emitter's burst of three: %d" % live(p, 1))
	var child: AvatarParticles.System = p._systems[1]
	check(child.colours[0].is_equal_approx(Color(1, 0, 0, 1)), "a sub-emitter's particle takes its parent's colour: %s" % child.colours[0])
	for k in 30:
		p._process(STEP)
	check(live(p, 0) == 4 and live(p, 1) == 12, "a burst fires once a cycle, and a system that does not loop stops: %d %d" % [live(p, 0), live(p, 1)])
	for k in 120:
		p._process(STEP)
	check(live(p, 0) == 0 and live(p, 1) == 0, "particles die at the end of their lifetime")
	sk.free()


func _switches_and_effects_drive_a_system() -> void:
	var model := Node3D.new()
	model.set_meta("expressions", {"parameters": [{"name": "On", "type": "bool", "default": 0.0}, {"name": "Pick", "type": "float", "default": 0.0}],
		"targets": [{"effect": "switch", "default": 0.0}, {"effect": {"particle": {"system": 0, "field": "material"}}, "default": 0.0}, {"effect": {"particle": {"system": 0, "field": "rate", "end": "both"}}, "default": 30.0}],
		"particles": [{"system": 0, "when": [[0, 1]]}],
		"clips": [{"length": 1.0, "curves": [{"target": 0, "step": true, "keys": [[0, 1]]}]}, {"length": 1.0, "curves": [{"target": 1, "step": true, "keys": [[0, 1]]}]}],
		"layers": [{"weight": 1.0, "default": 0, "states": [
			{"motion": {}, "transitions": [{"to": 1, "conditions": [{"parameter": "On", "mode": "if"}]}]},
			{"motion": {"clip": 0}, "transitions": [{"to": 0, "conditions": [{"parameter": "On", "mode": "ifNot"}]}]}]},
			{"weight": 1.0, "default": 0, "states": [
			{"motion": {}, "transitions": [{"to": 1, "conditions": [{"parameter": "Pick", "mode": "greater", "threshold": 0.5}]}]},
			{"motion": {"clip": 1}, "transitions": []}]}]})
	check(ExpressionDefinition.valid(model.get_meta("expressions")), "a definition switching and moving a particle system is valid")
	var player := ExpressionPlayer.new(model)
	var sk := skeleton()
	var f := file()
	f.systems[0].loop = true
	var p := AvatarParticles.new(read(f), sk, player)
	sk.add_child(p)
	p._process(STEP)
	check(live(p, 0) == 0, "a system whose switch is off emits nothing")
	player.state.put("On", 1)
	player.state.advance(0)
	p._process(0.1)
	check(live(p, 0) == 4 + 3, "turned on, it plays from its start: its burst and a tenth of a second at the rate the target sets: %d" % live(p, 0))
	var s: AvatarParticles.System = p._systems[0]
	check(s.instance.material_override == s.materials[0], "it draws its first material")
	player.state.put("Pick", 1)
	player.state.advance(0)
	p._process(STEP)
	check(s.instance.material_override == s.materials[1], "a material target chooses its second")
	player.state.put("On", 0)
	player.state.advance(0)
	p._process(STEP)
	check(live(p, 0) == 0 and not s.instance.visible and s.following.is_empty(), "turned off, its particles go at once and its sub-emitter follows none of them")
	sk.free()
	player.free()
	model.free()


func _rate_and_distance_emit_as_the_emitter_runs() -> void:
	var f := file()
	f.systems[0].loop = true
	f.systems[0].bursts = []
	f.systems[0].subEmitters = []
	f.systems[0].distance = {"min": [1.0], "max": [1.0], "scale": [100.0, 100.0]}
	f.systems[0].max = 1000
	var sk := skeleton()
	var p := AvatarParticles.new(read(f), sk, null)
	sk.add_child(p)
	p._process(STEP)
	p._process(STEP)
	check(live(p, 0) == 0, "an emitter at rest emits nothing by distance")
	sk.position = Vector3(0.1, 0, 0)
	p._process(STEP)
	check(live(p, 0) == 10, "moved a tenth of a metre at a hundred a metre, it emits ten: %d" % live(p, 0))
	var s: AvatarParticles.System = p._systems[0]
	check(s.starts[0].distance_to(Vector3(0.1, 0, 0)) < 0.06, "a world-space particle starts where the emitter is: %s" % s.starts[0])
	sk.free()


## A converted avatar's particles survive a VRM export and import: the system's node by name and its texture.
func _roundtrip() -> void:
	var scene: PackedScene = preload("res://demo/expressions.gd").scene()
	var model := scene.instantiate() as Node3D
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var f := file()
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color8(0, 255, 0, 128))
	f.systems[0].node = sk.get_bone_name(0)
	f.systems[1].node = sk.get_bone_name(0)
	f.systems[0].renderer.materials[0].image = 0
	f.images = [image]
	model.set_meta("springs", {})
	model.set_meta("particles", f)
	Vrm.write(model, "user://particles.vrm")
	model.free()
	var bytes := FileAccess.get_file_as_bytes("user://particles.vrm")
	var json: Dictionary = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
	var written: Dictionary = json.extensions.get(Vrm.PARTICLES, {})
	check((written.get("systems", []) as Array).size() == 2 and written.systems[0].node is float, "the systems are written with their node's index")
	var index := int(written.systems[0].renderer.materials[0].get("image", -1)) if not written.is_empty() else -1
	check(index >= 0 and json.images[index].mimeType == "image/webp", "a particle texture is written as a WebP image")
	var reloaded := Avatar.read(bytes)
	check(reloaded != null, "the avatar with particles reads back")
	if reloaded == null:
		return
	var avatar := Avatar.open(reloaded, Color.WHITE)
	var p := avatar.find_child("Particles", false, false) as AvatarParticles
	check(p != null and p._systems.size() == 2 and p._systems[0].bone >= 0, "the read avatar runs both systems on their bone")
	var texture: Texture2D = p._systems[0].materials[0].get_shader_parameter("albedo") if p != null else null
	check(texture != null and texture.get_image().get_pixel(0, 0).is_equal_approx(Color8(0, 255, 0, 128)), "the texture reads back losslessly")
	avatar.free()
