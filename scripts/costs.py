#!/usr/bin/env python3
"""Fits the frame budget's unit costs (Budget.COSTS) from a run of demo/costs.json: costs.py OUT_DIR

OUT_DIR is what `NESTCOMBE_SCENE=demo/costs.json scripts/bench.sh OUT_DIR ...` left on a headset. Each phase is the
bare meadow plus one kind of build, at the quality ladder's bottom step, from the air and standing; its cost is its
median viewport GPU time (the governor's signal) over the bare meadow's from the same view. A phase whose frames fell
to half rate is left out: GPU time read there is not the scene's. A unit's cost is the most any view of any phase
holding it as the one unknown gives, so the bound holds from every view measured."""
import json
import os
import re
import sys

out = sys.argv[1]
# fill_flora is no build command, so the game does not count these; the pools' sizes are Flora's.
FLORA = {"grass": {"grass": 12000}, "flowers": {"flower": 4000}, "trees": {"tree": 64}}
# Each phase and the unit it fits, over what earlier phases fitted of its others.
ORDER = [("grass", "grass"), ("flowers", "flower"), ("trees", "tree"), ("walls-r10", "wall_m2"), ("walls-r15", "wall_m2"),
         ("walls-r20", "wall_m2"), ("plaster", "plaster_m2"), ("fences", "fence_m2"), ("paths", "path_m2"), ("ponds", "pond"),
         ("village", "roof_m2"), ("lanterns", "fitting"), ("meadow", "bush"), ("hills", None), ("stone", None)]

units = {}
log = next(p for p in ("godot.log", "logcat.txt") if os.path.exists(os.path.join(out, p)))
for line in open(os.path.join(out, log), errors="replace"):
    m = re.search(r"budget: (\S+) units (\{.*?\}) ms", line)
    if m:
        units[m.group(1)] = json.loads(m.group(2))
units.update(FLORA)
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
    if mid([s["frames"] for s in secs]) < 60:
        halved.add(name)

views = ["aerial", "ground"]
base = {v: gpu[f"base/{v}"] for v in views}
cost = {}
for phase, unit in ORDER:
    have = units.get(phase, {})
    for v in views:
        name = f"{phase}/{v}"
        if name not in gpu or name in halved:
            print(f"{name}: {'half rate, left out' if name in halved else 'not measured'}", file=sys.stderr)
            continue
        extra = gpu[name] - base[v] - sum(have[k] * cost[k] for k in have if k != unit) / 1000.0
        print(f"{name:16} {gpu[name]:6.2f} ms, {extra:+6.2f} ms over the base and what is fitted, units {have}", file=sys.stderr)
        if unit is not None:
            cost[unit] = max(cost.get(unit, 0.0), extra * 1000.0 / have[unit])
print(json.dumps({"base_ms": round(max(base.values()), 2), **{k: round(v, 3) for k, v in cost.items()}}))
