#!/usr/bin/env python3
"""A headless Atari 2600 for Game 3's tools: a 6502 with the console's
address decoding, F6 bankswitching, the RIOT timer and the joysticks,
driven a frame at a time. Nothing is drawn, but cycles are counted, so
a frame that is not 262 lines shows, and so does a drawn line that runs
past its 76 cycles. With `tia_log` set it records every TIA write, for
tools/picture.py.

The CPU (Machine) is Game 2's tools/headless.py, copied so each game's
tools stand alone. What is new:

- F6: reading or writing $1FF6-$1FF9 in any mirror maps bank 0-3.
- The Superchip: 128 bytes of cartridge RAM, written at $1000-$107F and
  read back at $1080-$10FF. A ROM has one when every bank's first 128
  bytes repeat as its next 128, the test Stella uses. A read of the
  write half is counted in `sc_bad_reads`: on a real cartridge it
  writes whatever is on the bus.
"""
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
        # a store doesn't read its target (Game 2's core did, harmlessly
        # there; here it would look like a read of the Superchip's write half)
        m = a if mode == "acc" else (self.read(e) if e is not None and mode != "rel"
                                     and name not in ("STA", "STX", "STY") else 0)
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
# The console around the CPU.
# ---------------------------------------------------------------------
TIA_INPUTS = {0x0C: "inpt4", 0x0D: "inpt5"}
STICK0 = {"R": 0x80, "L": 0x40, "D": 0x20, "U": 0x10}   # SWCHA high nibble, active low
HOT = range(0x1FF6, 0x1FFA)                               # F6: banks 0-3


class VCS(Machine):
    def __init__(self, rom, bank=0):
        super().__init__(rom[:4096])
        self.rom = rom
        self.nbanks = len(rom) // 4096
        self.m = bytearray(0x10000)
        self.map_bank(bank)
        self.pc = self.m[0xFFFC] | self.m[0xFFFD] << 8
        self.min_sp = 0xFF
        self.vsync_on = False
        self.frame_start = False
        self.tia_log = None
        self.in_kernel = False
        self.kernel_late = 0
        self.tia_hits = 0
        self.superchip = all(rom[b:b + 128] == rom[b + 128:b + 256]
                             for b in range(0, len(rom), 4096))
        self.sc = bytearray(128)
        self.sc_bad_reads = 0
        self.margins = {}                      # timer value set -> ticks left at the wait

    def map_bank(self, b):
        self.bank = b
        img = self.rom[b * 4096:(b + 1) * 4096]
        for base in range(0x1000, 0x10000, 0x2000):
            self.m[base:base + 4096] = img

    def _hot(self, a):
        if a in HOT and a - 0x1FF6 < self.nbanks:
            self.map_bank(a - 0x1FF6)

    def read(self, addr):
        a = addr & 0x1FFF
        if self.superchip and 0x1000 <= a < 0x1100:
            if a < 0x1080:
                self.sc_bad_reads += 1
                return 0
            return self.sc[a & 0x7F]
        if a & 0x1000:
            v = self.m[addr & 0xFFFF]
            self._hot(a)
            return v
        if not a & 0x80:                       # TIA
            name = TIA_INPUTS.get(a & 0x0F)
            return getattr(self, name) if name else 0
        if not a & 0x200:                      # RAM, either mirror
            return self.m[0x80 | (a & 0x7F)]
        r = a & 0x2FF                          # RIOT
        if r == 0x285 and self._first_read:   # the first look at the flag: how
            self.margins.setdefault(self._timer_v, []).append(   # many ticks were left
                -1 if self.expired else self.timer)
        if r == 0x285 and self.expired:
            self.in_kernel = True              # the wait is over: lines are drawn now
        return super().read(r)

    def write(self, addr, v):
        a = addr & 0x1FFF
        v &= 0xFF
        if self.superchip and 0x1000 <= a < 0x1080:
            self.sc[a & 0x7F] = v
            return
        if a & 0x1000:
            self._hot(a)
            return
        if not a & 0x80:                       # TIA
            t = a & 0x3F
            if self.tia_log is not None:
                self.tia_log.append((self.cycles + self.cur_cyc - 1, t, v))
            if t == 0x00:
                rising = bool(v & 2) and not self.vsync_on
                self.vsync_on = bool(v & 2)
                if rising:
                    self.frame_start = True
                if v & 2:
                    self.in_kernel = False
            super().write(t, v)
            return
        if not a & 0x200:
            self.m[0x80 | (a & 0x7F)] = v
            return
        if (a & 0x2FF) in (0x294, 0x295, 0x296, 0x297):
            self.in_kernel = False
            super().write(a & 0x2FF, v)
            self.frac = self.interval - 1
            return
        super().write(a & 0x2FF, v)

    def push(self, v):
        if self.sp & 0x80:
            self.m[self.sp] = v & 0xFF
        else:
            self.tia_hits += 1                 # $0100-$017F: the TIA
        self.sp = (self.sp - 1) & 0xFF
        self.min_sp = min(self.min_sp, self.sp)

    def pull(self):
        self.sp = (self.sp + 1) & 0xFF
        return self.m[self.sp] if self.sp & 0x80 else 0


def symbols(path):
    out = {}
    for line in open(path, errors="replace"):
        m = re.match(r"^(\S+)\s+([0-9a-f]{4})", line.strip())
        if m:
            out[m.group(1)] = int(m.group(2), 16)
    return out


class Run:
    """One powered-on console. A frame runs from one VSYNC rising edge to
    the next."""

    def __init__(self, rom, sym, bank=0):
        self.m = VCS(rom, bank)
        self.rom, self.sym = rom, sym
        self.ram = {k: v for k, v in sym.items() if 0x80 <= v <= 0xFF and k[0] != "."}
        self.lines, self.late = [], []
        self.frame = 0
        self._run_to_frame()

    def r(self, name, i=0):
        return self.m.m[self.ram[name] + i]

    def w(self, name, v, i=0):
        self.m.m[self.ram[name] + i] = v & 0xFF

    def table(self, label, n, bank=0):
        a = self.sym[label] - 0xF000 + bank * 4096
        return list(self.rom[a:a + n])

    def _run_to_frame(self):
        m, guard = self.m, 0
        m.frame_start = False
        while not m.frame_start:
            m.step()
            guard += 1
            if guard > 400000:
                sys.exit(f"no VSYNC for 400,000 instructions (pc {m.pc:04x}, bank {m.bank})")

    def step_frame(self, stick="", fire=False, reset=False):
        m = self.m
        m.swcha = 0xFF
        for k in stick:
            m.swcha &= ~STICK0[k] & 0xFF
        m.inpt4 = 0 if fire else 0x80
        m.swchb = 0xFF & ~(1 if reset else 0)
        c0, w0 = m.cycles, len(m.wsyncs)
        m.kernel_late = 0
        self._run_to_frame()
        self.lines.append(m.cycles // 76 - c0 // 76)
        self.late.append(m.kernel_late)
        m.wsyncs.clear()
        m.colupf.clear()
        self.frame += 1
