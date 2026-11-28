class_name Shelf
extends RefCounted

## The gardens a player keeps, a file each in `dir`, and each one's backups from five minutes to two hours back. With
## no `dir` nothing is kept, as in scripted runs.

## Minutes back a garden can be returned to.
const BACKUPS: Array[int] = [5, 10, 60, 120]
## Seconds: a garden changed is backed up at most this often.
const EVERY := 300
## Seconds: an age this long or longer is offered only the first backup of each span, so a few files cover two hours.
const SPAN := 1800
## Gardens a shelf holds.
const MOST := 12
const STARTS := ["cottage", "tower", "hamlet"]

var dir := ""
var current := 1
## Every garden with a file, and the current one.
var gardens: Array[int] = []
## By garden, Unix seconds of its backups, oldest first.
var backups := {}
var clock := func() -> int: return int(Time.get_unix_time_from_system())
## By garden, its `World.seq` when last left, so a diorama is built again only when its garden changed.
var seqs := {}
var _shown := -1
var _seen := -1
var _seen_msec := 0


static func open(at: String) -> Shelf:
	var s := Shelf.new()
	s.dir = at
	if at == "":
		s.gardens = [s.current]
		return s
	DirAccess.make_dir_recursive_absolute(at)
	for f in DirAccess.get_files_at(at):
		var name := f.get_basename()
		if f.get_extension() == "save" and name.is_valid_int():
			s.gardens.append(name.to_int())
		elif f.get_extension() == "backup" and name.get_slice_count("-") == 2 and name.get_slice("-", 0).is_valid_int() and name.get_slice("-", 1).is_valid_int():
			(s.backups.get_or_add(name.get_slice("-", 0).to_int(), []) as Array).append(name.get_slice("-", 1).to_int())
	for times: Array in s.backups.values():
		times.sort()
	var chosen := FileAccess.get_file_as_string(at.path_join("current")).strip_edges() if FileAccess.file_exists(at.path_join("current")) else ""
	s.gardens.sort()
	s.current = chosen.to_int() if chosen.is_valid_int() else s.gardens.front() if not s.gardens.is_empty() else 1
	if not s.current in s.gardens:
		s.gardens.append(s.current)
		s.gardens.sort()
	return s


func path(id: int) -> String:
	return "" if dir == "" else dir.path_join("%d.save" % id)


func backup_path(id: int, at: int) -> String:
	return dir.path_join("%d-%d.backup" % [id, at])


## The garden `file` holds, or null when it holds none.
static func read(file: String) -> Variant:
	return bytes_to_var(FileAccess.get_file_as_bytes(file)) if file != "" and FileAccess.file_exists(file) else null


func fresh() -> int:
	return gardens.max() + 1


## Puts `bytes`, a garden, on the shelf as a new one beside this; its id.
func add(bytes: PackedByteArray) -> int:
	var id := fresh()
	gardens.append(id)
	Main.replace_file(ProjectSettings.globalize_path(path(id)), bytes)
	return id


## A backup of this garden, `bytes`, as taken at Unix second `at`.
func add_backup(at: int, bytes: PackedByteArray) -> void:
	Main.replace_file(ProjectSettings.globalize_path(backup_path(current, at)), bytes)
	var times: Array = backups.get_or_add(current, [])
	times.append(at)
	times.sort()


func full() -> bool:
	return gardens.size() >= MOST


func choose(id: int) -> void:
	current = id
	if not id in gardens:
		gardens.append(id)
		gardens.sort()
	if dir != "":
		Main.replace_file(ProjectSettings.globalize_path(dir.path_join("current")), str(id).to_utf8_buffer())


## By age in BACKUPS, the backup time of the current garden offered for it; an age is left out when its backup is
## offered for a shorter one.
func offered() -> Dictionary:
	return Shelf.offer(backups.get(current, []), clock.call())


## The youngest backup at least each age old, of those each age chooses from.
static func offer(times: Array, now: int) -> Dictionary:
	var out := {}
	var given := {}
	for minutes in BACKUPS:
		var best := -1
		for t: int in _candidates(times, minutes):
			if now - t >= minutes * 60 and t > best:
				best = t
		if best >= 0 and not given.has(best):
			out[minutes] = best
			given[best] = true
	return out


## The backups worth keeping at `now`: each one offered now, or one that will be once it is old enough.
static func kept(times: Array, now: int) -> Array:
	var offered := offer(times, now).values()
	return times.filter(func(t: int) -> bool:
		return t in offered or BACKUPS.any(func(minutes: int) -> bool: return now - t < minutes * 60 and t in _candidates(times, minutes)))


## Ages shorter than SPAN choose from every backup, longer ones from the first of each SPAN.
static func _candidates(times: Array, minutes: int) -> Array:
	if minutes * 60 < SPAN:
		return times
	var spans := {}
	for t: int in times:
		var span := floori(float(t) / SPAN)
		if not spans.has(span) or t < spans[span]:
			spans[span] = t
	return spans.values()


## On the main thread as the current garden is kept: the backup `write` makes of it then, if one is due, and the
## backups it no longer needs.
func back_up(force := false) -> Dictionary:
	if dir == "":
		return {}
	var now: int = clock.call()
	var times: Array = backups.get_or_add(current, [])
	if not force and not times.is_empty() and now - times.back() < EVERY:
		return {}
	if times.has(now):
		return {}
	times.append(now)
	var keep := Shelf.kept(times, now)
	var drop := times.filter(func(t: int) -> bool: return not t in keep).map(func(t: int) -> String: return ProjectSettings.globalize_path(backup_path(current, t)))
	backups[current] = keep
	return {"to": ProjectSettings.globalize_path(backup_path(current, now)), "drop": drop}


## On any thread.
static func write(job: Dictionary, bytes: PackedByteArray) -> void:
	if job.is_empty():
		return
	Main.replace_file(job.to, bytes)
	for p: String in job.drop:
		DirAccess.remove_absolute(p)


## `seq`, of a garden that just opened, is shown at once.
func show(seq: int) -> void:
	_seen = seq
	_shown = seq


## `seq` once it has stood a few seconds, so a garden being built has its diorama built again only when building
## pauses.
func shown(seq: int) -> int:
	if seq != _seen:
		_seen = seq
		_seen_msec = Time.get_ticks_msec()
	elif Time.get_ticks_msec() - _seen_msec >= World.KEEP_EVERY * 1000.0:
		_shown = seq
	return _shown


## Starting build `name` laid on `terrain`, as `World.snapshot` has a garden: each command numbered as the host
## numbers them (`World._order`), so what is built on it next is numbered past them.
static func start(name: String, terrain: Terrain, format: String) -> Dictionary:
	var cmds := []
	var houses: Array = {
		"cottage": [[Vector3(0, 0, -6), 0.3, false]],
		"tower": [[Vector3(0, 0, -7), 0.0, true], [Vector3(4.5, 0, -5), -0.5, false]],
		"hamlet": [[Vector3(-5, 0, -7), 0.4, false], [Vector3(2, 0, -9), -0.2, false], [Vector3(6, 0, -3), -1.2, false]],
	}[name]
	var trees: Array = {
		"cottage": [Vector2(-4, -3), Vector2(4, -9), Vector2(5, -2)],
		"tower": [Vector2(-4, -4), Vector2(-3, -10)],
		"hamlet": [Vector2(-1, -3), Vector2(-9, -2), Vector2(9, -9), Vector2(0, -14)],
	}[name]
	for h: Array in houses:
		var at := WallTool.stance(terrain.ground(h[0].x, h[0].z), h[1], h[2])
		var w := Wall.new(name.hash() + cmds.size(), null, terrain)
		var d := w.data()
		w.free()
		d.closed = true
		d.top = WallLayout.Top.CAP
		d.height = at.height
		d.points = PackedVector3Array(WallTool.outline(at))
		var roof := RoofLayout.new()
		roof.kind = RoofLayout.Kind.CONE if at.round else RoofLayout.Kind.GABLE
		roof.seed = d.seed
		roof.pitch = at.pitch
		roof.overhang = at.overhang
		roof.center = at.center
		roof.radius = at.size.x * 0.5
		d.roof = roof.data()
		cmds.append({"op": "wall", "ids": PackedInt32Array([(cmds.size() + 1) * Commands.MAX_PIECES]), "walls": [d]})
	for i in trees.size():
		var p: Vector2 = trees[i]
		cmds.append({"op": "plant", "kind": "tree" if i % 3 != 2 else "bush", "seed": name.hash() + i, "at": terrain.ground(p.x, p.y), "id": cmds.size() + 1})
	for c: Dictionary in cmds:
		c.seq = cmds.size()
		c.by = 1
	return {"format": format, "seq": cmds.size(), "cmds": cmds}
