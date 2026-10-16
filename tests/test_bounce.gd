extends SceneTree

## Headless checks of the light builds give back and of shadows and fog for a floating eye:
## godot4 --headless --path game --script ../tests/test_bounce.gd

const WEST_LOW := Vector3(-0.917, 0.4, 0)
const EAST_LOW := Vector3(0.917, 0.4, 0)

var failures := 0


func _init() -> void:
	_open_meadow_sees_the_whole_sky()
	_wall_feet_are_darker_than_the_open()
	_corners_are_darker_than_a_wall_face()
	_tiles_shade_too()
	_sunlit_faces_bounce_light()
	_shaded_faces_bounce_none()
	_light_moves_with_the_sun()
	_taking_a_wall_away_restores_the_sky()
	_moving_the_sun_relights()
	_reshaped_ground_solves_again()
	_masonry_reports_only_what_stands_in_the_light()
	_floating_stretches_shadows_and_fog()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## A built wall from `a` to `b` on the ground as Masonry hands it over: a 0.4 m piece every 0.4 m in each
## course up to `height`.
func _wall(a: Vector2, b: Vector2, height := 2.6) -> Array[PackedFloat32Array]:
	var kind := Wall.kinds()[Wall.Part.STONE]
	var stones := PackedFloat32Array()
	var n := 0
	var steps := ceili(a.distance_to(b) / 0.4)
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var y := 0.2
		while y < height:
			stones.resize((n + 1) * kind.stride())
			kind.write(stones, n, Transform3D(Basis().scaled(Vector3.ONE * 0.4), Vector3(p.x, Terrain.height_at(p.x, p.y) + y, p.y)), Color(0.8, 0.78, 0.72))
			n += 1
			y += 0.4
	return [stones]


func _built(walls: Array, sun := EAST_LOW) -> Bounce:
	var b := Bounce.new()
	b.set_sun(sun, Color.WHITE)
	for i in walls.size():
		b.place(i + 1, walls[i], PackedInt32Array([Wall.kinds()[Wall.Part.STONE].stride()]))
	b.finish()
	return b


func _open_meadow_sees_the_whole_sky() -> void:
	var b := _built([_wall(Vector2(0, -5), Vector2(0, 5))])
	_check(b.probe(30, 30, 0).a > 0.99, "a probe far from any build sees the whole sky")
	_check(b.probe(30, 30, 0).r == 0.0, "and gets no bounce")


func _wall_feet_are_darker_than_the_open() -> void:
	var b := _built([_wall(Vector2(0, -5), Vector2(0, 5))])
	var foot := b.probe(1.5, 0, 0).a
	var away := b.probe(5.5, 0, 0).a
	_check(foot < 0.85, "the ground at a wall's foot sees less sky, got %.2f" % foot)
	_check(away > foot, "and more of it farther out: %.2f against %.2f" % [away, foot])
	_check(b.probe(1.5, 0, 3).a > 0.99, "a layer whose middle is above the wall's top sees the whole sky")


func _corners_are_darker_than_a_wall_face() -> void:
	var b := _built([_wall(Vector2(0, -6), Vector2(0, 6)), _wall(Vector2(0, -6), Vector2(8, -6))])
	var corner := b.probe(1.5, -4.5, 0).a
	var face := b.probe(1.5, 3.5, 0).a
	_check(corner < face, "an inner corner is darker than a straight wall's foot: %.2f against %.2f" % [corner, face])


func _tiles_shade_too() -> void:
	var tiles := _wall(Vector2(0, -5), Vector2(0, 5))
	var b := Bounce.new()
	var stone := Wall.kinds()[Wall.Part.STONE].stride()
	b.place(1, [PackedFloat32Array(), tiles[0]] as Array[PackedFloat32Array], PackedInt32Array([stone, stone]))
	b.finish()
	_check(b.probe(1.5, 0, 0).a < 0.85, "every buffer placed shades, not only the first")


func _sunlit_faces_bounce_light() -> void:
	# The wall at x = -4 faces the low eastern sun over the lower wall at x = 0.
	var b := _built([_wall(Vector2(0, -6), Vector2(0, 6), 1.0), _wall(Vector2(-4, -6), Vector2(-4, 6))])
	_check(b.probe(-2.5, 0, 0).r > 0.0, "ground facing a sunlit face takes its light, got %.3f" % b.probe(-2.5, 0, 0).r)


func _shaded_faces_bounce_none() -> void:
	var lone := _built([_wall(Vector2(-3, -6), Vector2(-3, 6))])
	var shaded := _built([_wall(Vector2(-3, -6), Vector2(-3, 6)), _wall(Vector2(0, -6), Vector2(0, 6), 6.0)])
	_check(shaded.probe(-1.5, 0, 0).r < lone.probe(-1.5, 0, 0).r * 0.5, "a face in a taller wall's shadow throws back little light: %.3f against %.3f" % [shaded.probe(-1.5, 0, 0).r, lone.probe(-1.5, 0, 0).r])


func _light_moves_with_the_sun() -> void:
	var w := _wall(Vector2(0, -6), Vector2(0, 6))
	var west := _built([w], WEST_LOW)
	var east := _built([w], EAST_LOW)
	_check(east.probe(1.5, 0, 0).r > west.probe(1.5, 0, 0).r, "the face toward the sun lights the ground before it")


func _taking_a_wall_away_restores_the_sky() -> void:
	var b := _built([_wall(Vector2(0, -5), Vector2(0, 5))])
	b.place(1, [] as Array[PackedFloat32Array], PackedInt32Array())
	b.finish()
	_check(b.probe(1.5, 0, 0).a > 0.99, "a wall taken away gives back its sky")
	_check(b.probe(1.5, 0, 0).r == 0.0, "and its bounce")


func _moving_the_sun_relights() -> void:
	var b := _built([_wall(Vector2(0, -6), Vector2(0, 6))], WEST_LOW)
	var was := b.probe(1.5, 0, 0).r
	b.set_sun(EAST_LOW, Color.WHITE)
	b.finish()
	_check(b.probe(1.5, 0, 0).r > was, "a sun that moved lights the faces now toward it")


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
	_check(b.probe(1.5, 0, 0).a > foot, "ground raised beside a wall sees over more of it: %.2f then %.2f" % [foot, b.probe(1.5, 0, 0).a])
	Terrain.write(cells, before)


func _masonry_reports_only_what_stands_in_the_light() -> void:
	var m := Masonry.new(Wall.kinds())
	var got := []
	m.placed.connect(func(o: int, bufs: Array[PackedFloat32Array], strides: PackedInt32Array) -> void: got.append([o, bufs.size(), strides]))
	var parts: Array[Dictionary] = []
	for k in Wall.Part.size():
		var buf := PackedFloat32Array()
		buf.resize(Wall.kinds()[k].stride())
		parts.append(Masonry.split(buf, Wall.kinds()[k].stride()))
	m.place(7, parts)
	_check(got.size() == 1 and got[0][1] == 2, "a wall's stones and tiles shade, not its mortar, shadow boxes or ivy: %s" % [got])
	m.remove(7)
	_check(got.size() == 2 and got[1][1] == 0, "and it reports when they go")
	m.remove(7)
	_check(got.size() == 2, "and nothing for what was never there")
	m.free()


func _floating_stretches_shadows_and_fog() -> void:
	var standing := Look.shadow_and_fog(1.65)
	var floating := Look.shadow_and_fog(25.0)
	_check(standing.shadow_reach == Look.SHADOW_REACH and standing.fog_begin == Look.FOG_BEGIN, "a standing eye keeps the standing shadows and fog")
	_check(floating.shadow_reach > standing.shadow_reach and floating.shadow_reach <= Look.SHADOW_FARTHEST, "shadows reach farther from the air, to a bound")
	_check(floating.shadow_reach * floating.near_split > 25.0, "from 25 m up the near split reaches past the drop to the ground")
	_check(floating.fog_begin > 25.0 and floating.fog_end > standing.fog_end, "and fog starts beyond it")
