class_name World
extends Node

## The garden as data, changed only by build commands (docs/multiplayer.md, Commands). Tools `submit` a
## command; the host checks it, orders it, applies it and broadcasts it, and every machine applies the same
## commands in the same order. Applying returns the inverse command, which the host keeps on its author's
## undo stack. A tool shows its own edit as a ghost until the command comes back, the host turns it down
## or the garden is swapped; then World calls the `done` it was submitted with.

const LIMIT := 200
## Ground and the meadow's own plants are tracked for undo in square patches of this many metres.
const PATCH := 8.0
## Commands a player may send per second, and in one burst.
const RATE := 20.0
const BURST := 60.0
## The key a wipe, and the undo of one, touches: everything.
const WIPED := "*"
## A growing plant stands at its spot's height above the ground as it is when it grows, so new heights wait for
## every stroke to grow.
const GROWS_FIRST := ["heights"]
## Commands that can leave a tree or bush standing where water covers its root, which `_drown` then takes out.
const DROWNING := ["heights", "ponds", "plant", "tree"]
## A saved garden from another format is moved aside rather than rebuilt into a different one: 3 paints
## each build its own colours.
const FORMAT := 3
## A command applying for longer than this is logged.
const SLOW_MS := 4.0
const OVER := "over the frame budget"
## A ponds or ground command whose water fills again over at least this many grid points is worked out on another
## thread before it applies (Refill), and the commands after it wait for it: on a Quest 2 a fill takes about 10 µs a
## grid point of script, and a lake is tens of thousands.
const AHEAD := 256

signal applied(cmd: Dictionary)
## The whole garden was swapped (joining or leaving someone's): tools drop what they were doing.
signal restored
## The replacement garden, including its terrain, is ready for the player.
signal loaded
## The frame budget turned down what `hand` tried (null for a hand we cannot tell).
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
## The garden's season; each build carries its own colours.
var palette := Palette.new()
## Where the sun stands (Daylight), shown on `look` once the sky tool lets the sky go.
var time := Daylight.DEFAULT
var look: Look
## Standing walls, paths, easels, boulders and plant groups by id, as the plain values their commands carry, and each
## pond's level by the grid point it fills from. A group keeps its command's fields, its `size` and the indices of its plants
## since `hidden`; an easel where it stands, which way it faces, its canvas's strokes, oldest first, and its oil
## palette's mixing field (`Mixing.bytes`, empty when clean); a boulder the ground point under it, its turn, seed, scale,
## paint and stone style.
var state := blank()
var seq := 0
var sculpted := false
## Host only: per player, their undo and redo stacks of {seq, inverse, keys}.
var stacks := {}
## Host only: per thing in the garden, the sequence number of each player's last change to it.
var touched := {}
var _allowance := {}
var _next_token := 0
## True from asking the host for its garden again until it arrives; commands meanwhile are moot.
var _awaiting := false
## The ground strokes standing, by id.
var _strokes := {}
## The meadow worn bare under each house's or tower's floor on the ground, by its wall's id, so no grass shows through.
var _floor_marks := {}
var _resending := {}
## What to do when each of our sent commands is settled, by token.
var _done := {}
## Where this garden is saved between sessions, or "" to save nothing (see `load_from`).
var save_path := ""
var _keep_due := false
var _keep_task := -1
## What the garden's builds count as in the frame budget (Budget.UNITS), kept as each command applies; walls and paths
## by key too, so taking one away takes back what it added.
var units := {}
var _units_of := {}
## False lets the garden take builds past the frame budget, as the stress scene does to find what they cost.
var bounded := true
var _fills := {}
## Per hand, what the edit its tool is showing would add, and the frame it said so.
var _pending := {}
## The hand each of our sent commands came from, by token, so the one turned down feels it.
var _hands := {}
## The op of each of our sent commands, by token, for the log line when one is turned down.
var _ops := {}
## Commands waiting to be ordered (host) or applied (others), oldest first, as {cmd, by, run}: the first may wait for
## its water to be worked out on another thread, and the rest wait behind it, so every machine still applies the same
## commands in the same order.
var _queue: Array[Dictionary] = []
var _ahead_task := -1
## What the task leaves: the refill, and the fills `Commands` checks a pond put against (Water.know).
var _ahead := []
## The refill worked out for the command now applying, for `_set_ponds`.
var _ready_refill: Refill


## A garden with nothing in it.
static func blank() -> Dictionary:
	return {"stairs": {}, "walls": {}, "paths": {}, "grounds": {}, "groups": {}, "ponds": {}, "easels": {}, "boulders": {}, "decorations": {}}


func _init() -> void:
	name = "World"
	palette.apply()


func _ready() -> void:
	multiplayer.peer_disconnected.connect(func(id: int) -> void: _allowance.erase(id))


func fill(hand: Node = null) -> float:
	return Budget.fill(Budget.add(units.duplicate(), pending(hand)) if hand != null else units)


## Tools say each frame what the edit they show would add, so the bar can show whether it fits.
func preview(hand: Node, change: Dictionary) -> void:
	_pending[hand] = [Engine.get_process_frames(), change]


func pending(hand: Node) -> Dictionary:
	var p: Array = _pending.get(hand, [-2, {}])
	return p[1] if Engine.get_process_frames() - p[0] <= 1 else {}


func fits(cmd: Dictionary) -> bool:
	return not bounded or Budget.fits(units, change_of(cmd))


## What `cmd` would add to `units`, without applying it: negative for what it takes away. A paint stroke counts every
## plant its dabs hold, though some may fall on paths.
func change_of(cmd: Dictionary) -> Dictionary:
	var out := {}
	match cmd.get("op"):
		"wall":
			for w: Dictionary in cmd.walls:
				Budget.add(out, Budget.wall(w))
		"unwall":
			for id in cmd.ids:
				Budget.add(out, _units_of.get("w%d" % id, {}), -1.0)
		"reshape":
			if state[cmd.of].has(cmd.id):
				var trial := reshaped(state[cmd.of][cmd.id], cmd.data)
				Budget.add(Budget.add(out, _units(cmd.of, trial)), _units_of.get(_keys(cmd)[0], {}), -1.0)
		"stairs":
			Budget.add(out, Budget.stairs(cmd.stairs))
		"unstairs":
			Budget.add(out, _units_of.get("q%d" % cmd.id, {}), -1.0)
		"path":
			Budget.add(out, Budget.path(cmd.path))
		"unpath", "unground":
			Budget.add(out, _units_of.get("q%d" % cmd.id, {}), -1.0)
		"ground":
			Budget.add(out, Budget.ground(cmd))
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
			for g in cmd.get("put", {}):
				wet -= _wet(g)
			for g in cmd.get("drop", []):
				wet -= _wet(g)
			if wet != 0:
				out.pond_m2 = wet
		"easel":
			out.easel = 1
		"uneasel":
			if state.easels.has(cmd.id):
				out.easel = -1
		"decoration":
			out = Budget.decoration(cmd.style)
		"undecoration":
			Budget.add(out, _units_of.get("d%d" % cmd.id, {}), -1.0)
		"boulder":
			out.boulder = Budget.boulder(cmd.scale)
		"unboulder":
			Budget.add(out, _units_of.get("b%d" % cmd.id, {}), -1.0)
		"batch":
			for c: Dictionary in cmd.cmds:
				Budget.add(out, change_of(c))
	return out


## The meadow's own grass and flowers are part of the base (Budget.CAPACITY_MS): priced as painted ones, packed
## beside the eye, its spread pool would charge several times what it measures. A tree costs one unit at every scale.
func _unit(group: int, p: Flora.Plant) -> Dictionary:
	var u := flora.unit_of(p)
	return {} if u == "" or group == 0 and not u in Flora.PLACED else {u: 1}


func _account(key: String, now: Dictionary) -> void:
	Budget.add(units, _units_of.get(key, {}), -1.0)
	Budget.add(units, now)
	if now.is_empty():
		_units_of.erase(key)
	else:
		_units_of[key] = now


func _exit_tree() -> void:
	if _ahead_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_ahead_task)
		_ahead_task = -1
	flush()


func _process(_delta: float) -> void:
	if not _queue.is_empty():
		_drain()


## Runs `run`, which orders or applies `cmd` (by player `by` on the host), once every command before it has run and
## the water it changes is worked out.
func _enqueue(cmd: Dictionary, by: int, run: Callable) -> void:
	_queue.append({"cmd": cmd, "by": by, "run": run})
	_drain()


## Runs the waiting commands in turn until one waits for its water; with `wait`, waits for each.
func _drain(wait := false) -> void:
	while not _queue.is_empty():
		if _ahead_task >= 0:
			if not wait and not WorkerThreadPool.is_task_completed(_ahead_task):
				return
			WorkerThreadPool.wait_for_task_completion(_ahead_task)
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
		var before := Terrain.water_levels()
		var written := water.written() if water != null else PackedInt32Array()
		var owners := water.owners() if water != null else PackedInt32Array()
		var shown: Array[PondLayout.Pond] = water.shown() if water != null else []
		var checks: Dictionary = _queue[0].cmd.get("put", {}) if _queue[0].by >= 0 else {}
		var box := [r, []]
		_ahead = box
		_ahead_task = WorkerThreadPool.add_task(func() -> void:
			r.work()
			if water != null:
				r.publish(before, written, owners, shown)
			for g: Vector2i in checks:
				var p: PondLayout.Pond = r.filled.get(g) if not r.fills.has(g) else PondLayout.fill(r.heights, Terrain.ALL, g, checks[g])
				box[1].append([r.heights, g, checks[g], -INF, p]))


## Every waiting command run.
func settle() -> void:
	_drain(true)


## The refill the command `e` waits for, its inputs set but not worked out, or null when it changes too little water
## to work out ahead: a ponds or ground command, or the first of a batch's, an undo or redo by what it undoes.
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
	var heights := Terrain.read(Terrain.ALL)
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


## Writes a save still due and waits for the last one to land.
func flush() -> void:
	if _keep_due:
		_keep()
	if _keep_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_keep_task)
		_keep_task = -1


## Loads the garden saved at `path`, if there is one, and from then on saves this garden there: rewritten
## after every frame in which a command changed it while it was our own (not one we are visiting). A file
## of another format, or one this game cannot read whole, is moved aside to `path`.bad before anything is
## written over it.
func load_from(path: String) -> void:
	save_path = path
	if not FileAccess.file_exists(path):
		return
	var snap: Variant = bytes_to_var(FileAccess.get_file_as_bytes(path))
	if restore_whole(snap):
		print("world: loaded %s" % path)
		return
	var why := "held a garden this game cannot read whole"
	if snap is Dictionary and snap.get("format") != FORMAT:
		why = "was saved in format %s and this game reads format %d" % [snap.get("format"), FORMAT]
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path) + ".bad")
	push_error("world: %s %s; moved it to .bad (%s)" % [path, why, error_string(err)])
	if err != OK:
		save_path = ""


## Rebuilds the garden from `snap` (snapshot); false if it is not a garden this game can read whole.
func restore_whole(snap: Variant) -> bool:
	var whole: bool = snap is Dictionary and snap.get("format") == FORMAT and snap.get("cmds") is Array and typeof(snap.get("seq")) == TYPE_INT
	return whole and restore(snap) == snap.cmds.size()


## The snapshot is taken here, so the garden it describes cannot change under the writer.
func _keep() -> void:
	_keep_due = false
	if save_path == "":
		return
	var bytes := var_to_bytes(snapshot())
	flush()
	var path := ProjectSettings.globalize_path(save_path)
	_keep_task = WorkerThreadPool.add_task(func() -> void: World._write(path, bytes))


## Written beside the garden and renamed over it, so a crash mid-write leaves the last one whole.
static func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path + ".new", FileAccess.WRITE)
	if f == null:
		push_error("world: cannot save the garden at %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_buffer(bytes)
	f.close()
	var err := DirAccess.rename_absolute(path + ".new", path)
	if err != OK:
		push_error("world: cannot save the garden at %s: %s" % [path, error_string(err)])


func attach(walls: WallTool, plants: Flora, ways: Paths, ground: GroundGrab, ponds: Water = null, stands: Easels = null, rocks: Boulders = null) -> void:
	wall_tool = walls
	flora = plants
	paths = ways
	ground_grab = ground
	water = ponds
	easels = stands
	boulders = rocks
	if flora != null and flora.groups.has(0):
		_grow_meadow()


## The meadow's own group as it grows, every plant standing and every tree an oak, its trees and bushes charged as
## planted ones are.
func _grow_meadow() -> void:
	state.groups[0] = {"kind": "meadow", "size": flora.groups[0].size(), "hidden": {}, "trees": flora.meadow_trees(), "bushes": flora.meadow_bushes(), "species": {}, "scale": {}, "moss": {}, "places": {}}
	for p: Flora.Plant in flora.groups[0]:
		if p != null:
			Budget.add(units, _unit(0, p))


func me() -> int:
	return multiplayer.get_unique_id()


## Sends a build command to the host; `done` runs once it is in the garden, turned down, or moot. One that would
## take the garden past its frame budget is turned down here at once; `hand`, the one whose tool made it, feels a
## turned-down command.
func submit(cmd: Dictionary, done := Callable(), hand: XRController3D = null) -> void:
	_next_token += 1
	cmd.token = _next_token
	if done.is_valid():
		_done[_next_token] = done
	if hand != null:
		_hands[_next_token] = hand
	_ops[_next_token] = cmd.get("op")
	if not cmd.get("op") in ["undo", "redo"] and not fits(cmd):
		_turned_down(_next_token, OVER)
		return
	if multiplayer.is_server():
		_enqueue(cmd, me(), _order.bind(cmd, me()))
	else:
		_propose.rpc_id(1, cmd)


func _settle(token: int) -> void:
	var done: Callable = _done.get(token, Callable())
	_done.erase(token)
	_hands.erase(token)
	_ops.erase(token)
	if done.is_valid():
		done.call()


func undo() -> void:
	submit({"op": "undo"})


func redo() -> void:
	submit({"op": "redo"})


@rpc("any_peer", "reliable")
func _propose(cmd: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var by := multiplayer.get_remote_sender_id()
	if not _spend(by, 1.0):
		_refuse(by, cmd, "more commands a second than it takes")
		return
	_enqueue(cmd, by, _order.bind(cmd, by))


## Takes `cost` from a player's allowance, which refills at RATE a second up to BURST; false if it is short.
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
			return
		cmd = step.inverse.duplicate(true)
		if not fits(cmd):
			stacks[by][kind].append(step)
			_refuse(by, proposed, OVER)
			return
	else:
		cmd = Commands.clean(proposed, state, false)
		if cmd.is_empty():
			_refuse(by, proposed, "no such command in this build" if not kind in Commands.OPS else "it does not fit the garden as it stands")
			return
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
	elif cmd.op in ["stairs", "plant", "path", "ground", "easel", "boulder", "decoration"] and not cmd.has("id"):
		cmd.id = seq
	var inverse := _timed(cmd)
	if cmd.op == "plant" and not cmd.kind in Flora.PLACED:
		cmd.skip = state.groups[cmd.id].skip
	_commit.rpc(cmd)
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
	match kind:
		"undo":
			_push(mine.redo, entry)
		"redo":
			_push(mine.undo, entry)
		_:
			_push(mine.undo, entry)
			mine.redo.clear()


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
	_turned_down(token, "the host refused it")


@rpc("authority", "reliable")
func _capped(token: int) -> void:
	_turned_down(token, OVER)


func _turned_down(token: int, why: String) -> void:
	print("world: %s turned down: %s" % [_ops.get(token), why])
	var hand: XRController3D = _hands.get(token)
	if hand != null and not is_instance_valid(hand):
		hand = null
	if why == OVER:
		cap(hand)
	elif hand != null:
		Cues.play(Cues.Act.REFUSED, hand.global_position, hand)
	_settle(token)


## The frame budget turns down what `hand` tried: its budget bar grows and shakes, it grunts, and the hand feels it.
func cap(hand: XRController3D) -> void:
	if hand != null:
		Cues.play(Cues.Act.CAPPED, hand.global_position, hand)
	capped.emit(hand)


@rpc("authority", "reliable")
func _commit(sent: Dictionary) -> void:
	_enqueue(sent, -1, _apply_sent.bind(sent))


func _apply_sent(sent: Dictionary) -> void:
	var cmd := {} if _awaiting else Commands.clean(sent, state, true)
	if cmd.is_empty():
		# Our own stroke's ghost stays until the garden it is in comes back: `restore` settles it.
		if not _awaiting:
			push_error("world: the host sent a command this garden cannot apply: %s; asking for the garden again" % sent.get("op"))
			_awaiting = true
			_resend.rpc_id(1)
		return
	seq = cmd.seq
	_timed(cmd)


## Applies a played command, logging one that takes most of a frame, so a hitch it causes is placed without guessing.
func _timed(cmd: Dictionary) -> Dictionary:
	var start := Time.get_ticks_usec()
	var inverse := _apply(cmd)
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	if ms > SLOW_MS:
		print("world: applying %s took %.1f ms" % [cmd.op, ms])
	return inverse


## A player whose garden no longer matches the host's asks for it whole.
@rpc("any_peer", "reliable")
func _resend() -> void:
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


## The player's latest undo (or redo) step that nobody else has changed anything of since, taken off its stack; steps
## others built on are dropped on the way. A dropped wipe takes every step below it, all on a garden it took away.
## Without `take`, finds it and changes no stack.
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


## A build's garden data `now` with a `reshape`'s `data` applied: a roof's and the paint's by the entries they name.
static func reshaped(now: Dictionary, data: Dictionary) -> Dictionary:
	var out := now.merged(data, true)
	if data.has("roof"):
		out.roof = now.roof.merged(data.roof, true)
	if data.has("paint"):
		out.paint = PackedInt32Array(now.paint)
		for e in data.paint:
			out.paint[e] = data.paint[e]
	return out


## What a build from the garden's table `of` counts as in the frame budget.
static func _units(of: String, d: Dictionary) -> Dictionary:
	match of:
		"walls":
			return Budget.wall(d)
		"stairs":
			return Budget.stairs(d)
		"decorations":
			return Budget.decoration(d.style)
		"easels":
			return {"easel": 1}
	return {"boulder": Budget.boulder(d.scale)}


## A ground stroke as the garden keeps it, from its command; given its `id`, the command that lays it again.
static func _ground(d: Dictionary, id := -1) -> Dictionary:
	var out := {"kind": d.kind, "stamps": d.stamps}
	if d.has("style"):
		out.style = d.style
	if id >= 0:
		out.merge({"op": "ground", "id": id})
	return out


## What a command changes, as keys `touched` tracks: a wall, a painted group, patches of ground and meadow.
func _keys(cmd: Dictionary) -> Array:
	match cmd.op:
		"wall":
			var out := Array(cmd.ids).map(func(id: int) -> String: return "w%d" % id)
			for w: Dictionary in cmd.walls:
				out.append_array(Array(w.on).map(func(id: int) -> String: return "w%d" % id))
			return out
		"unwall":
			return Array(cmd.ids).map(func(id: int) -> String: return "w%d" % id)
		"reshape":
			return ["%s%d" % [{"walls": "w", "stairs": "q", "boulders": "b", "decorations": "d", "easels": "e"}[cmd.of], cmd.id]]
		"plant":
			return ["p%d" % cmd.id]
		"tree":
			if cmd.group != 0:
				return ["p%d" % cmd.group]
			# A move's inverse carries where it stood, so its undo entry keys both patches.
			var at: Vector3 = cmd.get("at", flora.groups[0][cmd.index].anchor)
			return ["m%d,%d" % [floori(at.x / PATCH), floori(at.z / PATCH)]]
		"stairs":
			return ["q%d" % cmd.id] + Array(cmd.stairs.on).map(func(id: int) -> String: return "w%d" % id)
		"unstairs", "path", "unpath", "ground", "unground", "restone":
			return ["q%d" % cmd.id]
		"season":
			return ["season"]
		"easel", "uneasel":
			return ["e%d" % cmd.id]
		"decoration":
			return ["d%d" % cmd.id] + (["w%d" % cmd.wall] if cmd.wall >= 0 else [])
		"undecoration":
			return ["d%d" % cmd.id]
		"boulder", "unboulder":
			return ["b%d" % cmd.id]

		"ponds":
			return (cmd.get("put", {}).keys() + cmd.get("drop", [])).map(func(g: Vector2i) -> String: return "o%d,%d" % [g.x, g.y])
		"paint", "unpaint", "sheet":
			return ["e%d" % cmd.easel]
		"mix":
			return ["x%d" % cmd.easel]
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
					var at: Vector3 = meadow[i].anchor
					out["m%d,%d" % [floori(at.x / PATCH), floori(at.z / PATCH)]] = true
			return out.keys()
		"heights":
			var r := Terrain.world_rect(cmd.cells)
			var out := []
			for j in range(floori(r.position.y / PATCH), floori(r.end.y / PATCH) + 1):
				for i in range(floori(r.position.x / PATCH), floori(r.end.x / PATCH) + 1):
					out.append("t%d,%d" % [i, j])
			return out
	return []


## Changes the garden by one command and returns the command that takes it back. The author's ghost
## goes first, so a stroke's hump is not counted twice under walls laid on the new ground; a painted
## stroke's goes last, to stand until the plants it shows have grown, and so does a turned sky's, which only shows the
## garden's sky again if the host turned it down.
func _apply(cmd: Dictionary) -> Dictionary:
	var last: bool = cmd.op == "sky" or cmd.op == "plant" and not cmd.kind in Flora.PLACED
	if flora != null and cmd.op in GROWS_FIRST:
		flora.grow_now()
	var mine: bool = cmd.get("by") == me() and cmd.has("token")
	# An undo or redo carries its own token but no walls in hand.
	var handed := mine and _done.has(cmd.token)
	if mine and not last:
		_settle(cmd.token)
	var inverse := {}
	match cmd.op:
		"wall":
			for i in cmd.ids.size():
				state.walls[cmd.ids[i]] = cmd.walls[i].duplicate(true)
				wall_tool.put(cmd.ids[i], handed)
				_account("w%d" % cmd.ids[i], Budget.wall(state.walls[cmd.ids[i]]))
				_floor_mark(cmd.ids[i])
			inverse = {"op": "unwall", "ids": cmd.ids}
		"unwall":
			inverse = _take("walls", cmd.ids)
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
			elif cmd.of == "stairs":
				stairs.settle(cmd.id)
			elif cmd.of == "decorations":
				if decorations != null:
					decorations.settle(cmd.id)
			elif cmd.of == "easels":
				if easels != null:
					easels.stand(cmd.id, now.at, now.yaw)
			elif boulders != null:
				boulders.put(cmd.id, now)
			_account(_keys(cmd)[0], _units(cmd.of, now))
			if cmd.of == "walls":
				_floor_mark(cmd.id)
			inverse = {"op": "reshape", "of": cmd.of, "id": cmd.id, "data": before}
		"stairs":
			state.stairs[cmd.id] = cmd.stairs.duplicate(true)
			stairs.put(cmd.id, state.stairs[cmd.id])
			_account("q%d" % cmd.id, Budget.stairs(cmd.stairs))
			inverse = {"op": "unstairs", "id": cmd.id}
		"unstairs":
			inverse = _take("stairs", [cmd.id])
		"path":
			state.paths[cmd.id] = cmd.path.duplicate(true)
			paths.put(cmd.id, state.paths[cmd.id])
			_account("q%d" % cmd.id, Budget.path(cmd.path))
			inverse = {"op": "unpath", "id": cmd.id}
		"unpath":
			inverse = {"op": "path", "id": cmd.id, "path": state.paths[cmd.id]}
			state.paths.erase(cmd.id)
			paths.take(cmd.id)
			_account("q%d" % cmd.id, {})
		"ground":
			state.grounds[cmd.id] = _ground(cmd)
			var stroke := Ground.Stroke.new(cmd.kind as Ground.Kind, cmd.get("style", 0))
			stroke.stamps = cmd.stamps
			_strokes[cmd.id] = stroke
			Ground.lay(stroke, cmd.id)
			_account("q%d" % cmd.id, Budget.ground(cmd))
			inverse = {"op": "unground", "id": cmd.id}
		"unground":
			inverse = _ground(state.grounds[cmd.id], cmd.id)
			state.grounds.erase(cmd.id)
			Ground.lift(_strokes[cmd.id])
			_strokes.erase(cmd.id)
			_account("q%d" % cmd.id, {})
		"restone":
			inverse = {"op": "restone", "id": cmd.id, "style": state.grounds[cmd.id].style}
			state.grounds[cmd.id].style = cmd.style
			Ground.restyle(cmd.id, cmd.style)
		"plant":
			var g := cmd.duplicate(true)
			for k in ["op", "seq", "by", "token", "id"]:
				g.erase(k)
			var plants := flora.grow(cmd.id, g)
			g.size = plants.size()
			g.hidden = {}
			if g.kind in Flora.PLACED:
				g.places = {}
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
			for k: String in ["species", "scale", "moss"]:
				if not cmd.has(k):
					continue
				inverse[k] = g[k].get(cmd.index, FloraLayout.Species.OAK if k == "species" else false if k == "moss" else 1.0)
				if cmd[k] == (FloraLayout.Species.OAK if k == "species" else false if k == "moss" else 1.0):
					g[k].erase(cmd.index)
				else:
					g[k][cmd.index] = cmd[k]
			if flora.species_of(first) >= 0:
				flora.set_look(first, g.species.get(cmd.index, FloraLayout.Species.OAK), g.scale.get(cmd.index, 1.0))
				flora.set_moss(first, g.moss.get(cmd.index, false))
		"heights":
			inverse = {"op": "heights", "cells": cmd.cells, "values": Terrain.read(cmd.cells)}
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
				# A build an earlier taking took with what it stood on is not there to reshape.
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
		"easel":
			state.easels[cmd.id] = {"at": cmd.at, "yaw": cmd.yaw, "strokes": cmd.strokes.duplicate(), "mix": cmd.mix}
			if easels != null:
				easels.put(cmd.id, state.easels[cmd.id])
			_account("e%d" % cmd.id, {"easel": 1})
			inverse = {"op": "uneasel", "id": cmd.id}
		"uneasel":
			var e: Dictionary = state.easels[cmd.id]
			inverse = {"op": "easel", "id": cmd.id, "at": e.at, "yaw": e.yaw, "strokes": e.strokes, "mix": e.mix}
			state.easels.erase(cmd.id)
			if easels != null:
				easels.take(cmd.id)
			_account("e%d" % cmd.id, {})
		"paint":
			state.easels[cmd.easel].strokes.append(cmd.stroke)
			if easels != null:
				easels.painted(cmd.easel, cmd.stroke, handed)
			inverse = {"op": "unpaint", "easel": cmd.easel}
		"unpaint":
			var strokes: Array = state.easels[cmd.easel].strokes
			inverse = {"op": "paint", "easel": cmd.easel, "stroke": strokes.pop_back()}
			if easels != null:
				easels.repaint(cmd.easel, strokes)
		"mix":
			inverse = {"op": "mix", "easel": cmd.easel, "mix": state.easels[cmd.easel].mix}
			state.easels[cmd.easel].mix = cmd.mix
			if easels != null:
				easels.mixed(cmd.easel, cmd.mix, handed)
		"sheet":
			inverse = {"op": "sheet", "easel": cmd.easel, "strokes": state.easels[cmd.easel].strokes}
			state.easels[cmd.easel].strokes = cmd.strokes.duplicate()
			if easels != null:
				easels.repaint(cmd.easel, state.easels[cmd.easel].strokes)
		"decoration":
			state.decorations[cmd.id] = Commands._decoration(cmd)
			_account("d%d" % cmd.id, Budget.decoration(cmd.style))
			inverse = {"op": "undecoration", "id": cmd.id}
		"undecoration":
			inverse = _take("decorations", [cmd.id])
		"boulder":
			state.boulders[cmd.id] = Commands._boulder(cmd)
			if boulders != null:
				boulders.put(cmd.id, state.boulders[cmd.id])
			_account("b%d" % cmd.id, {"boulder": Budget.boulder(cmd.scale)})
			inverse = {"op": "unboulder", "id": cmd.id}
		"unboulder":
			var b: Dictionary = state.boulders[cmd.id]
			inverse = b.merged({"op": "boulder", "id": cmd.id})
			state.boulders.erase(cmd.id)
			if boulders != null:
				boulders.take(cmd.id)
			_account("b%d" % cmd.id, {})
	if cmd.op in DROWNING and flora != null:
		var back := _drown()
		if not back.is_empty():
			inverse = {"op": "batch", "cmds": [inverse, back]}
	if mine and last:
		_settle(cmd.token)
	applied.emit(cmd)
	if save_path != "" and not _keep_due and multiplayer.is_server():
		_keep_due = true
		_keep.call_deferred()
	return inverse


## The square metres pond `g` holds under water as it last filled: none for a pond the garden does not hold.
func _wet(g: Vector2i) -> int:
	var was: Array = _fills.get(g, [])
	return was[1].cells.size() if not was.is_empty() and was[1] != null else 0


## Takes out every tree and bush standing where water covers its root, as the delete tool takes one, so a pond never
## hides one that still stands; returns what brings them back, or {} for none.
func _drown() -> Dictionary:
	var by_group := {}
	for parts in flora.solids():
		if Water.drowned(parts[0].anchor):
			for p: Flora.Plant in parts:
				by_group.get_or_add(p.group, []).append(p.index)
	if by_group.is_empty():
		return {}
	for g in by_group:
		by_group[g] = PackedInt32Array(by_group[g])
	return _apply({"op": "show", "plants": by_group, "on": false})


## Whether `p` is part of a tree or bush whose root water covers, which may not stand.
func _drowned(p: Flora.Plant) -> bool:
	return p.pool in [flora.trunks, flora.foliage, flora.bushes] and Water.drowned(p.anchor)


## Of group `g`'s plants at `indices`, those that may stand.
func _dry(g: int, indices: PackedInt32Array) -> PackedInt32Array:
	var plants: Array = flora.groups.get(g, [])
	var out := PackedInt32Array()
	for i in indices:
		if i < 0 or i >= plants.size() or plants[i] == null or not _drowned(plants[i]):
			out.append(i)
	return out


## Takes the builds `ids` from the garden's table `of` (Commands.STANDS_ON), and with them everything standing on them,
## all the way up, and returns what brings all of it back, oldest builds first. What a batch took already, with what it
## stood on, is passed over.
func _take(of: String, ids: Array) -> Dictionary:
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
	for table: String in gone:
		assert(table in ["walls", "stairs", "decorations"], "World._take cannot take %s" % table)
	var back := []
	var walls: Array = gone.get("walls", {}).keys()
	walls.sort()
	for i in range(0, walls.size(), Commands.MAX_PIECES):
		var chunk := PackedInt32Array(walls.slice(i, i + Commands.MAX_PIECES))
		back.append({"op": "wall", "ids": chunk, "walls": Array(chunk).map(func(id: int) -> Dictionary: return state.walls[id])})
	for id: int in gone.get("stairs", {}):
		back.append({"op": "stairs", "id": id, "stairs": state.stairs[id]})
		state.stairs.erase(id)
		stairs.take(id)
		_account("q%d" % id, {})
	for id: int in gone.get("decorations", {}):
		back.append(state.decorations[id].merged({"op": "decoration", "id": id}))
		state.decorations.erase(id)
		_account("d%d" % id, {})
	walls.reverse()
	for id: int in walls:
		state.walls.erase(id)
		wall_tool.take(id)
		_account("w%d" % id, {})
		_floor_mark(id)
	return back[0] if back.size() == 1 else {"op": "batch", "cmds": back}


## Takes `cmd`'s ponds out and puts its new ones in, then fills every pond over the ground as it stands (Refill). A
## pond that holds no water any more, or whose water another's covers, goes: the ones `cmd` puts win, then the higher.
## What brings back the ponds as they were `before` goes on `inverse`. Only ponds whose fill read the `ground` the
## command changed, or at a new level, fill again. A refill worked out ahead (`_ahead`) is applied as it stands.
func _set_ponds(cmd: Dictionary, before: Dictionary, inverse: Dictionary, ground: Rect2i) -> void:
	for g in cmd.get("drop", []):
		state.ponds.erase(g)
	var put: Dictionary = cmd.get("put", {})
	state.ponds.merge(put, true)
	var r := _ready_refill
	if r == null or not r.matches(state.ponds, put, _fills, ground):
		r = Refill.make(state.ponds.duplicate(), put.duplicate(), _fills.duplicate(), ground, Terrain.read(Terrain.ALL))
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


## Hands a joining player this garden.
func welcome(id: int) -> void:
	_welcome.rpc_id(id, snapshot())


@rpc("authority", "reliable")
func _welcome(snap: Dictionary) -> void:
	if not (snap.get("cmds") is Array and typeof(snap.get("seq")) == TYPE_INT):
		push_error("world: the host sent a garden this one cannot read")
		return
	_awaiting = false
	restore(snap)


## Commands that rebuild this garden from an empty meadow, and the sequence number they stand for.
## Groups regrow in the order they were planted, so every machine's plant pools fill alike.
func snapshot() -> Dictionary:
	var cmds := []
	if sculpted:
		cmds.append({"op": "heights", "cells": Terrain.ALL, "values": Terrain.read(Terrain.ALL)})
	if not state.ponds.is_empty():
		cmds.append({"op": "ponds", "put": state.ponds.duplicate()})
	for id in state.stairs:
		cmds.append({"op": "stairs", "id": id, "stairs": state.stairs[id]})
	for id in state.paths:
		cmds.append({"op": "path", "id": id, "path": state.paths[id]})
	for id in state.grounds:
		cmds.append(_ground(state.grounds[id], id))
	for id in state.walls:
		cmds.append({"op": "wall", "ids": PackedInt32Array([id]), "walls": [state.walls[id]]})
	for id in state.easels:
		var e: Dictionary = state.easels[id]
		cmds.append({"op": "easel", "id": id, "at": e.at, "yaw": e.yaw, "strokes": e.strokes, "mix": e.mix})
	for id in state.decorations:
		cmds.append(state.decorations[id].merged({"op": "decoration", "id": id}))
	for id in state.boulders:
		cmds.append(state.boulders[id].merged({"op": "boulder", "id": id}))
	for id in state.groups:
		var g: Dictionary = state.groups[id]
		if g.kind != "meadow":
			var c := g.duplicate(true)
			for k in ["hidden", "size", "species", "scale", "moss", "places"]:
				c.erase(k)
			c.op = "plant"
			c.id = id
			cmds.append(c)
		if not g.hidden.is_empty():
			cmds.append({"op": "show", "plants": {id: PackedInt32Array(g.hidden.keys())}, "on": false})
		for i in g.get("species", {}).merged(g.get("scale", {})).merged(g.get("moss", {})).merged(g.get("places", {})):
			var c := {"op": "tree", "group": id, "index": i}
			for k in ["species", "scale", "moss", "places"]:
				if g.get(k, {}).has(i):
					c["at" if k == "places" else k] = g[k][i]
			cmds.append(c)
	if palette.season != Palette.SUMMER:
		cmds.append({"op": "season", "index": palette.season})
	if time != Daylight.DEFAULT:
		cmds.append({"op": "sky", "time": time})
	for c in cmds:
		c.seq = seq
		c.by = 1
	return {"format": FORMAT, "seq": seq, "cmds": cmds}


## Back to the empty meadow, then the snapshot's garden, and how many of its commands applied. Undo history
## goes with the old garden.
func restore(snap: Dictionary) -> int:
	settle()
	var applied: int = _hushed(func() -> int:
		_clear()
		Ground.clear()
		flora.clear_ghosts()
		stacks.clear()
		touched.clear()
		for t in _done.keys():
			_settle(t)
		restored.emit()
		return _rebuild(snap.cmds))
	seq = snap.seq
	flora.grow_now()
	loaded.emit()
	return applied


func _floor_mark(id: int) -> void:
	if _floor_marks.has(id):
		Ground.lift(_floor_marks[id])
		_floor_marks.erase(id)
	var d: Dictionary = state.walls.get(id, {})
	if d.is_empty() or not d.closed or d.fence or not d.has("roof") or not d.on.is_empty():
		return
	var mark := Ground.Stroke.new(Ground.Kind.EARTH)
	mark.stamps = WallLayout.floor_stamps(d.points)
	_floor_marks[id] = mark
	Ground.lay(mark, id)


## Runs `change` with the walls' sounds and the ground's rewear held until it has finished; what it returns.
func _hushed(change: Callable) -> Variant:
	wall_tool.quiet = true
	Ground.quiet = true
	var out: Variant = change.call()
	wall_tool.quiet = false
	Ground.quiet = false
	Ground.rewear()
	return out


## Back to the empty meadow, every one of its plants standing, in summer, the sun where a garden starts.
func _clear() -> void:
	for id in state.walls.keys():
		wall_tool.take(id)
	for id in state.stairs.keys():
		stairs.take(id)
	for id in state.paths.keys():
		paths.take(id)
	if easels != null:
		easels.clear()
	if boulders != null:
		boulders.clear()
	if water != null:
		water.reset()
	for id in _strokes:
		Ground.lift(_strokes[id])
	_strokes.clear()
	for id in _floor_marks:
		Ground.lift(_floor_marks[id])
	_floor_marks.clear()
	state = blank()
	_fills.clear()
	units = {}
	_units_of.clear()
	flora.reset()
	palette.season = Palette.SUMMER
	palette.apply()
	_show_sky(Daylight.DEFAULT)
	_grow_meadow()
	if sculpted:
		ground_grab.restore(Terrain.ALL, Terrain.base_heights())
		sculpted = false


## Applies a snapshot's commands, each checked against the garden as the ones before it left it; how many applied.
func _rebuild(cmds: Array) -> int:
	var applied := 0
	for sent in cmds:
		var cmd := Commands.clean(sent, state, true) if sent is Dictionary else {}
		if cmd.is_empty():
			push_error("world: skipped a snapshot command this garden cannot apply")
			continue
		cmd.erase("token")
		_apply(cmd)
		applied += 1
	return applied


## Hides the meadow's own flowers, bushes and trees, leaving its grass.
func _bare_meadow() -> void:
	var scenery := PackedInt32Array()
	for p: Flora.Plant in flora.groups[0]:
		if p.pool != flora.grass:
			scenery.append(p.index)
	var hidden: Dictionary = state.groups[0].hidden
	for i in flora.set_shown(0, scenery, false):
		hidden[i] = true
		Budget.add(units, _unit(0, flora.groups[0][i]), -1.0)


## What this machine shows of the garden, for comparing machines: every wall's data and laid stones, once laid,
## every plant group's standing plants, the ground, and the garden's share of the frame budget, which its bar shows.
func digest() -> Dictionary:
	flora.grow_now()
	for w: Wall in wall_tool.walls:
		w.lay_now()
	var heights := Array(Terrain.read(Terrain.ALL))
	var out := {"seq": seq, "walls": {}, "groups": {}, "ground": hash(heights), "heights": [heights.min(), heights.max()]}
	for w: Wall in wall_tool.walls:
		out.walls[str(w.id)] = {"data": var_to_str(state.walls[w.id]), "stones": w.layout.stones.size(), "height": w.layout.height, "floors": Array(w.layout.floors)}
	for g in flora.groups:
		var shown := 0
		var spot := Vector3.ZERO
		for p: Flora.Plant in flora.groups[g]:
			if p != null and p.shown():
				shown += 1
				spot += p.anchor
		var species := []
		var scales := []
		for p: Flora.Plant in flora.groups[g]:
			if p != null and p.pool == flora.trunks:
				species.append(flora.species_of(p))
				scales.append(snappedf(flora.scale_of(p), 0.001))
		out.groups[str(g)] = {"kind": state.groups[g].kind, "plants": flora.groups[g].size(), "shown": shown, "spot": var_to_str(spot.snapped(Vector3.ONE * 0.01)), "species": species, "scale": scales}
	out.stairs = state.stairs.duplicate(true)
	out.paths = state.paths.keys()
	out.pond_levels = state.ponds.keys().map(func(g: Vector2i) -> String: return "%s %.3f" % [g, state.ponds[g]])
	out.grounds = state.grounds.keys()
	Ground.settle()
	out.mask = hash(Ground.laid.get_data())
	out.ponds = water.ponds.size() if water != null else 0
	out.season = palette.season
	out.easels = {}
	for id in state.easels:
		var e: Dictionary = state.easels[id]
		out.easels[str(id)] = {"at": var_to_str(e.at.snapped(Vector3.ONE * 0.01)), "strokes": e.strokes.size(), "paint": hash(var_to_str(e.strokes)), "mix": hash(e.mix)}
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
