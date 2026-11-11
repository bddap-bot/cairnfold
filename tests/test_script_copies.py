import re
import unittest
from pathlib import Path

from sources import script_const

ROOT = Path(__file__).parents[1]


def read(path):
    return (ROOT / path).read_text()


class ScriptCopies(unittest.TestCase):
    # The shell scripts and a printed command keep their own copy of a game value; this holds each to its source.

    def test_host_ports_follow_session(self):
        [port], [ports], [port_range] = (script_const('session.gd', n) for n in ('PORT', 'PORTS', 'PORT_RANGE'))
        for path in ('scripts/poses.sh', 'scripts/store-art.sh'):
            with self.subTest(path=path):
                first, stride, blocks = re.search(r'^(?:first|port)=\$\(\((\d+) \+ (\d+) \* \(RANDOM % (\d+)\)\)\)$', read(path), re.M).groups()
                self.assertEqual((float(first), float(stride)), (port, ports))
                self.assertLessEqual(int(blocks) * ports, port_range)
        self.assertEqual(float(re.search(r'hosting=(\d+)', read('scripts/bench.sh')).group(1)), port)

    def test_bench_players_follow_session(self):
        [most] = script_const('session.gd', 'MAX_PLAYERS')
        bench = read('scripts/bench.sh')
        self.assertEqual(float(re.search(r'case \$players in \[1-(\d)\]', bench).group(1)), most)
        self.assertIn(f'CAIRNFOLD_PLAYERS is 1 to {most:.0f}"', bench)

    def test_package_follows_the_export(self):
        names = set(re.findall(r'^package/unique_name="([^"]+)"', read('game/export_presets.cfg'), re.M))
        self.assertEqual(len(names), 1)
        [name] = names
        self.assertIn(f'pkg={name}\n', read('scripts/quest-install.sh'))
        self.assertIn(f'--app {name} ', read('scripts/hitches.py'))


if __name__ == '__main__':
    unittest.main()
