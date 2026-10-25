Plaster shader comparison

Run demo/plaster-detail.json with CAIRNFOLD_SCENE through scripts/bench.sh on
an unworn Quest 2. The scene deliberately disables the build budget and fixes
full detail to compare shader cost at the same density. These records exceed
the GPU budget even before the change; they are cost comparisons, not a
frame-budget pass. All runs use the benchmark's fixed seed and GPU level.

baseline and baseline-repeat use the original tiled plaster.
dual-hashed-weather blends two grain samples with hashed broad noise.
procedural replaces the grain with filtered mathematical noise.
texture-weather blends two grain samples and a third broad texture sample.
vertex-height moves terrain-relative wear height to vertices.

The selected texture-weather implementation is cheapest in five of six phases.
Its GPU medians (ms), versus the two baseline runs, are:
  close:           14.30 vs 13.72 / 14.16
  far:             20.81 vs 21.38 / 20.76
  walls aerial:    36.95 vs 35.45 / 34.99
  walls ground:    25.58 vs 25.07 / 25.18
  village aerial:  43.76 vs 40.56 / 40.24
  village ground:  18.38 vs 17.84 / 18.05
The measured total includes the entire rendered scene; these differences are
not isolated shader timings. Baseline drift ranges up to 0.62 ms. The larger
village difference remains a measured regression, not explained away by drift.

The dual-hashed-weather record uses the stock analyzer on the log prefix
through driver completion. A stale host wrapper delayed collection and allowed
shell rendering after the game exited; those post-completion samples are
excluded. The other records use normal collection.
