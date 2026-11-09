from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import coop  # noqa: E402


class CoopPlayers(unittest.TestCase):
    def test_every_peer_waits_for_every_view_before_leaving(self):
        for count in (2, 3, 4, 8):
            scripts = coop.scripts(count)
            expected = {f"{name}-final" for name in scripts}
            self.assertEqual(len(scripts), count)
            for name, steps in scripts.items():
                with self.subTest(count=count, name=name):
                    own = next(i for i, s in enumerate(steps) if s.get("name") == f"{name}-final")
                    self.assertEqual(set(steps[own + 1]["digests"]), expected)
                    for before, step in zip(steps, steps[1:]):
                        if step["op"] in ("visit", "quit"):
                            self.assertNotEqual(before["op"], "wait")
                    samples = [s for s in steps if s["op"] == "network_sample"]
                    self.assertEqual(len(samples), 2 if name in ("host", "join") and count > 2 else 1)

    def test_waits_have_no_time_limit(self):
        # A late peer starts, imports and builds after the others, as fast as the machine allows.
        runs = {count: coop.scripts(count) for count in (2, 4, 8)}
        runs["reshape"] = coop.reshape_scripts()
        for run, scripts in runs.items():
            for name, steps in scripts.items():
                for step in steps:
                    if step["op"] == "until":
                        with self.subTest(run=run, name=name, step=step):
                            self.assertNotIn("seconds", step)

    def test_a_player_hung_at_exit_leaves_its_threads_and_dies(self):
        hung = subprocess.Popen([sys.executable, "-c", "import time; print('ready', flush=True); time.sleep(600)"],
                                stdout=subprocess.PIPE, preexec_fn=coop.traceable)
        hung.stdout.readline()
        with tempfile.TemporaryDirectory() as folder:
            stack = Path(folder) / "exit-stack.txt"
            coop.end_hung(hung, stack)
            self.assertIn("Thread 1", stack.read_text())
        self.assertIsNotNone(hung.returncode)
        hung.stdout.close()
