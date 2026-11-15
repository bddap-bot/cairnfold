#!/usr/bin/env python3
"""layers.py OUT_DIR [JSON], OUT_DIR from `CAIRNFOLD_SCENE=demo/meadow-layers.json scripts/bench.sh OUT_DIR ...`.

A layer's cost is its median GPU time (VrApi's App=) shown minus its median hidden; "all" hides every layer at once."""
import json
import os
import statistics
import sys

out = sys.argv[1]
d = json.load(open(os.path.join(out, "metrics.json")))
table = {}
for name, phase in sorted(json.load(open(os.path.join(out, "record.json")))["phases"].items()):
    parts = name.split("/")
    if len(parts) == 4 and "gpu_ms" in phase:
        view, layer, mode, _ = parts
        table.setdefault(view, {}).setdefault(layer, {"on": [], "off": []})[mode].append(phase["gpu_ms"])
result = {}
for view, layers in table.items():
    shown = statistics.median(x for row in layers.values() for x in row["on"])
    print(f"{view}: {shown:.2f} ms shown, median of every shown stretch")
    for layer, row in layers.items():
        saved = statistics.median(row["on"]) - statistics.median(row["off"])
        result.setdefault(view, {})[layer] = {"on": row["on"], "off": row["off"], "saved_ms": round(saved, 3)}
        print(f"  {layer:10} {saved:+6.2f} ms  shown {', '.join(f'{x:.2f}' for x in row['on'])}  hidden {', '.join(f'{x:.2f}' for x in row['off'])}")
    result[view]["shown_ms"] = round(shown, 3)
if len(sys.argv) > 2:
    json.dump({"render_scale": d["info"].get("render_scale"), "views": result}, open(sys.argv[2], "w"), indent=1)
