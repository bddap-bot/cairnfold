import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

READER = Path(__file__).resolve().parents[1] / "scripts/sessions.py"


def tally(hist_ms, late=0, cpu=2.0, gpu=None):
    hist = {}
    for ms in hist_ms:
        hist[str(int(ms * 2))] = hist.get(str(int(ms * 2)), 0) + 1
    return {"frames": len(hist_ms), "late": late, "max": max(hist_ms), "hist": hist, "cpu_ms": cpu * len(hist_ms),
            "gpu_ms": (gpu or 0.0) * len(hist_ms), "gpu_frames": len(hist_ms) if gpu else 0}


class Sessions(unittest.TestCase):
    def write(self, folder, session, rows, part=0, end=True):
        start = {"schema": 1, "session": session, "started": 1000.0 + part, "revision": "abc1234def", "device": "Quest 2", "event": "start", "part": part + 1}
        lines = [start] + [dict(r, event="frame", session=session) for r in rows]
        if end:
            lines.append({"event": "end", "session": session, "ended": 2000.0})
        (folder / f"{session}-{part:04d}.jsonl").write_text("".join(json.dumps(l) + "\n" for l in lines))

    def test_activities_merge_across_seconds_and_chunks(self):
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d) / "quest2"
            folder.mkdir()
            self.write(folder, "s1", [{"unix": 1.0, "refresh_hz": 72, "step": 0, "fill": 0.2,
                                       "activity": {"moving": tally([13.9] * 96 + [30.0, 30.0, 30.0, 40.0], late=4, gpu=9.0), "still": tally([13.9] * 50)}}], end=False)
            self.write(folder, "s1", [{"unix": 2.0, "refresh_hz": 72, "step": 1, "fill": 0.5, "context": {"players": 2},
                                       "activity": {"moving": tally([13.9] * 100, gpu=11.0), "coop": tally([13.9] * 100)}}], part=1)
            out = subprocess.run([sys.executable, str(READER), d, "--json"], capture_output=True, text=True, check=True)
            [s] = json.loads(out.stdout)
            self.assertEqual(s["where"], f"{Path(d).resolve().name}/quest2")
            one = subprocess.run([sys.executable, str(READER), str(folder), "--json"], capture_output=True, text=True, check=True)
            self.assertEqual(json.loads(one.stdout)[0]["where"], "quest2", "a device's own folder is named by itself")
            self.assertEqual(s["seconds"], 2)
            self.assertEqual(s["players"], 2)
            self.assertEqual(s["ended"], 2000.0)
            moving = s["activity"]["moving"]
            self.assertEqual(moving["frames"], 200)
            self.assertEqual(moving["late"], 4)
            self.assertEqual(moving["worst_ms"], 40.0)
            self.assertEqual(moving["p50_ms"], 14.0)
            self.assertEqual(moving["p99_ms"], 30.5, "the 198th of 200 frames is a 30 ms one, in its 0.5 ms bin")
            self.assertEqual(moving["gpu_ms"], 10.0)
            self.assertEqual(s["steps"], {"0": 1, "1": 1})
            self.assertEqual(s["fill"], {"max": 0.5, "last": 0.5})
            text = subprocess.run([sys.executable, str(READER), d], capture_output=True, text=True, check=True).stdout
            self.assertIn("/quest2 Quest 2 abc1234def s1", text)
            self.assertIn("moving", text)
            self.assertIn("coop", text)

    def test_stalls_and_pauses_are_listed(self):
        with tempfile.TemporaryDirectory() as d:
            stall = {"ms": 437.0, "tags": ["still"], "scripts_ms": 12.0, "scripts_after_ms": 436.0, "compiled": [0, 2],
                     "notes": [{"what": "world: applying wipe", "ms": 431.0}, {"what": "wheel: right opened"}]}
            self.write(Path(d), "s", [{"unix": 1.0, "t": 10.0, "paused_s": 52.5, "stalls": [stall]}, {"unix": 2.0, "t": 11.0, "paused_s": 1.0}])
            [s] = json.loads(subprocess.run([sys.executable, str(READER), d, "--json"], capture_output=True, text=True, check=True).stdout)
            self.assertEqual(s["paused_s"], 53.5)
            self.assertEqual(s["stalls"], [dict(stall, t=10.0)])
            text = subprocess.run([sys.executable, str(READER), d], capture_output=True, text=True, check=True).stdout
            self.assertIn("paused: 53.5 s", text)
            self.assertIn("437 ms  still  scripts 12.0/436.0 ms, pipelines 0+2: world: applying wipe 431 ms; wheel: right opened", text)

    def test_last_keeps_the_newest_and_an_empty_folder_fails(self):
        with tempfile.TemporaryDirectory() as d:
            self.write(Path(d), "old", [{"unix": 1.0}], part=0)
            self.write(Path(d), "new", [{"unix": 9.0}], part=5)
            out = subprocess.run([sys.executable, str(READER), d, "--last", "1", "--json"], capture_output=True, text=True, check=True)
            self.assertEqual([s["session"] for s in json.loads(out.stdout)], ["new"])
        with tempfile.TemporaryDirectory() as d:
            self.assertNotEqual(subprocess.run([sys.executable, str(READER), d], capture_output=True).returncode, 0)
