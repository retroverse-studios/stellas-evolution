#!/usr/bin/env python3
"""Build-time solvability check for Stella Was Together's toggle floors.

Decision-gate (#9) prototype. A toggle floor is one room with TWO
geometries (world A / world B). The player swaps worlds by pushing UP
inside a portal x-range; every position persists in RAM across the
swap. This solver re-implements Stella's exact fixed-point physics
(ported byte-for-byte from Game 1's proven check_levels.py) and runs a
BFS over an (x, feet, world) state space to prove, for each floor:

  (a) SOLVABLE with switching ENABLED  — the goal is reachable, and
  (b) UNSOLVABLE with switching DISABLED — locked in the start world,
      the goal cannot be reached.

Both proofs must hold or the build fails: (a) guarantees the floor can
be finished, (b) guarantees the toggle is the reason — that the floor
is a genuine decision gate, not solvable by ordinary platforming.

Collision rules modelled exactly (as Game 1):
- solid boxes (top < bottom): block sideways movement (ClampBoxes,
  boxes iterated 5..0 with the pushed x cascading, 8-bit wrap on the
  left-edge push, then the unsigned MIN_X / MaxX clamp), head-bonk
  while rising (first hit 5..0 wins), and land-on-top while falling
- one-way shelves (top == bottom) / $FF pads never block or bonk
- the collision box set in force depends on the current world

Switching model (standing-state, portal-gated): from a standing state
whose x lies in the floor's portal range, the world flips; Stella then
settles under gravity in the new world (a switch over solid ground is a
no-op move; a switch out from under your feet drops you). This captures
T1 and T2. The mid-air switch (T3) is modelled by also offering a flip
at any airborne frame spent inside the portal column (see arc()).

Usage: python3 tools/check_levels.py build/stella-was-together.bin \
                build/main.sym src/main.asm
"""
import re
import sys

NUM_BOXES = 6
ROM_BASE = 0xF000
CI = 0                 # Stella is character 0


def load(bin_path, sym_path, asm_path):
    rom = open(bin_path, "rb").read()
    syms = {}
    for line in open(sym_path):
        m = re.match(r"^(\S+)\s+([0-9a-f]{4})", line.strip())
        if m:
            syms[m.group(1)] = int(m.group(2), 16)

    def u8(name, off=0):
        return rom[syms[name] - ROM_BASE + off]

    def bytes_at_addr(addr, n):
        return list(rom[addr - ROM_BASE:addr - ROM_BASE + n])

    asm = open(asm_path).read()

    def const(name, base=10):
        m = re.search(name + r"\s*=\s*\$?([0-9a-fA-F]+)", asm)
        return int(m.group(1), 16 if base == 16 or "$" in m.group(0) else 10)

    grav = int(re.search(r"GRAV_LO\s*=\s*\$([0-9a-fA-F]+)", asm).group(1), 16)
    min_x = int(re.search(r"MIN_X\s*=\s*(\d+)", asm).group(1))
    maxfall = int(re.search(r"MAXFALL\s*=\s*(\d+)", asm).group(1))
    num_floors = int(re.search(r"NUM_FLOORS\s*=\s*(\d+)", asm).group(1))
    wrap_w = int(re.search(r"WRAP_W\s*=\s*(\d+)", asm).group(1))
    wrap_hi = int(re.search(r"WRAP_HI\s*=\s*(\d+)", asm).group(1))

    phys = {
        "h": u8("HeightTbl", CI), "w": u8("WidthTbl", CI),
        "spd": u8("SpeedTbl", CI), "maxx": u8("MaxXTbl", CI),
        "jhi": u8("JumpHiTbl", CI), "jlo": u8("JumpLoTbl", CI),
        "grav": grav, "min_x": min_x, "maxfall": maxfall,
        "wrap_w": wrap_w, "wrap_hi": wrap_hi,
    }

    floors = []
    for f in range(1, num_floors):
        boxa = (u8("BoxAHiTbl", f) << 8) | u8("BoxALoTbl", f)
        boxb = (u8("BoxBHiTbl", f) << 8) | u8("BoxBLoTbl", f)
        floors.append({
            "idx": f,
            "start": (u8("StartXTbl", f), u8("StartYTbl", f)),
            "goal": (u8("GoalXTbl", f), u8("GoalYTbl", f)),
            "goal_h": u8("GoalHTbl", f),
            "portals": [(u8("PortalLTbl", f), u8("PortalRTbl", f)),
                        (u8("Portal2LTbl", f), u8("Portal2RTbl", f))],
            "boxes": [bytes_at_addr(boxa, 24), bytes_at_addr(boxb, 24)],
            "wrap": u8("WrapTbl", f),   # 1 = screen-wrap edges (W1)
            # 1 = in-screen portal (teleport) floor (P1); the two linked
            # portal mouths Stella jumps between (x, top-y).
            "teleport": u8("TeleportTbl", f),
            "mouthA": (u8("MouthAXTbl", f), u8("MouthAYTbl", f)),
            "mouthB": (u8("MouthBXTbl", f), u8("MouthBYTbl", f)),
        })
    return floors, phys


class World:
    """One world's collision boxes (SoA: 6 tops,6 bots,6 lefts,6 rights)."""
    def __init__(self, rec):
        self.tops = rec[0:6]
        self.bots = rec[6:12]
        self.lefts = rec[12:18]
        self.rights = rec[18:24]


class Sim:
    """Mirror of the 6502 physics (16-bit 8.8 vertical, integer x),
    parameterised by which world's boxes are in force."""

    def __init__(self, floor, phys):
        self.f, self.p = floor, phys
        self.h = phys["h"]
        self.w = phys["w"]
        self.spd = phys["spd"]
        self.maxx = phys["maxx"]
        j = (phys["jhi"] << 8) | phys["jlo"]
        self.jump = j - 0x10000 if j & 0x8000 else j
        self.grav = phys["grav"]
        self.maxfall = phys["maxfall"] << 8
        self.worlds = [World(floor["boxes"][0]), World(floor["boxes"][1])]
        self.portals = floor["portals"]
        # in-screen portal (P1): teleport the standing state between the
        # two linked mouths instead of swapping worlds.
        self.teleport = floor["teleport"]
        self.mouthA = floor["mouthA"]   # (x, top-y)
        self.mouthB = floor["mouthB"]
        self.gx, self.gy = floor["goal"]
        self.gh = floor["goal_h"]
        self.wrap_w = phys["wrap_w"]
        self.wrap_hi = phys["wrap_hi"]
        # Runtime edge mode, toggled by main() for the wrap floor's two
        # proofs: True mirrors the engine's modular-x wrap, False falls
        # back to the MIN_X / MaxX clamp (edges treated as walls).
        self.wrap_active = False

    def in_portal(self, x):
        return any(l <= x < r for l, r in self.portals)

    def in_portal_a(self, x):
        l, r = self.portals[0]
        return l <= x < r

    def in_portal_b(self, x):
        l, r = self.portals[1]
        return l <= x < r

    def clamp_x(self, w, x, new_x, y, direction):
        cyh = y + self.h
        new_x &= 0xFF
        for i in range(NUM_BOXES - 1, -1, -1):
            top, bot = w.tops[i], w.bots[i]
            if bot == top:
                continue
            if bot <= y or top >= cyh:
                continue
            l, r = w.lefts[i], w.rights[i]
            if new_x >= r or new_x + self.w <= l:
                continue
            new_x = ((l - self.w) & 0xFF) if direction > 0 else r
        if self.wrap_active:
            # modular-x, byte-for-byte with the ReadInput .wrapEdge path
            if new_x >= self.wrap_hi:
                new_x = (new_x + self.wrap_w) & 0xFF   # left underflow
            elif new_x >= self.wrap_w:
                new_x = (new_x - self.wrap_w) & 0xFF   # right overflow
            return new_x
        if new_x < self.p["min_x"]:
            new_x = self.p["min_x"]
        if new_x >= self.maxx:
            new_x = self.maxx
        return new_x

    def surfaces(self, w):
        for i in range(NUM_BOXES - 1, -1, -1):
            if w.tops[i] != 0xFF:
                yield (w.tops[i], w.lefts[i], w.rights[i])

    def solids(self, w):
        for i in range(NUM_BOXES - 1, -1, -1):
            if w.bots[i] != w.tops[i]:
                yield (w.tops[i], w.bots[i], w.lefts[i], w.rights[i])

    def landing(self, w, prev_feet, new_feet, x):
        for top, l, r in self.surfaces(w):
            if prev_feet <= top <= new_feet and x < r and x + self.w > l:
                return top
        return None

    def touch(self, x, y):
        return (x < self.gx + 8 and x + self.w > self.gx and
                y < self.gy + self.gh and y + self.h > self.gy)

    def simulate(self, world, x, feet, jump, direction, switch_frame):
        """One jump/fall in `world`, constant direction. If switch_frame
        is not None, toggle the world at that airborne frame with vy and
        position preserved (a true momentum-keeping mid-air switch).
        Returns (land_world, land_x, land_feet, touched, portal_frames)
        where portal_frames lists the airborne frames spent inside the
        portal column BEFORE any switch — the candidate switch instants."""
        y256 = (feet - self.h) << 8
        vy = self.jump if jump else 0
        touched = self.touch(x, y256 >> 8)
        cur = world
        w = self.worlds[cur]
        portal_frames = []
        for frame in range(600):
            if direction:
                x = self.clamp_x(w, x, x + direction * self.spd,
                                 y256 >> 8, direction)
            if switch_frame is None and self.in_portal(x):
                portal_frames.append(frame)
            if switch_frame is not None and frame == switch_frame:
                cur = 1 - cur
                w = self.worlds[cur]
            prev_feet = (y256 >> 8) + self.h
            vy = min(vy + self.grav, self.maxfall)
            y256 += vy
            if y256 < 0:
                y256, vy = 0, 0
            y = y256 >> 8
            if y > 120:
                return (cur, None, None, touched, portal_frames)
            touched |= self.touch(x, y)
            if vy < 0:
                prev_top = prev_feet - self.h
                for top, bot, l, r in self.solids(w):
                    if prev_top >= bot > y and x < r and x + self.w > l:
                        y256, vy = bot << 8, 0
                        y = bot
                        break
            else:
                top = self.landing(w, prev_feet, y + self.h, x)
                if top is not None:
                    return (cur, x, top, touched, portal_frames)
        return (cur, None, None, touched, portal_frames)

    def arc(self, world, x, feet, jump, direction, allow_switch):
        """Yield (world, land_x, land_feet, touched) for the no-switch
        arc and, if allow_switch, one variant per airborne portal frame
        in which Stella flips worlds at that instant (single switch)."""
        base = self.simulate(world, x, feet, jump, direction, None)
        yield base[:4]
        if allow_switch:
            for fr in base[4]:
                out = self.simulate(world, x, feet, jump, direction, fr)
                yield out[:4]

    def reachable(self, allow_switch):
        """BFS over standing (grounded) states. The goal counts only
        when Stella is STANDING on it — mirroring the engine's grounded
        CheckGoal — so merely arcing through the marker's airspace (in a
        world where no platform is there) is NOT a win. That grounded
        rule is what forces T3's switch to happen mid-air: the only
        standing state over the goal exists in the other world."""
        sx, sy = self.f["start"]
        start = (sx, sy + self.h, 0)   # (x, feet, world) — world A
        seen = set()
        stack = [start]
        while stack:
            st = stack.pop()
            if st in seen:
                continue
            seen.add(st)
            x, feet, world = st
            if self.touch(x, feet - self.h):
                return True            # grounded on the marker: solved
            w = self.worlds[world]
            # in-screen PORTAL (P1): UP inside a portal column teleports
            # the standing state to the OTHER column's mouth — SAME world,
            # no swap. She arrives standing on the mouth's platform.
            if allow_switch and self.teleport:
                if self.in_portal_a(x):
                    mx, my = self.mouthB
                    stack.append((mx, my + self.h, world))
                elif self.in_portal_b(x):
                    mx, my = self.mouthA
                    stack.append((mx, my + self.h, world))
            # portal-gated standing WORLD-SWITCH (T*): flip world, settle
            elif allow_switch and self.in_portal(x):
                for ow, lx, lf, _ in self.arc(1 - world, x, feet,
                                              False, 0, False):
                    if lx is not None:
                        stack.append((lx, lf, ow))
            # world-flip mid-arc is meaningless on the single-world portal
            # floor (both box sets are identical), so suppress it there.
            arc_switch = allow_switch and not self.teleport
            # walk one step each way
            for d in (-1, 1):
                nx = self.clamp_x(w, x, x + d * self.spd, feet - self.h, d)
                if nx != x:
                    if self.landing(w, feet, feet, nx) is not None:
                        stack.append((nx, feet, world))
                    else:
                        for ow, lx, lf, _ in self.arc(world, x, feet,
                                                      False, d, arc_switch):
                            if lx is not None:
                                stack.append((lx, lf, ow))
            # jumps: left / straight / right
            for d in (-1, 0, 1):
                for ow, lx, lf, _ in self.arc(world, x, feet, True, d,
                                              arc_switch):
                    if lx is not None:
                        stack.append((lx, lf, ow))
        return False


def main():
    bin_path, sym_path, asm_path = sys.argv[1:4]
    floors, phys = load(bin_path, sym_path, asm_path)
    failed = False
    wrap_n = 0
    portal_n = 0
    for fl in floors:
        sim = Sim(fl, phys)
        if fl["teleport"]:
            # In-screen portal floor: prove the puzzle needs the portal.
            # With the portal ON the goal (on a floating high shelf) is
            # reachable — stand in portal A, teleport to B up top, walk to
            # the marker. With the portal OFF the shelf cannot be reached
            # by walking or jumping, so the goal is unreachable: the
            # teleport is genuinely load-bearing, not a shortcut past an
            # already-solvable floor.
            portal_n += 1
            name = "P%d" % portal_n
            with_portal = sim.reachable(allow_switch=True)
            without_portal = sim.reachable(allow_switch=False)
            ok = with_portal and not without_portal
            print("FLOOR %s: portal ON -> %s ; portal OFF -> %s : %s"
                  % (name,
                     "SOLVABLE" if with_portal else "unsolvable",
                     "SOLVABLE" if without_portal else "unsolvable",
                     "ok (portal genuinely required)" if ok else "FAIL"))
            if not with_portal:
                print("  FAIL: %s is not solvable even with the portal"
                      % name)
            if without_portal:
                print("  FAIL: %s is solvable WITHOUT the portal — not a "
                      "gate" % name)
            failed = failed or not ok
            continue
        if fl["wrap"]:
            # Wrap floor: prove the puzzle needs the screen-wrap. With
            # wrap ON the marker is reachable (walk off one edge, come
            # back the other); with the edges treated as WALLS (clamp)
            # the central wall boxes Stella in and the marker is not
            # reachable — so the wrap is genuinely required, not decor.
            wrap_n += 1
            name = "W%d" % wrap_n
            sim.wrap_active = True
            with_wrap = sim.reachable(allow_switch=False)
            sim.wrap_active = False
            without_wrap = sim.reachable(allow_switch=False)
            ok = with_wrap and not without_wrap
            print("FLOOR %s: wrap ON -> %s ; wrap OFF -> %s : %s"
                  % (name,
                     "SOLVABLE" if with_wrap else "unsolvable",
                     "SOLVABLE" if without_wrap else "unsolvable",
                     "ok (wrap genuinely required)" if ok else "FAIL"))
            if not with_wrap:
                print("  FAIL: %s is not solvable even with wrap" % name)
            if without_wrap:
                print("  FAIL: %s is solvable WITHOUT wrap — not a gate"
                      % name)
            failed = failed or not ok
            continue
        with_sw = sim.reachable(allow_switch=True)
        without_sw = sim.reachable(allow_switch=False)
        name = "T%d" % fl["idx"]
        ok = with_sw and not without_sw
        print("FLOOR %s: switching ON -> %s ; switching OFF -> %s : %s"
              % (name,
                 "SOLVABLE" if with_sw else "unsolvable",
                 "SOLVABLE" if without_sw else "unsolvable",
                 "ok (genuine decision gate)" if ok else "FAIL"))
        if not with_sw:
            print("  FAIL: %s is not solvable even with the toggle" % name)
        if without_sw:
            print("  FAIL: %s is solvable WITHOUT the toggle — not a gate"
                  % name)
        failed = failed or not ok
    if failed:
        print("check-levels: FAILED")
        sys.exit(1)
    print("check-levels: all %d prototype floor(s) proved both ways"
          % len(floors))


if __name__ == "__main__":
    main()
