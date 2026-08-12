# Stella Was Together

**Game 2 of 4 · 8K ROM · F8 bankswitching**

Stella and Alex meet **Marcus** (blue square — fits where the others can't; see
[decisions.md #21](../../docs/decisions.md)). Three characters, cooperation
puzzles, and a spatial toolkit that grows across the game.

- **Theme:** connection & difference — "Not every challenge could be overcome alone."
- **Scope:** ~10 floors of a single climbed tower, 3 characters, narration between floors.
- **Spatial ladder (decision #18):** **wrap → portal → world-swap**, wrap always-on.
  Acts: 1 = wrap, 2 = portal, 3 = world-swap, 4 = finale (composes them).

## Current state (2026-08-13)

**Acts 1, 2 and 3 are complete.** Cold start → title on the dusk gradient →
the **waking-Marcus opening** → nine floors in order, each with narration.
The spatial ladder stands full height: wrap (always on) → portal →
world-swap, each verb kept as the next arrives (decision #18).

**Act 1 — wrap:**
1. **Together Again** — the boost carries over; the totem teaches per-colour
   homes. *"NOT EVERY CLIMB IS MADE ALONE."*
2. **The Low Door** — Marcus's gift: a tunnel only he fits. *"THE DOOR KNEW
   WHO IT WAS FOR."*
3. **The Wall** — the wrap twist: the answer is off the edge of the screen.
   *"THEY WENT THE OTHER WAY AROUND."*

**Act 2 — portal** (UP in a blinking 8px column teleports the active
character to that column's mouth):
4. **The Fold** — locked room: every home above a stack-proof shelf; the
   only move is the door. *"IT FOLDED."*
5. **The High Door** — old verb gates the new: guard walls around the
   column; Alex needs a boost to reach it, and the lintel is his home.
   *"TOO HIGH."*
6. **The Cross** — the doors cross the screen; portals stop meaning "up".
   *"SIDEWAYS."*

**Act 3 — world-swap** (UP while grounded in a thin 4px **rift** beam at
the screen's edge swaps which truth the room is in; you never move — the
world does; the sky's gradient reverses as the constant which-world tell):
7. **Two Truths** — the homes sit visible on their totem from frame one,
   provably unreachable in world A; world B owns the approach ladder (and
   its 16-du rungs gate Alex into a boost). *"TWO TRUTHS / ONE PLACE."*
8. **The Handoff** — world A's staircase ends at a shared perch in the
   beam; world B's continuation begins there. Proven: NEITHER world alone
   can finish (the perch sits 2 du above the best stack-jump), so the
   handoff is the only way. *"EACH TRUE / IN TURN."*
9. **The Way Home** — the twist: the stairs are in world B but the homes
   are in world A — swap there, climb, and the lamps VANISH (in B those
   ledges were never true), so swap back onto what you earned. *"THE WAY
   HOME / WAS THROUGH."*

**The world-swap grammar** (what makes three characters safe in a world
that rearranges itself — the workbench was Stella-only and never faced it):
swaps are **grounded-only** and **rift-gated**, and every box that differs
between worlds is **one-way** — no body can be left inside a new wall; the
worst a swap can do is drop you. The delivery is a **pointer swap** (world
B's interior planes + boxes live after the record; `SwapWorld` repoints
three pointers and reverses the sky), not the workbench's 24-byte-RAM bank
copy — RAM is full (the lamps own those bytes now), and the mapper chip was
never visible to the player anyway. See decisions.md #9's amendment.

**The solver** runs per-floor proofs on every `make`: solvable with help,
teaching load-bearing (wrap-off / portal-off / swap-off / each-world-alone
negative proofs), playability margins, and the art audits (portal and rift
columns: the ON/OFF plane copies must differ by exactly the column mask the
input tables claim). Adding a floor is one row in each floor table + a
record + a narration string + a proof row.

**The bank-1 annex.** The title and narration states never share a frame
with play, so both live in bank 1 now (frame loops, kernels, logic, all
text) — bank 0 hands over at `MainLoop`'s top and gets the frame back on
fire. That's what funded Act 3 (and what the F8 skeleton was keeping honest
for). ROM: exactly 8192 bytes; **bank 0 has 11 bytes free** (Act 4's finale
will need a small diet first, as usual); bank 1 has ~2.5 KB free.

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
- [x] **Act 2 (portal floors)** — the verb re-attached from
      `game2-workbench` (pointer-swap blink; feet-du mouths), three floors
      (locked room / boost-gated door / the doors cross), all proven:
      solvable, portal-off unsolvable, art-vs-table audit clean
- [x] **Act 3 (world-swap floors)** — grounded rift-gated swaps; the
      one-way-difference grammar (audited); F7/F8/F9 with swap-off and
      each-world-alone negative proofs; the sky reverses as the
      which-world tell. The bank-1 annex (title + story moved out of the
      game bank) funded it
- [ ] Act 4 finale (one floor composing wrap + portal + swap)
- [ ] Per-act sky palettes (altitude as the progress bar), two-voice audio
- [ ] Dual-gravity variation floors where Act 4 wants them (decision #25)
