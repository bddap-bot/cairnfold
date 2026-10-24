#!/usr/bin/env python3
"""What one unit of a build costs a view by how far off it stands, from a demo/build-distance.json run:
distance.py OUT_DIR RECORD.json

Each phase pair shows a kind's cluster from one spot and hides its layer from the same view: SPOT is the eye's metres
from the cluster's middle standing and looking at it, outN standing N m off looking away, airN 22 m up and N m off.
A pair's cost is its viewport GPU time over its partner's; a spot's is the larger of its two pairs, in µs a unit:
a wall m² of ivy, a boulder unit (Budget.boulder), a moss patch. The dearest spot of each kind Budget prices is added to
RECORD (what bench.sh recorded of that run) under "prices", which tests/test_prices.py holds Budget.COSTS to; ivy is no
unit, charged in the masonry rates of the walls it grows on."""
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
    print(f"{kind:11} {spot:6} " + " ".join(f"{x:+6.2f}" for x in ms) + f" ms  -> {max(ms) * 1000 / n:8.3f} µs a unit of {n:.1f}")
    if kind in UNIT and max(ms) * 1000 / n > prices.get(UNIT[kind], {"us": -1.0})["us"]:
        prices[UNIT[kind]] = {"unit": UNIT[kind], "us": round(max(ms) * 1000 / n, 3), "at": f"{kind}/{spot}"}
record = json.load(open(sys.argv[2]))
record["prices"] = {f"{k}@distance": v for k, v in prices.items()}
with open(sys.argv[2], "w") as f:
    json.dump(record, f, indent=1)
