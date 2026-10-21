import json
from pathlib import Path
import unittest
from test_cues import _bands

ROOT = Path(__file__).parents[1]


class CharcoalRecording(unittest.TestCase):
    def test_provenance_and_soft_spectrum(self):
        folder = ROOT / 'game/audio/charcoal'
        source = json.loads((folder / 'source.json').read_text())
        self.assertIn('CC0', source['licence'])
        self.assertTrue(source['page'].startswith('https://'))
        self.assertTrue(source['author'])
        for profile in ('soft', 'paper', 'dark'):
            clips = sorted(folder.glob(f'{profile}*.ogg'))
            self.assertEqual(len(clips), 8)
            for clip in clips:
                bands = _bands(clip)
                self.assertLess(bands['above 2000'], 0.005, clip.name)
                self.assertLess(bands['above 4000'], 0.0001, clip.name)
                self.assertLess(bands['peak'], 0.4, clip.name)
                self.assertLess(bands['centroid'], 1400, clip.name)
