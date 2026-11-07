import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
REPORT = (SCRIPTS / "bench.sh").read_text().split('python3 - "$out" "$device" "$record" "$players" <<\'PY\'', 1)[1].split("\n", 1)[1].rsplit("\nPY", 1)[0]
sys.path.insert(0, str(SCRIPTS))
import trend  # noqa: E402


def report(out, device):
    return subprocess.run([sys.executable, "-c", REPORT, str(out), device, str(out / "record.json"), "1"], capture_output=True, text=True,
                          env={**os.environ, "PYTHONPATH": str(SCRIPTS)})


def bench(out, device, gpu_ms, seconds, stress="[]"):
    (out / "metrics.json").write_text(json.dumps({"info": {"budget": {"gpu_ms": gpu_ms, "refresh_hz": 72}}, "seconds": seconds}))
    (out / "stress.json").write_text(stress)
    return report(out, device)


class BenchmarkRendering(unittest.TestCase):
    def test_failed_rendering_cannot_pass_the_frame_budget(self):
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            seconds = [{"label": "drag", "p50": 13.89, "p99": 13.89, "late": 0, "draws": 100, "prims": 1000}]
            for log in ["logcat.txt", "godot.log"]:
                with self.subTest(log=log):
                    path = out / log
                    path.write_text('ERROR: When supplying a custom region, it must be contained within the framebuffer rectangle\n')
                    result = bench(out, "desktop", 11.111, seconds)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("invalid framebuffer region; rendering failed", result.stderr)
                    path.unlink()
            result = report(out, "desktop")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("drag", result.stdout)

    def test_a_quest_game_crash_is_named_a_crash(self):
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
            for name, (log, message) in logs.items():
                with self.subTest(log=name):
                    (out / "logcat.txt").write_text(log)
                    result = report(out, "quest")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(message, result.stderr)
            for name, log in {"clean": ran + game.format(s=25, text="driver: done"),
                              "shell after quit": ran + game.format(s=25, text="driver: done") + vrapi.format(s=27, pid=5664)}.items():
                with self.subTest(log=name):
                    (out / "logcat.txt").write_text(log)
                    result = report(out, "quest")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("paths/stroke", result.stdout)

    def test_a_phases_stalls_are_kept_in_its_record(self):
        stall = {"ms": 412.5, "tags": ["build"], "main_ms": {"scripts": 400.1}, "compiled": [0, 2], "notes": [{"what": "wipe", "ms": 390.0}]}
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            result = bench(out, "desktop", 12.5, [{"label": "wipe/village", "p50": 13.89, "p99": 13.89, "late": 1, "draws": 100, "prims": 1000,
                             **({"stalls": [stall]} if i == 0 else {})} for i in range(3)])
            self.assertEqual(result.returncode, 0, result.stderr)
            phase = json.loads((out / "record.json").read_text())["phases"]["wipe/village"]
            self.assertEqual(phase["stalls"], [{"ms": 412.5, "notes": [{"what": "wipe", "ms": 390.0}], "compiled": [0, 2]}])

    def test_a_phase_is_pinned_only_when_every_second_held_one_step(self):
        cases = {"held": ([6, 6, 6], [True] * 3, True), "governed once": ([6, 6, 6], [True, True, False], False),
                 "re-pinned": ([6, 6, 14], [True] * 3, False), "unrecorded": ([6, 6, 6], [None] * 3, None)}
        for case, (steps, pins, pinned) in cases.items():
            with self.subTest(case=case), tempfile.TemporaryDirectory(dir=".") as folder:
                out = Path(folder)
                result = bench(out, "desktop", 12.5, [{"label": "camera", "p50": 13.89, "p99": 13.89, "late": 0, "draws": 100, "prims": 1000,
                                 "step": step, **({} if pin is None else {"pinned": pin})}
                                for step, pin in zip([6] + steps, [pins[0]] + pins)])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads((out / "record.json").read_text())["phases"]["camera"].get("pinned"), pinned)

    def test_only_a_marked_phase_past_the_build_budget_goes_unheld(self):
        """A phase over the line fails unless the scene marks its label past_budget and its garden is past the
        build budget: an unmarked feature on a dense garden is held, and a mark exempts no garden a player can build."""
        labels = {21: ("feature", 2.0), 22: ("feature", 2.0), 23: ("pricing", 2.0), 24: ("pricing", 2.0), 25: ("buildable", 0.5), 26: ("buildable", 0.5)}
        game = '17923700{s}.000  6423  6467 I godot   : {text}\n'
        vrapi = '17923700{s}.000  6423  6717 I VrApi   : FPS=72/72,Prd=40ms,App=15.00ms,GPU%=0.5\n'
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            (out / "logcat.txt").write_text(game.format(s=20, text="xr: session at 72.0 Hz") + "".join(vrapi.format(s=s) for s in labels)
                                            + game.format(s=27, text="driver: done"))
            result = bench(out, "quest", 11.111,
                           [{"label": labels.get(s, ("-", 0.0))[0], "fill": labels.get(s, ("-", 0.0))[1], "unix": 1792370000 + s,
                             "p50": 13.89, "p99": 13.89, "late": 0, "draws": 100, "prims": 1000} for s in range(20, 28)],
                           json.dumps([{"op": "label", "name": "pricing", "past_budget": True},
                                       {"op": "label", "name": "buildable", "past_budget": True},
                                       {"op": "label", "name": "feature"}]))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("over budget: feature, buildable", result.stdout)
            self.assertIn("past the build budget (2.00)", result.stdout)

    def test_pair_layer_pairs_each_phase_bench_lets_past_and_bench_judges_each_pair_as_its_phase(self):
        scene = [{"op": "label", "name": "sweep/arches"}, {"op": "wait", "seconds": 1},
                 {"op": "label", "name": "buildable", "past_budget": True}, {"op": "wait", "seconds": 1},
                 {"op": "label", "name": "feature"}, {"op": "wait", "seconds": 1}, {"op": "label", "name": "-"}]
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            (out / "scene.json").write_text(json.dumps(scene))
            paired = subprocess.run([sys.executable, str(SCRIPTS / "pair_layer.py"), str(out / "scene.json"), "masonry"],
                                    capture_output=True, text=True, check=True).stdout
            pairs = [s["name"] for s in json.loads(paired) if s["op"] == "label" and s["name"].startswith("pair/")]
            self.assertEqual(sorted({p.rsplit("/", 2)[0] for p in pairs}), ["pair/buildable", "pair/sweep/arches"])
            names = ["pair/sweep/arches/none/1", "pair/sweep/arches/1masonry/1", "pair/buildable/none/1", "pair/buildable/1masonry/1"]
            game = '17923700{s}.000  6423  6467 I godot   : {text}\n'
            vrapi = '17923700{s}.000  6423  6717 I VrApi   : FPS=72/72,Prd=40ms,App=15.00ms,GPU%=0.5\n'
            labels = {21 + 2 * i + k: name for i, name in enumerate(names) for k in (0, 1)}
            (out / "logcat.txt").write_text(game.format(s=20, text="xr: session at 72.0 Hz") + "".join(vrapi.format(s=s) for s in labels)
                                            + game.format(s=29, text="driver: done"))
            result = bench(out, "quest", 11.111,
                           [{"label": labels.get(s, "-"), "fill": 0.5, "unix": 1792370000 + s,
                             "p50": 13.89, "p99": 13.89, "late": 0, "draws": 100, "prims": 1000} for s in range(20, 30)], paired)
            self.assertIn("over budget: pair/buildable/none/1, pair/buildable/1masonry/1\n", result.stdout)

    def test_a_phase_keeps_the_charges_of_its_fullest_second(self):
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            result = bench(out, "desktop", 12.5, [{"label": "village", "p50": 13.89, "p99": 13.89, "late": 0, "draws": 100, "prims": 1000,
                             "fill": f, "charges": {"wall_m2": f}} for f in (0.5, 2.0, 1.0)])
            self.assertEqual(result.returncode, 0, result.stderr)
            phase = json.loads((out / "record.json").read_text())["phases"]["village"]
            self.assertEqual((phase["fill"], phase["charges_ms"]), (2.0, {"wall_m2": 2.0}))

    def test_a_phases_peak_memory_is_kept_in_its_record(self):
        with tempfile.TemporaryDirectory(dir=".") as folder:
            out = Path(folder)
            result = bench(out, "desktop", 12.5, [{"label": "figures", "p50": 13.89, "p99": 13.89, "late": 0, "draws": 100, "prims": 1000,
                             "mem_mb": {"textures": 100.0 + i, "buffers": 50.0 - i, "video": 300.0}} for i in range(3)])
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

    def test_a_governed_pair_is_refused(self):
        """The Frame tour gov-tip5, whose governor fell to the bottom step at r20/ground, against gov-main at steps 7 to
        10: from r20/ground on every phase read faster by its median alone, and r20/ground hid a second at half rate."""
        tour = Path(__file__).resolve().parent / "governed-tour"
        records = {}
        with tempfile.TemporaryDirectory(dir=".") as folder:
            for name in ["gov-main", "gov-tip5"]:
                out = Path(folder) / name
                out.mkdir()
                (out / "metrics.json").write_text((tour / f"{name}.json").read_text())
                (out / "stress.json").write_text("[]")
                result = report(out, "frame")
                self.assertEqual(result.returncode, 0, result.stderr)
                records[name] = json.loads((out / "record.json").read_text())
        self.assertEqual(records["gov-tip5"]["phases"]["r20/ground"]["worst"], {"late": 32, "p50": 27.52, "p99": 33.564})
        shared = [p for p in records["gov-tip5"]["phases"] if p in records["gov-main"]["phases"]]
        later = shared[shared.index("r20/ground"):]
        self.assertEqual(len(later), 48)

        def verdicts(control, candidate):
            with contextlib.redirect_stdout(io.StringIO()) as printed:
                trend.pair(control, candidate)
            rows = {line.split()[0]: line for line in printed.getvalue().splitlines()}
            return [rows[p].rsplit(maxsplit=1)[-1] for p in later], rows

        self.assertFalse(any("pinned" in row for row in records["gov-tip5"]["phases"].values()))
        pinned = lambda step: [{**r, "phases": {p: {**row, "step": step(row), "pinned": True}
                                                for p, row in r["phases"].items()}}
                               for r in (records["gov-main"], records["gov-tip5"])]
        self.assertEqual(verdicts(*pinned(lambda row: 0))[0].count("faster"), 45)
        said, rows = verdicts(*pinned(lambda row: row.get("step", 0)))
        self.assertEqual(said, ["refused"] * 48)
        said, rows = verdicts(records["gov-main"], records["gov-tip5"])
        self.assertEqual(said, ["refused"] * 48)
        self.assertIn(" 32 late p50  27.5 p99  33.6 refused", rows["r20/ground"])
        with tempfile.TemporaryDirectory(dir=".") as folder:
            paths = []
            for name in ("gov-main", "gov-tip5"):
                (Path(folder) / f"{name}.json").write_text(json.dumps(records[name]))
                paths.append(str(Path(folder) / f"{name}.json"))
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()) as said:
                self.assertEqual(trend.main(["--pair", *paths]), 1)
        step = lambda name: records[name]["phases"]["r20/ground"]["step"]
        self.assertIn(f"refused r20/ground, not pinned at one step: control unrecorded pin at step {step('gov-main')}, "
                      f"candidate unrecorded pin at step {step('gov-tip5')}", said.getvalue())

    def test_a_comparison_holds_only_phases_pinned_at_one_step(self):
        """A governed stress run read camera phases at 6.3 ms where, pinned at step 6, the same change read 12.55 to
        13.54 ms against 13.14 to 13.73 before: the governor's figure, not the change's."""
        seen = {"p50": 13.0, "draws": 100, "prims": 1000}
        pinned = lambda ms, step=6: {**seen, "gpu_ms": ms, "step": step, "pinned": True}
        governed = {**seen, "gpu_ms": 6.3, "step": 6, "pinned": False}
        cases = {
            "pinned": (pinned(13.14), pinned(12.55), None),
            "governed": (pinned(13.14), governed, "candidate governed at step 6"),
            "unrecorded": ({**seen, "gpu_ms": 13.14, "step": 6}, pinned(12.55), "control unrecorded pin at step 6"),
            "steps differ": (pinned(13.14), pinned(12.55, 7), "control at step 6, candidate at step 7"),
        }
        for case, (control, candidate, why) in cases.items():
            with self.subTest(case=case):
                with contextlib.redirect_stdout(io.StringIO()):
                    _, refused = trend.pair({"phases": {"camera": control}}, {"phases": {"camera": candidate}})
                self.assertEqual(refused, [("camera", why)] if why else [])
                with tempfile.TemporaryDirectory(dir=".") as folder:
                    record = Path(folder) / "record.json"
                    record.write_text(json.dumps({"budget_gpu_ms": 11.111, "phases": {
                        "pair/camera/2x/0": candidate, "pair/camera/none/0": control,
                        "pair/camera/none/1": control, "pair/camera/2x/1": candidate}}))
                    for args in ([], ["--price", "x", "x", "2", "pair/camera/2x/0=pair/camera/none/0"]):
                        result = subprocess.run([sys.executable, str(SCRIPTS / "paired.py"), str(record), *args],
                                                capture_output=True, text=True)
                        self.assertEqual(result.returncode != 0, why is not None, result.stderr)
                        if why:
                            self.assertIn("not pinned at one step", result.stderr)
                            self.assertIn("governed" if case == "governed" else "step", result.stderr)


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
