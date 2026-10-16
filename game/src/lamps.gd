class_name Lamps
extends RefCounted

## Lantern light, baked: how much reaches each of Bounce's probes, on its grid so shaders read it where they read
## the bounce (bounce.gdshaderinc), shared as the global lamp_volume. Every lantern lights and none costs the frame:
## the volume is solved again on a worker only when a lantern is hung or taken or the ground moves. Godot's own
## lights cost the Quest 2 milliseconds a frame each. Walls do not stop the light.

## How far a lantern's light carries: from high on a tall house's wall down to its floor.
const REACH := 9.0
## Lantern light as the shaders add it, colour times strength.
const LIGHT := Color(0.4, 0.28, 0.16)
## Light is stored this many times under its value, so a byte holds it from beside a flame out to its reach.
const ENCODE := 4.0

var texture := ImageTexture3D.new()
var _layers: Array[Image] = []
var _flames := PackedVector3Array()
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


## The lanterns' flames, wherever they hang now.
func light(flames: PackedVector3Array) -> void:
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
	var ground := Bounce.grounds(Terrain.read(Terrain.ALL))
	var out := {}
	_out = out
	_task = WorkerThreadPool.add_task(func() -> void: out.layers = shine(flames, ground), false)


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
## off with distance and gone at REACH, as Godot fades an omni light.
static func shine(flames: PackedVector3Array, ground: PackedFloat32Array) -> Array[PackedByteArray]:
	var n := Bounce.CELLS
	var sum := PackedFloat32Array()
	sum.resize(n * n * Bounce.LAYERS)
	var r := ceili(REACH / Terrain.STEP)
	for f in flames:
		var c := Bounce.column(f.x, f.z)
		for j in range(maxi(c.y - r, 0), mini(c.y + r + 1, n)):
			for i in range(maxi(c.x - r, 0), mini(c.x + r + 1, n)):
				var x := -Terrain.SIZE * 0.5 + (i + 0.5) * Terrain.STEP
				var z := -Terrain.SIZE * 0.5 + (j + 0.5) * Terrain.STEP
				var flat := Vector2(x - f.x, z - f.z).length_squared()
				for k in Bounce.LAYERS:
					var d := sqrt(flat + pow(ground[j * n + i] + k + 0.5 - f.y, 2.0))
					if d < REACH:
						var fade := 1.0 - pow(d / REACH, 4.0)
						sum[(k * n + j) * n + i] += fade * fade / maxf(d, 0.5)
	var layers: Array[PackedByteArray] = []
	for k in Bounce.LAYERS:
		var px := PackedByteArray()
		px.resize(n * n)
		for p in n * n:
			px[p] = clampi(roundi(sum[k * n * n + p] / ENCODE * 255.0), 0, 255)
		layers.append(px)
	return layers
