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
