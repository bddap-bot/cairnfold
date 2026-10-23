# Fixed foveation's cost over walls from the air, Quest 2

Stress-scene excerpts, `scripts/bench.sh OUT --android APK` with `NESTCOMBE_SCENE` set to the scene named below.
docs/design.md reads them in "Anti-aliasing on the Quest 2".

- `*-<rev>.json` with no suffix, the bisect: the stress scene's meadow, flora, r10 to r25, r15-tall and village
  phases at step 0, on the commit named. fe69646, e8ef998, 6141beb and 36f3888 draw village/aerial in 22 to 29 ms;
  9ad5a2b, the first commit that sets the view's VRS mode to XR, and a4d3a15 take 277 to 291.
- `-step5`: the same phases at step 5 on b6635a0. `-vrs-never-set-step5`: that build without the VRS mode set, so
  the runtime's foveation level is asked for but no map is applied.
- `-vrs-follows-level-step5-levels`: the village from the air at step 5, the driver's `antialias` foveation
  3, 1, 2, 0 twice, in a build whose VRS mode is XR only at a level over 0.
- `-step6`: the same phases at step 6, the stress scene's own step, on b6635a0. `-6afab3d-primed-step6` and
  `-6afab3d-primed-step5`: the change these records came with, whose mode follows the rung and whose priming first
  draws the map at rung 2. `-vrs-follows-level-step6`: the mode following the rung without that priming.
- `-shadows`: the village from the air at steps 14 and 15 (the sun's shadows on, then off), twice.
- `-msaa-unshaded`: the village from the air at step 5, the driver's `antialias` 2x, none, 2x unshaded, 2x, 4x.
