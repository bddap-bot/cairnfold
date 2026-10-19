import re
import unittest
from pathlib import Path

SRC = Path(__file__).parents[1] / 'game/src'


def expanded(path):
    text = path.read_text()
    return re.sub(r'#include "res://src/([^"]+)"', lambda m: expanded(SRC / m.group(1)), text)


class Shaders(unittest.TestCase):
    def test_every_lit_surface_takes_lantern_light(self):
        # Lanterns are no Godot lights: a shaded surface is lit by them only through given_back (Lamps). Water
        # mostly mirrors the sky and keeps no diffuse colour for a lantern to light. A picture-book page's meadow is
        # lit in the page's own world, where no lantern hangs.
        for path in sorted(set(SRC.glob('*.gdshader')) - {SRC / 'water.gdshader', SRC / 'lesson_dish.gdshader'}):
            text = expanded(path)
            mode = re.search(r'^render_mode ([^;]*);', text, re.M)
            if not text.startswith('shader_type spatial') or (mode and 'unshaded' in mode.group(1)):
                continue
            body = text.split('void vertex()', 1)[-1]
            with self.subTest(shader=path.name):
                self.assertTrue(re.search(r'given_(back|at)\(', body) and re.search(r'EMISSION\s*\+?=', body))


if __name__ == '__main__':
    unittest.main()
