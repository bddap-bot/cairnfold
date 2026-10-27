extends "res://../tests/support/suite.gd"

var probes := 0
var cases := 0
var triangles := 0
var instances := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for finish_kind in WallLayout.Finish.values():
		for pitch in [0.0, 1.2, 4.0]:
			for curve in [-RoofLayout.CURVE, 0.0, RoofLayout.CURVE]:
				for thatch in [false] if pitch == 0.0 else [false, true]:
					for raised in [0.0, 1.5]:
						_case(finish_kind, pitch, curve, thatch, raised)
	for curve in [-RoofLayout.CURVE, 0.0, RoofLayout.CURVE]:
		for pitch in [0.0, 1.2, 4.0]:
			for thatch in [false] if pitch == 0.0 else [false, true]:
				_case(WallLayout.Finish.BARE, pitch, curve, thatch, 1.5, RoofLayout.Kind.CONE)
	for end in [WallLayout.GableEnd.BOARDS, WallLayout.GableEnd.STEPS]:
		for finish_kind in WallLayout.Finish.values():
			for curve in [-RoofLayout.CURVE, 0.0, RoofLayout.CURVE]:
				for thatch in [false, true]:
					_case(finish_kind, 1.2, curve, thatch, 1.5, RoofLayout.Kind.GABLE, end)
	print("tests: roof closure: %d cases, %d probes, %d leaks; %d instances, %d triangles" % [cases, probes, failures, instances, triangles])
	finish()


func _case(finish_kind: WallLayout.Finish, pitch: float, curve: float, thatch: bool, raised: float, kind := RoofLayout.Kind.GABLE, end_style := WallLayout.GableEnd.WALL) -> void:
	cases += 1
	var r := RoofLayout.new()
	r.kind = kind
	r.radius = 2.25
	r.pitch = pitch
	r.curve = curve
	r.thatch = thatch
	var w := WallLayout.new()
	w.seed = 216519444
	w.points = WallLayout.circle(Vector3.ZERO, r.radius) if kind == RoofLayout.Kind.CONE else WallLayout.rectangle(Vector3.ZERO, Vector3(7.75, 0, 0), 4.5)
	w.closed = true
	w.finish = finish_kind
	w.height = 2.4
	w.rise = raised
	w.cover = WallLayout.Cover.DECK if r.flat() else WallLayout.Cover.ROOF
	w.gable_end = end_style
	w.gable = r
	w.build(func(_x: float, _z: float) -> float: return 0.0)
	var kinds := Wall.kinds()
	var roof := Wall.pack_roof(w, r, kinds, Palette.plain())
	var packed := Wall.pack(w, kinds, Palette.plain())
	var rendered := Wall.new(w.seed, null, Terrain.new())
	rendered.layout = w
	rendered.add_roof(r)
	rendered._take(packed)
	rendered._pack_roof(roof)
	var faces := PackedVector3Array()
	for part in [Wall.Part.STONE, Wall.Part.MORTAR, Wall.Part.TIMBER, Wall.Part.TILE]:
		faces.append_array(_instances(rendered._parts[part], kinds[part]))
		instances += rendered._parts[part].size() / kinds[part].stride()
	for node in [rendered._gables, rendered._torching, rendered._coat, rendered._ceiling]:
		if node.mesh != null:
			faces.append_array(node.mesh.get_faces())
	triangles += faces.size() / 3
	rendered.free()
	var mesh := TriangleMesh.new()
	assert(mesh.create_from_faces(faces))
	var leaks := 0
	var corners: Array[float] = []
	corners.assign(w.corners() if kind == RoofLayout.Kind.GABLE else [0.0])
	for side in corners.size():
		for i in range(1, 20):
			var start: float = corners[side]
			var end: float = corners[side + 1] if side + 1 < corners.size() else w.length()
			var f := w.frame_at(lerpf(start, end, i / 20.0))
			var outward: Vector3 = f.tangent.cross(Vector3.UP) * -w.inner_side()
			var heights: Array[float] = []
			for dy_i in range(1, 14, 2):
				heights.append(f.point.y + w.height + dy_i * 0.01)
			for below in [0.05, 0.1]:
				heights.append(r.height_at(f.point.x, f.point.z) - below)
			for height in heights:
				var target: Vector3 = Vector3(f.point.x, height, f.point.z)
				for slope_i in range(-32, 33, 8):
					var slope := slope_i * 0.025
					var dir: Vector3 = (outward + Vector3.UP * slope).normalized()
					var origin := target - dir * 0.8
					if origin.y >= r.height_at(origin.x, origin.z) - RoofLayout.TORCHING_DROP:
						continue
					probes += 1
					var hit := mesh.intersect_ray(origin, dir)
					var cavity := w.plastered() and end_style == WallLayout.GableEnd.WALL and not r.flat() and side % 2 == 1 and slope == 0.0 and height < r.base and not hit.is_empty() and origin.distance_to(hit.position) > origin.distance_to(target)
					if hit.is_empty() or cavity:
						leaks += 1
						if leaks < 4:
							print("LEAK ", origin, " ", dir, " side ", side, " height ", height, " slope ", slope)
	failures += leaks
	if leaks > 0:
		print("FAIL: closure kind=%d end=%d finish=%d pitch=%.1f curve=%.2f thatch=%s raised=%.1f: %d leaks" % [kind, end_style, finish_kind, pitch, curve, thatch, raised, leaks])


## Reproduce the rendered instance transforms, including the panel mitres in stone.gdshaderinc.
static func _instances(buffer: PackedFloat32Array, kind: Masonry.Kind) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var source := kind.mesh.get_faces()
	for i in range(0, buffer.size(), kind.stride()):
		var x := Transform3D(Basis(Vector3(buffer[i], buffer[i + 4], buffer[i + 8]), Vector3(buffer[i + 1], buffer[i + 5], buffer[i + 9]), Vector3(buffer[i + 2], buffer[i + 6], buffer[i + 10])), Vector3(buffer[i + 3], buffer[i + 7], buffer[i + 11]))
		for v in source:
			if kind.custom:
				var turn := buffer[i + (18 if v.x < 0.0 else 19)]
				if turn != 0.0:
					v.x += v.z * x.basis.z.length() * tan(turn) / Vector2(x.basis.x.x, x.basis.x.z).length()
			faces.append(x * v)
	return faces
