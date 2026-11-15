class_name ExpressionState
extends RefCounted

## The imported FX controller and its expression parameters.
var data: Dictionary
var values := {}
var definitions := {}
var outputs: Array[float] = []
var states: Array[int] = []
var elapsed: Array[float] = []
## Each layer's say over the targets. A motionless state writing defaults says nothing; one writing none repeats the
## layer's last motion, plus every other target as kept then if that motion's state wrote no defaults either.
var _layer_values: Array[Dictionary] = []
var _holding: Array[bool] = []
## The first weighted layer playing a motion without write defaults, or -1. It gives a target no layer up to it wrote
## this frame `_kept` by its weight over the default, as Unity does (tests/unity/write-defaults.json).
var _holder := -1
## Each target's value when a layer last wrote it; returning to its default leaves it.
var _kept: Array[float] = []
## Targets whose kept value moved under the holder, rebuilt next advance: a part-weight holder fades them over frames.
var _refeed := {}
var pulses := {}
var _animated_parameters: Array[int] = []
## Per target, the indices of the layers that may animate it, in layer order.
var _writers: Array[Array] = []
## Per layer, per state: whether its motion samples the same at every time, and whether re-entering it replays the last
## re-entry (a self-transition re-enters every frame its conditions hold, as Unity's any state does).
var _timeless: Array[Array] = []
var _repeats: Array[Array] = []
## A settled layer took no transition since a parameter it reads changed; until one does or it reaches `_until` (its
## next exit time, normalized) it would sample as it did, so it is passed over.
var _settled: Array[bool] = []
var _until: Array[float] = []
var _reenter: Array[bool] = []
var _speed: Array[float] = []
var _lengths: Array[float] = []
## Parameter name -> indices of the layers that read it.
var _readers := {}
var _rebuild := false
## The targets whose outputs advancing changed since a player last bound them.
var moved := {}
var opened: Array[Dictionary] = []
var revision := 0
const EXIT := -2
const SINGLE_STEP := 1.0 / 8388608.0


func _init(definition: Dictionary) -> void:
	data = definition if ExpressionDefinition.valid(definition) else {}
	for p: Dictionary in data.get("parameters", []):
		definitions[p.name] = p
		put(p.name, p.get("default", 0.0))
	for t: Dictionary in data.get("targets", []):
		outputs.append(float(t.get("default", 0.0)))
		_kept.append(outputs[-1])
		_writers.append([])
		if t.effect is Dictionary and t.effect.has("parameter") and definitions.has(t.effect.parameter):
			_animated_parameters.append(outputs.size() - 1)
	for layer: Dictionary in data.get("layers", []):
		var i := states.size()
		states.append(-1)
		elapsed.append(0.0)
		_layer_values.append({})
		_holding.append(false)
		_settled.append(layer.states.is_empty())
		_until.append(INF)
		_reenter.append(false)
		_speed.append(0.0)
		_lengths.append(0.0)
		var targets := {}
		var timeless := []
		var repeats := []
		for state: Dictionary in layer.states:
			_targets(state.get("motion", {}), targets)
			timeless.append(_timeless_motion(state.get("motion", {})))
			repeats.append(timeless[-1] and (state.get("drivers", []) as Array).is_empty() and (layer.get("any", []) + state.get("transitions", [])).all(func(t: Dictionary) -> bool: return not t.has("exitTime")))
		_timeless.append(timeless)
		_repeats.append(repeats)
		# A state with no motion that writes no defaults may repeat every target.
		var all: bool = layer.states.any(func(state: Dictionary) -> bool: return not state.has("motion") and not state.get("writeDefaults", true))
		for t in _writers.size() if all else targets.keys():
			_writers[t].append(i)
		var reads := {}
		_reads(layer, reads)
		for key: String in reads:
			(_readers.get_or_add(key, []) as Array).append(i)


func put(key: String, value: float) -> void:
	if not definitions.has(key) or not is_finite(value):
		return
	_write(key, _typed(key, value))


func _write(key: String, value: float) -> void:
	if values.get(key) != value:
		values[key] = value
		revision += 1
		for i: int in _readers.get(key, []):
			_settled[i] = false


func saved() -> Dictionary:
	var out := {}
	for key: String in definitions:
		if definitions[key].get("saved", false):
			out[key] = values[key]
	return out


## Resets the layers too, so each re-enters reading the saved values even if it first entered before they were read.
func restore(saved_values: Dictionary) -> void:
	pulses.clear()
	for key: String in definitions:
		put(key, definitions[key].get("default", 0.0))
	for key: String in saved_values:
		if definitions.get(key, {}).get("saved", false) and (saved_values[key] is float or saved_values[key] is int):
			put(key, saved_values[key])
	states.fill(-1)
	elapsed.fill(0.0)
	_speed.fill(0.0)
	for i in _layer_values.size():
		_layer_values[i] = {}
		_holding[i] = false
		_settled[i] = (data.layers[i].states as Array).is_empty()
	for t in _kept.size():
		_kept[t] = float(data.targets[t].get("default", 0.0))
	_refeed.clear()
	_holder = -1
	_rebuild = true


func reset() -> void:
	close()
	pulses.clear()
	for key: String in definitions:
		put(key, definitions[key].get("default", 0.0))


func active(control: Dictionary) -> bool:
	return control.get("parameter", "") != "" and is_equal_approx(values.get(control.parameter, 0.0), _typed(control.parameter, float(control.get("value", 1.0))))


func activate(control: Dictionary) -> void:
	var key: String = control.get("parameter", "")
	var value: float = control.get("value", 1.0)
	match control.type:
		"toggle": put(key, 0.0 if active(control) else value)
		"button":
			put(key, value)
			pulses[key] = 1.0
		_:
			opened.append(control)
			put(key, value)


func back() -> bool:
	if opened.is_empty():
		return false
	put(opened.pop_back().get("parameter", ""), 0.0)
	return true


func controls() -> Array:
	for c in range(opened.size() - 1, -1, -1):
		if opened[c].type == "submenu":
			return opened[c].controls
	return data.get("menu", [])


func turning() -> Dictionary:
	return opened.back() if not opened.is_empty() and opened.back().type != "submenu" else {}


func close() -> void:
	while not opened.is_empty():
		back()


func puppet(control: Dictionary, stick: Vector2, radial: float) -> void:
	var axes: Array = control.get("axes", [])
	var v: Array = [clampf(radial, 0.0, 1.0)]
	if control.type == "twoAxis":
		v = [stick.x, stick.y]
	elif control.type == "fourAxis":
		v = [maxf(stick.y, 0), maxf(stick.x, 0), maxf(-stick.y, 0), maxf(-stick.x, 0)]
	for i in mini(axes.size(), v.size()):
		put(axes[i], v[i])


func advance(delta: float) -> void:
	for key: String in pulses.keys():
		pulses[key] -= delta
		if pulses[key] <= 0.0:
			put(key, 0.0)
			pulses.erase(key)
	var changed := _refeed
	_refeed = {}
	if _rebuild:
		_rebuild = false
		for t in outputs.size():
			changed[t] = true
	for i in states.size():
		elapsed[i] += delta * _speed[i]
		if _settled[i] and (elapsed[i] / _lengths[i] if _lengths[i] > 0 else elapsed[i]) < _until[i]:
			if _reenter[i]:
				elapsed[i] = 0.0
			continue
		var layer: Dictionary = data.layers[i]
		if layer.states.is_empty():
			continue
		if states[i] < 0:
			_enter(i, _entered(layer))
			elapsed[i] = delta * _speed[i]
		var state: Dictionary = layer.states[states[i]]
		var normalized := elapsed[i] / _lengths[i] if _lengths[i] > 0 else elapsed[i]
		var next := _transition(layer.get("any", []), states[i], normalized)
		if next == -1:
			next = _transition(state.get("transitions", []), states[i], normalized)
		if next == EXIT:
			next = _entered(layer)
		var again: bool = next == states[i] and _repeats[i][next]
		if next >= 0:
			_enter(i, next)
			state = layer.states[states[i]]
		_settled[i] = again or (next < 0 and _timeless[i][states[i]])
		_reenter[i] = again
		_until[i] = INF
		if next < 0:
			for transitions: Array in [layer.get("any", []), state.get("transitions", [])]:
				for t: Dictionary in transitions:
					if t.has("exitTime") and normalized < t.exitTime:
						_until[i] = minf(_until[i], t.exitTime)
		var said := _layer_values[i]
		if state.has("motion"):
			var sampled := _motion(state.motion, elapsed[i])
			for t: int in sampled:
				if said.get(t) != sampled[t]:
					changed[t] = true
			for t: int in said:
				if not sampled.has(t):
					changed[t] = true
			_layer_values[i] = sampled
			_holding[i] = not state.get("writeDefaults", true)
		elif state.get("writeDefaults", true):
			for t: int in said:
				changed[t] = true
			_layer_values[i] = {}
			_holding[i] = false
		elif _holding[i]:
			_holding[i] = false
			var all := {}
			for t in outputs.size():
				all[t] = said.get(t, _kept[t])
				changed[t] = true
			_layer_values[i] = all
	var holder := -1
	for i in states.size():
		if _holding[i] and float(data.layers[i].get("weight", 1.0)) > 0.0:
			holder = i
			break
	if holder != _holder:
		_holder = holder
		for t in outputs.size():
			changed[t] = true
	moved.merge(changed)
	for t: int in changed:
		var value := float(data.targets[t].get("default", 0.0))
		var held := lerpf(value, _kept[t], float(data.layers[holder].get("weight", 1.0))) if holder >= 0 else value
		var written := false
		for i: int in _writers[t]:
			var weight := float(data.layers[i].get("weight", 1.0))
			if weight <= 0.0 or not _layer_values[i].has(t):
				continue
			if not written and i > holder:
				value = held
			value = lerpf(value, _layer_values[i][t], weight)
			written = true
		if not written and holder >= 0:
			value = held
			written = true
		outputs[t] = value
		if written and _kept[t] != value:
			_kept[t] = value
			if holder >= 0:
				_refeed[t] = true
	# The animator writes a parameter its clips animate every frame, past the menu's range, so a driver or the menu
	# setting it holds only until the next.
	for t: int in _animated_parameters:
		var key: String = data.targets[t].effect.parameter
		_write(key, outputs[t] if definitions[key].type == "float" else roundf(outputs[t]))
	for i in opened.size():
		var c := opened[i]
		if c.get("parameter", "") != "" and not active(c):
			while opened.size() > i:
				back()
			break


func _enter(layer: int, state: int) -> void:
	states[layer] = state
	elapsed[layer] = 0.0
	var motion: Dictionary = data.layers[layer].states[state].get("motion", {})
	_speed[layer] = float(data.layers[layer].states[state].get("speed", 1.0))
	_lengths[layer] = _length(motion)
	for d: Dictionary in data.layers[layer].states[state].get("drivers", []):
		var v: float = d.get("value", 0.0)
		match d.get("drive", "set"):
			"add": v += values.get(d.parameter, 0.0)
			"copy": v = values.get(d.get("source", ""), 0.0)
			"random":
				var type: String = definitions.get(d.parameter, {}).get("type", "float")
				v = float(randf() < d.get("chance", 1.0)) if type == "bool" else float(randi_range(int(d.get("min", 0)), int(d.get("max", 1)))) if type == "int" else randf_range(d.get("min", 0.0), d.get("max", 1.0))
		put(d.parameter, v)


## EXIT for a transition to the state machine's exit, -1 for none; `time` is normalized.
func _transition(transitions: Array, current: int, time: float) -> int:
	for t: Dictionary in transitions:
		if (t.get("notToSelf", false) and t.to == current) or (t.has("exitTime") and time < t.exitTime):
			continue
		var holds := true
		for c: Dictionary in t.get("conditions", []):
			if not _condition(c):
				holds = false
				break
		if holds:
			return EXIT if t.to < 0 else int(t.to)
	return -1


func _entered(layer: Dictionary) -> int:
	var entry := _transition((layer.get("entry", []) as Array).filter(func(t: Dictionary) -> bool: return t.to >= 0), -1, 0.0)
	return entry if entry >= 0 else int(layer.get("default", 0))


func _condition(c: Dictionary) -> bool:
	var v: float = values.get(c.parameter, 0.0)
	var threshold: float = c.get("threshold", 0.0)
	match c.mode:
		"if": return v != 0.0
		"ifNot": return v == 0.0
		"greater": return v > threshold
		"less": return v < threshold
		"equals": return is_equal_approx(v, threshold)
		"notEqual": return not is_equal_approx(v, threshold)
	return false


func _length(motion: Dictionary) -> float:
	if motion.has("clip"):
		return float(data.clips[int(motion.clip)].get("length", 0.0))
	var length := 0.0
	for child: Dictionary in motion.get("children", []):
		length = maxf(length, _length(child.motion))
	return length


func _motion(motion: Dictionary, time: float) -> Dictionary:
	var out := {}
	if motion.has("clip"):
		var clip: Dictionary = data.clips[int(motion.clip)]
		var length: float = clip.get("length", 0.0)
		if motion.has("time"):
			time = values.get(motion.time, 0.0) * length
		elif clip.get("loop", false) and length > 0:
			time = fposmod(time, length)
		for c: Dictionary in clip.get("curves", []):
			if not (c.keys as Array).is_empty():
				out[int(c.target)] = sample(c.keys, time, c.get("step", false))
		return out
	var children: Array = motion.get("children", [])
	var weights: Array[float] = []
	weights.resize(children.size())
	weights.fill(0.0)
	var parameters: Array = motion.get("parameters", [])
	var point := Vector2(values.get(parameters[0], 0.0), values.get(parameters[1], 0.0)) if parameters.size() >= 2 else Vector2.ZERO
	match motion.get("blend", ""):
		"direct":
			for i in children.size():
				weights[i] = maxf(0.0, values.get(children[i].parameter, 0.0))
		"1d":
			var order := range(children.size())
			order.sort_custom(func(a: int, b: int) -> bool: return children[a].threshold < children[b].threshold)
			if not order.is_empty():
				weights[order[0]] = 1.0
				for k in range(1, order.size()):
					var a: int = order[k - 1]
					var b: int = order[k]
					if point.x >= float(children[b].threshold):
						weights[a] = 0.0
						weights[b] = 1.0
					elif point.x > float(children[a].threshold):
						weights[b] = inverse_lerp(float(children[a].threshold), float(children[b].threshold), point.x)
						weights[a] = 1.0 - weights[b]
						break
		"2d":
			for i in children.size():
				var a := Vector2(children[i].position[0], children[i].position[1])
				weights[i] = 1.0
				for j in children.size():
					var b := Vector2(children[j].position[0], children[j].position[1]) - a
					if i != j and b.length_squared() > 0.0:
						weights[i] = minf(weights[i], clampf(1.0 - (point - a).dot(b) / b.length_squared(), 0.0, 1.0))
	var total: float = weights.reduce(func(a: float, b: float) -> float: return a + b, 0.0)
	# Unity sums a direct tree's children unless it normalizes its blend values.
	var divisor := total if total > 0.0 and (motion.get("blend") != "direct" or motion.get("normalized", false)) else 1.0
	var blended: bool = motion.get("blend", "") in ["1d", "2d"]
	var share := 0.0
	var keyed := {}
	for i in children.size():
		if weights[i] <= 0.0:
			continue
		var child: Dictionary = children[i]
		var sample_values := _motion(child.motion, time * float(child.get("speed", 1.0)) + float(child.get("offset", 0.0)) * _length(child.motion))
		var w := weights[i] / divisor
		share += w
		for t: int in sample_values:
			out[t] = out.get(t, 0.0) + sample_values[t] * w
			keyed[t] = keyed.get(t, 0.0) + w
	# Unity blends a 1D or 2D tree from rest, yet a target only children at no weight animate is left to the layers below.
	if blended:
		for t: int in keyed:
			out[t] += float(data.targets[t].get("default", 0.0)) * (share - keyed[t])
	return out


## Unity's AnimationCurve.Evaluate. Equal keys with flat facing slopes hold exactly: the Bezier drifts an ulp from frame
## to frame and a layer resting there would not settle. Unity keeps times in single precision, so a time short of a key
## by under SINGLE_STEP (2^-23) of it is at it: a quarter of a four-frame motion-time clip lands on its second key.
static func sample(keys: Array, time: float, stepped: bool) -> float:
	var after := keys.size()
	for i in keys.size():
		var key := float(keys[i][0])
		if time < key - absf(key) * SINGLE_STEP:
			after = i
			break
	if after == 0:
		return float(keys[0][1])
	if after == keys.size():
		return float(keys[-1][1])
	var a: Array = keys[after - 1]
	var b: Array = keys[after]
	var span := float(b[0]) - float(a[0])
	if stepped or span <= 0.0:
		return float(a[1])
	var p := (time - float(a[0])) / span
	if a.size() < 4 or b.size() < 4:
		return lerpf(float(a[1]), float(b[1]), p)
	if a[3] == null or b[2] == null or (float(a[1]) == float(b[1]) and float(a[3]) == 0.0 and float(b[2]) == 0.0):
		return float(a[1])
	var wa := clampf(float(a[5]), 0.0, 1.0) if a.size() == 6 else 1.0 / 3.0
	var wb := clampf(float(b[4]), 0.0, 1.0) if b.size() == 6 else 1.0 / 3.0
	var low := 0.0
	var high := 1.0
	for _i in 32:
		var mid := 0.5 * (low + high)
		if _bezier(mid, 0.0, wa, 1.0 - wb, 1.0) < p:
			low = mid
		else:
			high = mid
	return _bezier(0.5 * (low + high), float(a[1]), float(a[1]) + wa * span * float(a[3]), float(b[1]) - wb * span * float(b[2]), float(b[1]))


static func _bezier(s: float, p0: float, p1: float, p2: float, p3: float) -> float:
	var r := 1.0 - s
	return r * r * r * p0 + 3.0 * r * r * s * p1 + 3.0 * r * s * s * p2 + s * s * s * p3


## A motion with "time" is played by that parameter, not the clock.
func _timeless_motion(motion: Dictionary) -> bool:
	if motion.has("clip"):
		return motion.has("time") or (data.clips[int(motion.clip)].get("curves", []) as Array).all(func(c: Dictionary) -> bool: return _flat(c.keys))
	return (motion.get("children", []) as Array).all(func(child: Dictionary) -> bool: return _timeless_motion(child.motion))


## Keys as ExpressionDefinition._key checks them.
static func _flat(keys: Array) -> bool:
	return keys.all(func(k: Array) -> bool: return float(k[1]) == float(keys[0][1]) and (k.size() < 4 or ((k[2] == null or float(k[2]) == 0.0) and (k[3] == null or float(k[3]) == 0.0))))


func _targets(motion: Dictionary, targets: Dictionary) -> void:
	if motion.has("clip"):
		for curve: Dictionary in data.clips[int(motion.clip)].get("curves", []):
			targets[int(curve.target)] = true
	for child: Dictionary in motion.get("children", []):
		_targets(child.motion, targets)


## Drivers are skipped: they read only as a state is entered, which a settled layer does not.
static func _reads(of: Variant, reads: Dictionary) -> void:
	if of is Dictionary:
		for key: String in of:
			var v: Variant = of[key]
			if key == "drivers":
				continue
			if v is String and key in ["parameter", "time"]:
				reads[v] = true
			elif key == "parameters" and v is Array:
				for p: Variant in v:
					reads[str(p)] = true
			else:
				_reads(v, reads)
	elif of is Array:
		for v: Variant in of:
			_reads(v, reads)


func _typed(key: String, value: float) -> float:
	match definitions.get(key, {}).get("type", "float"):
		"bool": return 1.0 if value != 0.0 else 0.0
		"int": return clampf(int(value), 0, 255)
	return clampf(value, -1.0, 1.0)
