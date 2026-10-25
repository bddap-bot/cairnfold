class_name Mixing
extends RefCounted

## The open board of an oil palette, where paint is mixed by painting it on and picked up by touching it: a grid of
## texels each holding an amount of paint and its colour. A brush touching the board trades paint with every texel
## under it, giving where it is fuller than the board and taking where the board is fuller, and smearing the two
## colours into each other either way, so stirring blue into yellow makes green. Colours mix as pigments do, by
## Kubelka-Munk with one constant: each colour is its absorption over scattering (K/S) per channel, which mixes in
## proportion to the amounts.
##
## The field's state is its `bytes`: per texel the square root of each channel's linear reflectance and the amount,
## which is what the garden keeps and sends (`mix`) and what the GPU draws (`mixing.gdshader`).

const SIZE := Vector2i(48, 32)
## The board the grid spans, in the palette's frame (x, z), centred on it.
const METRES := Easels.PALETTE_SIZE
const TEXEL := METRES.x / SIZE.x
## Paint lies only within this share of the board's oval, and not over the thumb hole.
const OVAL := 0.92
const THUMB_CLEAR := 0.026
## A full brush holds this much paint per texel under it, and soaks paint up until its load is SOAK times the
## amount on the board under it.
const HOLDS := 1.0
const SOAK := 1.5
## How fast brush and board trade, per second, and how much of that is smearing.
const RATE := 12.0
const STIR := 0.5

var bytes := PackedByteArray()
var _ks := PackedFloat32Array()
var _amount := PackedFloat32Array()
static var _open := PackedByteArray()
static var _to_ks := PackedFloat32Array()
## A clean board's bytes, K/S and amounts, worked out once: every easel set up starts from it.
static var _clean := []


func _init() -> void:
	if _open.is_empty():
		_open.resize(SIZE.x * SIZE.y)
		for y in SIZE.y:
			for x in SIZE.x:
				var at := texel_at(Vector2i(x, y))
				var oval := Vector2(at.x / (METRES.x * 0.5), at.y / (METRES.y * 0.5)).length()
				_open[y * SIZE.x + x] = 1 if oval < OVAL and at.distance_to(Vector2(Easels.THUMB.x, Easels.THUMB.z)) > THUMB_CLEAR else 0
		_to_ks.resize(256)
		for v in 256:
			_to_ks[v] = ks(v * v / 65025.0)
	load_bytes(PackedByteArray())


## The board's point (palette frame x, z) at texel `t`'s centre.
static func texel_at(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * TEXEL - METRES * 0.5


## K/S of linear reflectance `r`, and back.
static func ks(r: float) -> float:
	r = clampf(r, 0.002, 1.0)
	return (1.0 - r) * (1.0 - r) / (2.0 * r)


static func reflectance(k: float) -> float:
	return 1.0 + k - sqrt(k * k + 2.0 * k)


## A brush's paint (optical density, as `Brushwork` carries it) as K/S, and back.
static func ks_of(density: Vector3) -> Vector3:
	return Vector3(ks(exp(-density.x)), ks(exp(-density.y)), ks(exp(-density.z)))


static func density_of(k: Vector3) -> Vector3:
	return Vector3(-log(reflectance(k.x)), -log(reflectance(k.y)), -log(reflectance(k.z)))


## The field as `data`, as `bytes` holds it; empty for a clean board.
func load_bytes(data: PackedByteArray) -> void:
	var n := SIZE.x * SIZE.y
	var clean := data.size() != n * 4
	if clean and not _clean.is_empty():
		bytes = _clean[0].duplicate()
		_ks = _clean[1].duplicate()
		_amount = _clean[2].duplicate()
		return
	if clean:
		data = PackedByteArray()
		data.resize(n * 4)
	bytes = data.duplicate()
	_ks.resize(n * 3)
	_amount.resize(n)
	for i in n:
		_ks[i * 3] = _to_ks[bytes[i * 4]]
		_ks[i * 3 + 1] = _to_ks[bytes[i * 4 + 1]]
		_ks[i * 3 + 2] = _to_ks[bytes[i * 4 + 2]]
		_amount[i] = bytes[i * 4 + 3] / 255.0
	if clean:
		_clean = [bytes.duplicate(), _ks.duplicate(), _amount.duplicate()]


func empty() -> bool:
	return _amount.count(0.0) == _amount.size()


## Whether paint may lie at `point` (palette frame x, z).
static func open_at(point: Vector2) -> bool:
	var t := ((point + METRES * 0.5) / TEXEL).floor()
	return t.x >= 0 and t.y >= 0 and t.x < SIZE.x and t.y < SIZE.y and _open[int(t.y) * SIZE.x + int(t.x)] == 1


## The brush `brush` ({ks: Vector3, load: 0..1}) touching the board at `at` (palette frame x, z) over a disc of
## `radius` metres for `delta` seconds: trades paint with each texel under it. Returns the brush as it leaves, and
## whether any texel changed.
func touch(brush: Dictionary, at: Vector2, radius: float, delta: float) -> Array:
	var r := maxf(radius, TEXEL * 0.75)
	var cx := (at.x + METRES.x * 0.5) / TEXEL - 0.5
	var cy := (at.y + METRES.y * 0.5) / TEXEL - 0.5
	var rt := r / TEXEL
	var rr := rt * rt
	var x0 := maxi(ceili(cx - rt), 0)
	var x1 := mini(floori(cx + rt), SIZE.x - 1)
	var y0 := maxi(ceili(cy - rt), 0)
	var y1 := mini(floori(cy + rt), SIZE.y - 1)
	var kr: float = brush.ks.x
	var kg: float = brush.ks.y
	var kb: float = brush.ks.z
	var load: float = brush.load
	var pace := 1.0 - exp(-RATE * delta)
	var held := load * HOLDS
	var cover := 0.0
	var gained := 0.0
	var lost := 0.0
	var tr := 0.0
	var tg := 0.0
	var tb := 0.0
	var changed := false
	for y in range(y0, y1 + 1):
		var dy := y - cy
		for x in range(x0, x1 + 1):
			var i := y * SIZE.x + x
			var dx := x - cx
			var d2 := (dx * dx + dy * dy) / rr
			if d2 >= 1.0 or _open[i] == 0:
				continue
			var w := pace * (1.0 - d2)
			cover += 1.0 - d2
			var a := _amount[i]
			var flow := w * 0.5 * (a * SOAK * HOLDS - held) / (1.0 + SOAK)
			var stir := w * STIR * minf(a, held)
			var take := minf(maxf(flow, 0.0) + stir, a)
			var give := maxf(-flow, 0.0) + stir
			if take <= 0.0 and give <= 0.0:
				continue
			var left := a - take
			var now := minf(left + give, 1.0)
			var j := i * 3
			var or_ := _ks[j]
			var og := _ks[j + 1]
			var ob := _ks[j + 2]
			gained += take
			tr += or_ * take
			tg += og * take
			tb += ob * take
			lost += now - left
			if now > 0.0:
				var s := (now - left) / now
				_ks[j] = or_ + (kr - or_) * s
				_ks[j + 1] = og + (kg - og) * s
				_ks[j + 2] = ob + (kb - ob) * s
			_amount[i] = now
			var o := i * 4
			bytes[o] = roundi(sqrt(reflectance(_ks[j])) * 255.0)
			bytes[o + 1] = roundi(sqrt(reflectance(_ks[j + 1])) * 255.0)
			bytes[o + 2] = roundi(sqrt(reflectance(_ks[j + 2])) * 255.0)
			bytes[o + 3] = roundi(now * 255.0)
			changed = true
	var k := Vector3(kr, kg, kb)
	if cover > 0.0:
		var kept := maxf(held * cover - lost, 0.0)
		var after := kept + gained
		if after > 0.0:
			k = (k * kept + Vector3(tr, tg, tb)) / after
		load = clampf(after / (HOLDS * cover), 0.0, 1.0)
	return [{"ks": k, "load": load}, changed]


## The paint at `point` (palette frame x, z): {ks, amount}.
func at(point: Vector2) -> Dictionary:
	var t := ((point + METRES * 0.5) / TEXEL).floor()
	var i := clampi(int(t.y), 0, SIZE.y - 1) * SIZE.x + clampi(int(t.x), 0, SIZE.x - 1)
	return {"ks": Vector3(_ks[i * 3], _ks[i * 3 + 1], _ks[i * 3 + 2]), "amount": _amount[i]}
