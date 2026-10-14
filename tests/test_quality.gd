extends SceneTree

## The quality ladder and the governor that walks it: godot4 --headless --path game --script ../tests/test_quality.gd

const BUDGET := 12.5
const DT := 1.0 / 72.0

var failures := 0


func _initialize() -> void:
	_every_step_draws_less()
	_frames_over_budget_step_down_at_once()
	_a_badly_late_frame_steps_down_two()
	_one_late_frame_is_not_enough()
	_calm_steps_back_up_after_a_spell()
	_an_undone_step_up_waits_twice_as_long()
	_a_spike_after_a_step_up_slows_only_that_step()
	_the_ladder_has_ends()
	_a_held_step_reaches_its_knobs()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## Feeds `frames` frames of `ms` and returns the level after.
func _feed(g: Quality.Governor, ms: float, frames: int) -> int:
	for i in frames:
		g.step(ms, BUDGET, DT)
	return g.level


func _every_step_draws_less() -> void:
	var steps := Quality.ladder
	for i in steps.size() - 1:
		var a := steps[i]
		var b := steps[i + 1]
		_check(b.grass_m <= a.grass_m and b.flowers_m <= a.flowers_m and b.blob_detail <= a.blob_detail, "step %d draws no more than step %d" % [i + 1, i])
		_check(b.grass_m < a.grass_m or b.flowers_m < a.flowers_m or b.blob_detail < a.blob_detail, "step %d draws less than step %d" % [i + 1, i])
	var q := Quality.new(null, null)
	_check(q.governor.bottom == steps.size() - 1, "the governor's bottom is the ladder's last step")
	q.pin = 99
	_check(q.step() == steps.size() - 1, "a pin past the bottom holds the bottom")
	q.free()


func _frames_over_budget_step_down_at_once() -> void:
	var g := Quality.Governor.new(10)
	_check(_feed(g, BUDGET * 1.1, 2) == 1, "two frames over budget step down one")
	_check(_feed(g, BUDGET * 1.1, Quality.Governor.SETTLE_FRAMES) == 1, "the timer gets frames to catch up after a step")
	_check(_feed(g, BUDGET * 1.1, 2) == 2, "still over budget, it keeps stepping down")


func _a_badly_late_frame_steps_down_two() -> void:
	var g := Quality.Governor.new(10)
	_check(_feed(g, BUDGET * 1.5, 2) == 2, "frames a quarter over budget step down two")


func _one_late_frame_is_not_enough() -> void:
	var g := Quality.Governor.new(10)
	for i in 50:
		g.step(BUDGET * 1.1 if i % 2 == 0 else BUDGET * 0.97, BUDGET, DT)
	_check(g.level == 0, "isolated late frames leave the ladder alone")


func _calm_steps_back_up_after_a_spell() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * 1.1, 2 + Quality.Governor.SETTLE_FRAMES)
	_check(_feed(g, BUDGET * 0.97, 72 * 5) == 1, "near the budget it holds its step")
	_check(_feed(g, BUDGET * 0.5, int(72 * 1.5)) == 1, "a short calm is not enough")
	_check(_feed(g, BUDGET * 0.5, 72) == 0, "two calm seconds step back up")


func _an_undone_step_up_waits_twice_as_long() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * 1.1, 2 + Quality.Governor.SETTLE_FRAMES)
	_feed(g, BUDGET * 0.5, 72 * 3)
	_check(g.level == 0, "stepped back up")
	_feed(g, BUDGET * 1.1, 2 + Quality.Governor.SETTLE_FRAMES)
	_check(g.level == 1, "and straight back down")
	_check(_feed(g, BUDGET * 0.5, 72 * 3) == 1, "the next step up waits longer")
	_check(_feed(g, BUDGET * 0.5, 72 * 2) == 0, "four calm seconds")


func _a_spike_after_a_step_up_slows_only_that_step() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * 1.1, 3 * (2 + Quality.Governor.SETTLE_FRAMES))
	_check(g.level == 3, "three steps down")
	_feed(g, BUDGET * 0.5, 72 * 3)
	_check(g.level == 2, "one step back up")
	_feed(g, BUDGET * 1.1, 3 * (2 + Quality.Governor.SETTLE_FRAMES))
	_check(g.level == 5, "and three down again")
	_check(_feed(g, BUDGET * 0.5, 72 * 3) == 4, "steps the ladder fell through keep their two seconds")


func _the_ladder_has_ends() -> void:
	var g := Quality.Governor.new(3)
	_check(_feed(g, BUDGET * 2.0, 200) == 3, "it stops at the bottom")
	_check(_feed(g, 1.0, 72 * 400) == 0, "and at the top")


func _a_held_step_reaches_its_knobs() -> void:
	var flora := Flora.new()
	root.add_child(flora)
	var q := Quality.new(null, flora)
	root.add_child(q)
	var bottom: Quality.Step = Quality.ladder[-1]
	q.pin = Quality.ladder.size() - 1
	q._process(0.1)
	_check(not q._settled, "a step whose reaches are still moving is not settled")
	_check(flora.blob_detail == bottom.blob_detail, "blob detail changes at once")
	for i in 100:
		q._process(0.1)
	_check(q._settled, "and settles once they arrive")
	_check(flora.grass_reach == bottom.grass_m and flora.flower_reach == bottom.flowers_m, "grass and flowers at the step's reach")
	q.free()
	flora.free()
