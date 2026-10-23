import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class BenchmarkRendering(unittest.TestCase):
    def test_failed_rendering_cannot_pass_the_frame_budget(self):
        source = (Path(__file__).resolve().parents[1] / "scripts/bench.sh").read_text()
        report = source.split('python3 - "$out" "$device" "$record" <<\'PY\'\n', 1)[1].rsplit("\nPY", 1)[0]
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            (out / "metrics.json").write_text(json.dumps({
                "info": {"budget": {"gpu_ms": 12.5, "refresh_hz": 72}},
                "seconds": [{"label": "drag", "p50": 13.89, "p99": 13.89,
                             "late": 0, "draws": 100, "prims": 1000}],
            }))
            for log in ["logcat.txt", "godot.log"]:
                with self.subTest(log=log):
                    path = out / log
                    path.write_text('ERROR: When supplying a custom region, it must be contained within the framebuffer rectangle\n')
                    result = subprocess.run([sys.executable, "-c", report, str(out), "desktop", str(out / "record.json")], capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("invalid framebuffer region; rendering failed", result.stderr)
                    path.unlink()
            result = subprocess.run([sys.executable, "-c", report, str(out), "desktop", str(out / "record.json")], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("drag", result.stdout)

    def test_a_quest_game_crash_is_named_a_crash(self):
        source = (Path(__file__).resolve().parents[1] / "scripts/bench.sh").read_text()
        report = source.split('python3 - "$out" "$device" "$record" <<\'PY\'\n', 1)[1].rsplit("\nPY", 1)[0]
        game = '17923700{s}.000  6423  6467 I godot   : {text}\n'
        vrapi = '17923700{s}.000  {pid}  6717 I VrApi   : FPS=72/72,Prd=40ms,App=10.00ms,GPU%=0.5\n'
        ran = (game.format(s=20, text="xr: session at 72.0 Hz")
               + vrapi.format(s=21, pid=6423) + vrapi.format(s=22, pid=6423))
        crashed = ran + ('1792370023.000  6423  6467 F libc    : Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), '
                         'fault addr 0x10 in tid 6467 (VkThread), pid 6423 (pbot.nestbisect)\n') + vrapi.format(s=24, pid=5664)
        logs = {
            "crash": (crashed, "the game crashed during paths/stroke: Fatal signal 11 (SIGSEGV)"),
            "death": (ran + vrapi.format(s=24, pid=5664), "the game died during paths/stroke before its script ended"),
            "shell": (ran + vrapi.format(s=23, pid=5664) + game.format(s=25, text="driver: done"), "another process rendered during paths/stroke"),
        }
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            (out / "metrics.json").write_text(json.dumps({
                "info": {"budget": {"gpu_ms": 12.5, "refresh_hz": 72}},
                "seconds": [{"label": "-" if s == 20 else "paths/stroke", "unix": 1792370000 + s, "p50": 13.89, "p99": 13.89,
                             "late": 0, "draws": 100, "prims": 1000} for s in range(20, 26)],
            }))
            run = lambda: subprocess.run([sys.executable, "-c", report, str(out), "quest", str(out / "record.json")], capture_output=True, text=True)
            for name, (log, message) in logs.items():
                with self.subTest(log=name):
                    (out / "logcat.txt").write_text(log)
                    result = run()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(message, result.stderr)
            (out / "logcat.txt").write_text(ran + game.format(s=25, text="driver: done"))
            result = run()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("paths/stroke", result.stdout)
