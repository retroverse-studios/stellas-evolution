#!/usr/bin/env python3
"""Pictures for the manual, drawn from the cartridge's own bytes.

The ten rooms as the ROM holds them (the playfield, each shape where it
wakes, each light where it is the right way up), one of them upside
down with the lights its remix moves them to, the
title screen, the five narration screens (as strips of their text), the
cast to scale, the closing screen and a room with the clock run low.
None of these is a screenshot. They are the level records and the text
tables turned into pixels, so a picture cannot fall behind the game:
change a room, run this, and the manual's picture of it changes too.

    python3 tools/manual_pictures.py build/stella-was-alone.bin \\
        build/main.sym src/main.asm manual/pictures

The geometry is exact: one pixel here is one pixel of the 2600's
picture, scaled up three times. The colours are near-NTSC, picked by
hand for the dozen the game uses. Room names are read from the comments
above the level records. Needs Pillow.

Usage: python3 tools/manual_pictures.py ROM SYM ASM OUTDIR
"""
import os
import re
import sys

from PIL import Image

RECORD = 73           # bytes per level record, as check_levels.py reads it
ROM_BASE = 0xF000
W, H = 160, 192       # the 2600's picture, without the cartridge's overscan
SCALE = 3             # each 2600 pixel becomes a 3 by 3 block
NUM_LEVELS = 10
NUM_STORIES = 6
STORIES = ["story-alone", "story-more", "story-two", "story-together", "story-shifted"]

# The colours the game draws with, as RGB. Hue 0 is the grey ramp and
# takes its luma from LUMA; the rest are picked by eye.
LUMA = {0: 0, 2: 36, 4: 77, 6: 122, 8: 173, 10: 219, 12: 255, 14: 255}
HANDED = {
    0x36: (168, 66, 36), 0x38: (216, 84, 44),      # Stella: idle, active
    0xCC: (84, 190, 104), 0xCE: (104, 214, 124),   # Alex: idle, active
    0x84: (62, 96, 190), 0x85: (70, 106, 202),     # the stranger, breathing
    0x86: (78, 116, 214), 0x87: (88, 128, 226),
    0x20: (112, 34, 8),                            # the ember sky
    0x42: (150, 62, 62), 0x43: (176, 70, 70),      # the clock, running out
    0x44: (200, 80, 80), 0x45: (222, 92, 92),
}


def rgb(colour):
    if colour in HANDED:
        return HANDED[colour]
    v = LUMA[colour & 0x0F]
    return (v, v, v) if colour < 0x10 else (v, v // 2, v // 3)


class Screen:
    """A 160 by 192 grid of TIA colour bytes."""

    def __init__(self, background=0x00):
        self.px = [[background] * W for _ in range(H)]

    def dot(self, x, y, colour, wide=1):
        if 0 <= y < H:
            for k in range(wide):
                if 0 <= x + k < W:
                    self.px[y][x + k] = colour

    def rect(self, x, y, w, h, colour):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.dot(xx, yy, colour)

    def upside_down(self):
        self.px.reverse()

    def save(self, path, rows=None):
        """Write the picture, scaled. `rows` keeps only those scanlines:
        a narration screen is saved as a strip of its text, because three
        lines of five-pixel letters are small on a whole screen."""
        keep = self.px if rows is None else self.px[rows[0]:rows[1]]
        img = Image.new("RGB", (W, len(keep)))
        img.putdata([rgb(c) for row in keep for c in row])
        img.resize((W * SCALE, len(keep) * SCALE), Image.NEAREST).save(path, optimize=True)


def mirrored(pf0, pf1, pf2):
    """One playfield row of a room: the left twenty pixels, then their
    reflection. PF0 is the upper nibble, bit 4 leftmost; PF1 runs bit 7
    to bit 0; PF2 runs bit 0 to bit 7."""
    left = [bool(pf0 & (0x80 >> i)) for i in range(4)]
    left += [bool(pf1 & (0x80 >> i)) for i in range(8)]
    left += [bool(pf2 & (1 << i)) for i in range(8)]
    return left + left[::-1]


def text_row(l0, l1, l2, r0, r1, r2):
    """One row of an asymmetric playfield, forty pixels. The kernel feeds
    the left half first and rewrites the three registers mid-line, so the
    right half is a second twenty pixels in the same bit order."""
    return mirrored(l0, l1, l2)[:20] + mirrored(r0, r1, r2)[:20]


def put_row(s, px, y, colour):
    for x in range(40):
        if px[x]:
            s.dot(x * 4, y, colour, wide=4)


class Cart:
    """The ROM, its symbols and its tables."""

    def __init__(self, rom_path, sym_path, asm_path):
        self.rom = open(rom_path, "rb").read()
        self.sym = {}
        for line in open(sym_path):
            m = re.match(r"^(\S+)\s+([0-9a-f]{4})", line.strip())
            if m:
                self.sym[m.group(1)] = int(m.group(2), 16)
        asm = open(asm_path).read()
        self.names = re.findall(r'; --- Level \d+ "([^"]+)"', asm)
        if len(self.names) != NUM_LEVELS:
            sys.exit("manual-pictures: expected %d room names in the source, found %d"
                     % (NUM_LEVELS, len(self.names)))
        addrs = [hi << 8 | lo for lo, hi in zip(self.at("LvlPtrLo"), self.at("LvlPtrHi"))]
        self.rooms = [self.raw(a, RECORD) for a in addrs]

    def at(self, name, n=NUM_LEVELS):
        return self.raw(self.sym[name], n)

    def raw(self, addr, n):
        a = addr - ROM_BASE
        return list(self.rom[a:a + n])

    def story_row(self, story, r):
        """Playfield row r of narration screen `story`: its six planes."""
        base = self.sym["StoryLo"] + story
        lo, hi = self.rom[base - ROM_BASE], self.rom[self.sym["StoryHi"] + story - ROM_BASE]
        stride = self.at("StoryStride", NUM_STORIES)[story]
        addr = (hi << 8 | lo) - ROM_BASE
        return text_row(*[self.rom[addr + plane * stride + r] for plane in range(6)])


def room_picture(cart, rec, background=0x00, remix=False):
    s = Screen(background)
    sky, world = cart.sym["COL_SKY"], cart.sym["COL_PF"]
    for band in range(12):
        row = mirrored(rec[band], rec[12 + band], rec[24 + band])
        for dy in range(16):                     # a band is eight double-lines
            put_row(s, row, band * 16 + dy, sky if band < 3 else world)
    goal_h = cart.sym["GOAL_H"] * 2
    heights, widths = cart.at("HeightTbl", 2), cart.at("WidthTbl", 2)
    stella, alex = 0x38, 0xCC
    place = 1 if remix else 0                    # the remix is the second set
    for ci in range(rec[60]):
        x, y = rec[65 + place * 4 + ci * 2], rec[66 + place * 4 + ci * 2] * 2
        s.rect(x, y, 8, goal_h, stella if ci == 0 else alex)
    for ci in range(rec[60]):                    # each shape where it wakes
        s.rect(rec[61 + ci * 2], rec[62 + ci * 2] * 2, widths[ci], heights[ci] * 2,
               stella if ci == 0 else alex)
    return s


def title_picture(cart, ember=False):
    s = Screen(0x20 if ember else 0x00)
    l0, l1, l2 = cart.at("LogoPF0L", 7), cart.at("LogoPF1L", 7), cart.at("LogoPF2L", 7)
    r0, r1, r2 = cart.at("LogoPF0R", 7), cart.at("LogoPF1R", 7), cart.at("LogoPF2R", 7)
    for r in range(7):                           # the mark: seven rows of eight du
        px = text_row(l0[r], l1[r], l2[r], r0[r], r1[r], r2[r])
        for dy in range(16):
            put_row(s, px, 40 + r * 16 + dy, cart.at("LogoColr", 7)[r])
    for r in range(cart.at("StoryLen", NUM_STORIES)[5]):   # and its one word
        for dy in range(2):
            put_row(s, cart.story_row(5, r), 160 + r * 2 + dy, 0x0E)
    return s


def cast_picture(cart):
    """The three of them to scale, on one floor: Stella, Alex, and the
    square from the closing screen. Three game pixels to one here."""
    s = Screen()
    heights, widths = cart.at("HeightTbl", 2), cart.at("WidthTbl", 2)
    s.rect(0, 150, W, 3, cart.sym["COL_PF"])
    s.rect(14, 150 - heights[0] * 6, widths[0] * 3, heights[0] * 6, 0x38)
    s.rect(52, 150 - heights[1] * 6, widths[1] * 3, heights[1] * 6, 0xCC)
    s.rect(128, 150 - 24, 24, 24, 0x86)
    return s


def story_picture(cart, story):
    """A narration screen: its rows centred, white on black, two scanlines
    to a row, as the story kernel draws them."""
    s = Screen()
    n = cart.at("StoryLen", NUM_STORIES)[story]
    for r in range(n):
        for dy in range(2):
            put_row(s, cart.story_row(story, r), 96 - n + r * 2 + dy, 0x0E)
    return s


def closing_picture(cart, seconds):
    """The screen after the last level: a question, three digits, and
    something small and blue that the game does not explain."""
    s = Screen()
    digits = [seconds // 100, seconds // 10 % 10, seconds % 10]
    glyphs = [11, 10] + digits + [10]            # ? _ H T O _ ; 10 is blank
    font = cart.at("DigitFont", 84)
    for line in range(14):                       # seven rows, two scanlines each
        y = 30 + line
        for slot, g in enumerate(glyphs):
            bits = font[g * 7 + 6 - line // 2]   # the font is stored bottom-up
            for b in range(8):
                if bits & (0x80 >> b):
                    s.dot(48 + slot * 8 + b, y, 0x0E)
    s.rect(76, 120, 8, 8, 0x86)
    return s


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    cart = Cart(*sys.argv[1:4])
    out = sys.argv[4]
    os.makedirs(out, exist_ok=True)
    written = []

    def slug(i):
        return "room-%02d-%s" % (i + 1, cart.names[i].lower().replace(" ", "-"))

    def write(s, name, rows=None):
        s.save(os.path.join(out, name), rows)
        written.append(name)

    for i, rec in enumerate(cart.rooms):
        write(room_picture(cart, rec), slug(i) + ".png")
    s = room_picture(cart, cart.rooms[2], remix=True)   # Discovery, the world turned over
    s.upside_down()
    write(s, slug(2) + "-upside-down.png")
    write(title_picture(cart), "title.png")
    write(title_picture(cart, ember=True), "title-ember.png")
    write(cast_picture(cart), "the-cast.png")
    for story, name in enumerate(STORIES):
        n = cart.at("StoryLen", NUM_STORIES)[story]
        write(story_picture(cart, story), name + ".png", rows=(96 - n - 12, 96 + n + 12))
    write(room_picture(cart, cart.rooms[6], background=0x44), "clock-low.png")
    write(closing_picture(cart, 0), "closing-screen.png")
    print("manual-pictures: %d pictures in %s" % (len(written), out))


if __name__ == "__main__":
    main()
