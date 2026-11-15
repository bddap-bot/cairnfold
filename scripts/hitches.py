#!/usr/bin/env python3
"""hitches.py SAMPLES.txt [THREAD] [WINDOWS]: the longest runs of busy 20 ms windows on a Quest's main thread.

The APK is profileable. During a bench, with the template's native debug symbols (arm64-v8a/libgodot_android.so from
Godot_native_debug_symbols.VERSION.template_release.android.zip) in /data/local/tmp/sym:
  simpleperf record --app io.github.bddapbot.cairnfold -g -f 1000 --duration SECONDS -o /data/local/tmp/nc.perf.data
  simpleperf report-sample -i /data/local/tmp/nc.perf.data --symdir /data/local/tmp/sym --show-callchain \\
    --include-thread-name VkThread > /data/local/tmp/samples.txt
Godot's Android main loop runs on VkThread; GDScript shows only as the engine calls it makes."""
import collections
import sys
from dataclasses import dataclass, field

BUCKET_NS = 20_000_000


@dataclass
class Sample:
    time: int = 0
    count: int = 0
    thread: str = ""
    symbols: list[str] = field(default_factory=list)


def read(path: str) -> list[Sample]:
    out: list[Sample] = []
    for line in open(path, errors="replace"):
        s = line.strip()
        if s == "sample:":
            out.append(Sample())
        elif not out:
            continue
        elif s.startswith("time:"):
            out[-1].time = int(s.split()[1])
        elif s.startswith("event_count:"):
            out[-1].count = int(s.split()[1])
        elif s.startswith("thread_name:"):
            out[-1].thread = s.split(":", 1)[1].strip()
        elif s.startswith("symbol:"):
            out[-1].symbols.append(s.split(":", 1)[1].strip())
    return out


def main() -> None:
    thread = sys.argv[2] if len(sys.argv) > 2 else "VkThread"
    windows = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    samples = sorted((s for s in read(sys.argv[1]) if s.thread == thread), key=lambda s: s.time)
    if not samples:
        sys.exit(f"hitches: no samples on {thread}")
    t0 = samples[0].time
    buckets: collections.Counter[int] = collections.Counter()
    for s in samples:
        buckets[(s.time - t0) // BUCKET_NS] += s.count
    # A frame's main thread sleeps in the runtime's wait between frames; a stall keeps it busy bucket after bucket.
    busy = sorted(buckets.values())[len(buckets) * 9 // 10] * 0.8
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for k in range(max(buckets) + 2):
        hot = buckets.get(k, 0) >= busy
        if hot and start is None:
            start = k
        elif not hot and start is not None:
            runs.append((start, k))
            start = None
    for a, b in sorted(sorted(runs, key=lambda r: r[1] - r[0], reverse=True)[:windows]):
        inclusive: collections.Counter[str] = collections.Counter()
        total = 0
        for s in samples:
            if t0 + a * BUCKET_NS <= s.time < t0 + b * BUCKET_NS:
                total += s.count
                for f in set(s.symbols):
                    inclusive[f] += s.count
        print(f"== {a * BUCKET_NS / 1e9:.2f}s to {b * BUCKET_NS / 1e9:.2f}s after recording began, {(b - a) * BUCKET_NS // 1_000_000} ms busy")
        for f, c in inclusive.most_common(40):
            print(f"  {100 * c / total:5.1f}%  {f[:170]}")


main()
