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

Requires [DASM](https://dasm-assembler.github.io/). Test in the
[Stella](https://stella-emu.github.io/) emulator.

```sh
# (build scripts to come)
dasm src/main.asm -f3 -obuild/stella-was-alone.bin
```

See [`../../docs/`](../../docs/) for the full design documents.

**Status:** in design — first prototype target: one rectangle moving on one level.
