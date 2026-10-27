extends "res://../tests/support/suite.gd"

## Headless checks of reading Unity packages: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_unity_package.gd

const Yaml = preload("res://../scripts/unity/yaml.gd")
const XXHash = preload("res://../scripts/unity/xxhash.gd")
const Assets = preload("res://../scripts/unity/assets.gd")
const Prefabs = preload("res://../scripts/unity/prefabs.gd")
const Materials = preload("res://../scripts/unity/materials.gd")
const UnityAvatar = preload("res://../scripts/unity_avatar.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_xxhash_matches_the_reference()
	_yaml_reads_unity_objects()
	_nested_prefabs_flatten()
	_material_properties_read_either_layout()
	_outside_constraints_place()
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
