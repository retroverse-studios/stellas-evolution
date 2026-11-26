#!/usr/bin/env python3
"""Screenshots from the ROM itself, for checking what the harness cannot
read out of RAM: whether the mid-frame P1 hop draws three characters
solid, and what the title's player count looks like.

tools/headless.py runs the cartridge and logs every TIA write with the
cycle it lands on; this replays that log onto a 160x192 picture. It
models the playfield (both halves, repeated or mirrored), both players
(position from RESPx and HMOVE, NUSIZ copies and double width, REFPx)
and the colour registers, which is all Game 2 draws with. It does not
model missiles, the ball or HMOVE's comb, and colours are an
approximate NTSC palette.

    python3 tools/picture.py ROM SYM OUTDIR

writes title-1p.png, title-2p.png and play-2p.png (two players with a
pair split vertically, so P1 hops) and play-1p.png.
"""
import colorsys
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import headless as H  # noqa: E402

SCALE = 3


def rgb(c):
    """Rough NTSC: hue 0 grey, hues 1-15 around the colour wheel."""
    hue, lum = c >> 4, (c & 0x0E) / 14
    v = 0.12 + 0.88 * lum
    if hue == 0:
        g = int(255 * lum)
        return (g, g, g)
    h = NTSC_HUE[hue]
    r, g, b = colorsys.hsv_to_rgb(h, 0.75 - 0.35 * lum, v)
    return (int(r * 255), int(g * 255), int(b * 255))


# hues 1-15 as a colour-wheel angle: gold, orange, red-orange, red,
# purple, ... blue ... green ... back to orange (near-NTSC, by eye)
NTSC_HUE = [0, .14, .08, .03, .97, .88, .78, .68, .62, .57, .50, .42, .33, .25, .18, .11]

COPIES = {0: [0], 1: [0, 16], 2: [0, 32], 3: [0, 16, 32], 4: [0, 64],
          5: [0], 6: [0, 32, 64], 7: [0]}
WIDTH = {5: 2, 7: 4}


def render(log):
    """log: one frame of (cycle, register, value); -1 marks a line start."""
    reg = [0] * 64
    reg[0x01] = 2                               # a frame starts in VBLANK
    new, old = [0, 0], [0, 0]                   # GRPx and its VDEL copy
    pos = [3, 3]
    marks = [c for c, r, _ in log if r == -1]
    starts = []                                 # a line every 76 cycles,
    for i, c in enumerate(marks):               # re-anchored at each WSYNC
        nxt = marks[i + 1] if i + 1 < len(marks) else c + 76
        while c < nxt:
            starts.append(c)
            c += 76
    # the picture begins at the first line drawn with VBLANK off
    rows = []
    events = [e for e in log if e[1] != -1]
    ei = 0
    for li, ls in enumerate(starts):
        line = []
        le = starts[li + 1] if li + 1 < len(starts) else ls + 76
        span = (le - ls) * 3                     # colour clocks in this line
        cc_events = []
        while ei < len(events) and events[ei][0] < le:
            c, r, v = events[ei]
            cc_events.append(((c - ls) * 3, r, v))
            ei += 1
        k = 0
        drawn = False
        for cc in range(0, min(span, 228)):
            while k < len(cc_events) and cc_events[k][0] <= cc:
                _, r, v = cc_events[k]
                k += 1
                reg[r] = v
                if r == 0x1B:                    # GRP0: P1's delayed copy
                    new[0], old[1] = v, new[1]   # takes P1's pending byte
                elif r == 0x1C:
                    new[1], old[0] = v, new[0]
                if r in (0x10, 0x11):            # RESP0 / RESP1
                    pos[r - 0x10] = 3 if cc < 68 else (cc - 68 + 5) % 160
                elif r == 0x2A:                  # HMOVE
                    for p, hm in ((0, 0x20), (1, 0x21)):
                        d = reg[hm] >> 4
                        d = d - 16 if d > 7 else d
                        pos[p] = (pos[p] - d) % 160
                elif r == 0x2B:
                    reg[0x20] = reg[0x21] = 0
            if cc < 68:
                continue
            x = cc - 68
            if reg[0x01] & 2:
                line.append(None)
                continue
            drawn = True
            col = reg[0x09]
            # playfield
            half, px = divmod(x, 80)
            b = px // 4
            if half and reg[0x0A] & 1:
                b = 19 - b
            if b < 4:
                on = reg[0x0D] >> (4 + b) & 1
            elif b < 12:
                on = reg[0x0E] >> (11 - b) & 1
            else:
                on = reg[0x0F] >> (b - 12) & 1
            if on:
                col = reg[0x08]
            for p in (1, 0):                     # P0 drawn last: it wins
                nus = reg[0x04 + p] & 7
                w = WIDTH.get(nus, 1)
                for off in COPIES[nus]:
                    d = (x - pos[p] - off) % 160
                    if d < 8 * w:
                        bit = d // w
                        if reg[0x0B + p] & 8:
                            bit = 7 - bit
                        g = old[p] if reg[0x25 + p] & 1 else new[p]
                        if g >> (7 - bit) & 1:
                            col = reg[0x06 + p]
            line.append(col)
        if drawn:
            rows.append(line)
    return rows[:192]


def save(rows, path):
    img = Image.new("RGB", (160 * SCALE, len(rows) * SCALE))
    px = img.load()
    for y, line in enumerate(rows):
        for x, c in enumerate(line[:160]):
            colour = rgb(c) if c is not None else (0, 0, 0)
            for dy in range(SCALE):
                for dx in range(SCALE):
                    px[x * SCALE + dx, y * SCALE + dy] = colour
    img.save(path)


def frame(r, **kw):
    """One frame's TIA log, VSYNC to VSYNC."""
    r.m.tia_log = []
    r.step_frame(**kw)
    log, r.m.tia_log = r.m.tia_log, None
    return log


def main():
    rom_path, sym_path, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    rom, sym = open(rom_path, "rb").read(), H.symbols(sym_path)
    r = H.Run(rom, sym)
    H.settle(r, 20)
    save(render(frame(r)), os.path.join(out, "title-1p.png"))
    H.press(r, select=True)
    save(render(frame(r)), os.path.join(out, "title-2p.png"))
    H.press(r, fire0=True)
    while r.r("State") != sym["STATE_PLAY"]:
        H.press(r, fire0=True)
    H.settle(r, 40)
    for _ in range(25):                         # joystick 2 walks Alex left,
        r.step_frame(stick1="L")               # joystick 1 jumps Stella
    r.step_frame(fire0=True)
    for _ in range(6):
        r.step_frame()
    log = frame(r)
    print(f"play-2p: RepoDU {r.r('RepoDU')} (255 = no hop), Active {r.r('Active')}, "
          f"Active2 {r.r('Active2')}, y {[r.r('CharY', i) for i in range(3)]}")
    save(render(log), os.path.join(out, "play-2p.png"))
    log2 = frame(r)
    save(render(log2), os.path.join(out, "play-2p-next.png"))
    H.press(r, reset=True)
    H.press(r, select=True)                     # two -> endless one
    save(render(frame(r)), os.path.join(out, "title-endless.png"))
    H.press(r, select=True)                     # -> endless two
    H.press(r, select=True)                     # -> the story, one player
    H.press(r, fire0=True)
    while r.r("State") != sym["STATE_PLAY"]:
        H.press(r, fire0=True)
    H.settle(r, 40)
    save(render(frame(r)), os.path.join(out, "play-1p.png"))
    # the score screens, reached as the game reaches them: an endless
    # run's clock runs out (State can't be poked at a frame boundary:
    # bank 0 has already chosen its bank by the VSYNC that starts one)
    H.press(r, reset=True)
    H.press(r, select=True)                     # -> endless one
    H.press(r, fire0=True)
    while r.r("State") != sym["STATE_PLAY"]:
        r.step_frame()
    r.w("Mode", 0x80 | 14)
    r.w("RunLo", 312 & 255)
    r.w("RunHi", 312 >> 8)
    r.w("TimerSec", 0)
    while r.r("State") != sym["STATE_SCORE"]:
        r.step_frame()
    H.settle(r, 2)
    save(render(frame(r)), os.path.join(out, "score-endless.png"))
    r.w("Mode", 0)                              # the story's layout
    H.settle(r, 2)
    save(render(frame(r)), os.path.join(out, "score-story.png"))

if __name__ == "__main__":
    main()
