#!/usr/bin/env python3
"""Summarise the play sessions recorded under DIR (PlayLog's JSONL chunks, at any depth): how each ran, by what the
player was doing.

    sessions.py DIR [--last N] [--json]

Sessions print oldest first, each with where its chunks were found, its device, build revision, id and length, then
per activity (Metrics.ACTIVITIES) its frames, late frames, p50, p99 and worst frame time, and mean CPU and GPU ms a
frame; then the seconds spent at each quality step, the garden's budget fill, the time paused (headset off, app in
the background), and the worst stalls (Metrics.STALL_MS), each with what the game noted as running long in it, and
what its replay record holds: the frames of input (Replay), any lost to the ring, and its size an hour of play."""
import argparse
import base64
import json
from pathlib import Path
import re
import struct
import sys
import zlib

METRICS = (Path(__file__).resolve().parents[1] / "game/src/metrics.gd").read_text()
ACTIVITIES = json.loads(re.search(r"^const ACTIVITIES := (\[.*\])$", METRICS, re.M).group(1))
BINS_PER_MS = int(re.search(r"^const BINS_PER_MS := (\d+)$", METRICS, re.M).group(1))
STALLS_SHOWN = 20


def read(folder):
    folder = Path(folder).resolve()
    sessions = {}
    for chunk in sorted(folder.rglob("*.jsonl")):
        for line in chunk.read_text().splitlines():
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            s = sessions.setdefault(record.get("session"), {"rows": [], "inputs": [], "replay_bytes": 0,
                                                            "where": chunk.parent.relative_to(folder.parent).as_posix()})
            event = record.get("event")
            if event == "start":
                s.setdefault("start", record)
            elif event == "end":
                s["ended"] = record.get("ended")
            elif event == "frame":
                s["rows"].append(record)
            elif event == "input":
                s["inputs"].append(record)
                s["replay_bytes"] += len(line) + 1
            elif event == "replay":
                s["replay"] = record
                s["replay_bytes"] += len(line) + 1
    out = []
    for sid, s in sessions.items():
        if sid is None or "start" not in s:
            continue
        rows = sorted(s["rows"], key=lambda r: r.get("unix") or 0)
        out.append(summarise(sid, s["start"], s.get("ended"), s["where"], rows) | {"replay": replay(s)})
    return sorted(out, key=lambda x: x["started"])


def frames(event, layout):
    """An "input" event's frames, each {delta, head, hands: [{pose, stick, inputs, flags}]}, as layout lays them out."""
    raw = zlib.decompress(base64.b64decode(event["data"]))
    head_bytes, hand_bytes = struct.calcsize(layout["head"]), struct.calcsize(layout["hand"])
    out = []
    for at in range(0, len(raw), layout["frame_bytes"]):
        delta, *head = struct.unpack_from(layout["head"], raw, at)
        hands = []
        for i, tracker in enumerate(layout["hands"]):
            *pose, sx, sy, held, flags = struct.unpack_from(layout["hand"], raw, at + head_bytes + i * hand_bytes)
            hands.append({"pose": pose, "stick": [sx, sy],
                          "inputs": [n for b, n in enumerate(layout["inputs"][tracker]) if held >> b & 1],
                          "flags": [n for b, n in enumerate(layout["flags"]) if flags >> b & 1]})
        out.append({"delta": delta, "head": head, "hands": hands})
    return out


def replay(s):
    """How much of the session its replay record holds, and its size an hour of the play it covers."""
    layout = s["start"].get("input")
    if not s["inputs"] or not layout:
        return None
    inputs = sorted(s["inputs"], key=lambda e: e["first"])
    held = sum(e["frames"] for e in inputs)
    played = sum(f["delta"] for e in inputs for f in frames(e, layout))
    return {
        "frames": held,
        "missing": inputs[-1]["first"] + inputs[-1]["frames"] - held,
        "seconds": round(played, 1),
        "start": "replay" in s,
        "bytes": s["replay_bytes"],
        "mb_per_hour": round(s["replay_bytes"] / played * 3600 / 1e6, 2) if played else None,
    }


def merge(rows):
    """Every second's activity tallies summed per tag; the histograms merge bin by bin."""
    merged = {}
    for row in rows:
        for tag, t in (row.get("activity") or {}).items():
            m = merged.setdefault(tag, {"frames": 0, "late": 0, "max": 0.0, "hist": {}, "cpu_ms": 0.0, "gpu_ms": 0.0, "gpu_frames": 0})
            for k in ["frames", "late", "cpu_ms", "gpu_ms", "gpu_frames"]:
                m[k] += t.get(k, 0)
            m["max"] = max(m["max"], t.get("max", 0.0))
            for b, n in t.get("hist", {}).items():
                m["hist"][int(b)] = m["hist"].get(int(b), 0) + n
    return merged


def quantile(hist, q):
    """The upper edge of the bin holding the q-th frame, in ms."""
    total = sum(hist.values())
    if total == 0:
        return None
    seen = 0
    for b in sorted(hist):
        seen += hist[b]
        if seen >= q * total:
            return (b + 1) / BINS_PER_MS
    return (max(hist) + 1) / BINS_PER_MS


def summarise(sid, start, ended, where, rows):
    activity = {}
    for tag, m in merge(rows).items():
        activity[tag] = {
            "frames": m["frames"],
            "late": m["late"],
            "p50_ms": quantile(m["hist"], 0.5),
            "p99_ms": quantile(m["hist"], 0.99),
            "worst_ms": round(m["max"], 2),
            "cpu_ms": round(m["cpu_ms"] / m["frames"], 2) if m["frames"] else None,
            "gpu_ms": round(m["gpu_ms"] / m["gpu_frames"], 2) if m["gpu_frames"] else None,
        }
    steps = {}
    for row in rows:
        if "step" in row:
            steps[row["step"]] = steps.get(row["step"], 0) + 1
    fills = [row["fill"] for row in rows if "fill" in row]
    stalls = [dict(s, t=row.get("t")) for row in rows for s in row.get("stalls", [])]
    return {
        "session": sid,
        "where": where,
        "device": start.get("device"),
        "revision": start.get("revision"),
        "started": start.get("started"),
        "ended": ended,
        "seconds": len(rows),
        "refresh_hz": rows[-1].get("refresh_hz") if rows else None,
        "players": max((row.get("context", {}).get("players", 1) for row in rows), default=1),
        "activity": activity,
        "steps": {str(k): v for k, v in sorted(steps.items())},
        "fill": {"max": max(fills), "last": fills[-1]} if fills else None,
        "paused_s": round(sum(row.get("paused_s", 0.0) for row in rows), 1),
        "stalls": stalls,
    }


def text(s):
    from datetime import datetime, timezone
    when = datetime.fromtimestamp(s["started"], timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ") if s["started"] else "?"
    rev = (s["revision"] or "?")[:10]
    end = "" if s["ended"] else ", no end record"
    lines = [f"{s['where']} {s['device']} {rev} {s['session']} {when}: {s['seconds']} s at {s['refresh_hz']} Hz, "
             f"{s['players']} player{'s' if s['players'] != 1 else ''}{end}"]
    lines.append(f"  {'':9} {'frames':>7} {'late':>6} {'p50':>6} {'p99':>6} {'worst':>7} {'cpu':>6} {'gpu':>6}")
    fmt = lambda v: "-" if v is None else f"{v:.1f}"
    for tag in ACTIVITIES:
        a = s["activity"].get(tag)
        if a:
            lines.append(f"  {tag:9} {a['frames']:7} {a['late']:6} {fmt(a['p50_ms']):>6} {fmt(a['p99_ms']):>6} "
                         f"{fmt(a['worst_ms']):>7} {fmt(a['cpu_ms']):>6} {fmt(a['gpu_ms']):>6}")
    if s["steps"]:
        lines.append("  quality steps (s): " + ", ".join(f"{k}: {v}" for k, v in s["steps"].items()))
    if s["fill"]:
        lines.append(f"  budget fill: max {s['fill']['max']:.3f}, last {s['fill']['last']:.3f}")
    if s["paused_s"]:
        lines.append(f"  paused: {s['paused_s']} s")
    if s["replay"]:
        r = s["replay"]
        lost = f", {r['missing']} frames lost to the ring" if r["missing"] else ""
        begun = "" if r["start"] else ", its start lost to the ring"
        lines.append(f"  replay: {r['frames']} frames over {r['seconds']} s, {r['bytes'] / 1e6:.2f} MB, "
                     f"{r['mb_per_hour']} MB an hour{lost}{begun}")
    if s["stalls"]:
        worst = sorted(sorted(s["stalls"], key=lambda x: -x["ms"])[:STALLS_SHOWN], key=lambda x: x["t"] or 0)
        lines.append(f"  stalls: {len(s['stalls'])}, the worst {len(worst)}:")
        for x in worst:
            noted = "; ".join(n["what"] + (f" {n['ms']:.0f} ms" if "ms" in n else "") for n in x.get("notes", [])) or "nothing noted"
            lines.append(f"    {fmt(x['t']):>8} s {x['ms']:7.0f} ms  {','.join(x.get('tags', []))}  scripts {fmt(x.get('scripts_ms'))}/"
                         f"{fmt(x.get('scripts_after_ms'))} ms, pipelines {'+'.join(str(c) for c in x.get('compiled', []))}: {noted}")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder")
    parser.add_argument("--last", type=int, default=0)
    parser.add_argument("--json", action="store_true")
    a = parser.parse_args()
    sessions = read(a.folder)
    if a.last:
        sessions = sessions[-a.last:]
    if not sessions:
        print(f"sessions: none under {a.folder}", file=sys.stderr)
        return 1
    print(json.dumps(sessions, indent=1) if a.json else "\n".join(text(s) for s in sessions))
    return 0


if __name__ == "__main__":
    sys.exit(main())
