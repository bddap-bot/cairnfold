class_name Ground
extends RefCounted

## What the ground is made of, one per World: one texel per TEXEL over the play area, shared with shaders as the global
## ground_mask (ground.gdshaderinc). Red is trodden earth, green is stone, alpha is sand, none of them is meadow, and blue
## holds the style (StoneStyles) of the stroke that laid most of the stone there, and TILLED where a garden bed laid most
## of the earth. Every path
## and painted stroke is a mark that stamps soft discs onto it, and the mask is those marks replayed in
## the order of their build commands' ids, so lifting any one (undo) leaves exactly what the rest made, and
## every machine replays them alike. `laid` holds the garden's marks alone, for what build commands read;
## the shown image adds a player's own strokes still being drawn or on their way.

## EARTH and SAND wear the ground to earth or sand over whatever was there; STONE lays stone over it, earth and sand
## included, and MEADOW takes back only stone, so a path under painted-out stone keeps its wear.
enum Kind { MEADOW, EARTH, STONE, SAND }

## The bit of blue a bed's earth sets over the stone style's bits below it, so neither changes the other.
const TILLED := 128

const SIZE := 512
const TEXEL := Terrain.SIZE / SIZE

var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
var texture := ImageTexture.create_from_image(image)
var laid := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
## The garden's marks in id order, with their ids alongside.
var _marks: Array[Object] = []
var _ids: Array[int] = []
## Finished strokes on their way to the garden, still shown.
var _held: Array[Object] = []
## Counts rewears, so a path being drawn can tell its wear was wiped.
var rewears := 0
## True while a whole garden is being swapped in: one rewear at the end instead of one per mark.
var quiet := false
## Marks laid last, not yet worn into `laid`: worn from the frame after they are laid, a path a few rows a frame, or at
## once when `laid` is read, so a build's release does not wear its whole path in one frame. The shown image keeps what
## it showed until they are.
var _unworn: Array[Object] = []
var _unworn_since := 0
## The rows of the first unworn path already worn into `laid`.
var _worn_rows := 0
## The patches of `laid` to wear again with the unworn marks, a frame after: where a mark was lifted or restyled, or a
## mark laid among older ones, whose wear finds its patch. A house carried off its worn floor and set down on a new one
## wears both once, and not in the frame that moved it.
var _stale: Array = []
## A stroke was held or released: the shown image is redrawn when the unworn marks are.
var _unshown := false
static var _brushes := {}
## The texels each of the garden's marks last wore, so lifting one, or laying one among older ones, wears again only
## that patch and the marks meeting it.
var _areas := {}
static var _wearing := Rect2i()
## The style this machine's player lays stone and sets boulders down in: the one they last turned the style wheel to.
static var style := 0
## Where a patch is worn again before it is copied into `laid`: what lies outside the patch is never read.
var _patch := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)


## A painted ground stroke: soft discs of one kind, replayed in order, its stone in one style.
class Stroke:
	var kind: Kind
	var style := 0
	## x, z, full radius and the width of the fade past it.
	var stamps := PackedVector4Array()

	func _init(m: Kind, look := 0) -> void:
		kind = m
		style = look

	## Adds a stamp, shown at once on `shown`, which holds this stroke.
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
	_marks.clear()
	_ids.clear()
	_held.clear()
	rewear()
	RenderingServer.global_shader_parameter_set(&"ground_mask", texture)


func _texel(x: float, z: float, from := image) -> Color:
	if from == laid:
		settle()
	return _pixel(from, x, z)


static func _pixel(from: Image, x: float, z: float) -> Color:
	return from.get_pixel(clampi(int((x / Terrain.SIZE + 0.5) * SIZE), 0, SIZE - 1), clampi(int((z / Terrain.SIZE + 0.5) * SIZE), 0, SIZE - 1))


## How bare of plants the ground is at a point, 0 meadow to 1 earth, sand or stone, as the plant shaders read it.
func bare(x: float, z: float) -> float:
	return bare_in(image, x, z)


## The same from the garden's marks alone.
func laid_bare(x: float, z: float) -> float:
	return bare_in(laid_image(), x, z)


## The garden's marks, settled, for reading many points with `bare_in`.
func laid_image() -> Image:
	settle()
	return laid


static func bare_in(from: Image, x: float, z: float) -> float:
	var c := _pixel(from, x, z)
	return minf(c.r + c.g + c.a, 1.0)


func stone(x: float, z: float) -> float:
	return _texel(x, z).g


## The build command id of the topmost stroke or path laying stone where the garden's ground there is mostly stone,
## else of the topmost path, or -1. A house's worn floor is neither.
func mark_at(x: float, z: float) -> int:
	var stony := _texel(x, z, laid).g >= 0.5
	for i in range(_marks.size() - 1, -1, -1):
		var m: Object = _marks[i]
		if (m.kind == Kind.STONE if stony else m is PathLayout) and m.covers(x, z):
			return _ids[i]
	return -1


## Adds the garden's mark from build command `id`, in its place by id.
func lay(mark: Object, id: int) -> void:
	var i := _ids.bsearch(id)
	_ids.insert(i, id)
	_marks.insert(i, mark)
	if i == _marks.size() - 1 and not quiet:
		_wait()
		_unworn.append(mark)
	elif not quiet:
		_wait()
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


## Gives the garden's stone stroke from build command `id` style `look`, as it wears.
func restyle(id: int, look: int) -> void:
	var i := _ids.find(id)
	if i < 0 or _marks[i].style == look:
		return
	_marks[i].style = look
	rewear_mark(_marks[i])


## Wears the garden's `mark` again where it lies, after what it lays changed.
func rewear_mark(mark: Object) -> void:
	if not quiet and _marks.has(mark):
		_rewear_area(_areas.get(mark, Rect2i(0, 0, SIZE, SIZE)))


## Keeps showing a player's finished stroke until `release`, when its command has landed or been turned down.
func hold(mark: Object) -> void:
	_held.append(mark)
	_wait()
	_unshown = true


func release(mark: Object) -> void:
	_held.erase(mark)
	_wait()
	_unshown = true


## The garden swapped for another: its marks and held strokes go.
func clear() -> void:
	_marks.clear()
	_ids.clear()
	_held.clear()
	_areas.clear()
	rewear()


## The garden's marks in order into `laid`, then held strokes over them into the shown image.
func rewear() -> void:
	if quiet:
		return
	laid.fill(Color(0, 0, 0, 0))
	for m in _marks:
		_area_of(m, laid)
	_unworn.clear()
	_worn_rows = 0
	_stale.clear()
	_show()


## Wears `mark` onto `onto`, noting the texels it wore; returns them.
func _area_of(mark: Object, onto: Image) -> Rect2i:
	_wearing = Rect2i()
	mark.wear(onto)
	_areas[mark] = _wearing
	return _wearing


## Has `area` of `laid` worn again a frame later, or once `laid` is read.
func _rewear_area(area: Rect2i) -> void:
	if area.has_area():
		_wait()
		_stale.append(area)


## Wears again, in order, every mark meeting each stale patch, and only those patches of `laid`.
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


func settle() -> void:
	if _unworn.is_empty() and not _unshown and _stale.is_empty():
		return
	_wear_unworn()
	_wear_stale()
	_show()


## Wears every unworn mark into `laid`, or with `budget_us` as many of a path's rows as fit that many microseconds (one
## at least); whether none is left.
func _wear_unworn(budget_us := INF) -> bool:
	var start := Time.get_ticks_usec()
	while not _unworn.is_empty():
		var m: Object = _unworn[0]
		if m is PathLayout:
			_wearing = _areas.get(m, Rect2i()) if _worn_rows > 0 else Rect2i()
			while _worn_rows < m.row_ends.size():
				m.wear(laid, _worn_rows, _worn_rows + 1)
				_worn_rows += 1
				if Budget.over(start, budget_us):
					break
			_areas[m] = _wearing
			if _worn_rows < m.row_ends.size():
				return false
		else:
			_area_of(m, laid)
		_unworn.pop_front()
		_worn_rows = 0
		if Budget.over(start, budget_us):
			return _unworn.is_empty()
	return true


func _wait() -> void:
	if _unworn.is_empty() and not _unshown and _stale.is_empty():
		_unworn_since = Engine.get_process_frames()


## Settles what has waited since an earlier frame; called once a frame.
func settle_due() -> void:
	if Engine.get_process_frames() > _unworn_since and (not _unworn.is_empty() or _unshown or not _stale.is_empty()) and _wear_unworn(Budget.GROUND_WEAR_US):
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


## Blends a disc of `kind` onto `onto`: full out to `radius`, fading to nothing over `verge` past it. Stone takes
## the texels it lays most of, or that held little stone, for its style `look`; earth the texels it lays most of for its
## look, TILLED or not.
## False if it fell off the mask, or was meadow that found no stone to take: a stamp that changes nothing
## now may still matter on a replay once an earlier mark is lifted.
static func stamp(onto: Image, x: float, z: float, radius: float, verge: float, kind: Kind, look := 0) -> bool:
	var fade := _brush(radius, verge)
	var side := int(sqrt(fade.size()))
	var r := (side - 1) / 2
	var at := Vector2i(roundi((x / Terrain.SIZE + 0.5) * SIZE - 0.5) - r, roundi((z / Terrain.SIZE + 0.5) * SIZE - 0.5) - r)
	var area := Rect2i(at, Vector2i(side, side)).intersection(Rect2i(0, 0, SIZE, SIZE))
	if area.size.x <= 0 or area.size.y <= 0:
		return false
	_wearing = area if not _wearing.has_area() else _wearing.merge(area)
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


## A disc's coverage, 0 to 255, row by row.
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
