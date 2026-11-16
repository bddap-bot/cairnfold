from pathlib import Path
import re
import json
import subprocess
import unittest

ROOT = Path(__file__).parents[1]
DELIMITER = re.compile(r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$')


def cells(row: str) -> int:
    row = row.strip()
    row = row[1:] if row.startswith('|') else row
    row = row[:-1] if row.endswith('|') and not row.endswith('\\|') else row
    return len(re.split(r'(?<!\\)\|', row))


def mismatched_tables(text: str) -> list[str]:
    found, fenced, previous = [], False, ''
    for number, line in enumerate(text.split('\n'), 1):
        if line.lstrip().startswith('```'):
            fenced = not fenced
        elif not fenced and '|' in previous and '-' in line and DELIMITER.match(line):
            if cells(previous) != cells(line):
                found.append(f'{number}: {cells(previous)} header cells over {cells(line)} delimiter cells')
        previous = '' if fenced else line
    return found


class Docs(unittest.TestCase):
    def test_every_table_delimiter_matches_its_header(self):
        tracked = subprocess.run(['git', 'ls-files', '*.md'], cwd=ROOT, capture_output=True, text=True, check=True)
        for path in tracked.stdout.split():
            with self.subTest(path=path):
                self.assertEqual(mismatched_tables((ROOT / path).read_text()), [], f'{path}: GFM renders these as text')

    def test_each_extension_lists_the_fields_its_reader_requires(self):
        vrm = (ROOT / 'game/src/vrm.gd').read_text()
        names = dict(re.findall(r'^const (\w+) := "(\w+)"$', vrm, re.M))
        table = re.search(r'^const REQUIRED := (\{\n.*?\n\})$', vrm, re.M | re.S).group(1)
        required = json.loads(re.sub(r'^\t(\w+):', lambda m: f'"{names[m.group(1)]}":', table, flags=re.M))
        listed = {}
        for doc in sorted((ROOT / 'docs').glob('*.md')):
            for extension, rows in re.findall(r'^`(\w+)` records and the fields each must carry.*\n(?:.*\n)*?\| record \| fields \|\n\|---\|---\|\n((?:\|.*\|\n)+)', doc.read_text(), re.M):
                listed[extension] = {kind: re.findall(r'`(\w+)`', fields) for kind, fields in re.findall(r'^\| `(\w+)` \| (.*) \|$', rows, re.M)}
        self.assertEqual(listed, required)


if __name__ == '__main__':
    unittest.main()
