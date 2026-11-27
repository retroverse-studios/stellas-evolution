#!/usr/bin/env python3
"""The manual's pictures, drawn from the cartridge itself.

Each one is a real frame of the game: tools/headless.py runs the ROM and
logs every TIA write, and tools/picture.py replays the log onto a
picture. Nothing here is drawn by hand, so a picture can't disagree with
the game. (Game 1's manual_pictures.py drew from the ROM's bytes; Game 2
draws from its frames, which also gets the sprites, the lamps and the
sky exactly right.)

    python3 tools/manual_pictures.py ROM SYM OUTDIR

Writes title*.png, waking.png, the-cast.png, floor-NN-<name>.png (world
A, and -b for world B on floors 7-11), story-*.png, clock-low.png and
score*.png. Needs Pillow. Not part of `make`: see `make pictures`.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import headless as H  # noqa: E402
from picture import frame, render, save  # noqa: E402

NAMES = ["together-again", "the-low-door", "the-wall", "the-fold",
         "the-high-door", "the-cross", "two-truths", "the-handoff",
         "the-way-home", "the-seam", "where-they-meet"]


def lit(r):
    """Step to a frame where every vacant lamp is in its lit phase, so a
    picture shows where every home is."""
    for _ in range(256):
        if r.r("FrameCtr") & 0x50 == 0x50:
            return
        r.step_frame()


def shot(r, out, name, crop=None):
    """Two frames, merged. When characters stand level, two of them
    share a sprite and take turns, a frame each (the eye blends them on
    a television). Every hue on screen belongs to a character or a lamp
    (#27), so a coloured pixel in either frame is kept."""
    a, b = render(frame(r)), render(frame(r))
    rows = [[y if (x is None or not x >> 4) and y is not None and y >> 4 else x
             for x, y in zip(la, lb)] for la, lb in zip(a, b)]
    if crop:                            # (left, top, right, bottom) in pixels
        x0, y0, x1, y1 = crop
        rows = [row[x0:x1] for row in rows[y0:y1]]
    save(rows, os.path.join(out, name + ".png"))
    print(name)


def to_play(r, sym):
    H.press(r, fire0=True)
    while r.r("State") != sym["STATE_PLAY"]:
        H.press(r, fire0=True)


def load(r, sym, f):
    r.w("FloorSeq", f)
    r.w("State", sym["STATE_LOAD"])
    H.settle(r, 4)


def main():
    rom_path, sym_path, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    rom, sym = open(rom_path, "rb").read(), H.symbols(sym_path)
    S = {n: sym[f"STATE_{n}"] for n in H.STATES}

    # --- the title, in its four modes
    r = H.Run(rom, sym)
    H.settle(r, 20)
    for name in ("title", "title-2p", "title-endless", "title-endless-2p"):
        shot(r, out, name)
        H.press(r, select=True)

    # --- the waking: Marcus's eyes open in the dark
    H.press(r, fire0=True)
    while not (r.r("State") == S["WAKE"] and r.r("WakePhase") >= 2):
        r.step_frame()
    H.settle(r, 40)
    shot(r, out, "waking")

    # --- every floor as it loads, homes lit; world B where there is one
    r = H.Run(rom, sym)
    H.settle(r, 20)
    to_play(r, sym)
    for f, name in enumerate(NAMES):
        load(r, sym, f)
        lit(r)
        shot(r, out, f"floor-{f + 1:02d}-{name}")
        if f >= 6:
            r.call("SwapWorld")
            H.settle(r, 2)
            lit(r)
            shot(r, out, f"floor-{f + 1:02d}-{name}-b")

    # --- the cast, side by side on floor 1's ground, to scale
    load(r, sym, 0)
    for ci, x in ((0, 12), (1, 28), (2, 52)):  # clear of the totem
        r._place(ci, x, 88 - r.bank0("HeightTbl", 3)[ci])
    H.settle(r, 3)
    shot(r, out, "the-cast", crop=(0, 140, 72, 184))

    # --- all three home: the completion beat, then the narration
    for f, story in ((0, "story-not-every-climb"), (9, "story-one-door"),
                     (10, "story-stella-was-together")):
        load(r, sym, f)
        r.goto_homes()
        if not r.homes_hold():
            r.call("SwapWorld")
            r.goto_homes()
        r.step_frame()
        if f == 0:
            H.settle(r, 20)
            shot(r, out, "floor-01-home")
        while r.r("State") != S["STORY"]:
            r.step_frame()
        H.settle(r, 4)
        shot(r, out, story)
        if f != 10:
            while r.r("State") == S["STORY"]:
                H.press(r, fire0=True)
            while r.r("State") != S["PLAY"]:
                r.step_frame()
    # the story's end: the run time
    while r.r("State") == S["STORY"]:
        H.press(r, fire0=True)
    while r.r("State") != S["SCORE"]:
        r.step_frame()
    r.w("RunLo", 312 & 255)            # a run's time, in seconds: the
    r.w("RunHi", 312 >> 8)             # teleporting one above took four
    H.settle(r, 4)
    shot(r, out, "score-story")

    # --- the clock's shadow: a timed floor with seconds running out
    r = H.Run(rom, sym)
    H.settle(r, 20)
    to_play(r, sym)
    load(r, sym, 3)
    r.w("TimerSec", 6)                  # 6 seconds left: two steps dark
    for _ in range(64 * 2):
        if r.r("TimerSec") <= 4:
            break
        r.step_frame()
    lit(r)
    shot(r, out, "clock-low")


if __name__ == "__main__":
    main()
