#!/usr/bin/env python3
"""distance.py OUT_DIR RECORD.json, from a demo/build-distance.json run.

A spot N is the eye N m from the cluster's middle looking at it, outN N m off looking away, airN 22 m up and N m off. A
spot costs the larger of its two pairs in µs a unit (a wall m² of ivy, Budget.boulder, a moss patch); ivy is no Budget
unit, charged in its walls' masonry rates. tests/test_prices.py holds Budget.COSTS to the "prices" written here."""
import json
import os
import re
import sys
from collections import defaultdict

out = sys.argv[1]
units = {}
log = next(p for p in ("godot.log", "logcat.txt") if os.path.exists(os.path.join(out, p)))
for line in open(os.path.join(out, log), errors="replace"):
    m = re.search(r"budget: (\S+) units (\{.*?\}) ms", line)
    if m:
        units[m.group(1)] = json.loads(m.group(2))
UNIT = {"boulders": "boulder", "moss": "moss", "mossspread": "moss"}
COUNT = {"ivy": lambda u: u["wall_m2"], "boulders": lambda u: u["boulder"], "moss": lambda u: 256, "mossspread": lambda u: 256}

d = json.load(open(os.path.join(out, "metrics.json")))
secs = defaultdict(list)
for s in d["seconds"]:
    if "viewport_gpu_ms" in s:
        secs[s["label"]].append(s["viewport_gpu_ms"])
gpu = {k: sorted(v[1:] or v)[len(v[1:] or v) // 2] for k, v in secs.items()}
each = defaultdict(list)
for name in gpu:
    m = re.fullmatch(r"(\w+)/(\w+)/on/(\d+)", name)
    if m and f"{m[1]}/{m[2]}/off/{int(m[3]) + 1}" in gpu:
        each[m[1], m[2]].append(gpu[name] - gpu[f"{m[1]}/{m[2]}/off/{int(m[3]) + 1}"])
prices = {}
for (kind, spot), ms in each.items():
    n = COUNT[kind](units[kind])
    us = max(ms) * 1000 / n
    print(f"{kind:11} {spot:6} " + " ".join(f"{x:+6.2f}" for x in ms) + f" ms  -> {us:8.3f} µs a unit of {n:.1f}")
    if kind in UNIT and us > prices.get(UNIT[kind], {"us": -1.0})["us"]:
        prices[UNIT[kind]] = {"unit": UNIT[kind], "us": round(us, 3), "at": f"{kind}/{spot}"}
record = json.load(open(sys.argv[2]))
record["prices"] = {f"{k}@distance": v for k, v in prices.items()}
with open(sys.argv[2], "w") as f:
    json.dump(record, f, indent=1)
