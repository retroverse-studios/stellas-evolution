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

## Status: v0.2 — full game loop, 5 levels

Title screen ("STELLA" on the asymmetric playfield, fire to start), then five
levels following the story's staged introduction:

1. **Awakening** — Stella alone; learn to move and jump
2. **Exploration** — Stella alone; climb the ledges to the high perch
3. **Discovery** — Alex appears; only he fits under the pillar (8-du gap vs
   Stella's 9-du height)
4. **Connection** — Stella climbs to her perch while Alex slips underneath
5. **Ascent** — both routes through the same tower

Goal markers are color-matched missiles (red = Stella's, green = Alex's); a
marker vanishes when its character reaches it, and the level ends when every
present character is home. Solid boxes block sideways movement and bonk heads
(one-way ledges don't), which is what makes Alex's low-gap ability real. TIA
sounds: rising jump sweep, landing thump, two-note goal fanfare. Win screen
cycles colors, then back to the title.

Next up:
- The five narration text screens (48px text kernel) — the 4K script
- Tune difficulty from playtesting; maybe a 6th level
- Real hardware validation via flash cart
