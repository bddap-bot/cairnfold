#!/usr/bin/env python3
"""Writes every sound in game/audio: the music sections as three synchronized stems
each, the meadow bed, the stone sounds and the water sounds. Deterministic; run under nix-shell."""

import json
import pathlib
import subprocess
import sys
import tempfile

import numpy as np

SR = 44100
TAIL = 3.0
ROOT = pathlib.Path(__file__).resolve().parent.parent / "game" / "audio"
STEMS = ("bed", "lead", "orn")
rng = np.random.default_rng(7)

NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
QUALITY = {
    "": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "maj7": [0, 4, 7, 11],
    "m7": [0, 3, 7, 10], "m9": [0, 3, 7, 10, 14], "maj9": [0, 4, 7, 11, 14],
    "sus4": [0, 5, 7], "9": [0, 4, 7, 10, 14], "add9": [0, 4, 7, 14], "6": [0, 4, 7, 9],
}
B_MAJOR = [11, 1, 3, 4, 6, 8, 10]
B_MINOR = [11, 1, 2, 4, 6, 7, 9]


def pc(name):
    return (NAMES[name[0]] + name[1:].count("#") - name[1:].count("b")) % 12


def note(name):
    return 12 * (int(name[-1]) + 1) + pc(name[:-1])


def chord(spec):
    head, _, slash = spec.partition("/")
    root = head[:2] if len(head) > 1 and head[1] in "#b" else head[:1]
    pcs = {(pc(root) + i) % 12 for i in QUALITY[head[len(root):]]}
    bass = pc(slash or root)
    # A fixed window gives close voice leading for free: every chord tone sits in D3..C#4.
    return sorted(50 + (p - 50) % 12 for p in pcs), 35 + (bass - 35) % 12


# The two motifs, as (beat, beats, midi).
M1 = [(0, 1.5, 90), (3.5, 0.5, 83), (4, 1, 87), (7.5, 0.5, 85), (8, 1.5, 83), (11.5, 0.5, 83), (12, 1, 78)]
M2 = [(i * 0.5, 0.5, n) for i, n in enumerate([83, 86, 90, 86, 85, 86, 85, 86, 85, 86, 85, 86, 85, 86, 85])]


def moved(motif, at=0.0, shift=0, stretch=1.0, swap=None):
    out = []
    for b, d, n in motif:
        if swap and n % 12 == swap[0]:
            n += swap[1] - swap[0]
        out.append((at + b * stretch, d * stretch, n + shift))
    return out


def diatonic(motif, scale, steps):
    rel = [(p - 11) % 12 for p in scale]
    out = []
    for b, d, n in motif:
        octave, r = divmod(n - 11, 12)
        up, j = divmod(rel.index(r) + steps, 7)
        out.append((b, d, 11 + 12 * (octave + up) + rel[j]))
    return out


# ---------------------------------------------------------------- instruments

def _t(seconds):
    return np.arange(int(seconds * SR)) / SR


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def pluck(m, dur, vel):
    f = hz(m)
    t = _t(dur + 2.0)
    out = np.zeros_like(t)
    for k in range(1, 9):
        fk = f * k * (1 + 0.0004 * k * k)
        if fk > 3000:
            break
        decay = (1.0 + 1.7 * (k - 1)) * (f / 300) ** 0.35
        out += k ** -1.9 * np.exp(-t * decay) * np.sin(2 * np.pi * fk * t + rng.uniform(0, 6.28))
    out *= 1 - np.exp(-t / 0.005)
    out *= np.where(t > dur, np.exp(-(t - dur) / 0.35), 1.0)
    return vel * out


def mallet(m, dur, vel):
    f = hz(m)
    t = _t(dur + 1.5)
    out = np.exp(-t * 2.2) * np.sin(2 * np.pi * f * t) + 0.1 * np.exp(-t * 14) * np.sin(2 * np.pi * 4 * f * t)
    out *= 1 - np.exp(-t / 0.004)
    return vel * out


def flute(m, dur, vel):
    f = hz(m)
    t = _t(dur + 0.6)
    depth = 0.0035 * np.clip((t - 0.3) / 0.5, 0, 1)
    ph = 2 * np.pi * f * np.cumsum(1 + depth * np.sin(2 * np.pi * 5.1 * t)) / SR
    tone = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.07 * np.sin(3 * ph)
    breath = _fft_lowpass(rng.standard_normal(len(t)), min(3 * f, 2000)) * 0.05
    env = np.clip(t / 0.09, 0, 1) ** 2 * np.exp(-t * 0.25)
    env *= np.where(t > dur, np.exp(-(t - dur) / 0.12), 1.0)
    return vel * (tone + breath) * env


def pad(notes, dur, vel):
    t = _t(dur + 2.5)
    out = np.zeros((len(t), 2))
    for m in notes:
        for detune, pan in ((-6, -0.6), (0, 0.0), (6, 0.6)):
            f = hz(m) * 2 ** (detune / 1200)
            ph = 2 * np.pi * f * t + rng.uniform(0, 6.28)
            v = np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
            out += _pan(v, pan)
    env = np.clip(t / 1.4, 0, 1) ** 1.5 * np.where(t > dur, np.exp(-(t - dur) / 0.8), 1.0)
    env *= 1 + 0.08 * np.sin(2 * np.pi * 0.17 * t)
    return vel * out * env[:, None] / (3 * len(notes)) ** 0.5


def bass(m, dur, vel):
    f = hz(m)
    t = _t(dur + 0.8)
    ph = 2 * np.pi * f * t
    v = np.sin(ph) + 0.14 * np.sin(2 * ph) + 0.03 * np.sin(3 * ph)
    env = np.clip(t / 0.03, 0, 1) * (0.55 + 0.45 * np.exp(-t * 1.2))
    env *= np.where(t > dur, np.exp(-(t - dur) / 0.2), 1.0)
    return vel * v * env


INSTRUMENTS = {"pluck": pluck, "mallet": mallet, "flute": flute, "bass": bass}


def _fft_lowpass(x, cutoff, order=2):
    size = 1 << (len(x) - 1).bit_length()
    f = np.fft.rfftfreq(size, 1 / SR)
    gain = 1 / np.sqrt(1 + (f / cutoff) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(x, size, axis=0) * (gain[:, None] if x.ndim == 2 else gain), size, axis=0)[: len(x)]


def _pan(mono, p):
    a = (p + 1) * np.pi / 4
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1)


def _impulse(seconds=2.6):
    t = _t(seconds)
    chans = []
    for _ in range(2):
        noise = rng.standard_normal(len(t))
        spec = np.fft.rfft(noise)
        f = np.fft.rfftfreq(len(t), 1 / SR)
        bands = []
        # Highs die first, as in a soft room: no bright shimmer hanging over the tail.
        for lo, hi, rt in ((0, 400, 2.2), (400, 1500, 1.6), (1500, 4000, 0.8), (4000, SR, 0.3)):
            band = np.fft.irfft(np.where((f >= lo) & (f < hi), spec, 0), n=len(t))
            bands.append(band * np.exp(-6.9 * t / rt))
        ir = sum(bands)
        ir[: int(0.018 * SR)] = 0
        chans.append(ir / np.sqrt((ir**2).sum()))
    return np.stack(chans, axis=1)


IR = _impulse()


def reverb(x, wet):
    n = len(x) + len(IR)
    size = 1 << (n - 1).bit_length()
    out = np.empty((n, 2))
    for c in range(2):
        out[:, c] = np.fft.irfft(np.fft.rfft(x[:, c], size) * np.fft.rfft(IR[:, c], size), size)[:n]
    return x * (1 - wet) + out[: len(x)] * wet * 1.4


# ---------------------------------------------------------------- music

class Section:
    def __init__(self, name, bpm, beats, chords, beats_per_chord=4):
        self.name, self.bpm, self.beats = name, bpm, beats
        self.parts = {s: [] for s in STEMS}
        at = 0.0
        for spec in chords:
            span = beats_per_chord
            if isinstance(spec, tuple):
                spec, span = spec
            notes, root = chord(spec)
            self.parts["bed"].append((at, span, notes, "pad", 0.17, 0.0))
            self.parts["bed"].append((at, span, [root], "bass", 0.2, 0.0))
            at += span

    def add(self, stem, events, inst, vel, pan=0.0, shift=0):
        for b, d, n in events:
            if b < self.beats:
                self.parts[stem].append((b, d, [n + shift], inst, vel * rng.uniform(0.85, 1.05), pan))
        return self

    def render(self):
        spb = 60 / self.bpm
        n = int((self.beats * spb + TAIL) * SR)
        stems = {}
        for stem, events in self.parts.items():
            buf = np.zeros((n, 2))
            for b, d, notes, inst, vel, p in events:
                if inst == "pad":
                    sig = pad(notes, d * spb, vel)
                else:
                    sig = _pan(INSTRUMENTS[inst](notes[0], d * spb, vel), p)
                start = max(0, int((b * spb + rng.normal(0, 0.006) * (inst != "pad")) * SR))
                end = min(n, start + len(sig))
                buf[start:end] += sig[: end - start]
            stems[stem] = reverb(buf, 0.22 if stem == "bed" else 0.32)
        return stems


def ostinato(start, end, a, b, step=0.5):
    out, x, i = [], start, 0
    while x < end:
        out.append((x, step, a if i % 2 == 0 else b))
        x += step
        i += 1
    return out


def sections():
    D, Cs, Ds = 2, 1, 3
    out = []

    s = Section("first-light", 100, 32, ["B", "G#m", "E", "F#", "B", "D#m", "E", "F#sus4"])
    s.add("lead", moved(M1, 0, -12), "pluck", 0.5, -0.15).add("lead", moved(M1, 16, -12), "pluck", 0.4, -0.15)
    s.add("orn", [(16, 4, note("D#4")), (20, 4, note("B3")), (24, 4, note("G#3")), (28, 4, note("A#3"))], "flute", 0.22, 0.3)
    out.append(s)

    s = Section("ostinato", 108, 32, ["Bm", "G", "Em", "F#", "Bm", "G", "Em7", ("F#sus4", 2), ("F#", 2)])
    s.add("lead", moved(M2, 0, -12), "pluck", 0.42, -0.2).add("lead", moved(M2, 16, -12), "pluck", 0.38, -0.2)
    s.add("lead", [(8, 4, note("F#4")), (12, 2, note("E4")), (14, 2, note("D4")), (24, 4, note("F#4")), (28, 4, note("C#4"))], "flute", 0.3)
    s.add("orn", ostinato(8, 32, note("D4"), note("C#4")), "mallet", 0.22, 0.35)
    out.append(s)

    s = Section("waltz", 138, 48, ["B", "G#m", "E", "F#", "B", "D#m", ("E", 3), ("F#", 3), "B"], 6)
    for half, (inst, shift, vel) in enumerate((("pluck", -12, 0.42), ("flute", -24, 0.32))):
        long_notes = [n for _, d, n in M1 if d >= 1]
        pickups = [n for _, d, n in M1 if d < 1]
        base = half * 24
        for i, ln in enumerate(long_notes):
            s.add("lead", [(base + 6 * i, 4, ln)], inst, vel, shift=shift)
            if i < len(pickups):
                s.add("lead", [(base + 6 * i + 5, 1, pickups[i])], inst, vel * 0.8, shift=shift)
    for bar in range(16):
        notes, _ = chord(["B", "G#m", "E", "F#", "B", "D#m", "E", "B"][bar // 2])
        for beat in (1, 2):
            for n in notes[:3]:
                s.parts["bed"].append((bar * 3 + beat, 0.6, [n + 12], "pluck", 0.07, 0.25))
    out.append(s)

    s = Section("overlay-minor", 104, 32, ["Bm", "Gmaj7", "Em7", "F#sus4", "Bm", "Gmaj7", "Em7", "F#"])
    s.add("orn", moved(M2[:4], 0, -24) + ostinato(2, 32, note("D4"), note("C#4")), "pluck", 0.2, 0.3)
    s.add("lead", moved(M1, 0, -12, swap=(Ds, D)), "flute", 0.34, -0.2)
    s.add("lead", moved(M1, 16, -12, swap=(Ds, D)), "pluck", 0.44, -0.2)
    out.append(s)

    s = Section("fragments", 72, 32, [("Badd9", 8), ("Emaj7/B", 8), ("Badd9", 8), ("Bsus4", 4), ("B", 4)])
    s.add("lead", [(3.5, 0.5, note("B3")), (4, 3, note("D#4")), (11.5, 0.5, note("C#4")), (12, 3, note("B3")),
                   (19.5, 0.5, note("B3")), (20, 4, note("F#3"))], "flute", 0.34, -0.25)
    s.add("orn", [(7.5, 0.5, note("B4")), (8, 2, note("D#5")), (15.5, 0.5, note("C#5")), (16, 2, note("B4")),
                  (23.5, 0.5, note("B4")), (24, 3, note("F#4")), (28, 3, note("B3"))], "pluck", 0.3, 0.3)
    out.append(s)

    s = Section("relative", 100, 32, ["D", "Bm", "G", "A", "D", "Bm7", "Gmaj7", ("Asus4", 2), ("A", 2)])
    s.add("lead", moved(diatonic(M2, B_MINOR, 2), 0, -24), "pluck", 0.45, -0.15)
    s.add("lead", moved(diatonic(moved(M1, swap=(Ds, D)), B_MINOR, 2), 16, -24), "flute", 0.36, -0.15)
    s.add("orn", ostinato(8, 32, note("E4"), note("F#4")), "mallet", 0.2, 0.35)
    out.append(s)

    s = Section("slow-reharm", 84, 32, ["Emaj7", "D#m7", "C#m9", "F#sus4", "Gmaj7", "F#sus4", "Emaj7", "Bmaj9"])
    s.add("lead", moved(M1, 0, -24), "flute", 0.4).add("lead", moved(M1, 16, -24), "flute", 0.36)
    answers = {0: ("D#5", "B4"), 1: ("C#5", "A#4"), 2: ("B4", "G#4"), 3: ("A#4", "C#5"),
               4: ("B4", "D5"), 5: ("A#4", "C#5"), 6: ("G#4", "B4"), 7: ("A#4", "F#4")}
    for bar, (a, b) in answers.items():
        s.add("orn", [(bar * 4 + 2, 0.5, note(a)), (bar * 4 + 2.5, 1, note(b))], "pluck", 0.18, 0.35)
    out.append(s)

    s = Section("dorian", 120, 32, ["Bm7", "E9", "Bm7", "E9", "Gmaj7", "A", "Bm7", "F#sus4"])
    s.add("orn", ostinato(0, 32, note("D4"), note("C#4"), 1.0), "mallet", 0.2, 0.3)
    for at in (0, 8):
        s.add("lead", moved(M2[:4], at, -12, 2) + [(at + 4, 3.5, note("C#5"))], "flute", 0.3, -0.2)
    s.add("lead", moved(M1, 16, -24, swap=(Ds, D)), "pluck", 0.46, -0.2)
    out.append(s)

    s = Section("overlay-major", 104, 32, ["B", "E/B", "G#m", "F#", "B", "E", "G#m7", ("F#sus4", 2), ("F#", 2)])
    s.add("orn", ostinato(0, 32, note("D#4"), note("C#4")), "mallet", 0.18, 0.35)
    s.add("lead", moved(M1, 0, -12), "pluck", 0.46, -0.2).add("lead", moved(M1, 16, -12), "flute", 0.34, -0.2)
    out.append(s)

    mirror = [(b, d, 59 + {0: 0, 2: 4, 3: 5, 4: 7, 7: 12}[k]) for (b, d, _), k in zip(M1, [0, 4, 2, 3, 4, 4, 7])]
    s = Section("mirror", 92, 32, ["B", "D#m", "Eadd9", "B", "B", "G#m", "Eadd9", "Bmaj7"])
    s.add("lead", mirror, "flute", 0.36, -0.2).add("lead", moved(mirror, 16), "pluck", 0.44, -0.25)
    s.add("orn", moved(M1, 16, -24), "flute", 0.26, 0.3)
    out.append(s)

    s = Section("canon", 96, 32, ["B", "G#m", "E", "F#", "B", "G#m", "E", "F#"])
    s.add("lead", moved(M1, 0, -12), "pluck", 0.46, -0.3).add("lead", moved(M1, 16, -12), "pluck", 0.38, -0.3)
    s.add("orn", moved(M1, 8, -24), "flute", 0.3, 0.35).add("orn", moved(M1, 24, -24), "flute", 0.26, 0.35)
    out.append(s)

    s = Section("lullaby", 80, 24, ["Bmaj9", "Emaj9/B", "G#m7", "F#sus4", ("Bmaj9", 8)])
    s.add("lead", [(0, 1.5, note("F#5")), (3.5, 0.5, note("B4")), (4, 1, note("D#5")), (7.5, 0.5, note("C#5")),
                   (8, 6, note("B4"))], "pluck", 0.36, -0.1)
    s.add("orn", [(11.5, 0.5, note("B3")), (12, 4, note("F#3")), (16, 6, note("B3"))], "flute", 0.26, 0.25)
    out.append(s)
    return out


# ---------------------------------------------------------------- effects

def _clack(fund, decay, bright):
    t = _t(0.35)
    out = np.zeros_like(t)
    for ratio, amp in ((1.0, 1.0), (2.32, 0.5), (3.71, 0.25 * bright), (5.4, 0.1 * bright)):
        out += amp * np.exp(-t * decay * ratio**0.6) * np.sin(2 * np.pi * fund * ratio * t + rng.uniform(0, 6.28))
    thud = np.exp(-t * 40) * np.sin(2 * np.pi * 95 * t)
    grit = _fft_lowpass(rng.standard_normal(len(t)) * np.exp(-t * 90), 1800)
    return out * 0.5 + thud * 0.7 + grit * 0.15


def _rattle(seconds, count, low):
    out = np.zeros(int(seconds * SR))
    times = np.sort(rng.uniform(0, seconds - 0.35, count) ** 1.6 / seconds**0.6)
    for i, x in enumerate(times):
        c = _clack(rng.uniform(380, 900) * low, rng.uniform(25, 45), 0.4) * rng.uniform(0.2, 1.0) * (1 - i / count) ** 0.8
        start = int(x * SR)
        end = min(len(out), start + len(c))
        out[start:end] += c[: end - start]
    return out


def effects():
    fx = {}
    for i in range(5):
        fx[f"stone{i}"] = _clack(rng.uniform(520, 820), rng.uniform(28, 40), rng.uniform(0.5, 1.0))
    for i in range(3):
        fx[f"settle{i}"] = _rattle(1.0, 9, 0.8)
    for i in range(2):
        fx[f"arch{i}"] = _rattle(1.2, 22, 1.0)
        fx[f"crumble{i}"] = _rattle(1.8, 40, 0.65)
    return {k: _fft_lowpass(v, 3200) for k, v in fx.items()}


def meadow(seconds=48.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    for c in range(2):
        brown = np.cumsum(rng.standard_normal(n))
        brown -= _fft_lowpass(brown, 8)
        gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / seconds * 3 + c) * np.sin(2 * np.pi * t / seconds * 5 + 1.3 * c)
        wind = _fft_lowpass(brown, 600) * gust
        hiss = rng.standard_normal(n)
        rustle = _fft_lowpass(hiss, 2600) - _fft_lowpass(hiss, 700)
        out[:, c] = wind / np.std(wind) * 0.05 + rustle / np.std(rustle) * 0.008 * gust**2
    for _ in range(9):
        at = rng.uniform(0, seconds - 1.5)
        call = _bird()
        start = int(at * SR)
        out[start : start + len(call)] += _pan(call, rng.uniform(-0.8, 0.8))
    fade = int(4 * SR)
    # Crossfade the end into the start so the loop point is inaudible.
    ramp = np.linspace(0, 1, fade)[:, None]
    out[:fade] = out[:fade] * ramp + out[-fade:] * (1 - ramp)
    return out[:-fade]


def _bird():
    notes = []
    base = rng.uniform(1700, 2400)
    for k in range(rng.integers(2, 5)):
        t = _t(rng.uniform(0.07, 0.14))
        f = base * (1 + 0.25 * np.sin(np.pi * t / t[-1])) * rng.uniform(0.9, 1.1)
        notes.append(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]) ** 2)
        notes.append(np.zeros(int(rng.uniform(0.04, 0.09) * SR)))
    return np.concatenate(notes) * 0.012


# ---------------------------------------------------------------- water

# Its own generator, so adding water sounds never changes the music, bed or stone sounds above.
wrng = np.random.default_rng(31)


def _bubble(f0, seconds, rise):
    """A small bubble: a decaying sine whose pitch rises as it shrinks, as real bubbles do."""
    t = _t(seconds)
    f = f0 * (1 + rise * t / seconds)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 6 / seconds) * np.sin(np.pi * np.minimum(t / 0.004, 0.5))


def _slosh(seconds, cutoff):
    """One soft wave against the bank: low band-limited noise under a slow swell."""
    t = _t(seconds)
    n = wrng.standard_normal(len(t))
    body = _fft_lowpass(n, cutoff) - _fft_lowpass(n, 90)
    swell = np.sin(np.pi * t / seconds) ** 2 * np.exp(-t * 1.2 / seconds)
    return body / np.std(body) * swell


def lapping(seconds=16.0):
    n = int(seconds * SR)
    out = np.zeros(n)
    at = 0.0
    while at < seconds - 1.6:
        w = _slosh(wrng.uniform(0.9, 1.6), wrng.uniform(500, 850)) * wrng.uniform(0.5, 1.0)
        start = int(at * SR)
        out[start : start + len(w)] += w[: n - start]
        if wrng.random() < 0.6:
            b = _bubble(wrng.uniform(280, 520), wrng.uniform(0.05, 0.1), 0.4) * wrng.uniform(0.1, 0.25)
            bs = start + int(wrng.uniform(0.3, 0.8) * SR)
            out[bs : bs + len(b)] += b[: max(0, n - bs)]
        at += wrng.uniform(1.1, 2.3)
    fade = int(2 * SR)
    ramp = np.linspace(0, 1, fade)
    out[:fade] = out[:fade] * ramp + out[-fade:] * (1 - ramp)
    return _fft_lowpass(out[:-fade], 1400)


def water():
    fx = {}
    for i in range(3):
        x = _slosh(0.5, 900) * 0.6
        for k in range(wrng.integers(2, 4)):
            b = _bubble(wrng.uniform(330, 640), wrng.uniform(0.04, 0.09), 0.5) * wrng.uniform(0.3, 0.7)
            s = int(wrng.uniform(0.0, 0.2) * SR)
            x[s : s + len(b)] += b[: len(x) - s]
        fx[f"dip{i}"] = x
    for i in range(2):
        seconds = 2.4
        x = _slosh(seconds, 700) * 0.7
        for k in range(14):
            b = _bubble(wrng.uniform(220, 480), wrng.uniform(0.06, 0.14), 0.45) * wrng.uniform(0.15, 0.5)
            s = int(wrng.uniform(0.05, seconds - 0.4) ** 1.3 / seconds**0.3 * SR)
            x[s : s + len(b)] += b[: len(x) - s]
        fx[f"fill{i}"] = x
    return {k: _fft_lowpass(v, 1800) for k, v in fx.items()}


# ---------------------------------------------------------------- output

def write_ogg(path, x, quality=3):
    x = np.asarray(x)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    channels = 1 if x.ndim == 1 else x.shape[1]
    with tempfile.NamedTemporaryFile(suffix=".raw") as raw:
        raw.write(pcm.tobytes())
        raw.flush()
        subprocess.run(["oggenc", "-Q", "-r", "-B", "16", "-C", str(channels), "-R", str(SR), "-q", str(quality),
                        "-o", str(path), raw.name], check=True)


def main():
    music = ROOT / "music"
    music.mkdir(parents=True, exist_ok=True)
    manifest = []
    for i, s in enumerate(sections()):
        stems = s.render()
        mix = sum(stems.values())
        gain = 10 ** (-19 / 20) / np.sqrt((mix**2).mean())
        peak = np.abs(mix).max() * gain
        if peak > 0.9:
            gain *= 0.9 / peak
        name = f"{i:02d}-{s.name}"
        for stem, x in stems.items():
            write_ogg(music / f"{name}.{stem}.ogg", _fft_lowpass(x * gain, 6000))
        manifest.append({"name": name, "bpm": s.bpm, "beats": s.beats})
        print(f"music: {name} {s.beats * 60 / s.bpm:.1f} s at {s.bpm} bpm")
    (ROOT / "music.json").write_text(json.dumps(manifest, indent=1) + "\n")
    write_ogg(ROOT / "meadow.ogg", meadow(), 2)
    fx = ROOT / "fx"
    fx.mkdir(exist_ok=True)
    for name, x in effects().items():
        write_ogg(fx / f"{name}.ogg", x / np.abs(x).max() * 0.8)
    for name, x in water().items():
        write_ogg(fx / f"{name}.ogg", x / np.abs(x).max() * 0.6)
    lap = lapping()
    write_ogg(ROOT / "lap.ogg", lap / np.abs(lap).max() * 0.6, 2)
    print(f"audio: {ROOT}")


if __name__ == "__main__":
    sys.exit(main())
