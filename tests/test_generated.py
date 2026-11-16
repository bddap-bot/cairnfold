from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def run(*args, cwd=ROOT):
    done = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=600)
    out = done.stdout + done.stderr
    if done.returncode or "SCRIPT ERROR" in out:
        raise AssertionError(f"{' '.join(map(str, args))} exited {done.returncode}:\n{out[-4000:]}")
    return out


def godot(script, *args):
    return run("godot4", "--headless", "--path", ROOT / "game", "--script", ROOT / script, "--", *args)


class Generated(unittest.TestCase):
    def assertSameFiles(self, made, committed, names):
        self.assertEqual(sorted(p.name for p in Path(made).iterdir()), sorted(names))
        for name in names:
            with self.subTest(file=name):
                self.assertEqual((Path(made) / name).read_bytes(), (committed / name).read_bytes(), f"{name} is not what its script writes")

    def test_avatars_writes_the_built_in_avatars(self):
        with tempfile.TemporaryDirectory() as out:
            godot("scripts/avatars.gd", out)
            self.assertSameFiles(out, ROOT / "game/avatars", [p.name for p in (ROOT / "game/avatars").glob("*.vrm")])

    def test_mocap_writes_the_wave_and_the_poses(self):
        with tempfile.TemporaryDirectory() as out:
            godot("scripts/mocap.gd", out)
            self.assertSameFiles(out, ROOT / "game/animations", ["wave.tres", "poses.json"])



if __name__ == "__main__":
    unittest.main()
