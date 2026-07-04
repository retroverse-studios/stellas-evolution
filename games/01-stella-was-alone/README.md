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

## Status: v0.3 — 7 levels, character stacking

Title screen ("STELLA", fire to start), then seven levels following the
story's staged introduction:

1. **Awakening** — Stella alone; learn to move and jump
2. **Exploration** — Stella alone; climb the ledges to the high perch
3. **Discovery** — Alex appears; only he fits under the pillar, and low
   blocks make both characters hop along the way
4. **Connection** — Stella climbs to her perch while Alex slips underneath
5. **Ascent** — both routes through the same tower
6. **Boost** — the ledge is beyond Alex's jump: he leaps from Stella's head
7. **Lift** — the perch is beyond even Stella's jump: she needs Alex's back

Characters can stand on each other (one-way, no carrying — that's an 8K
feature). Each character exits through its own color-matched goal marker and
vanishes; the level ends when everyone present is home. Console **SELECT
restarts the level** (needed if you send someone home in the wrong order in
6/7), RESET returns to the title. Solid boxes block sideways movement and
bonk heads; one-way ledges don't. TIA sounds throughout.

ROM headroom: ~2.0KB of the 4KB still free.

Next up:
- The five narration text screens (48px text kernel) — the 4K script
- More levels (69 bytes each) as playtesting suggests
- Real hardware validation via flash cart
