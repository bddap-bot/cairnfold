class_name FittingTool
extends Node3D

## Windows and decorations, for whichever hand holds them. With windows, the trigger on a wall opens a
## window where the hand points, or a door where that is near the ground; one beside another on its course
## fuses with it into a wider opening, and the trigger on one closes it. With decorations, what the hand
## points at decides what goes there: a chimney on a house's roof, a flag on a tower's roof or a wall's top,
## a lantern on a wall's face or a fence; the trigger on one takes it away. The lanterns nearest the head
## cast real light; the rest glow.

const TINT := Color(1.0, 0.93, 0.78, 0.6)
## A press this near a placed fitting takes it away.
const TAKE_REACH := 0.6
const LIGHTS := 3
const LIGHT_EVERY := 0.25

var rig: Rig
var walls: WallTool
var world: World
var _buttons: Array[Buttons] = []
## Fitting lists sent and not yet back, by wall id and key, so a quick second press builds on the first.
var _sent := {}
var _lights: Array[OmniLight3D] = []
var _since_lights := INF


func _init(player: Rig, builder: WallTool, garden: World) -> void:
	rig = player
	walls = builder
	world = garden
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["trigger_click"]))
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
	for b in _buttons:
		var hand: Hand = b.hand
		if (hand.tool == Hand.Tool.WINDOWS or hand.tool == Hand.Tool.DECORATIONS) and rig.aim_hand != hand and hand.get_has_tracking_data():
			var t := hand.global_transform
			var target := aim(hand.tool, t.origin, -t.basis.z)
			hand.point(target.point if not target.is_empty() else Terrain.raycast(t.origin, -t.basis.z), TINT)
			if b.pressed("trigger_click") and not target.is_empty() and not walls.busy():
				fit(target)
		b.latch()
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


## Places what `aim` found, or takes away the one already there, as one build command.
func fit(target: Dictionary) -> void:
	var w: Wall = target.wall
	var layout := w.layout
	match target.what:
		"window":
			var click := Vector2(target.s, target.y)
			var near := _window_at(layout, click)
			_edit(w, false, "windows", click, near, near >= 0 or layout.window_fits(click))
		"lantern":
			var s: float = layout.nearest_post(target.s) if layout.fence else target.s
			var hang := Vector3(s, target.y, target.side)
			var near := layout.lanterns.find_custom(func(e): return absf(layout.offset(e.x, s)) < TAKE_REACH and (layout.fence or absf(e.y - hang.y) < TAKE_REACH and e.z == hang.z))
			_edit(w, false, "lanterns", hang, near, near >= 0 or layout.lantern_fits(s, hang.y))
		"flag":
			var near := layout.flags.find_custom(func(e): return absf(layout.offset(e, target.s)) < TAKE_REACH)
			_edit(w, false, "flags", target.s, near, near >= 0 or layout.flag_fits(target.s))
		"chimney":
			var spot := w.roof.chimney_spot(target.at)
			var near := w.roof.chimneys.find_custom(func(e): return e.distance_to(spot) < RoofLayout.STACK_WIDTH + 0.3)
			_edit(w, true, "chimneys", spot, near, true)
		"tower_flag":
			world.submit({"op": "reshape", "id": w.id, "data": {"roof": {"flag": not w.roof.flag}}})


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


## Takes entry `near` out of the list `key`, or adds `value` if `near` is -1; nothing happens unless `ok`.
func _edit(w: Wall, on_roof: bool, key: String, value: Variant, near: int, ok: bool) -> void:
	if not ok:
		return
	var host: Object = w.roof if on_roof else w.layout
	var after: Array = _sent.get(w.id, {}).get(key, host.get(key)).duplicate()
	if near >= 0:
		after.remove_at(near)
	elif after.size() >= (Commands.MAX_CHIMNEYS if key == "chimneys" else Commands.MAX_FITTINGS):
		return
	else:
		after.append(value)
	_sent.get_or_add(w.id, {})[key] = after
	var packed: Variant
	match key:
		"lanterns":
			packed = PackedVector3Array(after)
		"flags":
			packed = PackedFloat32Array(after)
		_:
			packed = PackedVector2Array(after)
	world.submit({"op": "reshape", "id": w.id, "data": {"roof": {key: packed}} if on_roof else {key: packed}}, func() -> void:
		if _sent.get(w.id, {}).get(key) == after:
			_sent[w.id].erase(key))


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
