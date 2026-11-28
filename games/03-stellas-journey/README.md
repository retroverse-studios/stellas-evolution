# Stella's Journey

**Game 3 of 4 · 16K ROM · F6 bankswitching with the Superchip (F6SC)**

The trio gains enhanced abilities — Stella clings to walls, Alex slides under
barriers, Marcus boosts others' jumps — as their world begins to fail. Spreading
"corruption zones" (the 2600's real flicker artifact, weaponized as story) are the
series' first antagonist force. Mid-game the trio meets **Flicker**, a fragile
circle that exists only every other frame — and the game ends with Flicker's
sacrifice to hold the way open.

- **Theme:** purpose & entropy — "Meaning wasn't about reaching an end, but in how you moved through the journey."
- **Scope:** 12-15 levels, 4 characters (Flicker joins mid-game — see decisions.md #3)
- **Key mechanics:** corruption zones as hazard, four parallel bank states (pending decisions.md #9), flicker as design element
- **Bodies bump** (decisions.md #53): characters block each other sideways for the first time, taught by an early room and the eyes reacting — the awareness arc's step from sight to touch
- **Dramatic turn:** the series' first true loss — see decisions.md #11

**Status:** design and prototypes. Nothing playable yet but test ROMs.
Start with [`DESIGN-KICKOFF.md`](DESIGN-KICKOFF.md).

## Prototype 1: the tall room (done)

A room two and two-thirds screens tall, a view that scrolls a du at a
time, and Stella, Alex, Marcus and Flicker drawn with the TIA's two
sprites. See decision #61 for what it found.

```
make            # both prototypes and all their checks (about a minute)
make pictures   # build/pictures: the hold, the pan, the cast
make room       # the room, drawn as text
```

Play `build/proto1.bin` in Stella. Left and right walk, fire jumps,
down and fire changes character, RESET starts again. The opening holds
on the homes at the top, then pans down to the cast; fire skips the
hold. There is no goal yet: the homes light up, and nothing happens
when everyone is home.

## Prototype 2: through the static (done)

Prototype 1's room with a band of corruption across it: gold static
that sends anyone who touches it back to their last lamp. Only Flicker
gets through, and anyone in a stack with Flicker: stand on Flicker,
or carry it, and you go too. A stack with Flicker in it walks and
jumps as one; only its top can jump off. See decision #63.

Play `build/proto2.bin` in Stella. To get through: climb to the rung
just under the static (the one with gaps either side), put someone on
Flicker's head, and jump with Flicker from the rung's inner end.

| File | What it is |
| --- | --- |
| `src/proto1.asm` | The test ROM: 16K, F6 with the Superchip, all in bank 0 |
| `src/room1.inc` | The room, made by `tools/genroom.py` |
| `tools/genroom.py` | Makes a room from a list of boxes and fails if what is drawn isn't solid |
| `tools/vcs.py` | A headless 2600, Game 2's CPU with F6 and the Superchip added |
| `tools/picture.py` | Pictures replayed from the ROM's TIA writes |
| `tools/check_proto1.py` | The checks: timing, the stack, the view, every character drawn exactly |
| `src/proto2.asm` | Prototype 2: the static, riding, stacks that move as one |
| `src/room2.inc` | Its room, made by `tools/genroom.py` (four versions of the playfield) |
| `tools/check_proto2.py` | Prototype 2's own checks, and a soak of stacks |
