class_name Ground
extends RefCounted

## What the ground is made of: one texel per TEXEL over the play area, shared with shaders as the global
## ground_mask (ground.gdshaderinc). Red is trodden earth, green is stone, neither is meadow, and blue is the
## stone's style (StoneStyles), the last stroke's that laid most of the stone there. Every path
## and painted stroke is a mark that stamps soft discs onto it, and the mask is those marks replayed in
## the order of their build commands' ids, so lifting any one (undo) leaves exactly what the rest made, and
## every machine replays them alike. `laid` holds the garden's marks alone, for what build commands read;
## the shown image adds a player's own strokes still being drawn or on their way.

## EARTH wears the ground to earth over whatever was there; STONE lays stone over it, earth included, and
## MEADOW takes back only stone, so a path under painted-out stone keeps its wear.
enum Kind { MEADOW, EARTH, STONE }

const SIZE := 512
const TEXEL := Terrain.SIZE / SIZE

static var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
static var texture := ImageTexture.create_from_image(image)
static var laid := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
## The garden's marks in id order, with their ids alongside.
static var _marks: Array[Object] = []
static var _ids: Array[int] = []
## Finished strokes on their way to the garden, still shown.
static var _held: Array[Object] = []
## Counts rewears, so a path being drawn can tell its wear was wiped.
static var rewears := 0
## True while a whole garden is being swapped in: one rewear at the end instead of one per mark.
static var quiet := false
## Marks laid last, not yet worn into `laid`: worn on the frame after they are laid, or at once when `laid` is read,
## so a build's release does not wear its whole path in the frame it lands.
static var _unworn: Array[Object] = []
static var _unworn_since := 0
## A stroke was held or released: the shown image is redrawn when the unworn marks are.
static var _unshown := false
static var _brushes := {}
## The texels each of the garden's marks last wore, so lifting one, or laying one among older ones, wears again only
## that patch and the marks meeting it.
static var _areas := {}
static var _wearing := Rect2i()
## The style this machine's player lays stone and sets boulders down in: the one they last turned the style wheel to.
static var style := 0
## Where a patch is worn again before it is copied into `laid`: what lies outside the patch is never read.
static var _patch := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)


## A painted ground stroke: soft discs of one kind, replayed in order, its stone in one style.
class Stroke:
	var kind: Kind
	var style := 0
	## x, z, full radius and the width of the fade past it.
	var stamps := PackedVector4Array()

	func _init(m: Kind, look := 0) -> void:
		kind = m
		style = look

	func add(x: float, z: float, radius: float, verge: float) -> bool:
		if not Ground.stamp(Ground.image, x, z, radius, verge, kind, style):
			return false
		stamps.append(Vector4(x, z, radius, verge))
		Ground.upload()
		return true

	func wear(onto: Image) -> void:
		for s in stamps:
			Ground.stamp(onto, s.x, s.y, s.z, s.w, kind, style)

	func covers(x: float, z: float) -> bool:
		for s in stamps:
			if Vector2(s.x - x, s.y - z).length() < s.z + s.w:
				return true
		return false


static func install() -> void:
	_marks.clear()
	_ids.clear()
	_held.clear()
	rewear()
	RenderingServer.global_shader_parameter_set(&"ground_mask", texture)


static func _texel(x: float, z: float, from := image) -> Color:
	if from == laid:
		settle()
	return from.get_pixel(clampi(int((x / Terrain.SIZE + 0.5) * SIZE), 0, SIZE - 1), clampi(int((z / Terrain.SIZE + 0.5) * SIZE), 0, SIZE - 1))


## How bare of plants the ground is at a point, 0 meadow to 1 earth or stone, as the plant shaders read it.
static func bare(x: float, z: float) -> float:
	var c := _texel(x, z)
	return minf(c.r + c.g, 1.0)


## The same from the garden's marks alone.
static func laid_bare(x: float, z: float) -> float:
	var c := _texel(x, z, laid)
	return minf(c.r + c.g, 1.0)


static func stone(x: float, z: float) -> float:
	return _texel(x, z).g


## The build command id of the topmost path or stone stroke showing at a point, or -1: stone where the garden's
## ground there reads more stone than earth, else a path.
static func mark_at(x: float, z: float) -> int:
	var c := _texel(x, z, laid)
	var stony := c.g > c.r
	for i in range(_marks.size() - 1, -1, -1):
		var m: Object = _marks[i]
		if (m is Stroke) == stony and (not stony or m.kind == Kind.STONE) and m.covers(x, z):
			return _ids[i]
	return -1


## Adds the garden's mark from build command `id`, in its place by id.
static func lay(mark: Object, id: int) -> void:
	var i := _ids.bsearch(id)
	_ids.insert(i, id)
	_marks.insert(i, mark)
	if i == _marks.size() - 1 and not quiet:
		_wait()
		_unworn.append(mark)
	elif not quiet:
		_rewear_area(_area_of(mark, _patch))


static func lift(mark: Object) -> void:
	var i := _marks.find(mark)
	if i < 0:
		return
	_marks.remove_at(i)
	_ids.remove_at(i)
	if not quiet:
		_rewear_area(_areas.get(mark, Rect2i(0, 0, SIZE, SIZE)))
	_areas.erase(mark)


## Gives the garden's stone stroke from build command `id` style `look`, as it wears.
static func restyle(id: int, look: int) -> void:
	var i := _ids.find(id)
	if i < 0 or _marks[i].style == look:
		return
	_marks[i].style = look
	if not quiet:
		_rewear_area(_areas.get(_marks[i], Rect2i(0, 0, SIZE, SIZE)))


## Keeps showing a player's finished stroke until `release`, when its command has landed or been turned down.
static func hold(mark: Object) -> void:
	_held.append(mark)
	_wait()
	_unshown = true


static func release(mark: Object) -> void:
	_held.erase(mark)
	_wait()
	_unshown = true


## The garden swapped for another: its marks and held strokes go.
static func clear() -> void:
	_marks.clear()
	_ids.clear()
	_held.clear()
	_areas.clear()
	rewear()


## The garden's marks in order into `laid`, then held strokes over them into the shown image.
static func rewear() -> void:
	if quiet:
		return
	laid.fill(Color(0, 0, 0, 0))
	for m in _marks:
		_area_of(m, laid)
	_unworn.clear()
	_show()


## Wears `mark` onto `onto`, noting the texels it wore; returns them.
static func _area_of(mark: Object, onto: Image) -> Rect2i:
	_wearing = Rect2i()
	mark.wear(onto)
	_areas[mark] = _wearing
	return _wearing


## Wears again, in order, every mark meeting `area`, and only that patch of `laid`.
static func _rewear_area(area: Rect2i) -> void:
	for m in _unworn:
		_area_of(m, laid)
	_unworn.clear()
	if area.has_area():
		_patch.fill_rect(area, Color(0, 0, 0, 0))
		for m in _marks:
			if not _areas.has(m) or _areas[m].intersects(area):
				_area_of(m, _patch)
		laid.blit_rect(_patch, area, area.position)
	_show()


static func settle() -> void:
	if _unworn.is_empty() and not _unshown:
		return
	for m in _unworn:
		_area_of(m, laid)
	_unworn.clear()
	_show()


static func _wait() -> void:
	if _unworn.is_empty() and not _unshown:
		_unworn_since = Engine.get_process_frames()


## Settles what has waited since an earlier frame; called once a frame.
static func settle_due() -> void:
	if Engine.get_process_frames() > _unworn_since:
		settle()


static func _show() -> void:
	_unshown = false
	image.copy_from(laid)
	for m in _held:
		m.wear(image)
	rewears += 1
	upload()


static func upload() -> void:
	texture.update(image)


## Blends a disc of `kind` onto `onto`: full out to `radius`, fading to nothing over `verge` past it. Stone takes
## the texels it lays most of, or that held little stone, for `look`.
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
			match kind:
				Kind.EARTH:
					px[k] = e + ((255 - e) * a + 127) / 255
					px[k + 1] = g - (g * a + 127) / 255
				Kind.STONE:
					px[k + 1] = g + ((255 - g) * a + 127) / 255
					if a >= 128 or g < 128:
						px[k + 2] = look
				Kind.MEADOW:
					px[k + 1] = g - (g * a + 127) / 255
			changed = changed or px[k] != e or px[k + 1] != g or px[k + 2] != b
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
