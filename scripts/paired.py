#!/usr/bin/env python3
"""What a thing costs by itself, from a bench record of paired phases:
    paired.py RECORD.json
    paired.py RECORD.json --price KIND UNIT COUNT FULL=EMPTY...

A scene such as demo/conure-cost.json alternates each view with and without the thing, labelled
pair/PHASE/NTHING/K and pair/PHASE/none/K, K the pair; its order runs with, without, without, with,
so a drift through the run cancels. Each pair's difference is one draw; the mean, its standard error
and that per thing are added to the record under "pairs" and printed.

With --price, each FULL=EMPTY names a phase holding COUNT of KIND and the same view without them. The price is the
most any pair gives a unit, in microseconds; it is added to the record under "prices", KIND's entry naming the Budget
unit it is charged as, and tests/test_prices.py holds every unit's charge to the latest price recorded for it."""
import json
import math
import re
import sys


def stats(xs: list[float]) -> dict[str, float]:
    mean = sum(xs) / len(xs)
    se = math.sqrt(sum((x - mean) ** 2 for x in xs) / (len(xs) - 1) / len(xs)) if len(xs) > 1 else float("nan")
    return {"mean": round(mean, 3), "se": round(se, 3)}


def paired(record: str, d: dict) -> None:
    groups: dict[str, dict[int, dict[str, dict]]] = {}
    count: dict[str, int] = {}
    for name, phase in d["phases"].items():
        m = re.fullmatch(r"pair/(.+)/(?:(\d+)\D*|none)/(\d+)", name)
        if not m:
            continue
        side = "with" if m.group(2) else "without"
        if m.group(2):
            count[m.group(1)] = int(m.group(2))
        groups.setdefault(m.group(1), {}).setdefault(int(m.group(3)), {})[side] = phase
    if not groups:
        sys.exit(f"paired: {record} has no pair/ phases")
    pairs = {}
    print(f"{'phase':12} {'n':>2} {'pairs':>5} {'without ms':>10} {'delta ms':>14} {'per one ms':>14} {'draws':>6} {'prims':>7}")
    for phase, ks in groups.items():
        full = [p for p in ks.values() if "with" in p and "without" in p and "gpu_ms" in p["with"] and "gpu_ms" in p["without"]]
        if not full:
            sys.exit(f"paired: {phase} has no complete pair with GPU times")
        n = count[phase]
        gpu = stats([p["with"]["gpu_ms"] - p["without"]["gpu_ms"] for p in full])
        base = stats([p["without"]["gpu_ms"] for p in full])
        draws = stats([p["with"]["draws"] - p["without"]["draws"] for p in full])
        prims = stats([p["with"]["prims"] - p["without"]["prims"] for p in full])
        pairs[phase] = {"things": n, "pairs": len(full), "without_gpu_ms": base, "gpu_ms": gpu,
                        "gpu_ms_each": {k: round(v / n, 3) for k, v in gpu.items()}, "draws": draws, "prims": prims}
        print(f"{phase:12} {n:2} {len(full):5} {base['mean']:10.2f} {gpu['mean']:7.2f} ± {gpu['se']:4.2f} "
              f"{gpu['mean'] / n:7.3f} ± {gpu['se'] / n:4.3f} {draws['mean']:6.1f} {prims['mean']:7.0f}")
    d["pairs"] = pairs


def price(d: dict, kind: str, unit: str, count: str, *pairs: str) -> None:
    gpu = {name: phase["gpu_ms"] for name, phase in d["phases"].items() if "gpu_ms" in phase}
    each = {}
    for pair in pairs:
        full, empty = pair.split("=")
        each[pair] = (gpu[full] - gpu[empty]) * 1000.0 / float(count)
        print(f"{full:24} over {empty:20} {each[pair]:.3f} µs a {unit}")
    d.setdefault("prices", {})[kind] = {"unit": unit, "us": round(max(each.values()), 3)}
    print(f"{kind}: {d['prices'][kind]['us']} µs a {unit}")


record, *rest = sys.argv[1:]
d = json.load(open(record))
if rest[:1] == ["--price"]:
    price(d, *rest[1:])
else:
    paired(record, d)
with open(record, "w") as f:
    json.dump(d, f, indent=1)
