class_name FittingTool
extends Node3D

## Windows, arches and decorations, for whichever hand holds them. With windows, the trigger on a wall opens a
## window where the hand points, or a door where that is near the ground; one beside another on its course
## fuses with it into a wider opening, and the trigger on one closes it. With the arch, the trigger on a wall cuts
## an archway through it where the hand points, and on one of the wall's own fills it. With decorations, what the hand
## points at decides what goes there: a chimney on a house's roof, a flag on a tower's roof or a wall's top,
## a lantern on a wall's face or a fence; the trigger on one takes it away. Every lantern lights what is
## around it (`Lamps`).
##
## While windows or the arch are held, the wall pointed at is laid as a press would leave it, through the path that lays the
## press's command, so what shows is what a press builds. A decoration's ghost rides the hand's ray instead: set on
## the wall where a press would place it, faint and hanging in the air where it would not, and a press there shakes
## it. A press that places nothing bumps the hand.

const TINT := Color(1.0, 0.93, 0.78, 0.6)
## A press this near a placed fitting takes it away.
const TAKE_REACH := 0.6
const LIGHT_EVERY := 0.25
## A ghost with nowhere to go hangs this high over the ground the hand points at, or this far along the
## ray where that ground is far or missing.
const HANG_OVER := 1.0
const HANG := 2.5
const SHAKE := 0.35

var rig: Rig
var walls: WallTool
var world: World
var _buttons: Array[Buttons] = []
## Per hand: each fitting's ghost by ToolModels.FITTING_PARTS key, and how long since a refused press.
var _ghosts: Array[Dictionary] = []
var _shaken: Array[float] = []
## Per hand, the window or arch target its wall was last laid for.
var _aims: Array[Dictionary] = []
## The reshape data each wall is laid with that the garden does not have yet, by id.
var _previewed := {}
## Fitting lists sent and not yet back, by wall id and key, so a quick second press builds on the first.
var _sent := {}
var lamps := Lamps.new()
var _since_lights := INF
var _ghost_fits := _ghost_material(Color(1.0, 0.96, 0.88, 0.7), 0.25)
var _ghost_astray := _ghost_material(Color(0.72, 0.76, 0.86, 0.5), 0.0)


func _init(player: Rig, builder: WallTool, garden: World) -> void:
	rig = player
	walls = builder
	world = garden
	lamps.install()
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["tool"]))
		var ghosts := {}
		for what in ToolModels.FITTING_PARTS:
			if what == "window":
				continue
			var g := ToolModels.fitting(what)
			g.top_level = true
			g.visible = false
			add_child(g)
			ghosts[what] = g
		_ghosts.append(ghosts)
		_shaken.append(INF)
		_aims.append({})


func _process(delta: float) -> void:
	var shown := {}
	for i in _buttons.size():
		var b := _buttons[i]
		var hand: Hand = b.hand
		var ghost := {}
		if hand.tool in [Hand.Tool.WINDOWS, Hand.Tool.ARCH, Hand.Tool.DECORATIONS] and rig.aim_hand != hand and hand.tracked():
			var t := hand.global_transform
			var target := _steady(i, aim(hand.tool, t.origin, -t.basis.z))
			var hit: Variant = target.point if not target.is_empty() else Terrain.raycast(t.origin, -t.basis.z)
			hand.point(hit, TINT)
			if not target.is_empty():
				var c := change(target)
				var cmd := _command(target, c)
				world.preview(hand, world.change_of(cmd))
				if target.what in ["window", "arch"] and c.near < 0 and not cmd.is_empty():
					shown.get_or_add(cmd.id, {}).merge(cmd.data, true)
			if b.pressed("tool") and not walls.busy(hand) and not fit(target, hand):
				_shaken[i] = 0.0
				Cues.play(Cues.Act.REFUSED, hand.global_position, hand)
			if not hand.picking and hand.tool == Hand.Tool.DECORATIONS:
				ghost = ghost_of(target, t.origin, -t.basis.z, hit)
		_show_ghost(i, ghost, delta)
		b.latch()
	for id in _sent:
		if _sent[id].has("windows") and not shown.get(id, {}).has("windows"):
			shown.get_or_add(id, {}).windows = PackedVector2Array(_sent[id].windows)
		if _sent[id].has("arches") and not shown.get(id, {}).has("arches"):
			shown.get_or_add(id, {}).arches = PackedFloat32Array(_sent[id].arches)
	show_reshaped(shown)
	_since_lights += delta
	if _since_lights >= LIGHT_EVERY:
		light_lanterns()
	lamps.update()


## What a press from `origin` along `dir` would do with `tool`: a dictionary naming `what` and where, or empty.
func aim(tool: Hand.Tool, origin: Vector3, dir: Vector3) -> Dictionary:
	var pick := walls.pick_wall(origin, dir)
	var roof := walls.pick_roof(origin, dir)
	var on_roof: bool = not roof.is_empty() and (pick.is_empty() or pick.distance > 0.2 or roof.along < pick.along)
	if tool == Hand.Tool.WINDOWS:
		if on_roof or pick.is_empty() or pick.wall.layout.fence:
			return {}
		return {"what": "window", "wall": pick.wall, "s": pick.s, "y": _height(pick), "point": pick.point}
	if tool == Hand.Tool.ARCH:
		if on_roof or pick.is_empty() or pick.wall.layout.fence:
			return {}
		return {"what": "arch", "wall": pick.wall, "s": pick.s, "point": pick.point}
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


## `target`, or the window or arch target hand `i` last aimed where `target` would make the same opening, so a hand
## moving within one lays the wall once.
func _steady(i: int, target: Dictionary) -> Dictionary:
	var held := _aims[i]
	if target.get("what") in ["window", "arch"] and target.what == held.get("what") and held.wall == target.wall:
		var layout: WallLayout = target.wall.layout
		var same := false
		match target.what:
			"window":
				same = layout.opening_for(Vector2(held.s, held.y)) == layout.opening_for(Vector2(target.s, target.y))
			"arch":
				same = absf(layout.offset(held.s, target.s)) < WallLayout.ARCH_HALF
		if same:
			held.point = target.point
			return held
	_aims[i] = target
	return target


## Lays each wall in `shown`, by id, with its reshape data, as the command sending it would; every other wall laid
## so before is laid as the garden has it again.
func show_reshaped(shown: Dictionary) -> void:
	for id in _previewed.keys():
		if shown.has(id):
			continue
		var w := walls.find(id)
		if w != null and w.reshaped == _previewed[id]:
			walls.settle(id)
		_previewed.erase(id)
	for id in shown:
		var w := walls.find(id)
		if w != null and w.reshaped != shown[id]:
			_previewed[id] = shown[id]
			walls.show_reshaped(id, shown[id])


static func _height(pick: Dictionary) -> float:
	return pick.point.y - (pick.wall as Wall).layout.point_at(pick.s).y


## Places what `aim` found, or takes away the one already there, as one build command from `hand`; false where the
## press does nothing.
func fit(target: Dictionary, hand: XRController3D = null) -> bool:
	var cmd := command(target)
	if cmd.is_empty():
		return false
	var w: Wall = target.wall
	var key: String = cmd.data.roof.keys()[0] if cmd.data.has("roof") else cmd.data.keys()[0]
	var after: Variant = cmd.data.roof[key] if cmd.data.has("roof") else cmd.data[key]
	if world.fits(cmd):
		var garden: Dictionary = world.state.walls.get(w.id, {})
		var had: Variant = (garden.get("roof", {}) if cmd.data.has("roof") else garden).get(key)
		var off: bool = (not after) if after is bool else (had != null and Array(after).size() < Array(had).size())
		Cues.play(Cues.Act.FITTING_OFF if off else Cues.Act.FITTING, target.get("point", w.global_position), hand)
	if target.what == "tower_flag":
		world.submit(cmd, Callable(), hand)
		return true
	_sent.get_or_add(w.id, {})[key] = Array(after)
	world.submit(cmd, func() -> void:
		if _sent.get(w.id, {}).get(key) == Array(after):
			_sent[w.id].erase(key), hand)
	return true


## The build command a press on `target` sends, or {} where it does nothing.
func command(target: Dictionary) -> Dictionary:
	return _command(target, change(target))


func _command(target: Dictionary, c: Dictionary) -> Dictionary:
	if not c.ok:
		return {}
	var w: Wall = target.wall
	if target.what == "tower_flag":
		return {"op": "reshape", "of": "walls", "id": w.id, "data": {"roof": {"flag": not w.roof.flag}}}
	var after: Array = c.after
	var packed: Variant
	match c.key:
		"lanterns":
			packed = PackedVector3Array(after)
		"flags", "arches":
			packed = PackedFloat32Array(after)
		_:
			packed = PackedVector2Array(after)
	return {"op": "reshape", "of": "walls", "id": w.id, "data": {"roof": {c.key: packed}} if c.on_roof else {c.key: packed}}


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
			var placed: Array[Vector2] = []
			placed.assign(_placed(w, false, "windows"))
			var near := layout.window_at(click, placed)
			return _change(w, false, "windows", click, near, near >= 0 or layout.window_fits(click, placed))
		"lantern":
			var s: float = layout.nearest_post(target.s) if layout.fence else target.s
			var hang := Vector3(s, target.y, target.side)
			var near := layout.lanterns.find_custom(func(e): return absf(layout.offset(e.x, s)) < TAKE_REACH and (layout.fence or absf(e.y - hang.y) < TAKE_REACH and e.z == hang.z))
			return _change(w, false, "lanterns", hang, near, near >= 0 or layout.lantern_fits(s, hang.y))
		"flag":
			var near := layout.flags.find_custom(func(e): return absf(layout.offset(e, target.s)) < TAKE_REACH)
			return _change(w, false, "flags", target.s, near, near >= 0 or layout.flag_fits(target.s))
		"arch":
			var own := _placed(w, false, "arches")
			var near := own.find_custom(func(a): return absf(layout.offset(a, target.s)) < WallLayout.ARCH_HALF * 2.0)
			var standing := walls.standing_arches(w, own)
			var clear := not standing.any(func(a): return absf(layout.offset(a, target.s)) < WallLayout.ARCADE_GAP)
			return _change(w, false, "arches", target.s, near, near >= 0 or (clear and layout.can_arch() and layout.fits_arch(target.s, standing)))
		"chimney":
			var spot := w.roof.chimney_spot(target.at)
			var near := w.roof.chimneys.find_custom(func(e): return e.distance_to(spot) < RoofLayout.STACK_WIDTH + 0.3)
			return _change(w, true, "chimneys", spot, near, true)
	return {"ok": true, "near": 0 if w.roof.flag else -1}


## The list `key` on the wall (or its roof) as the garden has it with our sent commands applied, read from the garden
## rather than the wall, which may be showing windows or an arch aimed at.
func _placed(w: Wall, on_roof: bool, key: String) -> Array:
	var d: Dictionary = world.state.walls[w.id]
	return Array(_sent.get(w.id, {}).get(key, (d.roof if on_roof else d)[key]))


func _change(w: Wall, on_roof: bool, key: String, value: Variant, near: int, ok: bool) -> Dictionary:
	var after := _placed(w, on_roof, key).duplicate()
	if near >= 0:
		after.remove_at(near)
	elif after.size() >= {"chimneys": Commands.MAX_CHIMNEYS, "arches": Commands.MAX_ARCHES}.get(key, Commands.MAX_FITTINGS):
		ok = false
	else:
		after.append(value)
	return {"ok": ok, "on_roof": on_roof, "key": key, "after": after, "near": near, "value": value}


## The ghost a hand holding decorations shows for `target`, pointing from `origin` along `dir` at `hit` (or
## nothing): the fitting `what` at `xform`, `fits` where a press would place it. Where the press would
## take a fitting away it shows none, the fitting itself being there.
func ghost_of(target: Dictionary, origin: Vector3, dir: Vector3, hit: Variant) -> Dictionary:
	var c := change(target)
	if c.ok and c.near >= 0:
		return {}
	if target.is_empty():
		var at: Vector3 = hit + Vector3.UP * HANG_OVER if hit != null and origin.distance_to(hit) < HANG * 2.0 else origin + dir * HANG
		return {"what": "lantern", "xform": _facing(at, -dir), "fits": false}
	var w: Wall = target.wall
	var layout := w.layout
	var what: String = target.what
	var at: Vector3
	var face := Vector3.ZERO
	match what:
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


## Hands every lantern's flame, and the houses holding them, to the light they cast.
func light_lanterns() -> void:
	_since_lights = 0.0
	lamps.light(walls.walls)


func _exit_tree() -> void:
	lamps.stop()
