class_name FittingTool
extends Node3D

## One opening operation for windows and both door styles, plus decorations. A low window click makes a
## plain door; the arch selection supplies the archway door style; on a gable roof's slope the window opens a dormer.
## Both preview and commit the same list.
## Decorations hang as ghosts until their command returns, placed or taken away as the trigger is let go; a stroke
## with it held from one point to another hangs a string between them. Every edit goes through World.

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
## Per hand, the opening target its wall was last laid for.
var _aims: Array[Dictionary] = []
## Per hand, the seed of the decoration its next press places, drawn once per placement so its preview holds still.
var _draws: Array[int] = []
## Per hand, the aim its decorations trigger went down on, until it is let go; null while it is up.
var _starts: Array = []
## The reshape data each wall is laid with that the garden does not have yet, by id.
var _previewed := {}
## Fitting lists sent and not yet back, by wall id and key, so a quick second press builds on the first.
var _sent := {}
var lamps := Lamps.new()
var _since_lights := INF
var _ghost_fits := _ghost_material(Color(1.0, 0.96, 0.88, 0.7), 0.25)
var _ghost_astray := _ghost_material(WaterTool.REFUSED, 0.0)


func _init(player: Rig, builder: WallTool, garden: World) -> void:
	rig = player
	walls = builder
	world = garden
	world.decorations = Decorations.new(world, walls)
	add_child(world.decorations)
	lamps.terrain = world.terrain
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
		_draws.append(randi())
		_starts.append(null)


func _process(delta: float) -> void:
	world.decorations.sync()
	var shown := {}
	for i in _buttons.size():
		var b := _buttons[i]
		var hand: Hand = b.hand
		var ghost := {}
		if hand.tool in [Hand.Tool.WINDOWS, Hand.Tool.ARCH, Hand.Tool.DECORATIONS] and rig.aim_hand != hand and hand.tracked():
			var t := hand.global_transform
			var target := _steady(i, aim(hand.tool, t.origin, -t.basis.z))
			var placing: bool = target.get("what") == "decoration" and not target.has("fitting")
			if placing:
				target.seed = _draws[i]
			var hit: Variant = target.point if not target.is_empty() else world.terrain.raycast(t.origin, -t.basis.z)
			hand.point(hit, TINT)
			var decorating := hand.tool == Hand.Tool.DECORATIONS
			var stroke := string_command(_starts[i], target, _draws[i], world.decorations.string_style, walls.paint[Palette.Element.LANTERN]) if decorating and _starts[i] != null else {}
			if not stroke.is_empty():
				world.preview(hand, world.change_of(stroke))
			elif not target.is_empty():
				var c := change(target)
				var cmd := _command(target, c)
				world.preview(hand, world.change_of(cmd))
				if target.what == "opening" and c.near < 0 and not cmd.is_empty():
					shown.get_or_add(cmd.id, {}).merge(cmd.data, true)
			if decorating and b.pressed("tool") and not walls.busy(hand):
				_starts[i] = target
			elif decorating and b.released("tool") and _starts[i] != null:
				_let_go(i, hand, stroke, target)
			elif not decorating and b.pressed("tool") and not walls.busy(hand) and not fit(target, hand):
				_refused(i, hand)
			if not hand.picking and decorating:
				ghost = ghost_of(target, t.origin, -t.basis.z, hit) if stroke.is_empty() else {"what": "decoration", "d": stroke, "xform": world.decorations.frame(stroke), "fits": true}
		if hand.tool != Hand.Tool.DECORATIONS or not b.held("tool"):
			_starts[i] = null
		_show_ghost(i, ghost, delta)
		b.latch()
	for id in _sent:
		if _sent[id].has("openings") and not shown.get(id, {}).has("openings"):
			shown.get_or_add(id, {}).openings = PackedVector4Array(_sent[id].openings)
	show_reshaped(shown)
	_since_lights += delta
	if _since_lights >= LIGHT_EVERY:
		light_lanterns()
	lamps.update()


## Hand `i`'s decorations trigger let go aiming at `target`: it hangs `stroke` where it drew one, or else does what its
## preview showed there.
func _let_go(i: int, hand: Hand, stroke: Dictionary, target: Dictionary) -> void:
	_starts[i] = null
	if not stroke.is_empty():
		if world.fits(stroke):
			Cues.play(Cues.Act.FITTING, stroke.to, hand)
		world.submit(stroke, Callable(), hand)
	elif not fit(target, hand):
		_refused(i, hand)
		return
	if not stroke.is_empty() or (target.get("what") == "decoration" and not target.has("fitting")):
		_draws[i] = randi()


func _refused(i: int, hand: Hand) -> void:
	_shaken[i] = 0.0
	Cues.play(Cues.Act.REFUSED, hand.global_position, hand)


## The string a stroke of the decorations tool from aim `from` to aim `to` hangs between their points, each on a pole
## where a decoration would stand there outdoors, seeded `seed`, of `style` with its lanterns in `lantern` (a
## Palette.Element.LANTERN swatch); {} where none hangs.
func string_command(from: Dictionary, to: Dictionary, seed: int, style: int, lantern: int) -> Dictionary:
	if from.is_empty() or to.is_empty():
		return {}
	var ends: Array[Vector3] = []
	var drop := Vector2.ZERO
	for k in 2:
		var end: Dictionary = [from, to][k]
		drop[k] = DecorationLayout.POLE if end.get("what") == "decoration" and end.get("mount") in ["ground", "deck", "foundation"] and not end.has("fitting") else 0.0
		ends.append(end.point + Vector3.UP * drop[k])
	var cmd := {"op": "decoration", "wall": -1, "mount": "span", "at": ends[0], "to": ends[1], "drop": drop, "s": 0.0, "side": 1.0, "turn": 0.0, "seed": seed, "style": style, "lantern": lantern}
	return cmd if Commands._decoration(cmd) != null else {}


## What a press from `origin` along `dir` would do with `tool`: a dictionary naming `what` and where, or empty.
func aim(tool: Hand.Tool, origin: Vector3, dir: Vector3) -> Dictionary:
	var decoration := tool == Hand.Tool.DECORATIONS
	var target := World.Kind.TARGET_PAST_ARCHES if decoration else World.Kind.TARGET
	var hits := world.pick(origin, dir, {target: INF, World.Kind.GROUND: INF, World.Kind.FLOOR: INF} if decoration else {target: INF})
	var pick: Dictionary = hits.get(target, {})
	var facing := atan2(-dir.x, -dir.z)
	if not hits.is_empty():
		var hit: Dictionary = hits.values().back()
		match hits.keys().back():
			World.Kind.FLOOR:
				return {"what": "decoration", "mount": "floor", "point": hit.point, "wall": hit.wall, "turn": facing}
			World.Kind.GROUND:
				return {"what": "decoration", "mount": "ground", "point": hit.point, "wall": null, "s": 0.0, "side": 1.0, "turn": facing}
	if pick.has("fitting"):
		var what: String = pick.what
		if (tool == Hand.Tool.DECORATIONS and not what in ["opening", "dormer", "hatch"]) or (tool in [Hand.Tool.WINDOWS, Hand.Tool.ARCH] and what == "opening") or (tool == Hand.Tool.WINDOWS and what in ["dormer", "hatch"]):
			return pick
		if pick.on_roof and tool in [Hand.Tool.WINDOWS, Hand.Tool.ARCH]:
			return {}
	var roof := pick if pick.get("surface") == "roof" else {}
	var on_roof := not roof.is_empty()
	if tool in [Hand.Tool.WINDOWS, Hand.Tool.ARCH]:
		if on_roof and tool == Hand.Tool.WINDOWS and roof.wall.roof.flat():
			return {"what": "hatch", "wall": roof.wall, "at": roof.wall.roof.spot_of(roof.point), "point": roof.point}
		if on_roof and tool == Hand.Tool.WINDOWS and roof.wall.roof.kind == RoofLayout.Kind.GABLE:
			return {"what": "dormer", "wall": roof.wall, "at": roof.wall.roof.spot_of(roof.point), "point": roof.point}
		if on_roof or pick.is_empty() or pick.wall.layout.fence:
			return {}
		if tool == Hand.Tool.ARCH:
			return {"what": "opening", "wall": pick.wall, "s": pick.s, "y": 0.0, "style": WallLayout.Family.ARCHWAY, "point": pick.point}
		var corner: float = pick.wall.layout.corner_near(pick.s)
		var family := WallLayout.Family.CORNER if not is_nan(corner) else walls.window_family
		var y := _height(pick)
		if not WallLayout.LIGHTS[family].door:
			y = maxf(y, WallLayout.lowest(family))
		return {"what": "opening", "wall": pick.wall, "s": pick.s if is_nan(corner) else corner, "y": y, "style": family, "point": pick.point}
	if on_roof:
		var w: Wall = roof.wall
		if w.roof.flat():
			return {"what": "decoration", "mount": "deck", "point": roof.point, "wall": w, "turn": facing}
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
	if not layout.fence and y <= 0.25:
		if layout.stilted():
			return {}
		return {"what": "decoration", "mount": "foundation", "wall": pick.wall, "s": pick.s, "side": side if side != 0.0 else 1.0, "point": pick.point, "turn": 0.0}
	return {"what": "lantern", "wall": pick.wall, "s": pick.s, "y": y, "side": side if side != 0.0 else 1.0, "point": pick.point}


## `target`, or the opening target hand `i` last aimed where `target` would make the same opening, so a hand
## moving within one lays the wall once.
func _steady(i: int, target: Dictionary) -> Dictionary:
	var held := _aims[i]
	if target.get("what") == "opening" and not target.has("fitting") and not held.has("fitting") and target.what == held.get("what") and held.wall == target.wall:
		var layout: WallLayout = target.wall.layout
		var same := layout.opening_for(_opening(held)) == layout.opening_for(_opening(target))
		if same:
			held.point = target.point
			return held
	_aims[i] = target
	return target


static func _opening(target: Dictionary) -> Vector4:
	return Vector4(target.s, target.y, target.get("style", WallLayout.Family.COTTAGE), target.get("size", 1.0))


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
	if target.what == "decoration":
		world.submit(cmd, Callable(), hand)
		return true
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
	if target.has("fitting"):
		return removal(world.state, target)
	return _command(target, change(target))


func _command(target: Dictionary, c: Dictionary) -> Dictionary:
	if target.has("fitting"):
		return removal(world.state, target)
	if not c.ok:
		return {}
	if target.what == "decoration":
		return decoration_command(target.merged({"lantern": walls.paint[Palette.Element.LANTERN]}))
	var w: Wall = target.wall
	if target.what == "tower_flag":
		return {"op": "reshape", "of": "walls", "id": w.id, "data": {"roof": {"flag": not w.roof.flag}}}
	return {"op": "reshape", "of": "walls", "id": w.id, "data": FittingGrip.data(c.key, FittingGrip.packed(c.key, c.after), c.on_roof)}


## What a press on `target` would do: `ok` false where nothing; otherwise the list `key` on the wall (or
## its roof, `on_roof`) becomes `after`, with entry `near` taken out of it, or with `value` added where
## `near` is -1.
func change(target: Dictionary) -> Dictionary:
	if target.is_empty():
		return {"ok": false}
	if target.what == "decoration":
		return {"ok": true, "near": target.index if target.has("fitting") else -1}
	var w: Wall = target.wall
	var layout := w.layout
	if target.has("fitting"):
		return {"ok": not removal(world.state, target).is_empty(), "near": target.index}
	match target.what:
		"opening":
			if layout.fence:
				return {"ok": false}
			var click := _opening(target)
			var placed: Array[Vector4] = []
			placed.assign(_placed(w, false, "openings"))
			var near := layout.placed_at(click, placed)
			return _change(w, false, "openings", click, near, near >= 0 or layout.opening_fits(click, walls.standing_openings(w, placed)))
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
			return _change(w, true, "chimneys", spot, near, near >= 0 or w.roof.clear_of_dormers(spot))
		"dormer":
			var placed := _placed(w, true, "dormers")
			var spot := w.roof.dormer_spot(target.at)
			var near := placed.find_custom(func(e: Vector2) -> bool: return not RoofLayout.spots_apart(w.roof.dormer_spot(e), spot, RoofLayout.DORMER_HALF + RoofLayout.DORMER_EAVE))
			return _change(w, true, "dormers", spot, near, near >= 0 or w.roof.dormer_fits(spot, placed))
		"hatch":
			var placed := _placed(w, true, "hatches")
			var spot := w.roof.hatch_spot(target.at)
			var near := placed.find_custom(func(e: Vector2) -> bool: return RoofLayout.hatches_meet(w.roof.hatch_spot(e), spot))
			return _change(w, true, "hatches", spot, near, near >= 0 or w.roof.hatch_fits(spot, placed))
	return {"ok": true, "near": 0 if w.roof.flag else -1}


## The list `key` on the wall (or its roof) as the garden has it with our sent commands applied, read from the garden
## rather than the wall, which may be previewing an opening.
func _placed(w: Wall, on_roof: bool, key: String) -> Array:
	var d: Dictionary = world.state.walls[w.id]
	return Array(_sent.get(w.id, {}).get(key, (d.roof if on_roof else d)[key]))


func _change(w: Wall, on_roof: bool, key: String, value: Variant, near: int, ok: bool) -> Dictionary:
	var after := _placed(w, on_roof, key).duplicate()
	if near >= 0:
		after.remove_at(near)
	elif after.size() >= {"chimneys": Commands.MAX_CHIMNEYS, "dormers": Commands.MAX_DORMERS, "hatches": Commands.MAX_HATCHES}.get(key, Commands.MAX_FITTINGS):
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
	if target.what == "decoration":
		var d := decoration_command(target.merged({"lantern": walls.paint[Palette.Element.LANTERN]}))
		if world.decorations.frame(d) == null:
			return {}
		return {"what": "decoration", "d": d, "xform": world.decorations.frame(d), "fits": true}
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
			at = r.mid + r.along * c.value.x + r.across * c.value.y + Vector3.UP * w.roof.spot_height(c.value)
			var index := _placed(w, true, "chimneys").size()
			var height := snappedf(w.roof.chimney_top(c.value) - w.roof.spot_height(c.value), 0.05)
			# Laid along the roof's own ridge, the ghost needs no turn of its own.
			return {"what": what, "xform": Transform3D(Basis(), at), "fits": c.ok, "roof": w.roof, "spot": c.value, "index": index, "shape": [w.roof.seed, index, w.roof.thatched(), height]}
		"tower_flag":
			what = "flag"
			at = w.roof.flag_top()
			face = RoofLayout.FLAG_ALONG.normalized().cross(Vector3.UP)
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
	var shape := []
	if ghost.get("what") == "decoration":
		var d: Dictionary = ghost.d
		shape = [d.style, d.seed, world.decorations.rise(d), d.mount, Decorations.span(d).snapped(Vector3.ONE * 0.25), d.get("drop"), d.lantern]
	if ghost.get("what") == "decoration" and (not _ghosts[i].has("decoration") or _ghosts[i].decoration.get_meta(&"shape") != shape):
		if _ghosts[i].has("decoration"):
			_ghosts[i].decoration.free()
		var n := ToolModels.decoration(world.decorations.laid(ghost.d), ghost.d.lantern)
		n.top_level = true
		n.set_meta(&"shape", shape)
		add_child(n)
		_ghosts[i].decoration = n
	# A chimney stands taller down its slope: its ghost is laid again as its height moves 5 cm, by the roof it goes on.
	if ghost.get("what") == "chimney" and _ghosts[i].chimney.get_meta(&"shape", []) != ghost.shape:
		_ghosts[i].chimney.free()
		var g := ToolModels.fitting("chimney", ghost.roof, ghost.spot, ghost.index)
		g.top_level = true
		g.set_meta(&"shape", ghost.shape)
		add_child(g)
		_ghosts[i].chimney = g
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
		if not g.visible or g.get_meta(&"mat", null) != mat:
			g.set_meta(&"mat", mat)
			for c in g.get_children():
				if c is Fittings:
					(c as Fittings).ghostly(mat)
				elif c is GeometryInstance3D:
					c.material_override = mat
				else:
					for m in c.get_children():
						(m as GeometryInstance3D).material_override = mat
		g.visible = true


## Hands every lantern's flame, and the houses holding them, to the light they cast.
func light_lanterns() -> void:
	_since_lights = 0.0
	lamps.light(walls.walls, world.decorations.flames, world.decorations.lights)


func _exit_tree() -> void:
	lamps.stop()


## Placement and deletion refine the same first building surface with the fittings in front of it that the garden has:
## a previewed opening is the hand's own aim, never something to take away. A `held` pick also sees builds another
## hand is pulling, and `through_arches` sees through an arch, as `WallTool.pick_building` does; without it a grip or
## a delete into the hole takes the arch.
static func pick_target(builder: WallTool, origin: Vector3, dir: Vector3, held := false, through_arches := false) -> Dictionary:
	var best := builder.pick_building(origin, dir, held, through_arches)
	for w in builder.walls:
		if builder._held(w) and not held:
			continue
		for item in targets(w):
			if through_arches and item.what == "opening" and item.value.z == WallLayout.Family.ARCHWAY:
				continue
			var box: AABB = item.box
			var local: Vector3 = item.inverse * origin
			var direction: Vector3 = item.inverse.basis * dir
			var hit: Variant = local if box.has_point(local) else box.intersects_ray(local, direction)
			if hit == null or removal(builder.world.state, item).is_empty():
				continue
			var along: float = (hit - local).dot(direction) / direction.length_squared()
			var point := origin + dir * along
			if w.layout.hides(point):
				continue
			if along > best.get("along", INF) + 0.001:
				continue
			best = item.duplicate()
			best.point = point
			best.along = along
			best.s = w.layout.closest_s(point)
			best.y = point.y - w.layout.point_at(best.s).y
			best.surface = "roof" if item.on_roof else "wall"
			best.distance = 0.0
	if builder.world.decorations != null:
		for item in builder.world.decorations.targets():
			var local: Vector3 = item.inverse * origin
			var direction: Vector3 = item.inverse.basis * dir
			var hit: Variant = item.box.intersects_ray(local, direction)
			if hit == null:
				continue
			var along: float = (hit - local).dot(direction) / direction.length_squared()
			if along < 0.0 or along > best.get("along", INF) + 0.001:
				continue
			best = item.duplicate()
			best.point = origin + dir * along
			best.along = along
	return best


## Addressable additions only: ivy is grown as part of the wall, not stored as separate plants.
static func targets(w: Wall) -> Array[Dictionary]:
	if w.get_meta(&"fitting_laid", -1) == w.layout.laid:
		return w.get_meta(&"fitting_targets")
	var out: Array[Dictionary] = []
	var l := w.layout
	# A wall the garden just brought back shows nothing until its stones are laid, and a gable's frame comes from them.
	if l.laid == 0:
		return out
	for i in l.lanterns.size():
		var v := l.lanterns[i]
		if not l.lantern_fits(v.x, v.y):
			continue
		var f := l.frame_at(l.nearest_post(v.x) if l.fence else v.x)
		var at: Vector3 = f.point + Vector3.UP * (WallLayout.FENCE_HEIGHT + 0.25 if l.fence else v.y)
		if not l.fence:
			at += f.tangent.cross(Vector3.UP) * v.z * (WallLayout.THICKNESS * 0.5 + WallLayout.LANTERN_OUT)
		out.append(_target(w, "lantern", "lanterns", i, v, AABB(at + Vector3(-0.14, -0.1, -0.14), Vector3(0.28, 0.44, 0.28))))
	for i in l.openings.size():
		var v := l.openings[i]
		if l._opening_in(l.apertures, v.x, v.y).is_empty():
			continue
		var o := l.opening_for(v)
		var f := l.frame_at(v.x)
		var xform := Transform3D(Basis(f.tangent, Vector3.UP, f.tangent.cross(Vector3.UP)), f.point)
		var box := AABB(Vector3(-o.half, o.sill, -WallLayout.THICKNESS * 0.5 - 0.02), Vector3(o.half * 2, o.head - o.sill, WallLayout.THICKNESS + 0.04))
		out.append(_target(w, "opening", "openings", i, v, box, false, xform))
	for i in l.flags.size():
		var v := l.flags[i]
		if l.flag_fits(v):
			var f := l.frame_at(v)
			out.append(_target(w, "flag", "flags", i, v, _flag_bounds(f.point + Vector3.UP * (l.height + WallLayout.CAP), f.tangent)))
	if w.roof != null:
		var r := w.roof
		var f := r.frame()
		for i in r.chimneys.size():
			var v := r.chimneys[i]
			var foot: Vector3 = f.mid + f.along * v.x + f.across * v.y
			var surface := r.spot_height(v)
			var top := r.chimney_top(v) + 0.34
			var half := (RoofLayout.STACK_WIDTH + 0.14) * 0.5
			var xform := Transform3D(Basis(f.along, Vector3.UP, f.across), foot)
			out.append(_target(w, "chimney", "chimneys", i, v, AABB(Vector3(-half, surface, -half), Vector3(half * 2, top - surface, half * 2)), true, xform))
		for i in r.dormers.size():
			var room := r.dormer_bounds(r.dormers[i])
			if not room.is_empty():
				out.append(_target(w, "dormer", "dormers", i, r.dormers[i], room[1], true, room[0]))
		for i in r.hatches.size():
			var lid := r.hatch_bounds(r.hatches[i])
			if not lid.is_empty() and r.hatch_fits(r.hatches[i], r.hatches.slice(0, i)):
				out.append(_target(w, "hatch", "hatches", i, r.hatches[i], lid[1], true, lid[0]))
		if r.flag:
			out.append(_target(w, "tower_flag", "flag", 0, true, _flag_bounds(r.flag_top(), RoofLayout.FLAG_ALONG), true))
	w.set_meta(&"fitting_laid", w.layout.laid)
	w.set_meta(&"fitting_targets", out)
	return out


static func _flag_bounds(foot: Vector3, along: Vector3) -> AABB:
	var parts := WallLayout.flag(foot, along, Color.WHITE)
	var unit := AABB(Vector3.ONE * -0.5, Vector3.ONE)
	return (parts.pole * unit).merge(parts.finial * unit).merge(parts.cloth.xform * AABB(Vector3(0, -0.5, -0.08), Vector3(1, 1, 0.16)))


static func _target(w: Wall, what: String, key: String, index: int, value: Variant, box: AABB, on_roof := false, space := Transform3D.IDENTITY) -> Dictionary:
	return {"wall": w, "fitting": true, "what": what, "key": key, "index": index, "value": value, "bounds": space * box, "box": box, "inverse": space.affine_inverse(), "on_roof": on_roof}


static func removal(state: Dictionary, target: Dictionary) -> Dictionary:
	if target.has("decoration"):
		return {"op": "take", "of": "decorations", "ids": PackedInt32Array([target.decoration])} if state.decorations.has(target.decoration) else {}
	if not is_instance_valid(target.wall):
		return {}
	var w: Wall = target.wall
	if not state.walls.has(w.id):
		return {}
	var data: Dictionary = state.walls[w.id]
	if target.on_roof:
		data = data.get("roof", {})
	var after: Variant = data.get(target.key)
	if after == null:
		return {}
	if target.what == "tower_flag":
		if not after:
			return {}
		after = false
	else:
		after = after.duplicate()
		var index: int = after.find(target.value)
		if index < 0:
			return {}
		after.remove_at(index)
	return {"op": "reshape", "of": "walls", "id": w.id, "data": FittingGrip.data(target.key, after, target.on_roof)}


static func decoration_command(target: Dictionary) -> Dictionary:
	var w: Wall = target.get("wall")
	var mount: String = target.get("mount", "ground" if w == null else "foundation")
	var at: Vector3 = target.point
	var turn: float = target.get("turn", 0.0)
	if mount in ["floor", "deck"]:
		var x := Decorations.plan(w)
		at = x.affine_inverse() * Vector3(at.x, 0.0, at.z)
		turn -= atan2(-x.basis.x.z, x.basis.x.x)
	return {"op": "decoration", "wall": w.id if w != null else -1, "mount": mount, "at": at, "s": float(target.get("s", 0.0)), "side": float(target.get("side", 1.0)), "turn": turn, "seed": int(target.get("seed", 0)), "style": int(target.get("style", DecorationLayout.PRESENT)), "lantern": int(target.get("lantern", 0))}
