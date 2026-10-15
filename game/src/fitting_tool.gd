class_name FittingTool
extends Node3D

## Windows and decorations, for whichever hand holds them. With windows, the trigger on a wall opens a
## window where the hand points, or a door where that is near the ground; one beside another on its course
## fuses with it into a wider opening, and the trigger on one closes it. With decorations, what the hand
## points at decides what goes there: a chimney on a house's roof, a flag on a tower's roof or a wall's top,
## a lantern on a wall's face or a fence; the trigger on one takes it away. The lanterns nearest the head
## cast real light; the rest glow.
##
## While held, a ghost of the fitting rides the hand's ray: set on the wall where a press would place it,
## faint and hanging in the air where it would not, and a press there shakes it and bumps the hand. The
## masonry it can go on glows meanwhile (the stone shader's `fitting_glow`).

const TINT := Color(1.0, 0.93, 0.78, 0.6)
## A press this near a placed fitting takes it away.
const TAKE_REACH := 0.6
const LIGHTS := 3
const LIGHT_EVERY := 0.25
## A ghost with nowhere to go hangs this high over the ground the hand points at, or this far along the
## ray where that ground is far or missing.
const HANG_OVER := 1.0
const HANG := 2.5
const SHAKE := 0.35
const GLOW_FADE := 0.3

var rig: Rig
var walls: WallTool
var world: World
var _buttons: Array[Buttons] = []
## Per hand: each fitting's ghost by ToolModels.FITTING_PARTS key, and how long since a refused press.
var _ghosts: Array[Dictionary] = []
var _shaken: Array[float] = []
## Fitting lists sent and not yet back, by wall id and key, so a quick second press builds on the first.
var _sent := {}
var _lights: Array[OmniLight3D] = []
var _since_lights := INF
var _glow := 0.0
var _ghost_fits := _ghost_material(Color(1.0, 0.96, 0.88, 0.7), 0.25)
var _ghost_astray := _ghost_material(Color(0.72, 0.76, 0.86, 0.5), 0.0)


func _init(player: Rig, builder: WallTool, garden: World) -> void:
	rig = player
	walls = builder
	world = garden
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))
		var ghosts := {}
		for what in ToolModels.FITTING_PARTS:
			var g := ToolModels.fitting(what)
			g.top_level = true
			g.visible = false
			add_child(g)
			ghosts[what] = g
		_ghosts.append(ghosts)
		_shaken.append(INF)
	for i in LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.4)
		l.light_energy = 1.4
		l.omni_range = 4.5
		l.omni_attenuation = 1.6
		l.shadow_enabled = false
		l.visible = false
		_lights.append(l)
		add_child(l)


func _process(delta: float) -> void:
	var holding := false
	for i in _buttons.size():
		var b := _buttons[i]
		var hand: Hand = b.hand
		var ghost := {}
		if (hand.tool == Hand.Tool.WINDOWS or hand.tool == Hand.Tool.DECORATIONS) and rig.aim_hand != hand and hand.tracked():
			holding = true
			var t := hand.global_transform
			var target := aim(hand.tool, t.origin, -t.basis.z)
			var hit: Variant = target.point if not target.is_empty() else Terrain.raycast(t.origin, -t.basis.z)
			hand.point(hit, TINT)
			if b.pressed("trigger_click") and not walls.busy() and not fit(target):
				_shaken[i] = 0.0
				hand.trigger_haptic_pulse(&"haptic", 0.0, 0.35, 0.05, 0.0)
				hand.trigger_haptic_pulse(&"haptic", 0.0, 0.35, 0.05, 0.12)
			if not hand.picking:
				ghost = ghost_of(hand.tool, target, t.origin, -t.basis.z, hit)
		_show_ghost(i, ghost, delta)
		b.latch()
	var glow := move_toward(_glow, 1.0 if holding else 0.0, delta / GLOW_FADE)
	if glow != _glow:
		_glow = glow
		RenderingServer.global_shader_parameter_set(&"fitting_glow", _glow)
	_since_lights += delta
	if _since_lights >= LIGHT_EVERY:
		place_lights()


## What a press from `origin` along `dir` would do with `tool`: a dictionary naming `what` and where, or empty.
func aim(tool: Hand.Tool, origin: Vector3, dir: Vector3) -> Dictionary:
	var pick := walls.pick_wall(origin, dir)
	var roof := walls.pick_roof(origin, dir)
	var on_roof: bool = not roof.is_empty() and (pick.is_empty() or pick.distance > 0.2 or roof.along < pick.along)
	if tool == Hand.Tool.WINDOWS:
		if on_roof or pick.is_empty() or pick.wall.layout.fence:
			return {}
		return {"what": "window", "wall": pick.wall, "s": pick.s, "y": _height(pick), "point": pick.point}
	if on_roof:
		var w: Wall = roof.wall
		if w.roof.kind == RoofLayout.Kind.CONE:
			return {"what": "tower_flag", "wall": w, "point": roof.point}
		return {"what": "chimney", "wall": w, "at": w.roof.spot_of(roof.point), "point": roof.point}
	if pick.is_empty():
		return {}
	var layout: WallLayout = pick.wall.layout
	var y := _height(pick)
	if not layout.fence and layout.cover != WallLayout.Cover.ROOF and y > layout.height - WallTool.TOP_BAND:
		return {"what": "flag", "wall": pick.wall, "s": pick.s, "point": pick.point}
	var side := signf((origin - pick.point).dot(layout.frame_at(pick.s).tangent.cross(Vector3.UP)))
	return {"what": "lantern", "wall": pick.wall, "s": pick.s, "y": y, "side": side if side != 0.0 else 1.0, "point": pick.point}


static func _height(pick: Dictionary) -> float:
	return pick.point.y - (pick.wall as Wall).layout.point_at(pick.s).y


## Places what `aim` found, or takes away the one already there, as one build command; false where the
## press does nothing.
func fit(target: Dictionary) -> bool:
	var c := change(target)
	if not c.ok:
		return false
	var w: Wall = target.wall
	if target.what == "tower_flag":
		world.submit({"op": "reshape", "id": w.id, "data": {"roof": {"flag": not w.roof.flag}}})
		return true
	var after: Array = c.after
	_sent.get_or_add(w.id, {})[c.key] = after
	var packed: Variant
	match c.key:
		"lanterns":
			packed = PackedVector3Array(after)
		"flags":
			packed = PackedFloat32Array(after)
		_:
			packed = PackedVector2Array(after)
	world.submit({"op": "reshape", "id": w.id, "data": {"roof": {c.key: packed}} if c.on_roof else {c.key: packed}}, func() -> void:
		if _sent.get(w.id, {}).get(c.key) == after:
			_sent[w.id].erase(c.key))
	return true


## What a press on `target` would do: `ok` false where nothing; otherwise the list `key` on the wall (or
## its roof, `on_roof`) becomes `after`, with entry `near` taken out of it, or with `value` added where
## `near` is -1.
func change(target: Dictionary) -> Dictionary:
	if target.is_empty():
		return {"ok": false}
	var w: Wall = target.wall
	var layout := w.layout
	match target.what:
		"window":
			var click := Vector2(target.s, target.y)
			var near := _window_at(layout, click)
			return _change(w, false, "windows", click, near, near >= 0 or layout.window_fits(click))
		"lantern":
			var s: float = layout.nearest_post(target.s) if layout.fence else target.s
			var hang := Vector3(s, target.y, target.side)
			var near := layout.lanterns.find_custom(func(e): return absf(layout.offset(e.x, s)) < TAKE_REACH and (layout.fence or absf(e.y - hang.y) < TAKE_REACH and e.z == hang.z))
			return _change(w, false, "lanterns", hang, near, near >= 0 or layout.lantern_fits(s, hang.y))
		"flag":
			var near := layout.flags.find_custom(func(e): return absf(layout.offset(e, target.s)) < TAKE_REACH)
			return _change(w, false, "flags", target.s, near, near >= 0 or layout.flag_fits(target.s))
		"chimney":
			var spot := w.roof.chimney_spot(target.at)
			var near := w.roof.chimneys.find_custom(func(e): return e.distance_to(spot) < RoofLayout.STACK_WIDTH + 0.3)
			return _change(w, true, "chimneys", spot, near, true)
	return {"ok": true, "near": 0 if w.roof.flag else -1}


## The placed window nearest `click` among those in the opening there, or -1 where there is none.
static func _window_at(layout: WallLayout, click: Vector2) -> int:
	var o := layout.opening_at(click.x, click.y)
	var near := -1
	if o.is_empty():
		return near
	for i in layout.windows.size():
		var e := layout.windows[i]
		if layout.opening_at(e.x, e.y) == o and (near < 0 or absf(layout.offset(e.x, click.x)) < absf(layout.offset(layout.windows[near].x, click.x))):
			near = i
	return near


func _change(w: Wall, on_roof: bool, key: String, value: Variant, near: int, ok: bool) -> Dictionary:
	var host: Object = w.roof if on_roof else w.layout
	var after: Array = _sent.get(w.id, {}).get(key, host.get(key)).duplicate()
	if near >= 0:
		after.remove_at(near)
	elif after.size() >= (Commands.MAX_CHIMNEYS if key == "chimneys" else Commands.MAX_FITTINGS):
		ok = false
	else:
		after.append(value)
	return {"ok": ok, "on_roof": on_roof, "key": key, "after": after, "near": near, "value": value}


## The ghost a hand holding `tool` shows for `target`, pointing from `origin` along `dir` at `hit` (or
## nothing): the fitting `what` at `xform`, `fits` where a press would place it. Where the press would
## take a fitting away it shows none, the fitting itself being there.
func ghost_of(tool: Hand.Tool, target: Dictionary, origin: Vector3, dir: Vector3, hit: Variant) -> Dictionary:
	var c := change(target)
	if c.ok and c.near >= 0:
		return {}
	if target.is_empty():
		var at: Vector3 = hit + Vector3.UP * HANG_OVER if hit != null and origin.distance_to(hit) < HANG * 2.0 else origin + dir * HANG
		return {"what": "window" if tool == Hand.Tool.WINDOWS else "lantern", "xform": _facing(at, -dir), "fits": false}
	var w: Wall = target.wall
	var layout := w.layout
	var what: String = target.what
	var at: Vector3
	var face := Vector3.ZERO
	match what:
		"window":
			var o := layout.opening_for(Vector2(target.s, target.y))
			var f := layout.frame_at(o.s)
			face = f.tangent.cross(Vector3.UP)
			face *= -1.0 if (origin - f.point).dot(face) < 0.0 else 1.0
			what = "door" if o.door else "window"
			at = f.point + Vector3.UP * (0.0 if o.door else (o.sill + o.head) * 0.5) + face * WallLayout.THICKNESS * 0.5
		"lantern":
			if layout.fence:
				what = "post_lantern"
				at = layout.frame_at(c.value.x).point + Vector3.UP * (WallLayout.FENCE_HEIGHT + 0.25)
				face = origin - at
			else:
				var f := layout.frame_at(target.s)
				at = f.point + Vector3.UP * target.y
				face = f.tangent.cross(Vector3.UP) * target.side
		"flag":
			var f := layout.frame_at(target.s)
			at = f.point + Vector3.UP * (layout.height + WallLayout.CAP)
			face = f.tangent.cross(Vector3.UP)
		"chimney":
			var r := w.roof.frame()
			at = r.mid + r.along * c.value.x + r.across * c.value.y + Vector3.UP * w.roof.rise(1.0 - absf(c.value.y) / w.roof.half_span())
			face = r.across
		"tower_flag":
			what = "flag"
			at = w.roof.frame().mid + Vector3.UP * w.roof.pitch
			face = Vector3(1, 0, 0.4).normalized().cross(Vector3.UP)
	return {"what": what, "xform": _facing(at, face), "fits": c.ok}


## Upright at `at`, its face turned toward `face` across the ground.
static func _facing(at: Vector3, face: Vector3) -> Transform3D:
	face.y = 0.0
	face = face.normalized() if face.length() > 0.01 else Vector3.BACK
	return Transform3D(Basis(Vector3.UP.cross(face), Vector3.UP, face), at)


static func _ghost_material(tint: Color, glow: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = tint
	mat.roughness = 0.8
	mat.emission_enabled = glow > 0.0
	mat.emission = Color(1.0, 0.8, 0.5) * glow
	return mat


func _show_ghost(i: int, ghost: Dictionary, delta: float) -> void:
	_shaken[i] += delta
	for what in _ghosts[i]:
		var g: Node3D = _ghosts[i][what]
		var on: bool = ghost.get("what") == what
		if not on:
			g.visible = false
			continue
		var x: Transform3D = ghost.xform
		if _shaken[i] < SHAKE:
			var k := _shaken[i] / SHAKE
			x.origin += x.basis.x * sin(k * TAU * 3.0) * 0.06 * (1.0 - k)
		g.global_transform = x
		var mat := _ghost_fits if ghost.fits else _ghost_astray
		if not g.visible or g.get_meta(&"mat") != mat:
			g.set_meta(&"mat", mat)
			for c in g.get_children():
				if c is Fittings:
					(c as Fittings).ghostly(mat)
				else:
					for m in c.get_children():
						(m as GeometryInstance3D).material_override = mat
		g.visible = true


## Moves the few real lights to the lanterns nearest the head.
func place_lights() -> void:
	_since_lights = 0.0
	var head := rig.head.global_position
	var lamps: Array[Vector3] = []
	for w in walls.walls:
		for f in w.layout.flames:
			lamps.append(f.origin)
	lamps.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(head) < b.distance_squared_to(head))
	for i in LIGHTS:
		_lights[i].visible = i < lamps.size()
		if i < lamps.size():
			_lights[i].global_position = lamps[i]
