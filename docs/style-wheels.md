# Boulder and house style previews

A boulder target gets one miniature boulder for each stone style. Painted stone
keeps its ground swatches. The miniature calls `Boulders._instance` with
`BoulderLayout` geometry and uses `Stones.shared_material`, as placed boulders do.
Both choices and both hands share its MultiMesh. The material's miniature flag
samples surface noise in model space so shrinking the model preserves detail;
lighting still samples the garden at the model's actual position.

A rectangular house face gets stone, plaster and timber houses. They use the
existing `ToolModels._house` path through `WallLayout` and `RoofLayout`, with
openings omitted and the selected face style. House roof and gable previews also
omit openings. The held house tool and other style wheels keep their existing
models. Miniature masonry uses the existing shared baked geometry and materials.

`demo/style-models.json` measures each wheel open for 25 seconds on the same
scene and view, with the normal quality governor. It waits two minutes before
measurement because the physical Quest shell continued rendering for 44–68
seconds after scene startup in the first two attempts. Those attempts failed the
benchmark's contamination check and are excluded. The check remains unchanged.
The same wheel fixtures are appended to `demo/stress.json`.
