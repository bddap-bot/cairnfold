import os
from pathlib import Path
import shlex
import shutil
import struct
import subprocess
import tempfile
import textwrap
import unittest
import zipfile

script = Path(__file__).resolve().parents[1] / 'scripts/quest-install.sh'

# A Quest as adb shows it: /sdcard is a folder on the host. An install of an older version is refused, an uninstall
# erases that package's external files folder, and a push makes the folders its files need and no empty one, closed to
# the game as a Quest 3's shell makes them. The shell runs on the host, with no `am`: a restore that starts the game
# fails. FAKE_FAIL names the adb call that fails, or with `corrupt` a push that lands other bytes; with FAKE_REFUSE=N
# the first N pushes are refused as a freshly installed app's folder refuses them.
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
        refused = root + '/refused-pushes'
        if fail == 'push' or (os.path.getsize(refused) if os.path.exists(refused) else 0) < int(os.environ.get('FAKE_REFUSE', 0)):
            with open(refused, 'a') as f:
                f.write('x')
            sys.exit('adb: error: failed to copy: remote secure_mkdirs failed: Operation not permitted')
        source, target = args[1], on_device(args[2])
        if target.endswith('/'):
            target += os.path.basename(source)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if os.path.isdir(source):
            for at, folders, names in os.walk(source):
                for name in names:
                    to = os.path.join(target, os.path.relpath(os.path.join(at, name), source))
                    os.makedirs(os.path.dirname(to), exist_ok=True)
                    shutil.copy(os.path.join(at, name), to)
            for at, folders, names in os.walk(target):
                os.chmod(at, 0o2770)
                for name in names:
                    os.chmod(os.path.join(at, name), 0o640)
        else:
            shutil.copy(source, target)
            os.chmod(target, 0o640)
        if fail == 'corrupt':
            for at, folders, names in os.walk(target) if os.path.isdir(target) else [('', [], [target])]:
                for name in names:
                    with open(os.path.join(at, name), 'ab') as f:
                        f.write(b'!')
    elif args[0] == 'shell' and (fail == 'shell' or fail == 'shell-after-uninstall' and 'uninstall' in open(root + '/adb.log').read()):
        sys.exit('error: closed')
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
        (bin / 'sleep').write_text(f'#!/bin/sh\necho >> {self.root}/sleeps\n')
        (bin / 'sleep').chmod(0o755)
        self.quest = self.root / 'quest'
        self.files = self.quest / 'sdcard/Android/data/io.github.bddapbot.cairnfold/files'
        (self.files / 'avatars').mkdir(parents=True)
        self.game_made = {self.files / 'avatars'}
        (self.files / 'bench').mkdir()
        (self.files / 'garden.save').write_bytes(b'the players\x00 garden')
        (self.files / 'garden.save.bad').write_bytes(b'an unreadable garden')
        (self.files / 'avatars/Wren.vrm').write_bytes(b'vrm')
        (self.files / 'bench/metrics.json').write_text('{}')
        (self.files / 'check/bench').mkdir(parents=True)
        (self.files / 'check/bench/drive.sh').write_text('true')
        (self.files / 'launch.args').write_text('--bench')
        (self.quest / 'installed').touch()
        self.saves = self.root / 'saves'
        self.env = dict(os.environ, PATH=f'{bin}:{os.environ["PATH"]}', FAKE_QUEST=str(self.quest),
                        CAIRNFOLD_QUEST_SAVES=str(self.saves))

    def tearDown(self):
        self.temporary.cleanup()

    def install(self, package='io.github.bddapbot.cairnfold', quest=True, **env):
        path = apk(self.root / 'old.apk', package, quest)
        return subprocess.run([str(script), str(path)], env=dict(self.env, **env), capture_output=True, text=True)

    def test_a_build_installed_as_another_package_never_touches_the_game(self):
        run = self.install(package='io.github.bddapbot.nestbisect')
        self.assertEqual(run.returncode, 0, run.stderr)
        log = (self.quest / 'adb.log').read_text()
        self.assertIn('uninstall io.github.bddapbot.nestbisect', log)
        self.assertNotIn('cairnfold', log)
        self.assertEqual((self.files / 'garden.save').read_bytes(), b'the players\x00 garden')

    def test_an_apk_without_the_vr_category_is_refused(self):
        run = self.install(quest=False)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('no Quest APK', run.stderr)
        self.assertFalse((self.quest / 'adb.log').exists())

    def test_the_package_is_read_from_the_apk(self):
        run = subprocess.run([str(script), '--package', str(apk(self.root / 'x.apk', 'a.b.c'))], capture_output=True, text=True)
        self.assertEqual(run.stdout.strip(), 'a.b.c', run.stderr)

    def start_game(self):
        """What the game's start does, as a Quest 3 lets it: it may read a file or write in a folder it made, or one the
        shell opened to all; the start makes its files folder its own. It reads every save, replaces the garden, adds
        to each folder and records a session where record-sessions asks it to."""
        def opened(path, bit):
            return path in self.game_made or path.stat().st_mode & bit
        self.files.mkdir(parents=True, exist_ok=True)
        self.game_made.add(self.files)
        for path in self.files.rglob('*'):
            if path.is_file():
                self.assertTrue(opened(path, 0o004), f'the game cannot read {path}')
            else:
                self.assertTrue(opened(path, 0o002), f'the game cannot write into {path}')
                (path / 'new').write_bytes(b'')
        (self.files / 'garden.save.new').write_bytes(b'a garden')
        (self.files / 'garden.save.new').rename(self.files / 'garden.save')
        if (self.files / 'record-sessions').exists():
            if not (self.files / 'sessions').exists():
                (self.files / 'sessions').mkdir()
            (self.files / 'sessions/9-9-9-0000.jsonl').write_text('{}')

    def test_an_install_that_uninstalls_puts_back_every_shape_of_saves(self):
        sessions = {'sessions/1-2-3-0000.jsonl': b'{}', 'sessions/1-2-3-0001.jsonl': b'{"part":2}'}
        shapes = {
            'sessions only': sessions,
            'record-sessions': {'record-sessions': b'', **sessions},
            'empty': {},
            'full': {'garden.save': b'the players\x00 garden', 'garden.save.bad': b'an unreadable garden',
                     'avatars/Wren.vrm': b'vrm', "avatars/a folder's/Moth.vrm": b'moth', 'record-sessions': b'', **sessions},
        }
        for shape, saves in shapes.items():
            with self.subTest(shape=shape):
                self.tearDown()
                self.setUp()
                for p in list(self.files.iterdir()):
                    if p.name not in ('bench', 'check', 'launch.args'):
                        shutil.rmtree(p) if p.is_dir() else p.unlink()
                (self.files / 'avatars/empty').mkdir(parents=True)
                for rel, data in saves.items():
                    (self.files / rel).parent.mkdir(parents=True, exist_ok=True)
                    self.game_made.add((self.files / rel).parent)
                    (self.files / rel).write_bytes(data)
                run = self.install()
                self.assertEqual(run.returncode, 0, run.stderr)
                log = (self.quest / 'adb.log').read_text()
                self.assertIn('uninstall', log)
                self.assertNotIn('am start', log)
                on_device = {str(p.relative_to(self.files)): p.read_bytes() for p in self.files.rglob('*') if p.is_file()}
                self.assertEqual(on_device, saves)
                copy = next(self.saves.iterdir())
                self.assertEqual({str(p.relative_to(copy)): p.read_bytes() for p in copy.rglob('*') if p.is_file()}, saves)
                self.game_made = set()
                self.start_game()

    def test_a_restore_of_a_copy_holding_shell_pushed_folders_puts_back_only_the_saves(self):
        copy = self.root / 'copy'
        (copy / 'check/bench').mkdir(parents=True)
        (copy / 'check/bench/drive.sh').write_text('true')
        (copy / 'garden.save').write_bytes(b'kept')
        subprocess.run(['adb', 'uninstall', 'io.github.bddapbot.cairnfold'], env=self.env, check=True)
        run = subprocess.run([str(script), '--restore', str(copy)], env=self.env, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual((self.files / 'garden.save').read_bytes(), b'kept')
        self.assertFalse((self.files / 'check').exists())

    def test_a_restore_onto_saves_that_have_grown_puts_the_copy_back(self):
        copy = self.root / 'copy'
        (copy / 'avatars').mkdir(parents=True)
        (copy / 'avatars/Wren.vrm').write_bytes(b'an older wren')
        (self.files / 'avatars/Moth.vrm').write_bytes(b'a newer moth')
        run = subprocess.run([str(script), '--restore', str(copy)], env=self.env, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual((self.files / 'avatars/Wren.vrm').read_bytes(), b'an older wren')
        self.assertEqual((self.files / 'avatars/Moth.vrm').read_bytes(), b'a newer moth')

    def test_a_restore_of_a_copy_that_is_not_there_fails(self):
        run = subprocess.run([str(script), '--restore', str(self.root / 'nowhere')], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('no copy of saves', run.stderr)

    def test_a_copy_shares_files_identical_to_an_earlier_one(self):
        earlier = self.saves / '20000101T000000Z/garden.save'
        earlier.parent.mkdir(parents=True)
        earlier.write_bytes(b'the players\x00 garden')
        os.utime(earlier, (0, 0))
        self.assertEqual(self.install().returncode, 0)
        copy = next(d for d in self.saves.iterdir() if d != earlier.parent)
        self.assertEqual((copy / 'garden.save').stat().st_ino, earlier.stat().st_ino)

    def test_saves_that_cannot_be_copied_stop_the_run_before_the_uninstall(self):
        for fail in 'shell', 'pull':
            with self.subTest(fail=fail):
                run = self.install(FAKE_FAIL=fail)
                self.assertNotEqual(run.returncode, 0)
                self.assertIn('stopping', run.stderr)
                self.assertNotIn('uninstall', (self.quest / 'adb.log').read_text())
                self.assertEqual((self.files / 'garden.save').read_bytes(), b'the players\x00 garden')
                (self.quest / 'adb.log').unlink()

    def test_a_backup_that_cannot_read_the_device_fails(self):
        run = subprocess.run([str(script), '--backup', str(self.root / 'copy')], env=dict(self.env, FAKE_FAIL='shell'),
                             capture_output=True, text=True)
        self.assertNotEqual(run.returncode, 0)

    def test_pushes_the_reinstalled_folder_refuses_at_first_are_tried_again(self):
        (self.files / 'record-sessions').write_text('')
        (self.files / 'sessions').mkdir()
        (self.files / 'sessions/1-2-3.jsonl').write_text('{}')
        run = self.install(FAKE_REFUSE='5')
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual((self.quest / 'refused-pushes').read_text(), 'xxxxx')
        self.assertEqual((self.files / 'sessions/1-2-3.jsonl').read_text(), '{}')

    def test_a_restore_that_does_not_land_fails_loudly(self):
        for fail in 'push', 'corrupt':
            with self.subTest(fail=fail):
                run = self.install(FAKE_FAIL=fail)
                self.assertNotEqual(run.returncode, 0)
                self.assertIn('--restore', run.stderr)
                copy = next(self.saves.iterdir())
                self.assertEqual((copy / 'garden.save').read_bytes(), b'the players\x00 garden')
                self.tearDown()
                self.setUp()

    def test_an_adb_failure_during_the_restore_names_the_copy_to_restore(self):
        run = self.install(FAKE_FAIL='shell-after-uninstall')
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('--restore', run.stderr)

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
        self.assertNotIn('cairnfold', log)
        self.assertEqual((files / 'garden.save').read_bytes(), b'the bisect garden')


if __name__ == '__main__':
    unittest.main()
