#!/usr/bin/env python3
"""A scene that prices one diagnostic layer in each phase that may pass the build budget: pair_layer.py SCENE.json LAYER

Prints SCENE with each phase scripts/past_budget.py may let past the budget, whatever its garden's fill, followed,
from that phase's own view, by the layer shown and hidden in turn, labelled as scripts/paired.py reads them:
pair/PHASE/1LAYER/K and pair/PHASE/none/K, ordered with, without, without, with, so a drift through the run cancels.
The garden every later phase builds on is left as the scene builds it. `CAIRNFOLD_SCENE=OUT/stress-masonry.json
scripts/bench.sh ...` on its output, then `scripts/paired.py RECORD`, gives each such phase the share of its GPU time
the layer (driver.gd's LAYERS) draws."""
import json
import math
import sys

from past_budget import past_budget

SETTLE_S = 1
MEASURE_S = 5


def pairs(phase: dict, layer: str) -> list[dict]:
    out = []
    for k, side in ((1, "with"), (1, "without"), (2, "without"), (2, "with")):
        out += [{"op": "label", "name": "-"},
                {"op": "layer", "name": layer, "mode": "on" if side == "with" else "off"},
                {"op": "wait", "seconds": SETTLE_S},
                {**phase, "name": f"pair/{phase['name']}/{'1' + layer if side == 'with' else 'none'}/{k}"},
                {"op": "wait", "seconds": MEASURE_S}]
    return out + [{"op": "label", "name": "-"}, {"op": "layer", "name": layer, "mode": "on"}]


scene, layer = sys.argv[1:]
out: list[dict] = []
open_phase = None
for step in json.load(open(scene)):
    if open_phase and step["op"] not in ("view", "wait"):
        out += pairs(open_phase, layer)
        open_phase = None
    out.append(step)
    if step["op"] == "label" and past_budget(step, math.inf):
        open_phase = step
if open_phase:
    out += pairs(open_phase, layer)
print("[\n" + ",\n".join("  " + json.dumps(s) for s in out) + "\n]")
