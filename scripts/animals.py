#!/usr/bin/env python3
"""The animal calls, softened for a headset: rumble and hiss out, highs rolled off, every call at one loudness.
Run under nix-shell."""

import json
import pathlib
import subprocess
import urllib.request
import zipfile

import numpy as np

from compose import ROOT as AUDIO, SR, _fft_lowpass, write_ogg

ROOT = AUDIO / "animals"
CACHE = pathlib.Path(__file__).resolve().parent / ".animals-cache"
# (high-pass Hz, low-pass Hz, low-pass order, pitch ratio). Conure chirps sit at 3–5 kHz, so they drop three semitones
# toward the meadow bed's birds; contact calls ring to 8 kHz and keep their lowest two harmonics. Fox and squirrel drop
# out of their brightness; a rustle is broadband, so it keeps little above 1.6 kHz.
SHAPE = {
    "conure": (500, 2600, 3, 2 ** (-3 / 12)),
    "conure contact": (600, 1800, 6, 2 ** (-3 / 12)),
    "duck": (250, 3500, 2, 1.0),
    "duckling": (900, 3000, 2, 1.0),
    "sheep": (150, 3500, 2, 1.0),
    "deer": (300, 2600, 3, 1.0),
    "fox": (350, 2400, 3, 2 ** (-3 / 12)),
    "frog": (120, 2200, 3, 1.0),
    "owl": (150, 1800, 3, 1.0),
    "squirrel": (400, 2400, 3, 2 ** (-3 / 12)),
    "rustle": (200, 1600, 4, 1.0),
}
GAP = 0.09
RMS = 10 ** (-22 / 20)
PEAK = 0.7


def decode(url, member=None):
    """The recording at `url`, or the file `member` in the zip there, as mono samples at SR."""
    CACHE.mkdir(exist_ok=True)
    path = CACHE / url.rsplit("/", 1)[1]
    if not path.exists():
        request = urllib.request.Request(url, headers={"User-Agent": "cairnfold-animals"})
        path.write_bytes(urllib.request.urlopen(request, timeout=60).read())
    if member is not None:
        out = CACHE / f"{path.stem}-{pathlib.PurePosixPath(member).name}"
        if not out.exists():
            with zipfile.ZipFile(path) as z:
                out.write_bytes(z.read(member))
        path = out
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
    main()
