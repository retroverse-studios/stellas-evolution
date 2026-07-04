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

## Status: v0.1 sandbox — playable

One room: walls, ground, a low center block (both characters), side ledges
(Stella's jump only), and high corner perches (climb via the ledges). Both
characters render with per-character physics; the active character is drawn
brighter. 96 double-line kernel, 12-band mirrored playfield, swept landing
collision, 8.8 fixed-point vertical physics.

Next up (roughly in order):
- Goal markers (ball sprite) + level-complete detection for both characters
- Multiple levels via level-data tables
- Jump/land sounds (TIA: AUDC 4 rising sweep / AUDC 6 thump per the addendum)
- Title screen and the five narration text screens
- Real hardware validation via flash cart
