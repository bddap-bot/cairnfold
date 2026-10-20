#!/usr/bin/env python3
"""Cuts the action sounds in game/audio/fx that are recordings, not synthesised, from the CC0 files its sources.json
lists: the first half second of each, low-passed at 1.8 kHz like every synthesised effect, faded in and out, and
written at one peak, so their cue's level alone sets how loud they play. Run under nix-shell."""

import json
import sys

import numpy as np

from animals import decode
from compose import ROOT, SR, _fft_lowpass, write_ogg

FX = ROOT / "fx"
SECONDS = 0.5
PEAK = 0.7


def cut(x):
    x = _fft_lowpass(x[: int(SECONDS * SR)], 1800, 4)
    x = np.pad(x, (0, int(SECONDS * SR) - len(x)))
    n_in, n_out = int(0.01 * SR), int(0.08 * SR)
    x[:n_in] *= np.linspace(0, 1, n_in)
    x[-n_out:] *= np.linspace(1, 0, n_out)
    return x * PEAK / np.abs(x).max()


def main():
    for s in json.loads((FX / "sources.json").read_text()):
        write_ogg(FX / f"{s['clip']}.ogg", cut(decode(s["audio"], s["member"])), 5)
        print(f"{s['clip']}: from {s['page']}")


if __name__ == "__main__":
    sys.exit(main())
