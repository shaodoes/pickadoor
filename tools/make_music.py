"""Composes the Pickadoor lobby theme: a slow, melancholic piano-and-strings loop.

    python tools/make_music.py            -> assets/audio/lobby_theme.wav (+ .mp3 via ffmpeg)

Everything is synthesised with numpy (no samples, no third-party music), so the track is original.
Mood target: sparse minor-key piano over a cold string pad, slow, room-sized reverb, seamless loop.
"""
import math
import os
import subprocess

import numpy as np

SR = 44100
BPM = 58
BEAT = 60 / BPM
BAR = 4 * BEAT
BARS = 16  # ~66 s loop
LENGTH = BARS * BAR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")

rng = np.random.default_rng(7)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


# ---------------------------------------------------------------- instruments
def piano(freq, dur, vel=0.8):
    """Additive piano-ish tone: decaying harmonics, slight inharmonicity, soft hammer."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(1, 9):
        amp = vel * (0.6 ** (k - 1)) / k ** 0.3
        decay = 0.9 + 0.45 * k  # upper partials die faster
        inharm = 1 + 0.0004 * k * k
        out += amp * np.exp(-t * decay) * np.sin(2 * math.pi * freq * k * inharm * t)
    # a soft felt thump, not a click: short, quiet, and low-passed
    hammer = rng.standard_normal(n) * np.exp(-t * 120) * 0.012 * vel
    hammer = np.convolve(hammer, np.ones(24) / 24, mode="same")
    env = np.minimum(1, t * 400)  # 2.5 ms attack
    out = (out + hammer) * env * np.exp(-t * 0.35)
    return out


def strings(freq, dur, vel=0.25):
    """Detuned band-limited saws through a slow swell; reads as a cold string section."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for det in (-0.35, 0.0, 0.4):
        f = freq * 2 ** (det / 1200)
        # vibrato must be integrated into the phase, or it becomes a chirp that sweeps the note
        vib = 1 + 0.0025 * np.sin(2 * math.pi * 4.7 * t + rng.uniform(0, 6))
        phase = 2 * math.pi * np.cumsum(f * vib) / SR
        for k in range(1, 12):
            out += (1 / k) * np.sin(phase * k) * (0.5 ** (k / 3))
    attack = np.clip(t / 1.6, 0, 1) ** 2
    release = np.clip((dur - t) / 1.2, 0, 1)
    return out * vel * attack * release / 3


def sub(freq, dur, vel=0.18):
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.clip(t / 0.5, 0, 1) * np.clip((dur - t) / 0.8, 0, 1)
    return vel * env * np.sin(2 * math.pi * freq * t)


# ---------------------------------------------------------------- composition
# D minor. Progression per bar: i - VI - III - VII (Dm Bb F C), then i - iv - VI - V (Dm Gm Bb A)
D, E, F_, G, A, Bb, C = 62, 64, 65, 67, 69, 70, 72
CHORDS = [
    [D, F_, A], [Bb, D + 12, F_ + 12], [F_, A, C + 12], [C, E, G],
    [D, F_, A], [G, Bb, D + 12], [Bb, D + 12, F_ + 12], [A, C + 12 + 1, E + 12],  # A major (C#) pulls home
]
BASS = [D - 24, Bb - 24, F_ - 24, C - 24, D - 24, G - 24, Bb - 24, A - 24]

# a sparse melody, one phrase per 4 bars, written in beats: (beat offset, midi, length in beats)
MELODY = [
    # phrase 1
    (0.0, A + 12, 2), (2.0, F_ + 12, 1.5), (3.5, E + 12, 2.5),
    (8.0, D + 12, 3), (11.0, C + 12, 1), (12.0, A, 4),
    # phrase 2 (answers, climbs)
    (16.0, A + 12, 1.5), (17.5, Bb + 12, 1.5), (19.0, A + 12, 2),
    (24.0, D + 24, 2), (26.0, C + 24, 2), (28.0, A + 12, 4),
    # phrase 3 (lower, tired)
    (32.0, F_ + 12, 2), (34.0, E + 12, 2), (36.0, D + 12, 4), (42.0, A, 2),
    # phrase 4 (leaves it unresolved, then the loop resolves it)
    (48.0, G + 12, 2), (50.0, F_ + 12, 2), (52.0, E + 12, 3), (56.0, C + 12 + 1, 4), (60.0, D + 12, 4),
]


def place(buf, signal, start_s):
    i = int(start_s * SR)
    j = min(len(buf), i + len(signal))
    if j > i:
        buf[i:j] += signal[: j - i]


def compose():
    n = int(LENGTH * SR)
    pianoL, pianoR = np.zeros(n), np.zeros(n)
    pad = np.zeros(n)
    low = np.zeros(n)

    for bar in range(BARS):
        chord = CHORDS[bar % len(CHORDS)]
        t0 = bar * BAR
        # strings: chord tones an octave down, held through the bar (overlapping into the next)
        for note in chord:
            place(pad, strings(midi(note - 12), BAR + 1.5, vel=0.22 if bar % 8 < 4 else 0.26), t0)
        place(low, sub(midi(BASS[bar % 8]), BAR + 0.3), t0)
        # piano: a slow broken chord, the roll slightly uneven like a human hand
        for k, note in enumerate(chord):
            delay = k * BEAT * 0.9 + rng.uniform(-0.02, 0.03)
            vel = 0.5 + rng.uniform(-0.08, 0.08) - 0.08 * k
            sig = piano(midi(note), BAR * 1.6, vel)
            pan = 0.35 + 0.3 * k / 2
            place(pianoL, sig * (1 - pan), t0 + delay)
            place(pianoR, sig * pan, t0 + delay)
        # bass note doubled quietly on the piano on beat 1
        sig = piano(midi(BASS[bar % 8] + 12), BAR * 1.8, 0.42)
        place(pianoL, sig * 0.55, t0)
        place(pianoR, sig * 0.45, t0)

    for beat, note, length in MELODY:
        sig = piano(midi(note), length * BEAT * 1.9, 0.78 + rng.uniform(-0.05, 0.05))
        place(pianoL, sig * 0.52, beat * BEAT + rng.uniform(-0.015, 0.015))
        place(pianoR, sig * 0.48, beat * BEAT + rng.uniform(-0.015, 0.015))

    # whole thing dips slightly in bars 8-11, swells into the final phrase
    env = np.ones(n)
    for bar in range(BARS):
        g = 1.0
        if 8 <= bar < 12:
            g = 0.85
        elif bar >= 12:
            g = 1.05
        i, j = int(bar * BAR * SR), int((bar + 1) * BAR * SR)
        env[i:j] = g
    # one-second moving average (cumsum form; a direct convolution here takes minutes)
    pad_n = SR // 2
    padded = np.concatenate([np.full(pad_n, env[0]), env, np.full(pad_n, env[-1])])
    csum = np.cumsum(np.insert(padded, 0, 0.0))
    env = (csum[SR:] - csum[:-SR])[: n] / SR

    left = (pianoL + pad * 0.9 + low) * env
    right = (pianoR + pad * 1.0 + low) * env
    return left, right


# ---------------------------------------------------------------- effects
def reverb(x, seconds=3.2, mix=0.32):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t * (6.9 / seconds))
    # darker tail: crude one-pole low-pass on the impulse
    for _ in range(2):
        ir = np.convolve(ir, [0.25, 0.5, 0.25], mode="same")
    ir[0] = 1.0
    ir /= np.sqrt(np.sum(ir * ir)) * 0.9
    wet = np.fft.irfft(np.fft.rfft(x, len(x) + n) * np.fft.rfft(ir, len(x) + n))[: len(x)]
    return x * (1 - mix) + wet * mix


def make_loop(x):
    """Fold the reverb tail that spills past the end back onto the start, so the loop is seamless."""
    n = int(LENGTH * SR)
    tail = x[n:]
    out = x[:n].copy()
    out[: len(tail)] += tail
    fade = int(0.03 * SR)
    ramp = np.linspace(0, 1, fade)
    out[:fade] *= ramp
    out[-fade:] *= ramp[::-1]
    return out


def soft_clip(x):
    return np.tanh(x * 1.1) / math.tanh(1.1)


def main():
    os.makedirs(OUT, exist_ok=True)
    left, right = compose()
    extra = int(4 * SR)
    left = np.concatenate([left, np.zeros(extra)])
    right = np.concatenate([right, np.zeros(extra)])
    left, right = reverb(left), reverb(right)
    left, right = make_loop(left), make_loop(right)
    stereo = np.stack([left, right], axis=1)
    stereo /= np.max(np.abs(stereo)) + 1e-9
    stereo = soft_clip(stereo * 0.9) * 0.85
    pcm = (stereo * 32767).astype(np.int16)

    wav = os.path.join(OUT, "lobby_theme.wav")
    import wave

    with wave.open(wav, "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())
    mp3 = os.path.join(OUT, "lobby_theme.mp3")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-b:a", "192k", mp3], check=False)
    print("wrote", wav, "and", mp3, f"({LENGTH:.1f}s loop)")


if __name__ == "__main__":
    main()
