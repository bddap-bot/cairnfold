# Shadow rotation check

Run `scripts/shadows.gd` on the Frame through Godot 4.5.1 with the game's Mobile
renderer and an active OpenXR session. Hold the TV lease for the run. An unworn
headset must render rather than pause in standby; restore its runtime setting
when finished. The normal game installation need not be replaced.

From a source checkout on the headset:

```sh
NESTCOMBE_SHADOW_OUT="$PWD/out/shadows" godot --path game --script "$PWD/scripts/shadows.gd"
```

Copy the output directory back, then run:

```sh
nix-shell --run 'python3 scripts/shadows.py out/shadows'
```

The script builds a wall, house and tree in winter, holds the head position and
quality level fixed, and turns through nine yaw angles. A diagnostic compositor
reads both complete eye buffers before tonemapping, using the same linear-to-sRGB
conversion for every capture. It records the actual per-eye projection matrices.
The checker reprojects fixed world-space tree and roof regions into those images,
writes head-on comparison crops, and fails if their mean brightness changes by
more than 2.5/255. A brightness ceiling also rejects a sweep with the shadows
removed. Both eyes must pass; missing captures and insufficient visible coverage
are errors.

Set `NESTCOMBE_SHADOW_BASELINE=1` to restore the previous two splits, 45 m reach,
6 m near split and 0.8 fade start in the diagnostic only. This is the negative
control: the same rendered check must fail. `NESTCOMBE_SHADOW_SCENE=hill` captures
the snowy hillside; `NESTCOMBE_SHADOW_SCENE=tree` captures a close canopy at the
coarsest quality step. Those alternate views are for visual comparison, not the
fixed-region checker.

The readback deliberately stalls to collect pixels. These runs do **not** measure
the frame budget. Use `scripts/bench.sh` without the diagnostic for performance.
The game never loads this capture code during ordinary play.

The root is view-depth selection in the engine's
[Mobile shadow shader](https://github.com/godotengine/godot/blob/4.5.1-stable/servers/rendering/renderer_rd/shaders/forward_mobile/scene_forward_mobile.glsl).
Map stabilization already exists in
[the directional shadow fitting code](https://github.com/godotengine/godot/blob/4.5.1-stable/servers/rendering/renderer_scene_cull.cpp).
The fix removes the fade and split transitions from the garden rather than
changing quality with the head's direction.
