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
measurement. For the physical runs, close the Quest shell after game launch with
`adb shell am force-stop com.oculus.vrshell`, before the measured phases. Three
initial attempts caught the shell rendering beside the game, including repeated
hand-presence transitions; those runs failed the benchmark's contamination check
and are excluded. The check remains unchanged.
The same wheel fixtures are appended to `demo/stress.json`.

On the physical Quest 2 at 72 Hz, CPU/GPU levels 4/4, the open boulder wheel
measured 9.73 ms before and 9.76 ms after; the open house wheel measured 10.42 ms
before and 11.05 ms after. Both pass the then 12.5 ms GPU budget, and the 11.1 ms line (`Budget.line_ms()`) that replaced it. The benchmark exited
0 for both accepted runs, including its contamination and completion checks.
The boulder phase had zero late frames in each run; the house phase had two in
each. These are paired whole-scene measurements, not an isolated attribution of
the small differences to any one rendering change. Records are in
`perf/quest-2/style-models/`. These runs validate the two wheel fixtures, not the
entire stress tour.
