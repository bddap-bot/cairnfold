class_name ExpressionState
extends RefCounted

## The imported FX controller and its expression parameters, independent of rendering and input.
var data: Dictionary
var values := {}
var definitions := {}
var outputs: Array[float] = []
var states: Array[int] = []
var elapsed: Array[float] = []
var _layer_values: Array[Dictionary] = []
var _layer_targets: Array[Dictionary] = []
var pulses := {}
var opened: Array[Dictionary] = []
var revision := 0


func _init(definition: Dictionary) -> void:
	data = definition
	for p: Dictionary in data.get("parameters", []):
		definitions[p.name] = p
		put(p.name, p.get("default", 0.0))
	for t: Dictionary in data.get("targets", []):
		outputs.append(float(t.get("default", 0.0)))
	for layer: Dictionary in data.get("layers", []):
		states.append(-1)
		elapsed.append(0.0)
		_layer_values.append({})
		var targets := {}
		for state: Dictionary in layer.states:
			_targets(state.get("motion", {}), targets)
		_layer_targets.append(targets)


func put(key: String, value: float) -> void:
	if not definitions.has(key) or not is_finite(value):
		return
	value = _typed(key, value)
	if values.get(key) != value:
		values[key] = value
		revision += 1


func saved() -> Dictionary:
	var out := {}
	for key: String in definitions:
		if definitions[key].get("saved", false):
			out[key] = values[key]
	return out


func restore(saved_values: Dictionary) -> void:
	for key: String in saved_values:
		if definitions.has(key) and definitions[key].get("saved", false) and (saved_values[key] is float or saved_values[key] is int):
			put(key, saved_values[key])


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


func back() -> void:
	if not opened.is_empty():
		put(opened.pop_back().get("parameter", ""), 0.0)


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
	for i in states.size():
		var layer: Dictionary = data.layers[i]
		if layer.states.is_empty():
			continue
		if states[i] < 0:
			var entry := _transition(layer.get("entry", []), -1, 0.0)
			_enter(i, entry if entry >= 0 else int(layer.get("default", 0)))
		var state: Dictionary = layer.states[states[i]]
		elapsed[i] += delta * float(state.get("speed", 1.0))
		var length := _length(state.get("motion", {}))
		var normalized := elapsed[i] / length if length > 0 else elapsed[i]
		var next := _transition(layer.get("any", []) + state.get("transitions", []), states[i], normalized)
		if next >= 0:
			_enter(i, next)
			state = layer.states[states[i]]
		var sampled := _motion(state.get("motion", {}), elapsed[i])
		for t: int in _layer_targets[i]:
			if sampled.has(t) or state.get("writeDefaults", true):
				_layer_values[i][t] = sampled.get(t, float(data.targets[t].get("default", 0.0)))
	for t in outputs.size():
		outputs[t] = float(data.targets[t].get("default", 0.0))
	for i in states.size():
		for t: int in _layer_values[i]:
			outputs[t] = lerpf(outputs[t], _layer_values[i][t], float(data.layers[i].get("weight", 1.0)))
	for i in opened.size():
		var c := opened[i]
		if c.get("parameter", "") != "" and not active(c):
			while opened.size() > i:
				back()
			break


func _enter(layer: int, state: int) -> void:
	states[layer] = state
	elapsed[layer] = 0.0
	for d: Dictionary in data.layers[layer].states[state].get("drivers", []):
		var v: float = d.get("value", 0.0)
		match d.get("drive", "set"):
			"add": v += values.get(d.parameter, 0.0)
			"copy": v = values.get(d.get("source", ""), 0.0)
			"random":
				var type: String = definitions.get(d.parameter, {}).get("type", "float")
				v = float(randf() < d.get("chance", 1.0)) if type == "bool" else float(randi_range(int(d.get("min", 0)), int(d.get("max", 1)))) if type == "int" else randf_range(d.get("min", 0.0), d.get("max", 1.0))
		put(d.parameter, v)


func _transition(transitions: Array, current: int, time: float) -> int:
	for t: Dictionary in transitions:
		if t.to < 0 or (t.get("notToSelf", false) and t.to == current) or (t.has("exitTime") and time < t.exitTime):
			continue
		if (t.get("conditions", []) as Array).all(_condition):
			return int(t.to)
	return -1


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
	for i in children.size():
		if weights[i] <= 0.0:
			continue
		var child: Dictionary = children[i]
		var sample_values := _motion(child.motion, time * float(child.get("speed", 1.0)) + float(child.get("offset", 0.0)) * _length(child.motion))
		for t: int in sample_values:
			out[t] = out.get(t, 0.0) + sample_values[t] * weights[i] / maxf(total, 1.0)
	return out


static func sample(keys: Array, time: float, stepped: bool) -> float:
	for i in range(1, keys.size()):
		if time < float(keys[i][0]):
			return float(keys[i - 1][1]) if stepped else lerpf(float(keys[i - 1][1]), float(keys[i][1]), clampf(inverse_lerp(float(keys[i - 1][0]), float(keys[i][0]), time), 0.0, 1.0))
	return float(keys[-1][1])


func _targets(motion: Dictionary, targets: Dictionary) -> void:
	if motion.has("clip"):
		for curve: Dictionary in data.clips[int(motion.clip)].get("curves", []):
			targets[int(curve.target)] = true
	for child: Dictionary in motion.get("children", []):
		_targets(child.motion, targets)


func _typed(key: String, value: float) -> float:
	match definitions.get(key, {}).get("type", "float"):
		"bool": return 1.0 if value != 0.0 else 0.0
		"int": return clampf(int(value), 0, 255)
	return clampf(value, -1.0, 1.0)
