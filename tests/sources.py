"""Reads the game's constants from its sources, for tests holding a copy elsewhere to them."""
import re
from pathlib import Path

SRC = Path(__file__).parents[1] / 'game/src'


def numbers(*texts):
    found = [float(n) for text in texts if text for n in re.findall(r'(?<![\w.])-?\d+(?:\.\d+)?', text)]
    assert found, f'no number in {texts}'
    return found


def shader_const(path, name):
    return numbers(*re.search(rf'^(?:const \w+ {name} = ([^;]+);|#define {name} (.+))$', (SRC / path).read_text(), re.M).group(1, 2))


def script_const(path, name):
    return numbers(re.search(rf'^const {name}\b[^=]*= (.+)$', (SRC / path).read_text(), re.M).group(1))


def enum_members(path, enum):
    return [m.strip() for m in re.search(rf'^enum {enum} \{{([^}}]*)\}}', (SRC / path).read_text(), re.M).group(1).split(',')]
