# Sample avatars

Public VRM files the avatar tests and `scripts/coop.sh` read. None ships with the game.

- `crimsom-0.x.vrm`: "Crimsom", avatar 001 of 100Avatars by Polygonal Mind, CC0
  (https://github.com/kourtincat/100Avatars, `100Avatars_001/100Avatars_001_Crimsom.vrm`).
- `crimsom-1.0.vrm`: the same model converted to VRM 1.0 with the VRM Add-on for Blender
  4.10.2 in Blender 5.0.1, CC0.
- `godette-0.x.vrm`: "Low-Poly Godette", original model by SirRichard94
  (https://github.com/SirRichard94/low-poly-godette), VRM adaptation by Lyuma, licensed
  under Creative Commons Attribution 3.0 Unported (CC BY 3.0,
  https://creativecommons.org/licenses/by/3.0/). Taken unchanged from
  https://github.com/V-Sekai/godot-vrm, `vrm_samples/Godette_vrm_v4.vrm`.

Unity source packages, which `tests/test_avatar.gd` converts with `scripts/unity_avatar.gd`:

- `seed-san/`: "Seed-san" by VirtualCast, Inc., licensed under the VRM Public License 1.0
  (https://vrm.dev/licenses/1.0/; its VRM metadata grants use by everyone, redistribution and
  modified redistribution, with credit required). Taken unchanged from the Unity sample project
  in https://github.com/vrm-c/UniVRM at commit `efd20f62f1bf0ac3fcc34de1e497324c5197d146`,
  `Assets/VRM10_Samples/ModelSetup_SeedSan/Models/`: the FBX model (five SkinnedMeshRenderer
  meshes, 43 blend shapes) and its `.meta`, whose humanDescription is the Unity humanoid
  Avatar definition. The sample's textures, materials and prefab are not included.
