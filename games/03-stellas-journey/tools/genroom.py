#!/usr/bin/env python3
"""Build a tall room's data from a list of boxes, and check that what is
drawn is what is solid.

A room is a list of boxes. The playfield is worked out from the boxes,
never written by hand, so the drawing and the collision can't drift
apart (Game 1's rule, decision #35: drawn is solid, both ways).

- A ledge is one-way: you stand on its top and jump up through it. It
  is drawn as the one band its top starts.
- A solid box blocks from every side and is drawn as every band it
  covers.
- Tops and solid bottoms sit on band lines (multiples of 8 du), and
  left and right edges on playfield columns (multiples of 4 px).
- The playfield is mirrored, so the drawing is symmetric. A box whose
  mirror is not also a box draws something that isn't solid, and the
  build fails.
- A home's lamp is its band's colour, so a home's band draws nothing
  but the home. Prototype 1's kernel stores a band's colour at cycle
  38, pixel 46, so in its room ("late_colour") a home's band and the
  band below it also draw nothing left of pixel 48. Game 2 kept to the
  same rule by hand. Prototype 2's kernel stores the colour inside
  horizontal blank, and that rule goes.
- The corruption (prototype 2) is a box nobody stands on. Its bands are
  its colour, so they draw nothing else. It is drawn as static: the
  room's playfield comes in four versions that differ only there, each
  with half the corruption's columns lit, so the brightness holds still
  while the pattern moves.

Heights and widths are read from the assembly source, so a home's
height can't disagree with the character standing on it.

    python3 tools/genroom.py src/proto1.asm src/room1.inc climb [--show]
    python3 tools/genroom.py src/proto2.asm src/room2.inc static [--show]
"""
import random
import re
import sys

BANDS = 32                    # 256 du: 2 2/3 screens of 96 du
NAMES = ["STELLA", "ALEX", "MARCUS", "FLICKER"]

# ---------------------------------------------------------------------
# Prototype 1's room, "the climb". A test room, not a level: rungs 16 du
# apart, alternating a centre ledge and a pair at the sides, with the
# four homes near the top so the opening pan starts on them. One solid
# block (band 17-18) so walking into a wall and bumping a head are
# both exercised. x in pixels, y in du, bottom None for a ledge.
# ---------------------------------------------------------------------
CLIMB = {
    "boxes": {
        "ground": (0, 160, 248, 256),
        "b29": (48, 112, 232, None),
        "b27l": (8, 40, 216, None), "b27r": (120, 152, 216, None),
        "b25": (64, 96, 200, None),
        "b23l": (24, 56, 184, None), "b23r": (104, 136, 184, None),
        "b21": (48, 112, 168, None),
        "b19l": (8, 40, 152, None), "b19r": (120, 152, 152, None),
        "block": (64, 96, 136, 152),
        "b15l": (24, 56, 120, None), "b15r": (104, 136, 120, None),
        "b13": (48, 112, 104, None),
        "b11l": (8, 40, 88, None), "b11r": (120, 152, 88, None),
        "b9": (64, 96, 72, None),
        "b7l": (24, 56, 56, None), "b7r": (104, 136, 56, None),
        "b5": (48, 112, 40, None),
        "b3": (72, 88, 24, None),
        "b1": (48, 112, 8, None),
    },
    # whose home is which ledge: Stella, Alex, Marcus, Flicker
    "homes": ["b5", "b1", "b9", "b3"],
    # (x, the box each starts standing on)
    "spawns": [(20, "ground"), (60, "ground"), (76, "b29"), (120, "ground")],
    # sky luma per band, top to bottom. The characters use lumas 4, 6, 8
    # and E and the platforms A, so the sky keeps to 0 and 2 (#27)
    "sky": [0] * 16 + [2] * 16,
    # Drawn side walls would be lit with the lamps: a home's colour is its
    # whole band's COLUPF. So the screen's edge is the wall, and x is
    # clamped 4 px inside it, as Game 2 clamps when it doesn't wrap.
    "walls": False,
    "late_colour": True,      # prototype 1's kernel: see the rules above
    "corrupt": {},
}

# ---------------------------------------------------------------------
# Prototype 2's room, "the static": the climb with band 14 turned to
# corruption from wall to wall. Below it the climb as before; above it
# the climb to the homes. The only way up is through the static, and
# only Flicker, and whoever rides it, gets through. The rung under the
# static (b15, top 120) and the one over it (b13, top 104) are 16 du
# apart and overlap at x 48-56: Flicker's jump, 16.7 du, carries it
# (and a rider) from one to the other.
# ---------------------------------------------------------------------
STATIC = dict(CLIMB, late_colour=False, corrupt={"c14": (0, 160, 112, 120)})

ROOMS = {"climb": CLIMB, "static": STATIC}


def consts(asm_path):
    txt = open(asm_path).read()
    out = {}
    for name in NAMES:
        for kind in ("H", "W"):
            m = re.search(rf"^{name}_{kind}\s*=\s*(\d+)", txt, re.M)
            if not m:
                sys.exit(f"genroom: {name}_{kind} not found in {asm_path}")
            out[(name, kind)] = int(m.group(1))
    return out


def columns(x0, x1):
    """The left-half playfield columns (0-19, 4 px each) a span covers,
    either side of the mirror line."""
    cols = set()
    for px in range(x0, x1):
        cols.add(px // 4 if px < 80 else 19 - (px - 80) // 4)
    return cols


def build(room, c):
    boxes = room["boxes"]
    draw = [set() for _ in range(BANDS)]          # columns drawn, per band
    for name, (x0, x1, top, bot) in boxes.items():
        assert x0 % 4 == 0 and x1 % 4 == 0 and 0 <= x0 < x1 <= 160, f"{name}: x not on a column"
        assert top % 8 == 0, f"{name}: top {top} not on a band line"
        if bot is None:
            bands = [top // 8]
        else:
            assert bot % 8 == 0 and bot > top, f"{name}: bottom {bot} not on a band line"
            bands = range(top // 8, bot // 8)
        for b in bands:
            draw[b] |= columns(x0, x1)

    static = [set() for _ in range(BANDS)]        # corruption columns, per band
    cor = room["corrupt"]
    for name, (x0, x1, top, bot) in cor.items():
        assert x0 % 4 == 0 and x1 % 4 == 0 and top % 8 == 0 and bot % 8 == 0, name
        for b in range(top // 8, bot // 8):
            assert not draw[b], f"{name}: band {b} is the corruption's colour, and draws boxes too"
            static[b] |= columns(x0, x1)
            covered = set()
            for x0b, x1b, tb, bb in cor.values():
                if tb // 8 <= b < bb // 8:
                    covered |= set(range(x0b, x1b))
            for col in static[b]:
                for px in list(range(col * 4, col * 4 + 4)) + list(range(156 - col * 4, 160 - col * 4)):
                    assert px in covered, f"band {b}: static at pixel {px} with no corruption there"

    # drawn is solid: every pixel the mirrored playfield shows must be in
    # some box covering that band (the walls are the clamp, not a box)
    for b in range(BANDS):
        covered = set()
        for name, (x0, x1, top, bot) in boxes.items():
            hit = top // 8 == b if bot is None else top // 8 <= b < bot // 8
            if hit:
                covered |= set(range(x0, x1))
        for col in draw[b]:
            for px in list(range(col * 4, col * 4 + 4)) + list(range(156 - col * 4, 160 - col * 4)):
                assert px in covered, f"band {b}: pixel {px} is drawn but no box is solid there"

    for name in room["homes"]:
        x0, x1, t, _ = boxes[name]
        hb = t // 8
        if draw[hb] != columns(x0, x1):
            sys.exit(f"genroom: band {hb} is {name}'s lamp, and draws more than {name}")
        if static[hb]:
            sys.exit(f"genroom: band {hb} is both a lamp and corruption")
        if room["late_colour"]:
            for b in (hb, hb + 1):
                if b < BANDS and any(col < 12 for col in draw[b]):
                    sys.exit(f"genroom: band {b} is a home's lamp band (or just below one) and "
                             f"draws left of pixel 48, where the colour changes late")

    variants = 4 if cor else 1
    pf0, pf1, pf2 = [], [], []
    for v in range(variants):
        for b in range(BANDS):
            cols = set(draw[b])
            if static[b]:                         # half the static's columns lit
                lit = sorted(static[b])
                cols |= set(random.Random(b * 4 + v).sample(lit, len(lit) // 2))
            if room["walls"]:
                cols.add(0)
            pf0.append(sum(1 << (4 + k) for k in range(4) if k in cols))
            pf1.append(sum(1 << (7 - (k - 4)) for k in range(4, 12) if k in cols))
            pf2.append(sum(1 << (k - 12) for k in range(12, 20) if k in cols))

    order = sorted(boxes, key=lambda n: (boxes[n][2], boxes[n][0]))
    idx = {n: i for i, n in enumerate(order)}
    top = [boxes[n][2] for n in order]
    bot = [min(boxes[n][3], 255) if boxes[n][3] is not None else boxes[n][2] for n in order]
    left = [boxes[n][0] for n in order]
    right = [boxes[n][1] for n in order]
    band_start = [sum(1 for t in top if t < 8 * b) for b in range(BANDS + 1)]
    # solids that can block sideways or bump a head: the ground can do
    # neither (nobody is ever below it), so it is left out of the list
    solids = [idx[n] for n in order if boxes[n][3] is not None and boxes[n][3] < 256]

    homes = []
    for ci, name in enumerate(room["homes"]):
        x0, x1, t, _ = boxes[name]
        homes.append((t - c[(NAMES[ci], "H")], x0, x1, t // 8))
    spawns = []
    for ci, (x, name) in enumerate(room["spawns"]):
        x0, x1, t, _ = boxes[name]
        w = c[(NAMES[ci], "W")]
        assert x0 <= x and x + w <= x1, f"{NAMES[ci]} does not start on {name}"
        spawns.append((x, t - c[(NAMES[ci], "H")]))
    corrupt = [cor[n] for n in sorted(cor, key=lambda n: cor[n][2])]
    cor_bands = sorted({b for b in range(BANDS) if static[b]})
    return dict(pf=(pf0, pf1, pf2), sky=room["sky"], top=top, bot=bot, left=left,
                right=right, band_start=band_start, solids=solids, homes=homes,
                spawns=spawns, draw=draw, static=static, variants=variants,
                corrupt=corrupt, cor_bands=cor_bands)


def row(label, vals, fmt="{:d}"):
    out = []
    for i in range(0, len(vals), 16):
        chunk = ",".join(fmt.format(v) for v in vals[i:i + 16])
        out.append(f"{label if i == 0 else '':<12}.byte {chunk}")
    return "\n".join(out)


def emit(r, path):
    pf0, pf1, pf2 = r["pf"]
    h = "${:02X}"
    lines = [
        "; Generated by tools/genroom.py from its room list. Do not edit:",
        "; change the boxes there and rebuild.",
        f"ROOM_NB = {len(r['top'])}",
        f"ROOM_VARIANTS = {r['variants']}    ; versions of the playfield, 32 bands each",
        row("RoomPF0:", pf0, h), row("RoomPF1:", pf1, h), row("RoomPF2:", pf2, h),
        row("RoomSky:", r["sky"], h),
        "; boxes, in order of top (the landing search walks them in this order)",
        row("BoxTop:", r["top"]), row("BoxBot:", r["bot"]),
        row("BoxL:", r["left"]), row("BoxR:", r["right"]),
        "; BandStart[b]: the first box whose top is in band b or below",
        row("BandStart:", r["band_start"]),
        row("SolidList:", r["solids"] + [255]),
        "; the solids' highest top and lowest bottom: a character outside them",
        "; can't walk into one",
        f"SOLID_TOP = {min((r['top'][i] for i in r['solids']), default=255)}",
        f"SOLID_BOT = {max((r['bot'][i] for i in r['solids']), default=0)}",
        "; homes: the CharY a character stands at, the ledge's x extent, its band",
        row("HomeY:", [hm[0] for hm in r["homes"]]),
        row("HomeL:", [hm[1] for hm in r["homes"]]),
        row("HomeR:", [hm[2] for hm in r["homes"]]),
        row("HomeBand:", [hm[3] for hm in r["homes"]]),
        row("SpawnX:", [s[0] for s in r["spawns"]]),
        row("SpawnY:", [s[1] for s in r["spawns"]]),
    ]
    if r["corrupt"]:
        cz = r["corrupt"]
        lines += [
            "; the corruption: boxes nobody stands on, and the bands it colours",
            f"COR_N = {len(cz)}",
            f"COR_TOP = {min(b[2] for b in cz)}    ; the highest top and lowest bottom:",
            f"COR_BOT = {max(b[3] for b in cz)}    ; a character outside them can't touch it",
            row("CorTop:", [b[2] for b in cz]), row("CorBot:", [b[3] for b in cz]),
            row("CorL:", [b[0] for b in cz]), row("CorR:", [b[1] for b in cz]),
            row("CorBands:", r["cor_bands"] + [255]),
        ]
    lines.append("")
    open(path, "w").write("\n".join(lines))


def show(r, walls):
    for b in range(BANDS):
        cols = r["draw"][b] | ({0} if walls else set())
        left = "".join("#" if k in cols else ":" if k in r["static"][b] else "."
                       for k in range(20))
        print(f"{b:2d} {left}{left[::-1]}")


if __name__ == "__main__":
    c = consts(sys.argv[1])
    room = ROOMS[sys.argv[3]]
    r = build(room, c)
    emit(r, sys.argv[2])
    if "--show" in sys.argv:
        show(r, room["walls"])
