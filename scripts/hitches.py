#!/usr/bin/env python3
"""Where a Quest's main thread stalled: the longest runs of busy 20 ms windows in a simpleperf dump of the game, and the
native functions inclusive in each. hitches.py SAMPLES.txt [THREAD] [WINDOWS]

The Quest APK is profileable. While a bench runs, under the headset's adb:
  simpleperf record --app io.github.bddapbot.cairnfold -g -f 1000 --duration SECONDS -o /data/local/tmp/nc.perf.data
then, with Godot's native debug symbols for the template (Godot_native_debug_symbols.VERSION.template_release.android.zip,
arm64-v8a/libgodot_android.so) pushed to /data/local/tmp/sym:
  simpleperf report-sample -i /data/local/tmp/nc.perf.data --symdir /data/local/tmp/sym --show-callchain \\
    --include-thread-name VkThread > /data/local/tmp/samples.txt
and pull samples.txt. On Android Godot's main loop runs on VkThread. GDScript functions show only as the engine calls
they make (ShaderMaterial::set_shader, ResourceLoader::load, ...)."""
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
    cur: Sample | None = None
    for line in open(path, errors="replace"):
        s = line.strip()
        if s == "sample:":
            if cur is not None:
                out.append(cur)
            cur = Sample()
        elif cur is None:
            continue
        elif s.startswith("time:"):
            cur.time = int(s.split()[1])
        elif s.startswith("event_count:"):
            cur.count = int(s.split()[1])
        elif s.startswith("thread_name:"):
            cur.thread = s.split(":", 1)[1].strip()
        elif s.startswith("symbol:"):
            cur.symbols.append(s.split(":", 1)[1].strip())
    if cur is not None:
        out.append(cur)
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
