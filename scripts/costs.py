#!/usr/bin/env python3
"""costs.py OUT_DIR, from `CAIRNFOLD_SCENE=demo/costs.json scripts/bench.sh OUT_DIR ...`: a candidate COSTS line.

A phase's cost is its median GPU time (VrApi's App=, at Budget.fit_step) over the bare meadow's, or ON's phase's, from
the same view; a view below the refresh rate is left out, its GPU time not the scene's. A unit takes the most any view
gives it, so the bound holds from every view; grass and flowers are also packed into the 1.8 m disc a garden can paint
beside the eye. Masonry's far rate is fitted from the air, its near excess (`<unit>_near`, Budget.Near) standing.
Wildlife numbers are capped however much is built, so the WILD phases' animals, each phase's counted whole even where
two bring the same kind, are charged once to the base: the dearest view of the bare meadow or of the meadow with its own
plants, measured whole since they spread wider than any phase packs them. The governor's viewport timer is no fit: on
a Quest 2 it reads about 1 ms of timewarp in some runs and not others (docs/design.md, "Bench repeatability on the
Quest 2"); the base carries the timewarp so the room holds."""
import json
import os
import re
import sys

out = sys.argv[1]
# (phase, the unit it fits over what earlier rows fitted of its others, the views it fits from)
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
# Fitted over the phase it is built on, so its unit is not charged the error of prices fitted on other layouts.
ON = {"lanterns": "walls-r10", "thatch": "village"}
WILD = ["flowers-wild", "trees-wild", "fences-wild", "ponds-wild"]

units = {}
# fill_flora is no build command, so its plants' units come from the flora field of the line.
log = next(p for p in ("godot.log", "logcat.txt") if os.path.exists(os.path.join(out, p)))
for line in open(os.path.join(out, log), errors="replace"):
    m = re.search(r"budget: (\S+) units (\{.*?\}) ms .* flora (\{.*?\})", line)
    if m:
        units[m.group(1)] = json.loads(m.group(3)) or json.loads(m.group(2))

d = json.load(open(os.path.join(out, "metrics.json")))
record = json.load(open(os.path.join(out, "record.json")))["phases"]
gpu = {name: p["gpu_ms"] for name, p in record.items() if "gpu_ms" in p}
phases = {}
for s in d["seconds"]:
    if s["label"] in gpu:
        phases.setdefault(s["label"], []).append(s)
mid = lambda xs: sorted(xs)[len(xs) // 2]
halved = {name for name, secs in phases.items() if mid([s["frames"] for s in secs[1:] or secs]) < round(d["info"]["refresh_hz"]) - 1}

views = [name.split("/")[1] for name in gpu if name.startswith("base/")]
base = {v: gpu[f"base/{v}"] for v in views}
cost = {}


def extras(phase, unit, only=None):
    """Yields (ms over the base or ON's phase less what is fitted of units other than `unit`, units) per view."""
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
# Water costs by the pixels it covers, so the filled bowl bounds any garden's; over the meadow with its plants, since
# the lake drowns those it covers.
lake = [gpu[f"lake/{v}"] - gpu[f"meadow/{v}"] for v in ("aerial", "ground", "shore")
        if f"lake/{v}" in gpu and f"meadow/{v}" in gpu and f"lake/{v}" not in halved and f"meadow/{v}" not in halved]
if not lake:
    sys.exit("costs: no view measured the lake; nothing written")
print(f"lake over the meadow: {', '.join(f'{x:+.2f}' for x in lake)} ms", file=sys.stderr)
water = max(lake)
wild = sum(max([extra for extra, _ in extras(phase, None)] + [0.0]) for phase in WILD)
meadow = [gpu[f"meadow/{v}"] for v in views if f"meadow/{v}" in gpu and f"meadow/{v}" not in halved]
line = {**{k: round(v, 3) for k, v in cost.items()}, "water": round(water * 1000.0, 3), "timber": "TIMBER_US", "arch": "ARCH_US", "moss": "MOSS_US"}
print(", ".join(f'"{k}": {v}' for k, v in line.items()))
timewarp = max([record[name].get("timewarp_ms", 0.0) for name in record if name.startswith(("base/", "meadow/")) and name not in halved] + [0.0])
base_ms = max([*base.values(), *meadow]) + wild + timewarp
print(f"base {base_ms:.2f} ms, {timewarp:.2f} of it the compositor's timewarp, against the {d['info']['budget']['gpu_ms']:.2f} ms line (Budget.line_ms()); CAPACITY_MS is the line less "
      f"this base less what demo/meadow-flora.json reads the meadow's trees and bushes to cost")
