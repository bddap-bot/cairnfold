import json
from pathlib import Path
import unittest


class CoopChoreography(unittest.TestCase):
    def test_players_leave_on_an_event_not_a_timer(self):
        # A timer only holds while every other player keeps pace, which a busy machine does not promise.
        for script in sorted((Path(__file__).resolve().parents[1] / "demo").glob("coop-*.json")):
            ops = [step["op"] for step in json.loads(script.read_text())]
            for before, op in zip(ops, ops[1:]):
                if op in ("visit", "quit"):
                    with self.subTest(script=script.name, op=op):
                        self.assertNotEqual(before, "wait")


class CoopPlayers(unittest.TestCase):
    @staticmethod
    def harness():
        import importlib.util
        path = Path(__file__).resolve().parents[1] / "scripts/coop.py"
        spec = importlib.util.spec_from_file_location("coop", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_every_peer_waits_for_every_view_before_leaving(self):
        for count in (2, 3, 4, 8):
            scripts = self.harness().scripts(count)
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
        for count in (2, 4, 8):
            for name, steps in self.harness().scripts(count).items():
                for step in steps:
                    if step["op"] == "until":
                        with self.subTest(count=count, name=name, step=step):
                            self.assertNotIn("seconds", step)
