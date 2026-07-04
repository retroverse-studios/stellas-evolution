# Stella's Evolution: Decision Log

> Decisions that need to be made before or during development.
> Mark each as DECIDED with the outcome and date when resolved.

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

**Status:** DECIDED (2026-07-04) — Option C. 6502 assembly with DASM, tested in the Stella emulator, validated on real hardware periodically.

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

**Status:** DECIDED (2026-07-04) — Option C (hybrid). The 4K game's five key narrative moments in the creative brief are its entire text budget (3-5 screens); narration grows with each installment. Option D (a story manual) can complement a physical release (see #7) but is not the primary vehicle.

---

## 3. Number of Characters per Game

**Question:** Stick with the original 2-2-3-5+ character progression, or adjust?

**Original plan (design-document.md):**
- "Stella Was Alone" (4K): 2 characters (Stella + Alex)
- "Stella Was Together" (8K): 3 characters (+ Marcus)
- "Stella's Journey" (16K): 3 characters with enhanced abilities
- "Stella Was Aware" (ARM): 5+ characters including original "echo" characters

**Alternative (from gameplay-mechanics addendum):**
- Consider a 4th character "Flicker" in the 16K version (circle, flickers between banks)
- Or introduce Flicker in the ARM version as an echo element

**Considerations:**
- Each character on the 2600 requires sprite multiplexing — more characters = more complex kernel
- 3 characters in 8K is already ambitious for sprite multiplexing
- The Flicker concept is clever but adds significant technical complexity
- Mitigating factor: Flicker is *drawn* every other frame by design, which is exactly what 2600 sprite multiplexing produces anyway — the "limitation" is the character

**Status:** DECIDED (2026-07-04) — Progression is now 2-3-4-5+. Flicker joins mid-game in "Stella's Journey" (16K) as the emotional core of that game's story (see creative-brief.md and #11). Flicker is playable if the 16K kernel budget allows a fourth multiplexed sprite; the fallback is a scripted companion that follows the active character — the narrative works either way. Validate kernel cost early in 16K prototyping.

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

## 6. The Thomas Was Alone Homage (ARM Game)

**Question:** How literal is the crossover with Thomas Was Alone?

**Options:**
- A) **Direct crossover** — Thomas and friends appear as named characters (needs Mike Bithell's blessing)
- B) **Spiritual crossover** — shapes that are clearly inspired by but not named Thomas
- C) **Meta-reference** — the characters discover they're an homage, but don't literally meet Thomas

**Considerations:**
- Option A requires IP permission from Mike Bithell / Bithell Games
- Option C is the safest and most interesting narratively
- Game mechanics are not copyrightable; character names, narration text, and titles are the protected expression
- The intent is to do right by the original, not merely to stay legal — permission will be sought regardless

**Status:** DECIDED (2026-07-04) — Option C is the baseline. The ARM game was retitled from "Stella Meets Thomas" to "Stella Was Aware", and the crossover was rewritten as wordless "echo" sequences with original, unnamed silhouettes (see creative-brief.md). Crediting the inspiration by name ("an homage to Mike Bithell's Thomas Was Alone") in the credits/README is fine and honest.

**Upgrade path:** Contact Bithell Games before the ARM game enters production. If they grant a blessing, the echoes can be upgraded to a literal named cameo (Option A) as a bonus — the design works either way. If they decline or don't respond, ship Option C unchanged; nothing depends on the answer.

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

**Status:** DECIDED (2026-07-04) — Option A, DASM. Revisit only if a concrete blocker emerges.

---

## 9. Bank-Switching as a Puzzle Mechanic

**Question:** Adopt the gameplay-mechanics addendum's proposal to make bank switching a core puzzle mechanic (parallel world states per ROM bank) in the 8K and 16K games, or keep bank switching as a purely technical detail?

**Options:**
- A) **Adopt fully** — parallel world states are the signature mechanic of games 2 and 3
- B) **Adopt partially** — a few showcase levels use it; most levels are conventional platforming
- C) **Reject** — keep the original design's conventional cooperative puzzles

**Considerations:**
- This is the single biggest open design question: it reshapes level design, ROM budget, and possibly the character-switching scheme for games 2 and 3
- It is the strongest idea in the addendum — the mechanic maps 1:1 to real hardware and teaches the player something true
- It adds real technical risk: level state must survive bank switches within 128 bytes of RAM
- It does not affect the 4K game, so development can start before this is decided

**Recommendation:** Design 3 bank-switching puzzles on paper (per the addendum's next steps) before committing. Decide after the 4K game ships.

**Status:** OPEN — decision needed before "Stella Was Together" (8K) design work begins

---

## 10. Repository Structure

**Question:** One repository per game, or a single monorepo?

**Options:**
- A) **Monorepo** — one repo, `docs/` for shared design docs, one subfolder per game under `games/`
- B) **Repo per game** — four repos plus a fifth for shared docs

**Considerations:**
- The design docs cover all four games and are shared by all of them
- Each game's engine builds on the previous one — code carries forward
- A solo project benefits from a single history and issue tracker
- If a game later needs its own repo (e.g., for a separate release community), `git subtree split` can extract a subfolder with history intact

**Status:** DECIDED (2026-07-04) — Option A. Monorepo with `docs/` and `games/01-stella-was-alone/` through `games/04-stella-was-aware/`.

---

## 11. Loss and Sacrifice in the Story Arc

**Question:** Does the series include real loss, or is the arc uninterrupted growth and harmony?

**Options:**
- A) **Real loss** — a character is sacrificed and the loss is permanent within that game
- B) **Fake-out loss** — a character appears lost but returns within the same game
- C) **No loss** — the arc stays purely about growth and connection

**Considerations:**
- Without stakes, the ARM game's transcendence is handed to the characters rather than earned
- "Thomas Was Alone" drew much of its power from melancholy and sacrifice
- Flicker is the natural candidate: a character who was always only half-there
- A children-friendly tone is preserved if the loss is quiet, chosen, and ultimately answered

**Status:** DECIDED (2026-07-04) — Option A, with a consolation: Flicker sacrifices itself at the end of "Stella's Journey" (16K) to hold the way open, and the loss stands for the whole of that game's ending. In "Stella Was Aware" (ARM), Flicker is found persisting in the space between frames, among the echoes — transformed, not restored. The theme: what is loved persists, but not unchanged. Revisit tone during playtesting if it lands too heavy.

---

## 12. 4K Level Count and Narration Placement

**Question:** How many levels in "Stella Was Alone", and does the narration live in ROM, the manual, or both?

**Considerations:**
- ~2.0KB of the 4KB ROM is free at v0.3 (7 levels)
- A level costs 69 bytes; the 48px text kernel + font + the five script lines costs ~650-850 bytes — both fit together
- Classic Atari games told the story in the manual; decision #2 chose hybrid narration
- The five creative-brief moments are one-liners — cheap in ROM, and they're the emotional skeleton

**Recommendation:** 10 levels + the five short in-ROM text screens (both fit), with the expanded prose version of the story in the manual for the physical release. Levels win any remaining space fight.

**Status:** OPEN

---

## 13. Replayability Variations (4K)

**Question:** Random/procedural levels, alternate goal placements, timed modes — how much replayability, and by what mechanism?

**Considerations:**
- Author preference: strong fixed storyline with small tweaks, not roguelike randomness
- Runtime procedural generation can't be solvability-checked in 4K — an unsolvable level is a shipped bug
- Pre-validated variety is safe: 2-3 authored goal positions per level, one picked at level start (costs ~2 bytes per extra spot + ~20 bytes of code)
- Timed mode is the classic 2600 variation; the console difficulty switches are free UI (no menu needed). Per-level timer beats a global one (a global timer compounds early mistakes)
- Timer display can be ambient: background color creeps toward red as time runs out — tension without a score kernel

**Recommendation:** Fixed levels and story. Replayability = (a) alternate pre-validated goal spots chosen at random per playthrough, (b) Difficulty A switch = per-level timer with color-creep. No runtime procgen in the 4K game; revisit a generated "bonus room" mode for the 8K game.

**Status:** OPEN

---

## 14. Level Solvability Tooling

**Question:** Should an external tool verify that levels (and any physics/goal variations) are actually completable?

**Considerations:**
- Levels are pure data (69-byte records) and jump arcs are closed-form — a small Python solver can build the reachability graph per character, including head-boost edges
- Every new variation axis (alternate goals, timers, tweaked physics) multiplies the combinations a human must hand-verify
- The same solver enables the generate-offline / validate / hand-curate / bake-as-data pipeline if generated levels are ever wanted — generation happens on a modern machine, never in ROM

**Recommendation:** Build `tools/check-levels.py`, run it from `make` so an unsolvable level breaks the build. Author levels by hand; use the solver as the safety net (and later, optionally, as the filter for generated candidates worth hand-curating).

**Status:** OPEN

---

## 15. Next-Game Teaser in the 4K Ending

**Question:** Should the 4K game end with a glimpse of what's coming in "Stella Was Together"?

**Options:**
- A) **Marcus cameo** — an inert blue square visible in the final level or on the win screen; he's the 8K game's headline
- B) **Strange-physics room** — one low-gravity level as a 16K foreshadow
- C) **Text only** — closing line hints at expansion ("The world shifted. Expanded.")

**Considerations:**
- The ball sprite is free; showing it blue needs a scanline color trick (kernel budget) or can simply appear on the win screen where budget is loose
- Option A matches the story: the 8K game opens with Marcus's arrival
- The creative brief's closing line already implies expansion — text costs nothing once the text kernel exists

**Recommendation:** A + C: closing narration line, and a small blue square quietly present on the win screen (upgrade to an in-level cameo if kernel budget allows).

**Status:** OPEN

---

## 16. Background Audio in the 4K Game

**Question:** Is background music worth the bytes, or is that the 8K game's territory?

**Considerations:**
- Channel 1 is unused (all effects run on channel 0)
- The gameplay-mechanics addendum already specifies the 4K approach: a single sustained drone (AUDC 1) whose pitch rises with progress — ~20-30 bytes total
- Real melodies fight TIA's detuned scale and eat ROM; the addendum assigns two-voice harmony to the 8K game

**Recommendation:** Implement the addendum's drone: low hum that rises in pitch each level — "the world waking up." Defer anything melodic to the 8K game.

**Status:** OPEN
