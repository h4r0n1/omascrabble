#!/usr/bin/env python3
"""Synthesizes the game's sound effects (original audio, no samples).

    python3 tools/gen-sounds.py

Writes short, quiet 22.05 kHz mono WAV files to assets/sounds/. Standard
library only. The output is deterministic (fixed noise seed), so re-running it
reproduces the same files.
"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.85 / peak
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))
    print(path, len(samples) / RATE, "s")


def env(t, attack, decay):
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / decay)


def tone(freqs, length, attack, decay, gains=None):
    n = int(length * RATE)
    gains = gains or [1.0] * len(freqs)
    out = []
    for i in range(n):
        t = i / RATE
        e = env(t, attack, decay)
        out.append(e * sum(g * math.sin(2 * math.pi * f * t) for f, g in zip(freqs, gains)))
    return out


def noise_burst(length, decay, rng, lowpass=0.35):
    n = int(length * RATE)
    out, y = [], 0.0
    for i in range(n):
        t = i / RATE
        y += lowpass * (rng.uniform(-1, 1) - y)
        out.append(y * math.exp(-t / decay))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] if i < len(t) else 0.0 for t in tracks) for i in range(n)]


def at(track, offset):
    return [0.0] * int(offset * RATE) + track


def main():
    rng = random.Random(1987)

    # Picking a tile up: a soft, dry tick.
    write("pickup", mix(noise_burst(0.05, 0.006, rng, 0.5), tone([2400], 0.05, 0.001, 0.008, [0.25])))

    # Setting a tile down on the board: a small wooden clack with a body.
    write("place", mix(noise_burst(0.09, 0.004, rng, 0.6),
                       tone([1650, 2900, 4100], 0.09, 0.0008, 0.018, [0.6, 0.3, 0.12])))

    # A valid move: two quiet notes, a fifth apart.
    write("valid", mix(tone([659.25, 1318.5], 0.32, 0.006, 0.09, [1, 0.2]),
                       at(tone([987.77, 1975.5], 0.3, 0.006, 0.1, [1, 0.15]), 0.07)))

    # A refused move: a low, muted thud that glides down.
    n = int(0.16 * RATE)
    thud, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (190 - 90 * t / 0.16) / RATE
        thud.append(math.sin(phase) * env(t, 0.004, 0.05))
    write("invalid", mix(thud, noise_burst(0.05, 0.01, rng, 0.15)))

    # A Scrabble: a quick rising arpeggio.
    notes = [523.25, 659.25, 783.99, 1046.5]
    write("bingo", mix(*[at(tone([f, f * 2], 0.32, 0.004, 0.11, [1, 0.25]), k * 0.075) for k, f in enumerate(notes)]))

    # The end of a won game: a soft major chord.
    write("victory", mix(tone([261.63, 329.63, 392.0, 523.25], 0.9, 0.05, 0.35, [0.7, 0.6, 0.55, 0.4]),
                         at(tone([1046.5], 0.5, 0.02, 0.2, [0.25]), 0.12)))


if __name__ == "__main__":
    main()
