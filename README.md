# Stella's Evolution

> *Chase the beam.*

A four-part puzzle-platformer series for the **Atari 2600**, inspired by Mike Bithell's
*Thomas Was Alone*. Each game targets a real hardware tier of the 2600's lifespan —
from a bare 4K cartridge to a modern ARM-coprocessor cart — and the story's
complexity grows with the hardware. As the ROM expands, so does the characters'
awareness of their world.

"Stella" was the Atari 2600's internal codename during development. The name carries weight.

## The Series

| # | Title | Tech | Theme | Status |
|---|-------|------|-------|--------|
| 1 | **Stella Was Alone** | 4K, no bankswitching | Existence & isolation | In design |
| 2 | **Stella Was Together** | 8K, F8 bankswitching | Connection & difference | Planned |
| 3 | **Stella's Journey** | 16K, F6 bankswitching | Purpose & complexity | Planned |
| 4 | **Stella Was Aware** | ARM coprocessor (Harmony/Melody-class) | Meta-awareness & transcendence | Planned |

Games ship one at a time, starting with *Stella Was Alone* (see `docs/decisions.md`).

## Repository Layout

```
docs/     Shared design documents for the whole series
games/    One folder per game (source, assets, build)
  01-stella-was-alone/
  02-stella-was-together/
  03-stellas-journey/
  04-stella-was-aware/
```

## Reading Order for the Design Docs

1. [`docs/creative-brief.md`](docs/creative-brief.md) — story, characters, narrative arc
2. [`docs/design-document.md`](docs/design-document.md) — gameplay, levels, scope, timeline
3. [`docs/gameplay-mechanics.md`](docs/gameplay-mechanics.md) — addendum: "chase the beam" theme, bank-switching-as-puzzle mechanic
4. [`docs/technical-document.md`](docs/technical-document.md) — RAM/ROM maps, kernels, physics, tooling
5. [`docs/atari-element-prioritization.md`](docs/atari-element-prioritization.md) — what to cut when constraints bite
6. [`docs/decisions.md`](docs/decisions.md) — the live decision log (start here to see what's settled)

## Toolchain

- **Assembler:** [DASM](https://dasm-assembler.github.io/) (6502 assembly)
- **Emulator:** [Stella](https://stella-emu.github.io/) for testing and debugging
- **Hardware validation:** periodic testing on a real Atari 2600 via flash cart
- **ARM game:** C/C++ on Harmony/Melody-class cartridge hardware, plus DASM for the 2600-side interface

## On the Homage

This series is *inspired by* — not a clone of — *Thomas Was Alone*. All characters,
names, narration, and level designs are original. The final game acknowledges its
inspiration through wordless "echo" sequences with original, unnamed silhouettes
rather than borrowed characters (see `docs/decisions.md` #6). We gratefully credit
Mike Bithell's *Thomas Was Alone* as the spark for this project.

## License

- **Code** (everything under `games/`): [MIT](LICENSE)
- **Design documents and other written content** (everything under `docs/`):
  [Creative Commons Attribution 4.0](LICENSE-DOCS)
