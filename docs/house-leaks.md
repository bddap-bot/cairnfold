# House shell probes

`tests/test_house_leaks.gd` runs through the normal `scripts/test.sh` glob. It
builds fixed-seed houses through `World._order`, waits for their layouts, then
casts fixed Fibonacci spheres from interior points on each floor. The corpus
includes stone, plaster and timber; stone and plaster foundations; gable and
round roofs; tiles, thatch and curved flat decks; all gable styles; windows,
doors and arches; raised and tall houses; overlapping buildings; and
wall strokes produced by `WallPlan`.

The probe reads full-detail rendered instance buffers and their source meshes,
including floor flags/planks, mortar beds, gables, thatch and roof lining. It
applies the plaster panel vertex mitres used by the shader. Shadow proxies and
collision slabs cannot seal a visible hole. Triangle intersections are
geometric and double-sided; this does not test material transparency, face
culling or distance-dependent LOD appearance.

The first hit must belong to the room shell. Terrain and unrelated geometry
are foreign surfaces, not successful containment. Escaping rays are exempt
only if they cross an actual layout window, door or arch before their first
hit. A hit on the shell is contained regardless of whether the ray passed
through another room opening on its way there.

The default corpus is an **inventory**, not a claim that all generated houses
are sealed. The probe's positive/negative controls and thirteen currently sealed seeds are gates. Discovered cases
are repaired separately, then added to the sealed-case gates with their fix.
No known failing case is skipped. The known cap-band case also has fixed
near-wall rays at several heights and slopes: a sphere from the middle of a
room can miss a narrow seam.

Run a larger fixed sweep or fail on every escape:

```sh
nix-shell --run 'godot4 --headless --fixed-fps 60 --path game --script ../tests/test_house_leaks.gd -- --leak-sweep'
nix-shell --run 'godot4 --headless --fixed-fps 60 --path game --script ../tests/test_house_leaks.gd -- --leak-strict'
```

`HOUSE_LEAK_SEED=8756` selects one reproducible case. Set `HOUSE_LEAK_REPORT` to
an absolute JSON path to retain all escaping rays, their origins/directions,
world positions, first-hit parts, collision results and the build commands.
The command list uses Godot's `var_to_str` notation and can be read with
`str_to_var`; strict failures also print it. Elapsed time is reported separately
and never participates in generation, ray selection or pass/fail decisions.

Positions use the collision query when it reports a surface missing from the
rendered shell; otherwise they are estimated exits from the room volume,
including sky misses. The JSON records which method located each point.
The two nearest mesh parts are diagnostic candidates, measured from their
vertices; they are not a proven root cause. Counts are escaping rays, not
unique physical gaps. Collision hits on render escapes are reported separately
using the game's building and floor queries. Sampling is finite: passing these rays does not
prove mathematical watertightness or coverage of every possible generated
room. Use the larger sweep and preserve a directed repro whenever a new gap
is found.

The normal corpus records one cap-band escape in seed `8756`, a report case
pending its geometry fix; the other thirteen seeds, `31` among them since its
floor joins were sealed, are in `SEALED_SEEDS`. A repaired case
belongs in that list, keeping the same generator and rays. An escape only the larger sweep finds is
kept as a fixed origin and direction in `SEALED_RAYS`, checked on every run, since the normal sphere
would not meet it again. `--leak-strict`
turns the report case into a failure without changing what is measured.
