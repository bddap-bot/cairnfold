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

## Flicker in a headset

Each second of a session log carries `eye_fov_spread_deg`: the widest change of any
edge of either eye's frustum within that second. The engine fits the sun's
stabilized shadow map to the eyes' combined frustum every frame, so the map holds
still only while the frusta do; a nonzero spread in the seconds around a flicker
names the runtime's projection as its input. A desktop camera holding the same
place, time of day and quality step, turned in 0.15° and 0.5° steps or moved in
3 mm to 2 cm steps, keeps every static shadow unchanged frame to frame. So do a
camera preview re-rendering the shadow every third frame and the governor's step
logged per second (its highest), which stays on a shadowed step through such a
report.

## Held objects

One map over the whole garden has texels about 0.2 m across: the map is fitted
to a sphere round the eyes' combined frustum out to `Look.SHADOW_REACH`, about
450 m in radius for a Quest's field of view. A held book is 0.15 m, so it
covered a texel's centre in some frames and none in others, and its shadow
blinked on and off as the hand trembled. A session log through the report held
one quality step and zero `eye_fov_spread_deg`, so the map stood still and only
the book moved across it. Each eye reads the same map, so both eyes saw the
same blink.

A near split 8 m deep drew the book whole and steady, but on the Quest 2 stress
scene it cost a median 1.3 ms of GPU time a phase (1.6 ms with a 4096 atlas,
so the cost came from the split, not the atlas): every garden caster near the eye is
drawn twice. A decal laid along the light cost 3.5 ms whenever it showed, at
any length. So the book casts nothing into the map, and the ground's
shader darkens what lies behind it itself (`held_shadow.gdshaderinc`):
`HeldShadow` sets one matrix taking a world point into the box behind the
book along the light, each vertex carries its point there, and each fragment
tests that box. Taking albedo cannot only take the sun away, so it cannot
match a real shadow on every surface. Its strength is fitted on the meadow's
ground against the book's real shadow from that split, at 11°, 34° and 50°
up, to within 0.03 of the shaded share of luminance. It costs the Quest 2
about 0.15 ms while the book is out. Reading it in the grass too cost twice
that, so grass blades stand lit over it; walls and stones do not read it, and
on ground already in a building's shade it still darkens.
`tests/gpu_held_shadow.gd` moves a book-sized board over ground reading the
box and fails if its shadow is missing from any frame.

## A photo's sun

A photo is lit by its own sun (`Look.photo_sun`, four blended splits), which no
other view sees. The first frame drawn with it asks for seven new pipeline
specializations, and Godot draws that frame while they compile, without that
sun's shadows. That first photo of a session lost every shadow, while every later
photo, after a three-second gap or a new time of day, cast them with no further
compiles. Neither the shadow atlas resize nor the foliage detail swap in
`PhotoTool.draw_finest` changes this. `PhotoTool._ready` draws one small photo
view as the game loads, so the pipelines are built before the first shot.
