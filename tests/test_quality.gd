extends "res://../tests/support/suite.gd"

const BUDGET := 12.5
const DT := 1.0 / 72.0
const UNDER_LINE := Quality.Governor.LINE - 0.01
const OVER_LINE := (Quality.Governor.LINE + Quality.Governor.CLIFF) / 2.0
const PAST_CLIFF := (Quality.Governor.CLIFF + 1.0) / 2.0


func _initialize() -> void:
	_every_step_draws_less()
	_frames_over_budget_step_down_at_once()
	_frames_past_the_cliff_step_down_at_once()
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
	_a_measured_cost_follows_the_frame()
	_a_measured_cost_is_never_under_the_estimate()
	_a_step_up_waits_a_second_after_a_missed_refresh()
	_every_other_refresh_held_by_the_cpu_still_climbs()
	_a_step_up_into_every_other_refresh_is_not_retried()
	_a_held_step_reaches_its_knobs()
	_every_other_refresh_under_the_line_steps_neither_way()
	_a_step_under_way_is_judged_only_by_frames_past_the_cliff()
	_a_pause_is_not_every_other_refresh()
	_the_frames_after_a_stall_are_not_judged()
	_frames_steadily_four_refreshes_apart_step_down()
	_frames_the_player_does_not_see_step_nothing_down()
	_every_other_refresh_held_by_the_cpu_steps_nothing_down()
	_nothing_branches_on_the_headset_or_the_build()
	_every_headset_starts_conservative_and_climbs_to_what_it_holds()
	_a_flat_window_is_governed_to_its_own_pace()
	_a_rung_no_knob_of_the_headset_tells_apart_is_passed_by()
	_an_unsettled_step_is_not_followed_into_one_that_pops()
	_a_step_up_that_shows_at_once_waits_longest_and_longer_each_time_undone()
	_every_pipeline_a_rung_draws_with_is_primed()
	_a_density_map_that_costs_the_frame_comes_off()
	_a_density_map_that_saves_stays_on()
	_a_frame_that_makes_every_refresh_keeps_the_map()
	_the_density_map_is_tried_again_once_calm()
	_a_map_suddenly_dear_comes_off_at_once()
	_a_pinned_step_holds_the_density_map()
	_a_file_is_priced_by_what_its_frames_measure()
	finish()


func _down(g: Quality.Governor) -> void:
	_feed(g, BUDGET * 1.1, 2 + Quality.Governor.SETTLE_FRAMES)
	_feed(g, BUDGET * UNDER_LINE, 72)


func _feed(g: Quality.Governor, ms: float, frames: int) -> int:
	for i in frames:
		g.step(ms, BUDGET, DT)
	return g.level


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
		var drawn_less := b.render_scale < a.render_scale or b.msaa < a.msaa or (a.reflections and not b.reflections) or b.foveation > a.foveation
		check(b.grass_m <= a.grass_m and b.flowers_m <= a.flowers_m and b.blob_detail <= a.blob_detail and b.stone_near_m <= a.stone_near_m and b.ivy_m <= a.ivy_m and (a.shadows or not b.shadows) and b.scale_3d <= a.scale_3d and b.render_scale <= a.render_scale and b.msaa <= a.msaa and (a.reflections or not b.reflections) and b.foveation >= a.foveation and (a.files or not b.files) and (a.outlines or not b.outlines) and (a.toon or not b.toon), "step %d draws no more than step %d" % [i + 1, i])
		check(drawn_less or b.grass_m < a.grass_m or b.flowers_m < a.flowers_m or b.blob_detail < a.blob_detail or b.stone_near_m < a.stone_near_m or b.ivy_m < a.ivy_m or (a.shadows and not b.shadows) or b.scale_3d < a.scale_3d or (a.files and not b.files) or (a.outlines and not b.outlines) or (a.toon and not b.toon), "step %d draws less than step %d" % [i + 1, i])
		check(not drawn_less or i < Quality.START, "only the steps above the start change how the view is drawn, step %d does" % (i + 1))
	for i in steps.size():
		check(steps[i].msaa != Viewport.MSAA_DISABLED, "step %d keeps anti-aliasing on" % i)
		check(steps[i].grass_m * Flora.GRASS_SURVIVORS_FROM >= Flora.GRASS_LOD_BEGIN + Flora.GRASS_LOD_BAND, "step %d keeps its survivors until the rest have sunk away" % i)
	for i in steps.size():
		check(steps[i].files == (i < steps.size() - 1), "only the last step draws people without their own files: step %d" % i)
	var q := Quality.new(Callable(), null, null)
	check(q.governor.bottom == steps.size() - 1, "the governor's bottom is the ladder's last step")
	q.pin = 99
	check(q.step() == steps.size() - 1, "a pin past the bottom holds the bottom")
	q.free()


func _frames_over_budget_step_down_at_once() -> void:
	var g := Quality.Governor.new(10)
	check(_feed(g, BUDGET * 1.1, 2) == 1, "two frames over budget step down one")
	check(_feed(g, BUDGET * 1.1, Quality.Governor.SETTLE_FRAMES) == 1, "the timer gets frames to catch up after a step")
	check(_feed(g, BUDGET * 1.1, 2) == 2, "still over budget, it keeps stepping down")


## The Steam Frame's runtime holds every other refresh once its GPU time nears the period, short of the budget.
func _frames_past_the_cliff_step_down_at_once() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * 0.5, 72)
	check(_feed(g, BUDGET * PAST_CLIFF, 2) == 1, "two frames past the cliff step down one")
	_feed(g, BUDGET * PAST_CLIFF, Quality.Governor.SETTLE_FRAMES)
	for i in 60:
		g.step(BUDGET * (PAST_CLIFF + 0.06 - 0.002 * i), BUDGET, DT)
	check(g.level == 1, "frames past it falling as they jitter take no more before the step's second is in: %d" % g.level)
	check(_feed(g, BUDGET * PAST_CLIFF, 20) == 2, "they do once it is")
	_feed(g, BUDGET * 1.1, Quality.Governor.SETTLE_FRAMES)
	check(_feed(g, BUDGET * 1.1, 2) == 3, "and frames over budget step on before it")
	g = Quality.Governor.new(10)
	check(_feed(g, BUDGET * PAST_CLIFF, 2) == 1, "from the first frames too")
	_feed(g, BUDGET * 0.5, 72 * 2)
	g.step(BUDGET * 0.5, BUDGET, 2.0)
	_feed(g, BUDGET * 0.5, Quality.Governor.SETTLE_FRAMES)
	check(_feed(g, BUDGET * PAST_CLIFF, 2) == 2, "and the first after a pause")
	g = Quality.Governor.new(10)
	_feed(g, BUDGET * 0.5, 72)
	for i in 72:
		g.step(BUDGET * (PAST_CLIFF if i % 2 == 0 else OVER_LINE), BUDGET, DT)
	check(g.level == 0, "frames past the cliff one at a time leave the ladder alone")


func _a_badly_late_frame_steps_down_two() -> void:
	var g := Quality.Governor.new(10)
	check(_feed(g, BUDGET * 1.5, 2) == 2, "frames a quarter over budget step down two")


func _one_late_frame_is_not_enough() -> void:
	var g := Quality.Governor.new(10)
	for i in 50:
		g.step(BUDGET * 1.1 if i % 2 == 0 else BUDGET * 0.8, BUDGET, DT)
	check(g.level == 0, "isolated late frames leave the ladder alone")


func _a_missed_refresh_over_the_line_steps_down() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * UNDER_LINE, 72)
	g.step(BUDGET * OVER_LINE, BUDGET, DT * 2.0)
	check(_feed(g, BUDGET * 0.5, 72 * 2) == 0, "a single refresh missed with the GPU over the line, the frames after under it, leaves the ladder alone")
	g.step(BUDGET * OVER_LINE, BUDGET, DT * 2.0)
	g.step(BUDGET * OVER_LINE, BUDGET, DT)
	check(g.level == 2, "one the next frame repeats over the line steps down two at once: %d" % g.level)
	g = Quality.Governor.new(10)
	_feed(g, BUDGET * UNDER_LINE, 72)
	g.step(BUDGET * OVER_LINE, BUDGET, DT)
	g.step(BUDGET * OVER_LINE, BUDGET, DT * 2.0)
	check(g.level == 2, "as does one after a frame over the line: %d" % g.level)
	g = Quality.Governor.new(10)
	_feed(g, BUDGET * 0.5, 72)
	g.step(BUDGET * 0.5, BUDGET, DT * 2.0)
	check(g.level == 0, "one the CPU held leaves the ladder alone")
	_feed(g, BUDGET * 0.5, 36)
	_feed(g, BUDGET * OVER_LINE, 2)
	check(g.level == 0, "nor counts with frames over the line after the frames under it")
	g = Quality.Governor.new(10)
	_feed(g, BUDGET * UNDER_LINE, 72)
	g.step(BUDGET * OVER_LINE, BUDGET, DT * 2.0)
	g.step(BUDGET * OVER_LINE, BUDGET, 2.0)
	_feed(g, BUDGET * OVER_LINE, Quality.Governor.SETTLE_FRAMES + 2)
	check(g.level == 0, "a miss before a pause does not count with frames over the line after it")
	g = Quality.Governor.new(10)
	_feed(g, BUDGET * UNDER_LINE, 72)
	g.step(BUDGET * OVER_LINE, BUDGET, DT * 2.0)
	g.step(BUDGET * OVER_LINE, BUDGET, DT * 2.0)
	_feed(g, BUDGET * OVER_LINE, Quality.Governor.SETTLE_FRAMES)
	g.step(BUDGET * OVER_LINE, BUDGET, DT * 2.0)
	g.step(BUDGET * OVER_LINE, BUDGET, DT * 2.0)
	check(g.level == 2, "a miss reading no lower than the one that stepped down waits for the average: %d" % g.level)
	g.step(BUDGET * (Quality.Governor.LINE + 0.01), BUDGET, DT * 2.0)
	check(g.level == 4, "one reading lower steps on: %d" % g.level)


func _calm_steps_back_up_after_a_spell() -> void:
	var g := Quality.Governor.new(10)
	_down(g)
	check(_feed(g, BUDGET * UNDER_LINE, 72 * 5) == 1, "near the line it holds its step")
	check(_feed(g, BUDGET * 0.1, int(72 * 1.7)) == 1, "a short calm is not enough")
	check(_feed_until(g, BUDGET * 0.1, 72, 0) == 0, "two calm seconds step back up")
	check(_feed(g, BUDGET * OVER_LINE, 6 + 36) == 0, "a step up gets a second's average")
	check(_feed(g, BUDGET * OVER_LINE, 50) == 1, "before frames over the line step down again")


func _an_undone_step_up_waits_twice_as_long() -> void:
	var g := Quality.Governor.new(10)
	_down(g)
	_feed(g, BUDGET * 0.1, 72 * 3)
	check(g.level == 0, "stepped back up")
	_down(g)
	check(g.level == 1, "and straight back down")
	check(_feed(g, BUDGET * 0.1, 72 * 3) == 1, "the next step up waits longer")
	check(_feed(g, BUDGET * 0.1, 72 * 2) == 0, "four calm seconds")


func _a_spike_after_a_step_up_slows_only_that_step() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * 1.1, 3 * (2 + Quality.Governor.SETTLE_FRAMES))
	check(g.level == 3, "three steps down")
	_feed(g, BUDGET * UNDER_LINE, 72)
	_feed(g, BUDGET * 0.1, 72 * 3)
	check(g.level == 2, "one step back up")
	_feed(g, BUDGET * 1.1, 3 * (2 + Quality.Governor.SETTLE_FRAMES))
	check(g.level == 5, "and three down again")
	_feed(g, BUDGET * UNDER_LINE, 72)
	check(_feed(g, BUDGET * 0.1, 72 * 3) == 4, "steps the ladder fell through keep their two seconds")


func _the_ladder_has_ends() -> void:
	var g := Quality.Governor.new(3)
	check(_feed(g, BUDGET * 2.0, 200) == 3, "it stops at the bottom")
	check(_feed(g, 1.0, 72 * 400) == 0, "and at the top")


## The governor may reach any rung mid-play.
func _every_pipeline_a_rung_draws_with_is_primed() -> void:
	var primed := Quality.primed()
	var drawn := {}
	for n in primed:
		var s := Quality.ladder[n]
		drawn[[s.render_scale, s.msaa, s.reflections, s.shadows, s.scale_3d, s.foveation > 0]] = true
	for s in Quality.ladder:
		check(drawn.has([s.render_scale, s.msaa, s.reflections, s.shadows, s.scale_3d, s.foveation > 0]), "a rung's pipelines are primed")
	check(primed[-1] == Quality.START, "priming ends where the governor starts")


func _an_average_over_the_line_steps_down_before_frames_run_late() -> void:
	var g := Quality.Governor.new(10)
	check(_feed(g, BUDGET * OVER_LINE, 36) == 0, "the first second sets the average")
	check(_feed(g, BUDGET * OVER_LINE, 40) == 1, "then frames under the budget but over the line step down")
	check(_feed(g, BUDGET * OVER_LINE, 36) == 1, "and wait a second to see what that saved")
	check(_feed(g, BUDGET * OVER_LINE, 50) == 2, "before stepping again")
	g = Quality.Governor.new(10)
	_feed(g, BUDGET * 4.0, 1)
	check(_feed(g, BUDGET * 0.3, 72 * 2) == 0, "an average a burst left over the line, the frames now under it, steps nothing down")


func _a_step_up_waits_for_room_for_what_the_step_down_saved() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * OVER_LINE, 36)
	_feed(g, BUDGET * 1.1, 2 + Quality.Governor.SETTLE_FRAMES)
	_feed(g, BUDGET * 0.75, 72)
	check(_feed(g, BUDGET * 0.75, 72 * 10) == 1, "no step up the saving would take back over the line")
	check(_feed(g, BUDGET * 0.5, 72 * 4) == 0, "until the scene leaves room for it")
	var h := Quality.Governor.new(10)
	_feed(h, BUDGET * OVER_LINE, 36)
	_feed(h, BUDGET * 1.1, 2 + Quality.Governor.SETTLE_FRAMES)
	_feed(h, BUDGET * 0.75, 72)
	check(_feed(h, BUDGET * 0.75, int(72 * (Quality.Governor.CALM_SECONDS_MAX + Quality.Governor.CALM_SECONDS + 1.0))) == 0, "or the saving was measured long ago")


func _an_unmeasured_step_up_waits_for_room_for_an_estimate() -> void:
	var g := Quality.Governor.new(10)
	_down(g)
	var near := Quality.Governor.LINE - Quality.Governor.UNMEASURED / 2.0
	check(_feed(g, BUDGET * near, int(72 * (Quality.Governor.CALM_SECONDS_MAX + 10.0))) == 1, "a cost forgotten is unmeasured, and no step up has less room than the estimate")
	check(_feed(g, BUDGET * 0.5, 72 * 4) == 0, "until there is")


func _a_measured_cost_follows_the_frame() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * 0.6, 72)
	_feed(g, BUDGET * 1.1, 2)
	_feed(g, BUDGET * 0.4, 72 + 2 * Quality.Governor.SETTLE_FRAMES)
	var light := g.cost(1, BUDGET)
	check(g.level == 1 and light > BUDGET * Quality.Governor.UNMEASURED, "a step down measures what it saved")
	_feed(g, BUDGET * 0.58, 72 * 5)
	check(absf(g.cost(1, BUDGET) / light - 0.58 / 0.4) < 0.02, "and costs that share of a heavier frame")
	check(_feed(g, BUDGET * 0.58, 72 * 10) == 1, "which leaves no room under the line for it")


## A step's cost depends on the view as well as the frame.
func _a_measured_cost_is_never_under_the_estimate() -> void:
	var shares := PackedFloat32Array([0.25])
	var g := Quality.Governor.new(10, PackedInt32Array(), 0, shares)
	_feed(g, BUDGET * 0.4, 72)
	_feed(g, BUDGET * 1.1, 2)
	_feed(g, BUDGET * 0.4, 72 + 2 * Quality.Governor.SETTLE_FRAMES)
	check(g.level == 1 and g._cost[1] >= 0.0 and g._cost[1] < 0.25, "a step down in a light view measures a small share: %.3f" % g._cost[1])
	check(_feed(g, BUDGET * 0.7, 72 * 10) == 1, "which leaves no room under the line for it")


func _a_step_up_waits_a_second_after_a_missed_refresh() -> void:
	var g := Quality.Governor.new(10)
	_down(g)
	_feed(g, BUDGET * 0.1, int(72 * (Quality.Governor.CALM_SECONDS - 0.5)))
	g.step(BUDGET * 0.1, BUDGET, DT * 2.0)
	check(_feed(g, BUDGET * 0.1, int(72 * (Quality.Governor.MISSED_SECONDS - 0.1))) == 1, "a calm spell does not step up within a second of a missed refresh")
	check(_feed(g, BUDGET * 0.1, 72) == 0, "it does once the second is past")


func _every_other_refresh_held_by_the_cpu_still_climbs() -> void:
	var g := Quality.Governor.new(10)
	_down(g)
	for i in 72 * 4:
		g.step(BUDGET * 0.3, BUDGET, DT * 2.0)
	check(g.level == 0, "a steady rate the CPU holds is no missed refresh")


## After a step up crosses its cliff the Steam Frame's runtime holds every other refresh for seconds, its GPU times
## high, so the step back down measures nothing saved.
func _a_step_up_into_every_other_refresh_is_not_retried() -> void:
	var g := Quality.Governor.new(10)
	_down(g)
	check(_feed_until(g, BUDGET * 0.4, 72 * 4, 0) == 0, "a step up with room for what the step down saved")
	check(_feed(g, BUDGET * OVER_LINE, Quality.Governor.SETTLE_FRAMES + 72 + 36) == 1, "lands at every other refresh and steps back down")
	_feed(g, BUDGET * OVER_LINE, Quality.Governor.SETTLE_FRAMES + 72)
	check(_feed(g, BUDGET * 0.6, 72 * 30) == 1, "which reads no saving, yet the step up is not taken again")


func _a_held_step_reaches_its_knobs() -> void:
	var terrain := Terrain.new()
	var flora := Flora.new(terrain, Ground.new())
	root.add_child(flora)
	var masonry := Masonry.new(Wall.kinds())
	root.add_child(masonry)
	var parts: Array[Dictionary] = []
	for k in Wall.kinds():
		var buf := PackedFloat32Array()
		buf.resize(k.stride())
		parts.append(Masonry.split(buf, k))
	masonry.place(1, parts)
	var look := Look.build(root, terrain)
	var sun := look.sun
	sun.shadow_enabled = true
	var q := Quality.new(Callable(), null, flora, masonry, look)
	root.add_child(q)
	q.view = SubViewport.new()
	var bottom: Quality.Step = Quality.ladder[-1]
	q.pin = Quality.ladder.size() - 1
	q._process(0.1)
	q._process(0.1)
	check(q._settled, "a step down takes its reaches at once")
	check(flora.blob_detail == bottom.blob_detail, "blob detail changes at once")
	check(flora.grass_reach == bottom.grass_m and flora.flower_reach == bottom.flowers_m, "grass and flowers at the step's reach")
	var ks := Wall.kinds()
	check(ks[Wall.Part.STONE].near == bottom.stone_near_m and ks[Wall.Part.IVY].reach == bottom.ivy_m, "stones and ivy at the step's reach")
	check(ks[Wall.Part.IVY].material.get_shader_parameter("reach") == bottom.ivy_m, "and the leaves shrink away by it")
	check(sun.shadow_enabled == bottom.shadows and is_equal_approx(q.view.scaling_3d_scale, bottom.scale_3d * bottom.render_scale), "the sun's shadows and the 3D resolution at the step's, with no swapchain carrying its scale too")
	check(q.view.msaa_3d == bottom.msaa and look.env.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED, "the step's MSAA, without reflections")
	check(Avatar.outlines == bottom.outlines and Avatar.toon == bottom.toon, "avatars' outlines and toon shading as the step keeps them")
	var ivy: Masonry.Chunk = masonry._chunks[Vector3i(0, 0, Wall.Part.IVY)]
	var stone: Masonry.Chunk = masonry._chunks[Vector3i(0, 0, Wall.Part.STONE)]
	check(is_equal_approx(ivy.instance.visibility_range_end, bottom.ivy_m + ks[Wall.Part.IVY].radius()) and stone.far.get_instance_shader_parameter(&"piece_range").x == bottom.stone_near_m, "a chunk already standing takes the step's reaches")
	q.pin = 0
	q._process(0.1)
	q._process(0.1)
	check(not q._settled and flora.grass_reach < Quality.ladder[0].grass_m, "a step up grows its reaches out, unsettled until they arrive")
	for i in 100:
		q._process(0.1)
	check(ks[Wall.Part.STONE].near == Quality.ladder[0].stone_near_m and ks[Wall.Part.IVY].reach == Quality.ladder[0].ivy_m, "back at the top, they return")
	check(sun.shadow_enabled and q.view.scaling_3d_scale == 1.0, "and so do the shadows and the full 3D resolution")
	check(q.view.msaa_3d == Viewport.MSAA_4X and look.env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY, "and 4x MSAA and the sky's reflections")
	check(Avatar.outlines and Avatar.toon, "and avatars' outlines and toon shading")
	look.free()
	q.view.free()
	q.free()
	masonry.free()
	flora.free()


func _every_other_refresh_under_the_line_steps_neither_way() -> void:
	var g := Quality.Governor.new(10, PackedInt32Array(), 3)
	check(_feed_dt(g, BUDGET * 0.7, 36 * 15, DT * 2.0) == 3, "fifteen seconds at every other refresh, the timer under the line with room for a step up, step nothing down, nor up")
	check(_feed_dt(g, BUDGET * OVER_LINE, 3, DT * 2.0) == 5, "the timer over it, they step down two at once")


func _nothing_branches_on_the_headset_or_the_build() -> void:
	var model := RegEx.create_from_string("get_model_name|OS\\.get_name\\(\\)|\"(Quest|Steam Frame|Lepton|Pico)[^\"]*\"")
	# Android's photo folder is a storage fact, not a choice of what to draw.
	var feature := RegEx.create_from_string("OS\\.has_feature\\((?!\"android\"\\))[^)]*\\)")
	for f in DirAccess.get_files_at("res://src"):
		# play_log.gd alone records the device's name.
		if not f.ends_with(".gd") or f == "play_log.gd":
			continue
		var text := FileAccess.get_file_as_string("res://src".path_join(f))
		for m in model.search_all(text):
			check(false, "%s reads the headset or the platform: %s" % [f, m.get_string()])
		for m in feature.search_all(text):
			check(false, "%s branches on the build: %s" % [f, m.get_string()])
	for line in FileAccess.get_file_as_string("res://export_presets.cfg").split("\n"):
		if line.begins_with("custom_features="):
			check(line == "custom_features=\"\"", "an export preset carries a feature the game could branch on: %s" % line)


func _every_headset_starts_conservative_and_climbs_to_what_it_holds() -> void:
	var shares := Quality.shares(true)
	var fast := Quality.Governor.new(Quality.ladder.size() - 1, Quality.popping(), Quality.START, shares)
	check(Quality.START == Quality.DRAWN.size() - 1, "the start is the last of the ways of drawing the view")
	check(fast.level == Quality.START, "a headset starts at the cheapest view with every reach whole")
	check(_feed_until(fast, BUDGET * 0.3, 72 * 60, 0) == 0, "one with room climbs to the top")
	var tight := Quality.Governor.new(Quality.ladder.size() - 1, Quality.popping(), Quality.START, shares)
	check(_feed(tight, BUDGET * 0.7, 72 * 120) == Quality.START, "one whose frame would not hold the next rung's estimated cost stays at the start")
	var near := Quality.Governor.new(Quality.ladder.size() - 1, Quality.popping(), Quality.START, shares)
	near.step(BUDGET * 0.3, BUDGET, DT)
	check(near.cost(Quality.START, BUDGET) > BUDGET * Quality.Governor.UNMEASURED, "a larger swapchain's estimate is its share of the frame, not the flat guess")


func _a_flat_window_is_governed_to_its_own_pace() -> void:
	var terrain := Terrain.new()
	var flora := Flora.new(terrain, Ground.new())
	root.add_child(flora)
	var q := Quality.new(func() -> float: return Budget.FLAT_HZ, null, flora)
	root.add_child(q)
	q.view = SubViewport.new()
	var now := [0]
	q.clock = func() -> int: return now[0]
	var budget := 1000.0 / Budget.FLAT_HZ
	check(is_equal_approx(q.budget_ms, budget) and not q.held(), "the flat window holds a %.1f ms budget, got %.1f" % [budget, q.budget_ms])
	check(q.step() == Quality.START, "and starts where a headset does")
	var run := func(ms: float, seconds: float) -> void:
		for i in int(seconds * Budget.FLAT_HZ):
			now[0] += int(1e6 / Budget.FLAT_HZ)
			q.frame(ms + 0.001 * (i % 2), 1.0 / Budget.FLAT_HZ)
	run.call(budget * 0.7, Quality.WARMUP_S + 1.0)
	check(q.step() == Quality.START, "frames inside the budget hold the start through the warm-up: %d" % q.step())
	run.call(budget * 1.2, 2.0)
	var down := q.step()
	check(down > Quality.START, "frames over %.1f ms step it down: %d" % [budget, down])
	check(is_equal_approx(q.view.scaling_3d_scale, Quality.ladder[down].scale_3d * Quality.ladder[down].render_scale), "the view drawn at the step's scale")
	run.call(budget * 0.2, 120.0)
	check(q.step() < Quality.START, "frames well under it climb back past the start: %d" % q.step())
	check(is_equal_approx(q.view.scaling_3d_scale, Quality.ladder[q.step()].render_scale), "a swapchain rung draws the flat view at its share")
	q.view.free()
	q.free()
	flora.free()
	for hz: Vector2 in [Vector2(-1.0, 60.0), Vector2(60.0, 60.0), Vector2(120.0, 60.0), Vector2(144.0, 72.0), Vector2(75.0, 75.0), Vector2(90.0, 90.0), Vector2(50.0, 50.0)]:
		check(is_equal_approx(Main.shown_rate(hz.x), hz.y), "a %.0f Hz display holds frames to %.0f Hz, got %.1f" % [hz.x, hz.y, Main.shown_rate(hz.x)])


func _a_rung_no_knob_of_the_headset_tells_apart_is_passed_by() -> void:
	var idle := Quality.idle(false)
	check(idle.size() == 1 and Quality.ladder[idle[0]].foveation > Quality.ladder[idle[0] - 1].foveation, "without fixed foveation its rung changes nothing, got %s" % [idle])
	check(Quality.idle(true).is_empty(), "with it every rung changes something")
	var g := Quality.Governor.new(Quality.ladder.size() - 1, Quality.popping(), Quality.START, Quality.shares(false), idle)
	var seen := {}
	for i in 72 * 120:
		g.step(BUDGET * 0.3, BUDGET, DT)
		seen[g.level] = true
	check(not seen.has(idle[0]) and seen.has(0), "climbing to the top passes it by")
	for i in 72 * 10:
		g.step(BUDGET * 1.1, BUDGET, DT)
		seen[g.level] = true
	check(not seen.has(idle[0]), "and so does stepping down")


func _every_other_refresh_held_by_the_cpu_steps_nothing_down() -> void:
	var g := Quality.Governor.new(10)
	check(_feed_dt(g, BUDGET * 0.4, 36 * 5, DT * 2.0) == 0, "with the timer low the CPU held the frame, which no step fixes")


func _feed_dt(g: Quality.Governor, ms: float, frames: int, dt: float) -> int:
	for i in frames:
		g.step(ms, BUDGET, dt)
	return g.level


func _an_unsettled_step_is_not_followed_into_one_that_pops() -> void:
	var g := Quality.Governor.new(10, PackedInt32Array([3]))
	for i in 72 * 3:
		g.step(BUDGET * 1.5, BUDGET, DT, false)
	check(g.level == 3, "frames far over budget walk down to the pop and wait there while the knobs move, got %d" % g.level)
	_feed(g, BUDGET * 1.5, 2 + Quality.Governor.SETTLE_FRAMES)
	check(g.level > 3, "and once they arrive, step past it")
	g = Quality.Governor.new(10, PackedInt32Array([3]))
	_feed(g, BUDGET * 1.5, 36)
	check(g.level == 3, "a step down not yet averaged is not followed into a pop on single frames, got %d" % g.level)
	_feed(g, BUDGET * 1.5, 72)
	check(g.level > 3, "once its second is in, it is")


func _a_step_under_way_is_judged_only_by_frames_past_the_cliff() -> void:
	var g := Quality.Governor.new(10)
	for i in 72 * 3:
		g.step(BUDGET * (Quality.Governor.LINE + 0.05), BUDGET, DT, false)
	check(g.level == 0, "an average over the line while the knobs still move leaves the step alone")
	for i in 2:
		g.step(BUDGET * PAST_CLIFF, BUDGET, DT, false)
	check(g.level == 1, "frames past the cliff step down even so")
	_feed(g, BUDGET * 1.1, Quality.Governor.SETTLE_FRAMES)
	for i in 72 * 5:
		g.step(BUDGET * 0.1, BUDGET, DT, false)
	check(g.level == 1, "and a calm while the knobs still move does not step up")


func _a_pause_is_not_every_other_refresh() -> void:
	var g := Quality.Governor.new(10)
	_feed(g, BUDGET * 0.5, 72 * 2)
	g.step(BUDGET * 0.5, BUDGET, 2.0)
	check(_feed(g, BUDGET * 0.5, 72 * 2) == 0, "a two-second gap, as with the headset off the head, steps nothing down")


func _the_frames_after_a_stall_are_not_judged() -> void:
	var g := Quality.Governor.new(10, PackedInt32Array([0]), 1)
	_feed_until(g, BUDGET * 0.1, 72 * 70, 0)
	check(g.level == 0, "the governor climbs across the pop")
	_feed(g, BUDGET * 0.5, 72 * 2)
	g.step(BUDGET * 2.0, BUDGET, 0.5)
	_feed(g, BUDGET * 2.0, 2)
	check(_feed(g, BUDGET * UNDER_LINE, 72 * 2) == 0, "a half-second stall and the two heavy frames drawing what it built step nothing down")
	check(_feed(g, BUDGET * 1.1, 2 + Quality.Governor.SETTLE_FRAMES) == 1, "frames over budget after it still do")


## Measured: a Quest 2 drawing heavy avatars ran every frame at the fourth refresh, PAUSE periods apart, so a steady
## gap is the scene's cost, not a pause.
func _frames_steadily_four_refreshes_apart_step_down() -> void:
	var period := DT * 1000.0
	var g := Quality.Governor.new(10)
	for i in 72 * 2:
		g.step(period * UNDER_LINE, period, DT)
	for i in 30:
		g.step(period * 1.04, period, DT * Quality.Governor.PAUSE * 1.01)
	check(g.level > 0, "frames four refreshes apart for a second and a half step down, at %d" % g.level)
	for i in 72 * 2:
		g.step(period * UNDER_LINE, period, DT)
	var at := g.level
	g.step(period * 2.0, period, 0.4)
	g.step(period * 2.0, period, DT)
	check(g.level == at, "a stall after them still reads as one, at %d from %d" % [g.level, at])


## A photo's frames take 45 ms; the two after a cover still read its time.
func _frames_the_player_does_not_see_step_nothing_down() -> void:
	for see in [false, true]:
		var g := Quality.Governor.new(10)
		_feed(g, BUDGET * UNDER_LINE, 72 * 2)
		for i in 30:
			g.step(BUDGET * 1.3, BUDGET, 0.045, true, see)
		_feed(g, BUDGET * 1.3, 2)
		_feed(g, BUDGET * UNDER_LINE, 72 * 2)
		check((g.level == 0) != see, "%s, a cover's frames leave the governor at %d" % ["seen" if see else "unseen", g.level])


func _a_step_up_that_shows_at_once_waits_longest_and_longer_each_time_undone() -> void:
	var pops := Quality.popping()
	check(pops == PackedInt32Array([Quality.START - 3, Quality.START - 2, Quality.START - 1, Quality.ladder.size() - 6, Quality.ladder.size() - 5, Quality.ladder.size() - 4, Quality.ladder.size() - 3, Quality.ladder.size() - 2]), "the steps into 2x MSAA, each smaller swapchain, toon shading off, outlines off, shadows off, a lower 3D scale and people without their own files pop, got %s" % [pops])
	var g := Quality.Governor.new(10, PackedInt32Array([0]))
	_down(g)
	check(_feed(g, BUDGET * 0.1, 72 * 30) == 1, "a step up that pops waits more than a calm spell")
	check(_feed_until(g, BUDGET * 0.1, 72 * 40, 0) == 0, "and is taken after the longest calm")
	_down(g)
	check(g.level == 1, "undone at once")
	var longest := int(72 * Quality.Governor.CALM_SECONDS_MAX)
	check(_feed(g, BUDGET * 0.1, longest + 72 * 30) == 1, "it waits longer than the longest calm")
	check(_feed_until(g, BUDGET * 0.1, longest + 72 * 10, 0) == 0, "and is taken again after twice the longest calm")
	_down(g)
	check(_feed(g, BUDGET * 0.1, 3 * longest + 72 * 30) == 1, "undone again, it waits twice as long again")
	check(_feed_until(g, BUDGET * 0.1, longest + 72 * 10, 0) == 0, "and is taken after it")
	_down(g)
	check(_feed(g, BUDGET * 0.1, 3 * longest + 72 * 30) == 1, "undone a third time, it waits as long")
	check(_feed_until(g, BUDGET * 0.1, longest + 72 * 10, 0) == 0, "and no longer: a longer calm than that is rare in play")


func _feed_map(m: Quality.Map, on_ms: float, off_ms: float, seconds: float) -> bool:
	for i in int(seconds * 72):
		m.step(on_ms if m.on else off_ms, BUDGET, DT)
	return m.on


func _a_density_map_that_costs_the_frame_comes_off() -> void:
	var m := Quality.Map.new()
	check(not _feed_map(m, 25.0, 12.0, 2.0), "a map that makes the frame twice as dear comes off")
	check(not _feed_map(m, 25.0, 12.0, 30.0), "and stays off while the frame without it runs over the line")


func _a_density_map_that_saves_stays_on() -> void:
	var m := Quality.Map.new()
	check(_feed_map(m, 15.0, 16.0, 30.0), "a map that saves stays on, however long the frame runs over the period")
	m = Quality.Map.new()
	check(_feed_map(m, 15.0, 13.0, 30.0), "as does one that costs less than a fifth of the frame")


## Measured on a Quest 2: a frame over the line and under the period made every refresh with the map on; one trial off
## held every fourth refresh.
func _a_frame_that_makes_every_refresh_keeps_the_map() -> void:
	var line := BUDGET * Quality.Governor.LINE
	var m := Quality.Map.new()
	var switches := 0
	for i in 60 * 72:
		var was := m.on
		m.step(lerpf(line, BUDGET, 0.9) if m.on else BUDGET * 1.1, BUDGET, DT)
		switches += int(m.on != was)
	check(m.on and switches == 0, "a frame over the line and under the period is never tried without the map: %d switches in a minute" % switches)
	check(not _feed_map(m, BUDGET * 1.02, BUDGET * 0.7, 2.0), "just past the period, a map that makes the frame dearer comes off")


func _the_density_map_is_tried_again_once_calm() -> void:
	var m := Quality.Map.new()
	_feed_map(m, 100.0, 25.0, 2.0)
	check(_feed_map(m, 5.0, 5.5, Quality.Map.CALM_SECONDS + 2.0), "a calm frame puts the map back on, where it costs nothing")
	_feed_map(m, 100.0, 25.0, 2.0)
	check(not _feed_map(m, 30.0, 5.0, Quality.Map.CALM_SECONDS + 1.0), "a map still dear when tried again comes off again")
	_feed_map(m, 30.0, 25.0, 0.5)
	check(not _feed_map(m, 30.0, 5.0, Quality.Map.CALM_SECONDS * 2.0 - 0.5), "and the next try waits twice as long")
	check(_feed_map(m, 5.0, 5.0, Quality.Map.CALM_SECONDS * 2.0 + 2.0), "then tries again")


## Measured on a Quest 2: a fresh timber village seen from the air, after a trial off that saved nothing, drew seven
## times dearer with the map, at 6 fps.
func _a_map_suddenly_dear_comes_off_at_once() -> void:
	var m := Quality.Map.new()
	_feed_map(m, 15.0, 16.0, 2.0)
	check(m.on, "a map whose trial saved nothing is back on")
	var dt := 1.0 / 6.0
	var seconds := 0.0
	while m.on and seconds < 5.0:
		m.step(170.0, BUDGET, dt)
		seconds += dt
	check(not m.on and seconds <= 0.5, "frames many times the line take it off within half a second: %.2f s" % seconds)
	for i in 30:
		m.step(170.0 if m.on else 25.0, BUDGET, dt)
	check(not m.on, "and it stays off once that saved most of the frame")
	check(_feed_map(m, 5.0, 5.0, Quality.Map.CALM_SECONDS + 2.0), "and goes back on once the frame is calm")
	m = Quality.Map.new()
	for i in 2:
		m.step(40.0, BUDGET, DT)
	check(_feed_map(m, 8.0, 9.0, 1.0), "dear frames for less than a quarter of a second leave a map that saves on")
	m = Quality.Map.new()
	m.step(170.0, BUDGET, 0.4)
	check(_feed_map(m, 8.0, 9.0, 1.0), "as does one stalled frame, however long")
	m = Quality.Map.new()
	_feed_map(m, 13.0, 16.0, 2.0)
	for i in 2:
		m.step(170.0, BUDGET, dt)
	check(_feed_map(m, 13.0, 16.0, 30.0), "a spike after a trial that saved nothing leaves a map that saves on")
	m = Quality.Map.new()
	_feed_map(m, 100.0, 5.0, 2.0)
	check(not m.on, "a map five times dearer is off")
	var waited := 0.0
	while not m.on and waited < Quality.Map.CALM_SECONDS_MAX:
		m.step(5.0, BUDGET, dt)
		waited += dt
	var held := 0.0
	while m.on and held < 5.0:
		m.step(250.0, BUDGET, dt)
		held += dt
	check(not m.on and held <= 0.5, "tried back on once calm, it comes off within half a second: %.2f s" % held)
	m = Quality.Map.new()
	var on_steps := 0
	for i in int(60.0 / dt):
		m.step(250.0 if m.on else 100.0, BUDGET, dt)
		on_steps += int(m.on)
	check(on_steps * dt < 6.0, "a map that costs most of a frame still dear without it stays off: on %.1f s of 60" % (on_steps * dt))
	m = Quality.Map.new()
	var toggles := 0
	var was := m.on
	for i in int(4.0 * Quality.Map.RETRY_SECONDS / dt):
		m.step(170.0, BUDGET, dt)
		toggles += int(m.on != was)
		was = m.on
	check(toggles <= 8, "a frame as dear without the map tries it off at most once a retry wait: %d switches in four" % toggles)


func _a_file_is_priced_by_what_its_frames_measure() -> void:
	var line := 1000.0 / 72.0 * Quality.Governor.LINE
	var p := Quality.People.new()
	var refused: Array[String] = []
	var reopened := [0]
	p.refused.connect(func(key: String) -> void: refused.append(key))
	p.reopened.connect(func() -> void: reopened[0] += 1)
	for i in Quality.People.FRAMES - 1:
		p.measure(8.0)
	check(not p.measured(), "one frame short of the window nothing is priced")
	p.measure(8.0)
	check(p.measured(), "a full window prices files")
	check(p.admit("dear", line) and p.trial.key == "dear", "an unmeasured file is let in to be measured: %s" % p.why)
	check(not p.admit("cheap", line), "another waits while the headroom is held for it: %s" % p.why)
	for i in Quality.People.FRAMES:
		p.measure(6.0)
	check(p.trial.key == "dear", "out of view a file is not measured")
	_try(p, 26.0, Quality.Map.TRIAL_FRAMES - 1)
	for i in Quality.People.FRAMES:
		p.measure(26.0)
	_try(p, 26.0, Quality.Map.TRIAL_FRAMES - 1)
	check(p.trial != null and refused.is_empty(), "a file that leaves view before its trial ends starts over")
	p.measure(26.0, true)
	check(p.trial == null and refused == ["dear"], "a file its frames show past the headroom is refused: %s" % p.why)
	check("18.00 ms" in p.why, "against the frames before it was let in, however the frames since run: %s" % p.why)
	var offers: int = reopened[0]
	for i in Quality.People.FRAMES - 1:
		p.measure(8.0)
	check(not p.admit("cheap", line) and "held" in p.why, "the window measured with it is no headroom to price by: %s" % p.why)
	p.measure(8.0)
	check(reopened[0] == offers, "files are offered again only once the window is measured afresh")
	p.measure(8.0)
	check(reopened[0] == offers + 1, "and then they are")
	check(not p.admit("dear", line), "a refused file stays refused at its measured cost: %s" % p.why)
	p.measure(60.0)
	check(p.admit("cheap", line), "another is let in to be measured: %s" % p.why)
	_try(p, 10.5, Quality.Map.TRIAL_FRAMES - 1)
	p.measure(60.0, true)
	check(refused == ["dear"] and p.trial == null, "a file whose frames hold the line stays drawn, one stalled frame aside: %s" % p.why)
	check("2.50 ms" in p.why, "its cost is the median over the median: %s" % p.why)
	for i in Quality.People.FRAMES:
		p.measure(10.5)
	check(not p.admit("cheap", line), "a second figure of it is priced at its measured cost against what is left: %s" % p.why)
	for i in Quality.People.FRAMES:
		p.measure(8.0)
	check(p.admit("cheap", line) and p.trial == null, "with room it is let in at its cost, unmeasured again: %s" % p.why)
	check(not p.admit("cheap", line), "a file just let in takes its share of the room: %s" % p.why)
	for i in Quality.People.SHOWN_FRAMES:
		p.measure(8.0)
	check(p.admit("cheap", line), "once the median holds it the room is the frames' to measure: %s" % p.why)
	check(p.admit("next", line), "an unmeasured file is let in beside it: %s" % p.why)
	_try(p, 11.0, Quality.Map.TRIAL_FRAMES)
	check("0.50 ms" in p.why and refused.back() == "next", "its frames are priced over what the file let in just before takes too: %s" % p.why)
	for i in Quality.People.FRAMES:
		p.measure(12.0)
	check(not p.admit("new", line), "an unmeasured file waits for headroom: %s" % p.why)
	var was: int = reopened[0]
	for i in Quality.People.FRAMES:
		p.measure(8.0)
	check(reopened[0] > was, "figures standing in are offered again as the frames are measured")
	check(p.admit("new", line), "and it is let in to be measured: %s" % p.why)
	for i in Quality.People.PATIENCE:
		p.measure(8.0)
	check(p.trial != null, "a figure out of view is waited for")
	p.measure(8.0)
	check(p.trial == null and refused.back() == "new", "until its patience runs out, unpriced: %s" % p.why)
	for i in Quality.People.FRAMES:
		p.measure(8.0)
	check(not p.admit("new", line) and "waiting" in p.why, "a file left unmeasured sits out the next offer: %s" % p.why)
	p.measure(8.0)
	check(p.admit("new", line), "and is measured when offered after it: %s" % p.why)
	p.abandon("its figure gone")
	check(p.trial == null and refused.back() == "new", "a file no figure draws any longer is left unmeasured")
	for i in Quality.People.FRAMES + 1:
		p.measure(8.0)
	check(not p.admit("new", line), "left again, it sits out twice as many: %s" % p.why)
	for i in Quality.People.FRAMES:
		p.measure(8.0)
	check(p.admit("new", line), "and then is measured: %s" % p.why)
	var q := Quality.new(Callable(), null, null)
	check(q.files() and q.admit("file"), "with nothing pacing the picture nothing is priced and every file is drawn whole")
	q.free()


## Frames of `ms` with the file being measured in view: the GPU timer's settle, then `frames` more.
func _try(p: Quality.People, ms: float, frames: int) -> void:
	for i in Quality.Map.SETTLE_FRAMES + frames:
		p.measure(ms, true)


func _a_pinned_step_holds_the_density_map() -> void:
	var terrain := Terrain.new()
	var flora := Flora.new(terrain, Ground.new())
	root.add_child(flora)
	var foveated := -1
	for i in Quality.ladder.size():
		if Quality.ladder[i].foveation > 0:
			foveated = i
			break
	for pinned: bool in [true, false]:
		var q := Quality.new(func() -> float: return 72.0, null, flora)
		root.add_child(q)
		q.view = SubViewport.new()
		q._foveates = true
		var now := [0]
		q.clock = func() -> int: return now[0]
		if pinned:
			q.pin = foveated
		for i in int((Quality.WARMUP_S + 5.0) * 72):
			now[0] += int(1e6 / 72.0)
			if not pinned:
				q.governor.level = foveated
			q.frame((BUDGET * 5.0 if q.map.on else BUDGET * 0.5) + 0.001 * (i % 2), DT)
		check(q.map.on == pinned, "a density map making the frame five times the period %s: on %s" % ["stays on under a pin" if pinned else "comes off a governed step", q.map.on])
		if not pinned:
			q.pin = foveated
			check(q.map.on, "a pin taken with the map off puts it back on")
		q.view.free()
		q.free()
	flora.free()
