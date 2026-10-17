#!/usr/bin/env python3
"""Frame time per scene across the runs bench.sh recorded under perf/RIG/SCENE/: trend.py [RIG [SCENE]]

Per phase, the GPU milliseconds a frame (the desktop, with no GPU target, its median frame time) of the latest run
beside the run before it and the best run, marking a rise of more than a tenth. It only reports: frame time is held to
the budget by bench.sh on a headset, never by a test."""
import json
import os
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../perf")
want = sys.argv[1:]
for rig in sorted(os.listdir(root)) if os.path.isdir(root) else []:
    if want and rig != want[0]:
        continue
    for scene in sorted(os.listdir(os.path.join(root, rig))):
        if len(want) > 1 and scene != want[1]:
            continue
        folder = os.path.join(root, rig, scene)
        runs = [(name[:-5], json.load(open(os.path.join(folder, name)))["phases"]) for name in sorted(os.listdir(folder))]
        latest_name, latest = runs[-1]
        print(f"{rig} {scene}: {len(runs)} runs, latest {latest_name}")
        print(f"  {'phase':24} {'latest':>7} {'before':>7} {'best':>7}")
        for phase, row in latest.items():
            key = "gpu_ms" if "gpu_ms" in row else "p50"
            seen = [r[phase][key] for _, r in runs[:-1] if key in r.get(phase, {})]
            before = seen[-1] if seen else None
            best = min(seen + [row[key]])
            mark = " rose" if before and row[key] > before * 1.1 else ""
            show = lambda v: f"{v:7.2f}" if v is not None else f"{'-':>7}"
            print(f"  {phase:24} {show(row[key])} {show(before)} {show(best)}{mark}")
