import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).parents[1]


def charges() -> dict[str, float]:
    source = (ROOT / 'game/src/budget.gd').read_text()
    consts = {name: float(value) for name, value in re.findall(r'^const (\w+) := ([\d.]+)$', source, re.M)}
    table = re.search(r'^const COSTS := \{(.*)\}$', source, re.M).group(1)
    return {unit: eval(expr, {}, consts) for unit, expr in re.findall(r'"(\w+)": ([^,]+)', table)}


class Prices(unittest.TestCase):
    def test_no_kind_is_charged_below_its_latest_quest_2_price(self):
        latest = {}
        for record in sorted((ROOT / 'perf/quest-2').glob('*/*.json'), key=lambda p: p.name):
            for kind, price in json.loads(record.read_text()).get('prices', {}).items():
                latest[kind] = (price, record.relative_to(ROOT))
        self.assertIn('pondweed', latest)
        costs = charges()
        for kind, (price, record) in latest.items():
            self.assertIn(price['unit'], costs, f'{record}: {kind} is charged as no unit Budget.COSTS prices')
            self.assertGreaterEqual(costs[price['unit']], price['us'],
                                    f'{record}: {kind} costs {price["us"]} µs a {price["unit"]}, charged {costs[price["unit"]]}')


if __name__ == '__main__':
    unittest.main()
