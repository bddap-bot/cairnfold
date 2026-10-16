import io
import importlib.util
from pathlib import Path
import tarfile
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('notices', Path(__file__).parents[1] / 'scripts/notices.py')
notices = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notices)


class PackageNotices(unittest.TestCase):
    def test_upstream_text_is_preserved_and_ndk_bumps_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source.tar.gz'
            license_text = b'Copyright upstream\r\nFull license text.\r\n'
            with tarfile.open(source, 'w:gz') as archive:
                for name, data in {
                    'release/thirdparty/component/LICENSE': license_text,
                    'release/platform/config.gradle': b"ndkVersion : '28.1.13356709'",
                }.items():
                    member = tarfile.TarInfo(name)
                    member.size = len(data)
                    archive.addfile(member, io.BytesIO(data))
            notices.extract(source, root / 'good', '28.1.13356709')
            self.assertEqual((root / 'good/thirdparty/component/LICENSE').read_bytes(), license_text)
            with self.assertRaisesRegex(AssertionError, 'update Android NDK'):
                notices.extract(source, root / 'stale', 'old-version')

    def test_finished_archives_reject_missing_and_changed_text(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            expected = root / 'expected'
            files = ['LICENSE-MIT', 'LICENSE-APACHE', 'godot/COPYRIGHT.txt',
                     'godot/LICENSE.txt', 'Cinzel-OFL.txt',
                     'openxr-vendors/meta/LICENSE-SDK', 'android/DEPENDENCIES.txt']
            for name in files:
                path = expected / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('Original upstream text: ' + name)
            for suffix in ('.tar.gz', '.zip', '.apk'):
                for broken in (None, *files):
                    for truncated in (False, True):
                        package = root / ('package' + suffix)
                        prefix = 'assets/notices/' if suffix == '.apk' else 'nestcombe/notices/'
                        if suffix != '.tar.gz':
                            with zipfile.ZipFile(package, 'w') as archive:
                                for name in files:
                                    if name != broken:
                                        archive.write(expected / name, prefix + name)
                                    elif truncated:
                                        archive.writestr(prefix + name, 'truncated')
                        else:
                            stage = root / 'stage'
                            stage.mkdir(exist_ok=True)
                            with tarfile.open(package, 'w:gz') as archive:
                                for name in files:
                                    if name != broken:
                                        archive.add(expected / name, prefix + name)
                                    elif truncated:
                                        (stage / 'bad').write_text('truncated')
                                        archive.add(stage / 'bad', prefix + name)
                        if broken:
                            with self.assertRaises((KeyError, AssertionError)):
                                notices.check(package, expected)
                        else:
                            notices.check(package, expected)


if __name__ == '__main__':
    unittest.main()
