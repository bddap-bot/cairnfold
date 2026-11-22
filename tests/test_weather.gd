extends "res://../tests/support/suite.gd"

## What the fog and snow look like needs a renderer; demo/weather.json shows them on the desktop.


func _initialize() -> void:
	_the_clear_weather_keeps_the_tuned_fog()
	_thicker_fog_comes_nearer()
	_the_ground_layer_rises_from_clinging_to_standing_high()
	_snow_falls_in_a_winter_alone()
	_the_hand_shapes_it_by_turn_and_rise()
	_peers_send_only_weather_in_range()
	_the_sky_let_go_turning_runs_on()
	boot_main()
	_in_the_garden.call_deferred()


func _the_clear_weather_keeps_the_tuned_fog() -> void:
	for lift: float in [0.0, 9.0, 25.0]:
		var fog := Weather.fog(Weather.CLEAR, Look.fog_at_height(lift))
		var tuned := Look.fog_at_height(lift)
		check(is_equal_approx(fog.fog_depth_begin, tuned.fog_depth_begin) and is_equal_approx(fog.fog_depth_end, tuned.fog_depth_end), "the clear weather's fog begins and ends where the tuned fog does %.0f m up" % lift)
	var fog := Weather.fog(Weather.CLEAR, Look.fog_at_height(0.0))
	check(is_equal_approx(fog.fog_density, Look.AIR_FOG.fog_density) and is_equal_approx(fog.fog_sky_affect, Look.AIR_FOG.fog_sky_affect), "as thick, taking as much of the sky: %.3f, %.3f" % [fog.fog_density, fog.fog_sky_affect])
	check(fog.fog_height_density == 0.0 and Weather.veil(Weather.CLEAR) == 0.0, "with no layer on the ground and no veil on the far hills")


func _thicker_fog_comes_nearer() -> void:
	var standing := Look.fog_at_height(0.0)
	var last := {}
	for k in 11:
		var w := Weather.CLEAR.merged({"thick": k / 10.0}, true)
		var fog := Weather.fog(w, standing)
		if not last.is_empty():
			check(fog.fog_depth_end < last.fog_depth_end and fog.fog_depth_begin < last.fog_depth_begin, "thicker fog begins and ends nearer at %.1f: %.1f to %.1f m" % [w.thick, fog.fog_depth_begin, fog.fog_depth_end])
			check(fog.fog_density > last.fog_density and fog.fog_sky_affect > last.fog_sky_affect, "and is denser, taking more of the sky, at %.1f" % w.thick)
			check(Weather.veil(w) >= Weather.veil(last.w), "and veils the far hills no less at %.1f" % w.thick)
		last = fog.merged({"w": w})
	var thickest := Weather.fog(Weather.CLEAR.merged({"thick": 1.0}, true), standing)
	var thinnest := Weather.fog(Weather.CLEAR.merged({"thick": 0.0}, true), standing)
	check(thickest.fog_depth_end < 20.0 and thickest.fog_density == 1.0, "the thickest fog closes in within 20 m: %.1f" % thickest.fog_depth_end)
	check(thinnest.fog_depth_end > standing.fog_depth_end * 1.8, "the thinnest lets the eye see twice as far: %.0f m" % thinnest.fog_depth_end)
	check(Weather.veil(Weather.CLEAR.merged({"thick": 1.0}, true)) == 1.0, "and the thickest hides the far hills whole")


func _the_ground_layer_rises_from_clinging_to_standing_high() -> void:
	var standing := Look.fog_at_height(0.0)
	var low := Weather.fog(Weather.CLEAR.merged({"high": 0.06}, true), standing)
	var none := Weather.fog(Weather.CLEAR.merged({"high": 0.0}, true), standing)
	var gathering := Weather.fog(Weather.CLEAR.merged({"high": 0.01}, true), standing)
	check(none.fog_height_density == 0.0 and gathering.fog_height_density > 0.0 and gathering.fog_height_density < low.fog_height_density * 0.5, "the layer gathers from nothing as it first rises: %.3f a metre" % gathering.fog_height_density)
	var high := Weather.fog(Weather.CLEAR.merged({"high": 1.0}, true), standing)
	check(low.fog_height_density > 0.0 and low.fog_height < 1.5, "a little height lays a layer clinging to the ground: its top at %.2f m" % low.fog_height)
	check(high.fog_height == Weather.LAYER.y, "the most stands it %.0f m high" % high.fog_height)
	var thin := Weather.fog({"thick": 0.0, "high": 0.5, "snow": 0.0}, standing)
	var thick := Weather.fog({"thick": 1.0, "high": 0.5, "snow": 0.0}, standing)
	check(thick.fog_height_density > thin.fog_height_density * 5.0 and thin.fog_height == thick.fog_height, "a thicker layer is denser under the same top: %.2f against %.2f a metre" % [thick.fog_height_density, thin.fog_height_density])


func _snow_falls_in_a_winter_alone() -> void:
	var mesh := Snowfall.flakes(100)
	var stored: Variant = mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	var custom: PackedFloat32Array = stored.to_float32_array() if stored is PackedByteArray else stored
	var ranks := []
	for i in 100:
		ranks.append(custom[i * 16 + 3])
	check(range(100).all(func(i: int) -> bool: return absf(ranks[i] - (i + 0.5) / 100.0) < 1e-6), "every flake has its own rank, so a share of them falls")
	var first_half := Vector3.ZERO
	for i in 50:
		first_half += Vector3(custom[i * 16], custom[i * 16 + 1], custom[i * 16 + 2])
	check((first_half / 50.0).distance_to(Vector3.ONE * 0.5) < 0.12, "and the flakes falling in a light snow fill the box: centred at %s" % (first_half / 50.0))


func _the_hand_shapes_it_by_turn_and_rise() -> void:
	var start := Weather.CLEAR.duplicate()
	var thicker := WeatherTool.shaped(start, false, 90.0, 0.0)
	check(is_equal_approx(thicker.thick, 0.75) and thicker.high == 0.0 and thicker.snow == 0.0, "a wrist turned clockwise half way thickens the fog half way: %s" % thicker)
	check(WeatherTool.shaped(start, false, -400.0, 0.0).thick == 0.0, "turned back far enough it is the thinnest")
	var lifted := WeatherTool.shaped(start, false, 0.0, WeatherTool.FULL_RISE * 0.25)
	check(is_equal_approx(lifted.high, 0.25) and lifted.thick == start.thick, "the hand raised lifts the fog off the ground: %s" % lifted)
	check(WeatherTool.shaped(lifted, false, 0.0, -1.0).high == 0.0, "lowered all the way it lies on the ground no more")
	var snowing := WeatherTool.shaped(start, true, WeatherTool.FULL_TURN, 0.3)
	check(snowing.snow == 1.0 and snowing.thick == start.thick and snowing.high == start.high, "aimed at a winter sky the turn sets the snowfall alone: %s" % snowing)


func _peers_send_only_weather_in_range() -> void:
	var t := Terrain.new()
	var ok := Commands.clean({"op": "weather", "thick": 1.0, "high": 0.3, "snow": 0.0}, World.blank(), false, t)
	check(ok == {"op": "weather", "thick": 1.0, "high": 0.3, "snow": 0.0}, "a weather command is taken whole: %s" % ok)
	for bad: Dictionary in [{"thick": 1.5, "high": 0.0, "snow": 0.0}, {"thick": 0.5, "high": -0.1, "snow": 0.0}, {"thick": 0.5, "high": 0.0}, {"thick": 0.5, "high": 0.0, "snow": NAN}, {"thick": 1, "high": 0.0, "snow": 0.0}]:
		check(Commands.clean({"op": "weather"}.merged(bad), World.blank(), false, t).is_empty(), "and one out of range or short is turned down: %s" % bad)
	check(not Commands.clean({"op": "sky", "time": 0.5, "pace": SkyTool.FASTEST}, World.blank(), false, t).is_empty(), "the sky runs as fast as a day a minute")
	check(Commands.clean({"op": "sky", "time": 0.5, "pace": SkyTool.FASTEST * 2.0}, World.blank(), false, t).is_empty() and Commands.clean({"op": "sky", "time": 0.5}, World.blank(), false, t).is_empty(), "and no faster, nor with no pace")


func _the_sky_let_go_turning_runs_on() -> void:
	check(SkyTool.pace_of(deg_to_rad(SkyTool.STILL * 0.95)) == 0.0 and SkyTool.pace_of(-deg_to_rad(SkyTool.STILL * 0.95)) == 0.0, "let go turning slower than %.0f° a second, the sky stands" % SkyTool.STILL)
	var slow := SkyTool.pace_of(deg_to_rad(SkyTool.STILL + 5.0))
	check(slow > 0.0 and 1.0 / slow / 3600.0 >= 6.0, "let go turning a little faster it runs slowly, %.0f hours a day" % (1.0 / slow / 3600.0))
	var last := 0.0
	for deg in range(20, 181, 10):
		var p := SkyTool.pace_of(deg_to_rad(deg))
		check(p > last, "turned faster it runs faster: %.0f° a second, a day in %.1f minutes" % [deg, 1.0 / p / 60.0])
		last = p
		check(is_equal_approx(SkyTool.pace_of(SkyTool.rate_for(p)), p), "and the turn for a pace gives that pace at %.0f°" % deg)
	check(SkyTool.pace_of(-deg_to_rad(60.0)) == -SkyTool.pace_of(deg_to_rad(60.0)) and SkyTool.pace_of(-deg_to_rad(60.0)) < 0.0, "turned back, it runs back as fast")
	check(SkyTool.pace_of(100.0) == SkyTool.FASTEST and SkyTool.pace_of(-100.0) == -SkyTool.FASTEST, "flung hard it runs a day a minute at most")


func _in_the_garden() -> void:
	await frames(3)
	var world: World = main.world
	var look: Look = main.look
	var weather_on_wheel := ToolWheel.paths(Hand.TREE)
	check(weather_on_wheel.has(Hand.Tool.WEATHER) and weather_on_wheel[Hand.Tool.WEATHER].slice(0, -1) == weather_on_wheel[Hand.Tool.SEEDS].slice(0, -1), "the weather opens beside the seeds and the easel: %s" % [weather_on_wheel.get(Hand.Tool.WEATHER)])
	var flakes := Snowfall.new()
	main.add_child(flakes)
	flakes.fall(Vector3(1, 2, 3), 0.0, 1.0)
	check(not flakes.visible, "with none falling none are drawn")
	flakes.fall(Vector3(1, 2, 3), 0.5, 0.0)
	check(not flakes.visible, "nor under a roof")
	flakes.fall(Vector3(1, 2, 3), 0.5, 0.8)
	check(flakes.visible and flakes.global_position == Vector3(1, 2, 3) and flakes.mat.get_shader_parameter("amount") == 0.5 and flakes.mat.get_shader_parameter("open") == 0.8, "falling, they wrap round the head, as many as the snowfall")
	flakes.free()
	var cloud := ToolModels.build(Hand.Tool.WEATHER)
	check(cloud.get_child_count() > 0, "and the hand holds a cloud")
	cloud.free()
	var tuned := Look.AIR_FOG.merged(Look.fog_at_height(look._lift), true)
	check(look.env.fog_height_density == 0.0 and is_equal_approx(look.env.fog_depth_end, tuned.fog_depth_end) and is_equal_approx(look.env.fog_density, tuned.fog_density) and is_equal_approx(look.env.fog_sky_affect, tuned.fog_sky_affect), "a new garden's fog is the tuned one")

	await play([{"op": "weather", "hand": "left", "thick": 0.9, "high": 0.2, "seconds": 0.5}])
	check(absf(world.weather.thick - 0.9) < 0.02 and absf(world.weather.high - 0.2) < 0.02, "the weather op's turn and rise shape the garden's fog: %s" % world.weather)
	var want := fog_now(world.weather, look)
	check(is_equal_approx(look.env.fog_depth_end, want.fog_depth_end) and is_equal_approx(look.env.fog_height, want.fog_height) and is_equal_approx(look.env.fog_height_density, want.fog_height_density), "and the view shows it: ends at %.1f m, a layer to %.1f m" % [look.env.fog_depth_end, look.env.fog_height])
	var stack: int = world.stacks.get(world.me(), {"undo": []}).undo.size()
	check(main.weather_tool.shaping.is_empty(), "the trigger let go, no hand shapes it")
	look.submerge(true)
	check(look.env.fog_height_density == 0.0 and look.env.fog_depth_end == Look.WATER_FOG.fog_depth_end, "under water the water's fog takes over, no layer on it")
	look.submerge(false)
	check(is_equal_approx(look.env.fog_height_density, want.fog_height_density) and is_equal_approx(look.env.fog_depth_end, want.fog_depth_end), "and out again the weather's fog is back")

	var hand: Hand = main.rig.right
	var was := hand.global_transform
	hand.tool = Hand.Tool.WEATHER
	hand.global_basis = Basis.looking_at(Vector3(0, 1, -1).normalized())
	main.weather_tool.open(hand)
	check(not main.weather_tool.shaping[hand].snow, "aimed at a summer sky the hand shapes the fog, since no snow falls then")
	main.weather_tool.shaping.erase(hand)
	await play([{"op": "colour", "hand": "left", "element": "meadow", "swatch": 4, "seconds": 0.3}, {"op": "pick", "hand": "left", "tool": "none"}])
	await play([{"op": "weather", "hand": "right", "snow": 0.8, "seconds": 0.3}])
	check(absf(world.weather.snow - 0.8) < 0.02, "in winter, aimed at the sky, it sets the snowfall: %s" % world.weather)
	await frames(2)
	check(look.snow.visible and is_equal_approx(look.snow.mat.get_shader_parameter("amount"), world.weather.snow), "and the snow falls round the head")
	await play([{"op": "colour", "hand": "left", "element": "meadow", "swatch": 1, "seconds": 0.3}, {"op": "pick", "hand": "left", "tool": "none"}])
	await frames(2)
	check(not look.snow.visible and world.weather.snow > 0.0, "back in summer it stops, the snowfall kept for the next winter")

	check(world.stacks.get(world.me(), {"undo": []}).undo.size() == stack + 2, "shaping the weather is no step to undo, only the season's two turns")
	var kept := world.weather.duplicate()
	var snap := world.snapshot()
	check(snap.cmds.any(func(c: Dictionary) -> bool: return c.op == "weather" and c.thick == kept.thick and c.snow == kept.snow), "the garden keeps its weather")
	await play([{"op": "wipe", "seconds": 2.5}])
	check(world.weather == kept and look.weather == kept, "a wipe leaves the weather be")
	await play([{"op": "weather", "hand": "left", "thick": 0.4, "seconds": 0.3}, {"op": "undo"}])
	await frames(5)
	check(absf(world.weather.thick - 0.4) < 0.02 and world.weather.snow == kept.snow, "and undoing the wipe brings the garden back under the weather it has now: %s" % world.weather)
	world.restore({"format": world.format(), "seq": 0, "cmds": []})
	check(world.weather == Weather.CLEAR and look.weather == Weather.CLEAR and look.env.fog_height_density == 0.0, "a fresh garden starts clear")
	world.restore(snap)
	check(world.weather == kept and look.weather == kept, "and the kept one comes back with its weather")

	var stack_before: int = world.stacks.get(world.me(), {"undo": []}).undo.size()
	await play([{"op": "sun", "time": 0.45, "seconds": 0.4}])
	check(world.pace == 0.0 and absf(world.time - 0.45) < 1e-3, "the sky let go held still stands where it was set")
	await frames(30)
	check(absf(world.time - 0.45) < 1e-3, "and stays")
	await play([{"op": "sun", "time": 0.5, "pace": 0.5, "seconds": 0.4}])
	check(absf(world.pace - 0.5 / 60.0) < 0.5 / 60.0 * 0.02, "let go turning, the sky runs on by itself, half a day a minute: %.5f" % world.pace)
	var from := world.time
	await frames(60)
	check(absf(wrapf(world.time - from - world.pace, -0.5, 0.5)) < 1e-3 + World.RUN_STEP and absf(look.time - world.time) < 1e-6, "a second later it has run on %.4f of a day, the view with it" % (world.time - from))
	check(world.snapshot().cmds.any(func(c: Dictionary) -> bool: return c.op == "sky" and c.pace == world.pace), "the garden keeps it running")
	var moves := 0
	var shown := look.time
	for f in 60:
		await process_frame
		if look.time != shown:
			check(absf(wrapf(look.time - shown, -0.5, 0.5)) >= World.RUN_STEP * 0.999, "the light moves a minute of the day at a time, not every frame")
			moves += 1
			shown = look.time
	check(moves > 3 and moves < 30, "so a running sky relights the garden %d times a second, not 60" % moves)
	var stack_now: int = world.stacks.get(world.me(), {"undo": []}).undo.size()
	check(stack_now == stack_before, "letting the sky run is no step to undo either")
	var sky: SkyTool = main.sky_tool
	var grab := Daylight.toward_sun(look.time).rotated(Vector3.UP, deg_to_rad(40.0))
	var still := hand.held_still
	hand.held_still = true
	hand.global_basis = Basis.looking_at(grab)
	sky.take(hand, grab)
	await frames(2)
	var held := look.time
	await frames(20)
	check(sky.holder == hand and absf(look.time - held) < 1e-6, "a hand on the sky holds it from running")
	sky.holder = null
	hand.held_still = still
	hand.global_transform = was
	await play([{"op": "sun", "time": 0.3, "pace": -1.0, "seconds": 0.4}])
	check(world.pace < 0.0, "turned back and let go, it runs back: %.5f" % world.pace)
	from = world.time
	await frames(60)
	check(wrapf(world.time - from, -0.5, 0.5) < 0.0, "toward the dawn")
	await play([{"op": "sun", "time": 0.5, "seconds": 0.4}])
	check(world.pace == 0.0, "and let go still it stands again")
	finish()


static func fog_now(w: Dictionary, look: Look) -> Dictionary:
	return Weather.fog(w, Look.fog_at_height(look._lift))
