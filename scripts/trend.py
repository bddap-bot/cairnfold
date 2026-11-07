#!/usr/bin/env python3
"""Frame time per scene across the runs bench.sh recorded under perf/RIG/SCENE/: trend.py [RIG [SCENE]]
Two runs' records phase by phase, a candidate against its control: trend.py --pair CONTROL CANDIDATE

Per phase, the GPU milliseconds a frame (the desktop, with no GPU target, its median frame time) of the latest run
beside its base, the median of the BASE runs before it with as many players and the phase on the same quality step, and
the best run, marking a rise of more than RISE times and FLOOR_MS over the base. A phase the governor walks settles on
whichever step the phases before it leave it at, and its GPU time is that step's, so only runs on one step compare.
Runs are the records bench.sh names TIMESTAMP-REVISION.json, ordered by that timestamp, not by commit, so a late
bench of an older commit is the latest run; any other file is no run. Given
a scene, exits 1 when a phase's GPU time rose, so a bench run recording a regression fails, and fails again when
rerun once. A pair compares a phase only when both runs held it pinned at one step: a governed phase measures the
governor, not the change, so the pair refuses it, naming its steps, and exits 1, as it does when a phase rose as a
scene's run does; beside each it shows both runs' worst second, which a median hides."""
import json
import os
import re
import statistics
import sys
from pathlib import Path

# Two Quest 2 stress runs of one build (a4d3a15) differ by under this on all but five of 132 phases; those five, aerial
# views of big builds among them, read up to five times apart, which the median of a few runs absorbs.
BASE = 3
RISE = 1.25
FLOOR_MS = 2.0
ROSE = f"GPU time rose more than {RISE - 1:.0%} and {FLOOR_MS:g} ms: "
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


def rise(base, ms):
    return ms > base * RISE and ms - base > FLOOR_MS


def report(rig, scene, folder):
    """Prints the scene's trend; returns the phases whose GPU time rose."""
    found = runs(folder)
    if not found:
        return []
    latest_name, latest = found[-1]
    players = latest.get("players", 1)
    earlier = [r["phases"] for _, r in found[:-1] if r.get("players", 1) == players]
    print(f"{rig} {scene}: {len(found)} runs, latest {latest_name}" + (f", {players} players" if players > 1 else ""))
    print(f"  {'phase':24} {'step':>4} {'latest':>7} {'base':>7} {'best':>7}")
    risen = []
    for phase, row in latest["phases"].items():
        key = "gpu_ms" if "gpu_ms" in row else "p50"
        seen = [r[phase][key] for r in earlier if key in r.get(phase, {}) and r[phase].get("step") == row.get("step")]
        base = statistics.median(seen[-BASE:]) if seen else None
        best = min(seen + [row[key]])
        rose = base is not None and rise(base, row[key])
        if rose and key == "gpu_ms":
            risen.append(phase)
        print(f"  {phase:24} {row.get('step', '-'):>4} {shown(row[key])} {shown(base)} {shown(best)}{' rose' if rose else ''}")
    return risen


def shown(v):
    return f"{v:7.2f}" if v is not None else f"{'-':>7}"


def unpinned(phases):
    """Why the named phases do not compare, each not held pinned at one step; None when they do."""
    at = lambda p: f" at step {p['step']}" if "step" in p else ""
    governed = [f"{name} {'governed' if 'pinned' in p else 'unrecorded pin'}{at(p)}" for name, p in phases.items()
                if not p.get("pinned")]
    if governed:
        return ", ".join(governed)
    if len({p["step"] for p in phases.values()}) > 1:
        return ", ".join(f"{name}{at(p)}" for name, p in phases.items())
    return None


def pair(control, candidate):
    """Prints candidate's phases against control's; returns (risen, (phase, why) for each refused)."""
    a, b = control["phases"], candidate["phases"]
    for side, mine, other in (("control", a, b), ("candidate", b, a)):
        only = [phase for phase in mine if phase not in other]
        if only:
            print(f"  only in {side}: {', '.join(only)}")
    print(f"  {'phase':24} {'steps':>7} {'gpu ms':>15} {'frame p50':>15} {'worst second':>28}")
    risen, refused = [], []
    worst = lambda r: (f"{r['worst']['late']:3} late p50 {r['worst']['p50']:5.1f} p99 {r['worst']['p99']:5.1f}"
                       if "worst" in r else f"{'-':>28}")
    for phase, new in b.items():
        if phase not in a:
            continue
        old = a[phase]
        key = "gpu_ms" if "gpu_ms" in new and "gpu_ms" in old else "p50"
        why = unpinned({"control": old, "candidate": new})
        if why:
            refused.append((phase, why))
            verdict = "refused"
        elif rise(old[key], new[key]):
            if key == "gpu_ms":
                risen.append(phase)
            verdict = "slower"
        elif rise(new[key], old[key]):
            verdict = "faster"
        else:
            verdict = ""
        steps = f"{old.get('step', '-')}/{new.get('step', '-')}"
        print(f"  {phase:24} {steps:>7} {shown(old.get('gpu_ms'))} {shown(new.get('gpu_ms'))} {shown(old.get('p50'))} {shown(new.get('p50'))}"
              f" {worst(old)} | {worst(new)} {verdict}".rstrip())
    return risen, refused


def main(want):
    if want[:1] == ["--pair"]:
        if len(want) != 3:
            sys.exit("usage: trend.py --pair CONTROL CANDIDATE")
        control, candidate = (json.loads(Path(path).read_text()) for path in want[1:])
        risen, refused = pair(control, candidate)
        for phase, why in refused:
            print(f"refused {phase}, not pinned at one step: {why}", file=sys.stderr)
        if risen:
            print(ROSE + ", ".join(risen), file=sys.stderr)
        return 1 if risen or refused else 0

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
        print(ROSE + ", ".join(risen), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
