# Decoration measurements

Every decoration style in `DecorationLayout.STYLES` stands on every mount: a house's foundation, the ground,
a house's floor or a flat roof's deck. Placement stores the mount and places a present, whose lid carries a
picture built from the Style tool's own model; the Style wheel turns it into any other style.
Each decoration keeps its own command identity for save, co-op, delete and undo.
Foundation pieces follow the house frame. Planters use the existing flower meshes and colours.
Lanterns, torches and campfires feed the shared baked lamp volume; no dynamic lights are added.

## Quest 2 paired cost

`demo/decoration-costs.json` measures 24 copies of each of its first nine styles against a matching
night baseline at the budget fitting quality step. Viewport GPU medians exclude
the first second of each eight-second phase. The difference divided by 24 is
the per-piece estimate below. Runtime GPU is the independent VrApi App signal.
The budget uses viewport GPU; its existing conservative solid/flower reservations
cover every measured increment. These are one-run estimates, not isolated mesh
costs: scene rebuilding and normal frame variation remain in the differences.

The present replaced the bracket lantern in the sweep and is not yet measured.

| Style | Triangles | Viewport GPU µs/piece | Runtime GPU µs/piece | Reserved µs/piece |
| --- | ---: | ---: | ---: | ---: |
| Planter | 286 | 31.26 | 51.25 | 46.08 |
| Bench | 972 | 54.86 | 55.00 | 192.11 |
| Rain barrel | 3348 | 121.84 | 132.08 | 661.73 |
| Woodpile | 972 | 105.51 | 124.58 | 192.11 |
| Steps | 324 | 55.90 | 55.42 | 512.30 |
| Gatepost lantern | 770 | 68.13 | 96.25 | 192.11 |
| Standing torch | 230 | 47.47 | 51.25 | 85.38 |
| Campfire | 1338 | 95.18 | 118.33 | 384.23 |

Steps are measured at a 0.6 m rise (three treads); their reservation covers
all 24 treads, or 2,592 triangles. Solids use one draw, planters two, and lit
decorations three. The geometry counts include flower, flame and halo triangles.

The sweep deliberately disables the construction limit. Several 24-copy scenes
exceed the then 12.5 ms runtime GPU line; the sweep is a cost measurement, not a
claim that those unbounded gardens hold refresh.

Reproduce the visual review with `scripts/render.sh demo/decorations.json OUT`.
Run the device measurement with `NESTCOMBE_SCENE=demo/decoration-costs.json
scripts/bench.sh OUT --android APK` through the leased device wrapper.
