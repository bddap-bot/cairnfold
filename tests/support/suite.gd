extends SceneTree

## What every headless test shares: failures counted and reported on the `tests:` and `FAIL:` lines scripts/test.sh
## reads, and an exit through Main.quit, which waits for playing sounds.
## Seconds of the host's time an until() waits before it calls the wait a hang.
const HANG := 120

var failures := 0
var main: Main


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func finish() -> void:
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func boot_main() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
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


## The data a wall sends: `with`'s fields, the rest as a fresh Wall has them.
static func wall_data(with: Dictionary) -> Dictionary:
	var w := Wall.new(0, null, Terrain.new())
	var d := w.data()
	w.free()
	d.merge(with, true)
	return d


## The index of the `village` step that `steps[at]` looks over: the last one before it.
static func village_before(steps: Array, at: int) -> int:
	var village := at
	while steps[village].op != "village":
		village -= 1
	return village


## Runs `steps` through a Driver and waits for it; a run whose every step returns at once finishes inside add_child.
func play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	var ran := [false]
	d.finished.connect(func() -> void: ran[0] = true)
	main.add_child(d)
	if not ran[0]:
		await d.finished
	d.queue_free()
