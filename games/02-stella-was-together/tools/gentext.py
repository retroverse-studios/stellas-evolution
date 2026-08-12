#!/usr/bin/env python3
"""Render the narration screens to Atari 2600 playfield data.

Emits src/text.inc: for each story screen, six planes of playfield
bytes (PF0L/PF1L/PF2L/PF0R/PF1R/PF2R) that the story kernel replays
line-by-line on the asymmetric 40-column playfield. Each text row is
a 3x5 font padded to 6 double-lines; every plane ends with one blank
byte the kernel uses for all non-text lines.

Usage: python3 tools/gentext.py src/text.inc
"""
import sys

# 3x5 font, rows top->bottom, 3 bits per row (MSB = left column)
FONT = {
    'A': [0b010, 0b101, 0b111, 0b101, 0b101],
    'B': [0b110, 0b101, 0b110, 0b101, 0b110],
    'C': [0b011, 0b100, 0b100, 0b100, 0b011],
    'D': [0b110, 0b101, 0b101, 0b101, 0b110],
    'E': [0b111, 0b100, 0b110, 0b100, 0b111],
    'F': [0b111, 0b100, 0b110, 0b100, 0b100],
    'G': [0b011, 0b100, 0b101, 0b101, 0b011],
    'H': [0b101, 0b101, 0b111, 0b101, 0b101],
    'I': [0b111, 0b010, 0b010, 0b010, 0b111],
    'J': [0b001, 0b001, 0b001, 0b101, 0b010],
    'K': [0b101, 0b110, 0b100, 0b110, 0b101],
    'L': [0b100, 0b100, 0b100, 0b100, 0b111],
    'M': [0b101, 0b111, 0b111, 0b101, 0b101],
    'N': [0b101, 0b111, 0b111, 0b111, 0b101],
    'O': [0b010, 0b101, 0b101, 0b101, 0b010],
    'P': [0b110, 0b101, 0b110, 0b100, 0b100],
    'Q': [0b010, 0b101, 0b101, 0b010, 0b001],
    'R': [0b110, 0b101, 0b110, 0b101, 0b101],
    'S': [0b011, 0b100, 0b010, 0b001, 0b110],
    'T': [0b111, 0b010, 0b010, 0b010, 0b010],
    'U': [0b101, 0b101, 0b101, 0b101, 0b111],
    'V': [0b101, 0b101, 0b101, 0b101, 0b010],
    'W': [0b101, 0b101, 0b111, 0b111, 0b101],
    'X': [0b101, 0b101, 0b010, 0b101, 0b101],
    'Y': [0b101, 0b101, 0b010, 0b010, 0b010],
    'Z': [0b111, 0b001, 0b010, 0b100, 0b111],
    '.': [0b000, 0b000, 0b000, 0b000, 0b010],
    ',': [0b000, 0b000, 0b000, 0b010, 0b100],
    "'": [0b010, 0b010, 0b000, 0b000, 0b000],
    '!': [0b010, 0b010, 0b010, 0b000, 0b010],
    '?': [0b110, 0b001, 0b010, 0b000, 0b010],
    ' ': [0, 0, 0, 0, 0],
}

# The 8K script (terse 10-column form). One list of rows (max 10
# chars) per screen. Screen 0 is the TITLE logo (drawn rainbow on the
# dusk-violet sky by TitleKernel); the rest are between-floor
# narration screens (white on black by StoryKernel).
#   0: title SUBTITLE — the game's word, set small beneath the big
#      ported STELLA logo (decision #28: every game is one word)
#   1: after Act 1 Floor 1            — theme: connection & difference,
#      "not every challenge could be overcome alone" (creative-brief.md)
#   2: after Act 1 Floor 2 "The Low Door" — Marcus's gift (decision #21)
#   3: after Act 1 Floor 3 "The Wall"     — the wrap twist closes Act 1
# Adding a floor adds one narration screen here and one FloorStoryTbl
# entry in src/main.asm.
SCREENS = [
    [" TOGETHER"],                                          # 0: subtitle
    ["NOT EVERY", " CLIMB IS", "MADE ALONE"],               # 1: after F1
    [" THE DOOR", " KNEW WHO", "IT WAS FOR"],               # 2: after F2
    ["THEY WENT", "THE OTHER", "WAY AROUND"],               # 3: after F3
    ["IT FOLDED."],                                         # 4: after F4
    ["TOO HIGH."],                                          # 5: after F5
    ["SIDEWAYS."],                                          # 6: after F6
    ["TWO TRUTHS", " ONE PLACE."],                          # 7: after F7
    ["EACH TRUE", " IN TURN."],                             # 8: after F8
    ["THE WAY HOME", " WAS THROUGH."],                      # 9: after F9
]


def row_columns(text):
    """A text row -> 40 column bits (10 chars x 4 columns)."""
    text = text.upper().ljust(10)[:10]
    cols_by_line = []
    for line in range(5):
        cols = []
        for ch in text:
            glyph = FONT.get(ch, FONT[' '])[line]
            cols += [(glyph >> 2) & 1, (glyph >> 1) & 1, glyph & 1, 0]
        cols_by_line.append(cols)
    return cols_by_line  # 5 lines of 40 column bits


def encode(cols):
    """40 column bits -> (PF0L, PF1L, PF2L, PF0R, PF1R, PF2R)."""
    pf0l = sum(cols[i] << (4 + i) for i in range(4))            # c0-3
    pf1l = sum(cols[4 + i] << (7 - i) for i in range(8))        # c4-11
    pf2l = sum(cols[12 + i] << i for i in range(8))             # c12-19
    pf0r = sum(cols[20 + i] << (4 + i) for i in range(4))       # c20-23
    pf1r = sum(cols[24 + i] << (7 - i) for i in range(8))       # c24-31
    pf2r = sum(cols[32 + i] << i for i in range(8))             # c32-39
    return pf0l, pf1l, pf2l, pf0r, pf1r, pf2r


def build_screen(rows):
    """-> six plane byte-lists, each 6*R+1 long (blank line pads +
    one trailing blank byte for all non-text scanlines)."""
    planes = [[] for _ in range(6)]
    for row in rows:
        lines = row_columns(row)
        for line in lines:
            for p, b in enumerate(encode(line)):
                planes[p].append(b)
        for p in range(6):
            planes[p].append(0)  # 1 blank double-line between rows
    for p in range(6):
        planes[p].append(0)      # the kernel's "blank" index (6R)
    return planes


def emit_screen(lines, i, rows):
    planes = build_screen(rows)
    stride = len(planes[0])
    lines.append(f"Story{i}:  ; {' / '.join(r.strip() for r in rows)}")
    for p in planes:
        for j in range(0, len(p), 12):
            chunk = ",".join(f"${b:02x}" for b in p[j:j + 12])
            lines.append(f"        .byte {chunk}")
    return stride


def main(out_dir):
    """Two files, and the whole presentation lives in bank 1: the title
    and the narration never share a frame with play, so their kernels,
    logic and text map in as the bank-1 annex and hand the frame back
    on fire. text.inc = all screens (bank 1); storytab.inc = the
    LoadStory pointer tables (also read only from bank 1)."""
    header = ["; generated by tools/gentext.py -- do not edit by hand"]
    strides = [emit_screen([], i, rows) for i, rows in enumerate(SCREENS)]

    # bank 1: every screen, including screen 0 (the title subtitle)
    lines = header[:]
    for i, rows in enumerate(SCREENS):
        emit_screen(lines, i, rows)
    with open(f"{out_dir}/text.inc", "w") as f:
        f.write("\n".join(lines) + "\n")

    # bank 1: the LoadStory tables
    lines = header[:]
    lines.append("StoryLo:     .byte " + ",".join(f"<Story{i}" for i in range(len(SCREENS))))
    lines.append("StoryHi:     .byte " + ",".join(f">Story{i}" for i in range(len(SCREENS))))
    lines.append("StoryLen:    .byte " + ",".join(str(s - 1) for s in strides))
    lines.append("StoryStride: .byte " + ",".join(str(s) for s in strides))
    with open(f"{out_dir}/storytab.inc", "w") as f:
        f.write("\n".join(lines) + "\n")

    total = sum(s * 6 for s in strides)
    print(f"gentext: {len(SCREENS)} screens, {total} bytes (all bank 1)")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "src")
