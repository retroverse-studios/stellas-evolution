#!/usr/bin/env python3
"""Build-time solvability check for Stella Was Together's real floors.

The workbench's prototype toggle/wrap/portal floors (T1-T3, W1, P1, WP1)
were removed from the shipped game — their proofs live in the
`game2-workbench` git tag. This solver proves the REAL floors the game
plays in order. So far that is Act 1 Floor 1 "Together Again".

Floor 1 is a single-world, three-character floor with wrap edges. Its
proof (check_floor1) re-implements each character's exact fixed-point
physics (ported byte-for-byte from Game 1's proven check_levels.py) and,
using a friend's reachable footing as a stepstool (add_helpers), proves:

  (a) every character can stand on its own home ledge (solvable), and
  (b) the cooperation is GENUINELY required — at least one character
      cannot reach its home alone — so the "not alone" beat is real, not
      decorative, and (c) a working exit order exists (>= 2 characters
      can finish alone, so a booster is always available to help).

`make` fails if any of these breaks. Adding a floor adds its record +
home table to src/main.asm and, for a three-character floor, is proved
here automatically once its FloorRec/FloorHomeCharY are wired in.

Usage: python3 tools/check_levels.py build/stella-was-together.bin \
                build/main.sym src/main.asm
"""
import re
import sys

NUM_BOXES = 6
ROM_BASE = 0xF000


def load(bin_path, sym_path, asm_path):
    rom = open(bin_path, "rb").read()
    syms = {}
    for line in open(sym_path):
        m = re.match(r"^(\S+)\s+([0-9a-f]{4})", line.strip())
        if m:
            syms[m.group(1)] = int(m.group(2), 16)

    asm = open(asm_path).read()

    grav = int(re.search(r"GRAV_LO\s*=\s*\$([0-9a-fA-F]+)", asm).group(1), 16)
    min_x = int(re.search(r"MIN_X\s*=\s*(\d+)", asm).group(1))
    maxfall = int(re.search(r"MAXFALL\s*=\s*(\d+)", asm).group(1))
    wrap_w = int(re.search(r"WRAP_W\s*=\s*(\d+)", asm).group(1))
    wrap_hi = int(re.search(r"WRAP_HI\s*=\s*(\d+)", asm).group(1))
    num_chars = int(re.search(r"NUM_CHARS\s*=\s*(\d+)", asm).group(1))
    num_floors = int(re.search(r"NUM_FLOORS\s*=\s*(\d+)", asm).group(1))

    def u8n(name, n):     # first n bytes of a table (per-character arrays)
        base = syms[name] - ROM_BASE
        return list(rom[base:base + n])

    phys = {
        "grav": grav, "min_x": min_x, "maxfall": maxfall,
        "wrap_w": wrap_w, "wrap_hi": wrap_hi,
        "h3": u8n("HeightTbl", num_chars), "w3": u8n("WidthTbl", num_chars),
        "spd3": u8n("SpeedTbl", num_chars), "maxx3": u8n("MaxXTbl", num_chars),
        "jhi3": u8n("JumpHiTbl", num_chars), "jlo3": u8n("JumpLoTbl", num_chars),
    }

    def floor_wrap(f):
        base = syms["FloorWrapTbl"] - ROM_BASE
        return rom[base + f]

    def load_three_char_floor(f, rec_name, home_name):
        """A single-world, three-character floor: boxes at record+36,
        spawns at record+60, per-character home CharY in home_name, all
        three homes on the centred 8px column (px 76-83)."""
        rec = syms[rec_name] - ROM_BASE
        boxes = list(rom[rec + 36:rec + 60])      # 6 tops,bots,lefts,rights
        sp = list(rom[rec + 60:rec + 66])         # SX,SY,AX,AY,MX,MY
        return {
            "idx": f,
            "boxes": boxes,
            "wrap": floor_wrap(f),
            "spawns": [(sp[0], sp[1]), (sp[2], sp[3]), (sp[4], sp[5])],
            "homeY": u8n(home_name, num_chars),
            "home_l": 76, "home_r": 84,
        }

    # The shipped floor table, in play order. Extend this list as floors
    # are added (record label + home-table label).
    floor_defs = [
        ("Floor1Rec", "Floor1HomeCharY"),
    ]
    floors = []
    for f in range(num_floors):
        rec_name, home_name = floor_defs[f]
        floors.append(load_three_char_floor(f, rec_name, home_name))
    return floors, phys, num_chars


class Char1:
    """One character's physics on a single-world floor, with optional
    helper HEAD surfaces (the stacking beat). A port of Game 1's proven
    per-character solver, adapted to Game 2's three characters, one-way
    ledges and wrap edges. Vertical is 16-bit 8.8; x is integer."""

    def __init__(self, boxes, phys, ci, wrap):
        self.tops = boxes[0:6]
        self.bots = boxes[6:12]
        self.lefts = boxes[12:18]
        self.rights = boxes[18:24]
        self.h = phys["h3"][ci]
        self.w = phys["w3"][ci]
        self.spd = phys["spd3"][ci]
        self.maxx = phys["maxx3"][ci]
        j = (phys["jhi3"][ci] << 8) | phys["jlo3"][ci]
        self.jump = j - 0x10000 if j & 0x8000 else j
        self.grav = phys["grav"]
        self.maxfall = phys["maxfall"] << 8
        self.min_x = phys["min_x"]
        self.wrap = wrap
        self.wrap_w = phys["wrap_w"]
        self.wrap_hi = phys["wrap_hi"]
        self.extra = []            # (top, left, right) helper head surfaces

    def clamp_x(self, x, new_x, y, direction):
        cyh = y + self.h
        new_x &= 0xFF
        for i in range(NUM_BOXES - 1, -1, -1):
            top, bot = self.tops[i], self.bots[i]
            if bot == top:
                continue
            if bot <= y or top >= cyh:
                continue
            l, r = self.lefts[i], self.rights[i]
            if new_x >= r or new_x + self.w <= l:
                continue
            new_x = ((l - self.w) & 0xFF) if direction > 0 else r
        if self.wrap:
            if new_x >= self.wrap_hi:
                new_x = (new_x + self.wrap_w) & 0xFF
            elif new_x >= self.wrap_w:
                new_x = (new_x - self.wrap_w) & 0xFF
            return new_x
        if new_x < self.min_x:
            new_x = self.min_x
        if new_x >= self.maxx:
            new_x = self.maxx
        return new_x

    def surfaces(self):
        for i in range(NUM_BOXES - 1, -1, -1):
            if self.tops[i] != 0xFF:
                yield (self.tops[i], self.lefts[i], self.rights[i])
        yield from self.extra      # friends' heads, after every box

    def solids(self):
        for i in range(NUM_BOXES - 1, -1, -1):
            if self.tops[i] != 0xFF and self.bots[i] != self.tops[i]:
                yield (self.tops[i], self.bots[i], self.lefts[i], self.rights[i])

    def landing(self, prev_feet, new_feet, x):
        for top, l, r in self.surfaces():
            if prev_feet <= top <= new_feet and x < r and x + self.w > l:
                return top
        return None

    def arc(self, x, feet, jump, direction):
        y256 = (feet - self.h) << 8
        vy = self.jump if jump else 0
        for _ in range(600):
            if direction:
                x = self.clamp_x(x, x + direction * self.spd,
                                 y256 >> 8, direction)
            prev_feet = (y256 >> 8) + self.h
            vy = min(vy + self.grav, self.maxfall)
            y256 += vy
            if y256 < 0:
                y256, vy = 0, 0
            y = y256 >> 8
            if y > 120:
                return None
            if vy < 0:
                prev_top = prev_feet - self.h
                for top, bot, l, r in self.solids():
                    if prev_top >= bot > y and x < r and x + self.w > l:
                        y256, vy = bot << 8, 0
                        y = bot
                        break
            else:
                top = self.landing(prev_feet, y + self.h, x)
                if top is not None:
                    return (x, top)
        return None

    def footing(self, start):
        """BFS over standing states; returns {feet: set(x)}."""
        sx, sy = start
        seen, stack, foot = set(), [(sx, sy + self.h)], {}
        while stack:
            x, feet = stack.pop()
            if (x, feet) in seen:
                continue
            seen.add((x, feet))
            foot.setdefault(feet, set()).add(x)
            for d in (-1, 1):      # walk one step
                nx = self.clamp_x(x, x + d * self.spd, feet - self.h, d)
                if nx != x:
                    if self.landing(feet, feet, nx) is not None:
                        stack.append((nx, feet))
                    else:
                        land = self.arc(x, feet, False, d)
                        if land is not None:
                            stack.append(land)
            for d in (-1, 0, 1):   # jump left / straight / right
                land = self.arc(x, feet, True, d)
                if land is not None:
                    stack.append(land)
        return foot

    def can_home(self, start, home_feet, home_l, home_r):
        for feet, xs in self.footing(start).items():
            if feet != home_feet:
                continue
            for x in xs:
                if x < home_r and x + self.w > home_l:
                    return True
        return False


def add_helpers(sim, helpers):
    """Give `sim` static head surfaces over each helper's reachable
    footing — one surface per contiguous run of standable x (gap
    tolerance = the helper's stride), exactly as Game 1's solver, so a
    friend genuinely acts as a stepstool without faking support over
    ground the helper cannot itself reach."""
    for hsim, hstart in helpers:
        for feet, xs in hsim.footing(hstart).items():
            head_top = feet - hsim.h
            run = []
            for x in sorted(xs):
                if run and x - run[-1] > hsim.spd:
                    sim.extra.append((head_top, run[0], run[-1] + hsim.w))
                    run = []
                run.append(x)
            if run:
                sim.extra.append((head_top, run[0], run[-1] + hsim.w))


def check_floor(rec, phys, num_chars, name):
    """Prove a three-character floor: every character can stand on its
    own home ledge (with friends available as stepstools), the floor
    genuinely NEEDS the cooperative boost (at least one character is
    unsolvable alone), and a working order exists (>=2 finish alone)."""
    boxes = rec["boxes"]
    wrap = rec["wrap"]
    spawns = rec["spawns"]
    home_l, home_r = rec["home_l"], rec["home_r"]
    names = ["Stella", "Alex", "Marcus"]
    solo, helped = {}, {}
    for ci in range(num_chars):
        home_feet = rec["homeY"][ci] + phys["h3"][ci]
        solo[ci] = Char1(boxes, phys, ci, wrap).can_home(
            spawns[ci], home_feet, home_l, home_r)
        sim = Char1(boxes, phys, ci, wrap)
        helpers = [(Char1(boxes, phys, hj, wrap), spawns[hj])
                   for hj in range(num_chars) if hj != ci]
        add_helpers(sim, helpers)
        helped[ci] = sim.can_home(spawns[ci], home_feet, home_l, home_r)

    reach = {ci: solo[ci] or helped[ci] for ci in range(num_chars)}
    all_home = all(reach.values())
    coop_required = not all(solo.values())
    boosters = sum(1 for ci in range(num_chars) if solo[ci])
    order_ok = boosters >= 2      # >=2 finish alone -> a booster can help
    ok = all_home and coop_required and order_ok
    detail = " ; ".join(
        "%s(home=%s,alone=%s)" % (names[ci], reach[ci], solo[ci])
        for ci in range(num_chars))
    print("FLOOR %s: all three reach their homes -> %s ; cooperation "
          "genuinely required -> %s : %s"
          % (name,
             "YES" if all_home else "NO",
             "YES" if coop_required else "NO",
             "ok (three homes, load-bearing coop beat)" if ok else "FAIL"))
    print("  detail: " + detail)
    if not all_home:
        print("  FAIL: %s not solvable even with friends as stepstools"
              % name)
    if not coop_required:
        print("  FAIL: %s solvable with everyone alone — no cooperative "
              "beat" % name)
    if all_home and coop_required and not order_ok:
        print("  FAIL: %s has no booster that can finish alone — order "
              "impossible" % name)
    return ok


def main():
    bin_path, sym_path, asm_path = sys.argv[1:4]
    floors, phys, num_chars = load(bin_path, sym_path, asm_path)
    failed = False
    for i, fl in enumerate(floors):
        name = "F%d" % (i + 1)
        failed = failed or not check_floor(fl, phys, num_chars, name)
    if failed:
        print("check-levels: FAILED")
        sys.exit(1)
    print("check-levels: all %d real floor(s) proved" % len(floors))


if __name__ == "__main__":
    main()
