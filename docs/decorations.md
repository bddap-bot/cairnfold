# Decoration measurements

Every decoration style in `DecorationLayout.STYLES` but the two strings stands on every mount: a house's foundation,
the ground, a house's floor or a flat roof's deck; a string hangs on a span alone (docs/design.md, "Lights, strings
and smoke"). Placement stores the mount and places a present, whose lid carries a
picture built from the Style tool's own model; the Style wheel turns it into any other style.
Each decoration keeps its own command identity for save, co-op, delete and undo.
Foundation pieces follow the house frame. Planters use the existing flower meshes and colours.
Lanterns, torches and campfires feed the shared baked lamp volume, each in its own colour and brightness; no dynamic
lights are added. The Lantern, Lamp post and the strings are charged by the rule below and not yet measured.

## Quest 2 paired cost

A house's decorations are laid as one batch, and those on open ground as one batch per 16 m cell, each split by
lantern colour: one set of draws for the stones, flames, flowers and pictures of every piece in it. A piece a hand
carries or a delete sweep takes stands alone until it is let go.

`demo/decoration-costs.json` measures 24 copies of every style against a matching night baseline at the budget
fitting quality step: the first nine at a 30 m house's foot or on the ground beside it, the indoor furniture on that
house's floor seen from inside it, the outdoor furniture on a flat-roofed one's deck seen from above. Viewport GPU
medians exclude the first second of each eight-second phase; the difference divided by 24 is a piece's cost. Each
style is held to the dearer of two runs on one Quest 2.

The same scene was run twice on one Quest 2 with every piece its own node ("Before") and twice batched ("After"),
alternating. Batching took a present's 24 copies from 46 draws over the baseline to none, a string of lights' from 72
to 3, and every style's cost fell but a stool's, by 15.6 µs a piece on average (median 14.6) against a mean
difference of 8.5 µs between two runs of one style.

The least linear rule at or over every style's dearer batched run is 35.66 µs a piece and 2.55 µs a solid, a flame
or picture costing nothing the runs resolve. `Budget.decoration` charges it, rounded up to 35.7 and 2.6 µs, one rule
on every mount, with a planter's flowers charged as painted ones. The charge counts the style as laid at its tallest,
so steps are charged for 24 treads although measured with three. Before, the rule was 52.5 µs a piece, 2.8 µs a
solid and 11.2 µs a flame overlay with its halo, a present's picture counting as two.

| Style | Solids | Flowers | Before 1 µs | Before 2 µs | After 1 µs | After 2 µs | Charged µs | Charged before µs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Present | 5 | 0 | 38.6 | 29.6 | 17.8 | 17.1 | 48.7 | 88.9 |
| Planter | 2 | 5 | 19.1 | 30.7 | 20.7 | 13.5 | 50.1 | 67.3 |
| Bench | 9 | 0 | 42.8 | 30.8 | 24.0 | 19.7 | 59.1 | 77.7 |
| Rain barrel | 31 | 0 | 82.2 | 93.3 | 49.1 | 45.9 | 116.3 | 139.3 |
| Woodpile | 9 | 0 | 43.4 | 32.5 | 28.7 | 21.6 | 59.1 | 77.7 |
| Steps | 3 | 0 | 26.3 | 12.8 | 10.8 | 7.1 | 98.1 | 119.7 |
| Gatepost lantern | 7 | 0 | 46.7 | 28.9 | 23.1 | 15.2 | 53.9 | 83.3 |
| Standing torch | 2 | 0 | 34.0 | 22.0 | 17.4 | 19.8 | 40.9 | 69.3 |
| Campfire | 12 | 0 | 48.8 | 44.7 | 32.2 | 32.1 | 66.9 | 119.7 |
| Chair | 6 | 0 | 28.9 | 16.2 | 17.2 | 9.8 | 51.3 | 69.3 |
| Table | 5 | 0 | 26.9 | 48.3 | 32.4 | 14.8 | 48.7 | 66.5 |
| Settle | 4 | 0 | 9.1 | 25.1 | 16.0 | 0.8 | 46.1 | 63.7 |
| Bed | 5 | 0 | -6.2 | 4.0 | -38.6 | -34.6 | 48.7 | 66.5 |
| Shelf | 9 | 0 | 10.5 | 27.4 | 19.4 | -5.3 | 59.1 | 77.7 |
| Rug | 2 | 0 | 40.4 | 24.8 | 4.7 | 5.4 | 40.9 | 58.1 |
| Stool | 4 | 0 | 15.1 | 13.4 | 15.7 | 12.9 | 46.1 | 63.7 |
| Chest | 4 | 0 | 19.9 | 18.9 | 0.5 | -5.2 | 46.1 | 63.7 |
| Potted plant | 2 | 3 | 37.6 | 47.4 | 31.6 | 46.3 | 46.4 | 63.6 |
| Candle stand | 4 | 0 | 28.3 | 21.9 | 17.5 | 22.6 | 46.1 | 74.9 |
| Table and chairs | 15 | 0 | 76.0 | 73.8 | 67.7 | 73.9 | 74.7 | 94.5 |
| Garden bench | 4 | 0 | 45.5 | 53.7 | 23.2 | 34.0 | 46.1 | 63.7 |
| Trough planter | 2 | 5 | 58.9 | 64.0 | 34.6 | 36.4 | 50.1 | 67.3 |
| Parasol | 7 | 0 | 60.7 | 62.3 | 45.2 | 46.0 | 53.9 | 72.1 |
| String lights | 8 | 0 | 65.2 | 73.5 | 37.5 | 52.9 | 56.5 | 130.9 |

The sweep disables the construction limit; it measures cost, not whether those gardens hold refresh.

## Bounded density

`demo/decoration-density.json` holds the construction limit and tries 80 placements of each style: the first nine at
a small house's foot or on the ground, the furniture on an 8 by 6 m house's floor or flat roof. Each phase settles ten
seconds and measures ten. On a Quest 2, under the charges above, every phase held 72 Hz under the 11.11 ms GPU line
and the benchmark exited 0:

| Style | Pieces admitted | Budget fill | Runtime GPU ms | Late frames |
| --- | ---: | ---: | ---: | ---: |
| Present | 80 | 0.915 | 7.13 | 0 |
| Planter | 80 | 0.939 | 7.24 | 0 |
| Bench | 72 | 0.992 | 8.19 | 0 |
| Rain barrel | 36 | 0.978 | 8.89 | 2 |
| Woodpile | 72 | 0.992 | 8.16 | 1 |
| Steps | 43 | 0.984 | 6.73 | 0 |
| Gatepost lantern | 79 | 0.993 | 8.00 | 0 |
| Standing torch | 80 | 0.699 | 6.29 | 2 |
| Campfire | 69 | 0.986 | 8.25 | 1 |
| Chair | 58 | 0.991 | 8.86 | 1 |
| Table | 61 | 0.990 | 7.71 | 0 |
| Settle | 65 | 0.996 | 7.87 | 0 |
| Bed | 61 | 0.990 | 8.21 | 1 |
| Shelf | 51 | 1.000 | 7.77 | 1 |
| Rug | 73 | 0.994 | 9.22 | 0 |
| Stool | 65 | 0.996 | 8.36 | 1 |
| Chest | 65 | 0.996 | 7.79 | 0 |
| Potted plant | 65 | 1.000 | 8.21 | 1 |
| Candle stand | 65 | 0.996 | 9.20 | 0 |
| Table and chairs | 41 | 0.998 | 9.06 | 2 |
| Garden bench | 66 | 0.993 | 8.24 | 0 |
| Trough planter | 61 | 0.996 | 7.78 | 0 |
| Parasol | 57 | 1.000 | 8.51 | 0 |
| String lights | 54 | 0.995 | 9.22 | 0 |

Reproduce the visual review with `scripts/render.sh demo/decorations.json OUT`.
Run the device measurements with `CAIRNFOLD_SCENE=demo/decoration-costs.json scripts/bench.sh OUT --android APK`
(and `demo/decoration-density.json`) through the leased device wrapper.
