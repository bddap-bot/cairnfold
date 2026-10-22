extends SceneTree

## The quality ladder and the governor that walks it: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_quality.gd

const BUDGET := 12.5
const DT := 1.0 / 72.0
## A share of the budget just under the governor's line.
const UNDER_LINE := Quality.Governor.LINE - 0.01

var failures := 0


func _initialize() -> void:
	_every_step_draws_less()
	_frames_over_budget_step_down_at_once()
	_a_badly_late_frame_steps_down_two()
	_one_late_frame_is_not_enough()
	_a_missed_refresh_over_the_line_steps_down()
	_calm_steps_back_up_after_a_spell()
	_an_undone_step_up_waits_twice_as_long()
	_a_spike_after_a_step_up_slows_only_that_step()
	_the_ladder_has_ends()
	_an_average_over_the_line_steps_down_before_frames_run_late()
	_a_step_up_waits_for_room_for_what_the_step_down_saved()
	_an_unmeasured_step_up_waits_for_room_for_an_estimate()
	_a_step_up_into_every_other_refresh_is_not_retried()
	_a_held_step_reaches_its_knobs()
	_every_other_refresh_steps_down_whatever_the_timer_reads()
	_a_step_under_way_is_judged_only_by_frames_over_budget()
	_a_pause_is_not_every_other_refresh()
	_every_other_refresh_held_by_the_cpu_steps_nothing_down()
	_nothing_branches_on_the_headset_or_the_build()
	_every_headset_starts_conservative_and_climbs_to_what_it_holds()
	_a_rung_no_knob_of_the_headset_tells_apart_is_passed_by()
	_an_unsettled_step_is_not_followed_into_one_that_pops()
	_a_step_up_that_shows_at_once_waits_longest_and_once_undone_holds()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## Steps down one, then measures what the step saved over a second of frames just under the line.
func _down(g: Quality.Governor) -> void:
	_feed(g, BUDGET * 1.1, 2 + Quality.Governor.SETTLE_FRAMES)
	_feed(g, BUDGET * UNDER_LINE, 72)


## Feeds `frames` frames of `ms` and returns the level after.
func _feed(g: Quality.Governor, ms: float, frames: int) -> int:
	for i in frames:
		g.step(ms, BUDGET, DT)
	return g.level


## Feeds up to `frames` frames of `ms`, stopping once the governor reaches `level`, and returns the level after.
func _feed_until(g: Quality.Governor, ms: float, frames: int, level: int) -> int:
	for i in frames:
		if g.level == level:
			break
		g.step(ms, BUDGET, DT)
	return g.level


func _every_step_draws_less() -> void:
	var steps := Quality.ladder
	for i in steps.size() - 1:
		var a := steps[i]
		var b := steps[i + 1]
		var drawn_less := b.render_scale < a.render_scale or b.msaa < a.msaa or (a.reflections and not b.reflections) or b.foveation > a.foveation or (a.lake and not b.lake)
		_check(b.grass_m <= a.grass_m and b.flowers_m <= a.flowers_m and b.blob_detail <= a.blob_detail and b.stone_near_m <= a.stone_near_m and b.ivy_m <= a.ivy_m and (a.shadows or not b.shadows) and b.scale_3d <= a.scale_3d and b.render_scale <= a.render_scale and b.msaa <= a.msaa and (a.reflections or not b.reflections) and b.foveation >= a.foveation and (a.lake or not b.lake), "step %d draws no more than step %d" % [i + 1, i])
		_check(drawn_less or b.grass_m < a.grass_m or b.flowers_m < a.flowers_m or b.blob_detail < a.blob_detail or b.stone_near_m < a.stone_near_m or b.ivy_m < a.ivy_m or (a.shadows and not b.shadows) or b.scale_3d < a.scale_3d, "step %d draws less than step %d" % [i + 1, i])
		_check(not drawn_less or i < Quality.START, "only the steps above the start change how the view is drawn, step %d does" % (i + 1))
	for i in steps.size():
		_check(steps[i].msaa != Viewport.MSAA_DISABLED, "step %d keeps anti-aliasing on" % i)
		_check(steps[i].grass_m * Flora.GRASS_SURVIVORS_FROM >= Flora.GRASS_LOD_BEGIN + Flora.GRASS_LOD_BAND, "step %d keeps its survivors until the rest have sunk away" % i)
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
		g.step(BUDGET * 1.1 if i % 2 == 0 else BUDGET * 0.8, BUDGET, DT)
	_check(g.level == 0, "isolated late frames leave the ladder alone")


func _a_missed_refresh_over_the_line_steps_down() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * UNDER_LINE, 72)
	g.step(BUDGET * 0.9, BUDGET, DT * 2.0)
	_check(g.level == 2, "a refresh missed with the GPU over the line steps down two at once: %d" % g.level)
	g = Quality.Governor.new(10)
	_feed(g, BUDGET * 0.5, 72)
	g.step(BUDGET * 0.5, BUDGET, DT * 2.0)
	_check(g.level == 0, "one the CPU held leaves the ladder alone")


func _calm_steps_back_up_after_a_spell() -> void:
	var g := Quality.Governor.new(10)
	_down(g)
	_check(_feed(g, BUDGET * UNDER_LINE, 72 * 5) == 1, "near the line it holds its step")
	_check(_feed(g, BUDGET * 0.1, int(72 * 1.7)) == 1, "a short calm is not enough")
	_check(_feed_until(g, BUDGET * 0.1, 72, 0) == 0, "two calm seconds step back up")
	_check(_feed(g, BUDGET * 0.9, 6 + 36) == 0, "a step up gets a second's average")
	_check(_feed(g, BUDGET * 0.9, 50) == 1, "before frames over the line step down again")


func _an_undone_step_up_waits_twice_as_long() -> void:
	var g := Quality.Governor.new(10)
	_down(g)
	_feed(g, BUDGET * 0.1, 72 * 3)
	_check(g.level == 0, "stepped back up")
	_down(g)
	_check(g.level == 1, "and straight back down")
	_check(_feed(g, BUDGET * 0.1, 72 * 3) == 1, "the next step up waits longer")
	_check(_feed(g, BUDGET * 0.1, 72 * 2) == 0, "four calm seconds")


func _a_spike_after_a_step_up_slows_only_that_step() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * 1.1, 3 * (2 + Quality.Governor.SETTLE_FRAMES))
	_check(g.level == 3, "three steps down")
	_feed(g, BUDGET * UNDER_LINE, 72)
	_feed(g, BUDGET * 0.1, 72 * 3)
	_check(g.level == 2, "one step back up")
	_feed(g, BUDGET * 1.1, 3 * (2 + Quality.Governor.SETTLE_FRAMES))
	_check(g.level == 5, "and three down again")
	_feed(g, BUDGET * UNDER_LINE, 72)
	_check(_feed(g, BUDGET * 0.1, 72 * 3) == 4, "steps the ladder fell through keep their two seconds")


func _the_ladder_has_ends() -> void:
	var g := Quality.Governor.new(3)
	_check(_feed(g, BUDGET * 2.0, 200) == 3, "it stops at the bottom")
	_check(_feed(g, 1.0, 72 * 400) == 0, "and at the top")


func _an_average_over_the_line_steps_down_before_frames_run_late() -> void:
	var g := Quality.Governor.new(10)
	_check(_feed(g, BUDGET * 0.9, 36) == 0, "the first second sets the average")
	_check(_feed(g, BUDGET * 0.9, 40) == 1, "then frames under the budget but over the line step down")
	_check(_feed(g, BUDGET * 0.9, 36) == 1, "and wait a second to see what that saved")
	_check(_feed(g, BUDGET * 0.9, 50) == 2, "before stepping again")


func _a_step_up_waits_for_room_for_what_the_step_down_saved() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * 1.0, 36)
	_feed(g, BUDGET * 1.1, 2 + Quality.Governor.SETTLE_FRAMES)
	_feed(g, BUDGET * 0.75, 72)
	_check(_feed(g, BUDGET * 0.75, 72 * 10) == 1, "no step up the saving would take back over the line")
	_check(_feed(g, BUDGET * 0.5, 72 * 4) == 0, "until the scene leaves room for it")
	var h := Quality.Governor.new(10)
	_feed(h, BUDGET * 1.0, 36)
	_feed(h, BUDGET * 1.1, 2 + Quality.Governor.SETTLE_FRAMES)
	_feed(h, BUDGET * 0.75, 72)
	_check(_feed(h, BUDGET * 0.75, int(72 * (Quality.Governor.CALM_SECONDS_MAX + Quality.Governor.CALM_SECONDS + 1.0))) == 0, "or the saving was measured long ago")


func _an_unmeasured_step_up_waits_for_room_for_an_estimate() -> void:
	var g := Quality.Governor.new(10)
	_down(g)
	var near := Quality.Governor.LINE - Quality.Governor.UNMEASURED / 2.0
	_check(_feed(g, BUDGET * near, int(72 * (Quality.Governor.CALM_SECONDS_MAX + 10.0))) == 1, "a cost forgotten is unmeasured, and no step up has less room than the estimate")
	_check(_feed(g, BUDGET * 0.5, 72 * 4) == 0, "until there is")


## The Steam Frame's runtime keeps a game at every other refresh for seconds after a step up crossed its cliff, and its
## GPU times read high while it does, so the step back down measures nothing saved.
func _a_step_up_into_every_other_refresh_is_not_retried() -> void:
	var g := Quality.Governor.new(10)
	_down(g)
	_check(_feed_until(g, BUDGET * 0.4, 72 * 4, 0) == 0, "a step up with room for what the step down saved")
	_check(_feed(g, BUDGET * 0.95, Quality.Governor.SETTLE_FRAMES + 72 + 36) == 1, "lands at every other refresh and steps back down")
	_feed(g, BUDGET * 0.95, Quality.Governor.SETTLE_FRAMES + 72)
	_check(_feed(g, BUDGET * 0.6, 72 * 30) == 1, "which reads no saving, yet the step up is not taken again")


func _a_held_step_reaches_its_knobs() -> void:
	var flora := Flora.new()
	root.add_child(flora)
	var masonry := Masonry.new(Wall.kinds())
	root.add_child(masonry)
	var parts: Array[Dictionary] = []
	for k in Wall.kinds():
		var buf := PackedFloat32Array()
		buf.resize(k.stride())
		parts.append(Masonry.split(buf, k))
	masonry.place(1, parts)
	var look := Look.build(root)
	var sun := look.sun
	sun.shadow_enabled = true
	var q := Quality.new(null, flora, masonry, look)
	root.add_child(q)
	q.view = SubViewport.new()
	var bottom: Quality.Step = Quality.ladder[-1]
	q.pin = Quality.ladder.size() - 1
	q._process(0.1)
	q._process(0.1)
	_check(q._settled, "a step down takes its reaches at once")
	_check(flora.blob_detail == bottom.blob_detail, "blob detail changes at once")
	_check(flora.grass_reach == bottom.grass_m and flora.flower_reach == bottom.flowers_m, "grass and flowers at the step's reach")
	var ks := Wall.kinds()
	_check(ks[Wall.Part.STONE].near == bottom.stone_near_m and ks[Wall.Part.IVY].reach == bottom.ivy_m, "stones and ivy at the step's reach")
	_check(ks[Wall.Part.IVY].material.get_shader_parameter("reach") == bottom.ivy_m, "and the leaves shrink away by it")
	_check(sun.shadow_enabled == bottom.shadows and is_equal_approx(q.view.scaling_3d_scale, bottom.scale_3d), "the sun's shadows and the 3D resolution at the step's")
	_check(q.view.msaa_3d == bottom.msaa and look.env.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED and not look._lake[1].visible and look._plain.visible, "the step's MSAA, without reflections, over the plain")
	var ivy: Masonry.Chunk = masonry._chunks[Vector3i(0, 0, Wall.Part.IVY)]
	var stone: Masonry.Chunk = masonry._chunks[Vector3i(0, 0, Wall.Part.STONE)]
	_check(is_equal_approx(ivy.instance.visibility_range_end, bottom.ivy_m + ks[Wall.Part.IVY].radius()) and is_equal_approx(stone.far.visibility_range_begin, bottom.stone_near_m + ks[Wall.Part.STONE].radius()), "a chunk already standing takes the step's reaches")
	q.pin = 0
	q._process(0.1)
	q._process(0.1)
	_check(not q._settled and flora.grass_reach < Quality.ladder[0].grass_m, "a step up grows its reaches out, unsettled until they arrive")
	for i in 100:
		q._process(0.1)
	_check(ks[Wall.Part.STONE].near == Quality.ladder[0].stone_near_m and ks[Wall.Part.IVY].reach == Quality.ladder[0].ivy_m, "back at the top, they return")
	_check(sun.shadow_enabled and q.view.scaling_3d_scale == 1.0, "and so do the shadows and the full 3D resolution")
	_check(q.view.msaa_3d == Viewport.MSAA_4X and look.env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY and look._lake[1].visible and not look._plain.visible, "and 4x MSAA, the sky's reflections and the lake")
	look.free()
	q.view.free()
	q.free()
	masonry.free()
	flora.free()


func _every_other_refresh_steps_down_whatever_the_timer_reads() -> void:
	var g := Quality.Governor.new(10)
	for i in 40:
		g.step(BUDGET * 0.7, BUDGET, DT * 2.0)
	_check(g.level == 1, "a second at every other refresh, the timer under the line, steps down")
	for i in 36 * 15:
		g.step(BUDGET * 0.7, BUDGET, DT * 2.0)
	_check(g.level == 10, "and it keeps stepping down, never up, while the runtime holds that rate")


## Every headset runs the one ladder: nothing in the game reads which headset or build it is to choose what it draws.
## The play log alone records the device's name.
func _nothing_branches_on_the_headset_or_the_build() -> void:
	var model := RegEx.create_from_string("get_model_name|OS\\.get_name\\(\\)|\"(Quest|Steam Frame|Lepton|Pico)[^\"]*\"")
	# Android keeps photos in its own folder: a storage fact, not a choice of what to draw.
	var feature := RegEx.create_from_string("OS\\.has_feature\\((?!\"android\"\\))[^)]*\\)")
	for f in DirAccess.get_files_at("res://src"):
		if not f.ends_with(".gd") or f == "play_log.gd":
			continue
		var text := FileAccess.get_file_as_string("res://src".path_join(f))
		for m in model.search_all(text):
			_check(false, "%s reads the headset or the platform: %s" % [f, m.get_string()])
		for m in feature.search_all(text):
			_check(false, "%s branches on the build: %s" % [f, m.get_string()])
	for line in FileAccess.get_file_as_string("res://export_presets.cfg").split("\n"):
		if line.begins_with("custom_features="):
			_check(line == "custom_features=\"\"", "an export preset carries a feature the game could branch on: %s" % line)


func _every_headset_starts_conservative_and_climbs_to_what_it_holds() -> void:
	var shares := Quality.shares(true)
	var fast := Quality.Governor.new(Quality.ladder.size() - 1, Quality.popping(), Quality.START, shares)
	_check(Quality.START == Quality.DRAWN.size() - 1, "the start is the last of the ways of drawing the view")
	_check(fast.level == Quality.START, "a headset starts at the cheapest view with every reach whole")
	_check(_feed_until(fast, BUDGET * 0.3, 72 * 60, 0) == 0, "one with room climbs to the top")
	var tight := Quality.Governor.new(Quality.ladder.size() - 1, Quality.popping(), Quality.START, shares)
	_check(_feed(tight, BUDGET * 0.7, 72 * 120) == Quality.START, "one whose frame would not hold the next rung's estimated cost stays at the start")
	var near := Quality.Governor.new(Quality.ladder.size() - 1, Quality.popping(), Quality.START, shares)
	near.step(BUDGET * 0.3, BUDGET, DT)
	_check(near.cost(Quality.START, BUDGET) > BUDGET * Quality.Governor.UNMEASURED, "a larger swapchain's estimate is its share of the frame, not the flat guess")


func _a_rung_no_knob_of_the_headset_tells_apart_is_passed_by() -> void:
	var idle := Quality.idle(false)
	_check(idle.size() == 1 and Quality.ladder[idle[0]].foveation > Quality.ladder[idle[0] - 1].foveation, "without fixed foveation its rung changes nothing, got %s" % [idle])
	_check(Quality.idle(true).is_empty(), "with it every rung changes something")
	var g := Quality.Governor.new(Quality.ladder.size() - 1, Quality.popping(), Quality.START, Quality.shares(false), idle)
	var seen := {}
	for i in 72 * 120:
		g.step(BUDGET * 0.3, BUDGET, DT)
		seen[g.level] = true
	_check(not seen.has(idle[0]) and seen.has(0), "climbing to the top passes it by")
	for i in 72 * 10:
		g.step(BUDGET * 1.1, BUDGET, DT)
		seen[g.level] = true
	_check(not seen.has(idle[0]), "and so does stepping down")


func _every_other_refresh_held_by_the_cpu_steps_nothing_down() -> void:
	var g := Quality.Governor.new(10)
	_check(_feed_dt(g, BUDGET * 0.4, 36 * 5, DT * 2.0) == 0, "with the timer low the CPU held the frame, which no step fixes")


func _feed_dt(g: Quality.Governor, ms: float, frames: int, dt: float) -> int:
	for i in frames:
		g.step(ms, BUDGET, dt)
	return g.level


func _an_unsettled_step_is_not_followed_into_one_that_pops() -> void:
	var g := Quality.Governor.new(10, PackedInt32Array([3]))
	for i in 72 * 3:
		g.step(BUDGET * 1.5, BUDGET, DT, false)
	_check(g.level == 3, "frames far over budget walk down to the pop and wait there while the knobs move, got %d" % g.level)
	_feed(g, BUDGET * 1.5, 2 + Quality.Governor.SETTLE_FRAMES)
	_check(g.level > 3, "and once they arrive, step past it")


func _a_step_under_way_is_judged_only_by_frames_over_budget() -> void:
	var g := Quality.Governor.new(10)
	for i in 72 * 3:
		g.step(BUDGET * (Quality.Governor.LINE + 0.05), BUDGET, DT, false)
	_check(g.level == 0, "an average over the line while the knobs still move leaves the step alone")
	for i in 2:
		g.step(BUDGET * 1.1, BUDGET, DT, false)
	_check(g.level == 1, "frames over budget step down even so")
	_feed(g, BUDGET * 1.1, Quality.Governor.SETTLE_FRAMES)
	for i in 72 * 5:
		g.step(BUDGET * 0.1, BUDGET, DT, false)
	_check(g.level == 1, "and a calm while the knobs still move does not step up")


func _a_pause_is_not_every_other_refresh() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * 0.5, 72 * 2)
	g.step(BUDGET * 0.5, BUDGET, 2.0)
	_check(_feed(g, BUDGET * 0.5, 72 * 2) == 0, "a two-second gap, as with the headset off the head, steps nothing down")


func _a_step_up_that_shows_at_once_waits_longest_and_once_undone_holds() -> void:
	var pops := Quality.popping()
	_check(pops == PackedInt32Array([Quality.START - 4, Quality.START - 3, Quality.START - 2, Quality.START - 1, Quality.ladder.size() - 3, Quality.ladder.size() - 2]), "the steps into 2x MSAA, each smaller swapchain, the plain, shadows off and a lower 3D scale pop, got %s" % [pops])
	var g := Quality.Governor.new(10, PackedInt32Array([0]))
	_down(g)
	_check(_feed(g, BUDGET * 0.1, 72 * 30) == 1, "a step up that pops waits more than a calm spell")
	_check(_feed_until(g, BUDGET * 0.1, 72 * 40, 0) == 0, "and is taken after the longest calm")
	_down(g)
	_check(g.level == 1, "undone at once")
	_check(_feed(g, BUDGET * 0.1, 72 * 300) == 1, "it is not taken again")
