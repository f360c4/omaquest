#!/usr/bin/env python3
"""Generate the plugin's audio from code, the way the sprites are text.

Everything under assets/sounds/ comes out of this file. Nothing was recorded,
nothing was downloaded, and there is no sample in the repository whose origin
somebody has to take on trust — which matters for a plugin that runs
unsandboxed inside somebody's shell, and is the same reason the sprites are
plain-text grids.

    python3 tools/make-sounds.py

A plucked string, not a chiptune. The first version was square waves and noise
percussion and it sounded like an arcade cabinet — which is a fine sound and
the wrong one for a game about a chronicle, a realm and a bard. This is
Karplus-Strong: a burst of noise run through a short delay line, which is what
a plucked string actually is, and about fifteen lines of arithmetic.

Slow, modal, and quiet enough to sit under a fight rather than over it.

Two things make the difference between "a beep" and "an instrument", and the
first version had neither: sample rate, so the high partials of a pluck are not
aliased into grit, and a room. Everything here goes through a small reverb at
the end — a handful of delayed, quieter copies — because a note with no space
around it sounds like a circuit and a note with space sounds like a string in
a hall.
"""

import math
import pathlib
import struct
import wave

RATE = 22050
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "sounds"

# Equal temperament from A4, by semitones.
def hz(semitones_from_a4):
    return 440.0 * (2.0 ** (semitones_from_a4 / 12.0))


NOTE = {
    "A2": hz(-24), "B2": hz(-22), "C3": hz(-21), "D3": hz(-19), "E3": hz(-17),
    "F3": hz(-16), "G3": hz(-14), "A3": hz(-12), "B3": hz(-10),
    "C4": hz(-9), "D4": hz(-7), "E4": hz(-5), "F4": hz(-4), "G4": hz(-2),
    "A4": hz(0), "B4": hz(2), "C5": hz(3), "D5": hz(5), "E5": hz(7),
    "F5": hz(8), "G5": hz(10), "A5": hz(12),
}


def reverb(samples, mix=0.34):
    """A small hall: four delays, each quieter and slightly detuned in length.

    Not a good reverb — a good one needs all-pass chains and diffusion. This
    is four comb delays, which is enough to stop a plucked note sounding like
    it was recorded inside a matchbox.
    """
    taps = [(int(RATE * 0.037), 0.42), (int(RATE * 0.053), 0.31),
            (int(RATE * 0.071), 0.23), (int(RATE * 0.097), 0.16)]
    tail = int(RATE * 0.35)
    out = list(samples) + [0.0] * tail

    for delay, gain in taps:
        for i in range(len(samples)):
            target = i + delay
            if target < len(out):
                out[target] += samples[i] * gain * mix
    return out


def pluck(frequency, duration, volume=0.22, damping=0.498):
    """Karplus-Strong: a lute, near enough.

    Fill a buffer one wavelength long with noise, then walk it averaging each
    pair and feeding the result back. The averaging is a low-pass filter, so
    the high partials die first and what is left decays like a string.
    """
    total = int(RATE * duration)
    length = max(2, int(RATE / frequency))

    buffer = []
    state = 0x1F123BB5
    for _ in range(length):
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        buffer.append(((state >> 16) / 32768.0) - 1.0)

    out = []
    index = 0
    for i in range(total):
        value = buffer[index]
        out.append(value * volume)
        buffer[index] = (buffer[index] + buffer[(index + 1) % length]) * damping
        index = (index + 1) % length

    # A gentler attack than a raw noise burst, which is what made the first
    # version sound struck rather than plucked.
    attack = max(1, int(RATE * 0.004))
    for i in range(min(attack, total)):
        out[i] *= i / attack

    # And a long release, so a note cut off mid-decay does not click.
    edge = max(1, int(RATE * 0.04))
    for i in range(min(edge, total)):
        out[total - 1 - i] *= i / edge
    return out


def drone(frequency, duration, volume=0.05):
    """A sine, very quiet, under everything. The room the tune is played in."""
    total = int(RATE * duration)
    edge = max(1, int(RATE * 0.25))
    out = []
    for i in range(total):
        value = volume * math.sin(2 * math.pi * frequency * i / RATE)
        if i < edge:
            value *= i / edge
        elif i > total - edge:
            value *= (total - i) / edge
        out.append(value)
    return out


def silence(duration):
    return [0.0] * int(RATE * duration)


def mix(*tracks):
    """Lay tracks over each other, padding to the longest."""
    length = max(len(t) for t in tracks)
    out = [0.0] * length
    for track in tracks:
        for i, value in enumerate(track):
            out[i] += value
    return out


def chain(*segments):
    out = []
    for segment in segments:
        out.extend(segment)
    return out


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        frames = bytearray()
        for value in samples:
            clipped = max(-1.0, min(1.0, value))
            frames += struct.pack("<h", int(clipped * 32767))
        handle.writeframes(bytes(frames))
    return path


# ---------------------------------------------------------------- the theme

# Twenty seconds in D minor at about 72, which is walking pace. It has to bear
# being heard once a fight for months, so it does nothing: no percussion, no
# resolution, no crescendo. A tune somebody is playing in the corner of the
# room while the fight happens.
BEAT = 60.0 / 64


def melody_line():
    phrase = [
        ("D4", 2), ("F4", 1), ("A4", 1),
        ("G4", 2), ("F4", 2),
        ("E4", 2), ("D4", 1), ("E4", 1),
        ("D4", 4),
        ("A4", 2), ("C5", 1), ("D5", 1),
        ("C5", 2), ("A4", 2),
        ("G4", 1), ("F4", 1), ("E4", 2),
        ("D4", 4),
    ]
    out = []
    for note, beats in phrase:
        out.extend(pluck(NOTE[note], BEAT * beats, 0.20))
    return out


def counter_line():
    """A lower voice answering on the off-beats, sparse enough to notice."""
    phrase = [
        (None, 2), ("D3", 2),
        (None, 2), ("A3", 2),
        (None, 2), ("F3", 2),
        (None, 2), ("D3", 2),
        (None, 2), ("F3", 2),
        (None, 2), ("E3", 2),
        (None, 2), ("D3", 2),
        (None, 4),
    ]
    out = []
    for note, beats in phrase:
        duration = BEAT * beats
        out.extend(silence(duration) if note is None else pluck(NOTE[note], duration, 0.11))
    return out


def drone_line():
    total = sum(beats for _, beats in [
        ("D4", 2), ("F4", 1), ("A4", 1), ("G4", 2), ("F4", 2),
        ("E4", 2), ("D4", 1), ("E4", 1), ("D4", 4),
        ("A4", 2), ("C5", 1), ("D5", 1), ("C5", 2), ("A4", 2),
        ("G4", 1), ("F4", 1), ("E4", 2), ("D4", 4),
    ])
    half = total / 2
    return chain(drone(NOTE["D3"], BEAT * half, 0.045),
                 drone(NOTE["A2"], BEAT * half, 0.045))


def harmony_line():
    """A third above, quieter, entering only on the second half of the phrase.

    One voice for twenty seconds is a tune; two voices, one of them arriving
    late, is a piece of music. It is the cheapest thing in this file and the
    one that does the most.
    """
    phrase = [
        (None, 4), (None, 4), (None, 4), (None, 4),
        ("C5", 2), ("E5", 1), ("F5", 1),
        ("E5", 2), ("C5", 2),
        (None, 4),
        ("F4", 4),
    ]
    out = []
    for note, beats in phrase:
        duration = BEAT * beats
        out.extend(silence(duration) if note is None else pluck(NOTE[note], duration, 0.10))
    return out


def battle_theme():
    return reverb(mix(melody_line(), counter_line(), harmony_line(), drone_line()), 0.40)


# ---------------------------------------------------------------- the cues

def hit():
    return reverb(pluck(NOTE["D3"], 0.22, 0.17), 0.30)


def crit():
    return reverb(chain(pluck(NOTE["A3"], 0.10, 0.18), pluck(NOTE["D4"], 0.30, 0.18)), 0.34)


def hurt():
    return reverb(chain(pluck(NOTE["C3"], 0.10, 0.15), pluck(NOTE["B2"], 0.34, 0.13)), 0.30)


def victory():
    return reverb(chain(
        pluck(NOTE["D4"], 0.16, 0.19),
        pluck(NOTE["F4"], 0.16, 0.19),
        pluck(NOTE["A4"], 0.16, 0.19),
        mix(pluck(NOTE["D5"], 0.90, 0.19), drone(NOTE["D3"], 0.90, 0.05)),
    ), 0.42)


def defeat():
    return reverb(chain(
        pluck(NOTE["A3"], 0.20, 0.16),
        pluck(NOTE["F3"], 0.20, 0.16),
        mix(pluck(NOTE["D3"], 1.00, 0.15), drone(NOTE["D3"], 1.00, 0.05)),
    ), 0.42)


def found():
    """The hero comes back from a walk with something."""
    return reverb(chain(pluck(NOTE["A4"], 0.12, 0.16), pluck(NOTE["D5"], 0.40, 0.16)), 0.34)


def level_up():
    return reverb(chain(
        pluck(NOTE["D4"], 0.14, 0.19),
        pluck(NOTE["A4"], 0.14, 0.19),
        pluck(NOTE["D5"], 0.14, 0.19),
        mix(pluck(NOTE["F5"], 1.00, 0.19), drone(NOTE["D4"], 1.00, 0.05)),
    ), 0.42)


SOUNDS = {
    "battle_theme.wav": battle_theme,
    "hit.wav": hit,
    "crit.wav": crit,
    "hurt.wav": hurt,
    "victory.wav": victory,
    "defeat.wav": defeat,
    "found.wav": found,
    "level_up.wav": level_up,
}


def main():
    total = 0
    for name, build in SOUNDS.items():
        path = write(name, build())
        size = path.stat().st_size
        total += size
        print(f"  {name:<20} {size / 1024:7.1f} KiB")
    print(f"  {'total':<20} {total / 1024:7.1f} KiB")


if __name__ == "__main__":
    main()
