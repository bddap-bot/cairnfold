extends SceneTree

const Probe = preload("res://../tests/support/house_leaks.gd")
const SEEDS := [8756, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 60]
const SEALED_SEEDS := [24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 60]
## Escapes the dense sweep found, as [origin, direction]: the normal sphere is too sparse to meet them again.
const SEALED_RAYS := {
	35: [
		# The wall corner above a crossing bowed deck must seal without the deck's hanging mortar bed.
		[Vector3(-0.5, 1.33116233348846, -17.8215808868408), Vector3(-0.901065587997437, 0.43359375, -0.008791608735919)],
	],
	31: [
		# Past lintel ends and over a lintel's top, where the joint had no mortar behind it.
		[Vector3(-0.5, 2.10659718513489, -20.5), Vector3(0.0616170428693295, -0.008544921875, -0.998063266277313)],
		[Vector3(0.5, 2.10659718513489, -19.5), Vector3(-0.284503400325775, -0.004638671875, -0.958663821220398)],
		[Vector3(0.0, 1.91231036186218, -17.3493766784668), Vector3(0.0930395945906639, 0.034912109375, -0.995050132274628)],
		[Vector3(0.5, 1.80514013767242, -14.1987533569336), Vector3(0.995217204093933, -0.061279296875, 0.0760760083794594)],
		# Down through the floor seam where joined houses meet, where the older floor stopped short of the newer.
		[Vector3(0.0, 1.91231036186218, -17.3493766784668), Vector3(-0.610257267951965, -0.75390625, -0.243333980441093)],
		[Vector3(0.0, 1.80514013767242, -14.6987533569336), Vector3(-0.610257267951965, -0.75390625, -0.243333980441093)],
		[Vector3(0.0, 1.80514013767242, -14.6987533569336), Vector3(0.605869054794312, -0.76171875, -0.229580596089363)],
		[Vector3(0.0, 1.80514013767242, -14.6987533569336), Vector3(0.42256498336792, -0.86328125, -0.276015102863312)],
		[Vector3(0.5, 1.80514013767242, -14.1987533569336), Vector3(0.358669877052307, -0.80078125, -0.479692935943604)],
	],
}
var started := Time.get_ticks_msec()
var failures := 0
var main: Main
var inventory: Array = []
var ground_part: Dictionary


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _run() -> void:
	await process_frame
	_contract()
	var terrain := Probe.new()
	var ground := Terrain.build_mesh().get_faces()
	for i in ground.size():
		ground[i].y = Terrain.height_at(ground[i].x, ground[i].z)
	terrain.add_faces(ground, "terrain", -1)
	ground_part = terrain.parts[0]
	var seeds := SEEDS.duplicate()
	var nightly := OS.get_cmdline_user_args().has("--leak-sweep")
	if nightly:
		for i in 64:
			seeds.append(1000 + i)
	var requested := OS.get_environment("HOUSE_LEAK_SEED")
	if not requested.is_empty():
		seeds = [int(requested)]
	for seed_value in seeds:
		await _house(seed_value, 4096 if nightly else 256)
	var elapsed := Time.get_ticks_msec() - started
	var path := OS.get_environment("HOUSE_LEAK_REPORT")
	if not path.is_empty():
		FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify({"cases": inventory, "milliseconds": elapsed}, "\t"))
	print("tests: house leak inventory: %d cases in %.3f s (report only; promote repaired cases to gates)" % [inventory.size(), elapsed / 1000.0])
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _contract() -> void:
	var probe := Probe.new()
	var box := BoxMesh.new()
	box.size = Vector3(4, 4, 4)
	probe.add_faces(box.get_faces(), "shell", 1)
	var w := Wall.new(1, null)
	w.id = 1
	var room: Array[Wall] = [w]
	for dir in Probe.directions(256):
		_check(probe.probe(Vector3.ZERO, dir, room).status == "shell", "a closed rendered box contains every ray")
	probe.parts.clear()
	var faces := box.get_faces()
	var hole := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		if faces[i].z == -2.0 and faces[i + 1].z == -2.0 and faces[i + 2].z == -2.0:
			continue
		hole.append_array(faces.slice(i, i + 3))
	probe.add_faces(hole, "shell-with-hole", 1)
	_check(probe.probe(Vector3.ZERO, Vector3.FORWARD, room).status == "leak", "removing rendered triangles creates a leak")
	var outside := box.get_faces()
	for i in outside.size():
		outside[i] += Vector3(0, 0, -8)
	probe.add_faces(outside, "unrelated-building", 2)
	_check(probe.probe(Vector3.ZERO, Vector3.FORWARD, room).status == "leak", "hitting another building through a gap still leaks")
	probe.parts.pop_back()
	probe.add_faces(outside, "ground-or-water", -1)
	_check(probe.probe(Vector3.ZERO, Vector3.FORWARD, room).status == "leak", "outside ground/water cannot plug a room's gap")
	w.layout.points = WallLayout.rectangle(Vector3(-3, 0, 0), Vector3(3, 0, 0), 4.0)
	w.layout.closed = true
	w.layout.height = 3.0
	for opening in [Vector4(3, 1.5, 0, 1), Vector4(3, 0.3, 0, 1), WallLayout.archway(3)]:
		w.layout.openings.assign([opening])
		w.layout.build(func(_x: float, _z: float) -> float: return 0.0)
		var y := 1.5 if opening.y == 1.5 else 0.8
		var origin := Vector3(0, w.layout.samples[0].y + y, 0)
		_check(Probe.aperture(w, origin, Vector3.FORWARD, 10.0), "window, door and arch interiors are intended openings")
		_check(not Probe.aperture(w, origin, Vector3.FORWARD, 1.0), "an opening behind the first hit cannot excuse a leak")
		_check(not Probe.aperture(w, origin + Vector3.RIGHT * 2.0, Vector3.FORWARD, 10.0), "solid wall beside an opening is not exempt")
		_check(not Probe.aperture(w, origin + Vector3.UP * 3.0, Vector3.FORWARD, 10.0), "space above an opening is not exempt")
	w.free()
	_check(Probe.directions(256) == Probe.directions(256), "ray sets repeat exactly")


func _commands(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var length := rng.randf_range(4.5, 7.0)
	var depth := rng.randf_range(3.0, 4.5)
	var shape := seed_value % 4
	var center := Vector3(0, 0, -20)
	if seed_value == 8756:
		length = 7.75
		depth = 4.5
	var w := Wall.new(seed_value, null)
	w.layout.points = WallLayout.circle(center, depth * 0.5) if shape == 1 else WallLayout.rectangle(center - Vector3.RIGHT * length * 0.5, center + Vector3.RIGHT * length * 0.5, depth)
	w.layout.height = 2.4 if seed_value == 8756 else 2.7
	w.layout.rise = 1.2 if seed_value % 3 == 0 else 0.0
	w.layout.closed = true
	w.layout.top = seed_value % WallLayout.Top.size()
	w.layout.plaster = shape != 1 and seed_value % 3 != 1
	w.layout.plinth_plaster = seed_value % 2 == 0
	w.layout.timber_style = -1 if seed_value % 3 == 0 else 0
	if seed_value == 60:
		w.layout.height = 5.4
	w.layout.gable_end = seed_value % WallLayout.GableEnd.size()
	w.layout.openings.assign([WallLayout.archway(length * 0.5)] if seed_value % 2 == 0 else [Vector4(length * 0.5, 1.5, 0, 1), Vector4(length + depth * 0.5, 0.3, 0, 1)])
	var r := RoofLayout.new()
	r.kind = RoofLayout.Kind.CONE if shape == 1 else RoofLayout.Kind.GABLE
	r.center = center
	r.radius = depth * 0.5
	r.pitch = 0.0 if seed_value % 5 == 0 else 1.4
	r.curve = [-0.5, 0.0, 0.5][seed_value % 3]
	r.seed = seed_value
	r.thatch = seed_value % 4 == 3
	if seed_value == 8756:
		w.layout.plaster = false
		w.layout.gable_end = WallLayout.GableEnd.WALL
		w.layout.openings = []
		r.pitch = 1.2
		r.curve = -RoofLayout.CURVE
	w.add_roof(r)
	var data := w.data()
	w.free()
	var commands := [{"op": "wall", "walls": [data]}]
	if shape == 3:
		for offset in [depth * 0.6, depth * 1.2]:
			var other: Dictionary = data.duplicate(true)
			var moved: PackedVector3Array = other.points
			for i in moved.size():
				moved[i] += Vector3(0, 0, offset)
			other.points = moved
			other.roof.center += Vector3(0, 0, offset)
			commands.append({"op": "wall", "walls": [other]})
	if shape == 2:
		var plan := WallPlan.new([], PackedVector3Array(), seed_value)
		plan.seed = seed_value
		plan.plaster = data.plaster
		var stroke: Array[Vector3] = []
		for i in 7:
			stroke.append(center + Vector3(lerpf(-length, length, i / 6.0), 0, sin(i * 0.8) * depth * 0.3))
		var layouts := plan.pieces(stroke, Terrain.height_at)
		for layout in layouts:
			var wall := Wall.new(seed_value, null)
			wall.layout = layout
			commands.append({"op": "wall", "walls": [wall.data()]})
			wall.free()
	return commands

func _house(seed_value: int, count: int) -> void:
	main.world.restore({"seq": 0, "cmds": []})
	await process_frame
	var commands := _commands(seed_value)
	_check(not commands.is_empty(), "seed produces build commands")
	_check(var_to_str(commands) == var_to_str(_commands(seed_value)), "seed %d commands repeat" % seed_value)
	for cmd in commands:
		main.world._order(cmd, 1)
	main.tool._relay_due()
	for w in main.tool.walls:
		w.lay_now()
	_check(main.tool._due.is_empty() and main.tool.walls.all(func(w: Wall) -> bool: return not w.laying()), "all command geometry has settled")
	var room: Array[Wall] = main.tool.walls.duplicate()
	_check(room.size() == commands.size(), "seed %d accepted every real build command" % seed_value)
	if room.is_empty():
		return
	if seed_value == 35:
		for w in room:
			for piece in w.roof.mortar + w.roof.tiles:
				var x: Transform3D = piece.xform
				if piece.kind not in WallLayout.DECK_PIECES or w.layout.joined.any(func(other: Massing) -> bool: return Massing.encloses(Vector2(x.origin.x, x.origin.z), other.inner)):
					continue
				for c in WallLayout.BOX:
					var p: Vector3 = x * c
					_check(not w.layout.joined.any(func(other: Massing) -> bool: return Massing.encloses(Vector2(p.x, p.z), other.centre)), "curved join keeps deck corners outside the adjoining ceiling")
	var probe := Probe.new()
	for w in room:
		probe.add_wall(w)
	probe.parts.append(ground_part)
	var record := {"seed": seed_value, "totals": {"shell": 0, "opening": 0, "leak": 0}, "groups": {}, "collision_hits_on_render_leaks": 0, "commands": var_to_str(commands), "rays": []}
	for w in room:
		if not w.layout.closed:
			continue
		var center := w.massing.rect.get_center()
		for floor_y in w.layout.floors:
			var ceiling := w.roof.height_at(center.x, center.y) - 0.25
			for other_floor in w.layout.floors:
				if other_floor > floor_y:
					ceiling = minf(ceiling, other_floor - 0.25)
			for offset in [Vector2.ZERO, Vector2(-0.5, -0.5), Vector2(0.5, 0.5)]:
				var origin := Vector3(center.x + offset.x, lerpf(floor_y, ceiling, 0.5), center.y + offset.y)
				_check(w.massing.holds(origin), "seed %d probe starts inside its room" % seed_value)
				for direction in Probe.directions(count):
					_trace(probe, origin, direction, room, w, record)
		if seed_value == 8756:
			# The cap-band regression needs near-wall rays: exterior timber can mask an inner cavity.
			for side in 4:
				var corners := w.layout.corners()
				var end: float = corners[side + 1] if side < 3 else w.layout.length()
				for i in range(1, 20):
					var f := w.layout.frame_at(lerpf(corners[side], end, i / 20.0))
					var outward: Vector3 = -w.layout.inner_side() * f.tangent.cross(Vector3.UP)
					for dy in [0.01, 0.03, 0.05, 0.07, 0.09, 0.11, 0.13]:
						var target: Vector3 = f.point + Vector3.UP * (w.layout.height + dy)
						for slope in [-0.8, -0.6, -0.4, -0.2, 0.0, 0.2, 0.4, 0.6, 0.8]:
							var direction: Vector3 = (outward + Vector3.UP * slope).normalized()
							var origin: Vector3 = target - direction * 0.8
							if w.massing.holds(origin) and origin.y < w.roof.height_at(origin.x, origin.z) - RoofLayout.TORCHING_DROP:
								_trace(probe, origin, direction, room, w, record)
	for ray: Array in SEALED_RAYS.get(seed_value, []):
		var sealed: Dictionary = probe.probe(ray[0], ray[1], room)
		_check(sealed.status == "shell", "seed %d ray from %s along %s is sealed: %s" % [seed_value, ray[0], ray[1], sealed])
	if seed_value in SEALED_SEEDS:
		_check(record.totals.leak == 0, "sealed seed %d has %d escapes" % [seed_value, record.totals.leak])
	inventory.append(record)
	print("tests: leak seed=%d totals=%s groups=%s" % [seed_value, JSON.stringify(record.totals), JSON.stringify(record.groups)])
	if record.totals.leak > 0 and OS.get_cmdline_user_args().has("--leak-strict"):
		print("rebuild seed=%d commands=%s" % [seed_value, var_to_str(commands)])
		_check(false, "seed %d has %d render leaks" % [seed_value, record.totals.leak])


func _trace(probe: RefCounted, origin: Vector3, direction: Vector3, room: Array[Wall], w: Wall, record: Dictionary) -> void:
	var result: Dictionary = probe.probe(origin, direction, room)
	record.totals[result.status] += 1
	if result.status != "leak":
		return
	var collision_hit := main.tool.pick_building(origin, direction)
	var floor_hit := main.tool.pick_floor(origin, direction)
	if floor_hit.get("along", INF) < collision_hit.get("along", INF):
		collision_hit = floor_hit
	var collision: Variant = collision_hit.get("point")
	var p: Vector3 = collision if collision != null else Probe.exit_point(origin, direction, room)
	if collision != null:
		record.collision_hits_on_render_leaks += 1
	var band := "floor/foundation" if p.y < w.layout.floors[0] + 0.05 else ("wall/gable/roof" if p.y > w.layout.samples[0].y + w.layout.height - 0.1 else "wall")
	record.rays.append({"origin": _v(origin), "direction": _v(direction), "position": _v(p), "position_basis": "collision shell" if collision != null else "room volume exit", "band": band, "first_hit": result.first_hit, "first_hit_position": [] if result.first_hit == "sky" else _v(result.hit_position), "collision_hit": _v(collision) if collision != null else []})
	if not record.groups.has(band):
		record.groups[band] = {"count": 0, "position": _v(p), "origin": _v(origin), "direction": _v(direction), "nearest_parts": probe.neighbours(p), "first_hit": result.first_hit}
	record.groups[band].count += 1

static func _v(p: Vector3) -> Array:
	return [p.x, p.y, p.z]
