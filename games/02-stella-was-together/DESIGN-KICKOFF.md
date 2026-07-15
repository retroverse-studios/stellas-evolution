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
- [x] Kernel spike: 3 multiplexed sprites (Stella + Alex + Marcus) on one
      screen, flicker only when scanlines overlap — **done in v0.1-visual**
- [ ] `make` runs the solver on Game 2 levels (even if only trivially)

### v0.1-visual (shipped in bank 0, 2026-07)

The kernel spike grew into a playable one-level demo that also banks the
8K visual budget's first installment:

- **Three-sprite multiplexer:** P0 is Stella's alone; Alex and Marcus
  time-share P1. When their scanlines don't collide (≥ 2 du gap) the kernel
  repositions P1 mid-frame — one du spent on an inline RESP1/HMOVE hop —
  and all three draw solid at 60Hz. When they do collide, P1 alternates
  tenants at 30Hz, per the flicker-is-embraced rule. The hop is nudged off
  playfield band boundaries so no PF update is ever missed.
- **Per-level palette:** `LvlSkyTbl`/`LvlPFTbl` drive COLUBK/COLUPF; the
  demo level is dusk blue with warm tan platforms — visibly not Game 1.
- **Banded sky gradient:** 5 shades over the 12 playfield bands, built in
  RAM at level load from the palette base.
- **Eyes:** each character has an eye row that sits on the side last
  walked toward and blinks (~every 2 s). Marcus (blue square, balanced
  stats — 1.5 px/frame walk, jump apex between Alex's and Stella's) is in.
- **Squash & stretch:** 1 du taller while rising, 1 du shorter for 4
  frames on a real landing — draw-only, physics untouched.
- Game 1's physics (8.8 gravity, box collision, bonk, head-standing — now
  against either friend) and the Down+Fire switch verb (extended to a
  3-cycle) are ported. Fire is jump; decision #9 remains open and bank 1
  still holds the skeleton's placeholder frame.
- Not yet: goals/levels beyond the demo screen, narration, two-voice
  audio, the solver, any bank-1 gameplay.

## The opening: waking Marcus (promoted from stretch, 2026-07-15)

Game 2 opens on a recreation of Game 1's epilogue: black screen, the small
blue square, silent. Then the world *evolves in* — the banded sky gradient
assembles step by step (one band color, then 2, 3, 4… until the full
gradient stands), color saturating as it goes, and Marcus's eyes appear
(first blink = the moment he wakes). Stella drops in from the left,
Alex slides in under her, and the first level begins.

Cost estimate: ~200-300 bytes (a color-ramp table + a state that reuses
the existing gradient builder and eye code). The morph doubles as the
series' visual thesis: each game, the world gains fidelity.
