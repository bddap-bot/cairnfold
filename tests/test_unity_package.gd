extends "res://../tests/support/suite.gd"

## Headless checks of reading Unity packages: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_unity_package.gd

const Yaml = preload("res://../scripts/unity/yaml.gd")
const XXHash = preload("res://../scripts/unity/xxhash.gd")
const Assets = preload("res://../scripts/unity/assets.gd")
const Prefabs = preload("res://../scripts/unity/prefabs.gd")
const Materials = preload("res://../scripts/unity/materials.gd")
const UnityAvatar = preload("res://../scripts/unity_avatar.gd")
const Expressions = preload("res://../scripts/unity/expressions.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_xxhash_matches_the_reference()
	_yaml_reads_unity_objects()
	_nested_prefabs_flatten()
	_material_properties_read_either_layout()
	_outside_constraints_place()
	_a_branching_physbone_root_stays_still()
	_a_physbone_ends_at_its_endpoint()
	_a_transform_the_skeleton_lacks_becomes_a_bone()
	_a_menu_toggle_switches_a_hidden_renderer()
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


## A constraint with a weighted source outside the avatar places its GameObject; one sourced by the avatar's own
## transforms, or weighted nothing outside, does not.
func _outside_constraints_place() -> void:
	var objs := {
		1: {"type": "GameObject", "data": {"m_Component": [{"component": {"fileID": "2"}}]}},
		2: {"type": "ParentConstraint", "data": {"m_Sources": [{"sourceTransform": {"fileID": "7", "guid": "elsewhere"}, "weight": "1"}]}},
		3: {"type": "GameObject", "data": {"m_Component": [{"component": {"fileID": "4"}}]}},
		4: {"type": "MonoBehaviour", "data": {"PositionAtRest": {}, "Sources": {"source0": {"SourceTransform": {"fileID": "9"}, "Weight": "1"}, "source1": {"SourceTransform": {"fileID": "8"}, "Weight": "0"}}}},
	}
	var inside := {9: true}
	check(UnityAvatar._constrained(objs, 1, inside), "a source in another prefab places its GameObject")
	check(not UnityAvatar._constrained(objs, 3, inside), "the avatar's own source, and an unweighted outside one, do not")


## A PhysBone whose root has two children: under the default multiChildType the root stays still and each branch is its
## own chain; under First the first branch's chain turns the root.
func _a_branching_physbone_root_stays_still() -> void:
	var sk := Skeleton3D.new()
	var objs := {}
	for bone: Array in [[10, "Root", 0], [11, "A", 10], [12, "B", 10], [13, "A2", 11], [14, "B2", 12]]:
		sk.add_bone(bone[1])
		objs[bone[0] + 100] = {"type": "GameObject", "data": {"m_Name": bone[1]}}
		objs[bone[0]] = {"type": "Transform", "data": {"m_GameObject": {"fileID": str(bone[0] + 100)}, "m_Father": {"fileID": str(bone[2])}}}
	var chains := func(multi_child: String) -> Array:
		objs[20] = {"type": "MonoBehaviour", "data": {"pull": "0.2", "rootTransform": {"fileID": "10"}, "multiChildType": multi_child}}
		var out := []
		for spring: Dictionary in UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).springs:
			out.append(spring.joints.map(func(j: Dictionary) -> String: return sk.get_bone_name(j.node)))
		out.sort()
		return out
	check(chains.call("0") == [["A", "A2"], ["B", "B2"]], "under Ignore the root is in no chain: %s" % [chains.call("0")])
	check(chains.call("1") == [["B", "B2"], ["Root", "A", "A2"]], "under First the first branch turns the root: %s" % [chains.call("1")])
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
	var springs: Array = UnityAvatar._springs(objs, 10, sk, {}, 1.0, {}).get("springs", [])
	var joints: Array = springs[0].joints if springs.size() == 1 else []
	check(joints.size() == 2 and joints[0].node == 0, "the bone's chain runs to its endpoint: %s" % [springs])
	if joints.size() == 2:
		check(sk.get_bone_parent(joints[1].node) == 0 and sk.get_bone_rest(joints[1].node).origin.is_equal_approx(Vector3(-0.02, 0.1, 0)), "the endpoint is a bone under it at its offset: %s" % sk.get_bone_rest(joints[1].node).origin)
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
  m_Motion: {fileID: 5}
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
""")
	var descriptor := {"customExpressions": "1", "expressionsMenu": {"guid": "m1"}, "expressionParameters": {"guid": "p1"}, "baseAnimationLayers": [{"type": "5", "isDefault": "0", "animatorController": {"guid": "c1"}}]}
	var expressions := Expressions.new(Assets.new(dir), descriptor)
	check(expressions.data.menu.size() == 2 and expressions.data.menu[0].type == "toggle" and expressions.data.menu[0].parameter == "Hat", "the menu's toggles read: %s" % [expressions.data.get("menu")])
	check(expressions.data.parameters.any(func(p: Dictionary) -> bool: return p.name == "Hat" and p.type == "bool" and p.saved), "its parameter reads as a saved bool")
	var layer: Dictionary = expressions.data.layers[0]
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
	var data := UnityAvatar._bound(expressions, switches, [{"node": "Body 1", "when": [[0, 1]], "renderers": [5], "weights": {}, "mesh": ArrayMesh.new()}], objs, paths, sk, Materials.new(Assets.new(dir)), {})
	check(data.menu.size() == 1 and data.menu[0].name == "Hat", "the toggle that moves nothing is cut: %s" % [data.menu])
	check(data.shown == [{"node": "Body 1", "when": [[0, 1]]}] and data.clips[0].curves[0] == {"target": 0, "step": true, "keys": [[0.0, 1.0]]}, "the hat's mesh shows under its switch, which the clip sets: %s %s" % [data.shown, data.clips])
	sk.free()
