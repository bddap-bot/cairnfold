# What the fixed-foveation map costs the Quest 2

One Quest 2, `CAIRNFOLD_SCENE=demo/foveation-X.json scripts/bench.sh OUT --android APK`, each record the bench's phase table
(`gpu_ms` is the runtime's App= time a frame). Builds: edec2ce5 (main) for all but `governed-guard.json`, which is
520a82f9 (`Quality.Map`).

| Record | Scene | What it varies |
| --- | --- | --- |
| `layers.json` | `demo/foveation-layers.json` | the timber village from the air at step 16: each layer hidden in turn, foveation 0 to 3 |
| `trees.json` | `demo/foveation-trees.json` | 64 tall trees added in view, hidden, shadows off, masonry hidden |
| `trees-out-of-view.json` | `demo/foveation-trees-out-of-view.json` | the same trees 160 m behind the eye |
| `small-trees.json` | `demo/foveation-small-trees.json` | 64 trees at a third the size, in view |
| `swapchain.json` | `demo/foveation-swapchain.json` | steps 6, 5, 4, 3, 2: the swapchain at 0.7, 0.85 and 1.0 with the map |
| `governed-guard.json` | `demo/foveation-governed.json` | governed, with `Quality.Map` |

`trace-map-off.txt` and `trace-map-on.txt` are `ovrgpuprofiler -t 0.2 -v -s 1,21,28,39,40` render-stage traces of the
timber village from the air at step 6, with the map off and on. `trace-map-on-trees.txt` is the stress scene's
village/aerial, where the flora pools' trees stand in view and the map is on.
