#!/usr/bin/env python3
"""Cut three quiet charcoal textures from the CC0 pencil recording; run under nix-shell."""
import json
import numpy as np
from animals import decode
from compose import ROOT, SR, _fft_lowpass, write_ogg

OUT = ROOT / "charcoal"
PROFILES = {"soft": 950, "paper": 1250, "dark": 700}


def main():
    source = json.loads((OUT / "source.json").read_text())
    recording = decode(source["audio"])
    # Select separate active passages rather than repeat one tiny scratch.
    for name, cutoff in PROFILES.items():
        for i, start in enumerate((2, 5, 8, 11, 14, 18, 22, 26)):
            x = recording[int(start * SR):int((start + 0.16) * SR)].copy()
            x = _fft_lowpass(x - _fft_lowpass(x, 180, 4), cutoff, 6)
            x *= np.sin(np.linspace(0, np.pi, len(x))) ** 2
            rms = np.sqrt(np.mean(x * x))
            x *= min(0.07 / max(rms, 1e-9), 0.35 / max(np.abs(x).max(), 1e-9))
            write_ogg(OUT / f"{name}{i}.ogg", x, 5)


if __name__ == "__main__":
    main()
