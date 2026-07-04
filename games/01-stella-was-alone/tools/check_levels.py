#!/usr/bin/env python3
"""Build-time solvability check for Stella Was Alone levels.

Reads the assembled ROM + symbol file, extracts the level records and
physics tables, then re-implements the game's exact fixed-point
physics to prove each character can reach its goal — including via a
boost from the other character's head, and including exit-order
constraints (the booster must be able to finish after the boosted).

Conservative approximations (may reject a humanly-solvable level, but
never approves an unsolvable one, with one caveat*):
- air control is a constant direction per jump/fall (L/R/none)
- boosts assume the partner can stand anywhere in the contiguous span
  of their reachable footing on each surface (*caveat: if a partner's
  footing on one surface has gaps, a boost from inside a gap would be
  wrongly allowed — our levels have no such gaps)

Usage: python3 tools/check_levels.py build/stella-was-alone.bin build/main.sym src/main.asm
"""
import re
import sys

RECORD = 74           # bytes per level record
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
    levels = []
    for lo, hi in zip(lvl_lo, lvl_hi):
        a = (hi << 8 | lo) - ROM_BASE
        levels.append(list(rom[a:a + RECORD]))
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
        self.exit_order = rec[73]  # 0 any; 1 Stella last; 2 Alex last
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
        lvl = self.lvl
        cyh = y + self.h
        for i in lvl.boxes:
            top, bot = lvl.tops[i], lvl.bots[i]
            if bot == top:
                continue
            if bot <= y or top >= cyh:
                continue
            l, r = lvl.lefts[i], lvl.rights[i]
            if new_x >= r or new_x + self.w <= l:
                continue
            new_x = l - self.w if direction > 0 else r
        return max(self.p["min_x"], min(self.maxx, new_x))

    def surfaces(self):
        lvl = self.lvl
        for i in lvl.boxes:
            yield (lvl.tops[i], lvl.lefts[i], lvl.rights[i])
        yield from self.extra

    def solids(self):
        lvl = self.lvl
        for i in lvl.boxes:
            if lvl.bots[i] != lvl.tops[i]:
                yield (lvl.tops[i], lvl.bots[i], lvl.lefts[i], lvl.rights[i])

    def landing(self, prev_feet, new_feet, x):
        for top, l, r in self.surfaces():
            if prev_feet <= top <= new_feet and x < r and x + self.w > l:
                return top
        return None

    def arc(self, x, feet, jump, direction, goal):
        """Simulate one jump or fall with constant direction.
        Returns (landing state or None, goal_touched)."""
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
                top = self.landing(prev_feet, y + self.h, x)
                if top is not None:
                    return (x, top), touched
        return None, touched

    def touch(self, x, y, goal):
        gx, gy = goal
        return (x < gx + 8 and x + self.w > gx and
                y < gy + self.p["goal_h"] and y + self.h > gy)

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


def char_can_finish(lvl, phys, ci, goal, helper):
    """Can character ci reach its goal, optionally with the other
    character available as a step stool? Returns (ok, width)."""
    sim = Sim(lvl, phys, ci)
    if helper is not None:
        hsim = Sim(lvl, phys, helper)
        _, footing = hsim.reachable(lvl.starts[helper], (0, 200))
        for feet, xs in footing.items():
            head_top = feet - phys["h"][helper]
            span_l, span_r = min(xs), max(xs) + phys["w"][helper]
            sim.extra.append((head_top, span_l, span_r))
    goal_states, _ = sim.reachable(lvl.starts[ci], goal)
    return len(goal_states) > 0, len(goal_states)


def check_level(idx, lvl, phys):
    problems = []
    for vi, goals in enumerate(lvl.goals):
        tag = "primary" if vi == 0 else "alternate"
        if lvl.cc == 1:
            ok, width = char_can_finish(lvl, phys, 0, goals[0], None)
            if not ok:
                problems.append(f"{tag}: Stella cannot reach her goal")
            elif width < MIN_GOAL_STATES:
                print(f"LEVEL {idx + 1}: WARNING {tag}: Stella's goal "
                      f"reachable from only {width} state(s)")
            continue
        s_solo, s_w = char_can_finish(lvl, phys, 0, goals[0], None)
        a_solo, a_w = char_can_finish(lvl, phys, 1, goals[1], None)
        s_help, s_hw = char_can_finish(lvl, phys, 0, goals[0], 1)
        a_help, a_hw = char_can_finish(lvl, phys, 1, goals[1], 0)
        s_help, s_hw = (s_help or s_solo), max(s_w, s_hw)
        a_help, a_hw = (a_help or a_solo), max(a_w, a_hw)
        for name, ok, width in (("Stella", s_help, s_hw),
                                ("Alex", a_help, a_hw)):
            if ok and width < MIN_GOAL_STATES:
                print(f"LEVEL {idx + 1}: WARNING {tag}: {name}'s goal "
                      f"reachable from only {width} state(s)")
        detail = (f"S(solo={s_solo},help={s_help}) "
                  f"A(solo={a_solo},help={a_help})")
        # someone must be able to go first (with help), and the other
        # must then finish alone — and the in-game exit-order lock, if
        # set, must enforce an order that actually works
        if lvl.exit_order == 1:      # Stella locked until Alex is home
            ok = a_help and s_solo
        elif lvl.exit_order == 2:    # Alex locked until Stella is home
            ok = s_help and a_solo
        else:
            ok = (s_help and a_solo) or (a_help and s_solo)
        if not ok:
            problems.append(f"{tag}: no completable exit order "
                            f"(lock={lvl.exit_order}) — {detail}")
        # a lock should exist wherever exactly one order works
        if lvl.exit_order == 0 and not (s_solo and a_solo):
            problems.append(f"{tag}: order matters but no exit-order "
                            f"lock is set — {detail}")
    return problems


def main():
    bin_path, sym_path, asm_path = sys.argv[1:4]
    levels, phys = load(bin_path, sym_path, asm_path)
    failed = False
    for i, rec in enumerate(levels):
        lvl = Level(rec)
        problems = check_level(i, lvl, phys)
        if problems:
            failed = True
            for p in problems:
                print(f"LEVEL {i + 1}: FAIL — {p}")
        else:
            print(f"LEVEL {i + 1}: ok")
    if failed:
        print("check-levels: FAILED")
        sys.exit(1)
    print(f"check-levels: all {len(levels)} levels solvable")


if __name__ == "__main__":
    main()
