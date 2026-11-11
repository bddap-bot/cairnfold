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
    return list(enum_values(path, enum))


def enum_values(path, enum):
    values, value = {}, 0
    for member in re.search(rf'^enum {enum} \{{([^}}]*)\}}', (SRC / path).read_text(), re.M).group(1).split(','):
        name, _, given = member.partition('=')
        value = int(given) if given.strip() else value
        values[name.strip()] = value
        value += 1
    return values


def script_strings(path, name):
    return re.findall(r'"([^"]*)"', re.search(rf'^const {name}\b[^=]*= (\[.*\])$', (SRC / path).read_text(), re.M).group(1))


def shader_named(path, prefix):
    """The shader's compiled-in constants named `prefix` + a name, by that name."""
    return {m[0]: float(m[1]) for m in re.findall(rf'^const \w+ {prefix}(\w+) = (-?[\d.]+);$', (SRC / path).read_text(), re.M)}
