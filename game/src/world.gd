class_name World
extends Node

## Every machine applies the host's commands in one order; a tool's edit stays a ghost until its `done` runs.

const LIMIT := 200
## Metres: the side of the squares undo tracks ground and meadow edits in.
const PATCH := 8.0
const KEYS := {"walls": "w", "stairs": "q", "paths": "q", "grounds": "q", "easels": "e", "decorations": "d", "boulders": "b"}
## Commands per second, and in one burst.
const RATE := 20.0
const BURST := 60.0
const COMMAND_BYTES := 4096
## Views that put and take each build themselves; walls carry more, decorations are laid from their table at sync.
const LAID := ["stairs", "paths", "easels", "boulders"]
const WIPED := "*"
const DROWNING := ["heights", "ponds", "plant", "tree"]
const FORMAT := 11
## Seconds: each keep copies the whole garden on the frame.
const KEEP_EVERY := 5.0
const OVER := "over the frame budget"
## Refill grid points past which it moves off-thread: about 10 µs a point on a Quest 2, and a lake is tens of thousands.
const AHEAD := 256

enum Kind { GROUND, BUILDING, BUILDING_PAST_ARCHES, TARGET, HELD_TARGET, TARGET_PAST_ARCHES, FLOOR, PLANT, BOULDER, STAIRS, EASEL, STAND }

signal applied(cmd: Dictionary)
## Tools drop what they were doing.
signal restored
signal loaded
## `hand` is null when it cannot be told.
signal capped(hand: XRController3D)

var wall_tool: WallTool
var flora: Flora
var stairs: Stairs
var paths: Paths
var ground_grab: GroundGrab
var water: Water
var easels: Easels
var boulders: Boulders
var decorations: Decorations
var views: Dictionary:
	get:
		return {"walls": wall_tool, "stairs": stairs, "paths": paths, "easels": easels, "boulders": boulders, "decorations": decorations}
var holders: Array[Node] = []
var terrain := Terrain.new()
var marks := Ground.new()
var palette := Palette.new()
var time := Daylight.DEFAULT
var look: Look
## `ponds` holds each pond's level by the grid point it fills from.
var state := blank()
var seq := 0
var sculpted := false
## Host only.
var stacks := {}
## Host only.
var touched := {}
var _allowance := {}
var _next_token := 0
## -1 when not asked.
var _asked_msec := -1
## Darkens the view so a garden swap never shows; true once black.
var blackout := func() -> bool: return true
var _strokes := {}
## So no grass shows through a house's or tower's floor.
var _floor_marks := {}
var _resending := {}
var _sent := {}
var save_path := ""
var _keep_due := false
var _record_due := false
var _keep_task := -1
var _keep_wait := 0.0
var units := {}
var _units_of := {}
var _cells_of := {}
var _near := Budget.Near.new()
var _near_units := {}
## Share of the frame budget; INF lets builds past it, as the stress scene does to find what they cost.
var limit := 1.0
var _fills := {}
## Summed once: summing on every wipe and swap held a Quest's frame for hundreds of milliseconds.
var _meadow_units := {}
var _pending := {}
## {cmd, by, run}, oldest first: all wait behind one whose water is worked off-thread, keeping every machine's order.
var _queue: Array[Dictionary] = []
var _ahead_task := -1
var play_log: PlayLog
## Tools' submits from replayed input are dropped: the record holds the host's order.
var replayed := false
## [refill, the fills `Commands` checks a pond put against (Water.know)].
var _ahead := []
var _ready_refill: Refill


static func blank() -> Dictionary:
	return {"stairs": {}, "walls": {}, "paths": {}, "grounds": {}, "groups": {}, "ponds": {}, "easels": {}, "boulders": {}, "decorations": {}}


func _init() -> void:
	name = "World"
	palette.apply()


func _ready() -> void:
	multiplayer.peer_disconnected.connect(func(id: int) -> void: _allowance.erase(id))


func fill(hand: Node = null) -> float:
	return Budget.fill(Budget.add(units.duplicate(), pending(hand)) if hand != null else units)


## Tools call this every frame while they show an edit.
func preview(hand: Node, change: Dictionary) -> void:
	_pending[hand] = [Engine.get_process_frames(), change]


func pending(hand: Node) -> Dictionary:
	var p: Array = _pending.get(hand, [-2, {}])
	return p[1] if Engine.get_process_frames() - p[0] <= 1 else {}


func fits(cmd: Dictionary) -> bool:
	return Budget.fits(units, change_of(cmd), limit)


## A paint stroke counts every plant its dabs hold, though some may fall on paths.
func change_of(cmd: Dictionary) -> Dictionary:
	var cells := {}
	var out := _change(cmd, cells)
	if not cells.is_empty():
		Budget.add(Budget.add(out, _near.units(cells)), _near_units, -1.0)
	return out


func _change(cmd: Dictionary, cells: Dictionary) -> Dictionary:
	var out := {}
	match cmd.get("op"):
		"wall":
			for w: Dictionary in cmd.walls:
				Budget.add(out, units_for("walls", w))
				_add_cells(cells, _spread("walls", w))
		"stairs", "path", "ground", "easel", "decoration", "boulder":
			var of: String = Commands.PUTS.find_key(cmd.op)
			Budget.add(out, units_for(of, cmd))
			_add_cells(cells, _spread(of, cmd))
		"take":
			for id in cmd.ids:
				var key := "%s%d" % [KEYS[cmd.of], id]
				Budget.add(out, _units_of.get(key, {}), -1.0)
				_add_cells(cells, _cells_of.get(key, {}), -1.0)
		"reshape":
			if state[cmd.of].has(cmd.id):
				var trial := reshaped(state[cmd.of][cmd.id], cmd.data)
				var key: String = _keys(cmd)[0]
				Budget.add(Budget.add(out, units_for(cmd.of, trial)), _units_of.get(key, {}), -1.0)
				_add_cells(_add_cells(cells, _spread(cmd.of, trial)), _cells_of.get(key, {}), -1.0)
		"plant":
			var n := 1
			if not cmd.kind in Flora.PLACED:
				n = 0
				for d: Array in cmd.dabs:
					n += d[2]
			Budget.add(out, Budget.plants(cmd.kind, n))
		"show":
			for g in cmd.plants:
				var plants: Array = flora.groups.get(g, [])
				for i in cmd.plants[g]:
					var p: Flora.Plant = plants[i] if i >= 0 and i < plants.size() else null
					if p != null and p.current() and p.shown() != cmd.on and not (cmd.on and _drowned(p)):
						Budget.add(out, _unit(g, p), 1.0 if cmd.on else -1.0)
		"heights", "ponds":
			var wet: int = cmd.get("wet", 0)
			for g in cmd.get("put", {}).keys() + cmd.get("drop", []):
				wet -= _wet_m2(g)
			if wet != 0:
				out.pond_m2 = wet
		"batch":
			for c: Dictionary in cmd.cmds:
				Budget.add(out, _change(c, cells))
	return out


## The meadow's grass and flowers are in the base (Budget.CAPACITY_MS): priced as painted, they would cost several times
## what they measure. A tree costs one unit at every scale.
func _unit(group: int, p: Flora.Plant) -> Dictionary:
	var u := flora.unit_of(p)
	return {} if u == "" or group == 0 and not u in Flora.PLACED else {u: 1}


func _account(key: String, now: Dictionary, cells := {}) -> void:
	Budget.add(units, _units_of.get(key, {}), -1.0)
	Budget.add(units, now)
	_set_or_erase(_units_of, key, now)
	if cells.is_empty() and not _cells_of.has(key):
		return
	_near.add(_cells_of.get(key, {}), -1.0)
	_near.add(cells)
	_set_or_erase(_cells_of, key, cells)
	Budget.add(units, _near_units, -1.0)
	_near_units = _near.units()
	Budget.add(units, _near_units)


static func _add_cells(into: Dictionary, cells: Dictionary, times := 1.0) -> Dictionary:
	for c in cells:
		_set_or_erase(into, c, Budget.add(into.get(c, {}), cells[c], times))
	return into


static func _set_or_erase(d: Dictionary, key: Variant, value: Dictionary) -> void:
	if value.is_empty():
		d.erase(key)
	else:
		d[key] = value


func _exit_tree() -> void:
	if _ahead_task >= 0:
		Work.take(_ahead_task)
		_ahead_task = -1
	flush()


func _process(delta: float) -> void:
	if not _queue.is_empty():
		_drain()
	_keep_wait -= delta
	if (_keep_due or _record_due) and _keep_wait <= 0.0 and (_keep_task < 0 or WorkerThreadPool.is_task_completed(_keep_task)):
		_keep()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		flush()


func _enqueue(cmd: Dictionary, by: int, run: Callable) -> void:
	_queue.append({"cmd": cmd, "by": by, "run": run})
	_drain()


func _drain(block := false) -> void:
	while not _queue.is_empty():
		if not block and _queue[0].get("swap", false) and not blackout.call():
			return
		if _ahead_task >= 0:
			if not block and not Work.due(_ahead_task):
				return
			Work.take(_ahead_task)
			_ahead_task = -1
			_ready_refill = _ahead[0]
			Water.know(_ahead[1])
			_queue.pop_front().run.call()
			_ready_refill = null
			Water.know([])
			continue
		var r := _refill_ahead(_queue[0])
		if r == null:
			_queue.pop_front().run.call()
			continue
		var before := terrain.water_levels()
		var written := water.written if water != null else PackedInt32Array()
		var owners := water.owners if water != null else PackedInt32Array()
		var shown: Array[PondLayout.Pond] = water.shown() if water != null else []
		var checks: Dictionary = _queue[0].cmd.get("put", {}) if _queue[0].by >= 0 else {}
		var box := [r, []]
		_ahead = box
		_ahead_task = Work.start(func() -> void:
			r.work()
			if water != null:
				r.publish(before, written, owners, shown)
			for g: Vector2i in checks:
				var p: PondLayout.Pond = r.filled.get(g) if not r.fills.has(g) else PondLayout.fill(r.heights, Terrain.ALL, g, checks[g])
				box[1].append([r.heights, g, checks[g], p]), Budget.WATER_FRAMES)


func settle() -> void:
	_drain(true)


func _refill_ahead(e: Dictionary) -> Refill:
	var cmd: Dictionary = e.cmd
	if cmd.get("op") in ["undo", "redo"] and e.by >= 0:
		cmd = _resolve(e.by, cmd.op, false).get("inverse", {})
	if cmd.get("op") == "batch" and cmd.get("cmds") is Array:
		var first: Array = cmd.cmds.filter(func(c: Variant) -> bool: return c is Dictionary and c.get("op") in ["heights", "ponds"])
		cmd = first[0] if not first.is_empty() else {}
	if not cmd.get("op") in ["heights", "ponds"]:
		return null
	var put: Variant = cmd.get("put", {})
	var drop: Variant = cmd.get("drop", [])
	if not put is Dictionary or not drop is Array:
		return null
	var ponds: Dictionary = state.ponds.duplicate()
	for g: Variant in drop:
		ponds.erase(g)
	for g: Variant in put:
		if typeof(g) != TYPE_VECTOR2I or not Terrain.ALL.has_point(g) or typeof(put[g]) != TYPE_FLOAT or not is_finite(put[g]):
			return null
		ponds[g] = put[g]
	var heights := terrain.read(Terrain.ALL)
	var ground := Rect2i()
	if cmd.op == "heights":
		ground = cmd.get("cells", Rect2i())
		var values: Variant = cmd.get("values")
		if typeof(ground) != TYPE_RECT2I or not Terrain.ALL.encloses(ground) or not values is PackedFloat32Array or values.size() != ground.get_area():
			return null
		var n := 0
		for j in range(ground.position.y, ground.end.y):
			for i in range(ground.position.x, ground.end.x):
				heights[j * Terrain.VERTS + i] = values[n]
				n += 1
	var work := 0
	for g: Vector2i in ponds:
		var was: Array = _fills.get(g, [])
		if was.is_empty() or was[0] != ponds[g]:
			var wet: Variant = cmd.get("wet", 0)
			work += maxi(wet if typeof(wet) == TYPE_INT else 0, was[1].cells.size() if not was.is_empty() else 0)
		elif was[1].ground.intersects(ground):
			work += was[1].cells.size()
	if work < AHEAD:
		return null
	return Refill.of(ponds, put.duplicate(), _fills.duplicate(), ground, heights)


func idle() -> bool:
	return _queue.is_empty()


func flush() -> void:
	if _keep_due or _record_due:
		_keep()
	if _keep_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_keep_task)
		_keep_task = -1


## Only the host saves. A file this game cannot read whole is moved to `path`.bad before anything is written over it.
func load_from(path: String) -> void:
	save_path = path
	if not FileAccess.file_exists(path):
		return
	var snap: Variant = bytes_to_var(FileAccess.get_file_as_bytes(path))
	if restore_whole(snap):
		print("world: loaded %s" % path)
		if Daylight.moonless(time):
			_show_sky(Daylight.sun_at(Daylight.DUSK, false))
		return
	var why := "held a garden this game cannot read whole"
	if snap is Dictionary and snap.get("format") != FORMAT:
		why = "was saved in format %s and this game reads format %d" % [snap.get("format"), FORMAT]
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path) + ".bad")
	push_error("world: %s %s; moving it to .bad: %s" % [path, why, error_string(err)])
	if err != OK:
		save_path = ""


func restore_whole(snap: Variant) -> bool:
	var whole: bool = snap is Dictionary and snap.get("format") == FORMAT and snap.get("cmds") is Array and typeof(snap.get("seq")) == TYPE_INT
	return whole and restore(snap) == snap.cmds.size()


## Snapshots here so the garden cannot change under the writer.
func _keep() -> void:
	var ours := _keep_due and save_path != ""
	_keep_due = false
	_record_due = false
	if not ours and play_log == null:
		return
	var start := Time.get_ticks_usec()
	var bytes := var_to_bytes(snapshot())
	if play_log != null:
		play_log.kept(seq, bytes)
	if _keep_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_keep_task)
	Metrics.note("world: keeping the garden", (Time.get_ticks_usec() - start) / 1000.0)
	_keep_wait = KEEP_EVERY
	if not ours:
		return
	var path := ProjectSettings.globalize_path(save_path)
	_keep_task = WorkerThreadPool.add_task(func() -> void: Main.replace_file(path, bytes))


## `kinds` is an ordered {Kind: reach}; each kind's hit falls short of its reach and of every earlier kind's hit. A kind
## in `ties` takes a tie from those before it, as a boulder always does; plants, stairs and stands never do.
func pick(origin: Vector3, dir: Vector3, kinds: Dictionary, skip := {}, ties: Array[Kind] = []) -> Dictionary:
	var hits := {}
	var near := INF
	for kind: Kind in kinds:
		var reach: float = kinds[kind]
		var within := minf(reach, near)
		var hit: Dictionary
		match kind:
			Kind.PLANT:
				hit = flora.solid_hit(origin, dir, within, skip)
			Kind.BOULDER:
				hit = boulders.pick(origin, dir, within) if boulders != null else {}
				if not hit.is_empty() and skip.has(hit.boulder):
					hit = {}
			Kind.STAIRS:
				hit = stairs.pick(origin, dir, within) if stairs != null else {}
			Kind.STAND:
				hit = easels.pick_stand(origin, dir, within) if easels != null else {}
			_:
				hit = _unbounded(kind, origin, dir, reach, skip)
				if not hit.is_empty() and (hit.along > near or hit.along == near and not kind in ties or kind != Kind.GROUND and hit.along >= reach):
					hit = {}
		if not hit.is_empty():
			hits[kind] = hit
			near = hit.along
	return hits


func _unbounded(kind: Kind, origin: Vector3, dir: Vector3, reach: float, skip: Dictionary) -> Dictionary:
	match kind:
		Kind.GROUND:
			var at: Variant = terrain.raycast(origin, dir, reach)
			return {} if at == null else {"point": at, "along": origin.distance_to(at)}
		Kind.BUILDING:
			return wall_tool.pick_building(origin, dir)
		Kind.BUILDING_PAST_ARCHES:
			return wall_tool.pick_building(origin, dir, false, true)
		Kind.TARGET:
			return FittingTool.pick_target(wall_tool, origin, dir)
		Kind.HELD_TARGET:
			return FittingTool.pick_target(wall_tool, origin, dir, true)
		Kind.TARGET_PAST_ARCHES:
			return FittingTool.pick_target(wall_tool, origin, dir, false, true)
		Kind.FLOOR:
			return wall_tool.pick_floor(origin, dir)
		Kind.EASEL:
			var hit := easels.pick(origin, dir) if easels != null else {}
			return {} if hit.is_empty() or skip.has(hit.easel) else hit
	return {}


func attach(walls: WallTool, plants: Flora, ways: Paths, ground: GroundGrab, ponds: Water = null, stands: Easels = null, rocks: Boulders = null) -> void:
	wall_tool = walls
	flora = plants
	paths = ways
	ground_grab = ground
	water = ponds
	easels = stands
	boulders = rocks
	for view in [ways, stands, rocks]:
		if view != null:
			view.world = self
	holders.assign([walls, ponds].filter(func(h: Node) -> bool: return h != null))
	if flora != null and flora.groups.has(0):
		_grow_meadow()


func _grow_meadow() -> void:
	state.groups[0] = {"kind": "meadow", "size": flora.groups[0].size(), "hidden": {}, "trees": flora.meadow_trees, "bushes": flora.meadow_bushes, "species": {}, "scale": {}, "moss": {}, "places": {}, "turns": {}}
	if _meadow_units.is_empty():
		for p: Flora.Plant in flora.groups[0]:
			if p != null:
				Budget.add(_meadow_units, _unit(0, p))
	Budget.add(units, _meadow_units)


func me() -> int:
	return multiplayer.get_unique_id()


func hear(call: String, args: Array, whose := -1) -> void:
	if play_log != null:
		var from := multiplayer.get_remote_sender_id()
		play_log.heard(from, from if whose < 0 else whose, call, args)


func submit_cued(cmd: Dictionary, act: Cues.Act, at: Vector3, hand: XRController3D, done := Callable()) -> void:
	if fits(cmd):
		Cues.play(act, at, hand)
	submit(cmd, done, hand)


## `done` runs once the command is in the garden, turned down, or moot.
func submit(cmd: Dictionary, done := Callable(), hand: XRController3D = null) -> void:
	if replayed:
		if done.is_valid():
			done.call()
		return
	_next_token += 1
	cmd.token = _next_token
	_sent[_next_token] = {"op": cmd.get("op"), "hand": hand}
	if done.is_valid():
		_sent[_next_token].done = done
	if multiplayer.is_server():
		_enqueue(cmd, me(), _order.bind(cmd, me()))
	elif cmd.get("op") in ["undo", "redo"] or fits(cmd):
		_propose.rpc_id(1, cmd)
	else:
		_turned_down(_next_token, OVER)


func answered() -> bool:
	return _sent.is_empty()


func _settle(token: int) -> void:
	var sent: Dictionary = _sent.get(token, {})
	_sent.erase(token)
	if sent.get("done", Callable()).is_valid():
		sent.done.call()


func undo(hand: XRController3D = null) -> void:
	submit({"op": "undo"}, Callable(), hand)


func redo(hand: XRController3D = null) -> void:
	submit({"op": "redo"}, Callable(), hand)


@rpc("any_peer", "reliable")
func _propose(cmd: Dictionary) -> void:
	hear("_propose", [cmd])
	if not multiplayer.is_server():
		return
	var by := multiplayer.get_remote_sender_id()
	if not _spend(by, cost(cmd)):
		_refuse(by, cmd, "more commands a second than it takes")
		return
	_enqueue(cmd, by, _order.bind(cmd, by))


## Capped at a burst so the largest command a tool makes still goes through.
static func cost(cmd: Dictionary) -> float:
	return minf(BURST, 1.0 + var_to_bytes(cmd).size() / float(COMMAND_BYTES))


func _spend(by: int, cost: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var a: Array = _allowance.get_or_add(by, [BURST, now])
	a[0] = minf(BURST, a[0] + (now - a[1]) * RATE)
	a[1] = now
	if a[0] < cost:
		return false
	a[0] -= cost
	return true


func _order(proposed: Dictionary, by: int) -> void:
	var kind: Variant = proposed.get("op")
	var cmd := {}
	if kind == "undo" or kind == "redo":
		var step := _resolve(by, kind)
		if step.is_empty():
			_refuse(by, proposed, "nothing to %s" % kind)
			return
		# Visitors recheck what the host sends, and one that fails asks for the whole garden again.
		cmd = Commands.clean(step.inverse.merged({"seq": seq + 1, "by": by}).duplicate(true), state, true, terrain)
		if cmd.is_empty():
			_refuse(by, proposed, "the garden has moved on from what it takes back")
			return
		if not fits(cmd):
			stacks[by][kind].append(step)
			_refuse(by, proposed, OVER)
			return
	else:
		cmd = Commands.clean(proposed, state, false, terrain)
		if cmd.is_empty():
			_refuse(by, proposed, "no such command in this build" if not kind in Commands.OPS else "it does not fit the garden as it stands")
			return
		_gather(cmd)
		if kind != "wipe" and not fits(cmd):
			_refuse(by, proposed, OVER)
			return
	seq += 1
	cmd.seq = seq
	cmd.by = by
	if typeof(proposed.get("token")) == TYPE_INT:
		cmd.token = proposed.token
	if cmd.op == "wall" and not cmd.has("ids"):
		cmd.ids = PackedInt32Array(range(seq * Commands.MAX_PIECES, seq * Commands.MAX_PIECES + cmd.walls.size()))
	elif cmd.op != "wall" and (cmd.op in Commands.PUTS.values() or cmd.op == "plant") and not cmd.has("id"):
		cmd.id = seq
	var inverse := _timed(cmd)
	if cmd.op == "plant" and not cmd.kind in Flora.PLACED:
		cmd.skip = state.groups[cmd.id].skip
	_commit.rpc(cmd)
	if play_log != null:
		play_log.heard(0, by, "ordered", [cmd])
	# Turning the sky is not an edit, so undo leaves it be.
	if cmd.op == "sky":
		return
	var keys := _keys(cmd)
	for k in _keys(inverse) if inverse.has("op") else []:
		if not k in keys:
			keys.append(k)
	for k in keys:
		touched.get_or_add(k, {})[by] = seq
	var mine: Dictionary = stacks.get_or_add(by, {"undo": [], "redo": []})
	var entry := {"seq": seq, "inverse": inverse, "keys": keys}
	_push(mine.redo if kind == "undo" else mine.undo, entry)
	if kind not in ["undo", "redo"]:
		mine.redo.clear()


## On the host, so every machine lays the same clutter.
static func _gather(cmd: Dictionary) -> void:
	if cmd.op == "wall":
		for w: Dictionary in cmd.walls:
			w.clutter = ClutterLayout.of_wall(w)
	elif cmd.op == "path":
		cmd.clutter = ClutterLayout.of_path(cmd)


func _refuse(by: int, proposed: Dictionary, why: String) -> void:
	var token: Variant = proposed.get("token")
	if by == me() and typeof(token) == TYPE_INT:
		_turned_down(token, why)
		return
	print("world: refused %s from player %d: %s" % [str(proposed.get("op")).left(16), by, why])
	if typeof(token) == TYPE_INT:
		if why == OVER:
			_capped.rpc_id(by, token)
		else:
			_refused.rpc_id(by, token)


@rpc("authority", "reliable")
func _refused(token: int) -> void:
	hear("_refused", [token])
	_turned_down(token, "the host refused it")


@rpc("authority", "reliable")
func _capped(token: int) -> void:
	hear("_capped", [token])
	_turned_down(token, OVER)


func _turned_down(token: int, why: String) -> void:
	var sent: Dictionary = _sent.get(token, {})
	print("world: %s turned down: %s" % [sent.get("op"), why])
	var hand: XRController3D = sent.get("hand")
	if hand != null and not is_instance_valid(hand):
		hand = null
	if why == OVER:
		cap(hand)
	elif hand != null:
		Cues.play(Cues.Act.REFUSED, hand.global_position, hand)
	_settle(token)


func cap(hand: XRController3D) -> void:
	if hand != null:
		Cues.play(Cues.Act.CAPPED, hand.global_position, hand)
	capped.emit(hand)


@rpc("authority", "reliable")
func _commit(sent: Dictionary) -> void:
	hear("_commit", [sent], sent.get("by") if sent.get("by") is int else -1)
	_enqueue(sent, -1, _apply_sent.bind(sent))


func _apply_sent(sent: Dictionary) -> void:
	var cmd := {} if _asked_msec >= 0 else Commands.clean(sent, state, true, terrain)
	if cmd.is_empty():
		# Our stroke's ghost stays until the garden comes back: `restore` settles it.
		if _asked_msec < 0:
			push_error("world: the host sent a command this garden cannot apply: %s; asking for the garden again" % _refusal(sent))
			_asked_msec = Time.get_ticks_msec()
			_resend.rpc_id(1)
		return
	seq = cmd.seq
	_timed(cmd)


func _refusal(sent: Dictionary) -> String:
	var out := "%s #%s by %s, this garden at #%d" % [sent.get("op"), sent.get("seq"), sent.get("by"), seq]
	var of: Variant = sent.get("of")
	var id: Variant = sent.get("id")
	if not (of is String and state.get(of) is Dictionary and id is int):
		return out
	if not state[of].has(id):
		return out + "; %s %d is not here" % [of, id]
	out += "; %s %d stands here" % [of, id]
	if sent.get("op") != "reshape" or not sent.get("data") is Dictionary:
		return out
	var alone := ""
	for k: Variant in sent.data:
		if Commands.clean(sent.merged({"data": {k: sent.data[k]}}, true), state, true, terrain).is_empty():
			alone += "; its %s fails: %s here, %s sent" % [k, str(state[of][id].get(k)).left(160), str(sent.data[k]).left(160)]
	return out + (alone if alone != "" else "; its changes fail only together")


func _timed(cmd: Dictionary) -> Dictionary:
	var start := Time.get_ticks_usec()
	var inverse := _apply(cmd)
	Metrics.note("world: applying %s" % cmd.op, (Time.get_ticks_usec() - start) / 1000.0)
	return inverse


@rpc("any_peer", "reliable")
func _resend() -> void:
	hear("_resend", [])
	if multiplayer.is_server():
		var by := multiplayer.get_remote_sender_id()
		if _spend(by, BURST * 0.5):
			welcome(by)
		elif not _resending.has(by):
			_resending[by] = true
			get_tree().create_timer(BURST * 0.5 / RATE).timeout.connect(func() -> void:
				_resending.erase(by)
				if by in multiplayer.get_peers():
					welcome(by))


static func _push(stack: Array, entry: Dictionary) -> void:
	stack.append(entry)
	if stack.size() > LIMIT:
		stack.pop_front()


## Steps others built on are dropped on the way; a dropped wipe takes every step below it, all on a garden it took away.
func _resolve(by: int, which: String, take := true) -> Dictionary:
	var stack: Array = stacks.get(by, {}).get(which, [])
	for i in range(stack.size() - 1, -1, -1):
		var e: Dictionary = stack[i]
		if take:
			stack.pop_back()
		if _untouched_by_others(e, by):
			return e
		if WIPED in e.keys:
			if take:
				stack.clear()
			return {}
	return {}


## A wipe touches everything, so anyone's later change to anything stands on it, and it stands on every earlier step.
func _untouched_by_others(e: Dictionary, by: int) -> bool:
	for k in (touched.keys() if WIPED in e.keys else e.keys + [WIPED]):
		var last: Dictionary = touched.get(k, {})
		for who in last:
			if who != by and last[who] > e.seq:
				return false
	return true


static func reshaped(now: Dictionary, data: Dictionary) -> Dictionary:
	var out := now.merged(data, true)
	if data.has("roof"):
		out.roof = now.roof.merged(data.roof, true)
	if data.has("paint"):
		out.paint = PackedInt32Array(now.paint)
		for e in data.paint:
			out.paint[e] = data.paint[e]
	return out


static func _spread(of: String, d: Dictionary) -> Dictionary:
	match of:
		"walls":
			var points := Array(d.points)
			if d.closed and points.size() > 2:
				points.append(points[0])
			return Budget.spread(Budget.wall(d), points)
		"stairs":
			return Budget.spread(Budget.stairs(d), [d.a, d.b])
		"paths":
			return Budget.spread(Budget.path(d), Array(d.points))
	return {}


static func units_for(of: String, d: Dictionary) -> Dictionary:
	match of:
		"walls":
			return Budget.wall(d)
		"stairs":
			return Budget.stairs(d)
		"paths":
			return Budget.path(d)
		"grounds":
			return Budget.ground(d)
		"decorations":
			return Budget.decoration(d)
		"easels":
			return {"easel": 1}
	return {"boulder": Budget.boulder(d.scale)}


func _put(of: String, id: int) -> Dictionary:
	var d: Dictionary = state[of][id]
	if of == "walls":
		return {"op": "wall", "ids": PackedInt32Array([id]), "walls": [d]}
	return d.merged({"op": Commands.PUTS[of], "id": id})


func _keys(cmd: Dictionary) -> Array:
	match cmd.op:
		"wall":
			var out := Array(cmd.ids).map(func(id: int) -> String: return "w%d" % id)
			for w: Dictionary in cmd.walls:
				out.append_array(Array(w.on).map(func(id: int) -> String: return "w%d" % id))
			return out
		"take":
			var out := Array(cmd.ids).map(func(id: int) -> String: return "%s%d" % [KEYS[cmd.of], id])
			if cmd.of == "easels":
				out.append_array(Array(cmd.ids).map(func(id: int) -> String: return "x%d" % id))
			return out
		"reshape":
			return ["%s%d" % [KEYS[cmd.of], cmd.id]]
		"plant":
			return ["p%d" % cmd.id]
		"tree":
			if cmd.group != 0:
				return ["p%d" % cmd.group]
			# A move's inverse carries where it stood, so its undo entry keys both patches.
			var at: Vector3 = cmd.get("at", flora.groups[0][cmd.index].anchor)
			return [_meadow_key(at)]
		"stairs":
			return ["q%d" % cmd.id] + Array(cmd.on).map(func(id: int) -> String: return "w%d" % id)
		"path", "ground", "restone":
			return ["q%d" % cmd.id]
		"season":
			return ["season"]
		"easel":
			return ["e%d" % cmd.id, "x%d" % cmd.id]
		"decoration":
			return ["d%d" % cmd.id] + (["w%d" % cmd.wall] if cmd.wall >= 0 else [])
		"boulder":
			return ["b%d" % cmd.id]

		"ponds":
			return _pond_keys(cmd)
		"paint", "unpaint":
			return [("x%d" if cmd.palette else "e%d") % cmd.easel]
		"sheet":
			return ["e%d" % cmd.easel]
		"wipe", "garden":
			return [WIPED]
		"batch":
			var out := {}
			for c: Dictionary in cmd.cmds:
				for k in _keys(c):
					out[k] = true
			return out.keys()
		"show":
			var out := {}
			for g in cmd.plants:
				if g != 0:
					out["p%d" % g] = true
					continue
				var meadow: Array = flora.groups[0]
				for i in cmd.plants[0]:
					out[_meadow_key(meadow[i].anchor)] = true
			return out.keys()
		"heights":
			var r := Terrain.world_rect(cmd.cells)
			var out := []
			for j in range(floori(r.position.y / PATCH), floori(r.end.y / PATCH) + 1):
				for i in range(floori(r.position.x / PATCH), floori(r.end.x / PATCH) + 1):
					out.append("t%d,%d" % [i, j])
			# A sculpt's inverse puts back the ponds its refill drained.
			return out + _pond_keys(cmd)
	return []


static func _pond_keys(cmd: Dictionary) -> Array:
	return (cmd.get("put", {}).keys() + cmd.get("drop", [])).map(func(g: Vector2i) -> String: return "o%d,%d" % [g.x, g.y])


static func _meadow_key(at: Vector3) -> String:
	return "m%d,%d" % [floori(at.x / PATCH), floori(at.z / PATCH)]


## The author's ghost settles first, so a hump is not counted twice under walls on the new ground; a paint stroke's,
## sky's and path's settle last, so the ghost stands until its plants have grown, its sky is set, its arches relaid.
func _apply(cmd: Dictionary) -> Dictionary:
	var last: bool = cmd.op in ["sky", "path"] or cmd.op == "plant" and not cmd.kind in Flora.PLACED
	var mine: bool = cmd.get("by") == me() and cmd.has("token")
	# An undo or redo carries its own token but no walls in hand.
	var sent: Dictionary = _sent.get(cmd.token, {}) if mine else {}
	var handed := sent.has("done")
	var op: Variant = sent.get("op")
	if op in ["undo", "redo"]:
		var hand: XRController3D = sent.hand
		if hand != null and is_instance_valid(hand):
			Cues.play(Cues.Act.UNDO if op == "undo" else Cues.Act.REDO, hand.global_position, hand)
	if mine and not last:
		_settle(cmd.token)
	var inverse := {}
	match cmd.op:
		"wall":
			for i in cmd.ids.size():
				state.walls[cmd.ids[i]] = cmd.walls[i].duplicate(true)
				wall_tool.put(cmd.ids[i], handed)
				_floor_mark(cmd.ids[i])
			inverse = _built("walls", cmd.ids)
		"take":
			inverse = _take(cmd.of, cmd.ids)
		"reshape":
			var now: Dictionary = state[cmd.of][cmd.id]
			var before := {}
			for k in cmd.data:
				if k == "roof":
					before["roof"] = {}
					for r in cmd.data.roof:
						before.roof[r] = now.roof[r]
						now.roof[r] = cmd.data.roof[r]
				elif k == "paint":
					before["paint"] = {}
					var paint := PackedInt32Array(now.paint)
					for e in cmd.data.paint:
						before.paint[e] = paint[e]
						paint[e] = cmd.data.paint[e]
					now.paint = paint
				else:
					before[k] = now[k]
					now[k] = cmd.data[k]
			if cmd.of == "walls":
				wall_tool.restyle(cmd.id, cmd.data.keys())
				_floor_mark(cmd.id)
			elif views[cmd.of] != null:
				views[cmd.of].show_reshaped(cmd.id)
			_account(_keys(cmd)[0], units_for(cmd.of, now), _spread(cmd.of, now))
			inverse = {"op": "reshape", "of": cmd.of, "id": cmd.id, "data": before}
		"stairs", "path", "easel", "decoration", "boulder":
			inverse = _add(Commands.PUTS.find_key(cmd.op), cmd.id, Commands.build_of(cmd))
		"ground":
			var stroke := Ground.Stroke.new(cmd.kind as Ground.Kind, cmd.get("style", 0))
			stroke.stamps = cmd.stamps
			_strokes[cmd.id] = stroke
			marks.lay(stroke, cmd.id)
			inverse = _add("grounds", cmd.id, Commands.build_of(cmd))
		"restone":
			inverse = {"op": "restone", "id": cmd.id, "style": state.grounds[cmd.id].style}
			state.grounds[cmd.id].style = cmd.style
			marks.restyle(cmd.id, cmd.style)
		"plant":
			var g := Commands.build_of(cmd)
			var plants := flora.grow(cmd.id, g)
			g.size = plants.size()
			g.hidden = {}
			if g.kind in Flora.PLACED:
				g.places = {}
				g.turns = {}
			if g.kind == "tree":
				g.species = {}
				g.scale = {}
				g.moss = {}
			state.groups[cmd.id] = g
			Budget.add(units, Budget.plants(g.kind, 1 if g.kind in Flora.PLACED else g.size - g.skip.size()))
			inverse = {"op": "show", "plants": {cmd.id: PackedInt32Array(range(plants.size()))}, "on": false}
		"show":
			var changed := {}
			for g in cmd.plants:
				var did := flora.set_shown(g, _dry(g, cmd.plants[g]) if cmd.on else cmd.plants[g], cmd.on)
				if did.is_empty():
					continue
				changed[g] = did
				var hidden: Dictionary = state.groups[g].hidden
				for i in did:
					Budget.add(units, _unit(g, flora.groups[g][i]), 1.0 if cmd.on else -1.0)
					if cmd.on:
						hidden.erase(i)
					else:
						hidden[i] = true
			inverse = {"op": "show", "plants": changed, "on": not cmd.on}
		"tree":
			var g: Dictionary = state.groups[cmd.group]
			var first: Flora.Plant = flora.groups[cmd.group][cmd.index]
			inverse = {"op": "tree", "group": cmd.group, "index": cmd.index}
			if cmd.has("at"):
				inverse.at = first.foot()
				g.places[cmd.index] = cmd.at
				flora.move(first, cmd.at)
			if cmd.has("turn"):
				inverse.turn = g.turns.get(cmd.index, 0.0)
				if cmd.turn == 0.0:
					g.turns.erase(cmd.index)
				else:
					g.turns[cmd.index] = cmd.turn
				flora.turn_to(first, cmd.turn)
			for k: String in ["species", "scale", "moss"]:
				if not cmd.has(k):
					continue
				var plain: Variant = FloraLayout.Species.OAK if k == "species" else false if k == "moss" else 1.0
				inverse[k] = g[k].get(cmd.index, plain)
				if cmd[k] == plain:
					g[k].erase(cmd.index)
				else:
					g[k][cmd.index] = cmd[k]
			if flora.species_of(first) >= 0:
				flora.set_look(first, g.species.get(cmd.index, FloraLayout.Species.OAK), g.scale.get(cmd.index, 1.0))
				flora.set_moss(first, g.moss.get(cmd.index, false))
		"heights":
			inverse = {"op": "heights", "cells": cmd.cells, "values": terrain.read(cmd.cells)}
			var before: Dictionary = state.ponds.duplicate()
			ground_grab.restore(cmd.cells, cmd.values)
			sculpted = true
			_set_ponds(cmd, before, inverse, cmd.cells)
		"ponds":
			inverse = {"op": "ponds"}
			_set_ponds(cmd, state.ponds.duplicate(), inverse, Rect2i())
		"season":
			inverse = {"op": "season", "index": palette.season}
			palette.season = cmd.index
			palette.apply()
		"sky":
			inverse = {"op": "sky", "time": time}
			_show_sky(cmd.time)
		"wipe":
			inverse = {"op": "garden", "cmds": snapshot().cmds}
			var season := palette.season
			var sun := time
			_hushed(func() -> void:
				_clear()
				palette.season = season
				palette.apply()
				_show_sky(sun)
				_bare_meadow())
		"batch":
			var back := []
			for c: Dictionary in cmd.cmds:
				# An earlier take in the batch may have taken it with what it stood on.
				if c.op == "reshape" and not state[c.of].has(c.id):
					continue
				var undone := _apply(c)
				back = (undone.cmds if undone.op == "batch" else [undone]) + back
			inverse = {"op": "batch", "cmds": back}
		"garden":
			inverse = {"op": "wipe"}
			_hushed(func() -> void:
				_clear()
				_rebuild(cmd.cmds))
		"paint":
			state.easels[cmd.easel][Commands.surface(cmd)].append(cmd.stroke)
			if easels != null:
				easels.painted(cmd.easel, cmd.stroke, handed, cmd.palette)
			inverse = {"op": "unpaint", "easel": cmd.easel, "palette": cmd.palette}
		"unpaint":
			var strokes: Array = state.easels[cmd.easel][Commands.surface(cmd)]
			inverse = {"op": "paint", "easel": cmd.easel, "palette": cmd.palette, "stroke": strokes.pop_back()}
			if easels != null:
				easels.repaint(cmd.easel, strokes, cmd.palette)
		"sheet":
			inverse = {"op": "sheet", "easel": cmd.easel, "strokes": state.easels[cmd.easel].strokes}
			state.easels[cmd.easel].strokes = cmd.strokes.duplicate()
			if easels != null:
				easels.repaint(cmd.easel, state.easels[cmd.easel].strokes)
	if cmd.op in DROWNING and flora != null:
		var back := _drown()
		if not back.is_empty():
			inverse = {"op": "batch", "cmds": [inverse, back]}
	if mine and last:
		_settle(cmd.token)
	applied.emit(cmd)
	if save_path != "" and multiplayer.is_server():
		_keep_due = true
	if play_log != null:
		_record_due = true
	return inverse


func _wet_m2(g: Vector2i) -> int:
	var was: Array = _fills.get(g, [])
	return was[1].cells.size() if not was.is_empty() and was[1] != null else 0


## So a pond never hides a tree or bush that still stands.
func _drown() -> Dictionary:
	var by_group := {}
	for parts in flora.solids():
		if Water.drowned(terrain, parts[0].anchor):
			for p: Flora.Plant in parts:
				by_group.get_or_add(p.group, []).append(p.index)
	if by_group.is_empty():
		return {}
	for g in by_group:
		by_group[g] = PackedInt32Array(by_group[g])
	return _apply({"op": "show", "plants": by_group, "on": false})


func _drowned(p: Flora.Plant) -> bool:
	return p.pool in [flora.trunks, flora.foliage, flora.bushes] and Water.drowned(terrain, p.anchor)


func _dry(g: int, indices: PackedInt32Array) -> PackedInt32Array:
	var plants: Array = flora.groups.get(g, [])
	var out := PackedInt32Array()
	for i in indices:
		if i < 0 or i >= plants.size() or plants[i] == null or not _drowned(plants[i]):
			out.append(i)
	return out


func _take(of: String, ids: PackedInt32Array) -> Dictionary:
	var gone := {of: {}}
	for id: int in ids:
		if state[of].has(id):
			gone[of][id] = true
	var bearing: Dictionary = gone.walls.duplicate() if of == "walls" else {}
	var grew := not bearing.is_empty()
	while grew:
		grew = false
		for table: String in Commands.STANDS_ON:
			var field: String = Commands.STANDS_ON[table]
			if field.is_empty():
				continue
			for id: int in state[table]:
				if gone.get(table, {}).has(id):
					continue
				var on: Variant = state[table][id][field]
				if not (Array(on) if on is PackedInt32Array else [on]).any(func(o: int) -> bool: return bearing.has(o)):
					continue
				gone.get_or_add(table, {})[id] = true
				if table == "walls":
					bearing[id] = true
					grew = true
	var back := []
	var walls: Array = gone.get("walls", {}).keys()
	walls.sort()
	for i in range(0, walls.size(), Commands.MAX_PIECES):
		var chunk := PackedInt32Array(walls.slice(i, i + Commands.MAX_PIECES))
		back.append({"op": "wall", "ids": chunk, "walls": Array(chunk).map(func(id: int) -> Dictionary: return state.walls[id])})
	for table: String in Commands.PUTS:
		if table == "walls":
			continue
		for id: int in gone.get(table, {}):
			back.append(_put(table, id))
			state[table].erase(id)
			if table == "grounds":
				marks.lift(_strokes[id])
				_strokes.erase(id)
			elif _laid(table):
				views[table].take(id)
			_account("%s%d" % [KEYS[table], id], {})
	walls.reverse()
	for id: int in walls:
		state.walls.erase(id)
		wall_tool.take(id)
		_account("w%d" % id, {})
		_floor_mark(id)
	return back[0] if back.size() == 1 else {"op": "batch", "cmds": back}


func _laid(of: String) -> bool:
	return of in LAID and views[of] != null


func _add(of: String, id: int, entry: Dictionary) -> Dictionary:
	state[of][id] = entry
	if _laid(of):
		views[of].put(id, entry)
	return _built(of, PackedInt32Array([id]))


func _built(of: String, ids: PackedInt32Array) -> Dictionary:
	for id in ids:
		_account("%s%d" % [KEYS[of], id], units_for(of, state[of][id]), _spread(of, state[of][id]))
	return {"op": "take", "of": of, "ids": ids}


func _set_ponds(cmd: Dictionary, before: Dictionary, inverse: Dictionary, ground: Rect2i) -> void:
	for g in cmd.get("drop", []):
		state.ponds.erase(g)
	var put: Dictionary = cmd.get("put", {})
	state.ponds.merge(put, true)
	var r := _ready_refill
	var heights := terrain.read(Terrain.ALL)
	if r == null or not r.matches(state.ponds, put, _fills, ground, heights):
		r = Refill.make(state.ponds.duplicate(), put.duplicate(), _fills.duplicate(), ground, heights)
	_ready_refill = null
	for g in r.gone:
		state.ponds.erase(g)
	_fills.clear()
	for g in state.ponds:
		_fills[g] = [state.ponds[g], r.filled[g]]
	if water != null:
		water.show_ponds(r.found, r)
	var back := {}
	for g in before:
		if not state.ponds.has(g) or state.ponds[g] != before[g]:
			back[g] = before[g]
	var gone: Array = state.ponds.keys().filter(func(g: Vector2i) -> bool: return not before.has(g))
	if not back.is_empty():
		inverse.put = back
	if not gone.is_empty():
		inverse.drop = gone
	_account("ponds", {"pond_m2": r.wet} if r.wet > 0 else {})


func _show_sky(t: float) -> void:
	time = t
	if look != null:
		look.set_time(t)


func welcome(id: int) -> void:
	_welcome.rpc_id(id, snapshot())


@rpc("authority", "reliable")
func _welcome(snap: Dictionary) -> void:
	hear("_welcome", [snap])
	if not (snap.get("cmds") is Array and typeof(snap.get("seq")) == TYPE_INT):
		push_error("world: the host sent a garden this one cannot read")
		return
	swap(snap)


func swap(snap: Dictionary) -> void:
	_queue.append({"cmd": {}, "by": -1, "swap": true, "run": func() -> void:
		var asked := _asked_msec
		_asked_msec = -1
		var applied := _restore(snap)
		if asked >= 0:
			print("world: the garden asked for again came %d ms later; %d of its %d commands applied" % [Time.get_ticks_msec() - asked, applied, snap.cmds.size()])})
	_drain()


## Groups regrow in the order they were planted, so every machine's plant pools fill alike.
func snapshot() -> Dictionary:
	var cmds := []
	if sculpted:
		cmds.append({"op": "heights", "cells": Terrain.ALL, "values": terrain.read(Terrain.ALL)})
	if not state.ponds.is_empty():
		cmds.append({"op": "ponds", "put": state.ponds.duplicate()})
	for of: String in Commands.PUTS:
		for id: int in state[of]:
			cmds.append(_put(of, id))
	for id in state.groups:
		var g: Dictionary = state.groups[id]
		if g.kind != "meadow":
			var c := g.duplicate(true)
			for k in ["hidden", "size", "species", "scale", "moss", "places", "turns"]:
				c.erase(k)
			c.op = "plant"
			c.id = id
			cmds.append(c)
		if not g.hidden.is_empty():
			cmds.append({"op": "show", "plants": {id: PackedInt32Array(g.hidden.keys())}, "on": false})
		var named := {"species": "species", "scale": "scale", "moss": "moss", "places": "at", "turns": "turn"}
		var changed := {}
		for k in named:
			changed.merge(g.get(k, {}))
		for i in changed:
			var c := {"op": "tree", "group": id, "index": i}
			for k in named:
				if g.get(k, {}).has(i):
					c[named[k]] = g[k][i]
			cmds.append(c)
	if palette.season != Palette.SUMMER:
		cmds.append({"op": "season", "index": palette.season})
	if time != Daylight.DEFAULT:
		cmds.append({"op": "sky", "time": time})
	for c in cmds:
		c.seq = seq
		c.by = 1
	return {"format": FORMAT, "seq": seq, "cmds": cmds}


func restore(snap: Dictionary) -> int:
	settle()
	return _restore(snap)


func _restore(snap: Dictionary) -> int:
	var start := Time.get_ticks_usec()
	var applied: int = _hushed(func() -> int:
		_clear()
		marks.clear()
		flora.clear_ghosts()
		stacks.clear()
		touched.clear()
		for t in _sent.keys():
			_settle(t)
		restored.emit()
		return _rebuild(snap.cmds))
	seq = snap.seq
	flora.grow_now()
	loaded.emit()
	Metrics.note("world: restoring a garden of %d commands" % snap.cmds.size(), (Time.get_ticks_usec() - start) / 1000.0)
	return applied


func _floor_mark(id: int) -> void:
	if _floor_marks.has(id):
		marks.lift(_floor_marks[id])
		_floor_marks.erase(id)
	var d: Dictionary = state.walls.get(id, {})
	if d.is_empty() or not d.closed or d.fence or not d.has("roof") or not d.on.is_empty():
		return
	var mark := Ground.Stroke.new(Ground.Kind.EARTH)
	mark.stamps = WallLayout.floor_stamps(d.points)
	_floor_marks[id] = mark
	marks.lay(mark, id)


func _hushed(change: Callable) -> Variant:
	wall_tool.quiet = true
	marks.quiet = true
	var out: Variant = change.call()
	wall_tool.quiet = false
	marks.quiet = false
	marks.rewear()
	return out


func _clear() -> void:
	for h in holders:
		h.call(&"clear")
	for table: String in LAID:
		if _laid(table):
			for id: int in state[table].keys():
				views[table].take(id)
	for d: Dictionary in [_strokes, _floor_marks]:
		for id in d:
			marks.lift(d[id])
		d.clear()
	state = blank()
	_fills.clear()
	units = {}
	_units_of.clear()
	_cells_of.clear()
	_near = Budget.Near.new()
	_near_units = {}
	flora.reset()
	palette.season = Palette.SUMMER
	palette.apply()
	_show_sky(Daylight.DEFAULT)
	_grow_meadow()
	if sculpted:
		ground_grab.restore(Terrain.ALL, Terrain.base_heights())
		sculpted = false


func _rebuild(cmds: Array) -> int:
	var applied := 0
	for sent in cmds:
		var cmd := Commands.clean(sent, state, true, terrain) if sent is Dictionary else {}
		if cmd.is_empty():
			push_error("world: skipped a snapshot command this garden cannot apply")
			continue
		cmd.erase("token")
		_apply(cmd)
		applied += 1
	return applied


func _bare_meadow() -> void:
	var hidden: Dictionary = state.groups[0].hidden
	for i in flora.set_shown(0, flora.meadow_scenery, false):
		hidden[i] = true
		Budget.add(units, _unit(0, flora.groups[0][i]), -1.0)


func digest() -> Dictionary:
	flora.grow_now()
	for w: Wall in wall_tool.walls:
		w.lay_now()
	var heights := Array(terrain.read(Terrain.ALL))
	var out := {"seq": seq, "walls": {}, "groups": {}, "ground": hash(heights), "heights": [heights.min(), heights.max()]}
	for w: Wall in wall_tool.walls:
		out.walls[str(w.id)] = {"data": var_to_str(state.walls[w.id]), "stones": w.layout.stones.size(), "height": w.layout.height, "floor": w.layout.floor_y}
	for g in flora.groups:
		var shown := 0
		var spot := Vector3.ZERO
		var species := []
		var scales := []
		var turns := []
		for p: Flora.Plant in flora.groups[g]:
			if p == null:
				continue
			if p.shown():
				shown += 1
				spot += p.anchor
			if p.pool == flora.trunks:
				species.append(flora.species_of(p))
				scales.append(snappedf(flora.scale_of(p), 0.001))
				turns.append(snappedf(flora.turn_of(p), 0.001))
		out.groups[str(g)] = {"kind": state.groups[g].kind, "plants": flora.groups[g].size(), "shown": shown, "spot": var_to_str(spot.snapped(Vector3.ONE * 0.01)), "species": species, "scale": scales, "turn": turns}
	out.stairs = state.stairs.duplicate(true)
	out.paths = state.paths.keys()
	out.pond_levels = state.ponds.keys().map(func(g: Vector2i) -> String: return "%s %.3f" % [g, state.ponds[g]])
	out.grounds = state.grounds.keys()
	marks.settle()
	out.mask = hash(marks.laid.get_data())
	out.marks = marks.replayed()
	out.ponds = water.ponds.size() if water != null else 0
	out.season = palette.season
	out.easels = {}
	for id in state.easels:
		var e: Dictionary = state.easels[id]
		out.easels[str(id)] = {"at": var_to_str(e.at.snapped(Vector3.ONE * 0.01)), "strokes": e.strokes.size(), "paint": hash(var_to_str(e.strokes)), "palette": e.palette.size(), "palette_paint": hash(var_to_str(e.palette))}
	out.decorations = {}
	for id in state.decorations:
		out.decorations[str(id)] = var_to_str(state.decorations[id])
	out.boulders = {}
	for id in state.boulders:
		var b: Dictionary = state.boulders[id]
		var shown: Boulders.Boulder = boulders.find(id) if boulders != null else null
		out.boulders[str(id)] = {"seed": b.seed, "scale": b.scale, "paint": b.paint, "style": b.style, "turn": var_to_str(b.turn), "at": var_to_str(shown.transform.origin.snapped(Vector3.ONE * 0.01)) if shown != null else ""}
	out.budget = snappedf(fill(), 0.001)
	return out
