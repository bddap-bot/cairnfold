# Decoration measurements

Every decoration style in `DecorationLayout.STYLES` stands on every mount: a house's foundation, the ground,
a house's floor or a flat roof's deck. Placement stores the mount and places a present, whose lid carries a
picture built from the Style tool's own model; the Style wheel turns it into any other style.
Each decoration keeps its own command identity for save, co-op, delete and undo.
Foundation pieces follow the house frame. Planters use the existing flower meshes and colours.
Lanterns, torches and campfires feed the shared baked lamp volume; no dynamic lights are added.

## Quest 2 paired cost

`demo/decoration-costs.json` measures 24 copies of every style against a matching night baseline at the budget
fitting quality step: the first nine at a 30 m house's foot or on the ground beside it, the indoor furniture on that
house's floor seen from inside it, the outdoor furniture on a flat-roofed one's deck seen from above. Viewport GPU
medians exclude the first second of each eight-second phase; the difference divided by 24 is a piece's cost. Two runs
on one Quest 2 differ by up to 30 µs a piece, so each style is held to the dearer of the two.

A piece costs mostly for being a piece, its own draws, and little for its size: the least linear rule at or over every
style's dearer run is 52.42 µs a piece, 2.80 µs a solid and 11.14 µs a flame overlay with its halo (a present's
picture counts as two). `Budget.decoration` charges it, rounded up to 52.5, 2.8 and 11.2 µs, one rule on every mount,
with a planter's flowers charged as painted ones. The charge counts the style as laid at its tallest, so steps are
charged for 24 treads although measured with three. Before, every solid was a whole fitting (15.187 µs) and every
flame two.

| Style | Solids | Flames | Flowers | Run 1 µs | Run 2 µs | Charged µs | Charged before µs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Present | 5 | 2 | 0 | 21.4 | 35.8 | 88.9 | 136.7 |
| Planter | 2 | 0 | 5 | 28.5 | 22.2 | 67.3 | 39.5 |
| Bench | 9 | 0 | 0 | 34.5 | 38.2 | 77.7 | 136.7 |
| Rain barrel | 31 | 0 | 0 | 98.5 | 108.8 | 139.3 | 470.8 |
| Woodpile | 9 | 0 | 0 | 61.1 | 77.6 | 77.7 | 136.7 |
| Steps | 3 | 0 | 0 | 25.1 | 15.4 | 119.7 | 364.5 |
| Gatepost lantern | 7 | 1 | 0 | 69.9 | 83.1 | 83.3 | 136.7 |
| Standing torch | 2 | 1 | 0 | 26.5 | 36.1 | 69.3 | 60.7 |
| Campfire | 12 | 3 | 0 | 92.1 | 99.5 | 119.7 | 273.4 |
| Chair | 6 | 0 | 0 | 37.2 | 33.8 | 69.3 | 91.1 |
| Table | 5 | 0 | 0 | 29.2 | 47.4 | 66.5 | 75.9 |
| Settle | 4 | 0 | 0 | 15.8 | 44.8 | 63.7 | 60.7 |
| Bed | 5 | 0 | 0 | 7.9 | 14.7 | 66.5 | 75.9 |
| Shelf | 9 | 0 | 0 | -0.5 | 42.5 | 77.7 | 136.7 |
| Rug | 2 | 0 | 0 | 24.0 | 53.4 | 58.1 | 30.4 |
| Stool | 4 | 0 | 0 | 22.1 | 49.5 | 63.7 | 60.7 |
| Chest | 4 | 0 | 0 | 8.7 | 37.9 | 63.7 | 60.7 |
| Potted plant | 2 | 0 | 3 | 36.7 | 63.5 | 63.6 | 35.9 |
| Candle stand | 4 | 1 | 0 | 49.7 | 57.8 | 74.9 | 91.1 |
| Table and chairs | 15 | 0 | 0 | 60.0 | 53.9 | 94.5 | 227.8 |
| Garden bench | 4 | 0 | 0 | 27.6 | 30.1 | 63.7 | 60.7 |
| Trough planter | 2 | 0 | 5 | 37.1 | 34.3 | 67.3 | 39.5 |
| Parasol | 7 | 0 | 0 | 38.0 | 31.8 | 72.1 | 106.3 |
| String lights | 8 | 5 | 0 | 50.3 | 50.8 | 130.9 | 273.4 |

The first nine styles were first measured on an earlier build, its bare scene 3 to 4 ms dearer on the GPU; those
figures (woodpile 105.5 µs, steps 55.9 µs, rain barrel 121.8 µs) are not this build's and are left out of the fit. Fit
with them too, the rule would charge nothing for a flame and 6.8 µs a solid, and a table and chairs 146 µs for 60
measured.

The sweep disables the construction limit; it measures cost, not whether those gardens hold refresh.

## Bounded density

`demo/decoration-density.json` holds the construction limit and tries 80 placements of each style: the first nine at
a small house's foot or on the ground, the furniture on an 8 by 6 m house's floor or flat roof. Each phase settles ten
seconds and measures ten. On the Quest 2 every phase held 72 Hz under the 11.11 ms GPU line and the benchmark exited 0.
Furniture phases, under the charges above:

| Style | Pieces admitted | Budget fill | Runtime GPU ms | Late frames |
| --- | ---: | ---: | ---: | ---: |
| Chair | 43 | 0.992 | 8.21 | 2 |
| Table | 45 | 0.995 | 7.92 | 2 |
| Settle | 47 | 0.995 | 8.30 | 0 |
| Bed | 45 | 0.995 | 8.51 | 1 |
| Shelf | 38 | 0.986 | 7.53 | 1 |
| Rug | 51 | 0.989 | 9.27 | 0 |
| Stool | 47 | 0.995 | 8.68 | 2 |
| Chest | 47 | 0.995 | 8.26 | 1 |
| Potted plant | 47 | 0.994 | 9.04 | 1 |
| Candle stand | 40 | 0.996 | 9.32 | 1 |
| Table and chairs | 32 | 0.989 | 8.83 | 2 |
| Garden bench | 48 | 0.997 | 8.40 | 1 |
| Trough planter | 45 | 0.990 | 8.54 | 1 |
| Parasol | 42 | 0.990 | 8.57 | 1 |
| String lights | 23 | 0.987 | 8.69 | 2 |

The first nine styles' phases held as well, at 6.83 to 8.49 ms runtime GPU.

Reproduce the visual review with `scripts/render.sh demo/decorations.json OUT`.
Run the device measurements with `NESTCOMBE_SCENE=demo/decoration-costs.json scripts/bench.sh OUT --android APK`
(and `demo/decoration-density.json`) through the leased device wrapper.
