# TODO: Screenshots for the manual

> **Status 2026-07-14 (second pass):** ten shots curated and embedded in
> `manual.html` (curated copies `01-…` to `10-…` are half-res NEAREST
> downscales; raw captures kept alongside). Only the optional timed-HUD shot
> remains. Deliberately unused: the endless tally screen (`stella-was-alone_3.png`,
> "? 003") — it shows the small blue someone, and the manual keeps its secrets.

**How to capture:** launch Stella on the RC1 ROM and press **F12** at each moment
below — snapshots land in `manual/screenshots/` if Stella was started with:

    /Applications/Stella.app/Contents/MacOS/Stella \
      -snapsavedir "$(pwd)/manual/screenshots" -snapname rom \
      ../../downloads/stella-was-alone-v1.0-rc1.bin

(Or grant the terminal Accessibility + Screen Recording in System Settings →
Privacy & Security, and Claude can drive the game and capture these itself.)

Stella numbers the files automatically; rename to the names below so the
manual can reference them stably.

## Shot list

| # | File | Moment | Section | Status |
|---|------|--------|---------|--------|
| 1 | `01-title-rainbow.png` | Title screen, rainbow lettering | 2 · Getting Started | ✅ embedded |
| 2 | `02-narration-two.png` | "AND THEN THERE WERE TWO." narration | 1 · The Story | ✅ embedded |
| 3 | `03-first-steps.png` | Early level: Stella and her marker | 3 · Your Goal | ✅ embedded |
| 4 | `04-jump.png` | Stella mid-jump over the pedestal | 2 · Getting Started | ✅ embedded |
| 5 | `05-boost.png` | Alex on Stella's head at the tall wall | 4 · The Shapes | ✅ embedded |
| 6 | `06-both-shapes.png` | Bright (active) Stella + dim Alex | 4 · The Shapes | ✅ embedded |
| 7 | `07-upside-down.png` | Inverted level, both shapes on the ceiling | 5 · Game 1: The Story | ✅ embedded |
| 8 | `08-title-ember.png` | Title after SELECT — ember sky | 6 · Game 2: Endless | ✅ embedded |
| 9 | `09-endless-red-sky.png` | Endless with the red well into the sky | 6 · Game 2: Endless | ✅ embedded |
| 10 | `10-world-shifted.png` | "THE WORLD SHIFTED. CHANGED." narration | 5 · Game 1: The Story | ✅ embedded |
| 11 | ~~`11-timed-hud.png`~~ | ~~LEFT DIFFICULTY = A level timer~~ | 7 · Console Switches | ❌ dropped — there is no HUD; timed mode shows as the same red-sky effect already pictured in shot 9 (sky reddens in the last 16 s, then the level restarts) |

## Deliberately NOT screenshotted

- **The epilogue** (small, blue, silent). The manual only hints at it —
  "some questions answer themselves in time" — and a screenshot would spoil
  the reveal. Classic Atari manuals kept their secrets; so do we.
- **The final time screen** — the player's number should be their own.

## Style notes for embedding

- Frame each shot like a period manual: thin dark border, slight rounding on
  the corners (CRT vibe), caption set like the existing `figcap` style —
  e.g. *"Fig. 2 — Actual game screen. Stella and Alex find the exits."*
- Atari manuals loved the phrase **"actual game screen"** — use it once.
- Keep shots at integer scale (2× or 3×) so pixels stay crisp; no smoothing.
- Capture with default NTSC TV effects off (or `-tv.filter 0`) for clean pixels.
