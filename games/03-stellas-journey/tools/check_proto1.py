#!/usr/bin/env python3
"""Run prototype 1 headlessly and check it.

What has to hold, on every frame checked:

- TIMING. 262 lines, and no drawn line past its 76 cycles.
- STACK. The stack never reaches the variables.
- THE SUPERCHIP. The ROM is laid out so Stella and Gopher2600 see one,
  the lamps live in it, and nothing reads its write half.
- THE VIEW. Between 0 and 160. After the opening, the held character
  stays in view, or the view is on its way to it.
- THE PICTURE. Each frame is replayed from the TIA writes. A character
  is either drawn whole, every row of it that is in view and exactly
  the pixels of its picture (less any P0 covers: the TIA draws P0 over
  P1), or not drawn at all. Nothing else on
  screen is in a character's colour from a sprite. The held character
  is drawn on every frame it is in view (Flicker only on even frames).
  Flicker is never drawn on an odd frame.
- TURNS. A character in view that is left out is drawn again soon:
  the longest wait is reported, and fails past MAX_WAIT frames.

Scenes: power-on in each of the four banks, the opening, the cast
level on the ground (the worst case: one tenant a frame), the cast on
four different ledges (P1 hops twice), a character poking in at the top
of the view, and a soak of random input with characters dropped on
random ledges.

    python3 tools/check_proto1.py ROM SYM [--frames N] [--quiet]
"""
import argparse
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import picture as P  # noqa: E402
import vcs  # noqa: E402

NAMES = ["Stella", "Alex", "Marcus", "Flicker"]
MAX_WAIT = 6                   # frames a character in view may go undrawn


class Checks:
    def __init__(self, quiet):
        self.fails, self.n, self.quiet = [], 0, quiet

    def that(self, label, ok, detail=""):
        self.n += 1
        if not ok:
            self.fails.append(label)
        if not ok or not self.quiet:
            print(f"  {'ok  ' if ok else 'FAIL'}  {label}" + (f" - {detail}" if detail else ""))


class Proto:
    def __init__(self, rom, sym, bank=0):
        self.r = vcs.Run(rom, sym, bank)
        self.r.m.min_sp, self.r.m.tia_hits = 0xFF, 0   # the power-on clear isn't the stack
        self.sym, self.rom = sym, rom
        self.col = self.r.table("ColTbl", 4)
        self.width = self.r.table("WidthTbl", 4)
        self.height = self.r.table("HeightTbl", 4)
        self.nusiz = self.r.table("NusizTbl", 4)
        self.waits = [0] * 4
        self.max_wait = [0] * 4
        self.bad = []                          # (frame, what) for the picture
        self.timing = []                       # (frame, lines, late)

    def place(self, ci, x, top):
        r = self.r
        r.w("CharX", x, ci)
        r.w("CharY", top - self.height[ci], ci)
        for v in ("CharYLo", "CharVYHi", "CharVYLo", "SquashT"):
            r.w(v, 0, ci)
        r.w("OnGround", 1, ci)

    def step(self, look=False, **kw):
        r = self.r
        self.drawn_x = [r.r("CharX", i) for i in range(4)]   # input moves x after the drawing
        if not look:
            r.step_frame(**kw)
        else:
            srcs = []
            rows = P.render(P.frame(r, **kw), srcs)
            self.look(rows, srcs)
        lines, late = r.lines[-1], r.late[-1]
        if lines != 262 or late > 75:
            self.timing.append((r.frame, lines, late))

    def expected(self, ci):
        """{(row, x)} this character's picture covers, if it is drawn.
        Each du r is read on picture row 2r+3, the line after the one
        its sprite byte is written on, where the whole byte shows."""
        r = self.r
        top, h, x = r.r("DrawY", ci), r.r("DrawH", ci), self.drawn_x[ci]
        lo = r.r("GfxLo", ci)
        page = self.sym["GfxPage"] & 0xFF00
        scale = 2 if self.nusiz[ci] == 5 else 1
        out = set()
        for du in range(95):
            k = (du - top) & 0xFF
            if k >= h:
                continue
            g = self.rom[(page | lo) + k - 0xF000]
            for bit in range(8):
                if g >> (7 - bit) & 1:
                    for s in range(scale):
                        out.add((2 * du + 3, x + bit * scale + s))
        return out

    def look(self, rows, srcs):
        r = self.r
        f = r.frame
        odd = r.r("FrameCtr") & 1
        seen = {}
        for y in range(3, 192, 2):             # line 1 of each du
            for x, (c, s) in enumerate(zip(rows[y], srcs[y])):
                if s in (0, 1) and c in self.col:
                    seen.setdefault(self.col.index(c), set()).add((y, x))
        for ci in range(4):
            exp = self.expected(ci)
            got = seen.get(ci, set())
            in_view = bool(exp) and not (ci == 3 and odd)
            hidden = {(y, x) for y, x in exp - got if srcs[y][x] == 0 and rows[y][x] != self.col[ci]}
            exp = exp - hidden                 # under P0: the TIA draws P0 over P1
            if got and got != exp:
                self.bad.append((f, f"{NAMES[ci]} drawn wrong: {len(got - exp)} extra, "
                                    f"{len(exp - got)} missing pixels"))
            if ci == 3 and odd and got:
                self.bad.append((f, "Flicker drawn on an odd frame"))
            if ci == r.r("Active") and in_view and not got:
                self.bad.append((f, f"{NAMES[ci]}, held and in view, not drawn"))
            if in_view and not got:
                self.waits[ci] += 1
                self.max_wait[ci] = max(self.max_wait[ci], self.waits[ci])
            else:
                self.waits[ci] = 0

    def settle(self, active):
        """Skip the opening and put the view where it would come to rest
        on the held character."""
        r = self.r
        r.w("PanT", 0)
        r.w("CamStep", 3)
        r.w("Active", active)
        centre = r.r("CharY", active) + self.height[active] // 2
        r.w("ViewY", max(0, min(160, centre - 48)))

    def in_view(self, ci):
        r = self.r
        top = (r.r("CharY", ci) - r.r("ViewY")) & 0xFF
        return top < 96 or top + self.height[ci] > 256


def ledges(p):
    """(top, left, right) of every box in the room: anywhere to stand."""
    n = p.sym["ROOM_NB"]
    tops, left, right = (p.r.table(t, n) for t in ("BoxTop", "BoxL", "BoxR"))
    return list(zip(tops, left, right))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom")
    ap.add_argument("sym")
    ap.add_argument("--frames", type=int, default=3000)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    rom, sym = open(a.rom, "rb").read(), vcs.symbols(a.sym)
    c = Checks(a.quiet)
    ram_end = sym["RamEnd"]

    print("the Superchip")
    p = Proto(rom, sym)
    c.that("every bank's first 128 bytes repeat (how emulators tell)", p.r.m.superchip)
    c.that("code starts past the Superchip's 256 bytes", sym["ColdStart"] >= 0xF100,
           f"ColdStart ${sym['ColdStart']:04X}")
    for _ in range(40):
        p.step()
    lamps = [p.r.m.sc[i] for i in range(13)]
    c.that("the lamps are in it, and the kernel draws them", any(lamps) and
           sym["LampR"] == 0xF080, " ".join(f"{v:02X}" for v in lamps))

    print("power-on")
    for bank in range(4):
        p = Proto(rom, sym, bank)
        for _ in range(8):
            p.step()
        c.that(f"boots in bank {bank}", not p.timing[2:] and p.r.r("PanT") > 0,
               f"{p.timing[:3]}")

    print("the opening")
    p = Proto(rom, sym)
    hold = p.r.r("PanT")
    views = []
    for _ in range(hold + 120):
        p.step()
        views.append(p.r.r("ViewY"))
    c.that("holds on the homes at the top", all(v == 0 for v in views[:hold - 2]),
           f"{hold} frames")
    steps = [b - a for a, b in zip(views, views[1:]) if b != a]
    c.that("then pans down, two du a frame", steps and all(s == 2 for s in steps[:20]),
           f"{steps[:6]}")
    c.that("and comes to rest on the floor, Stella in view",
           views[-1] == 160 and p.in_view(0), f"ViewY {views[-1]}")
    c.that("every opening frame 262 lines, no late line", not p.timing, f"{p.timing[:3]}")

    print("the cast level on the ground (one sprite between three)")
    p = Proto(rom, sym)
    for ci, x in enumerate((20, 50, 90, 120)):
        p.place(ci, x, 248)
    p.settle(0)
    for _ in range(60):
        p.step()
    for _ in range(48):
        p.step(look=True)
    c.that("every character drawn whole or not at all", not p.bad, f"{p.bad[:2]}")
    c.that(f"nobody in view waits more than {MAX_WAIT} frames", max(p.max_wait) <= MAX_WAIT,
           ", ".join(f"{NAMES[i]} {w}" for i, w in enumerate(p.max_wait)))
    worst_level = p.max_wait[:]

    print("the cast on four ledges (P1 hops twice)")
    p = Proto(rom, sym)
    p.place(2, 60, 248)                                  # Marcus held, on the floor
    p.place(0, 70, 168)                                  # Stella on b21, poking in at the top
    p.place(1, 112, 184)                                 # Alex on b23 right
    p.place(3, 80, 200)                                  # Flicker on b25
    p.settle(2)
    for _ in range(60):
        p.step()
    hops = 0
    for _ in range(48):
        p.step(look=True)
        hops += p.r.r("Hop2") != 0xFF
    c.that("every character drawn whole or not at all", not p.bad, f"{p.bad[:2]}")
    c.that("all in view drawn every frame (Flicker every other)",
           max(p.max_wait) <= 1, ", ".join(f"{NAMES[i]} {w}" for i, w in enumerate(p.max_wait)))
    c.that("P1 hops twice on Flicker's frames", hops >= 20, f"{hops} of 48 frames")

    print("a character poking in at the top of the view")
    p = Proto(rom, sym)
    p.place(0, 30, 248)
    p.settle(0)
    for _ in range(60):
        p.step()
    view = p.r.r("ViewY")
    p.place(2, 100, view + 3)                            # Marcus: 3 of his 6 du show
    p.r.w("CharVYHi", 0, 2)
    p.r.w("OnGround", 0, 2)
    p.step(look=True)
    top = p.r.r("DrawY", 2)
    c.that("clipped at the top, drawn exactly", not p.bad and top >= 250,
           f"DrawY {top}, {p.bad[:1]}")

    print(f"soak: {a.frames} frames of random input, characters dropped on ledges")
    p = Proto(rom, sym)
    rng = random.Random(3)
    spots = ledges(p)
    lost, away = [], 0
    stick, hold_for = "", 0
    for f in range(a.frames):
        if f % 97 == 0:
            ci = rng.randrange(4)
            t, lo, hi = rng.choice(spots)
            if hi - lo >= p.width[ci]:
                p.place(ci, rng.randrange(lo, hi - p.width[ci] + 1), t)
        if hold_for == 0:
            stick = rng.choice(["", "L", "R", "L", "R", "D"])
            hold_for = rng.randrange(4, 40)
        hold_for -= 1
        fire = rng.random() < 0.08
        p.step(look=(f % 25 == 0), stick=stick, fire=fire)
        v = p.r.r("ViewY")
        if v > 160:
            lost.append((f, f"ViewY {v}"))
        away = away + 1 if p.r.r("PanT") == 0 and not p.in_view(p.r.r("Active")) else 0
        if away > 90:                                    # a teleport or a hand-over
            lost.append((f, f"{NAMES[p.r.r('Active')]} out of view, ViewY {v}"))
    print(f"  (picture checked on every 25th frame; deepest stack ${p.r.m.min_sp + 1:02X},"
          f" variables end at ${ram_end:02X})")
    for t, label in ((sym["VB_TIM"], "vertical blank"), (sym["OS_TIM"], "overscan")):
        left = p.r.m.margins.get(t, [])
        if left:
            print(f"  ({label}: at worst {min(left)} of {t} timer ticks to spare,"
                  f" {min(left) * 64 / 76:.1f} lines)")
    worst_late = max(p.r.late)
    print(f"  (the latest WSYNC in a drawn line lands on cycle {worst_late} of 75)")
    c.that("every frame 262 lines, no drawn line late", not p.timing,
           f"{len(p.timing)} bad, first {p.timing[:3]}")
    c.that("the stack stays clear of the variables", p.r.m.min_sp + 1 > ram_end and not p.r.m.tia_hits,
           f"lowest push ${p.r.m.min_sp + 1:02X}")
    c.that("nothing reads the Superchip's write half", not p.r.m.sc_bad_reads,
           f"{p.r.m.sc_bad_reads} reads")
    c.that("the view stays in the room and on the held character", not lost, f"{lost[:3]}")
    c.that("every character drawn whole or not at all", not p.bad, f"{p.bad[:2]}")

    print(f"\n{c.n - len(c.fails)} of {c.n} checks pass"
          f" (worst wait with the cast level: {max(worst_level)} frames)")
    sys.exit(1 if c.fails else 0)


if __name__ == "__main__":
    main()
