#!/usr/bin/env python3
"""Build-time solvability check for Stella Was Alone levels.

Reads the assembled ROM + symbol file, extracts the level records and
physics tables, then re-implements the game's exact fixed-point
physics to prove each level completable under PLACE AND HOLD
(decision #26, rc3): a character's goal counts only while it STANDS
on it (grounded overlap), and the level completes when everyone
present holds theirs at once. So the proof per character is a
reachable STANDING state on its own goal — including via a boost from
the other character's head — and at least one character must manage
it entirely alone (the booster finishes last; the boosted one simply
stays put). The old exit-order locks are gone — and as of the rc3 byte
diet the lock byte is gone from the records too, so a record is 73
bytes, not 74.

Five proofs run on every level and both goal layouts (decision #35):
- DRAWN IS SOLID: every box is drawn, and everything drawn where a
  body can reach is a box (decision #17, both directions).
- NO EMBEDDING: no stance on a box overlaps a slab (RC2.1's scan).
- CLIMB: no home may stand on the floor (decision #33).
- ONE-WAY: each character holds its home, at least one of them alone.
- RELAY: when neither can, `joint_plan` must play the level as one
  alternating sequence -- see its docstring. `--joint` runs that search
  on every level, not only where the one-way rule fails.

Engine collision rules modelled exactly (v1.0-rc2):
- solid boxes (top < bottom): block sideways movement (ClampBoxes,
  boxes iterated 5..0 with the pushed x cascading into earlier boxes,
  8-bit wrap on the left-edge push, then the unsigned MIN_X / MaxX
  clamp), head-bonk while rising (first hit in 5..0 order wins), and
  land-on-top while falling
- one-way shelves (top == bottom) and $FF pads: land-on-top only —
  never block sideways, never bonk
- the partner's head is a one-way landing surface checked only after
  every box has missed, exactly like .landLoop's fall-through

Deliberate abstraction gaps (documented, not bugs):
- air control is a constant direction per jump/fall (L/R/none); the
  engine allows per-frame steering, so this is conservative
- the helper is modelled as static head surfaces over each contiguous
  run of its reachable footing (gap tolerance = its walk stride); the
  helper's own movement/exit isn't co-simulated — exit-order logic
  below covers who must still finish alone
- helpers aren't stacked recursively (no boost-to-boost), which is
  conservative
- timers (timed mode / endless clock) are ignored: levels are a few
  seconds across, never time-bound
- quest 2 (upside-down second run) flips only the KERNEL VIEW
  (Band0/BandStep, CharDrawY, FlipG); UpdatePhysics/ClampBoxes read
  the same level record either way, so solvability is orientation-
  invariant and one simulation proves both orientations

Usage: python3 tools/check_levels.py build/stella-was-alone.bin build/main.sym src/main.asm [--joint]
"""
import re
import sys

RECORD = 73           # bytes per level record
NUM_BOXES = 6
ROM_BASE = 0xF000


def load(bin_path, sym_path, asm_path):
    rom = open(bin_path, "rb").read()
    syms = {}
    for line in open(sym_path):
        m = re.match(r"^(\S+)\s+([0-9a-f]{4})", line.strip())
        if m:
            syms[m.group(1)] = int(m.group(2), 16)

    def bytes_at(name, n):
        a = syms[name] - ROM_BASE
        return list(rom[a:a + n])

    asm = open(asm_path).read()
    grav = int(re.search(r"GRAV_LO\s*=\s*\$([0-9a-fA-F]+)", asm).group(1), 16)
    min_x = int(re.search(r"MIN_X\s*=\s*(\d+)", asm).group(1))
    num_levels = int(re.search(r"NUM_LEVELS\s*=\s*(\d+)", asm).group(1))
    maxfall = int(re.search(r"MAXFALL\s*=\s*(\d+)", asm).group(1))
    goal_h = int(re.search(r"GOAL_H\s*=\s*(\d+)", asm).group(1))

    phys = {
        "h": bytes_at("HeightTbl", 2),
        "w": bytes_at("WidthTbl", 2),
        "s": bytes_at("SpeedTbl", 2),
        "maxx": bytes_at("MaxXTbl", 2),
        "jhi": bytes_at("JumpHiTbl", 2),
        "jlo": bytes_at("JumpLoTbl", 2),
        "grav": grav, "min_x": min_x, "maxfall": maxfall,
        "goal_h": goal_h,
    }
    lvl_lo = bytes_at("LvlPtrLo", num_levels)
    lvl_hi = bytes_at("LvlPtrHi", num_levels)

    # --- RECORD STRUCTURE ------------------------------------------
    # A level record is a fixed 73-byte layout with FOUR 6-slot box
    # tables, and it is corrupted constantly and invisibly: writing 5
    # values into a 6-slot table, or losing the indentation before the
    # first .byte after a label (which makes DASM emit a short record),
    # both leave the source looking fine and shift every table after
    # it. All three happened while these levels were being redesigned.
    #
    # So assert the shape rather than trusting it: every record must be
    # exactly RECORD bytes (measured to the NEXT record, which is where
    # a short record shows up as a gap), charCount must be sane, and
    # the spawn heights must be plausible feet-on-ground values.
    problems = []
    addrs = [(hi << 8 | lo) for lo, hi in zip(lvl_lo, lvl_hi)]
    for i in range(num_levels):
        rec = list(rom[addrs[i] - ROM_BASE: addrs[i] - ROM_BASE + RECORD])
        if i + 1 < num_levels:
            got = addrs[i + 1] - addrs[i]
            if got != RECORD:
                problems.append(
                    "LEVEL %d record is %d bytes, not %d. One of the four "
                    "box tables almost certainly has the wrong number of "
                    "values -- they are 6 bytes each and every table "
                    "after the short one is shifted." % (i + 1, got, RECORD))
        if rec[60] not in (1, 2):
            problems.append(
                "LEVEL %d charCount is %d, not 1 or 2 -- the record is "
                "misaligned" % (i + 1, rec[60]))
            continue
        for ci in range(rec[60]):
            feet = rec[62 + 2 * ci] + phys["h"][ci]
            if not 0 <= feet <= 96:
                problems.append(
                    "LEVEL %d character %d spawns at feet %d, outside the "
                    "screen (0-96) -- the record is misaligned"
                    % (i + 1, ci, feet))
    if problems:
        for p in problems:
            print("check-levels: " + p)
        sys.exit(1)

    levels = []
    for addr in addrs:
        levels.append(list(rom[addr - ROM_BASE: addr - ROM_BASE + RECORD]))
    return levels, phys


class Level:
    def __init__(self, rec):
        self.tops = rec[36:42]
        self.bots = rec[42:48]
        self.lefts = rec[48:54]
        self.rights = rec[54:60]
        self.cc = rec[60]
        self.starts = [(rec[61], rec[62]), (rec[63], rec[64])]
        self.goals = [
            [(rec[65], rec[66]), (rec[67], rec[68])],   # primary
            [(rec[69], rec[70]), (rec[71], rec[72])],   # alternate
        ]
        self.boxes = [i for i in range(NUM_BOXES) if self.tops[i] != 0xFF]


class Sim:
    """Mirror of the 6502 physics (16-bit 8.8 vertical, integer x)."""

    def __init__(self, lvl, phys, ci):
        self.lvl, self.p, self.ci = lvl, phys, ci
        self.h = phys["h"][ci]
        self.w = phys["w"][ci]
        self.spd = phys["s"][ci]
        self.maxx = phys["maxx"][ci]
        j = (phys["jhi"][ci] << 8 | phys["jlo"][ci])
        self.jump = j - 0x10000 if j & 0x8000 else j
        self.grav = phys["grav"]
        self.maxfall = phys["maxfall"] << 8
        self.extra = []  # (top, left, right) one-way head surfaces

    def clamp_x(self, x, new_x, y, direction):
        """Engine ClampBoxes + ReadInput's clamp, cycle-exact:
        boxes are walked 5..0 with NewX cascading between them, the
        left-edge push (LV - width) wraps 8-bit, and the final MIN_X /
        MaxX comparison is unsigned (a wrapped push can land at MaxX,
        never below MIN_X)."""
        lvl = self.lvl
        cyh = y + self.h
        new_x &= 0xFF
        for i in range(NUM_BOXES - 1, -1, -1):
            top, bot = lvl.tops[i], lvl.bots[i]
            if bot == top:          # one-way shelf or $FF pad
                continue
            if bot <= y or top >= cyh:
                continue
            l, r = lvl.lefts[i], lvl.rights[i]
            if new_x >= r or new_x + self.w <= l:
                continue
            new_x = ((l - self.w) & 0xFF) if direction > 0 else r
        if new_x < self.p["min_x"]:
            new_x = self.p["min_x"]
        if new_x >= self.maxx:
            new_x = self.maxx
        return new_x

    def surfaces(self):
        """Landing surfaces in engine .landLoop order: boxes 5..0
        (first hit wins), then the partner's head — the engine only
        reaches the head check after every box has missed."""
        lvl = self.lvl
        for i in range(NUM_BOXES - 1, -1, -1):
            if lvl.tops[i] != 0xFF:
                yield (lvl.tops[i], lvl.lefts[i], lvl.rights[i])
        yield from self.extra

    def solids(self):
        """Head-bonk candidates in engine .bonkLoop order (5..0,
        first hit wins); top == bottom shelves and pads never bonk."""
        lvl = self.lvl
        for i in range(NUM_BOXES - 1, -1, -1):
            if lvl.bots[i] != lvl.tops[i]:
                yield (lvl.tops[i], lvl.bots[i], lvl.lefts[i], lvl.rights[i])

    def landing(self, prev_feet, new_feet, x):
        for top, l, r in self.surfaces():
            if prev_feet <= top <= new_feet and x < r and x + self.w > l:
                return top
        return None

    def arc(self, x, feet, jump, direction, goal, trace=None):
        """Simulate one jump or fall with constant direction.
        Returns (landing state or None, goal_touched). With `trace`
        (a list) every falling frame is appended as (x, prev_feet,
        new_feet), so a caller can test a head against the same arc."""
        y256 = (feet - self.h) << 8
        vy = self.jump if jump else 0
        touched = self.touch(x, y256 >> 8, goal)
        for _ in range(600):
            if direction:
                x = self.clamp_x(x, x + direction * self.spd, y256 >> 8, direction)
            prev_feet = (y256 >> 8) + self.h
            vy = min(vy + self.grav, self.maxfall)
            y256 += vy
            if y256 < 0:
                y256, vy = 0, 0
            y = y256 >> 8
            if y > 120:
                return None, touched
            touched |= self.touch(x, y, goal)
            if vy < 0:  # head bonk on solid undersides
                prev_top = prev_feet - self.h
                for top, bot, l, r in self.solids():
                    if prev_top >= bot > y and x < r and x + self.w > l:
                        y256, vy = bot << 8, 0
                        y = bot
                        break
            else:
                if trace is not None:
                    trace.append((x, prev_feet, y + self.h))
                top = self.landing(prev_feet, y + self.h, x)
                if top is not None:
                    return (x, top), touched
        return None, touched

    def touch(self, x, y, goal):
        """Game 2's AtHome rule, verbatim (the #31 convergence): grounded
        (the caller only ever asks about standing states), a horizontal
        overlap of the 8px pad, and the body's top at EXACTLY the home
        height. The home height is the pad's stored top + GOAL_H - this
        body's height, because the pad is drawn with its bottom on the
        standing surface — so every record byte keeps its old meaning.

        This was a box overlap against the 3du pad, which accepted any
        standing height in an 11du window. Eleven surfaces could each
        count as home and only the level data prevented a false
        completion. The solver proved the loose rule while the ROM now
        enforces the tight one, which is the drift this repo exists to
        prevent."""
        gx, gy = goal
        home_top = (gy + self.p["goal_h"] - self.h) & 0xFF
        return (x < gx + 8 and x + self.w > gx and y == home_top)

    def reachable(self, start, goal):
        """BFS over standing states. Returns (goal_states, footing):
        goal_states is the set of standing states from which the goal
        gets touched (few states = a razor-thin, human-hostile level);
        footing maps surface top -> set of standable x."""
        sx, sy = start
        feet0 = sy + self.h
        seen, queue, footing = set(), [(sx, feet0)], {}
        goal_states = set()
        if self.touch(sx, sy, goal):
            goal_states.add((sx, feet0))
        while queue:
            x, feet = queue.pop()
            if (x, feet) in seen:
                continue
            seen.add((x, feet))
            footing.setdefault(feet, set()).add(x)
            if self.touch(x, feet - self.h, goal):
                goal_states.add((x, feet))
            moves = []
            for d in (-1, 0, 1):
                moves.append((True, d))          # jump L/N/R
            for d in (-1, 1):                    # walk one step
                nx = self.clamp_x(x, x + d * self.spd, feet - self.h, d)
                if nx != x:
                    if self.landing(feet, feet, nx) is not None:
                        queue.append((nx, feet))
                        if self.touch(nx, feet - self.h, goal):
                            goal_states.add((nx, feet))
                    else:
                        moves.append((False, d))  # walked off an edge
            for jump, d in moves:
                land, touched = self.arc(x, feet, jump, d, goal)
                if touched:
                    goal_states.add((x, feet))
                if land is not None:
                    lx, ltop = land
                    queue.append((lx, ltop))
        return goal_states, footing


MIN_GOAL_STATES = 4   # fewer launch states than this = human-hostile


def solid_boxes(lvl):
    """(top, bottom, left, right) of every solid box, pads and one-way
    shelves left out."""
    return [(t, b, l, r) for t, b, l, r in
            zip(lvl.tops, lvl.bots, lvl.lefts, lvl.rights)
            if t != 0xFF and t != b]


def char_can_finish(lvl, phys, ci, goal, helper):
    """Can character ci reach its goal, optionally with the other
    character available as a step stool? Returns (ok, width, embedded)."""
    sim = Sim(lvl, phys, ci)
    if helper is not None:
        hsim = Sim(lvl, phys, helper)
        _, footing = hsim.reachable(lvl.starts[helper], (0, 200))
        for feet, xs in footing.items():
            head_top = feet - phys["h"][helper]
            # one head surface per CONTIGUOUS run of reachable footing
            # (gap tolerance = the helper's walk stride), so a solid
            # tower splitting the ground doesn't fake support over the
            # unreachable middle
            stride = phys["s"][helper]
            run = []
            for x in sorted(xs):
                if run and x - run[-1] > stride:
                    sim.extra.append(
                        (head_top, run[0], run[-1] + phys["w"][helper]))
                    run = []
                run.append(x)
            if run:
                sim.extra.append(
                    (head_top, run[0], run[-1] + phys["w"][helper]))
    _, footing = sim.reachable(lvl.starts[ci], goal)
    # place-and-hold: what matters is STANDING states that overlap
    # the goal (the grounded rule), not mid-air touches
    holds = [(x, f) for f, xs in footing.items() for x in xs
             if sim.touch(x, f - sim.h, goal)]
    # RC2.1's "global overlap scan", as a build check rather than a
    # one-off: nowhere a shape can STAND ON A BOX may its body overlap
    # a solid box. (L3 woke Stella a double-line inside two slabs at
    # once, and her first press pushed her through one of them.) A
    # shape perched on a friend's head beside a slab is the residual
    # RC2-NOTES.md already records; heads are set aside for this test.
    heads, sim.extra = sim.extra, []
    embedded = sorted(
        (x, f) for f, xs in footing.items() for x in xs
        if sim.landing(f, f, x) is not None
        and any(bt > f - sim.h and tp < f and x < rr and x + sim.w > ll
                for tp, bt, ll, rr in solid_boxes(lvl)))
    sim.extra = heads
    return len(holds) > 0, len(holds), embedded


def home_is_on_the_floor(lvl, phys, ci, goal):
    """Decision #33's standing rule, machine-checked at last: every
    character in every level must have a route that is a CLIMB.

    #33 says this file "reports any home whose standing surface is the
    floor". Game 1's checker never had that check, and three homes sat
    on the floor unnoticed: Alex's in L4 under both layouts, and in the
    alternate layout Stella's in the very first level of the game. A
    home on the floor is half the cast not playing the level. The
    floor is the level's lowest surface (box 0 in every level so far),
    not the surface a shape happens to wake on: L5 wakes on a platform."""
    floor = max(t for t in lvl.tops if t != 0xFF)
    return goal[1] + phys["goal_h"] == floor


def joint_plan(lvl, phys, goals):
    """JOINT PROOF: one alternating sequence, played out to the end.

    The per-character proof treats a helper as standing anywhere it
    could have walked on its own, and its acceptance rule needs one
    character to finish entirely alone. Neither can see a RELAY: a
    level where each character can only finish from where the OTHER
    one ends up, so the second helper has already been helped. Such a
    level fails above as "no workable hold order" even though the
    engine plays it perfectly well.

    So this search plays the level instead. A state is where both
    shapes are STANDING, each on a box, compressed to the stretch each
    one can still walk along without leaving its footing. From a state
    either shape may move: walk to any spot on its stretch, then jump
    or step off an edge in one constant direction -- the same arcs as
    every other proof here. It may land on the other's head (the base
    must first be able to walk to a spot of its own stride that
    catches it, and the landing may not leave a body inside a slab),
    walk along that head, and jump or step off again. Every edge is a
    real sequence of inputs, so a found plan IS a solution.

    Not modelled, which can only cost solutions, never invent them:
    steering that changes direction mid-air, switching while both are
    airborne, and a base walking out from under a rider.

    least moves first, and among those the one with the fewest boosts (a
    boost is two moves, boarding then launching). Returns such a plan
    as a list of (who, what, from, to, moves), or None if neither shape
    can bring both home."""
    sims = [Sim(lvl, phys, 0), Sim(lvl, phys, 1)]
    w, h, spd = phys["w"], phys["h"], phys["s"]
    solids = [(lvl.tops[i], lvl.bots[i], lvl.lefts[i], lvl.rights[i])
              for i in range(NUM_BOXES)
              if lvl.tops[i] != 0xFF and lvl.bots[i] != lvl.tops[i]]
    arcs = {}

    def arc(ci, x, feet, jump, d):
        """One arc, cached: where it lands on a box (or None), the
        falling frames a head may still catch it in (a box wins the
        landing frame, so that one is left out), and the span of feet
        those frames sweep — most arcs never cross a given head."""
        key = (ci, x, feet, jump, d)
        if key not in arcs:
            frames = []
            land, _ = sims[ci].arc(x, feet, jump, d, (0, 200), trace=frames)
            test = frames if land is None else frames[:-1]
            sweep = ((min(pf for _, pf, _ in test), max(nf for _, _, nf in test))
                     if test else None)
            arcs[key] = (land, test, sweep)
        return arcs[key]

    walks = {}                  # (ci, feet) -> the stretches known on that surface

    def run(ci, x, feet):
        """The stretch character ci can walk along from (x, feet):
        (feet, first x, last x). Only its own stride's spots exist."""
        known = walks.setdefault((ci, feet), [])
        for r in known:
            if r[1] <= x <= r[2] and (x - r[1]) % spd[ci] == 0:
                return r
        sim, step = sims[ci], spd[ci]
        lo = hi = x
        while True:
            nx = sim.clamp_x(lo, lo - step, feet - h[ci], -1)
            if nx == lo or sim.landing(feet, feet, nx) is None:
                break
            lo = nx
        while True:
            nx = sim.clamp_x(hi, hi + step, feet - h[ci], 1)
            if nx == hi or sim.landing(feet, feet, nx) is None:
                break
            hi = nx
        r = (feet, lo, hi)
        known.append(r)
        return r

    def spots(ci, r):
        return range(r[1], r[2] + 1, spd[ci])

    def holds(ci, r):
        return any(sims[ci].touch(x, r[0] - h[ci], goals[ci])
                   for x in spots(ci, r))

    def strides(ci, a, b, phase):
        """x in [a, b] on the stride that lands on `phase`."""
        return [p for p in range(a, b + 1) if (p - phase) % spd[ci] == 0]

    def leaves(ci, pr, landing, what, origin, moves=1):
        nr = run(ci, landing[0], landing[1])
        return ((nr, pr) if ci == 0 else (pr, nr)), (ci, what, origin, landing, moves)

    def from_head(ci, pi, pr, fx, bases, boarded, origin):
        """ci has just landed on the base's head at x = fx, by the move
        `boarded` from `origin`, the base standing at one of `bases`.
        Walk the head, then jump or step off; each clean landing on a
        box is a new state two moves on (the boarding, then the
        launch)."""
        ht = pr[0] - h[pi]
        top = ht - h[ci]
        lo_x, hi_x = phys["min_x"], phys["maxx"][ci]   # nowhere else exists

        def riding(x):
            return [p for p in bases if x < p + w[pi] and x + w[ci] > p]

        def clear(x):
            return not any(bt > top and tp < ht and x < rr and x + w[ci] > ll
                           for tp, bt, ll, rr in solids)

        if not clear(fx):
            return []                     # it came to rest inside a slab
        xs = [fx]
        for d in (-1, 1):
            x = fx
            while True:
                x += d * spd[ci]
                if not (lo_x <= x <= hi_x) or not riding(x) or not clear(x):
                    break
                xs.append(x)
        xs.sort()
        out = []
        for x in xs:
            moves = [(True, -1), (True, 0), (True, 1)]
            for d in (-1, 1):
                if (d < 0 and x == xs[0]) or (d > 0 and x == xs[-1]):
                    moves.append((False, d))
            for jump, d in moves:
                land, test, sweep = arc(ci, x, ht, jump, d)
                if land is None:
                    continue
                # the base stays put; whichever spot it chose must not
                # catch the rider again on the way down
                for p in riding(x):
                    if all(not (fx2 < p + w[pi] and fx2 + w[ci] > p)
                           for fx2, _, _ in test):
                        what = (f"{boarded} onto a head, then "
                                f"{'jump' if jump else 'step off'} from it")
                        out.append(leaves(ci, pr, land, what, origin, 2))
                        break
        return out

    def successors(state):
        out = []
        for ci in (0, 1):
            pi = 1 - ci
            r, pr = (state[0], state[1]) if ci == 0 else (state[1], state[0])
            ht = pr[0] - h[pi]
            anywhere = set(strides(pi, pr[1], pr[2], pr[1]))   # where the other may stand
            for x in spots(ci, r):
                moves = [(True, -1), (True, 0), (True, 1)]
                for d in (-1, 1):        # stepping off an edge, at an edge
                    if (d < 0 and x == r[1]) or (d > 0 and x == r[2]):
                        nx = sims[ci].clamp_x(x, x + d * spd[ci], r[0] - h[ci], d)
                        if nx != x and sims[ci].landing(r[0], r[0], nx) is None:
                            moves.append((False, d))
                for jump, d in moves:
                    land, test, sweep = arc(ci, x, r[0], jump, d)
                    what = "jump" if jump else "step off"
                    caught = set()      # base spots this arc has been offered as a catch
                    if sweep and sweep[0] <= ht <= sweep[1]:
                        for fx, pf, nf in test:
                            if not pf <= ht <= nf:
                                continue     # the head is not in this frame's sweep
                            here = [p for p in strides(
                                        pi, max(fx - w[pi] + 1, pr[1]),
                                        min(fx + w[ci] - 1, pr[2]), pr[1])
                                    if p not in caught]
                            if here:    # a base that walked to one of these spots catches it
                                out.extend(from_head(ci, pi, pr, fx, here, what, (x, r[0])))
                                caught.update(here)
                    if land is not None and anywhere - caught:
                        # or the base simply stands clear, and the arc lands where it would
                        out.append(leaves(ci, pr, land, what, (x, r[0])))
        return out

    start = (run(0, lvl.starts[0][0], lvl.starts[0][1] + h[0]),
             run(1, lvl.starts[1][0], lvl.starts[1][1] + h[1]))
    prev = {start: None}          # state -> (state before it, the move made)
    rank = {start: 0}             # state -> moves * 64 + boosts, the cheaper the better
    by_rank = {0: [start]}        # Dijkstra: one small bucket per rank
    while True:
        if not by_rank:
            return None
        r = min(by_rank)
        st = by_rank[r].pop()
        if not by_rank[r]:
            del by_rank[r]
        if rank[st] != r:
            continue              # reached more cheaply since it was queued
        if holds(0, st[0]) and holds(1, st[1]):
            plan = []
            while prev[st] is not None:
                st, info = prev[st]
                plan.append(info)
            plan.reverse()
            return plan
        for nxt, info in successors(st):
            far = r + info[4] * 64 + (info[4] == 2)
            if far < rank.get(nxt, 1 << 30):
                rank[nxt] = far
                prev[nxt] = (st, info)
                by_rank.setdefault(far, []).append(nxt)


def col_drawn(rec, band, px):
    """Is playfield pixel px (0-159) set in BAND `band` of this record?
    The playfield is MIRRORED (CTRLPF=1), so the right half reflects
    the left; the three planes cover px 0-15 / 16-47 / 48-79, one byte
    per band each (PF0 at +0, PF1 at +12, PF2 at +24)."""
    if px >= 80:
        px = 159 - px
    if px < 16:
        return (rec[band] >> (4 + px // 4)) & 1
    if px < 48:
        return (rec[12 + band] >> (7 - (px - 16) // 4)) & 1
    return (rec[24 + band] >> ((px - 48) // 4)) & 1


def rise_of(phys, ci):
    """How far one jump lifts character ci, in du, counted the way the
    engine counts it: gravity first, then the move."""
    v = (phys["jhi"][ci] << 8 | phys["jlo"][ci]) - 65536
    total = 0
    while True:
        v += phys["grav"]
        if v >= 0:
            return -total / 256.0
        total += v


def highest_standable(lvl, phys):
    """The highest box top any shape could ever stand on, judged by
    height alone - which can only over-estimate. Start from the floor
    and keep any top that some shape could land on from a height it
    already has, alone or off the other's head. Three levels have a
    pillar that reaches du 40; nothing can stand on it, because no
    surface is within a jump of its top, and the sky above it is as
    far away as the sky anywhere else."""
    tops = sorted({t for t in lvl.tops if t != 0xFF}, reverse=True)
    have = {tops[0]}             # du grow downwards: the largest top is the floor
    lifts = []                   # (rise, lift): alone, and off a friend's head
    for ci in range(lvl.cc):
        lifts.append((rise_of(phys, ci), 0))
        if lvl.cc == 2:
            lifts.append((rise_of(phys, ci), phys["h"][1 - ci]))
    again = True
    while again:
        again = False
        for t in tops:
            if t not in have and any(f - lift - rise <= t + 1 for f in have
                                     for rise, lift in lifts):
                have.add(t)
                again = True
    return min(have)


def check_art(rec, lvl, idx, phys):
    """Decision #17's visual honesty rule, machine-checked at last --
    and in BOTH directions.

    Every collision box must be FULLY DRAWN over the bands it spans:
    a slab you can stand on that isn't visible, or a visible slab you
    fall through, is the exact bug RC2 was written to kill — and for
    eight years nothing re-checked it. That matters more now than
    before: redesigning levels to spend the spare boxes means editing
    the playfield bytes and the collision table in the same breath, and
    the two drifting apart is the easiest mistake in this file to make.

    And everything DRAWN where a body can get to must be solid. The
    playfield is mirrored, so a box added on one side of the screen is
    drawn on the other side too; if only one of the pair has a box, the
    other is a ghost — a slab a shape can stand inside. Five levels
    had them (L3, L5, L6, L9, L10), and in L5 both shapes woke inside
    one. Scenery above the highest point any body can reach is left
    alone: L2's far-off structures are meant to be looked at.

    A band is 8 du (16 scanlines), so a box spanning du [bot, top] must
    be drawn in every band from bot//8 up to top//8.
    """
    problems = []
    # The 4px side walls are a convention of EVERY level in this game
    # (PF0 bit 4, the outer 4 columns) and they are not a collision
    # box, so the box audit below cannot see them. Regenerating a
    # level's playfield from its geometry drops them silently — which
    # is exactly what happened to levels 3, 6 and 10 while their
    # routes were being redesigned. A level with no walls still
    # collides correctly (MIN_X/MaxXTbl clamp in code, not in the
    # playfield), so nothing else would ever notice.
    if (rec[0] & 0x10) == 0:
        problems.append("PF0 band 0 has no $10 side wall — every other "
                        "level in the game draws the 4px outer columns "
                        "there. Nothing collides differently, it just "
                        "looks like the screen has no frame.")
    boxes = solid_boxes(lvl)
    for b in range(NUM_BOXES):
        if lvl.tops[b] == 0xFF:
            continue
        top, bot = lvl.tops[b], lvl.bots[b]
        left, right = lvl.lefts[b], lvl.rights[b]
        if top == bot:
            continue           # a one-way shelf is drawn as an edge
        lo, hi = top // 8, min(11, (bot - 1) // 8)
        if hi < lo:              # a box drawn as an edge only
            continue
        missing = [(band, px) for band in range(lo, hi + 1)
                   for px in range(left, min(right, 160))
                   if not col_drawn(rec, band, px)]
        if missing:
            problems.append(
                "box %d (top %d, bot %d, x %d-%d) is not drawn over its "
                "own bands %d-%d — %d columns missing, first at %s. You "
                "could stand on something invisible."
                % (b, top, bot, left, right, lo, hi, len(missing),
                   missing[0]))
    # --- the other direction: drawn, so it had better be solid ------
    # The topmost point any body can occupy: a shape standing on the
    # highest surface it can really stand on, on its friend's head if
    # there is one, at the top of its jump. Drawn stuff entirely above
    # that is scenery (decision #36).
    reach = min(highest_standable(lvl, phys)
                - (phys["h"][1 - ci] if lvl.cc == 2 else 0)
                - phys["h"][ci] - rise_of(phys, ci)
                for ci in range(lvl.cc))
    ghosts = {}
    for band in range(11):            # band 11 is the ground: box 0 holds it
        if (band + 1) * 8 <= reach:
            continue
        for px in range(4, 156, 4):   # the side walls are drawn, never boxes
            if any(col_drawn(rec, band, px + k) for k in range(4)) and not any(
                    t <= band * 8 and b >= band * 8 + 8 and l <= px and px + 4 <= r
                    for t, b, l, r in boxes):
                ghosts.setdefault(band, []).append(px)
    if ghosts:
        problems.append(
            "drawn but NOT solid — the playfield is mirrored, so a box "
            "on one side is drawn on the other too and only one of the "
            "pair collides: "
            + "; ".join(f"du {b*8}-{b*8+8} px {min(v)}-{max(v)+3}"
                        for b, v in sorted(ghosts.items()))
            + ". A shape can stand inside it (RC2: what is drawn solid "
              "must BE solid).")
    return problems


def check_level(idx, lvl, phys, rec=None, force_joint=False):
    problems = []
    plans = []          # (variant tag, joint plan, is it a relay?)
    if rec is not None:
        problems.extend(check_art(rec, lvl, idx, phys))
    for vi, goals in enumerate(lvl.goals):
        tag = "primary" if vi == 0 else "alternate"
        for ci, name in enumerate(("Stella", "Alex")[:lvl.cc]):
            if home_is_on_the_floor(lvl, phys, ci, goals[ci]):
                problems.append(f"{tag}: {name}'s home stands on the floor — "
                                f"every home must be a climb (decision #33)")
        if lvl.cc == 1:
            ok, width, stuck = char_can_finish(lvl, phys, 0, goals[0], None)
            if stuck:
                problems.append(f"{tag}: Stella can stand inside a slab — "
                                f"first at x={stuck[0][0]}, feet du {stuck[0][1]}")
            if not ok:
                problems.append(f"{tag}: Stella cannot reach her goal")
            elif width < MIN_GOAL_STATES:
                print(f"LEVEL {idx + 1}: WARNING {tag}: Stella's goal "
                      f"reachable from only {width} state(s)")
            continue
        s_solo, s_w, s_stuck = char_can_finish(lvl, phys, 0, goals[0], None)
        a_solo, a_w, a_stuck = char_can_finish(lvl, phys, 1, goals[1], None)
        s_help, s_hw, _ = char_can_finish(lvl, phys, 0, goals[0], 1)
        a_help, a_hw, _ = char_can_finish(lvl, phys, 1, goals[1], 0)
        for name, stuck in (("Stella", s_stuck), ("Alex", a_stuck)):
            if stuck:
                problems.append(f"{tag}: {name} can stand inside a slab — "
                                f"first at x={stuck[0][0]}, feet du {stuck[0][1]}")
        s_help, s_hw = (s_help or s_solo), max(s_w, s_hw)
        a_help, a_hw = (a_help or a_solo), max(a_w, a_hw)
        for name, ok, width in (("Stella", s_help, s_hw),
                                ("Alex", a_help, a_hw)):
            if ok and width < MIN_GOAL_STATES:
                print(f"LEVEL {idx + 1}: WARNING {tag}: {name}'s goal "
                      f"reachable from only {width} state(s)")
        detail = (f"S(solo={s_solo},help={s_help}) "
                  f"A(solo={a_solo},help={a_help})")
        # place-and-hold: the boosted character stays put on its goal,
        # so completion needs each to HOLD (help allowed) and at least
        # one to manage entirely alone — that one moves last. A level
        # where BOTH need the other is a relay: the per-character rule
        # cannot see it, so the joint search speaks instead.
        ok = (s_help and a_solo) or (a_help and s_solo)
        plan = None
        if not ok or force_joint:
            plan = joint_plan(lvl, phys, [goals[0], goals[1]])
        if ok and force_joint and plan is None:
            problems.append(f"{tag}: the per-character proof passes, but "
                            f"the joint search finds no way to play it — {detail}")
        elif not ok and plan:
            plans.append((tag, plan, True))
        elif not ok:
            problems.append(f"{tag}: no workable hold order — {detail} — "
                            f"and the joint search finds no alternating sequence")
        elif plan:
            plans.append((tag, plan, False))
    return problems, plans


def main():
    argv = sys.argv[1:]
    force_joint = "--joint" in argv
    bin_path, sym_path, asm_path = [a for a in argv if not a.startswith("--")][:3]
    levels, phys = load(bin_path, sym_path, asm_path)
    failed = False
    for i, rec in enumerate(levels):
        lvl = Level(rec)
        problems, plans = check_level(i, lvl, phys, rec, force_joint)
        if problems:
            failed = True
            for p in problems:
                print(f"LEVEL {i + 1}: FAIL — {p}")
        else:
            line = f"LEVEL {i + 1}: ok"
            for tag, plan, relay in plans:
                moves = sum(step[4] for step in plan)
                boosts = sum(1 for step in plan if step[4] == 2)
                kind = (f" — {tag} is a RELAY: neither shape finishes "
                        f"alone; a plan of {moves} moves" if relay
                        else f" — {tag}: a plan of {moves} moves")
                line += f"{kind}, {boosts} of them a boost off a friend's head"
            print(line)
    if failed:
        print("check-levels: FAILED")
        sys.exit(1)
    print(f"check-levels: all {len(levels)} levels solvable")


if __name__ == "__main__":
    main()
