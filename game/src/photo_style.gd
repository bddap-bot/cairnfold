class_name PhotoStyle
extends RefCounted

## A look the camera's lens draws through, and the eyes too while one stays on the whole view: a pass over the drawn
## view (StylePass) or, for the sculpture, the garden drawn white (Quality.SCULPTURE_LAYER).

enum Kind { PLAIN, PAINTERLY, SCULPTURE, MONO, SEPIA, CYANOTYPE }

const LUMA := Vector3(0.2126, 0.7152, 0.0722)
## Of the view's height: strokes about 17 px long on a photo, a texel or two on a camera's screen.
const STROKES := 0.007
const SATURATED := 1.3

## Kind -> its pass's tone, rows mapping linear rgb to rgb, or null for no pass.
const TONES := {
	Kind.PLAIN: null,
	Kind.PAINTERLY: Basis(LUMA * (1.0 - SATURATED) + Vector3(SATURATED, 0, 0), LUMA * (1.0 - SATURATED) + Vector3(0, SATURATED, 0), LUMA * (1.0 - SATURATED) + Vector3(0, 0, SATURATED)),
	Kind.SCULPTURE: null,
	Kind.MONO: Basis(LUMA, LUMA, LUMA),
	Kind.SEPIA: Basis(LUMA * 1.15, LUMA * 0.92, LUMA * 0.66),
	Kind.CYANOTYPE: Basis(LUMA * 0.35, LUMA * 0.62, LUMA * 1.1),
}


static var _shell: ShaderMaterial
## Instance id -> a WeakRef to one of Godot's own materials in the garden (`carve`), so a figure's go with it.
static var _carved := {}
## Instance ids of the cameras drawing the sculpture.
static var _carving := {}
## Figures are opened on worker threads too (ToolModels' icons).
static var _lock := Mutex.new()


static func _static_init() -> void:
	RenderingServer.global_shader_parameter_set(&"sculpture_layer", Quality.SCULPTURE_LAYER)
	_shell = ShaderMaterial.new()
	_shell.shader = preload("res://src/sculpture_shell.gdshader")


## Godot's own materials run no shader of the garden's, so while a camera carves, each under `n` takes the sculpture's
## white as a pass of its own, which every other camera drops in its vertex stage; at other times they carry none, since
## the kit and figures hold over a hundred surfaces, each a draw more.
static func carve(n: Node) -> void:
	var meshes := n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		meshes.append(n)
	_lock.lock()
	for mi: MeshInstance3D in meshes:
		for i in mi.get_surface_override_material_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D and _carvable(m) and not _carved.has(m.get_instance_id()):
				_carved[m.get_instance_id()] = weakref(m)
				m.next_pass = _shell if _carves_now() else null
	_lock.unlock()


## An opaque surface whose next pass nothing else owns (Avatar's outline hulls do): a white pass over anything seen
## through would hide what lies behind it.
static func _carvable(m: BaseMaterial3D) -> bool:
	return m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and m.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED \
		and not m.has_meta("hull") and (m.next_pass == null or m.next_pass == _shell)


static func _carves(cam: Camera3D, on: bool) -> void:
	_lock.lock()
	var was := not _carving.is_empty()
	var left := _carves.bind(cam, false)
	if on:
		_carving[cam.get_instance_id()] = true
		if not cam.tree_exiting.is_connected(left):
			cam.tree_exiting.connect(left, CONNECT_ONE_SHOT)
	else:
		_carving.erase(cam.get_instance_id())
	var now := _carves_now()
	if was != now:
		for id: int in _carved.keys():
			var m: BaseMaterial3D = _carved[id].get_ref()
			if m == null:
				_carved.erase(id)
			else:
				m.next_pass = _shell if now else null
	_lock.unlock()


## A camera freed outside the tree never says it left.
static func _carves_now() -> bool:
	for id: int in _carving.keys():
		if not is_instance_id_valid(id):
			_carving.erase(id)
	return not _carving.is_empty()


static func of(name: String) -> Kind:
	return Kind[name.to_upper()]


static func named(kind: Kind) -> String:
	return Kind.find_key(kind).to_lower()


static func mask(kind: Kind, seen: int) -> int:
	return seen | Quality.SCULPTURE_LAYER if kind == Kind.SCULPTURE else seen & ~Quality.SCULPTURE_LAYER


## Sets `cam` to draw `seen` through `kind`. A camera keeps one pass, holding a copy of its view, and turns it to each
## style it draws.
static func dress(cam: Camera3D, kind: Kind, seen: int) -> void:
	cam.cull_mask = mask(kind, seen)
	var was: Kind = cam.get_meta(&"style", Kind.PLAIN)
	if was == kind:
		return
	cam.set_meta(&"style", kind)
	if (was == Kind.SCULPTURE) != (kind == Kind.SCULPTURE):
		_carves(cam, kind == Kind.SCULPTURE)
	var tone: Variant = TONES[kind]
	if tone == null:
		if cam.compositor != null:
			(cam.compositor.compositor_effects[0] as StylePass).rest()
		cam.compositor = null
		return
	var c: Compositor = cam.get_meta(&"pass") if cam.has_meta(&"pass") else _pass()
	cam.set_meta(&"pass", c)
	var p: StylePass = c.compositor_effects[0]
	p.tone = tone
	p.reach = STROKES if kind == Kind.PAINTERLY else 0.0
	cam.compositor = c


static func _pass() -> Compositor:
	var c := Compositor.new()
	c.compositor_effects = [StylePass.new()]
	return c
