#!/usr/bin/env python3
"""Check prototype 2's mechanics: the static, riding Flicker, stacks that
move as one, and jumping off. (Its timing, the stack, the view and the
drawing are prototype 1's checks, run on this ROM as well: see `make`.)

Each scene places characters, holds one, plays the stick, and looks at
RAM and at pictures replayed from the TIA writes.

- THE STATIC is drawn: band 14 in its colour, about half lit, and the
  pattern moves.
- TOUCHING IT sends a character back to its last lamp.
- FLICKER goes through it, from the rung below to the rung above.
- RIDING: a character standing on Flicker moves with it, sideways and
  up, and goes through the static with it.
- ANY MEMBER DRIVES: holding the one on top walks the stack.
- FLICKER ON TOP: a stack with Flicker anywhere in it moves as one and
  goes through.
- JUMPING OFF inside the static sends the one who jumped back; and
  nobody jumps off a stack in mid-air.
- WITHOUT FLICKER nothing changes: a friend who walks away leaves you
  standing in the air, and you fall.
- A SOAK OF STACKS: random stacks with Flicker in them, under random
  input, every frame 262 lines and every 20th frame drawn exactly.
  The random soak in check_proto1.py rarely builds a stack, and stacks
  are where the time goes.

    python3 tools/check_proto2.py ROM SYM [--quiet]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import picture as P  # noqa: E402
import vcs  # noqa: E402
from check_proto1 import NAMES, Checks, Proto  # noqa: E402

STELLA, ALEX, MARCUS, FLICKER = range(4)
BELOW, ABOVE = 120, 104          # the rungs under and over the static (b15, b13)


class Scene(Proto):
    def __init__(self, rom, sym, held, view=None):
        super().__init__(rom, sym)
        self.held = held
        self.view = view

    def start(self):
        r = self.r
        r.w("PanT", 0)
        r.w("CamStep", 3)
        r.w("Active", self.held)
        top = r.r("CharY", self.held)
        r.w("ViewY", self.view if self.view is not None else max(0, min(160, top - 44)))
        r.w("BackN", 0)

    def on_head(self, rider, base, dx=0):
        """Put rider standing on base's head."""
        r = self.r
        self.place(rider, r.r("CharX", base) + dx, r.r("CharY", base))

    def run(self, frames, stick="", fire=False, look=False):
        for _ in range(frames):
            self.step(look=look, stick=stick, fire=fire)

    def jump(self, look=False):
        self.step(fire=True, look=look)
        self.step(look=look)

    def y(self, ci):
        return self.r.r("CharY", ci)

    def x(self, ci):
        return self.r.r("CharX", ci)

    def standing_on(self, ci, top):
        return self.y(ci) == top - self.height[ci] and self.r.r("OnGround", ci)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom")
    ap.add_argument("sym")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--stack-frames", type=int, default=2400)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    rom, sym = open(a.rom, "rb").read(), vcs.symbols(a.sym)
    c = Checks(a.quiet)
    spawn_x = Proto(rom, sym).r.table("SpawnX", 4)
    spawn_y = Proto(rom, sym).r.table("SpawnY", 4)

    print("the static")
    s = Scene(rom, sym, MARCUS)
    s.place(MARCUS, 70, ABOVE)                       # the view: bands 6-18
    s.start()
    s.run(3)
    patterns, lit, colour = set(), [], set()
    for _ in range(16):
        srcs = []
        rows = P.render(P.frame(s.r), srcs)
        y = 2 * (14 * 8 + 3 - s.r.r("ViewY")) + 3      # a line in the middle of band 14
        row = [(c_, src) for c_, src in zip(rows[y], srcs[y])]
        on = tuple(src == "PF" for _, src in row)
        patterns.add(on)
        lit.append(sum(on))
        colour |= {c_ for c_, src in row if src == "PF"}
    c.that("band 14 is drawn in the static's colour, and only that",
           colour == {sym["CORRUPT_COL"]}, f"{sorted(hex(v) for v in colour)}")
    c.that("about half of it lit, on every frame", all(56 <= n <= 104 for n in lit),
           f"{min(lit)}-{max(lit)} of 160 px")
    c.that("and the pattern moves", len(patterns) >= 3, f"{len(patterns)} patterns in 16 frames")
    c.that("every frame 262 lines", not s.timing, f"{s.timing[:2]}")

    print("touching it")
    s = Scene(rom, sym, STELLA)
    s.place(STELLA, 30, BELOW)
    s.start()
    s.run(2)
    s.jump()
    s.run(40)
    c.that("Stella jumps into it from the rung below and goes back to where she started",
           s.r.r("BackN") == 1 and s.x(STELLA) == spawn_x[STELLA] and s.y(STELLA) == spawn_y[STELLA],
           f"sent back {s.r.r('BackN')} times, now at x {s.x(STELLA)} y {s.y(STELLA)}")
    s.run(80)
    c.that("and the view follows her down", s.in_view(STELLA), f"ViewY {s.r.r('ViewY')}")

    print("Flicker")
    s = Scene(rom, sym, FLICKER)
    s.place(FLICKER, 48, BELOW)
    s.start()
    s.run(2)
    s.jump(look=True)
    s.run(40, look=True)
    c.that("goes through it, from the rung below to the rung above",
           s.standing_on(FLICKER, ABOVE) and s.r.r("BackN") == 0,
           f"y {s.y(FLICKER)}, sent back {s.r.r('BackN')}")
    c.that("drawn right all the way", not s.bad, f"{s.bad[:2]}")

    print("riding Flicker")
    s = Scene(rom, sym, FLICKER)
    s.place(FLICKER, 48, BELOW)
    s.on_head(STELLA, FLICKER, -1)
    s.start()
    s.run(3)
    c.that("Stella on Flicker's head is in its stack", s.r.r("Fused") == (1 << STELLA | 1 << FLICKER),
           f"Fused {s.r.r('Fused'):04b}, Stella on {s.r.r('OnHead', STELLA)}")
    x0 = s.x(STELLA), s.x(FLICKER)
    s.run(10, stick="L", look=True)                  # (the rung runs from 24 to 56)
    moved = s.x(STELLA) - x0[0], s.x(FLICKER) - x0[1]
    c.that("Flicker walks and Stella goes with it", moved[0] == moved[1] < 0, f"moved {moved}")
    s.run(10, stick="R", look=True)
    c.that("and back", (s.x(STELLA), s.x(FLICKER)) == x0, f"{(s.x(STELLA), s.x(FLICKER))} vs {x0}")
    s.jump(look=True)
    s.run(40, look=True)
    c.that("Flicker jumps through the static carrying her: both on the rung above",
           s.standing_on(FLICKER, ABOVE) and s.y(STELLA) == ABOVE - 4 - 9 and s.r.r("BackN") == 0,
           f"Flicker y {s.y(FLICKER)}, Stella y {s.y(STELLA)}, sent back {s.r.r('BackN')}")
    c.that("both drawn right all the way", not s.bad, f"{s.bad[:2]}")
    c.that("every frame 262 lines", not s.timing, f"{s.timing[:2]}")

    print("any member drives")
    s = Scene(rom, sym, STELLA)
    s.place(FLICKER, 48, BELOW)
    s.on_head(STELLA, FLICKER, -1)
    s.start()
    s.run(3)
    x0 = s.x(STELLA), s.x(FLICKER)
    s.run(10, stick="L")
    moved = s.x(STELLA) - x0[0], s.x(FLICKER) - x0[1]
    c.that("holding Stella, on top, walks the whole stack", moved[0] == moved[1] < 0, f"moved {moved}")

    print("Flicker on top")
    s = Scene(rom, sym, MARCUS)
    s.place(MARCUS, 48, BELOW)
    s.on_head(FLICKER, MARCUS, 1)
    s.start()
    s.run(3)
    c.that("Marcus carrying Flicker is one stack", s.r.r("Fused") == (1 << MARCUS | 1 << FLICKER),
           f"Fused {s.r.r('Fused'):04b}")
    s.jump(look=True)
    s.run(40, look=True)
    c.that("Marcus jumps through the static with Flicker on his head",
           s.standing_on(MARCUS, ABOVE) and s.y(FLICKER) == ABOVE - 6 - 4 and s.r.r("BackN") == 0,
           f"Marcus y {s.y(MARCUS)}, Flicker y {s.y(FLICKER)}, sent back {s.r.r('BackN')}")
    c.that("drawn right all the way", not s.bad, f"{s.bad[:2]}")

    print("jumping off inside the static")
    s = Scene(rom, sym, STELLA)
    s.place(FLICKER, 48, BELOW)
    s.on_head(STELLA, FLICKER, -1)
    s.start()
    s.run(3)
    head_in = s.y(STELLA) < 120 and s.y(STELLA) + 9 > 112
    c.that("riding Flicker on the rung under it, Stella's head is in the static already, unharmed",
           head_in and s.r.r("BackN") == 0, f"Stella y {s.y(STELLA)}, the static 112-119")
    s.jump()
    s.run(4)
    c.that("she jumps off there, and goes back to where she started",
           s.r.r("BackN") == 1 and s.x(STELLA) == spawn_x[STELLA] and s.y(STELLA) == spawn_y[STELLA],
           f"sent back {s.r.r('BackN')}, now x {s.x(STELLA)} y {s.y(STELLA)}")

    s = Scene(rom, sym, FLICKER)
    s.place(FLICKER, 48, BELOW)
    s.on_head(MARCUS, FLICKER, -1)
    s.start()
    s.run(3)
    s.step(fire=True)                              # one frame up: Marcus in the static
    inside = s.y(MARCUS)
    s.r.w("Active", MARCUS)
    s.r.w("FirePrev", 0x80)
    s.jump()
    s.run(40)
    c.that("Marcus can't jump off in mid-air: the stack carries him through",
           inside < 120 and inside + 6 > 112 and s.r.r("BackN") == 0
           and s.standing_on(FLICKER, ABOVE) and s.y(MARCUS) == ABOVE - 4 - 6,
           f"was at y {inside}; sent back {s.r.r('BackN')}, Flicker y {s.y(FLICKER)},"
           f" Marcus y {s.y(MARCUS)}")

    print("without Flicker")
    s = Scene(rom, sym, STELLA, view=160)
    s.place(STELLA, 40, 248)
    s.on_head(ALEX, STELLA, -4)
    s.start()
    s.run(3)
    ax = s.x(ALEX)
    c.that("Alex on Stella is not in a stack that moves", s.r.r("Fused") == 1 << FLICKER,
           f"Fused {s.r.r('Fused'):04b}")
    s.run(40, stick="R")
    c.that("Stella walks away; Alex stays where he was and falls to the floor",
           s.x(ALEX) == ax and s.standing_on(ALEX, 248), f"Alex x {ax} -> {s.x(ALEX)}, y {s.y(ALEX)}")

    print("a soak of stacks: Flicker carrying one, two, three, or carried")
    import random
    from check_proto1 import ledges
    rng = random.Random(a.seed)
    s = Scene(rom, sym, FLICKER)
    s.start()
    spots = [sp for sp in ledges(s) if sp[2] - sp[1] >= 16]
    shapes = 0
    os_left = []
    os_t = sym["OS_TIM"]
    for f in range(a.stack_frames):
        if f % 120 == 0:                             # a new stack on a random ledge
            top, lo, hi = rng.choice(spots)
            order = [FLICKER] + rng.sample([STELLA, ALEX, MARCUS], rng.randrange(1, 4))
            if rng.random() < 0.3:
                order[0], order[1] = order[1], order[0]  # Flicker carried
            for ci in set(range(4)) - set(order):    # the rest somewhere else
                t2, l2, h2 = rng.choice(spots)
                s.place(ci, rng.randrange(l2, h2 - s.width[ci] + 1), t2)
            s.place(order[0], rng.randrange(lo, hi - 15), top)
            for below, above in zip(order, order[1:]):
                s.on_head(above, below, 0)
            s.r.w("Active", rng.choice(order))
            shapes += 1
        stick = rng.choice(["", "", "L", "R", "D"])
        n0 = len(s.r.m.margins.get(os_t, []))
        s.step(look=(f % 20 == 0), stick=stick, fire=rng.random() < 0.05)
        if f % 120:
            os_left += s.r.m.margins.get(os_t, [])[n0:]
    # The frame a new stack is placed is the harness's, not the game's:
    # four characters land at once, which play can't arrange. Left out.
    real = [t for t in s.timing if t[0] % 120 not in (1,)]
    c.that(f"{shapes} stacks, {a.stack_frames:,} frames: every one 262 lines, no drawn line late",
           not real, f"{len(real)} bad, first {real[:3]}")
    c.that("every character drawn whole or not at all", not s.bad, f"{s.bad[:2]}")
    c.that("the stack stays clear of the variables",
           s.r.m.min_sp + 1 > sym["RamEnd"] and not s.r.m.tia_hits and not s.r.m.sc_bad_reads,
           f"lowest push ${s.r.m.min_sp + 1:02X}")
    print(f"  (vertical blank: at worst {min(s.r.m.margins[sym['VB_TIM']])} timer ticks spare;"
          f" overscan: at worst {min(os_left)}, leaving out the placement frames)")

    print(f"\n{c.n - len(c.fails)} of {c.n} checks pass")
    sys.exit(1 if c.fails else 0)


if __name__ == "__main__":
    main()
