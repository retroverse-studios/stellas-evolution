# Stella Was Together — Design Kickoff

**Game 2 of 4 · 8K ROM · F8 bankswitching · kickoff 2026-07-12**

The F8 skeleton in `src/main.asm` builds to exactly 8192 bytes and proves the
plumbing: two 4K banks, identical trampoline stubs at $F000, and the fire
button hopping between a Stella-red world (bank 0) and a Marcus-blue world
(bank 1). Everything below is what we pour into that shell.

## Scope recap

Per `docs/decisions.md` #3 and the design document:

- **Three characters:** Stella (tall red rectangle, high jump), Alex (flat
  green rectangle, fast, fits under overhangs), **Marcus** (blue square,
  balanced — the new arrival and the story's center of gravity).
- **8-10 levels**, short narrative interludes between them (decision #2:
  hybrid narration, budget grows from game 1's five screens).
- **Theme:** connection and difference — "Not every challenge could be
  overcome alone."
- **Audio:** two-voice TIA harmony; character timbres Stella = pure (AUDC 4),
  Alex = buzzy (AUDC 1), Marcus = bass (AUDC 6); level transitions resolve
  dissonance to consonance (gameplay-mechanics addendum).
- Flicker-as-multiplexing is embraced, not hidden: three characters on one
  scanline visibly flicker, so level design rewards vertical separation.

## What carries over from Game 1's engine

Game 1 (`games/01-stella-was-alone/src/main.asm`, ~2KB of code + data in 4K)
is the seed. Port, don't rewrite:

- **Frame skeleton** — the 262-line loop (VSYNC / TIM64T 44 / kernel /
  TIM64T 35) is already the skeleton of both banks here.
- **Physics** — 8.8 fixed-point gravity in double-lines (du), terminal fall,
  the head-boost stacking mechanic. Extend the character arrays from 2 to 3
  entries; the code is already indexed.
- **Level format** — the 69-byte record (12x3 PF bands + 6 collision boxes +
  spawns/goals) works as-is; add one spawn/goal pair for Marcus (+4 bytes)
  and revisit alternate-goal spots later.
- **Text kernel + `tools/gentext.py`** — the narration pipeline is done;
  Game 2 just gets a bigger script budget.
- **Solver** — `tools/check_levels.py` must learn Marcus's jump arc and,
  if decision #9 lands, dual-state levels (see below). Non-negotiable:
  build-breaking solvability checks saved Game 1 repeatedly.
- **Character switching** — Game 1's Down+Fire cycle extends to 3 characters
  unchanged, *unless* #9 binds switching to the bank switch.

New engine work unique to Game 2: a third multiplexed sprite (the biggest
kernel risk — prototype early), two-voice audio, and everything below.

## The open decision: #9, bank-switching-as-puzzle

`docs/decisions.md` #9 is still OPEN and gates all level design: do the two
ROM banks hold **two parallel world states** — same level, different walls —
with the player toggling between them while positions persist in RAM?

**Proposal: adopt Option B-leaning-A, and prototype before committing.**

The skeleton was deliberately built so both banks already draw *the same
place arranged differently* (different pillar layouts, different color).
The prototype is a straight extension:

1. **Paper first (the addendum's step 4):** design 3 dual-state puzzles on
   grid paper. Verify at least one needs a mid-air switch, one uses
   "wall here / path there", and one makes a switch in world A change
   something in world B. If 3 good puzzles don't exist on paper, adopt
   Option C and stop.
2. **ROM prototype (1-2 weeks):** in this skeleton, load *the same level
   record* from each bank's own data (bank 0 = state A geometry, bank 1 =
   state B geometry). Port Game 1's physics for one character into shared
   code duplicated per bank. Fire = switch world; character position/velocity
   live in RAM so they persist across the swap — which is the entire trick,
   and the entire pitch.
3. **Solver next:** teach `check_levels.py` a `(x, y, world)` state space.
   If the solver generalizes cleanly, that's strong evidence the mechanic is
   tractable; if the state space explodes, that's evidence for Option B
   (a few showcase levels) over A (signature mechanic throughout).

RAM budget check: Game 1 used ~60 of 128 bytes. A third character adds ~7,
dual-state adds roughly a world flag + a few cross-world switch states.
Comfortable — the constraint is kernel time and ROM, not RAM.

Character-switch coupling ("Stella lives in bank A, Marcus in bank B") is
seductive but should be decided *after* the prototype: it may overload one
button and confuse the player. Prototype world-switch and character-switch
as separate verbs first.

## First milestone — "one level, two worlds" (v0.1)

- [ ] Paper: 3 dual-state puzzles designed and hand-solved (kills or
      confirms #9 — do this first)
- [ ] Port Game 1 physics + one character (Stella) into bank 0
- [ ] Same level in both banks with divergent geometry; fire switches
      worlds, position persists
- [ ] Playfield collision works against *the current bank's* geometry
- [ ] Record #9 as DECIDED in `docs/decisions.md` with the prototype verdict
- [ ] Kernel spike: 3 multiplexed sprites (Stella + Alex + Marcus) on one
      screen, flicker only when scanlines overlap
- [ ] `make` runs the solver on Game 2 levels (even if only trivially)

Stretch: Marcus's arrival vignette — the blue square from Game 1's win
screen, now awake.
