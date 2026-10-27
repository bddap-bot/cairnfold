class_name MirrorTool
extends Node3D

## For a hand holding the hand mirror: the trigger stands a mirror where the hand points, facing the player, or moves
## it there, and the trigger on the standing mirror puts it away. It is the player's own, as a camera is: no edit to the
## garden, and nobody else sees it. It reflects people alone, every avatar the game draws (Quality.PEOPLE_LAYER) and
## the player's own (SELF_LAYER), lit by its own light against a plain backdrop. Each eye sees it through its own view:
## a camera at that eye reflected in the glass, whose frustum is the glass itself, so it reads as a mirror, not a
## screen. Put away, or out of sight, it draws nothing.

const TINT := Color(0.8, 0.9, 1.0, 0.6)
## How many times the hand mirror's size the standing one is: its glass, 0.8 by 1.2 m and topped above a tall player's
## crown, shows the heads at eye height in its oval's broad middle and a player standing before it whole.
const STAND := 20.0
const BACKDROP := Color(0.62, 0.66, 0.63)

var rig: Rig
var terrain: Terrain
## The standing mirror, built once and hidden while put away.
var stand: Node3D
var _glass: ShaderMaterial
var _seen: VisibleOnScreenNotifier3D
var _light: DirectionalLight3D
var _env := Environment.new()
var _views: Array[SubViewport] = []
var _buttons: Array[Buttons] = []


func _init(player: Rig, ground: Terrain) -> void:
	rig = player
	terrain = ground
	for h in rig.hands:
		_buttons.append(Buttons.new(h).watch(["tool"]))
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = BACKDROP
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.86, 0.88, 0.92)
	_env.ambient_light_energy = 0.55
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# The garden's grade is applied once, to the glass as the eyes see it.
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stand = Node3D.new()
	var glass := ToolModels.mirror(stand)
	_glass = ShaderMaterial.new()
	_glass.shader = preload("res://src/mirror.gdshader")
	glass.material_override = _glass
	var foot := MeshInstance3D.new()
	foot.mesh = ToolModels.cylinder(0.018, 0.02, 0.003, 24)
	foot.position = Vector3(0, 0.0015, 0)
	foot.material_override = (stand.get_child(0) as MeshInstance3D).material_override
	stand.add_child(foot)
	_seen = VisibleOnScreenNotifier3D.new()
	_seen.aabb = AABB(ToolModels.MIRROR_CENTRE - Vector3(ToolModels.MIRROR_GLASS.x, ToolModels.MIRROR_GLASS.y, 0.01) * 0.5, Vector3(ToolModels.MIRROR_GLASS.x, ToolModels.MIRROR_GLASS.y, 0.01))
	stand.add_child(_seen)
	_light = DirectionalLight3D.new()
	_light.layers = Quality.MIRROR_LAYER
	_light.light_cull_mask = Quality.PEOPLE_LAYER | Quality.SELF_LAYER
	_light.light_energy = 0.9
	_light.basis = Basis.looking_at(Vector3(-0.35, -0.55, 1.0))
	stand.add_child(_light)
	stand.visible = false
	add_child(stand)


## The people's pipelines for a view of the mirror's kind compile as the game loads, drawn once from before the head
## looking back at it, so standing a mirror holds no frame.
func _ready() -> void:
	if RenderingServer.get_rendering_device() == null:
		return
	var vp := _view()
	var head := rig.head.global_transform
	var cam: Camera3D = vp.get_child(0)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.global_transform = Transform3D(head.basis * Basis(Vector3.UP, PI), head * Vector3(0, -0.3, -1.6))
	stand.visible = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	stand.visible = false
	vp.queue_free()


func standing() -> bool:
	return stand.visible


func _process(_delta: float) -> void:
	for i in rig.hands.size():
		var h: Hand = rig.hands[i]
		if h.tool == Hand.Tool.MIRROR and h.tracked() and not h.picking and not h.taken() and rig.aim_hand != h:
			_aim(h, _buttons[i].pressed("tool"))
		_buttons[i].latch()
	_reflect()


func _aim(h: Hand, pressed: bool) -> void:
	var from := h.global_position
	var dir := -h.global_basis.z
	var on: Variant = glass_hit(from, dir)
	if on != null:
		h.point(on, TINT)
		if pressed:
			put_away()
		return
	var hit: Variant = terrain.raycast(from, dir)
	h.point(hit, TINT)
	if pressed and hit != null:
		Cues.play(Cues.Act.EASEL_PLACE, hit, h)
		stand_at(hit, rig.head.global_position)


## Stands the mirror with its foot at `foot`, its glass turned toward `toward` about the upright.
func stand_at(foot: Vector3, toward: Vector3) -> void:
	var flat := Vector3(toward.x - foot.x, 0, toward.z - foot.z)
	var facing := Basis.looking_at(-flat.normalized()) if flat.length() > 0.01 else stand.global_basis.orthonormalized()
	stand.global_transform = Transform3D(facing.scaled(Vector3.ONE * STAND), foot)
	stand.visible = true
	var eyes := _eyes().size()
	if _views.size() != maxi(eyes, 1):
		_close_views()
		for i in maxi(eyes, 1):
			_views.append(_view())
	_glass.set_shader_parameter(&"left_eye", _views[0].get_texture())
	_glass.set_shader_parameter(&"right_eye", _views[-1].get_texture())


func put_away() -> void:
	stand.visible = false
	_close_views()


func _close_views() -> void:
	for vp in _views:
		vp.queue_free()
	_views.clear()


func _view() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Budget.MIRROR_VIEW
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.cull_mask = Quality.MIRROR_MASK
	cam.environment = _env
	vp.add_child(cam)
	add_child(vp)
	return vp


## The glass's frame: its centre, x along its width and y up its height, each as long as the glass, z out of its face.
func glass() -> Transform3D:
	return stand.global_transform * Transform3D(Basis.from_scale(Vector3(ToolModels.MIRROR_GLASS.x, ToolModels.MIRROR_GLASS.y, 1)), ToolModels.MIRROR_CENTRE)


## Where a ray from `from` along `dir` meets the standing mirror's glass, from either side, or null.
func glass_hit(from: Vector3, dir: Vector3) -> Variant:
	if not standing():
		return null
	var g := glass()
	var o := g.affine_inverse() * from
	var d := g.affine_inverse().basis * dir
	if is_zero_approx(d.z) or -o.z / d.z <= 0.0:
		return null
	var p := o - d * (o.z / d.z)
	return g * p if Vector2(p.x, p.y).length() <= 0.5 else null


## The camera that sees, through `glass` (`glass()`), what an eye at `eye` sees in it: at the eye's reflection, looking
## out of the glass, its near plane the glass and its frustum offset onto the glass's centre. Empty for an eye behind
## the glass, which sees no reflection.
static func reflection(glass: Transform3D, eye: Vector3) -> Dictionary:
	var n := glass.basis.z.normalized()
	var d := (eye - glass.origin).dot(n)
	if d <= 0.01:
		return {}
	var at := Transform3D(Basis(-glass.basis.x.normalized(), glass.basis.y.normalized(), -n), eye - 2.0 * d * n)
	var centre := at.affine_inverse() * glass.origin
	return {"at": at, "offset": Vector2(centre.x, centre.y), "near": d}


## Where each eye is that draws this frame: each XR view's, or the one camera's.
func _eyes() -> Array:
	var vp := get_viewport()
	var xr := XRServer.primary_interface
	if vp != null and vp.use_xr and xr != null and xr.is_initialized():
		return range(xr.get_view_count()).map(func(i: int) -> Vector3: return xr.get_transform_for_view(i, XRServer.world_origin).origin)
	var cam := vp.get_camera_3d() if vp != null else null
	return [cam.global_position] if cam != null else []


func _reflect() -> void:
	if not standing():
		return
	var g := glass()
	var eyes := _eyes()
	for i in _views.size():
		var view := {} if eyes.is_empty() or not _seen.is_on_screen() else reflection(g, eyes[mini(i, eyes.size() - 1)])
		_views[i].render_target_update_mode = SubViewport.UPDATE_DISABLED if view.is_empty() else SubViewport.UPDATE_ALWAYS
		if view.is_empty():
			continue
		var cam: Camera3D = _views[i].get_child(0)
		cam.global_transform = view.at
		cam.set_frustum(g.basis.y.length(), view.offset, view.near, rig.far())
