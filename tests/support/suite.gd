extends SceneTree

## What every headless test shares: failures counted and reported on the `tests:` and `FAIL:` lines scripts/test.sh
## reads, and an exit through Main.quit, which waits for playing sounds. A test runs under `--fixed-fps 60`, as
## scripts/test.sh runs it: every frame is then 1/60 s, so frame deltas, timers and Driver steps count frames, where
## without it they take the host's clock and a loaded host changes what a frame holds.
## Seconds of the host's time an until() waits before it calls the wait a hang.
const HANG := 120

var failures := 0
var main: Main


static func _static_init() -> void:
	Budget.frame_deadline = false


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## Which of earth, sand and stone `marks`' garden ground at (x, z) holds most of, as the terrain shader shows it.
static func kind_at(marks: Ground, x: float, z: float) -> Ground.Kind:
	var c := marks._texel(x, z, marks.laid)
	return Ground.Kind.STONE if c.g >= 0.5 else Ground.Kind.SAND if c.a > c.r else Ground.Kind.EARTH


## Whether `marks`' garden earth at (x, z) is a bed's.
static func tilled(marks: Ground, x: float, z: float) -> bool:
	return marks._texel(x, z, marks.laid).b8 & Ground.TILLED != 0


func finish() -> void:
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


## Boots the game with `args` as if launched with them, besides any this run was launched with, on one session seed, so
## every run lays the same garden: a build's seed, and so its clutter, is drawn from the generator Main seeds, and a
## check met by most gardens but not all would fail one run in several, loaded or not.
func boot_main(args := {}) -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.args = args
	main.rng_seed = 1
	root.add_child(main)


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Waits frame by frame until `done` holds, and whether it did. No frame count bounds it: worker threads and sockets keep
## the host's clock while frames run as fast as it allows, so a loaded host outruns any count. A wait still unmet after
## HANG of the host's own time fails as `what` instead of stalling the run.
func until(done: Callable, what: String) -> bool:
	var start := Time.get_ticks_msec()
	while not done.call():
		if Time.get_ticks_msec() - start > HANG * 1000:
			check(false, what)
			return false
		await process_frame
	return true


## A straight wall `length` along x on flat ground: its windows as (s, sill) cut first, then its archways at `arches`.
static func straight_wall(length: float, height: float, arches: Array[float] = [], seed := 1, windows: Array[Vector2] = []) -> WallLayout:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(length, 0, 0)]
	w.height = height
	w.openings.assign(windows.map(func(v: Vector2) -> Vector4: return Vector4(v.x, v.y, 0, 1)))
	w.openings.append_array(arches.map(WallLayout.archway))
	w.seed = seed
	w.build(Terrain.flat)
	return w


## A 7×5 house from x 0 to 7 and z -2.5 to 2.5, an archway in the middle of the wall at z -2.5 and a window in the
## middle of the wall at z 2.5, its roof bearing `dormers`.
static func lit_house(cover := WallLayout.Cover.ROOF, dormers: Array[Vector2] = [], at := Vector3.ZERO) -> Lamps.Room:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(at, at + Vector3(7, 0, 0), 5)
	w.closed = true
	w.cover = cover
	w.top = WallLayout.Top.CAP
	w.height = 2.4
	w.openings.assign([3.5].map(WallLayout.archway))
	w.openings.append_array([Vector4(15.5, 1.6, 0, 1)])
	w.build(Terrain.flat)
	var roof: RoofLayout = null
	if cover == WallLayout.Cover.ROOF:
		roof = RoofLayout.new()
		roof.pitch = 2.5
	var massing := Massing.of(w, roof)
	if massing.roof != null:
		massing.roof.dormers = dormers
	return Lamps.Room.of(w, massing, massing.roof)


## The data a wall sends: `with`'s fields, the rest as a fresh Wall has them.
static func wall_data(with: Dictionary) -> Dictionary:
	var w := Wall.new(0, null, Terrain.new())
	var d := w.data()
	w.free()
	d.merge(with, true)
	return d


## The roof a wall sends: `with`'s fields, the rest as a fresh RoofLayout has them.
static func roof_data(with: Dictionary) -> Dictionary:
	return RoofLayout.new().data().merged(with, true)


## Lays `h`'s walls on flat ground and seats its roof on them, as a garden's wall does.
static func lay_house(h: Dictionary) -> void:
	var w: WallLayout = h.wall
	w.build(Terrain.flat)
	w.seat(h.roof)
	h.roof.build()
	w.hide_roof(h.roof)


## Where the stress scene's `<phase>/aerial` view stands in `steps`, -1 when it has none; its `<phase>/<view>` views are
## checked to stand too.
func aerial_at(steps: Array, phase: String, views: Array[String] = ["ground"]) -> int:
	var at := steps.find_custom(func(s: Dictionary) -> bool: return s.get("name", "") == phase + "/aerial")
	check(at >= 0, "the stress scene has a %s/aerial phase" % phase)
	for v in views:
		check(steps.any(func(s: Dictionary) -> bool: return s.get("name", "") == "%s/%s" % [phase, v]), "the stress scene has a %s/%s phase" % [phase, v])
	return at


## The index of the last step at or before `steps[at]` whose op is `op`.
static func step_before(steps: Array, at: int, op: String) -> int:
	var i := at
	while steps[i].op != op:
		i -= 1
	return i


static func seeded_wall(points: PackedVector3Array) -> Dictionary:
	return wall_data({"points": points, "seed": 3})


static func avatar_file(name := "") -> String:
	return ProjectSettings.globalize_path("res://").path_join("../tests/avatars").path_join(name)


static func sloped_ground(x: float, z: float) -> float:
	return x * 0.1 + z * 0.05


## The tiles of roof `build`, or the stones of any other, of `kind`.
static func of_kind(build: Object, kind: String) -> Array:
	var list: Array = build.tiles if build is RoofLayout else build.stones
	return list.filter(func(s: Dictionary) -> bool: return s.kind == kind)


## Whether the box `x` lays over the ground point `p`, seen from above.
static func box_covers(x: Transform3D, p: Vector2) -> bool:
	var inverse := x.affine_inverse()
	return AABB(Vector3.ONE * -0.5, Vector3.ONE).intersects_ray(inverse * Vector3(p.x, x.origin.y + 10.0, p.y), inverse.basis * Vector3.DOWN) != null


## Whether `p` lies in laid piece `st` as it is drawn, its ends cut as WallLayout.drawn_corners cuts them.
static func piece_holds(st: Dictionary, p: Vector3) -> bool:
	var x: Transform3D = st.xform
	var q := x.affine_inverse() * p
	var e: Vector2 = st.get("ends", Vector2.ZERO)
	var axis := x.basis.y.normalized()
	q.x -= q.z * x.basis.z.length() * tan(e.x if q.x < 0.0 else e.y) / (x.basis.x - axis * x.basis.x.dot(axis)).length()
	return absf(q.x) <= 0.5 and absf(q.y) <= 0.5 and absf(q.z) <= 0.5


## `n` directions spread evenly over the sphere, along a Fibonacci spiral.
static func sphere_directions(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in n:
		var y := 1.0 - 2.0 * (i + 0.5) / n
		var a := i * PI * (3.0 - sqrt(5.0))
		var r := sqrt(1.0 - y * y)
		out.append(Vector3(cos(a) * r, y, sin(a) * r))
	return out


## A tracked controller aiming ahead in each of `rig`'s hands, for the caller to remove from XRServer when done.
static func track_hands(rig: Rig) -> Array[XRControllerTracker]:
	var out: Array[XRControllerTracker] = []
	for hand in rig.hands:
		var tracker := XRControllerTracker.new()
		tracker.name = hand.tracker
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker)
		out.append(tracker)
	return out


static func lay_walls(tool: WallTool) -> void:
	for w in tool.walls:
		w.lay_now()


## Draws a wall from `a` to `b` with `tool`'s first mason as a hand does, in `samples` steps, and returns it.
static func stroke_wall(tool: WallTool, a: Vector3, b: Vector3, samples := 30) -> Wall:
	var m: WallTool.Mason = tool.masons[0]
	var terrain := tool.world.terrain
	tool.begin_stroke(m, terrain.ground(a.x, a.z))
	for i in samples + 1:
		var p := a.lerp(b, i / float(samples))
		tool.extend_stroke(m, terrain.ground(p.x, p.z))
	tool.end_stroke(m)
	return tool.walls[-1]


## Draws a path from `a` to `b` with `paths` as a hand does, in 40 steps, submits it to `world` and returns the
## world's sequence number after it.
static func stroke_path(paths: Paths, world: World, a: Vector3, b: Vector3, half: float) -> int:
	paths.begin(world.terrain.ground(a.x, a.z), half)
	for i in 41:
		var p := a.lerp(b, i / 40.0)
		paths.extend(world.terrain.ground(p.x, p.z), half)
	var ghost := paths.end()
	world.submit(ghost.data.merged({"op": "path"}), paths.drop.bind(ghost))
	return world.seq


## Lets a frame pass and writes the save it left due; saves are written on a worker thread, so this waits for the last
## one to land.
func flushed() -> void:
	await process_frame
	main.world.flush()


## Runs every command waiting on the world and waits until every wall and stair has laid what they hold.
func laid() -> void:
	main.world.settle()
	await until(func() -> bool: return not main.world.stairs.laying() and not main.tool.walls.any(func(w: Wall) -> bool: return w.laying()), "every build lays")


## Runs `steps` through a Driver and waits for it; a run whose every step returns at once finishes inside add_child.
func play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	var ran := [false]
	d.finished.connect(func() -> void: ran[0] = true)
	main.add_child(d)
	if not ran[0]:
		await d.finished
	d.queue_free()


func turn_picker(target: Dictionary, steps: int) -> void:
	var picker: PaletteTool = main.palette_tool
	picker.open(main.rig.right, target)
	picker.twist(main.rig.right, Dial.step(target.count) * steps)
	picker.close(main.rig.right)


## A cleaned command as the host would send it on, checked again as a peer checks it.
func peer_relayed(cmd: Dictionary, by: int) -> Dictionary:
	var world := main.world
	var hosted := Commands.clean(cmd, world.state, false, world.terrain)
	hosted.seq = world.seq + 1
	hosted.by = by
	return Commands.clean(hosted, world.state, true, world.terrain)


## Orders `walls` built as `by`, and the id the first of them takes.
func order_walls(walls: Array, by: int) -> int:
	var world := main.world
	world._order({"op": "wall", "walls": walls}, by)
	return world.seq * Commands.MAX_PIECES


func order_wall(by: int, x := 0.0) -> int:
	var terrain := main.world.terrain
	return order_walls([seeded_wall(PackedVector3Array([terrain.ground(x, -5), terrain.ground(x + 4, -5)]))], by)
