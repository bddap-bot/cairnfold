extends "res://../tests/support/suite.gd"

## Headless checks of reading Unity packages: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_unity_package.gd

const Yaml = preload("res://../scripts/unity/yaml.gd")
const XXHash = preload("res://../scripts/unity/xxhash.gd")
const Assets = preload("res://../scripts/unity/assets.gd")
const Prefabs = preload("res://../scripts/unity/prefabs.gd")
const Materials = preload("res://../scripts/unity/materials.gd")
const FbxSlots = preload("res://../scripts/unity/fbx_slots.gd")
const UnityAvatar = preload("res://../scripts/unity_avatar.gd")
const Expressions = preload("res://../scripts/unity/expressions.gd")
const VRCFury = preload("res://../scripts/unity/vrcfury.gd")
const SpringDefinition = preload("res://addons/avatar_workshop/spring_definition.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_xxhash_matches_the_reference()
	_the_view_is_given_in_the_models_axes()
	_yaml_reads_unity_objects()
	_nested_prefabs_flatten()
	_model_objects_keep_their_bindings_and_transforms()
	_material_properties_read_either_layout()
	_materials_cull_as_their_shader_reads()
	_materials_blend_as_their_shader_blends()
	_an_sdk_shader_the_package_omits_is_known()
	_outside_constraints_place()
	_native_constraints_resolve_world_and_feedback()
	_mesh_bones_do_not_alias_another_models_names()
	_a_dotted_bone_name_binds_its_own_transform()
	_sources_binding_one_bone_differently_share_one_bind()
	_a_branching_physbone_root_stays_still()
	_a_physbone_ends_at_its_endpoint()
	_a_physbone_carries_its_limit()
	_a_physbone_limit_follows_its_curves_down_the_chain()
	_a_physbone_carries_its_settings_bone_by_bone()
	_legacy_springs_keep_their_root_and_endpoint()
	_a_dynamic_bone_sizes_by_its_own_transform()
	_colliders_keep_their_shape_side_and_bone()
	_a_collider_rides_its_bone_where_unity_places_it()
	_physics_runs_as_the_menu_switches_it()
	_a_moved_collider_rides_its_own_bone()
	_linked_props_keep_their_placement_and_bone_identity()
	_a_transform_the_skeleton_lacks_becomes_a_bone()
	_a_menu_toggle_switches_a_hidden_renderer()
	_a_direct_tree_sums_its_toggles_unnormalized()
	_a_hue_radial_keeps_its_material_binding()
	_a_decal_alpha_binds_its_atlas_layer()
	_a_shrunk_texture_averages_what_its_cell_covers()
	_the_atlas_widens_before_its_cells_shrink()
	_a_decal_keeps_the_size_unity_imports()
	_matcaps_and_emission_join_the_look()
	_installed_packages_lend_only_missing_images()
	_submeshes_take_slots_in_first_use_order()
	_gesture_faces_become_expressions()
	_a_shape_name_keeps_each_renderers_weight()
	_curves_keep_their_unity_tangents()
	_an_unpacked_armature_still_takes_a_link()
	_transform_and_physbone_curves_bind()
	_vrcfury_toggles_join_the_menu()
	_vrcfury_full_controller_paths_resolve_from_their_object()
	_a_udim_discard_tile_is_a_switch()
	_a_radial_moving_nothing_is_cut_beside_a_live_one()
	_a_blend_child_holds_what_its_sibling_animates_at_rest()
	_a_full_controller_renames_its_layers_and_menu()
	finish()


## XXH64's published values, and a model object's file ID as Unity's importer names it.
## The descriptor's view position becomes the eyes' offset from the head bone in the model's axes, as VRM gives it and
## Avatar reads it, whichever way the head bone is turned at rest.
func _the_view_is_given_in_the_models_axes() -> void:
	var sk := Skeleton3D.new()
	sk.add_bone("Head")
	sk.add_bone("EyeL")
	sk.add_bone("EyeR")
	sk.set_bone_parent(1, 0)
	sk.set_bone_parent(2, 0)
	sk.set_bone_rest(0, Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 1.5, 0)))
	sk.set_bone_rest(1, Transform3D(Basis(), Vector3(-0.03, 0.05, 0.08)))
	sk.set_bone_rest(2, Transform3D(Basis(), Vector3(0.03, 0.05, 0.08)))
	var human := {"head": NodePath(":Head"), "leftEye": NodePath(":EyeL"), "rightEye": NodePath(":EyeR")}
	var viewed: Vector3 = UnityAvatar._eyes(sk, {"ViewPosition": {"x": "0", "y": "1.6", "z": "0.07"}}, human)
	check(viewed.is_equal_approx(Vector3(0, 0.1, 0.07)), "the view position stands from the head bone in the model's axes: %s" % viewed)
	var eyes: Vector3 = UnityAvatar._eyes(sk, {}, human)
	var between := (sk.get_bone_global_rest(1).origin + sk.get_bone_global_rest(2).origin) / 2.0
	check(eyes.is_equal_approx(between - Vector3(0, 1.5, 0)), "without one, the eyes stand between the eye bones: %s" % eyes)
	sk.free()


func _xxhash_matches_the_reference() -> void:
	check(XXHash.hash64(PackedByteArray()) == -1205034819632174695, "XXH64 of nothing (0xEF46DB3751D8E999)")
	check(XXHash.hash64("a".to_ascii_buffer()) == -3292477735350538661, "XXH64 of a (0xD24EC4F1A98C6E5B)")
	check(XXHash.hash64("abcdefghijklmnopqrstuvwxyz012345678901234567890".to_ascii_buffer()) == XXHash.hash64("abcdefghijklmnopqrstuvwxyz012345678901234567890".to_ascii_buffer()), "XXH64 is a function")
	check(XXHash.file_id("Mesh", "Body", 0) == 2959467708922500008, "a model's mesh named Body is Type:Mesh->Body0")


func _yaml_reads_unity_objects() -> void:
	var text := """%YAML 1.1
%TAG !u! tag:unity3d.com,2011:
--- !u!1 &100
GameObject:
  m_Name: 'it''s here'
  m_IsActive: 1
  m_Component:
  - component: {fileID: 101}
  - component: {fileID: 102}
--- !u!137 &102
SkinnedMeshRenderer:
  m_Materials:
  - {fileID: 2100000, guid: abc, type: 2}
  - {fileID: 0}
  m_BlendShapeWeights:
  - 0
  - 100
  m_Text: a long value
    that wraps
--- !u!4 &-7 stripped
Transform:
  m_CorrespondingSourceObject: {fileID: 400000, guid: def, type: 3}
"""
	var objs := Yaml.objects(text)
	check(objs.size() == 3 and objs.has(-7) and objs[-7].stripped, "three objects, the negative ID stripped")
	check(objs[100].type == "GameObject" and objs[100].data.m_Name == "it's here", "a quoted name with its quote")
	check((objs[100].data.m_Component as Array).size() == 2 and objs[100].data.m_Component[1].component.fileID == "102", "a sequence of mappings at its key's indent")
	var r: Dictionary = objs[102].data
	check(r.m_Materials[0].guid == "abc" and r.m_Materials[1].fileID == "0", "flow mappings in a sequence")
	check(r.m_BlendShapeWeights == ["0", "100"], "scalars in a sequence")
	check(r.m_Text == "a long value that wraps", "a plain scalar over two lines")


## A scene instancing a prefab that instances another: modifications reach objects of both, objects take the IDs
## Unity gives them, and a stripped object is the object it stands for.
func _nested_prefabs_flatten() -> void:
	var dir := ProjectSettings.globalize_path("user://prefabs")
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(name: String, guid: String, text: String) -> void:
		FileAccess.open(dir.path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	write.call("inner.prefab", "a1", """--- !u!1 &10
GameObject:
  m_Name: Hat
  m_IsActive: 1
  m_Component:
  - component: {fileID: 11}
--- !u!4 &11
Transform:
  m_GameObject: {fileID: 10}
  m_Father: {fileID: 0}
""")
	write.call("outer.prefab", "b2", """--- !u!1001 &20
PrefabInstance:
  m_Modification:
    m_TransformParent: {fileID: 0}
    m_Modifications:
    - target: {fileID: 10, guid: a1, type: 3}
      propertyPath: m_Name
      value: Cap
      objectReference: {fileID: 0}
  m_SourcePrefab: {fileID: 100100000, guid: a1, type: 3}
""")
	write.call("scene.unity", "c3", """--- !u!1001 &30
PrefabInstance:
  m_Modification:
    m_TransformParent: {fileID: 0}
    m_Modifications:
    - target: {fileID: %d, guid: b2, type: 3}
      propertyPath: m_IsActive
      value: 0
      objectReference: {fileID: 0}
  m_SourcePrefab: {fileID: 100100000, guid: b2, type: 3}
--- !u!1 &%d stripped
GameObject:
  m_CorrespondingSourceObject: {fileID: %d, guid: b2, type: 3}
  m_PrefabInstance: {fileID: 30}
""" % [20 ^ 10, 30 ^ (20 ^ 10), 20 ^ 10])
	var prefabs := Prefabs.new(Assets.new(dir))
	var objs := prefabs.flatten("c3")
	var hat: int = 30 ^ (20 ^ 10)
	check(objs.has(hat) and objs[hat].data.m_Name == "Cap" and objs[hat].data.m_IsActive == "0", "the inner GameObject takes both prefabs' modifications (%s)" % [objs.get(hat, {}).get("data")])
	check(objs[hat].data.m_Component[0].component.fileID == str(30 ^ (20 ^ 11)), "its references take the scene's IDs")
	check(prefabs.missing.is_empty(), "nothing missing")


func _model_objects_keep_their_bindings_and_transforms() -> void:
	var assets := Assets.new(ProjectSettings.globalize_path("res://../tests/avatars"))
	var prefabs := Prefabs.new(assets)
	var model := prefabs.model(assets.of(["fbx"])[0])
	var bound := 0
	var positioned := 0
	for id: int in model.objects:
		var object: Dictionary = model.objects[id]
		if object.type == "Transform" and object.has("node"):
			var expected: Transform3D = model.state.get_nodes()[object.node].xform
			check(UnityAvatar._local(object.data).is_equal_approx(expected), "generated source transforms preserve the model's position and rotation")
			positioned += int(not expected.origin.is_zero_approx())
		if object.type == "SkinnedMeshRenderer":
			var bones := Yaml.list(object.data.get("m_Bones"))
			check(not bones.is_empty(), "a model's skinned renderer retains its bone references")
			for bone: Dictionary in bones:
				check(model.objects.has(Yaml.file_id(bone)), "generated bone references resolve to source transforms")
			bound += bones.size()
	check(positioned > 0 and bound > 0, "the model fixture exercises both nonzero positions and skin bindings")
	(model.scene as Node).free()


func _material_properties_read_either_layout() -> void:
	var lines: Array[String] = []
	lines.assign("""Material:
  m_SavedProperties:
    m_TexEnvs:
    - _MainTex:
        m_Texture: {fileID: 2800000, guid: t1, type: 3}
        m_Scale: {x: 2, y: 1}
    m_Floats:
    - first:
        name: _Mode
      second: 1""".split("\n"))
	var saved: Dictionary = Yaml.document(lines).Material.m_SavedProperties
	check(Materials._properties(saved.m_TexEnvs)._MainTex.m_Texture.guid == "t1", "a property list of one-key entries")
	check(Materials._properties(saved.m_Floats)._Mode == "1", "a property list of first/second pairs")


## A material draws the faces its shader's `Cull` names, from the property it reads, whatever stale culling properties
## the material still saves; the SDK's shaders, absent from packages, read theirs by GUID.
func _materials_cull_as_their_shader_reads() -> void:
	var dir := ProjectSettings.globalize_path("user://cull")
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(name: String, guid: String, text: String) -> void:
		FileAccess.open(dir.path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	write.call("property.shader", "property", 'Shader "Fixture" { Properties { _Sides ("Cull Off", Int) = 2 } SubShader { // Cull Off\n /* Cull Front */ Pass { Cull [_Sides] } Pass { Cull Front } } }')
	write.call("off.shader", "off", 'Shader "Fixture/Off" { SubShader { Pass { cull off } } }')
	write.call("plain.shader", "plain", 'Shader "Fixture/Plain" { SubShader { Pass { } } }')
	var material := func(name: String, shader: String, floats: String) -> void:
		write.call(name + ".mat", name, "Material:\n  m_Shader: {fileID: 4800000, guid: %s, type: 3}\n  m_SavedProperties:\n    m_Floats:\n%s" % [shader, floats])
	material.call("both", "property", "    - _Cull: 2\n    - _Sides: 0\n")
	material.call("front", "property", "    - _Sides: 1\n")
	material.call("fixed", "off", "    - _Cull: 2\n")
	material.call("default", "plain", "    - _Cull: 0\n")
	material.call("sdk", "e765db0afa7ecfc44ade2e4e2491f65a", "    - _Cull: 2\n    - _Culling: 0\n")
	material.call("absent", "0123456789abcdef0123456789abcdef", "    - _Cull: 0\n")
	material.call("builtin", "0000000000000000f000000000000000", "    - _Cull: 0\n")
	write.call("ints.mat", "ints", "Material:\n  m_Shader: {fileID: 4800000, guid: property, type: 3}\n  m_SavedProperties:\n    m_Ints:\n    - _Sides: 0\n    m_Floats:\n    - _Sides: 2\n")
	var materials := Materials.new(Assets.new(dir))
	var cull := func(guid: String) -> int: return materials.materials[materials.use({"guid": guid}, Color.WHITE)].cull
	check(cull.call("both") == Materials.Cull.OFF, "the first pass's cull property decides, past comments and names, not a stale _Cull")
	check(cull.call("ints") == Materials.Cull.OFF, "an Int property reads from the saved ints")
	check(cull.call("builtin") == Materials.Cull.BACK, "a built-in shader culls back faces whatever _Cull says")
	check(cull.call("front") == Materials.Cull.FRONT, "front culling reads as front")
	check(cull.call("fixed") == Materials.Cull.OFF, "a fixed Cull Off draws both sides")
	check(cull.call("default") == Materials.Cull.BACK, "a shader naming no Cull culls back faces")
	check(cull.call("sdk") == Materials.Cull.OFF, "the SDK's Toon Standard reads _Culling")
	check(cull.call("absent") == Materials.Cull.OFF, "a shader missing from the package reads _Cull")
	materials.pack(materials.materials.keys())
	var sided := materials.atlas_materials()
	check(sided[0].cull_mode == BaseMaterial3D.CULL_BACK and sided[1].cull_mode == BaseMaterial3D.CULL_DISABLED and sided[0].albedo_texture == sided[1].albedo_texture, "one atlas, drawn one-sided and two-sided")
## A material blends exactly when its shader's destination blend factor is not Zero, whatever its queue says, by its
## colour's alpha plus Poiyomi's Alpha Mod, and writes depth as its _ZWrite says; the atlas draws its faces blended.
func _materials_blend_as_their_shader_blends() -> void:
	var dir := ProjectSettings.globalize_path("user://blend")
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(name: String, guid: String, text: String) -> void:
		FileAccess.open(dir.path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	write.call("toon.shader", "toon", 'Shader "Fixture/Toon" { Properties { _Color ("Color", Color) = (1, 1, 1, 1) _AlphaMod ("Alpha Mod", Range(-1, 1)) = 0 _SrcBlend ("Src", Int) = 1 _DstBlend ("Dst", Int) = 0 _ZWrite ("ZWrite", Int) = 1 } SubShader { Pass { Blend [_SrcBlend] [_DstBlend] ZWrite [_ZWrite] } } }')
	write.call("plain.shader", "plain", 'Shader "Fixture/Plain" { SubShader { Pass { } } }')
	var material := func(name: String, shader: String, queue: int, alpha: float, floats: String) -> void:
		write.call(name + ".mat", name, "Material:\n  m_Shader: {fileID: 4800000, guid: %s, type: 3}\n  m_CustomRenderQueue: %d\n  m_SavedProperties:\n    m_Floats:\n%s    m_Colors:\n    - _Color: {r: 1, g: 1, b: 1, a: %s}\n" % [shader, queue, floats, alpha])
	material.call("late", "toon", 3000, 1.0, "    - _SrcBlend: 1\n    - _DstBlend: 0\n    - _ZWrite: 1\n")
	material.call("veil", "toon", 3000, 0.51, "    - _SrcBlend: 1\n    - _DstBlend: 10\n    - _ZWrite: 0\n")
	material.call("sheer", "toon", 2460, 1.0, "    - _SrcBlend: 5\n    - _DstBlend: 10\n    - _ZWrite: 1\n    - _AlphaMod: -0.15\n")
	material.call("stale", "plain", 2000, 1.0, "    - _DstBlend: 10\n")
	var materials := Materials.new(Assets.new(dir))
	var of := func(guid: String) -> Dictionary: return materials.materials[materials.use({"guid": guid}, Color.WHITE)]
	check(of.call("late").alpha != Materials.Alpha.BLEND, "a shader blending One Zero draws opaque from the transparent queue")
	check(of.call("stale").alpha != Materials.Alpha.BLEND, "a saved blend factor the shader does not declare is stale")
	check(Materials.pass_of(of.call("veil")) == Materials.Pass.BLENDED, "a blend over OneMinusSrcAlpha with ZWrite off draws blended")
	check(Materials.pass_of(of.call("sheer")) == Materials.Pass.BLENDED_DEPTH and is_equal_approx(of.call("sheer").alpha_mod, -0.15), "ZWrite on blends writing depth, its Alpha Mod read")
	materials.pack(materials.materials.keys())
	var alpha := func(guid: String) -> float:
		var cell: Rect2i = of.call(guid).cell
		return materials.atlas.get_pixelv(cell.position + cell.size / 2).a
	check(absf(alpha.call("veil") - 0.51) < 0.01 and absf(alpha.call("sheer") - 0.85) < 0.01, "the atlas keeps the blended alphas, Alpha Mod added: %.3f, %.3f" % [alpha.call("veil"), alpha.call("sheer")])
	var drawn := materials.atlas_materials()
	check(drawn.size() == 2 * Materials.PASSES, "one atlas material for each pass on each side")
	var blended := drawn[2 * Materials.Pass.BLENDED]
	var depth := drawn[2 * Materials.Pass.BLENDED_DEPTH + 1]
	check(blended.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and blended.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY and not blended.get_meta("extras").depthWrite, "blended faces draw blended, writing no depth")
	check(depth.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and depth.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS and depth.get_meta("extras").depthWrite and depth.cull_mode == BaseMaterial3D.CULL_DISABLED, "depth-written blended faces say so in their glTF extras")


## A material naming one of the VRChat SDK's shaders, which a package never carries, reads that shader's name and
## properties as if the package held it.
func _an_sdk_shader_the_package_omits_is_known() -> void:
	var dir := ProjectSettings.globalize_path("user://sdk-shader")
	DirAccess.make_dir_recursive_absolute(dir)
	FileAccess.open(dir.path_join("toon.mat"), FileAccess.WRITE).store_string("Material:\n  m_Shader: {fileID: 4800000, guid: e765db0afa7ecfc44ade2e4e2491f65a, type: 3}\n")
	FileAccess.open(dir.path_join("toon.mat.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: toon\n")
	var materials := Materials.new(Assets.new(dir))
	var m: Dictionary = materials.materials[materials.use({"guid": "toon"}, Color.WHITE)]
	check(m.shader == "VRChat/Mobile/Toon Standard", "the SDK shader is known by name: %s" % m.shader)
	check(m.properties.has("_HueShift") and m.properties.has("_Color"), "the SDK shader's declared properties are known")


func _outside_constraints_place() -> void:
	var objs := {
		1: {"type": "GameObject", "data": {"m_Component": [{"component": {"fileID": "2"}}]}},
		2: {"type": "ParentConstraint", "data": {"m_Sources": [{"sourceTransform": {"fileID": "7", "guid": "elsewhere"}, "weight": "1"}]}},
		3: {"type": "GameObject", "data": {"m_Component": [{"component": {"fileID": "4"}}]}},
		4: {"type": "MonoBehaviour", "data": {"PositionAtRest": {}, "Sources": {"source0": {"SourceTransform": {"fileID": "9"}, "Weight": "1"}, "source1": {"SourceTransform": {"fileID": "8"}, "Weight": "0"}}}},
	}
	var inside := {9: true}
	check(not UnityAvatar._constrained(objs, 1, inside), "native constraints retain their rendered subtree for runtime evaluation")
	check(not UnityAvatar._constrained(objs, 3, inside), "the avatar's own source, and an unweighted outside one, do not")


## A PhysBone whose root has two children: under the default multiChildType the root stays still and each branch is its
## own chain; under First the first branch's chain turns the root.
func _a_branching_physbone_root_stays_still() -> void:
	var sk := Skeleton3D.new()
	var objs := {}
	for bone: Array in [[10, "Root", 0], [11, "A", 10], [12, "B", 10], [13, "A2", 11], [14, "B2", 12]]:
		sk.add_bone(bone[1])
		if bone[2] != 0:
			sk.set_bone_parent(sk.get_bone_count() - 1, bone[2] - 10)
		objs[bone[0] + 100] = {"type": "GameObject", "data": {"m_Name": bone[1]}}
		objs[bone[0]] = {"type": "Transform", "data": {"m_GameObject": {"fileID": str(bone[0] + 100)}, "m_Father": {"fileID": str(bone[2])}}}
	objs[99] = objs[10]
	var chains := func(multi_child: String) -> Array:
		objs[20] = {"type": "MonoBehaviour", "data": {"pull": "0.2", "rootTransform": {"fileID": "99"}, "multiChildType": multi_child}}
		var out := []
		for spring: Dictionary in UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).springs:
			out.append(spring.joints.map(func(j: Dictionary) -> String: return sk.get_bone_name(j.node)))
		out.sort()
		return out
	check(chains.call("0") == [["A", "A2"], ["B", "B2"]], "under Ignore the root is in no chain: %s" % [chains.call("0")])
	check(chains.call("1") == [["B", "B2"], ["Root", "A", "A2"]], "under First the first branch turns the root: %s" % [chains.call("1")])
	objs[21] = {"type": "MonoBehaviour", "data": {"pull": "0.2", "rootTransform": {"fileID": "11"}}}
	check(chains.call("1") == [["A", "A2"], ["Root", "B", "B2"]], "a nested component owns its subtree, including when the parent names an alias")
	objs[20].data.ignoreOtherPhysBones = "0"
	var shared: Array = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).springs
	check(shared.size() == 3, "an explicit opt-out retains overlapping source components")
	objs[110].data.m_Component = [{"component": {"fileID": "10"}}]
	objs[190] = objs[110]
	objs[20].data.rootTransform.fileID = "0"
	objs[20].data.m_GameObject = {"fileID": "190"}
	check(UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).springs.size() == 3, "an implicit root resolves its GameObject alias before checking avatar membership")
	var branches := Skeleton3D.new()
	for name: String in ["A", "A2", "B", "B2"]:
		branches.add_bone(name)
	branches.set_bone_parent(1, 0)
	branches.set_bone_parent(3, 2)
	objs.erase(21)
	objs[20].data.multiChildType = "0"
	var report := {}
	var organizational: Array = UnityAvatar._springs(objs, 10, branches, {}, 1.0, report).springs
	check(organizational.size() == 2, "an organizational root absent from the output skeleton still owns its child chains")
	check(JSON.parse_string(report["spring coverage"])[0].reason == "", "a represented organizational root is not reported as missing")
	branches.free()
	sk.free()


## A chain's colliders arrive as the source shapes them: one on a bone's unweighted child sits on that bone where the
## child puts it, turned and scaled by it; inside spheres and planes, which VRM's own shapes cannot hold, ride in
## VRMC_springBone_extended_collider over a point; a DynamicBone collider lies along its direction.
func _colliders_keep_their_shape_side_and_bone() -> void:
	var sk := Skeleton3D.new()
	sk.add_bone("Head")
	sk.add_bone("Hair")
	sk.set_bone_parent(1, 0)
	sk.add_bone("Hair2")
	sk.set_bone_parent(2, 1)
	var turn := sin(PI / 4.0)
	var objs := {
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "110"}, "m_Father": {"fileID": "0"}}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "111"}, "m_Father": {"fileID": "10"}}},
		12: {"type": "Transform", "data": {"m_GameObject": {"fileID": "112"}, "m_Father": {"fileID": "11"}}},
		30: {"type": "Transform", "data": {"m_GameObject": {"fileID": "130"}, "m_Father": {"fileID": "10"}, "m_LocalPosition": {"x": "0.1", "y": "0.2", "z": "0"}, "m_LocalRotation": {"x": "0", "y": "0", "z": str(turn), "w": str(turn)}, "m_LocalScale": {"x": "2", "y": "2", "z": "2"}}},
		110: {"type": "GameObject", "data": {"m_Name": "Head", "m_Component": [{"component": {"fileID": "10"}}]}},
		111: {"type": "GameObject", "data": {"m_Name": "Hair", "m_Component": [{"component": {"fileID": "11"}}]}},
		112: {"type": "GameObject", "data": {"m_Name": "Hair2", "m_Component": [{"component": {"fileID": "12"}}]}},
		130: {"type": "GameObject", "data": {"m_Name": "Head Collider", "m_Component": [{"component": {"fileID": "30"}}]}},
		40: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "130"}, "rootTransform": {"fileID": "0"}, "shapeType": "1", "insideBounds": "0", "radius": "0.05", "height": "0.3", "position": {"x": "0", "y": "0.01", "z": "0"}, "rotation": {"x": "0", "y": "0", "z": "0", "w": "1"}}},
		41: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "130"}, "rootTransform": {"fileID": "10"}, "shapeType": "0", "insideBounds": "1", "radius": "0.2", "height": "0", "position": {"x": "0", "y": "0", "z": "0"}}},
		42: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "130"}, "rootTransform": {"fileID": "10"}, "shapeType": "2", "insideBounds": "0", "radius": "0", "height": "0", "position": {"x": "0", "y": "-0.1", "z": "0"}}},
		43: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "110"}, "m_Center": {"x": "0.1", "y": "0", "z": "0"}, "m_Direction": "0", "m_Radius": "0.05", "m_Height": "0.3", "m_Bound": "0"}},
		20: {"type": "MonoBehaviour", "data": {"pull": "0.2", "rootTransform": {"fileID": "11"}, "colliders": [{"fileID": "40"}, {"fileID": "41"}, {"fileID": "42"}, {"fileID": "43"}]}},
	}
	var report := {}
	var out: Dictionary = UnityAvatar._springs(objs, 10, sk, {}, 1.0, report)
	var springs: Array = out.get("springs", [])
	check(springs.size() == 1 and springs[0].has("colliderGroups"), "the chain keeps a collider group: %s" % [springs])
	if springs.size() != 1 or not springs[0].has("colliderGroups"):
		sk.free()
		return
	var listed: Array = out.colliderGroups[springs[0].colliderGroups[0]].colliders.map(func(i: int) -> Dictionary: return out.colliders[i])
	check(listed.size() == 4, "all four of the chain's colliders arrive: %s" % [report.get("spring components")])
	if listed.size() != 4:
		sk.free()
		return
	var near := func(a: Array, b: Vector3) -> bool: return Vector3(a[0], a[1], a[2]).is_equal_approx(b)
	var capsule: Dictionary = listed[0].shape.get("capsule", {})
	check(listed[0].node == 0 and not capsule.is_empty(), "the child's capsule sits on the bone above it: %s" % [listed[0]])
	if not capsule.is_empty():
		check(near.call(capsule.offset, Vector3(-0.28, 0.2, 0)) and near.call(capsule.tail, Vector3(0.12, 0.2, 0)), "turned a quarter about Z, the capsule lies along X, its ends where the child puts them: %s" % [capsule])
		check(is_equal_approx(capsule.radius, 0.1), "and its radius takes the child's scale: %s" % [capsule.radius])
	var inside: Dictionary = listed[1].get("extensions", {}).get("VRMC_springBone_extended_collider", {}).get("shape", {}).get("sphere", {})
	check(inside.get("inside", false) and is_equal_approx(inside.get("radius", 0.0), 0.2), "an inside sphere keeps its side in the extension: %s" % [listed[1]])
	check(listed[1].shape.sphere.radius == 0.0, "over a point where the extension is not read")
	var plane: Dictionary = listed[2].get("extensions", {}).get("VRMC_springBone_extended_collider", {}).get("shape", {}).get("plane", {})
	check(not plane.is_empty() and near.call(plane.normal, Vector3.UP) and near.call(plane.offset, Vector3(0, -0.1, 0)), "a plane faces its transform's up: %s" % [listed[2]])
	var legacy: Dictionary = listed[3].shape.get("capsule", {})
	check(not legacy.is_empty() and near.call(legacy.offset, Vector3(0, 0, 0)) and near.call(legacy.tail, Vector3(-0.2, 0, 0)), "a DynamicBone collider lies along its direction, X mirrored: %s" % [listed[3]])
	sk.free()


## A collider keeps the offset from its bone that Unity's transforms give it, wherever the output rest poses that bone.
func _a_collider_rides_its_bone_where_unity_places_it() -> void:
	var sk := Skeleton3D.new()
	sk.add_bone("Chest")
	sk.add_bone("Breast")
	sk.set_bone_parent(1, 0)
	sk.set_bone_rest(0, Transform3D(Basis(Vector3.BACK, 0.02), Vector3(0.02, 1.0, 0)))
	sk.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.05)))
	var objs := {
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "110"}, "m_Father": {"fileID": "0"}, "m_LocalPosition": {"x": "0", "y": "1", "z": "0"}}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "111"}, "m_Father": {"fileID": "10"}, "m_LocalPosition": {"x": "0", "y": "0", "z": "0.05"}}},
		30: {"type": "Transform", "data": {"m_GameObject": {"fileID": "130"}, "m_Father": {"fileID": "10"}, "m_LocalPosition": {"x": "0", "y": "0.03", "z": "0.06"}}},
		110: {"type": "GameObject", "data": {"m_Name": "Chest", "m_Component": [{"component": {"fileID": "10"}}]}},
		111: {"type": "GameObject", "data": {"m_Name": "Breast", "m_Component": [{"component": {"fileID": "11"}}]}},
		130: {"type": "GameObject", "data": {"m_Name": "Chest Sphere", "m_Component": [{"component": {"fileID": "30"}}]}},
		40: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "130"}, "rootTransform": {"fileID": "0"}, "shapeType": "0", "insideBounds": "1", "radius": "0.1", "height": "0", "position": {"x": "0", "y": "0", "z": "0"}}},
		20: {"type": "MonoBehaviour", "data": {"pull": "0.2", "rootTransform": {"fileID": "11"}, "endpointPosition": {"x": "0", "y": "0.04", "z": "0"}, "colliders": [{"fileID": "40"}]}},
	}
	var out: Dictionary = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {})
	var colliders: Array = out.get("colliders", [])
	check(colliders.size() == 1, "the sphere arrives: %s" % [out])
	if colliders.size() == 1:
		var offset: Array = colliders[0].extensions.VRMC_springBone_extended_collider.shape.sphere.offset
		check(Vector3(offset[0], offset[1], offset[2]).is_equal_approx(Vector3(0, 0.03, 0.06)), "the sphere sits where Unity puts it from the chest, not shifted by the rest's own offset and turn: %s" % [offset])
	sk.free()


## A PhysBone or collider runs as Unity runs it when the avatar loads, or under the menu switches that turn on its own
## flag and each inactive GameObject above it; one nothing turns on stays out.
func _physics_runs_as_the_menu_switches_it() -> void:
	var sk := Skeleton3D.new()
	for name: String in ["Chest", "Left", "Right", "Far"]:
		sk.add_bone(name)
		sk.set_bone_parent(sk.get_bone_count() - 1, 0 if name != "Chest" else -1)
	var transform := func(go: int, father: int) -> Dictionary: return {"type": "Transform", "data": {"m_GameObject": {"fileID": str(go)}, "m_Father": {"fileID": str(father)}}}
	var object := func(name: String, t: int, active := "1") -> Dictionary: return {"type": "GameObject", "data": {"m_Name": name, "m_IsActive": active, "m_Component": [{"component": {"fileID": str(t)}}]}}
	var sphere := func(go: int, enabled: String, radius: String) -> Dictionary: return {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": str(go)}, "m_Enabled": enabled, "rootTransform": {"fileID": "0"}, "shapeType": "0", "insideBounds": "0", "radius": radius, "height": "0", "position": {"x": "0", "y": "0", "z": "0"}}}
	var physbone := func(go: int, enabled: String, root: int, colliders: Array) -> Dictionary: return {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": str(go)}, "m_Enabled": enabled, "pull": "0.2", "rootTransform": {"fileID": str(root)}, "endpointPosition": {"x": "0", "y": "0.04", "z": "0"}, "colliders": colliders.map(func(c: int) -> Dictionary: return {"fileID": str(c)})}}
	var objs := {
		10: transform.call(110, 0), 11: transform.call(111, 10), 12: transform.call(112, 10), 30: transform.call(130, 10), 31: transform.call(131, 10), 32: transform.call(132, 31),
		110: object.call("Chest", 10), 111: object.call("Left", 11), 112: object.call("Right", 12), 130: object.call("Hidden Sphere", 30, "0"), 131: object.call("Off Parent", 31, "0"), 132: object.call("Far", 32),
		40: sphere.call(130, "1", "0.1"), 41: sphere.call(110, "0", "0.2"), 42: sphere.call(110, "1", "0.05"),
		20: physbone.call(111, "1", 11, [40, 41, 42]), 21: physbone.call(112, "0", 12, []), 22: physbone.call(132, "1", 32, []),
	}
	var roots := func(out: Dictionary) -> Array:
		var names: Array = out.springs.map(func(s: Dictionary) -> String: return sk.get_bone_name(s.joints[0].node))
		names.sort()
		return names
	var radii := func(out: Dictionary) -> Array:
		var left: Dictionary = out.springs.filter(func(s: Dictionary) -> bool: return sk.get_bone_name(s.joints[0].node) == "Left")[0]
		var listed: Array = out.colliderGroups[left.colliderGroups[0]].colliders.map(func(c: int) -> float: return snappedf(out.colliders[c].shape.sphere.radius, 0.01))
		listed.sort()
		return listed
	var fixed: Dictionary = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {})
	check(roots.call(fixed) == ["Left"], "without the menu only what runs at load is carried: %s" % [roots.call(fixed)])
	check(radii.call(fixed) == [0.05], "and the one collider that runs: %s" % [fixed.colliders])
	check(fixed.switched == {"springs": [], "colliders": []}, "nothing waits on a switch: %s" % [fixed.switched])
	var switched: Dictionary = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}, {"by_object": {130: 0, 21: 1, 131: 2}})
	check(roots.call(switched) == ["Far", "Left", "Right"], "the menu's PhysBones are carried: %s" % [roots.call(switched)])
	check(radii.call(switched) == [0.05, 0.1], "so is the collider it shows, and not the one it never enables: %s" % [switched.colliders])
	var waits: Array = switched.switched.springs.map(func(s: Dictionary) -> Array: return [s.joints[0], s.when])
	waits.sort()
	check(waits == [["Far", [[2, 1]]], ["Right", [[1, 1]]]], "each switched PhysBone waits on its own flag or its object's parent: %s" % [switched.switched.springs])
	var shown: Array = switched.switched.colliders
	check(shown.size() == 1 and shown[0].when == [[0, 1]] and is_equal_approx(switched.colliders[shown[0].collider].shape.sphere.radius, 0.1), "the shown sphere waits on its object: %s" % [shown])
	sk.free()


## A collider whose transform the menu moves rides a bone of its own, placed where Unity places the transform.
func _a_moved_collider_rides_its_own_bone() -> void:
	var sk := Skeleton3D.new()
	sk.add_bone("Chest")
	sk.add_bone("Breast")
	sk.set_bone_parent(1, 0)
	sk.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	sk.set_meta("unity_bones", {110: 0, 111: 1})
	var objs := {
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "110"}, "m_Father": {"fileID": "0"}, "m_LocalPosition": {"x": "0", "y": "1", "z": "0"}}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "111"}, "m_Father": {"fileID": "10"}}},
		30: {"type": "Transform", "data": {"m_GameObject": {"fileID": "130"}, "m_Father": {"fileID": "10"}, "m_LocalPosition": {"x": "0", "y": "0.03", "z": "0.06"}}},
		110: {"type": "GameObject", "data": {"m_Name": "Chest", "m_Component": [{"component": {"fileID": "10"}}]}},
		111: {"type": "GameObject", "data": {"m_Name": "Breast", "m_Component": [{"component": {"fileID": "11"}}]}},
		130: {"type": "GameObject", "data": {"m_Name": "Lifter", "m_Component": [{"component": {"fileID": "30"}}]}},
		40: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "130"}, "rootTransform": {"fileID": "0"}, "shapeType": "0", "insideBounds": "0", "radius": "0.02", "height": "0", "position": {"x": "0", "y": "0", "z": "0"}}},
		20: {"type": "MonoBehaviour", "data": {"pull": "0.2", "rootTransform": {"fileID": "11"}, "endpointPosition": {"x": "0", "y": "0.04", "z": "0"}, "colliders": [{"fileID": "40"}]}},
	}
	var out: Dictionary = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}, {}, {30: true})
	var lifter := sk.find_bone("Lifter")
	check(lifter >= 0 and sk.get_bone_parent(lifter) == 0 and sk.get_bone_rest(lifter).origin.is_equal_approx(Vector3(0, 0.03, 0.06)), "the moved transform becomes a bone under the chest where Unity places it")
	check(out.colliders.size() == 1 and out.colliders[0].node == lifter and Vector3(out.colliders[0].shape.sphere.offset[0], out.colliders[0].shape.sphere.offset[1], out.colliders[0].shape.sphere.offset[2]).is_zero_approx(), "the collider sits on it: %s" % [out.colliders])
	sk.free()


## A PhysBone of one bone with an endpoint swings about that endpoint, a bone added past the leaf at its offset in the
## leaf's axes (X mirrored) and scale; without one the bone has no chain.
func _a_physbone_ends_at_its_endpoint() -> void:
	var sk := Skeleton3D.new()
	sk.add_bone("Ear")
	var objs := {
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "110"}, "m_Father": {"fileID": "0"}, "m_LocalScale": {"x": "2", "y": "2", "z": "2"}}},
		110: {"type": "GameObject", "data": {"m_Name": "Ear"}},
	}
	objs[20] = {"type": "MonoBehaviour", "data": {"pull": "0.2", "rootTransform": {"fileID": "10"}, "endpointPosition": {"x": "0", "y": "0", "z": "0"}}}
	check(UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).is_empty(), "a bone with no endpoint has no chain")
	objs[20].data.endpointPosition = {"x": "0.01", "y": "0.05", "z": "0"}
	objs[20].data.gravity = "-0.01"
	var definition: Dictionary = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {})
	var springs: Array = definition.get("springs", [])
	var read: Array = SpringDefinition.read({"nodes": [{}, {}], "extensions": {"VRMC_springBone": definition}}).springs
	check(read.size() == 1 and read[0].joints.all(func(j: Dictionary) -> bool: return j.gravity.is_equal_approx(Vector3(0, 0.01, 0))), "a negative PhysBone gravity pulls up: %s" % [read])
	var joints: Array = springs[0].joints if springs.size() == 1 else []
	check(joints.size() == 2 and joints[0].node == 0, "the bone's chain runs to its endpoint: %s" % [springs])
	if joints.size() == 2:
		check(sk.get_bone_parent(joints[1].node) == 0 and sk.get_bone_rest(joints[1].node).origin.is_equal_approx(Vector3(-0.02, 0.1, 0)), "the endpoint is a bone under it at its offset: %s" % sk.get_bone_rest(joints[1].node).origin)
	sk.free()


## A PhysBone's limit rides on each of its joints, its angles in degrees and its limitRotation turned into the joint's
## own axes (X mirrored), and survives the reading the converter writes the springs back from.
func _a_physbone_carries_its_limit() -> void:
	var sk := Skeleton3D.new()
	sk.add_bone("Ear")
	sk.add_bone("Tip")
	sk.set_bone_parent(1, 0)
	sk.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)))
	var objs := {
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "110"}, "m_Father": {"fileID": "0"}}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "111"}, "m_Father": {"fileID": "10"}, "m_LocalPosition": {"x": "0", "y": "0.1", "z": "0"}}},
		110: {"type": "GameObject", "data": {"m_Name": "Ear"}},
		111: {"type": "GameObject", "data": {"m_Name": "Tip"}},
		20: {"type": "MonoBehaviour", "data": {"pull": "0.2", "rootTransform": {"fileID": "10"}, "limitType": "3", "maxAngleX": "14", "maxAngleZ": "16", "limitRotation": {"x": "32", "y": "0", "z": "0"}}},
	}
	var definition: Dictionary = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {})
	var joints: Array = definition.springs[0].joints if definition.get("springs", []).size() == 1 else []
	check(joints.size() == 2, "the bone and its child make the chain: %s" % [definition])
	if joints.size() == 2:
		var limit: Dictionary = joints[0].get("extras", {}).get("limit", {})
		check(limit.get("shape") == "polar" and is_equal_approx(limit.get("x", 0.0), 14.0) and is_equal_approx(limit.get("z", 0.0), 16.0), "the polar limit's angles are carried: %s" % [joints[0]])
		var q: Array = limit.get("rotation", [])
		check(q.size() == 4 and Quaternion(q[0], q[1], q[2], q[3]).is_equal_approx(Quaternion(Vector3.RIGHT, deg_to_rad(32.0))), "its turn about X is carried into the joint's axes: %s" % [q])
		var read: Array = UnityAvatar._read_springs(definition, [{}, {}]).springs
		check(read.size() == 1 and read[0].joints[0].get("extras") == joints[0].extras, "reading the springs keeps each joint's limit: %s" % [read])
	# A bone along Unity's X, its limit turned about X then Z: VRChat's CalcLimitAxis turns Y to the bone first, and
	# applies limitRotation's angles about X, then Y, then Z.
	objs[11].data.m_LocalPosition = {"x": "0.1", "y": "0", "z": "0"}
	sk.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(-0.1, 0, 0)))
	objs[20].data.limitType = "2"
	objs[20].data.limitRotation = {"x": "30", "y": "0", "z": "40"}
	var turned: Array = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).springs[0].joints
	var unity := Quaternion(Vector3.UP, Vector3.RIGHT) * Quaternion(Vector3.BACK, deg_to_rad(40.0)) * Quaternion(Vector3.RIGHT, deg_to_rad(30.0))
	var mirrored := func(v: Vector3) -> Vector3: return Vector3(-v.x, v.y, v.z)
	var r: Array = turned[0].get("extras", {}).get("limit", {}).get("rotation", [0, 0, 0, 1])
	var frame := Quaternion(r[0], r[1], r[2], r[3])
	check((frame * Vector3.UP).is_equal_approx(mirrored.call(unity * Vector3.UP)), "the limit's axis is VRChat's, in the joint's axes: %s vs %s" % [frame * Vector3.UP, mirrored.call(unity * Vector3.UP)])
	check(is_equal_approx(absf((frame * Vector3.RIGHT).dot(mirrored.call(unity * Vector3.RIGHT))), 1.0), "and its hinge turns across VRChat's X: %s vs %s" % [frame * Vector3.RIGHT, mirrored.call(unity * Vector3.RIGHT)])
	objs[20].data.limitType = "0"
	var free: Array = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).springs[0].joints
	check(not free[0].get("extras", {}).has("limit"), "a PhysBone without a limit carries none: %s" % [free])
	sk.free()


## A PhysBone's limit angles and limitRotation are each scaled by their curves at the bone's place down the chain, as
## VRChat's CalcMaxAngle and CalcLimitRotation take CalcBoneRatio: a curve at 0 at the root gives the root no swing on that axis.
func _a_physbone_limit_follows_its_curves_down_the_chain() -> void:
	var sk := Skeleton3D.new()
	for name in ["Root", "Mid", "Tip"]:
		sk.add_bone(name)
	for i in [1, 2]:
		sk.set_bone_parent(i, i - 1)
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)))
	var ramp := {"m_Curve": [{"time": "0", "value": "0", "inSlope": "0", "outSlope": "1"}, {"time": "1", "value": "1", "inSlope": "1", "outSlope": "0"}]}
	var objs := {
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "110"}, "m_Father": {"fileID": "0"}}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "111"}, "m_Father": {"fileID": "10"}, "m_LocalPosition": {"x": "0", "y": "0.1", "z": "0"}}},
		12: {"type": "Transform", "data": {"m_GameObject": {"fileID": "112"}, "m_Father": {"fileID": "11"}, "m_LocalPosition": {"x": "0", "y": "0.1", "z": "0"}}},
		110: {"type": "GameObject", "data": {"m_Name": "Root"}},
		111: {"type": "GameObject", "data": {"m_Name": "Mid"}},
		112: {"type": "GameObject", "data": {"m_Name": "Tip"}},
		20: {"type": "MonoBehaviour", "data": {"pull": "0.2", "rootTransform": {"fileID": "10"}, "limitType": "3", "maxAngleX": "25", "maxAngleXCurve": ramp, "maxAngleZ": "40",
			"limitRotation": {"x": "32", "y": "0", "z": "0"}, "limitRotationXCurve": ramp}},
	}
	var joints: Array = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).springs[0].joints
	var limits: Array = joints.slice(0, 2).map(func(j: Dictionary) -> Dictionary: return j.get("extras", {}).get("limit", {}))
	check(limits.size() == 2 and is_equal_approx(limits[0].get("x", -1.0), 0.0) and is_equal_approx(limits[1].get("x", -1.0), 25.0), "the X angle follows its curve, none at the root: %s" % [limits])
	check(limits.size() == 2 and is_equal_approx(limits[0].get("z", -1.0), 40.0) and is_equal_approx(limits[1].get("z", -1.0), 40.0), "the Z angle without a curve stays whole: %s" % [limits])
	var turn := func(l: Dictionary) -> Quaternion: var q: Array = l.get("rotation", [0, 0, 0, 1]); return Quaternion(q[0], q[1], q[2], q[3])
	check(limits.size() == 2 and turn.call(limits[0]).is_equal_approx(Quaternion.IDENTITY) and turn.call(limits[1]).is_equal_approx(Quaternion(Vector3.RIGHT, deg_to_rad(32.0))), "the turn follows its curve: %s" % [limits])
	sk.free()


## Every joint of a PhysBone carries the source's own settings for the runtime to step it as VRChat does: each curve
## evaluated at the bone's place down the chain as VRChat's Calc functions place it, the radius at both its ends, and
## which bone ends at the endpoint.
func _a_physbone_carries_its_settings_bone_by_bone() -> void:
	var sk := Skeleton3D.new()
	for name in ["Root", "Mid", "Tip"]:
		sk.add_bone(name)
	for i in [1, 2]:
		sk.set_bone_parent(i, i - 1)
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)))
	var ramp := func(a: float, b: float) -> Dictionary: return {"m_Curve": [{"time": "0", "value": str(a), "inSlope": "0", "outSlope": str(b - a)}, {"time": "1", "value": str(b), "inSlope": str(b - a), "outSlope": "0"}]}
	var objs := {
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "110"}, "m_Father": {"fileID": "0"}, "m_LocalScale": {"x": "2", "y": "2", "z": "2"}}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "111"}, "m_Father": {"fileID": "10"}, "m_LocalPosition": {"x": "0", "y": "0.1", "z": "0"}, "m_LocalScale": {"x": "1", "y": "1.5", "z": "1"}}},
		12: {"type": "Transform", "data": {"m_GameObject": {"fileID": "112"}, "m_Father": {"fileID": "11"}, "m_LocalPosition": {"x": "0", "y": "0.1", "z": "0"}}},
		110: {"type": "GameObject", "data": {"m_Name": "Root"}},
		111: {"type": "GameObject", "data": {"m_Name": "Mid"}},
		112: {"type": "GameObject", "data": {"m_Name": "Tip"}},
		20: {"type": "MonoBehaviour", "data": {"version": "1", "integrationType": "1", "rootTransform": {"fileID": "10"}, "endpointPosition": {"x": "0", "y": "0.05", "z": "0"},
			"pull": "0.2", "pullCurve": ramp.call(1.0, 0.5), "spring": "0.7", "stiffness": "0.1", "gravity": "-0.02", "gravityFalloff": "0.5", "immobileType": "1", "immobile": "0.3",
			"maxStretch": "0.1", "maxSquish": "0.4", "stretchMotion": "0.5", "radius": "0.04", "radiusCurve": ramp.call(1.0, 0.5)}},
	}
	var definition: Dictionary = UnityAvatar._springs(objs, 10, sk, {}, 2.0, {})
	var joints: Array = definition.springs[0].joints if definition.get("springs", []).size() == 1 else []
	check(joints.size() == 4, "the three bones and the endpoint make the chain: %s" % [definition])
	if joints.size() != 4:
		sk.free()
		return
	var bones: Array = joints.slice(0, 3).map(func(j: Dictionary) -> Dictionary: return j.get("extras", {}).get("physbone", {}))
	var first: Dictionary = bones[0]
	check(first.get("version") == "1.1" and first.get("integration") == "advanced" and first.get("immobileType") == "world", "the version, integration and immobile type are carried: %s" % [first])
	check(is_equal_approx(first.get("spring", 0.0), 0.7) and is_equal_approx(first.get("stiffness", 0.0), 0.1) and is_equal_approx(first.get("gravity", 0.0), -0.02) and is_equal_approx(first.get("gravityFalloff", 0.0), 0.5) and is_equal_approx(first.get("immobile", 0.0), 0.3), "the settings without a curve are carried as set, gravity's sign kept: %s" % [first])
	check(is_equal_approx(first.get("maxStretch", 0.0), 0.1) and is_equal_approx(first.get("maxSquish", 0.0), 0.4) and is_equal_approx(first.get("stretchMotion", 0.0), 0.5), "stretch and squish are carried: %s" % [first])
	var pulls: Array = bones.map(func(b: Dictionary) -> float: return b.get("pull", 0.0))
	check(is_equal_approx(pulls[0], 0.2) and is_equal_approx(pulls[1], 0.15) and is_equal_approx(pulls[2], 0.1), "pull follows its curve from the root to the bone before the endpoint: %s" % [pulls])
	var radii: Array = bones.map(func(b: Dictionary) -> Array: return b.get("radius", []))
	var r := func(t: float) -> float: return 0.04 * (1.0 - 0.5 * t)
	var expected := [[r.call(0.0) * 2.0, r.call(1.0 / 3.0) * 3.0], [r.call(1.0 / 3.0) * 3.0, r.call(2.0 / 3.0) * 3.0], [r.call(2.0 / 3.0) * 3.0, r.call(1.0) * 3.0]]
	for i in 3:
		check(radii[i].size() == 2 and is_equal_approx(radii[i][0], expected[i][0]) and is_equal_approx(radii[i][1], expected[i][1]), "bone %d's radius at each end follows the curve to the endpoint, scaled by that end's bone as VRChat scales it: %s vs %s" % [i, radii, expected])
	check(bones.map(func(b: Dictionary) -> int: return b.get("depth", -1)) == [0, 1, 2] and bones.map(func(b: Dictionary) -> bool: return b.get("endpoint", false)) == [false, false, true], "each bone knows its depth and the last ends at the endpoint: %s" % [bones])
	var shared := {"springs": [{"joints": [{"node": 0, "extras": {"physbone": {"pull": 0.066}}}, {"node": 1}]}, {"joints": [{"node": 0, "extras": {"physbone": {"pull": 0.033}}}, {"node": 2}]}], "colliders": []}
	var kept: Array = UnityAvatar._read_springs(shared, [{}, {}, {}]).springs.map(func(c: Dictionary) -> float: return c.joints[0].get("extras", {}).get("physbone", {}).get("pull", 0.0))
	check(kept.size() == 2 and is_equal_approx(kept[0], 0.066) and is_equal_approx(kept[1], 0.033), "two PhysBones sharing a bone each keep their own settings through the read: %s" % [kept])
	objs[20].data.erase("version")
	var unversioned: Dictionary = UnityAvatar._springs(objs, 10, sk, {}, 2.0, {}).springs[0].joints[0].extras.physbone
	check(unversioned.get("version") == "1.0", "a PhysBone saved without a version is 1.0, Unity's default for the field: %s" % [unversioned])
	objs[20].data.erase("endpointPosition")
	var plain: Array = UnityAvatar._springs(objs, 10, sk, {}, 2.0, {}).springs[0].joints
	check(plain.size() == 3 and not plain[1].extras.physbone.endpoint and is_equal_approx(plain[1].extras.physbone.pull, 0.1), "without an endpoint the last bone is a tail and the curve ends a bone sooner: %s" % [plain])
	sk.free()


func _linked_props_keep_their_placement_and_bone_identity() -> void:
	var objs := {}
	for spec: Array in [[10, "Avatar", 0, Vector3.ZERO], [11, "Chest", 10, Vector3.UP], [20, "Wing", 10, Vector3(0.2, 0.4, 0)], [21, "Wing", 20, Vector3(0.1, 0.1, 0)], [22, "Tip", 21, Vector3(0, 0.2, 0)]]:
		objs[spec[0] + 100] = {"type": "GameObject", "guid": "main" if spec[0] == 11 else "prop", "data": {"m_Name": spec[1], "m_Component": [{"component": {"fileID": str(spec[0])}}]}}
		objs[spec[0]] = {"type": "Transform", "data": {"m_GameObject": {"fileID": str(spec[0] + 100)}, "m_Father": {"fileID": str(spec[2])}, "m_LocalPosition": {"x": str(spec[3].x), "y": str(spec[3].y), "z": str(spec[3].z)}}}
	objs[30] = {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "120"}, "references": {"RefIds": [{"type": {"class": "ArmatureLink"}, "data": {"propBone": {"fileID": "120"}, "linkTo": [{"bone": "8", "useBone": "1"}]}}]}}}
	objs[31] = {"type": "MonoBehaviour", "data": {"rootTransform": {"fileID": "21"}, "pull": "0.2"}}
	objs[20].data.m_LocalScale = {"x": "0.5", "y": "0.5", "z": "0.5"}
	objs[24] = {"type": "Transform", "data": {"m_GameObject": {"fileID": "999"}, "m_Father": {"fileID": "10"}}}
	objs[123] = {"type": "GameObject", "data": {"m_Name": "Tip End"}}
	objs[23] = {"type": "Transform", "data": {"m_GameObject": {"fileID": "123"}, "m_Father": {"fileID": "22"}, "m_LocalPosition": {"y": "0.2"}}}
	var before := UnityAvatar._world_transform(objs, 22)
	UnityAvatar._attach_armatures(objs, 10, UnityAvatar._model_bones(objs, 10, "main", []), {"human": {"Chest": "Chest"}}, {})
	check(objs[20].data.m_Father.fileID == "11", "a linked prop follows its authored humanoid target")
	check(UnityAvatar._world_transform(objs, 22).is_equal_approx(before), "reparenting without alignment preserves the prop's world placement")
	var sk := Skeleton3D.new()
	sk.add_bone("Chest")
	var rests: Array[Transform3D] = [Transform3D(Basis(Vector3.UP, 0.1), Vector3.UP)]
	sk.set_bone_rest(0, rests[0])
	sk.set_meta("unity_bones", {111: 0})
	var tip := UnityAvatar._as_bone(objs, 22, sk, rests)
	check(tip == 3 and sk.get_bone_parent(1) == 0, "the linked hierarchy is attached under the humanoid bone")
	check(rests[tip].is_equal_approx(rests[0] * UnityAvatar._world_transform(objs, 11).affine_inverse() * before), "the linked prop keeps its place relative to the bone as the scene poses it, wherever the output rest puts that bone")
	check(UnityAvatar._as_bone(objs, 22, sk, rests) == tip and sk.get_bone_count() == 4, "a source object is added once despite duplicate bone names")
	var springs: Array = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).springs
	check(springs.size() == 1 and springs[0].joints[0].node == 2, "the spring uses the inner object's identity, not the outer bone with the same name")
	check(springs[0].joints.size() == 3 and sk.get_bone_name(springs[0].joints[2].node) == "Tip End", "an unweighted source end node still supplies the spring's last segment")
	check(sk.get_bone_global_rest(springs[0].joints[2].node).is_equal_approx(rests[0] * UnityAvatar._world_transform(objs, 11).affine_inverse() * UnityAvatar._world_transform(objs, 23)), "a later unweighted child inherits the prop scale exactly once")
	objs[140] = {"type": "GameObject", "data": {"m_Name": "Chest"}}
	objs[141] = {"type": "GameObject", "data": {"m_Name": "Tip"}}
	objs[40] = {"type": "Transform", "data": {"m_GameObject": {"fileID": "140"}, "m_Father": {"fileID": "10"}}}
	objs[41] = {"type": "Transform", "data": {"m_GameObject": {"fileID": "141"}, "m_Father": {"fileID": "40"}}}
	objs[32] = {"type": "MonoBehaviour", "data": {"rootTransform": {"fileID": "40"}, "pull": "0.2"}}
	check(UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).springs.size() == 1, "an unbound object does not acquire another object's spring bones by sharing their names")
	sk.free()


func _legacy_springs_keep_their_root_and_endpoint() -> void:
	var sk := Skeleton3D.new()
	sk.add_bone("Root")
	sk.add_bone("Tip")
	sk.set_bone_parent(1, 0)
	sk.set_bone_rest(1, Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(0, 0.1, 0)))
	var objs := {
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "110"}, "m_Father": {"fileID": "0"}}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "111"}, "m_Father": {"fileID": "10"}}},
		110: {"type": "GameObject", "data": {"m_Name": "Root"}},
		111: {"type": "GameObject", "data": {"m_Name": "Tip"}},
		20: {"type": "MonoBehaviour", "data": {"m_Root": {"fileID": "10"}, "m_Damping": "0.6", "m_Elasticity": "0.12", "m_Stiffness": "0.9", "m_EndOffset": {"x": "0", "y": "0.02", "z": "0"}}},
	}
	objs[99] = objs[10]
	objs[20].data.m_Root = {"fileID": "99"}
	var report := {}
	var springs: Array = UnityAvatar._springs(objs, 10, sk, {}, 1.0, report).get("springs", [])
	check(springs.size() == 1, "a legacy component produces a spring chain")
	if springs.size() == 1:
		var joints: Array = springs[0].joints
		check(joints.size() == 3 and joints[0].node == 0 and joints[1].node == 1, "the root, child and endpoint are retained")
		check(is_equal_approx(joints[0].dragForce, 0.6), "legacy damping remains damping")
		if joints.size() == 3:
			var offset := sk.get_bone_global_rest(joints[2].node).origin - sk.get_bone_global_rest(1).origin
			check(offset.is_equal_approx(Vector3(0, 0.02, 0)), "the endpoint follows root axes despite the rotated leaf: %s" % offset)
	check(str(report.get("spring components", "")).begins_with("0 PhysBones, 1 DynamicBones"), "the inventory distinguishes source component types")
	sk.free()


## A DynamicBone on an unscaled object sizes its radius and end offset by that object, not by the scaled armature its
## root bone lies in: a bone of an armature scaled 100 keeps a 0.02 radius, not 2.
func _a_dynamic_bone_sizes_by_its_own_transform() -> void:
	var sk := Skeleton3D.new()
	sk.add_bone("Root")
	sk.add_bone("Tip")
	sk.set_bone_parent(1, 0)
	sk.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	sk.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)))
	var objs := {
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "110"}, "m_Father": {"fileID": "0"}}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "111"}, "m_Father": {"fileID": "10"}, "m_LocalScale": {"x": "100", "y": "100", "z": "100"}}},
		12: {"type": "Transform", "data": {"m_GameObject": {"fileID": "112"}, "m_Father": {"fileID": "11"}, "m_LocalPosition": {"x": "0", "y": "0.01", "z": "0"}}},
		13: {"type": "Transform", "data": {"m_GameObject": {"fileID": "113"}, "m_Father": {"fileID": "12"}, "m_LocalPosition": {"x": "0", "y": "0.001", "z": "0"}}},
		110: {"type": "GameObject", "data": {"m_Name": "Avatar", "m_Component": [{"component": {"fileID": "10"}}]}},
		111: {"type": "GameObject", "data": {"m_Name": "Armature"}},
		112: {"type": "GameObject", "data": {"m_Name": "Root"}},
		113: {"type": "GameObject", "data": {"m_Name": "Tip"}},
		20: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "110"}, "m_Root": {"fileID": "12"}, "m_Damping": "0.2", "m_Radius": "0.02", "m_EndOffset": {"x": "0", "y": "0.02", "z": "0"}}},
	}
	var springs: Array = UnityAvatar._springs(objs, 10, sk, {}, 100.0, {}).get("springs", [])
	var joints: Array = springs[0].joints if springs.size() == 1 else []
	check(joints.size() == 3, "the root, tip and endpoint make the chain: %s" % [springs])
	if joints.size() == 3:
		check(joints.all(func(j: Dictionary) -> bool: return is_equal_approx(j.hitRadius, 0.02)), "each joint's radius is the component's, in its unscaled object's units: %s" % [joints])
		var offset := sk.get_bone_global_rest(joints[2].node).origin - sk.get_bone_global_rest(1).origin
		check(offset.is_equal_approx(Vector3(0, 0.02, 0)), "the endpoint lies its offset in the object's units past the tip: %s" % offset)
	sk.free()


## A transform the skeleton lacks becomes a bone, with each ancestor up to the nearest that is one, placed by their local
## transforms (X mirrored) and that bone's scale; one under no bone adds nothing.
func _a_transform_the_skeleton_lacks_becomes_a_bone() -> void:
	var sk := Skeleton3D.new()
	sk.add_bone("Chest")
	var rests: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))]
	var objs := {}
	for t: Array in [[10, "Chest", 0, "2"], [11, "Wing", 10, "1"], [12, "Wing Tip", 11, "1"], [13, "Loose", 0, "1"]]:
		objs[t[0] + 100] = {"type": "GameObject", "data": {"m_Name": t[1]}}
		objs[t[0]] = {"type": "Transform", "data": {"m_GameObject": {"fileID": str(t[0] + 100)}, "m_Father": {"fileID": str(t[2])}, "m_LocalPosition": {"x": "0.1", "y": "0", "z": "0"}, "m_LocalScale": {"x": t[3], "y": t[3], "z": t[3]}}}
	objs[10].data.m_LocalPosition = {"x": "0", "y": "1", "z": "0"}
	var tip := UnityAvatar._as_bone(objs, 12, sk, rests)
	var wing := sk.find_bone("Wing")
	check(wing == 1 and tip == 2 and sk.get_bone_name(tip) == "Wing Tip" and sk.get_bone_parent(tip) == wing and sk.get_bone_parent(wing) == 0, "the transform and its ancestor are bones under the chest")
	check(rests.size() == 3 and rests[tip].origin.is_equal_approx(Vector3(-0.4, 1, 0)), "each sits where Unity places it, scaled as the chest is: %s" % [rests])
	check(UnityAvatar._as_bone(objs, 13, sk, rests) == -1 and sk.get_bone_count() == 3, "a transform under no bone adds none")
	sk.free()


## An avatar's menu toggle, its parameter, and the FX layer whose clip turns a GameObject on: the GameObject is a
## switch, its renderer, inactive in the scene, draws under it, and the toggle survives pruning; a control whose
## parameter moves nothing is cut.
func _a_menu_toggle_switches_a_hidden_renderer() -> void:
	var dir := ProjectSettings.globalize_path("user://menu")
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(name: String, guid: String, text: String) -> void:
		FileAccess.open(dir.path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	write.call("menu.asset", "m1", """--- !u!114 &11400000
MonoBehaviour:
  controls:
  - name: Hat
    icon: {fileID: 0}
    type: 102
    parameter:
      name: Hat
    value: 1
    subParameters: []
  - name: Idle
    icon: {fileID: 0}
    type: 102
    parameter:
      name: Unused
    value: 1
    subParameters: []
""")
	write.call("parameters.asset", "p1", """--- !u!114 &11400000
MonoBehaviour:
  parameters:
  - name: Hat
    valueType: 2
    saved: 1
    defaultValue: 0
  - name: Unused
    valueType: 2
    saved: 1
    defaultValue: 0
""")
	write.call("fx.controller", "c1", """--- !u!91 &9100000
AnimatorController:
  m_AnimatorParameters:
  - m_Name: Hat
    m_Type: 4
    m_DefaultBool: 0
  m_AnimatorLayers:
  - m_Name: Hat
    m_StateMachine: {fileID: 1}
    m_DefaultWeight: 0
--- !u!1107 &1
AnimatorStateMachine:
  m_ChildStates:
  - m_State: {fileID: 2}
  - m_State: {fileID: 3}
  m_AnyStateTransitions: []
  m_EntryTransitions: []
  m_DefaultState: {fileID: 2}
--- !u!1102 &2
AnimatorState:
  m_Name: Off
  m_Transitions:
  - {fileID: 4}
  m_Motion: {fileID: 0}
  m_WriteDefaultValues: 1
--- !u!1102 &3
AnimatorState:
  m_Name: On
  m_Transitions: []
  m_Motion: {fileID: 6}
  m_WriteDefaultValues: 1
--- !u!1101 &4
AnimatorStateTransition:
  m_Conditions:
  - m_ConditionMode: 1
    m_ConditionEvent: Hat
    m_EventTreshold: 0
  m_DstState: {fileID: 3}
  m_HasExitTime: 0
--- !u!74 &5
AnimationClip:
  m_FloatCurves:
  - curve:
      m_Curve:
      - time: 0
        value: 1
    attribute: m_IsActive
    path: Hat
    classID: 1
  m_AnimationClipSettings:
    m_StopTime: 0
--- !u!206 &6
BlendTree:
  m_BlendType: 0
  m_BlendParameter: Hat
  m_Childs:
  - m_Motion: {fileID: 5}
    m_Threshold: 0
    m_TimeScale: -1
    m_CycleOffset: 0.25
  - m_Motion: {fileID: 5}
    m_Threshold: 1
""")
	var descriptor := {"customExpressions": "1", "expressionsMenu": {"guid": "m1"}, "expressionParameters": {"guid": "p1"}, "baseAnimationLayers": [{"type": "5", "isDefault": "0", "animatorController": {"guid": "c1"}}]}
	var expressions := Expressions.new(Assets.new(dir), descriptor)
	check(expressions.data.menu.size() == 2 and expressions.data.menu[0].type == "toggle" and expressions.data.menu[0].parameter == "Hat", "the menu's toggles read: %s" % [expressions.data.get("menu")])
	check(expressions.data.parameters.any(func(p: Dictionary) -> bool: return p.name == "Hat" and p.type == "bool" and p.saved), "its parameter reads as a saved bool")
	var layer: Dictionary = expressions.data.layers[0]
	var children: Array = layer.states[1].motion.children
	check(children[0].speed == -1.0 and children[0].offset == 0.25 and children[1].speed == 1.0 and children[1].offset == 0.0, "blend children keep reverse playback and cycle offsets, with normal playback by default")
	check(layer.weight == 1.0 and layer.states.size() == 2 and layer.states[0].transitions[0].to == 1 and layer.states[0].transitions[0].conditions[0].mode == "if", "the first layer weighs one and its toggle transition reads: %s" % [layer])
	var objs := {
		1: {"type": "GameObject", "data": {"m_Name": "Avatar", "m_Component": [{"component": {"fileID": "2"}}]}},
		2: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}, "m_Father": {"fileID": "0"}}},
		3: {"type": "GameObject", "data": {"m_Name": "Hat", "m_IsActive": "0", "m_Component": [{"component": {"fileID": "4"}}, {"component": {"fileID": "5"}}]}},
		4: {"type": "Transform", "data": {"m_GameObject": {"fileID": "3"}, "m_Father": {"fileID": "2"}}},
		5: {"type": "SkinnedMeshRenderer", "data": {"m_GameObject": {"fileID": "3"}, "m_Enabled": "1"}},
	}
	var paths := UnityAvatar._paths(objs, 2)
	check(paths.get("Hat") == 4, "a clip's path names the transform under the avatar")
	var switches := UnityAvatar._switches(expressions, objs, paths)
	check(switches.targets.size() == 1 and switches.targets[0].default == 0.0 and switches.by_object.get(3) == 0, "the GameObject the clip turns on is a switch, off as the scene has it")
	var drawn := UnityAvatar._renderers(objs, 2, switches.by_object, {})
	check(drawn.size() == 1 and drawn[0][0] == 5 and drawn[0][2] == [[0, 1]], "its inactive renderer draws while the switch is on: %s" % [drawn])
	var sk := Skeleton3D.new()
	var data := UnityAvatar._bound(expressions, switches, [{"node": "Body 1", "when": [[0, 1]], "renderers": [5], "weights": {}, "mesh": ArrayMesh.new()}], {}, objs, paths, sk, Materials.new(Assets.new(dir)), {})
	check(data.menu.size() == 1 and data.menu[0].name == "Hat", "the toggle that moves nothing is cut: %s" % [data.menu])
	check(data.shown == [{"node": "Body 1", "when": [[0, 1]]}] and data.clips[0].curves[0] == {"target": 0, "step": true, "keys": [[0.0, 1.0]]}, "the hat's mesh shows under its switch, which the clip sets: %s %s" % [data.shown, data.clips])
	sk.free()


func _a_direct_tree_sums_its_toggles_unnormalized() -> void:
	var dir := ProjectSettings.globalize_path("user://direct")
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(name: String, guid: String, text: String) -> void:
		FileAccess.open(dir.path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	var names := ["A", "B", "C"]
	write.call("menu.asset", "m1", "--- !u!114 &11400000\nMonoBehaviour:\n  controls:\n" + "".join(PackedStringArray(names.map(func(n: String) -> String: return "  - name: %s\n    icon: {fileID: 0}\n    type: 102\n    parameter:\n      name: %s\n    value: 1\n    subParameters: []\n" % [n, n]))))
	write.call("parameters.asset", "p1", "--- !u!114 &11400000\nMonoBehaviour:\n  parameters:\n" + "".join(PackedStringArray([["A", 1], ["B", 1], ["C", 0]].map(func(p: Array) -> String: return "  - name: %s\n    valueType: 2\n    saved: 1\n    defaultValue: %d\n" % p))))
	# An optimizer's layer: one direct tree, every child weighted by a constant parameter, each a toggle's 1D tree
	# between its off and on clips; A's toggle is a child twice, so its sum passes one.
	var controller := func(normalized: int) -> String:
		var text := "--- !u!91 &9100000\nAnimatorController:\n  m_AnimatorParameters:\n  - m_Name: One\n    m_Type: 1\n    m_DefaultFloat: 1\n"
		text += "".join(PackedStringArray(names.map(func(n: String) -> String: return "  - m_Name: %s\n    m_Type: 1\n" % n)))
		text += "  m_AnimatorLayers:\n  - m_Name: Toggles\n    m_StateMachine: {fileID: 1}\n--- !u!1107 &1\nAnimatorStateMachine:\n  m_ChildStates:\n  - m_State: {fileID: 2}\n  m_DefaultState: {fileID: 2}\n"
		text += "--- !u!1102 &2\nAnimatorState:\n  m_Name: Toggles\n  m_Transitions: []\n  m_Motion: {fileID: 10}\n  m_WriteDefaultValues: 1\n"
		text += "--- !u!206 &10\nBlendTree:\n  m_BlendType: 4\n  m_NormalizedBlendValues: %d\n  m_Childs:\n" % normalized
		text += "".join(PackedStringArray([11, 11, 12, 13].map(func(t: int) -> String: return "  - m_Motion: {fileID: %d}\n    m_DirectBlendParameter: One\n" % t)))
		for i in names.size():
			text += "--- !u!206 &%d\nBlendTree:\n  m_BlendType: 0\n  m_BlendParameter: %s\n  m_Childs:\n  - m_Motion: {fileID: %d}\n    m_Threshold: 0\n  - m_Motion: {fileID: %d}\n    m_Threshold: 1\n" % [11 + i, names[i], 20 + 2 * i, 21 + 2 * i]
			for on in 2:
				text += "--- !u!74 &%d\nAnimationClip:\n  m_FloatCurves:\n  - curve:\n      m_Curve:\n      - time: 0\n        value: %d\n    attribute: m_IsActive\n    path: %s\n    classID: 1\n  m_AnimationClipSettings:\n    m_StopTime: 0\n" % [20 + 2 * i + on, on, names[i]]
		return text
	var objs := {1: {"type": "GameObject", "data": {"m_Name": "Avatar", "m_Component": [{"component": {"fileID": "2"}}]}}, 2: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}, "m_Father": {"fileID": "0"}}}}
	for i in names.size():
		var go := 10 * (i + 1)
		objs[go] = {"type": "GameObject", "data": {"m_Name": names[i], "m_IsActive": "0", "m_Component": [{"component": {"fileID": str(go + 1)}}, {"component": {"fileID": str(go + 2)}}]}}
		objs[go + 1] = {"type": "Transform", "data": {"m_GameObject": {"fileID": str(go)}, "m_Father": {"fileID": "2"}}}
		objs[go + 2] = {"type": "SkinnedMeshRenderer", "data": {"m_GameObject": {"fileID": str(go)}, "m_Enabled": "1"}}
	var descriptor := {"customExpressions": "1", "expressionsMenu": {"guid": "m1"}, "expressionParameters": {"guid": "p1"}, "baseAnimationLayers": [{"type": "5", "isDefault": "0", "animatorController": {"guid": "c1"}}]}
	var shown := func(normalized: int) -> Array:
		write.call("fx.controller", "c1", controller.call(normalized))
		var expressions := Expressions.new(Assets.new(dir), descriptor)
		var paths := UnityAvatar._paths(objs, 2)
		var switches := UnityAvatar._switches(expressions, objs, paths)
		var meshes := UnityAvatar._renderers(objs, 2, switches.by_object, {}).map(func(r: Array) -> Dictionary: return {"node": "Body %d" % r[0], "when": r[2], "renderers": [r[0]], "weights": {}, "mesh": ArrayMesh.new()})
		var sk := Skeleton3D.new()
		var data := UnityAvatar._bound(expressions, switches, meshes, {}, objs, paths, sk, Materials.new(Assets.new(dir)), {})
		sk.free()
		check(data.layers[0].states[0].motion.get("normalized", false) == (normalized == 1), "the direct tree reads its normalized blend values flag as %d" % normalized)
		var state := ExpressionState.new(data)
		state.advance(1.0 / 60.0)
		return data.shown.map(func(s: Dictionary) -> bool: return ExpressionPlayer.shows(state.outputs, s.when))
	check(shown.call(0) == [true, true, false], "each toggle a direct tree sums at its full weight shows as its default says: %s" % [shown.call(0)])
	check(shown.call(1) == [false, false, false], "normalized blend values share the tree's weight among its toggles: %s" % [shown.call(1)])


func _a_hue_radial_keeps_its_material_binding() -> void:
	var dir := ProjectSettings.globalize_path("user://hue")
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(name: String, guid: String, text: String) -> void:
		FileAccess.open(dir.path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	write.call("colour.shader", "shader", 'Shader "Fixture" { Properties { _MainHueShift ("Hue", Float) = 0 } }')
	write.call("colour.mat", "colour", """Material:
  m_Shader: {guid: shader}
  m_SavedProperties:
    m_Floats:
    - _MainHueShift: 0.25
    - _MainHueShiftToggle: 1
    - _MainHueShiftColorSpace: 1
    - _MainHueShiftSelectOrShift: 0
""")
	var assets := Assets.new(dir)
	var materials := Materials.new(assets)
	materials.use({"guid": "colour"}, Color.WHITE)
	materials.pack(["colour"])
	var expressions := Expressions.new(assets, {})
	expressions.data = {
		"menu": [{"name": "Hue", "type": "radial", "parameter": "", "axes": ["Hue"], "value": 1, "icon": ""}],
		"parameters": [{"name": "Hue", "type": "float", "default": 0}],
		"layers": [{"weight": 1, "default": 0, "entry": [], "any": [], "states": [{"motion": {"clip": 0, "time": "Hue"}, "transitions": [], "drivers": []}]}],
		"clips": [{"length": 1, "loop": false, "curves": [{"path": "", "attribute": "material._MainHueShift", "class": "137", "keys": [[0.0, 0.0], [1.0, 1.0]]}]}],
	}
	var objs := {
		1: {"type": "GameObject", "data": {"m_Component": [{"component": {"fileID": "2"}}, {"component": {"fileID": "3"}}]}},
		2: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}}},
		3: {"type": "SkinnedMeshRenderer", "data": {"m_Materials": [{"guid": "colour"}]}},
	}
	var sk := Skeleton3D.new()
	var mesh := {"node": "Body", "when": [], "renderers": [3], "weights": {}, "mesh": ArrayMesh.new()}
	var data := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(data.menu.size() == 1 and data.targets.size() == 1, "a hue radial survives binding")
	if data.targets.size() == 1:
		var target: Dictionary = data.targets[0]
		check(target.default == 0.25 and target.effect.hue[0].node == "Body" and target.effect.hue[0].space == 1.0 and target.effect.hue[0].shift == 0.0, "the saved colour space, mode and default survive")
		check(data.clips[0].curves[0].keys == [[0.0, 0.0], [1.0, 1.0]] and not data.clips[0].curves[0].step, "hue remains continuous instead of becoming a switch")
	materials.materials.colour.properties.clear()
	var absent := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(absent.targets.is_empty(), "a stale saved property not declared by the shader has no binding")
	materials.materials.colour.shader = "VRChat/Mobile/Toon Standard"
	materials.materials.colour.properties = {"_HueShift": true}
	materials.materials.colour.floats = {"_HueShift": "0.5", "_HueShiftMaskChannel": "1"}
	materials.materials.colour.keywords = ["USE_HUE_SHIFT"]
	materials.materials.colour.textures = {"_HueShiftMask": {"m_Texture": {"guid": "mask"}}}
	var mask := Image.create_empty(2, 1, false, Image.FORMAT_RGBA8)
	mask.set_pixel(0, 0, Color(1, 0, 0, 1))
	mask.set_pixel(1, 0, Color(0, 1, 0, 1))
	materials._images.mask = mask
	expressions.data.clips[0].curves[0].attribute = "material._HueShift"
	expressions.data.clips[0].curves[0].keys = [[0.0, 0.0], [1.0, TAU]]
	var mobile := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(mobile.targets.size() == 1 and mobile.targets[0].effect.hue[0].space == 2.0, "Toon Standard binds RGB-axis hue")
	check(mobile.clips[0].curves[0].keys == [[0.0, 0.0], [1.0, TAU]], "the shader's angle stays in radians")
	var packed := Image.new()
	check(packed.load_png_from_buffer(Marshalls.base64_to_raw(mobile.hueMask)) == OK, "the hue mask is carried in expression metadata")
	var cell: Rect2i = materials.materials.colour.cell
	check(packed.get_pixel(cell.position.x + cell.size.x / 4, cell.position.y + cell.size.y / 2).r < 0.2 and packed.get_pixel(cell.position.x + 3 * cell.size.x / 4, cell.position.y + cell.size.y / 2).r > 0.8, "the selected green mask channel follows the atlas region")
	materials.materials.colour.keywords.clear()
	var disabled := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(disabled.targets.is_empty(), "a disabled shader feature does not create a hue binding")
	materials.hue_masks.clear()
	materials.materials.colour.properties = {"_Color": true}
	materials.materials.colour.colour = Color(0.0, 0.5, 0.25, 0.5)
	materials.materials.colour.alpha = Materials.Alpha.BLEND
	materials.pack(["colour"])
	materials.atlas_materials()
	expressions.data.clips[0].curves[0].attribute = "material._Color.r"
	expressions.data.clips[0].curves[0].keys = [[0.0, 0.0], [1.0, 1.0]]
	var colored := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(colored.targets.size() == 1 and colored.targets[0].default == 0.0 and colored.targets[0].effect.color[0].channel == 0, "RGB curves bind even when the saved channel is black")
	check(colored.clips[0].curves[0].keys == [[0.0, 0.0], [1.0, 1.0]], "RGB stays continuous")
	var raw := Image.new()
	check(raw.load_png_from_buffer(Marshalls.base64_to_raw(colored.colorAtlas)) == OK, "untinted colors are carried in the expression metadata")
	cell = materials.materials.colour.cell
	var center := cell.position + cell.size / 2
	check(materials.atlas.get_pixelv(center).r == 0.0 and raw.get_pixelv(center).r > 0.99, "animation can recover a channel that baking had removed")
	check(is_equal_approx(raw.get_pixelv(center).a, materials.atlas.get_pixelv(center).a), "the original transparency is preserved")
	materials.color_regions.clear()
	materials.materials.colour.shader = "Poiyomi Toon"
	materials.materials.colour.properties = {"_MainGamma_Test": true}
	materials.materials.colour.floats = {"_MainGamma_Test": "1", "_MainColorAdjustToggle": "1"}
	materials.materials.colour.textures = {"_MainColorAdjustTexture": {"m_Texture": {"guid": "mask"}}}
	expressions.data.clips[0].curves[0].attribute = "material._MainGamma_Test"
	expressions.data.clips[0].curves[0].keys = [[0.0, 1.0], [1.0, 2.0]]
	var toned := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(toned.targets.size() == 1 and toned.targets[0].default == 1.0 and toned.targets[0].effect.tone[0].channel == 0, "gamma keeps its material region and neutral default")
	check(toned.clips[0].curves[0].keys == [[0.0, 1.0], [1.0, 2.0]], "tone curves remain continuous")
	check(packed.load_png_from_buffer(Marshalls.base64_to_raw(toned.hueMask)) == OK, "the color adjustment mask is carried")
	var first := packed.get_pixel(cell.position.x + cell.size.x / 4, cell.position.y + cell.size.y / 2)
	check(first.r > 0.8 and first.g < 0.2 and first.b < 0.2 and first.a > 0.99, "the adjustment mask retains independent RGBA channels")
	materials.materials.colour.floats._MainColorAdjustToggle = "0"
	var off := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(off.targets.is_empty(), "disabled color adjustment does not bind tone curves")

	sk.free()


func _native_constraints_resolve_world_and_feedback() -> void:
	var dir := ProjectSettings.globalize_path("user://constraints")
	DirAccess.make_dir_recursive_absolute(dir)
	var assets := Assets.new(dir)
	assets.by_guid["anchor"] = {}
	var prefabs := Prefabs.new(assets)
	prefabs._flat["anchor"] = {90: {"type": "Transform", "data": {"m_LocalPosition": {"x": "2", "y": "3", "z": "4"}}}}
	var objs := {
		1: {"type": "GameObject", "data": {"m_Name": "Avatar", "m_IsActive": "1"}},
		2: {"type": "GameObject", "data": {"m_Name": "World", "m_IsActive": "1", "m_Component": [{"component": {"fileID": "20"}}]}},
		3: {"type": "GameObject", "data": {"m_Name": "Follower", "m_IsActive": "1", "m_Component": [{"component": {"fileID": "21"}}]}},
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}, "m_Children": [{"fileID": "11"}]}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "2"}, "m_Father": {"fileID": "10"}, "m_Children": [{"fileID": "12"}]}},
		12: {"type": "Transform", "data": {"m_GameObject": {"fileID": "3"}, "m_Father": {"fileID": "11"}}},
		20: {"type": "ParentConstraint", "data": {"m_Active": "1", "m_Sources": [{"sourceTransform": {"guid": "anchor", "fileID": "90"}, "weight": "1"}]}},
		21: {"type": "PositionConstraint", "data": {"m_Active": "1", "m_Sources": [{"sourceTransform": {"fileID": "12"}, "weight": "1"}, {"sourceTransform": {"fileID": "10"}, "weight": "0.01"}]}},
	}
	var sk := Skeleton3D.new()
	sk.set_meta("unity_bones", {})
	sk.set_meta("unity_top", 10)
	var rests: Array[Transform3D] = []
	var result := UnityAvatar._constraints(prefabs, objs, 10, sk, rests)
	check(not result.has("error"), "active native constraints resolve")
	if result.has("constraints"):
		check(result.constraints.size() == 2, "both active native constraints exported")
		var parent: Dictionary = result.constraints[0]
		var follower: Dictionary = result.constraints[1]
		check(parent.sources[0].world.slice(12, 15) == [-2.0, 3.0, 4.0], "external prefab keeps its world coordinates with handedness conversion")
		check(follower.sources[0].node == follower.node and is_equal_approx(follower.sources[1].weight, 0.01), "feedback reference and authored weight survive")
	objs[21].data.m_Enabled = "0"
	check(UnityAvatar._constraints(prefabs, objs, 10, sk, rests).constraints.size() == 1, "disabled component remains disabled")
	objs[2].data.m_IsActive = "0"
	check(UnityAvatar._constraints(prefabs, objs, 10, sk, rests).constraints.is_empty(), "inactive hierarchy remains inactive")
	sk.free()


func _mesh_bones_do_not_alias_another_models_names() -> void:
	var root := Node3D.new()
	var source := Skeleton3D.new()
	source.name = "Source"
	source.add_bone("Head")
	root.add_child(source)
	var mesh := MeshInstance3D.new()
	mesh.skin = Skin.new()
	mesh.skin.add_bind(0, Transform3D.IDENTITY)
	mesh.skeleton = NodePath("../Source")
	root.add_child(mesh)
	var target := Skeleton3D.new()
	target.add_bone("Head")
	target.set_meta("unity_bones", {1: 0})
	target.set_meta("unity_top", 10)
	target.set_meta("unity_model", "body")
	var rests: Array[Transform3D] = [Transform3D.IDENTITY]
	var objs := {
		1: {"type": "GameObject", "data": {"m_Name": "Head"}},
		2: {"type": "GameObject", "data": {"m_Name": "Head"}},
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "2"}, "m_Father": {"fileID": "10"}, "m_LocalPosition": {"x": "1"}}},
		20: {"type": "SkinnedMeshRenderer", "data": {"m_Mesh": {"guid": "prop"}, "m_Bones": [{"fileID": "11"}]}},
	}
	var bound := UnityAvatar._binder(mesh, target, rests, 1.0, objs, 20, false, 1)
	check(bound.binds[0][0] == 1 and target.get_bone_count() == 2, "prop Head binds to its own source transform, not humanoid Head")
	check(target.get_bone_global_rest(1).origin.is_equal_approx(Vector3(-1, 0, 0)), "same-named prop bone retains its authored position")
	root.free()
	target.free()


## A model's bone named as Blender numbers a duplicate ("Wing.001") binds its own Unity transform, not its parent's:
## Godot keeps the dot in a skeleton's bone name and drops it from a node's.
func _a_dotted_bone_name_binds_its_own_transform() -> void:
	var root := Node3D.new()
	var source := Skeleton3D.new()
	source.name = "Source"
	source.add_bone("Wing")
	source.add_bone("Wing.001")
	source.set_bone_parent(1, 0)
	root.add_child(source)
	var mesh := MeshInstance3D.new()
	mesh.skin = Skin.new()
	mesh.skin.add_bind(0, Transform3D.IDENTITY)
	mesh.skin.add_bind(1, Transform3D.IDENTITY)
	mesh.skeleton = NodePath("../Source")
	root.add_child(mesh)
	var target := Skeleton3D.new()
	target.add_bone("Wing")
	var rests: Array[Transform3D] = [Transform3D.IDENTITY]
	var objs := {
		1: {"type": "GameObject", "data": {"m_Name": "Wing"}},
		2: {"type": "GameObject", "data": {"m_Name": "Wing.001"}},
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "2"}, "m_Father": {"fileID": "10"}, "m_LocalPosition": {"x": "1"}}},
		20: {"type": "SkinnedMeshRenderer", "data": {"m_Mesh": {"guid": "prop"}, "m_Bones": [{"fileID": "10"}, {"fileID": "11"}]}},
	}
	var bound := UnityAvatar._binder(mesh, target, rests, 1.0, objs, 20, false, 0)
	check(bound.binds[1][0] != bound.binds[0][0] and target.get_bone_count() == 2, "Wing.001 binds its own bone, not Wing: %s" % [bound.binds])
	check(target.get_bone_parent(bound.binds[1][0]) == 0, "under Wing")
	root.free()
	target.free()


## glTF lists a skin's joints once each: a second source binding the same bones in poses one transform apart shares
## their binds, its new bones bind to match, and its vertices, moved by that transform, skin where its own binds put
## them in any pose. A first source keeps its binds and vertices as they are, and a source whose binds disagree by no
## one transform still lands where its binds put it with the skeleton at rest. A mirrored source is one transform apart.
func _sources_binding_one_bone_differently_share_one_bind() -> void:
	var rests: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), Transform3D(Basis(Vector3.UP, 0.5), Vector3(1, 1, 0)), Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 1.5, 0))]
	var skin := Skin.new()
	var binds := {}
	var shifted := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 100.0), Vector3(0, -2, 0))
	var first := [[0, Transform3D(Basis.IDENTITY, Vector3(0, -1, 0))], [1, Transform3D(Basis(Vector3.UP, 0.5), Vector3(-1, -1, 0))]]
	var second := [[1, first[1][1] * shifted], [2, Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, -1.5, 0.2)) * shifted]]
	var askew := [[0, first[0][1] * shifted], [1, first[1][1]]]
	var a := UnityAvatar._bind_once(first, skin, binds, rests)
	var b := UnityAvatar._bind_once(second, skin, binds, rests)
	var c := UnityAvatar._bind_once(askew, skin, binds, rests)
	check(skin.get_bind_count() == 3 and a.bound == [0, 1] and b.bound == [1, 2] and c.bound == [0, 1], "a bone sources bind differently is one bind: %s %s %s" % [a.bound, b.bound, c.bound])
	check(a.moves.all(func(m: Variant) -> bool: return m == Transform3D.IDENTITY), "the first source keeps its vertices where they are")
	var top := [[0, 1, 0, 0], [0.25, 0.75, 0.0, 0.0]]
	var identity := func(i: int) -> int: return i
	var vertex := Vector3(0.003, -0.0001, 0.0002)
	var skins := func(source: Array, bind: Dictionary, posed: Array[Transform3D]) -> Array:
		var at := UnityAvatar._at_rest(top, bind, identity) * vertex
		var expected := Vector3.ZERO
		var skinned := Vector3.ZERO
		for j in 2:
			expected += top[1][j] * (posed[source[j][0]] * source[j][1] * vertex)
			skinned += top[1][j] * (posed[bind.bound[j]] * skin.get_bind_pose(bind.bound[j]) * at)
		return [skinned, expected]
	var posed: Array[Transform3D] = [Transform3D(Basis(Vector3.UP, 0.2), Vector3.ZERO), Transform3D(Basis(Vector3.FORWARD, 1.2), Vector3(1, 1, 0)), Transform3D(Basis(Vector3.RIGHT, -0.7), Vector3(0, 2, 1))]
	var bent: Array = skins.call(second, b, posed)
	check(bent[0].is_equal_approx(bent[1]), "a vertex skins where its source's binds put it in any pose: %s vs %s" % bent)
	var resting: Array = skins.call(askew, c, rests)
	check(resting[0].is_equal_approx(resting[1]), "a source with no one move lands where its binds put it at rest: %s vs %s" % resting)
	var mirror := Transform3D.IDENTITY.scaled(Vector3(-1.01, 1.03, 1))
	var mirrored := [[0, first[0][1] * mirror], [1, first[1][1] * mirror]]
	var d := UnityAvatar._bind_once(mirrored, skin, binds, rests)
	var flipped: Array = skins.call(mirrored, d, posed)
	check(skin.get_bind_count() == 3 and flipped[0].is_equal_approx(flipped[1]), "a mirrored source shares the binds and skins where its binds put it: %s vs %s" % flipped)


func _a_decal_alpha_binds_its_atlas_layer() -> void:
	var dir := ProjectSettings.globalize_path("user://decal")
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(name: String, guid: String, text: String) -> void:
		FileAccess.open(dir.path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	write.call("skin.shader", "shader", 'Shader "Hidden/Locked/.poiyomi/Poiyomi Toon" { Properties { _DecalBlendAlpha2_Skin ("Alpha", Range(0, 1)) = 1 } }')
	write.call("skin.mat", "skin", """Material:
  m_Shader: {guid: shader}
  m_SavedProperties:
    m_TexEnvs:
    - _DecalMask:
        m_Texture: {guid: mask}
    m_Floats:
    - _DecalBlendAlpha2_Skin: 0.25
    - _DecalEnabled2: 1
    - _DecalBlendType2: 2
    - _Decal2MaskChannel: 1
    m_Colors:
    - _DecalColor2: {r: 1, g: 0.5, b: 0, a: 1}
    - _DecalPosition2: {r: 0.5, g: 0.5, b: 0, a: 0}
    - _DecalScale2: {r: 1, g: 1, b: 1, a: 0}
""")
	var mask := Image.create_empty(2, 1, false, Image.FORMAT_RGBA8)
	mask.set_pixel(0, 0, Color(1, 0, 0, 1))
	mask.set_pixel(1, 0, Color(0, 1, 0, 1))
	mask.save_png(dir.path_join("mask.png"))
	FileAccess.open(dir.path_join("mask.png.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: mask\n")
	var assets := Assets.new(dir)
	var materials := Materials.new(assets)
	materials.use({"guid": "skin"}, Color.WHITE)
	materials.pack(["skin"])
	var expressions := Expressions.new(assets, {})
	expressions.data = {
		"menu": [{"name": "Spots", "type": "toggle", "parameter": "Spots", "axes": [], "value": 1, "icon": ""}],
		"parameters": [{"name": "Spots", "type": "bool", "default": 0}],
		"layers": [{"weight": 1, "default": 0, "entry": [], "any": [], "states": [{"motion": {"clip": 0}, "transitions": [], "drivers": []}]}],
		"clips": [{"length": 0, "loop": false, "curves": [{"path": "", "attribute": "material._DecalBlendAlpha2_Skin", "class": "137", "keys": [[0.0, 1.0]]}]}],
	}
	var objs := {
		1: {"type": "GameObject", "data": {"m_Component": [{"component": {"fileID": "2"}}, {"component": {"fileID": "3"}}]}},
		2: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}}},
		3: {"type": "SkinnedMeshRenderer", "data": {"m_Materials": [{"guid": "skin"}]}},
	}
	var sk := Skeleton3D.new()
	var mesh := {"node": "Body", "when": [], "renderers": [3], "weights": {}, "mesh": ArrayMesh.new()}
	var data := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(data.targets.size() == 1 and data.targets[0].default == 0.25, "a decal alpha binds with its saved alpha: %s" % [data.targets])
	if data.targets.size() == 1:
		var region: Dictionary = data.targets[0].effect.look[0]
		check(region.node == "Body" and region.slot == 2 and region.field == "decal", "the region names its field and slot: %s" % [region])
		check(data.clips[0].curves[0].keys == [[0.0, 1.0]] and not data.clips[0].curves[0].step, "decal alpha stays continuous")
	var looks: Dictionary = data.get("looks", {})
	var cell: Rect2i = materials.materials.skin.cell
	var rect := [float(cell.position.x) / materials.atlas_side, float(cell.position.y) / materials.atlas_side, float(cell.end.x) / materials.atlas_side, float(cell.end.y) / materials.atlas_side]
	check((looks.get("decals", []) as Array).size() == 1, "one image per decal drawn")
	check(looks.get("materials", []) == [{"rect": rect, "decals": [null, null, {"alpha": 0.25, "intensity": 1.0, "multiply": true, "image": 0}, null], "matcaps": [null, null, null, null], "emission": null, "lighting": {"model": "lit"}}], "the look holds its cell and each slot's saved alpha, blend and image: %s" % [looks.get("materials")])
	if data.targets.size() == 1:
		check(data.targets[0].effect.look[0].image == 0, "the region names its decal's image")
	if (looks.get("decals", []) as Array).size() == 1:
		var layer: Image = looks.decals[0]
		var left := layer.get_pixel(layer.get_width() / 4, layer.get_height() / 2)
		var right := layer.get_pixel(3 * layer.get_width() / 4, layer.get_height() / 2)
		check(left.a < 0.2 and right.a > 0.8 and is_equal_approx(right.r, 1.0) and right.g > 0.45 and right.g < 0.55, "the image carries the decal colour under the mask's chosen channel: %s %s" % [left, right])
	var index := Image.new()
	check(index.load_png_from_buffer(Marshalls.base64_to_raw(looks.get("index", ""))) == OK, "the look index is a PNG")
	if not index.is_empty():
		check(index.get_pixelv(cell.get_center()).r8 == 1 and index.get_pixel(materials.atlas_side - 1, materials.atlas_side - 1).r8 == 0, "each texel names its material's look")
	expressions.data.clips[0].curves.clear()
	var unbound := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(unbound.targets.is_empty() and (unbound.get("looks", {}).get("decals", []) as Array).size() == 1, "a decal no clip animates is still drawn at its saved alpha")
	expressions.data.clips[0].curves.append({"path": "", "attribute": "material._DecalBlendAlpha2_Skin", "class": "137", "keys": [[0.0, 1.0]]})
	materials.materials.skin.properties._DecalAlphaIntensity2_Skin = true
	materials.materials.skin.floats._DecalAlphaIntensity2_Skin = "0"
	expressions.data.clips[0].curves.append({"path": "", "attribute": "material._DecalAlphaIntensity2_Skin", "class": "137", "keys": [[0.0, 3.0]]})
	var intense := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(intense.targets.size() == 2 and intense.targets[1].effect.look[0].field == "decalIntensity" and intense.targets[1].default == 0.0, "an animated alpha intensity binds as its slot's second factor: %s" % [intense.targets])
	check(intense.looks.materials[0].decals[2].intensity == 0.0, "the look holds the saved intensity under its declared name")
	expressions.data.clips[0].curves.pop_back()
	materials.materials.skin.colours._DecalPosition2 = {"r": 0.25, "g": 0.5, "b": 0, "a": 0}
	var moved := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(moved.targets.is_empty() and not moved.has("looks"), "a decal placed off the whole texture is neither bound nor drawn")
	materials.materials.skin.colours._DecalPosition2 = {"r": 0.5, "g": 0.5, "b": 0, "a": 0}
	materials.materials.skin.properties._DecalHueShift2_Skin = true
	materials.materials.skin.floats.merge({"_DecalHueShiftEnabled2": "1", "_DecalHueShiftColorSpace2": "1", "_DecalHueShift2": "0", "_DecalHueShift2_Skin": "0.5"})
	var hued := func() -> Color:
		var bound := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
		var drawn: Variant = bound.get("looks", {}).get("materials", [{}])[0].get("decals", [null, null, null])[2]
		if drawn == null:
			return Color(0, 0, 0, 0)
		var layer: Image = bound.looks.decals[drawn.image]
		return layer.get_pixel(3 * layer.get_width() / 4, layer.get_height() / 2)
	var cyan: Color = hued.call()
	check(cyan.a > 0.8 and cyan.r < 0.02 and absf(cyan.g - 0.9) < 0.02 and cyan.b > 0.98, "a decal at a fixed hue shift is drawn at it, by the shader-named value: linear orange half a turn round HSV is cyan, %s" % cyan)
	materials.materials.skin.colours._DecalColor2 = {"r": 1, "g": 1, "b": 1, "a": 1}
	materials.materials.skin.floats.merge({"_DecalHueShiftColorSpace2": "0", "_DecalHueShift2_Skin": "0.331"})
	var white: Color = hued.call()
	check(white.a > 0.8 and white.r > 0.98 and white.g > 0.98 and white.b > 0.98, "a white decal stays white under an OKLab hue shift: %s" % white)
	materials.materials.skin.floats._DecalHueShiftSpeed2 = "1"
	check(hued.call().a == 0.0, "a decal whose hue cycles over time is not drawn")
	sk.free()


func _a_shrunk_texture_averages_what_its_cell_covers() -> void:
	var dir := ProjectSettings.globalize_path("user://shrink")
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(name: String, guid: String, text: String) -> void:
		FileAccess.open(dir.path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	write.call("skin.shader", "shader", 'Shader "Hidden/Locked/.poiyomi/Poiyomi Toon" { Properties { } }')
	write.call("skin.mat", "skin", """Material:
  m_Shader: {guid: shader}
  m_SavedProperties:
    m_TexEnvs:
    - _MainTex:
        m_Texture: {guid: stripes}
    - _DecalTexture:
        m_Texture: {guid: stripes}
    m_Floats:
    - _DecalEnabled: 1
    m_Colors:
    - _DecalPosition: {r: 0.5, g: 0.5, b: 0, a: 0}
    - _DecalScale: {r: 1, g: 1, b: 1, a: 0}
""")
	var size := Vector2i(3000, 64)
	var stripes := PackedByteArray()
	stripes.resize(size.x * size.y * 4)
	for y in size.y:
		for x in size.x:
			var v := 255 if x % 2 == 0 else 0
			var i := (y * size.x + x) * 4
			stripes[i] = v
			stripes[i + 1] = v
			stripes[i + 2] = v
			stripes[i + 3] = 255
	Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, stripes).save_png(dir.path_join("stripes.png"))
	FileAccess.open(dir.path_join("stripes.png.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: stripes\n")
	var materials := Materials.new(Assets.new(dir), Materials.ATLAS)
	materials.use({"guid": "skin"}, Color.WHITE)
	materials.pack(["skin"])
	var cell: Rect2i = materials.materials.skin.cell
	var looks := materials.looks()
	var decal: Image = looks.decals[0] if (looks.get("decals", []) as Array).size() == 1 else Image.new()
	check(decal.get_width() == Materials.ATLAS, "a decal whose .meta names no import size keeps its texture's up to the atlas's widest, %d: %d" % [Materials.ATLAS, decal.get_width()])
	for named: Array in [["albedo", materials.atlas, cell]]:
		var img: Image = named[1]
		var area: Rect2i = named[2]
		if img.is_empty():
			continue
		var spread := Vector2(1, 0)
		for y in range(area.position.y + 3, area.end.y - 3, 7):
			for x in range(area.position.x + 3, area.end.x - 3):
				var r := img.get_pixel(x, y).r
				spread = Vector2(minf(spread.x, r), maxf(spread.y, r))
		check(spread.x > 0.4 and spread.y < 0.6, "a 3000-texel texture of one-texel stripes shrunk to %d texels is the stripes' grey in the %s, not a moire of them: %s" % [area.size.x, named[0], spread])


func _a_decal_keeps_the_size_unity_imports() -> void:
	var dir := ProjectSettings.globalize_path("user://imported")
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(name: String, guid: String, text: String, meta: String) -> void:
		FileAccess.open(dir.path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n%s" % [guid, meta])
	write.call("skin.shader", "shader", 'Shader "Hidden/Locked/.poiyomi/Poiyomi Toon" { Properties { } }', "")
	write.call("skin.mat", "skin", """Material:
  m_Shader: {guid: shader}
  m_SavedProperties:
    m_TexEnvs:
    - _MainTex:
        m_Texture: {guid: small}
    - _DecalTexture:
        m_Texture: {guid: tattoo}
    m_Floats:
    - _DecalEnabled: 1
    m_Colors:
    - _DecalPosition: {r: 0.5, g: 0.5, b: 0, a: 0}
    - _DecalScale: {r: 1, g: 1, b: 1, a: 0}
""", "")
	Image.create_empty(16, 16, false, Image.FORMAT_RGBA8).save_png(dir.path_join("small.png"))
	FileAccess.open(dir.path_join("small.png.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: small\n")
	var tattoo := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	tattoo.fill(Color(1, 0, 0, 1))
	tattoo.save_png(dir.path_join("tattoo.png"))
	var settings := func(default: int, standalone: int, overridden: int) -> String:
		return "TextureImporter:\n  platformSettings:\n  - serializedVersion: 3\n    buildTarget: DefaultTexturePlatform\n    maxTextureSize: %d\n    overridden: 0\n  - serializedVersion: 3\n    buildTarget: Standalone\n    maxTextureSize: %d\n    overridden: %d\n" % [default, standalone, overridden]
	for case: Array in [["", 256, "an unrestricted texture at its own size"], [settings.call(128, 32, 0), 128, "the default platform's size where the PC does not override it"], [settings.call(32, 128, 1), 128, "the PC's size where it overrides the default"], ["TextureImporter:\n  maxTextureSize: 2048\n  platformSettings:\n  - serializedVersion: 3\n    buildTarget: DefaultTexturePlatform\n    maxTextureSize: 128\n    overridden: 0\n", 128, "the default platform's size over a wider legacy field, as Unity imports it"]]:
		FileAccess.open(dir.path_join("tattoo.png.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: tattoo\n" + case[0])
		var materials := Materials.new(Assets.new(dir))
		materials.use({"guid": "skin"}, Color.WHITE)
		materials.pack(["skin"])
		var looks := materials.looks()
		var decal: Image = looks.decals[0] if (looks.get("decals", []) as Array).size() == 1 else Image.new()
		check(materials.materials.skin.cell.size.x == 16 and decal.get_size() == Vector2i(case[1], case[1]), "a decal over a 16-texel cell keeps %s, %d: %s" % [case[2], case[1], decal.get_size()])


func _the_atlas_widens_before_its_cells_shrink() -> void:
	var dir := ProjectSettings.globalize_path("user://widen")
	DirAccess.make_dir_recursive_absolute(dir)
	Image.create_empty(1024, 1024, false, Image.FORMAT_RGBA8).save_png(dir.path_join("big.png"))
	FileAccess.open(dir.path_join("big.png.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: big\n")
	Image.create_empty(256, 256, false, Image.FORMAT_RGBA8).save_png(dir.path_join("small.png"))
	FileAccess.open(dir.path_join("small.png.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: small\n")
	var keys := []
	for i in 6:
		var name := "m%d" % i
		FileAccess.open(dir.path_join(name + ".mat"), FileAccess.WRITE).store_string("Material:\n  m_SavedProperties:\n    m_TexEnvs:\n    - _MainTex:\n        m_Texture: {guid: %s}\n" % ("big" if i < 5 else "small"))
		FileAccess.open(dir.path_join(name + ".mat.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % name)
		keys.append(name)
	var many := Materials.new(Assets.new(dir))
	for key: String in keys:
		many.use({"guid": key}, Color.WHITE)
	many.pack(keys)
	check(many.atlas_side > Materials.ATLAS and many.atlas_side < 4096 and many.atlas.get_width() == many.atlas_side, "five 1024 textures widen the atlas past %d, by steps, to %d" % [Materials.ATLAS, many.atlas_side])
	var kept := func(packed: Materials) -> bool: return keys.all(func(key: String) -> bool: return (packed.materials[key].cell as Rect2i).size == (packed.materials[key].image as Image).get_size())
	check(kept.call(many), "each keeps its own size: %s" % [keys.map(func(key: String) -> Vector2i: return (many.materials[key].cell as Rect2i).size)])
	var narrow := Materials.new(Assets.new(dir), Materials.ATLAS)
	for key: String in keys:
		narrow.use({"guid": key}, Color.WHITE)
	narrow.pack(keys)
	check(narrow.atlas_side == Materials.ATLAS and not kept.call(narrow), "held to %d wide, the same textures shrink: %d" % [Materials.ATLAS, narrow.atlas_side])
	var one := Materials.new(Assets.new(dir))
	one.use({"guid": "m5"}, Color.WHITE)
	one.pack(["m5"])
	check(one.atlas_side == Materials.ATLAS, "one that fits stays %d wide: %d" % [Materials.ATLAS, one.atlas_side])
	FileAccess.open(dir.path_join("big.png.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: big\nTextureImporter:\n  maxTextureSize: 256\n  platformSettings:\n  - serializedVersion: 3\n    buildTarget: DefaultTexturePlatform\n    maxTextureSize: 128\n  - serializedVersion: 3\n    buildTarget: Standalone\n    maxTextureSize: 512\n    overridden: 1\n  - serializedVersion: 3\n    buildTarget: Android\n    maxTextureSize: 2048\n    overridden: 1\n  - serializedVersion: 3\n    buildTarget: iPhone\n    maxTextureSize: 4096\n    overridden: 1\n")
	var shown := Materials.new(Assets.new(dir))
	shown.use({"guid": "m0"}, Color.WHITE)
	shown.pack(["m0"])
	check((shown.materials["m0"].cell as Rect2i).size == Vector2i(512, 512), "a texture packs at the widest size its PC import settings name, not a phone's: %s" % (shown.materials["m0"].cell as Rect2i).size)
	FileAccess.open(dir.path_join("big.png.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: big\nTextureImporter:\n  maxTextureSize: 256\n  platformSettings:\n  - serializedVersion: 3\n    buildTarget: Standalone\n    maxTextureSize: 2048\n    overridden: 0\n")
	var unset := Materials.new(Assets.new(dir))
	unset.use({"guid": "m0"}, Color.WHITE)
	unset.pack(["m0"])
	check((unset.materials["m0"].cell as Rect2i).size == Vector2i(256, 256), "a Standalone size not overridden does not count: %s" % (unset.materials["m0"].cell as Rect2i).size)
	var wide := Image.create_empty(Materials.LAYER + 512, Materials.LAYER + 512, false, Image.FORMAT_L8)
	var carried := Image.new()
	carried.load_png_from_buffer(Marshalls.base64_to_raw(Materials._layer(wide, Image.INTERPOLATE_NEAREST)))
	check(carried.get_size() == Vector2i(Materials.LAYER, Materials.LAYER), "a layer of a widened atlas is carried %d wide: %s" % [Materials.LAYER, carried.get_size()])


func _matcaps_and_emission_join_the_look() -> void:
	var dir := ProjectSettings.globalize_path("user://look")
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(name: String, guid: String, text: String) -> void:
		FileAccess.open(dir.path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	write.call("poi.shader", "poi", 'Shader "Hidden/Locked/.poiyomi/Poiyomi Toon" { Properties { _Matcap3HueShift ("Hue", Range(0, 1)) = 0 _Matcap3Replace ("Replace", Range(0, 1)) = 0 } }')
	write.call("mobile.shader", "mobile", 'Shader "VRChat/Mobile/Toon Standard" { Properties { _EmissionHueShift ("Hue", Range(0, 6.3)) = 0 _EmissionStrength ("Strength", Range(0, 2)) = 1 } }')
	write.call("body.mat", "body", """Material:
  m_Shader: {guid: poi}
  m_SavedProperties:
    m_TexEnvs:
    - _Matcap3:
        m_Texture: {guid: gold}
    - _Matcap3Mask:
        m_Texture: {guid: half}
    - _GlobalMaskTexture0:
        m_Texture: {guid: grey}
    m_Floats:
    - _Matcap3Enable: 1
    - _Matcap3UVMode: 2
    - _Matcap3Border: 0.43
    - _Matcap3Intensity: 5
    - _Matcap3Replace: 0.771
    - _Matcap3Multiply: 0.737
    - _Matcap3HueShift: 0
    - _Matcap3HueShiftEnabled: 1
    - _Matcap3MaskChannel: 1
    - _Matcap3MaskGlobalMask: 1
    - _Matcap3MaskGlobalMaskBlendType: 2
    - _GlobalMaskTexturesEnable: 1
    - _Matcap2Enable: 1
    - _Matcap2UVMode: 3
    - _LightingMode: 5
    - _LightingCapEnabled: 1
    - _LightingCap: 0.8
    m_Colors:
    - _Matcap3Color: {r: 1, g: 1, b: 1, a: 1}
""")
	write.call("skin.mat", "skin", "Material:\n  m_Shader: {guid: affc81f3d164d734d8f13053effb1c5c}\n")
	write.call("eye.mat", "eye", """Material:
  m_Shader: {guid: mobile}
  m_ValidKeywords:
  - USE_HUE_SHIFT
  m_SavedProperties:
    m_TexEnvs:
    - _EmissionMap:
        m_Texture: {guid: half}
    - _HueShiftMask:
        m_Texture: {guid: half}
    m_Floats:
    - _EmissionStrength: 0.8
    - _EmissionHueShift: 0
    - _MatcapEnable: 1
    m_Colors:
    - _EmissionColor: {r: 0.5, g: 1, b: 1, a: 1}
""")
	var half := Image.create_empty(2, 1, false, Image.FORMAT_RGBA8)
	half.set_pixel(0, 0, Color(1, 0, 0, 1))
	half.set_pixel(1, 0, Color(0, 1, 0, 1))
	half.save_png(dir.path_join("half.png"))
	FileAccess.open(dir.path_join("half.png.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: half\n")
	var gold := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	gold.fill(Color(1, 0.8, 0.2, 1))
	gold.save_png(dir.path_join("gold.png"))
	FileAccess.open(dir.path_join("gold.png.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: gold\n")
	var grey := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	grey.fill(Color(0.5, 1, 1, 1))
	grey.save_png(dir.path_join("grey.png"))
	FileAccess.open(dir.path_join("grey.png.meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: grey\n")
	var assets := Assets.new(dir)
	var materials := Materials.new(assets)
	materials.use({"guid": "body"}, Color.WHITE)
	materials.use({"guid": "eye"}, Color.WHITE)
	materials.use({"guid": "skin"}, Color.WHITE)
	materials.pack(["body", "eye", "skin"])
	var expressions := Expressions.new(assets, {})
	expressions.data = {
		"menu": [{"name": "Tint", "type": "radial", "parameter": "Tint", "axes": [], "value": 1, "icon": ""}],
		"parameters": [{"name": "Tint", "type": "float", "default": 0}],
		"layers": [{"weight": 1, "default": 0, "entry": [], "any": [], "states": [{"motion": {"clip": 0}, "transitions": [], "drivers": []}]}],
		"clips": [{"length": 0, "loop": false, "curves": [
			{"path": "Body", "attribute": "material._Matcap3HueShift", "class": "137", "keys": [[0.0, 0.0], [1.0, 1.0]]},
			{"path": "Eyes", "attribute": "material._EmissionHueShift", "class": "137", "keys": [[0.0, 0.0], [1.0, 6.28]]},
		]}],
	}
	var objs := {
		1: {"type": "GameObject", "data": {"m_Component": [{"component": {"fileID": "2"}}, {"component": {"fileID": "3"}}]}},
		2: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}}},
		3: {"type": "SkinnedMeshRenderer", "data": {"m_Materials": [{"guid": "body"}]}},
		4: {"type": "GameObject", "data": {"m_Component": [{"component": {"fileID": "5"}}, {"component": {"fileID": "6"}}]}},
		5: {"type": "Transform", "data": {"m_GameObject": {"fileID": "4"}}},
		6: {"type": "SkinnedMeshRenderer", "data": {"m_Materials": [{"guid": "eye"}]}},
	}
	var sk := Skeleton3D.new()
	var meshes := [{"node": "Body", "when": [], "renderers": [3], "weights": {}, "mesh": ArrayMesh.new()}, {"node": "Eyes", "when": [], "renderers": [6], "weights": {}, "mesh": ArrayMesh.new()}]
	var data := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, meshes, {}, objs, {"Body": 2, "Eyes": 5}, sk, materials, {})
	var fields: Array = data.targets.map(func(t: Dictionary) -> Array: return [t.effect.look[0].node, t.effect.look[0].field, t.effect.look[0].slot])
	check(fields == [["Body", "matcapHueShift", 2], ["Eyes", "emissionHue", 0]], "matcap hue and emission hue bind to their looks: %s" % [fields])
	var looks: Dictionary = data.get("looks", {})
	var entries: Array = looks.get("materials", [])
	check(entries.size() == 3, "every material has a look, the plain Toon Lit one for its lighting alone")
	if entries.size() == 3:
		check(entries[0].lighting == {"model": "flat", "cap": 0.8}, "Poiyomi's Flat lighting carries its Max Brightness: %s" % [entries[0].lighting])
		check(entries[1].lighting == {"model": "lit"}, "Toon Standard is lit by angle: %s" % [entries[1].lighting])
		check(entries[2].lighting == {"model": "flat"} and entries[2].matcaps == [null, null, null, null], "Toon Lit lights flat, uncapped: %s" % [entries[2]])
		var gilt: Variant = entries[0].matcaps[2]
		check(entries[0].matcaps[1] == null, "a matcap mapped by a view the renderer does not draw is left out")
		check(gilt is Dictionary and gilt.texture == 0 and gilt.mode == "reflection" and gilt.intensity == 5.0 and gilt.replace == 0.771 and gilt.multiply == 0.737 and gilt.hue == {"shift": 0.0, "space": 0.0, "select": 1.0} and gilt.circle == null, "the matcap carries its texture, mapping and strengths: %s" % [gilt])
		var glows: Variant = entries[1].emission
		check(glows is Dictionary and is_equal_approx(glows.color[0], Color(0.5, 0, 0).srgb_to_linear().r) and glows.color[1] == 1.0 and glows.strength == 0.8 and glows.hue == 0.0 and glows.shiftsHue, "the emission carries its linear colour, strength and hue: %s" % [glows])
		check(entries[1].matcaps == [null, null, null, null], "a Toon Standard material draws no matcap Poiyomi left saved in it")
	check((looks.get("matcaps", []) as Array).size() == 1, "each matcap texture is carried once")
	check(Materials.global_mask({"floats": {"_GlobalMaskTexturesEnable": "0"}}, 3) == {"property": "", "channel": 0} and Materials.mask_blend(0.7, 1.0, 1) == 0.0, "a global mask no texture fills is Poiyomi's whole 1, which a subtract blend still takes away")
	check(Materials.global_mask({"floats": {"_GlobalMaskTexturesEnable": "1", "_GlobalMaskModifiersDistanceEnable": "1"}}, 3) is bool, "a global mask a modifier sets is one the atlas cannot hold")
	var masks := Image.new()
	check(masks.load_png_from_buffer(Marshalls.base64_to_raw(looks.get("matcapMasks", ""))) == OK, "the matcap masks are a PNG")
	if not masks.is_empty():
		var cell: Rect2i = materials.materials.body.cell
		var left := masks.get_pixel(cell.position.x + cell.size.x / 4, cell.position.y + cell.size.y / 2)
		var right := masks.get_pixel(cell.position.x + 3 * cell.size.x / 4, cell.position.y + cell.size.y / 2)
		check(left.b < 0.2 and absf(right.b - 0.5) < 0.05 and left.r == 1.0, "slot three's channel holds its mask's chosen channel times its global mask: %s %s" % [left, right])
	var glow := Image.new()
	check(glow.load_png_from_buffer(Marshalls.base64_to_raw(looks.get("emission", ""))) == OK, "the emission map is a PNG")
	if not glow.is_empty():
		var eye: Rect2i = materials.materials.eye.cell
		check(glow.get_pixel(eye.position.x + eye.size.x / 4, eye.position.y + eye.size.y / 2).r > 0.8 and glow.get_pixelv(materials.materials.body.cell.get_center()) == Color.BLACK, "the emission map lies over the glowing material only")
	var hue := Image.new()
	check(hue.load_png_from_buffer(Marshalls.base64_to_raw(data.get("hueMask", ""))) == OK, "a shifting emission carries its hue mask")
	if not hue.is_empty():
		var eye: Rect2i = materials.materials.eye.cell
		check(hue.get_pixel(eye.position.x + eye.size.x / 4, eye.position.y + eye.size.y / 2).r < 0.2 and hue.get_pixel(eye.position.x + 3 * eye.size.x / 4, eye.position.y + eye.size.y / 2).r > 0.8, "the mask's chosen channel")
	sk.free()


func _submeshes_take_slots_in_first_use_order() -> void:
	var geometry := {"children": [{"name": "LayerElementMaterial", "children": [{"name": "Materials", "props": [PackedInt32Array([2, 2, 0, 1, 0, 2])]}]}]}
	check(FbxSlots._first_uses(geometry) == PackedInt32Array([2, 0, 1]), "slots follow the polygons' first use of each material")
	var assets := Assets.new(ProjectSettings.globalize_path("res://../tests/avatars"))
	for guid: String in ["skin", "eye", "metal"]:
		assets.by_guid[guid] = {"file": "", "path": "Assets/%s.mat" % guid.capitalize(), "meta": ""}
	var mesh := ArrayMesh.new()
	for fbx_name: String in ["Trim.003", "Skin.001", "Lining.002"]:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var named := StandardMaterial3D.new()
		named.resource_name = fbx_name
		mesh.surface_set_material(mesh.get_surface_count() - 1, named)
	var refs := ["skin", "eye", "metal", "metal"].map(func(guid: String) -> Dictionary: return {"fileID": "2100000", "guid": guid})
	var slots := UnityAvatar._slot_of(mesh, refs, assets, ["Skin.001", "Lining.002", "Trim.003"])
	check(slots == [2, 0, 1], "a slot past the last submesh, a second pass over it, leaves the first-use pairing: %s" % [slots])


## The descriptor's visemes and the FX layer's gesture faces become expressions: a face named for a mood takes that
## preset once, a later one of the same mood and any other keeps its own name; a clip no gesture plays, and a shape a
## face sets to zero, are no expression. Their shapes come first, visemes ahead of faces.
func _gesture_faces_become_expressions() -> void:
	var dir := ProjectSettings.globalize_path("user://faces")
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(name: String, guid: String, text: String) -> void:
		FileAccess.open(dir.path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(dir.path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	var clip := func(shapes: Dictionary) -> String:
		var text := "--- !u!74 &7400000\nAnimationClip:\n  m_FloatCurves:\n"
		for s: String in shapes:
			text += "  - curve:\n      m_Curve:\n      - time: 0\n        value: 0\n      - time: 0.1\n        value: %s\n    attribute: blendShape.%s\n    path: Body\n    classID: 137\n" % [shapes[s], s]
		return text
	write.call("Big Smile.anim", "c1", clip.call({"Mouth Up": 100, "Brow Up": 0}))
	write.call("Happy 2.anim", "c2", clip.call({"Eyes Closed": 50}))
	write.call("Wave.anim", "c3", clip.call({"Mouth Up": 30}))
	write.call("Outfit.anim", "c4", clip.call({"Skirt Short": 100}))
	var transition := func(id: int, to: int, event: String) -> String:
		return "--- !u!1101 &%d\nAnimatorStateTransition:\n  m_Conditions:\n  - m_ConditionMode: 6\n    m_ConditionEvent: %s\n    m_EventTreshold: 1\n  m_DstState: {fileID: %d}\n" % [id, event, to]
	var state := func(id: int, motion: String) -> String:
		return "--- !u!1102 &%d\nAnimatorState:\n  m_Motion: %s\n" % [id, motion]
	write.call("FX.controller", "f1", "".join([
		transition.call(1, 10, "GestureLeft"), transition.call(2, 11, "GestureRight"), transition.call(3, 12, "Outfit"),
		state.call(10, "{fileID: 7400000, guid: c1, type: 2}"), state.call(11, "{fileID: 20}"), state.call(12, "{fileID: 7400000, guid: c4, type: 2}"),
		"--- !u!206 &20\nBlendTree:\n  m_Childs:\n  - m_Motion: {fileID: 7400000, guid: c2, type: 2}\n  - m_Motion: {fileID: 7400000, guid: c3, type: 2}\n  - m_Motion: {fileID: 20}\n"]))
	var visemes := ["sil", "pp", "ff", "th", "dd", "kk", "ch", "ss", "nn", "rr", "A", "E", "I", "O", "U"]
	var descriptor := {"lipSync": "3", "VisemeBlendShapes": visemes, "baseAnimationLayers": [{"type": "3", "animatorController": {"fileID": "9100000", "guid": "f1"}}, {"type": "5", "animatorController": {"fileID": "9100000", "guid": "f1", "type": "2"}}]}
	var face := UnityAvatar._face(Prefabs.new(Assets.new(dir)), {}, descriptor)
	var bound := func(name: String) -> Dictionary:
		var out := {}
		for b: Dictionary in face.expressions.get(name, []):
			out[b.shape] = b.weight
		return out
	check(bound.call("aa") == {"A": 1.0} and bound.call("ee") == {"E": 1.0} and bound.call("ih") == {"I": 1.0} and bound.call("oh") == {"O": 1.0} and bound.call("ou") == {"U": 1.0}, "the visemes are VRM's: %s" % [face.expressions])
	check(bound.call("happy") == {"Mouth Up": 1.0} and bound.call("happy 2") == {"Eyes Closed": 0.5} and bound.call("wave") == {"Mouth Up": 0.3}, "faces by mood, then by name, at their last keyed weight: %s" % [face.expressions])
	check(face.expressions.size() == 8, "no expression for the outfit or a zeroed shape: %s" % [face.expressions.keys()])
	check(face.shapes.slice(0, 15) == visemes and face.shapes.slice(15) == ["Mouth Up", "Eyes Closed", "Mouth Up"], "visemes first, then the faces' shapes: %s" % [face.shapes])
	check(UnityAvatar._face(Prefabs.new(Assets.new(dir)), {}, {"lipSync": "1", "VisemeBlendShapes": visemes}).expressions.is_empty(), "visemes count only where it lip-syncs by blend shape")

## Renderers merged into one mesh keep one shape for a name only where Unity weighs it alike in each: one renderer's saved
## weight or clip never moves another's. A shape alone in its mesh under its source's name keeps that name.
func _a_shape_name_keeps_each_renderers_weight() -> void:
	var dir := ProjectSettings.globalize_path("user://shapes")
	DirAccess.make_dir_recursive_absolute(dir)
	var root := Node3D.new()
	var source := Skeleton3D.new()
	source.name = "Source"
	source.add_bone("Hips")
	root.add_child(source)
	var nodes: Array[GLTFNode] = []
	var objects := {}
	var objs := {}
	var renderers := []
	var paths := {}
	for i in 3:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(i, 0, 0), Vector3(i, 1, 0), Vector3(i + 1, 0, 0)])
		arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
		var moved := []
		moved.resize(Mesh.ARRAY_MAX)
		moved[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0.1), Vector3(0, 0, 0.1), Vector3(0, 0, 0.1)])
		var mesh := ArrayMesh.new()
		mesh.add_blend_shape("Shorts")
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [moved])
		var mi := MeshInstance3D.new()
		mi.name = "M%d" % i
		mi.mesh = mesh
		mi.skin = Skin.new()
		mi.skin.add_bind(0, Transform3D.IDENTITY)
		mi.skeleton = NodePath("../Source")
		root.add_child(mi)
		var node := GLTFNode.new()
		node.resource_name = mi.name
		nodes.append(node)
		objects[100 + i] = {"type": "SkinnedMeshRenderer", "data": {"m_Mesh": {"fileID": str(10 + i)}}, "node": i}
		var go := 3 * i + 1
		objs[go] = {"type": "GameObject", "data": {"m_Name": "R%d" % i, "m_Component": [{"component": {"fileID": str(go + 1)}}, {"component": {"fileID": str(go + 2)}}]}}
		objs[go + 1] = {"type": "Transform", "data": {"m_GameObject": {"fileID": str(go)}}}
		objs[go + 2] = {"type": "SkinnedMeshRenderer", "data": {"m_GameObject": {"fileID": str(go)}, "m_Mesh": {"guid": "model", "fileID": str(10 + i)}, "m_BlendShapeWeights": ["0" if i == 0 else "100"], "m_Materials": []}}
		renderers.append([go + 2, go, []])
		paths["R%d" % i] = go + 1
	var state := GLTFState.new()
	state.set_nodes(nodes)
	var prefabs := Prefabs.new(Assets.new(dir))
	prefabs.assets.by_guid["model"] = {"file": "", "path": "model.fbx", "meta": ""}
	prefabs.models["model"] = {"scene": root, "state": state, "objects": objects}
	UnityAvatar._slot_cache["model"] = {}
	var sk := Skeleton3D.new()
	sk.add_bone("Hips")
	var rests: Array[Transform3D] = [Transform3D.IDENTITY]
	var materials := Materials.new(prefabs.assets)
	var merged := UnityAvatar._merge(prefabs, materials, objs, renderers, {"slots": {}, "targets": [], "by_object": {}}, {}, {}, sk, rests, 1.0, {})
	check(merged.meshes.size() == 1 and merged.meshes[0].weights == {"Shorts": 0.0, "Shorts (2)": 1.0}, "a name saved at two weights is two shapes, each at its renderer's weight: %s" % [merged.meshes.map(func(m: Dictionary) -> Dictionary: return m.weights)])
	check(merged.shapes == {3: {"Shorts": "Shorts"}, 6: {"Shorts": "Shorts (2)"}, 9: {"Shorts": "Shorts (2)"}}, "renderers weighed alike share their shape: %s" % [merged.shapes])
	var switched := renderers.map(func(r: Array) -> Array: return [r[0], r[1], [] if r[0] == 3 else [[0, 1]]])
	var apart := UnityAvatar._merge(prefabs, materials, objs, switched, {"slots": {}, "targets": [], "by_object": {}}, {}, {}, sk, rests, 1.0, {})
	var names: Array = apart.meshes.map(func(m: Dictionary) -> Array: return [m.renderers, m.weights])
	check(names == [[[3], {"Shorts": 0.0}], [[6, 9], {"Shorts": 1.0}]], "each mesh names its shape as the source does: %s" % [names])
	var animated := {6: {"Shorts": [[0, [[0.0, 50.0]]]]}}
	var split := UnityAvatar._merge(prefabs, materials, objs, renderers, {"slots": {}, "targets": [], "by_object": {}}, animated, {}, sk, rests, 1.0, {})
	check(split.shapes[6].Shorts != split.shapes[9].Shorts, "a clip moving one renderer's shape parts it from a renderer the clip leaves: %s" % [split.shapes])
	var expressions := Expressions.new(prefabs.assets, {})
	expressions.data = {
		"menu": [{"name": "Shorts", "type": "toggle", "parameter": "Shorts", "axes": [], "value": 1, "icon": ""}],
		"parameters": [{"name": "Shorts", "type": "bool", "default": 0}],
		"layers": [{"weight": 1, "default": 0, "entry": [], "any": [], "states": [{"motion": {"clip": 0}, "transitions": [], "drivers": []}]}],
		"clips": [{"length": 0, "loop": false, "curves": [{"path": "R0", "attribute": "blendShape.Shorts", "class": "137", "keys": [[0.0, 50.0]]}]}],
	}
	merged.meshes[0].node = "Body"
	var data := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, merged.meshes, merged.shapes, objs, paths, sk, materials, {})
	check(data.targets.size() == 1 and data.targets[0].effect.morph == [["Body", "Shorts"]] and data.targets[0].default == 0.0, "the clip moves only its own renderer's shape, from that renderer's weight: %s" % [data.targets])
	root.free()
	sk.free()


## A VRCFury Armature Link onto a humanoid bone applies when the avatar's armature is unpacked into the scene, its
## objects no longer the model's: the bone is the one the model's renderer skins to. A link with no target is reported.
func _an_unpacked_armature_still_takes_a_link() -> void:
	var objs := {}
	for spec: Array in [[10, "Avatar", 0, Vector3.ZERO], [11, "Armature", 10, Vector3.ZERO], [12, "Hips", 11, Vector3(0, 1, 0)], [20, "Part", 10, Vector3(0, 0.9, 0.2)], [21, "Bone", 20, Vector3(0, 0.1, 0)], [30, "Hips", 10, Vector3(0, 2, 0)]]:
		objs[spec[0] + 100] = {"type": "GameObject", "guid": "scene", "data": {"m_Name": spec[1], "m_Component": [{"component": {"fileID": str(spec[0])}}]}}
		objs[spec[0]] = {"type": "Transform", "data": {"m_GameObject": {"fileID": str(spec[0] + 100)}, "m_Father": {"fileID": str(spec[2])}, "m_LocalPosition": {"x": str(spec[3].x), "y": str(spec[3].y), "z": str(spec[3].z)}}}
	objs[40] = {"type": "SkinnedMeshRenderer", "data": {"m_Mesh": {"guid": "main"}, "m_Bones": [{"fileID": "12"}]}}
	objs[41] = {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "120"}, "references": {"RefIds": [{"type": {"class": "ArmatureLink"}, "data": {"propBone": {"fileID": "120"}, "linkTo": [{"bone": "0", "useBone": "1"}]}}]}}}
	objs[42] = {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "121"}, "references": {"RefIds": [{"type": {"class": "ArmatureLink"}, "data": {"propBone": {"fileID": "121"}, "linkTo": [{"bone": "8", "useBone": "1"}]}}]}}}
	var bones := UnityAvatar._model_bones(objs, 10, "main", [[40, 111, []]])
	check(bones.get("Hips") == 12, "the skinned Hips is the avatar's, not another object of that name: %s" % [bones])
	var before := UnityAvatar._world_transform(objs, 21)
	var report := {}
	UnityAvatar._attach_armatures(objs, 10, bones, {"human": {"Hips": "Hips"}}, report)
	check(objs[20].data.m_Father.fileID == "12" and UnityAvatar._world_transform(objs, 21).is_equal_approx(before), "the part hangs from the hips where the scene placed it")
	check(str(report.get("armature links with no target in the avatar", "")).contains("121"), "a link whose bone the avatar lacks is reported: %s" % [report])


## A clip's Euler rotation and position curves on a non-humanoid bone, and a PhysBone's enabled flag, become targets:
## rotation in Unity's own degrees with the transform's authored angles as its rest, position as an offset along the
## bone's mirrored axis, the PhysBone's flag as a switch.
func _transform_and_physbone_curves_bind() -> void:
	var objs := {
		1: {"type": "GameObject", "data": {"m_Name": "Avatar", "m_Component": [{"component": {"fileID": "2"}}]}},
		2: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}, "m_Father": {"fileID": "0"}}},
		3: {"type": "GameObject", "data": {"m_Name": "Tail", "m_Component": [{"component": {"fileID": "4"}}, {"component": {"fileID": "5"}}]}},
		4: {"type": "Transform", "data": {"m_GameObject": {"fileID": "3"}, "m_Father": {"fileID": "2"}, "m_LocalPosition": {"x": "0.5", "y": "1", "z": "0"}, "m_LocalRotation": {"x": "0", "y": "0", "z": "0", "w": "1"}, "m_LocalEulerAnglesHint": {"x": "-85", "y": "0", "z": "0"}}},
		5: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "3"}, "m_Enabled": "1", "m_Script": {"guid": "physbone"}, "rootTransform": {"fileID": "4"}, "pull": "0.2"}},
	}
	var sk := Skeleton3D.new()
	sk.add_bone("Hips")
	sk.add_bone("Tail")
	sk.add_bone("Tail End")
	sk.set_bone_parent(1, 0)
	sk.set_bone_parent(2, 1)
	sk.set_bone_rest(0, Transform3D.IDENTITY.scaled(Vector3.ONE * 2.0))
	sk.set_meta("unity_bones", {3: 1})
	sk.set_meta("humanoid_bones", {0: ["hips", "Hips"]})
	var expressions := Expressions.new(Assets.new(ProjectSettings.globalize_path("user://")), {})
	var curve := func(attribute: String, cls: String, keys: Array, script := "") -> Dictionary: return {"path": "Tail", "attribute": attribute, "class": cls, "script": script, "keys": keys}
	expressions.data = {
		"menu": [{"name": "Throb", "type": "toggle", "parameter": "Throb", "axes": [], "value": 1, "icon": ""}],
		"parameters": [{"name": "Throb", "type": "bool", "default": 0}],
		"layers": [{"weight": 1, "default": 0, "entry": [], "any": [], "states": [{"motion": {"clip": 0}, "transitions": [], "drivers": []}]}],
		"clips": [{"length": 1, "loop": true, "curves": [curve.call("localEulerAnglesRaw.x", "4", [[0.0, -85.0], [1.0, -80.0]]), curve.call("m_LocalPosition.x", "4", [[0.0, 0.5, 0.0, 0.0], [1.0, 0.75, 0.0, 0.0]]), curve.call("m_Enabled", "114", [[0.0, 0.0]], "physbone"), curve.call("m_Enabled", "114", [[0.0, 0.0]], "other script")]}],
	}
	var report := {}
	var paths := {"": 2, "Tail": 4}
	var switches := UnityAvatar._switches(expressions, objs, paths)
	check(switches.by_object.keys() == [5], "the PhysBone's flag is a switch, the other script's is not: %s" % [switches.by_object])
	var data := UnityAvatar._bound(expressions, switches, [], {}, objs, paths, sk, Materials.new(expressions.assets), report)
	var effects: Array = data.targets.map(func(t: Variant) -> Variant: return t.effect)
	check(effects.size() == 3, "the PhysBone switch, rotation and position bind: %s" % [effects])
	if effects.size() == 3:
		check(effects[0] == "switch" and data.targets[0].default == 1.0 and data.clips[0].curves[2].target == 0 and data.clips[0].curves[2].step, "the PhysBone's flag is a switch, on as the scene has it")
		check(effects[1] == {"rotation": {"node": "Tail", "axis": 0, "rest": [-85.0, 0.0, 0.0]}} and data.targets[1].default == -85.0, "rotation keeps Unity's degrees, its rest the authored angles: %s" % [data.targets[1]])
		check(data.clips[0].curves[0].keys == [[0.0, -85.0], [1.0, -80.0]], "rotation keys stay as authored")
		check(effects[2] == {"translation": {"node": "Tail", "direction": [-0.5, 0.0, 0.0]}} and data.targets[2].default == 0.0, "position moves along the mirrored X, in the parent's output units: %s" % [effects[2]])
		check(data.clips[0].curves[1].keys == [[0.0, 0.0, 0.0, 0.0], [1.0, 0.25, 0.0, 0.0]], "position keys are offsets from rest, tangents kept: %s" % [data.clips[0].curves[1].keys])
	sk.set_meta("unity_bones", {3: 0})
	var humanoid := UnityAvatar._bound(expressions, UnityAvatar._switches(expressions, objs, paths), [], {}, objs, paths, sk, Materials.new(expressions.assets), {})
	check(humanoid.targets.size() == 1 and humanoid.targets[0].effect == "switch", "transform curves on a humanoid bone are left to the muscles")
	sk.free()


## The synthetic clip reads into the keys Unity 2022.3 itself reports for it (tests/unity/unity-curves.json, written by
## tests/unity/Sample.cs).
func _curves_keep_their_unity_tangents() -> void:
	var unity: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../tests/unity/unity-curves.json"))
	var objects := Yaml.objects(FileAccess.get_file_as_string("res://../tests/unity/curve-tangents.anim"))
	var dir := ProjectSettings.globalize_path("user://curves")
	DirAccess.make_dir_recursive_absolute(dir)
	var expressions := Expressions.new(Assets.new(dir), {})
	expressions.data = {"clips": []}
	var clip: Dictionary = expressions.data.clips[expressions._clip("anim", 7400000, objects[7400000].data)]
	check(clip.curves.size() == unity.size(), "every curve reads: %s" % [clip.curves.size()])
	for c: Dictionary in clip.curves:
		var want: Array = unity.get(c.path, {}).get("keys", [])
		var same: bool = want.size() == c["keys"].size()
		for i in mini(want.size(), c["keys"].size()):
			var got: Array = c["keys"][i]
			same = same and got.size() == want[i].size()
			for j in mini(got.size(), want[i].size()):
				same = same and ((got[j] == null and want[i][j] == null) or (got[j] != null and want[i][j] != null and absf(got[j] - want[i][j]) < 1e-6))
		check(same, "%s keeps Unity's slopes, constant tangents and weights: %s" % [c.path, c["keys"]])
	check(UnityAvatar._scaled([[0.5, 100.0, 50.0, null, 0.2, 0.7]], 0.01) == [[0.5, 1.0, 0.5, null, 0.2, 0.7]], "a rescaled curve scales its slopes with its values and keeps its weights")


## VRCFury Toggles become what VRCFury builds at upload: a menu control at the toggle's path, its parameter, and a layer
## whose on state holds the actions as a clip (an object turned on, a blend shape set), siblings of one exclusive tag
## turned off on entry; a MoveMenuItem and SetIcon then apply. An object toggled on is the menu's switch, resting as
## its toggle starts.
func _vrcfury_toggles_join_the_menu() -> void:
	var objs := {
		1: {"type": "GameObject", "data": {"m_Name": "Avatar", "m_Component": [{"component": {"fileID": "2"}}, {"component": {"fileID": "9"}}]}},
		2: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}, "m_Father": {"fileID": "0"}}},
		3: {"type": "GameObject", "data": {"m_Name": "Hat", "m_IsActive": "1", "m_Component": [{"component": {"fileID": "4"}}, {"component": {"fileID": "5"}}]}},
		4: {"type": "Transform", "data": {"m_GameObject": {"fileID": "3"}, "m_Father": {"fileID": "2"}}},
		5: {"type": "SkinnedMeshRenderer", "data": {"m_GameObject": {"fileID": "3"}}},
	}
	var refs := [
		{"rid": "1", "type": {"class": "Toggle"}, "data": {"name": "Clothes/Hat", "saved": "1", "defaultOn": "0", "enableExclusiveTag": "1", "exclusiveTag": "head", "state": {"actions": [{"rid": "2"}, {"rid": "3"}]}}},
		{"rid": "2", "type": {"class": "ObjectToggleAction"}, "data": {"obj": {"fileID": "3"}, "mode": "0"}},
		{"rid": "3", "type": {"class": "BlendShapeAction"}, "data": {"blendShape": "Squash", "blendShapeValue": "40", "allRenderers": "1"}},
		{"rid": "4", "type": {"class": "Toggle"}, "data": {"name": "Clothes/Crown", "useGlobalParam": "1", "globalParam": "Crown", "enableExclusiveTag": "1", "exclusiveTag": "head", "state": {"actions": []}}},
		{"rid": "5", "type": {"class": "Toggle"}, "data": {"name": "Body/Size", "slider": "1", "defaultSliderValue": "0.25", "state": {"actions": [{"rid": "3"}]}}},
		{"rid": "6", "type": {"class": "MoveMenuItem"}, "data": {"fromPath": "Body/Size", "toPath": "Size"}},
		{"rid": "7", "type": {"class": "SetIcon"}, "data": {"path": "Clothes/Hat", "icon": {"objRef": {"guid": "icon"}}}},
	]
	objs[9] = {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "1"}, "config": {"features": refs.filter(func(r: Dictionary) -> bool: return not r.type.class.ends_with("Action")).map(func(r: Dictionary) -> Dictionary: return {"rid": r.rid})}, "references": {"RefIds": refs}}}
	var expressions := Expressions.new(Assets.new(ProjectSettings.globalize_path("user://")), {})
	var paths := {"": 2, "Hat": 4}
	VRCFury.apply(expressions, objs, paths)
	var menu: Array = expressions.data.get("menu", [])
	check(menu.size() == 3 and menu[0].name == "Clothes" and menu[2].name == "Size" and menu[2].type == "radial" and menu[2].axes == ["VF2_Body/Size"], "the toggles' paths make the menu, the slider moved to the top: %s" % [menu])
	if menu.size() < 2:
		return
	var hat: Dictionary = menu[0].controls[0]
	check(hat.name == "Hat" and hat.type == "toggle" and hat.parameter == "VF0_Clothes/Hat" and hat.icon == "icon", "the hat is a toggle of its own parameter with its icon: %s" % [hat])
	check(menu[0].controls[1].parameter == "Crown", "a global parameter keeps its name")
	var hat_parameter: Array = expressions.data.parameters.filter(func(p: Dictionary) -> bool: return p.name == "VF0_Clothes/Hat")
	check(hat_parameter.size() == 1 and hat_parameter[0].type == "bool" and hat_parameter[0].saved and hat_parameter[0].default == 0.0, "the hat's parameter is a saved bool, off: %s" % [hat_parameter])
	var size: Array = expressions.data.parameters.filter(func(p: Dictionary) -> bool: return p.name == "VF2_Body/Size")
	check(size.size() == 1 and size[0].type == "float" and size[0].default == 0.25, "the slider's parameter is a float at its default")
	var layer: Dictionary = expressions.data.layers[0]
	var curves: Array = expressions.data.clips[layer.states[1].motion.clip].curves
	check(curves.any(func(c: Dictionary) -> bool: return c.path == "Hat" and c.attribute == "m_IsActive" and c["class"] == "1" and c["keys"][0][1] == 1.0) and curves.any(func(c: Dictionary) -> bool: return c.path == "Hat" and c.attribute == "blendShape.Squash" and c["keys"][0][1] == 40.0), "the on state turns the hat on and sets the shape: %s" % [curves])
	var off: Array = expressions.data.clips[layer.states[0].motion.clip].curves
	check(off.size() == 1 and off[0].path == "Hat" and off[0]["keys"][0][1] == 0.0, "the off state turns the hat off, whatever the scene has: %s" % [off])
	check(layer.states[1].drivers == [{"parameter": "Crown", "drive": "set", "value": 0.0, "min": 0.0, "max": 1.0, "chance": 1.0, "source": ""}], "turning the hat on turns off the crown of its tag: %s" % [layer.states[1].drivers])
	check(layer.states[0].transitions[0].conditions[0] == {"parameter": "VF0_Clothes/Hat", "mode": "if", "threshold": 0.0}, "the parameter enters the on state")
	var switches := UnityAvatar._switches(expressions, objs, paths)
	check(switches.by_object.has(3) and switches.targets[switches.by_object[3]].default == 0.0, "the hat is the menu's switch, resting off as its toggle starts though the scene shows it")


## A FullController's bindings are below its object when that path is there, otherwise from the avatar's root; a
## rewrite renames a path's prefix and a delete drops it.
func _vrcfury_full_controller_paths_resolve_from_their_object() -> void:
	var paths := {"": 1, "Wings": 2, "Wings/Left": 3, "Body": 4}
	check(VRCFury._resolve(paths, "Wings", "Left") == "Wings/Left", "a path below the controller's object resolves there")
	check(VRCFury._resolve(paths, "Wings", "Body") == "Body", "a path only the root has resolves from the root")
	check(VRCFury._rewritten([{"from": "Old", "to": "Left"}], "Old/Tip") == "Left/Tip", "a rewrite renames the prefix")
	check(VRCFury._rewritten([{"from": "Gone", "delete": "1"}], "Gone/Tip") == null, "a delete drops the binding")
	var full := range(10).map(func(i: int) -> Dictionary: return {"name": str(i), "type": "toggle"})
	VRCFury._paged(full)
	check(full.size() == 8 and full[7].name == "Next" and (full[7].controls as Array).size() == 3, "a menu past VRChat's eight pages its rest into Next: %s" % [full])
	var menu := []
	VRCFury._merge(VRCFury._submenu(menu, ["Wings"]), [{"name": "Flap", "type": "toggle"}, {"name": "More", "type": "submenu", "controls": [{"name": "Glow", "type": "toggle"}]}])
	VRCFury._merge(VRCFury._submenu(menu, ["Wings"]), [{"name": "More", "type": "submenu", "controls": [{"name": "Fold", "type": "toggle"}]}])
	check(menu.size() == 1 and menu[0].controls.size() == 2 and (menu[0].controls[1].controls as Array).map(func(c: Dictionary) -> String: return c.name) == ["Glow", "Fold"], "menus under one prefix merge, submenus of one name join: %s" % [menu])


## A Poiyomi UDIM discard tile the menu animates is a switch on its renderer, and a tile discarded at rest that nothing
## changes is a switch that stays on; each vertex of a material that discards falls in the tile its UV names, counted
## from Unity's V, drawn while its tile's switch is off.
func _a_udim_discard_tile_is_a_switch() -> void:
	var objs := {
		1: {"type": "GameObject", "data": {"m_Name": "Avatar", "m_Component": [{"component": {"fileID": "2"}}]}},
		2: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}, "m_Father": {"fileID": "0"}}},
		3: {"type": "GameObject", "data": {"m_Name": "Body", "m_Component": [{"component": {"fileID": "4"}}, {"component": {"fileID": "5"}}]}},
		4: {"type": "Transform", "data": {"m_GameObject": {"fileID": "3"}, "m_Father": {"fileID": "2"}}},
		5: {"type": "SkinnedMeshRenderer", "data": {"m_GameObject": {"fileID": "3"}}},
	}
	var expressions := Expressions.new(Assets.new(ProjectSettings.globalize_path("user://")), {})
	expressions.data = {"menu": [], "parameters": [], "layers": [], "clips": [{"length": 0, "loop": false, "curves": [{"path": "Body", "attribute": "material._UDIMDiscardRow1_0", "class": "137", "keys": [[0.0, 0.0]]}]}]}
	var switches := UnityAvatar._switches(expressions, objs, {"": 2, "Body": 4})
	var animated: int = switches.by_object.get(UnityAvatar._udim_key(5, 1, 0), -1)
	check(animated >= 0 and switches.by_curve.get("Body|material._UDIMDiscardRow1_0|137") == animated, "the animated tile is a switch of the renderer")
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	# Godot's V runs down from Unity's: Unity (0.5, 1.5) is Godot (0.5, -0.5).
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(0.5, -0.5), Vector2(2.5, 0.5), Vector2(0.5, 0.5)])
	var floats := {"_EnableUDIMDiscardOptions": "1", "_UDIMDiscardUV": "1", "_UDIMDiscardRow1_0": "1", "_UDIMDiscardRow0_2": "1"}
	var report := {}
	var tiles := UnityAvatar._udim_tiles(switches, 5, {"floats": floats}, arrays, report)
	check(tiles.get("vertex", []) == ["1:0", "0:2", "0:0"], "each vertex lies in its Unity tile: %s" % [tiles])
	var still: int = switches.by_object.get(UnityAvatar._udim_key(5, 0, 2), -1)
	check(tiles.get("1:0") == [[animated, 0]] and switches.targets[animated].default == 1.0, "the animated tile draws while its switch is off, discarded at rest")
	check(still >= 0 and tiles.get("0:2") == [[still, 0]] and switches.targets[still].default == 1.0, "a tile only discarded at rest is a switch that stays on")
	check(not tiles.has("0:0"), "a tile nothing discards needs no switch")
	check(UnityAvatar._udim_tiles(switches, 5, {"floats": {}}, arrays, report).is_empty(), "a material that discards nothing splits nothing")


## A 1D blend tree reads no second parameter, so a live one makes no radial effective: a radial whose own layer moves
## nothing is cut even while another radial's tree moves something.
func _a_radial_moving_nothing_is_cut_beside_a_live_one() -> void:
	var objs := {
		1: {"type": "GameObject", "data": {"m_Name": "Avatar", "m_Component": [{"component": {"fileID": "2"}}]}},
		2: {"type": "Transform", "data": {"m_GameObject": {"fileID": "1"}, "m_Father": {"fileID": "0"}}},
		3: {"type": "GameObject", "data": {"m_Name": "Tail", "m_Component": [{"component": {"fileID": "4"}}, {"component": {"fileID": "5"}}]}},
		4: {"type": "Transform", "data": {"m_GameObject": {"fileID": "3"}, "m_Father": {"fileID": "2"}}},
		5: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "3"}, "m_Enabled": "1", "m_Script": {"guid": "physbone"}, "rootTransform": {"fileID": "4"}, "pull": "0.2"}},
	}
	var tree := func(parameter: String, clip: int) -> Dictionary: return {"blend": "1d", "parameters": [parameter, ""], "children": [{"motion": {"clip": clip}, "threshold": 1.0, "parameter": "", "speed": 1.0, "offset": 0.0, "position": [0.0, 0.0]}]}
	var expressions := Expressions.new(Assets.new(ProjectSettings.globalize_path("user://")), {})
	expressions.data = {
		"menu": [{"name": "Live", "type": "radial", "parameter": "", "axes": ["Live"], "value": 1, "icon": ""}, {"name": "Dead", "type": "radial", "parameter": "", "axes": ["Dead"], "value": 1, "icon": ""}],
		"parameters": [{"name": "Live", "type": "float", "default": 0}, {"name": "Dead", "type": "float", "default": 0}],
		"layers": [
			{"weight": 1, "default": 0, "entry": [], "any": [], "states": [{"motion": tree.call("Live", 0), "transitions": [], "drivers": []}]},
			{"weight": 1, "default": 0, "entry": [], "any": [], "states": [{"motion": tree.call("Dead", 1), "transitions": [], "drivers": []}]}],
		"clips": [
			{"length": 0, "loop": false, "curves": [{"path": "Tail", "attribute": "m_Enabled", "class": "114", "script": "physbone", "keys": [[0.0, 0.0]]}]},
			{"length": 0, "loop": false, "curves": [{"path": "Nowhere", "attribute": "m_IsActive", "class": "1", "script": "", "keys": [[0.0, 0.0]]}]}],
	}
	var paths := {"": 2, "Tail": 4}
	var switches := UnityAvatar._switches(expressions, objs, paths)
	var sk := Skeleton3D.new()
	var data := UnityAvatar._bound(expressions, switches, [], {}, objs, paths, sk, Materials.new(expressions.assets), {})
	sk.free()
	check((data.menu as Array).map(func(c: Dictionary) -> String: return c.name) == ["Live"], "only the radial that moves something stays: %s" % [data.menu])


## A 1D blend child that leaves a target its sibling animates holds that target at its default, so the blend leaves
## rest as Unity's does rather than growing from zero; a direct blend is left as it is.
func _a_blend_child_holds_what_its_sibling_animates_at_rest() -> void:
	var child := func(motion: Dictionary, threshold: float) -> Dictionary: return {"motion": motion, "threshold": threshold, "parameter": "", "speed": 1.0, "offset": 0.0, "position": [0.0, 0.0]}
	var data := {"clips": [{"length": 0.0, "loop": false, "curves": [{"target": 0, "step": false, "keys": [[0.0, 2.0, 0.0, 0.0]]}]}]}
	var tree := {"blend": "1d", "parameters": ["Size", ""], "children": [child.call({}, 0.0), child.call({"clip": 0}, 1.0)]}
	var direct := {"blend": "direct", "parameters": ["", ""], "children": [child.call({}, 0.0), child.call({"clip": 0}, 1.0)]}
	var targets := [{"effect": {"scale": {"node": "Tail", "axis": 0}}, "default": 0.5}]
	UnityAvatar._hold_unanimated(data, targets, tree)
	UnityAvatar._hold_unanimated(data, targets, direct)
	var rest: Variant = tree.children[0].motion.get("clip")
	check(rest is int and data.clips[rest].curves == [{"target": 0, "step": false, "keys": [[0.0, 0.5, 0.0, 0.0]]}], "the empty child holds the scale at its default: %s" % [data.clips])
	check(tree.children[1].motion.clip == 0 and data.clips[0].curves.size() == 1, "the animating child is unchanged")
	check(direct.children[0].motion.is_empty(), "a direct blend's children are left alone")
	var nested := {"blend": "1d", "parameters": ["Outer", ""], "children": [child.call({"clip": 0}, 0.0), child.call({"blend": "1d", "parameters": ["Inner", ""], "children": [child.call({}, 0.0)]}, 1.0)]}
	UnityAvatar._hold_unanimated(data, targets, nested)
	var inner: Variant = nested.children[1].motion.children[0].motion.get("clip")
	check(inner is int and data.clips[inner].curves[0]["keys"][0][1] == 0.5, "a subtree's child holds what the enclosing tree's sibling animates")


## A FullController's parameter names change everywhere its layers and menu read or set them.
func _a_full_controller_renames_its_layers_and_menu() -> void:
	var renamed := func(n: String) -> String: return "VF3_" + n if n != "" and n != "IsLocal" else n
	var layers := [{"entry": [{"to": 0, "conditions": [{"parameter": "Hat", "mode": "if", "threshold": 0.0}]}], "any": [], "states": [
		{"motion": {"blend": "1d", "parameters": ["Size", ""], "children": [{"motion": {}, "parameter": ""}]}, "transitions": [{"to": 0, "conditions": [{"parameter": "IsLocal", "mode": "if", "threshold": 0.0}]}], "drivers": [{"parameter": "Hat", "source": "Size"}]}]}]
	var menu := [{"name": "More", "type": "submenu", "parameter": "", "axes": [], "controls": [{"name": "Hat", "type": "toggle", "parameter": "Hat", "axes": []}, {"name": "Size", "type": "radial", "parameter": "", "axes": ["Size"]}]}]
	VRCFury._rename_layers(layers, renamed)
	VRCFury._rename_menu(menu, renamed)
	var state: Dictionary = layers[0].states[0]
	check(layers[0].entry[0].conditions[0].parameter == "VF3_Hat" and state.motion.parameters == ["VF3_Size", ""] and state.drivers[0] == {"parameter": "VF3_Hat", "source": "VF3_Size"}, "conditions, blend parameters and drivers take the new names: %s" % [layers])
	check(state.transitions[0].conditions[0].parameter == "IsLocal", "VRChat's own parameter keeps its name")
	check(menu[0].controls[0].parameter == "VF3_Hat" and menu[0].controls[1].axes == ["VF3_Size"], "the menu's controls take the new names: %s" % [menu])

func _installed_packages_lend_only_missing_images() -> void:
	var root := ProjectSettings.globalize_path("user://lend")
	var write := func(dir: String, name: String, guid: String, text: String) -> void:
		DirAccess.make_dir_recursive_absolute(root.path_join(dir))
		FileAccess.open(root.path_join(dir).path_join(name), FileAccess.WRITE).store_string(text)
		FileAccess.open(root.path_join(dir).path_join(name + ".meta"), FileAccess.WRITE).store_string("fileFormatVersion: 2\nguid: %s\n" % guid)
	write.call("avatar", "own.png", "own", "avatar's")
	write.call("avatar", "shared.png", "shared", "avatar's")
	write.call("packages/shader", "matcap.png", "matcap", "package's")
	write.call("packages/shader", "shared.png", "shared", "package's")
	write.call("packages/sdk", "other.prefab", "prefab", "package's")
	var alone := Assets.new(root.path_join("avatar"))
	var lent := Assets.new(root.path_join("avatar"), root.path_join("packages"))
	check(not alone.by_guid.has("matcap") and lent.text("matcap") == "package's", "an image the package names but lacks is read from the installed packages")
	check(lent.text("shared") == "avatar's" and lent.text("own") == "avatar's", "the package's own assets win")
	check(not lent.by_guid.has("prefab"), "the installed packages lend images alone")
