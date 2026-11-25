#!/usr/bin/env python3
"""Run the assembled ROM itself, headlessly.

A small 6502 with the RIOT timer and the input and audio registers this
game uses, driven one frame at a time. Nothing is drawn, but cycles are
counted: a WSYNC sleeps to the end of its scanline, so a kernel line that
runs past 76 cycles shows, and so does logic that outlasts the vertical
blank. What it is for is everything that happens in that blank — the
state machine, input edges, physics, the goal rule, the clock, and what
goes to the speaker — for the reset routine, and for the kernels' budget.

    python3 tools/headless.py build/stella-was-alone.bin build/main.sym
        plays the game through every screen and checks what it does
    python3 tools/headless.py A.bin A.sym --compare B.bin B.sym
        feeds both ROMs the same random input, frame for frame, and
        reports the first frame on which their memory differs

It is not Stella and not a console. It cannot hear the tune or see the
picture, its cycle counts are only as good as its table (branches and
page crossings included, no undefined behaviour), and it does not model
the TIA: a register written after the beam has passed is not noticed. On
its first outing it found four faults that reading the
source had not: a rest that played the chip's highest note, a 32-step
table indexed by a counter that could only count to seven, a tune that
would not let go of the completion beat, and a reset routine that had
never cleared RAM.

Usage: python3 tools/headless.py ROM SYM [--compare ROM SYM]
                                       [--frames N] [--runs K] [--quiet]
"""
import argparse
import random
import re
import sys

# ---------------------------------------------------------------------
# The 6502: the 151 documented opcodes, by mnemonic and addressing mode.
# ---------------------------------------------------------------------
_ALU = ["izx", "zp", "imm", "abs", "izy", "zpx", "aby", "abx"]   # in bbb order
_ROWS = [("ORA", _ALU, "01 05 09 0D 11 15 19 1D"), ("AND", _ALU, "21 25 29 2D 31 35 39 3D"),
         ("EOR", _ALU, "41 45 49 4D 51 55 59 5D"), ("ADC", _ALU, "61 65 69 6D 71 75 79 7D"),
         ("STA", ["zp", "zpx", "abs", "aby", "abx", "izx", "izy"], "85 95 8D 99 9D 81 91"),
         ("LDA", _ALU, "A1 A5 A9 AD B1 B5 B9 BD"), ("CMP", _ALU, "C1 C5 C9 CD D1 D5 D9 DD"),
         ("SBC", _ALU, "E1 E5 E9 ED F1 F5 F9 FD"),
         ("ASL", ["acc", "zp", "zpx", "abs", "abx"], "0A 06 16 0E 1E"),
         ("ROL", ["acc", "zp", "zpx", "abs", "abx"], "2A 26 36 2E 3E"),
         ("LSR", ["acc", "zp", "zpx", "abs", "abx"], "4A 46 56 4E 5E"),
         ("ROR", ["acc", "zp", "zpx", "abs", "abx"], "6A 66 76 6E 7E"),
         ("STX", ["zp", "zpy", "abs"], "86 96 8E"),
         ("LDX", ["imm", "zp", "zpy", "abs", "aby"], "A2 A6 B6 AE BE"),
         ("DEC", ["zp", "zpx", "abs", "abx"], "C6 D6 CE DE"),
         ("INC", ["zp", "zpx", "abs", "abx"], "E6 F6 EE FE"),
         ("BIT", ["zp", "abs"], "24 2C"), ("JMP", ["abs", "ind"], "4C 6C"),
         ("STY", ["zp", "zpx", "abs"], "84 94 8C"),
         ("LDY", ["imm", "zp", "zpx", "abs", "abx"], "A0 A4 B4 AC BC"),
         ("CPY", ["imm", "zp", "abs"], "C0 C4 CC"), ("CPX", ["imm", "zp", "abs"], "E0 E4 EC")]
OPS = {}
for name, modes, codes in _ROWS:
    for mode, code in zip(modes, codes.split()):
        OPS[int(code, 16)] = (name, mode)
for name, code in [("BPL", "10"), ("BMI", "30"), ("BVC", "50"), ("BVS", "70"), ("BCC", "90"),
                   ("BCS", "B0"), ("BNE", "D0"), ("BEQ", "F0")]:
    OPS[int(code, 16)] = (name, "rel")
for code, name in [(0x18, "CLC"), (0x38, "SEC"), (0x58, "CLI"), (0x78, "SEI"), (0xB8, "CLV"),
                   (0xD8, "CLD"), (0xF8, "SED"), (0x48, "PHA"), (0x08, "PHP"), (0x68, "PLA"),
                   (0x28, "PLP"), (0xAA, "TAX"), (0xA8, "TAY"), (0xBA, "TSX"), (0x8A, "TXA"),
                   (0x9A, "TXS"), (0x98, "TYA"), (0xCA, "DEX"), (0x88, "DEY"), (0xE8, "INX"),
                   (0xC8, "INY"), (0xEA, "NOP")]:
    OPS[code] = (name, "imp")
OPS.update({0x00: ("BRK", "imp"), 0x20: ("JSR", "jsr"), 0x40: ("RTI", "rti"), 0x60: ("RTS", "rts")})
assert len(OPS) == 151
RMW = {"ASL", "ROL", "LSR", "ROR", "DEC", "INC"}
_CYCLES = {"imm": 2, "zp": 3, "zpx": 4, "zpy": 4, "abs": 4, "abx": 4, "aby": 4,
           "izx": 6, "izy": 5, "ind": 5}


class Machine:
    """Registers, 64K of memory, and what this game touches of the outside
    world: SWCHA, SWCHB, INPT4, INPT5, the RIOT timer, and the six audio
    registers (kept where the ROM leaves them, in .aud, as
    AUDC0 AUDC1 AUDF0 AUDF1 AUDV0 AUDV1)."""

    def __init__(self, rom):
        self.m = bytearray(0x10000)
        self.m[0xF000:0x10000] = rom
        self.a = self.x = self.y = 0
        self.sp = 0xFD
        self.n = self.v = self.d = self.i = self.z = self.c = 0
        self.pc = self.m[0xFFFC] | self.m[0xFFFD] << 8
        self.timer = 0
        self.interval = 64
        self.frac = 0
        self.expired = True
        self.swcha = 0xFF
        self.swchb = 0xFF
        self.inpt4 = 0x80
        self.inpt5 = 0x80
        self.aud = [0] * 6
        self.cycles = 0          # cycles run, sleeps on WSYNC included
        self.linepos = 0         # cycles since the scanline began
        self.wsyncs = []         # (pc after the write, cycle it landed on, after a timer wait?)
        self._wsync = None
        self.waited = False      # TIMINT read since the last WSYNC
        self.colupf = []         # (cycle, value) of every COLUPF write
        self.overruns = 0        # frames whose logic outlasted the vertical blank
        self._timer_v = 0
        self._first_read = False

    def flag(self, v):
        v &= 0xFF
        self.z = int(v == 0)
        self.n = v >> 7
        return v

    def read(self, addr):
        addr &= 0xFFFF
        if addr == 0x284:                       # INTIM
            self.expired = False
            return self.timer & 0xFF
        if addr == 0x285:                       # TIMINT
            if self._first_read and self._timer_v == 44 and self.expired:
                self.overruns += 1             # the flag was up before the wait began
            self._first_read = False
            self.waited = True
            v = 0x80 if self.expired else 0
            self.expired = False
            return v
        if addr == 0x280:
            return self.swcha
        if addr == 0x282:
            return self.swchb
        if addr == 0x3C:
            return self.inpt4
        if addr == 0x3D:
            return self.inpt5
        return self.m[addr]

    def write(self, addr, v):
        addr &= 0xFFFF
        v &= 0xFF
        if addr in (0x294, 0x295, 0x296, 0x297):   # the 8 / 16 / 64 / 1024 cycle timers
            self.interval = {0x294: 8, 0x295: 16, 0x296: 64, 0x297: 1024}[addr]
            self.timer = v
            self.frac = 0
            self.expired = False
            self._timer_v, self._first_read = v, True
            return
        audio = (0x15, 0x16, 0x17, 0x18, 0x19, 0x1A)
        if addr in audio:
            self.aud[audio.index(addr)] = v
        self.m[addr] = v
        if addr == 0x02:                      # WSYNC
            self._wsync = self.pc
        elif addr == 0x08:                    # COLUPF
            self.colupf.append((self.cycles, v))

    def push(self, v):
        self.m[0x100 | self.sp] = v & 0xFF
        self.sp = (self.sp - 1) & 0xFF

    def pull(self):
        self.sp = (self.sp + 1) & 0xFF
        return self.m[0x100 | self.sp]

    def ea(self, mode):
        """(effective address, page crossed); advances past the operand."""
        pc = self.pc
        if mode == "imm":
            self.pc = (pc + 1) & 0xFFFF
            return pc, False
        if mode in ("zp", "zpx", "zpy", "izx", "izy"):
            b = self.m[pc]
            self.pc = (pc + 1) & 0xFFFF
            if mode in ("zpx", "zpy"):
                return (b + (self.x if mode == "zpx" else self.y)) & 0xFF, False
            if mode == "zp":
                return b, False
            z = (b + self.x) & 0xFF if mode == "izx" else b
            base = self.m[z] | self.m[(z + 1) & 0xFF] << 8
            if mode == "izx":
                return base, False
            e = (base + self.y) & 0xFFFF
            return e, (e & 0xFF00) != (base & 0xFF00)
        a = self.m[pc] | self.m[(pc + 1) & 0xFFFF] << 8
        self.pc = (pc + 2) & 0xFFFF
        if mode == "abs":
            return a, False
        if mode == "ind":
            return self.m[a] | self.m[(a & 0xFF00) | ((a + 1) & 0xFF)] << 8, False
        e = (a + (self.x if mode == "abx" else self.y)) & 0xFFFF
        return e, (e & 0xFF00) != (a & 0xFF00)

    def step(self):
        op = self.m[self.pc]
        self.pc = (self.pc + 1) & 0xFFFF
        name, mode = OPS[op]
        cross, e = False, None
        if mode in ("imp", "acc"):
            cyc = 2
        elif mode == "rel":
            off = self.m[self.pc]
            self.pc = (self.pc + 1) & 0xFFFF
            e, cyc = off - 256 if off > 127 else off, 2
        elif mode == "jsr":
            e, _ = self.ea("abs")
            cyc = 6
        elif mode in ("rts", "rti"):
            cyc = 6
        else:
            e, cross = self.ea(mode)
            cyc = _CYCLES[mode]
            if name in RMW:
                cyc += 2
            if name in ("STA", "STX", "STY") and mode in ("abx", "aby", "izy"):
                cyc += 1
        a = self.a
        m = a if mode == "acc" else (self.read(e) if e is not None and mode != "rel" else 0)
        if name in ("LDA", "LDX", "LDY"):
            self.flag(m)
            if name == "LDA":
                self.a = m
            elif name == "LDX":
                self.x = m
            else:
                self.y = m
        elif name == "STA":
            self.write(e, a)
        elif name == "STX":
            self.write(e, self.x)
        elif name == "STY":
            self.write(e, self.y)
        elif name in ("AND", "ORA", "EOR"):
            self.a = self.flag({"AND": a & m, "ORA": a | m, "EOR": a ^ m}[name])
        elif name in ("ADC", "SBC"):
            mm = m if name == "ADC" else m ^ 0xFF
            t = a + mm + self.c
            self.v = int(bool(~(a ^ mm) & (a ^ t) & 0x80))
            self.c = int(t > 0xFF)
            self.a = self.flag(t)
        elif name in ("CMP", "CPX", "CPY"):
            r = {"CMP": a, "CPX": self.x, "CPY": self.y}[name]
            self.c = int(r >= m)
            self.flag(r - m)
        elif name == "BIT":
            self.z = int((a & m) == 0)
            self.n = m >> 7
            self.v = (m >> 6) & 1
        elif name in RMW:
            if name == "DEC":
                v = (m - 1) & 0xFF
            elif name == "INC":
                v = (m + 1) & 0xFF
            else:
                c = self.c
                if name == "ASL":
                    self.c, v = m >> 7, (m << 1) & 0xFF
                elif name == "LSR":
                    self.c, v = m & 1, m >> 1
                elif name == "ROL":
                    self.c, v = m >> 7, ((m << 1) | c) & 0xFF
                else:
                    self.c, v = m & 1, (m >> 1) | (c << 7)
            if mode == "acc":
                self.a = self.flag(v)
            else:
                self.write(e, v)
                self.flag(v)
        elif name == "JMP":
            self.pc = e
        elif name == "JSR":
            r = (self.pc - 1) & 0xFFFF
            self.push(r >> 8)
            self.push(r)
            self.pc = e
        elif name == "RTS":
            lo = self.pull()
            self.pc = (((self.pull() << 8) | lo) + 1) & 0xFFFF
        elif name == "RTI":
            self._pull_p()
            lo = self.pull()
            self.pc = self.pull() << 8 | lo
        elif name == "BRK":
            self.i = 1
            self.pc = (self.pc + 1) & 0xFFFF
            self.push(self.pc >> 8)
            self.push(self.pc)
            self.push(0x30)
            self.pc = self.read(0xFFFE) | self.read(0xFFFF) << 8
        elif name[0] == "B":                   # the eight branches (BIT, BRK: above)
            if {"BPL": self.n == 0, "BMI": self.n, "BVC": self.v == 0, "BVS": self.v,
                    "BCC": self.c == 0, "BCS": self.c, "BNE": self.z == 0, "BEQ": self.z}[name]:
                cyc += 1 + int((self.pc & 0xFF00) != ((self.pc + e) & 0xFF00))
                self.pc = (self.pc + e) & 0xFFFF
        elif name == "PHA":
            self.push(a)
        elif name == "PHP":
            self.push(0x20 | self.n << 7 | self.v << 6 | 0x10 | self.d << 3 | self.i << 2
                      | self.z << 1 | self.c)
        elif name == "PLA":
            self.a = self.flag(self.pull())
        elif name == "PLP":
            self._pull_p()
        elif name == "TAX":
            self.x = self.flag(a)
        elif name == "TAY":
            self.y = self.flag(a)
        elif name == "TSX":
            self.x = self.flag(self.sp)
        elif name == "TXA":
            self.a = self.flag(self.x)
        elif name == "TXS":
            self.sp = self.x
        elif name == "TYA":
            self.a = self.flag(self.y)
        elif name == "DEX":
            self.x = self.flag(self.x - 1)
        elif name == "DEY":
            self.y = self.flag(self.y - 1)
        elif name == "INX":
            self.x = self.flag(self.x + 1)
        elif name == "INY":
            self.y = self.flag(self.y + 1)
        elif name in ("CLC", "SEC", "CLI", "SEI", "CLV", "CLD", "SED"):
            setattr(self, {"CLC": "c", "SEC": "c", "CLI": "i", "SEI": "i", "CLV": "v",
                           "CLD": "d", "SED": "d"}[name], int(name in ("SEC", "SEI", "SED")))
        if cross and name not in ("STA", "STX", "STY"):
            cyc += 1
        self.cycles += cyc
        self.linepos += cyc
        if self._wsync is not None:       # the write is the instruction's last cycle
            idx = self.linepos - 1
            self.wsyncs.append((self._wsync, idx, self.waited))
            self._wsync = None
            self.linepos = 0
            self.waited = False
            cyc += 75 - idx % 76         # and the CPU sleeps to the end of the line
        self.frac += cyc
        while self.frac >= self.interval:
            self.frac -= self.interval
            self.timer = (self.timer - 1) & 0xFF
            if self.timer == 0xFF:
                self.expired = True

    def _pull_p(self):
        p = self.pull()
        self.n, self.v, self.d, self.i, self.z, self.c = [(p >> k) & 1 for k in (7, 6, 3, 2, 1, 0)]


def symbols(path):
    """DASM's symbol file: labels and = constants alike, name -> value."""
    out = {}
    for line in open(path):
        m = re.match(r"^(\S+)\s+([0-9a-f]{4})", line.strip())
        if m:
            out[m.group(1)] = int(m.group(2), 16)
    return out


# ---------------------------------------------------------------------
# Driving it a frame at a time.
# ---------------------------------------------------------------------
STICK = {"R": 0x80, "L": 0x40, "D": 0x20, "U": 0x10}   # SWCHA bits, active low


class Run:
    """One powered-on machine. A frame is one trip round MainLoop:
    logic, kernel and overscan."""

    def __init__(self, rom, sym, fill=None):
        self.m = Machine(rom)
        self.sym = sym
        self.ram = {k: v for k, v in sym.items() if 0x80 <= v <= 0xFF}
        self.loop = sym["MainLoop"]
        self.frame = 0
        self.audio = []            # (frame, AUDC1, AUDF1, AUDV1, State) while recording
        self.trace = []            # (frame, State, RAM, audio registers) every frame
        self.record_audio = False
        if fill:                   # power-on RAM, before the reset routine runs
            fill(self.m)
        guard = 0
        while self.m.pc != self.loop:
            self.m.step()
            guard += 1
            if guard > 100000:
                sys.exit(f"the reset routine never reached MainLoop (pc {self.m.pc:04x})")

    def r(self, name):
        return self.m.m[self.ram[name]]

    def w(self, name, v):
        self.m.m[self.ram[name]] = v & 0xFF

    def step_frame(self, stick="", fire=False, select=False, reset=False, timed=False):
        """Run one frame with these inputs; -> the State it ended in."""
        m = self.m
        m.swcha = 0xFF
        for k in stick:
            m.swcha &= ~STICK[k]
        m.inpt4 = 0 if fire else 0x80
        # SWCHB: bit 0 RESET and bit 1 SELECT are active low; bit 6, the
        # left difficulty switch, reads 1 in the A position (the timed one)
        m.swchb = 0xFF & ~(2 if select else 0) & ~(1 if reset else 0) & ~(0 if timed else 0x40)
        state = self.r("State")
        self.trace.append((self.frame, state, bytes(m.m[0x80:0x100]), tuple(m.aud)))
        if self.record_audio:
            self.audio.append((self.frame, m.aud[1], m.aud[3], m.aud[5], state))
        assert m.pc == self.loop
        guard = 0
        while True:
            if m.pc == self.loop and guard:
                break
            m.step()
            guard += 1
            if guard > 400000:
                sys.exit(f"frame {self.frame} never ended (pc {m.pc:04x})")
        self.frame += 1
        return self.r("State")

    def goto_goals(self):
        """Put every present shape standing on its own light (as if played
        there), with no motion left in it."""
        m, s = self.m, self.sym
        for i in range(self.r("CharCount")):
            m.m[self.ram["CharX"] + i] = m.m[self.ram["GoalX"] + i]
            m.m[self.ram["CharY"] + i] = (m.m[self.ram["GoalY"] + i] + s["GOAL_H"]
                                          - (s["STELLA_H"] if i == 0 else s["ALEX_H"])) & 0xFF
            m.m[self.ram["CharYLo"] + i] = 0
            m.m[self.ram["CharVYHi"] + i] = 0
            m.m[self.ram["CharVYLo"] + i] = 0
            m.m[self.ram["OnGround"] + i] = 1


# ---------------------------------------------------------------------
# The walkthrough: every screen, in order, with what must be true.
# ---------------------------------------------------------------------
class Checks:
    def __init__(self, quiet=False):
        self.fails, self.quiet, self.n = [], quiet, 0

    def that(self, label, ok, detail=""):
        self.n += 1
        if not self.quiet or not ok:
            print(f"  {'ok  ' if ok else 'FAIL'}  {label}{(' - ' + detail) if detail else ''}")
        if not ok:
            self.fails.append(label)
        return ok


def heard(run, frames, step, **inputs):
    """Record `frames` frames of play and lay them on the tune's grid:
    from the first struck note, one sample every `step` frames."""
    start = run.frame
    run.record_audio = True
    for _ in range(frames):
        run.step_frame(**inputs)
    rec, run.audio = run.audio, []
    run.record_audio = False
    play = [(f - start, c, p, v) for f, c, p, v, st in rec if st == 1]
    if not play:
        return []
    s0 = next((i for i in range(1, len(play)) if play[i][3] == 5 and play[i - 1][3] != 5), None)
    if s0 is None:
        return []
    per = []
    for k in range((len(play) - s0 - step) // step):
        i = s0 + step * k
        per.append((None if play[i][3] == 0 else play[i][2],
                    [play[i + j][3] for j in range(step)], play[i][1]))
    return per


def rotation_of(table, pitches):
    """Is `pitches` the `table` (None = a rest) gone round from anywhere?"""
    long = table * (len(pitches) // len(table) + 2)
    return any((long[k:] + long[:k])[:len(pitches)] == pitches for k in range(len(table)))


def struck_right(per, step, strike):
    return (all(v[0] in (0, 5) for p, v, c in per)                       # every step starts on its own frame
            and all(v[:strike] == [5] * strike and v[strike:] == [2] * (step - strike)
                    for p, v, c in per if p is not None)
            and all(v == [0] * step for p, v, c in per if p is None))


def walkthrough(rom, sym, quiet=False):
    c = Checks(quiet)
    T, P, D, W, S = (sym[f"STATE_{k}"] for k in ("TITLE", "PLAY", "DONE", "WIN", "STORY"))

    def junk(machine):                  # power-on RAM that is anything but zeroed
        q = random.Random(7)
        for a in range(0x80, 0x100):
            machine.m[a] = q.randrange(1, 256)

    b = Run(rom, sym, fill=junk)
    c.that("a cold boot with garbage in RAM comes up on the title",
           b.r("State") == T and b.r("TimedFlag") == 0, f"State {b.r('State')}")
    for _ in range(3):
        b.step_frame()
    c.that("and takes fire there like any other boot", b.step_frame(fire=True) == S)

    r = Run(rom, sym)
    x1 = lambda: r.m.m[r.ram["CharX"] + 1]           # Alex's, when he is there
    vy = lambda i: r.m.m[r.ram["CharVYHi"] + i]
    for _ in range(5):
        r.step_frame()
    c.that("the title holds, channel 1 silent", r.r("State") == T and r.m.aud[5] == 0)
    for _ in range(9):
        r.step_frame(fire=True)
    c.that("fire on the title opens the first story screen", r.r("State") == S and r.r("Level") == 0)
    c.that("holding fire does not skip the story screen", r.r("State") == S)
    for _ in range(3):
        r.step_frame()
    r.step_frame(fire=True)
    for _ in range(4):
        r.step_frame(fire=True)
    c.that("a new press starts play; still-held fire does not jump",
           r.r("State") == P and r.r("OnGround") == 1 and vy(0) == 0)
    x0 = r.r("CharX")
    for _ in range(15):
        r.step_frame("R")
    c.that("right walks Stella 1 px a frame", r.r("CharX") == x0 + 15, f"x {x0} -> {r.r('CharX')}")
    for _ in range(40):
        r.step_frame("L")
    c.that("left walks her back to the wall", r.r("CharX") == 4, f"x -> {r.r('CharX')}")

    # ---- the tune, as the ROM plays it -------------------------------
    # ---- the tune, as the ROM plays it -------------------------------
    tempo, strike, hurry = sym.get("TEMPO", 4), sym.get("STRIKE", 2), sym.get("HURRY", 1)
    table = [None if b & 0x80 else b for b in rom[sym["Tune"] - 0xF000:sym["Tune"] - 0xF000 + 32]]
    step = 1 << tempo
    per = heard(r, 1100, step)
    c.that(f"the tune keeps a {step}-frame grid for 1,100 frames ({len(per)} steps)",
           struck_right(per, step, strike))
    c.that("the notes are the table in the ROM, in order",
           rotation_of(table, [p for p, _, _ in per]), f"first {[p for p, _, _ in per][:12]}")
    c.that("it is a pure tone (AUDC 12)", all(cc == 12 for _, _, cc in per))
    if hurry:
        per = heard(r, 300, step // 2, timed=True)
        c.that("timed mode with the clock still high: the tune does not hurry yet",
               not (rotation_of(table, [p for p, _, _ in per]) and struck_right(per, step // 2, max(strike // 2, 1))))
        r.w("TimerSec", 10)
        per = heard(r, 400, step // 2, timed=True)
        c.that("under time pressure the tune runs twice as fast",
               rotation_of(table, [p for p, _, _ in per]), f"first {[p for p, _, _ in per][:12]}")
        c.that("struck shorter there", struck_right(per, step // 2, max(strike // 2, 1)))
        r.w("TimerSec", 60)

    jumps, was = 0, True
    for _ in range(100):
        r.step_frame(fire=True)
        air = r.r("OnGround") == 0
        jumps += air and was
        was = not air
    c.that("fire held for 100 frames jumps exactly once", jumps == 1, f"{jumps} jumps")
    c.that("after a held jump she is grounded again", r.r("OnGround") == 1)

    # ---- the completion beat -----------------------------------------
    r.goto_goals()
    c.that("standing on the light completes the level", r.step_frame() == D)
    c.that("the fanfare is the sound of the beat", r.r("SoundId") == 3 and r.m.aud[4] > 0)
    r.step_frame()
    vols = set()
    for _ in range(69):
        vols.add(r.m.aud[5])
        r.step_frame()
    c.that("channel 1 is silent for the completion beat", vols == {0}, str(vols))
    while r.step_frame() == D:
        pass
    c.that("the beat ends on the next level's story screen", r.r("State") == S and r.r("Level") == 1)

    # ---- two shapes ---------------------------------------------------
    r.w("Level", 2)
    r.step_frame(fire=True)
    r.step_frame()
    c.that("a two-shape level loads both shapes",
           r.r("State") == P and r.r("CharCount") == 2 and r.r("Active") == 0)
    sky, pf = sym["COL_SKY"], sym["COL_PF"]
    i = len(r.m.colupf)
    r.step_frame()
    bands = [v for _, v in r.m.colupf[i:]]
    c.that("one colour write a band, the top three the dim sky and the nine below the world",
           bands == [sky] * 4 + [pf] * 9, str([hex(v) for v in bands]))
    r.step_frame("D", fire=True)
    r.step_frame()
    c.that("down + fire switches to Alex without a jump", r.r("Active") == 1 and vy(0) == 0 and vy(1) == 0)
    r.step_frame("D", fire=True)
    r.step_frame()
    c.that("and back to Stella", r.r("Active") == 0)
    r.step_frame("D", fire=True)
    r.step_frame()
    xa = x1()
    for _ in range(10):
        r.step_frame("R")
    c.that("Alex walks 2 px a frame", x1() == xa + 20, f"x {xa} -> {x1()}")
    xs = r.r("CharX")
    for _ in range(5):
        r.step_frame("R")
    c.that("while Stella, not being controlled, stays put", r.r("CharX") == xs)
    r.step_frame(fire=True)
    r.step_frame()
    c.that("fire alone makes Alex, the active shape, jump", vy(1) != 0 and vy(0) == 0)
    r.step_frame(select=True)
    r.step_frame()
    c.that("SELECT restarts the level",
           r.r("State") == P and r.r("CharX") == 20 and r.r("CharY") == 79 and r.r("Active") == 0)

    # ---- the ending ---------------------------------------------------
    r.step_frame(reset=True)
    for _ in range(2):
        r.step_frame()
    r.step_frame(fire=True)
    c.that("back at the title, a new run opens on level 1",
           r.r("State") == S and r.r("Level") == 0 and r.r("Quest") == 0)
    for _ in range(3):
        r.step_frame()                     # let go: a held button is not a new press
    last = sym["NUM_LEVELS"] - 1
    r.w("Level", last)
    r.step_frame(fire=True)
    r.step_frame()
    c.that("the finale goes straight to play, both shapes",
           r.r("State") == P and r.r("Level") == last and r.r("CharCount") == 2)
    r.goto_goals()
    r.step_frame()
    c.that("the finale completes", r.step_frame() == D)
    while r.step_frame() == D:
        pass
    c.that("after the finale: 'THE WORLD SHIFTED'", r.r("State") == S and r.r("StoryAfter") == 2)
    for _ in range(3):
        r.step_frame()
    r.step_frame(fire=True)
    r.step_frame()
    c.that("fire turns the world over: Quest 2, level 1, no narration",
           r.r("State") == P and r.r("Quest") == 1 and r.r("Level") == 0 and r.r("CharCount") == 1
           and r.r("BandStep") == 255)
    c.that("the run clock carried over into the upside-down replay",
           r.r("TFrm") + r.r("SecOnes") + 10 * r.r("SecTens") + 100 * r.r("SecHund") > 0)
    i = len(r.m.colupf)
    r.step_frame()
    bands = [v for _, v in r.m.colupf[i:]]
    c.that("upside down the sky is still at the top of the screen",
           bands == [sky] + [pf] * 9 + [sky] * 3, str([hex(v) for v in bands]))
    r.w("Level", last)
    r.step_frame(select=True)
    r.step_frame()
    c.that("the finale again, upside down",
           r.r("State") == P and r.r("Level") == last and r.r("BandStep") == 255)
    r.goto_goals()
    r.step_frame()
    c.that("it completes", r.step_frame() == D)
    while r.step_frame() == D:
        pass
    c.that("after the second finale the stranger is waiting", r.r("State") == S and r.r("StoryAfter") == 1)
    for _ in range(3):
        r.step_frame()
    r.step_frame(fire=True)
    r.step_frame()
    c.that("fire meets the stranger (the epilogue)", r.r("State") == W and r.m.aud[5] == 0)
    left = False
    for _ in range(29):
        r.step_frame(fire=True)
        if r.step_frame(fire=True) == T:
            left = True
    c.that("the epilogue ignores a held button for its first 60 frames", not left and r.r("State") == W)
    for _ in range(3):
        r.step_frame()
    r.step_frame(fire=True)
    r.step_frame()
    c.that("then fire returns to the title", r.r("State") == T and r.r("Quest") == 0)

    # ---- endless ------------------------------------------------------
    r.step_frame(select=True)
    r.step_frame()
    c.that("SELECT arms the endless game", r.r("TimedFlag") == 1)
    r.step_frame(fire=True)
    r.step_frame()
    c.that("endless starts with no story screen, 45 s on the clock",
           r.r("State") == P and r.r("TimerSec") == 45)
    r.goto_goals()
    r.step_frame()
    c.that("the room completes", r.step_frame() == D)
    while r.step_frame() == D:
        pass
    c.that("a survived room counts and tightens the clock",
           r.r("EndCnt") == 1 and r.r("State") == P and r.r("TimerSec") == 43)
    for _ in range(30):
        r.w("TimerSec", 1)                 # let the clock run out
        for _ in range(61):
            r.step_frame()
        if r.r("State") != P:
            break
    c.that("when the clock wins, the endless run ends on the stranger's screen",
           r.r("State") == W and r.m.aud[5] == 0)
    r.step_frame(reset=True)
    c.that("console RESET returns to the title, everything zeroed",
           r.r("State") == T and r.r("EndCnt") == 0 and r.r("TimedFlag") == 0)

    # ---- the budget: every line, and the blank under load ---------------
    # Both bodies and both lamps on the same du rows, row by row down the
    # screen: line 2 with all three of its objects visible, in both views.
    for quest in (0, 1):
        r.w("Quest", quest)
        r.w("Level", 2)
        r.step_frame(select=True)
        for k in range(80):
            for c_i in range(r.r("CharCount")):
                r.m.m[r.ram["CharY"] + c_i] = (k + c_i) & 0xFF
                r.m.m[r.ram["CharYLo"] + c_i] = 0
                r.m.m[r.ram["GoalY"] + c_i] = (k + 7 - 3 * c_i) & 0xFF
            r.step_frame()
    # SELECT held with the stick and fire down: a reload every frame, the
    # most logic any frame was ever caught doing.
    r.w("Quest", 0)
    for level in range(sym["NUM_LEVELS"]):
        r.w("Level", level)
        for _ in range(3):
            r.step_frame("LR", fire=True, select=True)

    def latest(run):
        k0, k1, game = run.sym["GameKernel"], run.sym["HeightTbl"], run.sym["TitleKernel"]
        every, in_game, late = 0, 0, 0
        for pc, idx, waited in run.m.wsyncs[1:]:
            if not waited and k0 <= pc < k1:
                every = max(every, idx)
                if pc < game:
                    in_game, late = max(in_game, idx), late + (idx >= 76)
        return every, in_game, late

    every, in_game, late = max(latest(b), latest(r))
    c.that(f"the game kernel always reaches its next WSYNC inside the scanline (latest write {in_game} of 76)",
           late == 0)
    c.that(f"no kernel line runs more than a few cycles past its scanline (latest write {every} of 76: "
           "the title's last logo line and the epilogue's last digit line, one line long each)",
           every < 92)
    c.that("every frame's logic fits in the vertical blank, SELECT held and the stick down included",
           b.m.overruns + r.m.overruns == 0, f"{b.m.overruns + r.m.overruns} frames overran")
    return c


# ---------------------------------------------------------------------
# A/B: the same random input on two ROMs.
# ---------------------------------------------------------------------
def script(seed, n):
    """Segments of (frames, stick, fire): taps, holds, drifts, down+fire."""
    q = random.Random(seed)
    out, f = [], 0
    while f < n:
        kind = q.random()
        if kind < 0.25:
            seg = (q.randint(1, 3), q.choice(["", "R", "L", "D", "LD", "RD", "U"]), True)
        elif kind < 0.6:
            seg = (q.randint(2, 30), q.choice(["R", "L", ""]), False)
        elif kind < 0.7:
            seg = (q.randint(1, 4), "", True)
        elif kind < 0.78:
            seg = (q.randint(1, 3), "D", True)
        else:
            seg = (q.randint(5, 80), "", False)
        out.append(seg)
        f += seg[0]
    return out


def pokes(seed, n, levels):
    """frame -> "goals" | "reset" | (variable, value): finish whatever is
    on screen, jump to another level, meddle with the clock, hit RESET."""
    q = random.Random(seed + 99)
    pk, f = {}, 400
    while f < n - 200:
        kind = q.random()
        if kind < 0.45:
            pk[f] = "goals"
        elif kind < 0.6:
            pk[f] = ("Level", q.randrange(levels))
        elif kind < 0.75:
            pk[f] = ("TimerSec", q.randrange(31))
        else:
            pk[f] = "reset"
        f += q.randint(120, 500)
    return pk


def play(rom, sym, segs, pk):
    run = Run(rom, sym)
    f = 0
    for frames, stick, fire in segs:
        for _ in range(frames):
            if f in pk:
                what = pk[f]
                if what == "goals":
                    run.goto_goals()
                elif what == "reset":
                    run.step_frame(stick, fire, reset=True)
                    f += 1
                    continue
                else:
                    run.w(what[0], what[1])
            run.step_frame(stick, fire, timed=(f // 700) % 2 == 1)
            f += 1
    return run


def without_pointers(run, at=-1):
    """RAM as the game sees it at trace index `at`, minus the pointers:
    those hold ROM addresses, which differ between two builds that are
    otherwise the same program."""
    ram = bytearray(run.m.m[0x80:0x100] if at < 0 else run.trace[at][2])
    for first, count in (("PF0Ptr", 8), ("TPtr", 12)):
        if first in run.ram:
            ram[run.ram[first] - 0x80:run.ram[first] - 0x80 + count] = b"\0" * count
    return bytes(ram)


def compare(rom_a, sym_a, rom_b, sym_b, frames, runs, quiet):
    bad = 0
    for seed in range(runs):
        segs = script(seed, frames)
        pk = pokes(seed, frames, sym_a["NUM_LEVELS"])
        a = play(rom_a, sym_a, segs, pk)
        b = play(rom_b, sym_b, segs, pk)
        first = next((i for i in range(min(len(a.trace), len(b.trace)))
                      if (a.trace[i][1], without_pointers(a, i), a.trace[i][3])
                      != (b.trace[i][1], without_pointers(b, i), b.trace[i][3])), None)
        same = first is None and len(a.trace) == len(b.trace)
        states = sorted({x[1] for x in a.trace})
        print(f"seed {seed}: {len(a.trace)} frames, states {states} - "
              f"{'identical' if same else f'DIFFER at frame {first}'}")
        bad += not same
    return bad


def main():
    ap = argparse.ArgumentParser(description="run the ROM headlessly")
    ap.add_argument("rom")
    ap.add_argument("sym")
    ap.add_argument("--compare", nargs=2, metavar=("ROM", "SYM"),
                    help="feed both ROMs the same random input and compare")
    ap.add_argument("--frames", type=int, default=6000, help="frames per A/B run (6000)")
    ap.add_argument("--runs", type=int, default=8, help="A/B runs (8)")
    ap.add_argument("--quiet", action="store_true", help="print only the failures")
    args = ap.parse_args()
    rom, sym = open(args.rom, "rb").read(), symbols(args.sym)
    if args.compare:
        print(f"headless: {args.runs} runs of {args.frames} frames, {args.rom} vs {args.compare[0]}")
        bad = compare(rom, sym, open(args.compare[0], "rb").read(), symbols(args.compare[1]),
                      args.frames, args.runs, args.quiet)
    else:
        bad = walkthrough(rom, sym, args.quiet).fails
        print(f"headless: {args.rom}: {'all checks pass' if not bad else str(len(bad)) + ' FAILED'}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
