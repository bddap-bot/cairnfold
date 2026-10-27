extends RefCounted

## A VRChat avatar descriptor's Expressions Menu, Expression Parameters and FX controller, read as data: the menu tree,
## the parameters, and the controller's layers with their states, transitions, blend trees and parameter drivers. Its
## clips stay as Unity binds them, each curve by the GameObject path, attribute and class it animates; the importer
## decides what each binds to in the model.

const Yaml = preload("res://../scripts/unity/yaml.gd")
const Assets = preload("res://../scripts/unity/assets.gd")

const CONTROLS := {"101": "button", "102": "toggle", "103": "submenu", "201": "twoAxis", "202": "fourAxis", "203": "radial"}
const VALUE_TYPES := ["int", "float", "bool"]
const ANIMATOR_TYPES := {"1": "float", "3": "int", "4": "bool", "9": "bool"}
const CONDITIONS := {"1": "if", "2": "ifNot", "3": "greater", "4": "less", "6": "equals", "7": "notEqual"}
const DRIVES := ["set", "add", "random", "copy"]
const FX := "5"
## Parameters VRChat sets for the wearer itself, as an avatar worn in VR with head and hands tracked sees them at rest.
const BUILT_IN := {"IsLocal": 1.0, "VRMode": 1.0, "TrackingType": 3.0, "Grounded": 1.0, "Upright": 1.0}
const MAX_MENU_DEPTH := 8

var assets: Assets
## "menu" (the root menu's controls), "parameters", "layers", "clips" (each {"length", "loop", "curves"}); empty
## without a descriptor menu or FX controller.
var data := {}
## What was met and not translated, by kind, with how many of each.
var dropped := {}
var _documents := {}
var _clips := {}


func _init(from: Assets, descriptor: Dictionary) -> void:
	assets = from
	if str(descriptor.get("customExpressions", "0")) != "1":
		return
	var menu := _guid(descriptor.get("expressionsMenu"))
	var controller := ""
	for layer: Variant in _list(descriptor.get("baseAnimationLayers")):
		if layer is Dictionary and str(layer.get("type", "")) == FX and str(layer.get("isDefault", "1")) != "1":
			controller = _guid(layer.get("animatorController"))
	if not assets.by_guid.has(menu) or not assets.by_guid.has(controller):
		return
	var parameters := _parameters(_guid(descriptor.get("expressionParameters")), controller)
	data = {"menu": _menu(menu, 0), "parameters": parameters, "layers": [], "clips": []}
	data.layers = _layers(controller, parameters)


func _count(kind: String) -> void:
	dropped[kind] = dropped.get(kind, 0) + 1


static func _list(v: Variant) -> Array:
	return v if v is Array else []


static func _guid(ref: Variant) -> String:
	return str((ref as Dictionary).get("guid", "")) if ref is Dictionary else ""


static func _id(ref: Variant) -> int:
	return str((ref as Dictionary).get("fileID", "0")).to_int() if ref is Dictionary else 0


static func _float(v: Variant, otherwise := 0.0) -> float:
	return str(v).to_float() if v != null and str(v).is_valid_float() else otherwise


## The asset's objects by file ID, read once.
func _objects(guid: String) -> Dictionary:
	if not _documents.has(guid):
		_documents[guid] = Yaml.objects(assets.text(guid))
	return _documents[guid]


## The first MonoBehaviour's fields in a ScriptableObject asset such as a menu or parameter list.
func _asset(guid: String) -> Dictionary:
	for o: Dictionary in _objects(guid).values():
		if o.type == "MonoBehaviour":
			return o.data
	return {}


## The controls of a menu: {"name", "type", "parameter", "value", "icon" (a texture GUID or ""), "controls" (a
## submenu's), "axes" (a puppet's or radial's parameters)}.
func _menu(guid: String, depth: int) -> Array:
	var out := []
	for c: Variant in _list(_asset(guid).get("controls")):
		if not c is Dictionary:
			continue
		var type: String = CONTROLS.get(str(c.get("type", "")), "")
		if type == "":
			_count("menu control of type %s" % c.get("type", ""))
			continue
		var control := {"name": str(c.get("name", "")), "type": type, "parameter": str((c.get("parameter", {}) as Dictionary).get("name", "")) if c.get("parameter") is Dictionary else "", "value": _float(c.get("value"), 1.0), "icon": _guid(c.get("icon"))}
		control.axes = _list(c.get("subParameters")).map(func(p: Variant) -> String: return str((p as Dictionary).get("name", "")) if p is Dictionary else "")
		if type == "submenu":
			var sub := _guid(c.get("subMenu"))
			if not assets.by_guid.has(sub) or depth >= MAX_MENU_DEPTH:
				_count("submenu not in the package")
				continue
			control.controls = _menu(sub, depth + 1)
		out.append(control)
	return out


## Every parameter the menu or controller names: {"name", "type", "default", "saved"}, the expression parameters'
## defaults over the controller's, built-in ones at BUILT_IN.
func _parameters(list: String, controller: String) -> Array:
	var out := {}
	for o: Dictionary in _objects(controller).values():
		if o.type != "AnimatorController":
			continue
		for p: Variant in _list(o.data.get("m_AnimatorParameters")):
			var name := str(p.get("m_Name", ""))
			var type: String = ANIMATOR_TYPES.get(str(p.get("m_Type", "")), "float")
			var value := _float(p.get("m_DefaultFloat")) if type == "float" else _float(p.get("m_DefaultInt")) if type == "int" else _float(p.get("m_DefaultBool"))
			out[name] = {"name": name, "type": type, "default": BUILT_IN.get(name, value), "saved": false}
	for p: Variant in _list(_asset(list).get("parameters")):
		if not p is Dictionary or str(p.get("name", "")) == "":
			continue
		var name := str(p.name)
		out[name] = {"name": name, "type": VALUE_TYPES[clampi(str(p.get("valueType", "0")).to_int(), 0, 2)], "default": _float(p.get("defaultValue")), "saved": str(p.get("saved", "1")) == "1"}
	return out.values()


## The controller's layers: {"weight", "default" state, "entry" and "any" transitions, "states"}, sub-state machines
## flattened into their layer's states.
func _layers(guid: String, parameters: Array) -> Array:
	var objs := _objects(guid)
	var out := []
	for o: Dictionary in objs.values():
		if o.type != "AnimatorController":
			continue
		var first := true
		for l: Variant in _list(o.data.get("m_AnimatorLayers")):
			var machine := _id(l.get("m_StateMachine"))
			if str(l.get("m_SyncedLayerIndex", "-1")) != "-1":
				_count("synced layer")
				continue
			if not objs.has(machine):
				continue
			if str(l.get("m_BlendingMode", "0")) != "0":
				_count("additive layer")
			var states := {}
			var machines := {}
			_collect(objs, machine, states, machines)
			var order := states.keys()
			var index := {}
			for i in order.size():
				index[order[i]] = i
			var layer := {"weight": 1.0 if first else _float(l.get("m_DefaultWeight"), 1.0), "states": [], "any": [], "entry": [], "default": index.get(_default(objs, machine), 0)}
			first = false
			for m: int in machines:
				for t: Variant in _list(objs[m].data.get("m_AnyStateTransitions")):
					layer.any.append_array(_transition(objs, _id(t), index))
			for t: Variant in _list(objs[machine].data.get("m_EntryTransitions")):
				layer.entry.append_array(_transition(objs, _id(t), index))
			for s: int in order:
				var d: Dictionary = objs[s].data
				var state := {"name": str(d.get("m_Name", "")), "speed": _float(d.get("m_Speed"), 1.0), "writeDefaults": str(d.get("m_WriteDefaultValues", "1")) == "1", "transitions": [], "drivers": []}
				var motion := _motion(guid, d.get("m_Motion"), 0)
				if not motion.is_empty():
					state.motion = motion
				if str(d.get("m_TimeParameterActive", "0")) == "1" and motion.has("clip"):
					state.motion.time = str(d.get("m_TimeParameter", ""))
				if str(d.get("m_SpeedParameterActive", "0")) == "1":
					_count("state speed parameter")
				for t: Variant in _list(d.get("m_Transitions")):
					state.transitions.append_array(_transition(objs, _id(t), index))
				for b: Variant in _list(d.get("m_StateMachineBehaviours")):
					state.drivers.append_array(_drivers(objs.get(_id(b), {}).get("data", {})))
				layer.states.append(state)
			out.append(layer)
	return out


## The states of a state machine and its sub-state machines, by file ID, and the machines themselves.
static func _collect(objs: Dictionary, machine: int, states: Dictionary, machines: Dictionary) -> void:
	if machines.has(machine) or not objs.has(machine):
		return
	machines[machine] = true
	for c: Variant in _list(objs[machine].data.get("m_ChildStates")):
		var s := _id((c as Dictionary).get("m_State"))
		if objs.has(s):
			states[s] = true
	for c: Variant in _list(objs[machine].data.get("m_ChildStateMachines")):
		_collect(objs, _id((c as Dictionary).get("m_StateMachine")), states, machines)


## A state machine's default state, through the default of a sub-state machine it names.
static func _default(objs: Dictionary, machine: int) -> int:
	var d := _id(objs[machine].data.get("m_DefaultState"))
	return d


## A transition as {"to" (a state index, -1 for the layer's exit), "conditions", "exitTime" (absent without one)}: a
## transition into a sub-state machine goes to its default state. Empty for a muted transition or one to nowhere.
func _transition(objs: Dictionary, id: int, index: Dictionary) -> Array:
	if not objs.has(id):
		return []
	var d: Dictionary = objs[id].data
	if str(d.get("m_Mute", "0")) == "1":
		return []
	var to := -1
	if str(d.get("m_IsExit", "0")) != "1":
		var target := _id(d.get("m_DstState"))
		if not index.has(target) and objs.has(_id(d.get("m_DstStateMachine"))):
			target = _default(objs, _id(d.get("m_DstStateMachine")))
		if not index.has(target):
			return []
		to = index[target]
	var conditions := []
	for c: Variant in _list(d.get("m_Conditions")):
		var mode: String = CONDITIONS.get(str(c.get("m_ConditionMode", "")), "")
		if mode == "":
			_count("transition condition mode %s" % c.get("m_ConditionMode", ""))
			continue
		conditions.append({"parameter": str(c.get("m_ConditionEvent", "")), "mode": mode, "threshold": _float(c.get("m_EventTreshold"))})
	var out := {"to": to, "conditions": conditions}
	if str(d.get("m_HasExitTime", "0")) == "1":
		out.exitTime = _float(d.get("m_ExitTime"), 1.0)
	if str(d.get("m_CanTransitionToSelf", "1")) != "1":
		out.notToSelf = true
	return [out]


## A VRChat parameter driver's entries: {"parameter", "drive", "value", "min", "max", "chance", "source"}.
func _drivers(d: Dictionary) -> Array:
	if not d.has("parameters") or not d.has("localOnly"):
		if d.has("playable") or d.has("layer"):
			_count("animator layer or tracking control")
		return []
	var out := []
	for p: Variant in _list(d.get("parameters")):
		var drive: int = clampi(str(p.get("type", "0")).to_int(), 0, 3)
		out.append({"parameter": str(p.get("name", "")), "drive": DRIVES[drive], "value": _float(p.get("value")), "min": _float(p.get("valueMin")), "max": _float(p.get("valueMax"), 1.0), "chance": _float(p.get("chance"), 1.0), "source": str(p.get("source", ""))})
	return out


## A state's motion: {"clip": index into data.clips}, or a blend tree {"blend": "1d"|"2d"|"direct", "parameters",
## "children": [{"motion", "threshold" or "position" or "parameter"}]}; empty for none.
func _motion(document: String, ref: Variant, depth: int) -> Dictionary:
	var guid := _guid(ref)
	if guid == "":
		guid = document
	var id := _id(ref)
	if id == 0 or depth > 8:
		return {}
	var objs := _objects(guid)
	if not objs.has(id):
		for o: Dictionary in objs.values():
			if o.type == "AnimationClip" and id == 7400000:
				return {"clip": _clip(guid, id, o.data)}
		_count("motion not in the package")
		return {}
	var o: Dictionary = objs[id]
	if o.type == "AnimationClip":
		return {"clip": _clip(guid, id, o.data)}
	if o.type != "BlendTree":
		return {}
	var d: Dictionary = o.data
	var type := str(d.get("m_BlendType", "0"))
	var blend: String = {"0": "1d", "1": "2d", "2": "2d", "3": "2d", "4": "direct"}.get(type, "")
	if blend == "":
		return {}
	var tree := {"blend": blend, "parameters": [str(d.get("m_BlendParameter", "")), str(d.get("m_BlendParameterY", ""))], "children": []}
	for c: Variant in _list(d.get("m_Childs")):
		var child := {"motion": _motion(guid, c.get("m_Motion"), depth + 1), "threshold": _float(c.get("m_Threshold")), "parameter": str(c.get("m_DirectBlendParameter", ""))}
		var at: Variant = c.get("m_Position")
		child.position = [_float((at as Dictionary).get("x")), _float((at as Dictionary).get("y"))] if at is Dictionary else [0.0, 0.0]
		tree.children.append(child)
	return tree


## The index in data.clips of a clip: {"length", "loop", "curves": [{"path", "attribute", "class", "keys": [[time,
## value]...]} or, for an object reference curve, "refs": [[time, GUID or ""]...]}]}.
func _clip(guid: String, id: int, d: Dictionary) -> int:
	var key := "%s:%d" % [guid, id]
	if _clips.has(key):
		return _clips[key]
	var curves := []
	for c: Variant in _list(d.get("m_FloatCurves")):
		curves.append({"path": str(c.get("path", "")), "attribute": str(c.get("attribute", "")), "class": str(c.get("classID", "")), "keys": _keys((c.get("curve", {}) as Dictionary).get("m_Curve"), func(v: Variant) -> float: return _float(v))})
	for kind: String in ["m_ScaleCurves", "m_PositionCurves", "m_EulerCurves"]:
		for c: Variant in _list(d.get(kind)):
			var attribute: String = {"m_ScaleCurves": "m_LocalScale", "m_PositionCurves": "m_LocalPosition", "m_EulerCurves": "localEulerAnglesRaw"}[kind]
			for axis: String in ["x", "y", "z"]:
				curves.append({"path": str(c.get("path", "")), "attribute": "%s.%s" % [attribute, axis], "class": "4", "keys": _keys((c.get("curve", {}) as Dictionary).get("m_Curve"), func(v: Variant) -> float: return _float((v as Dictionary).get(axis)) if v is Dictionary else 0.0)})
	if not _list(d.get("m_RotationCurves")).is_empty():
		_count("rotation curve")
	for c: Variant in _list(d.get("m_PPtrCurves")):
		var refs := []
		for k: Variant in _list(c.get("curve")):
			refs.append([_float((k as Dictionary).get("time")), _guid((k as Dictionary).get("value"))])
		curves.append({"path": str(c.get("path", "")), "attribute": str(c.get("attribute", "")), "class": str(c.get("classID", "")), "refs": refs})
	var settings: Dictionary = d.get("m_AnimationClipSettings", {}) if d.get("m_AnimationClipSettings") is Dictionary else {}
	var length := maxf(_float(settings.get("m_StopTime")) - _float(settings.get("m_StartTime")), 0.0)
	_clips[key] = data.clips.size()
	data.clips.append({"length": length, "loop": str(settings.get("m_LoopTime", "0")) == "1", "curves": curves})
	return _clips[key]


static func _keys(list: Variant, value: Callable) -> Array:
	var out := []
	for k: Variant in _list(list):
		if k is Dictionary:
			out.append([_float(k.get("time")), value.call(k.get("value"))])
	return out
