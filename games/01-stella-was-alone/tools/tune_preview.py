#!/usr/bin/env python3
"""Render the tunes in src/tune.inc to WAV, to hear a draft before it
goes near a console.

This is an approximation of channel 1, not an emulation. It is the
same notes, the same steps, the same two-volume strike and the same
speed the ROM uses, on a plain square wave (pure tone, AUDC 12); the
old drone (TUNE 0) is drawn from the 4-bit polynomial AUDC 1 really
plays. What it leaves out is everything else the machine does: the
sound effects on channel 0, the TV speaker, and the buzz a real TIA
adds. Trust it for the notes and the rhythm; confirm the rest in
Stella, and on hardware. (tools/headless.py checks that the ROM really
plays the table this reads, on the grid this assumes.)

Usage: python3 tools/tune_preview.py [outdir] [--loops N] [--fast]

Writes tune<N>-<name>.wav for each tune, two loops by default, and
with --fast tune<N>-<name>-fast.wav as well: the tune as it plays
while the clock is low, when HURRY doubles the tempo.
"""
import os
import re
import sys
import wave
from array import array

RATE = 48000                    # samples per second
FRAME = 262 * 76 * 3 / 3579545  # one NTSC frame, in seconds
CLOCK = 30123.0                 # the TIA audio clock
NAMES = {0: "drone", 1: "lament", 2: "walk", 3: "hope"}


def value(b):
    """A DASM byte: 28 or $80."""
    b = b.strip()
    return int(b[1:], 16) if b.startswith("$") else int(b)


def parse(path):
    """tune number -> {"tempo", "strike", "hurry", "table"}, from the
    IF TUNE blocks of tune.inc (read top to bottom, never nested)."""
    tunes = {}
    cur = None                  # the tunes the open IF block covers
    filling = None              # the tunes whose table is being read
    hurry = 1
    for raw in open(path):
        line = raw.split(";", 1)[0].strip()
        if not line:
            continue
        m = re.match(r"IF TUNE\s*(=|>)\s*(\d+)$", line)
        if m:
            n = int(m.group(2))
            cur = [n] if m.group(1) == "=" else list(range(n + 1, max(NAMES) + 1))
            continue
        if line == "ENDIF":
            cur = filling = None
            continue
        m = re.match(r"(TEMPO|STRIKE|HURRY)\s*=\s*(\d+)$", line)
        if m:
            key, n = m.group(1).lower(), int(m.group(2))
            if key == "hurry":
                hurry = n
            for t in cur or []:
                tunes.setdefault(t, {})[key] = n
            filling = None
            continue
        m = re.match(r"(?:Tune|ArpOff):\s*(?:\.byte\s*(.*))?$", line)
        if m and cur:
            for t in cur:
                tunes.setdefault(t, {})["table"] = []
            filling = cur
            line = ".byte " + m.group(1) if m.group(1) else ""
        if line.startswith(".byte") and filling:
            for t in filling:
                tunes[t]["table"] += [value(b) for b in line[5:].split(",") if b.strip()]
            continue
        filling = None          # anything else ends a table
    for spec in tunes.values():
        spec.setdefault("hurry", hurry)
    return tunes


def step_seconds(spec, fast):
    """TEMPO is the number of right shifts the ROM does on the frame
    counter, so a step is 2**TEMPO frames - halved when HURRY doubles
    the counter under pressure."""
    return (1 << spec["tempo"]) * FRAME / (2 if fast else 1)


def drone_pitch(n):
    """AUDC 1: the 4-bit polynomial, clocked at CLOCK / (n + 1)."""
    s = [1, 0, 0, 0]            # x^4 + x^3 + 1, period 15
    for _ in range(11):
        s.append(s[-4] ^ s[-3])
    return s


def render(tune, spec, loops, fast):
    table = spec["table"]
    step = step_seconds(spec, fast)
    strike = int(round(spec.get("strike", 4) / (2 if fast else 1) * FRAME * RATE))
    out = array("h")
    for _ in range(loops):
        for b in table:
            if tune == 0:       # the drone: its own figure, on level 0
                n = 23 + b
                pat, hz, vol = drone_pitch(n), CLOCK / (n + 1), 2
            elif b & 0x80:
                pat, hz, vol = None, 0, 0
            else:
                pat, hz, vol = None, CLOCK / 2 / (b + 1), None
            count = int(round(step * RATE))
            chips_per_sample = hz / RATE
            phase = 0.0
            for i in range(count):
                v = vol
                if v is None:   # struck: loud for a while, then soft
                    v = 5 if i < strike else 2
                if hz == 0:
                    s = 0.0
                elif pat:
                    s = 1.0 if pat[int(phase) % 15] else -1.0
                else:
                    s = 1.0 if (phase % 1.0) < 0.5 else -1.0
                phase += chips_per_sample
                out.append(int(s * v / 15.0 * 24000))
    return out


def write(path, data):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    loops = int(args[1]) if len(args) > 1 else 2
    fast = "--fast" in sys.argv
    here = os.path.dirname(os.path.abspath(__file__))
    tunes = parse(os.path.join(here, "..", "src", "tune.inc"))
    outdir = args[0] if args else os.path.join(here, "..", "build", "tune-previews")
    os.makedirs(outdir, exist_ok=True)
    for tune in sorted(tunes):
        spec = tunes[tune]
        if len(spec["table"]) != (4 if tune == 0 else 32):
            sys.exit(f"tune {tune}: expected 32 steps, found {len(spec['table'])}")
        name = f"tune{tune}-{NAMES[tune]}"
        data = render(tune, spec, loops, False)
        write(os.path.join(outdir, name + ".wav"), data)
        print(f"{outdir}/{name}.wav: {len(spec['table'])} steps at "
              f"{step_seconds(spec, False) * 1000:.0f} ms, {len(data) / RATE:.1f} s")
        if fast and spec["hurry"]:
            data = render(tune, spec, loops, True)
            write(os.path.join(outdir, name + "-fast.wav"), data)
            print(f"{outdir}/{name}-fast.wav: {len(spec['table'])} steps at "
                  f"{step_seconds(spec, True) * 1000:.0f} ms, {len(data) / RATE:.1f} s")


if __name__ == "__main__":
    main()
