import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

script = Path(__file__).resolve().parents[1] / 'scripts/quest-install.sh'

# A Quest as adb shows it: /sdcard is a folder on the host. An install of an older version is refused, an uninstall
# erases the app's external files folder, a push makes no folder, and only the game's start makes the folders it uses.
FAKE_ADB = textwrap.dedent('''\
    #!/usr/bin/env python3
    import os, shutil, subprocess, sys
    root = os.environ['FAKE_QUEST']
    files = root + '/sdcard/Android/data/io.github.bddapbot.nestcombe/files'
    on_device = lambda path: root + path
    args = sys.argv[1:]
    fail = os.environ.get('FAKE_FAIL', '')
    with open(root + '/adb.log', 'a') as log:
        log.write(' '.join(args) + '\\n')
    if args[0] == 'install':
        if '-r' in args and os.path.exists(root + '/installed'):
            print('Failure [INSTALL_FAILED_VERSION_DOWNGRADE]')
            sys.exit(1)
        open(root + '/installed', 'w').close()
    elif args[0] == 'uninstall':
        os.remove(root + '/installed')
        shutil.rmtree(files, ignore_errors=True)
    elif args[0] == 'pull':
        if fail == 'pull':
            sys.exit(1)
        shutil.copytree(on_device(args[1]), args[2], dirs_exist_ok=True)
    elif args[0] == 'push':
        if fail == 'push':
            sys.exit(1)
        shutil.copy(args[1], on_device(args[2]))
    elif args[0] == 'shell' and args[1:3] == ['am', 'start']:
        os.makedirs(files + '/avatars', exist_ok=True)
        with open(files + '/garden.save', 'w') as f:
            f.write('a fresh garden')
    elif args[0] == 'shell' and args[1:3] == ['am', 'force-stop']:
        pass
    elif args[0] == 'shell':
        sys.exit(subprocess.run(['sh', '-c', ' '.join(args[1:]).replace('/sdcard', root + '/sdcard')]).returncode)
    else:
        sys.exit('fake adb: ' + ' '.join(args))
    ''')


class QuestInstallKeepsSaves(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        bin = self.root / 'bin'
        bin.mkdir()
        (bin / 'adb').write_text(FAKE_ADB)
        (bin / 'adb').chmod(0o755)
        self.quest = self.root / 'quest'
        self.files = self.quest / 'sdcard/Android/data/io.github.bddapbot.nestcombe/files'
        (self.files / 'avatars').mkdir(parents=True)
        (self.files / 'bench').mkdir()
        (self.files / 'garden.save').write_bytes(b'the players\x00 garden')
        (self.files / 'avatars/Fairy.vrm').write_bytes(b'vrm')
        (self.files / 'bench/metrics.json').write_text('{}')
        (self.quest / 'installed').touch()
        self.saves = self.root / 'saves'
        self.env = dict(os.environ, PATH=f'{bin}:{os.environ["PATH"]}', FAKE_QUEST=str(self.quest),
                        NESTCOMBE_QUEST_SAVES=str(self.saves))

    def tearDown(self):
        self.temporary.cleanup()

    def install(self, **env):
        return subprocess.run([str(script), 'old.apk'], env=dict(self.env, **env), capture_output=True, text=True)

    def test_an_install_that_uninstalls_puts_the_saves_back(self):
        run = self.install()
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn('uninstall', (self.quest / 'adb.log').read_text())
        self.assertEqual((self.files / 'garden.save').read_bytes(), b'the players\x00 garden')
        self.assertEqual((self.files / 'avatars/Fairy.vrm').read_bytes(), b'vrm')
        self.assertFalse((self.files / 'bench').exists())

    def test_saves_that_cannot_be_copied_never_block_the_install(self):
        run = self.install(FAKE_FAIL='pull')
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn('could not be copied off', run.stderr)
        self.assertTrue((self.quest / 'installed').exists())

    def test_a_restore_that_does_not_land_fails_loudly(self):
        run = self.install(FAKE_FAIL='push')
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('--restore', run.stderr)
        copy = next(self.saves.iterdir())
        self.assertEqual((copy / 'garden.save').read_bytes(), b'the players\x00 garden')


if __name__ == '__main__':
    unittest.main()
