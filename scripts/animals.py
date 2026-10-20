#!/usr/bin/env python3
"""Cuts the animal calls in game/audio/animals from the recordings listed in its sources.json, softened for a
headset: rumble and hiss filtered out, highs rolled off, the conures' a little lower, every call at one loudness.
Downloads each recording once into scripts/.animals-cache; run under nix-shell."""

import json
import pathlib
import subprocess
import sys
import urllib.request

import numpy as np

from compose import SR, _fft_lowpass, write_ogg

ROOT = pathlib.Path(__file__).resolve().parent.parent / "game" / "audio" / "animals"
CACHE = pathlib.Path(__file__).resolve().parent / ".animals-cache"
# Per kind: high-pass and low-pass corners in Hz and pitch ratio. A conure's chirps sit at 3–5 kHz, so they are
# taken down three semitones, near the meadow bed's birds, and rolled off from 2.6 kHz with a steeper slope than the others;
# their contact calls, loud and ringing to 8 kHz, keep only their lowest two harmonics.
# A fox is taken down three semitones too, out of the bright bark its quarrels have.
SHAPE = {
    "conure": (500, 2600, 3, 2 ** (-3 / 12)),
    "conure contact": (600, 1800, 6, 2 ** (-3 / 12)),
    "duck": (250, 3500, 2, 1.0),
    "duckling": (900, 3000, 2, 1.0),
    "sheep": (150, 3500, 2, 1.0),
    "deer": (300, 2600, 3, 1.0),
    "fox": (350, 2400, 3, 2 ** (-3 / 12)),
}
GAP = 0.09
RMS = 10 ** (-22 / 20)
PEAK = 0.7


def decode(url):
    CACHE.mkdir(exist_ok=True)
    path = CACHE / url.rsplit("/", 1)[1]
    if not path.exists():
        request = urllib.request.Request(url, headers={"User-Agent": "nestcombe-animals"})
        path.write_bytes(urllib.request.urlopen(request, timeout=60).read())
    pcm = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(pcm, np.float32).astype(np.float64)


def shape(x, kind):
    high, low, order, pitch = SHAPE[kind]
    if pitch != 1.0:
        x = np.interp(np.arange(0, len(x) - 1, pitch), np.arange(len(x)), x)
    x = _fft_lowpass(x - _fft_lowpass(x, high, 4), low, order)
    fade = np.ones(len(x))
    n_in, n_out = int(0.008 * SR), int(0.06 * SR)
    fade[:n_in] = np.linspace(0, 1, n_in)
    fade[-n_out:] = np.linspace(1, 0, n_out) ** 2
    return x * fade


def loud(x):
    frames = x[: len(x) // 441 * 441].reshape(-1, 441)
    rms = np.sqrt((frames**2).mean(axis=1))
    return np.sqrt((rms[rms > rms.max() * 0.25] ** 2).mean())


def clip(audio, parts, kind):
    pieces = []
    for start, length in parts:
        x = shape(audio[int(start * SR): int((start + length) * SR)], kind)
        pieces += [x / loud(x), np.zeros(int(GAP * SR))]
    x = np.concatenate(pieces[:-1])
    x *= RMS / loud(x)
    return x * min(1.0, PEAK / np.abs(x).max())


def main():
    sources = json.loads((ROOT / "sources.json").read_text())
    for old in ROOT.glob("*.ogg"):
        old.unlink()
    for s in sources:
        audio = decode(s["audio"])
        for name, parts in s["clips"].items():
            x = clip(audio, parts, s["kind"])
            write_ogg(ROOT / f"{name}.ogg", x, 2)
            print(f"{name}: {len(x) / SR:.2f} s from {s['page']}")


if __name__ == "__main__":
    sys.exit(main())
