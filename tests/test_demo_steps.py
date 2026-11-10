import json
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import coop  # noqa: E402

# Read off the scene file by scripts/past_budget.py, not by Driver.
OUTSIDE = {"label": {"past_budget"}}
# Driver._run reads op and background; scripts/bench.sh sums every step's seconds into the run's time limit.
EVERY = {"op", "background", "seconds"}
HANDS = ("left", "right")
TOOLS = re.search(r"enum Tool \{([^}]*)\}", (ROOT / "game/src/hand.gd").read_text()).group(1).replace(" ", "").lower().split(",")


def functions(path):
    out = {}
    for m in re.finditer(r"^(?:static )?func (\w+)\(([^)]*)\)[^\n]*:\n((?:\t[^\n]*\n|\n)*)", path.read_text(), re.M):
        out[m.group(1)] = ([p.split(":")[0].split("=")[0].strip() for p in m.group(2).split(",") if p.strip()], m.group(3))
    return out


CLASSES = {"Driver": functions(ROOT / "game/src/driver.gd"), "Lessons": functions(ROOT / "game/src/lessons.gd")}
DRIVER = CLASSES["Driver"]


def arguments(text):
    out, depth, cur = [], 0, ""
    for ch in text:
        if ch in ")]}" and depth == 0:
            break
        depth += (ch in "([{") - (ch in ")]}")
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    return out + [cur.strip()]


def reads(owner, name, param, seen):
    if (owner, name, param) in seen:
        return set()
    seen.add((owner, name, param))
    body = CLASSES[owner][name][1]
    v = re.escape(param)
    keys = set(re.findall(rf"\b{v}\.(\w+)\b(?!\()", body)) | set(re.findall(rf"\b{v}(?:\.(?:get|has)\(|\[)\"(\w+)\"", body))
    # A key named at run time: any string the function spells may be one.
    if re.search(rf"\b{v}(?:\[(?!\")|\.(?:get|has)\((?!\"))", body):
        keys |= set(re.findall(r"\"(\w+)\"", body))
    for m in re.finditer(r"(?<![\w.])(?:(\w+)\.)?(\w+)\(", body):
        args = arguments(body[m.end():])
        if param not in args:
            continue
        callee = m.group(1) or owner
        if callee not in CLASSES or m.group(2) not in CLASSES[callee]:
            raise AssertionError(f"{owner}.{name} hands its step to {m.group(0)}, which this check does not read")
        keys |= reads(callee, m.group(2), CLASSES[callee][m.group(2)][0][args.index(param)], seen)
    return keys


KEYS = {}


def faults(step):
    """What in `step` Driver would not play: a misspelt op or key, or one Driver no longer reads, would otherwise
    play as a step that silently does less."""
    op = step["op"]
    params = DRIVER.get("_" + op, ([], ""))[0]
    if len(params) != 1:
        return [f"Driver plays no {op}"]
    if op not in KEYS:
        KEYS[op] = reads("Driver", "_" + op, params[0], set()) | OUTSIDE.get(op, set()) | EVERY
    out = [f"{op} reads no {k}" for k in sorted(set(step) - KEYS[op])]
    hands = {**step.get("tools", {}), **({step["hand"]: None} if "hand" in step else {})}
    out += [f"{op} names hand {h}" for h in hands if h not in HANDS]
    tools = list(step.get("tools", {}).values()) + ([step["tool"]] if "tool" in step else [])
    return out + [f"{op} names tool {t}" for t in tools if t not in TOOLS]


def nested(steps):
    for step in steps:
        yield step
        if step["op"] == "sized":
            yield from nested(step["build"])
            yield from ({"op": "view", **v} for v in step["views"])


def scripts():
    for path in sorted((ROOT / "demo").glob("*.json")):
        yield path.name, json.loads(path.read_text())
    for mode, made in {"coop": coop.scripts(4), "spawn": coop.spawn_scripts(), "reshape": coop.reshape_scripts()}.items():
        for name, steps in made.items():
            yield f"coop.py {mode} {name}", steps


class DemoSteps(unittest.TestCase):
    def test_driver_plays_every_step_whole(self):
        count = 0
        for where, steps in scripts():
            for step in nested(steps):
                count += 1
                self.assertEqual(faults(step), [], f"{where}: {step}")
        self.assertGreater(count, 1000, "the scripts are found")

    def test_faults_found(self):
        self.assertEqual(faults({"op": "wall", "points": [], "seconds": 1, "hand": "left"}), [], "a key read through a helper counts")
        self.assertEqual(faults({"op": "gesture", "length": 1, "keys": [], "press": [], "tools": {"right": "walls"}}), [], "a key Lessons reads counts")
        self.assertEqual(faults({"op": "wall", "secnds": 1}), ["wall reads no secnds"])
        self.assertEqual(faults({"op": "wall", "pillars": 1}), ["wall reads no pillars"], "a string the op spells is no key")
        self.assertEqual(faults({"op": "wall", "tool": "walls"}), ["wall reads no tool"], "another object's field is no key")
        self.assertEqual(faults({"op": "gesture", "duplicate": 1, "length": 1}), ["gesture reads no duplicate"], "a method is no key")
        self.assertEqual(faults({"op": "wal"}), ["Driver plays no wal"])
        self.assertEqual(faults({"op": "drawing"}), ["Driver plays no drawing"])
        self.assertEqual(faults({"op": "pick", "hand": "lft", "tool": "wals"}), ["pick names hand lft", "pick names tool wals"])
        self.assertEqual(faults({"op": "gesture", "tools": {"lft": "walls", "right": "wals"}}), ["gesture names hand lft", "gesture names tool wals"])


if __name__ == "__main__":
    unittest.main()
