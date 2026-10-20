#!/usr/bin/env python3
"""Fits the frame budget's unit costs from a run of demo/costs.json and writes them into game/src/budget.gd as the
headset's line of Budget.COSTS: costs.py OUT_DIR QUEST_2|FRAME

OUT_DIR is what `NESTCOMBE_SCENE=demo/costs.json scripts/bench.sh OUT_DIR ...` left on that headset. Each phase is the
bare meadow plus one kind of build, at the step the headset's budget is fitted at (Budget.fit_step), from the air and standing; its cost is its
median viewport GPU time (the governor's signal) over the bare meadow's from the same view. A view whose frames fell
below the refresh rate is left out: GPU time read there is not the scene's. A unit's cost is the most any view of any phase
holding it as the one unknown gives, so the bound holds from every view measured. Wildlife comes to builds in numbers
its caps bound, however much is built, so what a phase's animals add once they have come, over what its builds were
fitted to cost, is charged once to the base: the room is what is left with every kind of animal there, each phase's
animals counted whole even where two phases bring the same kind. The base is the dearest view of the meadow with its
own plants standing or of the bare meadow, dusk included: the meadow's plants spread far wider than a pool-full phase
packs them, so it is measured whole rather than counted at their prices."""
import json
import os
import re
import sys

out, device = sys.argv[1], sys.argv[2]
# fill_flora is no build command, so the game does not count these; the pools' sizes are Flora's.
FLORA = {"grass": {"grass": 12000}, "flowers": {"flower": 4000}, "trees": {"tree": 64}, "bushes": {"bush": 256}}
FLORA.update({"flowers-wild": FLORA["flowers"], "trees-wild": FLORA["trees"]})
# Each phase and the unit it fits, over what earlier phases fitted of its others.
ORDER = [("grass", "grass"), ("flowers", "flower"), ("trees", "tree"), ("bushes", "bush"), ("walls-r10", "wall_m2"), ("walls-r15", "wall_m2"),
         ("walls-r20", "wall_m2"), ("plaster", "plaster_m2"), ("fences", "fence_m2"), ("ponds", "pond"),
         ("village", "roof_m2"), ("floors", "floor_m2"), ("thatch", "thatch_m2"), ("lanterns", "fitting"), ("meadow", None), ("hills", None), ("stone", None), ("easels", "easel"), ("boulders", "boulder")]
WILD = ["flowers-wild", "trees-wild", "fences-wild", "ponds-wild"]

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
    if mid([s["frames"] for s in secs]) < round(d["info"]["refresh_hz"]) - 1:
        halved.add(name)

views = [name.split("/")[1] for name in gpu if name.startswith("base/")]
base = {v: gpu[f"base/{v}"] for v in views}
cost = {}


def extras(phase, unit):
    """What each measured view of `phase` takes over the base and over what is fitted of its units other than `unit`."""
    have = units.get(phase, {})
    for v in views:
        name = f"{phase}/{v}"
        if name in halved:
            print(f"{name}: below the refresh rate, left out", file=sys.stderr)
        if name not in gpu or name in halved:
            continue
        extra = gpu[name] - base[v] - sum(have[k] * cost[k] for k in have if k != unit) / 1000.0
        print(f"{name:20} {gpu[name]:6.2f} ms, {extra:+6.2f} ms over the base and what is fitted, units {have}", file=sys.stderr)
        yield extra, have


for phase, unit in ORDER:
    for extra, have in extras(phase, unit):
        if unit is not None:
            cost[unit] = max(cost.get(unit, 0.0), extra * 1000.0 / have[unit])
missing = [unit for _, unit in ORDER if unit is not None and unit not in cost]
if missing:
    sys.exit(f"costs: no view measured {', '.join(missing)}; nothing written")
wild = sum(max([extra for extra, _ in extras(phase, None)] + [0.0]) for phase in WILD)
meadow = [gpu[f"meadow/{v}"] for v in views if f"meadow/{v}" in gpu and f"meadow/{v}" not in halved]
line = {"budget_ms": "1000.0 / REFRESH_HZ * Quality.Governor.LINE", "base_ms": round(max([*base.values(), *meadow]) + wild, 2),
        **{k: round(v, 3) for k, v in cost.items()}, "timber": "TIMBER_US"}
text = ", ".join(f'"{k}": {v}' for k, v in line.items())
budget = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../game/src/budget.gd")
src = open(budget).read()
src, n = re.subn(rf"^const {device}_COSTS := \{{.*\}}$", f"const {device}_COSTS := {{{text}}}", src, flags=re.M)
if n != 1:
    sys.exit(f"costs: no line `const {device}_COSTS := {{...}}` in {budget}")
open(budget, "w").write(src)
print(f"costs: {device} {text}")
