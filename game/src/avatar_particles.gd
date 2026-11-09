class_name AvatarParticles
extends Node3D

## An avatar's particle systems (docs/particles.md), each drawn as one MultiMesh. The CPU decides when particles are
## born, where and with what start values, and writes each once; particle.gdshaderinc works out where a particle is at
## any age, so a frame costs the CPU only its births. A system runs while the expressions' switches it is drawn under
## are on, playing from its start each time they turn on, as a GameObject switched on plays its ParticleSystem.

## The shader each blend draws with.
const SHADERS := {"alpha": preload("res://src/particle_alpha.gdshader"), "add": preload("res://src/particle_add.gdshader"), "premultiplied": preload("res://src/particle_premultiplied.gdshader"), "multiply": preload("res://src/particle_multiply.gdshader"), "opaque": preload("res://src/particle_opaque.gdshader"), "cutout": preload("res://src/particle_opaque.gdshader")}
## particle.gdshaderinc's curve rows, each the low end of a range, the high end the row after.
const ROW_COLOUR := 0
const ROW_SIZE := 2
const ROW_PATH := 4
const ROW_VELOCITY := 6
const ROW_SPIN_PATH := 8
const ROW_NOISE_LIMIT := 10
const ROW_COLOUR_BY_SPEED := 12
const ROW_SIZE_BY_SPEED := 14
const ROWS := 16
## The samples of each curve row: as many as a converted file's curves carry.
const CURVE_SAMPLES := 16
const GRAVITY := Vector3(0, -9.81, 0)
## A slot no particle holds was born this long ago.
const UNBORN := -1e9
## Unity's limit dampens speed past it by its share each thirtieth of a second.
const DAMPEN_RATE := 30.0
## How many slots past a living one a birth looks for a free one, before it is dropped as a full system's is.
const SLOT_SEARCH := 16
## Past this the clock starts again, once nothing is alive, so the birth times the GPU reads keep their precision.
const CLOCK_SPAN := 3600.0

var _skeleton: Skeleton3D
## The skeleton's constraint solver, which places a system on a bone it moves.
var _solver: Constraints
var _expressions: ExpressionPlayer
var _systems: Array[System] = []
var _now := 0.0
## Each "particle" effect of the expressions: [target index, effect].
var _effects := []
## The value each target had when its effects last set it.
var _applied: Array[float] = []
## When this frame's first birth began, -1 before it: births alone spend Budget.PARTICLE_BIRTHS_US of the frame.
var _births_from := -1
## Runs every system whatever its switches, playing again each that stops: the most an avatar's particles cost, which
## a bench prices.
var unswitched := false


class System:
	var definition: Dictionary
	var bone := -1
	var when := []
	var multimesh: MultiMesh
	var instance: MultiMeshInstance3D
	var materials: Array[ShaderMaterial] = []
	var active := false
	var playing := false
	var time := 0.0
	## The fraction of a particle its rates have built up toward the next birth.
	var pending := 0.0
	var bursts_fired := PackedInt32Array()
	var frame := Transform3D.IDENTITY
	var velocity := Vector3.ZERO
	var placed := false
	var slot := 0
	var alive_until := 0.0
	var births := PackedFloat32Array()
	var lives := PackedFloat32Array()
	var gravities := PackedFloat32Array()
	var starts := PackedVector3Array()
	var velocities := PackedVector3Array()
	var sizes := PackedVector3Array()
	var rotations := PackedVector3Array()
	var colours := PackedColorArray()
	## [child System, "birth" or "death", inherited properties].
	var children := []
	## A child's emission from each living particle of its parent: {"child", "on", "inherit", "parent" slot, "born",
	## "time", "pending", "bursts_fired", "last" position}.
	var following := []


## Runs `definition` (ParticleDefinition.read) on the bones of `skeleton`, switched and moved by `expressions`'s
## targets where it has any.
func _init(definition: Dictionary, skeleton: Skeleton3D, expressions: ExpressionPlayer) -> void:
	name = "Particles"
	_skeleton = skeleton
	_solver = Constraints.of(skeleton)
	_expressions = expressions
	process_priority = 2
	var data: Dictionary = expressions.state.data if expressions != null else {}
	var meshes: Array = definition.get("meshes", [])
	for d: Dictionary in definition.get("systems", []):
		var s := System.new()
		s.definition = d.duplicate(true)
		s.bone = skeleton.find_bone(d.node)
		_systems.append(s)
	for p: Dictionary in data.get("particles", []):
		if ExpressionDefinition._index(p.system, _systems.size()):
			_systems[int(p.system)].when = p.when
	for s in _systems:
		for sub: Dictionary in s.definition.subEmitters:
			s.children.append([_systems[sub.system], sub.on, sub.inherit])
		_build(s, meshes)
	var targets: Array = data.get("targets", [])
	for i in targets.size():
		var effect: Variant = targets[i].get("effect")
		if effect is Dictionary and effect.has("particle") and ExpressionDefinition._index(effect.particle.system, _systems.size()):
			_effects.append([i, effect.particle])
	_applied.resize(targets.size())
	_applied.fill(NAN)


func _build(s: System, meshes: Array) -> void:
	var d := s.definition
	var r: Dictionary = d.renderer
	var count: int = d.max
	for list: Variant in [s.births, s.lives, s.gravities, s.starts, s.velocities, s.sizes, s.rotations, s.colours]:
		list.resize(count)
	s.births.fill(UNBORN)
	if not r.draw or count == 0 or s.bone < 0:
		return
	var mesh: Mesh
	if r.mode == "mesh":
		mesh = meshes[r.mesh]
	else:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		mesh = quad
	s.multimesh = MultiMesh.new()
	s.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	s.multimesh.use_colors = true
	s.multimesh.use_custom_data = true
	s.multimesh.mesh = mesh
	s.multimesh.instance_count = count
	# Each instance is 12 floats of transform, 4 of colour and 4 of custom data: born never, alive a second.
	var buffer := PackedFloat32Array()
	buffer.resize(count * 20)
	for i in count:
		buffer[i * 20 + 16] = UNBORN
		buffer[i * 20 + 17] = 1.0
	s.multimesh.buffer = buffer
	s.instance = MultiMeshInstance3D.new()
	s.instance.multimesh = s.multimesh
	s.instance.top_level = true
	s.instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.instance.layers = Quality.PEOPLE_LAYER
	# Particles are placed by the shader, never by the instance transforms the engine would bound them by.
	s.instance.custom_aabb = AABB(Vector3.ONE * -1e4, Vector3.ONE * 2e4)
	s.instance.visible = false
	add_child(s.instance)
	var curves := ImageTexture.create_from_image(_curves(d))
	var by_size: Array = d.sizeBySpeed.range if d.has("sizeBySpeed") else [0.0, 1.0]
	var by_colour: Array = d.colorBySpeed.range if d.has("colorBySpeed") else [0.0, 1.0]
	for m: Dictionary in r.materials:
		var mat := ShaderMaterial.new()
		mat.shader = SHADERS[m.blend]
		var tint: Color = m.color
		var glow: Color = m.emission
		var uniforms := {
			"curves": curves, "gravity": GRAVITY, "world_space": d.world, "mode": ParticleDefinition.MODES.find(r.mode),
			"align": ParticleDefinition.ALIGNS.find(r.align), "pivot": r.pivot, "length_scale": r.length,
			"velocity_scale": r.velocityScale, "max_size": r.maxSize, "has_velocity": d.has("velocity"),
			"velocity_in_world": d.has("velocity") and d.velocity.world, "has_noise": d.has("noise"),
			"has_limit": d.has("limit"), "has_size_by_speed": d.has("sizeBySpeed"), "has_colour_by_speed": d.has("colorBySpeed"),
			"has_colour_over_life": d.has("colorOverLife"), "has_spin": d.has("spin"),
			"speed_ranges": Vector4(by_size[0], by_size[1], by_colour[0], by_colour[1]),
			"noise_frequency": d.noise.frequency if d.has("noise") else 0.0, "damping": _damping(d),
			"tint": Vector4(tint.r, tint.g, tint.b, tint.a), "emission": Vector3(glow.r, glow.g, glow.b), "uv_transform": m.uv,
			"cutoff": m.cutoff if m.blend == "cutout" else 0.0, "textured": m.has("texture"),
		}
		for key: String in uniforms:
			mat.set_shader_parameter(key, uniforms[key])
		if m.has("texture"):
			mat.set_shader_parameter("albedo", m.texture)
		s.materials.append(mat)
	s.instance.material_override = s.materials[0]


func _process(delta: float) -> void:
	_now += delta
	if _now > CLOCK_SPAN and _systems.all(func(s: System) -> bool: return s.alive_until < _now and s.following.is_empty()):
		_now = 0.0
		for s in _systems:
			s.alive_until = 0.0
			_clear(s)
	_births_from = -1
	var outputs: Array[float] = []
	if _expressions != null:
		outputs = _expressions.state.outputs
	_apply(outputs)
	var origin := _skeleton.global_transform
	var moved := PackedFloat32Array()
	moved.resize(_systems.size())
	# Every system is placed and switched before any emits, so a parent's first particles find their sub-emitters on.
	for k in _systems.size():
		var s := _systems[k]
		if s.bone < 0:
			continue
		var pose := _solver.placed(s.bone) if _solver != null else origin * _skeleton.get_bone_global_pose(s.bone)
		var frame := Transform3D(pose.basis.orthonormalized(), pose.origin)
		s.velocity = (frame.origin - s.frame.origin) / delta if s.placed and delta > 0.0 else Vector3.ZERO
		moved[k] = frame.origin.distance_to(s.frame.origin) if s.placed else 0.0
		s.frame = frame
		s.placed = true
		var on := unswitched or outputs.is_empty() or ExpressionPlayer.shows(outputs, s.when)
		if on != s.active:
			s.active = on
			if on and s.definition.awake:
				_play(s)
			elif not on:
				# A GameObject switched off hides its particles at once; its sub-emitters follow none of them.
				s.playing = false
				_clear(s)
	# A parent's particles that died this frame give their death bursts before births take their slots.
	for s in _systems:
		_follow(s, delta)
	for k in _systems.size():
		var s := _systems[k]
		if unswitched and s.active and not s.playing:
			_play(s)
		if s.active and s.playing and not s.definition.sub:
			_run(s, delta, moved[k])
		# A system whose particles have all died draws nothing, though each slot would collapse to a point.
		if s.instance != null:
			s.instance.visible = s.active and _now < s.alive_until
			for mat in s.materials:
				mat.set_shader_parameter("now", _now)
				mat.set_shader_parameter("emitter", Projection(s.frame))


## Sets each particle effect's field to its target's value where that changed. A tint or emission is set on every
## material a clip may choose, as Unity's animator sets it on whichever its renderer draws.
func _apply(outputs: Array[float]) -> void:
	for e: Array in _effects:
		var i: int = e[0]
		if i >= outputs.size() or outputs[i] == _applied[i]:
			continue
		_applied[i] = outputs[i]
		var v := outputs[i]
		var p: Dictionary = e[1]
		var s := _systems[int(p.system)]
		var d := s.definition
		var channel := int(p.get("channel", 0))
		var linear := v if channel == 3 else Color(v, v, v).srgb_to_linear().r
		match p.field:
			"material":
				if s.instance != null:
					s.instance.material_override = s.materials[clampi(roundi(v), 0, s.materials.size() - 1)]
			"tint", "emission":
				for mat in s.materials:
					var c: Variant = mat.get_shader_parameter(p.field)
					c[channel] = linear
					mat.set_shader_parameter(p.field, c)
			"color":
				for end: String in ["min", "max"] if p.get("end", "both") == "both" else [p.end]:
					var samples: PackedColorArray = d.color[end]
					for k in samples.size():
						var c := samples[k]
						c[channel] = linear
						samples[k] = c
					d.color[end] = samples
			_:
				for c: Dictionary in d[p.field] if d[p.field] is Array else [d[p.field]]:
					match p.get("end", "both"):
						"min": c.scale[0] = v
						"max": c.scale[1] = v
						_: c.scale = [v, v]


func _play(s: System) -> void:
	s.playing = true
	s.time = 0.0
	s.pending = 0.0
	s.bursts_fired.resize((s.definition.bursts as Array).size())
	s.bursts_fired.fill(0)


## Clears every particle of `s`, so no slot holds a birth time the clock could come round to again.
func _clear(s: System) -> void:
	s.following.clear()
	for i in s.births.size():
		if s.births[i] != UNBORN:
			s.births[i] = UNBORN
			if s.multimesh != null:
				s.multimesh.set_instance_custom_data(i, Color(UNBORN, 1.0, 0.0, 0.0))


## Emits `s`'s particles for a step of `delta` in which its emitter moved `moved`.
func _run(s: System, delta: float, moved: float) -> void:
	var d := s.definition
	var before: float = s.time - d.delay
	s.time += delta
	var at: float = s.time - d.delay
	if at < 0.0:
		return
	var count := 0
	if not d.loop and at > d.duration:
		s.playing = false
		at = d.duration
	elif d.loop and floorf(maxf(before, 0.0) / d.duration) != floorf(at / d.duration):
		count += _bursts(d.bursts, s.bursts_fired, d.duration)
		s.bursts_fired.fill(0)
	var cycle := fmod(at, d.duration) if d.loop else at
	var u: float = cycle / d.duration
	# Births past the system's room would find no slot whenever they were made.
	s.pending = minf(s.pending + _value(d.rate, u, randf()) * delta + _value(d.distance, u, randf()) * moved + _bursts(d.bursts, s.bursts_fired, cycle) + count, d.max)
	s.pending -= _emit_up_to(int(s.pending), func() -> void: _emit(s, s.frame, s.velocity, u, null, -1))


## How many particles the bursts not yet fired by time `t` of a cycle give, counting each fired in `fired`.
func _bursts(bursts: Array, fired: PackedInt32Array, t: float) -> int:
	var count := 0
	for b in bursts.size():
		var burst: Dictionary = bursts[b]
		while fired[b] < int(burst.cycles) and burst.time + fired[b] * burst.interval <= t:
			fired[b] += 1
			if randf() < burst.probability:
				count += roundi(_value(burst.count, 0.0, randf()))
	return count


## Emits each child's particles from the living particles of `s` that it follows, and from those that died.
func _follow(s: System, delta: float) -> void:
	if s.children.is_empty():
		return
	var kept := []
	for f: Dictionary in s.following:
		var parent: int = f.parent
		var child: System = f.child
		if s.births[parent] != f.born or not child.active:
			continue
		var age := _now - float(f.born)
		var position := _position(s, parent, age)
		var died := age >= s.lives[parent]
		if f.on == "death":
			if died:
				# A death's burst is whole whatever the frame's budget: nothing would give it later.
				for k in mini(_bursts(child.definition.bursts, f.bursts_fired, 0.0), child.definition.max):
					_emit(child, Transform3D(child.frame.basis, position), Vector3.ZERO, 0.0, s, parent, f.inherit)
			else:
				kept.append(f)
			continue
		var cd := child.definition
		var t: float = f.time + delta
		f.time = t
		if died or (not cd.loop and t > cd.duration):
			# Births a frame's budget put off are still owed once their parent is gone.
			for k in mini(int(f.pending), cd.max):
				_emit(child, Transform3D(child.frame.basis, position), Vector3.ZERO, 1.0, s, parent, f.inherit)
			continue
		var cycle := fmod(t, cd.duration) if cd.loop else t
		var u: float = cycle / cd.duration
		f.pending = minf(f.pending + _value(cd.rate, u, randf()) * delta + _value(cd.distance, u, randf()) * position.distance_to(f.last) + _bursts(cd.bursts, f.bursts_fired, cycle), cd.max)
		f.last = position
		f.pending -= _emit_up_to(int(f.pending), func() -> void: _emit(child, Transform3D(child.frame.basis, position), Vector3.ZERO, u, s, parent, f.inherit))
		kept.append(f)
	s.following = kept


## Calls `emit` up to `count` times, while this frame's births have time left: how many it called.
func _emit_up_to(count: int, emit: Callable) -> int:
	var made := 0
	if count > 0 and _births_from < 0:
		_births_from = Time.get_ticks_usec()
	while made < count and not Budget.over(_births_from, Budget.PARTICLE_BIRTHS_US):
		emit.call()
		made += 1
	return made


## Writes one particle of `s` born now from the emitter at `frame` moving at `velocity` (world), `u` through its
## system's cycle; a sub-emitter's particle takes the properties `inherit` names from slot `parent` of `from`. Dropped
## where no slot near the next is free, as a full system emits none.
func _emit(s: System, frame: Transform3D, velocity: Vector3, u: float, from: System, parent: int, inherit: Array = []) -> void:
	if s.births.is_empty():
		return
	var i := -1
	for k in mini(SLOT_SEARCH, s.births.size()):
		var at := (s.slot + k) % s.births.size()
		if s.births[at] == UNBORN or _now - s.births[at] >= s.lives[at]:
			i = at
			break
	if i < 0:
		return
	s.slot = (i + 1) % s.births.size()
	var d := s.definition
	var shape := _shape(d.shape)
	var place: Transform3D = d.shape.matrix
	var at: Vector3 = frame * (place * shape[0])
	var heading: Vector3 = frame.basis * (place.basis * shape[1]).normalized() * _value(d.speed, u, randf())
	if d.has("inherit"):
		heading += velocity * _value(d.inherit, u, randf())
	var life := maxf(_value(d.lifetime, u, randf()), 1e-3)
	var size := _axes(d.size, u, true)
	var rotation := _axes(d.rotation, u, false)
	var colour: Color = _at(d.color.min, u).lerp(_at(d.color.max, u), randf())
	if from != null:
		if "color" in inherit:
			colour *= from.colours[parent]
		if "size" in inherit:
			size *= from.sizes[parent]
		if "rotation" in inherit:
			rotation += from.rotations[parent]
		if "lifetime" in inherit:
			life *= from.lives[parent]
	if not d.world:
		var back := s.frame.affine_inverse()
		at = back * at
		heading = back.basis * heading
	var seed := randf()
	s.births[i] = _now
	s.lives[i] = life
	s.gravities[i] = _value(d.gravity, u, randf())
	s.starts[i] = at
	s.velocities[i] = heading
	s.sizes[i] = size
	s.rotations[i] = rotation
	s.colours[i] = colour
	s.alive_until = maxf(s.alive_until, _now + life)
	if s.multimesh != null:
		s.multimesh.set_instance_transform(i, Transform3D(Basis(at, heading, size), rotation))
		s.multimesh.set_instance_color(i, colour)
		s.multimesh.set_instance_custom_data(i, Color(_now, life, seed, s.gravities[i]))
	for c: Array in s.children:
		var child: System = c[0]
		if child.active:
			var fired := PackedInt32Array()
			fired.resize((child.definition.bursts as Array).size())
			s.following.append({"child": child, "on": c[1], "inherit": c[2], "parent": i, "born": s.births[i], "time": 0.0, "pending": 0.0, "bursts_fired": fired, "last": _position(s, i, 0.0)})


## Where slot `i` of `s` is in the world `age` seconds after its birth, by the shader's closed form without its
## velocity curves and noise.
func _position(s: System, i: int, age: float) -> Vector3:
	var start := s.starts[i]
	var heading := s.velocities[i]
	var d := s.definition
	var down := GRAVITY if d.world else s.frame.basis.inverse() * GRAVITY
	var moved := heading * age
	var damping := _damping(d)
	if damping > 0.0:
		var limit := _value(d.limit.speed, 0.0, 0.5)
		if heading.length() > limit:
			var held := heading / heading.length() * limit
			moved = held * age + (heading - held) * (1.0 - exp(-damping * age)) / damping
	var at := start + moved + 0.5 * down * s.gravities[i] * age * age
	return at if d.world else s.frame * at


## How fast speed past a system's limit falls away, per second, or 0 for a system without one.
static func _damping(d: Dictionary) -> float:
	return -log(maxf(1.0 - d.limit.dampen, 1e-3)) * DAMPEN_RATE if d.has("limit") else 0.0


## A point in a shape and the way a particle leaves it, in the shape's own axes, which Unity's shapes face along +Z.
static func _shape(shape: Dictionary) -> Array:
	var r: float = shape.radius
	var inward := func() -> float: return 1.0 - shape.thickness * randf()
	var at := Vector3.ZERO
	var heading := Vector3.BACK
	match shape.type:
		"sphere", "hemisphere":
			heading = _unit()
			if shape.type == "hemisphere":
				heading.z = absf(heading.z)
			at = heading * r * inward.call()
		"cone":
			var turn: float = randf() * shape.arc
			var out := sqrt(float(inward.call()))
			var tilt: float = shape.angle * out
			heading = Vector3(cos(turn) * sin(tilt), sin(turn) * sin(tilt), cos(tilt))
			at = Vector3(cos(turn), sin(turn), 0.0) * r * out + heading * shape.length * randf()
		"box":
			at = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
		"circle":
			var turn: float = randf() * shape.arc
			heading = Vector3(cos(turn), sin(turn), 0.0)
			at = heading * r * sqrt(float(inward.call()))
		"edge":
			at = Vector3((randf() * 2.0 - 1.0) * r, 0.0, 0.0)
			heading = Vector3.UP
	if shape.randomDirection > 0.0:
		heading = heading.lerp(_unit(), shape.randomDirection)
	if shape.spherical > 0.0 and at.length() > 0.0:
		heading = heading.lerp(at.normalized(), shape.spherical)
	if shape.randomPosition > 0.0:
		at += _unit() * shape.randomPosition * randf()
	return [at, heading if heading.length() > 1e-6 else Vector3.BACK]


static func _unit() -> Vector3:
	var z := randf() * 2.0 - 1.0
	var turn := randf() * TAU
	var across := sqrt(1.0 - z * z)
	return Vector3(across * cos(turn), across * sin(turn), z)


## A curve's value at share `u` of its span for a particle whose random for it is `k`.
static func _value(c: Dictionary, u: float, k: float) -> float:
	return lerpf(c.scale[0] * _at(c.min, u), c.scale[1] * _at(c.max, u), k)


## Samples spaced evenly over a span, read linearly between neighbours at share `u` of it: floats or colours.
static func _at(samples: Variant, u: float) -> Variant:
	if samples.size() == 1:
		return samples[0]
	var x: float = clampf(u, 0.0, 1.0) * (samples.size() - 1)
	var i := mini(int(x), samples.size() - 2)
	return lerp(samples[i], samples[i + 1], x - i)


## A start size or rotation: one curve for all three axes of a size and Z alone of a rotation, or one per axis, each
## axis with its own random unless one curve sizes all three alike.
static func _axes(curves: Array, u: float, size: bool) -> Vector3:
	if curves.size() == 1:
		var v := _value(curves[0], u, randf())
		return Vector3(v, v, v) if size else Vector3(0, 0, v)
	return Vector3(_value(curves[0], u, randf()), _value(curves[1], u, randf()), _value(curves[2], u, randf()))


## The life curves of system `d` as particle.gdshaderinc reads them: CURVE_SAMPLES wide, ROWS high.
static func _curves(d: Dictionary) -> Image:
	var img := Image.create_empty(CURVE_SAMPLES, ROWS, false, Image.FORMAT_RGBAF)
	var put := func(row: int, values: Callable) -> void:
		for end in 2:
			for x in CURVE_SAMPLES:
				img.set_pixel(x, row + end, values.call(end, float(x) / (CURVE_SAMPLES - 1)))
	var ends := ["min", "max"]
	var one := func(c: Dictionary, end: int, u: float) -> float: return c.scale[end] * _at(c[ends[end]], u)
	var three := func(curves: Array, end: int, u: float) -> Vector3:
		if curves.size() == 1:
			var v: float = one.call(curves[0], end, u)
			return Vector3(v, v, v)
		return Vector3(one.call(curves[0], end, u), one.call(curves[1], end, u), one.call(curves[2], end, u))
	var rgb := func(v: Vector3) -> Color: return Color(v.x, v.y, v.z)
	put.call(ROW_COLOUR, func(end: int, u: float) -> Color: return _at(d.colorOverLife[ends[end]], u) if d.has("colorOverLife") else Color.WHITE)
	put.call(ROW_SIZE, func(end: int, u: float) -> Color: return rgb.call(three.call(d.sizeOverLife, end, u) if d.has("sizeOverLife") else Vector3.ONE))
	var velocity := func(end: int, u: float) -> Vector3:
		return Vector3(one.call(d.velocity.x, end, u), one.call(d.velocity.y, end, u), one.call(d.velocity.z, end, u)) if d.has("velocity") else Vector3.ZERO
	put.call(ROW_VELOCITY, func(end: int, u: float) -> Color: return rgb.call(velocity.call(end, u)))
	put.call(ROW_PATH, func(end: int, u: float) -> Color: return rgb.call(_integral(func(t: float) -> Vector3: return velocity.call(end, t), u)))
	var spin := func(end: int, u: float) -> Vector3:
		if not d.has("spin"):
			return Vector3.ZERO
		return Vector3(0, 0, one.call(d.spin[0], end, u)) if (d.spin as Array).size() == 1 else three.call(d.spin, end, u)
	put.call(ROW_SPIN_PATH, func(end: int, u: float) -> Color: return rgb.call(_integral(func(t: float) -> Vector3: return spin.call(end, t), u)))
	put.call(ROW_NOISE_LIMIT, func(end: int, u: float) -> Color: return Color(one.call(d.noise.strength, end, u) if d.has("noise") else 0.0, one.call(d.limit.speed, end, u) if d.has("limit") else 0.0, 0.0))
	put.call(ROW_COLOUR_BY_SPEED, func(end: int, u: float) -> Color: return _at(d.colorBySpeed.color[ends[end]], u) if d.has("colorBySpeed") else Color.WHITE)
	put.call(ROW_SIZE_BY_SPEED, func(end: int, u: float) -> Color:
		var v: float = one.call(d.sizeBySpeed.size, end, u) if d.has("sizeBySpeed") else 1.0
		return Color(v, v, v))
	return img


## The integral of `f` over [0, u], by the trapezoid rule on four steps a curve sample.
static func _integral(f: Callable, u: float) -> Vector3:
	var steps := maxi(roundi(u * (CURVE_SAMPLES - 1) * 4), 1)
	var h := u / steps
	var sum := Vector3.ZERO
	for k in steps:
		sum += 0.5 * h * ((f.call(k * h) as Vector3) + (f.call((k + 1) * h) as Vector3))
	return sum
