import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
REPORT = (SCRIPTS / "bench.sh").read_text().split('python3 - "$out" "$device" "$record" "$players" <<\'PY\'', 1)[1].split("\n", 1)[1].rsplit("\nPY", 1)[0]
sys.path.insert(0, str(SCRIPTS))
import trend  # noqa: E402


class BenchmarkRendering(unittest.TestCase):
    def test_failed_rendering_cannot_pass_the_frame_budget(self):
        report = REPORT
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            (out / "metrics.json").write_text(json.dumps({
                "info": {"budget": {"gpu_ms": 11.111, "refresh_hz": 72}},
                "seconds": [{"label": "drag", "p50": 13.89, "p99": 13.89,
                             "late": 0, "draws": 100, "prims": 1000}],
            }))
            (out / "stress.json").write_text("[]")
            for log in ["logcat.txt", "godot.log"]:
                with self.subTest(log=log):
                    path = out / log
                    path.write_text('ERROR: When supplying a custom region, it must be contained within the framebuffer rectangle\n')
                    result = subprocess.run([sys.executable, "-c", report, str(out), "desktop", str(out / "record.json"), "1"], capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("invalid framebuffer region; rendering failed", result.stderr)
                    path.unlink()
            result = subprocess.run([sys.executable, "-c", report, str(out), "desktop", str(out / "record.json"), "1"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("drag", result.stdout)

    def test_a_quest_game_crash_is_named_a_crash(self):
        report = REPORT
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
                "info": {"budget": {"gpu_ms": 11.111, "refresh_hz": 72}},
                "seconds": [{"label": "-" if s == 20 else "paths/stroke", "unix": 1792370000 + s, "p50": 13.89, "p99": 13.89,
                             "late": 0, "draws": 100, "prims": 1000} for s in range(20, 26)],
            }))
            (out / "stress.json").write_text("[]")
            run = lambda: subprocess.run([sys.executable, "-c", report, str(out), "quest", str(out / "record.json"), "1"], capture_output=True, text=True)
            for name, (log, message) in logs.items():
                with self.subTest(log=name):
                    (out / "logcat.txt").write_text(log)
                    result = run()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(message, result.stderr)
            for name, log in {"clean": ran + game.format(s=25, text="driver: done"),
                              "shell after quit": ran + game.format(s=25, text="driver: done") + vrapi.format(s=27, pid=5664)}.items():
                with self.subTest(log=name):
                    (out / "logcat.txt").write_text(log)
                    result = run()
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("paths/stroke", result.stdout)

    def test_a_phases_stalls_are_kept_in_its_record(self):
        stall = {"ms": 412.5, "tags": ["build"], "scripts_ms": 400.1, "compiled": [0, 2], "notes": [{"what": "wipe", "ms": 390.0}]}
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            (out / "metrics.json").write_text(json.dumps({
                "info": {"budget": {"gpu_ms": 12.5, "refresh_hz": 72}},
                "seconds": [{"label": "wipe/village", "p50": 13.89, "p99": 13.89, "late": 1, "draws": 100, "prims": 1000,
                             **({"stalls": [stall]} if i == 0 else {})} for i in range(3)],
            }))
            (out / "stress.json").write_text("[]")
            result = subprocess.run([sys.executable, "-c", REPORT, str(out), "desktop", str(out / "record.json"), "1"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            phase = json.loads((out / "record.json").read_text())["phases"]["wipe/village"]
            self.assertEqual(phase["stalls"], [{"ms": 412.5, "notes": [{"what": "wipe", "ms": 390.0}], "compiled": [0, 2]}])

    def test_only_a_marked_phase_past_the_build_budget_goes_unheld(self):
        """A phase over the line fails unless the scene marks its label past_budget and its garden is past the
        build budget: an unmarked feature on a dense garden is held, and a mark exempts no garden a player can build."""
        labels = {21: ("feature", 2.0), 22: ("feature", 2.0), 23: ("pricing", 2.0), 24: ("pricing", 2.0), 25: ("buildable", 0.5), 26: ("buildable", 0.5)}
        game = '17923700{s}.000  6423  6467 I godot   : {text}\n'
        vrapi = '17923700{s}.000  6423  6717 I VrApi   : FPS=72/72,Prd=40ms,App=15.00ms,GPU%=0.5\n'
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            (out / "metrics.json").write_text(json.dumps({
                "info": {"budget": {"gpu_ms": 11.111, "refresh_hz": 72}},
                "seconds": [{"label": labels.get(s, ("-", 0.0))[0], "fill": labels.get(s, ("-", 0.0))[1], "unix": 1792370000 + s,
                             "p50": 13.89, "p99": 13.89, "late": 0, "draws": 100, "prims": 1000} for s in range(20, 28)],
            }))
            (out / "stress.json").write_text(json.dumps([{"op": "label", "name": "pricing", "past_budget": True},
                                                         {"op": "label", "name": "buildable", "past_budget": True},
                                                         {"op": "label", "name": "feature"}]))
            (out / "logcat.txt").write_text(game.format(s=20, text="xr: session at 72.0 Hz") + "".join(vrapi.format(s=s) for s in labels)
                                            + game.format(s=27, text="driver: done"))
            result = subprocess.run([sys.executable, "-c", REPORT, str(out), "quest", str(out / "record.json"), "1"], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("over budget: feature, buildable", result.stdout)
            self.assertIn("past the build budget (2.00)", result.stdout)

    def test_a_phase_keeps_the_charges_of_its_fullest_second(self):
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            (out / "metrics.json").write_text(json.dumps({
                "info": {"budget": {"gpu_ms": 12.5, "refresh_hz": 72}},
                "seconds": [{"label": "village", "p50": 13.89, "p99": 13.89, "late": 0, "draws": 100, "prims": 1000,
                             "fill": f, "charges": {"wall_m2": f}} for f in (0.5, 2.0, 1.0)],
            }))
            (out / "stress.json").write_text("[]")
            result = subprocess.run([sys.executable, "-c", REPORT, str(out), "desktop", str(out / "record.json"), "1"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            phase = json.loads((out / "record.json").read_text())["phases"]["village"]
            self.assertEqual((phase["fill"], phase["charges_ms"]), (2.0, {"wall_m2": 2.0}))

    def test_a_phases_peak_memory_is_kept_in_its_record(self):
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            (out / "metrics.json").write_text(json.dumps({
                "info": {"budget": {"gpu_ms": 12.5, "refresh_hz": 72}},
                "seconds": [{"label": "figures", "p50": 13.89, "p99": 13.89, "late": 0, "draws": 100, "prims": 1000,
                             "mem_mb": {"textures": 100.0 + i, "buffers": 50.0 - i, "video": 300.0}} for i in range(3)],
            }))
            (out / "stress.json").write_text("[]")
            result = subprocess.run([sys.executable, "-c", REPORT, str(out), "desktop", str(out / "record.json"), "1"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            phase = json.loads((out / "record.json").read_text())["phases"]["figures"]
            self.assertEqual(phase["mem_mb"], {"textures": 102.0, "buffers": 49.0, "video": 300.0})


class Trend(unittest.TestCase):
    def record(self, folder, name, phases, **more):
        (folder / name).write_text(json.dumps({"budget_gpu_ms": 12.5, **more, "phases": phases}))

    def test_the_latest_run_is_the_newest_timestamp_and_other_files_are_no_runs(self):
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            self.record(out, "20261023T140141Z-d334474.json", {"village/aerial": {"p50": 280.0, "gpu_ms": 271.4}})
            self.record(out, "20261021T140221Z-fe69646.json", {"village/aerial": {"p50": 33.0, "gpu_ms": 31.4}})
            self.record(out, "audio-lifetime-control.json", {"village/aerial": {"p50": 75.0, "gpu_ms": 71.0}})
            (out / "foveation.json").write_text(json.dumps({"runs": []}))
            self.assertEqual([name for name, _ in trend.runs(out)], ["20261021T140221Z-fe69646", "20261023T140141Z-d334474"])
            self.assertEqual(trend.report("quest-2", "stress", out), ["village/aerial"])

    def test_a_rise_stays_one_when_rerun_and_other_player_counts_are_no_base(self):
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            for day in range(1, 4):
                self.record(out, f"2026100{day}T000000Z-aaaaaaa.json", {"a": {"gpu_ms": 30.0}})
            self.record(out, "20261005T000000Z-ccccccc.json", {"a": {"gpu_ms": 90.0}}, players=8)
            self.record(out, "20261006T000000Z-bbbbbbb.json", {"a": {"gpu_ms": 40.0}})
            self.assertEqual(trend.report("rig", "scene", out), ["a"])
            self.record(out, "20261007T000000Z-bbbbbbb.json", {"a": {"gpu_ms": 40.0}})
            self.assertEqual(trend.report("rig", "scene", out), ["a"])
            self.record(out, "20261008T000000Z-ddddddd.json", {"a": {"gpu_ms": 100.0}}, players=8)
            self.assertEqual(trend.report("rig", "scene", out), [])

    def test_only_a_gpu_rise_past_the_noise_fails(self):
        cases = {
            "steady": ({"gpu_ms": 30.0}, {"gpu_ms": 36.0}, []),
            "light": ({"gpu_ms": 4.0}, {"gpu_ms": 5.9}, []),
            "risen": ({"gpu_ms": 30.0}, {"gpu_ms": 40.0}, ["a"]),
            "desktop": ({"p50": 10.0}, {"p50": 20.0}, []),
        }
        for case, (before, latest, risen) in cases.items():
            with self.subTest(case=case), tempfile.TemporaryDirectory(dir=".") as folder:
                out = Path(folder)
                self.record(out, "20261022T000000Z-aaaaaaa.json", {"a": before})
                self.record(out, "20261023T000000Z-bbbbbbb.json", {"a": latest})
                self.assertEqual(trend.report("rig", "scene", out), risen)


class StressScene(unittest.TestCase):
    def test_only_a_wipe_phase_measures_taking_a_garden_away(self):
        """A second's row takes the label current when it is written, which can be a long frame after the second
        ends, so a clear or wipe is two seconds clear of the next measured phase."""
        steps = json.loads((SCRIPTS.parent / "demo/stress.json").read_text())
        label, since, measured = "-", None, []
        for i, step in enumerate(steps):
            if step["op"] == "label":
                label = step["name"]
                if since is not None and since < 2 and label != "-":
                    measured.append(f"{label} starts {since:g} s after a clear")
                if label != "-":
                    since = None
            elif step["op"] in ("clear", "bare") and not label.startswith("wipe/"):
                if label != "-":
                    measured.append(f"step {i} {step['op']} in {label}")
                since = 0.0
            elif since is not None:
                since += step.get("seconds", 0)
        self.assertEqual(measured, [])
        self.assertIn({"op": "label", "name": "wipe/village"}, steps)
