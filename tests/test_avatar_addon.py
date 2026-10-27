import hashlib
import json
from pathlib import Path
import unittest


class AvatarAddonPin(unittest.TestCase):
    def test_vendored_files_match_pin(self):
        root = Path(__file__).resolve().parents[1]
        addon = root / "game/addons/avatar_workshop"
        pin = json.loads((addon / "source.json").read_text())
        self.assertRegex(pin["commit"], r"^[0-9a-f]{40}$")
        self.assertEqual(pin["license"], "MIT OR Apache-2.0")
        for name, record in pin["files"].items():
            with self.subTest(file=name):
                self.assertEqual(hashlib.sha256((addon / name).read_bytes()).hexdigest(), record["sha256"])
        self.assertEqual(set(pin["files"]), {"skin_bindings.gd", "skin_bindings.gd.uid", "spring_native.gd", "spring_native.gd.uid", "expression_mixer.gd", "spring_definition.gd", "spring_runtime.gd", "spring_definition.gd.uid", "spring_runtime.gd.uid", "skeleton_bone.gd", "skeleton_bone.gd.uid", "LICENSE-MIT", "LICENSE-APACHE", "LICENSE-godot-vrm"})
        notices = (root / "LICENSE-avatar-workshop").read_text()
        for name in ("LICENSE-MIT", "LICENSE-APACHE", "LICENSE-godot-vrm"):
            self.assertIn((addon / name).read_text(), notices)
