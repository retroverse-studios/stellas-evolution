#!/usr/bin/env python3
"""Run Game 2's assembled ROM itself, headlessly.

A 6502 with the 2600's real address decoding, the F8 bank switch, the
RIOT timer and the input registers, driven one frame at a time. Nothing
is drawn, but cycles are counted: a WSYNC sleeps to the end of its
scanline, so a kernel line that runs past 76 cycles shows, a frame that
is not 262 lines shows, and so does logic that outlasts its blank.

The CPU core is Game 1's (tools/headless.py there), copied so that each
game's tools stand alone. What is new here is the memory map, which
Game 1's harness simplified:

- F8: touching $1FF8 or $1FF9 (in any mirror) maps bank 0 or bank 1
  into every mirror of the cartridge window.
- RAM is ONE 128-byte block, seen at $80-$FF and again at $180-$1FF.
  The stack lives in it. A push past the last variable overwrites that
  variable, and a push below $180 lands in the TIA. Game 1's harness
  kept the stack in a separate page, so it could not see either.
- A frame is VSYNC to VSYNC, not a trip round one MainLoop: the title
  and narration run their own frame loop in bank 1.

    python3 tools/headless.py build/stella-was-together.bin build/main.sym
        boots, plays every floor in order, soaks the game in random
        input, and checks timing, the stack, and the frame
    python3 tools/headless.py ROM SYM --ram
        and prints which states touch each RAM variable

Usage: python3 tools/headless.py ROM SYM [--ram] [--frames N] [--quiet]
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
        self.cur_cyc = cyc               # a store lands on the last of these
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
            inside = getattr(self, "in_kernel", False) and not self.waited
            self.wsyncs.append((self._wsync, idx, not inside, getattr(self, "bank", 0)))
            if inside:
                self.kernel_late = max(self.kernel_late, idx)
            self._wsync = None
            self.linepos = 0
            self.waited = False
            sleep = 75 - idx % 76        # and the CPU sleeps to the end of the line
            cyc += sleep
            self.cycles += sleep         # (Game 1's copy leaves this out: it never
                                         # measured a frame's length)
            if getattr(self, "tia_log", None) is not None:
                self.tia_log.append((self.cycles, -1, 0))   # a new line starts here
        self.frac += cyc
        while self.frac >= self.interval:
            self.frac -= self.interval
            self.timer = (self.timer - 1) & 0xFF
            if self.timer == 0xFF:
                self.expired = True

    def _pull_p(self):
        p = self.pull()
        self.n, self.v, self.d, self.i, self.z, self.c = [(p >> k) & 1 for k in (7, 6, 3, 2, 1, 0)]



# ---------------------------------------------------------------------
# The 2600 around the CPU: address decoding, F8, a frame at a time.
# ---------------------------------------------------------------------
TIA_INPUTS = {0x0C: "inpt4", 0x0D: "inpt5"}
STICK0 = {"R": 0x80, "L": 0x40, "D": 0x20, "U": 0x10}   # SWCHA high nibble, active low
STICK1 = {"R": 0x08, "L": 0x04, "D": 0x02, "U": 0x01}   # SWCHA low nibble


class VCS(Machine):
    """Machine with the console's memory map. `m` stays a flat 64K array
    because the core fetches opcodes and operands from it directly: the
    cartridge window is kept filled with the mapped bank in all eight of
    its mirrors, and RAM lives at $80-$FF, where zero-page pointers read
    it."""

    def __init__(self, rom, bank=1, fill=None):
        super().__init__(rom[:4096])
        self.rom = rom
        self.m = bytearray(0x10000)
        self.map_bank(bank)
        if fill:
            fill(self.m)                       # power-on RAM
        self.pc = self.m[0xFFFC] | self.m[0xFFFD] << 8
        self.state_var = None                  # RAM address of State, for the RAM log
        self.ram_log = None                    # addr -> {state: "r"/"w" set}
        self.tia_hits = 0                      # stack pushes that landed in the TIA
        self.min_sp = 0xFF
        self.vsync_on = False
        self.frame_start = False               # set by a VSYNC rising edge
        self.overrun_polls = 0                 # a timer wait whose flag was already up
        self.overrun_at = []                   # (State, pc) of each
        self.colubk = []
        self.tia_log = None                    # [(cycle, register, value)] when set
        self.sprite_cols = set()               # {(State, COLUP0/1 value)}
        self.cur_cyc = 0
        self.in_kernel = False                 # between a blank's end and the next timer set
        self.kernel_late = 0                   # latest WSYNC write inside a kernel

    def map_bank(self, b):
        self.bank = b
        img = self.rom[b * 4096:(b + 1) * 4096]
        for base in range(0x1000, 0x10000, 0x2000):
            self.m[base:base + 4096] = img

    def _hot(self, a):
        if a in (0x1FF8, 0x1FF9):
            self.map_bank(a - 0x1FF8)

    def _log(self, ram, kind):
        if self.ram_log is not None:
            st = self.m[self.state_var]
            self.ram_log.setdefault(ram, {}).setdefault(st, set()).add(kind)

    def read(self, addr):
        a = addr & 0x1FFF
        if a & 0x1000:
            v = self.m[addr & 0xFFFF]
            self._hot(a)
            return v
        if not a & 0x80:                       # TIA
            name = TIA_INPUTS.get(a & 0x0F)
            return getattr(self, name) if name else 0
        if not a & 0x200:                      # RAM, either mirror
            ram = 0x80 | (a & 0x7F)
            self._log(ram, "r")
            return self.m[ram]
        r = a & 0x2FF                          # RIOT
        if r == 0x285 and self.expired:
            self.in_kernel = True              # the wait is over: lines are drawn now
        if r in (0x284, 0x285):
            if self._first_read and self.expired:
                self.overrun_polls += 1
                self.overrun_at.append((self.m[self.state_var], self.pc, self.bank))
            self._first_read = False
        if r == 0x285:
            self.waited = True
        return super().read(r)

    def write(self, addr, v):
        a = addr & 0x1FFF
        v &= 0xFF
        if a & 0x1000:
            self._hot(a)                       # a write to ROM does nothing else
            return
        if not a & 0x80:                       # TIA
            t = a & 0x3F
            if self.tia_log is not None:       # for tools/picture.py
                self.tia_log.append((self.cycles + self.cur_cyc - 1, t, v))
            if t == 0x00:
                rising = bool(v & 2) and not self.vsync_on
                self.vsync_on = bool(v & 2)
                if rising:
                    self.frame_start = True
                if v & 2:
                    self.in_kernel = False
            elif t == 0x09:
                self.colubk.append((self.cycles, v))
            elif t in (0x06, 0x07):            # COLUP0/1: who draws in what
                self.sprite_cols.add((self.m[self.state_var], v))
            super().write(t, v)
            return
        if not a & 0x200:
            ram = 0x80 | (a & 0x7F)
            self._log(ram, "w")
            self.m[ram] = v
            return
        if (a & 0x2FF) in (0x294, 0x295, 0x296, 0x297):
            self.in_kernel = False
            super().write(a & 0x2FF, v)
            self.frac = self.interval - 1      # the RIOT's first count comes one
            return                             # cycle after the write, not one
        super().write(a & 0x2FF, v)            # interval: N*64+1 cycles to underflow

    def push(self, v):
        if self.sp & 0x80:
            ram = self.sp
            self._log(ram, "w")
            self.m[ram] = v & 0xFF
        else:
            self.tia_hits += 1                 # $0100-$017F: the TIA's mirror
        self.sp = (self.sp - 1) & 0xFF
        if self.sp < self.min_sp:
            self.min_sp = self.sp
            self.deepest = (self.m[self.state_var], self.pc, self.bank,
                            [self.m[a] for a in range(self.sp + 1, 0x100)])

    def pull(self):
        self.sp = (self.sp + 1) & 0xFF
        return self.m[self.sp] if self.sp & 0x80 else 0


def labels_by_bank(asm_path, sym):
    """(bank, address) -> label, for reports: the two banks share one
    address range, so an address alone does not name a routine."""
    out, bank = {}, 0
    for line in open(asm_path, errors="replace"):
        if re.match(r"\s+SEG\s+BANK1", line):
            bank = 1
        m = re.match(r"^([A-Za-z_]\w*):", line)
        if m and m.group(1) in sym and sym[m.group(1)] >= 0xF000:
            out[(bank, sym[m.group(1)])] = m.group(1)
    return out


def where(labels, bank, pc):
    best = max((a for b, a in labels if b == bank and a <= pc), default=None)
    return f"bank {bank} {labels[(bank, best)]}+{pc - best}" if best is not None else f"{pc:04x}"


def symbols(path):
    out = {}
    for line in open(path, errors="replace"):
        m = re.match(r"^(\S+)\s+([0-9a-f]{4})", line.strip())
        if m:
            out[m.group(1)] = int(m.group(2), 16)
    return out


class Run:
    """One powered-on console. A frame runs from one VSYNC rising edge to
    the next, whichever bank draws it."""

    def __init__(self, rom, sym, bank=1, fill=None):
        self.m = VCS(rom, bank, fill)
        self.rom, self.sym = rom, sym
        self.ram = {k: v for k, v in sym.items() if 0x80 <= v <= 0xFF and k[0] != "."}
        self.m.state_var = self.ram["State"]
        self.frame = 0
        self.lines = []                        # scanlines in each finished frame
        self.late = []                         # (frame, latest WSYNC write cycle) per frame
        self.frames = []                       # (State before, State after, lines, reset?)
        self.late_at = []                      # (State, pc, cycle) of kernel lines past 75
        self._run_to_frame()

    def r(self, name, i=0):
        return self.m.m[self.ram[name] + i]

    def w(self, name, v, i=0):
        self.m.m[self.ram[name] + i] = v & 0xFF

    def bank0(self, label, n):
        """n bytes of a bank-0 table, by label."""
        a = self.sym[label] - 0xF000
        return list(self.rom[a:a + n])

    def _run_to_frame(self):
        m, guard = self.m, 0
        m.frame_start = False
        while not m.frame_start:
            m.step()
            guard += 1
            if guard > 400000:
                sys.exit(f"no VSYNC for 400,000 instructions (pc {m.pc:04x}, bank {m.bank})")

    def step_frame(self, stick0="", fire0=False, stick1="", fire1=False,
                   select=False, reset=False, timed=False):
        """Run one frame with these inputs; -> the State it ended in."""
        m = self.m
        m.swcha = 0xFF
        for k in stick0:
            m.swcha &= ~STICK0[k]
        for k in stick1:
            m.swcha &= ~STICK1[k]
        m.swcha &= 0xFF
        m.inpt4 = 0 if fire0 else 0x80
        m.inpt5 = 0 if fire1 else 0x80
        m.swchb = 0xFF & ~(2 if select else 0) & ~(1 if reset else 0) & ~(0 if timed else 0x40)
        c0, w0 = m.cycles, len(m.wsyncs)
        before = self.r("State")
        sp0, tia0, deep0 = m.min_sp, m.tia_hits, getattr(m, "deepest", None)
        k0, m.kernel_late = m.kernel_late, 0
        self._run_to_frame()
        if m.kernel_late > 75:
            self.late_at += [(before, pc, idx, bank) for pc, idx, wa, bank in m.wsyncs[w0:]
                             if idx > 75 and not wa]
        m.kernel_late = max(k0, m.kernel_late)
        cyc = m.cycles - c0
        # scanline boundaries crossed, VSYNC to VSYNC: what the TV
        # counts. Rounding cycles/76 called a 262.54-line frame 263 and
        # would call 262.45 262, whichever side of its line VSYNC fell
        self.lines.append(m.cycles // 76 - c0 // 76)
        lw = [idx for _, idx, waited, _b in m.wsyncs[w0:] if not waited]
        self.late.append((self.frame, max(lw) if lw else 0))
        if reset:                              # the cold start's clear, not the game's stack
            m.min_sp, m.tia_hits, m.deepest = sp0, tia0, deep0
        if not timed and self.r("State") in (self.sym["STATE_PLAY"], self.sym["STATE_DONE"]):
            top = max(self.r("SkyGrad", i) & 0x0F for i in range(12))
            self.dim_frames = getattr(self, "dim_frames", 0) + (top < 8)
        self.frame += 1
        self.frames.append((before, self.r("State"), self.lines[-1], reset))
        return self.r("State")

    def home(self, ci):
        """(CharY, left, right) of character ci's home on this floor."""
        f = self.r("FloorSeq")
        n = self.sym["NUM_FLOORS"]
        lo, hi = self.bank0("FloorHomeLo", n)[f], self.bank0("FloorHomeHi", n)[f]
        a = (hi << 8 | lo) - 0xF000
        return tuple(self.rom[a + 3 * ci:a + 3 * ci + 3])

    def _place(self, ci, x, y):
        self.w("CharX", x, ci)
        self.w("CharY", y, ci)
        for v in ("CharYLo", "CharVYHi", "CharVYLo"):
            self.w(v, 0, ci)
        self.w("OnGround", 1, ci)

    def call(self, label):
        """Run one of the game's subroutines to its rts, between frames, as
        if the frame loop had called it (bank 0, where play runs)."""
        m, back = self.m, self.m.pc
        ret = self.sym["MainLoop"]
        m.push((ret - 1) >> 8)
        m.push(ret - 1)
        m.pc = self.sym[label]
        while m.pc != ret:
            m.step()
        m.pc = back

    def homes_hold(self):
        """Do all three still stand home a frame later? Tried on a copy."""
        import copy
        saved = self.m
        self.m = copy.deepcopy(saved)
        self.step_frame()
        ok = self.r("State") == self.sym["STATE_DONE"]
        self.m = saved
        self.frame -= 1
        self.lines.pop()
        self.late.pop()
        self.frames.pop()
        return ok

    def goto_homes(self, quick=False):
        """Every character standing at home, no motion left in it. A home
        is a height and an x range, and the range can be wider than the
        ledge under it (a full-width range on a floor of shelves), so each
        x along it is tried on a copy of the machine until the character
        is still standing there a frame later."""
        import copy
        width = self.bank0("WidthTbl", 3)
        for ci in range(3):
            y, left, right = self.home(ci)
            lo, hi = max(left, 4), min(right - 1, 156 - width[ci])
            if quick:                          # the soak: near enough is fine
                self._place(ci, (lo + hi) // 2, y)
                continue
            for x in sorted(range(lo, hi + 1, 2), key=lambda v: abs(v - (lo + hi) // 2)):
                trial = copy.deepcopy(self.m)
                saved, self.m = self.m, trial
                self._place(ci, x, y)
                self.step_frame()
                ok = self.r("CharY", ci) == y and self.r("OnGround", ci) and \
                    left < self.r("CharX", ci) + width[ci] and self.r("CharX", ci) < right
                self.m = saved
                self.frame -= 1
                self.lines.pop()
                self.late.pop()
                self.frames.pop()
                if ok:
                    self._place(ci, x, y)
                    break
            else:
                self._place(ci, (lo + hi) // 2, y)


class Checks:
    def __init__(self, quiet=False):
        self.fails, self.warns, self.quiet, self.n = [], [], quiet, 0

    def warn(self, label, ok, detail=""):
        """A known fault, measured and printed but not failed on, until it
        is fixed. Each says where it is."""
        if not ok:
            self.warns.append(label)
        if not ok or not self.quiet:
            print(f"  {'ok  ' if ok else 'WARN'}  {label}" + (f" - {detail}" if detail else ""))

    def that(self, label, ok, detail=""):
        self.n += 1
        if not ok:
            self.fails.append(label)
        if not ok or not self.quiet:
            print(f"  {'ok  ' if ok else 'FAIL'}  {label}" + (f" - {detail}" if detail else ""))


# ---------------------------------------------------------------------
# What must be true.
# ---------------------------------------------------------------------
STATES = ("TITLE", "PLAY", "STORY", "WAKE", "DONE", "LOAD", "OPEN", "SCORE")


def ram_top(asm_path):
    """First byte after the declared variables: the stack may use what
    is left above it, and nothing below."""
    txt = open(asm_path, errors="replace").read()
    block = txt[txt.index("SEG.U VARS"):]
    block = block[:block.index("SEG BANK0")]
    return 0x80 + sum(int(n) for n in re.findall(r"^\w+\s+ds\s+(\d+)", block, re.M))


def settle(r, n=3):
    for _ in range(n):
        r.step_frame()


def press(r, **kw):
    """A fresh press: one frame held, then released long enough to count
    as let go."""
    r.step_frame(**kw)
    settle(r)


def walkthrough(r, sym, c):
    S = {name: sym[f"STATE_{name}"] for name in STATES}
    nf = sym["NUM_FLOORS"]
    settle(r, 30)
    c.that("power-on reaches the title", r.r("State") == S["TITLE"])
    press(r, fire0=True)
    c.that("fire on the title opens the waking", r.r("State") == S["WAKE"])
    for _ in range(600):
        if r.r("State") == S["PLAY"]:
            break
        press(r, fire0=True)
    c.that("the waking gives way to floor 1", r.r("State") == S["PLAY"] and r.r("FloorSeq") == 0)
    finished = 0
    for f in range(nf):
        settle(r, 10)
        c.that(f"floor {f + 1} is in play", r.r("State") == S["PLAY"] and r.r("FloorSeq") == f,
               f"State {r.r('State')}, FloorSeq {r.r('FloorSeq')}")
        r.goto_homes()
        if not r.homes_hold() and "SwapWorld" in sym:
            r.call("SwapWorld")                 # the homes may be in the other world
            r.goto_homes()
        r.step_frame()
        done = r.r("State") == S["DONE"]
        c.that(f"floor {f + 1}: all three standing home completes it", done)
        if not done:
            break
        for _ in range(200):
            if r.step_frame() != S["DONE"]:
                break
        c.that(f"floor {f + 1}: the beat ends on a narration screen", r.r("State") == S["STORY"])
        for _ in range(60):
            if r.r("State") != S["STORY"]:
                break
            press(r, fire0=True)
        finished += 1
    c.that(f"all {nf} floors play in order", finished == nf)
    c.that("with the clock off, the sky keeps its full ramp (brightest band luma 8+) "
           "in play and in the completion beat", getattr(r, "dim_frames", 0) == 0,
           f"{getattr(r, 'dim_frames', 0)} frames dimmed")
    c.that("after the last narration, the run's time", r.r("State") == S["SCORE"])
    play_frames = sum(1 for a, b, n, rs in r.frames if a == S["PLAY"])
    run = r.r("RunHi") * 256 + r.r("RunLo")
    c.that("the run clock counted the played seconds (64 frames each)",
           abs(run - play_frames / 64) <= nf, f"{run} s for {play_frames} play frames")
    press(r, fire0=True)
    c.that("fire in the score's first beat does nothing", r.r("State") == S["SCORE"])
    settle(r, 70)
    press(r, fire0=True)
    settle(r, 2)
    c.that("then fire, the title", r.r("State") == S["TITLE"])


def two_players(r, sym, c):
    """SELECT on the title, the count surviving RESET, each joystick
    moving its own character, and DOWN+Fire taking the free one."""
    S = {name: sym[f"STATE_{name}"] for name in STATES}
    press(r, reset=True)
    settle(r, 10)
    c.that("the title starts at one player", r.r("State") == S["TITLE"] and r.r("Active2") == 0xFF,
           f"State {r.r('State')}, Active2 {r.r('Active2'):02X}")
    seen = []
    for _ in range(4):
        press(r, select=True)
        seen.append((r.r("Mode"), r.r("Active2")))
    c.that("SELECT steps two players, endless one, endless two, the story again",
           seen == [(0x40, 1), (0x80, 0xFF), (0xC0, 1), (0x00, 0xFF)],
           ", ".join(f"Mode {m:02X} Active2 {a:02X}" for m, a in seen))
    for _ in range(30):
        r.step_frame(select=True)
    settle(r)
    c.that("holding SELECT steps once", r.r("Active2") < 3 and r.r("Mode") == 0x40)
    press(r, reset=True)
    settle(r, 10)
    c.that("the player count survives console RESET", r.r("State") == S["TITLE"] and r.r("Active2") < 3)
    press(r, fire0=True)
    for _ in range(600):
        if r.r("State") == S["PLAY"]:
            break
        press(r, fire0=True)
    settle(r, 30)
    c.that("two players start on Stella and Alex",
           r.r("State") == S["PLAY"] and (r.r("Active"), r.r("Active2")) == (0, 1),
           f"State {r.r('State')}, Active {r.r('Active')}, Active2 {r.r('Active2')}")
    x0, x1 = r.r("CharX", 0), r.r("CharX", 1)
    for _ in range(12):
        r.step_frame(stick1="L")
    c.that("joystick 2 moves Alex, not Stella", r.r("CharX", 1) != x1 and r.r("CharX", 0) == x0,
           f"Stella {x0}->{r.r('CharX', 0)}, Alex {x1}->{r.r('CharX', 1)}")
    x0, x1 = r.r("CharX", 0), r.r("CharX", 1)
    for _ in range(12):
        r.step_frame(stick0="R")
    c.that("joystick 1 moves Stella, not Alex", r.r("CharX", 0) != x0 and r.r("CharX", 1) == x1,
           f"Stella {x0}->{r.r('CharX', 0)}, Alex {x1}->{r.r('CharX', 1)}")
    press(r, stick1="D", fire1=True)
    c.that("joystick 2's DOWN+Fire takes Marcus, the free one",
           (r.r("Active"), r.r("Active2")) == (0, 2))
    press(r, stick0="D", fire0=True)
    c.that("joystick 1's DOWN+Fire takes Alex, now the free one",
           (r.r("Active"), r.r("Active2")) == (1, 2))


def opening_plays_out(rom, sym, c):
    """Left alone, the waking opening runs every phase in order — the
    black, the sky, the eyes, Stella's fall, Alex sliding in — and hands
    over to floor 1 with everyone at their spawn. Its phases run in the
    annex since decision #51; the walkthrough skips it with fire."""
    r = Run(rom, sym)
    settle(r, 30)
    press(r, fire0=True)
    phases, n = [], 0
    while r.r("State") == sym["STATE_WAKE"] and n < 1200:
        p = r.r("WakePhase")
        if not phases or phases[-1] != p:
            phases.append(p)
        r.step_frame()
        n += 1
    if r.r("State") == sym["STATE_LOAD"]:       # floor 1 loads in its own frame
        r.step_frame()
        n += 1
    c.that("left alone, the opening runs its five phases in order",
           phases == [0, 1, 2, 3, 4], f"phases {phases}")
    c.that("the opening hands over to floor 1",
           r.r("State") == sym["STATE_PLAY"] and r.r("FloorSeq") == 0,
           f"after {n} frames")
    long = [ln for a, b, ln, rs in r.frames if ln != 262 and not rs]
    c.that("every frame of the opening is 262 lines", not long, f"{long[:5]}")


def endless(rom, sym, c):
    """The endless game (decision #52): straight to a floor at random,
    45 seconds less two a floor, no narration, never the same floor
    twice running; the clock running out ends the run on the score."""
    S = {name: sym[f"STATE_{name}"] for name in STATES}
    r = Run(rom, sym)
    settle(r, 30)
    press(r, select=True)
    press(r, select=True)
    c.that("two SELECTs: the endless game, one player",
           r.r("Mode") == 0x80 and r.r("Active2") == 0xFF)
    press(r, fire0=True)
    states = set()
    for _ in range(5):
        r.step_frame()
        states.add(r.r("State"))
    c.that("fire starts a floor, without the opening",
           r.r("State") == S["PLAY"] and S["WAKE"] not in states and S["OPEN"] not in states,
           f"State {r.r('State')}, floor {r.r('FloorSeq') + 1}")
    floors, clocks, stories = [r.r("FloorSeq")], [r.r("TimerSec")], 0
    # A player takes a different time over every floor, and the picker
    # rolls on the frame counter: finishing each floor the instant it
    # loads would step the dice by the same 91 frames every time and
    # test the harness's rhythm instead of the picker. Seeded, so the
    # run is the same every time.
    q = random.Random(52)
    for n in range(18):
        for _ in range(q.randrange(0, 200)):
            r.step_frame()
        r.goto_homes()
        if not r.homes_hold() and "SwapWorld" in sym:
            r.call("SwapWorld")
            r.goto_homes()
        r.step_frame()
        if r.r("State") != S["DONE"]:
            break
        for _ in range(200):
            st = r.step_frame()
            stories += st == S["STORY"]
            if r.r("State") == S["PLAY"]:
                break
        floors.append(r.r("FloorSeq"))
        clocks.append(r.r("TimerSec"))
    want = [max(12, 45 - 2 * i) for i in range(len(clocks))]
    c.that("each floor's clock: 45, two fewer a floor, never under 12",
           clocks == want and len(clocks) == 19, f"{clocks}")
    c.that("the count is the floors survived", r.r("Mode") & 0x3F == 18, f"Mode {r.r('Mode'):02X}")
    c.that("no narration between endless floors", stories == 0)
    c.that("never the same floor twice running",
           all(a != b for a, b in zip(floors, floors[1:])), f"floors {[f + 1 for f in floors]}")
    c.that("the floors are drawn from all of them", len(set(floors)) >= 6,
           f"{len(set(floors))} different in {len(floors)}")
    r.w("Mode", 0x80 | 62)
    for _ in range(3):
        r.goto_homes()
        if not r.homes_hold() and "SwapWorld" in sym:
            r.call("SwapWorld")
            r.goto_homes()
        r.step_frame()
        for _ in range(200):
            r.step_frame()
            if r.r("State") == S["PLAY"]:
                break
    c.that("the count stops at 63", r.r("Mode") == 0x80 | 63, f"Mode {r.r('Mode'):02X}")
    r.w("TimerSec", 0)
    for _ in range(70):
        r.step_frame()
        if r.r("State") != S["PLAY"]:
            break
    c.that("when the clock runs out, the run ends on the score", r.r("State") == S["SCORE"])
    settle(r, 70)
    press(r, fire0=True)
    settle(r, 2)
    c.that("fire on the score: the title, still the endless game",
           r.r("State") == S["TITLE"] and r.r("Mode") & 0xC0 == 0x80)
    long = [ln for a, b, ln, rs in r.frames if ln != 262 and not rs]
    c.that("every frame of the endless game is 262 lines", not long, f"{long[:5]}")


def the_seam(rom, sym, c):
    """Floor 10's moves, in the ROM itself (the solver proves them on
    its model; this plays them on the engine): in world A UP at the
    edge swaps, because the doors are only true in B; in world B the
    same press takes the door, which wins over the rift; and Alex,
    standing on Stella's head where world A's ledge runs through the
    rift, swaps — and the floor turns over with both of them home."""
    S = {name: sym[f"STATE_{name}"] for name in STATES}
    r = Run(rom, sym)
    settle(r, 30)
    press(r, fire0=True)
    for _ in range(900):
        if r.r("State") == S["PLAY"]:
            break
        press(r, fire0=True)
    r.w("FloorSeq", 9)
    r.w("State", S["LOAD"])
    settle(r, 3)
    h = [r.home(ci) for ci in range(3)]
    r._place(2, 150, 82)                     # Marcus, ground, in rift + door
    r.w("Active", 2)
    settle(r, 2)
    press(r, stick0="U")
    c.that("the seam: in world A, UP at the edge swaps (no doors there)",
           r.r("CurWorld") == 1 and r.r("CharX", 2) == 150)
    press(r, stick0="U")
    settle(r, 4)
    c.that("the seam: in world B the same press takes the door, not the rift",
           r.r("CurWorld") == 1 and r.r("CharX", 2) == 4 and r.r("CharY", 2) == 34,
           f"world {r.r('CurWorld')}, Marcus at ({r.r('CharX', 2)}, {r.r('CharY', 2)})")
    r.call("SwapWorld")                      # back to A for the boost
    r._place(0, 144, 15)                     # Stella on A's ledge at 24
    r._place(1, 140, 12)                     # Alex on her head, in the rift
    r._place(2, 40, 82)
    r.w("Active", 1)
    settle(r, 2)
    press(r, stick0="U")
    settle(r, 30)
    at = [(r.r("CharY", ci), r.r("CharX", ci)) for ci in range(3)]
    c.that("the seam: Alex swaps from Stella's head and both land home",
           r.r("CurWorld") == 1 and at[1][0] == h[1][0] and at[0][0] == h[0][0]
           and h[0][1] <= at[0][1] < h[0][2] and h[1][1] <= at[1][1] < h[1][2],
           f"world {r.r('CurWorld')}, Stella {at[0]}, Alex {at[1]}")


def clock_runs_out(r, sym, c):
    """A timed floor whose clock reaches zero starts over: through
    STATE_LOAD, so the reload runs in the next frame's vblank."""
    S = {name: sym[f"STATE_{name}"] for name in STATES}
    for _ in range(200):
        if r.r("State") == S["PLAY"]:
            break
        press(r, fire0=True)
    spawn = r.r("CharX", 0)
    for _ in range(10):
        r.step_frame(stick0="R")
    moved = r.r("CharX", 0)
    r.w("TimerSec", 0)
    seen = set()
    for _ in range(70):                         # the clock ticks every 64 frames
        r.step_frame(timed=True)
        seen.add(r.r("State"))
        if r.r("TimerSec") == 45:
            break
    c.that("when the clock runs out the floor starts over, through STATE_LOAD",
           S["LOAD"] in seen and r.r("State") == S["PLAY"] and r.r("TimerSec") == 45
           and r.r("CharX", 0) != moved,
           f"Stella walked {spawn}->{moved}, back to {r.r('CharX', 0)}")


def soak(r, frames, seed, sym, each=None):
    """Random input on both joysticks, random jumps between floors and
    the odd RESET: as many paths through the code as cheaply as possible.
    `each` (optional) is called after every frame."""
    q = random.Random(seed)
    nf = sym["NUM_FLOORS"]
    stick = ["", "L", "R", "U", "D", "LU", "RU", "LD", "RD"]
    f = 0
    while f < frames:
        n = q.randint(1, 40)
        s0, s1 = q.choice(stick), q.choice(stick)
        b0, b1 = q.random() < 0.3, q.random() < 0.3
        timed = q.random() < 0.3
        for _ in range(n):
            r.step_frame(s0, b0 and q.random() < 0.5, s1, b1 and q.random() < 0.5, timed=timed)
            if each:
                each()
        f += n
        k = q.random()
        if k < 0.04:
            r.step_frame(reset=True)
        elif k < 0.15 and r.r("State") == sym["STATE_PLAY"]:
            r.goto_homes(quick=True)
        elif k < 0.2 and r.r("State") == sym["STATE_PLAY"]:
            # jump floors the way the game does — through STATE_LOAD,
            # which loads the record. Poking FloorSeq alone left one
            # floor's record under another floor's tables: floor 1's
            # walls with floor 10's doors and rift, a frame no real
            # game can reach (and which overran the blank).
            r.w("FloorSeq", q.randrange(nf))
            r.w("State", sym["STATE_LOAD"])


def ram_vars(asm_path):
    """(address, name, size) of every declared variable, in order."""
    txt = open(asm_path, errors="replace").read()
    block = txt[txt.index("SEG.U VARS"):]
    block = block[:block.index("SEG BANK0")]
    out, addr = [], 0x80
    for name, n in re.findall(r"^(\w+)\s+ds\s+(\d+)", block, re.M):
        out.append((addr, name, int(n)))
        addr += int(n)
    return out


def report_ram(log, asm_path):
    """Which screens touch each variable. A variable no screen touches,
    or two that are never live on the same screen, is RAM to be had."""
    print("\nRAM: which states touch each variable (r = read, w = written;")
    print("TITLE:w alone is the power-on clear and nothing else)")
    for addr, name, size in ram_vars(asm_path):
        touched = {}
        for a in range(addr, addr + size):
            for st, kinds in log.get(a, {}).items():
                touched.setdefault(st, set()).update(kinds)
        desc = " ".join(f"{STATES[st] if st < len(STATES) else st}:{''.join(sorted(k))}"
                        for st, k in sorted(touched.items()))
        print(f"  ${addr:02X} {name:12s} {size:2d}  {desc or '(never touched)'}")


POINTERS = {"PF0Ptr", "PF1Ptr", "PF2Ptr", "PlatPtr", "HomePtr", "PFColPtr", "TPtr",
            "RecPtr"}


def named_ram(run, layout, skip):
    """The variables' values by name: two builds may lay RAM out
    differently, so they are compared variable by variable. Pointers hold
    ROM addresses, which move whenever code does, so they are left out."""
    mem = run.m.m
    return {name: bytes(mem[a:a + n]) for a, name, n in layout
            if name not in POINTERS and name not in skip}


def compare(rom_a, sym_a, asm_a, rom_b, sym_b, asm_b, frames, runs, skip):
    """The same random input on two builds; the first frame on which any
    shared variable differs."""
    la, lb = ram_vars(asm_a), ram_vars(asm_b)
    shared = {n for _, n, _ in la} & {n for _, n, _ in lb}
    skip = set(skip) | ({n for _, n, _ in la} ^ {n for _, n, _ in lb})
    bad = 0
    for seed in range(runs):
        ra, rb = Run(rom_a, sym_a), Run(rom_b, sym_b)
        q = random.Random(seed)
        stick = ["", "L", "R", "U", "D", "LU", "RU"]
        first = None
        f = 0
        while f < frames and first is None:
            n = q.randint(1, 40)
            s0, s1 = q.choice(stick), q.choice(stick)
            b0 = q.random() < 0.3
            timed = (f // 900) % 2 == 1
            poke = q.random()
            for _ in range(n):
                fire = b0 and q.random() < 0.5
                for r in (ra, rb):
                    r.step_frame(s0, fire, s1, False, timed=timed)
                va, vb = named_ram(ra, la, skip), named_ram(rb, lb, skip)
                va["(audio)"], vb["(audio)"] = list(ra.m.aud), list(rb.m.aud)
                if va != vb:
                    diff = [k for k in va if va[k] != vb.get(k)]
                    first = (f, [f"{k} {va[k]}/{vb.get(k)}" for k in diff]
                             + [f"in {STATES[ra.r('State')]}"])
                    break
                f += 1
            if first is None and poke < 0.1:
                for r in (ra, rb):
                    if r.r("State") == r.sym["STATE_PLAY"]:
                        r.goto_homes(quick=True)
            elif first is None and poke < 0.13:
                for r in (ra, rb):
                    r.step_frame(reset=True)
        states = sorted({STATES[a] for a, _, _, _ in ra.frames})
        print(f"seed {seed}: {f} frames, states {states} - "
              + ("identical" if first is None else f"DIFFER at frame {first[0]}: {first[1]}"))
        bad += first is not None
    print(f"compared by name: {len(shared - skip)} variables; not compared: "
          f"{', '.join(sorted(skip | (POINTERS & shared)))}")
    return bad


def main():
    ap = argparse.ArgumentParser(description="run Game 2's ROM headlessly")
    ap.add_argument("rom")
    ap.add_argument("sym")
    ap.add_argument("--asm", default="src/main.asm")
    ap.add_argument("--frames", type=int, default=6000, help="random-input frames (6000)")
    ap.add_argument("--ram", action="store_true", help="print the RAM-by-state table")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--compare", nargs=3, metavar=("ROM", "SYM", "ASM"),
                    help="A/B against another build, variable by variable")
    ap.add_argument("--runs", type=int, default=6, help="A/B runs (6)")
    ap.add_argument("--skip", default="", help="comma-separated variables not to compare")
    args = ap.parse_args()
    if args.compare:
        b_rom, b_sym, b_asm = args.compare
        bad = compare(open(b_rom, "rb").read(), symbols(b_sym), b_asm,
                      open(args.rom, "rb").read(), symbols(args.sym), args.asm,
                      args.frames, args.runs, [v for v in args.skip.split(",") if v])
        sys.exit(1 if bad else 0)
    rom = open(args.rom, "rb").read()
    sym = symbols(args.sym)
    top = ram_top(args.asm)
    c = Checks(args.quiet)

    for bank in (0, 1):
        for label, fill in (("cleared", None),
                            ("garbage", lambda m: m.__setitem__(slice(0x80, 0x100),
                                                                bytes(random.Random(7).randrange(256)
                                                                      for _ in range(128))))):
            b = Run(rom, sym, bank, fill)
            settle(b, 20)
            c.that(f"power-on in bank {bank}, RAM {label}: the title", b.r("State") == sym["STATE_TITLE"])

    r = Run(rom, sym)
    r.m.min_sp, r.m.tia_hits = 0xFF, 0          # the reset's clear pushes through the page on purpose
    if args.ram:
        r.m.ram_log = {}                        # slow: every RAM access, by State
    walkthrough(r, sym, c)
    play = sym["STATE_PLAY"]
    seen = {"two": 0, "hop": 0, "solo_hop": 0, "solo_bad": 0, "clash": 0}

    def solo():
        if r.r("Active2") != 0xFF:
            seen["solo_bad"] += 1
        if r.r("State") == play and r.r("RepoDU") != 0xFF:
            seen["solo_hop"] += 1

    def duo():
        a, b = r.r("Active"), r.r("Active2")
        if r.r("State") != play:
            return
        seen["two"] += 1
        if a == b or a > 2 or b > 2:
            seen["clash"] += 1
        if r.r("RepoDU") != 0xFF:
            seen["hop"] += 1

    soak(r, args.frames // 2, 1, sym, solo)
    c.that("one player: joystick 2 never takes a character", seen["solo_bad"] == 0,
           f"{seen['solo_bad']} frames")
    c.that("one player: P1 never hops (the other two always flicker)", seen["solo_hop"] == 0,
           f"{seen['solo_hop']} frames")
    two_players(r, sym, c)
    clock_runs_out(r, sym, c)
    opening_plays_out(rom, sym, c)
    endless(rom, sym, c)
    if sym["NUM_FLOORS"] >= 10:
        the_seam(rom, sym, c)
    soak(r, args.frames - args.frames // 2, 2, sym, duo)
    c.that("two players never hold the same character", seen["clash"] == 0 and seen["two"] > 0,
           f"{seen['clash']} of {seen['two']} play frames")
    c.that("two players: P1 hops when a pair separates", seen["hop"] > 0,
           f"{seen['hop']} of {seen['two']} play frames hop")
    print(f"  (two players: {seen['hop']} of {seen['two']} play frames draw everyone solid)")
    # decision #49: in play every character draws in its own colour —
    # never #27's dim tier (Marcus $82 vanished on the dark home blocks),
    # never a flicker lift past it (Alex $CE+2 = $D0, a wrong hue at black)
    palette = {0x38, 0xCE, 0x84}                # ColBriTbl, the series palette
    stray = sorted({v for st, v in r.m.sprite_cols
                    if st in (play, sym["STATE_DONE"])} - palette)
    c.that("in play every character draws in its own colour, held or free",
           not stray, ", ".join(f"${v:02X}" for v in stray))
    m = r.m

    from collections import Counter
    labels = labels_by_bank(args.asm, sym)
    names = {sym[f"STATE_{k}"]: k for k in STATES}

    def at(state, pc, bank):
        return f"{names.get(state, state)} at {where(labels, bank, pc)}"

    steady = [(a, n) for a, b, n, rs in r.frames if a == b and not rs]
    turns = [(a, b, n) for a, b, n, rs in r.frames if a != b and not rs]
    play = [n for a, n in steady if names.get(a) in ("PLAY", "DONE", "WAKE")]
    annex = [n for a, n in steady if names.get(a) in ("TITLE", "STORY")]
    long_play = sum(1 for n in play if n != 262)
    c.that("every play frame is 262 lines", long_play == 0,
           f"{long_play} of {len(play)} ({100 * long_play / max(1, len(play)):.1f}%) are "
           + ", ".join(f"{n} x{k}" for n, k in sorted(Counter(n for n in play if n != 262).items())))
    c.that("every title and narration frame is 262 lines", all(n == 262 for n in annex),
           ", ".join(f"{n} lines x{k}" for n, k in sorted(Counter(annex).items())))
    bad_turns = Counter((names.get(a), names.get(b), n) for a, b, n in turns if n != 262)
    c.that("the frame where one screen gives way to another is 262 lines", not bad_turns,
           "; ".join(f"{a} -> {b}: {n} lines x{k}" for (a, b, n), k in sorted(bad_turns.items())))
    late = Counter((at(st, pc, bk), idx) for st, pc, idx, bk in r.late_at)
    c.that("no kernel line runs past its scanline", not late,
           "; ".join(f"{w} (cycle {i}) x{k}" for (w, i), k in sorted(late.items())))
    over = Counter(at(st, pc, bk) for st, pc, bk in m.overrun_at)
    c.that("logic always fits its blank", not over,
           "; ".join(f"{w} x{k}" for w, k in sorted(over.items())))
    used = 0xFF - m.min_sp
    free = m.min_sp + 1 - top
    c.that(f"the stack never reaches the variables: deepest {used} bytes, "
           f"{free} to spare above ${top - 1:02X}", free >= 0 and m.tia_hits == 0)
    if args.ram:
        report_ram(m.ram_log, args.asm)
    print(f"headless: {args.rom}: "
          + ("all checks pass" if not c.fails else f"{len(c.fails)} FAILED")
          + (f", {len(c.warns)} known faults measured" if c.warns else ""))
    sys.exit(1 if c.fails else 0)


if __name__ == "__main__":
    main()
