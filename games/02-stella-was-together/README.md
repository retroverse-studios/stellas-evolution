# Stella Was Together

**Game 2 of 4 · 8K ROM · F8 bankswitching**

Stella and Alex meet **Marcus** (blue square — fits where the others can't; see
[decisions.md #21](../../docs/decisions.md)). Three characters, cooperation
puzzles, and a spatial toolkit that grows across the game.

- **Theme:** connection & difference — "Not every challenge could be overcome alone."
- **Scope:** ~10 floors of a single climbed tower, 3 characters, narration between floors.
- **Spatial ladder (decision #18):** **wrap → portal → world-swap**, wrap always-on.
  Acts: 1 = wrap, 2 = portal, 3 = world-swap, 4 = finale (composes them).

## Current state (2026-07-16)

**The real game skeleton exists and boots.** Cold start → rainbow title on the
dusk gradient sky → Act 1 Floor 1 "Together Again" (three characters, wrap,
cooperative stacking) → a narration screen → back to title. Every floor is
solver-proven (`make` runs `tools/check_levels.py`; the build fails if a floor
isn't provably completable). One real floor is built so far; adding the next is
one row in the floor table + one narration string.

Build & run: `make` → `build/stella-was-together.bin` (exactly 8192 bytes).
Note: Stella caches a ROM in memory — after a rebuild, quit and reopen the
`.bin` (a file change alone won't hot-reload).

## Version map — where everything lives

| What | Where |
|------|-------|
| **Real game** (title, Floor 1, narration, in-order flow) | current source, `src/main.asm` |
| **The workbench** (all mechanic prototypes: world-swap T1-T3, wrap W1, portal P1, wrap+portal WP1, the Meeting Place sandbox, + Floor 1 + the active→P0 colour fix) | git tag **`game2-workbench`** — `git checkout game2-workbench && make` to build & play it |
| **Design decisions** | [`../../docs/decisions.md`](../../docs/decisions.md) #9, #17-24 |
| **Design plan / act structure / discoverability rules** | [`DESIGN-KICKOFF.md`](DESIGN-KICKOFF.md) |

The prototype *floors* were removed from the real game (they were scaffolding);
the *capabilities* they proved live in the engine. See decision #24 for how
world-swap re-attaches in Act 3.

## What's built vs. planned

- [x] Engine: 3-character physics, sprite multiplexer, **active→P0** colour
      (the controlled character never flickers), always-on wrap, per-colour goals
- [x] Title screen (rainbow logo on gradient sky; no menu — decision #22)
- [x] State machine + in-order floor flow + between-floor narration (Game 1 text kernel)
- [x] Act 1 Floor 1 "Together Again"
- [ ] Act 1 floors 2-3 (teach Marcus's fit; develop cooperation)
- [ ] Marcus wake-up opening (from Game 1's blue-square ending — DESIGN-KICKOFF)
- [ ] Act 2 (portal floors), Act 3 (world-swap floors — re-attach per #24), Act 4 finale
- [ ] Two-voice audio
