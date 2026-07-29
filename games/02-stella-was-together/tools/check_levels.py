#!/usr/bin/env python3
"""Build-time solvability proofs for Stella Was Together's real floors.

The workbench's prototype toggle/wrap/portal floors (T1-T3, W1, P1, WP1)
were removed from the shipped game — their proofs live in the
`game2-workbench` git tag. This solver proves the REAL floors the game
plays in order: Act 1's three floors.

Each floor re-implements every character's exact fixed-point physics
(ported byte-for-byte from Game 1's proven check_levels.py; all physics
constants and tables are read from the assembled ROM, so the ROM is the
source of truth). Friends' reachable heads are added as stepstool
surfaces (add_helpers). Every floor proves:

  (a) all three characters can stand on their own home
      (solvable, helpers allowed), and
  (b) homeY-uniqueness, now advisory: a WARNING (not a failure) if a
      character can stand at its home height somewhere off its home box.
      This was a hard failure while the ROM's CheckGoal compared CharY
      only — the level data was the sole thing keeping completion
      honest. AtHome now tests x in the ROM, so such a spot is merely a
      readability wart (you are at home height, the lamp says vacant,
      and it is right), not a false completion. Kept as a warning
      because it is still usually worth knowing.

Plus a per-floor mode proof that the floor's TEACHING is load-bearing:

  coop (Floor 1) — at least one character cannot finish alone, and at
      least two can (so a booster is always available).
  fit (Floor 2)  — Marcus reaches his home ALONE (his gift), Stella can
      NEVER reach Marcus's home even with help (the low door is a real
      filter), and the coop/order rules above still hold for the rest.
  wrap (Floor 3) — solvable with the always-on wrap; with wrap forced
      OFF at least one character's home becomes unreachable even with
      help (the wrap genuinely is the answer, not a flourish).

`make` fails if any proof breaks. Adding a floor = its record + home
table in src/main.asm plus one FLOOR_DEFS row here (its mode). Home
heights AND boxes are read from the ROM's Floor?Home tables, so the
solver and the game cannot drift apart on where home is.

Known model limits (same family as Game 1's solver): helper heads are
static surfaces over each helper's reachable footing — proved over
every SUBSET of helpers, since an all-friends surface can shadow a
ledge sitting 1 du beneath a head and wrongly block it (a real friend
in the way simply moves). No interleaved movement or 2-high stacks are
modelled, and a stander's own head overlap is not re-checked on head
landings — matching the engine's HeadTest. Negative proofs that depend
on geometry (the Floor 3 wall reaches du 8; the best 3-friend stack
tops out at feet 18) hold regardless.

Usage: python3 tools/check_levels.py build/stella-was-together.bin \
                build/main.sym src/main.asm
"""
import re
import sys

NUM_BOXES = 6
ROM_BASE = 0xF000
NAMES = ["Stella", "Alex", "Marcus"]

# Per-floor proof metadata. Home heights and boxes are NOT here — they
# are read from the ROM's Floor?Home tables (3 bytes per character:
# CharY, x-left, x-right), the same bytes AtHome tests against.
FLOOR_DEFS = [
    {"rec": "Floor1Rec", "home": "Floor1Home", "mode": "coop"},
    {"rec": "Floor2Rec", "home": "Floor2Home", "mode": "fit"},
    {"rec": "Floor3Rec", "home": "Floor3Home", "mode": "wrap"},
]


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

    if num_floors != len(FLOOR_DEFS):
        print("check-levels: NUM_FLOORS=%d but %d FLOOR_DEFS — add the "
              "new floor's proof metadata here" % (num_floors, len(FLOOR_DEFS)))
        sys.exit(1)

    floors = []
    for f in range(num_floors):
        d = FLOOR_DEFS[f]
        rec = syms[d["rec"]] - ROM_BASE
        home = u8n(d["home"], 3 * num_chars)   # (CharY, xl, xr) per char
        floors.append({
            "idx": f, "mode": d["mode"],
            "homeY": [home[3 * c] for c in range(num_chars)],
            "home_box": [(home[3 * c + 1], home[3 * c + 2])
                         for c in range(num_chars)],
            "boxes": list(rom[rec + 36:rec + 60]),
            "wrap": rom[syms["FloorWrapTbl"] - ROM_BASE + f],
            "spawns": [(rom[rec + 60], rom[rec + 61]),
                       (rom[rec + 62], rom[rec + 63]),
                       (rom[rec + 64], rom[rec + 65])],
        })
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


def helper_subsets(ci):
    """The player chooses who stands where: prove with each subset of
    the other two as stepstools (a friend who is IN THE WAY simply
    moves — a static all-helpers surface can shadow a ledge sitting
    just beneath a head and wrongly block it)."""
    j, k = [c for c in range(3) if c != ci]
    return [(j,), (k,), (j, k)]


def reach(fl, phys, ci, wrap, helpers, target=None):
    """(can_home, footing) for character ci using the given helper
    subset. target overrides the char's own home (for gate proofs)."""
    hy, (hl, hr) = fl["homeY"][ci], fl["home_box"][ci]
    if target is not None:
        hy, (hl, hr) = fl["homeY"][target], fl["home_box"][target]
        hf = hy + phys["h3"][target]
    else:
        hf = hy + phys["h3"][ci]
    sim = Char1(fl["boxes"], phys, ci, wrap)
    add_helpers(sim, [(Char1(fl["boxes"], phys, hj, wrap),
                       fl["spawns"][hj]) for hj in helpers])
    return sim.can_home(fl["spawns"][ci], hf, hl, hr), \
        sim.footing(fl["spawns"][ci])


def survey(fl, phys, wrap):
    """Per character: (solo, helped-any-subset, union footing)."""
    out = []
    for ci in range(3):
        solo, foot = reach(fl, phys, ci, wrap, ())
        helped = solo
        union = dict((f, set(xs)) for f, xs in foot.items())
        for sub in helper_subsets(ci):
            ok, foot = reach(fl, phys, ci, wrap, sub)
            helped = helped or ok
            for f, xs in foot.items():
                union.setdefault(f, set()).update(xs)
        out.append((solo, helped, union))
    return out


def check_floor(fl, phys, name):
    fails, warns = [], []
    res = survey(fl, phys, fl["wrap"])
    solo = [r[0] for r in res]
    homed = [r[0] or r[1] for r in res]

    # (a) everyone home
    for ci in range(3):
        if not homed[ci]:
            fails.append("%s cannot reach home even with stepstools"
                         % NAMES[ci])

    # (b) homeY-uniqueness — advisory since AtHome tests x in the ROM
    for ci in range(3):
        hf = fl["homeY"][ci] + phys["h3"][ci]
        hl, hr = fl["home_box"][ci]
        w = phys["w3"][ci]
        bad = [(x, f) for f, xs in res[ci][2].items() if f == hf
               for x in xs if not (x < hr and x + w > hl)]
        if bad:
            warns.append("%s can stand at home height off the home box "
                         "(no longer completes — AtHome tests x): %s"
                         % (NAMES[ci], sorted(bad)[:4]))

    mode = fl["mode"]
    coop = not all(solo)
    boosters = sum(solo)
    if mode in ("coop", "fit", "wrap"):
        if not coop:
            fails.append("no cooperative beat: everyone finishes alone")
        if boosters < 2:
            fails.append("fewer than 2 solo finishers — no booster order")
    if mode == "fit":
        if not solo[2]:
            fails.append("Marcus cannot reach his home ALONE — his gift "
                         "must not need help")
        # the low door is a real filter: Stella can never reach his
        # home, whichever friends she uses as stepstools
        for sub in [()] + helper_subsets(0):
            if reach(fl, phys, 0, fl["wrap"], sub, target=2)[0]:
                fails.append("Stella can reach Marcus's home (helpers "
                             "%s) — the door doesn't filter her" % (sub,))
                break
    if mode == "wrap":
        res_no = survey(fl, phys, wrap=0)
        if all(r[0] or r[1] for r in res_no):
            fails.append("floor solvable with wrap OFF — the wrap twist "
                         "is decorative")

    detail = " ; ".join("%s(home=%s,alone=%s)" % (NAMES[ci], homed[ci], solo[ci])
                        for ci in range(3))
    verdict = "ok (%s proof)" % mode if not fails else "FAIL"
    print("FLOOR %s [%s]: %s" % (name, mode, verdict))
    print("  detail: " + detail)
    for w in warns:
        print("  WARNING: " + w)
    for f in fails:
        print("  FAIL: " + f)
    return not fails


def main():
    bin_path, sym_path, asm_path = sys.argv[1:4]
    floors, phys, num_chars = load(bin_path, sym_path, asm_path)
    failed = False
    for i, fl in enumerate(floors):
        if not check_floor(fl, phys, "F%d" % (i + 1)):
            failed = True
    if failed:
        print("check-levels: FAILED")
        sys.exit(1)
    print("check-levels: all %d real floor(s) proved" % len(floors))


if __name__ == "__main__":
    main()
