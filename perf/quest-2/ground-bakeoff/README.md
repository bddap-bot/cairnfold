# Ground shader bake-off, judged on one Quest 2

Three entrants optimized the ground's shader independently. Each branch's change was rebuilt on one main
(8e06f6ee) and played on one Quest 2 in one session, main between every candidate:
A, Opus, A, Fable, A, Astra, A, combined, A. The scene is `demo/ground-bakeoff.json`: the meadow-layers protocol
cut to the terrain layer, shown and hidden four times each from the air and standing. Ground is the median shown
less the median hidden viewport GPU time; whole frame is the median shown. "Before" is the mean of the two main runs
bracketing the candidate. The five main runs agree to 0.05 ms on the ground from the air and 0.04 ms on the whole
frame.

| entrant | model | ground air ms | ground standing ms | whole frame air / standing ms | image kept | notable technique |
|---|---|---|---|---|---|---|
| Opus | Opus 5.5 | 3.03 → 2.89 | 2.01 → 2.02 | 6.81 → 6.66 / 6.37 → 6.30 | y | each vertex reads its stored normal from the height texel it already reads, 1 tap where 5 were |
| Fable | Fable 5.1 | 3.04 → 2.98 | 2.02 → 2.04 | 6.82 → 6.75 / 6.37 → 6.31 | y | per-vertex pond gate skips the water-depth read and bank maths away from ponds; ground drawn after what stands on it; half-precision colour maths |
| Astra | Astra | 3.06 → 3.10 | 2.01 → 2.14 | 6.82 → 6.87 / 6.37 → 6.41 | y | half precision on twelve colour locals; no saving |
| Opus + Fable (landed) | both | 3.04 → 2.86 | 2.02 → 1.96 | 6.80 → 6.62 / 6.37 → 6.24 | y | the two above together |

Standing, the hidden-terrain time ran 4.27–4.28 ms on every candidate and 4.34–4.38 on every main run, so the
standing ground column carries that offset; the whole frame is the standing figure to read.

Image: every candidate's captures against the main run before it (main | candidate | 8× difference) show the
ground black in the difference, which falls on swaying grass, flowers and tree silhouettes as it does between two
main runs (mean |difference| on 0–255, aerial / standing: main against main 0.72 / 2.09 and 0.48 / 1.17;
Opus 0.45 / 2.04, Fable 0.59 / 1.98, Astra 0.86 / 1.75, combined 0.46 / 1.77).

Records, in run order: 20261022T095227Z (A), 095514Z (Opus), 095845Z (A), 100133Z (Fable), 100507Z (A),
100756Z (Astra), 101129Z (A), 101413Z (combined), 101739Z (A).
