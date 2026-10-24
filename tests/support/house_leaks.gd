extends RefCounted

## QA reads the same full-detail meshes and instance buffers as the renderer, never shadow proxies.
## A part keeps its owner, so an unrelated house cannot plug a hole in the room being tested.
var parts: Array[Dictionary] = []


func add_faces(faces: PackedVector3Array, label: String, owner: int) -> void:
	if faces.is_empty():
		return
	var tree := TriangleMesh.new()
	assert(tree.create_from_faces(faces))
	parts.append({"tree": tree, "label": label, "owner": owner})


func add_wall(w: Wall) -> void:
	var kinds := Wall.kinds()
	for part in [Wall.Part.STONE, Wall.Part.MORTAR, Wall.Part.TILE, Wall.Part.TIMBER, Wall.Part.FLOOR]:
		var kind := kinds[part]
		var source := kind.mesh.get_faces()
		var buffer: PackedFloat32Array = w._parts[part]
		var faces := PackedVector3Array()
		for i in range(0, buffer.size(), kind.stride()):
			var x := Transform3D(Basis(Vector3(buffer[i], buffer[i + 4], buffer[i + 8]), Vector3(buffer[i + 1], buffer[i + 5], buffer[i + 9]), Vector3(buffer[i + 2], buffer[i + 6], buffer[i + 10])), Vector3(buffer[i + 3], buffer[i + 7], buffer[i + 11]))
			for v in source:
				# stone.gdshaderinc mitres panels in the vertex shader, before MODEL_MATRIX.
				if kind.custom:
					var turn := buffer[i + (18 if v.x < 0.0 else 19)]
					if turn != 0.0:
						v.x += v.z * x.basis.z.length() * tan(turn) / Vector2(x.basis.x.x, x.basis.x.z).length()
				faces.append(w.transform * (x * v))
		add_faces(faces, "%d/%s" % [w.id, Wall.Part.keys()[part]], w.id)
	for pair in [[w._gables, "gable"], [w._coat, "thatch"], [w._torching, "torching"]]:
		var node: MeshInstance3D = pair[0]
		if node != null and node.mesh != null:
			var faces := node.mesh.get_faces()
			for i in faces.size():
				faces[i] = w.transform * node.transform * faces[i]
			add_faces(faces, "%d/%s" % [w.id, pair[1]], w.id)


func first(origin: Vector3, direction: Vector3) -> Dictionary:
	var best := {}
	for part in parts:
		var hit: Dictionary = part.tree.intersect_ray(origin, direction)
		if hit.is_empty():
			continue
		var distance := origin.distance_to(hit.position)
		if distance < best.get("distance", INF):
			best = {"position": hit.position, "distance": distance, "part": part.label, "owner": part.owner}
	return best


static func directions(count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in count:
		var y := 1.0 - 2.0 * (i + 0.5) / count
		var angle := i * PI * (3.0 - sqrt(5.0))
		var radius := sqrt(1.0 - y * y)
		out.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
	return out


## Apertures are tested at the wall centre plane, with exact layout bounds (no enlarged picking margin).
## Only a crossing before the first hit can excuse a ray. Hidden merge seams are not apertures.
static func aperture(w: Wall, origin: Vector3, direction: Vector3, limit: float) -> bool:
	var l := w.layout
	for i in range(1, l.samples.size()):
		var a: Vector3 = l.samples[i - 1]
		var b: Vector3 = l.samples[i]
		var edge := b - a
		var n := Vector3(edge.z, 0.0, -edge.x).normalized()
		var denom := n.dot(direction)
		if absf(denom) < 1e-8:
			continue
		var t := n.dot(a - origin) / denom
		if t <= 0.0 or t >= limit:
			continue
		var p := origin + direction * t
		var u := Vector2(p.x - a.x, p.z - a.z).dot(Vector2(edge.x, edge.z)) / Vector2(edge.x, edge.z).length_squared()
		if u < 0.0 or u > 1.0 or l.hides(p):
			continue
		var s := lerpf(l.lengths[i - 1], l.lengths[i], u)
		var y := p.y - lerpf(a.y, b.y, u)
		for o in l.apertures:
			var half: float = l.opening(y, false, o.size) if o.style == WallLayout.Family.ARCHWAY else o.half
			if absf(l.offset(s, o.s)) < half and y > o.sill and y < o.head:
				return true
	return false


func probe(origin: Vector3, direction: Vector3, room: Array[Wall]) -> Dictionary:
	var hit := first(origin, direction)
	if not hit.is_empty() and room.any(func(w: Wall) -> bool: return w.id == hit.owner):
		return {"status": "shell", "part": hit.part}
	var limit: float = hit.get("distance", INF)
	for w in room:
		if aperture(w, origin, direction, limit):
			return {"status": "opening"}
	return {"status": "leak", "first_hit": hit.get("part", "sky"), "hit_position": hit.get("position", Vector3.INF)}


## Locate the first exit from the room volume, for a diagnostic position even when the ray hits sky.
## This does not decide whether it leaks: only rendered triangle hits and apertures do that.
static func exit_point(origin: Vector3, direction: Vector3, room: Array[Wall]) -> Vector3:
	var low := 0.0
	for step in range(1, 2001):
		var high := step * 0.05
		var p := origin + direction * high
		if room.any(func(w: Wall) -> bool: return w.massing.holds(p)):
			low = high
			continue
		for iteration in 16:
			var mid := (low + high) * 0.5
			if room.any(func(w: Wall) -> bool: return w.massing.holds(origin + direction * mid)):
				low = mid
			else:
				high = mid
		return origin + direction * high
	return origin + direction * 100.0


func neighbours(p: Vector3) -> Array:
	var distances := []
	for part in parts:
		if part.owner < 0:
			continue
		var closest := INF
		# Diagnostics only, run once per representative rather than for every ray.
		var faces: PackedVector3Array = part.tree.get_faces()
		for v in faces:
			closest = minf(closest, p.distance_squared_to(v))
		distances.append([closest, part.label])
	distances.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return distances.slice(0, 2).map(func(d: Array) -> String: return d[1])
