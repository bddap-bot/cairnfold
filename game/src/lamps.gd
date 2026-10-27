class_name Lamps
extends Bake

## Lantern light, baked: how much reaches each of Bounce's probes in each lantern's colour, on its grid so shaders read
## it where they read the bounce (bounce.gdshaderinc), shared as the global lamp_volume. Every lantern lights and none costs the frame:
## the volume is solved again on a worker only when a lantern is hung or taken or the ground moves. Godot's own
## lights cost the Quest 2 milliseconds a frame each. A house's walls and roof hold its lanterns' light in and keep
## the light of lanterns outside out; its windows and, faintly, its doors shine with the light inside them.

## How far a lantern's light carries: from high on a tall house's wall down to its floor.
const REACH := 9.0
## Lantern light as the shaders add it, at a lit lantern's strength.
const LIGHT := 0.4
## A lantern's strength lit, bright and dim, in the order of each colour's swatches (Palette.Element.LANTERN).
const STRENGTHS: Array[float] = [1.0, 2.2, 0.45]
## A lit opening must read against the flame of an outdoor lantern, not only against unlit stone.
const WINDOW_GLOW := 8.0
## How brightly a room's glass shines in its glow colour once night falls, lantern or none.
const NIGHT_GLOW := 0.4
## Light is stored this many times under its value, so a byte holds it from beside a flame out to its reach.
const ENCODE := 4.0
## How far a lit window's light falls outside it.
const SPILL := 3.0
## How far out from its face a window's light spreads from: the wall around it reads the light a metre out
## (bounce.gdshaderinc), and from here that plane lies nearly edge on, so the window lights the ground more than
## its wall.
const OUT := 0.5
## How much of the light in a doorway gets out: a doorway spills a little, so a lit house reads by its windows.
const DOOR := 0.2

signal rooms_changed(rooms: Array[Room])

var texture := ImageTexture3D.new()
var _layers: Array[Image] = []
var _flames := PackedVector3Array()
var _lights := PackedColorArray()
var _rooms: Array[Room] = []
var _shells := []
## The ground the probes follow, and its heights_revision the last solve stood on.
var terrain: Terrain
var _ground := -1
var _dirty := false


func _init() -> void:
	for k in Bounce.LAYERS:
		_layers.append(Image.create(Bounce.CELLS, Bounce.CELLS, false, Image.FORMAT_RGBA8))
	texture.create(Image.FORMAT_RGBA8, Bounce.CELLS, Bounce.CELLS, Bounce.LAYERS, false, _layers)


func install() -> void:
	RenderingServer.global_shader_parameter_set(&"lamp_volume", texture)
	RenderingServer.global_shader_parameter_set(&"lamp_light", Vector3.ONE * LIGHT * ENCODE)


## The light a lantern of `look` (its Palette.Element.LANTERN swatch) casts: its glow colour times its strength.
static func light_of(look: int) -> Color:
	return Palette.GLOWS[look / STRENGTHS.size()] * STRENGTHS[look % STRENGTHS.size()]


## The air inside a house or tower: inside its walls' inner faces, from its floor up to its roof, and through
## its openings. Pure data, made on the main thread and read by the solve.
class Room:
	var inside: Array[PackedVector2Array] = []
	var probe_inside: Array[PackedVector2Array] = []
	var massing: Massing
	var joined: Array[Massing] = []
	var rect := Rect2()
	var floor := 0.0
	## Under a flat deck or a wall's top; a loop without a cover is open to the sky.
	var top := INF
	var roof: RoofLayout
	## Per opening: OUT before the middle of its outer face, its outward normal and how much of the light in it gets out.
	var openings: Array[Dictionary] = []

	static func of(layout: WallLayout, massing: Massing) -> Room:
		var r := Room.new()
		r.massing = massing
		r.joined = layout.joined.duplicate()
		var line := PackedVector2Array()
		for p in layout.points:
			line.append(Vector2(p.x, p.z))
		r.inside = Geometry2D.offset_polygon(line, -WallLayout.THICKNESS * 0.5)
		r.probe_inside = Geometry2D.offset_polygon(line, Terrain.STEP * 0.5)
		r.rect = Rect2(line[0], Vector2.ZERO)
		for p in line:
			r.rect = r.rect.expand(p)
		r.floor = massing.feet[0]
		r.roof = massing.roof
		if layout.cover != WallLayout.Cover.OPEN:
			r.top = massing.feet[0] + massing.rise
		for o in layout.apertures:
			r._open(layout, o.s, (o.sill + o.head) * 0.5, DOOR if o.door else WINDOW_GLOW, 2.0 * o.half * (o.head - o.sill))
		return r

	func _open(layout: WallLayout, s: float, y: float, gives: float, area: float) -> void:
		var f := layout.frame_at(s)
		var out: Vector3 = f.tangent.cross(Vector3.UP)
		var at: Vector3 = f.point + Vector3.UP * y
		if Massing.encloses(Vector2(at.x + out.x, at.z + out.z), inside):
			out = -out
		openings.append({"at": at + out * (WallLayout.THICKNESS * 0.5 + OUT), "out": out, "gives": gives, "area": area})

	## Boundary probes supply the inside face through linear filtering; include their half-cell support.
	func holds(p: Vector3, probe := false) -> bool:
		var margin := Terrain.STEP * 0.5 if probe else 0.0
		if p.y < floor - margin or not rect.grow(margin).has_point(Vector2(p.x, p.z)):
			return false
		var ceiling := roof.height_at(p.x, p.z) if roof != null else top
		if p.y >= ceiling + margin:
			return false
		if Massing.encloses(Vector2(p.x, p.z), probe_inside if probe else inside):
			return true
		# The inner half of a removed wall belongs to the joined room too.
		return massing.holds(p) and joined.any(func(s: Massing) -> bool: return s.holds(p))


	func connects(other: Room) -> bool:
		if not joined.any(func(s: Massing) -> bool: return s.same(other.massing)):
			return false
		for a in massing.inner:
			for b in other.massing.inner:
				for overlap in Geometry2D.intersect_polygons(a, b):
					var middle := Vector2.ZERO
					for p in overlap:
						middle += p
					middle /= overlap.size()
					var at := Vector3(middle.x, maxf(floor, other.floor) + 0.01, middle.y)
					if massing.holds(at) and other.massing.holds(at):
						return true
		return false


## The lanterns hung on `walls`, and `extra` burning in `extra_lights`, and the rooms of the houses and towers among
## them, wherever they stand now.
func light(walls: Array, extra := PackedVector3Array(), extra_lights := PackedColorArray()) -> void:
	var flames := extra.duplicate()
	var lights := extra_lights.duplicate()
	var shells := []
	for w: Wall in walls:
		var g := light_of(w.paint[Palette.Element.LANTERN])
		for f in w.layout.flames:
			flames.append(w.transform * f.origin)
			lights.append(g)
		if w.layout.closed and not w.layout.fence and w.massing != null:
			shells.append([w, w.massing, w.layout.laid])
	if shells != _shells:
		_shells = shells
		_rooms.clear()
		for s in shells:
			_rooms.append(Room.of(s[0].layout, s[1]))
		rooms_changed.emit(_rooms)
		_dirty = true
	if flames != _flames or lights != _lights:
		_flames = flames
		_lights = lights
		_dirty = true


func _next() -> Callable:
	if _ground != terrain.heights_revision:
		_ground = terrain.heights_revision
		_dirty = _dirty or not _flames.is_empty()
	if not _dirty:
		return Callable()
	_dirty = false
	var flames := _flames
	var lights := _lights
	var rooms := _rooms.duplicate()
	var heights := terrain.read(Terrain.ALL)
	return func() -> Dictionary: return {"layers": shine(flames, Bounce.grounds(heights), rooms, lights)}


## The light probe `layer` over column (x, z) holds in its strongest colour, as shaders add it.
func at(x: float, z: float, layer: int) -> float:
	var c := Bounce.column(x, z)
	var p := _layers[layer].get_pixel(c.x, c.y)
	return maxf(p.r, maxf(p.g, p.b)) * ENCODE


func _take(out: Dictionary) -> void:
	for k in Bounce.LAYERS:
		_layers[k].set_data(Bounce.CELLS, Bounce.CELLS, false, Image.FORMAT_RGBA8, out.layers[k])
	texture.update(_layers)


## Per layer, the light each probe takes from `flames`, each in its `lights` (lit in the first colour where none is
## given), with the ground at each column's middle `ground`: falling off with distance and gone at REACH, as Godot
## fades an omni light. A flame in one of `rooms` lights only that room, and its openings shine outward with the light
## at them; exterior flames spill inward through openings.
static func shine(flames: PackedVector3Array, ground: PackedFloat32Array, rooms: Array[Room] = [], lights := PackedColorArray()) -> Array[PackedByteArray]:
	var n := Bounce.CELLS
	var sum := PackedFloat32Array()
	sum.resize(n * n * Bounce.LAYERS * 3)
	if lights.is_empty():
		lights.resize(flames.size())
		lights.fill(light_of(0))
	var groups := _groups(rooms)
	var within := _rooms_at(rooms, ground, groups)
	var homes := PackedInt32Array()
	var r := ceili(REACH / Terrain.STEP)
	for fi in flames.size():
		var f := flames[fi]
		var g := lights[fi]
		var home := 0
		var near := false
		for k in rooms.size():
			if rooms[k].holds(f):
				home = groups[k]
			near = near or rooms[k].rect.grow(REACH).has_point(Vector2(f.x, f.z))
		homes.append(home)
		var c := Bounce.column(f.x, f.z)
		for j in range(maxi(c.y - r, 0), mini(c.y + r + 1, n)):
			for i in range(maxi(c.x - r, 0), mini(c.x + r + 1, n)):
				var x := -Terrain.SIZE * 0.5 + (i + 0.5) * Terrain.STEP
				var z := -Terrain.SIZE * 0.5 + (j + 0.5) * Terrain.STEP
				var flat := Vector2(x - f.x, z - f.z).length_squared()
				for k in Bounce.LAYERS:
					var p := (k * n + j) * n + i
					if within[p] != home:
						continue
					var y := ground[j * n + i] + k + 0.5
					var d := sqrt(flat + pow(y - f.y, 2.0))
					if d < REACH and not (home == 0 and near and _crosses(f, Vector3(x, y, z), within, ground)):
						var lit := _falloff(d)
						sum[p * 3] += lit * g.r
						sum[p * 3 + 1] += lit * g.g
						sum[p * 3 + 2] += lit * g.b
	for k in rooms.size():
		for o in rooms[k].openings:
			var inner: Vector3 = o.at - o.out * (WallLayout.THICKNESS + OUT)
			var lit := Color(0, 0, 0)
			var entering := Color(0, 0, 0)
			for f in flames.size():
				if homes[f] == groups[k]:
					lit += lights[f] * _falloff(flames[f].distance_to(inner))
				elif homes[f] == 0:
					var entrance: Vector3 = o.at - o.out * OUT
					var to: Vector3 = flames[f] - entrance
					if to.dot(o.out) > 0.0 and not _crosses(flames[f], entrance, within, ground):
						entering += lights[f] * _falloff(to.length()) * to.normalized().dot(o.out)
			if entering.r + entering.g + entering.b > 0.0:
				_spill(sum, inner, -o.out, entering, within, ground, groups[k])
			if lit.r + lit.g + lit.b > 0.0:
				_spill(sum, o.at, o.out, lit * o.gives, within, ground)
	var layers: Array[PackedByteArray] = []
	for k in Bounce.LAYERS:
		var px := PackedByteArray()
		px.resize(n * n * 4)
		for p in n * n:
			for c in 3:
				px[p * 4 + c] = clampi(roundi(sum[(k * n * n + p) * 3 + c] / ENCODE * 255.0), 0, 255)
			px[p * 4 + 3] = 255
		layers.append(px)
	return layers


## Transitive rooms come from the same joined masses that remove their internal walls.
static func _groups(rooms: Array[Room]) -> PackedInt32Array:
	var groups := PackedInt32Array()
	for i in rooms.size():
		groups.append(i + 1)
	for i in rooms.size():
		for j in i:
			if groups[i] == groups[j] or not rooms[i].connects(rooms[j]):
				continue
			var old := groups[i]
			var to := groups[j]
			for k in groups.size():
				if groups[k] == old:
					groups[k] = to
	return groups


static func _falloff(d: float) -> float:
	if d >= REACH:
		return 0.0
	var fade := 1.0 - pow(d / REACH, 4.0)
	return fade * fade / maxf(d, 0.5)


## Adds to the probes outside every room the light `lit` an opening at `at` facing `out` throws, brightest
## straight out and gone at SPILL. Outward spill stays below the eaves; inward spill stays in its room group.
static func _spill(sum: PackedFloat32Array, at: Vector3, out: Vector3, lit: Color, within: PackedInt32Array, ground: PackedFloat32Array, home := 0) -> void:
	var n := Bounce.CELLS
	var r := ceili(SPILL / Terrain.STEP)
	var c := Bounce.column(at.x, at.z)
	for j in range(maxi(c.y - r, 0), mini(c.y + r + 1, n)):
		for i in range(maxi(c.x - r, 0), mini(c.x + r + 1, n)):
			var x := -Terrain.SIZE * 0.5 + (i + 0.5) * Terrain.STEP
			var z := -Terrain.SIZE * 0.5 + (j + 0.5) * Terrain.STEP
			for k in Bounce.LAYERS:
				var p := (k * n + j) * n + i
				var to := Vector3(x, ground[j * n + i] + k + 0.5, z) - at
				var d := to.length()
				var facing := to.dot(out)
				if within[p] == home and facing > 0.0 and (home != 0 or to.y <= 0.0) and d < SPILL:
					var share := pow(facing / d, 2.0) * pow(1.0 - pow(d / SPILL, 2.0), 2.0)
					sum[p * 3] += lit.r * share
					sum[p * 3 + 1] += lit.g * share
					sum[p * 3 + 2] += lit.b * share


## Per probe, its connected room group, or 0 outside every room.
static func _rooms_at(rooms: Array[Room], ground: PackedFloat32Array, groups: PackedInt32Array) -> PackedInt32Array:
	var n := Bounce.CELLS
	var within := PackedInt32Array()
	within.resize(n * n * Bounce.LAYERS)
	for r in rooms.size():
		var bounds := rooms[r].rect.grow(Terrain.STEP * 0.5)
		var a := Bounce.column(bounds.position.x, bounds.position.y)
		var b := Bounce.column(bounds.end.x, bounds.end.y)
		for j in range(maxi(a.y, 0), mini(b.y + 1, n)):
			for i in range(maxi(a.x, 0), mini(b.x + 1, n)):
				var x := -Terrain.SIZE * 0.5 + (i + 0.5) * Terrain.STEP
				var z := -Terrain.SIZE * 0.5 + (j + 0.5) * Terrain.STEP
				for k in Bounce.LAYERS:
					if rooms[r].holds(Vector3(x, ground[j * n + i] + k + 0.5, z), true):
						within[(k * n + j) * n + i] = groups[r]
	return within


## Whether the way from `a` to `b`, both outside every room, passes through one.
static func _crosses(a: Vector3, b: Vector3, within: PackedInt32Array, ground: PackedFloat32Array) -> bool:
	var n := Bounce.CELLS
	var steps := ceili(a.distance_to(b) / (Terrain.STEP * 0.5))
	for s in range(1, steps):
		var q := a.lerp(b, float(s) / steps)
		var c := Bounce.column(q.x, q.z)
		if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n:
			continue
		var k := floori(q.y - ground[c.y * n + c.x])
		if k >= 0 and k < Bounce.LAYERS and within[(k * n + c.y) * n + c.x] > 0:
			return true
	return false
