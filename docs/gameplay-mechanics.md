# Stella's Evolution: Gameplay Mechanics Addendum

> Supplementary ideas to the core design-document.md and creative-brief.md.
> These concepts emerged from a later design session and are meant to be
> evaluated against the original docs, not replace them.

---

## "Chase the Beam" — Thematic Throughline

The Atari 2600 had no frame buffer. The TIA chip rendered one scanline at a time, in real-time. Programmers had to "chase the beam" — feeding the chip instructions fast enough to draw each line before the electron gun moved on.

**This should be the series tagline and the unifying metaphor.**

Every game in the series is about chasing something just ahead of you — understanding, connection, purpose, transcendence. The beam is always one step ahead. The characters are always catching up to what their hardware allows.

"Stella" was the Atari 2600's internal codename during development. The name carries weight.

---

## Bank Switching as a Puzzle Mechanic

The original design document describes bank switching as a technical implementation detail. But it could also be a **core gameplay mechanic** — especially in "Stella Was Together" (8K) and "Stella's Journey" (16K).

### The Idea

The level exists in two (or four) parallel states — one per ROM bank. The player can "switch banks" to change the level layout, but their position persists.

- What's a wall in Bank A might be a path in Bank B
- What's a platform in Bank A might be a hazard in Bank B
- Characters in different banks can affect each other (a switch in Bank A opens a door in Bank B)

### Implementation per Game

**"Stella Was Together" (8K — 2 banks):**
- Two parallel level states, toggled by the player
- Stella and Alex might each "live" in a different bank — you switch banks to switch characters, but the world changes too
- Puzzle: navigate both characters to their goals by alternating the world state
- This maps directly to F8 bankswitching — the mechanic IS the hardware

**"Stella's Journey" (16K — 4 banks):**
- Four parallel states
- With 3 characters + enhanced abilities, the combinatorics get rich
- Some puzzles require chaining: switch A→B to move Stella, B→C to move Alex, C→D to move Marcus, then D→A to reach the goal
- The Superchip's extra RAM could be represented as a "memory" mechanic — one piece of state that persists across ALL bank switches (e.g., a platform position, a switch state)

**"Stella Meets Thomas" (ARM):**
- Banks become fluid — the world morphs rather than hard-switching
- The characters can manipulate the transition itself
- Breaking the frame: levels extend beyond the 192-scanline display

### Why This Works

It's not just a gimmick — it maps 1:1 to real Atari 2600 hardware. Every puzzle teaches the player something true about how bankswitching works. The game becomes both entertainment and education about retro hardware.

---

## Flicker as Design Element

On the real 2600, when too many sprites share a scanline, the hardware alternates which ones are visible each frame — creating visible flicker. This was a limitation developers worked around.

**In Stella's Evolution, flicker should be intentional design:**

- In "Stella Was Together" and "Stella's Journey", when multiple characters are on the same scanline, they should visibly flicker — just like the real hardware
- This creates strategic considerations: keeping characters vertically separated reduces flicker
- In "Stella's Journey", the flicker could become a hazard — "corruption zones" where the display breaks down, killing characters on contact
- In "Stella Meets Thomas", flicker fades as the ARM coprocessor "fixes" the limitation — a visual metaphor for transcending constraints

### Optional: Flicker as a Character

A fourth character (circle shape) that naturally exists in a flickered state — visible every other frame. This character can pass through certain walls (because it's only "there" half the time) but is fragile.

**Note:** The original design has 3 characters (Stella, Alex, Marcus) through the first 3 games, with crossover characters in the ARM game. A "Flicker" character could be introduced in "Stella's Journey" (16K) as a late-game addition, or reserved for the ARM crossover. Evaluate against the existing character roster.

---

## Audio Design — TIA Specifics

The original docs mention audio progression but don't detail TIA-specific sound design. Here's a more detailed proposal:

**"Stella Was Alone" (4K):**
- TIA-only: 2 channels, each with 32 volume levels and ~30 tone patterns
- Use AUDC values 1 (buzzy), 4 (pure tone), 6 (bass), 12 (lead) for character sounds
- Jump = rising tone (AUDC 4, frequency sweep up)
- Land = brief low tone (AUDC 6, single frame)
- Goal = two-note fanfare (AUDC 12, ascending)
- Background: single sustained drone that shifts pitch with progress (AUDC 1)

**"Stella Was Together" (8K):**
- Same TIA, but use both channels for two-voice harmonies
- Character-specific timbres: Stella = pure (AUDC 4), Alex = buzzy (AUDC 1), Marcus = bass (AUDC 6)
- Level transition = the two channels resolve from dissonance to consonance

**"Stella's Journey" (16K):**
- More ROM for audio data = more varied sequences
- Introduce DPC-style patterns (rapidly switching between tones to simulate more channels)
- Environmental audio: different zones have different background drones
- Narrative moments marked by specific musical phrases

**"Stella Meets Thomas" (ARM):**
- ARM can pre-compute complex audio waveforms and stream to TIA
- Start each level in TIA-only sound, gradually introduce richer audio as you progress
- Final level: TIA sound transforms into something approaching a real soundtrack
- The audio evolution mirrors the visual evolution — starting constrained, ending transcendent

---

## Atari 2600 Bankswitching Quick Reference

Useful for level design meetings and puzzle prototyping.

| Scheme | Size | Banks | Hotspot Addresses | Era | Notable Games |
|--------|------|-------|-------------------|-----|---------------|
| None | 2K/4K | 1 | N/A | 1977-79 | Combat, Air-Sea Battle, Adventure |
| F8 | 8K | 2×4K | $1FF8, $1FF9 | 1980-82 | Pitfall!, River Raid, Enduro |
| F6 | 16K | 4×4K | $1FF6-$1FF9 | 1983-84 | Solaris, Jr. Pac-Man |
| F4 | 32K | 8×4K | $1FF4-$1FFB | 1984+ | Fatal Run, Radar Lock |
| FE | 8K | 2×4K | Stack-based | Activision | Decathlon, Robot Tank |
| E0 | 8K | 8×1K | $1FE0-$1FF7 | Parker Bros | Montezuma's Revenge |
| 3F | up to 512K | n×2K | $003F writes | Tigervision | Miner 2049er |
| Superchip | +128B RAM | Varies | $1000-$107F | 1983+ | Dig Dug, Crystal Castles |
| DPC | Custom | Custom | Custom | Activision | Pitfall II |
| ARM | Megabytes | Modern | Custom | 2005+ | Draconian, homebrew |

**Key concept:** The 6507 CPU sees a 4K window at $1000-$1FFF. Bankswitching swaps which physical ROM appears in that window by reading/writing "hotspot" addresses. This is literally what the bank-switching puzzle mechanic simulates in gameplay.

---

## Next Steps (Updated)

1. **Read "Racing the Beam"** (Nick Montfort & Ian Bogost) — the definitive book on Atari 2600 development philosophy
2. **Study the Stella emulator's debugger** — understand TIA registers, scanline timing, sprite positioning in practice
3. **Prototype "Stella Was Alone" in 6502 assembly** — start with DASM, a single rectangle moving horizontally, 1 level
4. **Design 3 bank-switching puzzles on paper** — prove the dual-state mechanic works before coding it
5. **Play Thomas Was Alone again** — take notes on how it paces character introductions and ability reveals
6. **Join AtariAge forums** — the homebrew community is active and helpful for 2600 development
