import os
from pathlib import Path
import shlex
import struct
import subprocess
import tempfile
import textwrap
import unittest
import zipfile

script = Path(__file__).resolve().parents[1] / 'scripts/quest-install.sh'

# A Quest as adb shows it: /sdcard is a folder on the host. An install of an older version is refused, an uninstall
# erases that package's external files folder, a push makes no folder, and only the game's start makes the folders it
# uses.
FAKE_ADB = textwrap.dedent('''\
    #!/usr/bin/env python3
    import os, shutil, subprocess, sys
    root = os.environ['FAKE_QUEST']
    files_of = lambda pkg: root + '/sdcard/Android/data/' + pkg + '/files'
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
        shutil.rmtree(files_of(args[1]), ignore_errors=True)
    elif args[0] == 'pull':
        if fail == 'pull':
            sys.exit(1)
        shutil.copytree(on_device(args[1]), args[2], dirs_exist_ok=True)
    elif args[0] == 'push':
        if fail == 'push':
            sys.exit(1)
        shutil.copy(args[1], on_device(args[2]))
    elif args[0] == 'shell' and args[1:3] == ['am', 'start']:
        files = files_of(args[4].split('/')[0])
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


def apk(path, package, quest=True):
    """A zip holding only an AndroidManifest.xml in Android's binary XML: <manifest package=...>, whose string pool
    names the Quest's VR category when quest."""
    strings = ['manifest', 'package', package] + ['com.oculus.intent.category.VR'] * quest
    offsets, data = [], b''
    for t in strings:
        offsets.append(len(data))
        data += struct.pack('<H', len(t)) + t.encode('utf-16le') + b'\0\0'
    data += b'\0' * (-len(data) % 4)
    start = 28 + 4 * len(strings)
    pool = struct.pack('<HHIIIIII', 0x0001, 28, start + len(data), len(strings), 0, 0, start, 0)
    pool += b''.join(struct.pack('<I', o) for o in offsets) + data
    attr = struct.pack('<IIIHBBI', 0xFFFFFFFF, 1, 2, 8, 0, 0x03, 2)
    tag = struct.pack('<IIIIHHHHHH', 0, 0xFFFFFFFF, 0xFFFFFFFF, 0, 20, 20, 1, 0, 0, 0) + attr
    tag = struct.pack('<HHI', 0x0102, 16, 8 + len(tag)) + tag
    body = pool + tag
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr('AndroidManifest.xml', struct.pack('<HHI', 0x0003, 8, 8 + len(body)) + body)
    return path


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

    def install(self, package='io.github.bddapbot.nestcombe', quest=True, **env):
        path = apk(self.root / 'old.apk', package, quest)
        return subprocess.run([str(script), str(path)], env=dict(self.env, **env), capture_output=True, text=True)

    def test_a_build_installed_as_another_package_never_touches_the_game(self):
        run = self.install(package='io.github.bddapbot.nestbisect')
        self.assertEqual(run.returncode, 0, run.stderr)
        log = (self.quest / 'adb.log').read_text()
        self.assertIn('uninstall io.github.bddapbot.nestbisect', log)
        self.assertNotIn('nestcombe', log)
        self.assertEqual((self.files / 'garden.save').read_bytes(), b'the players\x00 garden')

    def test_an_apk_without_the_vr_category_is_refused(self):
        run = self.install(quest=False)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('no Quest APK', run.stderr)
        self.assertFalse((self.quest / 'adb.log').exists())

    def test_the_package_is_read_from_the_apk(self):
        run = subprocess.run([str(script), '--package', str(apk(self.root / 'x.apk', 'a.b.c'))], capture_output=True, text=True)
        self.assertEqual(run.stdout.strip(), 'a.b.c', run.stderr)

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

    def test_the_restore_a_renamed_build_names_acts_on_that_build(self):
        package = 'io.github.bddapbot.nestbisect'
        files = self.quest / f'sdcard/Android/data/{package}/files'
        files.mkdir(parents=True)
        (files / 'garden.save').write_bytes(b'the bisect garden')
        run = self.install(package=package, FAKE_FAIL='push')
        self.assertNotEqual(run.returncode, 0)
        suggested = shlex.split(run.stderr.split('restore them with: ')[1])
        (self.quest / 'adb.log').unlink()
        run = subprocess.run(suggested, env=self.env, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        log = (self.quest / 'adb.log').read_text()
        self.assertIn(package, log)
        self.assertNotIn('nestcombe', log)
        self.assertEqual((files / 'garden.save').read_bytes(), b'the bisect garden')


if __name__ == '__main__':
    unittest.main()
