#!/usr/bin/env python3
"""usage: write_defaults.py RECORDING... > write-defaults.json

Reduces recordings of Avatar Workshop's reference harness playing its write-defaults fixture (AW_WD, AW_STEPS) to what
each step set and what the properties its layers animate read on its last frame. A recording whose transitions take
time is refused: its values hang on the frame rate.
"""
import csv
import json
import re
import sys
from pathlib import Path

KEYS = {"Hat": "active:Hat", "HatR": "enabled:Hat", "Color": "mat:Body:_Color"}


def rows(path: Path) -> list[list[str]]:
    with path.open(newline="") as f:
        return list(csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE))


def case(out: Path) -> dict[str, object]:
    layers = (out / "spec.txt").read_text().strip()
    if re.search(r"/[\d.]+[^:]*:", layers):
        sys.exit(f"{out}: {layers} has a transition that takes time")
    states = [state for layer in layers.split(";") for state in layer.split(":")[1].split("|")]
    properties = sorted({pair.split("=")[0] for state in states for pair in state[1:].split("+") if "=" in pair})
    keys = {KEYS.get(p, f"shape:Body:{p}"): p for p in properties}
    changes = [(int(f), keys[k], float(v.split(",")[0])) for f, k, v in rows(out / "values.tsv") if k in keys]
    steps = []
    for _, start, frames, _, label, *_ in rows(out / "steps.tsv"):
        last = int(start) + int(frames) - 1
        values: dict[str, float] = {}
        for frame, name, value in changes:
            if frame <= last:
                values[name] = value
        sets = {} if label == "rest" else {k: float(v) for k, v in (pair.split("=") for pair in label.split(","))}
        steps.append({"set": sets, "frames": int(frames), "values": values})
    return {"layers": layers, "steps": steps}


if __name__ == "__main__":
    json.dump({Path(p).name: case(Path(p)) for p in sorted(sys.argv[1:])}, sys.stdout, indent=1)
    print()
