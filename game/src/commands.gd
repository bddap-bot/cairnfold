class_name Commands
extends RefCounted

## The build commands' one schema. `clean` returns a fresh command holding only the fields its op
## defines, each checked for type and range against what a tool can make, or {} for anything else:
## every machine runs it on every command it is handed, so a peer cannot wedge or corrupt a garden.

const OPS := ["stairs", "unstairs", "wall", "unwall", "reshape", "path", "unpath", "ground", "unground", "plant", "show", "tree", "heights", "ponds", "season", "sky", "wipe", "garden", "batch", "easel", "uneasel", "paint", "unpaint", "mix", "sheet", "restone"]
## What a batch may carry: from a player, takings; from the host, also the undo of them.
const BATCHED := ["unstairs", "unwall", "reshape", "unpath", "unground", "show", "uneasel"]
const UNBATCHED := ["stairs", "wall", "path", "ground", "easel"]
## Most commands one batch carries.
const MAX_BATCH := 128
## A stroke builds at most this many walls; their ids follow from the command's sequence number.
const MAX_PIECES := 8
const MAX_POINTS := 256
const MAX_PATH_POINTS := 2048
const MAX_ARCHES := 16
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
const MAX_RUINS := 32
## Most commands a snapshot holds: per thing one, and per plant group one more for its hidden plants.
const MAX_SNAPSHOT := MAX_THINGS * 2 + 64
## Most builds one build stands on.
const MAX_SUPPORTS := 8
## What a `reshape` may change, by the garden's table of the builds it changes; `paint` and a wall's `roof` change
## by the entries they name.
const RESHAPES := {
	"walls": ["points", "height", "rise", "top", "plaster", "gable_end", "timber_style", "storey_floors", "arches", "windows", "lanterns", "flags", "ruins"],
	"stairs": ["rail"],
}


## Length of a stroke along the ground.
static func length(points: Variant) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += Vector2(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z).length()
	return total


## Walls, paths, easels and plant groups with anything standing.
static func _things(state: Dictionary) -> int:
	var n: int = state.stairs.size() + state.walls.size() + state.paths.size() + state.grounds.size() + state.easels.size()
	for g: Dictionary in state.groups.values():
		if g.kind != "meadow" and g.hidden.size() < g.size:
			n += 1
	return n


static func _unique(ids: PackedInt32Array) -> bool:
	var seen := {}
	for id in ids:
		seen[id] = true
	return seen.size() == ids.size()


static func clean(cmd: Dictionary, state: Dictionary, from_host: bool) -> Dictionary:
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
	if op in ["stairs", "plant", "path", "ground", "easel"] and from_host:
		if typeof(cmd.get("id")) != TYPE_INT or state.groups.has(cmd.id) or state.paths.has(cmd.id) or state.grounds.has(cmd.id) or state.stairs.has(cmd.id) or state.easels.has(cmd.id):
			return {}
		out.id = cmd.id
	if op in ["stairs", "wall", "path", "ground", "plant", "easel"] and not from_host and _things(state) >= MAX_THINGS:
		return {}
	var ok := false
	match op:
		"stairs":
			out.stairs = _stairs(cmd.get("stairs"))
			ok = out.stairs != null
		"unstairs":
			ok = typeof(cmd.get("id")) == TYPE_INT and state.stairs.has(cmd.id)
			out.id = cmd.get("id")
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
		"unwall":
			var ids: Variant = cmd.get("ids")
			ok = typeof(ids) == TYPE_PACKED_INT32_ARRAY and ids.size() >= 1 and ids.size() <= MAX_PIECES and _unique(ids) and Array(ids).all(func(id: int) -> bool: return state.walls.has(id))
			out.ids = ids
		"reshape":
			ok = RESHAPES.has(cmd.get("of")) and typeof(cmd.get("id")) == TYPE_INT and state[cmd.of].has(cmd.id) and cmd.get("data") is Dictionary
			if ok:
				out.of = cmd.of
				out.id = cmd.id
				out.data = _reshape(cmd.of, cmd.data, state[cmd.of][cmd.id])
				ok = out.data != null
		"path":
			out.path = _path(cmd.get("path"))
			ok = out.path != null and not (out.has("id") and state.paths.has(out.id))
		"unpath":
			ok = typeof(cmd.get("id")) == TYPE_INT and state.paths.has(cmd.id)
			out.id = cmd.get("id")
		"ground":
			ok = _ground(cmd, out)
		"unground":
			ok = typeof(cmd.get("id")) == TYPE_INT and state.grounds.has(cmd.id)
			out.id = cmd.get("id")
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
			ok = _ponds(cmd, state, from_host, out) and (from_host or out.has("put") and _pointed(out.put, state))
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
			ok = _batch(cmd, state, from_host, out)
		"easel":
			ok = _easel(cmd, state, from_host, out)
		"uneasel":
			ok = typeof(cmd.get("id")) == TYPE_INT and state.easels.has(cmd.id)
			out.id = cmd.get("id")
		"paint":
			var e: Variant = cmd.get("easel")
			ok = typeof(e) == TYPE_INT and state.easels.has(e)
			if ok:
				out.easel = e
				out.stroke = Brushwork.clean(cmd.get("stroke"))
				var strokes: Array = state.easels[e].strokes
				ok = out.stroke != null and strokes.size() < Brushwork.MAX_STROKES and _samples(strokes) + Brushwork.count(out.stroke) <= Brushwork.MAX_TOTAL
		"mix":
			var e: Variant = cmd.get("easel")
			var mix: Variant = cmd.get("mix")
			ok = typeof(e) == TYPE_INT and state.easels.has(e) and _mix(mix)
			out.easel = e
			out.mix = mix
		"unpaint":
			var e: Variant = cmd.get("easel")
			ok = typeof(e) == TYPE_INT and state.easels.has(e) and not state.easels[e].strokes.is_empty()
			out.easel = e
		"sheet":
			var e: Variant = cmd.get("easel")
			ok = typeof(e) == TYPE_INT and state.easels.has(e)
			if ok:
				out.easel = e
				out.strokes = _strokes(cmd.get("strokes"))
				ok = out.strokes != null and (from_host or out.strokes.is_empty())
	return out if ok else {}


## A new easel: where it stands and which way it faces, clear of the others; from the host, also the strokes and
## mixing field it comes back with when a taking is undone or a garden is rebuilt.
static func _easel(cmd: Dictionary, state: Dictionary, from_host: bool, out: Dictionary) -> bool:
	var at: Variant = cmd.get("at")
	var yaw: Variant = cmd.get("yaw")
	if typeof(at) != TYPE_VECTOR3 or not _finite(at) or typeof(yaw) != TYPE_FLOAT or not is_finite(yaw) or absf(yaw) > TAU:
		return false
	if not from_host and not Easels.room_at(at, state.easels):
		return false
	out.at = at
	out.yaw = yaw
	out.strokes = _strokes(cmd.get("strokes", []))
	out.mix = cmd.get("mix", PackedByteArray())
	return out.strokes != null and _mix(out.mix) and (from_host or (out.strokes.is_empty() and out.mix.is_empty()))


## An oil palette's mixing field: empty, or one as `Mixing.bytes` holds it.
static func _mix(d: Variant) -> bool:
	return d is PackedByteArray and (d.is_empty() or d.size() == Mixing.SIZE.x * Mixing.SIZE.y * 4)


## A canvas's strokes, each clean, within what one canvas holds, or null.
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
## one batch takes at most MAX_BATCH things and one `show`. From a player, a command that no longer applies (what it
## takes went meanwhile) is dropped and the rest stand; from the host, every one must apply.
static func _batch(cmd: Dictionary, state: Dictionary, from_host: bool, out: Dictionary) -> bool:
	var cmds: Variant = cmd.get("cmds")
	if not cmds is Array or cmds.is_empty() or cmds.size() > MAX_BATCH:
		return false
	var allowed := BATCHED + (UNBATCHED if from_host else [])
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
		var kept := clean(one, state, from_host)
		if kept.is_empty():
			if from_host:
				return false
			continue
		for k in ["seq", "by"]:
			kept.erase(k)
		var ids: Array = Array(kept.ids) if kept.has("ids") else ([kept.id] if kept.has("id") else [-1])
		for id: int in ids:
			var key := "%s%d" % ["w" if kept.op in ["wall", "unwall"] or kept.get("of") == "walls" else ("e" if kept.op in ["easel", "uneasel"] else ("q" if id >= 0 else "show")), id]
			if seen.has(key):
				return false
			seen[key] = true
		out.cmds.append(kept)
	return not out.cmds.is_empty() and seen.size() <= MAX_BATCH


static func _finite(v: Vector3) -> bool:
	return v.is_finite() and Terrain.bounds().has_point(v)


static func _in(x: Variant, range: Vector2) -> bool:
	return typeof(x) == TYPE_FLOAT and x >= range.x and x <= range.y


static func _at_least(x: Variant, low: float) -> bool:
	return typeof(x) == TYPE_FLOAT and is_finite(x) and x >= low


static func _wall(d: Variant) -> Variant:
	if not d is Dictionary:
		return null
	var points: Variant = d.get("points")
	var arches: Variant = d.get("arches")
	if typeof(points) != TYPE_PACKED_VECTOR3_ARRAY or points.size() < 2 or points.size() > MAX_POINTS or not Array(points).all(_finite) or length(points) > MAX_LENGTH:
		return null
	if typeof(arches) != TYPE_PACKED_FLOAT32_ARRAY or arches.size() > MAX_ARCHES or not Array(arches).all(func(a: float) -> bool: return is_finite(a) and a >= 0.0 and a < 4000.0):
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
	var plaster: Variant = d.get("plaster")
	if typeof(plaster) != TYPE_BOOL or (plaster and d.fence):
		return null
	var timber_style: Variant = d.get("timber_style")
	if typeof(timber_style) != TYPE_INT or timber_style < -1:
		return null
	timber_style = mini(timber_style, 0)
	if typeof(d.get("storey_floors")) != TYPE_BOOL:
		return null
	var gable_end: Variant = d.get("gable_end")
	if typeof(gable_end) != TYPE_INT or gable_end < 0 or gable_end >= WallLayout.GableEnd.size():
		return null
	var windows: Variant = d.get("windows")
	var lanterns: Variant = d.get("lanterns")
	var flags: Variant = d.get("flags")
	if typeof(windows) != TYPE_PACKED_VECTOR2_ARRAY or windows.size() > MAX_FITTINGS or not Array(windows).all(func(w: Vector2) -> bool: return w.is_finite() and w.x >= 0.0 and w.x < 4000.0 and w.y >= 0.0):
		return null
	if typeof(lanterns) != TYPE_PACKED_VECTOR3_ARRAY or lanterns.size() > MAX_FITTINGS or not Array(lanterns).all(func(l: Vector3) -> bool: return l.is_finite() and l.x >= 0.0 and l.x < 4000.0 and l.y >= 0.0 and absf(l.z) == 1.0):
		return null
	if typeof(flags) != TYPE_PACKED_FLOAT32_ARRAY or flags.size() > MAX_FITTINGS or not Array(flags).all(func(f: float) -> bool: return is_finite(f) and f >= 0.0 and f < 4000.0):
		return null
	if d.fence and not (windows.is_empty() and flags.is_empty()):
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
	var out := {"points": points, "height": d.height, "rise": rise, "arches": arches, "seed": d.seed, "closed": d.closed, "top": top, "fence": d.fence, "windows": windows, "lanterns": lanterns, "flags": flags, "ruins": ruins, "plaster": plaster, "gable_end": gable_end, "timber_style": timber_style, "storey_floors": d.storey_floors, "on": on, "paint": paint}
	if d.has("roof"):
		var r: Variant = d.roof
		if not r is Dictionary or typeof(r.get("kind")) != TYPE_INT or r.kind < 0 or r.kind >= RoofLayout.Kind.size():
			return null
		if typeof(r.get("center")) != TYPE_VECTOR3 or not _finite(r.center) or not _at_least(r.get("radius"), MIN_ROOF_RADIUS) or typeof(r.get("seed")) != TYPE_INT:
			return null
		if not _in(r.get("pitch"), RoofLayout.PITCH) or not _in(r.get("curve"), Vector2(-RoofLayout.CURVE, RoofLayout.CURVE)):
			return null
		var chimneys: Variant = r.get("chimneys")
		if typeof(chimneys) != TYPE_PACKED_VECTOR2_ARRAY or chimneys.size() > MAX_CHIMNEYS or not Array(chimneys).all(func(c: Vector2) -> bool: return c.is_finite() and absf(c.x) < 40.0 and absf(c.y) < 40.0) or typeof(r.get("flag")) != TYPE_BOOL:
			return null
		if typeof(r.get("thatch")) != TYPE_BOOL:
			return null
		out.plaster = plaster and r.kind != RoofLayout.Kind.CONE
		out.roof = {"kind": r.kind, "center": r.center, "radius": r.radius, "pitch": r.pitch, "curve": r.curve, "seed": r.seed, "chimneys": chimneys, "flag": r.flag, "thatch": r.thatch}
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
				if typeof(r) != TYPE_STRING or not r in ["kind", "center", "radius", "pitch", "curve", "chimneys", "flag", "thatch"]:
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
	var cleaned: Variant = _wall(trial) if of == "walls" else _stairs(trial)
	if cleaned == null:
		return null
	if of == "walls" and cleaned.plaster != trial.plaster:
		out["plaster"] = cleaned.plaster
	return out


static func _path(d: Variant) -> Variant:
	if not d is Dictionary or typeof(d.get("seed")) != TYPE_INT:
		return null
	var points: Variant = d.get("points")
	var halves: Variant = d.get("half_widths")
	if typeof(points) != TYPE_PACKED_VECTOR3_ARRAY or points.size() < 2 or points.size() > MAX_PATH_POINTS or not Array(points).all(_finite) or length(points) > MAX_LENGTH:
		return null
	if typeof(halves) != TYPE_PACKED_FLOAT32_ARRAY or halves.size() != points.size() or not Array(halves).all(func(h: float) -> bool: return h >= PathLayout.HALF_WIDTH.x - 0.001 and h <= PathLayout.HALF_WIDTH.y + 0.001):
		return null
	var style: Variant = d.get("style")
	if not style in ["cobble", "dirt"]:
		return null
	return {"points": points, "half_widths": halves, "seed": d.seed, "style": style}


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


## A tree's species, its scale or both: a planted tree is its group's first plant, a meadow tree one of the meadow
## group's `trees`.
static func _tree(cmd: Dictionary, state: Dictionary, out: Dictionary) -> bool:
	var g: Variant = cmd.get("group")
	var i: Variant = cmd.get("index")
	if typeof(g) != TYPE_INT or typeof(i) != TYPE_INT or not state.groups.has(g):
		return false
	var group: Dictionary = state.groups[g]
	if not (i == 0 if group.kind == "tree" else group.get("trees", PackedInt32Array()).has(i)):
		return false
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
	out.group = g
	out.index = i
	return out.has("species") or out.has("scale")


static func _heights(cmd: Dictionary, from_host: bool, out: Dictionary) -> bool:
	var cells: Variant = cmd.get("cells")
	var values: Variant = cmd.get("values")
	if typeof(cells) != TYPE_RECT2I or typeof(values) != TYPE_PACKED_FLOAT32_ARRAY:
		return false
	if cells.size.x < 1 or cells.size.y < 1 or not Rect2i(0, 0, Terrain.VERTS, Terrain.VERTS).encloses(cells) or values.size() != cells.get_area():
		return false
	for v in values:
		if not is_finite(v):
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
static func _pointed(put: Dictionary, state: Dictionary) -> bool:
	var g: Vector2i = put.keys()[0]
	return (state.ponds.has(g) or state.ponds.size() < MAX_PONDS) and Water.fill(g, put[g]) != null


static func _stairs(d: Variant) -> Variant:
	if not d is Dictionary:
		return null
	for key in ["a", "b"]:
		if typeof(d.get(key)) != TYPE_VECTOR3 or not _finite(d[key]):
			return null
	var length: float = d.a.distance_to(d.b)
	if length < 0.3 or length > MAX_LENGTH or not _in(d.get("width"), StairLayout.WIDTH):
		return null
	if typeof(d.get("seed")) != TYPE_INT or not d.get("rail") in StairLayout.RAILS or not Palette.valid(d.get("paint")):
		return null
	return {"a": d.a, "b": d.b, "width": d.width, "seed": d.seed, "rail": d.rail, "paint": d.paint}
