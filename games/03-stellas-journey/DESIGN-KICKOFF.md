# Stella's Journey design kickoff

**Game 3 of 4 · 16K ROM · F6 bankswitching · kickoff 2026-11-28**

Nothing is built yet. This document records what the author settled on
2026-11-28, what is still open, and what to prototype first. The decisions
log, `docs/decisions.md`, stays the authority. Where this document changes
an earlier decision it says so, and the log gets an entry once the change
has been tried in a ROM.

## What the game is

Four shapes travel through a world that is failing. The rooms are taller
than the screen, and the world is many rooms wide. Partway through they
meet Flicker, a circle that is only there every other frame. Flicker can
pass through the corruption that throws the others back, and it can take
a friend with it. At the end Flicker stays behind so the others can leave.

## Settled on 2026-11-28

### The three get no new abilities

The creative brief gave each of them an upgrade. Stella clings to walls,
Alex slides under barriers, Marcus bounces others higher. That line is
dropped.

Two of the three are things they already do. Stella is the tallest and
jumps the highest. Alex is flat and already goes under what stops the
others. Marcus does not boost anyone. His feature, from #21, is a medium
jump that fits under a low ceiling. Any head is a step up, and has been
since Game 1's room "Boost", so the boost belongs to everyone.

The fourth character is the new ability. This also keeps the rule from
#29's amendment: a new game adds to what the player knows and never makes
it false.

### New moves come from Flicker and from touch

| Move | Who | What happens |
| --- | --- | --- |
| Ride | Anyone on Flicker | Flicker carries its rider. Nobody else carries. #29 |
| Phase | Flicker, and any stack with Flicker in it | The stack passes through corruption as one body. Its outline has to fit the gap. #29 |
| Block | Everyone | Bodies are solid sideways. A friend can be a wall, or be in the way. #53 |
| Hold | Everyone, and some switches only Flicker | A switch stays on while someone stands on it. #34 |

Nothing is picked up and nothing is unlocked. Each move is taught by a
small room that can't be passed without it, one failure per character,
as #21 and #29 describe. The narration tells the story and never explains
a move.

### The corruption is the unstable barrier

The hazard and the thing Flicker phases through are one substance. A solid
character who touches it goes back to the last lamp they reached. Only
that character goes back. Everyone else, every switch and every gate stays
as it was. Flicker and its riders pass through.

This is the first cost to failing in the series. It is small on purpose.
Sending the whole room back would punish three characters, or a second
player, for one character's mistake.

### Rooms are tall, the world is wide

- A room is two or three screens high. The view scrolls up and down and
  follows the character you control.
- Rooms join sideways through gates. Going through a gate flips to the
  next room. There is no sideways scrolling.
- On entry the view pans from the homes down to the cast.
- A character can stand on their home out of view. A thin line in their
  colour at the top or bottom edge shows which way they are.
- A hole drops you to a lower part of the room. You climb back.

This settles the disagreement between #18, which says the world scrolls,
and #34, which says rooms and no scrolling. Both were half right.

The reasons are the hardware's. The picture is drawn a line at a time, so
starting the drawing further down the room is cheap, and *River Raid* did
it in 1982. Sideways is a different matter. The background is 40 blocks,
each four pixels wide, and this engine mirrors the left half onto the
right, per #20. A sideways scroll would lurch and would scroll both halves
towards each other.

*Adventure*, 1980, is the model for the wide part. It never scrolled. It
felt large because rooms joined edge to edge the same way every time, and
because things stayed where the player left them. Game 3 gets the second
half of that from switches and gates that stay as they were set.

### Going back is a move

The author accepted on 2026-11-28 that players will touch corruption on
purpose to get back to a lamp. It is allowed. The solver treats it as a
legal move, so every shortcut it opens is proved and none is an accident.

### Two players share one view

With one player there is one held character, or one stack, and the view
follows it. Everyone else stays where they were left, in view or out.

With two players:

- The view holds both held characters. It scrolls to keep them both in,
  and stops when they are a screen apart. Whoever is ahead waits at the
  edge of the view.
- Characters nobody holds can be anywhere. A character standing on its
  home in another part of the room stays there, and the players can
  travel back to it together.
- DOWN+Fire takes the next free character that is in view. If none is in
  view, the player lets go and holds nobody. A player who holds nobody
  does not pin the view, and takes a character again with DOWN+Fire when
  one is in view.

- In a fused stack any member can drive, #29. If both players hold a
  member, the lowest held member drives. Settled by the author on
  2026-11-28.

Letting go is what makes every one-player route playable by two. Without
it, a climb that only one shape can make would pin the pair for good.
Game 2's rule, DOWN+Fire takes the one nobody holds, #47, is the base.

### Rooms from Games 1 and 2 come back, larger

An old room can be one screen of a taller room. The player recognises the
screen, the view moves, and there is more above or below it than they
ever saw. The level data is already in the format the engine draws.

### Flicker is the hero, and the ending is the player's to perform

The last gate stays open only while Flicker holds its switch. The player
walks the other three out, in their own time. The game does not hurry
them and does not do it for them. The solver has to prove there is no way
out for all four.

A short epilogue is played with three. Corruption that a stack could once
cross is a wall again.

### Paddles and four players wait for Game 4

Game 3 uses joysticks, one or two players. Four paddles would give four
players, one per character, and Game 4 is the place for that. Reading the
paddle knobs takes time inside the drawing loop, and Game 3's drawing
loop already has a fourth sprite to find room for.

## How the corruption looks

It has to read as different from a door and from a rift, at a glance and
without relying on colour. #27 requires that. Game 2's doors are thin grey
columns that blink, and its rifts are thin grey beams that blink.

| | Door or rift, Game 2 | Corruption, Game 3 |
| --- | --- | --- |
| Shape | A thin line | A filled area, as wide as a wall or a floor |
| Motion | Blinks, all on then all off | Static. The pattern changes every frame |
| Colour | Grey | A hue. The first colour that is nobody's, #27 |

Shape and motion carry the difference. Colour confirms it.

The brief already describes it this way: "Static, where platforms should
be." Static also looks like Flicker's blink spread over a wall, which is
the story. Flicker is made of the same stuff and that is why it can pass.

Open: do doors and rifts appear in Game 3 at all? My recommendation is
that a gate between rooms uses the door's look, since the player has
already learned it, and that rifts stay in Game 2. The two-worlds idea
belonged to the two-bank cartridge.

## A glimpse of Game 4

The brief has a place for this. Beyond the corruption the cast sees "vast
structures of light" they can't read, and Game 4 makes them legible.

The author's idea is to show weather they can see and not touch: water,
snow, wind. My recommendation is one image, **static that falls.** Inside
Game 3 the specks of corruption jump at random. Past the last gate the
same specks all fall the same way, slowly. Disorder has become weather.
Direction reads from the motion alone, so no arrow is needed. Falling is
snow. Rising would be wind.

Where to put it, safest first:

1. On the closing screen, where no characters are drawn and every TIA
   object is free. Game 1 did this with Marcus's square, #15.
2. In the last room, above the highest point any body can reach. #36
   makes that scenery, and the solver must prove it is out of reach.

Take the first, and add the second if the drawing loop has room.

#15 turned out to bind two games together. Game 2 opens on the screen
Game 1 closed on. The same should hold here. Game 4 opens on the falling
static, and then the cast walks into it and it pushes them.

Water, currents and ice as things the cast interacts with belong to
Game 4, where the brief says the world "turns fluid". Each shape can
answer them differently, which gives Game 4 new moves without a fifth
playable character, #30.

Open: whether the glimpse is in colour. Game 4's world has colour
everywhere, per #27, so a pale blue-white here would be the first colour
that is neither somebody nor something wrong.

## RAM

Game 2 ends with three bytes spare, so the budget is the first thing to
plan. State packs into bits.

| What | Bytes |
| --- | --- |
| Flicker's position, speed and flags | about 5 |
| The view's position in the room | 1 |
| A room's switches, eight to a byte | 1 |
| The world's gates, 32 of them | 4 |
| Last lamp reached, two bits a character | 1 |

About twelve bytes. Game 2 spends twelve on its sky table and twelve on
its lamp colours, and Game 3 can read at least the sky from ROM.

The Superchip variant of F6 puts 128 more bytes of RAM on the cartridge.
Atari shipped it in 1983 and 1984. It stays in reserve, and its details
need checking before anyone relies on it.

## How rooms get proved

Game 2's solver searches one character at a time and treats friends as
steps. Blocking, fused stacks and held switches depend on where everyone
is at once, so that shortcut is gone. Four characters searched together,
pixel by pixel, is trillions of states. The plan, agreed in outline on
2026-11-28, has three speeds.

1. **While designing, seconds.** The solver finds one order of moves that
   finishes the room, and the harness plays it in the real ROM. That is a
   full proof that the room can be finished. It also runs the cheap
   blocker checks: a model with more reach than the game has still can't
   pass the barrier without the move the room teaches.
2. **Before a release, minutes to hours.** An exhaustive search over
   zones, where a zone is a stretch of ledge on which nothing differs.
   It answers what one route can't. Is there a state the players can
   reach and never finish from? Is there a way round the lesson? In the
   last room, is there a way out for all four? Every zone step it uses
   is checked against the exact physics.
3. **Play-testing, by people.** For what no search can judge. Can a
   player find the answer, and is it any good to play? Game 2's solver
   says it in its own header: solvable is not findable.

The exhaustive search wants a fast language and many processor cores, and
a graphics card is the wrong tool for it. A search like this is mostly
remembering which states it has seen, which is memory and branching, and
graphics cards are built for the same sum done millions of times.

Gates keep all of this affordable. Each room is proved alone, with a few
bits carried between rooms, so the cost adds across rooms.

The method may be worth sharing once Game 3 has tested it: physics read
from the built ROM, a build that fails when a room can't be finished, and
a harness that plays the cartridge without a screen. Decide after Game 3.

## Open questions

1. **A player who holds nobody.** The two-player rule above needs it.
   Whether waiting with empty hands is dull has to be played to find out.
2. **Size.** The README says 12 to 15 levels. Tall rooms change the unit.
   Eight to ten rooms of two or three screens is 20 to 30 screens, against
   Game 2's eleven.
3. **Does Flicker thin?** Flicker could show less often as the game goes
   on, one frame in two and later one in three. It would foreshadow the
   ending. It may also be unpleasant to control.
4. **Pushing.** Bodies block. Whether one can shove another is not
   decided. I recommend no. It multiplies what the solver must search.
5. **The form of home**, still open from #31.
6. **How the four banks are used.**

## Prototypes, in order

Each is a small test ROM, built before any room is designed.

1. **A tall room with four characters.** Vertical scrolling and the
   fourth sprite in the same drawing loop. This is the riskiest piece, and
   #29 says to prove Flicker's blink early.
2. **A fused stack through corruption.** Stack detection, the stack's
   outline, and what happens when a stack breaks up inside the corruption.
   #29 calls that last case the ending.
3. **Bodies that block**, with a solver that can prove a room using them.
   The solver today moves one character at a time and treats friends as
   ledges. Floor 11 of Game 2 showed what that costs.
4. **A gate and a switch** between two rooms, with the state kept.

## What carries over from Game 2

- The band-by-band drawing loop, the mirrored playfield and the per-band
  colour table.
- Place and hold as the goal, #26, and the lamps.
- The proof tools: `check_levels.py`, `headless.py`, `picture.py`.
- The annex pattern, where one bank calls jobs in another.
- The two-voice music engine, and the family of notes that are in tune.

## What this changes elsewhere

Not edited yet. These wait for the author's go-ahead.

- `docs/creative-brief.md`, Game 3 story beat 1 and the "Enhanced
  abilities" line.
- `games/03-stellas-journey/README.md`, its first paragraph and its
  mention of four bank states.
- `docs/decisions.md` #18, the Game 3 line, and a new entry for this
  kickoff.
