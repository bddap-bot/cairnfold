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
const SpringDefinition = preload("res://addons/avatar_workshop/spring_definition.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_xxhash_matches_the_reference()
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
	_sources_binding_one_bone_differently_share_one_bind()
	_a_branching_physbone_root_stays_still()
	_a_physbone_ends_at_its_endpoint()
	_a_physbone_carries_its_limit()
	_legacy_springs_keep_their_root_and_endpoint()
	_a_dynamic_bone_sizes_by_its_own_transform()
	_colliders_keep_their_shape_side_and_bone()
	_a_collider_rides_its_bone_where_unity_places_it()
	_components_off_when_the_avatar_loads_do_not_run()
	_linked_props_keep_their_placement_and_bone_identity()
	_a_transform_the_skeleton_lacks_becomes_a_bone()
	_a_menu_toggle_switches_a_hidden_renderer()
	_a_hue_radial_keeps_its_material_binding()
	_a_decal_alpha_binds_its_atlas_layer()
	_matcaps_and_emission_join_the_look()
	_submeshes_take_slots_in_first_use_order()
	_gesture_faces_become_expressions()
	_a_shape_name_keeps_each_renderers_weight()
	finish()


## XXH64's published values, and a model object's file ID as Unity's importer names it.
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
			var bones := Prefabs._list(object.data.get("m_Bones"))
			check(not bones.is_empty(), "a model's skinned renderer retains its bone references")
			for bone: Dictionary in bones:
				check(model.objects.has(UnityAvatar._ref(bone)), "generated bone references resolve to source transforms")
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


## A disabled PhysBone, and a collider that is disabled or on an inactive GameObject, do not run when the avatar loads;
## a PhysBone on an inactive GameObject moves bones the menu shows with it.
func _components_off_when_the_avatar_loads_do_not_run() -> void:
	var sk := Skeleton3D.new()
	for name: String in ["Chest", "Left", "Right"]:
		sk.add_bone(name)
	sk.set_bone_parent(1, 0)
	sk.set_bone_parent(2, 0)
	var objs := {
		10: {"type": "Transform", "data": {"m_GameObject": {"fileID": "110"}, "m_Father": {"fileID": "0"}}},
		11: {"type": "Transform", "data": {"m_GameObject": {"fileID": "111"}, "m_Father": {"fileID": "10"}}},
		12: {"type": "Transform", "data": {"m_GameObject": {"fileID": "112"}, "m_Father": {"fileID": "10"}}},
		30: {"type": "Transform", "data": {"m_GameObject": {"fileID": "130"}, "m_Father": {"fileID": "10"}}},
		31: {"type": "Transform", "data": {"m_GameObject": {"fileID": "131"}, "m_Father": {"fileID": "10"}}},
		32: {"type": "Transform", "data": {"m_GameObject": {"fileID": "132"}, "m_Father": {"fileID": "31"}}},
		110: {"type": "GameObject", "data": {"m_Name": "Chest", "m_Component": [{"component": {"fileID": "10"}}]}},
		111: {"type": "GameObject", "data": {"m_Name": "Left", "m_Component": [{"component": {"fileID": "11"}}]}},
		112: {"type": "GameObject", "data": {"m_Name": "Right", "m_Component": [{"component": {"fileID": "12"}}]}},
		130: {"type": "GameObject", "data": {"m_Name": "Hidden Sphere", "m_IsActive": "0", "m_Component": [{"component": {"fileID": "30"}}]}},
		131: {"type": "GameObject", "data": {"m_Name": "Off Parent", "m_IsActive": "0", "m_Component": [{"component": {"fileID": "31"}}]}},
		132: {"type": "GameObject", "data": {"m_Name": "Disabled Physics", "m_Component": [{"component": {"fileID": "32"}}]}},
		40: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "130"}, "m_Enabled": "1", "rootTransform": {"fileID": "0"}, "shapeType": "0", "insideBounds": "1", "radius": "0.1", "height": "0", "position": {"x": "0", "y": "0", "z": "0"}}},
		41: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "110"}, "m_Enabled": "0", "rootTransform": {"fileID": "0"}, "shapeType": "0", "insideBounds": "0", "radius": "0.1", "height": "0", "position": {"x": "0", "y": "0", "z": "0"}}},
		42: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "110"}, "m_Enabled": "1", "rootTransform": {"fileID": "0"}, "shapeType": "0", "insideBounds": "0", "radius": "0.05", "height": "0", "position": {"x": "0", "y": "0", "z": "0"}}},
		20: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "111"}, "m_Enabled": "1", "pull": "0.2", "rootTransform": {"fileID": "11"}, "endpointPosition": {"x": "0", "y": "0.04", "z": "0"}, "colliders": [{"fileID": "40"}, {"fileID": "41"}, {"fileID": "42"}]}},
		21: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "112"}, "m_Enabled": "0", "pull": "0.2", "rootTransform": {"fileID": "12"}, "endpointPosition": {"x": "0", "y": "0.04", "z": "0"}}},
		22: {"type": "MonoBehaviour", "data": {"m_GameObject": {"fileID": "132"}, "m_Enabled": "1", "pull": "0.2", "rootTransform": {"fileID": "12"}, "endpointPosition": {"x": "0", "y": "0.04", "z": "0"}}},
	}
	var out: Dictionary = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {})
	var springs: Array = out.get("springs", [])
	var roots := springs.map(func(s: Dictionary) -> String: return sk.get_bone_name(s.joints[0].node))
	roots.sort()
	check(roots == ["Left", "Right"], "the disabled PhysBone stays out and the one under an inactive parent stays in: %s" % [roots])
	var left := springs.filter(func(s: Dictionary) -> bool: return sk.get_bone_name(s.joints[0].node) == "Left")
	if left.size() == 1:
		var listed: Array = out.colliderGroups[left[0].colliderGroups[0]].colliders
		check(listed.size() == 1 and is_equal_approx(out.colliders[listed[0]].shape.sphere.radius, 0.05), "it collides with the one collider that runs: %s" % [out.colliders])
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
	objs[20].data.limitType = "0"
	var free: Array = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).springs[0].joints
	check(not free[0].has("extras"), "a PhysBone without a limit carries none: %s" % [free])
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
	UnityAvatar._attach_armatures(objs, 10, "main", {"human": {"Chest": "Chest"}}, {})
	check(objs[20].data.m_Father.fileID == "11", "a linked prop follows its authored humanoid target")
	check(UnityAvatar._world_transform(objs, 22).is_equal_approx(before), "reparenting without alignment preserves the prop's world placement")
	var sk := Skeleton3D.new()
	sk.add_bone("Chest")
	var rests: Array[Transform3D] = [Transform3D(Basis(Vector3.UP, 0.1), Vector3.UP)]
	sk.set_bone_rest(0, rests[0])
	sk.set_meta("unity_bones", {111: 0})
	var tip := UnityAvatar._as_bone(objs, 22, sk, rests)
	check(tip == 3 and sk.get_bone_parent(1) == 0, "the linked hierarchy is attached under the humanoid bone")
	check(rests[tip].is_equal_approx(before), "bone rests preserve the linked prop placement")
	check(UnityAvatar._as_bone(objs, 22, sk, rests) == tip and sk.get_bone_count() == 4, "a source object is added once despite duplicate bone names")
	var springs: Array = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).springs
	check(springs.size() == 1 and springs[0].joints[0].node == 2, "the spring uses the inner object's identity, not the outer bone with the same name")
	check(springs[0].joints.size() == 3 and sk.get_bone_name(springs[0].joints[2].node) == "Tip End", "an unweighted source end node still supplies the spring's last segment")
	check(sk.get_bone_global_rest(springs[0].joints[2].node).is_equal_approx(UnityAvatar._world_transform(objs, 23)), "a later unweighted child inherits the prop scale exactly once")
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
	check((looks.get("decals", []) as Array).size() == 3, "one layer per slot up to the highest drawn")
	check(looks.get("materials", []) == [{"decals": [null, null, {"alpha": 0.25, "intensity": 1.0, "multiply": true}, null], "matcaps": [null, null, null, null], "emission": null}], "the look holds each slot's saved alpha and blend: %s" % [looks.get("materials")])
	var cell: Rect2i = materials.materials.skin.cell
	if (looks.get("decals", []) as Array).size() == 3:
		var layer := Image.new()
		check(layer.load_png_from_buffer(Marshalls.base64_to_raw(looks.decals[2])) == OK, "the layer is a PNG")
		var left := layer.get_pixel(cell.position.x + cell.size.x / 4, cell.position.y + cell.size.y / 2)
		var right := layer.get_pixel(cell.position.x + 3 * cell.size.x / 4, cell.position.y + cell.size.y / 2)
		check(left.a < 0.2 and right.a > 0.8 and is_equal_approx(right.r, 1.0) and right.g > 0.45 and right.g < 0.55, "the layer carries the decal colour under the mask's chosen channel: %s %s" % [left, right])
		check(layer.get_pixel(Materials.ATLAS - 1, Materials.ATLAS - 1).a == 0.0, "outside the material the layer is clear")
	var index := Image.new()
	check(index.load_png_from_buffer(Marshalls.base64_to_raw(looks.get("index", ""))) == OK, "the look index is a PNG")
	if not index.is_empty():
		check(index.get_pixelv(cell.get_center()).r8 == 1 and index.get_pixel(Materials.ATLAS - 1, Materials.ATLAS - 1).r8 == 0, "each texel names its material's look")
	expressions.data.clips[0].curves.clear()
	var unbound := UnityAvatar._bound(expressions, {"targets": [], "by_curve": {}}, [mesh], {}, objs, {"": 2}, sk, materials, {})
	check(unbound.targets.is_empty() and (unbound.get("looks", {}).get("decals", []) as Array).size() == 3, "a decal no clip animates is still drawn at its saved alpha")
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
	sk.free()


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
    - _Matcap2Enable: 1
    - _Matcap2UVMode: 3
    m_Colors:
    - _Matcap3Color: {r: 1, g: 1, b: 1, a: 1}
""")
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
	var assets := Assets.new(dir)
	var materials := Materials.new(assets)
	materials.use({"guid": "body"}, Color.WHITE)
	materials.use({"guid": "eye"}, Color.WHITE)
	materials.pack(["body", "eye"])
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
	check(entries.size() == 2, "both materials have a look")
	if entries.size() == 2:
		var gilt: Variant = entries[0].matcaps[2]
		check(entries[0].matcaps[1] == null, "a matcap mapped by a view the renderer does not draw is left out")
		check(gilt is Dictionary and gilt.texture == 0 and gilt.mode == "reflection" and gilt.intensity == 5.0 and gilt.replace == 0.771 and gilt.multiply == 0.737 and gilt.hue == {"shift": 0.0, "space": 0.0, "select": 1.0} and gilt.circle == null, "the matcap carries its texture, mapping and strengths: %s" % [gilt])
		var glows: Variant = entries[1].emission
		check(glows is Dictionary and is_equal_approx(glows.color[0], Color(0.5, 0, 0).srgb_to_linear().r) and glows.color[1] == 1.0 and glows.strength == 0.8 and glows.hue == 0.0 and glows.shiftsHue, "the emission carries its linear colour, strength and hue: %s" % [glows])
		check(entries[1].matcaps == [null, null, null, null], "a Toon Standard material draws no matcap Poiyomi left saved in it")
	check((looks.get("matcaps", []) as Array).size() == 1, "each matcap texture is carried once")
	var masks := Image.new()
	check(masks.load_png_from_buffer(Marshalls.base64_to_raw(looks.get("matcapMasks", ""))) == OK, "the matcap masks are a PNG")
	if not masks.is_empty():
		var cell: Rect2i = materials.materials.body.cell
		var left := masks.get_pixel(cell.position.x + cell.size.x / 4, cell.position.y + cell.size.y / 2)
		var right := masks.get_pixel(cell.position.x + 3 * cell.size.x / 4, cell.position.y + cell.size.y / 2)
		check(left.b < 0.2 and right.b > 0.8 and left.r == 1.0, "slot three's channel holds its mask's chosen channel: %s %s" % [left, right])
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
## weight or clip never moves another's.
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
	var merged := UnityAvatar._merge(prefabs, materials, objs, renderers, {}, {}, {}, sk, rests, 1.0, {})
	check(merged.meshes.size() == 1 and merged.meshes[0].weights == {"Shorts": 0.0, "Shorts (2)": 1.0}, "a name saved at two weights is two shapes, each at its renderer's weight: %s" % [merged.meshes.map(func(m: Dictionary) -> Dictionary: return m.weights)])
	check(merged.shapes == {3: {"Shorts": "Shorts"}, 6: {"Shorts": "Shorts (2)"}, 9: {"Shorts": "Shorts (2)"}}, "renderers weighed alike share their shape: %s" % [merged.shapes])
	var animated := {6: {"Shorts": [[0, [[0.0, 50.0]]]]}}
	var split := UnityAvatar._merge(prefabs, materials, objs, renderers, {}, animated, {}, sk, rests, 1.0, {})
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
