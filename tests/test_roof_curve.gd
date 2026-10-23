extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for kind in RoofLayout.Kind.values():
		for curve in [-RoofLayout.CURVE, 0.0, RoofLayout.CURVE]:
			var r := RoofLayout.new()
			r.kind = kind
			r.corners = WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0)
			r.center = Vector3(3, 0, 2)
			r.radius = 2.0
			r.base = 3.0
			r.pitch = 0.0
			r.curve = curve
			r.build()
			var mid: Vector3 = r.frame().mid
			var height := r.height_at(mid.x, mid.z)
			check(signf(height - r.base) == signf(curve), "flat stone deck bows in the requested direction")
			check(is_equal_approx(r.deck_under(Vector3(mid.x, height + 0.5, mid.z)), height), "standing height follows deck curvature")
			var hit := r.ray_hit(mid + Vector3.UP * 3, Vector3.DOWN)
			check(absf(hit - (mid.y + 3 - height)) < 0.01, "roof picking follows the curved deck")
			for tile in r.tiles:
				var p: Vector3 = tile.xform.origin
				check(absf(p.y + RoofLayout.DECK_DROP + RoofLayout.SLAB.y * 0.5 - r.height_at(p.x, p.z)) < 0.007, "deck stone follows surface")
			for bed in r.mortar:
				var p: Vector3 = bed.xform.origin
				check(absf(p.y + RoofLayout.DECK_DROP + RoofLayout.SLAB.y * 0.65 - r.height_at(p.x, p.z)) < 0.0001, "mortar follows surface")
			var f := r.frame()
			var reach := r.half_span() - WallLayout.THICKNESS
			var length := reach if kind == RoofLayout.Kind.CONE else r.ridge_length() * 0.5 - WallLayout.THICKNESS * 0.5
			for i in 13:
				for j in 13:
					var x := length * (float(i) / 6.0 - 1.0)
					var z := reach * (float(j) / 6.0 - 1.0)
					if kind == RoofLayout.Kind.CONE and Vector2(x, z).length() > reach:
						continue
					var at: Vector3 = f.mid + f.along * x + f.across * z + Vector3.UP * 10.0
					var closed := r.mortar.any(func(bed: Dictionary) -> bool:
						var inverse: Transform3D = bed.xform.affine_inverse()
						return AABB(Vector3.ONE * -0.5, Vector3.ONE).intersects_ray(inverse * at, inverse.basis * Vector3.DOWN) != null)
					check(closed, "mortar closes every joint of a bowed deck at %s, curve %s" % [at, curve])
			r.pitch = 2.0
			var previous := r.rise(0.0)
			for i in range(1, 101):
				var next := r.rise(float(i) / 100)
				check(next >= previous, "limit keeps the pitched profile above its supports without reversing")
				previous = next
	finish()
