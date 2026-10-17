import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

game = Path(__file__).parents[1] / 'game'


class AndroidExportLeavesAdbAlone(unittest.TestCase):
    def test_editor_never_runs_adb(self):
        # Godot's Android exporter polls `adb devices` and runs `adb kill-server` at exit when an Android preset is
        # runnable, dropping every wireless session on the host's shared adb server.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            project = root / 'project'
            project.mkdir()
            for name in ['project.godot', 'export_presets.cfg']:
                shutil.copy(game / name, project)
            adb = root / 'sdk/platform-tools/adb'
            adb.parent.mkdir(parents=True)
            log = root / 'adb.log'
            adb.write_text(f'#!/bin/sh\necho "$*" >> {log}\n')
            adb.chmod(0o755)
            env = dict(os.environ, ANDROID_HOME=str(root / 'sdk'), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_DATA_HOME=str(root / 'data'), XDG_CACHE_HOME=str(root / 'cache'))
            run = subprocess.run(['godot4', '--headless', '--editor', '--path', str(project), '--quit-after', '200'],
                                 env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout[-4000:] + run.stderr[-4000:])
            self.assertFalse(log.exists(), log.read_text() if log.exists() else '')


if __name__ == '__main__':
    unittest.main()
