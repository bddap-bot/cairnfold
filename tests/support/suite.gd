extends SceneTree

## What every headless test shares: failures counted and reported on the `tests:` and `FAIL:` lines scripts/test.sh
## reads, and an exit through Main.quit, which waits for playing sounds.
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


## Runs `steps` through a Driver and waits for it, connecting before it starts since a run whose every step returns at
## once finishes inside add_child.
func play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	var ran := [false]
	d.finished.connect(func() -> void: ran[0] = true)
	main.add_child(d)
	while not ran[0]:
		await process_frame
	d.queue_free()
