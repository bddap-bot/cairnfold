class_name Ground
extends RefCounted

## The ground_mask texture, a texel per TEXEL metres: R trodden earth, G stone, A sand; B the StoneStyles style of the
## stroke that laid most stone, plus TILLED where a bed laid most earth. Marks replay in build id order, so undoing one
## leaves what the rest made, alike on every machine. `laid`, which commands read, is the garden's marks alone; `image`
## adds this player's strokes in flight.

## MEADOW takes back only stone, so a path under painted-out stone keeps its wear.
enum Kind { MEADOW, EARTH, STONE, SAND }

## A bit of B above the stone style's bits, so neither changes the other.
const TILLED := 128

const SIZE := 512
const TEXEL := Terrain.SIZE / SIZE

var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
var texture := ImageTexture.create_from_image(image)
var laid := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
## In id order, parallel to `_ids`.
var _marks: Array[Object] = []
var _ids: Array[int] = []
var _held: Array[Object] = []
## So a path being drawn can tell its wear was wiped.
var rewears := 0
## While a whole garden swaps in: one rewear at the end, not one per mark.
var quiet := false
## Worn into `laid` a few path rows a frame from the next, or at once when `laid` is read.
var _unworn: Array[Object] = []
var _unworn_since := 0
## Rows of the first unworn path already worn into `laid`.
var _worn_rows := 0
## Rect2i patches of `laid` to wear again a frame later, or marks laid among older ones, whose wear finds the patch,
## so a moved house wears both patches once.
var _stale: Array = []
var _unshown := false
static var _brushes := {}
## Mark -> the texels it last wore, so lifting or inserting one rewears only that patch and the marks meeting it.
var _areas := {}
static var _wearing := Rect2i()
## This machine's player's stone and boulder style, from the style wheel.
static var style := 0
## One byte per Terrain tile, row by row: 1 where stone was laid since the last full rewear (painted-out stone stays 1).
var stone_tiles := _no_tiles()
var stone_revision := 0
## Tile indices stone stamps reached since the last upload, on any image.
static var _stoned := PackedInt32Array()
## Scratch: nothing outside the patch is read.
var _patch := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)


class Stroke:
	var kind: Kind
	var style := 0
	## x, z, full radius, fade width past it.
	var stamps := PackedVector4Array()

	func _init(m: Kind, look := 0) -> void:
		kind = m
		style = look

	func add(shown: Ground, x: float, z: float, radius: float, verge: float) -> bool:
		if not Ground.stamp(shown.image, x, z, radius, verge, kind, style):
			return false
		stamps.append(Vector4(x, z, radius, verge))
		shown.upload()
		return true

	func wear(onto: Image) -> void:
		for s in stamps:
			Ground.stamp(onto, s.x, s.y, s.z, s.w, kind, style)

	func covers(x: float, z: float) -> bool:
		for s in stamps:
			if Vector2(s.x - x, s.y - z).length() < s.z + s.w:
				return true
		return false


func install() -> void:
	clear()
	RenderingServer.global_shader_parameter_set(&"ground_mask", texture)


func _texel(x: float, z: float, from := image) -> Color:
	if from == laid:
		settle()
	return _pixel(from, x, z)


static func _pixel(from: Image, x: float, z: float) -> Color:
	return from.get_pixel(clampi(int((x / Terrain.SIZE + 0.5) * SIZE), 0, SIZE - 1), clampi(int((z / Terrain.SIZE + 0.5) * SIZE), 0, SIZE - 1))


## 0 meadow to 1 earth, sand or stone, as the plant shaders read it.
func bare(x: float, z: float) -> float:
	return bare_in(image, x, z)


func laid_bare(x: float, z: float) -> float:
	return bare_in(laid_image(), x, z)


func laid_image() -> Image:
	settle()
	return laid


static func bare_in(from: Image, x: float, z: float) -> float:
	var c := _pixel(from, x, z)
	return minf(c.r + c.g + c.a, 1.0)


func stone(x: float, z: float) -> float:
	return _texel(x, z).g


## Build id of the topmost stone mark where `laid` is mostly stone, else of the topmost path, or -1; floors are neither.
func mark_at(x: float, z: float) -> int:
	var stony := _texel(x, z, laid).g >= 0.5
	for i in range(_marks.size() - 1, -1, -1):
		var m: Object = _marks[i]
		if (m.kind == Kind.STONE if stony else m is PathLayout) and m.covers(x, z):
			return _ids[i]
	return -1


func lay(mark: Object, id: int) -> void:
	var i := _ids.bsearch(id)
	_ids.insert(i, id)
	_marks.insert(i, mark)
	if quiet:
		return
	_wait()
	if i == _marks.size() - 1:
		_unworn.append(mark)
	else:
		_stale.append(mark)


func lift(mark: Object) -> void:
	var i := _marks.find(mark)
	if i < 0:
		return
	_marks.remove_at(i)
	_ids.remove_at(i)
	var unworn := _unworn.find(mark)
	if unworn >= 0:
		_unworn.remove_at(unworn)
		if unworn == 0:
			_worn_rows = 0
	if not quiet:
		_rewear_area(_areas.get(mark, Rect2i(0, 0, SIZE, SIZE)))
	_areas.erase(mark)


func restyle(id: int, look: int) -> void:
	var i := _ids.find(id)
	if i < 0 or _marks[i].style == look:
		return
	_marks[i].style = look
	rewear_mark(_marks[i])


func rewear_mark(mark: Object) -> void:
	if not quiet and _marks.has(mark):
		_rewear_area(_areas.get(mark, Rect2i(0, 0, SIZE, SIZE)))


## Keeps showing a finished stroke until `release`, when its command has landed or been turned down.
func hold(mark: Object) -> void:
	_held.append(mark)
	_wait()
	_unshown = true


func release(mark: Object) -> void:
	_held.erase(mark)
	_wait()
	_unshown = true


func clear() -> void:
	_marks.clear()
	_ids.clear()
	_held.clear()
	_areas.clear()
	rewear()


func rewear() -> void:
	if quiet:
		return
	stone_tiles = _no_tiles()
	_stoned.clear()
	stone_revision += 1
	laid.fill(Color(0, 0, 0, 0))
	for m in _marks:
		_area_of(m, laid)
	_unworn.clear()
	_worn_rows = 0
	_stale.clear()
	_show()


func _area_of(mark: Object, onto: Image) -> Rect2i:
	_wearing = Rect2i()
	mark.wear(onto)
	_areas[mark] = _wearing
	return _wearing


## A frame later, or once `laid` is read.
func _rewear_area(area: Rect2i) -> void:
	if area.has_area():
		_wait()
		_stale.append(area)


func _wear_stale() -> void:
	for stale: Variant in _stale:
		if stale is Object and not _marks.has(stale):
			continue
		var area: Rect2i = stale if stale is Rect2i else _area_of(stale, _patch)
		_patch.fill_rect(area, Color(0, 0, 0, 0))
		for m in _marks:
			if not _areas.has(m) or _areas[m].intersects(area):
				_area_of(m, _patch)
		laid.blit_rect(_patch, area, area.position)
	_stale.clear()


## [mark id, mask hash after it] per mark, from nothing: two machines' first differing entry names where masks part;
## a last hash other than `laid`'s shows the patched wear drifted from a full one.
func replayed() -> Array:
	var onto := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var out := []
	for i in _marks.size():
		_marks[i].wear(onto)
		out.append([_ids[i], hash(onto.get_data())])
	return out


func settle() -> void:
	if _caught_up():
		return
	_wear_unworn()
	_wear_stale()
	_show()


## `rows` < 0 for all; a path row or a whole other mark counts as one. Returns whether none is left.
func _wear_unworn(rows := -1) -> bool:
	var worn := 0
	while not _unworn.is_empty():
		var m: Object = _unworn[0]
		if m is PathLayout:
			_wearing = _areas.get(m, Rect2i()) if _worn_rows > 0 else Rect2i()
			while _worn_rows < m.row_ends.size() and (rows < 0 or worn < rows):
				m.wear(laid, _worn_rows, _worn_rows + 1)
				_worn_rows += 1
				worn += 1
			_areas[m] = _wearing
			if _worn_rows < m.row_ends.size():
				return false
		else:
			_area_of(m, laid)
			worn += 1
		_unworn.pop_front()
		_worn_rows = 0
		if rows >= 0 and worn >= rows:
			return _unworn.is_empty()
	return true


func _caught_up() -> bool:
	return _unworn.is_empty() and not _unshown and _stale.is_empty()


func _wait() -> void:
	if _caught_up():
		_unworn_since = Engine.get_process_frames()


## Called once a frame.
func settle_due() -> void:
	var rows := Budget.GROUND_WEAR_ROWS if Budget.frame_deadline else -1
	if Engine.get_process_frames() > _unworn_since and not _caught_up() and _wear_unworn(rows):
		_wear_stale()
		_show()


func _show() -> void:
	_unshown = false
	image.copy_from(laid)
	for m in _held:
		m.wear(image)
	rewears += 1
	upload()


func upload() -> void:
	texture.update(image)
	var more := false
	for t in _stoned:
		more = more or stone_tiles[t] == 0
		stone_tiles[t] = 1
	_stoned.clear()
	if more:
		stone_revision += 1


static func _no_tiles() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(Terrain.TILES * Terrain.TILES)
	return out


## A brush's outer ring is always clear, so the shader's filtering reads its stone from inside `area`.
static func _stone(area: Rect2i) -> void:
	var per := Terrain.TILE * Terrain.STEP / TEXEL
	var low := Vector2(area.position) / per
	var high := Vector2(area.end) / per
	for tj in range(maxi(floori(low.y), 0), mini(floori(high.y), Terrain.TILES - 1) + 1):
		for ti in range(maxi(floori(low.x), 0), mini(floori(high.x), Terrain.TILES - 1) + 1):
			_stoned.append(tj * Terrain.TILES + ti)


## False if off the mask, or meadow that changed nothing: another kind may matter on a replay once an earlier mark lifts.
static func stamp(onto: Image, x: float, z: float, radius: float, verge: float, kind: Kind, look := 0) -> bool:
	var fade := _brush(radius, verge)
	var side := int(sqrt(fade.size()))
	var r := (side - 1) / 2
	var at := Vector2i(roundi((x / Terrain.SIZE + 0.5) * SIZE - 0.5) - r, roundi((z / Terrain.SIZE + 0.5) * SIZE - 0.5) - r)
	var area := Rect2i(at, Vector2i(side, side)).intersection(Rect2i(0, 0, SIZE, SIZE))
	if area.size.x <= 0 or area.size.y <= 0:
		return false
	_wearing = area if not _wearing.has_area() else _wearing.merge(area)
	if kind == Kind.STONE:
		_stone(area)
	var region := onto.get_region(area)
	var px := region.get_data()
	var changed := false
	for j in area.size.y:
		var row := (area.position.y - at.y + j) * side + area.position.x - at.x
		for i in area.size.x:
			var a := fade[row + i]
			if a == 0:
				continue
			var k := (j * area.size.x + i) * 4
			var e := px[k]
			var g := px[k + 1]
			var b := px[k + 2]
			var s := px[k + 3]
			match kind:
				Kind.EARTH:
					px[k] = e + ((255 - e) * a + 127) / 255
					px[k + 1] = g - (g * a + 127) / 255
					px[k + 3] = s - (s * a + 127) / 255
					if a >= 128:
						px[k + 2] = (b & ~TILLED) | look
				Kind.SAND:
					px[k] = e - (e * a + 127) / 255
					px[k + 1] = g - (g * a + 127) / 255
					px[k + 3] = s + ((255 - s) * a + 127) / 255
				Kind.STONE:
					px[k + 1] = g + ((255 - g) * a + 127) / 255
					if a >= 128 or g < 128:
						px[k + 2] = (b & TILLED) | look
				Kind.MEADOW:
					px[k + 1] = g - (g * a + 127) / 255
			changed = changed or px[k] != e or px[k + 1] != g or px[k + 2] != b or px[k + 3] != s
	if changed:
		region.set_data(area.size.x, area.size.y, false, Image.FORMAT_RGBA8, px)
		onto.blit_rect(region, Rect2i(Vector2i.ZERO, area.size), area.position)
	return changed or kind != Kind.MEADOW


## Coverage 0 to 255, row by row.
static func _brush(radius: float, verge: float) -> PackedByteArray:
	var key := Vector2i(roundi(radius / TEXEL * 4.0), roundi(verge / TEXEL * 4.0))
	if not _brushes.has(key):
		var inner := key.x * TEXEL / 4.0
		var fade := maxf(key.y * TEXEL / 4.0, TEXEL)
		var r := ceili((inner + fade) / TEXEL)
		var out := PackedByteArray()
		for y in r * 2 + 1:
			for x in r * 2 + 1:
				out.append(roundi(255.0 * clampf((inner + fade - Vector2(x - r, y - r).length() * TEXEL) / fade, 0.0, 1.0)))
		_brushes[key] = out
	return _brushes[key]
