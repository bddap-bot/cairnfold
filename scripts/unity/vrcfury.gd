extends RefCounted

## The VRCFury features on an avatar, which VRCFury turns into menu controls, parameters and FX layers at upload, added
## to its expressions as that build would add them: each Toggle and each FullController's FX controller, menus and
## parameters in hierarchy order, then each MoveMenuItem and SetIcon. Features that add nothing a menu shows are
## passed over; what is not translated is counted.

const Yaml = preload("res://../scripts/unity/yaml.gd")
const Expressions = preload("res://../scripts/unity/expressions.gd")
const Prefabs = preload("res://../scripts/unity/prefabs.gd")

## Features that add nothing to the menu, its parameters or its layers: they rig, optimize or check the avatar.
const MENULESS := ["ArmatureLink", "BlendShapeLink", "BlendshapeOptimizer", "FixWriteDefaults", "ApplyDuringUpload", "UnlimitedParameters", "MmdCompatibility", "SpsOptions", "Slot4Fix", "DirectTreeOptimizer", "AnchorOverrideFix", "BoundingBoxFix"]
## Parameters VRChat drives, which VRCFury never renames.
const BUILT_IN := ["IsLocal", "Viseme", "Voice", "GestureLeft", "GestureRight", "GestureLeftWeight", "GestureRightWeight", "AngularY", "VelocityX", "VelocityY", "VelocityZ", "VelocityMagnitude", "Upright", "Grounded", "Seated", "AFK", "TrackingType", "VRMode", "MuteSelf", "InStation", "Earmuffs", "IsOnFriendsList", "AvatarVersion", "IsAnimatorEnabled", "ScaleModified", "ScaleFactor", "ScaleFactorInverse", "EyeHeightAsMeters", "EyeHeightAsPercent"]
## The most controls a VRChat menu shows; VRCFury pages the rest into a "Next" submenu.
const MENU_SLOTS := 8
## The Unity class ID of a clip curve on one of the controller's own parameters, which the merge renames with it.
const ANIMATOR := "95"
## Toggle settings that change behaviour this translation does not reproduce.
const TOGGLE_UNTRANSLATED := ["separateLocal", "hasTransition", "invertRestLogic", "exclusiveOffState", "securityEnabled"]


## Adds the features of the avatar under `paths` (each transform under it by its clip path, parents first) to `ex`.
static func apply(ex: Expressions, objs: Dictionary, paths: Dictionary) -> void:
	var path_of := {}
	var order := {}
	for p: String in paths:
		path_of[paths[p]] = p
		if not _editor_only(objs, paths[p]):
			order[Yaml.file_id(objs[paths[p]].data.get("m_GameObject"))] = [order.size(), paths[p]]
	var components := []
	# A component added to a prefab instance's object is not in that object's component list; it names its object.
	for id: int in objs:
		var d: Dictionary = objs[id].data
		if objs[id].type == "MonoBehaviour" and d.get("references") is Dictionary and order.has(Yaml.file_id(d.get("m_GameObject"))):
			components.append(d)
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return order[Yaml.file_id(a.get("m_GameObject"))][0] < order[Yaml.file_id(b.get("m_GameObject"))][0])
	var features := []
	for d: Dictionary in components:
		var refs := {}
		for entry: Variant in Yaml.list((d.references as Dictionary).get("RefIds")):
			if entry is Dictionary:
				refs[str(entry.get("rid", ""))] = entry
		var rids := [str((d.get("content", {}) as Dictionary).get("rid", ""))] if d.get("content") is Dictionary else []
		for f: Variant in Yaml.list((d.get("config", {}) as Dictionary).get("features") if d.get("config") is Dictionary else null):
			if f is Dictionary:
				rids.append(str(f.get("rid", "")))
		for rid: String in rids:
			if refs.has(rid):
				features.append({"index": features.size(), "class": str((refs[rid].get("type", {}) as Dictionary).get("class", "")), "data": refs[rid].get("data", {}), "refs": refs, "at": path_of[order[Yaml.file_id(d.get("m_GameObject"))][1]]})
	if features.is_empty():
		return
	if ex.data.is_empty():
		ex.data = Expressions.empty()
	var own := {}
	for p: Dictionary in ex.data.parameters:
		own[p.name] = true
	var exclusive := {}
	var menu_edits := []
	for f: Dictionary in features:
		match f["class"]:
			"Toggle":
				_toggle(ex, objs, paths, path_of, f, exclusive)
			"FullController":
				_full_controller(ex, objs, paths, f, own)
			"MoveMenuItem", "SetIcon":
				menu_edits.append(f)
			var other:
				if not other in MENULESS:
					ex._count("VRCFury %s" % other)
	for tag: String in exclusive:
		var members: Array = exclusive[tag]
		for m: Array in members:
			for other: Array in members:
				if other[0] != m[0]:
					(m[1] as Array).append(_driver(other[0], 0.0))
	for f: Dictionary in menu_edits:
		if f["class"] == "MoveMenuItem":
			_move(ex.data.menu, str(f.data.get("fromPath", "")).split("/", false), str(f.data.get("toPath", "")).split("/", false))
		else:
			var control: Variant = _find(ex.data.menu, str(f.data.get("path", "")).split("/", false))
			if control is Dictionary:
				control.icon = _object_guid(f.data.get("icon"))
	_paged(ex.data.menu)


static func _paged(menu: Array) -> void:
	if menu.size() > MENU_SLOTS:
		var rest := menu.slice(MENU_SLOTS - 1)
		menu.resize(MENU_SLOTS - 1)
		menu.append(_folder("Next", rest))
	for c: Dictionary in menu:
		if c.type == "submenu":
			_paged(c.controls)


## A Toggle as VRCFury builds it: its parameter, a layer whose on state holds its actions (as a clip, and drivers for
## the FX parameters it sets) and whose off state undoes them, or for a slider one blend from off to on, and unless it
## adds no menu item a control at its path.
static func _toggle(ex: Expressions, objs: Dictionary, paths: Dictionary, path_of: Dictionary, f: Dictionary, exclusive: Dictionary) -> void:
	var d: Dictionary = f.data
	var name := str(d.get("name", ""))
	var segments := name.split("/", false)
	for setting: String in TOGGLE_UNTRANSLATED:
		if str(d.get(setting, "0")) == "1":
			ex._count("VRCFury Toggle %s" % setting)
	var slider := str(d.get("slider", "0")) == "1"
	var parameter := str(d.get("globalParam", "")) if str(d.get("useGlobalParam", "0")) == "1" and str(d.get("globalParam", "")) != "" else "VF%d_%s" % [f.index, name]
	var default := Expressions._float(d.get("defaultSliderValue")) if slider else (1.0 if str(d.get("defaultOn", "0")) == "1" else 0.0)
	if not ex.data.parameters.any(func(p: Dictionary) -> bool: return p.name == parameter):
		ex.data.parameters.append({"name": parameter, "type": "float" if slider else "bool", "default": default, "saved": str(d.get("saved", "0")) == "1"})
	var on := {"length": 0.0, "loop": false, "curves": []}
	var off := {"length": 0.0, "loop": false, "curves": []}
	var on_drivers := []
	var off_drivers := []
	for a: Variant in Yaml.list((d.get("state", {}) as Dictionary).get("actions") if d.get("state") is Dictionary else null):
		var entry: Dictionary = f.refs.get(str((a as Dictionary).get("rid", "")) if a is Dictionary else "", {})
		_action(ex, objs, paths, path_of, f.at, str((entry.get("type", {}) as Dictionary).get("class", "")), entry.get("data", {}), on, off, on_drivers, off_drivers, default != 0.0)
	var clip := func(c: Dictionary) -> Dictionary:
		ex.data.clips.append(c)
		return {"clip": ex.data.clips.size() - 1}
	var layer := {"weight": 1.0, "any": [], "entry": [], "default": 0}
	if slider:
		var child := func(motion: Dictionary, threshold: float) -> Dictionary: return {"motion": motion, "threshold": threshold, "parameter": "", "speed": 1.0, "offset": 0.0, "position": [0.0, 0.0]}
		layer.states = [{"name": name, "speed": 1.0, "writeDefaults": true, "transitions": [], "drivers": [], "motion": {"blend": "1d", "parameters": [parameter, ""], "children": [child.call(clip.call(off), 0.0), child.call(clip.call(on), 1.0)]}}]
	else:
		layer.states = [
			{"name": "off", "speed": 1.0, "writeDefaults": true, "drivers": off_drivers, "motion": clip.call(off), "transitions": [{"to": 1, "conditions": [{"parameter": parameter, "mode": "if", "threshold": 0.0}]}]},
			{"name": "on", "speed": 1.0, "writeDefaults": true, "drivers": on_drivers, "motion": clip.call(on), "transitions": [{"to": 0, "conditions": [{"parameter": parameter, "mode": "ifNot", "threshold": 0.0}]}]}]
		if str(d.get("enableExclusiveTag", "0")) == "1":
			for tag: String in str(d.get("exclusiveTag", "")).split(",", false):
				(exclusive.get_or_add(tag.strip_edges(), []) as Array).append([parameter, on_drivers])
	ex.data.layers.append(layer)
	if segments.is_empty() or str(d.get("addMenuItem", "1")) == "0":
		return
	var type := "radial" if slider else "button" if str(d.get("holdButton", "0")) == "1" else "toggle"
	_submenu(ex.data.menu, segments.slice(0, segments.size() - 1)).append({"name": segments[segments.size() - 1], "type": type, "parameter": "" if slider else parameter, "value": 1.0, "axes": [parameter] if slider else [], "icon": _object_guid(d.get("icon")) if str(d.get("enableIcon", "0")) == "1" else ""})


## One Toggle action as curves of its on clip (and its off clip where the off state is not the scene's), and drivers on
## entering on and off, as VRCFury animates it; an object it turns rests as the toggle starts.
static func _action(ex: Expressions, objs: Dictionary, paths: Dictionary, path_of: Dictionary, at: String, type: String, a: Dictionary, on: Dictionary, off: Dictionary, on_drivers: Array, off_drivers: Array, starts_on: bool) -> void:
	var constant := func(clip: Dictionary, path: String, attribute: String, cls: String, value: float) -> void:
		clip.curves.append({"path": path, "attribute": attribute, "class": cls, "script": "", "keys": [[0.0, value, 0.0, 0.0]]})
	match type:
		"ObjectToggleAction":
			var go := Yaml.file_id(a.get("obj"))
			var t := Prefabs.transform_of(objs, go)
			if not path_of.has(t):
				ex._count("VRCFury action on an object outside the avatar")
				return
			var mode := str(a.get("mode", "0")).to_int()
			var shown := Yaml.on(objs[go].data, "m_IsActive")
			var value := 0.0 if mode == 1 or (mode == 2 and shown) else 1.0
			constant.call(on, path_of[t], "m_IsActive", "1", value)
			# Turning an object on or off sets it the other way while off; a flip leaves it as the scene has it.
			if mode != 2:
				constant.call(off, path_of[t], "m_IsActive", "1", 1.0 - value)
			# VRCFury leaves the avatar resting as its toggle starts.
			objs[go].data.m_IsActive = str(int(value if starts_on else (1.0 - value if mode != 2 else float(shown))))
		"BlendShapeAction":
			var renderers := _renderers(objs, path_of) if str(a.get("allRenderers", "0")) == "1" else [Yaml.file_id(a.get("renderer"))]
			for r: int in renderers:
				var p: Variant = _renderer_path(objs, path_of, r)
				if p != null:
					constant.call(on, p[0], "blendShape." + str(a.get("blendShape", "")), p[1], Expressions._float(a.get("blendShapeValue"), 100.0))
		"MaterialPropertyAction":
			var renderers := _renderers(objs, path_of) if str(a.get("affectAllMeshes", "0")) == "1" else [Yaml.file_id(a.get("renderer")), Yaml.file_id(a.get("renderer2"))]
			var property := str(a.get("propertyName", ""))
			var values := {}
			match str(a.get("propertyType", "0")):
				"1":
					for k: String in "rgba":
						values[property + "." + k] = Expressions._float((a.get("valueColor", {}) as Dictionary).get(k))
				"2", "3":
					for k: String in "xyzw":
						values[property + "." + k] = Expressions._float((a.get("valueVector", {}) as Dictionary).get(k))
				_:
					values[property] = Expressions._float(a.get("value"))
			for r: int in renderers:
				var p: Variant = _renderer_path(objs, path_of, r)
				if p != null:
					for v: String in values:
						constant.call(on, p[0], "material." + v, p[1], values[v])
		"MaterialAction":
			var renderer := Yaml.file_id(a.get("renderer"))
			if renderer == 0:
				renderer = Prefabs.renderer_of(objs, Yaml.file_id(a.get("obj")))
			var p: Variant = _renderer_path(objs, path_of, renderer)
			var guid := _object_guid(a.get("mat"))
			if p == null or guid == "":
				ex._count("VRCFury material swap outside the avatar")
				return
			on.curves.append({"path": p[0], "attribute": "m_Materials.Array.data[%d]" % str(a.get("materialIndex", "0")).to_int(), "class": p[1], "refs": [[0.0, guid]]})
		"ScaleAction":
			var t := Prefabs.transform_of(objs, Yaml.file_id(a.get("obj")))
			if not path_of.has(t):
				ex._count("VRCFury action on an object outside the avatar")
				return
			var by := Expressions._float(a.get("scale"), 1.0)
			var rest: Variant = objs[t].data.get("m_LocalScale")
			for k: String in "xyz":
				constant.call(on, path_of[t], "m_LocalScale." + k, "4", by * (Expressions._float((rest as Dictionary).get(k), 1.0) if rest is Dictionary else 1.0))
		"AnimationClipAction":
			var ref: Variant = (a.get("clip", {}) as Dictionary).get("objRef") if a.get("clip") is Dictionary else null
			var source: Variant = _own_clip(ex, ref)
			if source == null:
				ex._count("VRCFury clip not in the package")
				return
			for c: Dictionary in source.curves:
				var moved := c.duplicate()
				moved.path = _resolve(paths, at, c.path)
				on.curves.append(moved)
			on.length = maxf(on.length, source.length)
			on.loop = on.loop or source.loop
		"FxFloatAction":
			var n := str(a.get("name", ""))
			var rest: Array = ex.data.parameters.filter(func(p: Dictionary) -> bool: return p.name == n)
			on_drivers.append(_driver(n, Expressions._float(a.get("value"), 1.0)))
			off_drivers.append(_driver(n, float(rest[0].default) if not rest.is_empty() else 0.0))
		_:
			ex._count("VRCFury %s" % type)


## A clip read for this use alone, outside the expressions' clips and their cache, or null.
static func _own_clip(ex: Expressions, ref: Variant) -> Variant:
	var cache := ex._clips
	var count: int = ex.data.clips.size()
	ex._clips = {}
	var motion := ex._motion("", ref, 0)
	ex._clips = cache
	var out: Variant = ex.data.clips[motion.clip] if motion.has("clip") else null
	ex.data.clips.resize(count)
	return out


static func _driver(parameter: String, value: float) -> Dictionary:
	return {"parameter": parameter, "drive": "set", "value": value, "min": 0.0, "max": 1.0, "chance": 1.0, "source": ""}


## A FullController merged as VRCFury merges one: its FX layers with clips of their own, bindings resolved from its
## object, its parameters renamed apart from every other's (but the global ones, VRChat's own and those the avatar's own
## expression parameters name, which it shares) on its layers, its clips and the contacts under its object, and its
## menus under their prefixes.
static func _full_controller(ex: Expressions, objs: Dictionary, paths: Dictionary, f: Dictionary, own: Dictionary) -> void:
	var d: Dictionary = f.data
	var rewrites := Yaml.list(d.get("rewriteBindings"))
	var lists := []
	for p: Variant in Yaml.list(d.get("prms")):
		if p is Dictionary:
			lists.append(_object_guid(p.get("parameters")))
	var global := {}
	for g: Variant in Yaml.list(d.get("globalParams")):
		global[str(g)] = true
	var nonsynced_global := str(d.get("allNonsyncedAreGlobal", "0")) == "1"
	var synced := {}
	for list: String in lists:
		for p: Variant in Yaml.list(ex._asset(list).get("parameters")):
			if p is Dictionary:
				synced[str(p.get("name", ""))] = Yaml.on(p, "networkSynced")
	var renamed := func(n: String) -> String:
		if n == "" or own.has(n) or (global.has("*") and not global.has("!" + n)) or global.has(n) or n in BUILT_IN or Expressions.BUILT_IN.has(n) or (nonsynced_global and not synced.get(n, false)):
			return n
		return "VF%d_%s" % [f.index, n]
	var layers := []
	for c: Variant in Yaml.list(d.get("controllers")):
		if not c is Dictionary:
			continue
		var guid := _object_guid(c.get("controller"))
		if str(c.get("type", "")) != Expressions.FX:
			ex._count("VRCFury FullController non-FX controller")
			continue
		if not ex.assets.by_guid.has(guid):
			ex._count("VRCFury FullController controller not in the package")
			continue
		var by_name := {}
		for list: String in lists if not lists.is_empty() else [""]:
			var listed := {}
			for p: Variant in Yaml.list(ex._asset(list).get("parameters")):
				if p is Dictionary:
					listed[str(p.get("name", ""))] = true
			for p: Dictionary in ex._parameters(list, guid):
				if not by_name.has(p.name) or listed.has(p.name):
					by_name[p.name] = p
		var parameters: Array = by_name.values()
		for p: Dictionary in parameters:
			var n: String = renamed.call(p.name)
			if not ex.data.parameters.any(func(q: Dictionary) -> bool: return q.name == n):
				var copy := p.duplicate()
				copy.name = n
				ex.data.parameters.append(copy)
		var cache := ex._clips
		ex._clips = {}
		var first: int = ex.data.clips.size()
		layers.append_array(ex._layers(guid))
		ex._clips = cache
		for i in range(first, ex.data.clips.size()):
			var kept := []
			for curve: Dictionary in ex.data.clips[i].curves:
				if curve["class"] == ANIMATOR and curve.path == "":
					curve.attribute = renamed.call(curve.attribute)
					kept.append(curve)
					continue
				var path: Variant = _rewritten(rewrites, curve.path)
				if path != null:
					curve.path = _resolve(paths, f.at, path)
					kept.append(curve)
			ex.data.clips[i].curves = kept
	_rename_layers(layers, renamed)
	ex.data.layers.append_array(layers)
	var top: int = paths.get(f.at, 0)
	for id: int in objs:
		var c: Dictionary = objs[id].data
		if objs[id].type == "MonoBehaviour" and c.has("collisionTags") and c.has("parameter") and Prefabs.ancestors(objs, Prefabs.transform_of(objs, Yaml.file_id(c.get("m_GameObject")))).has(top):
			c.parameter = renamed.call(str(c.get_or_add("unrenamed parameter", c.parameter)))
	for m: Variant in Yaml.list(d.get("menus")):
		if not m is Dictionary:
			continue
		var guid := _object_guid(m.get("menu"))
		if not ex.assets.by_guid.has(guid):
			ex._count("VRCFury FullController menu not in the package")
			continue
		var controls := ex._menu(guid, 0)
		_rename_menu(controls, renamed)
		_merge(_submenu(ex.data.menu, str(m.get("prefix", "")).split("/", false)), controls)


static func _rename_layers(layers: Array, renamed: Callable) -> void:
	var motion := func(m: Dictionary, recurse: Callable) -> void:
		if m.has("time"):
			m.time = renamed.call(m.time)
		if m.has("parameters"):
			m.parameters = (m.parameters as Array).map(renamed)
		for c: Dictionary in m.get("children", []):
			c.parameter = renamed.call(c.parameter)
			recurse.call(c.motion, recurse)
	for layer: Dictionary in layers:
		var transitions: Array = layer.entry + layer.any
		for s: Dictionary in layer.states:
			transitions.append_array(s.transitions)
			motion.call(s.get("motion", {}), motion)
			for driver: Dictionary in s.drivers:
				driver.parameter = renamed.call(driver.parameter)
				driver.source = renamed.call(driver.source)
		for t: Dictionary in transitions:
			for c: Dictionary in t.conditions:
				c.parameter = renamed.call(c.parameter)


static func _rename_menu(controls: Array, renamed: Callable) -> void:
	for c: Dictionary in controls:
		c.parameter = renamed.call(c.parameter)
		c.axes = (c.axes as Array).map(renamed)
		_rename_menu(c.get("controls", []), renamed)


## A FullController binding path after its rewrites, null when one deletes it.
static func _rewritten(rewrites: Array, path: String) -> Variant:
	for r: Variant in rewrites:
		if not r is Dictionary:
			continue
		var from := str(r.get("from", ""))
		if from == "" or path == from or path.begins_with(from + "/"):
			if str(r.get("delete", "0")) == "1":
				return null
			var to := str(r.get("to", ""))
			path = (to + path.substr(from.length())).trim_prefix("/") if from != "" else (to + "/" + path).trim_prefix("/")
	return path


## A path a feature names from its own object, as VRCFury resolves it: below that object if it is there, otherwise
## from the avatar's root.
static func _resolve(paths: Dictionary, base: String, path: String) -> String:
	var below := (base + "/" + path).trim_prefix("/") if path != "" else base
	return below if base != "" and paths.has(below) else path


## A submenu `name` holding `controls`.
static func _folder(name: String, controls: Array) -> Dictionary:
	return {"name": name, "type": "submenu", "parameter": "", "value": 1.0, "axes": [], "icon": "", "controls": controls}


## The controls of the submenu at `segments` under `menu`, each missing submenu made.
static func _submenu(menu: Array, segments: Array) -> Array:
	var at := menu
	for s: String in segments:
		var found: Variant = null
		for c: Dictionary in at:
			if c.type == "submenu" and c.name == s:
				found = c
				break
		if found == null:
			found = _folder(s, [])
			at.append(found)
		at = found.controls
	return at


## Adds `controls` to `menu`, a submenu joining the one of its name already there, as VRCFury merges menus.
static func _merge(menu: Array, controls: Array) -> void:
	for c: Dictionary in controls:
		if c.type == "submenu":
			_merge(_submenu(menu, [c.name]), c.controls)
		else:
			menu.append(c)


static func _find(menu: Array, segments: Array) -> Variant:
	if segments.is_empty():
		return null
	for c: Dictionary in menu:
		if c.name == segments[0]:
			return c if segments.size() == 1 else _find(c.get("controls", []), segments.slice(1))
	return null


static func _move(menu: Array, from: Array, to: Array) -> void:
	if from.is_empty() or to.is_empty():
		return
	var parent: Variant = menu if from.size() == 1 else _find(menu, from.slice(0, from.size() - 1))
	var siblings: Array = parent if parent is Array else (parent.get("controls", []) if parent is Dictionary else [])
	for i in siblings.size():
		if siblings[i].name == from[from.size() - 1]:
			var control: Dictionary = siblings[i]
			siblings.remove_at(i)
			control.name = to[to.size() - 1]
			_merge(_submenu(menu, to.slice(0, to.size() - 1)), [control])
			return


static func _renderers(objs: Dictionary, path_of: Dictionary) -> Array:
	var out := []
	for t: int in path_of:
		var r := Prefabs.renderer_of(objs, Yaml.file_id(objs[t].data.get("m_GameObject")))
		if r != 0:
			out.append(r)
	return out


## [clip path, class] of a renderer in the avatar, or null.
static func _renderer_path(objs: Dictionary, path_of: Dictionary, renderer: int) -> Variant:
	if not objs.has(renderer) or not Prefabs.RENDERERS.has(objs[renderer].type):
		return null
	var t := Prefabs.transform_of(objs, Yaml.file_id(objs[renderer].data.get("m_GameObject")))
	return [path_of[t], Prefabs.RENDERERS[objs[renderer].type]] if path_of.has(t) else null


static func _editor_only(objs: Dictionary, t: int) -> bool:
	for at: int in Prefabs.ancestors(objs, t):
		if Prefabs.editor_only(objs, Yaml.file_id(objs[at].data.get("m_GameObject"))):
			return true
	return false


## The asset GUID a VRCFury GuidWrapper (a material, clip, controller, menu or texture field) names.
static func _object_guid(wrapper: Variant) -> String:
	if not wrapper is Dictionary:
		return ""
	var guid := Yaml.guid(wrapper.get("objRef"))
	return guid if guid != "" else str(wrapper.get("id", "")).get_slice("|", 0)
