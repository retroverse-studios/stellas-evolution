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

**AMENDMENT (2026-08-13) — how Act 3's swap is actually delivered, and the
grammar that makes it safe.** Two things the prototype never had to face:

- **Delivery: pointer swap, not bank switch.** The workbench moved world B's
  planes through a 24-byte RAM copy (`PFRam`); the real game's RAM is full
  (the home lamps own the old per-state-union bytes). So a dual floor's
  record carries world B's interior planes and boxes after the world-A
  record, and the swap repoints `PF1Ptr/PF2Ptr/PlatPtr` and reverses the sky
  gradient — the which-world tell runs on the luma channel (ramp backwards),
  not a warm/cool hue flip, per #27. The mapper chip never switches during
  play at all. What the player learns — "this place has two truths" — is
  unchanged; the hardware poetry was never visible to them. (Bank 1 did not
  go to waste: it is the ANNEX — title and narration live there, which is
  what paid for Act 3's bank-0 bytes.)
- **The grammar: only ONE-WAY boxes may differ between worlds, and swaps are
  grounded-only and rift-gated.** The workbench was Stella-only; with three
  characters, swapping a solid wall in leaves any friend standing in its
  footprint embedded in it — a silent rules-violation the series' teaching
  style can't announce. One-way ledges never side-block, so the worst a swap
  can do is drop you (legal). The rift gate makes every swap moment a finite
  standing state the solver can prove clear in both worlds. The workbench's
  mid-air switch (T3) is retired by the grounded rule — the solver only
  models standing states, and an unprovable verb is a bug farm.
  `check_levels.py` audits both rules on every build, plus the rift art
  mask, plus the negative proofs (no-swap, and for the interleave floors,
  each-world-alone).

Also settled by Act 3's floors: homes are fixed across worlds (the truths
differ in what you can STAND on, never in where home is), and place-and-hold
(#26) therefore forces every floor's homes to coexist in ONE world — the
"her truth / his truth" split ending is impossible by construction.

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
- A level costs 73 bytes; the 48px text kernel + font + the five script lines costs ~650-850 bytes — both fit together
- Classic Atari games told the story in the manual; decision #2 chose hybrid narration
- The five creative-brief moments are one-liners — cheap in ROM, and they're the emotional skeleton

**Recommendation:** 10 levels + the five short in-ROM text screens (both fit), with the expanded prose version of the story in the manual for the physical release. Levels win any remaining space fight.

**Status:** DECIDED (2026-07-29, recorded retroactively — shipped since v0.4) — the
recommendation, in full and unchanged. `NUM_LEVELS = 10`, and the creative brief's five
moments are the entire in-ROM script (`tools/gentext.py` SCREENS): "STELLA WAS ALONE." /
"THERE HAD TO BE MORE" / "AND THEN THERE WERE TWO." / "TOGETHER, THOUGH..." before levels
1, 2, 3 and 6, and "THE WORLD SHIFTED. CHANGED." at the ending. `LvlStory` maps levels to
screens; `$FF` means "no narration, straight into play". Both fit with ~110 bytes to
spare. The expanded prose lives in `MANUAL.md` for the physical release, per #2's hybrid.

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
- Levels are pure data (73-byte records) and jump arcs are closed-form — a small Python solver can build the reachability graph per character, including head-boost edges
- Every new variation axis (alternate goals, timers, tweaked physics) multiplies the combinations a human must hand-verify
- The same solver enables the generate-offline / validate / hand-curate / bake-as-data pipeline if generated levels are ever wanted — generation happens on a modern machine, never in ROM

**Recommendation:** Build `tools/check-levels.py`, run it from `make` so an unsolvable level breaks the build. Author levels by hand; use the solver as the safety net (and later, optionally, as the filter for generated candidates worth hand-curating).

**Status:** DECIDED (2026-07-29, recorded retroactively — shipped since v0.4) — the
recommendation, and it has more than paid for itself. `tools/check_levels.py` exists in
**both** games, re-implements the ROM's exact physics tables, and runs from `make` as its
own always-run target (not a step inside the ROM recipe — that shape silently skipped the
proof whenever the ROM happened to be up to date; fixed in both Makefiles 2026-07-29).
Levels are authored by hand; the solver is the net. Real bugs it caught, none of which a
human had noticed:
- Alex could not jump onto Stella's head (she is 9 du tall, his jump rose 8.2) — G1 v0.4.
- A solo-cheat on G1 levels 7 and 9: perch goals were tappable mid-air, so the boost
  levels could be beaten without the boost (#17, RC2).
- Marcus's Floor 1 regression when his jump grew to 16 du for Floor 2's sill: his overshoot
  landed exactly on the old 60 ledge and his own home became unreachable (G2, Act 1).
It has since grown negative proofs too — G2 Floor 3 is asserted UNSOLVABLE with wrap off,
so a floor's *teaching* is proven load-bearing, not just its solution proven to exist.
Generated levels remain unbuilt and unneeded; the generate/validate/curate pipeline stays
available if a "bonus room" mode is ever wanted (#13).

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

**Status:** DECIDED (2026-07-29, recorded retroactively — shipped since v0.4) — **A + C, and
it turned out to be load-bearing.** The closing screen carries "THE WORLD SHIFTED.
CHANGED." (screen 4), and `EnterWin` puts a small blue square below the run time — missile
1, 8px, breathing on a slow four-shade cycle (`SqCol`), unexplained and unnamed. The
in-level cameo was not needed and would have cost kernel budget for less mystery.

Not merely a teaser in hindsight: that square **is** Marcus, and Game 2's opening
(`STATE_WAKE`) is a deliberate recreation of this exact screen — black void, the small blue
square, alone — which the new world then assembles itself around, his eyes appearing as the
moment he wakes (see #21 and #23). The two games are joined at this image. Neither the
epilogue square nor the wake-up opening may be changed without the other.

---

## 16. Background Audio in the 4K Game

**Question:** Is background music worth the bytes, or is that the 8K game's territory?

**Considerations:**
- Channel 1 is unused (all effects run on channel 0)
- The gameplay-mechanics addendum already specifies the 4K approach: a single sustained drone (AUDC 1) whose pitch rises with progress — ~20-30 bytes total
- Real melodies fight TIA's detuned scale and eat ROM; the addendum assigns two-voice harmony to the 8K game

**Recommendation:** Implement the addendum's drone: low hum that rises in pitch each level — "the world waking up." Defer anything melodic to the 8K game.

**Status:** DECIDED (2026-07-29, recorded retroactively — shipped since v0.6) — the drone,
and it grew slightly past the recommendation because the bytes were there. `PlayExtras`
runs channel 1 (AUDC1 = 1) as a **four-note rising figure** (`ArpOff` = 8,5,3,0) over a base
pitch of `23 - 2*Level` — so the figure transposes up every level, and the world audibly
wakes across the run rather than only humming higher. Under time pressure (`TimerSec` < 16)
the figure doubles its tempo, which is the timed mode's tension carried in sound rather than
in a score display, matching #13's ambient-feedback principle. Effects stay on channel 0
(jump / land / goal fanfare) — the two channels never fight.

Still true: nothing melodic in the 4K game, and two-voice harmony remains the 8K game's
territory. **Game 2 currently has no background audio at all** — its two-voice score is
outstanding work, tracked in that game's README.

**AMENDMENT (2026-11-25) — a tune in the 4K game after all, on one voice.** The author
overturned "nothing melodic in the 4K game" when the two options were put side by side:
a one-channel tune in Game 1 costs Game 2 nothing that two voices do not still dwarf
(one voice becomes two; a hum becomes harmony), whereas the other candidate for Game 1's
first impression — the rainbow mark — would have spent something that belongs to Game 4.
What survives of the original decision: **one voice only** (channel 0 stays the
effects), and nothing that needs a second channel to be heard.

Three drafts were rendered as WAV previews and the author chose **the lament — at
the quicker of the two speeds it was heard at**, having been drafted at half that.
(`src/tune.inc`: TEMPO 4, STRIKE 2.) The two losing drafts and the old drone,
kept for A/B until the choice was made, were deleted afterwards; they are in the
history of commit `c3aa78a`. The tune has not been heard in Stella or on hardware
yet. Three things were learned building it and are now rules:

- **A pure TIA tone cannot transpose in tune.** The drone's "a little higher each
  level" is gone; it cannot be done with a melody, so the tune is the same on every
  level and the *tempo* carries the urgency instead.
- **A 32-step table cannot be indexed from the 8-bit frame counter.** Shifted right
  five times it only counts to seven, which was all the four-note figure needed. The
  tune has its own step counter (`TuneStep`, one byte).
- **`HURRY` is a decision, not a given.** With the tune already quick, doubling it
  again under pressure is a choice the author may want to hear before it ships; one
  constant in `tune.inc` turns it off.

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

**AMENDMENT (2026-07-29) — pair whoever SEPARATES, not whoever is inactive.**
P1 can carry two characters solid, because it hops mid-frame. So the question was never
"which two are inactive" but "which two separate": pair those on P1 and give the odd one
out P0 to itself, and nothing flickers. Only when NO pair separates — all three at one
height, which on a flat floor is every pair — is flicker forced, and then P0 goes to the
active character exactly as this decision always said. Pairs are tried preferring the one
NOT containing the active character, so the character you control keeps P0 to itself
whenever possible (a hop tenant is solid and would not flicker either, but it can clip a
du at the hop, and the one you are steering should never wear that). No kernel change —
the hop machinery, the cycle-counted repo lines and the boundary guards are untouched;
only the choice of who sits in which slot, made in vblank.

The other half is level design, which this decision already anticipated ("level design
rewards vertical separation") but which Floor 1 was violating: three characters standing
on one floor have their feet at the same du, so every pair overlapped and the worst case
was permanent, on the first floor of the game. Marcus now wakes PERCHED on the totem's
first step. Together the two changes took Floor 1 from flicker in all three states to
flicker in none.

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

## 24. World-Swap Verbs Removed From the Real-Game Skeleton (Re-attach in Act 3)

**Question:** When the Game 2 workbench was cut down to the real-game skeleton
(title + in-order floor flow + between-floor narration, prototype floors removed),
should the world-swap / portal *verbs* (`DoSwitch`/`DoTeleport` and their data)
stay in the code as dead routines, or be removed with the prototype floors?

**Considerations:**
- 128 bytes of RAM total. The narration text kernel needs its RAM state; world-swap
  needs a 24-byte `PFRam` playfield buffer. Both resident at once did not fit.
- A clean skeleton should not carry dead routines pointed at deleted data.
- World-swap is Act 3's mechanic — not needed until then.
- The *capability* does not depend on those specific routines surviving: the F8
  two-bank architecture (byte-identical trampoline stubs + a bank-1 entry/worker)
  is intact, the kernel already draws the playfield from pointers, and the full
  world-swap implementation is preserved in the `game2-workbench` tag.

**Status:** DECIDED (2026-07-16) — **Remove the verbs with the prototype floors;
re-attach world-swap in Act 3.** The skeleton keeps the F8 layout honest (8192
bytes, stubs + bank-1 targets) so Act 3 fills in bank 1 and reconnects the verbs to
the floor framework. **The RAM tension is straightforward to resolve, not a blocker:**
narration (STATE_STORY) and world-swap gameplay (STATE_PLAY) never run in the same
frame, so their RAM can *overlay* the same bytes (a per-state union, a standard 2600
technique) rather than coexist. Not a loss — a deferral with a known fix. See the
`game2-workbench` tag and `games/02-stella-was-together/README.md` for the version map.

## 25. Dual Gravity — a Level Variation, Not an Act; and Act Sizes

**Question:** DESIGN-KICKOFF floated dual gravity (a character walking the
ceilings) first as a candidate Act 2 mechanic, then as "#9's insurance policy."
Decision #18's spatial ladder (wrap → portal → world-swap) left it without a rung,
and it silently vanished from the plan. What is its actual fate? And with ~5KB of
the 8K still free after Act 1, is the 2-3-floors-per-act shape a ceiling?

**Considerations:**
- Not a new *mechanic* so much as a new *arrangement*: Game 1's Quest 2 already
  inverted the whole view; per-character or per-region gravity is that idea made
  local — e.g. a screen split into regions, one side normal, the other
  anti-gravity, so a character on the far side walks the ceiling of the SAME
  platforms everyone else stands on. Every floor is somebody's ceiling; no new
  level data.
- Estimated cost (from the original pitch): ~150-300 bytes — a per-character
  gravity sign, mirrored landing/bonk logic, ceiling home spots, eyes drawn on
  the character's lower edge. The solver must learn a gravity sign per character.
- It composes with the decided ladder rather than competing with it: a portal
  that flips gravity, or a world-swap where world B is world A upside-down
  ("A-normal / B-INVERTED"), were both already sketched in the kickoff.
- Acts: the 3/3/3/1 shape (intro/develop/twist per teaching act) is a floor
  *minimum*, not a budget. Bank 0 has ~0.9KB free with Act 1 complete; bank 1
  has ~4KB reserved for Act 3's world data with room to spare. A floor costs
  ~100-160 bytes (record + homes + colour bands + narration).

**Status:** DECIDED (2026-07-18) — **Kept, as a level variation inside the acts,
not an act of its own.** Acts 2 and 3 may use anti-gravity *regions or characters*
as floor-level variety (the way Game 1 used inversion for Quest 2), subject to the
usual gate: prototype one floor, teach it wordlessly, and the solver must prove it
load-bearing before more floors adopt it. The wrap → portal → world-swap ladder
(#18) is unchanged. Act floor counts may grow beyond 3 where the ROM allows —
pacing (Thomas Was Alone brevity, no filler) is the constraint, not the byte
budget.

## 26. One Goal Mechanic for the Series: Place and Hold

**Question:** Game 1 shipped touch-and-exit goals (a character reaching its marker
vanishes with it; exit-order locks force boost sequencing), while Game 2's totem
floors emerged as place-and-hold (the floor completes when every character stands
on its own home at once; nobody leaves play). Which is the series' goal mechanic?

**Considerations:**
- Place-and-hold keeps every piece on the board: if the order was wrong, the
  player just re-solves — no lock, no denial buzz, no dead character to mourn
  mid-level. Puzzle order *emerges* (the booster naturally finishes last because
  the boosted friend is standing on the result).
- It is the thematically correct ending image for this series: every level ends
  with the characters together on screen, not with them winking out one by one.
- It composes with the home-lamp feedback (#27): steady lamp = held, blinking =
  still to do.
- Backporting to Game 1 simplifies its engine: the exit-order machinery, the
  can't-switch-to-exited gate and the denial buzz all delete; `GoalDone` becomes
  a per-frame "standing on it now" flag. Record byte +73 (the old lock) is legacy.
- All ten Game 1 levels plus both goal variants re-prove under the new rule
  (solver: a reachable STANDING state on one's own goal, at least one character
  solo). Level semantics survive; the boost levels read better, not worse.

**Status:** DECIDED (2026-07-20) — **Place and hold, series-wide.** Game 2 already
plays this way; Game 1 backported (v1.0-rc3-dev, supersedes rc2.1 — hardware
validation is owed again). The manual's YOUR GOAL section rewritten to match.

## 27. Colour Accessibility: Luma Order, Home Lamps, Shape Echo

**Question:** The characters and their colour-matched homes were distinguished by
hue alone (Stella red, Alex green, Marcus blue) at near-equal brightness — the
worst case for red/green colour vision, which the project's own author has. What
is the series' colour-accessibility standard?

**Considerations:**
- The TIA colour byte is hue high-nibble + luma low-nibble: brightness is a free
  redundant channel that survives every kind of colour vision.
- Temporal coding (blinking) and shape coding are fully colour-independent.
- Game 1's locked-goal blink already established "blinking marker = not ready";
  the lamps generalize that language instead of inventing a new one.

**Status:** DECIDED (2026-07-20; palette corrected and unified 2026-07-29; the
world/actor split added 2026-07-29) — a governing rule, then three layers:

- **COLOUR MEANS AGENCY; the world is greyscale.** (2026-07-29, author's proposal.)
  Hue 0 is the neutral ramp, and the world lives there — sky, platforms, the mark.
  Every hue on screen therefore belongs to something with a will: the characters,
  and their home lamps (a home is a character's *intent*, which is why the lamps
  were already in character colours). This splits two jobs onto two channels, and
  **neither one asks the player to tell red from green** — the failure mode this
  whole decision exists for:
  - *Colour* answers **"is this an actor?"** — anything not grey. Red/green colour
    vision still separates coloured from neutral even when it cannot name the hue.
  - *Luma order* answers **"which actor?"** (below).

  **Luma budget.** The characters own six of the TIA's eight levels (2/4, 6/8,
  C/E), leaving 0 and A for the world, so the world takes exactly those: sky ramps
  0 → 8, platforms sit at A. Every character then differs in brightness from the
  ground it stands on, whoever it is. Verified in Game 2; the repaint also caught
  a live collision, tan platforms at luma C against Alex's idle luma C.
  Residual, and accepted: a *gradient* sky must cross someone, so Marcus fades in
  the mid sky and Stella in the low sky. Those are reduced contrast, not
  invisibility — hue still separates, because the sky is neutral and they are not.
  Any new sky palette must be checked band-by-band against the character lumas.

  **The arc.** This is #23's awareness thread made global rather than a fifth
  progression axis. G1-G2 the world is inert and grey; **G3** the corruption gets
  colour — something else is alive, and it is wrong, announcing itself by breaking
  the world's own rule; **G4** the world itself gains colour, because it wakes up.
  The game named *Stella Was Aware* is where the world becomes aware.

  Consequence for per-act sky palettes (Game 2 README, "altitude as the progress
  bar"): the sky **brightens as you climb**. Altitude on the luma channel is both
  more literal than a hue shift and the only version of it the author can see.

- **Luma order:** in any state, Alex is the brightest character on screen, Stella
  mid, Marcus darkest. **One palette, identical bytes in both games** — a
  character keeps its colour across the boxed set (2026-07-29; author's call:
  "I would prefer the colours to be the same across the games"). Any future
  per-game colour progression must be a *deliberate* mechanic or arc, not drift,
  and is doubted anyway on the grounds that it is hard to perceive across games
  played apart.

  | | dim (idle) | bright (active) |
  |---|---|---|
  | Marcus (hue $8) | `$82` | `$84` |
  | Stella (hue $3) | `$36` | `$38` |
  | Alex   (hue $C) | `$CC` | `$CE` |

  Stella is hue $3 — the red `design-document.md` specifies as `$30`. Game 2 had
  drifted to hue $4; Game 1 was right.

  **The active boost is +2, and +2 is the hardware maximum.** The ordering must
  hold for the *mix that reaches the screen* (one bright character plus the
  others dim), not merely within the bright table and the dim table separately.
  Three characters need dim tiers ≥ 4 luma apart, and the TIA gives 8 usable
  steps, so any boost above +2 lifts the active character onto its neighbour's
  luma. Exhaustive search over all assignments confirms no valid scheme exists
  at +4 or more, and that no scheme keeps every gap ≥ 4 (the tightest pair is
  Marcus-active Marcus/Stella, 2 apart).

  *The bug this replaced:* the original tables ($4A/$CE/$86 bright over
  $46/$CA/$82 dim, active +4) were ordered within each table but collided on
  screen. With Stella controlled she and Alex were **both luma A**; with Marcus
  controlled he and Stella were **both luma 6**. Two of the three states were
  colour-blind-unsafe — precisely the failure this decision exists to prevent —
  and it survived because the tables were only ever read down their columns.
  Verify the mixes, not the columns.

  "Which character am I controlling" therefore rests on the redundant channels
  rather than on luma: the active character owns the never-flickering P0 slot,
  wears the wide-awake eyes, and its home lamp blinks fast (Game 1: it is simply
  the one that answers the stick, plus the fast lamp).
- **Home lamps:** a vacant home blinks (slow), the CONTROLLED character's vacant
  home blinks FAST, a held home shows steady. Blink = to-do list; fast = "this
  one is yours"; steady = done. Game 2 builds a per-band COLUPF table in RAM each
  frame (overlaying the text kernel's TPtr, a #24-style per-state union); Game 1
  drives its goal missiles' visibility the same way.
- **Shape echo:** where home markers are geometry, their width matches their
  owner's body — Game 2 Floor 1's middle (Alex) ledge is double-wide. Game 1's
  missiles are capped at 8px by hardware; luma + lamps carry it there.

**AMENDMENT (2026-08-13) — the lamp's honesty rule.** A home lamp paints its
whole playfield BAND, so a home must BE its band's content: Act 2's floors
keep to the rule that the tinted feature and the home zone coincide — "the
whole shelf" (F4's Alex, F5/F6's Marcus), "either mirrored twin" (F4's Marcus
ledges, F6's Alex ledges — one zone spanning both, the Floor-3 pattern), or
"both guard lintels" (F5's Alex) — and never a *slice* of a tinted feature,
which would promise more home than the test grants. Bands are per-floor
distinct per character (three homes, three bands); this ruled out
ground-level homes outright, because band 11's content is the whole floor.

## 28. Title & Screen Design Language Across the Series

**Question:** Game 1's title (big rainbow STELLA on black) reads beautifully;
Game 2's original title set "STELLA WAS TOGETHER" in the small 3x5 narration
font and was hard to read. What is the series' title system — and what single
visual element ties all four games together as their presentation grows?

**Considerations:**
- Each game's identity is one word: ALONE, TOGETHER, JOURNEY, AWARE.
- The big 7-row STELLA logo is already the series' strongest mark; the 3x5
  pipeline font is for sentences, not signage.
- Per #22, UI sophistication grows per generation (G1-G2 switch-driven, G3 a
  real navigable menu, G4 full settings) — the title screen should grow the
  same way without losing the mark.
- The narration screens' voice — small white text on black — is the one thing
  that should NOT grow: the world gains fidelity, the narrator does not age.

**Status:** DECIDED (2026-07-20) —
- **The mark:** every title = the big STELLA logo, with the game's one word set
  small beneath. The BACKDROP evolves with the ROM: G1 a black void (4K,
  existence), G2 a grey dusk gradient (implemented: logo ported from G1,
  TOGETHER in small white beneath), G3 may add breadth/motion, G4 whatever the
  ARM earns.
- **The mark's colour — revised 2026-07-29.** It was the Atari rainbow. Under
  #27's colour-means-agency rule a rainbow mark is colour used as decoration,
  which is the exact habit the rule breaks — and spending the rainbow on Game 1
  wastes it. So the mark is lit in the neutral ramp (`$08,$0A,$0C,$0E,$0C,$0A,
  $08` — the rainbow's per-row banding transposed into the channel every player
  can see) for **Games 1-3**, and **BLOOMS into the full Atari rainbow in Game
  4**, when the world itself gains colour. This supersedes "the mark itself never
  changes": it is stronger for changing exactly once, at the end. A thing that
  never changes is a rule; a thing that changes once is an event — and this one
  lands on the game about becoming aware.
- **The constant thread:** narration/act screens stay small white-on-black
  text in ALL four games — the series' connective tissue.
- **Menus:** #22 unchanged. G1's switch-driven title is the homage and stays.
- **Done (2026-07-29):** G1's own small "ALONE" subtitle now ships. The byte
  diet that paid for it: the touch-and-exit era's exit-order lock byte was
  still sitting in all ten level records, dead since #26 (+10 bytes), and the
  title's subtitle feed loops its paired scanlines instead of open-coding
  them (the story kernel open-codes both lines only because it does per-line
  row bookkeeping between them; the title has none). G1's title is now the
  same five-zone shape as G2's — 40 + 112 (mark) + 8 + 12 (word) + 20 = 192 —
  so the mark sits in the same place on screen in both games, over a black
  void in G1 and a dusk sky in G2.
- **Consequence: Game 1 is nearly full** — 27 bytes free after the band-12 fix
  gave some back. **Amended 2026-07-30:** the original wording, "closed to new
  features", was too blunt and the author pushed back correctly. A NEW FEATURE
  and a CONSISTENCY FIX are not the same commitment:
  - A *new feature* adds something the series never promised. Game 1 is closed
    to those, and #22's whole argument is that its presentation is supposed to
    be the constrained one.
  - A *consistency or expectation fix* pays down a promise the series has
    ALREADY made — one mechanic (#26), one palette and one feedback language
    (#27), one mark (#28). Those are never out of scope. If one does not fit,
    the answer is a byte diet, not a dropped fix; the alternative is a boxed
    set whose four games quietly disagree with each other, which costs more
    than the bytes do. Every diet so far has been paid for by deleting
    something already dead (the exit-order lock, the pre-loop prefetch).

## 29. The Fourth Character — Flicker's Blink as Sprite Budget, and Phase-by-Contact

**Question:** Flicker (circle, joins mid-way through "Stella's Journey") is defined
by being visible only every other frame. How is a FOURTH character drawn on the
TIA's two players without wrecking decision #19's guarantee that the character you
control never flickers — and what, mechanically, is Flicker's gift?

**Considerations:**
- #19's arrangement (P0 = the active character, solid; P1 time-shares the two
  inactive ones) does not extend to four: P1 would carry three tenants at 20 Hz,
  well below fusion, and read as strobing rather than as flicker.
- The series' signature move is to let a hardware limitation wear the mask of
  emergence — Space Invaders' lockstep march, the eyes as awakening (#23). Flicker
  is the purest available case: the 2600's real multiplexing artifact, made a
  person. Drawing its blink as a deliberate *effect* would waste that.
- The brief gives Flicker passage through *"unstable" barriers* specifically, not
  through all matter — level-design control for free, and it dovetails with Game
  3's corruption zones, which are already the series' first antagonist force.
- Standing on a friend already means *lift me* (Game 1 levels 6-7, Game 2 Floor 1).
  The series escalates by giving an old verb a new meaning, not by adding verbs.

**Status:** DECIDED (2026-07-29, to be validated when Game 3 prototypes) —

- **The register arrangement — Flicker's fragility PAYS FOR the fourth sprite.**
  - *Flicker inactive:* P0 = the active character, solid (#19 holds unchanged).
    P1 three-way shares the rest, so Flicker — last in the rotation — is simply
    the blinkiest thing on screen. Its nature is arithmetic, not a drawn effect.
  - *Flicker active:* P0 = Flicker, drawn every other frame BECAUSE THAT IS WHAT
    IT IS. The alternate frames fall free, and go to an inactive character.
  This is an explicit, documented **exception** to #19 rather than a violation:
  the rule exists so the player can track what they control, and being hard to
  hold onto is precisely what controlling Flicker should feel like. It is also
  opt-in — you chose to pick Flicker up.

- **The mechanic — phase by contact.** Flicker passes through unstable barriers.
  A character STANDING ON Flicker phases too: both blink, both pass. The lift
  becomes a loan of identity, which is the whole series' thesis performed in one
  input the player already knows.
  - This needs **carry physics** (the rider moves with the base), which the engine
    has never had — stacking is currently one-way, the stander merely treats a
    head as a surface. Game 3's 16K and Game 4's ARM have the room; the solver
    must learn it too. Accepted as real work, not a footnote.
  - Contact IS the limit. No phased state persists after stepping off, so the
    power cannot leak into puzzles it was not invited to.

- **Why this mechanic and not another:** #11 has Flicker sacrifice itself *to hold
  the way open*. If Flicker's gift is phasing through solid matter, then holding a
  way open **is** staying phased inside a wall, forever. The mechanic and the death
  resolve into a single image the player will have spent a whole game learning to
  read. Nothing has to be written to explain it.

**AMENDMENT (2026-07-29) — carry is FLICKER'S, not the world's; stacks fuse.**

The original entry said carry physics, unqualified. That was wrong, and the author
caught it: *"if not in Game 1, or Game 2, then why in Game 3?"*

The distinction that matters is **adding an ability versus contradicting a learned
rule.** Every previous addition was additive — Alex slips under, Marcus fits, wrap and
portals arrive — and nothing the player already knew became false. General carry is not
like that. Since Game 1 level 6 the player has learned *stand on a friend, and if the
friend walks away, you fall*. Turning that into "you ride along" in Game 3 does not add
knowledge, it **invalidates** knowledge, silently, with no channel to announce it. The
series teaches wordlessly, so a silent reversal is not a teaching problem to solve — it
is a design error to remove.

So:

- **Only Flicker carries.** Standing on Stella, Alex or Marcus behaves exactly as it
  always has: the platform walks out from under you and you drop. Standing on **Flicker**
  carries you, because Flicker is half-present — you sink into it rather than resting on
  it. Nothing the player knows is contradicted. Carry stops being a physics change and
  becomes a property of a new character, structurally identical to Alex's flatness and
  Marcus's fit. It also tightens Flicker's gift into ONE idea instead of two that happen
  to arrive together: **ride me, and while you ride me, we both phase.**

- **A stack containing Flicker fuses into one body** (author, 2026-07-29). Not carry
  propagating upward — *fusion*. If Flicker is anywhere in the stack, every character in
  it moves as a single object and phases as a single object, and any member can drive.
  This is a mechanic, not a physics simulation, and it is the right one: the series is
  about connection, and here connection literally makes them one thing. It also makes the
  STACK'S SILHOUETTE the puzzle piece — Stella tall, Alex wide, Marcus square, Flicker
  small — so *who* is in the stack and *in what order* decides what gap the fused body
  fits through. That is a large, cheap puzzle space opening exactly where Games 3 and 4
  need one, and it is the reason the cast caps at four (#30): a four-stack is the maximum
  expression, and there is nothing after it.

- **The blink is the teaching signal, and it is free.** When someone stands on Flicker,
  BOTH blink; in a fused stack, ALL of them blink. Unmissable, instantaneous, wordless,
  and temporal rather than chromatic so it survives any colour vision (#27). The gift:
  four characters on two players *must* be multiplexed anyway, and a stack is vertically
  contiguous — the arrangement the hop machinery draws best. So the fiction (they are
  half-there, together) and the hardware fact (four bodies, two players) are the same
  thing. The signal costs nothing because the hardware was going to do it regardless.
  This is the series' standing move — a limitation wearing the mask of emergence.

- **How it is discovered.** The input is already owned: standing on a friend has been in
  the player's hands since Game 1. Nothing new is being taught except that THIS friend
  answers it differently — the #21 pattern exactly, same input, new outcome, found by
  trying. The teaching floor: a barrier no one can cross; Flicker walks through it (the
  player learns phasing at once); Flicker cannot finish alone, so someone must reach the
  far side; each other character fails against the barrier, one failure each; and then
  the player stands someone on Flicker — a move they already have — and walks it
  through. Keep that floor SMALL: two characters, one barrier, nothing else, so the state
  space is minutes rather than luck.

- **Narration never explains mechanics — series-wide, and load-bearing here.** Game 3 has
  16K and could afford to tell the player. It must not. Narration carries story; mechanics
  are taught by failure (#21, and Game 1 throughout). Written down explicitly because the
  temptation arrives precisely when there is ROM to spare. The same rule kills speech as a
  teaching channel: **AtariVox** is a third-party accessory most players will not own, so
  it may add flavour or optional save state, never information the game needs — the same
  reasoning that made narration hybrid in #2. No single channel may be load-bearing.

**To prototype before committing** (the usual gate, #25): stack detection each frame; the
fused body's collision profile; and the rule for what happens when the fusion ends inside
solid matter. That last one is not a loose end — it is the ending. If a fused stack must
clear the wall before it un-phases, then Flicker choosing to stay behind, holding the way
open, is #11's sacrifice expressed in the mechanic the player has used all game. The
solver must learn all of it, and that is likely a larger job than the ROM change.

---

---

## 30. The Playable Cast Caps at Four

**Question:** #3 sets the progression at 2-3-4-5+ and describes Game 4 as "5+
characters including original echo characters." Does a fifth PLAYABLE character
ever arrive, or does the cast stop at four?

**Considerations:**
- Two independent limits converge on four. The TIA has two players, and four
  bodies on two players is already the crunch that makes Flicker's blink
  load-bearing (#29) — a fifth has nothing left to ride on. And Down+Fire cycling
  is comfortable at four and tedious past it (#22 puts a real navigable menu in
  Game 3, which is where character select may want a better affordance anyway).
- The echoes are explicitly observe-but-never-touch (#6; brief §181) — scenery
  with presence, not a roster. So the cast already stopped at four; #3 simply does
  not say so, and its "5+" reads like a fifth playable character is planned.
- Game 4 runs on an ARM coprocessor, so hardware would NOT cap it there. The cap
  therefore has to be a design commitment, or it will quietly erode.

**Status:** DECIDED (2026-07-29) — **four playable characters, series-wide.**
Stella, Alex, Marcus, Flicker; nobody else is ever picked up. This **amends #3**:
its "5+" counts echoes, which are not playable. Game 4 grows in *awareness*, not
headcount — which keeps every game's growth axis distinct and legible: spatial
scale (#18), UI sophistication (#22), the eye motif (#23), and cast (#3, closed
here at four).

---

## 31. The Form of Home Evolves With the Cast

**Question:** A home is a small 8x6 missile PAD in Game 1 and the tinted LEDGE
itself in Game 2. Should the two be unified, or is the difference the world
evolving?

**Considerations:**
- What matters is already identical. The mechanic is one (#26: place and hold,
  stand on your own colour and stay) and so is the feedback language (#27:
  blinking means to-do, fast blinking means yours, steady means held). In both
  games the action reads the same — *stand on the coloured thing that is yours*.
  Only whether that thing is a pad ON the world or a piece OF the world differs,
  which is the least load-bearing layer of the three.
- **The difference is forced, and forced at exactly the right place.** Game 1's
  model works only because two characters map onto two player registers: Stella's
  marker is M0 and takes COLUP0, Alex's is M1 and takes COLUP1, one each, stable.
  A third character has nowhere to go — and in Game 2 COLUP0 is the ACTIVE
  character's colour, which changes the instant you switch, while COLUP1 changes
  mid-frame at the P1 hop and again every frame under the flicker. A missile
  would wear whichever character happened to own that register. Three
  independently coloured markers do not exist on this hardware, so the colour had
  to move into the playfield. The form changed at precisely the step where the
  cast grew from two to three, and cast growth is the series' own axis (#3).
- **Additive, not contradictory** — the test #29 turned on. Carry physics was
  rejected because it would make something the player had learned FALSE. Nothing
  here does: Game 2 simply has no pads, the rule is unchanged, and the action is
  unchanged. Re-learning a shape is not the same as un-learning a rule.
- #27 already conceded the difference in passing — *"where home markers are
  geometry, their width matches their owner's body… Game 1's missiles are capped
  at 8px by hardware"* — without ever saying why, or that it was meant.
- Unifying is not a trade-off with a price. Game 1 → Game 2's model needs a
  12-byte RAM colour table plus kernel work against 27 free bytes; Game 2 →
  Game 1's model is impossible per the register argument. One direction is
  unaffordable, the other unavailable.

**Status:** DECIDED (2026-07-30) — **keep the difference, and promote it from
accident to intent.** The form of home is a per-generation axis like spatial
scale (#18), UI (#22) and the eyes (#23):

- **G1 (4K):** home is a MARK ON the world — something placed there. The world
  is too simple to mean anything by itself.
- **G2 (8K):** home is a PLACE IN the world — the architecture itself is yours.
  The world has become able to hold meaning. (Author: *"gives a feel the world is
  opening up."*)
- **G3 (16K):** OPEN, but the world extends and scrolls, so home plausibly
  becomes a DESTINATION you travel to. The game is called *Stella's Journey*.
- **G4 (ARM):** OPEN. The world gains colour everywhere (#27), so "coloured =
  home" stops being distinctive and the idea has to become something else.

G3 and G4 are recorded as questions waiting, not as a plan quietly hardening —
decide them when those games are prototyped, against whatever the cast and the
hardware turn out to need.

**How it is told:** through the MANUALS, one quiet line each, exactly as #23 does
for the eyes — never stated in ROM. The author's point stands: this arc is only
legible to someone who reads the manuals, and that is not a weakness but the
period-accurate answer. Atari games told their stories in the manual precisely
because the cartridge could not, and a series *about* four generations of
hardware should be honest about that. A player who never opens the manual loses
nothing playable; the mechanic and the feedback carry the game on their own.

## 32. The Proof Rig Is The Product — and What an Audit of It Found

**Question:** Two games, two hand-written re-implementations of the same physics
in `check_levels.py`, ~1200 lines of duplicated model code, and a decision log
that asserted "one goal mechanic for the series" while the two ROMs implemented
two different ones. Game 2 has features Game 1 lacks (clock, timer, end state,
music) even though every per-generation axis in this log claims they *grow*.
And the READMEs' free-space figures, which gate the Act 4 plan, were wrong.
What is the series' actual standard here — and does it survive its own claims?

**Status:** DECIDED (2026-10-10) — **Keep both games; converge them; do not
rewrite.** An audit found the *code* was in good shape and the *claims* were
not. The solvers, the negative proofs and the art audits are the asset; every
defect was a missing check or a stale sentence, not a design flaw. A rewrite
would have thrown away the rig and re-earned every bug it has already caught.

Three things changed as a result:

**1. There is now ONE goal rule, and Game 1 has the tighter one.** #31 claimed
Game 2's `AtHome` "is Game 1's `CheckGoals` rule exactly". It was not: Game 1
tested a box *overlap* against a 3du pad, accepting any standing height in an
11du window — eleven surfaces could each count as home, and only the level data
kept that honest, which is the exact fragility `AtHome` was written to kill. And
Game 1 is the game a player meets *first*. Game 1 now uses Game 2's exact-height
test. It cost nothing: two compares became one, so the tight rule is 8 bytes
*cheaper* than the loose one, and Game 1 went from 21 free bytes to 29. The pad's
stored byte still means the pad's top, so no level data moved.

**2. The solver must read the ROM, and must prove it did.** Three ways it
wasn't:

- **`SpeedHalfTbl` was never read.** Marcus walks 1.5px/frame; the solver
  modelled him at 1.0. Under-approximating a real speed means every "he can't
  make it" conclusion was drawn about a slower character than the ROM's. States
  now carry frame parity, exactly as `WalkSpeed` uses `FrameCtr`.
- **Per-floor tables were indexed past their ends.** `FloorPortL`/`FloorPort2L`
  were 6 entries and `NUM_FLOORS` is 9. The ROM read past them by luck (the bytes
  that followed were leading `255`s, so it bailed correctly). The solver read
  `FloorPort2L+6`, found `0` instead of the `255` sentinel, and invented a portal
  column at x=[0,8) on three floors that have none — one that drops a body at
  feet 56, which is Alex's home height on two of them. A phantom edge in a proof
  graph is worse than no proof. Tables are now padded, and `check_levels.py`
  asserts every per-floor table has room for `NUM_FLOORS` entries by measuring
  to the next symbol — so the next table added is checked for free.
- **The lamp band table was never audited, and was WRONG.**
  `FloorBandByChar` is authored a row per character (Stella's nine floors, then
  Alex's, then Marcus's) but `PrepSprites` indexed it `char*3 + floor`. Correct
  at three floors; wrong the moment there were nine. Stella read her own row by
  luck — her row occupies indices 0–8 — while Alex and Marcus were tinted from
  *her* bands. **17 of 27 lamps were painted at the wrong height**, on every
  floor. The lamp is #27's entire colour-blind-safety story: the one piece of
  feedback that tells a player whose home is whose, without colour vision. It
  had been lighting up the wrong ledges, in the wrong colours, since Act 1.
  Two table entries were also simply wrong (F6 Stella and Marcus). Fixed with a
  `MulNine` stride table, and `check_levels.py` now audits that each lamp band
  contains its home's *surface* and that a floor's three bands are distinct.

**3. The documents now state what is true.** Game 2's README said bank 0 had
11 bytes free and used it to justify "Act 4 will need a diet first". It has
**408**. Game 1's said 19; it had 21 and now has 29. Level records are 73 bytes,
not 69. A series whose founding thesis is *hardware capability grows with the
cartridge* cannot ship docs claiming a generation is fuller than the one before
it.

**Still open, and deliberately so:** Game 2 has no clock, no timer, no
`STATE_WIN` and no music — four things Game 1 has. #22 and the audio addendum
both describe these axes as growing. Either restore them (there are 408 bytes
and a whole idle audio channel) or amend #22 to say the axis is non-monotonic.
This is an authoring decision, not an engineering one, and it is not made here.

**The rule this establishes:** every table the solver reads is asserted to
exist and to be long enough; every claim in these docs about bytes, rules or
behaviour is checked by the build or measured from the ROM. A proof you cannot
re-derive is a comment, and this repo has enough of those.

### Amendment to #32 — the clock is back (2026-10-10)

The open question #32 left — *restore Game 2's clock, or amend #22 to say
the UI axis is non-monotonic?* — is answered **restore**, because the audit
showed the missing clock was not a neutral omission. It was the reason Game 2
*felt easier* than Game 1 despite shipping twice the geometry: the 4K game
clocks every level and the 8K game had no time pressure at all. A later,
roomier cartridge that is strictly more forgiving than the earlier one is
the series' thesis running backwards.

Armed by the left difficulty switch, as Game 1 arms it: 45 seconds a floor,
and at zero the floor starts over. No new state machine, no fail screen, no
menu — #22's "mostly switch-driven" holds.

**One deliberate divergence from Game 1.** G1 signals urgency by creeping the
background toward red. G2 does not, and cannot: #27 gives hue to agency, and
in this game every hue on screen belongs to something with a will. A red sky
would put colour on the one thing that must not carry it, and would collide
with the ember title cue players already learned in Game 1. So the world
instead goes dark — the gradient loses up to four luma steps over the last
sixteen seconds, one per four, and can reach black without ever borrowing
into the hue nibble. Same information, same register (a wash becoming a
deadline), in the vocabulary this game already speaks. The platforms stay at
luma A, so a fully-dimmed floor is still perfectly readable.

Cost: 77 bytes of bank 0 and 3 bytes of RAM, against a bank 0 that turns out
to have had 408 free rather than the 11 the README claimed. The
completion beat's duplicated sky loop was folded into `BuildSky` while the
clock was being wired in, which paid for about a third of it — one sky
painter now, so the world cannot pop back to full brightness for the beat it
just ran out of.

## 33. Every Character Has a Puzzle — and How We Know

**Question:** The 4K game "felt easy", and the author could not say why: the
levels were not short (median four moves, same as the 8K game), the physics
had not been softened, and the boosts worked. What was actually wrong?

**Status:** DECIDED (2026-10-10) — **measured, fixed, and made a standing
check.** The problem was not length. It was that *in all eight two-character
levels, at least one character's home sat on the ground floor.* With six
collision boxes and goals placed where the geometry happened to leave room,
the floor was the path of least resistance, so in every single level half the
cast walked right and stopped. The level was a puzzle; one of its two
participants was not playing it.

This is now the series' standing difficulty metric, because it is the one that
caught the fault:

> **Every character in every level must have a route that is a climb.**
> `check_levels.py` reports any home whose standing surface is the floor.

Fixed in L3, L5, L6, L7, L9, L10. Three levels became genuinely cooperative as
a side effect rather than as a plan — L5's Alex turned out to need a boost, L7
got back the "he is the one who goes home last" its own comment promised, and
L9's Stella needs his back. The lesson generalises: **a level's stated intent
is a hypothesis, and the solver is how you test it.** Two level comments
described a co-op beat that the geometry did not actually contain.

**Still open.** L4's Alex is on the floor and resists the same technique: its
pillar spans du 40–80, which walls Stella out of the right half of the screen,
so she can never boost him there, and he rises only 10du. It needs the
geometry restructured rather than a goal moved. The alternate goal placements
also need a pass — they have been kept *working* but not always *hard*, and
half of all playthroughs pick one.

**Resolved 2026-11-25 — see #35.** L4's Alex has a climb, L1's alternate
light no longer sits on the floor, and the floor rule is a build failure in
Game 1's checker. It had never been in it: #33 describes the check as
standing, and the checker could not fail on it, which is how three floor
homes survived a commit titled "every goal in both variants is now a climb".

### The upside-down flip is flavour, not complexity

Worth stating plainly, since it is the one thing that looks like depth and is
not: Quest 2 flips the *view*, not the geometry. Physics, solution and route
are byte-identical, so it adds no puzzle at all — only a demand that the
player mentally re-invert a layout they have already solved. That is a real
cognitive task and it is good flavour; it is the 4K cartridge buying a second
playthrough out of nearly free bytes, and it should never be counted as
complexity when judging a game's difficulty. **The alternate goal placements
are the same species**: they move the destination without changing the
problem.

## 34. Where the Series Goes After Game 2 — Switches, Rooms, and the Shape of G3

**Question:** The author wants each generation to feel larger than the last, and
was reaching for procedural generation (a Pitfall-style idea) to get there. Is
that the right axis, and is there anything else worth building?

**Status:** DECIDED (2026-10-10) — **no runtime procedural generation; yes to
a switch verb; yes to rooms; generation belongs in the designer's hands, not
the cartridge.**

### Runtime generation is the wrong tool for this series

It works directly against what makes the series distinct. A randomly generated
layout has no *intended solution*, so there is nothing to deduce — the player's
job becomes execution ("can I make this jump") rather than discovery ("what is
the solution"). That buys volume by trading away the one thing the series is
for. It also feels *bigger* while being emptier, which is the wrong trade.

**The synthesis is already written in #14**: *"the solver enables the
generate-offline / validate / hand-curate / bake-as-data pipeline if generated
levels are ever wanted — generation happens on a modern machine, never in ROM."*
That is the honest version of the idea. `check_levels.py` is now a genuine
level-space search engine: it can prove a layout completable, measure its
playability margin, and prove whether its verb is load-bearing. Point that at a
parameterised generator, discard the boring candidates automatically, and
**hand-curate the survivors into authored puzzles** — puzzles a human chose
because the margin report said they were good.

That is the G3 axis. It scales with the cartridge by requiring **zero runtime
bytes**, and it is the one thing this project can do that nobody else on the
platform can, because the rig exists.

### The switch: a fourth axis, and the first stateful one

Acts 1–3 are all **stateless** — you may always wrap, always portal, always
swap. A switch (a lever, a button, a plate) is the first mechanic that
**persists a change**:

| Act | Verb | Kind |
|-----|------|------|
| 1 | wrap | spatial rule |
| 2 | portal | linked space |
| 3 | rift | change space |
| 4 | **switch** | **change the geometry over time** |

It is also nearly free: "the switch moves a wall" is *literally* Act 3's
machinery — `SwapWorld` already repoints `PF1Ptr/PF2Ptr/PlatPtr` at alternate
pages of the same record. A switch is that pointer swap triggered by the
player instead of by a rift. New semantics, almost no new code.

**Deliberately stationary, not portable.** Atari's *Adventure* uses a golden
key: an object you pick up and carry, which makes its puzzle a *fetch* quest
with an inventory and a question of who is carrying it. A switch has no
inventory and no carrying — it is a *causal* change, and all three characters
can work it. Same "something opens" surface, different puzzle type, and the
stationary form is the one that fits a three-character cast. **Switch, not
key.**

**And it gives Flicker a job.** G3 introduces him as a character who exists
only every other frame. A switch that responds only while he is standing on it
turns that fragility from a story beat into the puzzle itself — the one being
whose "off" phase is the mechanic. That is a far stronger reason to want him
than the one currently in the brief.

**Explicitly rejected: the mobile carrier.** *Adventure*'s dragon is a creature
you enter and are carried by. Our portal is the same *idea* but static; the
mobile version is not wanted. It converts the puzzle from deduction to timing —
waiting for a ride rather than working out a route — which is a different game,
and it reads poorly without a framebuffer. Linked space is already covered.

### Rooms, not scrolling

The homage game's later levels scroll. That is not reachable here, and *Adventure*
shows it is not necessary: it never scrolls. It is three fixed screens joined
by gates, and it feels like a world anyway. The engine already has this
mechanism — `LoadFloor` repoints the plane and box pointers at a different
record — so **a floor is already a room; it just is not presented as one.**

G3 should formalise it: a visible gate the player walks into, a hard cut, and a
distinct silhouette per room. Adventure made each room instantly identifiable
by **colour**; decision #27 gives hue to agency here, so that channel is
unavailable and the work must be done with geometry instead — distinct
silhouettes, plus the per-act sky gradient already on the todo list.

### Unlocked: mirrored levels are now testable

#13 rejected flipping *geometry* on the reasoning that "flipping geometry
breaks jump-chain solvability". That was an **assumption**, made when checking a
mirrored level meant hand-solving it. The solver now proves a mirrored layout
per character, with margins, in seconds. So a mirrored variant is not
known-impossible — it is *testable*, which makes it a cheap source of a
genuinely different puzzle that looks the same rotated. Still impossible in
G1 (a second record is 73 bytes against 29 free — which vindicates reading the
flip as a 4K accommodation), but comfortable at 16K with four banks.

## 35. The Rest of the Honesty Rule, a Joint Proof, and the Relay

**Question:** The 4K game is to be pushed as far as it goes before Game 2
grows past it. Step one was small on paper — give L1's alternate and L4's
Alex a climb, enforce #33's floor rule, and try one relay level. What did
the checker not know about its own levels?

**Status:** DECIDED (2026-11-25) — **measured, fixed, and made a standing
check — but not yet played.** Every level was re-proven two ways (the
shipped checker, and an independent per-frame search that allows full air
steering); none of it has been playtested in Stella or seen on hardware.
The levels are provisional until the author has played them.

### The checker only proved one direction

#17's rule is "what is drawn solid must BE solid". `check_art` checked
every collision box is drawn. It never checked the reverse, and the
playfield is mirrored: **a box added on one side of the screen is drawn on
the other side too.** The redesigns since rc1 — rc2's shelves, then #33's
"give every character a puzzle" — added one-sided boxes to symmetric art,
and five levels came to draw blocks that were not there:

| Level | What was drawn and not solid |
|---|---|
| L3 | the right-hand shelf (px 96–119) and the left low block (px 28–43) |
| L5 | the whole left platform (px 4–35) — where both shapes woke |
| L6 | the left mirror of the right ledge (px 16–31) |
| L9 | the left mirror of Alex's step (px 12–27) |
| L10 | a second tower, shelf and step: du 56–80 across most of the screen |

rc1's levels were symmetric and had none. Two of them were worse than
cosmetic. **L3 woke Stella one double-line inside the shelf and the pillar
at once**; her first press clamped her through one of them (a body inside
a box is pushed to that box's far edge), and that push was the level's only
route to her home. **L5's proof depended on the same push:** Alex had to
land on the platform with his head inside the overhanging ledge, and a
press carried him out of it. RC2.1's "global overlap scan" had been a
one-off; nothing re-ran it after the geometry moved.

### What the checker runs now

Five proofs on every level and both goal layouts, any one of which fails
the build:

- **DRAWN IS SOLID, both ways.** Every box is drawn, and everything drawn
  where a body can reach is a box. Scenery entirely above the highest
  point any body can occupy is left alone — L2's far-off structures are
  meant to be looked at.
- **NO EMBEDDING.** No stance on a box overlaps a slab (the overlap scan,
  as a build check). A shape perched on a friend's head beside a slab is
  the residual RC2-NOTES.md already records and is not tested.
- **CLIMB.** No home stands on the level's lowest surface (#33). The floor
  is the level's floor, not the surface a shape wakes on.
- **ONE-WAY.** Each shape holds its home, at least one of them alone.
- **RELAY.** When neither can, `joint_plan` must play the level start to
  finish.

`--joint` runs the joint search on every level; it found a bug in the
search on its first full run (L3: it assumed a friend's head always catches
a jumper, forgetting the friend can simply stand elsewhere).

### The relay: a class of level the engine had always played

The one-way rule needs one shape to finish entirely alone, and its helper
only stands where it could have walked unaided. Neither can see a level
where **each shape's home is reachable only from where the other one ends
up** — the second helper has already been helped. Such a level failed as
"no workable hold order", although the engine plays it perfectly well.

The joint search plays instead: both shapes standing, either one may walk,
jump or step off in one direction, land on the other's head (the base must
be able to walk to a spot that catches it, and nothing may come to rest
inside a slab), walk along it, and leave again. Every edge is a real
sequence of inputs, so a found plan is a solution. Not modelled, which can
only cost solutions: steering mid-air, switching while both are airborne,
and a base walking out from under a rider.

A relay is the place-and-hold answer to the order-locks #26 removed. The
order is not enforced; it is the only way, and the player finds that out.
It is the cheapest gameplay in the cartridge: zero bytes.

**L8 "Steps" and L10 "The Exit" are relays now** — 4 moves, and 7 for the
finale's longest plan. A first L8 was not one: from its tower top Stella
could reach the perch alone, and the exact search said so.

### A rule for level art, learned the hard way

- **A shape can stand on a ledge with ONE pixel of overlap.** Measure every
  "she can just reach it" from a ledge's last pixel, not its middle.
- **Sky matters as much as ground.** Alex is 16 px wide; if the gap between
  two overhead slabs is narrower, he cannot jump there at all. L5's right
  side had 13.
- **Waking beside a band-9 ledge's right edge makes the first press-right
  push a shape through it.** Spawns go clear of the ledge, not under its lip.
- **Anything off the mirror axis needs its twin** or the art must be
  symmetric. The checker enforces it; a level is now 6 boxes *including*
  twins, which is the real budget.

### What changed, level by level

| Level | Change | Kind now |
|---|---|---|
| 1 Awakening | the alternate light was on the floor: the block grew a column and the light sits on top, one jump short from the ground | solo |
| 3 Discovery | redrawn symmetric: shelves on both sides of the pillar; Stella wakes clear of them | parallel |
| 4 Connection | redrawn: wall perches become corner steps plus high ledges — a corner step anyone can reach, a 16 du climb from it only Stella can make | parallel |
| 5 Ascent | redrawn: solid wall blocks, Alex's home on the right one's top, clear sky where Stella lifts him | Alex needs Stella |
| 6 Boost | the fourth ledge gets its box | Alex needs Stella |
| 8 Steps | a relay: a beam with a perch at each end | relay |
| 9 Patience | corner steps; perches a double-line nearer the pillar (a solid stair beside the perch handed Stella the climb alone) | Stella needs Alex |
| 10 The Exit | redrawn symmetric; a relay over a tower | relay |

Unchanged: 2, 7. Six of the eight two-shape levels still need a friend,
in three shapes now: four one-way and two relays.

**Still owed:** a playtest of all of the above, the hardware validation
rc3 already owed, and the stale claims listed in the review that opened
this (the manual's "red doors" tip and its name for the endless game, the
landing page's byte count, Game 2's bank-0 figure, and whether Quest 2's
timer is meant to be forced — the README and #13 say so, the code does
not).

### The reset routine never cleared RAM

Found while giving the tune a counter: `Reset`'s loop (the same one, with
the same comment, in Game 2) pushes 256 zeros **onto the stack page**,
$0100–$01FF. A push cannot reach the console's RAM at $80–$FF, so "clears
TIA + RAM" was never true, and Game 1's "State = STATE_TITLE (0) from the
RAM clear" rested on RAM happening to be zero at power-on. Real hardware
does not promise that. Run with anything else in RAM, the machine drew the
game kernel from random pointers, console RESET changed nothing, and only
fire reached the title. Game 2 already sets `State` outright — presumably
because a cold boot misbehaved there once. Game 1 now clears $80–$FF for
real (7 bytes) and RESET returns everything to zero.

### Running the ROM headlessly

Everything above about input, the tune and the reset was checked by running the
assembled ROM on a small 6502 interpreter rather than by reading the listing, and
it is in the repo: **`tools/headless.py`** (`make headless`). It is a 6502 with the
RIOT timer and the input and audio registers the game uses, driven a frame at a
time; there is no beam, so it cannot see the picture or notice an overrun. What it
does is walk every screen — a cold boot with garbage in RAM, title, story, play,
the tune on its grid, the completion beat, two shapes, the ending, the upside-down
replay, the epilogue, endless, reset — and check what must be true of each; and
with `--compare OTHER.bin OTHER.sym` it feeds two ROMs the same random input and
reports the first frame on which their memory differs, which is how the `FireEdge`
refactor was proved to change nothing (eight runs of 6,000 frames, identical —
state and audio every frame; its memory only on the last frame, as #37 found).

It earned its keep on its first outing: three faults in the new tune code were
invisible in the source and obvious in the trace — a rest written as
`lda #0 / bne`, which is not the unconditional branch it looks like (every rest
played the *highest* note at full volume); a 32-step table indexed by a counter
that could only count to seven; and the tune running after the goal check on the
frame a level completes, so its last note held through the fanfare. It also caught
several bugs in itself before it caught any in the ROM, which is the right order,
and its own first version mislabelled the audio registers and reported each
frame's starting state — both of which showed up as failures of a ROM that was
correct. **A harness that fails is not evidence against the thing it tests until
the harness has been made to fail on purpose**: compare two ROMs that differ and
see it say so.

## 36. The Sky: Scenery Where No Shape Can Go, and Two Levels That Climb

**Question:** Every room kept to the bottom 40% of the screen. Is that a
limit of the engine, or a constraint to make levels easier to check — and
if nothing can ever climb above the middle, what harm is there in drawing
something up there? (The author asked for both: fuller rooms, and one or
two levels that climb.)

**Status:** DECIDED (2026-11-25) — **not a testing constraint, and not a
hard limit.** "Nothing can stand above the middle" was true only of the
levels as drawn: the highest surface any of them offered was du 48, in 8
and 10. Measured on the engine:

- One jump lands a shape 16 du higher — a sixth of the screen — and 24 du
  higher off the other's head.
- Given a staircase, Stella alone climbs to du 16; only the top band is
  dead, because the top of the screen cuts the jump.
- Every platform off the centre line needs its mirror twin, against six
  boxes. The levels were spending theirs on the puzzle at the bottom.

### Scenery above the highest point a body can reach

Anything drawn where no body can ever get is scenery, costs nothing (a
level's drawing is 36 bytes whether used or not), and `check_levels.py`
already allowed it. What it did not do was judge *reach* well: it took the
tallest box as the highest foothold, so a pillar nothing could climb put
its own top — and all the sky above it — off limits in three rooms. It now
starts from the floor and keeps only the tops some shape could land on
from a height it already has, alone or off a friend's head, judged by
height alone (which can only over-estimate). Lower L3's pillar by one band
and the build fails: its sky is no longer out of reach.

The look is a decision, not a rule: **hollow shapes** — windows and arches
hanging from the top edge — because a filled slab floating up there reads
as a platform you cannot reach (tried, and rejected on sight). A different
skyline per room, so a room can be recognised when it is upside down.

Room for sky, in bands of eight du: four in 1, 3 and 6; three in 2, 4, 7
and 9; one in 8; none in 5 and 10.

### Two rooms that climb

- **5 Ascent → du 24.** A floating stair of four *centred* slabs: a
  centred slab is one box, so the stair costs four of six. Each step is
  16 du, one jump for Stella alone; her light is on top. Alex's light is
  on the base slab, 16 du up — he still needs her head — so the room stays
  "Alex needs Stella".
- **10 The Exit → du 32.** A relay. Alex's home is the tower top at du 56,
  two of Stella's heads up; Stella's is the cap above it, 24 du higher
  than the tower, one Alex too high from the tower alone. Seven moves,
  three lifts.

Consequence: those two rooms have no sky — a shape can get into every
band of them. That is right: they are the top of the world.

**The grey, done the same day (#37):** the sky was the same grey as the
world. It is two luma steps dimmer now, which needed the kernel
restructured; that is written up with the audit, along with how the
rewrite was proved to draw the same picture.

### A rule for level art, learned the hard way (continued from #35)

- **Measure reach from what can be stood on, not from the tallest box.**
- **A pillar's top is a foothold if it is one boost away.** 4 and 9's
  pillars reached du 40, exactly one of Alex's-head boosts from their
  du-64 ledges; they reach 32 now, and their tops are out of reach.

## 37. The 4K Game Audited: Two Faults, a Kernel Rewritten for a Dim Sky

**Question:** Close Game 1. Before that, read all of it once, end to end,
and measure what cannot be seen in the source: does every line of every
kernel fit its scanline, does every frame's logic fit its blank.

**Status:** DECIDED and done (2026-11-25). Room after it: **13 bytes**.

### What reading found

- **RESET during a sound left channel 0 sounding** through the title
  and every story screen after it: the title silenced channel 1 and
  nothing ever wrote channel 0 until play began. The title writes it
  now (three bytes), which also covers a console at power-on, where
  the TIA is not promised silent.
- **A SELECT held with the stick and fire down ran past the blank** in
  level 3: 2,843 cycles of logic against the 2,816 the timer allows,
  so those frames began a line late. The reload was followed by the
  whole of the frame's logic on top of it. A reload is now the whole
  of its frame (three bytes): 1,185 cycles.
- **Reported, then withdrawn:** the audit first said the ember title
  was black over its bottom third. It is not; the logo is 112 lines,
  not 56, and the title draws all 192. Kept here because a finding
  that is wrong for an ordinary reason is worth as much as one that is
  right.

### What the A/B found, and reading had not

For one frame at the start of every upside-down level, both shapes were
drawn the right way up: `LoadLevel` seeded the kernel's draw heights
without the flip, and nothing corrected them until the next frame. The
draw-position loop is a routine now (`DrawPos`) and `LoadLevel` ends in
it. It would have been found by no one: one frame in sixty, on a screen
that has just changed.

### Measured, harmless, and left

- **Title and epilogue frames are one scanline long** (263 against 262):
  the loop that leaves the logo, and the one that leaves the digits,
  run to 90 and 84 cycles. It costs bytes to fix and shows nowhere.
- **The blank is 89% full:** 2,507 of 2,816 cycles in the worst of
  36,000 random frames. The overscan's 2,176 cycles are unused. Logic
  that is added later belongs there, not in the blank.
- **The story kernel's text-start line sat at exactly 76 cycles**, the
  only line in the ROM with nothing to spare. It has three now (two
  bytes). The game kernel has three, two at a band edge.

### The dim sky

The sky is two luma steps under the world: `COL_SKY = $06` against
`$0A`, one constant, to be tuned by eye in Stella. `BandColr` holds a
colour per band, in record order, so it reads the same forwards and
backwards, and a band line writes its colour in the hblank that the band
countdown used to spend. The countdown was what had to go:

- **X runs 160 ahead.** It counts 160 to 255 and wraps to 0 on the 96th
  du, which ends the loop without a compare, and its low three bits say
  where a du sits in its band. Everything the kernel compares X against
  is stored 160 high to match (`DrawPos`, `FlipG`); `HIDE_Y` is out of
  range either way.
- **Goal marker 0 is a subroutine**, so the band line, the plain line
  and the prefetch line share it.
- **The budget is 73 cycles** between one WSYNC and the next. Line 2
  uses 70 with everything visible (71 at a band edge), the prefetch
  line 70, a band line 64, a plain line 39. Marker 1 stays on line 2
  and marker 0 on line 1, where they always were.
- The kernel with its table is three bytes smaller than the one it
  replaced.

**How it was proved.** Old ROM against new, the same random input for
36,141 frames: memory and audio identical (pointers, the kernel's own
heights and one scratch byte aside); and scanline by scanline, the same
writes to the three playfield bytes, both shapes and both lamps, in the
same order — except nine frames, which are those upside-down first
frames, where the old ROM was the one drawing wrongly. With RESET pressed
in mid-sound, the only difference is channel 0: silent in the new ROM,
still sounding in the old.

**Not seen yet.** None of this has been looked at in Stella or on a
console. What to look at: the grey (`$08` is one step dim, `$04` is
two), and whether the sky now reads as distance.

### The harness learned to count

`tools/headless.py` counts cycles now: a WSYNC sleeps to the end of its
scanline, and the timer runs through it. Three checks came with that —
the game kernel always reaches its next WSYNC inside the scanline (the
latest write is at cycle 72 of 76), the blank holds every frame's logic
(SELECT held with the stick and fire down, in every level, both ways up,
included), and the band colours come out in the right order both ways
up. Its A/B compares every frame's memory. Until today it compared each
frame's state and audio registers and the **last** frame's memory, so
the `FireEdge` proof in #35 was weaker than it said; it is as stated
now.

## 38. The Manual for Game 1: Drawn Pictures, a Cast, and the Stranger

**Question:** The manual still described RC1: exit markers a shape left
by, a rainbow title, "red doors", and two modes numbered as if they were
the series' games. Its screenshots show rooms that no longer exist. What
should the manual be for the game as it is, and where do its pictures
come from when nobody can take new ones?

**Status:** DECIDED and done (2026-11-25).

- **Both manuals, same content.** `MANUAL.md` is the text the website
  links to; `manual/manual.html` is the illustrated, printable one. They
  say the same things in the same order.
- **Pictures are drawn from the cartridge.** `make pictures`
  (`tools/manual_pictures.py`) turns the level records and the text
  tables into pixels: each room with both shapes where they wake and each
  light in both its places, one room upside down, the title in both
  skies, the five narration screens, the cast to scale, the closing
  screen, a room with the clock low. The geometry is the game's. A room
  cannot change without its picture changing, and no picture can show a
  room that was not shipped. The RC1 screenshots are retired, all ten
  (`manual/SCREENSHOTS-TODO.md` says what to shoot again, for the day
  there is a television in the loop).
- **One story, three characters.** A background for the world as the
  creative brief has it (a constrained world, lights nobody explains,
  the shift, the turning over), a page each for Stella and Alex taken
  from the brief and from what the engine lets them do, and the stranger
  on the closing screen as a teaser: what it looks like, that it
  breathes, that it is not named here. Nothing is said that #15 and #21
  rely on, and its name is left for Game 2.
- **Two modes, not two games.** The story game and the endless game. In
  a four-game series, "Game 1" and "Game 2" on one cartridge read as the
  series' numbers.
- **Everything the cartridge does is written down:** the lights and
  their blinking, standing on a friend, the sky, the two placements of
  the lights, what SELECT does mid-room (the lights may come back in
  their other places, which is what the cartridge does today), the run
  clock and when it runs, the one-minute clock, and every switch,
  including the two that do nothing.

## 39. The Upside-Down Run Gets Its Own Lights

**Status:** Accepted (2026-11-25)

The second run was the first ten rooms with the picture turned over.
Turning the picture changes no puzzle, so ten of the twenty rooms were
already solved by the time they arrived. It was a way to get twenty
rooms out of ten records, and it still is: what changes is the 4 bytes
of each record that held a second set of lights.

- **The second set of lights is the remix.** It used to be a coin flip
  off the frame counter at load, and was mostly a mirror image. Now the
  story game plays it exactly when the world has turned over, and plays
  the first set otherwise. Each remix was chosen by searching every
  standable light position in the room with `check_levels.py`'s joint
  planner and taking the hardest pair that reads as a new idea rather
  than a longer walk. 5 (a leapfrog up the stair, 12 moves) and 7 (a
  relay with a flight across the room, 10 moves) are the big ones; 3, 6
  and 9 are at their room's ceiling already, so theirs are new routes.
- **The endless game keeps the first set.** Its clock falls to 12
  seconds and the remixes run to 12 moves.
- **The endless orientation is no longer the level's parity.** Bit 0 of
  `Rand` chose the orientation and `Rand mod 10` the room. 10 is even,
  so each room always came the same way up. Bit 6 now. Quest is 1 in
  the story and $40 in endless, and LoadLevel's `lsr` reads bit 0 as
  "the story's remix", which is why NextRandom must never use bit 0.
- **8 Patience and 9 Steps change places,** so the first relay is not
  followed by an easier room.
- **SELECT restarts the room as it was.** The manual's "the lights may
  come back in their other places" goes.
- **Cost: none.** 13 bytes free before and after.
- **Not decided here:** whether 7's remix is fun. It needs a person.

## 40. Polish for Game 1: a Glow, the Turn, and ALONE

**Status:** Accepted (2026-11-25)

Game 1 opens the series, so its polish goes into moments that make the
world feel bigger than the room, not into menus or more text. A
two-line narration screen costs about 78 bytes, which is more than
this whole decision spends.

- **Bytes come from code, not content.** `LoadLevel` was open-coded:
  three copies of a 16-bit add for the record pointers, unrolled reads,
  eleven `sta`s of zero. As loops, 13 bytes free became 69, with no
  room cut. The A/B harness proved the new code identical frame by
  frame.
- **The completion glow** replaces the grey strobe with gold that
  fades (luma = StateTimer / 8). The pause is 79 frames so the glow
  starts at luma 8, below the platforms' 10.
- **The turn** holds the first room upright and glowing for 127 frames
  before it loads upside down. It is the completion pause again, with
  Level at $FF so its advance lands on 0: 4 bytes. A rolling animation
  was weighed and left out. The kernel draws bands from Band0 by
  BandStep, and no cheap state in between looks like a turn.
- **ALONE fades** from the title once the stranger has been met, over
  about four seconds, and stays gone until power-off. `AloneFade` is
  the one byte the console RESET switch spares. Its value is 0 at
  power-on (`Reset` loads Y with 0, `Restart` stores Y after clearing
  RAM). The manual keeps it secret: it is the player's to notice.
- **Not done:** a hint of the stranger during play. The closing screen
  carries it, and the game kernel has four cycles to spare.
- **29 bytes free** after all of it.

## 41. The Manual Explains Itself, Behind a Warning

**Status:** Accepted (2026-11-25)

Hoping for an "aha" is a risk: a player who never finds the remixes or
the fading title never gets the payoff. So the manual now says these
things plainly, at the back, behind a warning page that asks the reader
to choose.

- **Behind the Design:** twenty rooms from ten records and the remix,
  the turn, the glow, ALONE fading from the title, the stranger, the
  unreachable sky, the program that solves every room, why the endless
  game keeps the first lights, and the 4,096 bytes. Rooms 5 and 7 are
  pictured upside down with their remix lights (`make pictures`).
- **Walkthrough:** all twenty rooms, written from `check_levels.py
  --joint`'s plans, so every answer is a solution the engine's physics
  accepts. The illustrated manual prints it upside down, with a button
  that turns it over; `MANUAL.md` folds each half into a `<details>`.
- **A correction found on the way:** room 9 (Steps) said Alex must be
  standing home before Stella climbs on him. The planner shows she
  climbs him anywhere on the beam and he walks home afterwards. It now
  says each needs the other.
- The first part of the manual still says nothing about the secrets. A
  tip points to the back for anyone who is stuck.

## 42. Made the 4K Way: the Era Rules for Game 1, in One Place

**Status:** Accepted (2026-11-25). Collects rules decided across #1,
#20, #22, #27 and #31, and says them in the manual.

Game 1 keeps to what a 1977-82 4K cartridge could be. The rules were
decided one at a time; this is the list.

- **4,096 bytes, no bankswitching** (#1, #4). 128 bytes of RAM, 87 used.
- **No on-screen menu** (#22). The options are the console's switches:
  SELECT picks the story game or the endless game, the left difficulty
  switch adds a clock, RESET goes back to the title. Menus grow with
  the series.
- **The story lives in the manual** (#31, #2). The cartridge holds five
  short narration screens; the booklet holds the world.
- **What the hardware draws:** a mirrored playfield (#20), two player
  sprites, a grey world with a few colours, and every screen legible on
  a black-and-white set (#27).
- **Modern tools are in how it was made, never in the cartridge:** the
  level checker, the headless harness and the picture tool run at build
  time and ship nothing (#43).

The manual says this in "About This Cartridge", so a player knows the
limits are chosen, not missed.

## 43. Transparent Use of AI and Tools

**Status:** Accepted (2026-11-25)

The project is developed with generative AI models and with Python
tools written for it. Players and readers should be able to know that,
and nothing in the repository said so.

- **What is said, and where:** the manual's "About This Cartridge" page
  and the repository README both state that the story, characters and
  series are Michael Borck's; that code, level designs, test tools and
  much of the writing are developed with the help of generative AI
  models under his direction; that he reviews, edits and approves all
  of it; and which tools check the game, none of which ships in the
  cartridge.
- **No vendor is named.** More than one model was used over the life of
  the project, and the statement is about how the game was made, not
  whose product helped.
- **Review is stated, not implied.** A name on the cover says who owns
  the work. It does not tell a reader that a person checked what the
  models produced, which is the thing a disclosure is for.
- **Traceability, as far as it goes:** later commits carry a
  `Co-Authored-By` trailer naming the model; earlier AI-assisted work
  is not marked commit by commit, and the README says so rather than
  claim otherwise.
- **Responsibility stays human:** the tools did a great deal of the
  work; the choices, and the responsibility for them, are the author's.
- **The source is linked from the manual,** so the claims can be
  checked: the code, the tools and this decision log are public.
- **Later games** carry the same page, updated for how each was made.

## 44. Two Players in Game 2 — and the Flicker Rule Relaxed

**Status:** DECIDED (2026-11-26) — **Game 2 is playable by one or two
players.** Amends #19 and the "lean into the flicker" change (commit
`82133b8`).

**The idea.** Each player holds one character. DOWN+Fire swaps to
whichever character nobody holds; with three characters and two players
there is always exactly one. One player alone plays exactly as now,
switching among all three. As far as we know the game that inspired the
series is single-player only, so this is a dimension of its own rather
than a borrowing.

**Why Game 2 and not Game 3:**
- The theme. Game 2 is *Stella Was Together*: "not every challenge
  could be overcome alone." It is the first game with more characters
  than one person comfortably steers.
- It is another axis on which each game grows (#22): Game 1 one
  player, Game 2 two.
- It is how the era did it. The console ships with two joysticks, and
  SELECT choosing one or two players is a period game variation, not a
  menu (#22, #42). Game 2's SELECT is unused ("reserved for future
  variation").
- Game 3 is harder: four characters, including Flicker, who flickers
  even while controlled (#29), on two sprites.

**The flicker rule, relaxed.** `82133b8` made the two characters you do
not control always flicker, so that the player learns "the one you
control is solid" and Flicker can break it in Game 3. With two players,
two characters are held and the TIA has two sprites, so the free one
must share a sprite with a held one. The mid-frame P1 hop that #19
built, and `82133b8` left in place but unreachable (`RepoDU` = $FF), is
turned back on: everyone draws solid whenever the free character
separates vertically from a held one, and only when all three stand
level do the free one and one held one flicker. The rule becomes
"everyone held is solid unless all three stand level." One-player mode
may keep the always-flicker look; that is open. We may yet find a
better answer.

**Design consequences:**
- Every floor must stay solvable by one player. The solver proves that
  already; two players acting at once can only make a floor easier,
  which is fine for co-op.
- The player count is chosen on the title with SELECT, shown in the
  game's own visual language (no menu text).

**Prerequisite: RAM.** Two players need a second "who is controlled"
byte, a second fire-button memory and the player count: two or three
bytes, fewer if flags are packed. Game 2 had none to spare: its new
harness found the stack already one byte into the variables (#45). The
hop's own six bytes (`P1Y2`..`P1Nu2`), unused since `82133b8`, become
needed again. RAM has to be reclaimed before two players can be built.

**The cartridge formats, for the record.** The 2600 sees only 4 KB of
cartridge at a time, so every game past the first bank-switches:
Game 2 is 8K as F8 (two 4K banks, already in use, and #9 made banking
the story's world-swap, now delivered by pointer swaps). Game 3 is 16K,
F6, four banks. Game 4 puts an ARM processor on the cartridge, as Champ
Games-style homebrews do: the ARM runs the game and prepares each
line's data, and the 6502 still feeds the TIA every scanline from what
the ARM prepared.

## 45. Game 2 Gets a Harness — and What It Found

**Status:** Accepted (2026-11-26)

Game 1's `tools/headless.py` found faults that reading the source had
not. Game 2 had no equivalent, and two players will touch the kernel
and RAM, so it gets one first: `games/02-stella-was-together/tools/
headless.py`, run by `make headless` (and `make ram` for the RAM
table).

**What it models that Game 1's did not:** F8 banking (either bank at
power-on); the 2600's address decoding, so RAM is one 128-byte block
that the stack shares; frames counted VSYNC to VSYNC across both banks;
the RIOT timer's first count one cycle after it is set; WSYNC sleeps in
the cycle total. Game 1's harness kept the stack in a separate page and
left WSYNC sleeps out of its cycle count; neither affected what it
checked, but run through the new model Game 1's frames come out at
263-265 lines rather than 262. That is worth confirming in Stella.

**Calibration.** With the timer modelled exactly, Game 2's play frames
come out at exactly 262 lines, the figure its own fix in `fecc421` was
checked against.

**Found, in order of harm:**
1. **The stack overruns the variables by one byte.** 121 bytes are
   declared; the deepest call chain (MainLoop -> WakeLogic or DoneLogic
   -> PrepSprites -> FillP1 -> CharColor) needs 8 bytes of stack; 129 >
   128. The eighth byte is `TimeDim` ($F8), the clock's darkening of
   the sky, which gets `$32` (50). `DoneLogic` repaints the sky every
   frame of the completion beat, subtracting `TimeDim`, so **from the
   second frame of every floor's completion beat the whole sky is
   black**: the "breath" is a cut to black for about 1.5 seconds. The
   waking opening clobbers it too, and does not reload the floor, so
   floor 1 begins with `TimeDim` = 50. This is very likely the flashing
   the author remembered.
2. **Screen changes make frames of the wrong length:** completion ->
   narration 50 lines (the kernel is skipped that frame), narration ->
   floor 287-289, title -> waking 276. A wrong-length frame can make a
   television roll for an instant.
3. **Play logic overruns its blank** in about 2% of soak frames (263-265
   lines), at the vertical-blank wait in `MainLoop`.
4. **Title and narration frames are a steady 263 lines:** the title's
   last logo line and the narration's last line before
   `AnnexOverscan` run past their scanline.

`make headless` fails on (1), the one that corrupts memory, and measures
(2)-(4) as WARN until they are fixed. The RAM table (`make ram`) shows
which screens touch each variable; it is where the bytes for (1) and for
two players (#44) will come from.

## 46. Game 2's RAM: Two Bugs Fixed, Five Bytes Found

**Status:** Accepted (2026-11-26). Follows #45; makes room for #44.

**Fixed:**
- **The stack overrun (#45, finding 1).** `CharColor` is inlined into
  `FillP1`, so the deepest chain is three calls (6 bytes), not four
  (8). The completion beat keeps its sky. 7 bytes of bank 0.
- **The untimed sky was four steps dark, always.** Found while fixing
  the first. `LoadFloor` set `TimerSec` only when the clock was armed,
  so untimed floors kept 0, and the dimming read "no seconds left" and
  took its full 4 luma off the sky. Every untimed floor since the clock
  was added (`41a5b4e`) showed a ramp of 0-4 instead of 0-8. `TimerSec`
  is now set to 45 either way; the clock still only counts when armed.

**Four bytes freed, with no change in behaviour:**
- `StateTimer` shares `WakeT`'s byte. The opening and the completion
  beat never run together, and each sets its own before reading it.
- `StoryAfter` is gone: it was "FloorSeq has reached NUM_FLOORS".
- `StoryId` is gone: the narration after floor n is screen n, so the
  annex reads `FloorSeq`. `FloorStoryTbl` (1 to 9) went with it.
- `TimeDim` is gone: it was a pure function of `TimerSec`. `BuildSky`
  works the dim out when it paints (into `SkyDim`, an alias of the
  physics scratch byte `LV`, since the sky is never painted inside
  physics). It is computed inline, not by a call, because a world swap
  reaches `BuildSky` two calls deep and one more would be the overrun
  again. The clock repaints at exactly the seconds where the dim
  changes: 12, 8, 4 and 0.

**Result:** 117 bytes declared, the stack 6 deep at most, **5 bytes
spare**. Two players (#44) need two or three.

**How it was checked:** `make headless` passes, with two new checks:
the stack against the variables, and (clock off) the sky keeps its full
ramp in play and in the completion beat; the old build fails that one
on 1,059 frames. `headless.py --compare` runs two builds on the same
random input and compares every variable by name each frame, so a
changed RAM layout can still be compared. Against the build with only
the two fixes: six runs of about 4,000 frames through every screen,
identical, skipping only the shared byte (`WakeT`/`StateTimer`), the
scratch bytes `LV` and `Temp`, the pointers, and the removed variables.


## 47. Game 2 Plays Two: SELECT, Two Joysticks, the Hop Back

**Status:** Accepted (2026-11-26). Builds #44 on the RAM #46 freed.

**What a player sees.**
- **The title** shows the player count as the cast. Stella stands
  alone on the bottom sky for one player; for two, Alex stands beside
  her. SELECT toggles it, one change per press. No text, no menu.
- **Power-on is one player.** Console RESET keeps the count, as a
  period game variation does.
- **Two players** start with joystick 1 on Stella and joystick 2 on
  Alex. Each moves, jumps and uses portals and rifts with their own
  stick. DOWN+Fire takes the one character nobody holds (0+1+2 = 3, so
  it is 3 minus the two held). Both held characters have wide eyes,
  full colour and a fast-blinking home lamp.
- **One player** is unchanged: DOWN+Fire cycles all three, and the two
  you don't hold always alternate at 30Hz (the rule from `82133b8`).

**Sprites in two-player mode.** #19's partition comes back, for two
players only. Of the three pairs, the first that separates vertically
shares P1 (hopping mid-frame) and the odd one out gets P0. Pairs are
tried so the odd one out is joystick 1's character, then joystick 2's,
then the free one. When no pair separates (all three level), the frame
falls back to the one-player look. In the harness soak, 70% of
two-player play frames draw everyone solid. `tools/picture.py`
renders frames from the ROM's own TIA writes, and shows Stella, Marcus
and Alex all solid in consecutive frames.

**RAM: one byte.** `Active2` is joystick 2's character, `$FF` for one
player, so the player count costs nothing extra. Fire and UP
edge-detection share `FirePrev` and `UpPrev`: bit 7 for joystick 1,
bit 6 for joystick 2. `Pad`, the joystick being read, is an alias of
the hop byte `P1Nu2`, because input finishes before `PrepSprites`
refills it. 118 bytes declared, 4 spare.

**The frame budget moved, and every play frame is now 262 lines.**
Reading two joysticks plus the sprite prep needed about 35 of
vertical blank's 41 lines, while overscan's 23 sat idle. Even one-player
play ran 263-280 lines on a quarter of frames once the input loop went
in. So vertical blank now reads the sticks and preps the sprites, and
overscan, after the kernel, runs physics, the goal check, sound, the
portal and rift blinks and the clock. Each frame still shows input and
physics one step old. The old fault (about 2% of play frames at
263-265 lines) went with it: 0 of 6,400 play frames are off in the
harness, in either mode.

**Cost:** bank 0 is down from 371 free bytes to 70. Act 4 will need
bank 0 room found, or code moved to bank 1 (2.4K free).

**Checked by `make headless`:** one player, joystick 2 never takes a
character and P1 never hops; SELECT toggles once per press and back;
the count survives RESET; two players start on Stella and Alex; each
stick moves only its own character; DOWN+Fire takes the free one, from
either stick; and in a two-player soak the two never hold the same
character. The harness's late-line report now lists only lines inside
the kernel. It used to sweep in vertical-blank WSYNCs from any frame
with a late line.

## 48. Game 2: Every Frame 262 Lines

**Status:** Accepted (2026-11-26). Closes the frame-length faults #45
measured; #47 already fixed play.

**What was wrong, and the fix:**
- **Title and narration ran 263 lines, every frame.** In both, one WSYNC
  landed after its line had ended, which costs a whole extra line. On
  the title it was the first line of the gap under the logo: the
  playfield clear ran before that WSYNC, behind the logo's last line.
  It now runs after it, still before the first visible pixel. In
  narration it was overscan's opening WSYNC: the text's last line plus
  the return and call already reach the next line. Narration now skips
  that WSYNC (`AnnexOverscanNow`); the title, whose last line ends
  early, keeps it.
- **Screen changes ran 276-292 lines.** Leaving the title or a
  narration, bank 0 set up the opening or loaded the floor between
  frames, outside any timer. Two one-frame states now do it inside a
  frame's vertical blank: `STATE_OPEN` (the title's fire) and
  `STATE_LOAD` (the next floor). `Bank0Entry` is now just `MainLoop`.
- **The end-of-floor pause's last frame was 50 lines.** When the pause
  handed over to narration, the frame skipped the kernel. Every bank-0
  frame now draws the game kernel, that one included.
- **The clock running out** reloaded the floor inline. Since #47 that
  happens in overscan, after physics, where both don't fit. It now
  sets `STATE_LOAD` and the next frame reloads.

**Checked:** `make headless` reports no warnings. The frame-length,
late-line and logic-budget checks were warnings while the faults were
known; they are now hard checks, so a regression fails the build. A new
check runs a timed floor's clock to zero and sees it start over through
`STATE_LOAD`. Console RESET frames are still excluded: RESET restarts
the machine mid-frame by design.

**Cost:** none. Bank 0 gained 20 bytes (90 free), because the kernel
choice and `Bank0Entry` got simpler.

## 49. Game 2: One Colour per Character in Play

**Status:** Accepted (2026-11-26). Amends #27's "Active is +2" for play;
#27's palette, luma order, lamps and shape echo are unchanged.

**What was wrong:** #27 gave a held character its bright colour and a
free one its colour two luma steps darker. In one player that step never
reached the screen: the free pair flicker on P1, and flicker tenants were
lifted +2, back onto the bright colour. Two players (#47) exposed it
twice:
- **The free character drew solid in its dim colour.** Dim Marcus ($82)
  all but vanished on the dark home blocks.
- **A held character sharing P1 in a level frame was lifted past its
  colour.** Alex's $CE + 2 = $D0: hue $D at luma 0, a dark wrong colour.
  Stella and Marcus drew $3A and $86, off the series palette.

**Decision:** in play every character draws in its own colour
(`ColBriTbl`), held or free. "This one is free" is carried by the eyes
(the squint, #47) and, in one player, by the flicker. The dim table now
only serves the waking opening, where Marcus is asleep. `CharColor` is
gone and `FillP1` lost its lift.

**Checked:** the harness records every sprite colour write; in play and
in the end-of-floor pause every one must be $38, $CE or $84. The
previous build fails that check with $36, $3A, $82, $86, $CC and $D0.

**Cost:** none; bank 0 gained 34 bytes (124 free).

## 50. Game 2: Floor 9 Proves Its Way Back

**Status:** Accepted (2026-11-26).

**Question:** floors 8 and 9 printed identical solver figures. Is one a
copy of the other?

**Finding:** no. They share their geometry with worlds A and B
exchanged: floor 8 has the stairs in A and the homes in B, floor 9 the
homes in A and the stairs in B. The solver's reach is over both worlds
together, so the figures match. What floor 9 is for — "a door you may
owe two crossings" — the solver never checked: `swapboth` only proves
that neither world alone is enough, which is true of both floors.

**Decision:** the dual-world solver can cap the number of swaps. A new
`return` mode proves that one swap from world A gets at least one
character short of home. Floor 9 is now `swapboth+return`, and every
swap floor prints who needs the return: nobody on floors 7 and 8;
Stella and Marcus on floor 9 (Alex's home is the perch both worlds
share, so one crossing is enough for him).

**Cost:** solver only; the ROM is unchanged.

## 51. Game 2: Room for Act 4 — the Annex Takes Jobs

**Status:** Accepted (2026-11-26). Act 4 is two floors (the seam, then
where they meet), and Game 2 gets endless mode and the run clock. Bank 0
had 124 bytes free, and the floors alone need about 270.

**The constraint:** the picture is drawn from bank 0, and the kernel
reads the floor records directly, so floors must live in bank 0. Bank 1
(the annex) already held the title and narration, but only as whole
frames: bank 0 handed the frame over and took it back.

**Decision:** bank 0 can now call bank 1 mid-frame. The stubs already
had an unused call-and-return pair (GoCopyB, from the world-swap
prototype), so this costs no stub bytes. It is now `GoAnnex`: bank 0
loads Y with a job and calls it; bank 1's `AnnexJob` runs the job, which
ends `jmp GoBackBank0`. The bank switch overwrites A, so a job answers
in X. A job can't call bank-0 routines; bank 0 keeps those calls and
asks the annex again. Moved:
- **The waking opening's phases** (black, sky, eyes, Stella's fall,
  Alex sliding in). They only touch RAM. Bank 0 keeps the calls to
  `LoadFloor`, physics and `PrepSprites`.
- **The sound engine.** It reads RAM and writes the sound registers,
  nothing else, and the second sound voice can now grow in bank 1.
  Its exits jump back instead of returning, so the stack is no deeper.

**Checked:** the A/B harness ran the new ROM against the old for eight
6,000-frame runs of random input: RAM and all six sound registers are
identical frame by frame, except two scratch bytes (`Temp`, `CYH`) that
hold the address of a floor record's plane, which moved down with the
code. A new check plays the opening untouched: all five phases in
order, floor 1 after 294 frames (as before), every frame 262 lines. The
stack is still 6 bytes deep at most.

**Cost:** bank 0 went from 124 to 459 bytes free; bank 1 from about
2,120 to 1,979.

## 52. Game 2: Endless, Its Score, and the Run Clock

**Status:** Accepted (2026-11-26). Game 1's endless game and run clock
come to Game 2, with one addition: the endless score shows floors
survived *and* time survived.

**What a player sees:**
- **SELECT on the title steps through four games:** one player, two
  players, endless with one, endless with two. The figures under the
  title show the player count, as before. The endless games turn the
  title sky ember, which is how Game 1 marks its endless game.
- **The endless game** skips the opening and the narration. Each floor
  is drawn at random from all nine, never the same one twice running.
  The clock starts at 45 seconds and loses two a floor, never going
  under 12 (Game 1's numbers). When it runs out, the run is over.
- **The run clock** counts every second played, timed or not, from
  floor 1 to the end.
- **The score screen** follows the story's last narration, or the end
  of an endless run. It uses Game 1's six-character digits: the story
  shows its time (`  312 `), the endless game its floors and time
  (`14 312`), over black or the ember sky. Fire returns to the title
  after a one-second beat, and the chosen game survives console RESET.

**RAM:** one byte. `Mode` holds the endless flag, the player count and
the floor count (bit 7, bit 6, bits 5-0, the count stopping at 63).
RESET passes it in Y, as it passed `Active2` before. The run clock's
low byte is the opening's phase byte, which is dead once the opening
hands over; that is when the clock is zeroed. The floor clock no longer
needs its own on/off byte: an untimed floor keeps `TimerSec` at `$FF`.
Spare RAM went from 4 bytes to 3. A clock "second" is 64 frames, as the
floor clock's is.

**Found on the way:**
- **Game 1's digit routine has a latent fault.** With VDEL on, P1 shows
  a delayed copy that only a `GRP0` write updates, and the routine
  clears `GRP0` before `GRP1`, so P1 keeps the last row of the sixth
  character. Game 1's sixth character is always blank, so it never
  showed; `14 312` ends on a digit and drew three white stripes down
  the screen. The routine also returns after its line has ended, so
  its next WSYNC lands late. Both are fixed in Game 2's copy, and the
  picture renderer now models VDEL, which is how the stripes showed.
- **The harness rounded frame lengths.** It divided a frame's cycles by
  76 and rounded, so a 262.54-line frame read 263 and a 262.45-line one
  would read 262. It now counts scanline boundaries between VSYNCs,
  which is what the TV sees. That exposed three handovers that really
  were 263 lines: the frame after console RESET (start-up now ends on a
  WSYNC), the last narration into the score (it now jumps there
  directly), and the narration into the next floor. Bank 1 now hands
  frames back past bank 0's check of which bank a state belongs to,
  which is never needed on that path and cost the time it didn't have.
  Every frame writes VSYNC at cycle 38-42 of its line; across a long
  random run the latest any screen change writes it is cycle 65.
- **The opening's last frame** loaded floor 1 as well as running the
  opening's physics, and ran to 263 lines. It now goes through
  `STATE_LOAD`, like every other screen change.
- **The level checker's table-length test** could not tell bank 0's
  labels from bank 1's (both banks sit at `$F000`) and had been
  comparing against both. It now reads which labels the source puts in
  bank 1, including its include files.

**Checked:** a new endless test plays nineteen floors and checks the
clock (45, 43, … 13, 12, 12), the count, that no floor repeats back to
back, that six or more different floors come up, that no narration
appears, that the count stops at 63, and that the run ends on the
score and returns to the title. The walkthrough now ends on the score
and checks the run clock against the frames played. SELECT is checked
through all four games and across RESET. Every frame of all of it is
262 lines.

**Cost:** bank 0 went from 459 to 387 bytes free; bank 1 from about
1,980 to 1,307 (the digit font is aligned so it never crosses a page).

## 53. Character Physics Across the Series: Pass Through, Then Touch

**Question:** Characters can land on each other, but they walk through
each other from the side, and a rider is never carried. Is that right?
What should happen when the one underneath moves, and when does the
series let bodies touch?

**The rule today (Games 1 and 2), now written down:** a friend's head
is a **one-way platform**, exactly like the one-way ledges. You land on
it from above; from below and from the side you pass through. Nobody is
carried: when the one underneath walks away, the rider stays where they
are and drops (#29: "stand on a friend, and if the friend walks away,
you fall").

**Why it stays that way in Games 1 and 2:**
- The solver proves every floor treating friends as surfaces, not
  walls. Solid bodies would make it search all three characters moving
  together, and every proof would have to be redone.
- With two players (#47), solid bodies let one player block another in
  a gap one body wide.
- Game 1 is finished and proved; Game 2's floors are proved.
- The honest objection, recorded: #17 made the world's collision honest
  ("boxes span exactly what they draw"), and characters are honest only
  from above.

**Decision (author, 2026-11-26):** **bodies bump in Game 3**, as the next
step of the awareness arc (#23): Game 1 is blind, in Game 2 they see each
other, in Game 3 they *feel* each other. More memory, more alive.

The condition is that it is **discoverable**, never a silent change.
Pass-through is something players have learned, and #29's amendment
forbids contradicting a learned rule without a channel to announce it.
So Game 3 must teach it wordlessly:
- an early room where a friend stands in the only corridor, so the
  first thing the player does with a friend is walk into them and stop;
- the eyes react to the touch (Game 3's eyes were already planned to
  track and react, #23), so the bump reads as contact, not as a wall;
- a narration line can name the moment after it happens, never before.

**What bumping means, and what it doesn't:**
- **Sideways, bodies block.** To get past a friend you jump on or over
  them, or switch to them and move them. (Pushing a friend along is not
  decided; blocking is the simpler rule and the easier one to prove.)
- **Still no carrying for ordinary friends.** Standing on Stella, Alex
  or Marcus works as it always has. Carrying stays Flicker's gift (#29):
  a stack with Flicker in it fuses into one body.
- **A fused stack meets an overhang as one shape.** It doesn't scrape a
  rider off; it simply doesn't fit, and which characters are in the
  stack, in what order, decides what fits (#29). The expected scrape-off
  rule (a wall stops the rider, the base moves on, the rider drops) only
  matters if a later game adds a carrier that isn't a fusion.

**Consequences for Game 3:**
- The solver must model bodies that block: joint positions where they
  matter. It runs on a PC, so the search can grow; the 16K cartridge
  only has to run the rule. This is real work, accepted.
- Two players can now block each other. Rooms should give a way round,
  or make blocking the point.
- Open for Game 3's design: whether a bumped friend can be pushed, and
  whether two-player mode keeps bodies solid.

## 54. Game 2: Floor 10, "The Seam"

**Status:** Accepted (2026-11-27). Act 4's first floor, made harder
at the designer's request: Alex can only get home on Stella's head.

**The floor.** Every verb meets at the screen's edge. The wrap joins
x=0 to x=160 there, the rift stands there, and in world B a pair of
doors stands beside it (world A has none). All three homes are in
world B: Stella on the seam ledge's right piece (40), Marcus on a
centre ledge (56), Alex on a high ledge (16) he cannot reach alone or
from world B at all. He swaps back to world A on the seam ledge,
climbs Stella onto world A's ledge at 24 (a stepping stone, nobody's
home), climbs her again where that ledge runs through the rift, and
swaps from her head. The floor turns over: he lands home, and Stella
drops from under him onto hers. The solver (`swap+seam+coop+return`)
proves everyone home in world B, nobody home with the doors or the
swap taken away, Stella and Alex not home without the wrap, Alex not
home alone or in one swap, and 52/38/114 ways in. The harness plays
the boost, and the door rules, in the ROM. Narration: "IT WAS / ONE
DOOR."

**Engine.** Doors and rifts share a floor for the first time:
- Doors are true only in world B (ReadPortal checks CurWorld). In B a
  press that misses the doors is left for ReadRift; one that hits a door
  is spent on it (the door wins where they overlap).
- The doors stand in PF0 beside the rift, so world B has its own PF0
  pair after the record (ON +126, OFF +138). BlinkRifts picks it and
  blinks doors and rift together; BlinkPortal leaves rift floors alone.
- `MulNine` became `MulFloors` (stride NUM_FLOORS).

**The solver was wrong twice, and the first layout shown could not be
finished.** It proved each character on its own. But SwapWorld flips
the floor for everyone, and CheckGoal wants all three home at once, so
a floor finishes only in a world where every home is standable; the
first layout had Stella's home only in B and Marcus's only in A.
`survey_dual` now judges every character in one shared finishing
world. And a friend's head was only counted where the friend could
walk without doors or swaps, so no boost on a door-reached ledge could
ever be found; helpers now take their footing from their own two-world
search. Floors 1–9 still prove under both.

**Found on the way: a vertical-blank overrun on floor 5** (two
players, both moving, on its four walls), in the shipped ROM too. The
soak used to jump floors by writing FloorSeq without loading the floor
(it now goes through STATE_LOAD), which hid it and then, on floor 10,
produced a frame no game can reach. Overscan has only 2 ticks to
spare, so the fix is cheaper code: ClampBoxes now visits only the
solid boxes. Every record already lists the ground first, then its
solid boxes, then the one-way ledges, so a 10-byte `FloorSolidN` table
gives the count, and check_levels.py audits the order in both worlds.
Vertical blank now keeps at least 5 ticks spare. The endless test also
finishes floors after a seeded, varying time, so it tests the picker
rather than the harness's fixed rhythm.

**Cost:** bank 0 has 169 bytes free (from 387): the record is 150
bytes, the tables and code the rest.

*Corrected by #55:* with mid-air steering in the solver, Marcus can't
get home alone either. The floor proves with Alex, then Marcus, then
Stella, who comes home last and alone. Its ways in are now 202/46/80.

## 55. Game 2: The Solver Learns to Steer in the Air

**Status:** Accepted (2026-11-27).

**The bug.** ReadInput reads the stick on every frame, in the air too,
so a player can turn round or stop mid-jump. The solver held one
direction from take-off to landing. Anything it called unreachable
might still be reachable by steering, so every "can't" proof was
unsound. A ROM test found one: on a draft of floor 11, Stella stepped
off a ledge, steered back under, and landed on a home the solver said
she could never reach. A second bug pointed the other way. `arc`
worked out Marcus's frame parity once and never flipped it, so in the
air he moved 2 px a frame, not 1.5, and the solver gave him reach he
doesn't have.

**The fix.** `Char1.lands` follows every steering choice (left, none,
right) on every frame of a fall or jump. Bodies at the same height and
speed are grouped, so the search stays tractable. Parity flips every
frame. Walking off a ledge, jumping, landing from a door, and landing
from a swap all go through it. A full `make` now takes about 3 minutes.

**What changed.** Floors 1-9 still prove, with new margins. Floor 10
didn't: it had only one solo finisher, and the coop rule asked for
two. That rule was a stand-in for the real question: can the three
finish in some order? Friends who are already home can't come back out
to boost. `booster_order_dual` asks that question directly. Someone
has to get home using only friends who are still out, and the last
one home has to get there alone. Floor 10 passes: Alex, then Marcus,
then Stella.

**The sky moved to the annex.** BuildSky's body, its two ramps, and
FloorSkyTbl are now bank 1's `JOB_SKY`. Bank 0 keeps a three-byte stub.
That frees 86 bytes for the finale (bank 0: 255 free). Frame timing is
unchanged (vertical blank at least 5 ticks spare, overscan 2).

