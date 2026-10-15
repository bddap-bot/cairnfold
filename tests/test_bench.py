import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class BenchmarkRendering(unittest.TestCase):
    def test_failed_rendering_cannot_pass_the_frame_budget(self):
        source = (Path(__file__).resolve().parents[1] / "scripts/bench.sh").read_text()
        report = source.split('python3 - "$out" "$device" <<\'PY\'\n', 1)[1].rsplit("\nPY", 1)[0]
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            (out / "metrics.json").write_text(json.dumps({
                "info": {"budget": {"gpu_ms": 12.5, "refresh_hz": 72}},
                "seconds": [{"label": "drag", "p50": 13.89, "p99": 13.89,
                             "draws": 100, "prims": 1000}],
            }))
            for log in ["logcat.txt", "godot.log"]:
                with self.subTest(log=log):
                    path = out / log
                    path.write_text('ERROR: When supplying a custom region, it must be contained within the framebuffer rectangle\n')
                    result = subprocess.run([sys.executable, "-c", report, str(out), "desktop"], capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("invalid framebuffer region; rendering failed", result.stderr)
                    path.unlink()
            result = subprocess.run([sys.executable, "-c", report, str(out), "desktop"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("drag", result.stdout)
