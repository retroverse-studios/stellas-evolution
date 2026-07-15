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

## Candidate mechanic: dual gravity (added 2026-07-15)

One shared screen, one character whose gravity points up: they walk the
ceilings and undersides of the SAME platforms everyone else stands on
(every floor is somebody's ceiling — no new level data). Estimated cost
~150-300 bytes: a per-character gravity sign, mirrored landing/bonk
logic, ceiling goal spots, eyes drawn on the character's bottom edge.
Rejected for Game 1 (~80 bytes free, arc already complete); it is
Game 2's insurance policy — **if #9 dies on paper, dual gravity is the
signature mechanic instead**, and both "worlds" being visible at once
is arguably friendlier than a remembered hidden state.

## Proposed act structure (2026-07-15, pending the #9 paper gate)

The whole game is one tower; each level a floor; nobody climbs alone.

1. **Act 1 — together (2-3 floors):** three characters, normal world.
   Marcus's wake-up opening; the low-ceiling floor that teaches his gift.
2. **Act 2 — the other side of the sky (2-3 floors):** dual gravity.
   One friend on the ceiling; cooperation across the divide.
3. **Act 3 — the world has two answers (2-3 floors):** #9's toggle.
   First A-normal/B-normal; then A-normal/B-INVERTED — the toggle also
   flips who hangs from the sky, fusing acts 2 and 3. Early floors gate
   the switch to **portal zones** (a blinking column; a cheap x-range
   check) as the teaching constraint; later floors grant free switching
   as the mastery reward.
4. **Act 4 — meet in the middle (1-2 floors):** parallel + dual at the
   tower top. Two climb the floor, one descends the ceiling; the game
   ends where they meet. The final portal is the landmark.

Scope honesty: that is 8-10 floors total, 2-3 per act — Thomas Was
Alone pacing, no filler. Solver must grow a (x, y, world, gravity)
state space; if it explodes, Act 4 simplifies before Act 3 does.

## UX frame (decided 2026-07-15)

- **Naming ladder:** the series is a *cycle* (four movements); each game
  a *movement*; movements contain *acts*; Game 2's levels are *floors*
  of the tower. Movement two, act three, floor eight.
- **Act shape: 3 / 3 / 3 / 1.** Teaching acts get three beats —
  introduce (safe), develop (combine), twist (subvert). The finale act
  is one spectacular floor: short climaxes read as confidence.
- **Altitude is the progress bar.** The per-act sky palette shifts as
  the tower is climbed (dusk violet → deep night → the toggle acts'
  strange hues → dawn at the summit). No HUD; the sky tells you where
  you are.
- **Six discoverability rules for the #9 toggle:**
  1. Act 3 opens with a locked-room floor: exit visibly walled, one
     blinking portal column, nothing else to try. The only move teaches
     the mechanic.
  2. World A warm, world B cool — switching is a full-screen color
     event. The sky gradients run in OPPOSITE directions per world, a
     constant tell for which truth you stand in.
  3. The switch has a sound signature: the two-voice chord resolves
     differently per world.
  4. Portal-gated switching first; free switching later, as graduation.
  5. Narration primes the act ("The tower had two truths, and only
     ever told one.")
  6. The mid-air switch is the act's twist floor, never its opening.

## Spatial mechanics — the direction that emerged from playtesting (2026-07-15)

Playtesting the world-swap prototype surfaced a better spine for Game 2.
The full-screen world-swap reads as "teleport to a different place," not
"same place rearranged" — cognitively heavy for 8K. Out of that came a
clearer plan:

- **Series axis — perceived spatial scale grows with the ROM:**
  Game 1 (4K) = bounded, one static screen ("four kilobytes of
  existence"); Game 2 (8K) = confined screen whose *space connects*
  (topology, not size); Game 3 (16K) = the world *extends* (scrolling,
  a journey — "Stella's Journey"); Game 4 (ARM) = transcendent, the
  screen a window onto something larger. Game 1 stays sealed — no
  backport; its confinement is the point, and the absence of wrap is
  what gives Game 2's wrap meaning.
- **Game 2's spatial ladder: wrap → portals → world-swap.** Increasing
  in difficulty *and* conceptual weight: move through space → shortcut
  through space → change space itself. World-swap (the #9 mechanic) is
  the hardest final rung, not the spine — which resolves #9 toward a few
  showcase floors (Option B), not a signature-throughout mechanic.
- **Mirrored playfield is KEPT.** Asymmetry comes from *actor placement*
  (characters, per-color goal markers, portals sit where you put them —
  the playfield mirror doesn't constrain them). True asymmetric PF was
  measured as not fitting the cycle-tuned kernel; unnecessary anyway.
- **Portal shimmer, not blink.** The portal column flows (a dark notch
  travels down it) so it never fully disappears — a blink read as an
  open/closed *timing gate*, which it is not.
- **Prototype status:** W1 wrap floor built + solver-proved load-bearing
  (walk off one edge, arrive the other; "the long way around"). Portal
  floor in progress. Wrap confirmed to feel good in play.
- **Puzzle idea banked:** a half-height barrier with decoy "climbable"
  platforms — the obvious route is a bluff; wrap is the real answer.

## First milestone — "one level, two worlds" (v0.1)

- [x] Paper: 3 dual-state puzzles designed and hand-solved — done as
      three built + solver-proven floors (T1/T2/T3, see v0.2 below)
- [x] Port Game 1 physics + one character (Stella) into bank 0
- [x] Same level in both worlds with divergent geometry; UP (in a
      portal) switches worlds, position/velocity persist in RAM
- [x] Playfield collision works against *the current world's* geometry
      (PlatPtr repointed on every switch)
- [ ] Record #9 as DECIDED in `docs/decisions.md` with the prototype verdict
- [x] Kernel spike: 3 multiplexed sprites (Stella + Alex + Marcus) on one
      screen, flicker only when scanlines overlap — **done in v0.1-visual**
- [x] `make` runs the solver on Game 2 levels — proves each toggle floor
      solvable WITH the switch and unsolvable WITHOUT it

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

## v0.2 "one level, two worlds" — the #9 decision-gate prototype (built)

Three Stella-only toggle floors now sit after the Meeting Place sandbox
(floor 0). SELECT cycles floors 0 → T1 → T2 → T3 → 0; reaching a floor's
red marker (while grounded) advances automatically.

**The mechanic.** Each toggle floor is one room with two geometries.
Push **UP inside a blinking portal column** to swap worlds. World A is
warm with the sky brightening toward the horizon; world B is cool with
the gradient running the opposite way — a constant which-world tell,
plus a full-screen palette flip and a short pitch-swept chime (up into
A, down into B) on every switch. Every character X/Y/velocity stays in
RAM across the swap; only the geometry and palette change. That RAM
persistence is the whole pitch.

**Bank / kernel architecture (measured).** The engine and the single
kernel live in bank 0; the kernel draws the playfield through pointers.

- **PF0** (the outer frame + the floor) never differs between worlds, so
  it stays in bank-0 ROM (one shared table for all toggle floors).
- **PF1 + PF2** carry the portal column and the interior geometry that
  the switch changes, so a toggle floor points them at a **24-byte RAM
  copy, `PFRam`**. On each switch `PFRam` is refilled: world A's 24 bytes
  are copied from bank 0; world B's live in bank 1 and are fetched by
  `jsr GoCopyB` → `CopyBWorker` (bank 1) → `jmp GoBackBank0`, all through
  byte-identical trampoline stubs (a build-time `STUB_SIZE` assert
  guards the two banks against drift).
- **Both worlds' collision boxes** stay in bank 0 beside the physics;
  `PlatPtr` is repointed at the current world's set on each switch.
- Bank 1 is now data + the copy worker; its old placeholder frame loop
  is dead plumbing, kept only to keep the F8 layout honest.
- The blinking portal is one playfield bit toggled in `PFRam`'s top 11
  bands each frame; the goal marker reuses the idle **P1** sprite (P0 is
  Stella) tinted her red — no new kernel code.

**Measured costs.** RAM: +32 bytes (24 `PFRam` + 8 of floor/world/edge
state), reaching $F3 — the 6502 stack (down to ~$F9 in the deepest
frame) still clears it. ROM: unchanged at exactly **8192 bytes**; bank 0
has ~1.75 KB free, bank 1 ~3.8 KB. The kernel and its cycle-tight timing
are **untouched** — reading `PFRam` from zero-page RAM costs the same as
reading ROM.

**The RAM wall (a real #9 finding).** A floor whose *floor itself*
differs between worlds would need a third per-world plane (PF0) in RAM —
36 bytes of `PFRam` — which collides with the stack. So a *forced*
mid-air switch can't come from a disappearing floor. T3 instead forces
it with per-world *interior* platforms over a shared floor: a launch
step exists only in world A, the goal's tall pillar only in world B, and
the pillar sits too high to gain from the floor — so the switch must
happen in mid-air off the step. This fits the 24-byte budget.

**The floors.**

- **T1 — the locked room.** A full-height central divider (world A)
  walls Stella off from her marker; one portal. Switching to world B
  removes the divider and opens the path.
- **T2 — wall here, path there.** Two portals. World-A walls and
  world-B walls interleave down a corridor, so no single world crosses;
  the solution alternates A → B → A at the two portals.
- **T3 — the twist (mid-air switch).** Forced as above: launch off the
  world-A step, flip to world B in mid-air over the gap, land on the
  world-B pillar. Standing-only switching is provably insufficient.

**Solver.** `tools/check_levels.py` reimplements Stella's exact
fixed-point physics (ported from Game 1) over an `(x, feet, world)`
state space with portal-gated switching, including momentum-preserving
mid-air switches, and a *grounded* goal rule (arcing through a marker's
airspace in a world where nothing supports it is not a win — this is
what forces T3 to be solved mid-air). For each floor it proves two
things and `make` fails if either breaks: **solvable WITH switching**
(the floor can be finished) and **UNSOLVABLE WITHOUT it** (the toggle is
genuinely the reason — not ordinary platforming). All three pass.

Solver tractability: the `(x, feet, world)` space stayed small and the
BFS is instant, which is evidence the mechanic is tractable at the tool
level — a point in favour of Option A (signature mechanic) over a
handful of showcase levels. See the report for the honest verdict.

**Scoped / deferred (honesty ledger).**

- Toggle floors are Stella-only (documented); Alex/Marcus are parked
  off-screen and their physics is skipped there.
- Visual vs. collision: the mirrored playfield means every wall is drawn
  as a symmetric pair, and platform tops land on ~8-du band boundaries,
  so a step/pillar top can sit a few du off its collision top. The
  *collision* (what the solver proves) is exact; the art approximates.
- Per-act sky palettes, narration, the "waking Marcus" opening, and
  two-voice harmony are still future work; only the switch chime exists.
- `docs/decisions.md` #9 is deliberately left for the user to record.
