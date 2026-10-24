#!/usr/bin/env python3
"""Fits the frame budget's unit costs from a run of demo/costs.json and prints a candidate for review:
costs.py OUT_DIR

OUT_DIR is what `NESTCOMBE_SCENE=demo/costs.json scripts/bench.sh OUT_DIR ...` left on that headset. Each phase is the
bare meadow plus one kind of build, at the fixed calibration step (Budget.fit_step), from the air and standing; its cost is its
median viewport GPU time (the governor's signal) over the bare meadow's from the same view, or over the phase it is built on
(ON) for one that adds to another's builds. Masonry is fitted twice: its far rate on all its area from the air, where every
chunk draws far meshes, and its near excess on the area near one eye (`<unit>_near`, Budget.near) standing among it. A view whose frames fell
below the refresh rate is left out: GPU time read there is not the scene's. A unit's cost is the most any view of any phase
holding it as the one unknown gives, so the bound holds from every view measured: grass and flowers are measured
both spread over 20 m and packed into the 1.8 m disc a garden can paint beside the eye, where each covers the most. Wildlife comes to builds in numbers
its caps bound, however much is built, so what a phase's animals add once they have come, over what its builds were
fitted to cost, is charged once to the base: the room is what is left with every kind of animal there, each phase's
animals counted whole even where two phases bring the same kind. The base is the dearest view of the meadow with its
own plants standing or of the bare meadow, dusk included: the meadow's plants spread far wider than a pool-full phase
packs them, so it is measured whole rather than counted at their prices. Its trees and bushes are charged as planted ones, so the room
is this base less what demo/meadow-flora.json reads them to cost (scripts/layers.py), view by view (docs/design.md). Water costs by the pixels it covers: a square
metre of it costs what small ponds wholly in view give, and all of it at most `water`, the lake phase's dearest view over
the meadow with its own plants, the meadow's whole bowl filled."""
import json
import os
import re
import sys

out = sys.argv[1]
# Each phase, the unit it fits over what earlier phases fitted of its others, and the views it fits from: from the air
# every chunk draws its far meshes.
FAR, NEAR = ("aerial",), ("ground",)
ORDER = [("grass", "grass", None), ("sweep/grass-dense", "grass", None), ("flowers", "flower", None), ("sweep/flowers-dense", "flower", None),
         ("trees", "tree", None), ("bushes", "bush", None),
         ("walls-r10", "wall_m2", FAR), ("walls-r15", "wall_m2", FAR), ("walls-r20", "wall_m2", FAR),
         ("walls-r10", "wall_m2_near", NEAR), ("walls-r15", "wall_m2_near", NEAR), ("walls-r20", "wall_m2_near", NEAR),
         ("plaster", "plaster_m2", FAR), ("plaster", "plaster_m2_near", NEAR), ("fences", "fence_m2", FAR), ("fences", "fence_m2_near", NEAR),
         ("ponds", "pond_m2", None), ("village", "roof_m2", FAR), ("hamlet", "roof_m2", FAR), ("village", "roof_m2_near", NEAR),
         ("hamlet", "roof_m2_near", NEAR), ("thatch", "thatch_m2", FAR),
         ("thatch", "thatch_m2_near", NEAR), ("hamlet", None, None), ("lanterns", "fitting", None), ("meadow", None, None),
         ("hills", None, None), ("stone", None, None), ("easels", "easel", None), ("boulders", "boulder", None)]
# A phase built on another's builds left standing, fitted against it from the same view: only what it changed counts, so
# its unit is not charged the error of prices fitted on other layouts.
ON = {"lanterns": "walls-r10", "thatch": "village"}
WILD = ["flowers-wild", "trees-wild", "fences-wild", "ponds-wild"]

units = {}
# fill_flora is no build command, so the game does not count its plants; the units line after it carries what they would
# count as, and those are the units of its phase.
log = next(p for p in ("godot.log", "logcat.txt") if os.path.exists(os.path.join(out, p)))
for line in open(os.path.join(out, log), errors="replace"):
    m = re.search(r"budget: (\S+) units (\{.*?\}) ms .* flora (\{.*?\})", line)
    if m:
        units[m.group(1)] = json.loads(m.group(3)) or json.loads(m.group(2))
units["base"] = {}

d = json.load(open(os.path.join(out, "metrics.json")))
phases = {}
for s in d["seconds"]:
    if s["label"] != "-" and "viewport_gpu_ms" in s:
        phases.setdefault(s["label"], []).append(s)
mid = lambda xs: sorted(xs)[len(xs) // 2]
gpu, halved = {}, set()
for name, secs in phases.items():
    secs = secs[1:] or secs
    gpu[name] = mid([s["viewport_gpu_ms"] for s in secs])
    if mid([s["frames"] for s in secs]) < round(d["info"]["refresh_hz"]) - 1:
        halved.add(name)

views = [name.split("/")[1] for name in gpu if name.startswith("base/")]
base = {v: gpu[f"base/{v}"] for v in views}
cost = {}


def extras(phase, unit, only=None):
    """What each measured view of `phase` (of `only` views) takes over the base, or over the phase it is built on (ON),
    and over what is fitted of its units other than `unit`, with the units it has."""
    have = units.get(phase, {})
    under = ON.get(phase)
    if under is not None:
        have = {k: have.get(k, 0.0) - units.get(under, {}).get(k, 0.0) for k in {*have, *units.get(under, {})}}
    for v in views:
        name, ref = f"{phase}/{v}", f"{under}/{v}" if under else f"base/{v}"
        if only is not None and v not in only:
            continue
        for n in (name, ref):
            if n in halved:
                print(f"{n}: below the refresh rate, {name} left out", file=sys.stderr)
        if name not in gpu or ref not in gpu or name in halved or ref in halved:
            continue
        extra = gpu[name] - gpu[ref] - sum(have[k] * cost.get(k, 0.0) for k in have if k != unit) / 1000.0
        print(f"{name:20} {gpu[name]:6.2f} ms, {extra:+6.2f} ms over {ref} and what is fitted, units {have}", file=sys.stderr)
        yield extra, have


for phase, unit, only in ORDER:
    for extra, have in extras(phase, unit, only):
        if unit is not None and have.get(unit, 0.0) > 0.0:
            cost[unit] = max(cost.get(unit, 0.0), extra * 1000.0 / have[unit])
missing = [unit for _, unit, _ in ORDER if unit is not None and unit not in cost]
if missing:
    sys.exit(f"costs: no view measured {', '.join(missing)}; nothing written")
# Water costs by the pixels it covers, so a view full of it is the most any garden's water can cost: the meadow's whole
# bowl filled, over the meadow with its own plants from the same view, since the lake drowns those it covers.
lake = [gpu[f"lake/{v}"] - gpu[f"meadow/{v}"] for v in ("aerial", "ground", "shore")
        if f"lake/{v}" in gpu and f"meadow/{v}" in gpu and f"lake/{v}" not in halved and f"meadow/{v}" not in halved]
if not lake:
    sys.exit("costs: no view measured the lake; nothing written")
print(f"lake over the meadow: {', '.join(f'{x:+.2f}' for x in lake)} ms", file=sys.stderr)
water = max(lake)
wild = sum(max([extra for extra, _ in extras(phase, None)] + [0.0]) for phase in WILD)
meadow = [gpu[f"meadow/{v}"] for v in views if f"meadow/{v}" in gpu and f"meadow/{v}" not in halved]
line = {**{k: round(v, 3) for k, v in cost.items()}, "water": round(water * 1000.0, 3), "timber": "TIMBER_US", "arch": "ARCH_US", "moss": f"{round(cost['flower'], 3)} * MOSS_FLOWERS"}
print(", ".join(f'"{k}": {v}' for k, v in line.items()))
base_ms = max([*base.values(), *meadow]) + wild
print(f"base {base_ms:.2f} ms against the {d['info']['budget']['gpu_ms']:.2f} ms line (Budget.line_ms()); CAPACITY_MS is the line less "
      f"this base less what demo/meadow-flora.json reads the meadow's trees and bushes to cost")
