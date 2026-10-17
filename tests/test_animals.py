import hashlib
import json
from pathlib import Path
import subprocess
import unittest

import numpy as np

ANIMALS = Path(__file__).parents[1] / 'game/audio/animals'
MODELS = Path(__file__).parents[1] / 'game/animals'


class AnimalCalls(unittest.TestCase):
    def test_every_call_is_soft(self):
        clips = sorted(ANIMALS.glob('*.ogg'))
        self.assertTrue(clips)
        for clip in clips:
            pcm = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(clip), '-ac', '1', '-ar', '44100', '-f', 'f32le', '-'],
                                 capture_output=True, check=True).stdout
            x = np.frombuffer(pcm, np.float32)
            power = np.abs(np.fft.rfft(x)) ** 2
            hz = np.fft.rfftfreq(len(x), 1 / 44100)
            self.assertLess(power[hz > 4000].sum() / power.sum(), 0.02, f'{clip.name} keeps its highs')
            self.assertLess(np.abs(x).max(), 0.75, f'{clip.name} is too loud')
            self.assertLess(len(x) / 44100, 1.5, f'{clip.name} is too long')

    def test_every_source_is_public_domain(self):
        for s in json.loads((ANIMALS / 'sources.json').read_text()):
            self.assertTrue(s['licence'].startswith('CC0'), s['page'])


class AnimalModels(unittest.TestCase):
    def test_every_model_is_the_public_domain_file_listed(self):
        sources = {s['file']: s for s in json.loads((MODELS / 'sources.json').read_text())}
        models = sorted(p.name for p in MODELS.glob('*.glb'))
        self.assertTrue(models)
        self.assertEqual(models, sorted(sources))
        for name in models:
            self.assertTrue(sources[name]['licence'].startswith('CC0'), name)
            self.assertEqual(hashlib.sha256((MODELS / name).read_bytes()).hexdigest(), sources[name]['sha256'], name)


if __name__ == '__main__':
    unittest.main()
