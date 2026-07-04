# Stella Was Alone

**Game 1 of 4 · 4K ROM · no bankswitching**

Two shapes — Stella (tall red rectangle, high jump, slow) and Alex (flat green
rectangle, fast, fits under overhangs) — wake alone in a constrained world and
learn that some heights and gaps can only be crossed together.

- **Theme:** existence & isolation — "Stella was alone. She didn't know why."
- **Scope:** 4-5 levels, 2 characters, 3-5 text screens (the entire script)
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

## Status: v0.6 — content complete: Quest 2, run clock, 62 bytes to spare

New since v0.4: **the run clock** — every playthrough is timed, and the
epilogue shows your total seconds above the blue square (48px sprite-text
kernel) — and **Quest 2**: press fire at the epilogue and the whole world
turns upside-down (the view flips; physics, controls and puzzles are
unchanged) with the timer always on. Finish Quest 2 to see your inverted
time. Also: the title logo wears the Atari rainbow (ember = timed mode via
SELECT), exit-order locks with blinking goals, and a four-note arpeggio
that rises each level and doubles tempo under time pressure.

## v0.4 baseline: 10 levels, narration, solver-verified

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
