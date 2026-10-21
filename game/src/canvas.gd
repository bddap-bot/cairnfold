class_name Canvas
extends Node

## One easel's canvas: its paint simulated on the GPU by paint.glsl, drawn by canvas.gdshader. Strokes come in two
## ways: a painter's own brush lays its dabs as it touches (`lay`), and a stroke from the garden is played back sample
## by sample at the pace it was painted (`play`), or a whole kept painting replayed as fast as the frame allows
## (`rebuild`). Wet paint flows and dries in ticks, only on tiles a wet brush touched in the last DRY_TICKS, and every
## dab lands at a known tick, so a replay lays the same painting the painter saw.
## Each time the canvas comes to rest at a stroke's end it keeps a checkpoint: its paint on the GPU, its tick and wet
## tiles, under a key naming every stroke laid so far. `rebuild` starts from the checkpoint of the longest prefix of its
## strokes and replays only the rest, so undoing the last stroke costs a texture copy however many came before.
## Without a RenderingDevice (headless runs) it keeps its ticks and does nothing on the GPU.

## GPU work a frame may take, in texel-steps (one texel through one flow step, or under one dab). A painter's own
## dabs land whatever they cost; a catching-up replay's are charged.
const STEPS := 3.0e6
## Ticks owed beyond this are let go: past its budget the paint dries slower instead of stalling the frame.
const MAX_OWED := 3.0
const TILES := Vector2i(Brushwork.SIZE.x / Brushwork.TILE, Brushwork.SIZE.y / Brushwork.TILE)
const BUNDLES := 3
const DAB_ROOM := 8192
const PAPER := 0
const DAB := 1
const FLOW := 2
## Checkpoints a canvas keeps, each two textures of 14 MB: undo steps back this far without a replay.
const CHECKPOINTS := 6

static var _shader: RID
static var _sampler: RID
static var _pipeline: RID

## Ticks laid so far, and the tick the last stroke on this canvas ended at.
var ticks := 0
var last_end := 0
var material: ShaderMaterial
var _rd: RenderingDevice
var _wet: Array[RID] = []
var _dry: RID
var _paper: RID
## Per bundle: [dab buffer, tile buffer, set A→B, set B→A].
var _bundles: Array = []
var _tiles := PackedInt32Array()
var _wet_tiles := {}
## Strokes waiting to play: ["wait", ticks] and ["dabs", params, dabs], played in order.
var _queue: Array = []
var _queued_ticks := 0
var _catching_up := false
## When the replay under way began, and the frames it has taken, for the log line its end writes.
var _replay_from := 0
var _replay_frames := 0
var _replay_strokes := 0
var _owed := 0.0
## The key of the strokes ended so far, in the order they ended (`_chain`), how many, and the checkpoints kept:
## [key, count, ticks, tiles, wet tiles, slot], newest last.
var _key := 0
var _count := 0
var _checkpoints: Array = []
## Strokes queued and not yet ended, and whether the painter's own brush has laid since its last `end`: a checkpoint is
## kept only between strokes.
var _pending := 0
var _open := false
## Render thread: each slot's [wet, dry] textures, made the first time it is saved to.
var _slots: Array = []
## What this frame lays, in order, and the dabs it uses.
var _ops: Array = []
var _batches: Array = []
var _dabs := PackedFloat32Array()
var _batch_start := 0
var _shown: Array[Texture2DRD] = []
var _frozen: Array[RID] = []
## Whether nothing has been laid since the sheet was last cleared: a blank sheet has nothing to keep on show.
var _blank := true


func _init() -> void:
	name = "Canvas"
	process_priority = 100
	_tiles.resize(TILES.x * TILES.y * 2)
	material = ShaderMaterial.new()
	material.shader = preload("res://src/canvas.gdshader")
	material.set_shader_parameter("metres", Brushwork.METRES)
	_rd = RenderingServer.get_rendering_device()
	for i in 3:
		_shown.append(Texture2DRD.new())
	if _rd != null:
		RenderingServer.call_on_render_thread(_create)
		for i in 3:
			_shown[i].texture_rd_rid = [_wet[0], _dry, _paper][i]
	for i in 3:
		material.set_shader_parameter(["wet", "dry", "paper"][i], _shown[i])


## Compiles the paint pipeline ahead of the first canvas, which would otherwise wait on it.
static func warm() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd != null:
		RenderingServer.call_on_render_thread(_compile.bind(rd))


static func _compile(rd: RenderingDevice) -> void:
	if not _shader.is_valid():
		var file: RDShaderFile = preload("res://src/paint.glsl")
		_shader = rd.shader_create_from_spirv(file.get_spirv())
		_sampler = rd.sampler_create(RDSamplerState.new())
		_pipeline = rd.compute_pipeline_create(_shader)


func _create() -> void:
	_compile(_rd)
	var fmt := RDTextureFormat.new()
	fmt.width = Brushwork.SIZE.x
	fmt.height = Brushwork.SIZE.y
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	for i in 2:
		_wet.append(_rd.texture_create(fmt, RDTextureView.new()))
	_dry = _rd.texture_create(fmt, RDTextureView.new())
	for t in _wet + [_dry]:
		_rd.texture_clear(t, Color(0, 0, 0, 0), 0, 1, 0, 1)
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	_paper = _rd.texture_create(fmt, RDTextureView.new())
	for b in BUNDLES:
		var dabs := _rd.storage_buffer_create(DAB_ROOM * Brushwork.DAB * 4)
		var tiles := _rd.storage_buffer_create(_tiles.size() * 4, _tiles.to_byte_array())
		_bundles.append([dabs, tiles, _uniforms(_wet[0], _wet[1], dabs, tiles), _uniforms(_wet[1], _wet[0], dabs, tiles)])
	_dispatch(_bundles[0][3], PAPER, Rect2i(Vector2i.ZERO, Brushwork.SIZE), [0, 0, 0], Vector4.ZERO, Vector4.ZERO)


func _uniforms(from: RID, to: RID, dabs: RID, tiles: RID) -> RID:
	var uniforms: Array[RDUniform] = []
	for i in 7:
		var u := RDUniform.new()
		u.binding = i
		if i == 0 or i == 6:
			u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			u.add_id(_sampler)
		else:
			u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER if i >= 4 else RenderingDevice.UNIFORM_TYPE_IMAGE
		u.add_id([from, to, _dry, _paper, dabs, tiles, _paper][i])
		uniforms.append(u)
	return _rd.uniform_set_create(uniforms, _shader, 0)


func _dispatch(set: RID, mode: int, rect: Rect2i, ints: Array, colour: Vector4, more: Vector4) -> void:
	var head := PackedInt32Array([rect.position.x, rect.position.y, rect.size.x, rect.size.y, mode, ints[0], ints[1], ints[2]])
	var tail := PackedFloat32Array([colour.x, colour.y, colour.z, colour.w, more.x, more.y, more.z, more.w])
	var push := head.to_byte_array()
	push.append_array(tail.to_byte_array())
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, set, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, ceili(rect.size.x / 8.0), ceili(rect.size.y / 8.0), 1)
	_rd.compute_list_end()


func _exit_tree() -> void:
	if _rd == null:
		return
	for t in _shown:
		t.texture_rd_rid = RID()
	var rids: Array[RID] = []
	for b: Array in _bundles:
		rids.append_array([b[2], b[3], b[0], b[1]])
	rids.append_array(_wet + [_dry, _paper] + _frozen)
	var rd := _rd
	var slots := _slots
	RenderingServer.call_on_render_thread(func() -> void:
		for slot: Array in slots:
			rids.append_array(slot)
		for r in rids:
			if r.is_valid():
				rd.free_rid(r))
	_rd = null


## Whether a kept painting is still being replayed.
func catching_up() -> bool:
	return _catching_up


## Whether any paint on the canvas is still wet.
func wet() -> bool:
	return not _wet_tiles.is_empty()


## Lays dabs now, at the current tick: the painter's own brush, as it touches.
func lay(stroke: Dictionary, dabs: PackedFloat32Array) -> void:
	_open = true
	if not dabs.is_empty():
		_lay(stroke, dabs)


## The painter's own `stroke` has ended now.
func end(stroke: Dictionary) -> void:
	_open = false
	_ended(stroke)


## Plays `stroke` after `gap` ticks, each sample at the tick it was painted.
func play(stroke: Dictionary, gap: int) -> void:
	_wait(gap)
	var s := Brushwork.Stroker.new(stroke)
	for i in Brushwork.count(stroke):
		var sample := Brushwork.unpack(stroke.samples, i)
		_wait(sample[3])
		_queue.append(["dabs", stroke, s.add(sample)])
	_queue.append(["end", stroke])
	_pending += 1


## The canvas as `strokes` leave it: back to the checkpoint of the longest prefix of them kept, or a blank sheet, then
## the rest replayed as fast as the frame allows, the painting as it was staying on show until the replay has caught up.
func rebuild(strokes: Array) -> void:
	var keys := [0]
	for s: Dictionary in strokes:
		keys.append(_chain(keys[-1], s))
	var from: Array = []
	for c: Array in _checkpoints:
		if c[1] <= strokes.size() and c[0] == keys[c[1]] and (from.is_empty() or c[1] > from[1]):
			from = c
	if (0 if from.is_empty() else from[1]) < strokes.size():
		_freeze()
	_queue.clear()
	_queued_ticks = 0
	_pending = 0
	_open = false
	_owed = 0.0
	_catching_up = false
	_close_batch()
	if from.is_empty():
		_ops.append(["clear"])
		_restore([0, 0, 0, PackedInt32Array(), {}, -1])
	else:
		_ops.append(["restore", from[5]])
		_restore(from)
		_checkpoints.erase(from)
		_checkpoints.append(from)
	_close_batch()
	print("canvas: %d strokes, %d of them from a checkpoint" % [strokes.size(), _count])
	if _count == strokes.size():
		_thaw()
		return
	for i in range(_count, strokes.size()):
		play(strokes[i], strokes[i].gap)
	_catching_up = true
	_replay_from = Time.get_ticks_usec()
	_replay_frames = 0
	_replay_strokes = strokes.size() - _count


func _restore(c: Array) -> void:
	_key = c[0]
	_count = c[1]
	ticks = c[2]
	last_end = c[2]
	if c[3].is_empty():
		_tiles.fill(0)
	else:
		_tiles = c[3].duplicate()
	_wet_tiles = c[4].duplicate()
	_blank = c[1] == 0


## The key of the strokes `key` names followed by `stroke`.
static func _chain(key: int, stroke: Dictionary) -> int:
	return hash([key, stroke.medium, stroke.brush, stroke.colour, stroke.strength, stroke.load, stroke.gap, stroke.samples])


## A stroke has ended at this tick; with no other under way, the canvas keeps a checkpoint of itself.
func _ended(stroke: Dictionary) -> void:
	last_end = ticks
	_key = _chain(_key, stroke)
	_count += 1
	if _open or _pending > 0:
		return
	var slot := -1
	for c: Array in _checkpoints:
		if c[0] == _key and c[1] == _count:
			slot = c[5]
			_checkpoints.erase(c)
			break
	if slot < 0 and _checkpoints.size() >= CHECKPOINTS:
		slot = _checkpoints.pop_front()[5]
	if slot < 0:
		slot = _checkpoints.size()
	_checkpoints.append([_key, _count, ticks, _tiles.duplicate(), _wet_tiles.duplicate(), slot])
	_ops.append(["save", slot])


func _wait(n: int) -> void:
	if n > 0:
		_queue.append(["wait", n])
		_queued_ticks += n


func _process(delta: float) -> void:
	if _catching_up:
		_owed = INF
	elif not _queue.is_empty() or wet():
		_owed = minf(_owed + delta * Brushwork.TICK_HZ, MAX_OWED)
	else:
		_owed = 0.0
	var budget := STEPS
	while true:
		if not _queue.is_empty() and _queue[0][0] != "wait":
			var e: Array = _queue.pop_front()
			if e[0] == "end":
				_pending -= 1
				_ended(e[1])
				continue
			if _catching_up and budget <= 0.0:
				_queue.push_front(e)
				break
			if not e[2].is_empty():
				var laid := _lay(e[1], e[2])
				if _catching_up:
					budget -= laid
			continue
		if _owed < 1.0:
			break
		var cost := _tick_cost()
		if cost > budget and budget < STEPS:
			break
		budget -= cost
		_owed -= 1.0
		_tick()
		if not _queue.is_empty():
			_queue[0][1] -= 1
			_queued_ticks -= 1
			if _queue[0][1] <= 0:
				_queue.pop_front()
		elif not wet():
			_owed = 0.0
			break
	if _catching_up:
		_replay_frames += 1
	if _catching_up and _queue.is_empty():
		_catching_up = false
		print("canvas: %d strokes back in %.0f ms over %d frames" % [_replay_strokes, (Time.get_ticks_usec() - _replay_from) / 1000.0, _replay_frames])
		_owed = 0.0
		_thaw()
	_submit()


func _tick_cost() -> float:
	return float(_wet_rect(ticks).get_area()) * 2.0


## The tiles wet at `tick`, as one rectangle of texels.
func _wet_rect(tick: int) -> Rect2i:
	var r := Rect2i()
	for t: int in _wet_tiles:
		if _tiles[t * 2] <= tick and tick < _tiles[t * 2 + 1]:
			var at := Rect2i(Vector2i(t % TILES.x, t / TILES.x) * Brushwork.TILE, Vector2i.ONE * Brushwork.TILE)
			r = at if r.size == Vector2i.ZERO else r.merge(at)
	return r


func _tick() -> void:
	var rect := _wet_rect(ticks)
	if rect.size != Vector2i.ZERO:
		_ops.append(["tick", ticks, rect])
	ticks += 1
	for t: int in _wet_tiles.keys():
		if _tiles[t * 2 + 1] <= ticks:
			_wet_tiles.erase(t)


## Lays `dabs` and returns their cost in texel-steps: the shader runs every dab over every texel of their rectangle.
func _lay(stroke: Dictionary, dabs: PackedFloat32Array) -> float:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(0, dabs.size(), Brushwork.DAB):
		var r := dabs[i + 2] * (1.6 if stroke.medium == Brushwork.Medium.SMEAR else 1.4) + 2.0
		lo = Vector2(minf(lo.x, dabs[i] - r), minf(lo.y, dabs[i + 1] - r))
		hi = Vector2(maxf(hi.x, dabs[i] + r), maxf(hi.y, dabs[i + 1] + r))
	var rect := Rect2i(Vector2i(lo.floor()), Vector2i((hi - lo).ceil()) + Vector2i.ONE).intersection(Rect2i(Vector2i.ZERO, Brushwork.SIZE))
	if rect.size == Vector2i.ZERO:
		return 0.0
	if stroke.medium == Brushwork.Medium.WATER:
		var wet_rect := rect.grow_individual(Brushwork.MARGIN, Brushwork.MARGIN, Brushwork.MARGIN, Brushwork.RUN)
		_wetten(wet_rect.intersection(Rect2i(Vector2i.ZERO, Brushwork.SIZE)))
	if _dabs.size() + dabs.size() > DAB_ROOM * Brushwork.DAB:
		_close_batch()
	var first := _dabs.size() / Brushwork.DAB
	_blank = false
	_dabs.append_array(dabs)
	_ops.append(["dabs", stroke, first, dabs.size() / Brushwork.DAB, rect])
	return float(rect.get_area()) * dabs.size() / Brushwork.DAB


## Wets the tiles under `rect` from now until DRY_TICKS from now. A tile dry again since this frame's batch began
## starts a new batch, since the batch's earlier ticks saw it wet until then.
func _wetten(rect: Rect2i) -> void:
	var from := rect.position / Brushwork.TILE
	var to := (rect.end - Vector2i.ONE) / Brushwork.TILE
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var t := y * TILES.x + x
			var until := ticks + Brushwork.DRY_TICKS
			if _wet_tiles.has(t):
				_tiles[t * 2 + 1] = until
				continue
			if _tiles[t * 2 + 1] > _batch_start and _tiles[t * 2 + 1] <= ticks:
				_close_batch()
			_tiles[t * 2] = ticks
			_tiles[t * 2 + 1] = until
			_wet_tiles[t] = true


func _close_batch() -> void:
	if not _ops.is_empty():
		_batches.append([_ops, _dabs, _tiles.duplicate()])
	_ops = []
	_dabs = PackedFloat32Array()
	_batch_start = ticks


func _submit() -> void:
	_close_batch()
	var batches := _batches
	_batches = []
	if _rd == null or batches.is_empty():
		return
	RenderingServer.call_on_render_thread(_run.bind(batches))


func _run(batches: Array) -> void:
	var k := 0
	for b: Array in batches:
		var bundle: Array = _bundles[k % BUNDLES]
		k += 1
		if not b[1].is_empty():
			_rd.buffer_update(bundle[0], 0, b[1].size() * 4, b[1].to_byte_array())
		_rd.buffer_update(bundle[1], 0, b[2].size() * 4, b[2].to_byte_array())
		for op: Array in b[0]:
			match op[0]:
				"clear":
					for t in _wet + [_dry]:
						_rd.texture_clear(t, Color(0, 0, 0, 0), 0, 1, 0, 1)
				"save":
					while _slots.size() <= op[1]:
						_slots.append([])
					if _slots[op[1]].is_empty():
						var fmt := _rd.texture_get_format(_dry)
						_slots[op[1]] = [_rd.texture_create(fmt, RDTextureView.new()), _rd.texture_create(fmt, RDTextureView.new())]
					_copy(_wet[0], _slots[op[1]][0])
					_copy(_dry, _slots[op[1]][1])
				"restore":
					_copy(_slots[op[1]][0], _wet[0])
					_copy(_slots[op[1]][0], _wet[1])
					_copy(_slots[op[1]][1], _dry)
				"tick":
					_dispatch(bundle[2], FLOW, op[2], [0, 0, 0], Vector4.ZERO, Vector4(0, 0, op[1], 0))
					_dispatch(bundle[3], FLOW, op[2], [0, 0, 0], Vector4.ZERO, Vector4(0, 0, op[1], 1))
				"dabs":
					var s: Dictionary = op[1]
					if s.medium == Brushwork.Medium.SMEAR:
						var region: Rect2i = op[4].grow(12).intersection(Rect2i(Vector2i.ZERO, Brushwork.SIZE))
						var origin := Vector3(region.position.x, region.position.y, 0)
						_rd.texture_copy(_wet[0], _wet[1], origin, origin, Vector3(region.size.x, region.size.y, 1), 0, 0, 0, 0)
					var c: Vector3 = Brushwork.CHARCOAL if s.medium == Brushwork.Medium.CHARCOAL else s.colour
					_dispatch(bundle[3], DAB, op[4], [op[2], op[3], s.brush], Vector4(c.x, c.y, c.z, s.strength), Vector4(s.medium, 0, 0, 0))


func _copy(from: RID, to: RID) -> void:
	_rd.texture_copy(from, to, Vector3.ZERO, Vector3.ZERO, Vector3(Brushwork.SIZE.x, Brushwork.SIZE.y, 1), 0, 0, 0, 0)


## Shows a copy of the canvas as it stood before this frame's `rebuild` while a replay catches up behind it.
func _freeze() -> void:
	if _rd == null or _blank or not _frozen.is_empty():
		return
	RenderingServer.call_on_render_thread(func() -> void:
		var fmt := _rd.texture_get_format(_dry)
		for from in [_wet[0], _dry]:
			var copy := _rd.texture_create(fmt, RDTextureView.new())
			_copy(from, copy)
			_frozen.append(copy))
	_shown[0].texture_rd_rid = _frozen[0]
	_shown[1].texture_rd_rid = _frozen[1]


func _thaw() -> void:
	if _frozen.is_empty():
		return
	_shown[0].texture_rd_rid = _wet[0]
	_shown[1].texture_rd_rid = _dry
	var gone := _frozen
	_frozen = []
	RenderingServer.call_on_render_thread(func() -> void:
		for r in gone:
			_rd.free_rid(r))
