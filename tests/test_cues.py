import json
from pathlib import Path
import re
import subprocess
import unittest

import numpy as np

ROOT = Path(__file__).parents[1]
FX = ROOT / 'game/audio/fx'
CUES = (ROOT / 'game/src/cues.gd').read_text()


def _families() -> dict[str, list[Path]]:
    out: dict[str, list[Path]] = {}
    for clip in sorted(FX.glob('*.ogg')):
        out.setdefault(re.sub(r'\d+$', '', clip.stem), []).append(clip)
    return out


def _bands(clip: Path) -> dict[str, float]:
    pcm = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(clip), '-ac', '1', '-ar', '44100', '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(pcm, np.float32)
    power = np.abs(np.fft.rfft(x)) ** 2
    hz = np.fft.rfftfreq(len(x), 1 / 44100)
    total = power.sum()
    out = {'centroid': float((power * hz).sum() / total), 'peak': float(np.abs(x).max())}
    for edge in (2000, 3000, 4000):
        out[f'above {edge}'] = float(power[hz > edge].sum() / total)
    return out


class ActionSounds(unittest.TestCase):
    def test_every_new_sound_is_no_brighter_than_the_stones_and_water(self) -> None:
        reference = json.loads(re.search(r'const REFERENCE := (\[.*?\])', CUES).group(1))
        families = _families()
        measured = {name: [_bands(c) for c in clips] for name, clips in families.items()}
        ceiling = {k: max(b[k] for name in reference for b in measured[name]) for k in measured[reference[0]][0]}
        rows = []
        for name in sorted(set(families) - set(reference)):
            for clip, b in zip(families[name], measured[name]):
                rows.append(f"{clip.stem:10s} centroid {b['centroid']:5.0f} Hz  >2 kHz {b['above 2000']:.4%}  "
                            f">3 kHz {b['above 3000']:.4%}  >4 kHz {b['above 4000']:.4%}")
                for edge in ('above 2000', 'above 3000', 'above 4000'):
                    self.assertLessEqual(b[edge], ceiling[edge], f'{clip.name} {edge} Hz: {b[edge]:.4%} against {ceiling[edge]:.4%}')
                self.assertLessEqual(b['centroid'], ceiling['centroid'] * 1.5, f'{clip.name} is brighter than the reference')
                self.assertLess(b['peak'], 0.75, f'{clip.name} is too loud')
        print(f"\nreference ceiling: centroid {ceiling['centroid']:.0f} Hz  >2 kHz {ceiling['above 2000']:.4%}  "
              f">3 kHz {ceiling['above 3000']:.4%}  >4 kHz {ceiling['above 4000']:.4%}\n" + '\n'.join(rows))

    def test_every_sound_family_has_its_clips(self) -> None:
        counts = {k: int(v) for k, v in re.findall(r'"(\w+)": (\d+)', re.search(r'const SOUNDS := \{(.*?)\}', CUES, re.S).group(1))}
        self.assertEqual({k: len(v) for k, v in _families().items()}, counts)


if __name__ == '__main__':
    unittest.main()
