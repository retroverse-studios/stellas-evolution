# Stella Was Alone

**Game 1 of 4 · 4K ROM · no bankswitching**

Two shapes — Stella (tall red rectangle, high jump, slow) and Alex (flat green
rectangle, fast, fits under overhangs) — wake alone in a constrained world and
learn that some heights and gaps can only be crossed together.

- **Theme:** existence & isolation — "Stella was alone. She didn't know why."
- **Scope:** 10 levels (replayed upside-down), 2 characters, 5 narration screens
- **Controls:** Left/Right move, Fire jumps, Down+Fire switches character
- **Constraint:** everything fits in 4,096 bytes of ROM and 128 bytes of RAM

## Building

Requires [DASM](https://dasm-assembler.github.io/) and the
[Stella](https://stella-emu.github.io/) emulator (`brew install dasm stella`).

```sh
make        # assembles src/main.asm -> build/stella-was-alone.bin (4096 bytes)
make run    # builds and launches in the Stella emulator
```

`src/vcs.h` is a hand-written set of TIA/RIOT register equates; `src/main.asm`
is the whole game.

See [`../../docs/`](../../docs/) for the full design documents.

## Status: v1.0-rc3-dev — the manual (2026-11-25)

[`MANUAL.md`](MANUAL.md) and the illustrated
[`manual/manual.html`](manual/manual.html) were rewritten for the game as
it is: the world and its backstory, a page each for Stella, Alex and the
stranger on the closing screen, how a room works, all ten rooms pictured
with a note on what each one asks, the upside-down run, the ending, the
endless game, the clock and every switch.

- **The pictures are drawn, not photographed.** `make pictures` turns the
  level records and the text tables into `manual/pictures/`: each room
  with both shapes where they wake and each light in both its places,
  the title in both skies, the five narration screens, the cast to
  scale, the closing screen. Geometry exact, colours near enough. So a
  picture cannot fall behind the game. The RC1 screenshots are no longer
  shown.
- **Two modes, not two games.** They are called the story game and the
  endless game now. "Game 1" and "Game 2" inside this cartridge were
  read as the series' numbers.
- **The stranger is in the manual**, as a teaser: what it looks like,
  what it does, and nothing more. `manual/SCREENSHOTS-TODO.md` had kept
  it out as a spoiler; the author asked for it.

## Status: v1.0-rc3-dev — the dim sky, and an audit (2026-11-25)

The whole of `src/main.asm` was read end to end and the ROM was run
through a cycle-counting harness. **The author has played it in Stella
and it plays; the dim grey below has not been seen in Stella or on a
console yet.**

- **The sky is dim now.** The top three bands of every room are drawn
  two luma steps darker than the world (`COL_SKY = $06` against
  `$0A`), so the scenery reads as distance and not as a platform you
  cannot reach. `GameKernel` was restructured to make room for one
  colour write per band; it is three bytes smaller than before, table
  included. To tune the grey by eye, change that one constant.
- **Two faults fixed.** RESET during a jump, a landing or the fanfare
  left channel 0 sounding through the title and the story screens; the
  title silences it now. And SELECT held with the stick and fire down
  made the reload run past the vertical blank in level 3 (2,843 cycles
  of the 2,816 it allows); a reload is now the whole of its frame,
  1,185.
- **One found by the A/B, not by reading:** for one frame at the start
  of every upside-down level, both shapes were drawn the right way up.
  The draw-position loop is a routine now (`DrawPos`) and `LoadLevel`
  ends in it.
- **Measured, and left alone:** title and epilogue frames are one
  scanline longer than the rest (263, not 262), because the logo's and
  the digits' last lines run long. The vertical blank is 89% full in
  the worst of 36,000 random frames, and the overscan is unused. The
  story kernel's text-start line sat at its full 76 cycles; it has
  three to spare now.
- **The kernel is proved unchanged.** Old ROM against new, the same
  random input for 36,141 frames: memory and audio identical, and
  scanline by scanline the same writes to the playfield, both shapes
  and both lamps, except the nine upside-down first frames, where the
  old ROM was the one that was wrong.
- **`tools/headless.py` counts cycles now.** A WSYNC sleeps to the end
  of its scanline, so a kernel line that runs long shows, and so does
  logic that outlasts the blank. Three checks came with it: the game
  kernel always reaches its next WSYNC in time (latest write 72 of
  76), the blank holds every frame with SELECT held and the stick
  down, and the band colours come out in order both ways up. Its A/B
  also compares every frame's memory now. Until today it compared each
  frame's state and audio but only the last frame's memory, so the
  `FireEdge` proof further down was weaker than it said.
- **Room:** 13 bytes free. RAM unchanged at 86 of 128.

## Status: v1.0-rc3-dev — the sky, and two levels that climb (2026-11-25)

The rooms were top-heavy: seven of the ten kept everything in the
bottom 40% of the screen. Now **eight rooms have scenery in their sky**
and **two climb into the top half**. Nothing here has been seen in
Stella or on a console; the pictures this was designed against are
drawn from the ROM's own bytes, not captured from a running game.

- **The rule:** anything drawn above the highest point any body can
  reach is scenery, and `check_levels.py` fails the build if a later
  change could make it reachable. It now judges that from the tops a
  shape could really stand on — by height, which can only
  over-estimate — so a pillar nothing can climb no longer puts its
  own top, and the sky above it, out of bounds.
- **What the sky looks like:** hollow windows and arches hanging from
  the top edge, a row of arches, a dotted ceiling; a different skyline
  in every room, so a room can be recognised when it is upside down.
  Hollow, because a filled slab floating up there reads as a platform
  you cannot reach. It costs no bytes: a level's drawing is a fixed
  36 bytes whether it is used or not.
- **5 Ascent climbs to du 24.** A floating stair of four centred
  slabs — each counts as one box — 16 du a step, which is one jump for
  Stella alone. Her light is on the top slab. Alex's is on the base
  slab: 16 du, too high for his own jump, so he still rides her head.
- **10 The Exit climbs to du 32.** A relay: Alex's home is the tower
  top, two of Stella's heads up; Stella's is the cap above it, 24 du
  higher than the tower, so he has to be standing home before she can
  climb on him. Seven moves, three lifts: still the longest plan in the
  game.
- **The pillars in 4 and 9 reach du 32 now** (they reached 40). At 40
  their tops were exactly one of Alex's-head boosts from the high
  ledges, so no sky was allowed in those rooms at all.
- **Room:** unchanged — 21 bytes free. Level records do not grow.

The ten levels as they stand:

1. **Awakening** — jump onto the step; the alternate light is on the
   column above it. One wide window high up, two small ones
2. **Exploration** — Stella alone; four hanging windows where two
   far-off blocks used to be
3. **Discovery** — shelves on both sides of the pillar; only Alex
   fits under it
4. **Connection** — each side of the pillar: a corner step anyone can
   reach, and a 16 du climb from it only Stella can make
5. **Ascent** — the floating stair to du 24; Alex onto its base
6. **Boost** — Alex needs Stella's head; the fourth ledge is solid
7. **Lift** — Stella needs Alex's back; a row of arches overhead
8. **Steps** — a relay across a beam; a dotted ceiling (the perches
   reach du 48, so this room has the least sky)
9. **Patience** — Stella needs Alex's back; corner steps
10. **The Exit** — the relay to the cap at du 32

No sky in 5 or 10: a shape can get into every band of those two.

## Status: v1.0-rc3-dev — the tune (2026-11-25)

Channel 1 plays a **tune** in place of the four-note drone (decision
#16, amended): **the lament**, C minor, chosen from three drafts by ear.
It has been heard only as a preview render and checked only by running
the ROM headlessly — **not yet in Stella, not on a console.**

```sh
make preview    # the tune rendered to build/tune-previews/, at tempo and under pressure
make headless   # run the ROM itself through every screen and check it
make pictures   # the manual's pictures, drawn from the ROM (needs Pillow)
```

What it is: each note struck twice, then a breath; up a minor third, up
a major third, then down step by step for two phrases, ending on the
lowest note the chip can play. Two thirds of the 8.5-second loop is
silence. It was drafted at half this speed and heard both ways; the
quicker one won, so that is how it is written (TEMPO 4, STRIKE 2 in
[`src/tune.inc`](src/tune.inc)).

How it works: one byte per step, 0–31 a pitch for a pure tone (higher
number, lower note), `$80` a rest. A step is 16 frames; the first two
of them are loud (volume 5), the rest soft (2), so the tone reads as
plucked and a repeated note articulates. While the clock is low the
frame counter is doubled and the tune plays twice as fast, which is the
signal the drone used to give. The tune is released for the completion
beat, so the fanfare has the floor to itself. What the melody loses is
the drone's "a little higher each level": a pure TIA tone cannot
transpose in tune.

- **A TIA pure tone cannot play every note in tune.** F5 and C6 are the
  weak ones; the tune leans on C minor, where the thirds come out truest.
- **Room:** see the status block above for the current count. RAM is at
  86 of 128 bytes. The four inline fire-button edge detectors became one
  routine (`FireEdge`) to pay for the tune.
- **The losing drafts and the old drone are gone** from `tune.inc`
  (they are in the history of commit `c3aa78a`). `HURRY = 0` there
  would stop the tune from doubling under pressure.
- **The reset routine now really clears RAM.** Its comment always said
  it did; the loop it used only ever cleared the stack page, so the
  title depended on RAM happening to be zero at power-on. Game 2 sets
  `State` outright for the same reason.
- **`tools/headless.py` runs the ROM itself:** a 6502 with the timer,
  the input and the audio registers, through every screen — a cold boot
  with garbage in RAM, title, story, play, the tune on its grid, the
  completion beat, two shapes, the ending, the upside-down replay, the
  epilogue, endless, reset (about 11 seconds; `--quiet` prints only
  failures). With `--compare OTHER.bin OTHER.sym` it feeds two ROMs the
  same random input and reports the first frame on which they differ —
  the way to prove a refactor changed nothing. It is not Stella: it
  cannot hear the tune, see the picture, or notice an overrun. On its
  first outing it found four faults reading the source had not, three
  of them in the new tune code and one, the RAM clear, in the game since
  v0.1.

- **How this was checked:** the refactor A/B'd by `headless.py` against
  the old inline code over eight random 6,000-frame runs with identical
  results (state and audio every frame; memory only on the last, see
  the block at the top), and every tune ROM walked through every
  screen. What is
  still to be judged by ear, in Stella and on a console: the sound, the
  volume against the effects, and the feel.

## Status: v1.0-rc3-dev — levels redrawn, five proofs (2026-11-25)

The first step of the "wow" pass (decision #35). The ROM is still
exactly 4096 bytes with 29 free. **None of this has been played in
Stella yet or seen on hardware** — the levels below are proven, not
playtested.

- **`tools/check_levels.py` runs five proofs** on every level and
  both goal layouts: drawn-is-solid (in *both* directions), no
  stance inside a slab, no home on the floor, the one-way rule, and,
  where that fails, a joint search that plays the level as one
  alternating sequence. `--joint` runs that search on every level.
- **Two audits it never had found real defects in the levels as they
  shipped:** L3, L5, L6, L9 and L10 drew solid-looking blocks with no
  collision behind them (a box added on one side of the mirrored
  playfield is drawn on the other side too), L3 woke Stella inside
  two slabs and her first press pushed her through one, and L5's
  only solution stood Alex inside a ledge. The floor rule #33
  describes was never in this checker; three homes were on the floor.
- **A new class of level: the relay**, where each shape's home can
  only be reached from where the other one ends up. The engine always
  played these; the old rule needed one shape to finish alone and
  rejected them. L8 and L10 are relays.

The ten levels after that pass (4, 5, 9 and 10 have changed since —
see the block above):

1. **Awakening** — jump onto the step; the alternate light is on the
   column above it, one jump short from the ground
2. **Exploration** — Stella alone; unchanged
3. **Discovery** — shelves on both sides of the pillar; only Alex
   fits under it
4. **Connection** — each side of the pillar is the same two-part
   lesson: a corner step anyone can reach, and a 16 du climb from it
   only Stella can make
5. **Ascent** — Stella: wall block, ledge, tower; Alex under the
   tower, then up on her head to the wall block beyond
6. **Boost** — Alex needs Stella's head; the fourth ledge is solid
7. **Lift** — Stella needs Alex's back; unchanged
8. **Steps** — a relay: over the beam or under it, then up off the
   friend who is standing home (4 moves)
9. **Patience** — Stella needs Alex's back; the steps are corner
   steps
10. **The Exit** — a relay over a tower, the longest plan in the
    game (7 moves)

## Status: v1.0-rc3-dev — place and hold (supersedes rc2.1)

The series' unified goal mechanic, backported from Game 2 (decision #26):
nobody exits at their marker any more — a level completes when everyone
present **stands on their own goal at the same time**, so any order can be
re-solved with all the pieces still in play. The exit-order locks and the
denial buzz are gone; order emerges (the booster finishes last). With it
came the colour-accessibility layer (decision #27): goal markers are now
**home lamps** — steady when held, blinking when vacant, blinking *fast*
for the shape you control — and Alex is always a step brighter than
Stella so the pair reads under red/green colour vision.

Final form: **Game 1 (The Story)** — 10 levels, then the world turns
upside down for 10 more, ending at the ? screen with your total time;
**Game 2 (Endless)** — SELECT at the title, random rooms in random
orientations, the clock tightening every level (45s − 2/level, floor
12s), rooms survived as your score.

Also in rc3: the title screen gained this game's one word — **ALONE**,
set small and white beneath the big rainbow STELLA mark (decision #28),
in the same five-zone layout Game 2 uses, so the mark lands in the same
place on screen in both games. Paid for by deleting the exit-order lock
byte that had been dead in all ten level records since place-and-hold.

- ROM: exactly 4096 bytes, **29 free** (up from 19: the #31 exact-home
  convergence replaced a box-overlap test with a single compare)
- All 10 levels + goal variants re-proven under place-and-hold by
  `tools/check_levels.py`, which now re-runs on every `make` (it used to
  live inside the ROM recipe and silently skip when the ROM was current)
- Manual draft: [MANUAL.md](MANUAL.md) (YOUR GOAL section updated)
- Remaining before v1.0: eyeball the new title screen in Stella, playtest
  the rc3 goal feel, then flash-cart hardware validation (owed again
  after rc3)

## Earlier: v0.6 — content complete: Quest 2, run clock

New since v0.4: **the run clock** — every playthrough is timed, and the
epilogue shows your total seconds above the blue square (48px sprite-text
kernel) — and **Quest 2**: press fire at the epilogue and the whole world
turns upside-down (the view flips; physics, controls and puzzles are
unchanged) with the timer always on. Finish Quest 2 to see your inverted
time. Also: the title logo wears the Atari rainbow (ember = timed mode via
SELECT), exit-order locks with blinking goals, and a four-note arpeggio
that rises each level and doubles tempo under time pressure.

## v0.4 baseline: 10 levels, narration, solver-verified

> Historical. The levels below are as they were first built; most
> have been redrawn since (rc2, then decision #35) — the current set
> is listed under Status above.

Title screen, then ten levels with narration screens at the story beats
("STELLA WAS ALONE." … "AND THEN THERE WERE TWO." … "THE WORLD SHIFTED."):

1. **Awakening** / 2. **Exploration** — Stella alone
3. **Discovery** — Alex appears (only he fits under the pillar)
4. **Connection** / 5. **Ascent** — ability-gated split routes
6. **Boost** — Alex needs Stella's head; 7. **Lift** — Stella needs Alex's back
8. **Steps** / 9. **Patience** — order matters: send the right one home first
10. **The Exit** — over and under the same tower, goals side by side

After level 10: the closing narration, then a small, unexplained blue square.

Features: character stacking (one-way), color-matched exit goals with two
pre-validated placements picked at random per playthrough, a level drone
that rises in pitch as the world wakes up, and **timed mode** on the left
difficulty switch (A = one minute per level, the background creeps red).
Console SELECT restarts a level; RESET returns to the title.

**Build-time solvability proof:** `make` runs `tools/check_levels.py`,
which re-implements the game physics and proves every level and goal
variant completable (including boost order) — an unsolvable level fails
the build. It already caught one real bug: Alex couldn't jump onto
Stella's head (she's 9 du tall, his jump rose 8.2).

ROM: ~930 bytes of the 4KB still free.

Remaining before release: playtest/tuning pass, real-hardware validation
via flash cart, the manual (expanded story prose).
