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

**Status:** DECIDED (2026-07-04) — Option A, per the author: develop the games sequentially but hold the official release so all four ship together as an anthology (the "evolution boxed set"). Mitigation for the long feedback gap: share each finished game's ROM with the AtariAge homebrew community as a beta — playtesting and buzz build across the years while the boxed set stays the event.

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

**Status:** DECIDED (2026-07-15) — **Option B (showcase levels), not the spine.** The
paper puzzles were built and solver-proven in ROM (floors T1/T2/T3 of the Game 2
prototype: locked-room, wall-here/path-there, forced mid-air switch — each proven
unsolvable without the toggle). The mechanic *works* and is tractable. But playtesting
showed the full-screen world-swap reads as "teleport to a different place," not "same
place rearranged" — cognitively heavy for 8K. It becomes the hardest *final* rung of
Game 2's spatial ladder (see #18), not the mechanic throughout. Its "two truths of one
place" idea may migrate to Game 4's meta-awareness theme. The lighter spatial verbs that
carry Game 2 — screen wrap and in-screen portals — need no bank switching at all, so 8K's
spare banks free up for characters, levels, and animation.

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

**Status:** DECIDED (2026-07-04) — implemented as: alternate goal spots; timed mode (SELECT on title or difficulty A); a run clock with the total shown on the epilogue; and **Quest 2** — after the ending, fire replays all ten levels with the *view* rendered upside-down (physics/controls unchanged, timer forced). Note: rotating level *geometry* was investigated and rejected — flipping geometry breaks jump-chain solvability, and 90°/270° can't be represented by the playfield hardware. Runtime procgen rejected for 4K; revisit for the 8K game.

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

## 17. Collision Model — Boxes Span Exactly What They Draw (4K, RC2/RC2.1)

**Question:** RC1 let Stella slide *through* the sides of platforms that were drawn as solid blocks — the collision boxes only blocked landings from above, not sideways movement. Fix it, leave it (lore: "the programmers got better across the series"), or make honest collision a Game 2 feature?

**Options:**
- A) **Leave RC1 as-is** — Stella's slide-through is a quirk; save the fix for Game 2
- B) **Fix in Game 1 now** — every drawn-solid platform truly blocks
- C) **Keep some one-way shelves** as a deliberate, thin-drawn mechanic

**Considerations:**
- Nothing has shipped publicly as final (decision #4 holds the boxed set); RC is a freeze label, not a release
- The manual's signature promise is "every level is mathematically verified to be completable" — thin if the solver doesn't model side-blocking
- Stella sliding under a barrier was silently *borrowing Alex's whole identity* ("he could slip beneath barriers that stopped her cold") — the bug erased his uniqueness
- The audit found all 18 "shelves" were drawn as full slabs; there were no genuine thin shelves to preserve

**Status:** DECIDED (2026-07-15) — **Option B, in two passes.** RC2: all 18 shelves made
truly solid; the solver taught side-blocking, one-way semantics, and boost runs, and it
caught a real solo-cheat on levels 7/9 (goal markers were tappable mid-jump). RC2.1: the
one carried-over exception (the "bottom-79 rule," which shaved a ledge's underside by 1 du
so Stella could still squeeze under) was removed after playtest — it read as clipping.
Now **every collision box spans exactly its drawn extent, in both orientations**; the
global scan finds zero body/slab overlaps. Levels 6 and 10 were minimally redesigned
where an under-ledge route was lost. RC2.1 is the public beta. One-way shelves remain an
*unspent* idea for Game 2. See `games/01-stella-was-alone/RC2-NOTES.md`.

---

## 18. Series Spatial-Scale Progression, and Game 2's Spatial Ladder

**Question:** Beyond hardware tier and character count, is there a third axis the series can grow along — and what is Game 2's core spatial mechanic?

**Considerations:**
- The series' founding image is Stella's world *expanding as the ROM expands* ("four kilobytes of existence… there had to be more")
- Game 2's world-swap (see #9) proved UX-heavy; playtesting pointed toward lighter, more legible spatial verbs
- Each game should introduce its spatial idea *fresh* — the value of a mechanic depends on its absence in the prior game

**Status:** DECIDED (2026-07-15) — a third progression axis: **perceived spatial scale grows
with the ROM.**
- **Game 1 (4K):** bounded, one static screen; the world can *flip* (upright → inverted,
  the Quest-2 second half) but never grows. Confinement is the point — it stays sealed, no
  backport of later spatial tricks.
- **Game 2 (8K):** still one screen, but its *space connects* — topology, not size. Its
  own internal ladder, in rising difficulty and conceptual weight:
  **wrap → portals → world-swap** (move through space → shortcut through space → change
  space itself). Wrap and portals are single-world and need no bank switch; world-swap
  (#9) is the hard final rung. **Wrap is the always-on baseline (decided 2026-07-15):**
  the screen edges connect on *every* floor — the world is a cylinder — and portals and
  world-swap layer on top of that ever-present wrap. Verbs accrete; they are not swapped
  in and out. (The prototype's isolated wrap/portal/world-swap floors were for testing
  each verb cleanly; the shipped game turns wrap on everywhere.) A hard boundary, where a
  puzzle needs one, is a wall placed just inside the edge — the world still wraps, that
  spot is blocked.
- **Game 3 (16K):** the world *extends* — scrolling, connected rooms, a journey ("Stella's
  Journey"). This is where breadth, not just depth, arrives.
- **Game 4 (ARM):** transcendent — the screen becomes a window onto something larger.

All three prototype verbs are built and solver-proven load-bearing (wrap floor W1, portal
floor P1, world-swap floors T1–T3). See `games/02-stella-was-together/DESIGN-KICKOFF.md`.

---

## 19. Three-Character Sprite Multiplexing (8K Kernel)

**Question:** The 2600 has two player sprites; Game 2 has three characters (Stella, Alex,
Marcus). How are three drawn on two sprites?

**Options:**
- A) **Full sort/multiplex** every character across both sprites each frame
- B) **P0 dedicated, P1 time-shared** — one character owns P0; the other two share P1
- C) **Flicker all three** at 30 Hz always

**Considerations:**
- A stable 262-line NTSC frame matters more than cleverness; the kernel is cycle-tight
- The gameplay-mechanics addendum embraces flicker-as-multiplexing rather than hiding it — level design rewards vertical separation
- Flicker foreshadows Game 3's Flicker character (the artifact made canonical)

**Status:** DECIDED (2026-07-15) — **Option B.** Stella owns P0; Alex and Marcus time-share
P1. When their scanlines don't overlap, the kernel repositions P1 mid-frame (an inline
RESP1/HMOVE hop) and all three draw solid at 60 Hz; when they overlap, P1 alternates them
at 30 Hz — flicker *only* where physically justified. Single failure mode (no room to hop)
degrades gracefully into the embraced flicker.

---

## 20. Mirrored Playfield Kept; Asymmetry From Actors

**Question:** The mirrored playfield reflects the left half onto the right, which doubles
walls and portals and confused early Game 2 playtests. Switch to a true asymmetric
playfield?

**Considerations:**
- True asymmetric PF needs per-scanline register rewrites at exact beam cycles; measured as
  not fitting the cycle-tuned kernel that Game 1 and the Game 2 multiplex depend on
- Sprites and markers are positioned *freely* — they are not mirrored
- Asymmetry the player reads (characters, per-color goal markers, portals at different
  heights/sides) comes from *where things are placed*, not from the background

**Status:** DECIDED (2026-07-15) — **Keep the mirrored playfield.** Get asymmetry from actor
and marker placement, and lay out walls/portals so the reflection *completes* a feature
rather than doubling it (a full-width shelf, or a wall on the mirror axis, reads as one
clean object). Zero extra kernel cost. Revisit only if a specific puzzle genuinely needs a
lopsided *wall* and the kernel has gained room.

---

## 21. Marcus's Identity and Discoverable Feature

**Question:** Marcus (blue square, Game 2's new character) must be mechanically distinct
from Stella (tall, high jump) and Alex (flat, fast, fits under overhangs). What is his
unique feature, and how does the player discover it without being told?

**Considerations:**
- The design document assigns him "balanced… perfect size for medium gaps"
- "Balanced" is not, by itself, a *feature* a player can feel
- Stella's tall body needs headroom to jump; under a low ceiling she bonks and effectively
  cannot jump at all
- Game 1's teaching style is failure-driven and wordless

**Status:** DECIDED (2026-07-15) — Marcus's feature is **fitting where the others cannot**:
a true visual square (12 scanlines — a TIA pixel is wider than a scanline), a walk speed
between Alex's and Stella's, and — the key — a medium jump that works under a *low ceiling*
where Stella's big arc bonks and Alex's fizzles short. Discovered by a level with a medium
gap under a low ceiling: try Stella (bonks), try Alex (falls short), try Marcus (fits
exactly). One failure each, insight owned forever. He is Game 1's silent blue epilogue
figure, now awake (see the wake-up opening in DESIGN-KICKOFF.md).

---

## 22. Presentation / UI Sophistication Grows Per Generation

**Question:** When does the series introduce a proper title screen and an on-screen options
menu (sound on/off, mode select, etc.)? Could Game 1 have a simple menu (Play / Sound /
Red Sky) in its ~80 spare bytes?

**Options:**
- A) **On-screen menu from Game 1** — a minimal Title/Play/Sound/Mode menu
- B) **Console-switch options only in Game 1**, on-screen menus arrive in later games
- C) **No options anywhere** — pure switch-driven throughout

**Considerations:**
- Authentic 4K-era games did *not* have on-screen option menus; options were the console
  hardware switches (SELECT cycles the game variation; the difficulty switches toggle modes)
- Game 1 already does this correctly and period-accurately: SELECT chooses story vs. endless
  (rainbow vs. ember sky), the left difficulty switch adds the level timer, RESET restarts
- ~80 free bytes is very tight for menu state + cursor + input + extra text strings
- On-screen menus historically arrived with larger cartridges — so menu sophistication is a
  natural fourth thing that can grow with the ROM, alongside scale, characters, and audio

**Status:** DECIDED (2026-07-15) — **Option B; UI sophistication is a per-generation axis.**
Game 1 stays switch-driven (authentic, already implemented, and an on-screen menu would
break the 4K aesthetic the series prides itself on). If a *sound on/off* toggle is wanted in
Game 1, the authentic and cheap route is a free console switch (e.g. the B/W–Color switch or
the right difficulty switch), not a menu. Progression: **G1** console switches → **G2** a
proper title screen, still mostly switch-driven → **G3** a real navigable on-screen menu →
**G4** full settings. The menu grows up as the hardware does.

## 23. The Eye Motif — Awareness Made Visible Across the Generations

**Question:** The Game 2 characters gained eyes (two dark pixels — bits turned off in
the sprite) that Game 1's solid blocks never had. Is this just presentation, or a
thematic thread worth deliberately carrying — and how much do we spell it out?

**Considerations:**
- The series' founding thesis (creative-brief.md): "As the hardware capabilities expand,
  so does the characters' awareness of their world." The eyes are that sentence, drawn.
- The eyes were added intentionally (facing + blink, for personality); the *artful* move is
  to let the fiction present them as an awakening rather than a feature — the same
  limitation-wearing-the-mask-of-emergence move the series makes everywhere (Space
  Invaders' lockstep march; Flicker's blink)
- It dovetails with the already-planned Marcus wake-up opening, where his eyes *appearing*
  is the moment he wakes

**Status:** DECIDED (2026-07-16) — **Carry it, subtly.** The eye is the visible index of the
series' awareness arc, and detail *grows* with the ROM (more bits = more awareness), never
shrinks:
- **G1 (4K):** solid blocks, no eyes — blind, unaware, pure existence ("she didn't know why").
- **G2 (8K):** eyes open — they can *see each other*, which is *why* connection is this
  game's theme. Sight = the dawn of awareness. Marcus's eyes appearing = waking.
- **G3 (16K):** the eyes do more (track, react, emote); Flicker exists at the edge of
  visibility, half-aware it is half-there.
- **G4 (ARM):** the eyes look *out* at the player — meta-awareness of the medium itself.

Document it only through the *manuals* — one quiet line each, so a reader of all four joins
the dots without being lectured (Game 2's could be simply "They can see each other now").
Never state the mechanism (that the eyes are unlit sprite bits); let it read as awakening.
