class_name Lamps
extends RefCounted

## Lantern light, baked: how much reaches each of Bounce's probes, on its grid so shaders read it where they read
## the bounce (bounce.gdshaderinc), shared as the global lamp_volume. Every lantern lights and none costs the frame:
## the volume is solved again on a worker only when a lantern is hung or taken or the ground moves. Godot's own
## lights cost the Quest 2 milliseconds a frame each. A house's walls and roof hold its lanterns' light in and keep
## the light of lanterns outside out; its windows and, faintly, its doors shine with the light inside them.

## How far a lantern's light carries: from high on a tall house's wall down to its floor.
const REACH := 9.0
## Lantern light as the shaders add it, colour times strength.
const LIGHT := Color(0.4, 0.28, 0.16)
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

var texture := ImageTexture3D.new()
var _layers: Array[Image] = []
var _flames := PackedVector3Array()
var _rooms: Array[Room] = []
var _shells := []
var _ground := -1
var _dirty := false
var _task := -1
var _out := {}


func _init() -> void:
	for k in Bounce.LAYERS:
		_layers.append(Image.create(Bounce.CELLS, Bounce.CELLS, false, Image.FORMAT_R8))
	texture.create(Image.FORMAT_R8, Bounce.CELLS, Bounce.CELLS, Bounce.LAYERS, false, _layers)


func install() -> void:
	RenderingServer.global_shader_parameter_set(&"lamp_volume", texture)
	RenderingServer.global_shader_parameter_set(&"lamp_light", Vector3(LIGHT.r, LIGHT.g, LIGHT.b) * ENCODE)


## The air inside a house or tower: inside its walls' inner faces, from its floor up to its roof, and through
## its openings. Pure data, made on the main thread and read by the solve.
class Room:
	var inside: Array[PackedVector2Array] = []
	var rect := Rect2()
	var floor := 0.0
	## Under a flat deck or a wall's top; a loop without a cover is open to the sky.
	var top := INF
	var roof: RoofLayout
	## Per opening: OUT before the middle of its outer face, its outward normal and how much of the light in it gets out.
	var openings: Array[Dictionary] = []

	static func of(layout: WallLayout, massing: Massing) -> Room:
		var r := Room.new()
		var line := PackedVector2Array()
		for p in layout.points:
			line.append(Vector2(p.x, p.z))
		r.inside = Geometry2D.offset_polygon(line, -WallLayout.THICKNESS * 0.5)
		r.rect = Rect2(line[0], Vector2.ZERO)
		for p in line:
			r.rect = r.rect.expand(p)
		r.floor = massing.feet[0]
		r.roof = massing.roof
		if layout.cover != WallLayout.Cover.OPEN:
			r.top = massing.feet[0] + massing.rise
		for o in layout.apertures:
			r._open(layout, o.s, (o.sill + o.head) * 0.5, DOOR if o.door else 1.0)
		return r

	func _open(layout: WallLayout, s: float, y: float, gives: float) -> void:
		var f := layout.frame_at(s)
		var out: Vector3 = f.tangent.cross(Vector3.UP)
		var at: Vector3 = f.point + Vector3.UP * y
		if Massing.encloses(Vector2(at.x + out.x, at.z + out.z), inside):
			out = -out
		openings.append({"at": at + out * (WallLayout.THICKNESS * 0.5 + OUT), "out": out, "gives": gives})

	func holds(p: Vector3) -> bool:
		if p.y < floor or not rect.has_point(Vector2(p.x, p.z)):
			return false
		var ceiling := roof.height_at(p.x, p.z) if roof != null else top
		return p.y < ceiling and Massing.encloses(Vector2(p.x, p.z), inside)


## The lanterns hung on `walls` and the rooms of the houses and towers among them, wherever they stand now.
func light(walls: Array) -> void:
	var flames := PackedVector3Array()
	var shells := []
	for w: Wall in walls:
		for f in w.layout.flames:
			flames.append(f.origin)
		if w.layout.closed and not w.layout.fence and w.massing != null:
			shells.append([w, w.massing, w.layout.laid])
	if shells != _shells:
		_shells = shells
		_rooms.clear()
		for s in shells:
			_rooms.append(Room.of(s[0].layout, s[1]))
		_dirty = true
	if flames != _flames:
		_flames = flames
		_dirty = true


## Takes a finished solve and starts one for whatever changed since; called once a frame.
func update() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		_collect()
	if _ground != Terrain.revision:
		_ground = Terrain.revision
		_dirty = not _flames.is_empty() or _dirty
	if not _dirty:
		return
	_dirty = false
	var flames := _flames
	var rooms := _rooms.duplicate()
	var heights := Terrain.read(Terrain.ALL)
	var out := {}
	_out = out
	_task = WorkerThreadPool.add_task(func() -> void: out.layers = shine(flames, Bounce.grounds(heights), rooms), false)


## Solves everything changed so far before returning.
func finish() -> void:
	update()
	while _task >= 0:
		_collect()
		update()


func stop() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## The light probe `layer` over column (x, z) holds, as shaders add it.
func at(x: float, z: float, layer: int) -> float:
	var c := Bounce.column(x, z)
	return _layers[layer].get_pixel(c.x, c.y).r * ENCODE


func _collect() -> void:
	stop()
	for k in Bounce.LAYERS:
		_layers[k].set_data(Bounce.CELLS, Bounce.CELLS, false, Image.FORMAT_R8, _out.layers[k])
	texture.update(_layers)


## Per layer, the light each probe takes from `flames` with the ground at each column's middle `ground`: falling
## off with distance and gone at REACH, as Godot fades an omni light. A flame in one of `rooms` lights only that
## room, and its openings shine outward with the light at them; a flame outside lights no room.
static func shine(flames: PackedVector3Array, ground: PackedFloat32Array, rooms: Array[Room] = []) -> Array[PackedByteArray]:
	var n := Bounce.CELLS
	var sum := PackedFloat32Array()
	sum.resize(n * n * Bounce.LAYERS)
	var within := _rooms_at(rooms, ground)
	var glow := PackedFloat32Array()
	glow.resize(rooms.size())
	var r := ceili(REACH / Terrain.STEP)
	for f in flames:
		var home := 0
		var near := false
		for k in rooms.size():
			if rooms[k].holds(f):
				home = k + 1
			near = near or rooms[k].rect.grow(REACH).has_point(Vector2(f.x, f.z))
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
						sum[p] += _falloff(d)
	for k in rooms.size():
		for o in rooms[k].openings:
			var inner: Vector3 = o.at - o.out * (WallLayout.THICKNESS + OUT)
			var lit := 0.0
			for f in flames:
				if rooms[k].holds(f):
					lit += _falloff(f.distance_to(inner))
			if lit > 0.0:
				_spill(sum, o.at, o.out, lit * o.gives, within, ground)
	var layers: Array[PackedByteArray] = []
	for k in Bounce.LAYERS:
		var px := PackedByteArray()
		px.resize(n * n)
		for p in n * n:
			px[p] = clampi(roundi(sum[k * n * n + p] / ENCODE * 255.0), 0, 255)
		layers.append(px)
	return layers


static func _falloff(d: float) -> float:
	if d >= REACH:
		return 0.0
	var fade := 1.0 - pow(d / REACH, 4.0)
	return fade * fade / maxf(d, 0.5)


## Adds to the probes outside every room the light `lit` an opening at `at` facing `out` throws, brightest
## straight out and gone at SPILL. None goes up: above an opening it would meet only the eaves' underside, and the
## probes there are what the roof over them reads.
static func _spill(sum: PackedFloat32Array, at: Vector3, out: Vector3, lit: float, within: PackedInt32Array, ground: PackedFloat32Array) -> void:
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
				if within[p] == 0 and facing > 0.0 and to.y <= 0.0 and d < SPILL:
					sum[p] += lit * pow(facing / d, 2.0) * pow(1.0 - pow(d / SPILL, 2.0), 2.0)


## Per probe, 1 + the index of the room it stands in, or 0 outside every room.
static func _rooms_at(rooms: Array[Room], ground: PackedFloat32Array) -> PackedInt32Array:
	var n := Bounce.CELLS
	var within := PackedInt32Array()
	within.resize(n * n * Bounce.LAYERS)
	for r in rooms.size():
		var a := Bounce.column(rooms[r].rect.position.x, rooms[r].rect.position.y)
		var b := Bounce.column(rooms[r].rect.end.x, rooms[r].rect.end.y)
		for j in range(maxi(a.y, 0), mini(b.y + 1, n)):
			for i in range(maxi(a.x, 0), mini(b.x + 1, n)):
				var x := -Terrain.SIZE * 0.5 + (i + 0.5) * Terrain.STEP
				var z := -Terrain.SIZE * 0.5 + (j + 0.5) * Terrain.STEP
				for k in Bounce.LAYERS:
					if rooms[r].holds(Vector3(x, ground[j * n + i] + k + 0.5, z)):
						within[(k * n + j) * n + i] = r + 1
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
