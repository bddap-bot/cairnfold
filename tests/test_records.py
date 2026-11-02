from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

script = Path(__file__).resolve().parents[1] / 'scripts/records.sh'


class Records(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.repo)
        (self.repo / 'scripts').mkdir()
        shutil.copy(script, self.repo / 'scripts/records.sh')
        self.git('init', '-q', '-b', 'main')
        self.write('game/world.gd', 'world\n')
        self.write('scripts/engine.patch', 'patch\n')
        self.write('README.md', 'readme\n')
        self.commit('main')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')

    def git(self, *args):
        return subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@t', *args], cwd=self.repo, check=True,
                              capture_output=True, text=True).stdout.strip()

    def write(self, path, text):
        (self.repo / path).parent.mkdir(parents=True, exist_ok=True)
        with open(self.repo / path, 'a') as f:
            f.write(text)

    def commit(self, message):
        self.git('add', '-A')
        self.git('commit', '-q', '-m', message)
        return self.git('rev-parse', 'HEAD')

    def records(self):
        return subprocess.run([self.repo / 'scripts/records.sh'], cwd=self.repo, capture_output=True, text=True)

    # The job's branch: a change benched on its working commit, then the record committed after it.
    def bench(self, commit=True):
        self.git('checkout', '-q', '-b', 'job', 'main')
        self.write('game/world.gd', 'cheaper\n')
        built = self.commit('change')
        self.write(f'perf/quest-2/stress/20261102T000000Z-{built[:7]}.json', '{}\n')
        if commit:
            self.commit('record')
        return built

    # Main moves under the job with a commit touching PATH, and the job rebases onto it.
    def rebase_onto(self, path):
        self.git('checkout', '-q', 'main')
        self.write(path, 'moved\n')
        self.commit('main moves')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        self.git('checkout', '-q', 'job')
        self.git('rebase', '-q', 'main')

    def test_record_on_the_tree_that_lands_passes(self):
        self.bench()
        self.assertEqual(self.records().returncode, 0)

    def test_rebase_onto_a_changed_game_fails(self):
        built = self.bench()
        self.rebase_onto('game/plants.gd')
        result = self.records()
        self.assertEqual(result.returncode, 1)
        self.assertIn(built, result.stdout)

    def test_rebase_onto_a_changed_engine_fails(self):
        self.bench()
        self.rebase_onto('scripts/engine.patch')
        self.assertEqual(self.records().returncode, 1)

    def test_rebase_onto_an_unrelated_change_passes(self):
        self.bench()
        self.rebase_onto('README.md')
        self.assertEqual(self.records().returncode, 0)

    def test_merging_a_changed_game_fails(self):
        self.bench()
        self.git('checkout', '-q', 'main')
        self.write('game/plants.gd', 'moved\n')
        self.commit('main moves')
        self.git('checkout', '-q', 'job')
        self.git('merge', '-q', '--no-edit', 'main')
        self.git('update-ref', 'refs/remotes/origin/main', 'main')
        self.assertEqual(self.records().returncode, 1)

    def test_change_after_the_record_fails(self):
        self.bench()
        self.write('game/world.gd', 'review fix\n')
        self.commit('review fix')
        self.assertEqual(self.records().returncode, 1)

    def test_uncommitted_record_is_held_to_the_working_tree(self):
        self.bench(commit=False)
        self.assertEqual(self.records().returncode, 0)
        self.write('game/world.gd', 'more\n')
        self.assertEqual(self.records().returncode, 1)

    def test_record_naming_no_commit_fails(self):
        self.write('perf/quest-2/stress/20261102T000000Z-deadbee.json', '{}\n')
        self.commit('record')
        self.assertEqual(self.records().returncode, 1)

    def test_without_origin_main_nothing_is_compared(self):
        self.bench()
        self.git('update-ref', '-d', 'refs/remotes/origin/main')
        self.assertEqual(self.records().returncode, 0)

    def test_records_already_on_main_are_not_checked(self):
        self.write('perf/quest-2/stress/20261101T000000Z-deadbee.json', '{}\n')
        self.commit('old record')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        self.write('perf/quest-2/stress/20261101T000000Z-deadbee.json', '{"edited": 1}\n')
        self.commit('edit old record')
        self.assertEqual(self.records().returncode, 0)


if __name__ == '__main__':
    unittest.main()
