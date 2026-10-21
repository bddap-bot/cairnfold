#!/usr/bin/env python3
"""What one kind of build costs a unit, from a bench record: prices.py RECORD.json KIND UNIT COUNT FULL=EMPTY...

Each FULL=EMPTY names a phase holding COUNT of KIND and the same view without them. The price is the most any pair
gives a unit, in microseconds; it is added to the record under "prices", KIND's entry naming the Budget unit it is
charged as, and tests/test_prices.py holds every unit's charge to the latest price recorded for it."""
import json
import sys

record, kind, unit, count, *pairs = sys.argv[1:]
d = json.load(open(record))
gpu = {name: phase["gpu_ms"] for name, phase in d["phases"].items() if "gpu_ms" in phase}
each = {}
for pair in pairs:
    full, empty = pair.split("=")
    each[pair] = (gpu[full] - gpu[empty]) * 1000.0 / float(count)
    print(f"{full:24} over {empty:20} {each[pair]:.3f} µs a {unit}")
d.setdefault("prices", {})[kind] = {"unit": unit, "us": round(max(each.values()), 3)}
with open(record, "w") as f:
    json.dump(d, f, indent=1)
print(f"{kind}: {d['prices'][kind]['us']} µs a {unit}")
