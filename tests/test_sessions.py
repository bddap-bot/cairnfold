import base64
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

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

    def test_replay_frames_decode_and_measure(self):
        layout = {"frame_bytes": 110, "head": "<f7f", "hand": "<7f2fHB", "hands": ["left_hand", "right_hand"],
                  "inputs": {"left_hand": ["trigger_click", "grip_click"], "right_hand": ["trigger_click", "primary_left"]},
                  "flags": ["tracked", "bare"]}
        def frame(i):
            head = struct.pack("<f7f", 1 / 72, 0, 1.6, i * 0.01, 0, 0, 0, 1)
            left = struct.pack("<7f2fHB", -0.2, 1.2, -0.3, 0, 0, 0, 1, 0, 1.0, 0b01 if i % 2 else 0, 0b01)
            right = struct.pack("<7f2fHB", 0.2, 1.2, -0.3, 0, 0, 0, 1, -1.0, 0, 0b10, 0b11)
            return head + left + right
        def event(first, n):
            raw = b"".join(frame(i) for i in range(first, first + n))
            return {"event": "input", "session": "s1", "first": first, "frames": n, "bytes": len(raw),
                    "data": base64.b64encode(zlib.compress(raw)).decode()}
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d)
            start = {"schema": 2, "session": "s1", "started": 1000.0, "revision": "abc", "device": "Quest 2", "event": "start", "part": 1, "input": layout}
            lines = [start, {"event": "replay", "session": "s1", "seeds": {"rng": "1"}, "save": "", "save_bytes": 0},
                     event(0, 72), {"event": "frame", "session": "s1", "unix": 1.0}, event(144, 72), {"event": "end", "session": "s1", "ended": 1002.0}]
            (folder / "s1-0000.jsonl").write_text("".join(json.dumps(l) + "\n" for l in lines))
            [s] = json.loads(subprocess.run([sys.executable, str(READER), d, "--json"], capture_output=True, text=True, check=True).stdout)
            r = s["replay"]
            self.assertEqual((r["frames"], r["missing"], r["seconds"], r["start"]), (144, 72, 2.0, True))
            replay_bytes = sum(len(json.dumps(l)) + 1 for l in lines[1:3] + lines[4:5])
            self.assertEqual(r["bytes"], replay_bytes)
            self.assertEqual(r["mb_per_hour"], round(replay_bytes / 2.0 * 3600 / 1e6, 2))
            sys.path.insert(0, str(READER.parent))
            import sessions
            [f0, f1] = sessions.frames(event(0, 2), layout)[:2]
            self.assertEqual(f1["hands"][0]["inputs"], ["trigger_click"])
            self.assertEqual(f0["hands"][0]["inputs"], [])
            right = f1["hands"][1]
            self.assertEqual((right["stick"], right["inputs"], right["flags"]), ([-1.0, 0], ["primary_left"], ["tracked", "bare"]))
            for got, want in zip(right["pose"], [0.2, 1.2, -0.3, 0, 0, 0, 1]):
                self.assertAlmostEqual(got, want, places=6)
            self.assertAlmostEqual(f1["head"][2], 0.01)
            self.assertAlmostEqual(f1["delta"], 1 / 72)
            text = subprocess.run([sys.executable, str(READER), d], capture_output=True, text=True, check=True).stdout
            self.assertIn("replay: 144 frames over 2.0 s", text)
            self.assertIn("72 frames lost to the ring", text)

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
