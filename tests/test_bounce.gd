extends "res://../tests/support/suite.gd"

## Headless checks of the light builds give back and of shadows and fog for a floating eye:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_bounce.gd

const WEST_LOW := Vector3(-0.917, 0.4, 0)
const EAST_LOW := Vector3(0.917, 0.4, 0)


func _init() -> void:
	_open_meadow_sees_the_whole_sky()
	_wall_feet_are_darker_than_the_open()
	_corners_are_darker_than_a_wall_face()
	_air_under_a_tower_on_a_wall_sees_the_sky()
	_tiles_shade_too()
	_sunlit_faces_bounce_light()
	_shaded_faces_bounce_none()
	_light_moves_with_the_sun()
	_taking_a_wall_away_restores_the_sky()
	_moving_the_sun_relights()
	_reshaped_ground_solves_again()
	_masonry_reports_only_what_stands_in_the_light()
	_floating_stretches_fog()
	_a_roof_overhead_hides_the_sky()
	_a_doorway_lets_the_sky_in()
	finish()


## A built wall from `a` to `b` on the ground as Masonry hands it over: a 0.4 m piece every 0.4 m in each
## course up to `height`.
func _wall(a: Vector2, b: Vector2, height := 2.6, from := 0.2) -> Array[PackedFloat32Array]:
	var kind := Wall.kinds()[Wall.Part.STONE]
	var stones := PackedFloat32Array()
	var n := 0
	var steps := ceili(a.distance_to(b) / 0.4)
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var y := from
		while y < height:
			stones.resize((n + 1) * kind.stride())
			kind.write(stones, n, Transform3D(Basis().scaled(Vector3.ONE * 0.4), Vector3(p.x, Terrain.height_at(p.x, p.y) + y, p.y)), Color(0.8, 0.78, 0.72))
			n += 1
			y += 0.4
	return [stones]


## A tower `radius` round `at` laid as on a wall's top: courses from `foot` above the ground up to `top`.
func _ring(at: Vector2, radius: float, foot: float, top: float) -> Array[PackedFloat32Array]:
	var kind := Wall.kinds()[Wall.Part.STONE]
	var stones := PackedFloat32Array()
	var n := 0
	var steps := ceili(TAU * radius / 0.4)
	for i in steps:
		var p := at + Vector2.from_angle(TAU * i / steps) * radius
		var y := foot + 0.2
		while y < top:
			stones.resize((n + 1) * kind.stride())
			kind.write(stones, n, Transform3D(Basis().scaled(Vector3.ONE * 0.4), Vector3(p.x, Terrain.height_at(p.x, p.y) + y, p.y)), Color(0.8, 0.78, 0.72))
			n += 1
			y += 0.4
	return [stones]


## Four walls round x, z in [-3, 3] with a doorway's gap 2 m high at z = 3, x in [-1.4, 1.4], and, with
## `roofed`, a tiled roof's pieces hanging 2.8 m up over it all.
func _house(roofed: bool) -> Array:
	var parts := [_wall(Vector2(-3, -3), Vector2(3, -3)), _wall(Vector2(3, -3), Vector2(3, 3)), _wall(Vector2(-3, -3), Vector2(-3, 3)),
		_wall(Vector2(-3, 3), Vector2(-1.6, 3)), _wall(Vector2(1.6, 3), Vector2(3, 3)), _wall(Vector2(-1.2, 3), Vector2(1.2, 3), 2.6, 2.2)]
	if roofed:
		for z in range(-3, 4):
			parts.append(_wall(Vector2(-3.4, z), Vector2(3.4, z), 3.2, 3.0))
	return parts


func _built(walls: Array, sun := EAST_LOW) -> Bounce:
	var b := Bounce.new()
	b.set_sun(sun, Color.WHITE)
	for i in walls.size():
		b.place(i + 1, walls[i], PackedInt32Array([Wall.kinds()[Wall.Part.STONE].stride()]))
	b.finish()
	return b


func _open_meadow_sees_the_whole_sky() -> void:
	var b := _built([_wall(Vector2(0, -5), Vector2(0, 5))])
	check(b.probe(30, 30, 0).a > 0.99, "a probe far from any build sees the whole sky")
	check(b.probe(30, 30, 0).r == 0.0, "and gets no bounce")


func _wall_feet_are_darker_than_the_open() -> void:
	var b := _built([_wall(Vector2(0, -5), Vector2(0, 5))])
	var foot := b.probe(1.5, 0, 0).a
	var away := b.probe(5.5, 0, 0).a
	check(foot < 0.85, "the ground at a wall's foot sees less sky, got %.2f" % foot)
	check(away > foot, "and more of it farther out: %.2f against %.2f" % [away, foot])
	check(b.probe(1.5, 0, 3).a > 0.99, "a layer whose middle is above the wall's top sees the whole sky")


func _corners_are_darker_than_a_wall_face() -> void:
	var b := _built([_wall(Vector2(0, -6), Vector2(0, 6)), _wall(Vector2(0, -6), Vector2(8, -6))])
	var corner := b.probe(1.5, -4.5, 0).a
	var face := b.probe(1.5, 3.5, 0).a
	check(corner < face, "an inner corner is darker than a straight wall's foot: %.2f against %.2f" % [corner, face])


func _air_under_a_tower_on_a_wall_sees_the_sky() -> void:
	var wall := _wall(Vector2(0, -6), Vector2(0, 6), 3.6)
	var plain := _built([wall]).probe(1.5, 0, 0).a
	var overhung := _built([wall, _ring(Vector2.ZERO, 1.8, 3.6, 8.0)]).probe(1.5, 0, 0).a
	var grounded := _built([wall, _ring(Vector2.ZERO, 1.8, 0.0, 8.0)]).probe(1.5, 0, 0).a
	check(overhung > plain * 0.8, "the foot of a wall under a tower standing on it sees the sky past the tower's overhang: %.2f against %.2f bare" % [overhung, plain])
	check(grounded < overhung, "a tower standing on the ground there hides more of it: %.2f against %.2f" % [grounded, overhung])


func _tiles_shade_too() -> void:
	var tiles := _wall(Vector2(0, -5), Vector2(0, 5))
	var b := Bounce.new()
	var stone := Wall.kinds()[Wall.Part.STONE].stride()
	b.place(1, [PackedFloat32Array(), tiles[0]] as Array[PackedFloat32Array], PackedInt32Array([stone, stone]))
	b.finish()
	check(b.probe(1.5, 0, 0).a < 0.85, "every buffer placed shades, not only the first")


func _sunlit_faces_bounce_light() -> void:
	# The wall at x = -4 faces the low eastern sun over the lower wall at x = 0.
	var b := _built([_wall(Vector2(0, -6), Vector2(0, 6), 1.0), _wall(Vector2(-4, -6), Vector2(-4, 6))])
	check(b.probe(-2.5, 0, 0).r > 0.0, "ground facing a sunlit face takes its light, got %.3f" % b.probe(-2.5, 0, 0).r)


func _shaded_faces_bounce_none() -> void:
	var lone := _built([_wall(Vector2(-3, -6), Vector2(-3, 6))])
	var shaded := _built([_wall(Vector2(-3, -6), Vector2(-3, 6)), _wall(Vector2(0, -6), Vector2(0, 6), 6.0)])
	check(shaded.probe(-1.5, 0, 0).r < lone.probe(-1.5, 0, 0).r * 0.5, "a face in a taller wall's shadow throws back little light: %.3f against %.3f" % [shaded.probe(-1.5, 0, 0).r, lone.probe(-1.5, 0, 0).r])


func _light_moves_with_the_sun() -> void:
	var w := _wall(Vector2(0, -6), Vector2(0, 6))
	var west := _built([w], WEST_LOW)
	var east := _built([w], EAST_LOW)
	check(east.probe(1.5, 0, 0).r > west.probe(1.5, 0, 0).r, "the face toward the sun lights the ground before it")


func _taking_a_wall_away_restores_the_sky() -> void:
	var b := _built([_wall(Vector2(0, -5), Vector2(0, 5))])
	b.place(1, [] as Array[PackedFloat32Array], PackedInt32Array())
	b.finish()
	check(b.probe(1.5, 0, 0).a > 0.99, "a wall taken away gives back its sky")
	check(b.probe(1.5, 0, 0).r == 0.0, "and its bounce")


func _moving_the_sun_relights() -> void:
	var b := _built([_wall(Vector2(0, -6), Vector2(0, 6))], WEST_LOW)
	var was := b.probe(1.5, 0, 0).r
	b.set_sun(EAST_LOW, Color.WHITE)
	b.finish()
	check(b.probe(1.5, 0, 0).r > was, "a sun that moved lights the faces now toward it")


func _reshaped_ground_solves_again() -> void:
	var b := _built([_wall(Vector2(0, -5), Vector2(0, 5))])
	var foot := b.probe(1.5, 0, 0).a
	var cells := Terrain.cells_around(1.5, 0, 3)
	var before := Terrain.read(cells)
	var raised := before.duplicate()
	for i in raised.size():
		raised[i] += 2.0
	Terrain.write(cells, raised)
	b.finish()
	check(b.probe(1.5, 0, 0).a > foot, "ground raised beside a wall sees over more of it: %.2f then %.2f" % [foot, b.probe(1.5, 0, 0).a])
	Terrain.write(cells, before)


func _masonry_reports_only_what_stands_in_the_light() -> void:
	var m := Masonry.new(Wall.kinds())
	var got := []
	m.placed.connect(func(o: int, bufs: Array[PackedFloat32Array], strides: PackedInt32Array) -> void: got.append([o, bufs.size(), strides]))
	var parts: Array[Dictionary] = []
	for k in Wall.Part.size():
		var buf := PackedFloat32Array()
		buf.resize(Wall.kinds()[k].stride())
		parts.append(Masonry.split(buf, Wall.kinds()[k]))
	m.place(7, parts)
	check(got.size() == 1 and got[0][1] == 4, "a wall's stones, tiles, thatch slabs and timbers shade, not its mortar, shadow boxes or ivy: %s" % [got])
	m.remove(7)
	check(got.size() == 2 and got[1][1] == 0, "and it reports when they go")
	m.remove(7)
	check(got.size() == 2, "and nothing for what was never there")
	m.free()


func _floating_stretches_fog() -> void:
	var standing := Look.fog_at_height(1.65)
	var floating := Look.fog_at_height(25.0)
	check(standing.fog_depth_begin == Look.FOG_BEGIN, "a standing eye keeps the standing fog")
	check(floating.fog_depth_begin > 25.0 and floating.fog_depth_end > standing.fog_depth_end, "and fog starts beyond it")


func _a_roof_overhead_hides_the_sky() -> void:
	var open := _built(_house(false))
	var roofed := _built(_house(true))
	for layer in 3:
		var a := open.probe(0.5, -1.5, layer).a
		var b := roofed.probe(0.5, -1.5, layer).a
		check(b < 0.1, "under a roof layer %d sees almost no sky: %.2f" % [layer, b])
		check(b < a, "and less than without it: %.2f against %.2f" % [b, a])
	check(roofed.probe(0.5, -1.5, 0).r == 0.0, "a roof's shaded underside throws back no sunlight")
	check(roofed.probe(10.5, 0.5, 0).a > 0.99, "the garden away from it keeps its sky")
	var eye := Vector3(0.5, Terrain.height_at(0.5, -1.5) + 1.6, -1.5)
	check(roofed.sky_at(eye) < 0.1, "an eye under the roof sees almost no sky, as exposure reads it: %.2f" % roofed.sky_at(eye))
	check(roofed.sky_at(Vector3(10.5, Terrain.height_at(10.5, 0.5) + 1.6, 0.5)) > 0.99, "an eye in the garden sees all of it")


func _a_doorway_lets_the_sky_in() -> void:
	var b := _built(_house(true))
	var by_door := b.probe(0.5, 1.5, 0).a
	var back := b.probe(0.5, -1.5, 0).a
	check(by_door > back, "inside, the floor by the doorway sees more sky than the back: %.3f against %.3f" % [by_door, back])
