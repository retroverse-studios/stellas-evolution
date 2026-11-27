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
  (c) PLAYABILITY MARGIN, advisory: WAYS IN — how many distinct (state,
      action) pairs arrive at home from somewhere that is not already
      home. This is the check that would have caught Floor 1, which was
      provably solvable and miserable to play: every character's obvious
      jump landed on the WRONG ledge, and the proof passed on the
      strength of a pixel-perfect side arc. SOLVABLE IS NOT FINDABLE.
      Calibrated on that floor — the bad version scored 6, its
      replacement 92, and every comfortable home scores 30+.

Plus a per-floor mode proof that the floor's TEACHING is load-bearing:

  coop (Floor 1) — at least one character cannot finish alone, and at
      least two can (so a booster is always available).
  fit (Floor 2)  — Marcus reaches his home ALONE (his gift), Stella can
      NEVER reach Marcus's home even with help (the low door is a real
      filter), and the coop/order rules above still hold for the rest.
  wrap (Floor 3) — solvable with the always-on wrap; with wrap forced
      OFF at least one character's home becomes unreachable even with
      help (the wrap genuinely is the answer, not a flourish).
  portal (F4-F6) — with the portal tables blanked, at least one home is
      unreachable even with help. Composes: F5 is "coop+portal".
  swap (F7-F9)  — the Act-3 world-swap floors. The state space grows a
      world bit: standing grounded in a rift column adds an edge to the
      same position in the other world (settles by gravity there). "swap"
      proves the floor unsolvable with swaps off; "swapboth" (the
      interleave floors) proves EACH world alone is insufficient;
      "return" (Floor 9) proves one swap from world A is not enough,
      so someone must cross back. Every swap floor prints who needs
      the return. Two
      audits ride along: every box that differs between worlds is
      one-way (so no swap can embed a body in a new wall), and every
      grounded rift state swaps into clear air in the other world.

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
import os
import re
import sys

NUM_BOXES = 6
WRAP_LIMIT = 160
MIN_WAYS_IN = 12  # calibrated: the Floor 1 that playtest called "really
                  # hard" scored 6; the version that replaced it scores 92,
                  # and every comfortable home on floors 1-2 scores 30+
ROM_BASE = 0xF000
NAMES = ["Stella", "Alex", "Marcus"]

# Per-floor proof metadata. Home heights and boxes are NOT here — they
# are read from the ROM's Floor?Home tables (3 bytes per character:
# CharY, x-left, x-right), the same bytes AtHome tests against. Modes
# combine with "+": a floor can be both a portal floor and a coop floor
# (F5: the boost gates the door), and each named check must hold.
FLOOR_DEFS = [
    {"rec": "Floor1Rec", "home": "Floor1Home", "mode": "coop"},
    {"rec": "Floor2Rec", "home": "Floor2Home", "mode": "fit"},
    {"rec": "Floor3Rec", "home": "Floor3Home", "mode": "wrap"},
    {"rec": "Floor4Rec", "home": "Floor4Home", "mode": "portal"},
    {"rec": "Floor5Rec", "home": "Floor5Home", "mode": "coop+portal"},
    {"rec": "Floor6Rec", "home": "Floor6Home", "mode": "portal"},
    {"rec": "Floor7Rec", "home": "Floor7Home", "mode": "swap"},
    {"rec": "Floor8Rec", "home": "Floor8Home", "mode": "swapboth"},
    {"rec": "Floor9Rec", "home": "Floor9Home", "mode": "swapboth+return"},
    {"rec": "Floor10Rec", "home": "Floor10Home", "mode": "swap+seam+coop+return"},
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

    # --- TABLE BOUNDS (the fix for the FloorPortL overrun) ----------
    # Every per-floor table the solver indexes by FloorSeq must have at
    # least NUM_FLOORS entries. We can't see a .byte table's length in
    # the symbol file, so we bound it by the NEXT symbol that starts
    # above it in the same bank: a table that overruns is a table whose
    # reading runs into whatever follows, which is how FloorPortL (six
    # entries, nine floors) silently handed the solver a phantom portal
    # on three floors. This asserts the property for every such table
    # at once, so the next one added is checked for free.
    #
    # Both banks are placed at $F000, so their addresses overlap and a
    # symbol's value can't say which bank it is in (this once tested
    # bit $1000, which both banks share). The source can: every label
    # defined after `SEG BANK1` is bank 1's, and those never bound a
    # bank-0 table.
    b1src = asm[asm.index("SEG BANK1"):]
    for inc in re.findall(r'^\s+include\s+"([^"]+)"', b1src, re.M):
        b1src += open(os.path.join(os.path.dirname(asm_path), inc)).read()
    bank1 = set(re.findall(r"^([A-Za-z_]\w*):?\s", b1src, re.M))
    def span(name):
        """Bytes available to `name` before the next bank-0 symbol."""
        base = syms[name]
        nxt = [a for n, a in syms.items()
               if n not in bank1 and 0xF000 <= a and a > base]
        return min(nxt) - base if nxt else 0x1000

    def need(name, count, why):
        have = span(name)
        if have < count:
            print("check-levels: TABLE OVERRUN — %s is indexed %d ways "
                  "(%s) but only %d bytes exist before the next symbol"
                  % (name, count, why, have))
            sys.exit(1)

    for tbl, why in (("FloorRecLo", "the floor record pointer"),
                     ("FloorHomeLo", "the home height table"),
                     ("FloorWrapTbl", "the edge mode"),
                     ("FloorSkyTbl", "the sky base"),
                     ("FloorRiftL", "the rift column"),
                     ("FloorPortL", "portal column A"),
                     ("FloorPort2L", "portal column B"),
                     ("FloorSolidN", "the solid-box count")):
        need(tbl, num_floors, why)
    # mouths are interleaved two per floor
    need("FloorMouX", 2 * num_floors, "portal mouths")
    need("FloorMouY", 2 * num_floors, "portal mouths")
    # per-character, per-floor lamp bands
    need("FloorBandByChar", 3 * num_floors, "home lamp bands")

    # --- PHYSICS TABLES ------------------------------------------
    # The solver's whole value is that it reads the ROM's tables rather
    # than restating them. Assert every one it depends on actually
    # resolves, so a renamed or dropped table is a build failure and
    # not a silently-stale constant.

    def u8n(name, n):     # first n bytes of a table (per-character arrays)
        if name not in syms:
            print("check-levels: MISSING SYMBOL %s — the solver reads it "
                  "from the ROM, so this is a rename, not a bug you can "
                  "ignore" % name)
            sys.exit(1)
        base = syms[name] - ROM_BASE
        return list(rom[base:base + n])

    phys = {
        "grav": grav, "min_x": min_x, "maxfall": maxfall,
        "wrap_w": wrap_w, "wrap_hi": wrap_hi,
        "h3": u8n("HeightTbl", num_chars), "w3": u8n("WidthTbl", num_chars),
        "spd3": u8n("SpeedTbl", num_chars), "maxx3": u8n("MaxXTbl", num_chars),
        "jhi3": u8n("JumpHiTbl", num_chars), "jlo3": u8n("JumpLoTbl", num_chars),
        # SpeedHalfTbl: Marcus walks 1.5px/frame (an extra pixel every
        # other frame). The solver USED to ignore this and model every
        # character at their whole-pixel SpeedTbl — a silent
        # under-approximation that happened not to flip any verdict
        # but meant the proofs were not about the game as built.
        "half3": u8n("SpeedHalfTbl", num_chars),
    }
    for name in ("SpeedTbl", "SpeedHalfTbl", "HeightTbl", "WidthTbl",
                 "MaxXTbl", "JumpHiTbl", "JumpLoTbl"):
        if name not in syms:
            print("check-levels: MISSING SYMBOL %s" % name)
            sys.exit(1)

    if num_floors != len(FLOOR_DEFS):
        print("check-levels: NUM_FLOORS=%d but %d FLOOR_DEFS — add the "
              "new floor's proof metadata here" % (num_floors, len(FLOOR_DEFS)))
        sys.exit(1)

    # FloorBandByChar is indexed char*NUM_FLOORS + floor (MulFloors +
    # FloorSeq, exactly as PrepSprites does it), so the whole table is
    # read once here and indexed [ci*NUM_FLOORS + floor] below.
    bb = syms["FloorBandByChar"] - ROM_BASE
    bands = list(rom[bb:bb + 3 * num_floors])

    floors = []
    for f in range(num_floors):
        d = FLOOR_DEFS[f]
        rec = syms[d["rec"]] - ROM_BASE
        home = u8n(d["home"], 3 * num_chars)   # (CharY, xl, xr) per char
        # Portal data, straight from the ROM's Act-2 tables. Columns are
        # 8px (R = L+8); 255 parks a column. Mouths are interleaved
        # floor*2+column, exactly as DoTeleport indexes them, and store
        # FEET du (the ROM subtracts the character's height on arrival).
        pl = rom[syms["FloorPortL"] - ROM_BASE + f]
        p2l = rom[syms["FloorPort2L"] - ROM_BASE + f]
        mou_x = syms["FloorMouX"] - ROM_BASE
        mou_y = syms["FloorMouY"] - ROM_BASE
        portals = []
        if pl != 255:
            portals.append(((pl, pl + 8),
                            (rom[mou_x + 2 * f], rom[mou_y + 2 * f])))
        if p2l != 255:
            portals.append(((p2l, p2l + 8),
                            (rom[mou_x + 2 * f + 1], rom[mou_y + 2 * f + 1])))
        # Act 3: rifts (PF0 edge beams, [L, L+4) + mirror) and world-B
        # data. Dual floors carry B's interior planes at +78/+90 and
        # B's boxes at +102 (the rift-blink's PF0 OFF copy is at +66).
        rl = rom[syms["FloorRiftL"] - ROM_BASE + f]
        rifts = []
        if rl != 255:
            rifts = [(rl, rl + 4), (156 - rl, 160 - rl)]
        dual = "swap" in d["mode"]
        # Act 4: a floor with doors AND rifts has its doors only in
        # world B (ReadPortal's CurWorld gate), and its own world-B PF0
        # pair after the record (ON +126, OFF +138: BlinkRifts)
        seam = dual and portals and rifts
        # ClampBoxes visits only boxes 1..FloorSolidN (box 0 is the
        # ground, which can't side-block): so box 0 must be the ground,
        # boxes 1..N solid and the rest one-way or pads — in BOTH worlds,
        # or a wall would stop blocking
        nsol = rom[syms["FloorSolidN"] - ROM_BASE + f]
        for tag, at in (("A", rec + 36), ("B", rec + 102)):
            if tag == "B" and "swap" not in d["mode"]:
                continue
            bx = rom[at:at + 24]
            kinds = ["S" if bx[i] != bx[i + 6] else "o" for i in range(6)]
            if bx[0] != 88 or bx[6] != 96 or bx[12] != 0 or bx[18] != 160 \
                    or kinds[1:] != ["S"] * nsol + ["o"] * (5 - nsol):
                print("check-levels: F%d world %s boxes %s don't match "
                      "FloorSolidN=%d (ground first, then the solid boxes, "
                      "then one-way) — ClampBoxes would miss a wall"
                      % (f + 1, tag, "".join(kinds), nsol))
                sys.exit(1)
        floors.append({
            "idx": f, "mode": d["mode"], "rec": rec,
            "homeY": [home[3 * c] for c in range(num_chars)],
            "home_box": [(home[3 * c + 1], home[3 * c + 2])
                         for c in range(num_chars)],
            "boxes": list(rom[rec + 36:rec + 60]),
            "wrap": rom[syms["FloorWrapTbl"] - ROM_BASE + f],
            "spawns": [(rom[rec + 60], rom[rec + 61]),
                       (rom[rec + 62], rom[rec + 63]),
                       (rom[rec + 64], rom[rec + 65])],
            "portals": [] if seam else portals,
            "portalsB": portals if seam else None,
            "pf0B": (list(rom[rec + 126:rec + 138]),
                     list(rom[rec + 138:rec + 150])) if seam else None,
            "rifts": rifts,
            "band": bands, "num_floors": num_floors,
            "boxesB": list(rom[rec + 102:rec + 126]) if dual else None,
            # the record's three art planes and, for portal floors, the
            # OFF copy at record+66 that BlinkPortal swaps in (on dual
            # floors +66 is the shared PF0's OFF copy — the rift blink)
            "planes": [list(rom[rec:rec + 12]),
                       list(rom[rec + 12:rec + 24]),
                       list(rom[rec + 24:rec + 36])],
            "off_plane": list(rom[rec + 66:rec + 78])
            if (portals or rifts) else [],
        })
    return floors, phys, num_chars


class Char1:
    """One character's physics on a single-world floor, with optional
    helper HEAD surfaces (the stacking beat). A port of Game 1's proven
    per-character solver, adapted to Game 2's three characters, one-way
    ledges and wrap edges. Vertical is 16-bit 8.8; x is integer.

    SpeedHalfTbl is honoured. Marcus walks 1.5px/frame — SpeedTbl on
    even frames, SpeedTbl+1 on odd — which WalkSpeed does with
    `FrameCtr & SpeedHalfTbl & 1`. The solver used to read SpeedTbl
    alone and model him at a flat 1.0. That is an under-approximation
    of a real speed, so every "he can't quite make it" conclusion was
    being drawn about a character slower than the one in the ROM. The
    fix carries the frame parity in the state: a state is
    (x, feet, parity) and the step size follows from the parity, which
    is exactly what the engine's FrameCtr does.
    """

    def __init__(self, boxes, phys, ci, wrap):
        self.tops = boxes[0:6]
        self.bots = boxes[6:12]
        self.lefts = boxes[12:18]
        self.rights = boxes[18:24]
        self.h = phys["h3"][ci]
        self.w = phys["w3"][ci]
        self.spd = phys["spd3"][ci]
        self.half = phys["half3"][ci] & 1     # 1 = the odd-frame extra px
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
        self.portals = []          # ((l, r), (mouth_x, mouth_feet))

    def fstep(self, par):
        """This frame's horizontal step: the half-step character gets
        one extra pixel on odd frames, exactly as WalkSpeed does."""
        return self.spd + self.half if par else self.spd

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

    def arc(self, x, feet, jump, direction, par=0):
        """One arc with the stick held one way throughout. Reachability
        uses lands() (the stick can change every frame); this survives
        for the swap-safety audit, which asks where a body that does
        nothing falls."""
        y256 = (feet - self.h) << 8
        vy = self.jump if jump else 0
        for _ in range(600):
            if direction:
                x = self.clamp_x(x, x + direction * self.fstep(par),
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
            par ^= 1                # was `par = np`: the step size
        return None                 # alternated once, then stuck

    def lands(self, x, feet, jump, par=0):
        """Every (x, feet, parity) an airborne body can land on, choosing
        left, right or neither afresh on every frame: ReadInput reads the
        stick every frame, airborne or not, so a player can steer a jump
        and stop over a ledge mid-fall. The solver used to hold one
        direction from take-off, which could only under-count where a
        body lands, so its "can't get home without X" proofs were not
        proofs (decision #55: on floor 11 Stella simply stepped off one
        ledge and let go onto her own). Vertical motion is the same for
        every x until a ceiling bonk, so the search keeps one set of x
        per (y256, vy) and steps them together."""
        key = (x, feet, jump, par)
        memo = self.__dict__.setdefault("_lands", {})
        if key in memo:
            return memo[key]
        h, w = self.h, self.w
        solids = list(self.solids())
        surfaces = list(self.surfaces())
        groups = {((feet - h) << 8, self.jump if jump else 0): {x}}
        out = set()
        for _ in range(600):
            if not groups:
                break
            step = self.fstep(par)
            np = par ^ 1
            nxt = {}
            for (y256, vy), xs in groups.items():
                y0 = y256 >> 8
                walls = [b for b in solids if not (b[1] <= y0 or b[0] >= y0 + h)]
                moved = set()
                for x0 in xs:
                    moved.add(x0)
                    for d in (-1, 1):
                        if walls:
                            moved.add(self.clamp_x(x0, x0 + d * step, y0, d))
                        else:
                            nx = (x0 + d * step) & 0xFF
                            if self.wrap:
                                if nx >= self.wrap_hi:
                                    nx = (nx + self.wrap_w) & 0xFF
                                elif nx >= self.wrap_w:
                                    nx = (nx - self.wrap_w) & 0xFF
                            else:
                                nx = min(max(nx, self.min_x), self.maxx)
                            moved.add(nx)
                prev_feet = y0 + h
                vy2 = min(vy + self.grav, self.maxfall)
                y2 = y256 + vy2
                if y2 < 0:
                    y2, vy2 = 0, 0
                y = y2 >> 8
                if y > 120:
                    continue
                if vy2 < 0:
                    rest = moved
                    for top, bot, l, r in solids:
                        if y0 >= bot > y:
                            hit = {x1 for x1 in rest if x1 < r and x1 + w > l}
                            if hit:
                                nxt.setdefault((bot << 8, 0), set()).update(hit)
                                rest = rest - hit
                    if rest:
                        nxt.setdefault((y2, vy2), set()).update(rest)
                else:
                    rest = moved
                    for top, l, r in surfaces:
                        if prev_feet <= top <= y + h:
                            hit = {x1 for x1 in rest if x1 < r and x1 + w > l}
                            for x1 in hit:
                                out.add((x1, top, np))
                            rest = rest - hit
                            if not rest:
                                break
                    if rest:
                        nxt.setdefault((y2, vy2), set()).update(rest)
            groups = nxt
            par = np
        memo[key] = out
        return out

    def portal_edge(self, x, par=0):
        """If x overlaps a column, the standing states the teleport
        delivers: arrive at the mouth with zero velocity and fall under
        the same gravity (and the same mid-air steering) as everyone
        else. A mouth on a surface yields the spot itself; a mouth over
        air yields every landing the fall can steer to. Empty set if x
        touches no column."""
        for (l, r), (mx, mfeet) in self.portals:
            if x < r and x + self.w > l:
                return self.lands(mx, mfeet, False, par)
        return set()

    def footing(self, start):
        """BFS over standing states; returns {feet: set(x)}. The state
        carries the frame parity for half-step characters, so both
        their step sizes are explored — the ROM alternates, so the
        player can be moving at either rate on any given frame."""
        sx, sy = start
        seen, stack, foot = set(), [(sx, sy + self.h, 0)], {}
        while stack:
            x, feet, par = stack.pop()
            if (x, feet, par) in seen:
                continue
            seen.add((x, feet, par))
            foot.setdefault(feet, set()).add(x)
            np = par ^ 1
            if self.portals:       # the Act-2 verb: UP in a column
                stack.extend(self.portal_edge(x, par))
            edge = False
            for d in (-1, 1):      # walk one step
                nx = self.clamp_x(x, x + d * self.fstep(par), feet - self.h, d)
                if nx != x:
                    if self.landing(feet, feet, nx) is not None:
                        stack.append((nx, feet, np))
                    else:
                        edge = True
            if edge:               # step off, steering all the way down
                stack.extend(self.lands(x, feet, False, par))
            stack.extend(self.lands(x, feet, True, par))   # jump
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
        add_heads(sim, hsim, hsim.footing(hstart))


def add_heads(sim, hsim, footing):
    """Head surfaces from a helper's footing {feet: xs} (see
    add_helpers); hsim gives the helper's height, width and stride."""
    for feet, xs in footing.items():
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


def reach(fl, phys, ci, wrap, helpers, target=None, portals_on=True):
    """(can_home, footing) for character ci using the given helper
    subset. target overrides the char's own home (for gate proofs).
    portals_on=False is the Act-2 negative proof: the doors stay shut."""
    hy, (hl, hr) = fl["homeY"][ci], fl["home_box"][ci]
    if target is not None:
        hy, (hl, hr) = fl["homeY"][target], fl["home_box"][target]
        hf = hy + phys["h3"][target]
    else:
        hf = hy + phys["h3"][ci]
    sim = Char1(fl["boxes"], phys, ci, wrap)
    if portals_on:
        sim.portals = list(fl["portals"])
    add_helpers(sim, [(Char1(fl["boxes"], phys, hj, wrap),
                       fl["spawns"][hj]) for hj in helpers])
    return sim.can_home(fl["spawns"][ci], hf, hl, hr), \
        sim.footing(fl["spawns"][ci])


def survey(fl, phys, wrap, portals_on=True):
    """Per character: (solo, helped-any-subset, union footing)."""
    out = []
    for ci in range(3):
        solo, foot = reach(fl, phys, ci, wrap, (), portals_on=portals_on)
        helped = solo
        union = dict((f, set(xs)) for f, xs in foot.items())
        for sub in helper_subsets(ci):
            ok, foot = reach(fl, phys, ci, wrap, sub, portals_on=portals_on)
            helped = helped or ok
            for f, xs in foot.items():
                union.setdefault(f, set()).update(xs)
        out.append((solo, helped, union))
    return out


class DualSim:
    """One character across BOTH worlds of an Act-3 floor: two Char1
    sharing the character's physics, with the state space (x, feet,
    world). A SWAP edge exists where the ROM grants it: grounded in a
    rift column, delivering the same position to the other world, where
    gravity re-seats it (a ledge true in only one world drops you).
    Helper heads are computed per world — a friend's footing differs
    per truth, and the static-helper approximation is unchanged."""

    def __init__(self, fl, phys, ci, wrap, helpers=(), swaps_on=True,
                 start_world=0, max_swaps=None, portals_on=True):
        self.max_swaps = max_swaps         # None: as many as you like
        self.w = phys["w3"][ci]
        self.h = phys["h3"][ci]
        self.rifts = fl["rifts"] if swaps_on else []
        self.start_world = start_world
        self.sims = []
        # Portals per world: Act 4 has doors true in only one world
        # (fl["portalsB"]); a floor without them keeps one set for both
        per_world = (fl["portals"], fl.get("portalsB") or fl["portals"])
        for boxes, ports in zip((fl["boxes"], fl["boxesB"]), per_world):
            s = Char1(boxes, phys, ci, wrap)
            s.portals = list(ports) if portals_on else []
            self.sims.append(s)
        # A friend's head is a surface wherever the FRIEND can stand,
        # and on a dual floor the friend crosses worlds and takes doors
        # too: its footing comes from its own DualSim (no helpers of
        # its own), split per world. Act 4 boosts happen on ledges only
        # a door reaches.
        for hj in helpers:
            hd = DualSim(fl, phys, hj, wrap, (), swaps_on, start_world,
                         None, portals_on)
            per = ({}, {})
            for x, feet, w, _p in hd.footing(fl["spawns"][hj]):
                per[w].setdefault(feet, set()).add(x)
            for w in (0, 1):
                add_heads(self.sims[w], hd.sims[w], per[w])

    def footing(self, start):
        """BFS: returns set of (x, feet, world) standing states. The frame
        parity rides along so half-step characters explore both of the
        step sizes the ROM alternates between."""
        sx, sy = start
        # n = swaps made so far, counted only when they are capped
        seen, stack = set(), [(sx, sy + self.h, self.start_world, 0, 0)]
        while stack:
            st = stack.pop()
            if st in seen:
                continue
            seen.add(st)
            x, feet, w, par, n = st
            sim = self.sims[w]
            np = par ^ 1
            if sim.portals:                # UP in a column, this world's
                for lx, lf, lp in sim.portal_edge(x, par):
                    stack.append((lx, lf, w, lp, n))
            # the ROM reads the door before the rift, and a teleport
            # spends the UP press: overlapping both, you go through
            # the door and never swap
            door = sim.portals and any(x < r and x + self.w > l
                                       for (l, r), _m in sim.portals)
            if (self.max_swaps is None or n < self.max_swaps) and not door:
                n2 = n if self.max_swaps is None else n + 1
                for (l, r) in self.rifts:  # the swap edge
                    if x < r and x + self.w > l:
                        for lx, lf, lp in self.sims[1 - w].lands(x, feet, False, par):
                            stack.append((lx, lf, 1 - w, lp, n2))
            edge = False
            for d in (-1, 1):              # walk one step
                nx = sim.clamp_x(x, x + d * sim.fstep(par), feet - sim.h, d)
                if nx != x:
                    if sim.landing(feet, feet, nx) is not None:
                        stack.append((nx, feet, w, np, n))
                    else:
                        edge = True
            if edge:                       # step off, steering down
                for lx, lf, lp in sim.lands(x, feet, False, par):
                    stack.append((lx, lf, w, lp, n))
            for lx, lf, lp in sim.lands(x, feet, True, par):   # jump
                stack.append((lx, lf, w, lp, n))
        return {st[:4] for st in seen}

    def can_home(self, start, hf, hl, hr):
        return bool(self.home_worlds(start, hf, hl, hr))

    def home_worlds(self, start, hf, hl, hr):
        """The worlds this character can stand home in. The swap is
        GLOBAL (SwapWorld flips the floor for everyone) and CheckGoal
        wants all three home at once, so a floor finishes only in a
        world every character can be home in — survey_dual intersects."""
        return {w for x, feet, w, _p in self.footing(start)
                if feet == hf and x < hr and x + self.w > hl}

    def entry_moves(self, start, hf, hl, hr):
        """Ways in, dual-world: the single-world count plus swap
        arrivals that land home."""
        def is_home(x, feet):
            return feet == hf and x < hr and x + self.w > hl
        ways = []
        for x, feet, w, par in self.footing(start):
            if is_home(x, feet):
                continue
            sim = self.sims[w]
            if not sim.half:
                # one parity is enough for a whole-pixel character (and
                # its mirror world's twin) — see entry_moves
                par = 0
            def any_home(ls):
                return any(is_home(lx, lf) for lx, lf, _p in ls)
            for (l, r) in self.rifts:
                if x < r and x + self.w > l:
                    if any_home(self.sims[1 - w].lands(x, feet, False, par)):
                        ways.append(((x, feet, w), "swap"))
            if sim.portals and any_home(sim.portal_edge(x, par)):
                ways.append(((x, feet, w), "door"))
            edge = False
            for d in (-1, 1):
                nx = sim.clamp_x(x, x + d * sim.fstep(par), feet - sim.h, d)
                if nx != x:
                    if sim.landing(feet, feet, nx) is not None:
                        if is_home(nx, feet):
                            ways.append(((x, feet, w), "walk"))
                    else:
                        edge = True
            if edge and any_home(sim.lands(x, feet, False, par)):
                ways.append(((x, feet, w), "step off"))
            if any_home(sim.lands(x, feet, True, par)):
                ways.append(((x, feet, w), "jump"))
        return ways


def survey_dual(fl, phys, swaps_on=True, start_world=0, max_swaps=None,
                portals_on=True, wrap=None):
    """Per character: (solo, helped-any-subset), judged in ONE finishing
    world. The world-swap is global and CheckGoal tests all three at
    once, so a character home only in world A and another home only in
    world B is not a finish: per world, collect who can be home (alone,
    or with some helper subset), and report the world where the most
    characters make it (all three, on a floor that proves)."""
    wrap = fl["wrap"] if wrap is None else wrap
    per = []                     # per char: (solo worlds, helped worlds)
    for ci in range(3):
        home = (fl["spawns"][ci], fl["homeY"][ci] + phys["h3"][ci],
                *fl["home_box"][ci])
        solo = DualSim(fl, phys, ci, wrap, (), swaps_on, start_world,
                       max_swaps, portals_on).home_worlds(*home)
        helped = set(solo)
        for sub in helper_subsets(ci):
            if helped == {0, 1}:
                break
            helped |= DualSim(fl, phys, ci, wrap, sub, swaps_on,
                              start_world, max_swaps,
                              portals_on).home_worlds(*home)
        per.append((solo, helped))
    best = max((0, 1), key=lambda w: (sum(w in h for _s, h in per),
                                      sum(w in s for s, _h in per)))
    return [(best in s, best in h) for s, h in per]

def booster_order_dual(fl, phys, wrap=None):
    """A finishing order for a dual-world coop floor, or None. Friends
    who are already home can't come back out to boost, so the order
    must run: each character gets home with a stepstool subset drawn
    only from those still out, and the last one home goes alone. All
    of it in one finishing world (the swap is global). The Act-1 rule
    ("two solo finishers") was a shortcut for this; with mid-air
    steering in the solver, the honest floor 10 has ONE solo finisher
    who boosts the other two in turn, which this proves."""
    wrap = fl["wrap"] if wrap is None else wrap
    from itertools import permutations
    cache = {}

    def homes(ci, sub):
        if (ci, sub) not in cache:
            home = (fl["spawns"][ci], fl["homeY"][ci] + phys["h3"][ci],
                    *fl["home_box"][ci])
            cache[ci, sub] = DualSim(fl, phys, ci, wrap, sub, True, 0,
                                     None, True).home_worlds(*home)
        return cache[ci, sub]

    for world in (0, 1):
        for order in permutations(range(3)):
            ok = True
            for i, ci in enumerate(order):
                out = tuple(sorted(order[i + 1:]))
                subs = [()] + [tuple(sorted(s)) for s in
                               ([(c,) for c in out] + ([out] if len(out) == 2 else []))]
                if not any(world in homes(ci, s) for s in subs):
                    ok = False
                    break
            if ok:
                return order
    return None


def boxes_of(b):
    """The floor's six boxes as (top, bottom, left, right) tuples —
    the record's SoA layout is tops b[0:6], bottoms b[6:12], lefts
    b[12:18], rights b[18:24]."""
    return [(b[i], b[i + 6], b[i + 12], b[i + 18]) for i in range(6)]


def check_swap_safety(fl, phys):
    """The Act-3 grammar, audited. (1) Every box that differs between
    the worlds is ONE-WAY — one-way boxes never side-block, so no swap
    can leave a body inside a new wall. (2) Every grounded rift state
    any character can reach in either world swaps into clear air in the
    other (no solid overlap) AND settles somewhere (no falling off the
    world)."""
    fails = []
    boxes_a = [b for b in boxes_of(fl["boxes"]) if b[0] != 0xFF]
    boxes_b = [b for b in boxes_of(fl["boxesB"]) if b[0] != 0xFF]
    for top, bot, l, r in set(boxes_a) ^ set(boxes_b):
        if top != bot:
            fails.append("box (%d,%d,%d,%d) differs between worlds and "
                         "is SOLID — a swap could embed a body in it"
                         % (top, bot, l, r))
    if not fl["rifts"]:
        fails.append("a swap floor with no rifts")
        return fails
    for ci in range(3):
        h = phys["h3"][ci]
        w_ = phys["w3"][ci]
        for w in (0, 1):
            sim = DualSim(fl, phys, ci, fl["wrap"], ())
            for x, feet, ww, _p in sim.footing(fl["spawns"][ci]):
                if ww != w:
                    continue
                if not any(x < r and x + w_ > l for l, r in fl["rifts"]):
                    continue
                other = sim.sims[1 - w]
                for top, bot, l, r in other.solids():
                    if bot > feet - h and top < feet and \
                       x < r and x + w_ > l:
                        fails.append("%s grounded in a rift at (%d, %d, "
                                     "world %s) is inside a wall in the "
                                     "other world" % (NAMES[ci], x, feet,
                                                      "AB"[w]))
                        break
                if other.arc(x, feet, False, 0) is None:
                    fails.append("%s swapping at (%d, %d, world %s) "
                                 "falls out of the world"
                                 % (NAMES[ci], x, feet, "AB"[w]))
    return fails


def check_rift_art(fl):
    """The rift-mask audit — same honesty rule as the portal audit,
    for the PF0 edge beams: the ON copy (the record's PF0 page) has the
    mask set in every band 0-10, the OFF copy (+66) differs only there,
    and the blink really toggles somewhere."""
    fails = []
    if not fl["rifts"]:
        return fails
    l = fl["rifts"][0][0]
    mask = 0
    for px in range(l, l + 4):           # PF0: px*4 columns, bit 4+px//4
        mask |= 1 << (4 + px // 4)
    on, off = fl["planes"][0], fl["off_plane"]
    for b in range(11):
        if on[b] & mask != mask:
            fails.append("band %d: PF0 $%02x lacks rift bits $%02x"
                         % (b, on[b], mask))
        if (on[b] ^ off[b]) & ~mask:
            fails.append("band %d: ON/OFF differ by more than the rift "
                         "mask ($%02x vs $%02x)" % (b, on[b], off[b]))
    if not any((on[b] ^ off[b]) & mask for b in range(11)):
        fails.append("the rift never actually blinks")
    if fl.get("pf0B"):
        # Act 4: world B's own PF0 pair carries the rift AND the doors
        # (PF0 columns: px 8-15 = bits 6-7, and their mirror)
        dmask = 0
        for (dl, _dr), _m in fl["portalsB"][:1]:
            for px in range(dl, dl + 8):
                dmask |= 1 << (4 + px // 4)
        if not fl["portalsB"] or fl["portalsB"][0][0][0] >= 16:
            fails.append("a seam floor's doors must stand in PF0 (x < 16)")
        both = mask | dmask
        on_b, off_b = fl["pf0B"]
        for b in range(11):
            if on_b[b] & both != both:
                fails.append("band %d: world B PF0 $%02x lacks rift+door "
                             "bits $%02x" % (b, on_b[b], both))
            if (on_b[b] ^ off_b[b]) & ~both:
                fails.append("band %d: world B ON/OFF differ by more than "
                             "rift+door ($%02x vs $%02x)"
                             % (b, on_b[b], off_b[b]))
        if not any((on_b[b] ^ off_b[b]) & dmask for b in range(11)):
            fails.append("world B's doors never actually blink")
        if len(fl["portalsB"]) < 2 or \
                fl["portalsB"][1][0][0] != 152 - fl["portalsB"][0][0][0]:
            fails.append("world B's second door should be the mirror")
    return fails


def entry_moves(sim, start, hf, hl, hr):
    """Every (state, action) that ARRIVES at home from a state that is not
    already home — "how many ways in", which is what playability turns on.
    Counting home states instead is misleading: once you are standing on a
    wide ledge, shuffling along it counts as dozens of home positions while
    there may be only one way to get onto it."""
    def is_home(x, feet):
        return feet == hf and x < hr and x + sim.w > hl
    ways = []
    # Only a half-step character has two distinct step sizes, so only it
    # is worth visiting twice — otherwise every (state, action) pair is
    # counted once per parity, the margins roughly double, and the
    # calibrated MIN_WAYS_IN threshold stops meaning anything.
    pars = (0, 1) if sim.half else (0,)
    for feet, xs in sim.footing(start).items():
        for x in xs:
            if is_home(x, feet):
                continue
            for par in pars:
                def any_home(ls):
                    return any(is_home(lx, lf) for lx, lf, _p in ls)
                if sim.portals and any_home(sim.portal_edge(x, par)):
                    ways.append(((x, feet), "portal"))   # by door
                edge = False
                for d in (-1, 1):
                    nx = sim.clamp_x(x, x + d * sim.fstep(par), feet - sim.h, d)
                    if nx != x:
                        if sim.landing(feet, feet, nx) is not None:
                            if is_home(nx, feet):
                                ways.append(((x, feet), "walk"))
                        else:
                            edge = True
                if edge and any_home(sim.lands(x, feet, False, par)):
                    ways.append(((x, feet), "step off"))
                if any_home(sim.lands(x, feet, True, par)):
                    ways.append(((x, feet), "jump"))
    return ways


def shadowed(fl, phys, ci, hf, hl, hr):
    """Is the home in the SHADOW of a higher surface? Falling, you land on
    the first surface your feet cross, so a home lying under a ledge that
    spans the same x can never be dropped onto — it is reachable only by
    arcing in from the side, which is the Floor 1 fault: solvable, and
    miserable. Returns (fully_shadowed, blocked_columns, total_columns)."""
    b, w = fl["boxes"], phys["w3"][ci]
    tops = [(b[i], b[i + 12], b[i + 18]) for i in range(NUM_BOXES)
            if b[i] != 0xFF and b[i] < hf]
    cols = range(max(0, hl - w + 1), min(WRAP_LIMIT, hr))
    blocked = [any(x < r and x + w > l for (_, l, r) in tops) for x in cols]
    return all(blocked), sum(blocked), len(blocked)



def portal_mask(left, plane_off):
    """The playfield bits an 8px column at x [left, left+8) sets, in the
    plane BlinkPortal derives (x < 48 -> PF1, else PF2 — the ROM rule).
    Left-half pixels only; the mirror half is the same byte reflected."""
    mask = 0
    for px in range(left, min(left + 8, 80)):
        if plane_off == 12:            # PF1: px 16-47, bit = 7-(px-16)//4
            mask |= 1 << (7 - (px - 16) // 4)
        else:                          # PF2: px 48-79, bit = (px-48)//4
            mask |= 1 << ((px - 48) // 4)
    return mask


def check_portal_art(fl):
    """The drawn portal and the tested portal must be the same portal.
    The kernel blinks columns by swapping the plane pointer between the
    record's ON copy and the OFF copy at record+66, so: (1) the ON copy
    has the column's mask set in every band 0-10 (a beam is floor-to-
    sky), (2) the two copies differ ONLY in that mask, (3) the blink is
    real — the mask really toggles in at least one band (bands that are
    $FF anyway, like a full-width shelf, legitimately can't show it),
    and (4) the mask is exactly what the trigger tables claim, mirror
    included. Returns a list of failures."""
    fails = []
    portals = fl["portals"]
    if not portals:
        return fails
    (l, r), _ = portals[0]
    plane_off = 12 if l < 48 else 24
    mask = portal_mask(l, plane_off)
    on = fl["planes"][plane_off // 12]
    off = fl["off_plane"]
    for b in range(11):
        if on[b] & mask != mask:
            fails.append("band %d: ON copy $%02x lacks column bits "
                         "$%02x — the beam has a gap" % (b, on[b], mask))
        if (on[b] ^ off[b]) & ~mask:
            fails.append("band %d: ON/OFF differ by more than the "
                         "column mask ($%02x vs $%02x, mask $%02x)"
                         % (b, on[b], off[b], mask))
    if not any((on[b] ^ off[b]) & mask for b in range(11)):
        fails.append("the column never actually blinks (ON==OFF "
                     "everywhere the mask lives)")
    mirror_l = 152 - l
    if mirror_l == l:
        if len(portals) > 1:
            fails.append("column at %d is self-mirrored; the second "
                         "range must be parked at 255" % l)
    elif len(portals) < 2 or portals[1][0][0] != mirror_l:
        fails.append("second column should be the mirror at %d, tabled "
                     "as %s" % (mirror_l,
                                portals[1][0][0] if len(portals) > 1
                                else "none"))
    return fails


def check_lamp_bands(fl, phys):
    """The HOME LAMPS must be painted on the bands that ARE the homes.

    FloorBandByChar[char*3 + floor] picks the 8-du band PrepSprites
    tints in that character's colour. The table's own comment claims a
    rule it "keeps honest" — three distinct bands per floor, and a
    tinted band is a whole home rather than a slice of one — but
    nothing checked it. Portal and rift art both get audited; the lamp
    that IS the goal feedback (#27) did not, which meant a wrong entry
    would paint Stella's lamp on Alex's ledge and the build would stay
    green. A band is 8 du tall (du = 2 scanlines, bands are 16), so a
    lamp is correct when its band actually overlaps its owner's home
    span, vertically and horizontally.
    """
    fails = []
    tb = fl["band"]
    mine = [tb[ci * fl["num_floors"] + fl["idx"]] for ci in range(3)]
    if len(set(mine)) != 3:
        fails.append("lamp bands %s are not three distinct bands — two "
                     "characters would share (and overwrite) one lamp"
                     % (mine,))
    for ci, band in enumerate(mine):
        if band > 11:
            fails.append("%s's lamp band %d is off the top of the screen"
                         % (NAMES[ci], band))
            continue
        # A band is a full-width horizontal stripe 8 du tall (96 du of
        # screen in 12 bands), and it is the DRAWN LEDGE the home sits
        # on — not the body. The character stands on top of the ledge, so
        # the band's job is to contain the surface the feet land on:
        # feet = homeY + height. Testing the body instead would be wrong
        # by the character's whole height, which is how this audit first
        # reported every floor in the game as broken.
        feet = fl["homeY"][ci] + phys["h3"][ci]
        lo, hi = band * 8, band * 8 + 8
        if not (lo <= feet < hi):
            fails.append("%s's lamp band %d (du %d-%d) does not contain "
                         "its home surface (du %d) — the lamp would be "
                         "painted at the wrong height, so the one piece "
                         "of feedback that teaches the goal rule would lie"
                         % (NAMES[ci], band, lo, hi, feet))
    return fails


def check_floor_dual(fl, phys, name):
    """The Act-3 path: the same three proofs (all-home, home-height
    uniqueness advisory, ways-in margin) over the two-world state
    space, plus the swap load-bearing proofs and the safety/art
    audits."""
    fails, warns, margins = [], [], []
    res = survey_dual(fl, phys)

    # (a) everyone home, helpers allowed, both worlds in play
    for ci in range(3):
        if not res[ci][1]:
            fails.append("%s cannot reach home even with stepstools and"
                         " swaps" % NAMES[ci])

    # (b) homeY-uniqueness advisory, per world
    for ci in range(3):
        hf = fl["homeY"][ci] + phys["h3"][ci]
        hl, hr = fl["home_box"][ci]
        w_ = phys["w3"][ci]
        sim = DualSim(fl, phys, ci, fl["wrap"], ())
        bad = sorted({(x, f, "AB"[w]) for x, f, w, _p
                    in sim.footing(fl["spawns"][ci])
                    if f == hf and not (x < hr and x + w_ > hl)})
        if bad:
            warns.append("%s can stand at home height off the home box "
                         "(no longer completes — AtHome tests x): %s"
                         % (NAMES[ci], bad[:4]))

    # (c) ways-in margin, best helper subset
    for ci in range(3):
        hf = fl["homeY"][ci] + phys["h3"][ci]
        hl, hr = fl["home_box"][ci]
        best, kinds = 0, []
        for sub in [()] + helper_subsets(ci):
            sim = DualSim(fl, phys, ci, fl["wrap"], sub)
            w = sim.entry_moves(fl["spawns"][ci], hf, hl, hr)
            if len(w) > best:
                best, kinds = len(w), sorted({k for _, k in w})
        margins.append("%s %d in (%s)" % (NAMES[ci], best,
                                          ",".join(kinds) or "none"))
        if best < MIN_WAYS_IN:
            warns.append("%s has only %d way(s) in — a trick shot "
                         "rather than a move" % (NAMES[ci], best))

    modes = fl["mode"].split("+")
    # the swap load-bearing proofs: swaps OFF, nobody leaves world A
    res_a = survey_dual(fl, phys, swaps_on=False)
    if all(r[1] for r in res_a):
        fails.append("floor solvable with swaps OFF — the world-swap "
                     "is decorative")
    if "swapboth" in modes:
        # and the interleave must be real: world B alone isn't a home
        res_b = survey_dual(fl, phys, swaps_on=False, start_world=1)
        if all(r[1] for r in res_b):
            fails.append("world B alone suffices — the handoff never "
                         "happens, the swap is one-sided")
    # how many crossings the floor asks, from world A: proved for
    # "return" (one swap is not enough: someone must come back),
    # reported for every swap floor so twin floors read differently
    one = survey_dual(fl, phys, max_swaps=1)
    if "swap" in fl["mode"]:
        short = [NAMES[ci] for ci in range(3) if not one[ci][1]]
        margins.append("needs a return: " + (", ".join(short) or "nobody"))
    if "seam" in modes:
        # the finale composes every verb: take any one away and some
        # character can't get home
        if all(r[1] for r in survey_dual(fl, phys, wrap=0)):
            fails.append("floor solvable with the wrap OFF — the seam "
                         "is decorative")
        if all(r[1] for r in survey_dual(fl, phys, portals_on=False)):
            fails.append("floor solvable with portals OFF — the door "
                         "is decorative")
    if "coop" in modes:
        # the not-alone beat: someone needs a friend's head, and the
        # others finish alone (they are the stepstools)
        if all(r[0] for r in res):
            fails.append("no cooperative beat: everyone finishes alone")
        order = booster_order_dual(fl, phys)
        if order is None:
            fails.append("no booster order: nobody can be the last one "
                         "home with only friends still out as stepstools")
        else:
            margins.append("order: " + " > ".join(NAMES[c] for c in order))
    if "return" in modes and all(r[1] for r in one):
        fails.append("one swap gets everyone home — the way back is "
                     "never needed")

    fails.extend(check_swap_safety(fl, phys))
    fails.extend(check_rift_art(fl))
    fails.extend(check_lamp_bands(fl, phys))

    detail = " ; ".join("%s(home=%s,alone=%s)" % (NAMES[ci], res[ci][1],
                                                  res[ci][0])
                        for ci in range(3))
    verdict = "ok (%s proof)" % fl["mode"] if not fails else "FAIL"
    print("FLOOR %s [%s]: %s" % (name, fl["mode"], verdict))
    print("  detail: " + detail)
    if margins:
        print("  margin: " + " ; ".join(margins))
    for w in warns:
        print("  WARNING: " + w)
    for f in fails:
        print("  FAIL: " + f)
    return not fails


def check_floor(fl, phys, name):
    if "swap" in fl["mode"]:
        return check_floor_dual(fl, phys, name)
    fails, warns, margins = [], [], []
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
                         % (NAMES[ci], bad[:4]))

    # (c) PLAYABILITY MARGIN — advisory, and the check that would have
    # caught Floor 1. A floor can be provably solvable and still be
    # miserable: Floor 1 shipped with every character's obvious jump
    # landing on the WRONG ledge, and the proof passed because a
    # pixel-perfect side arc existed. SOLVABLE IS NOT FINDABLE.
    #
    # The measure is WAYS IN: distinct (state, action) pairs that arrive
    # at home from a state that is not already home. Counting home
    # positions instead is misleading — once you are on a wide ledge,
    # shuffling along it scores dozens while there may be one way onto
    # it. Taken over the best helper subset, matching how (a) proves it.
    for ci in range(3):
        hf = fl["homeY"][ci] + phys["h3"][ci]
        hl, hr = fl["home_box"][ci]
        best, kinds = 0, []
        for sub in [()] + helper_subsets(ci):
            sim = Char1(fl["boxes"], phys, ci, fl["wrap"])
            sim.portals = list(fl["portals"])
            add_helpers(sim, [(Char1(fl["boxes"], phys, hj, fl["wrap"]),
                               fl["spawns"][hj]) for hj in sub])
            w = entry_moves(sim, fl["spawns"][ci], hf, hl, hr)
            if len(w) > best:
                best, kinds = len(w), sorted({k for _, k in w})
        full, nblocked, ncols = shadowed(fl, phys, ci, hf, hl, hr)
        shade = ("%d/%d shadowed" % (nblocked, ncols)) if nblocked else "open"
        margins.append("%s %d in (%s)" % (NAMES[ci], best, shade))
        if best < MIN_WAYS_IN:
            warns.append("%s has only %d way(s) in%s, %s — a trick shot "
                         "rather than a move; the floor is provable but "
                         "likely to feel unfair"
                         % (NAMES[ci], best,
                            " (" + ", ".join(kinds) + ")" if kinds else "",
                            shade))

    modes = fl["mode"].split("+")
    coop = not all(solo)
    boosters = sum(solo)
    if any(m in modes for m in ("coop", "fit", "wrap")):
        if not coop:
            fails.append("no cooperative beat: everyone finishes alone")
        if boosters < 2:
            fails.append("fewer than 2 solo finishers — no booster order")
    if "fit" in modes:
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
    if "wrap" in modes:
        res_no = survey(fl, phys, wrap=0)
        if all(r[0] or r[1] for r in res_no):
            fails.append("floor solvable with wrap OFF — the wrap twist "
                         "is decorative")
    if "portal" in modes:
        # The Act-2 load-bearing proof, same shape as the wrap proof:
        # with the doors shut, at least one home must be unreachable
        # even with help — else the portal is decoration.
        if not fl["portals"]:
            fails.append("mode claims a portal the floor doesn't have")
        else:
            res_no = survey(fl, phys, wrap=fl["wrap"], portals_on=False)
            if all(r[0] or r[1] for r in res_no):
                fails.append("floor solvable with the portal OFF — the "
                             "portal is decorative")
            fails.extend(check_portal_art(fl))
    fails.extend(check_lamp_bands(fl, phys))

    detail = " ; ".join("%s(home=%s,alone=%s)" % (NAMES[ci], homed[ci], solo[ci])
                        for ci in range(3))
    verdict = "ok (%s proof)" % fl["mode"] if not fails else "FAIL"
    print("FLOOR %s [%s]: %s" % (name, fl["mode"], verdict))
    print("  detail: " + detail)
    if margins:
        print("  margin: " + " ; ".join(margins))
    for w in warns:
        print("  WARNING: " + w)
    for f in fails:
        print("  FAIL: " + f)
    return not fails


def main():
    bin_path, sym_path, asm_path = sys.argv[1:4]
    floors, phys, num_chars = load(bin_path, sym_path, asm_path)
    failed = False
    only = os.environ.get("FLOORS")   # e.g. FLOORS=10,11 to iterate
    pick = {int(n) for n in only.split(",")} if only else None
    for i, fl in enumerate(floors):
        if pick and i + 1 not in pick:
            continue
        if not check_floor(fl, phys, "F%d" % (i + 1)):
            failed = True
    if failed:
        print("check-levels: FAILED")
        sys.exit(1)
    print("check-levels: %s proved" % ("floor(s) %s" % only if pick else
                                        "all %d real floor(s)" % len(floors)))


if __name__ == "__main__":
    main()
