import re
import unittest

from sources import SRC, enum_members, enum_values, script_const, script_strings, shader_const, shader_named


def expanded(path):
    text = path.read_text()
    return re.sub(r'#include "res://src/([^"]+)"', lambda m: expanded(SRC / m.group(1)), text)


class Shaders(unittest.TestCase):
    def test_every_lit_surface_takes_lantern_light(self):
        # Lanterns are no Godot lights: a shaded surface is lit by them only through given_back (Lamps). A picture-book
        # page's meadow is lit in the page's own world, where no lantern hangs.
        for path in sorted(set(SRC.glob('*.gdshader')) - {SRC / 'lesson_dish.gdshader'}):
            text = expanded(path)
            mode = re.search(r'^render_mode ([^;]*);', text, re.M)
            if not text.startswith('shader_type spatial') or (mode and 'unshaded' in mode.group(1)):
                continue
            body = text.split('void vertex()', 1)[-1]
            with self.subTest(shader=path.name):
                self.assertTrue(re.search(r'GIVE_HERE|given_(back|at|over|read)\(', body) and re.search(r'TAKE_GIVEN|EMISSION\s*\+?=', body))

    def test_shader_copies_match_their_scripts(self):
        # A size, index or layout a shader compiles in rather than takes as a uniform keeps its own copy; this names the source.
        pairs = [
            ('expression.gdshaderinc', 'RAMP', script_const('avatar.gd', 'RAMP')),
            ('expression.gdshaderinc', 'COAT_ROWS', script_const('avatar.gd', 'COAT_ROWS')),
            ('expression.gdshaderinc', 'MATCAP_ROWS', script_const('avatar.gd', 'MATCAP_ROWS')),
            ('expression.gdshaderinc', 'HEAD_ROWS', script_const('avatar.gd', 'HEAD_ROWS')),
            ('expression.gdshaderinc', 'MATCAPS', script_const('avatar.gd', 'MATCAPS')),
            ('conure.gdshader', 'L', script_const('conure.gd', 'ALONG')),
            ('conure.gdshader', 'D', script_const('conure.gd', 'OUT')),
            ('conure.gdshader', 'BODY', script_const('conure.gd', 'BODY')),
            ('conure.gdshader', 'BILL', [enum_members('conure.gd', 'Patch').index('BILL')]),
            ('conure.gdshader', 'PATCHES', [len(enum_members('conure.gd', 'Patch'))]),
            ('water.gdshaderinc', 'DROWNS', script_const('water.gd', 'DROWNS')),
            ('interior.gdshaderinc', 'OPENING', script_const('interior.gd', 'OPENING')),
            ('ground.gdshaderinc', 'TILLED', script_const('ground.gd', 'TILLED')),
            ('stone_ground.gdshaderinc', 'STONE_ROOM', script_const('stone_styles.gd', 'ROOM')),
            ('budget_bar.gdshader', 'NO', script_const('hand.gd', 'REFUSED')[:3]),
            ('paint.glsl', 'TILE', script_const('brushwork.gd', 'TILE')),
            ('paint.glsl', 'FLAT', [enum_members('brushwork.gd', 'Brush').index('FLAT')]),
        ]
        pairs += [('paint.glsl', name, script_const('canvas.gd', name)) for name in ('PAPER', 'DAB', 'FLOW')]
        pairs += [('paint.glsl', name, [i]) for i, name in enumerate(enum_members('brushwork.gd', 'Medium'))]
        pairs += [('stone_bake.glsl', name, [i]) for i, name in enumerate(enum_members('stone_styles.gd', 'Kind'))]
        rows = re.findall(r'^const (ROW_\w+)', (SRC / 'avatar_particles.gd').read_text(), re.M)
        pairs += [('particle.gdshaderinc', name, script_const('avatar_particles.gd', name)) for name in rows]
        for shader, name, source in pairs:
            with self.subTest(shader=shader, name=name):
                self.assertEqual(shader_const(shader, name), source)

    def test_shader_codes_match_their_scripts(self):
        # A code a script writes and a shader branches on, named on both sides: each name the shader gives is the
        # script's member of that name, whose index or value is the code.
        snake = lambda name: re.sub(r'(?<=[a-z])(?=[A-Z])', '_', name).upper()
        sides = [
            ('stone.gdshaderinc', 'ELEMENT_', enum_values('palette.gd', 'Element')),
            ('particle.gdshaderinc', 'MODE_', [m.upper() for m in script_strings('particle_definition.gd', 'MODES')]),
            ('particle.gdshaderinc', 'ALIGN_', [a.upper() for a in script_strings('particle_definition.gd', 'ALIGNS')]),
            ('expression.gdshaderinc', 'REGION_', [r.upper() for r in script_strings('expression_definition.gd', 'REGIONS')]),
            ('expression.gdshaderinc', 'LOOK_', [snake(f) for f in script_strings('expression_player.gd', 'LOOK_FIELDS')]),
        ]
        animals = {'duck': 'duck.gd', 'sheep': 'sheep.gd', 'conure': 'conure.gd', 'owl': 'owls.gd', 'frog': 'frogs.gd', 'squirrel': 'squirrels.gd', 'snake': 'snakes.gd'}
        sides += [(f'{shader}.gdshader', 'PART_', enum_values(script, 'Part')) for shader, script in animals.items()]
        for shader, prefix, members in sides:
            codes = members if isinstance(members, dict) else {name: i for i, name in enumerate(members)}
            named = shader_named(shader, prefix)
            with self.subTest(shader=shader, prefix=prefix):
                self.assertTrue(named)
                self.assertEqual(named, {name: float(codes[name]) for name in named if name in codes})
        bare = [(f'{shader}.gdshader', r'\bpart [=!<>]=? \d') for shader in animals]
        bare += [('stone.gdshaderinc', r'material - \d'), ('particle.gdshaderinc', r'\b(mode|align) [=!]= \d'), ('expression.gdshaderinc', r'\b(kind|field) == \d')]
        for shader, code in bare:
            with self.subTest(shader=shader):
                self.assertNotRegex((SRC / shader).read_text(), code)

    def test_decal_blends_match_the_definition(self):
        blend = re.search(r'vec3 decal_blend\(.*?\n}', (SRC / 'expression.gdshaderinc').read_text(), re.S).group(0)
        [listed] = [re.findall(r'\d+', l) for l in re.findall(r'^const DECAL_BLENDS.*$', (SRC / 'expression_definition.gd').read_text(), re.M)]
        # Blend 0, replace, is the shader's fall-through.
        self.assertEqual(['0'] + re.findall(r'mode == (\d+)', blend), listed)


if __name__ == '__main__':
    unittest.main()
