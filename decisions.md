# Stella's Evolution: Open Decisions

> Decisions that need to be made before or during development.
> Mark each as DECIDED with the outcome when resolved.

---

## 1. Target Platform for Development

**Question:** Develop directly in 6502 assembly for real Atari 2600 hardware from the start, or prototype in another language first?

**Options:**
- A) **6502 assembly from day one** — authentic, no throwaway work, but slow iteration
- B) **Prototype in Python/web, then port** — faster iteration but porting is significant work and doesn't map 1:1 to hardware constraints
- C) **Assembly with Stella emulator** — real assembly but test in emulator, hardware validation later

**Considerations:**
- The original technical document is written entirely for real hardware (RAM maps, ROM layouts, cycle budgets)
- The bank-switching-as-puzzle-mechanic only works authentically in real assembly
- Prototyping in another language won't teach you about TIA timing constraints
- The homebrew Atari community (AtariAge) can help with assembly questions

**Recommendation:** Option C. Write in assembly, test in Stella emulator, validate on hardware periodically.

**Status:** OPEN

---

## 2. Narration Style

**Question:** How is the story presented to the player?

**Options:**
- A) **Text screens between levels** (Thomas Was Alone style) — the creative brief assumes this
- B) **Environmental storytelling only** — no text, level design tells the story
- C) **Hybrid** — minimal text in 4K, increasing narration through the series
- D) **External narration** — story told in a companion booklet/website (classic Atari approach)

**Considerations:**
- Text on the 2600 is expensive (eats ROM)
- The creative brief has specific dialogue written for each game
- The 4K version has almost no room for text
- Classic Atari games shipped with detailed manuals that told the story

**Status:** OPEN

---

## 3. Number of Characters per Game

**Question:** Stick with the original 2-2-3-5+ character progression, or adjust?

**Original plan (design-document.md):**
- "Stella Was Alone" (4K): 2 characters (Stella + Alex)
- "Stella Was Together" (8K): 3 characters (+ Marcus)
- "Stella's Journey" (16K): 3 characters with enhanced abilities
- "Stella Meets Thomas" (ARM): 5+ characters including crossover

**Alternative (from gameplay-mechanics addendum):**
- Consider a 4th character "Flicker" in the 16K version (circle, flickers between banks)
- Or introduce Flicker in the ARM version as a crossover element

**Considerations:**
- Each character on the 2600 requires sprite multiplexing — more characters = more complex kernel
- 3 characters in 8K is already ambitious for sprite multiplexing
- The Flicker concept is clever but adds significant technical complexity

**Status:** OPEN

---

## 4. Scope for First Release

**Question:** Ship all 4 games, or release incrementally?

**Options:**
- A) **All 4 at once** — complete experience but years of development
- B) **One at a time** — "Stella Was Alone" first, gauge interest, then continue
- C) **First two together** — 4K + 8K as a natural pair, then 16K + ARM later

**Considerations:**
- Option B lets you validate the concept with the smallest investment
- The 4K game alone is a complete experience (the creative brief confirms this)
- Physical cartridge production is easier for individual releases
- The narrative works both as standalone (4K) and as a series

**Recommendation:** Option B. Ship "Stella Was Alone" first. It's the purest expression of the concept.

**Status:** OPEN

---

## 5. Connection to SwipeVerse / RetroVerse Brand

**Question:** Is Stella's Evolution connected to the other RetroVerse games?

**Options:**
- A) **Completely separate** — standalone Atari game
- B) **Easter eggs** — subtle RetroVerse references hidden in levels
- C) **Shared universe** — Stella exists in the same multiverse as SwipeVerse
- D) **Cross-promotion** — reference each other in marketing but not in-game

**Considerations:**
- Stella's Evolution targets actual Atari hardware; SwipeVerse is a web game
- The audiences may not overlap much
- Easter eggs are low-cost and fun (e.g., a RetroVerse logo hidden in a level)

**Status:** OPEN

---

## 6. The Thomas Was Alone Crossover (ARM Game)

**Question:** How literal is the crossover with Thomas Was Alone?

**Options:**
- A) **Direct crossover** — Thomas and friends appear as named characters (needs Mike Bithell's blessing)
- B) **Spiritual crossover** — shapes that are clearly inspired by but not named Thomas
- C) **Meta-reference** — the characters discover they're an homage, but don't literally meet Thomas

**Considerations:**
- Option A requires IP permission from Mike Bithell / Bithell Games
- Option C is the safest and most interesting narratively
- The creative brief currently assumes Option A ("My name is Thomas")

**Status:** OPEN — may need to contact Bithell Games if pursuing Option A

---

## 7. Physical Cartridge Production

**Question:** Produce physical Atari 2600 cartridges?

**Options:**
- A) **ROM-only** — distribute as .bin files for emulators and flash carts
- B) **Limited physical run** — small batch through AtariAge or similar
- C) **Full production** — professional packaging, manual, box art

**Considerations:**
- Physical carts are meaningful for the retro community
- AtariAge offers homebrew cartridge production services
- Costs vary: ~$30-50 per cart for small runs
- The story content could go in a physical manual (classic Atari style)

**Status:** OPEN

---

## 8. Development Tools

**Question:** Which assembler and toolchain?

**Options:**
- A) **DASM** — the standard for Atari 2600 homebrew (used in technical-document.md)
- B) **ca65 (cc65 suite)** — more features, used by some modern homebrew devs
- C) **Batari Basic** — higher-level language that compiles to 2600 (limits control)

**Considerations:**
- DASM has the most 2600 community support and examples
- The technical document already specifies DASM
- Batari Basic would speed development but limit the TIA-level control needed for the puzzle mechanics

**Recommendation:** DASM, as specified in the technical document.

**Status:** OPEN
