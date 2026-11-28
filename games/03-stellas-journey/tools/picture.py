#!/usr/bin/env python3
"""Pictures of prototype 1, drawn from the ROM's own TIA writes.

tools/vcs.py runs the cartridge and logs every TIA write with the cycle
it lands on; render() replays that log onto a 160 x 192 picture. It
models the playfield (both halves, mirrored or repeated), both players
(position from RESPx and HMOVE, NUSIZ copies and double width, REFPx)
and the colour registers. It does not model missiles, the ball or
HMOVE's comb, and the colours are an approximate NTSC palette. render()
and save() are Game 2's tools/picture.py.

    python3 tools/picture.py ROM SYM OUTDIR
"""
import colorsys
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vcs  # noqa: E402

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


def render(log, srcs=None):
    """log: one frame of (cycle, register, value); -1 marks a line start.
    srcs, if a list, gets a row per row of the picture saying where each
    pixel came from: "BK", "PF", 0 (P0) or 1 (P1)."""
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
        line, sline = [], []
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
                sline.append(None)
                continue
            drawn = True
            col, src = reg[0x09], "BK"
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
                col, src = reg[0x08], "PF"
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
                            col, src = reg[0x06 + p], p
            line.append(col)
            sline.append(src)
        if drawn:
            rows.append(line)
            if srcs is not None:
                srcs.append(sline)
    if srcs is not None:
        del srcs[192:]
    return rows[:192]


def save(rows, path):
    width = min(160, max(len(line) for line in rows))   # a crop is narrower
    img = Image.new("RGB", (width * SCALE, len(rows) * SCALE))
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


def shot(r, path, frames=2):
    """Frames merged, keeping any coloured pixel: characters that take
    turns on P1 each show in one of them, as the eye blends them on a
    television. Every hue on screen is a character or a lamp (#27)."""
    rows = None
    for _ in range(frames):
        f = render(frame(r))
        if rows is None:
            rows = f
            continue
        rows = [[b if (a is None or not a >> 4) and b is not None and b >> 4 else a
                 for a, b in zip(la, lb)] for la, lb in zip(rows, f)]
    save(rows, path)


def main():
    rom_path, sym_path, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    rom, sym = open(rom_path, "rb").read(), vcs.symbols(sym_path)
    r = vcs.Run(rom, sym)
    for _ in range(4):
        r.step_frame()
    save(render(frame(r)), os.path.join(out, "1-homes.png"))       # the hold
    while r.r("PanT"):
        r.step_frame()
    for _ in range(40):
        r.step_frame()
    save(render(frame(r)), os.path.join(out, "2-mid-pan.png"))
    for _ in range(80):
        r.step_frame()
    shot(r, os.path.join(out, "3-the-cast.png"), frames=6)
    print("pictures in", out)


if __name__ == "__main__":
    main()
