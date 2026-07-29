# Stella Was Together

**Game 2 of 4 · 8K ROM · F8 bankswitching**

Stella and Alex meet **Marcus** (blue square — fits where the others can't; see
[decisions.md #21](../../docs/decisions.md)). Three characters, cooperation
puzzles, and a spatial toolkit that grows across the game.

- **Theme:** connection & difference — "Not every challenge could be overcome alone."
- **Scope:** ~10 floors of a single climbed tower, 3 characters, narration between floors.
- **Spatial ladder (decision #18):** **wrap → portal → world-swap**, wrap always-on.
  Acts: 1 = wrap, 2 = portal, 3 = world-swap, 4 = finale (composes them).

## Current state (2026-07-29)

**Act 1 is complete and the game has its opening.** Cold start → rainbow title
on the dusk gradient sky → the **waking-Marcus opening** (black screen, the
blue square alone; the sky assembles band by band, his eyes appear, Stella
drops in, Alex slides in — fire skips) → Act 1's three floors in order, each
with its narration:

1. **Together Again** — the cooperative boost carries over from Game 1; the
   colour totem teaches per-colour homes. *"NOT EVERY CLIMB IS MADE ALONE."*
2. **The Low Door** — Marcus's gift (decision #21): a tunnel only he can
   enter — Stella is 1 du too tall for the slot, Alex's jump 6 du too weak
   for the sill; Stella alone crowns the slab above it.
   *"THE DOOR KNEW WHO IT WAS FOR."*
3. **The Wall** — the wrap twist: a wall to the sky, decoy stairs that
   promise the top and lie, Alex alone on the far side — and the answer is
   off the edge of the screen. *"THEY WENT THE OTHER WAY AROUND."*

Every floor is solver-proven (`make` runs `tools/check_levels.py`; the build
fails if a floor isn't provably completable, has a false-completion spot, or
its teaching isn't load-bearing — Floor 3 is proven UNSOLVABLE with wrap off).
Adding a floor is one row in the floor tables + a record + a narration string
+ a proof row in the solver.

Build & run: `make` → `build/stella-was-together.bin` (exactly 8192 bytes).
Note: Stella caches a ROM in memory — after a rebuild, quit and reopen the
`.bin` (a file change alone won't hot-reload).

## Version map — where everything lives

| What | Where |
|------|-------|
| **Real game** (title, Floor 1, narration, in-order flow) | current source, `src/main.asm` |
| **The workbench** (all mechanic prototypes: world-swap T1-T3, wrap W1, portal P1, wrap+portal WP1, the Meeting Place sandbox, + Floor 1 + the active→P0 colour fix) | git tag **`game2-workbench`** — `git checkout game2-workbench && make` to build & play it |
| **Design decisions** | [`../../docs/decisions.md`](../../docs/decisions.md) #9, #17-25 |
| **Design plan / act structure / discoverability rules** | [`DESIGN-KICKOFF.md`](DESIGN-KICKOFF.md) |

The prototype *floors* were removed from the real game (they were scaffolding);
the *capabilities* they proved live in the engine. See decision #24 for how
world-swap re-attaches in Act 3.

## What's built vs. planned

- [x] Engine: 3-character physics, sprite multiplexer, **active→P0** colour
      (the controlled character never flickers), always-on wrap, per-colour goals
- [x] Title screen (decision #28): the big STELLA mark lit in the neutral
      ramp, on the grey dusk gradient, TOGETHER set small beneath (no menu —
      decision #22). The Atari rainbow is saved for Game 4, when the world
      itself gains colour
- [x] **Greyscale world, colour = agency** (decision #27): the sky and
      platforms live on the neutral ramp, so every hue on screen belongs to
      something with a will — the characters and their home lamps. Sky ramps
      luma 0→8 (Game 1's void, grown a horizon); platforms sit at luma A, the
      one level no character uses, so nobody blends with the ground they
      stand on
- [x] State machine + in-order floor flow + between-floor narration (Game 1 text kernel)
- [x] **Marcus wake-up opening** (STATE_WAKE: the world assembles around
      Game 1's blue epilogue square; fire skips)
- [x] **Act 1 complete** — floors 1-3 (coop / Marcus's fit / the wrap twist),
      all solver-proven including the negative proofs
- [x] Solver upgrades: per-floor proof modes, helper-subset stepstools,
      wrap-off unsolvability gate; home heights **and boxes** are read from
      the ROM's `Floor?Home` tables, so the solver and the game cannot drift
      apart on where home is
- [x] Colour accessibility (decision #27): luma-ordered trio (Marcus <
      Stella < Alex in every state), HOME LAMPS (vacant homes blink — fast
      for the controlled character — and hold steady when their owner
      stands home), and Floor 1's shape echo (Alex's ledge is double-wide,
      like him)
- [x] **The completion beat** (`STATE_DONE`): Game 1's goal fanfare and its
      90-frame hold, so a floor's closing image — all three standing home
      together, which is what decision #26 exists for — gets seen instead of
      cut straight to text. The dusk sky takes a gentle 2-luma breath (Game 1
      pulses its black background; Game 2 pulses what replaced it)
- [x] **`AtHome`: one definition of home**, shared by `CheckGoal` and the
      lamps, testing grounded + x/y box overlap — Game 1's rule exactly, which
      is what decision #26 means by one goal mechanic. Home used to be "CharY
      equals the home value", kept honest only by a per-floor solver audit —
      the guarantee lived in the level data, not the code. Acts 2-4 (portals,
      world-swap's two truths of one place, anti-gravity regions) make
      same-height surfaces the point rather than an accident, so the test
      moved into the ROM
- [ ] Act 2 (portal floors — re-attach the portal verb from `game2-workbench`)
- [ ] Act 3 (world-swap floors — re-attach per #24), Act 4 finale
- [ ] Per-act sky palettes (altitude as the progress bar), two-voice audio
- [ ] Dual-gravity variation floors where Acts 2-3 want them (decision #25)
