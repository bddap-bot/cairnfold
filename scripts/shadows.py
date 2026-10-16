#!/usr/bin/env python3
"""Check full-eye captures from shadows.gd; run inside shell.nix with the capture directory."""
import json
from pathlib import Path
import subprocess
import sys

import numpy as np

YAW = range(-40, 41, 10)
PATCHES = {
    "tree": ((-7.2, -4.8), (2.2, 4.2), -25),
    "roof": ((6, 11), (2.5, 4.5), -24),
}


def read_image(path):
    size = subprocess.check_output(["magick", "identify", "-format", "%w %h", str(path)])
    w, h = map(int, size.split())
    raw = subprocess.check_output(["magick", str(path), "-depth", "8", "rgb:-"])
    return np.frombuffer(raw, dtype=np.uint8).reshape(h, w, 3)


def check(folder):
    failures = []
    for name, (xr, yr, z) in PATCHES.items():
        x, y = np.meshgrid(np.linspace(*xr, 120), np.linspace(yr[1], yr[0], 80))
        points = np.stack([x, y, np.full_like(x, z), np.ones_like(x)]).reshape(4, -1)
        for eye in range(2):
            means = []
            for yaw in YAW:
                meta = json.loads((folder / f"shadow-current-yaw-{yaw}.json").read_text())
                if not np.allclose(meta["head"], [0, 1.72953867912292, 20], atol=0.001):
                    raise ValueError("The sweep moved the head position")
                matrix = np.array(meta["matrices"][eye]).T
                ndc = matrix @ points
                ndc = ndc[:2] / ndc[3]
                img = read_image(folder / f"shadow-current-yaw-{yaw}-eye-{eye}.png")
                h, w = img.shape[:2]
                u = (ndc[0] + 1) * w / 2
                # RenderSceneData supplies Vulkan's downward-positive image Y.
                v = (ndc[1] + 1) * h / 2
                if not ((u >= 0) & (u < w - 1) & (v >= 0) & (v < h - 1)).all():
                    continue
                px, py = np.floor(u).astype(int), np.floor(v).astype(int)
                fx, fy = (u - px)[:, None], (v - py)[:, None]
                patch = (img[py, px] * (1 - fx) * (1 - fy)
                         + img[py, px + 1] * fx * (1 - fy)
                         + img[py + 1, px] * (1 - fx) * fy
                         + img[py + 1, px + 1] * fx * fy)
                means.append(float(patch.mean()))
                dest = folder / f"{name}-eye-{eye}-yaw-{yaw}.png"
                subprocess.run(["magick", "-size", "120x80", "-depth", "8", "rgb:-",
                                "-resize", "480x320", str(dest)],
                               input=patch.astype(np.uint8).tobytes(), check=True)
            if len(means) < 7:
                raise ValueError(f"{name} eye {eye}: insufficient visible sweep")
            spread = max(means) - min(means)
            # A broad, fixed region tolerates raster/VRS edge noise, but not shadow fading.
            held = spread <= 2.5 and max(means) < (110 if name == "tree" else 100)
            print(f"{name} eye {eye}: brightness {min(means):.3f}..{max(means):.3f}/255; "
                  f"variation {spread:.3f} (limit 2.5): {'PASS' if held else 'FAIL'}")
            if not held:
                failures.append((name, eye))
    return bool(failures)


if __name__ == "__main__":
    sys.exit(check(Path(sys.argv[1])))
