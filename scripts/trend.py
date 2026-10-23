#!/usr/bin/env python3
"""Frame time per scene across the runs bench.sh recorded under perf/RIG/SCENE/: trend.py [RIG [SCENE]]

Per phase, the GPU milliseconds a frame (the desktop, with no GPU target, its median frame time) of the latest run
beside its base, the median of the BASE runs before it with as many players, and the best run, marking a rise of more
than RISE times and FLOOR_MS over the base. Runs are the records bench.sh names TIMESTAMP-REVISION.json, ordered by that
timestamp; any other file is no run. Given a scene, exits 1 when a phase's GPU time rose, so a bench run recording a
regression fails, and fails again when rerun once."""
import json
import os
import re
import statistics
import sys

# Two Quest 2 stress runs of one build (a4d3a15) differ by under this on all but five of 132 phases; those five, aerial
# views of big builds among them, read up to five times apart, which the median of a few runs absorbs.
BASE = 3
RISE = 1.25
FLOOR_MS = 2.0
RUN = re.compile(r"(\d{8}T\d{6}Z)-[0-9a-f]+\.json")
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../perf")


def runs(folder):
    """The (name, record) of each run recorded in folder, oldest first."""
    found = []
    for name in sorted((n for n in os.listdir(folder) if RUN.fullmatch(n)), key=lambda n: RUN.fullmatch(n).group(1)):
        with open(os.path.join(folder, name)) as f:
            record = json.load(f)
        if "phases" in record:
            found.append((name[:-5], record))
    return found


def report(rig, scene, folder):
    """Prints the scene's trend; returns the phases whose GPU time rose."""
    found = runs(folder)
    if not found:
        return []
    latest_name, latest = found[-1]
    players = latest.get("players", 1)
    earlier = [r["phases"] for _, r in found[:-1] if r.get("players", 1) == players]
    print(f"{rig} {scene}: {len(found)} runs, latest {latest_name}" + (f", {players} players" if players > 1 else ""))
    print(f"  {'phase':24} {'latest':>7} {'base':>7} {'best':>7}")
    risen = []
    show = lambda v: f"{v:7.2f}" if v is not None else f"{'-':>7}"
    for phase, row in latest["phases"].items():
        key = "gpu_ms" if "gpu_ms" in row else "p50"
        seen = [r[phase][key] for r in earlier if key in r.get(phase, {})]
        base = statistics.median(seen[-BASE:]) if seen else None
        best = min(seen + [row[key]])
        rose = base is not None and row[key] > base * RISE and row[key] - base > FLOOR_MS
        if rose and key == "gpu_ms":
            risen.append(phase)
        print(f"  {phase:24} {show(row[key])} {show(base)} {show(best)}{' rose' if rose else ''}")
    return risen


def main(want):
    risen = []
    for rig in sorted(os.listdir(ROOT)) if os.path.isdir(ROOT) else []:
        if want and rig != want[0]:
            continue
        for scene in sorted(os.listdir(os.path.join(ROOT, rig))):
            folder = os.path.join(ROOT, rig, scene)
            if len(want) > 1 and scene != want[1] or not os.path.isdir(folder):
                continue
            risen += [f"{rig} {scene} {phase}" for phase in report(rig, scene, folder)]
    if risen and len(want) > 1:
        print(f"GPU time rose more than {RISE - 1:.0%} and {FLOOR_MS:g} ms: " + ", ".join(risen), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
