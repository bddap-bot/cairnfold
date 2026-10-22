extends SceneTree

## Sweeps the hand paths that read the picture book: a pass through a page from behind it to in front, at every
## speed, angle and tracking rate a player would make it, turns that page once; brushes and hovers turn none.

var failures := 0
var book: Book


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _run() -> void:
	book = Book.new(false)
	book.set_process(false)
	root.add_child(book)
	book.global_transform = Transform3D(Basis(Vector3(0.3, 1, -0.2).normalized(), 0.7), Vector3(0.2, 1.3, -0.4)) * Book.local(1.0)
	var missed_all := 0
	for side in [1, -1]:
		var passes := 0
		var missed := 0
		var wrong := 0
		for x in [0.02, 0.075, 0.13, 0.16]:
			for z in [-0.06, 0.0, 0.06]:
				for tilt in [0.0, 20.0, 40.0, 60.0]:
					for azimuth in ([0.0] if tilt == 0.0 else [0.0, 90.0, 180.0, 270.0]):
						for bow in [0.0, 2.0]:
							for speed in [0.15, 0.5, 1.5, 4.0]:
								for hz in [72.0, 90.0]:
									var d := Basis(Vector3.UP, deg_to_rad(azimuth)) * Basis(Vector3.BACK, deg_to_rad(tilt)) * Vector3.UP
									var turned := _pass(Vector3(side * x, 0.0, z), d, bow, speed, hz)
									passes += 1
									if turned == 0:
										missed += 1
									elif turned != side:
										wrong += 1
		print("book: %d passes back to front through the %s page, %d missed, %d turned the wrong way (%.1f%% miss)" % [passes,
			"right" if side > 0 else "left", missed, wrong, 100.0 * (missed + wrong) / passes])
		missed_all += missed + wrong
	check(missed_all == 0, "every pass from behind a page to in front turns it: right page on, left page back")
	var brushes := {
		"a hand resting on the page, tracking jitter": _wander(Vector3(0.07, 0.0, 0.0), 0.004, 3.0),
		"a hand hovering over the page": _wander(Vector3(0.07, 0.035, 0.02), 0.01, 3.0),
		"a hand waiting behind the book": _wander(Vector3(0.07, -0.05, 0.0), 0.015, 3.0),
		"a pass in front of the book toward it and away": _line(Vector3(0.07, 0.25, 0.0), Vector3(0.07, 0.01, 0.0), 1.0) + _line(Vector3(0.07, 0.01, 0.0), Vector3(0.07, 0.25, 0.0), 1.0),
		"a pass beside the fore-edge": _line(Vector3(0.24, -0.2, 0.0), Vector3(0.24, 0.2, 0.0), 1.0),
		"a pass above the top edge": _line(Vector3(0.07, -0.2, -0.13), Vector3(0.07, 0.2, -0.13), 1.0),
		"a pass below the bottom edge": _line(Vector3(0.07, -0.2, 0.13), Vector3(0.07, 0.2, 0.13), 1.0),
		"a sweep behind the book": _line(Vector3(0.2, -0.04, 0.0), Vector3(-0.2, -0.04, 0.0), 1.0),
		"a pass from in front to behind": _line(Vector3(0.07, 0.2, 0.0), Vector3(0.07, -0.2, 0.0), 1.0),
	}
	for what: String in brushes:
		check(_feel(brushes[what]) == 0, "%s turns no page" % what)
	check(_feel(_line(Vector3(0.12, 0.03, 0.0), Vector3(-0.05, 0.03, 0.0), 0.5)) == 1, "a leftward sweep over the pages turns on")
	check(_feel(_line(Vector3(-0.12, 0.03, 0.0), Vector3(0.05, 0.03, 0.0), 0.5)) == -1, "a rightward sweep over the pages turns back")
	check(_feel(_line(Vector3(0.07, -0.2, 0.0), Vector3(0.07, 0.2, 0.0), 1.0) + _line(Vector3(0.07, 0.2, 0.0), Vector3(-0.07, 0.03, 0.0), 0.6)) == 1,
		"a pass through the page and on across the spread turns one leaf")
	book.queue_free()
	await process_frame
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


## Which way the book turned a hand sampled `hz` times a second along `dir` from 25 cm behind the page through
## `through` (book frame) to 25 cm in front at `speed`, curling `bow` toward the spine once through, as a flick does.
func _pass(through: Vector3, dir: Vector3, bow: float, speed: float, hz: float) -> int:
	var spine := Vector3(-signf(through.x), 0, 0)
	var path: Array[Vector3] = []
	var reach := 0.25
	var phase := fposmod(through.x * 37.0 + through.z * 53.0, 1.0)
	var s := -reach + phase * speed / hz
	while s <= reach:
		path.append(through + dir * s + spine * bow * maxf(s, 0.0) * maxf(s, 0.0))
		s += speed / hz
	return _feel(path)


func _line(from: Vector3, to: Vector3, speed: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := ceili(from.distance_to(to) / speed * 72.0)
	for i in n + 1:
		out.append(from.lerp(to, float(i) / n))
	return out


## Three seconds of a hand held near `at`, its tracking wandering `by` either way.
func _wander(at: Vector3, by: float, seconds: float) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	var out: Array[Vector3] = []
	for i in int(seconds * 72.0):
		out.append(at + Vector3(rng.randf_range(-by, by), rng.randf_range(-by, by), rng.randf_range(-by, by)))
	return out


## Plays `path` (book frame) into the open book after a hand far beside it, returning the way it turned: 1 on, -1 back, 0
## none; a second turn counts as a failure of its own.
func _feel(path: Array[Vector3]) -> int:
	book.at = 2
	book._turn.clear()
	book.feel(book.global_transform * Vector3(1, -0.3, 0))
	book.feel(book.global_transform * Vector3(1, 0.3, 0))
	var way := 0
	for p in path:
		book.feel(book.global_transform * p)
		if not book._turn.is_empty():
			if way != 0:
				check(false, "one pass turns one leaf")
			way = book._turn.way
			book.at = book._turn.to
			book._turn.clear()
	return way
