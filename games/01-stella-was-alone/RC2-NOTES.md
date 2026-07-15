# Stella Was Alone — v1.0-rc2 notes

RC2 rule: what is drawn solid must *be* solid. In rc1, every floating
ledge/perch was a one-way shelf (`top == bottom`) drawn as a full
16-scanline playfield slab — visually identical to Level 1's solid
block and Level 3's solid steps, yet you could walk and jump through
its sides. The engine was correct; the data was dishonest.

## What changed

### Boxes converted shelf → solid (18 of 18 — no shelves survive)

| Level | Boxes converted | New box | Notes |
|---|---|---|---|
| 1 "Awakening" | none | — | already all solid |
| 2 "Exploration" | 2 ledges (x28-48, x112-132) | [72,79] | see bottom-79 rule |
| 2 | 2 wall perches (x0-8, x152-160) | [56,64] | full drawn band |
| 3 "Discovery" | none | — | already all solid |
| 4 "Connection" | 2 ledges (x32-48, x112-128) | [72,79] | |
| 4 | 2 wall perches (x0-8, x152-160) | [56,64] | |
| 5 "Ascent" | 2 ledges (x32-48, x112-128) | [72,79] | |
| 6 "Boost" | 2 ledges (x40-48, x112-120) | [72,79] | boost still lands: Alex's head-top on Stella starts above the box bottom, so he rises through and lands — from the ground the underside now bonks |
| 7 "Lift" | 2 perches (x40-48, x112-120) | [64,72] | full band; boosted Stella now slides over the lip from beside the column instead of rising through it |
| 8 "Steps" | 2 ledges (x32-48, x112-128) | [72,79] | |
| 9 "Patience" | 2 perches (x40-48, x112-120) | [64,72] | |
| 10 "The Exit" | 2 ledges (x32-48, x112-128) | [72,79] | Stella must still walk beneath the right ledge to reach the exit — bottom-79 keeps that route |

**The bottom-79 rule — SUPERSEDED in rc2.1.** rc2 gave band-9 ledges
bottom 79 so grounded Stella (head at du 79) could still walk under
them; playtesting vetoed it (her top visibly clipped the slab's last
2 scanlines). See the RC2.1 section below: every [72,79] in the table
above is now full-band [72,80] and nothing walks under those ledges.
Band-8 and band-7 perches were always full drawn band ([64,72],
[56,64]) — walkers pass below those with 7+ du of visible daylight,
no overlap.

### Kept as one-way shelves

None. Where the puzzle wants jump-through (boosts in 6/7/8/9), the
geometry still provides it honestly: a character standing on a
partner's head starts with its top *above* the ledge's underside, so
the engine's bonk rule (which only stops bodies coming from fully
below) lets the boost pass while ground jumps bonk.

### Geometry nudges

- **L7 goal x 110→112 (primary), 42→40 (alt); L9 goal x 42→40 (both
  layouts).** Goal markers now sit flush on their 8px perches. rc1's
  markers overhung the perch edge by 2px, and `CheckGoals` has no
  on-ground test — Stella could jump from the ground, get side-clamped
  against the perch column, and brush the overhanging sliver mid-air,
  finishing the "boost required" levels solo. With flush markers every
  launch that could touch either bonks on the perch underside (body
  capped at du 72, marker ends at 64) or is clamped where the marker
  is out of reach. Solver now proves L7/L9 Stella *cannot* finish
  solo and *can* when boosted, both goal layouts.
- No playfield band data changed: every slab was already drawn in the
  band its box occupies. (L2 band-2 and L10 band-1 high structures
  remain boxless scenery — provably out of jump reach.)

## Solver upgrades (tools/check_levels.py)

The simulator now mirrors the engine byte-for-byte where it matters:

- **ClampBoxes fidelity:** boxes iterated 5→0 with the pushed x
  cascading into earlier boxes; the left-edge push (`LV - width`)
  wraps 8-bit; the final MIN_X/MaxX clamp is unsigned — a wrapped
  push lands at MaxX, exactly as `ReadInput` does.
- **Landing/bonk order:** both loops run 5→0, first hit wins; the
  partner's head is only consulted after every box misses, matching
  `.landLoop`'s fall-through.
- **Helper footing runs:** boost surfaces are now one span per
  *contiguous* run of the helper's reachable footing (gap tolerance =
  walk stride), so a solid tower splitting the ground no longer fakes
  support over the unreachable middle (closes rc1's documented
  caveat).
- **Documented abstraction gaps** (in the module docstring): constant
  air direction per arc (conservative), static helper surfaces with
  exit-order handled combinatorially, no recursive stacking, timers
  ignored, and quest-2 orientation-invariance (the flip is view-only:
  Band0/BandStep/CharDrawY/FlipG never touch physics, so one
  simulation proves both orientations).

`make`: solver passes all 10 levels × both goal layouts, ROM builds
at exactly 4096 bytes. `downloads/` untouched (rc1 ROM preserved);
the rc2 ROM is `build/stella-was-alone.bin`.

## Suggested Stella (emulator) checklist

- **L1:** walk into the white block's side — still blocks (unchanged
  control case).
- **L2:** jump beside a mid ledge and hold toward it — you now ride
  its side and slip over the lip; you can no longer drift through the
  slab. Walking under it on the ground still works.
- **L4/L5/L8/L10:** same side-solidity on every ledge; towers/pillars
  unchanged.
- **L6:** jump as Stella directly beneath a ledge — instant head bonk
  (no more rising through the slab). Boost Alex from her head under
  the ledge — still lands on top.
- **L7/L9:** try the rc1 cheese — jump from the ground at the goal
  marker: you bonk or clamp short, and the marker is untouchable.
  Boosted from Alex's back, approach the perch from beside it and
  drift over the lip at the top of the jump (jumping from directly
  below the perch now bonks — that's the intended feel change).
- **Quest 2 (upside-down) and endless mode:** spot-check L6/L7 —
  physics is identical, only the view flips.

---

# v1.0-rc2.1 — full-band solids, no clipping anywhere

Playtest veto on rc2's bottom-79 rule: Stella walking under a band-9
ledge overlapped the drawn slab by 1 du (2 scanlines) and read as
clipping. rc2.1 removes the exception entirely.

## Changes per level

- **All band-9 ledges → [72,80]** (full drawn extent): L2 ×2, L4 ×2,
  L5 ×2, L6 ×2, L8 ×2, L10 ×2. Grounded Stella is now hard-blocked at
  every ledge's side, pixel-exact with the drawn edges (probe-verified
  from both directions on all 12). She crosses mid ledges **over the
  top**: jump at the side, ride the lip, walk across, drop off. Alex
  (3 du tall, head at du 85) still passes beneath them and the
  pillars with visible daylight — no overlap.
- **L6 "Boost": no geometry change needed.** The under-ledge walk to
  Stella's goal is replaced by the over-the-top crossing, which the
  solver proves for both goal layouts. The boost lesson is intact
  (Alex solo=False, boosted=True, lock=1, both layouts); Alex's
  boost launches from beside the ledge column and drifts onto it.
- **L10 "The Exit": goals moved past the far ledge** — primary
  118/130 → 132/144, alternate swapped likewise. The old spots sat
  in the right ledge's column shadow, unreachable for Stella once
  its side became a real wall (over-the-top can't reach a ground
  goal underneath a slab). The finale reads the same: both markers
  side by side at the exit corner; Stella goes over the tower and
  over the last ledge, Alex slips under both.
- Nothing else changed: no other spawns/ledges/goals, no playfield
  band bytes. L1/L3/L7/L9 untouched (L7/L9 perches were already
  full-band and stand clear of walkers).

## Verification

- `make`: solver proves all 10 levels, both goal layouts
  (orientation is physics-invariant, so both quests are covered);
  ROM exactly 4096 bytes.
- Boost/cheat class re-probed after side-hardening: L6/L8 Alex
  solo=False boosted=True, L7/L9 Stella solo=False boosted=True,
  all layouts, locks pointing the right way.
- Global overlap scan: every reachable standing state of both
  characters in all 10 levels checked against every solid box —
  zero body/slab overlaps.
- Known residual (engine-level, pre-dates rc1, out of rc2.1's
  data-only toolbox): landing on the *partner's head* doesn't
  consult boxes, so parking Stella flush against a ledge and
  boarding her head with Alex can pose Alex's upper sliver inside
  the slab edge for a moment. Mid-air motion is clean (sides clamp,
  undersides bonk) and boosts work from non-overlapping boarding
  spots; a head-landing box check in UpdatePhysics would close it —
  noted for a future engine pass.

## Stella (emulator) test checklist for rc2.1

- **L2/L4/L5/L6/L8/L10 — every mid ledge, both sides:** walk into
  it on the ground: Stella stops flush at the drawn edge, zero
  overlap, zero pass-under. Jump beside it holding toward it: she
  rides the side and slips over the lip. Walk Alex under the same
  ledges — visible gap above his head, never blocked.
- **L6 solve:** boost Alex from Stella's head beside the ledge
  column (he drifts onto the ledge at the top of the hop), collect
  his marker, then Stella climbs over that same ledge — jump at its
  side, cross the top, drop off — and walks to her ground marker.
  Both layouts mirror left/right.
- **L10 solve:** Alex under the tower and under the far ledge to
  the corner markers; Stella over the tower, land in the slot
  between tower and ledge, climb the ledge, drop off its far side
  to the exit. Markers now sit past the ledge (x132/x144) — nothing
  to collect beneath a slab anymore.
- **L7/L9 unchanged from rc2:** perch goals flush, ground-jump
  grabs impossible, boost lands via the side-of-perch drift.
- **Quest 2 / endless:** same levels upside-down, identical
  physics — spot-check L6 and L10 with the walls flipped.
