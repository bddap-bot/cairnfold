class_name Commands
extends RefCounted

## The build commands' one schema. `clean` returns a fresh command holding only the fields its op
## defines, each checked for type and range against what a tool can make and the garden's ground, or {} for anything
## else: every machine runs it on every command it is handed, so a peer cannot wedge or corrupt a garden.

const OPS := ["stairs", "wall", "take", "reshape", "path", "ground", "plant", "show", "tree", "heights", "ponds", "season", "sky", "wipe", "garden", "batch", "easel", "paint", "unpaint", "sheet", "restone", "boulder", "decoration"]
## What a batch may carry: from a player, takings; from the host, also the undo of them (PUTS) and of what water drowned.
const BATCHED := ["take", "reshape", "show"]
const HOST_BATCHED := ["heights", "ponds", "tree"]
## Most commands one batch carries.
const MAX_BATCH := 128
## A stroke builds at most this many walls; their ids follow from the command's sequence number.
const MAX_PIECES := 8
const MAX_POINTS := 2048
const MAX_PATH_POINTS := 2048
const MAX_DABS := 2000
const MAX_STROKE := 4000
const MIN_ROOF_RADIUS := 0.5
## Longest stroke a wall, a path or a flight of stairs may run; the tools stop growing one there.
const MAX_LENGTH := 240.0
## Where the tools stop a stroke: short of MAX_LENGTH by more than a stroke's last moves and joins add.
const STROKE_LENGTH := MAX_LENGTH - 16.0
## Most walls, paths and plant groups one garden holds.
const MAX_THINGS := 4000
const MAX_PONDS := 256
const MAX_STAMPS := 2000
const MAX_FITTINGS := 64
const MAX_CHIMNEYS := 8
const MAX_DORMERS := 8
const MAX_HATCHES := 8
const MAX_RUINS := 32
## Most commands a snapshot holds: per thing one, and per plant group one more for its hidden plants.
const MAX_SNAPSHOT := MAX_THINGS * 2 + 64
## Most builds one build stands on.
const MAX_SUPPORTS := 8
## What a `reshape` may change, by the garden's table of the builds it changes; `paint` and a wall's `roof` change
## by the entries they name.
const RESHAPES := {
	"walls": ["points", "height", "rise", "top", "finish", "wear", "foundation", "planks", "gable_end", "openings", "lanterns", "flags", "clutter", "ruins"],
	"stairs": ["rail", "a", "b", "width", "sag", "on"],
	"boulders": ["at", "turn", "sink", "scale", "style"],
	"decorations": ["style", "at", "turn", "s", "lantern", "to"],
	"easels": ["at", "yaw"],
	"paths": ["surface", "clutter"],
}
## Per table of the garden, the field naming the builds an entry stands on, or "" for one standing only on the ground:
## whatever stands on a build goes when it goes (`World._take`). Every table is named here, so a new one cannot be
## left out of that.
const STANDS_ON := {"walls": "on", "stairs": "on", "decorations": "wall", "paths": "", "grounds": "", "groups": "", "ponds": "", "easels": "", "boulders": ""}

## Per table of the garden holding builds, the command that puts one back, in the order a snapshot rebuilds them.
const PUTS := {"stairs": "stairs", "paths": "path", "grounds": "ground", "walls": "wall", "easels": "easel", "decorations": "decoration", "boulders": "boulder"}

## Length of a stroke along the ground.
static func length(points: Variant) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += Vector2(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z).length()
	return total


## Walls, paths, easels, boulders and plant groups with anything standing.
static func _things(state: Dictionary) -> int:
	var n: int = state.stairs.size() + state.walls.size() + state.paths.size() + state.grounds.size() + state.easels.size() + state.boulders.size() + state.decorations.size()
	for g: Dictionary in state.groups.values():
		if g.kind != "meadow" and g.hidden.size() < g.size:
			n += 1
	return n


static func _unique(ids: PackedInt32Array) -> bool:
	var seen := {}
	for id in ids:
		seen[id] = true
	return seen.size() == ids.size()


static func clean(cmd: Dictionary, state: Dictionary, from_host: bool, ground: Terrain) -> Dictionary:
	var op: Variant = cmd.get("op")
	if not op in OPS:
		return {}
	var out := {"op": op}
	for k in ["seq", "by"]:
		if from_host:
			if typeof(cmd.get(k)) != TYPE_INT:
				return {}
			out[k] = cmd[k]
	if typeof(cmd.get("token")) == TYPE_INT:
		out.token = cmd.token
	if ((op in PUTS.values() and op != "wall") or op == "plant") and from_host:
		if typeof(cmd.get("id")) != TYPE_INT or state.groups.has(cmd.id) or state.paths.has(cmd.id) or state.grounds.has(cmd.id) or state.stairs.has(cmd.id) or state.easels.has(cmd.id) or state.boulders.has(cmd.id) or state.decorations.has(cmd.id):
			return {}
		out.id = cmd.id
	if (op in PUTS.values() or op == "plant") and not from_host and _things(state) >= MAX_THINGS:
		return {}
	var ok := false
	match op:
		"stairs":
			out.stairs = _stairs(cmd.get("stairs"))
			ok = out.stairs != null
			if ok and not from_host:
				out.stairs.on = PackedInt32Array(Array(out.stairs.on).filter(func(o: int) -> bool: return state.walls.has(o)))
		"wall":
			var ws: Variant = cmd.get("walls")
			ok = ws is Array and ws.size() >= 1 and ws.size() <= MAX_PIECES
			if ok:
				out.walls = ws.map(_wall)
				ok = not out.walls.has(null)
			if ok and from_host:
				var ids: Variant = cmd.get("ids")
				ok = typeof(ids) == TYPE_PACKED_INT32_ARRAY and ids.size() == ws.size() and _unique(ids) and not Array(ids).any(func(id: int) -> bool: return state.walls.has(id))
				out.ids = ids
				# A build stands only on older ones, so what stands on what never loops.
				for i in (ws.size() if ok else 0):
					ok = ok and Array(out.walls[i].on).all(func(o: int) -> bool: return o < ids[i])
			elif ok:
				for w: Dictionary in out.walls:
					w.on = PackedInt32Array(Array(w.on).filter(func(o: int) -> bool: return state.walls.has(o)))
		"take":
			var of: Variant = cmd.get("of")
			var ids: Variant = cmd.get("ids")
			ok = PUTS.has(of) and typeof(ids) == TYPE_PACKED_INT32_ARRAY and ids.size() >= 1 and ids.size() <= (MAX_PIECES if of == "walls" else 1) and _unique(ids) and Array(ids).all(func(id: int) -> bool: return state[of].has(id))
			out.of = of
			out.ids = ids
		"reshape":
			ok = RESHAPES.has(cmd.get("of")) and typeof(cmd.get("id")) == TYPE_INT and state[cmd.of].has(cmd.id) and cmd.get("data") is Dictionary
			if ok:
				out.of = cmd.of
				out.id = cmd.id
				out.data = _reshape(cmd.of, cmd.data, state[cmd.of][cmd.id])
				ok = out.data != null
			if ok and cmd.of == "easels" and not from_host:
				var others: Dictionary = state.easels.duplicate()
				others.erase(cmd.id)
				ok = Easels.room_at(out.data.get("at", state.easels[cmd.id].at), others)
		"path":
			out.path = _path(cmd.get("path"))
			ok = out.path != null and not (out.has("id") and state.paths.has(out.id))
		"ground":
			ok = _ground(cmd, out)
		"restone":
			ok = typeof(cmd.get("id")) == TYPE_INT and state.grounds.get(cmd.id, {}).has("style") and _stone_style(cmd.get("style"))
			out.id = cmd.get("id")
			out.style = cmd.get("style")
		"plant":
			ok = _plant(cmd, out, from_host)
		"show":
			ok = typeof(cmd.get("on")) == TYPE_BOOL and cmd.get("plants") is Dictionary and _show(cmd.plants, state, out)
			out.on = cmd.get("on")
		"tree":
			ok = _tree(cmd, state, out)
		"heights":
			ok = _heights(cmd, from_host, out) and _ponds(cmd, state, from_host, out)
		"ponds":
			var wet: Variant = cmd.get("wet", 0)
			ok = _ponds(cmd, state, from_host, out) and (from_host or out.has("put") and _pointed(out.put, state, ground))
			ok = ok and typeof(wet) == TYPE_INT and wet >= 0 and wet <= Terrain.ALL.get_area()
			out.wet = wet
		"season":
			var i: Variant = cmd.get("index")
			ok = typeof(i) == TYPE_INT and i >= 0 and i < Palette.SEASONS.size()
			out.index = i
		"sky":
			var t: Variant = cmd.get("time")
			ok = typeof(t) == TYPE_FLOAT and t >= 0.0 and t <= 1.0
			out.time = t
		"wipe":
			ok = true
		"garden":
			var cmds: Variant = cmd.get("cmds")
			ok = from_host and cmds is Array and cmds.size() <= MAX_SNAPSHOT
			out.cmds = cmds
		"batch":
			ok = _batch(cmd, state, from_host, out, ground)
		"easel":
			ok = _easel(cmd, state, from_host, out)
		"paint":
			ok = _surface(cmd, state, out)
			if ok:
				out.stroke = Brushwork.clean(cmd.get("stroke"))
				var strokes: Array = state.easels[out.easel][surface(out)]
				ok = out.stroke != null and strokes.size() < Brushwork.MAX_STROKES and _samples(strokes) + Brushwork.count(out.stroke) <= Brushwork.MAX_TOTAL
		"unpaint":
			ok = _surface(cmd, state, out) and not state.easels[out.easel][surface(out)].is_empty()
		"sheet":
			var e: Variant = cmd.get("easel")
			ok = typeof(e) == TYPE_INT and state.easels.has(e)
			if ok:
				out.easel = e
				out.strokes = _strokes(cmd.get("strokes"))
				ok = out.strokes != null and (from_host or out.strokes.is_empty())
		"decoration":
			var d: Variant = _decoration(cmd)
			ok = d != null and (from_host or d.wall < 0 or state.walls.has(d.wall) and _holds(state.walls[d.wall], d.mount))
			if ok:
				out.merge(d)
		"boulder":
			var b: Variant = _boulder(cmd)
			ok = b != null
			if ok:
				out.merge(b)
	return out if ok else {}


## Whether a wall offers the surface a mount stands on: a house for its floors, a flat roof for its deck.
static func _holds(wall: Dictionary, mount: String) -> bool:
	match mount:
		"floor":
			return wall.has("roof")
		"deck":
			return wall.has("roof") and wall.roof.pitch <= 0.0
	return true


## A decoration: the build it stands on (-1 for none), its mount, style and seed, where it stands and its turn, its
## place along its wall's foot, the lantern swatch its flames burn in, and on a span the far end `to` and the pole
## `drop` under each end.
static func _decoration(d: Dictionary) -> Variant:
	if typeof(d.get("wall")) != TYPE_INT or typeof(d.get("style")) != TYPE_INT or typeof(d.get("seed")) != TYPE_INT or typeof(d.get("lantern")) != TYPE_INT:
		return null
	if d.style < 0 or d.style >= DecorationLayout.STYLES.size() or not d.get("mount") in DecorationLayout.MOUNTS or (d.wall < 0) != (d.mount in ["ground", "span"]):
		return null
	if not DecorationLayout.stands(d.style, d.mount) or d.lantern < 0 or d.lantern >= Palette.count(Palette.Element.LANTERN):
		return null
	if typeof(d.get("at")) != TYPE_VECTOR3 or not _finite(d.at):
		return null
	for key in ["turn", "s", "side"]:
		if typeof(d.get(key)) != TYPE_FLOAT or not is_finite(d[key]):
			return null
	if d.s < 0.0 or d.s >= 4000.0 or absf(d.side) != 1.0:
		return null
	var out := {"wall": d.wall, "mount": d.mount, "style": d.style, "seed": d.seed, "at": d.at, "turn": d.turn, "s": d.s, "side": d.side, "lantern": d.lantern}
	if d.mount != "span":
		return out if not d.has("to") and not d.has("drop") else null
	if typeof(d.get("to")) != TYPE_VECTOR3 or not _finite(d.to) or typeof(d.get("drop")) != TYPE_VECTOR2 or not d.drop.is_finite():
		return null
	var span: Vector3 = d.to - d.at
	var run := Vector2(span.x, span.z).length()
	if run < DecorationLayout.SPAN_LEAST or run > DecorationLayout.SPAN_MOST or absf(span.y) > run * DecorationLayout.SPAN_STEEPEST:
		return null
	if not (d.drop.x >= 0.0 and d.drop.x <= DecorationLayout.POLE and d.drop.y >= 0.0 and d.drop.y <= DecorationLayout.POLE):
		return null
	out.to = d.to
	out.drop = d.drop
	return out


## A boulder: the ground point under its centre, which way it is turned, how far it is pushed into the ground, the seed
## its shape grows from, its size, its paint and its style.
static func _boulder(d: Dictionary) -> Variant:
	var at: Variant = d.get("at")
	var turn: Variant = d.get("turn")
	var scale: Variant = d.get("scale")
	var sink: Variant = d.get("sink")
	if typeof(sink) != TYPE_FLOAT or not (sink >= 0.0 and sink < INF):
		return null
	if typeof(at) != TYPE_VECTOR3 or not _finite(at) or typeof(d.get("seed")) != TYPE_INT or not Palette.valid(d.get("paint")):
		return null
	if typeof(turn) != TYPE_QUATERNION or not turn.is_finite() or absf(turn.length() - 1.0) > 1e-3:
		return null
	if typeof(scale) != TYPE_FLOAT or not (scale >= BoulderLayout.LEAST and scale <= BoulderLayout.MOST) or not _stone_style(d.get("style")):
		return null
	return {"at": at, "turn": turn.normalized(), "sink": sink, "seed": d.seed, "scale": scale, "paint": d.paint, "style": d.style}


## A new easel: where it stands and which way it faces, clear of the others; from the host, also the strokes on its
## canvas and its oil palette it comes back with when a taking is undone or a garden is rebuilt.
static func _easel(cmd: Dictionary, state: Dictionary, from_host: bool, out: Dictionary) -> bool:
	if not _stands(cmd) or not from_host and not Easels.room_at(cmd.at, state.easels):
		return false
	out.at = cmd.at
	out.yaw = cmd.yaw
	out.strokes = _strokes(cmd.get("strokes", []))
	out.palette = _strokes(cmd.get("palette", []))
	return out.strokes != null and out.palette != null and (from_host or (out.strokes.is_empty() and out.palette.is_empty()))


## Whether an easel's `at` and `yaw` in `d` are a place in the garden and a facing.
static func _stands(d: Dictionary) -> bool:
	var at: Variant = d.get("at")
	var yaw: Variant = d.get("yaw")
	return typeof(at) == TYPE_VECTOR3 and _finite(at) and typeof(yaw) == TYPE_FLOAT and is_finite(yaw) and absf(yaw) <= TAU


## The easel a stroke command paints on, standing, and whether on its canvas or (`palette`) its oil palette's board.
static func _surface(cmd: Dictionary, state: Dictionary, out: Dictionary) -> bool:
	var e: Variant = cmd.get("easel")
	var palette: Variant = cmd.get("palette", false)
	out.easel = e
	out.palette = palette
	return typeof(e) == TYPE_INT and state.easels.has(e) and typeof(palette) == TYPE_BOOL


## The field of an easel's record holding the strokes a clean stroke command `cmd` paints.
static func surface(cmd: Dictionary) -> String:
	return "palette" if cmd.palette else "strokes"


## A surface's strokes, each clean, within what one surface holds, or null.
static func _strokes(d: Variant) -> Variant:
	if not d is Array or d.size() > Brushwork.MAX_STROKES:
		return null
	var out := []
	for s: Variant in d:
		var kept: Variant = Brushwork.clean(s)
		if kept == null:
			return null
		out.append(kept)
	return out if _samples(out) <= Brushwork.MAX_TOTAL else null


static func _samples(strokes: Array) -> int:
	var n := 0
	for s: Dictionary in strokes:
		n += Brushwork.count(s)
	return n


## Each command of a batch is checked against the garden as it stands, so no two may change the same thing, and
## one batch takes at most MAX_BATCH things and, from a player, one `show`. From a player, a command that no longer
## applies (what it takes went meanwhile) is dropped and the rest stand; from the host, every one must apply.
static func _batch(cmd: Dictionary, state: Dictionary, from_host: bool, out: Dictionary, ground: Terrain) -> bool:
	var cmds: Variant = cmd.get("cmds")
	# The host's batches include undoing a build taken with all that stood on it, however much that was.
	var most := MAX_SNAPSHOT if from_host else MAX_BATCH
	if not cmds is Array or cmds.is_empty() or cmds.size() > most:
		return false
	var allowed := BATCHED + (PUTS.values() + HOST_BATCHED if from_host else [])
	var seen := {}
	out.cmds = []
	for c: Variant in cmds:
		if not c is Dictionary or not c.get("op") in allowed:
			return false
		var one: Dictionary = c.duplicate()
		one.erase("token")
		if from_host:
			one.seq = cmd.seq
			one.by = cmd.by
		var kept := clean(one, state, from_host, ground)
		if kept.is_empty():
			if from_host:
				return false
			continue
		for k in ["seq", "by"]:
			kept.erase(k)
		# The host's undo of a drowning shows plants again beside what it undoes, which may itself show some.
		var ids: Array = Array(kept.ids) if kept.has("ids") else ([kept.id] if kept.has("id") else ([] if from_host and kept.op == "show" else [-1]))
		for id: int in ids:
			var key := "%s%d" % ["w" if kept.op == "wall" or kept.get("of") == "walls" else ("e" if kept.op == "easel" or kept.get("of") == "easels" else ("q" if id >= 0 else kept.op)), id]
			if seen.has(key):
				return false
			seen[key] = true
		out.cmds.append(kept)
	return not out.cmds.is_empty() and seen.size() <= most


static func _finite(v: Vector3) -> bool:
	return v.is_finite() and Terrain.ROOM.has_point(v)


static func _in(x: Variant, range: Vector2) -> bool:
	return typeof(x) == TYPE_FLOAT and x >= range.x and x <= range.y


static func _at_least(x: Variant, low: float) -> bool:
	return typeof(x) == TYPE_FLOAT and is_finite(x) and x >= low


static func _wall(d: Variant) -> Variant:
	if not d is Dictionary:
		return null
	var points: Variant = d.get("points")
	if typeof(points) != TYPE_PACKED_VECTOR3_ARRAY or points.size() < 2 or points.size() > MAX_POINTS or not Array(points).all(_finite) or length(points) > MAX_LENGTH:
		return null
	if not _at_least(d.get("height"), WallLayout.MIN_HEIGHT) or typeof(d.get("seed")) != TYPE_INT or typeof(d.get("closed")) != TYPE_BOOL:
		return null
	var rise: Variant = d.get("rise")
	if not _at_least(rise, 0.0) or (rise > 0.0 and not d.closed):
		return null
	var top: Variant = d.get("top")
	if typeof(top) != TYPE_INT or top < 0 or top >= WallLayout.Top.size():
		return null
	if typeof(d.get("fence")) != TYPE_BOOL:
		return null
	var finish: Variant = d.get("finish")
	if typeof(finish) != TYPE_INT or finish < 0 or finish >= WallLayout.Finish.size() or not WallLayout.suits(finish, d.fence):
		return null
	var wear: Variant = d.get("wear")
	if not _in(wear, Vector2(0.0, 1.0)) or (wear > 0.0 and finish != WallLayout.Finish.PLASTER):
		return null
	var foundation: Variant = d.get("foundation")
	if typeof(foundation) != TYPE_INT or foundation < 0 or foundation >= WallLayout.Foundation.size() or (foundation != WallLayout.Foundation.STONE and d.fence):
		return null
	if foundation > WallLayout.Foundation.PLASTER and not d.closed:
		return null
	var planks: Variant = d.get("planks")
	if typeof(planks) != TYPE_BOOL:
		return null
	var gable_end: Variant = d.get("gable_end")
	if typeof(gable_end) != TYPE_INT or gable_end < 0 or gable_end >= WallLayout.GableEnd.size():
		return null
	var openings: Variant = d.get("openings")
	var lanterns: Variant = d.get("lanterns")
	var flags: Variant = d.get("flags")
	if typeof(openings) != TYPE_PACKED_VECTOR4_ARRAY or openings.size() > MAX_FITTINGS or not Array(openings).all(func(w: Vector4) -> bool: return w.is_finite() and w.x >= 0.0 and w.x < 4000.0 and w.y >= 0.0 and w.z == floorf(w.z) and w.z >= 0.0 and w.z < WallLayout.Family.size() and w.w >= WallLayout.MIN_SIZE):
		return null
	if typeof(lanterns) != TYPE_PACKED_VECTOR3_ARRAY or lanterns.size() > MAX_FITTINGS or not Array(lanterns).all(func(l: Vector3) -> bool: return l.is_finite() and l.x >= 0.0 and l.x < 4000.0 and l.y >= 0.0 and absf(l.z) == 1.0):
		return null
	if typeof(flags) != TYPE_PACKED_FLOAT32_ARRAY or flags.size() > MAX_FITTINGS or not Array(flags).all(func(f: float) -> bool: return is_finite(f) and f >= 0.0 and f < 4000.0):
		return null
	if d.fence and not (Array(openings).all(func(o): return o.z == WallLayout.Family.ARCHWAY and o.w == 1.0) and flags.is_empty()):
		return null
	var ruins: Variant = d.get("ruins")
	if typeof(ruins) != TYPE_PACKED_VECTOR2_ARRAY or ruins.size() > MAX_RUINS or not Array(ruins).all(func(r: Vector2) -> bool: return r.is_finite() and r.x >= 0.0 and r.y > r.x and r.y < 4000.0):
		return null
	if not ruins.is_empty() and (d.fence or d.has("roof")):
		return null
	var on: Variant = d.get("on")
	if typeof(on) != TYPE_PACKED_INT32_ARRAY or on.size() > MAX_SUPPORTS or not _unique(on):
		return null
	var paint: Variant = d.get("paint")
	if not Palette.valid(paint):
		return null
	var clutter: Variant = _clutter(d)
	if clutter == null or d.fence and not clutter.is_empty():
		return null
	var out := {"points": points, "height": d.height, "rise": rise, "seed": d.seed, "closed": d.closed, "top": top, "fence": d.fence, "openings": openings, "lanterns": lanterns, "flags": flags, "clutter": clutter, "ruins": ruins, "finish": finish, "wear": wear, "foundation": foundation, "planks": planks, "gable_end": gable_end, "on": on, "paint": paint}
	if d.has("roof"):
		var r: Variant = d.roof
		if not r is Dictionary or typeof(r.get("kind")) != TYPE_INT or r.kind < 0 or r.kind >= RoofLayout.Kind.size():
			return null
		if typeof(r.get("center")) != TYPE_VECTOR3 or not _finite(r.center) or not _at_least(r.get("radius"), MIN_ROOF_RADIUS) or typeof(r.get("seed")) != TYPE_INT:
			return null
		if not _at_least(r.get("pitch"), 0.0) or not _at_least(r.get("curve"), -RoofLayout.CURVE) or r.curve > RoofLayout.CURVE:
			return null
		var chimneys: Variant = r.get("chimneys")
		if typeof(chimneys) != TYPE_PACKED_VECTOR2_ARRAY or chimneys.size() > MAX_CHIMNEYS or not Array(chimneys).all(func(c: Vector2) -> bool: return c.is_finite() and absf(c.x) < 40.0 and absf(c.y) < 40.0) or typeof(r.get("flag")) != TYPE_BOOL:
			return null
		var dormers: Variant = r.get("dormers")
		if typeof(dormers) != TYPE_PACKED_VECTOR2_ARRAY or dormers.size() > MAX_DORMERS or not Array(dormers).all(func(c: Vector2) -> bool: return c.is_finite() and absf(c.x) < 40.0 and absf(c.y) < 40.0):
			return null
		if r.kind == RoofLayout.Kind.CONE and not dormers.is_empty():
			return null
		var hatches: Variant = r.get("hatches")
		if typeof(hatches) != TYPE_PACKED_VECTOR2_ARRAY or hatches.size() > MAX_HATCHES or not Array(hatches).all(func(c: Vector2) -> bool: return c.is_finite() and absf(c.x) < 40.0 and absf(c.y) < 40.0):
			return null
		if not _at_least(r.get("overhang"), 0.0) or r.overhang > RoofLayout.MAX_OVERHANG:
			return null
		if typeof(r.get("deck")) != TYPE_INT or r.deck < 0 or r.deck >= RoofLayout.Deck.size():
			return null
		if typeof(r.get("thatch")) != TYPE_BOOL:
			return null
		if r.kind == RoofLayout.Kind.CONE:
			out.finish = WallLayout.Finish.BARE
			out.wear = 0.0
		out.roof = {"kind": r.kind, "center": r.center, "radius": r.radius, "pitch": r.pitch, "curve": r.curve, "seed": r.seed, "chimneys": chimneys, "dormers": dormers, "hatches": hatches, "overhang": r.overhang, "deck": r.deck, "flag": r.flag, "thatch": r.thatch}
	return out


## A build's changed fields, each as valid as in a whole build of its kind (`of`, the garden's table of them): a copy
## of it with them applied must pass.
static func _reshape(of: String, d: Dictionary, now: Dictionary) -> Variant:
	if d.is_empty():
		return null
	var out := {}
	var trial := now.duplicate(true)
	for k in d:
		# A peer re-checks what the host cleaned, so keys stay Strings: `out.roof = ` would store a StringName.
		if typeof(k) != TYPE_STRING:
			return null
		if k in RESHAPES[of]:
			out[k] = d[k]
			trial[k] = d[k]
		elif k == "roof" and now.has("roof") and d.roof is Dictionary and not d.roof.is_empty():
			out[k] = {}
			for r in d.roof:
				if typeof(r) != TYPE_STRING or not r in ["kind", "center", "radius", "pitch", "curve", "chimneys", "dormers", "hatches", "overhang", "deck", "flag", "thatch"]:
					return null
				out[k][r] = d.roof[r]
				trial.roof[r] = d.roof[r]
		elif k == "paint" and d.paint is Dictionary and not d.paint.is_empty():
			out[k] = {}
			trial.paint = PackedInt32Array(trial.paint)
			for e in d.paint:
				if typeof(e) != TYPE_INT or not Palette.SWATCHES.has(e) or typeof(d.paint[e]) != TYPE_INT:
					return null
				out[k][e] = d.paint[e]
				trial.paint[e] = d.paint[e]
		else:
			return null
	var cleaned: Variant = _whole(of, trial)
	if cleaned == null:
		return null
	if of == "walls":
		for k in ["finish", "wear"]:
			if cleaned[k] != trial[k]:
				out[k] = cleaned[k]
	return out


## A build of the garden's table `of` checked whole: a clean copy of it, or null.
static func _whole(of: String, d: Dictionary) -> Variant:
	match of:
		"walls":
			return _wall(d)
		"stairs":
			return _stairs(d)
		"decorations":
			return _decoration(d)
		"easels":
			return d if _stands(d) else null
		"paths":
			return _path(d)
	return _boulder(d)


static func _path(d: Variant) -> Variant:
	if not d is Dictionary or d.size() != (5 if d.has("clutter") else 4) or typeof(d.get("seed")) != TYPE_INT:
		return null
	var clutter: Variant = _clutter(d)
	if clutter == null:
		return null
	var surface: Variant = d.get("surface")
	if typeof(surface) != TYPE_INT or surface < 0 or surface >= PathLayout.Surface.size():
		return null
	var points: Variant = d.get("points")
	var halves: Variant = d.get("half_widths")
	if typeof(points) != TYPE_PACKED_VECTOR3_ARRAY or points.size() < 2 or points.size() > MAX_PATH_POINTS or not Array(points).all(_finite) or length(points) > MAX_LENGTH:
		return null
	if typeof(halves) != TYPE_PACKED_FLOAT32_ARRAY or halves.size() != points.size() or not Array(halves).all(func(h: float) -> bool: return h >= PathLayout.HALF_WIDTH.x - 0.001 and h <= PathLayout.HALF_WIDTH.y + 0.001):
		return null
	return {"points": points, "half_widths": halves, "seed": d.seed, "surface": surface, "clutter": clutter}


## A build's clutter (ClutterLayout), none if it carries no list, or null for a list no hand could leave.
static func _clutter(d: Dictionary) -> Variant:
	var list: Variant = d.get("clutter", PackedVector4Array())
	if typeof(list) != TYPE_PACKED_VECTOR4_ARRAY or list.size() > ClutterLayout.MOST or not Array(list).all(ClutterLayout.valid):
		return null
	return list


static func _ground(cmd: Dictionary, out: Dictionary) -> bool:
	var kind: Variant = cmd.get("kind")
	var stamps: Variant = cmd.get("stamps")
	if typeof(kind) != TYPE_INT or not kind in [Ground.Kind.MEADOW, Ground.Kind.STONE]:
		return false
	if typeof(stamps) != TYPE_PACKED_VECTOR4_ARRAY or stamps.is_empty() or stamps.size() > MAX_STAMPS:
		return false
	var radius := Vector2(FloraTool.MIN_RADIUS * 0.4, FloraTool.MAX_RADIUS * 0.4)
	for s: Vector4 in stamps:
		if not (s.is_finite() and _finite(Vector3(s.x, 0, s.y)) and s.z >= radius.x - 0.001 and s.z <= radius.y + 0.001 and s.w >= radius.x * 2.0 - 0.001 and s.w <= radius.y * 2.0 + 0.001):
			return false
	out.kind = kind
	out.stamps = stamps
	if kind == Ground.Kind.STONE:
		out.style = cmd.get("style")
		return _stone_style(out.style)
	return true


static func _stone_style(style: Variant) -> bool:
	return typeof(style) == TYPE_INT and style >= 0 and style < StoneStyles.STYLES.size()


static func _plant(cmd: Dictionary, out: Dictionary, from_host: bool) -> bool:
	if typeof(cmd.get("seed")) != TYPE_INT:
		return false
	out.seed = cmd.seed
	out.kind = cmd.get("kind")
	if typeof(out.kind) != TYPE_STRING:
		return false
	if out.kind in Flora.PLACED:
		out.at = cmd.get("at")
		return typeof(out.at) == TYPE_VECTOR3 and _finite(out.at)
	var dabs: Variant = cmd.get("dabs")
	if not out.kind in Flora.BRUSHES or not dabs is Array or dabs.is_empty() or dabs.size() > MAX_DABS:
		return false
	var total := 0
	for d: Variant in dabs:
		if not d is Array or d.size() != 3 or typeof(d[0]) != TYPE_VECTOR3 or not _finite(d[0]) or not _in(d[1], Vector2(FloraTool.MIN_RADIUS, FloraTool.MAX_RADIUS)) or typeof(d[2]) != TYPE_INT or d[2] < 1 or d[2] > MAX_STROKE:
			return false
		total += d[2]
		if total > MAX_STROKE:
			return false
	out.dabs = dabs.map(func(d: Array) -> Array: return [d[0], d[1], d[2]])
	if cmd.has("skip") and from_host:
		var skip: Variant = cmd.skip
		if typeof(skip) != TYPE_PACKED_INT32_ARRAY or skip.size() > total or not Array(skip).all(func(i: int) -> bool: return i >= 0 and i < total):
			return false
		out.skip = skip
	return total <= MAX_STROKE


static func _show(plants: Dictionary, state: Dictionary, out: Dictionary) -> bool:
	out.plants = {}
	for g: Variant in plants:
		var at: Variant = plants[g]
		if typeof(g) != TYPE_INT or not state.groups.has(g) or typeof(at) != TYPE_PACKED_INT32_ARRAY:
			return false
		var size: int = state.groups[g].size
		if at.size() > size or not Array(at).all(func(i: int) -> bool: return i >= 0 and i < size):
			return false
		out.plants[g] = at
	return true


## Where a tree or bush stands across the ground (`at`) and its turn about its foot from how it grew (`turn`), and a
## tree's species, scale and bark moss: a planted tree or bush is its group's first plant, a meadow tree one of the
## meadow group's `trees`, a meadow bush one of its `bushes`.
static func _tree(cmd: Dictionary, state: Dictionary, out: Dictionary) -> bool:
	var g: Variant = cmd.get("group")
	var i: Variant = cmd.get("index")
	if typeof(g) != TYPE_INT or typeof(i) != TYPE_INT or not state.groups.has(g):
		return false
	var group: Dictionary = state.groups[g]
	var tree: bool = i == 0 if group.kind == "tree" else group.get("trees", PackedInt32Array()).has(i)
	var bush: bool = i == 0 if group.kind == "bush" else group.get("bushes", PackedInt32Array()).has(i)
	if not tree and (not bush or cmd.has("species") or cmd.has("scale") or cmd.has("moss")):
		return false
	if cmd.has("at"):
		if typeof(cmd.at) != TYPE_VECTOR3 or not _finite(cmd.at):
			return false
		out.at = cmd.at
	if cmd.has("turn"):
		if typeof(cmd.turn) != TYPE_FLOAT or not is_finite(cmd.turn):
			return false
		out.turn = wrapf(cmd.turn, -PI, PI)
	if cmd.has("species"):
		var species: Variant = cmd.species
		if typeof(species) != TYPE_INT or species < 0 or species >= FloraLayout.Species.size():
			return false
		out.species = species
	if cmd.has("scale"):
		var scale: Variant = cmd.scale
		if typeof(scale) != TYPE_FLOAT or not (scale >= FloraLayout.SCALES.x and scale <= FloraLayout.SCALES.y):
			return false
		out.scale = scale
	if cmd.has("moss"):
		if typeof(cmd.moss) != TYPE_BOOL:
			return false
		out.moss = cmd.moss
	out.group = g
	out.index = i
	return out.has("at") or out.has("turn") or out.has("species") or out.has("scale") or out.has("moss")


static func _heights(cmd: Dictionary, from_host: bool, out: Dictionary) -> bool:
	var cells: Variant = cmd.get("cells")
	var values: Variant = cmd.get("values")
	if typeof(cells) != TYPE_RECT2I or typeof(values) != TYPE_PACKED_FLOAT32_ARRAY:
		return false
	if cells.size.x < 1 or cells.size.y < 1 or not Rect2i(0, 0, Terrain.VERTS, Terrain.VERTS).encloses(cells) or values.size() != cells.get_area():
		return false
	for v in values:
		if not absf(v) <= Terrain.RELIEF:
			return false
	out.cells = cells
	out.values = values
	return true


## Ponds a command puts at their levels, by the grid point each fills from, and ponds it takes out: only the host's
## commands, which undo or rebuild, carry them, except a player's one pond put by the pond tool.
static func _ponds(cmd: Dictionary, state: Dictionary, from_host: bool, out: Dictionary) -> bool:
	var put: Variant = cmd.get("put", {})
	var drop: Variant = cmd.get("drop", [])
	if not put is Dictionary or not drop is Array or put.size() > MAX_PONDS or drop.size() > MAX_PONDS:
		return false
	if not from_host and (not drop.is_empty() or put.size() > int(cmd.op == "ponds")):
		return false
	for g: Variant in put:
		var level: Variant = put[g]
		if typeof(g) != TYPE_VECTOR2I or not Terrain.ALL.has_point(g) or typeof(level) != TYPE_FLOAT or not is_finite(level):
			return false
	for g: Variant in drop:
		if typeof(g) != TYPE_VECTOR2I or not state.ponds.has(g) or put.has(g):
			return false
	if not put.is_empty():
		out.put = put.duplicate()
	if not drop.is_empty():
		out.drop = drop.duplicate()
	return true


## Whether a player's pond holds water over the ground as it stands, and the garden has room for it.
static func _pointed(put: Dictionary, state: Dictionary, ground: Terrain) -> bool:
	var g: Vector2i = put.keys()[0]
	return (state.ponds.has(g) or state.ponds.size() < MAX_PONDS) and Water.fill(ground, g, put[g]) != null


static func _stairs(d: Variant) -> Variant:
	if not d is Dictionary:
		return null
	for key in ["a", "b"]:
		if typeof(d.get(key)) != TYPE_VECTOR3 or not _finite(d[key]):
			return null
	var length: float = d.a.distance_to(d.b)
	if length < 0.3 or length > MAX_LENGTH or not _in(d.get("width"), StairLayout.WIDTH) or not _in(d.get("sag"), Vector2(0.0, StairLayout.SAG_MOST)) or not StairLayout.sag_fits(d.a, d.b, d.sag):
		return null
	if typeof(d.get("seed")) != TYPE_INT or not d.get("rail") in StairLayout.RAILS or not Palette.valid(d.get("paint")):
		return null
	var on: Variant = d.get("on")
	if typeof(on) != TYPE_PACKED_INT32_ARRAY or on.size() > MAX_SUPPORTS or not _unique(on):
		return null
	return {"a": d.a, "b": d.b, "width": d.width, "sag": d.sag, "seed": d.seed, "rail": d.rail, "paint": d.paint, "on": on}
