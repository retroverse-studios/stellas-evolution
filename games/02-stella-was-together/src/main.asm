; ---------------------------------------------------------------
; Stella Was Together — game 2 of 4, Stella's Evolution
; Atari 2600, 8K ROM, F8 bankswitching (2 x 4K banks)
;
; THE REAL GAME SKELETON (grown from the game2-workbench tag).
;
; The workbench's proven engine is KEPT — three-character physics
; with the active->P0 colour scheme, the P1 multiplexer, wrap edges,
; per-colour goals, and the F8 two-bank world-swap plumbing. What was
; REMOVED is the pile of SELECT-cycled prototype TEST floors (the
; Meeting Place sandbox, the world-swap floors T1/T2/T3, the wrap
; floor W1, the portal floor P1, the wrap+portal floor WP1). Those
; floors — and the full portal / world-swap verb implementations they
; exercised — live safely in the `game2-workbench` git tag; future
; acts re-attach them to the floor framework below.
;
; The real structure this file builds:
;   * the ANNEX (bank 1): the TITLE (decision #28: the big STELLA mark
;     in the neutral ramp on the dusk gradient, the game's one word
;     beneath — no menu, fire starts) and the NARRATION screens (Game
;     1's text kernel + tools/gentext.py). Neither state ever shares a
;     frame with play, so both live in bank 1; MainLoop's top hands
;     them the frame and Bank0Entry receives it back;
;   * the WAKING-MARCUS opening (bank 0, game kernel): Game 1's
;     epilogue — black screen, the small blue square — that the world
;     assembles itself around. Fire skips it;
;   * floors that play IN ORDER, walked from a clean FLOOR TABLE
;     (record + home table + wrap flag + sky base + narration id +
;     lamp bands + portal/rift columns);
;   * ACTS 1-3 COMPLETE (decision #18's ladder, one verb each, verbs
;     accrete):
;       Act 1 wrap (always-on): F1 "Together Again" (the boost), F2
;         "The Low Door" (Marcus's gift, #21), F3 "The Wall" (the wrap
;         twist);
;       Act 2 portal (UP in a blinking column teleports to its mouth):
;         F4 "The Fold" (locked room), F5 "The High Door" (boost gates
;         the door), F6 "The Cross" (the doors cross the screen);
;       Act 3 world-swap (UP grounded in a thin rift beam swaps which
;         truth the room is in — the sky reverses as the tell): F7
;         "Two Truths" (the approach ladder is only true in B), F8
;         "The Handoff" (neither world alone suffices), F9 "The Way
;         Home" (the stairs are in B, the homes in A: swap back).
;   * boot flow: title -> wake-up -> floors 1-9 (each followed by its
;     narration) -> back to the title.
;
; Adding a floor is: one row in each Floor* table + one record (with
; its OFF plane, and world-B pages for dual floors) + one Floor?Home +
; one narration string in tools/gentext.py's SCREENS + one FLOOR_DEFS
; row in tools/check_levels.py. Act order (docs/decisions.md #18):
;   Act 1 = wrap (the always-on baseline), Act 2 = portal, Act 3 =
;   world-swap, Act 4 = finale. Wrap is on for every floor.
;
; F8 in one breath: the 6507 sees a 4K window at $1000-$1FFF (mirrored
; at $F000-$FFFF, how this file addresses it). Touching $1FF8 maps bank
; 0; $1FF9 maps bank 1. The swap is instant, so any code that runs
; across a switch must be byte-identical at the same address in both
; banks — the trampoline stubs at the top of each bank. Bank 1 keeps
; that stub set (the world-swap capability's architectural core) so the
; 8192-byte F8 layout stays honest; its floor data lives in the tag.
;
; Engine code: MIT (see repository LICENSE).
; Story/characters: CC BY-NC-SA 4.0 (see repository LICENSE-DOCS).
;
; Controls (Game 1 conventions, decision #22):
;   Left/Right  move the active character
;   Fire        title: start ; opening: skip ; narration: continue ;
;               in play: jump
;   Down+Fire   cycle Stella -> Alex -> Marcus
;   SELECT      on the title: one player, two, endless one, endless two
;   RESET       return to the title
; ---------------------------------------------------------------

        processor 6502
        include "vcs.h"

; ---------------------------------------------------------------
; Constants. The 192 visible scanlines are 96 double-lines ("du");
; all vertical positions/physics are in du with 8.8 fixed point,
; exactly as in game 1.
; ---------------------------------------------------------------

BANK0HOT    = $FFF8     ; F8 hotspots ($1FF8/$1FF9 mirrored):
BANK1HOT    = $FFF9     ; reading either one swaps the 4K window

; --- game states -----------------------------------------------
STATE_TITLE = 0         ; rainbow logo, fire to start
STATE_PLAY  = 1         ; a floor is being played
STATE_STORY = 2         ; a between-floor narration screen
STATE_WAKE  = 3         ; the waking-Marcus opening (game kernel)
STATE_DONE  = 4         ; floor complete: the beat before the narration
STATE_LOAD  = 5         ; one frame: load floor FloorSeq, then PLAY
STATE_OPEN  = 6         ; one frame: set up the opening, then WAKE
STATE_SCORE = 7         ; the run's numbers (annex), fire for the title
                        ; (both do their setup inside a frame's vblank,
                        ; so a screen change is a 262-line frame too)
                        ; (game kernel — decision #26's closing image is
                        ; all three standing home together, so the game
                        ; holds on it instead of cutting to text)

; --- floor sequencing ------------------------------------------
NUM_FLOORS  = 9         ; Act 1 (wrap):   Together Again / The Low Door
                        ;   / The Wall
                        ; Act 2 (portal): The Fold / The High Door / The
                        ;   Cross
                        ; Act 3 (worlds): Two Truths / The Handoff /
                        ;   His Own Truth

; --- wake-up opening timing (frames) ---------------------------
WAKE_BLACK  = 80        ; phase 0: black screen, Marcus alone
WAKE_EYES   = 70        ; phase 2: eyes open before Stella arrives
JOB_WAKESETUP = 0       ; annex jobs (GoAnnex, Y = job; decision #51)
JOB_WAKEPRE   = 1
JOB_WAKEPOST  = 2
JOB_SOUND     = 3
JOB_NEXTFLOOR = 4       ; endless: count the floor, draw the next one

; THE WORLD IS GREYSCALE; COLOUR MEANS AGENCY (decision #27).
; Hue 0 is the neutral ramp, so every hue on screen belongs to
; something with a will: the three characters, and their home lamps
; (a home is a character's intent). The world itself is inert and grey.
; Two channels, two jobs, and neither asks the player to tell red from
; green: colour answers "is this an actor?", the luma ladder answers
; "which actor?".
;
; Luma budget. The characters occupy six of the TIA's eight levels
; (Marcus 2/4, Stella 6/8, Alex C/E), which leaves 0 and A for the
; world. So the world takes exactly those: the sky ramps 0 -> 8 (a
; black zenith, Game 1's void, lifting to a grey horizon — the void did
; not get replaced, it grew a horizon), and the platforms sit at A, the
; one level no character ever uses. Every character therefore differs
; in brightness from the ground it stands on, whoever it is.
FLOOR1_SKY  = $00       ; Act 1 sky base; +GradOfs -> luma 0..8
TITLE_SKY   = $00       ; the title shares Act 1's sky
EMBER_SKY   = $20       ; ...or burns ember: the endless game (Game 1's
                        ; ember title, decision #52)
ENDLESS_T   = 45        ; endless: seconds on the first floor, two
ENDLESS_MIN = 12        ; fewer each floor, never under twelve (Game 1)
SCORE_TOP   = 88        ; the score: blank, 15 lines of digits (14 and
SCORE_BOTTOM = 89       ; the clear), blank: 88 + 15 + 89 = 192
PFA_COLOR   = $0A       ; platforms: the one luma no character owns
COL_TEXT    = $0E       ; narration text: white
COL_STELLA  = $38       ; == ColBriTbl (the annex can't read bank 0)
COL_ALEX    = $CE
TITLE_X1    = 66        ; the title's figures: Stella, a 4px gap, Alex
TITLE_X2    = 78

SCREEN_DU   = 96
NUM_CHARS   = 3         ; index 0 = Stella, 1 = Alex, 2 = Marcus
STELLA_H    = 9         ; tall red rectangle: 8px wide, 18 scanlines
ALEX_H      = 3         ; flat green rectangle: 16px wide (doubled)
MARCUS_H    = 6         ; blue square: 8px wide, 12 scanlines —
                        ; a TIA pixel is wider than a scanline is
                        ; tall, so 12 lines is what reads square

EYEROW      = 1         ; the eye row: 1 du below the drawn top
EYES_L      = %10101111 ; two dark pixels toward the left edge
EYES_R      = %11110101 ; ...and toward the right
EYES_LSQ    = %10111111 ; narrowed (idle) variants: the active
EYES_RSQ    = %11111101 ; character is the wide-awake one

GRAV_LO     = $30       ; gravity 0.1875 du/frame^2
MAXFALL     = 3         ; terminal fall speed, du/frame

MIN_X       = 4         ; outer walls are 4px, handled by clamping
NUM_PLATS   = 6         ; collision boxes per level (pad with $FF)

; --- wrap constants (the always-on Act 1 baseline, decision #18) --
; x is taken modulo the 160px screen instead of being clamped. Steps
; are 1px, so NewX only ever lands just past an edge: NewX >= WRAP_HI
; is a byte-underflow off the LEFT edge (add 160); WRAP_W..WRAP_HI-1
; overflowed off the RIGHT edge (subtract 160); below WRAP_W untouched.
WRAP_W      = 160
WRAP_HI     = 200

; Level record layout (66 bytes each):
;   +0  12 bytes PF0 per band     +36  6 bytes box top (du)
;   +12 12 bytes PF1 per band     +42  6 bytes box bottom (du)
;   +24 12 bytes PF2 per band     +48  6 bytes box left x
;                                 +54  6 bytes box right x (excl)
;   +60 SX,SY, AX,AY, MX,MY       (three spawn points)
; A box with top==bottom is one-way; top=$FF is an unused pad entry.

; ---------------------------------------------------------------
; RAM ($80-$FF). Both banks share the one 128-byte RAM — that is
; the whole F8 trick: RAM is the only thing that survives a switch.
; Character arrays: index 0 = Stella, 1 = Alex, 2 = Marcus.
; ---------------------------------------------------------------

        SEG.U VARS
        ORG $80

CharX       ds 3        ; x pixel of left edge
CharY       ds 3        ; y du of top edge
CharYLo     ds 3
CharVYHi    ds 3        ; signed du/frame
CharVYLo    ds 3
OnGround    ds 3
CharFace    ds 3        ; 0 = facing left, 1 = facing right
SquashT     ds 3        ; frames of landing squash left

Active      ds 1        ; joystick 1's character
Active2     ds 1        ; joystick 2's character; $FF = one player
                        ; (SELECT on the title, decision #47). Never
                        ; equal to Active: DOWN+Fire in two-player
                        ; mode takes the one character nobody holds
FirePrev    ds 1        ; fire armed (released): bit 7 joystick 1,
                        ; bit 6 joystick 2
FrameCtr    ds 1
SoundId     ds 1        ; 1=jump 2=land 3=floor fanfare
SoundT      ds 1

PF0Ptr      ds 2        ; -> level record base (PF0 bands)
PF1Ptr      ds 2
PF2Ptr      ds 2
PlatPtr     ds 2        ; -> collision boxes

; --- kernel interface, rebuilt every frame by PrepSprites -------
BandLine    ds 1        ; kernel band countdown
DrawY       ds 3        ; drawn top per character (squash/stretch)
DrawH       ds 3        ; drawn height per character
EyeByte     ds 3        ; this frame's eye row per character
P1Top       ds 1        ; P1's current tenant: top / height / eyes
P1Hgt       ds 1
P1Eye       ds 1
P1XA        ds 1        ; P1's vblank position (first tenant's x)
P1Y2        ds 1        ; P1's second tenant, taken over mid-frame
P1H2        ds 1
P1Eye2      ds 1
P1X2        ds 1
P1Col2      ds 1
P1Nu2       ds 1
Pad         = P1Nu2     ; the joystick being read this pass (GetPad):
                        ; bits 7-4 R/L/D/U, bit 3 fire, bit 0 which
                        ; joystick, all active low but bit 0. Input
                        ; runs before PrepSprites refills P1Nu2, and
                        ; the kernel reads P1Nu2 only on a hop.
RepoDU      ds 1        ; du of the mid-frame P1 hop ($FF = never)
SkyGrad     ds 12       ; per-band sky colors (base + gradient)

; --- physics / logic scratch (also reused by the text kernels) --
PrevFeet    ds 1
NewFeet     ds 1
PrevTop     ds 1
TopV        ds 1
BotV        ds 1

; The game kernel reuses five physics-scratch bytes as its band
; PREFETCH slots (physics runs in vblank, the kernel after it — they
; never overlap). The next band's sky/playfield/lamp bytes are pulled
; in one line early so the boundary line only does zero-page stores,
; all inside hblank — this was the "broken ground" tear: indexed
; loads on the boundary line landed mid-scanline.
KSky        = PrevFeet
KPF0        = NewFeet
KPF1        = PrevTop
KPF2        = TopV
KCol        = BotV
LV          ds 1
RV          ds 1
BoxIdx      ds 1
CY          ds 1
CYH         ds 1
NewX        ds 1
MoveDir     ds 1
Temp        ds 1

; --- state machine + floor sequencing ---------------------------
State       ds 1        ; STATE_TITLE / STATE_PLAY / STATE_STORY
FloorSeq    ds 1        ; index of the current floor in the FloorTable
WrapMode    ds 1        ; per-floor edge mode: 0 = clamp, 1 = screen-wrap
ActiveM1    ds 1        ; physics loop bound (2 = all three characters)
HomePtr     ds 2        ; -> this floor's per-character home-CharY table
PFColor     ds 1        ; initial COLUPF for the floor
PFColPtr    ds 2        ; -> the per-band COLUPF table (home ledge tints)

; --- active->P0 slot: the kernel draws P0 from these, filled each
; vblank from whichever character is ACTIVE, so the player-controlled
; character is always the solid, never-flickering P0. ------------
P0Top       ds 1
P0Hgt       ds 1
P0Eye       ds 1

; --- text kernel interface (Game 1's narration pipeline) --------
TextEnd     ds 1        ; index of the blank byte in each plane
TextTop     ds 1        ; first du of the text block
TPtr        ds 12       ; six playfield plane pointers

; During PLAY the text pointers are dead, so the per-band COLUPF
; table (the "home lamps") overlays them — the decision #24 per-state
; union. PrepSprites rebuilds it every play frame; the fill is gated
; on STATE_PLAY so a floor-completion frame (whose CheckGoal has
; already pointed TPtr at the narration) is never clobbered.
PFColRam    = TPtr      ; 12 bytes, one COLUPF per band

; --- wake-up opening -------------------------------------------
WakePhase   ds 1        ; 0 black / 1 sky builds / 2 eyes / 3 Stella
                        ; drops / 4 Alex slides in
WakeT       ds 1        ; frame counter within the phase

StateTimer  = WakeT      ; STATE_DONE: frames left in the completion
                        ; beat. Shares WakeT's byte: the opening and the
                        ; beat never run together, and each sets its own
                        ; before reading it (decision #46)
UpPrev      ds 1        ; UP edge-detect for the portal/rift verbs,
                        ; bits as FirePrev; SELECT's on the title

; --- Act 3 (world-swap) -------------------------------------------
CurWorld    ds 1        ; 0 = world A, 1 = world B (decision #9's two
                        ; truths of one place). RAM is the whole point:
                        ; the banked copies hold geometry; PEOPLE persist.
RecPtr      ds 2        ; -> this floor's record, fixed at LoadFloor.
                        ; PF0Ptr can't anchor swaps any more (Act 3's
                        ; rift blink repoints it), so swaps and blinks
                        ; both reckon from RecPtr.
                        ; (StoryAfter and StoryId were here. Both are
                        ; FloorSeq in disguise: the narration after floor
                        ; n is screen n, and it is the last one when
                        ; FloorSeq reaches NUM_FLOORS. Decision #46)

; --- the floor clock (decision #22's UI axis, restored) ------------
; Game 1 has a per-level clock and a run clock; Game 2 had neither,
; which made the LATER, roomier cartridge strictly more forgiving than
; the 4K one — the exact inverse of the series' own thesis. Two bytes
; buy the clock back, and the stack still has eight bytes of headroom.
; Two bytes is all it takes: the frame counter is derived from the
; existing FrameCtr, so only the seconds need storing.
TimerSec    ds 1        ; seconds left on this floor; bit 7 set =
                        ; untimed ($FF). (TimerOn was its own byte: the
                        ; switch, sampled at load. Decision #52.)
                        ; (TimeDim was here: a pure function of
                        ; TimerSec, so BuildSky works it out when it
                        ; paints. Decision #46)
RunHi       ds 1        ; the run clock, high byte (decision #52)
RunLo       = WakePhase ; ...and low: the opening's phase byte, dead
                        ; once the opening hands over, which is when
                        ; the clock is zeroed. A clock "second" is 64
                        ; frames, as the floor clock's is
Mode        ds 1        ; bit 7 endless, bit 6 two players (the title's
                        ; SELECT, kept across RESET), bits 5-0 floors
                        ; survived in the endless game (capped at 63)
SkyDim      = LV        ; BuildSky's working copy of it. LV is physics
                        ; scratch, and BuildSky never runs inside physics

; ===============================================================
; BANK 0 — file $0000-$0FFF, mapped at $F000-$FFFF
; ===============================================================

        SEG BANK0
        ORG $0000
        RORG $F000

; ---------------------------------------------------------------
; F8 trampoline stubs. MUST be byte-identical at the same addresses
; in both banks: execution crosses banks inside these routines — the
; hotspot access swaps ROM mid-stream and the next opcode fetch comes
; from the other bank's copy. Bank 1 carries an unlabeled duplicate; a
; STUB_SIZE check there catches drift at assembly time. GoBank1 and
; GoBank0 hand whole frames across (the title and the narration);
; GoAnnex and GoBackBank0 are a call and its return, so bank 0 can
; run an annex job mid-frame (decision #51).
; ---------------------------------------------------------------

GoBank1:                ; jmp here from bank 0 code -> Bank1Entry
        lda BANK1HOT    ; the switch: A gets garbage, who cares
        jmp Bank1Entry  ; fetched from bank 1's identical copy
GoBank0:                ; jmp here from bank 1 code -> Bank0Entry
        lda BANK0HOT
        jmp Bank0Entry
GoAnnex:                ; jsr here from bank 0, Y = an annex job:
        lda BANK1HOT    ; map bank 1, then the identical stub's jmp
        jmp AnnexJob    ; lands in bank 1's job dispatcher
GoBackBank0:            ; jmp here from bank 1 to return to the caller
        lda BANK0HOT    ; map bank 0; the rts is fetched from bank 0's
        rts             ; identical stub and pops GoAnnex's return.
                        ; A is lost to the switch (and N/Z with it):
                        ; a job answers in X, Y or carry
ColdStart:              ; RESET vector target in both banks:
        ldy #0          ; power-on: the story, one player
WarmStart:              ; console RESET: jmp here with Y = Mode, so
        sei             ; the game the title chose survives it
        cld
        lda BANK0HOT    ; force bank 0 before touching anything
        jmp Bank0Init

STUB_SIZE = * - GoBank1

; ---------------------------------------------------------------
; Bank 0 cold start
; ---------------------------------------------------------------

Bank0Init:
        SUBROUTINE
        ldx #0          ; Y = the Mode to keep: 0 from power-on,
        txa             ; Mode from console RESET (a period game
.clear:                 ; variation survives RESET)
        dex
        txs
        pha
        bne .clear      ; clears TIA + RAM, leaves SP=$FF
        tya
        and #$C0        ; the choice, not the count
        sta Mode
        jsr SetPlayers  ; Active2 from Mode's bit 6

        lda #$80
        sta FirePrev
        lda #STATE_TITLE
        sta State       ; boot to the title (TitleLogic builds the sky
                        ; gradient + points the text kernel at the logo)
        sta WSYNC       ; and reach its first VSYNC from a line start:
                        ; ~38 cycles in, inside the 42 every frame
                        ; writes it at. From wherever this code ended
                        ; (cycle 74 once Mode was added), the frame
                        ; after a console RESET spanned 263 lines; the
                        ; old code made 262 by luck (decision #52)

; ---------------------------------------------------------------
; Frame loop. Same 262-line skeleton as game 1: 3 lines VSYNC,
; ~37 lines vertical blank (logic runs here), 192 visible, ~30
; overscan. The kernel is chosen by State: the title and narration
; use the asymmetric-playfield text kernels, play uses GameKernel.
; ---------------------------------------------------------------

; ---------------------------------------------------------------
; WaitVBlank pattern. The obvious `lda INTIM / bne` spin is a TRAP if
; the logic ever overruns its budget: once the RIOT timer underflows it
; switches to counting down every CPU CYCLE from 255, while this loop
; samples only every 7 cycles — so it misses zero roughly six times out
; of seven and waits another full 256 cycles for the next pass. A ONE
; LINE overrun becomes tens of lines, the frame stops being 262, and
; the picture rolls.
;
; That is exactly what moving right did. SetHorizPos's coarse-position
; divide loop costs 5 cycles per 15 pixels of x, so a character at the
; far right takes ~50 cycles longer to position than one at the left —
; and it is called twice. Add ClampBoxes, which only runs while you are
; MOVING, and the right-hand side of the screen tipped a budget the
; left-hand side fitted in. Measured: 262 lines standing still, 324
; walking Stella to the right.
;
; `bit TIMINT / bpl` waits on the timer's underflow FLAG instead, so if
; the flag is already set the wait falls straight through and an
; overrun costs only the cycles actually overspent. Same three bytes.
; It does not leave A = 0 the way `lda INTIM` did, so the beam-on
; `sta VBLANK` needs its own `lda #0`.
; ---------------------------------------------------------------

MainLoop:
        SUBROUTINE
        lda State               ; title, narration and the score run
        cmp #STATE_STORY        ; entirely in the bank-1 annex (none
        beq .annex              ; ever shares a frame with play): hand
        cmp #STATE_TITLE        ; it the frame; it hands back on fire
        beq .annex
        cmp #STATE_SCORE
        bne Bank0Entry
.annex:
        jmp GoBank1

; Bank0Entry: the bank-1 annex (title, narration) hands the frame back
; here, with State = STATE_OPEN (the title's fire) or STATE_LOAD (the
; next floor). Both are set up by the frame below, inside its vblank:
; doing it here, between frames, made those frames 276-292 lines. It
; lands past MainLoop's check, which is never needed from bank 1 (it
; only hands back for a bank-0 state) and cost the time a handover
; has: every frame writes VSYNC at cycle 38-42 of its line, and a
; handover that pushes it past 75 has spilled into the next line, a
; 263-line frame (decision #52).
Bank0Entry:
        lda #2
        sta VBLANK
        sta VSYNC
        sta WSYNC
        sta WSYNC
        sta WSYNC
        lda #0
        sta VSYNC
        lda #49
        sta TIM64T      ; ~41 scanlines of vertical blank — 5 ticks
                        ; more than the original 44, paid for by the
                        ; same 5 ticks off overscan below, so the frame
                        ; total is unchanged. Overscan was idling ~29
                        ; lines while the logic was running out of room.

        inc FrameCtr
        lda SWCHB       ; console RESET returns to the title
        lsr
        bcs .noReset
        ldy Mode
        jmp WarmStart
.noReset:
        lda State
        cmp #STATE_PLAY
        beq .doPlay
        cmp #STATE_WAKE
        beq .doWake
        cmp #STATE_DONE
        beq .doDone
        cmp #STATE_LOAD
        beq .doLoad
        jsr LoadFloor           ; STATE_OPEN (the title's frame never
        ldy #JOB_WAKESETUP      ; reaches here: the annex caught it):
        jsr GoAnnex             ; floor 1, then the opening's dark
        jsr PrepSprites
        jmp .logicDone
.doLoad:
        jsr LoadFloor           ; a floor boundary (or the clock ran
        lda #STATE_PLAY         ; out): load it, and rebuild the lamps
        sta State               ; NOW (PFColRam may still hold the
        jsr PrepSprites         ; narration pointers)
        jmp .logicDone
.doDone:
        jsr DoneLogic
        jmp .logicDone
.doWake:
        jsr WakeLogic
        jmp .logicDone
.doPlay:
        ldy #0          ; joystick 1, then joystick 2 (decision #47)
.player:
        jsr GetPad      ; Pad = this joystick; carry = nobody on it
        bcs .nextPad
        jsr ReadInput
        jsr ReadPortal  ; UP in a portal column -> teleport (Act 2)
        jsr ReadRift    ; UP grounded in a rift -> swap worlds (Act 3)
.nextPad:
        lda Pad
        lsr             ; bit 0: that was joystick 2
        bcs .padsDone
        ldy #1
        bne .player
.padsDone:
        jsr PrepSprites ; draw params + P1 multiplexer + positioning
                        ; (physics, the goal, sound, the blinks and the
                        ; clock run in OVERSCAN, after the kernel: see
                        ; there)
.logicDone:

                        ; every bank-0 frame draws the game
                        ; kernel: play, the opening, the beat, and the
                        ; beat's last frame (State already STORY: it
                        ; used to skip the kernel, a 50-line frame)
        lda #1
        sta CTRLPF      ; mirrored playfield
        lda PFColor     ; per-floor platform color (kernel steps it)
        sta COLUPF
.wv2:
        bit TIMINT              ; wait on the underflow FLAG, not
        bpl .wv2               ; on INTIM (see the note above)
        lda #0
        sta WSYNC
        sta VBLANK      ; A=0: beam on
        jsr GameKernel

Overscan:
        sta WSYNC       ; finish the last visible line cleanly —
        lda #2          ; blanking mid-line truncated the floor's
        sta VBLANK      ; final scanline on the right
        lda #0
        sta GRP0
        sta GRP1
        sta ENAM0
        sta ENAM1
        sta ENABL
        sta PF0         ; and the playfield — the kernel's last band
        sta PF1         ; used to survive into the next frame, and the
        sta PF2         ; beam is already on for the kernel-setup
                        ; cycles before the first WSYNC, so it printed
                        ; across the top of the screen
        lda #28         ; 5 ticks lent to vblank (see above), then one
        sta TIM64T      ; more off to land back on 262: `bit TIMINT`
                        ; exits at the UNDERFLOW, where `lda INTIM`
                        ; exited up to 64 cycles earlier (INTIM reads 0
                        ; for the last tick before it underflows), so
                        ; the robust wait cost the frame a line.

        ; Half of play's logic runs HERE (decision #47). Two joysticks
        ; made input plus sprite prep alone ~35 of vblank's ~41 lines,
        ; while overscan's ~23 sat idle. So vblank reads the sticks and
        ; preps the sprites; overscan, after the kernel, steps physics
        ; and everything that follows it. The frame still draws input
        ; and physics both one step old: physics ran at the end of the
        ; last frame, input at the top of this one.
        lda State
        cmp #STATE_PLAY
        bne .waitOS
        jsr UpdatePhysics
        jsr CheckGoal   ; all three home -> the beat, then narration
        ldy #JOB_SOUND
        jsr GoAnnex
        jsr BlinkPortal ; portal columns are only ever half-present
        jsr BlinkRifts  ; ...and the rifts, one size thinner
        jsr ClockTick   ; the floor clock (decision #22 restored)
.waitOS:
        bit TIMINT
        bpl .waitOS
        jmp MainLoop

; ===============================================================
; TITLE + NARRATION logic — moved to the bank-1 annex (the title and
; the story never share a frame with play). Bank 0 keeps only the
; handover: MainLoop's top dispatches both states through GoBank1,
; and Bank0Entry receives the frame back.
; ===============================================================

; ---------------------------------------------------------------
; The waking-Marcus opening (DESIGN-KICKOFF, promoted 2026-07-15).
; A recreation of Game 1's epilogue that the world assembles itself
; around. Runs on the game kernel with Floor 1 loaded, so the morph
; IS the first floor coming into being — the series' visual thesis
; (each game, the world gains fidelity) in one shot.
;   Phase 0  black screen, Marcus alone, eyeless, asleep-dim
;   Phase 1  the sky gradient assembles band by band, horizon first;
;            when it stands, the platforms appear
;   Phase 2  Marcus's eyes appear and he brightens — he is awake
;   Phase 3  Stella drops in from the sky above her spawn (physics
;            does the work; her landing thump is real)
;   Phase 4  Alex slides in from the left edge to his spawn
; Fire skips. The finish re-runs LoadFloor, which re-arms the floor
; cleanly — every character is already standing on its spawn.
; ---------------------------------------------------------------

; WakeLogic: the waking opening, one frame. Its phases are RAM-only
; and live in the annex (decision #51); bank 0 keeps the calls into
; bank-0 routines. The annex answers in X: 0 draw, 1 run physics
; (then ask again), 2 the opening is over.
WakeLogic:
        SUBROUTINE
        ldy #JOB_WAKEPRE
        jsr GoAnnex
        dex
        bmi .draw               ; 0: draw
        bne .finish             ; 2: over (or fire skipped it)
        jsr UpdatePhysics       ; 1: Stella falls, Alex slides in
        ldy #JOB_WAKEPOST
        jsr GoAnnex
        dex
        bpl .finish             ; 2: over; 0 falls through to draw
.draw:
        jsr PrepSprites
        lda WakePhase
        cmp #2
        bcs .awake
        lda #$FF                ; before the wake: no eyes...
        sta P0Eye
        lda ColDimTbl+2         ; ...and asleep-dim blue
        sta COLUP0
.awake:
        rts
.finish:
        lda #0                  ; the run clock starts with floor 1
        sta RunLo               ; (RunLo was the phase byte until now)
        sta RunHi
        lda #STATE_LOAD         ; floor 1 loads clean next frame, in
        sta State               ; its own vblank: loading it here as
        jmp PrepSprites         ; well, after the opening's physics,
                                ; ran this frame to 263 lines (#52)

; ===============================================================
; FLOOR FRAMEWORK — walk the FloorTable in order
; ===============================================================

; ---------------------------------------------------------------
; LoadFloor: load floor FloorSeq. Generic — it reads the floor's
; record pointer, per-character home-CharY table, wrap flag and sky
; base from the parallel Floor* tables, so a new floor is just one
; more row in each table plus its record + home table + narration.
; ---------------------------------------------------------------

LoadFloor:
        SUBROUTINE
        ldx FloorSeq
        lda FloorRecLo,x
        sta PF0Ptr
        lda FloorRecHi,x
        sta PF0Ptr+1
        clc                     ; PF1 <- +12, PF2 <- +24, boxes <- +36
        lda PF0Ptr
        adc #12
        sta PF1Ptr
        lda PF0Ptr+1
        adc #0
        sta PF1Ptr+1
        clc
        lda PF0Ptr
        adc #24
        sta PF2Ptr
        lda PF0Ptr+1
        adc #0
        sta PF2Ptr+1
        clc
        lda PF0Ptr
        adc #36
        sta PlatPtr
        lda PF0Ptr+1
        adc #0
        sta PlatPtr+1

        lda FloorHomeLo,x       ; per-character home-CharY table
        sta HomePtr
        lda FloorHomeHi,x
        sta HomePtr+1
        lda FloorWrapTbl,x      ; edge mode (Act 1 baseline: wrap ON)
        sta WrapMode

        ldy #60                 ; three spawn points (SX,SY,AX,AY,MX,MY)
        ldx #0
.spawn:
        lda (PF0Ptr),y
        sta CharX,x
        iny
        lda (PF0Ptr),y
        sta CharY,x
        iny
        inx
        cpx #NUM_CHARS
        bne .spawn

        ldx #NUM_CHARS-1
.zero:
        lda #0
        sta CharYLo,x
        sta CharVYHi,x
        sta CharVYLo,x
        sta SquashT,x
        lda #1
        sta OnGround,x
        sta CharFace,x          ; everyone wakes facing right
        dex
        bpl .zero
        lda Active2             ; two players: joystick 2 starts on
        bmi .solo               ; Alex, joystick 1 on Stella
        lda #1
        sta Active2
.solo:
        lda #0
        sta Active
        sta SoundId
        sta SoundT
        sta NUSIZ0
        sta VDELP0
        sta VDELP1
        lda #2                  ; all three characters have physics
        sta ActiveM1

        lda PF0Ptr              ; the record anchor for swaps and the
        sta RecPtr              ; rift blink (PF0Ptr itself gets
        lda PF0Ptr+1            ; repointed by both, so it can't serve)
        sta RecPtr+1
        lda #0                  ; every floor begins in world A
        sta CurWorld

        lda Mode                ; the endless game is always timed,
        bmi .endless            ; and tighter every floor
        lda SWCHB               ; left difficulty A arms the clock (#22:
        and #$40                ; switch-driven, no menu). Sampled here
        beq .untimed            ; so a mid-floor flip doesn't reset it.
        lda #45                 ; 45 seconds: G1's endless opening,
        bne .setClock           ; which is where a player meets a clock.
.untimed:                       ; Untimed is $FF: bit 7 tells ClockTick
        lda #$FF                ; not to count, and BuildSky's dim reads
        bne .setClock           ; none (16 - $FF borrows to no dim; a
                                ; zero here once dimmed the untimed sky
                                ; by its full 4 luma, decision #45)
.endless:
        and #$3F                ; floors survived: 45 - 2 each, to 12
        asl
        sta Temp
        lda #ENDLESS_T
        sec
        sbc Temp
        bcc .min
        cmp #ENDLESS_MIN
        bcs .setClock
.min:
        lda #ENDLESS_MIN
.setClock:
        sta TimerSec
        lda #0
        sta Temp                ; no breath on a fresh floor
        jsr BuildSky            ; world A's sky (CurWorld was just zeroed)
        lda #PFA_COLOR
        sta PFColor
        lda #<PFColRam          ; the kernel's per-band COLUPF table
        sta PFColPtr            ; lives in RAM (the home lamps),
        lda #>PFColRam          ; rebuilt by PrepSprites every frame
        sta PFColPtr+1
        rts

; ---------------------------------------------------------------
; BuildSky: rebuild the 12-band sky gradient for the CURRENT world.
; The which-world tell (kickoff rule 2, adapted to the greyscale
; world of #27): in world A the sky brightens toward the horizon; in
; world B the ramp runs BACKWARDS. Hue never changes — the world is
; neutral — but no two adjacent bands keep their order, so the swap
; reads on the whole screen for every kind of colour vision.
; ---------------------------------------------------------------

BuildSky:
        SUBROUTINE
        ldx FloorSeq
        lda FloorSkyTbl,x
        clc
        adc Temp                ; Temp is the caller's breath: 0 during
        sta Temp                ; play, +2 on the completion beat
        lda #16                 ; the clock's shadow, from the seconds
        sec                     ; left: none until the last sixteen,
        sbc TimerSec            ; then a luma step every four, to four
        bcs .dimmed             ; as it hits zero. Untimed floors keep
        lda #0                  ; TimerSec at 45: none. Dimming must
.dimmed:                        ; GROW as the seconds fall
        lsr
        lsr
        sta SkyDim
        ldx #11
.loop:
        lda GradOfs,x
        ldy CurWorld
        beq .fwd
        lda GradOfsR,x          ; world B: the ramp reversed
.fwd:
        clc
        adc Temp
        sec
        sbc SkyDim              ; the clock's shadow (0 untimed)
        bcc .black              ; never borrow into the hue nibble
        sta SkyGrad,x
        dex
        bpl .loop
        rts
.black:
        lda #0                  ; the clock can take the sky to black
        sta SkyGrad,x           ; but not one luma step further
        dex
        bpl .loop
        rts

; ---------------------------------------------------------------
; THE FLOOR CLOCK (decision #22's UI axis, restored to Game 2).
;
; Game 1 clocks each level; Game 2 had no timer at all, which made the
; later and roomier cartridge strictly MORE forgiving than the 4K one
; — the exact inverse of the series' own "capability grows with the
; cartridge" thesis. Two bytes of RAM buy the axis back.
;
; The signal is DARKENING, not reddening. Game 1 creeps the background
; toward red as time runs out, but #27 makes hue mean agency: in this
; game every hue on screen belongs to something with a will, and the
; world is the neutral ramp. A red sky would put colour on the one
; thing that must not have it, and would collide with the ember cue
; players already know from Game 1's title. So urgency is spent out of
; the world's own LIGHT instead: the gradient's base luma drops by up
; to 4 steps over the last sixteen seconds and the whole screen sinks.
; It is the same information in the same register — a wash becoming a
; deadline — carried in the vocabulary this game already speaks.
;
; Costs: the ramp is 0..8 luma, so a 4-step dim can reach black but
; never borrows into the hue nibble (the clock is clamped to the ramp
; for exactly that reason — see .clamp). Nothing else changes: the
; platforms stay at luma A (#27's "one level no character owns"), so
; a dimmed floor is still perfectly readable right down to zero.
;
; TIMED OFF BY DEFAULT, on the left difficulty switch — the same
; period-correct, menu-free control Game 1 uses (#22: Game 2 is a
; proper title screen but still mostly switch-driven). The story
; floors are untimed so the clock never gates the narrative; a player
; who wants the pressure flips A and gets it on every floor.
; ---------------------------------------------------------------

ClockTick:
        SUBROUTINE
        lda State               ; a floor that completed THIS frame has
        cmp #STATE_PLAY         ; already won: don't reload it out from
        bne .out                ; under the player on the same frame
        lda FrameCtr            ; already incremented this frame by
        and #%00111111          ; MainLoop, so counting its low bits
        bne .out                ; gives one tick every 64 frames and
        inc RunLo               ; stays in phase with no extra state.
        bne .runDone            ; The run clock counts every played
        inc RunHi               ; second, timed or not (decision #52)
.runDone:
        lda TimerSec
        bmi .out                ; untimed floor ($FF): nothing more
        beq .expired
        dec TimerSec
        lda TimerSec            ; does this tick change the light? The
        cmp #16                 ; dim is (16 - seconds) / 4 under
        bcs .out                ; sixteen, so it steps exactly at 12,
        and #3                  ; 8, 4 and 0: four repaints a floor
        bne .out
        lda #0
        sta Temp                ; no breath during play
        jsr BuildSky            ; repaint: the sky is only redrawn on
.out:                          ; load/swap/done otherwise
        rts
.expired:
        lda #STATE_LOAD         ; out of time: the floor starts over,
        bit Mode                ; exactly as Game 1's story mode does
        bpl .setState           ; (next frame's vblank reloads it: here,
        lda #60                 ; after physics in overscan, it can't
        sta StateTimer          ; fit) — or the endless run is over:
        lda #STATE_SCORE        ; the score, a beat before fire counts
.setState:
        sta State
        rts

; ---------------------------------------------------------------
; AtHome: X = character. Carry SET if that character is standing on
; ITS OWN home right now — grounded, at its home height, AND
; horizontally overlapping its home ledge.
;
; This is the ONE definition of "home" in the game: CheckGoal (does the
; floor complete?) and the home lamps (the feedback that teaches the
; rule) both call it, so what the player is told can never disagree with
; what the game tests. It is also Game 1's CheckGoals rule exactly —
; grounded + box overlap in X and Y — which is what decision #26 means
; by ONE goal mechanic for the series.
;
; The x test used to be absent here: home was "CharY equals the home
; value", and floors stayed honest only because check_levels.py proved
; per floor that no OTHER reachable footing produced that height. That
; put the guarantee in the level data instead of the code — fine for
; three hand-audited floors, but Acts 2-4 add portals, world-swap (two
; truths of ONE place, at identical heights) and possibly anti-gravity
; regions (#25), where same-height surfaces stop being an accident and
; start being the point.
;
; Clobbers A and Y; preserves X.
; ---------------------------------------------------------------

AtHome:
        SUBROUTINE
        lda OnGround,x
        beq .no                 ; home means STOOD on, not flown through
        lda MulThree,x
        tay                     ; -> this character's (Y, XL, XR)
        lda CharY,x
        cmp (HomePtr),y
        bne .no                 ; not at its home height
        iny
        lda CharX,x             ; body's right edge past the home's left
        clc
        adc WidthTbl,x
        cmp (HomePtr),y
        bcc .no
        beq .no                 ; touching edge-on is not standing on it
        iny
        lda CharX,x             ; body's left edge short of home's right
        cmp (HomePtr),y
        bcs .no
        sec                     ; home
        rts
.no:
        clc
        rts

; ---------------------------------------------------------------
; CheckGoal: a three-character floor completes when EACH character
; is standing on its own colour home ledge at the same time (AtHome).
; All home -> the fanfare and STATE_DONE's beat; DoneLogic then loads
; the narration and advances FloorSeq.
; ---------------------------------------------------------------

CheckGoal:
        SUBROUTINE
        ldx #NUM_CHARS-1
.loop:
        jsr AtHome
        bcc .done               ; someone isn't home: not yet
        dex
        bpl .loop
        ; all three home: one fanfare for the floor, then a beat to
        ; SEE it — three characters standing together on their own
        ; homes is the image decision #26 exists for. The annex's story
        ; handover waits for DoneLogic: TPtr overlays PFColRam, so the
        ; narration pointers would trample the lamps we are drawing.
        lda #3
        sta SoundId
        lda #16
        sta SoundT
        lda #STATE_DONE
        sta State
        lda #90
        sta StateTimer
.done:
        rts

; ---------------------------------------------------------------
; DoneLogic: the completion beat (Game 1's DoneLogic, in this game's
; palette). Everything freezes where it stands, the fanfare plays out,
; and the dusk sky takes a gentle 2-luma breath — Game 1 pulses its
; black background, so Game 2 pulses the thing that replaced it. When
; the timer runs out the narration takes over.
; ---------------------------------------------------------------

DoneLogic:
        SUBROUTINE
        ldy #JOB_SOUND
        jsr GoAnnex
        lda StateTimer          ; the breath: sky base +0 / +2 luma
        and #$08                ; (bigger would carry the luma nibble
        lsr                     ; into the next HUE — dusk violet must
        lsr                     ; stay dusk violet)
        sta Temp
        jsr BuildSky            ; the ONE sky painter: it already knows
                                ; which world to paint (a floor can
                                ; complete in world B, and the beat must
                                ; not flip the sky back) and it also
                                ; carries the clock's dim, so the world
                                ; doesn't pop back to full brightness
                                ; for the beat it just ran out of.
        jsr PrepSprites         ; keep the P1 multiplexer running: if
                                ; the two inactive characters overlap,
                                ; a frozen P1 would show only one of
                                ; them for the whole beat — and this is
                                ; the beat where all three must be seen
        dec StateTimer
        beq .advance
        rts
.advance:
        bit Mode                ; the endless game: no narration, the
        bpl .story              ; annex counts it and draws a floor,
        ldy #JOB_NEXTFLOOR      ; and its return goes straight back to
        jmp GoAnnex             ; our caller
.story:
        inc FloorSeq            ; the lamps are finished. The annex shows
        lda #STATE_STORY        ; screen FloorSeq (the narration after
                                ; floor n is screen n), and goes back to
                                ; the title once FloorSeq is NUM_FLOORS
        sta State
        rts

; SetPlayers: Active2 from Mode's bit 6: $FF one player, 1 two (joystick
; 2 starts on Alex). Bank 1 keeps its own copy for the title's SELECT.
SetPlayers:
        SUBROUTINE
        ldx #$FF
        bit Mode
        bvc .one
        ldx #1
.one:   stx Active2
        rts

; ---------------------------------------------------------------
; GetPad: Y = joystick (0 or 1). Copies it into Pad in one layout so
; the verbs below read either stick the same way: SWCHA's nibble for
; this stick in bits 7-4, its fire button in bit 3, Y in bit 0.
; Carry set: joystick 2 in one-player mode, nobody to move (Pad still
; gets bit 0, so the caller's loop ends).
; ---------------------------------------------------------------

GetPad:
        SUBROUTINE
        lda SWCHA
        cpy #0
        beq .stick
        ldx Active2
        bpl .two
        sty Pad
        sec
        rts
.two:
        asl                     ; joystick 2 is the low nibble
        asl
        asl
        asl
.stick:
        and #$F0
        sta Pad
        lda INPT4,y             ; INPT4 / INPT5: fire in bit 7
        and #$80
        lsr
        lsr
        lsr
        lsr
        ora Pad
        sta Pad
        tya
        ora Pad
        sta Pad
        clc
        rts

; PadChar: X = the character this Pad's joystick holds.
PadChar:
        ldx Active
        lda Pad
        lsr
        bcc .p1
        ldx Active2
.p1:    rts

; PadBit: A = this Pad's bit in FirePrev / UpPrev, Y = the joystick.
PadBit:
        lda Pad
        and #1
        tay
        lda PadBitTbl,y
        rts

; ---------------------------------------------------------------
; ReadInput: move this Pad's character (with solid-box blocking and
; the always-on wrap edges), fire jumps, down+fire switches: one
; player cycles Stella -> Alex -> Marcus; two players take the one
; character nobody holds.
; ---------------------------------------------------------------

ReadInput:
        SUBROUTINE
        jsr PadChar
        lda CharX,x
        sta NewX
        lda #$FF
        sta MoveDir
        lda Pad
        and #%01000000          ; left (active low)
        bne .noLeft
        lda #0
        sta MoveDir
        sta CharFace,x          ; eyes follow the walk
        jsr WalkSpeed
        sta Temp
        lda NewX
        sec
        sbc Temp
        sta NewX
.noLeft:
        lda Pad
        and #%10000000          ; right
        bne .noRight
        lda #1
        sta MoveDir
        sta CharFace,x
        jsr WalkSpeed
        sta Temp
        lda NewX
        clc
        adc Temp
        sta NewX
.noRight:
        lda MoveDir
        cmp #$FF
        beq .noMove
        jsr ClampBoxes          ; solid walls block sideways motion
        lda WrapMode            ; wrap floor: edges are seamless, not
        bne .wrapEdge           ; walls — take x modulo the screen
        lda NewX
        cmp #MIN_X
        bcs .okMin
        lda #MIN_X
.okMin:
        cmp MaxXTbl,x
        bcc .okMax
        lda MaxXTbl,x
.okMax:
        sta CharX,x
        jmp .noMove
.wrapEdge:
        lda NewX
        cmp #WRAP_HI            ; >= WRAP_HI: underflowed off the left
        bcs .wrapAdd
        cmp #WRAP_W             ; WRAP_W..: overflowed off the right
        bcc .wrapPut
        sbc #WRAP_W             ; (carry set here) x -= 160
        jmp .wrapPut
.wrapAdd:
        clc
        adc #WRAP_W             ; x += 160 (mod 256): -k -> 160-k
.wrapPut:
        sta CharX,x
.noMove:

        lda Pad
        and #%00001000          ; fire (active low)
        bne .release
        jsr PadBit
        and FirePrev
        beq .done               ; still held from the last press
        lda Pad
        and #%00100000          ; holding down?
        beq .switch
        lda OnGround,x          ; fire alone: jump if grounded
        beq .pressed
        lda JumpHiTbl,x
        sta CharVYHi,x
        lda JumpLoTbl,x
        sta CharVYLo,x
        lda #0
        sta OnGround,x
        lda #1
        sta SoundId
        lda #10
        sta SoundT
        jmp .pressed
.switch:
        lda Active2
        bpl .takeFree
        lda Active              ; the game 1 switch verb, extended to
        clc                     ; three: Stella -> Alex -> Marcus -> ...
        adc #1
        cmp #NUM_CHARS
        bcc .setA
        lda #0
.setA:
        sta Active
        jmp .pressed
.takeFree:                      ; two players: 0+1+2 = 3, so the one
        lda #3                  ; nobody holds is 3 - Active - Active2
        sec
        sbc Active
        sec
        sbc Active2
        tay
        lda Pad
        lsr
        bcs .setB
        sty Active
        bcc .pressed
.setB:
        sty Active2
.pressed:
        jsr PadBit              ; disarm until this button is released
        eor #$FF
        and FirePrev
        sta FirePrev
        rts
.release:
        jsr PadBit
        ora FirePrev
        sta FirePrev
.done:
        rts

; WalkSpeed: X = char. A = this frame's step in pixels. Marcus walks
; 1.5px/frame the cheap way: an extra pixel every other frame.
WalkSpeed:
        SUBROUTINE
        lda FrameCtr
        and SpeedHalfTbl,x
        and #1
        clc
        adc SpeedTbl,x
        rts

; ---------------------------------------------------------------
; THE PORTAL VERB (Act 2; decision #18's middle rung: move through
; space -> SHORTCUT through space -> change space). A portal is a
; linked pair of 8px columns drawn by the mirrored playfield, pulsing
; ~2x/second. UP (edge) while the ACTIVE character overlaps a column
; teleports them to that column's MOUTH — a position chosen per floor,
; so a column can lift, drop, or cross the screen (the mouths, not the
; columns, carry the puzzle). Only the active character teleports:
; friends never follow — each crossing is a separate, deliberate act.
;
; Re-attached from the game2-workbench tag's proven P1/WP1 verb, with
; changes the real game's constraints forced:
;   * The workbench blinked the column through a 24-byte PFRam copy;
;     RAM here ends 7 bytes from the stack ceiling, so the blink is a
;     POINTER SWAP instead: the kernel already draws the playfield
;     through PF1Ptr/PF2Ptr, so BlinkPortal repoints the portal plane
;     between the record's ON copy and a 12-byte OFF copy kept right
;     after the record (+66). Zero RAM, kernel untouched.
;   * The workbench was Stella-only, so mouths stored her CharY. With
;     three heights, mouth tables store FEET du and arrival subtracts.
;   * Byte diet (bank 0 is nearly full): column tables store only each
;     column's LEFT edge (columns are always 8px, so R = L+8), and the
;     plane is derived from x (columns left of 48 live in PF1, the rest
;     PF2) rather than carried as a table.
; ---------------------------------------------------------------

; ReadPortal: the input half. UP while the active character overlaps a
; column -> DoTeleport. Edge-gated like the workbench's, so holding UP
; never chains; floors without portals park FloorPortL at 255.
ReadPortal:
        SUBROUTINE
        ldy FloorSeq
        lda FloorPortL,y
        bmi .done               ; 255: no portal on this floor
        lda Pad
        and #%00010000          ; UP (active low)
        bne .release
        jsr PadBit
        and UpPrev
        beq .done               ; held: already handled this press
        jsr PadChar
        jsr InPortal            ; carry set + Y = column index
        bcc .clear
        jsr DoTeleport
.clear:
        jsr PadBit
        eor #$FF
        and UpPrev
        sta UpPrev
        rts
.release:
        jsr PadBit
        ora UpPrev
        sta UpPrev
.done:
        rts

; InPortal: X = character. Carry SET and Y = 0/1 if the character's
; body overlaps a column (any height — a beam has no top). Columns are
; 8px wide; the test is AtHome's overlap rule against [L, L+8).
InPortal:
        SUBROUTINE
        lda CharX,x
        clc
        adc WidthTbl,x          ; body's right edge
        sta Temp
        ldy FloorSeq
        lda FloorPortL,y        ; column A: [L, L+8)
        sta CY                  ; CY = L (physics scratch, dead here)
        clc
        adc #8
        cmp CharX,x             ; left edge at/past R: not in A
        beq .tryB
        bcc .tryB
        lda Temp
        cmp CY                  ; right edge short of/even with L
        beq .tryB
        bcc .tryB
        ldy #0
        sec
        rts
.tryB:
        lda FloorPort2L,y       ; column B, same test
        sta CY
        clc
        adc #8
        cmp CharX,x
        beq .out
        bcc .out
        lda Temp
        cmp CY
        beq .out
        bcc .out
        ldy #1
        sec
        rts
.out:
        clc
        rts

; DoTeleport: X = character, Y = column. Move them to that column's
; mouth: mouth tables hold FEET du, so CharY = feet - height. Arrive
; grounded with zeroed velocity, a short settle-squash and the portal
; blip — the landing reads as deliberate, and a mouth over open air
; would simply fall (none of the shipped floors do that). Mouths are
; interleaved per floor (FloorMouX/Y: floor*2 + column) so one indexed
; load serves both columns.
DoTeleport:
        SUBROUTINE
        lda FloorSeq
        asl
        sta CY
        tya
        ora CY
        tay                     ; mouth slot = floor*2 + column
        lda FloorMouX,y
        sta CharX,x
        lda FloorMouY,y
        sec
        sbc HeightTbl,x         ; mouth feet -> this character's top
        sta CharY,x
        lda #0
        sta CharYLo,x
        sta CharVYHi,x
        sta CharVYLo,x
        lda #1
        sta OnGround,x          ; physics re-seats her this frame
        lda #3
        sta SquashT,x
        lda #4                  ; the portal blip
        sta SoundId
        lda #8
        sta SoundT
        rts

; BlinkPortal: the draw half — pulse the column ~0.5s on / 0.5s off by
; swapping the portal plane's pointer between the record's ON copy and
; the OFF copy at record+66. Runs only in STATE_PLAY (the completion
; beat freezes the world, portal included). check_levels.py proves the
; two copies differ by exactly the column mask, and that the mask is
; what the trigger tables claim — the drawn portal and the tested
; portal cannot drift apart.
BlinkPortal:
        SUBROUTINE
        ldy FloorSeq
        lda FloorPortL,y
        bmi .done
        sta CY                  ; the column's left edge selects the
                                ; plane: x < 48 -> PF1, else PF2
        lda FrameCtr
        and #%00010000
        beq .off
        lda #12                 ; ON: the record's own plane...
        ldy CY
        cpy #48
        bcc .have               ; columns left of 48 live in PF1 (+12)
        lda #24                 ; ...the rest in PF2 (+24)
        bne .have
.off:
        lda #66                 ; OFF: the extra plane after the record
.have:
        clc
        adc RecPtr              ; the record anchor (PF0Ptr is off
        sta Temp                ; limits: Act 3's rift blink repoints it)
        lda RecPtr+1
        adc #0
        sta CYH                 ; Temp/CYH = the chosen plane's address
        lda CY
        cmp #48
        bcc .plane1
        lda Temp                ; PF2 column
        sta PF2Ptr
        lda CYH
        sta PF2Ptr+1
        rts
.plane1:
        lda Temp
        sta PF1Ptr
        lda CYH
        sta PF1Ptr+1
.done:
        rts

; ---------------------------------------------------------------
; THE WORLD-SWAP VERB (Act 3; decisions #9 + #18's final rung: change
; space itself). A RIFT is a thin 4px beam standing at the screen's
; edge (PF0 — the one plane that never differs between worlds), drawn
; as a mirrored pair like everything else. UP while GROUNDED in a rift
; swaps the world: the player's x, y and velocity persist (that RAM
; persistence is the whole pitch), and the geometry around them
; changes to the floor's other truth.
;
; Two grammar rules keep three characters safe in a world that
; rearranges itself (the workbench was Stella-only and never faced
; this):
;   * SWAPS ARE GROUNDED-ONLY, in the rift — so the swap moment is a
;     finite set of standing states, and the solver can prove every
;     one of them is clear in the other world.
;   * WHAT DIFFERS BETWEEN WORLDS IS ALWAYS ONE-WAY (ledge art that
;     exists in only one truth). One-way boxes never side-block, so no
;     body can be left inside a new wall — the worst a swap can do is
;     drop you, which is legal. The solver audits this too.
;
; The delivery is a POINTER SWAP, not the F8 bank switch the workbench
; prototyped: world B's interior planes and boxes live after the
; record (at +78/+90/+102; the rift-blink's PF0 OFF copy at +66), and
; SwapWorld repoints PF1Ptr/PF2Ptr/PlatPtr and reverses the sky. RAM
; is full (the lamps own the old union trick's bytes), and honestly —
; the truth the mechanic teaches is "two truths of one place", which
; the player can only ever SEE; the mapper chip was never visible.
; ---------------------------------------------------------------

; ReadRift: UP (edge) while the ACTIVE character stands grounded in a
; rift column -> SwapWorld. Floors without rifts park FloorRiftL=255.
; (Shares UpPrev with ReadPortal, but no floor in acts 2-3 has both
; verbs, so the two never contend; Act 4 must merge the reads first.)
ReadRift:
        SUBROUTINE
        ldy FloorSeq
        lda FloorRiftL,y
        bmi .done
        lda Pad
        and #%00010000          ; UP (active low)
        bne .release
        jsr PadBit
        and UpPrev
        beq .done
        jsr PadChar
        lda OnGround,x          ; grounded only — see the grammar above
        beq .clear
        jsr InRift
        bcc .clear
        jsr SwapWorld
.clear:
        jsr PadBit
        eor #$FF
        and UpPrev
        sta UpPrev
        rts
.release:
        jsr PadBit
        ora UpPrev
        sta UpPrev
.done:
        rts

; InRift: X = character. Carry SET if the character's body overlaps a
; rift column — the PF0 pair [L, L+4) and its mirror [156-L, 160-L).
InRift:
        SUBROUTINE
        lda CharX,x
        clc
        adc WidthTbl,x          ; body's right edge
        sta Temp
        ldy FloorSeq
        lda FloorRiftL,y
        sta CY                  ; CY = L
        clc
        adc #4
        cmp CharX,x             ; left edge at/past L+4: not in the left
        beq .try2               ; column
        bcc .try2
        lda Temp
        cmp CY                  ; right edge short of/even with L
        beq .try2
        bcc .try2
        sec
        rts
.try2:
        lda #156                ; the mirror column: [156-L, 160-L)
        sec
        sbc CY
        sta CY
        clc
        adc #4
        cmp CharX,x
        beq .out
        bcc .out
        lda Temp
        cmp CY
        beq .out
        bcc .out
        sec
        rts
.out:
        clc
        rts

; SwapWorld: flip CurWorld, repoint the interior pointers at the other
; world's pages of the record, rebuild the sky (reversed), chime. PF0
; is untouched: it is the shared plane — the frame, the floor, and the
; rifts themselves are the things BOTH truths agree on.
SwapWorld:
        SUBROUTINE
        lda CurWorld
        eor #1
        sta CurWorld
        bne .toB
        lda #12                 ; world A: PF1/PF2/boxes at +12/+24/+36
        bne .have
.toB:
        lda #78                 ; world B: the variants at +78/+90/+102
.have:
        sta Temp
        ldx #0
.loop:
        lda RecPtr
        clc
        adc Temp
        sta PF1Ptr,x            ; PF1Ptr, PF2Ptr, PlatPtr are
        lda RecPtr+1            ; consecutive zero-page pairs — one loop
        adc #0                  ; repoints all three
        sta PF1Ptr+1,x
        lda Temp
        clc
        adc #12
        sta Temp
        inx
        inx
        cpx #6
        bne .loop
        jsr BuildSky            ; the full-screen tell, reversed ramp
        lda #5                  ; the two-world chime (UpdateSound
        sta SoundId             ; reads CurWorld for the direction)
        lda #8
        sta SoundT
        rts

; BlinkRifts: pulse the rift columns ~0.5s on/off by swapping PF0Ptr
; between the record's PF0 page and its OFF copy at +66. Same language
; as the portal blink (a beam that is only ever half-present), drawn a
; size thinner (4px) so the two verbs never share a silhouette.
BlinkRifts:
        SUBROUTINE
        ldy FloorSeq
        lda FloorRiftL,y
        bmi .done
        lda FrameCtr
        and #%00010000
        beq .off
        lda #0                  ; ON: the record's own PF0 page
        beq .have
.off:
        lda #66                 ; OFF: the copy after the record
.have:
        clc
        adc RecPtr
        sta PF0Ptr
        lda RecPtr+1
        adc #0
        sta PF0Ptr+1
.done:
        rts

; ---------------------------------------------------------------
; ClampBoxes: block horizontal movement into solid boxes.
; In: X = char, NewX = proposed x, MoveDir = 0 left / 1 right.
; ---------------------------------------------------------------

ClampBoxes:
        SUBROUTINE
        lda CharY,x
        sta CY
        clc
        adc HeightTbl,x
        sta CYH
        lda #NUM_PLATS-1
        sta BoxIdx
.loop:
        ldy BoxIdx
        lda (PlatPtr),y         ; top
        sta TopV
        tya
        clc
        adc #6
        tay
        lda (PlatPtr),y         ; bottom
        sta BotV
        cmp TopV
        beq .next               ; one-way (or pad): never blocks
        ; vertical overlap: CY < bottom and CYH > top
        lda BotV
        cmp CY
        bcc .next
        beq .next
        lda TopV
        cmp CYH
        bcs .next
        ; horizontal overlap with the proposed position
        jsr FetchLR
        lda NewX
        cmp RV
        bcs .next
        lda NewX
        clc
        adc WidthTbl,x
        cmp LV
        bcc .next
        beq .next
        ; blocked: push back against the box edge
        lda MoveDir
        beq .fromRight
        lda LV
        sec
        sbc WidthTbl,x
        sta NewX
        jmp .next
.fromRight:
        lda RV
        sta NewX
.next:
        dec BoxIdx
        bpl .loop
        rts

; FetchLR: Y = box index + 6 (the bottom slot). Loads the box's
; left and right edges into LV/RV.
FetchLR:
        SUBROUTINE
        tya
        clc
        adc #6
        tay
        lda (PlatPtr),y
        sta LV
        tya
        clc
        adc #6
        tay
        lda (PlatPtr),y
        sta RV
        rts

; ---------------------------------------------------------------
; UpdatePhysics: gravity + vertical motion for all three characters;
; head bonks against solid boxes while rising, swept landing on box
; tops — or on either friend's head — while falling.
; ---------------------------------------------------------------

UpdatePhysics:
        SUBROUTINE
        ldx ActiveM1            ; 2 = all three characters
.charLoop:
        lda CharY,x             ; where the feet started
        clc
        adc HeightTbl,x
        sta PrevFeet

        lda CharVYLo,x          ; vy += gravity
        clc
        adc #GRAV_LO
        sta CharVYLo,x
        lda CharVYHi,x
        adc #0
        sta CharVYHi,x

        bmi .applyVel           ; rising: no fall clamp
        cmp #MAXFALL
        bcc .applyVel
        lda #MAXFALL
        sta CharVYHi,x
        lda #0
        sta CharVYLo,x
.applyVel:
        lda CharYLo,x           ; y += vy
        clc
        adc CharVYLo,x
        sta CharYLo,x
        lda CharY,x
        adc CharVYHi,x
        sta CharY,x

        bpl .phase              ; clamp at the top of the screen
        lda #0
        sta CharY,x
        sta CharYLo,x
        sta CharVYHi,x
        sta CharVYLo,x
.phase:
        lda CharVYHi,x
        bpl .landPhase
        jmp .bonkPhase

; --- falling: swept landing on box tops -------------------------
.landPhase:
        lda CharY,x
        clc
        adc HeightTbl,x
        sta NewFeet
        lda #NUM_PLATS-1
        sta BoxIdx
.landLoop:
        ldy BoxIdx
        lda (PlatPtr),y         ; top
        sta TopV
        cmp PrevFeet
        bcc .landNext           ; surface above where we started
        cmp NewFeet
        beq .landHit
        bcs .landNext           ; feet haven't reached it yet
.landHit:
        tya
        clc
        adc #6
        tay
        jsr FetchLR
        lda CharX,x
        cmp RV
        bcs .landNext
        lda CharX,x
        clc
        adc WidthTbl,x
        cmp LV
        bcc .landNext
        beq .landNext
.doLand:
        ; landed. thump + squash if this was a real fall
        lda OnGround,x
        bne .noSnd
        lda CharVYHi,x
        cmp #1
        bcc .noSnd
        lda #4
        sta SquashT,x           ; a few frames, 1 du shorter
        lda #2
        sta SoundId
        lda #4
        sta SoundT
.noSnd:
        lda TopV
        sec
        sbc HeightTbl,x
        sta CharY,x
        lda #0
        sta CharYLo,x
        sta CharVYHi,x
        sta CharVYLo,x
        lda #1
        sta OnGround,x
        jmp .nextChar
.landNext:
        dec BoxIdx
        bpl .landLoop
        ; no box caught us — maybe a friend's head did. Each character
        ; has two possible perches now; test both.
        lda OtherATbl,x
        tay
        jsr HeadTest
        bcs .doLand             ; TopV = the friend's head
        lda OtherBTbl,x
        tay
        jsr HeadTest
        bcs .doLand
        lda #0
        sta OnGround,x
        jmp .nextChar

; --- rising: bonk the head on solid box bottoms -----------------
.bonkPhase:
        lda PrevFeet
        sec
        sbc HeightTbl,x
        sta PrevTop
        lda #NUM_PLATS-1
        sta BoxIdx
.bonkLoop:
        ldy BoxIdx
        lda (PlatPtr),y         ; top
        sta TopV
        tya
        clc
        adc #6
        tay
        lda (PlatPtr),y         ; bottom
        sta BotV
        cmp TopV
        beq .bonkNext           ; one-way / pad
        lda PrevTop
        cmp BotV
        bcc .bonkNext           ; head already above the underside
        lda CharY,x
        cmp BotV
        bcs .bonkNext           ; hasn't reached it
        jsr FetchLR
        lda CharX,x
        cmp RV
        bcs .bonkNext
        lda CharX,x
        clc
        adc WidthTbl,x
        cmp LV
        bcc .bonkNext
        beq .bonkNext
        lda BotV                ; bonk: stop under the box
        sta CharY,x
        lda #0
        sta CharYLo,x
        sta CharVYHi,x
        sta CharVYLo,x
        jmp .nextChar
.bonkNext:
        dec BoxIdx
        bpl .bonkLoop

.nextChar:
        dex
        bmi .doneChars
        jmp .charLoop
.doneChars:
        rts

; HeadTest: can falling character X land on character Y's head this
; frame? Uses PrevFeet/NewFeet from the caller's sweep. Returns carry
; set (and TopV = the head's y) on a hit.
HeadTest:
        SUBROUTINE
        lda CharY,y             ; the friend's head, one-way surface
        sta TopV
        cmp PrevFeet
        bcc .no                 ; head above where we started
        cmp NewFeet
        beq .hit
        bcs .no                 ; feet haven't reached it yet
.hit:
        lda CharX,y
        clc
        adc WidthTbl,y
        sta RV
        lda CharX,x
        cmp RV
        bcs .no
        lda CharX,x
        clc
        adc WidthTbl,x
        cmp CharX,y
        bcc .no
        beq .no
        sec                     ; standing on a friend
        rts
.no:
        clc
        rts

; ---------------------------------------------------------------
; PrepSprites: everything the kernel needs, rebuilt each vblank.
;
; 1. Home-ledge pulse: swap the per-band COLUPF table between a
;    bright and a dim copy ~2x/second so each character's home ledge
;    breathes in its own colour.
; 2. Per character: drawn top/height (squash & stretch) and this
;    frame's eye byte (facing + blink).
; 3. The P1 multiplexer. P0 is the ACTIVE character's, solid. The two
;    inactive characters share P1: separated -> P1 hops mid-frame and
;    all three draw at 60Hz; overlapping -> P1 alternates at 30Hz.
; 4. Horizontal positioning for P0 and P1's first tenant.
; ---------------------------------------------------------------

PrepSprites:
        SUBROUTINE
; ---- the HOME LAMPS: build this frame's 12-band COLUPF table ----
; Colour-blind-safe goal feedback (decision #27): each home band is a
; lamp in its owner's own (luma-coded) colour. Vacant, it BLINKS
; against near-black — fast if its owner is the character you are
; controlling, slow otherwise — so the blinking is the to-do list
; and the fast blink answers "which home is mine?" without colour.
; Once its owner stands home it holds steady. Gated on STATE_PLAY and
; STATE_DONE (the completion beat, where all three read steady); the
; wake opening drives PFColPtr at ROM tables itself, and once the
; narration is loaded TPtr owns these bytes again.
        lda State
        cmp #STATE_PLAY
        beq .lamps
        cmp #STATE_DONE
        bne .noLamps
.lamps:
        ldy #11                 ; base coat: platform grey
        lda #PFA_COLOR
.tan:
        sta PFColRam,y
        dey
        bpl .tan
        ldx #NUM_CHARS-1
.lamp:
        lda MulNine,x           ; this character's lamp band here —
        clc                     ; char*NUM_FLOORS + floor. This was
        adc FloorSeq            ; MulThree (char*3 + floor), correct
        tay                     ; when there were three floors and
        lda FloorBandByChar,y   ; wrong the moment there were nine: the
        sta Temp                ; table is authored a row per character
        jsr AtHome              ; (Stella's nine, then Alex's, then
        bcc .vac                ; Marcus's), so char*3+floor walked off
        lda ColBriTbl,x         ; Stella's row and into Alex's. Stella
        bne .put                ; read her own values by luck — her row
.vac:                           ; occupies indices 0-8 — while Alex and
        cpx Active              ; Marcus were tinted from her bands on
        beq .fast               ; every floor. The lamp is decision
        cpx Active2             ; (either player's own home blinks fast)
        beq .fast
                                ; #27's whole colour-blind-safety story,
                                ; so two of three homes were lighting up
                                ; at the wrong height, in the wrong
                                ; colour, on all nine floors.
        lda FrameCtr
        and #$40                ; slow: the to-do list (0.47 Hz)
        jmp .test
.fast:
        lda FrameCtr
        and #$10                ; fast: "this one is yours" (1.88 Hz).
                                ; Was $08 = 3.75 Hz, over the 3-per-
                                ; second photosensitivity limit — and
                                ; it is the lamp you are looking at,
                                ; since it switches from steady to
                                ; blinking the instant you step off
                                ; your own home. Both rates halved, so
                                ; the 4x fast/slow ratio survives and
                                ; both sit under the limit.
.test:
        bne .lit
        lda #$02                ; off-phase: near-black
        bne .put
.lit:
        lda ColBriTbl,x         ; on-phase: the owner's own colour
.put:
        ldy Temp
        sta PFColRam,y
        dex
        bpl .lamp
.noLamps:
        ldx #NUM_CHARS-1
.each:
        lda HeightTbl,x
        sta Temp                ; drawn height
        lda CharY,x
        sta CY                  ; drawn top
        lda SquashT,x
        beq .noSquash
        dec SquashT,x
        inc CY                  ; landing: top drops 1 du, 1 du
        dec Temp                ; shorter — the feet stay planted
        jmp .eyes
.noSquash:
        lda CharVYHi,x
        bpl .eyes
        lda CY                  ; rising: 1 du taller, top 1 du
        beq .eyes               ; higher (unless at the ceiling)
        dec CY
        inc Temp
.eyes:
        lda CY
        sta DrawY,x
        lda Temp
        sta DrawH,x
        lda FrameCtr            ; blink: 4 frames closed out of
        and #$7F                ; every 128 (~every 2 seconds)
        cmp #4
        bcc .blink
        ldy CharFace,x          ; 0 left, 1 right
        cpx Active              ; awake eyes for a held character,
        beq .wide               ; narrowed for the free ones
        cpx Active2
        beq .wide
        iny
        iny
.wide:
        lda EyeTbl,y
        bne .setEye
.blink:
        lda #$FF                ; eyes shut: solid body
.setEye:
        sta EyeByte,x
        dex
        bpl .each

        ; ---- Who shares a sprite. ----
        ;
        ; ONE PLAYER: P0 = the active character, solid; the other two
        ; share P1, ALWAYS alternating at 30Hz. #19 hopped P1 mid-frame
        ; when they separated, so the look was conditional (solid here,
        ; flickering there); 82133b8 leaned into the flicker instead, so
        ; that over two games the player learns THE CHARACTER YOU
        ; CONTROL IS SOLID, THE OTHERS FLICKER, and Game 3's Flicker has
        ; a rule to break (#29).
        ;
        ; TWO PLAYERS (decision #47, relaxing that rule as #44 decided):
        ; two characters are held and the TIA has two sprites, so the
        ; free one must share. #19's hop comes back: whichever pair
        ; separates vertically shares P1, hopping mid-frame, and the
        ; odd one out has P0. Pairs are tried so that the odd one out
        ; is joystick 1's character, then joystick 2's, then the free
        ; one, so a held character keeps a sprite to itself when it
        ; can (a hop tenant is solid too; it can just clip a du at the
        ; hop). Only when no pair separates (all three level) does the
        ; one-player look take over for the frame.
        lda Active2
        bmi .flicker
        lda Active
        jsr TryPair
        bcs .paired
        lda Active2
        jsr TryPair
        bcs .paired
        lda #3                  ; the free one: 3 - Active - Active2
        sec
        sbc Active
        sec
        sbc Active2
        jsr TryPair
        bcs .paired
.flicker:
        lda #$FF
        sta RepoDU              ; never hop
        ldy Active
        sty CYH                 ; P0's character
        ldx OtherATbl,y         ; the two characters that are NOT active
        lda OtherBTbl,y
        tay
        lda FrameCtr
        and #1
        beq .fill               ; even frame: show X
        tya                     ; odd frame: show Y
        tax
.fill:
        jsr FillP1              ; P1 = tonight's tenant, whole frame
        jmp .p0
.paired:                        ; CYH = odd one out, Temp = upper,
        lda RepoDU              ; NewX = lower. Never hop on a band
        and #7                  ; boundary OR the prefetch line before
        beq .bump1              ; it: both line 1s are busy
        cmp #7
        bne .noShift
        inc RepoDU              ; du==7 mod 8: +2, landing on ==1
.bump1:
        inc RepoDU              ; (the 2-du gap margin absorbs +1;
.noShift:                       ; the rare +2 case can clip the lower
                                ; sprite's first line: cosmetic)
        ldx Temp
        jsr FillP1              ; P1 opens as the upper character...
        ldx NewX                ; ...and hops to the lower at RepoDU
        lda CharX,x
        sta P1X2
        lda DrawY,x
        sta P1Y2
        lda DrawH,x
        sta P1H2
        lda EyeByte,x
        sta P1Eye2
        lda NusizTbl,x
        sta P1Nu2
        lda ColBriTbl,x
        sta P1Col2

.p0:                            ; P0 = the odd one out, solid
        ldx CYH
        lda DrawY,x
        sta P0Top
        lda DrawH,x
        sta P0Hgt
        lda EyeByte,x
        sta P0Eye
        lda NusizTbl,x
        sta NUSIZ0              ; may be Alex (double width)
        lda ColBriTbl,x
        sta COLUP0
.position:
        ldx CYH
        lda CharX,x
        ldx #0
        jsr SetHorizPos
        lda P1XA                ; P1 = its first tenant
        ldx #1
        jsr SetHorizPos
        sta WSYNC
        sta HMOVE
        ldx #6                  ; HMCLR must wait 24+ cycles
.wait:
        dex
        bne .wait
        sta HMCLR
        rts

; TryPair: A = a character to leave on P0. Carry SET if the other two
; separate vertically enough for P1 to hop between them: then CYH = A,
; Temp = the upper of the two, NewX = the lower, RepoDU = the first du
; past the upper one (before PrepSprites nudges it off band lines).
TryPair:
        SUBROUTINE
        sta CYH
        tay
        ldx OtherATbl,y
        lda OtherBTbl,y
        tay                     ; X, Y = the pair
        lda DrawY,x             ; order them by drawn top
        cmp DrawY,y
        bcc .order              ; X already the upper one
        stx Temp
        tya
        tax
        ldy Temp
.order:
        stx Temp
        sty NewX
        lda DrawY,x
        clc
        adc DrawH,x
        sta RepoDU
        cmp #SCREEN_DU-3        ; the nudge adds up to 2 and the hop
        bcs .no                 ; must land before the last du
        adc #2                  ; (carry clear) 1 du hop + 1 du margin
        cmp DrawY,y
        bcc .yes
        beq .yes
.no:
        clc
        rts
.yes:
        sec
        rts

; FillP1: X = char. Loads P1's draw slot, color, size and vblank
; position from that character.
FillP1:
        SUBROUTINE
        lda DrawY,x
        sta P1Top
        lda DrawH,x
        sta P1Hgt
        lda EyeByte,x
        sta P1Eye
        lda CharX,x
        sta P1XA
        lda NusizTbl,x
        sta NUSIZ1              ; Alex doubled, Marcus single
        lda ColBriTbl,x         ; one colour per character in play
                                ; (decision #49). Held vs free was a
                                ; luma step (#27's +2), but in one
                                ; player the free pair flickered and
                                ; were lifted +2 back onto it, so the
                                ; step never reached the screen; and
                                ; in two players the solid free one
                                ; drew dim — Marcus at $82 vanished
                                ; on the dark home blocks — while a
                                ; held Alex sharing P1 in a level
                                ; frame was lifted $CE+2 = $D0, a
                                ; wrong hue at black. The eyes carry
                                ; "free" (squint), the flicker
                                ; carries it in one player.
        sta COLUP1
        rts

; A = x pixel (0-159), X = object (0=P0 1=P1)
SetHorizPos:
        SUBROUTINE
        sta WSYNC
        sec
.div:
        sbc #15
        bcs .div
        eor #7
        asl
        asl
        asl
        asl
        sta HMP0,x
        sta RESP0,x
        rts

; ---------------------------------------------------------------
; GameKernel: 96 double-lines, three characters on two players.
; (The proven multiplexer kernel — unchanged from the workbench.)
; ---------------------------------------------------------------

GameKernel:
        SUBROUTINE
        ldx #0                  ; X = du counter (all 96 of them)
        ldy #0                  ; Y = band index (never clobbered)
        lda #9
        sta BandLine
        lda SkyGrad
        sta COLUBK
        lda (PFColPtr),y        ; band 0 platform colour
        sta COLUPF
        lda (PF0Ptr),y
        sta PF0
        lda (PF1Ptr),y
        sta PF1
        lda (PF2Ptr),y
        sta PF2
        ; NO pre-loop prefetch. Y stays on band 0, and the loop does
        ; every fetch: the prefetch at du 7 pulls band 1, the swap at
        ; du 8 stores it. Priming K* with band 1 here as well looked
        ; harmless but was not — du 7's prefetch OVERWROTE it with band
        ; 2 before du 8's swap could consume it, so band 1 was never
        ; drawn, every band after it appeared 8 du early (which also
        ; skipped a step of the sky gradient), and the last 8 du fell
        ; off the end of the 12-byte tables into band "12":
        ; PF2Ptr[12] is the record's first collision-box TOP (88 =
        ; $58), so the bottom of every floor wore four ghost blocks in
        ; the shape of a number, and KCol read past the lamp table into
        ; TextEnd. The leftovers also bled into the next frame's first
        ; line (see Overscan).
.kloop:
        sta WSYNC               ; ---- line 1
        dec BandLine
        beq .swap               ; boundary: stores only, in hblank
        lda BandLine
        cmp #1
        beq .prefetch           ; the line before: indexed loads
        bne .line2
.swap:
        ; ORDER MATTERS: hblank is 68 colour clocks = 22.6 CPU cycles,
        ; so only stores completing by cycle 22 land before the beam
        ; reaches visible pixel 0. Everything after that is chasing the
        ; beam. Each register's deadline is when it FIRST displays:
        ; COLUBK and PF0 from px 0, PF1 from px 16, PF2 from px 32.
        ; COLUBK used to sit fifth, completing at cycle 32 = px 28, so
        ; the leftmost 28 of 160 px kept the previous band's sky for one
        ; scanline — a visible jog at every band boundary, all at the
        ; same x, which the eye joins into a vertical seam down the
        ; screen. Harmless-looking on the old violet gradient; obvious
        ; on a neutral ramp. It goes first now.
        lda KSky
        sta COLUBK              ; @14 — inside hblank, px 0 is correct
        lda KPF0
        sta PF0                 ; @20 — inside hblank (displays px 0)
        lda KPF1
        sta PF1                 ; @26 -> px 10, displays from px 16
        lda KPF2
        sta PF2                 ; @32 -> px 28, displays from px 32
        lda KCol
        sta COLUPF              ; @38 -> px 46; lamps start px 48
        lda #8
        sta BandLine
        bne .line2
.prefetch:
        iny                     ; Y rests on the next band from here;
        lda SkyGrad,y           ; the boundary line only stores.
        sta KSky                ; (PrepSprites keeps the P1 hop off
        lda (PF0Ptr),y          ; BOTH special lines.)
        sta KPF0
        lda (PF1Ptr),y
        sta KPF1
        lda (PF2Ptr),y
        sta KPF2
        lda (PFColPtr),y
        sta KCol
.line2:
        sta WSYNC               ; ---- line 2
        txa                     ; active character (P0)
        sec
        sbc P0Top
        cmp P0Hgt
        bcs .p0off
        cmp #EYEROW
        beq .p0eye
        lda #$FF
        bne .p0set
.p0eye:
        lda P0Eye               ; never zero: blink = solid body
        bne .p0set
.p0off:
        lda #0
.p0set:
        sta GRP0
        txa                     ; P1's current tenant
        sec
        sbc P1Top
        cmp P1Hgt
        bcs .p1off
        cmp #EYEROW
        beq .p1eye
        lda #$FF
        bne .p1set
.p1eye:
        lda P1Eye
        bne .p1set
.p1off:
        lda #0
.p1set:
        sta GRP1
        inx
        cpx RepoDU              ; time for the mid-frame P1 hop?
        beq .repo
        cpx #SCREEN_DU
        bne .kloop
        rts

.repo:
        lda #0                  ; the old tenant's pattern must die
        sta GRP1                ; before RESP1 moves the sprite
        lda P1X2
        sta WSYNC               ; ---- repo line 1: reposition P1
        sec                     ; (post-WSYNC timing = SetHorizPos)
.rdiv:
        sbc #15
        bcs .rdiv
        eor #7
        asl
        asl
        asl
        asl
        sta HMP1
        sta RESP1               ; @<=72 for x<=148: tightest line
        sta WSYNC               ; ---- repo line 2
        sta HMOVE               ; @3 — fine shift
        dec BandLine            ; line 1's skipped bookkeeping;
                                ; RepoDU is never a boundary du
        txa                     ; P0 (active) draws through the hop
        sec
        sbc P0Top
        cmp P0Hgt
        bcs .r0off
        cmp #EYEROW
        beq .r0eye
        lda #$FF
        bne .r0set
.r0eye:
        lda P0Eye
        bne .r0set
.r0off:
        lda #0
.r0set:
        sta GRP0
        lda P1Col2              ; P1 becomes the second tenant
        sta COLUP1
        lda P1Nu2
        sta NUSIZ1
        lda P1Y2
        sta P1Top
        lda P1H2
        sta P1Hgt
        lda P1Eye2
        sta P1Eye
        inx
        jmp .kloop              ; (repo du is never du 95)

; ---------------------------------------------------------------
; ---------------------------------------------------------------
; Character data (index 0 = Stella, 1 = Alex, 2 = Marcus)
; ---------------------------------------------------------------

HeightTbl:  .byte STELLA_H, ALEX_H, MARCUS_H
WidthTbl:   .byte 8, 16, 8
SpeedTbl:   .byte 1, 2, 1           ; Stella slow, Alex fast...
SpeedHalfTbl: .byte 0, 0, 1         ; ...Marcus 1.5 (the balance)
MaxXTbl:    .byte 156-8, 156-16, 156-8
JumpHiTbl:  .byte $FD, $FE, $FD     ; Stella -2.875 (rise 21 du),
JumpLoTbl:  .byte $20, $10, $80     ; Alex -1.9375 (10),
                                    ; Marcus -2.5 (16): highest,
                                    ; lowest, and in between.
                                    ; (Marcus +0.125 vs the workbench
                                    ; so he can mount Floor 2's 16-du
                                    ; sill — decision #21's "medium
                                    ; jump" made load-bearing; the
                                    ; solver re-proves every floor
                                    ; against these exact tables)
                                    ; SERIES PALETTE (decision #27) —
                                    ; identical bytes in Game 1. Stella
                                    ; is hue $3, the red design-document
                                    ; .md specifies as $30; Alex $C,
                                    ; Marcus $8.
ColBriTbl:  .byte $38, $CE, $84     ; LUMA-ORDERED: Marcus darkest,
ColDimTbl:  .byte $36, $CC, $82     ; Stella mid, Alex brightest — in
                                    ; every MIX that reaches the screen,
                                    ; not merely within each table.
                                    ; Active is +2, and +2 is the most
                                    ; the hardware allows: three
                                    ; characters over the TIA's 8 luma
                                    ; steps need dim tiers 4 apart, so a
                                    ; +4 boost would lift the active
                                    ; character onto its neighbour's
                                    ; luma. The old tables ($4A/$CE/$86
                                    ; over $46/$CA/$82, active +4) did
                                    ; exactly that: with Stella active
                                    ; she and Alex were both luma A, and
                                    ; with Marcus active he and Stella
                                    ; were both luma 6 — two of the
                                    ; three states colour-blind-unsafe,
                                    ; which is the one thing #27 exists
                                    ; to prevent. "Which one is mine" is
                                    ; carried by the never-flickering P0
                                    ; slot, the wide-awake eyes and the
                                    ; fast lamp blink, so the active cue
                                    ; can afford to be the subtle one.
NusizTbl:   .byte $00, $05, $00     ; Alex is double-width on P1
EyeTbl:     .byte EYES_L, EYES_R, EYES_LSQ, EYES_RSQ ; held, then free
PadBitTbl:  .byte $80, $40       ; FirePrev / UpPrev bit per joystick
OtherATbl:  .byte 1, 0, 0           ; the two possible head-perches
OtherBTbl:  .byte 2, 2, 1           ; for each character


; per-band gradient shape: brighter toward the horizon (5 shades)
GradOfs:    .byte 0,0,0,2,2,2,4,4,6,6,8,8
GradOfsR:   .byte 8,8,6,6,4,4,2,2,2,0,0,0   ; world B: the ramp reversed

; ===============================================================
; FLOOR TABLE — the game walks this in order (FloorSeq).
; Each floor: record ptr, per-character home-CharY table, wrap flag,
; sky base, its post-floor narration screen, and its act. Adding a
; floor = one entry in each of these + a Floor?Rec + a Floor?HomeCharY
; + a narration string in tools/gentext.py.
; ===============================================================

FloorRecLo:   .byte <Floor1Rec, <Floor2Rec, <Floor3Rec
        .byte <Floor4Rec, <Floor5Rec, <Floor6Rec
        .byte <Floor7Rec, <Floor8Rec, <Floor9Rec
FloorRecHi:   .byte >Floor1Rec, >Floor2Rec, >Floor3Rec
        .byte >Floor4Rec, >Floor5Rec, >Floor6Rec
        .byte >Floor7Rec, >Floor8Rec, >Floor9Rec
FloorHomeLo:  .byte <Floor1Home, <Floor2Home, <Floor3Home
        .byte <Floor4Home, <Floor5Home, <Floor6Home
        .byte <Floor7Home, <Floor8Home, <Floor9Home
FloorHomeHi:  .byte >Floor1Home, >Floor2Home, >Floor3Home
        .byte >Floor4Home, >Floor5Home, >Floor6Home
        .byte >Floor7Home, >Floor8Home, >Floor9Home
FloorWrapTbl: .byte 1, 1, 1           ; wrap is the always-on baseline
        .byte 1, 1, 1                 ; (decision #18) — every act
        .byte 1, 1, 1
FloorSkyTbl:  .byte FLOOR1_SKY, FLOOR1_SKY, FLOOR1_SKY
        .byte FLOOR1_SKY, FLOOR1_SKY, FLOOR1_SKY  ; per-act palettes: TODO
        .byte FLOOR1_SKY, FLOOR1_SKY, FLOOR1_SKY
; Act boundaries are a comment, not a table (the ROM never read it):
; floors 1-3 = Act 1 (wrap), 4-6 = Act 2 (portal), 7-9 = Act 3
; (world-swap), 10 = the finale (decision #18).
;
; RIFT TABLE (Act 3): the PF0 bit position of the floor's rift pair,
; as the left edge x of the left column (4 = PF0 bit5 -> px 4-7, with
; the mirror at 152-155 free). 255 = no rift. The mirror range is
; [156-L, 160-L) — InRift tests both. Rifts always live in PF0: the
; frame/floor plane is the one plane both worlds share.
FloorRiftL:  .byte 255,255,255
        .byte 255,255,255
        .byte   4,  4,  4
; char*3 — indexes both FloorBandByChar (char*3 + floor) and each
; floor's Floor?Home table (three bytes per character).
MulThree:     .byte 0, 3, 6
; char*NUM_FLOORS: the stride for the per-character band table, which
; is laid out a row per character (see .lamp). Distinct from MulThree,
; which strides the three-byte-per-character Floor?Home tables.
MulNine:      .byte 0, 9, 18
; The lamp band for each character on each floor (char*9 + floor,
; indexed by MulNine); PrepSprites paints these bands as the
; colour-blind-safe home lamps. A band is a full-width 8du stripe and
; it is the DRAWN LEDGE a home sits on, so the value must contain the
; home's surface (homeY + height) — the feet's du, not the body's.
; check_levels.py audits both of those rules; the table's own comment
; used to claim them and nothing checked.
FloorBandByChar:
        .byte 8, 7, 6, 1, 2, 2, 3, 5, 5   ; Stella
        .byte 9, 9, 8, 4, 9, 7, 5, 7, 7   ; Alex
        .byte 7, 8, 10, 2, 5, 5, 4, 6, 6 ; Marcus

; ---------------------------------------------------------------
; PORTAL TABLES (Act 2). Per floor: two column LEFT edges (columns
; are always 8px, so R = L+8) — a floor with no portals parks
; FloorPortL at 255; a floor with one column parks FloorPort2L at 255
; — and per column a MOUTH (arrival x + feet du), interleaved
; floor*2+column so DoTeleport is one indexed load. The mouths carry
; the puzzle: a column can lift (F4), be gated (F5), or cross the
; screen to somewhere its twin isn't (F6). The plane is derived from
; x, not tabled: columns left of 48 live in PF1, the rest in PF2 (the
; mirror always lands in the same plane). The OFF plane (the same 12
; band bytes minus the column mask) sits at record+66. The solver
; reads all of this from the ROM and re-proves the columns are where
; the art says — tables and art cannot drift apart.
;
; BOTH TABLES ARE NUM_FLOORS LONG. They used to be six entries and
; were indexed by FloorSeq, which is 0..8: floors 7-9 read PAST the
; end. It happened to be harmless — the bytes that followed were
; FloorPort2L's own leading 255s, so the ROM bailed out correctly by
; luck — but the solver read FloorPort2L+6 and found a 0 instead of
; the 255 sentinel, and invented a portal column at x=[0,8) on three
; floors that have none. On F8/F9 that phantom edge drops a body at
; feet 56, which is Alex's home height on both. Correct-by-accident
; is not correct; nine entries of 255 cost six bytes and bank 0 has
; 429 to spare.
; --------------------------------------------------------------
FloorPortL:  .byte 255,255,255, 32, 76,  40
        .byte 255,255,255
FloorPort2L: .byte 255,255,255,120,255, 112
        .byte 255,255,255
FloorMouX:   .byte   0,  0,   0,  0,   0,   0
        .byte 124,  36                 ; F4: L col -> right column's
                                      ; shelf spot; R col -> left
                                      ; column's ground spot
        .byte  76,  0                 ; F5: the one central column ->
                                      ; the shelf above it
        .byte 124,  52                 ; F6: the doors CROSS — L col ->
                                      ; Alex's right ledge; R col ->
                                      ; the shelf's left end
        .byte   0,  0,   0,   0,   0,   0 ; F7-F9: no portals, parked
FloorMouY:   .byte   0,  0,   0,  0,   0,   0
        .byte  32, 88                 ; F4: shelf top / ground
        .byte  40,  0                 ; F5: shelf top
        .byte  62, 40                 ; F6: ledge top / shelf top
        .byte   0,  0,   0,   0,   0,   0 ; F7-F9

; 12 black bands for the wake-up opening's unlit playfield, and 12
; plain-grey bands for the reveal (lamps start with player control)
BlackPF:      .byte 0,0,0,0,0,0,0,0,0,0,0,0
GreyPF:       .byte $0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A

; ===============================================================
; ACT 1, FLOOR 1 — "Together Again"
;
; The first REAL floor. All three characters, controllable (Down+Fire
; cycles Stella -> Alex -> Marcus), on a clean mirrored screen with
; wrap ON. Three per-colour HOMES form a central totem: three centred
; 8px one-way ledges (px 76-83, drawn by PF2 bit7 mirrored) stacked at
; three heights, each tinted its owner's colour by the kernel's
; per-band COLUPF (red = Stella low ledge 76, green = Alex mid ledge
; 68, blue = Marcus top ledge 58 — the new arrival crowns the totem).
; Completes only when ALL THREE stand on their own-colour ledge.
;
; The cooperative beat, and WHO OWNS WHICH LEDGE. The homes are assigned
; by what each character's own jump naturally CATCHES, because on a
; totem the ledges shadow one another: falling, you land on the first
; surface your feet cross, so a strong jump sails past its own ledge and
; lands on the one above.
;
; Originally Stella owned the low ledge (76) and Alex the mid (68), and
; the obvious move — stand under the totem, press fire — put EVERY
; character on the wrong ledge. Stella rises 20.6 du from the ground, so
; her feet peak at 67 and she catches 68 (Alex's) on the way down, every
; time; her own ledge sat 8 du below in the shadow of a WIDER one, so no
; jump could ever reach it from above. It was reachable — the solver
; proved it, from 15 positions — but only by arcing in from the side so
; you slip past 68 outside its x range and drop onto 76. A pixel-perfect
; move, on the first floor of the game, teaching nothing. Playtest found
; it "really hard" and playtest was right.
;
; So Stella and Alex swapped homes, and the shape echo (#27) followed
; Alex down — the double-wide ledge is wherever Alex lives. Now:
;   Stella (rise 20.6, peaks at 67): one jump from the ground lands her
;     on the MID ledge 68. Her home, first try, no instruction.
;   Marcus (rise 15.4): peaks at 72, catches the LOW ledge 76; from
;     there 68; from there his own TOP ledge 58. A three-hop solo climb
;     where every hop lands on the next rung, because his weaker jump
;     cannot overshoot one.
;   Alex (rise 9.1): peaks at 78.9 and catches NOTHING from the ground —
;     the low ledge is 12 du up. A friend stands on the ground as a
;     stepstool, he hops from their head, and lands exactly on the LOW
;     ledge 76, his home. One boost, and the only boost on the floor.
;
; tools/check_levels.py proves Alex needs that boost while Stella and
; Marcus finish alone — a genuine, load-bearing "not alone" beat.
; ===============================================================

; Each character's home, three bytes: the CharY it stands at (ledge top
; minus its height — Stella 76-9, Alex 68-3, Marcus 58-6) and the
; ledge's x extent [left, right). AtHome needs both.
; (Reworked from 76/68/60 with green/blue swapped when Marcus's jump
; grew to 16 du: his overshoot from the 76 ledge landed exactly on
; the old 60 ledge and his own 68 became unreachable — caught by the
; solver. Now the NEW ARRIVAL crowns the totem: Marcus's blue home
; is the top, two 76->68->58 hops of 8 and 10 du; Alex's green home
; is the middle.)
Floor1Home:
        .byte 59, 76,  84       ; Stella: MID ledge 68, narrow column
        .byte 73, 72,  88       ; Alex:   LOW ledge 76, double-wide (echo)
        .byte 52, 76,  84       ; Marcus: TOP ledge 58, crowning the totem

; The Floor-1 level record (66-byte layout). Open frame (wrap), a
; full-width floor, and three centred one-way home ledges. SHAPE
; ECHO (decision #27): each ledge's width matches its owner's body —
; Alex's mid ledge is double-wide (16px, PF2 bits 6-7) like his flat
; wide self; Stella's and Marcus's are the narrow 8px column.
;   PF0: open edges (top bands clear so x wraps); floor band = $F0
;   PF1: floor band only ($FF)
;   PF2: home ledges bands 7/8/9 (band 8 wide); $FF floor
Floor1Rec:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$80,$80,$C0,$00,$FF
        .byte  88, 76, 68, 58, $FF,$FF    ; box tops  (ledges one-way:
        .byte  96, 76, 68, 58, $FF,$FF    ; box bottoms   top == bottom)
        .byte   0, 72, 76, 76,   0,   0   ; box lefts
        .byte 160, 88, 84, 84,   0,   0   ; box rights (excl)
        .byte 20, 79                      ; Stella: ground, left
        .byte 40, 85                      ; Alex: ground, mid-left
        .byte 76, 70                      ; Marcus: PERCHED on the low
                                          ; ledge, not on the ground.
                                          ; Three characters standing on
                                          ; one floor all have their feet
                                          ; at du 88, so every pair
                                          ; overlaps and P1's two tenants
                                          ; can only alternate at 30Hz —
                                          ; the worst case, permanently,
                                          ; on the first floor of the
                                          ; game (#19 warned that level
                                          ; design has to buy the
                                          ; separation). Lifting the new
                                          ; arrival onto the totem's
                                          ; first step separates him from
                                          ; both, and it reads better
                                          ; too: he wakes already part
                                          ; way up the thing they are
                                          ; about to climb.

; ===============================================================
; ACT 1, FLOOR 2 — "The Low Door"
;
; Marcus's discoverable gift (decision #21). A wide raised SILL
; (top 72, x 48-112) carries a roof SLAB (56-64, x 64-96); between
; slab bottom and sill top runs an 8-du TUNNEL. Inside, floating 2 du
; over the sill, sits Marcus's blue HEART perch (one-way, top 70,
; x 76-84) — his home.
;
;   Stella (9 tall, rise 21): mounts the sill's exposed WINGS
;     (48-64 / 96-112) but is 1 du too tall for the tunnel slot —
;     she stands at the threshold, blocked. Her home: she alone can
;     jump the 16-du rise from wing to SLAB TOP. She cannot fit
;     through the door, but only she stands on top of it.
;   Alex (rise 10): the 16-du sill defeats his jump — a friend's
;     head (the Floor 1 lesson) lifts him to his green wing home.
;   Marcus (6 tall, rise 16): mounts the wing exactly, squeezes the
;     tunnel exactly, bonks the slab and drops neatly onto his
;     heart. One failure each for the others; his insight forever.
;
; The solver proves: everyone homes; Marcus homes ALONE; Stella can
; NEVER reach his heart; Alex genuinely needs the boost.
; Honesty ledger: the heart's one-way top (70) sits low in its drawn
; band (64-71), Game 1 RC2's documented few-du art allowance.
; ===============================================================

; home CharY + x extent: Stella slab 56-9, Alex wing 72-3 (either wing —
; the sill top is his home along its whole width), Marcus heart 70-6
Floor2Home:
        .byte 47, 64,  96       ; Stella: the slab roof
        .byte 69, 48, 112       ; Alex:   the sill top
        .byte 64, 76,  84       ; Marcus: the heart, inside the door

; Lamp bands (FloorBandByChar): 7 = slab (Stella), 8 = heart
; (Marcus), 9 = sill top (Alex); the sill's lower band stays tan.
Floor2Rec:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$F0,$80,$FF,$FF,$FF
        .byte  88, 72, 56, 70,$FF,$FF     ; tops: ground,sill,slab,heart
        .byte  96, 88, 64, 70,$FF,$FF     ; bottoms (heart is one-way)
        .byte   0, 48, 64, 76,  0,  0     ; lefts
        .byte 160,112, 96, 84,  0,  0     ; rights (excl)
        .byte 16, 79                      ; Stella: ground, far left
        .byte 32, 85                      ; Alex: ground, left
        .byte 136, 82                     ; Marcus: ground, right —
                                          ; the tower sorted them

; ===============================================================
; ACT 1, FLOOR 3 — "The Wall"
;
; The wrap twist — the banked "decoy platforms, wrap is the answer"
; puzzle. A wall on the mirror axis (decision #20: reads as one
; clean object) runs from the sky to the ground (top 8: even a
; three-friend tower stack tops out at feet 18 — proven, so there is
; NO way over). Three buttress stairs hug it (b1 80 / b2 64 / b3 48,
; each mountable from beside, never beneath), climbing 8-16-16: a
; staircase that promises the top and lies. The stairs are the
; homes, painted on the wall as colour courses: blue 80 (Marcus),
; green 64 (Alex), red 48 (Stella).
;
; Alex wakes ALONE on the far side. His green course needs a 16-du
; rise his jump cannot make, and every friend is behind the wall. The
; answer is the floor's name in negative: the world is a cylinder —
; walk AWAY from the wall, off the edge of the screen, and arrive
; beside him. The solver proves the floor UNSOLVABLE with wrap off:
; the twist is load-bearing, not decoration.
;
; STAIR WIDTHS, and why they are what they are. The wall splits every
; stair into two exposed shelves, one either side, and those shelves
; are the only places anyone can stand. They used to taper 16px / 8px /
; 4px going up, which put STELLA — 8px wide — on a 4px shelf, so she
; was always half off the ledge she lived on, and her home scored 6
; ways in on the playability check: a trick shot, the same score as the
; Floor 1 that playtest rejected.
;
; Now the shelves are sized to their OWNERS (the #27 shape echo, which
; the old widths had backwards — the 16px character stood on the 8px
; shelf and the 8px character on the 4px one):
;   b1 80  Marcus  20px shelves — the buttress base, widest
;   b2 64  Alex    16px shelves — exactly his 16px body
;   b3 48  Stella   8px shelves — exactly her 8px body
; Still tapering upward, so it still reads as a staircase that promises
; the top and lies. Stella goes 6 -> 14 ways in, Alex 30 -> 22 (still
; comfortable), Marcus 48 -> 56, and every proof holds: solvable,
; unsolvable with wrap off, Alex still unable to finish alone.
;
; Chosen by searching the buildable widths rather than by eye — the
; result is not monotonic (widening Stella's shelf to 16px makes the
; floor UNSOLVABLE, and the shape-echo-perfect widths only work once
; b1 widens to keep it distinct from b2), which is not something
; guessing would have found.
; ===============================================================

; home CharY + x extent: the three buttress stairs, Stella b3 48-9,
; Alex b2 64-3, Marcus b1 80-6
Floor3Home:
        .byte 39, 64,  96       ; Stella: b3, top stair, 8px shelves
        .byte 61, 56, 104       ; Alex:   b2, mid stair, 16px shelves
        .byte 74, 52, 108       ; Marcus: b1, bottom stair, 20px shelves

; Lamp bands (FloorBandByChar): 6 = b3 (Stella), 8 = b2 (Alex),
; 10 = b1 (Marcus) — the wall wears each stair's lamp as a painted
; course at its height.
Floor3Rec:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$C0,$C0,$C0,$C0,$C0,$F0,$C0,$FC,$C0,$FE,$FF
        .byte  88,  8, 80, 64, 48,$FF     ; tops: ground,wall,b1,b2,b3
        .byte  96, 88, 88, 70, 54,$FF     ; bottoms
        .byte   0, 72, 52, 56, 64,  0     ; lefts
        .byte 160, 88,108,104, 96,  0     ; rights (excl)
        .byte 12, 79                      ; Stella: ground, far left
        .byte 140, 85                     ; Alex: ALONE past the wall
        .byte 28, 82                      ; Marcus: ground, left

; ===============================================================
; ACT 2, FLOOR 4 — "The Fold"
;
; The portal introduce floor, and Act 2's locked room. One full-width
; SHELF floats at top 32 with every home on or above it — and NOTHING
; climbs there: the strongest solo jump tops out at feet 67 (Stella),
; the strongest three-friend stack-jump at ~58, and the shelf's
; underside is at 40. Eighteen du of proof margin. The only way up is
; the pair of blinking columns: stand in either, press UP, arrive at
; the other column's height-adjusted mouth on the shelf.
;
; The columns are PF1 bits 3+2 (px 32-39 and the mirror 120-127),
; blinking by pointer swap. LEFT column -> the RIGHT column's spot on
; the shelf (124, 32); RIGHT column -> the LEFT column's spot on the
; ground (36, 88): the way back down, so nobody is ever stranded on
; the shelf and the pair reads as two ends of one door.
;
; Homes are deliberately gentle — the work was noticing the door:
;   Stella: a high one-way ledge (top 14, on the mirror axis) — from
;     the shelf (32) a rise of 18; hers alone (Marcus peaks 4 du low).
;   Marcus: either of the twin low ledges (top 22, x 16-31 & 128-143 —
;     mirrored pairs share one home zone, the Floor-3 pattern).
;   Alex: the shelf ITSELF (his zone spans it, like Floor 2's sill —
;     the wide green lamp band paints exactly his home).
;
; tools/check_levels.py proves the floor UNSOLVABLE with the portal
; off (nothing reaches the shelf), which is what makes the column the
; lesson and not a flourish.
; ===============================================================

Floor4Home:
        .byte  5, 64,  96       ; Stella: high ledge (top 14), band 1
        .byte 29,  0, 160       ; Alex:   the whole shelf (32), band 4
        .byte 16, 16, 144       ; Marcus: twin ledges (22), band 2

Floor4Rec:
;   PF0: open edges (wrap); shelf band 4; floor band 11
        .byte $00,$00,$00,$00,$F0,$00,$00,$00,$00,$00,$00,$F0
;   PF1 (portal plane, ON): columns $0C in bands 0-10; band 2 adds
;   Marcus's ledges ($F0|$0C=$FC); band 4 the shelf ($FF); band 11 floor
        .byte $0C,$0C,$FC,$0C,$FF,$0C,$0C,$0C,$0C,$0C,$0C,$FF
;   PF2: band 1 Stella's ledge ($F0, axis 64-95); band 4 shelf; floor
        .byte $00,$F0,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$FF
;   boxes: ground / shelf / Stella's ledge (one-way) / Marcus's twins
        .byte  88, 32, 14, 22, 22,$FF    ; tops
        .byte  96, 40, 14, 22, 22,$FF    ; bottoms (one-way: top==bottom)
        .byte   0,  0, 64, 16,128,  0    ; lefts
        .byte 160,160, 96, 32,144,  0    ; rights (excl)
        .byte 148, 79                     ; Stella: ground, far right
        .byte 104, 85                     ; Alex: ground, right
        .byte  60, 82                     ; Marcus: ground, mid-left
;   PF1 OFF (record+66): the same bands minus the $0C column mask
        .byte $00,$00,$F0,$00,$FF,$00,$00,$00,$00,$00,$00,$FF

; ===============================================================
; ACT 2, FLOOR 5 — "The High Door"
;
; Develop: the old verb gates the new one. The portal column stands on
; the mirror axis (PF2 bit7 -> px 76-83, self-mirrored), but its ground
; entrance sits in a SLOT between two guard walls (tops 72 — a 16-du
; mount): Stella clears it, Marcus clears it exactly (the Floor 2 sill
; again), Alex's 10-du jump never will. Alex reaches the door the way
; he reached Floor 1's ledge: off a friend's head. Then UP, and the
; mouth is on the shelf (top 40) spanning the slot above.
;
; The boost is load-bearing AND so is the portal, and the solver proves
; both: portal-off, nothing reaches the shelf (stack-jumps peak at ~58,
; the shelf's underside is 48); Alex alone never passes the guards.
;
; Homes:
;   Alex: the guard LINTELS themselves (top 72, either one — the twin
;     zone). The boost that was always his floor-1 duty is here his
;     destination: the door was high, and the high place is his.
;   Marcus: the shelf (whole-shelf zone; he arrives on it).
;   Stella: a one-way ledge (top 22, axis) above the shelf — a rise of
;     18 from the shelf; only her jump makes it.
;
; The column shares PF2 with everything interior this floor, so the OFF
; plane matters: bands 9-10 keep the guards ($0E) and lose the column
; ($80); bands 2/5 keep ledge/shelf ($F0/$FF) untouched.
; ===============================================================

Floor5Home:
        .byte 13, 64,  96       ; Stella: ledge (top 22), band 2
        .byte 69, 52, 108       ; Alex: either guard lintel (72), band 9
        .byte 34,  0, 160       ; Marcus: the shelf (40), band 5

Floor5Rec:
;   PF0: open edges; floor band 11
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0
;   PF1: floor only
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
;   PF2 (portal plane, ON): central column $80 in bands 0-10; band 2
;   Stella's ledge ($F0); band 5 the shelf ($FF); bands 9-10 the
;   guards ($0E|$80=$8E); band 11 floor
        .byte $80,$80,$F0,$80,$80,$FF,$80,$80,$80,$8E,$8E,$FF
;   boxes: ground / guardL / guardR / shelf / Stella's ledge (one-way)
        .byte  88, 72, 72, 40, 22,$FF    ; tops
        .byte  96, 88, 88, 48, 22,$FF    ; bottoms
        .byte   0, 52, 96, 48, 64,  0    ; lefts
        .byte 160, 64,108,112, 96,  0    ; rights (excl)
        .byte  16, 79                     ; Stella: ground, far left
        .byte 120, 85                     ; Alex: ground, right of the slot
        .byte 140, 82                     ; Marcus: ground, far right
;   PF2 OFF (record+66): minus the $80 column bit
        .byte $00,$00,$F0,$00,$00,$FF,$00,$00,$00,$0E,$0E,$FF

; ===============================================================
; ACT 2, FLOOR 6 — "The Cross"
;
; The twist. Two portal pairs, and the doors CROSS the screen: the LEFT
; column (px 40-47) exits high RIGHT — on Alex's dive ledge (top 62);
; the RIGHT column (112-119) exits back LEFT — on the shelf (top 40).
; After two floors of "portals go up", the doors turn out to go
; *sideways*: each column's mouth is nowhere near its twin.
;
; Nobody's route is another's:
;   Alex walks into the left column on the ground and steps out onto
;     his ledge — arrival IS home (the gentlest ride; his second gift
;     after speed is that doors like him).
;   Marcus rides the right column to the shelf's left end; the whole
;     shelf is his home (the Floor 2 sill rule).
;   Stella rides the right column too, then claims the one thing the
;     doors don't hand out: her perch (top 22, axis) is an 18-du rise
;     off the shelf — only her jump closes the act.
;
; Every home needs a door: portal-off, the highest stack-jump (~58 du)
; can't touch the shelf's underside (48), let alone the perch. The
; ledges are mirrored twins sharing one zone (the Floor 3 pattern), so
; Alex's band-7 lamp paints exactly his two possible homes.
; ===============================================================

Floor6Home:
        .byte 13, 64,  96       ; Stella: perch (top 22), band 2
        .byte 59, 16, 144       ; Alex: twin dive ledges (62), band 7
        .byte 34,  0, 160       ; Marcus: the shelf (40), band 5

Floor6Rec:
;   PF0: open edges; floor band 11
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0
;   PF1 (portal plane, ON): columns $03 in bands 0-10; band 7 adds
;   Alex's ledges ($FC|$03=$FF); band 11 floor
        .byte $03,$03,$03,$03,$03,$03,$03,$FF,$03,$03,$03,$FF
;   PF2: band 2 Stella's perch ($F0, axis 64-95); band 5 the shelf
;   ($FF, 48-111 mirrored); band 11 floor
        .byte $00,$00,$F0,$00,$00,$FF,$00,$00,$00,$00,$00,$FF
;   boxes: ground / shelf / Stella's perch / Alex's ledges (one-way)
        .byte  88, 40, 22, 62, 62,$FF    ; tops
        .byte  96, 48, 22, 62, 62,$FF    ; bottoms
        .byte   0, 48, 64, 16,120,  0    ; lefts
        .byte 160,112, 96, 40,144,  0    ; rights (excl)
        .byte   8, 79                     ; Stella: ground, far left
        .byte  24, 85                     ; Alex: ground, left
        .byte 136, 82                     ; Marcus: ground, right — near
                                          ; the door that isn't his
;   PF1 OFF (record+66): minus the $03 column mask
        .byte $00,$00,$00,$00,$00,$00,$00,$FC,$00,$00,$00,$FF

; ===============================================================
; ACT 3 — the world-swap floors. Each dual floor's record is 126
; bytes: the 66-byte world-A record, the PF0 OFF copy for the rift
; blink (+66), then world B's interior planes (+78/+90) and boxes
; (+102). PF0 — frame, floor, rifts — is the shared plane: the things
; BOTH truths agree on. The grammar that keeps three characters safe
; (the workbench was Stella-only and never faced it): swaps are
; grounded-only and rift-gated, and EVERY box that differs between
; worlds is one-way, so no body can ever be left inside a new wall —
; the worst a swap can do is drop you. check_levels.py audits both.
; ===============================================================

; ===============================================================
; ACT 3, FLOOR 7 — "Two Truths"
;
; The introduce floor, and the act's locked room. All three homes sit
; on a shared shelf-and-totem at mid-screen — VISIBLE from the first
; frame, lamps blinking — and unreachable in world A: the shelf's top
; is 40, and the best three-friend stack-jump the engine allows peaks
; at feet ~58. World A is a flat room with a thin blinking beam at its
; edges. The beam is the only move.
;
; UP in the beam (grounded) swaps the world: same room, same shelf —
; but world B HAS the approach ladder (two one-way ledges, 72 and 56,
; that were never there in A). The truths differ only in what you can
; STAND on, which is the act's grammar: every box that differs between
; worlds is one-way, so a swap can never leave a body inside a new
; wall — the worst it does is drop you. (A solid wall that exists in
; only one world — the workbench's T1 — is exactly the design this
; grammar forbids: with three characters, a friend standing where the
; wall reappears would be embedded. The workbench was Stella-only and
; never faced it.)
;
; The ladder's 16-du hops gate Alex out (his 10-du jump): he is
; boosted up the ladder — Floor 1's lesson, the act remembering it —
; while Stella and Marcus climb alone. The solver proves world A alone
; can never reach any home.
; ===============================================================

Floor7Home:
        .byte 15, 72,  88       ; Stella: totem crown (top 24), band 3
        .byte 37, 48, 112       ; Alex:   the shelf itself (40), band 5
        .byte 26, 64,  96       ; Marcus: totem middle (32), band 4

Floor7Rec:
;   PF0 (shared): the rift (b5 = px 4-7 & mirror 152-155) bands 0-10;
;   floor band 11
        .byte $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$F0
;   PF1 world A: floor only (no ladder in this truth)
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
;   PF2 world A: band 3 the totem crown ($C0 = 72-87, axis); band 4
;   the totem middle ($F0 = 64-95); band 5 the shelf ($FF = 48-111);
;   floor
        .byte $00,$00,$00,$C0,$F0,$FF,$00,$00,$00,$00,$00,$FF
;   boxes A: ground / shelf (solid) / totem ledges (one-way)
        .byte  88, 40, 32, 24,$FF,$FF      ; tops
        .byte  96, 48, 32, 24,$FF,$FF      ; bottoms
        .byte   0, 48, 64, 72,  0,  0      ; lefts
        .byte 160,112, 96, 88,  0,  0      ; rights (excl)
        .byte  20, 79                      ; Stella: ground, left
        .byte  28, 85                      ; Alex: ground, left
        .byte  36, 82                      ; Marcus: ground, left
;   PF0 OFF (+66): minus the rift bit
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0
;   PF1 world B (+78): band 7 the 56-rung ($3C = 24-39); band 9 the
;   72-rung's PF1 part ($03 = 40-47); floor
        .byte $00,$00,$00,$00,$00,$00,$00,$3C,$00,$03,$00,$FF
;   PF2 world B (+90): the shared totem/shelf (identical to A) + the
;   72-rung's PF2 part (band 9, $03 = 48-55)
        .byte $00,$00,$00,$C0,$F0,$FF,$00,$00,$00,$03,$00,$FF
;   boxes B (+102): ground / shelf / totem / the two ladder rungs
        .byte  88, 40, 32, 24, 72, 56      ; tops
        .byte  96, 48, 32, 24, 72, 56      ; bottoms (rungs one-way)
        .byte   0, 48, 64, 72, 40, 24      ; lefts
        .byte 160,112, 96, 88, 56, 40      ; rights (excl)

; ===============================================================
; ACT 3, FLOOR 8 — "The Handoff"
;
; Develop: NEITHER truth alone reaches the top. World A holds the
; lower staircase (80/72/64) zigzagging up-left to a perch in the
; beam (56); world B holds the continuation (48/40) away from the
; beam. The perch is shared, so the swap at altitude strands nobody —
; the two truths hand the climb off between your feet.
;
; The perch sits at 56 for a reason: the best three-friend stack-jump
; the engine allows peaks at feet ~58, and 58 never lands on 56 — so
; world B alone can't start (no stairs, stack-proof) and world A alone
; can't finish (no continuation). The solver proves BOTH directions
; fail alone (the "swapboth" proof), which is what makes this a
; handoff and not a choice of doors.
;
; Homes: Alex owns the perch itself (he holds the door open for the
; climb); Marcus the first continuation ledge; Stella the top.
; ===============================================================

Floor8Home:
        .byte 31, 32,  48       ; Stella: top ledge (40), band 5
        .byte 53,  4,  20       ; Alex: the beam perch (56), band 7
        .byte 42, 16,  32       ; Marcus: continuation (48), band 6

Floor8Rec:
;   PF0 (shared): rift b5 bands 0-10; band 7 adds the perch (b5-b7 =
;   px 4-15, the rift's own bit inside it); floor
        .byte $20,$20,$20,$20,$20,$20,$20,$E0,$20,$20,$20,$F0
;   PF1 world A: band 7 the perch's PF1 part (16-19, SHARED — world B
;   carries it identical); bands 8/9 the 64/72 stairs; band 10 the
;   80-stair's left part; floor
        .byte $00,$00,$00,$00,$00,$00,$00,$80,$F0,$3C,$03,$FF
;   PF2 world A: band 10 the 80-stair's right part; floor
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$FF
;   boxes A: ground / the two beam perches (one-way, shared) / stairs
        .byte  88, 56, 56, 64, 72, 80      ; tops
        .byte  96, 56, 56, 64, 72, 80      ; bottoms (one-way all)
        .byte   0,  4,140, 16, 24, 40      ; lefts
        .byte 160, 20,156, 32, 40, 56      ; rights (excl)
        .byte 100, 79                      ; Stella: ground, right
        .byte 116, 85                      ; Alex: ground, right
        .byte 132, 82                      ; Marcus: ground, right
;   PF0 OFF (+66): minus the rift bit (band 7 keeps the perch)
        .byte $00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$F0
;   PF1 world B (+78): the perch part (identical, shared); bands 6/5
;   the 48/40 continuation; floor
        .byte $00,$00,$00,$00,$00,$0F,$F0,$80,$00,$00,$00,$FF
;   PF2 world B (+90): floor only
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
;   boxes B (+102): ground / perches / the continuation ledges
        .byte  88, 56, 56, 48, 40,$FF
        .byte  96, 56, 56, 48, 40,$FF
        .byte   0,  4,140, 16, 32,  0
        .byte 160, 20,156, 32, 48,  0

; ===============================================================
; ACT 3, FLOOR 9 — "The Way Home"
;
; The twist. Two floors taught "the other world is the answer"; this
; one's stairs are in world B but its HOMES are in world A. The play:
; world A shows you the homes (lamps blinking on their ledges) with
; nothing to climb — the beam-perch (56) is stack-proof by the usual
; two du. So you swap, climb world B's staircase to the beam... and
; the lamps VANISH: in world B those ledges were never true. The only
; move left is to swap BACK, and the perch you earned in world B is
; still under you — it is the one thing both truths agree on. Then
; climb down onto your homes.
;
; There and back again: the act's last lesson is that the swap is not
; a direction but a door you may owe two crossings. The solver proves
; neither world alone suffices (swapboth). Alex's home is the perch
; itself — he holds the door, twice.
; ===============================================================

Floor9Home:
        .byte 31, 32,  48       ; Stella: top ledge (40), band 5
        .byte 53,  4,  20       ; Alex: the beam perch (56), band 7
        .byte 42, 16,  32       ; Marcus: mid ledge (48), band 6

Floor9Rec:
;   PF0 (shared): as Floor 8 — rift b5; band 7 the perch; floor
        .byte $20,$20,$20,$20,$20,$20,$20,$E0,$20,$20,$20,$F0
;   PF1 world A: band 7 the perch's PF1 part (shared); bands 6/5 the
;   HOME ledges (they are only true here); floor
        .byte $00,$00,$00,$00,$00,$0F,$F0,$80,$00,$00,$00,$FF
;   PF2 world A: floor only
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
;   boxes A: ground / the perches (shared) / the two home ledges
        .byte  88, 56, 56, 48, 40,$FF      ; tops
        .byte  96, 56, 56, 48, 40,$FF      ; bottoms (one-way all)
        .byte   0,  4,140, 16, 32,  0      ; lefts
        .byte 160, 20,156, 32, 48,  0      ; rights (excl)
        .byte 100, 79                      ; Stella: ground, right
        .byte 116, 85                      ; Alex: ground, right
        .byte 132, 82                      ; Marcus: ground, right
;   PF0 OFF (+66): minus the rift bit (band 7 keeps the perch)
        .byte $00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$F0
;   PF1 world B (+78): the perch part (identical); bands 8/9/10 the
;   staircase (64 / 72 / 80) — only true HERE; floor
        .byte $00,$00,$00,$00,$00,$00,$00,$80,$F0,$3C,$03,$FF
;   PF2 world B (+90): the 80-stair's right part; floor
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$FF
;   boxes B (+102): ground / perches / the staircase
        .byte  88, 56, 56, 80, 72, 64      ; tops
        .byte  96, 56, 56, 80, 72, 64      ; bottoms (one-way all)
        .byte   0,  4,140, 40, 24, 16      ; lefts
        .byte 160, 20,156, 56, 40, 32      ; rights (excl)

; ---------------------------------------------------------------
; Narration text (generated by tools/gentext.py): ALL of it lives in
; the bank-1 annex (the title and story states never share a frame
; with play, so their kernels, logic, and text map in over there).
; Bank 0 keeps nothing of it but the handover: MainLoop's dispatch,
; Bank0Entry, and the StoryId byte.
; ---------------------------------------------------------------


; ---------------------------------------------------------------
; Bank 0 hotspots + vectors
; ---------------------------------------------------------------

        ORG $0FF8
        RORG $FFF8
        .byte 0, 0              ; $1FF8/$1FF9: the hotspots live here
        .word ColdStart         ; NMI (unused on the 2600)
        .word ColdStart         ; RESET
        .word ColdStart         ; IRQ (unused)

; ===============================================================
; BANK 1 — file $1000-$1FFF, also mapped at $F000-$FFFF
;
; The annex: the byte-identical stubs, the title and narration
; frames (Bank1Entry), and the jobs bank 0 calls mid-frame through
; GoAnnex (AnnexJob: the waking opening's phases and the sound).
; ===============================================================

        SEG BANK1
        ORG $1000
        RORG $F000

; F8 trampoline stubs — byte-for-byte copy of bank 0's stubs above.
Bank1Top:
        lda BANK1HOT            ; GoBank1
        jmp Bank1Entry
        lda BANK0HOT            ; GoBank0
        jmp Bank0Entry
        lda BANK1HOT            ; GoAnnex
        jmp AnnexJob
        lda BANK0HOT            ; GoBackBank0
        rts
        ldy #0                  ; ColdStart
        sei                     ; WarmStart
        cld
        lda BANK0HOT
        jmp Bank0Init

        IF * - Bank1Top != STUB_SIZE
        ECHO "F8 stubs drifted between banks — fix before flashing!"
        ERR
        ENDIF

; ---------------------------------------------------------------
; THE ANNEX. The title and the narration never share a frame with
; play, so both states — their frame loops, kernels, logic, and ALL
; the text — live in bank 1, mapped in for the state's whole duration
; (MainLoop hands over via GoBank1 when State is TITLE or STORY; the
; loops hand the frame back at the next frame boundary, so no torn
; frame ever leaves). This is what the F8 skeleton's second bank was
; keeping honest for. What it buys: ~1.1 KB of bank 0 back — the room
; Acts 3-4 are spent from — and space for the script to grow with the
; acts.
;
; Handover discipline: bank 0 sets StoryId (RAM, shared) at a floor
; boundary; StoryFrame re-points TPtr from it EVERY frame (LoadStory1
; is idempotent, so no "just entered" state is needed). The title is
; always world A and screen 0. Jobs called mid-frame (GoAnnex) are
; the other way in: see AnnexJob.
; ---------------------------------------------------------------

Bank1Entry:
        lda State
        cmp #STATE_TITLE
        beq TitleFrame
        cmp #STATE_SCORE
        bne .story
        jmp ScoreFrame
.story:
        jmp StoryFrame          ; STATE_STORY

; ---------------------------------------------------------------
; TitleFrame: the title's whole frame, in the annex. The dusk
; gradient, the big mark, the game's one word beneath, fire to start
; (no menu — decision #22). Behaviour-identical to the bank-0
; original; only the bank changed.
; ---------------------------------------------------------------

TitleFrame:
        SUBROUTINE
        lda #2
        sta VBLANK
        sta VSYNC
        sta WSYNC
        sta WSYNC
        sta WSYNC
        lda #0
        sta VSYNC
        lda #49
        sta TIM64T
        inc FrameCtr
        lda SWCHB               ; console RESET (cold start, as bank 0)
        lsr
        bcs .noReset
        ldy Mode
        jmp WarmStart
.noReset:
        lda #TITLE_SKY          ; the dusk gradient, banded (the annex
        bit Mode                ; has its own copy of GradOfs — the
        bpl .dusk               ; two banks can't read each other's
        lda #EMBER_SKY          ; ROM); ember for the endless game
.dusk:
        sta Temp
        ldx #11                 ; two banks can't read each other's ROM)
.grad:
        lda GradOfs1,x
        clc
        adc Temp
        sta SkyGrad,x
        dex
        bpl .grad
        lda #0                  ; screen 0 = the logo + the game's word
        jsr LoadStory1
        lda SWCHB               ; SELECT steps through four games (#47,
        and #2                  ; #52): one player, two, endless one,
        bne .selUp              ; endless two — period game variations,
        bit UpPrev              ; shown in the game's own picture (the
        bpl .selDone            ; figures, the ember sky), not a menu.
        lda #0                  ; Held: one step per press
        sta UpPrev
        lda Mode
        clc
        adc #$40
        and #$C0
        sta Mode
        jsr SetPlayers1
        jmp .selDone
.selUp:
        lda #$80
        sta UpPrev
.selDone:
        lda #$FF                ; Temp = joystick 2's figure: shown
        ldx Active2             ; only in two-player mode
        bpl .shown
        lda #0
.shown:
        sta Temp
        lda #COL_STELLA         ; the count, drawn as who is playing:
        sta COLUP0              ; Stella alone, or Stella and Alex
        lda #COL_ALEX           ; side by side on the bottom sky
        sta COLUP1
        lda #0
        sta NUSIZ0
        lda #5                  ; Alex is double-width, as in play
        sta NUSIZ1
        lda #TITLE_X1
        ldx #0
        jsr SetHorizPos1
        lda #TITLE_X2
        ldx #1
        jsr SetHorizPos1
        sta WSYNC
        sta HMOVE
        lda INPT4               ; fire: begin (at the waking opening)
        and #$80
        bne .release
        bit FirePrev
        bpl .inputDone
        lda #0
        sta FirePrev
        sta RunHi               ; a fresh run: the clock and the count
        lda Mode                ; (the story zeroes RunLo after the
        and #$C0                ; opening, whose phase byte it is)
        sta Mode
        bmi .endless
        lda #0
        sta FloorSeq            ; start at the first floor
        lda #STATE_OPEN         ; bank 0 sets the opening up next frame
        bne .begin
.endless:
        lda #0                  ; the endless game skips the opening
        sta RunLo               ; and the narration: a floor at random,
        jsr PickFloor           ; loaded by bank 0 next frame
        lda #STATE_LOAD
.begin:
        sta State
        jmp .inputDone
.release:
        lda #$80
        sta FirePrev
.inputDone:
.wv:
        bit TIMINT
        bpl .wv
        lda #0
        sta WSYNC
        sta VBLANK              ; A=0: beam on
        sta CTRLPF              ; asymmetric playfield for the logo
        jsr TitleKernel
        jsr AnnexOverscan
        lda State
        cmp #STATE_TITLE
        bne .toWake
        jmp TitleFrame
.toWake:
        jmp GoBank0             ; fire was pressed: to bank 0's wake

; ---------------------------------------------------------------
; StoryFrame: the narration state, held until fire — then back to
; bank 0 for the next floor (Bank0Entry loads it; FloorSeq was already
; advanced by DoneLogic before the handover) or, after the last floor,
; the title.
; ---------------------------------------------------------------

StoryFrame:
        SUBROUTINE
        lda #2
        sta VBLANK
        sta VSYNC
        sta WSYNC
        sta WSYNC
        sta WSYNC
        lda #0
        sta VSYNC
        lda #49
        sta TIM64T
        inc FrameCtr
        lda SWCHB               ; console RESET returns to the title
        lsr
        bcs .noReset
        ldy Mode
        jmp WarmStart           ; this bank's own copy: maps bank 0
.noReset:
        lda FloorSeq            ; after floor n, screen n (bank 0 has
        jsr LoadStory1          ; already counted it); re-point TPtr
                                ; every frame
        lda INPT4
        and #$80
        bne .release
        bit FirePrev
        bpl .inputDone
        lda #0
        sta FirePrev
        lda FloorSeq            ; the last narration leads to the title
        cmp #NUM_FLOORS
        bcs .toTitle
        lda #STATE_LOAD         ; bank 0 loads the floor next frame
        sta State
        jmp .inputDone
.toTitle:
        lda #60                 ; the run's time, a beat before fire
        sta StateTimer          ; counts (Game 1's epilogue)
        lda #STATE_SCORE
        sta State
        jmp .inputDone
.release:
        lda #$80
        sta FirePrev
.inputDone:
.wv:
        bit TIMINT
        bpl .wv
        lda #0
        sta WSYNC
        sta VBLANK              ; A=0: beam on
        sta CTRLPF              ; asymmetric playfield for text
        lda #COL_TEXT
        sta COLUPF
        jsr StoryKernel
        jsr AnnexOverscanNow    ; the text's last line ends at ~cycle 70;
        lda State               ; rts + jsr carry us into the next line,
        cmp #STATE_STORY        ; so a WSYNC there would land late and
                                ; cost a line (every narration frame
                                ; was 263)
        beq StoryFrame
        cmp #STATE_SCORE        ; the last narration gives way to the
        bne .toBank0            ; score: same bank, straight there. Via
        jmp ScoreFrame          ; bank 0's handover its VSYNC fell past
.toBank0:                       ; cycle 42, and the frame ran 263
        jmp GoBank0

; ---------------------------------------------------------------
; ScoreFrame: the run's numbers (decision #52), held until fire, then
; the title. The story shows its time ("  312 "); the endless game its
; floors and time ("14 312"). Game 1's epilogue digits: six glyphs of
; 48px sprite text, the same positions and the same kernel. A clock
; "second" is 64 frames, as everywhere in this game. Over the
; ember sky when the run was endless, the black of the story's end
; otherwise.
; ---------------------------------------------------------------

ScoreFrame:
        SUBROUTINE
        lda #2
        sta VBLANK
        sta VSYNC
        sta WSYNC
        sta WSYNC
        sta WSYNC
        lda #0
        sta VSYNC
        lda #49
        sta TIM64T
        inc FrameCtr
        lda SWCHB               ; console RESET returns to the title
        lsr
        bcs .noReset
        ldy Mode
        jmp WarmStart
.noReset:
        ; --- the six glyphs, into SkyGrad+0..5 (the title rebuilds it)
        lda RunLo               ; seconds, capped at 999
        sta CY
        lda RunHi
        sta CYH
        ldy #0                  ; hundreds
.hund:
        cpy #10
        bcs .cap
        lda CY
        sec
        sbc #100
        tax
        lda CYH
        sbc #0
        bcc .hDone
        sta CYH
        stx CY
        iny
        bne .hund
.cap:
        ldy #9
        lda #99
        sta CY
.hDone:
        lda #10                 ; blank
        sta SkyGrad+0
        sta SkyGrad+1
        sta SkyGrad+2
        sta SkyGrad+5
        tya
        ldx #2                  ; the story: "  HTO "
        bit Mode
        bpl .place
        ldx #3                  ; endless:   "FF HTO"
.place:
        sta SkyGrad,x
        lda CY
        jsr Tens1
        sty SkyGrad+1,x
        sta SkyGrad+2,x
        bit Mode
        bpl .glyphs
        lda Mode                ; floors survived, no leading zero
        and #$3F
        jsr Tens1
        sta SkyGrad+1
        tya
        bne .tens
        lda #10
.tens:
        sta SkyGrad+0
.glyphs:
        ldx #10
.glyph:
        txa
        lsr
        tay
        lda SkyGrad,y
        jsr SetGlyph1
        dex
        dex
        bpl .glyph
        ; --- the 48px setup: Game 1's EnterWin
        lda #$03
        sta NUSIZ0              ; three close copies of each player
        sta NUSIZ1
        lda #1
        sta VDELP0
        sta VDELP1
        lda #48
        ldx #0
        jsr SetHorizPos1
        lda #56
        ldx #1
        jsr SetHorizPos1
        sta WSYNC
        sta HMOVE
        lda #0                  ; the story's black, or ember
        bit Mode
        bpl .bg
        lda #EMBER_SKY
.bg:
        sta COLUBK
        ; --- fire, after a beat
        lda StateTimer
        beq .armed
        dec StateTimer
        jmp .inputDone
.armed:
        lda INPT4
        and #$80
        bne .release
        bit FirePrev
        bpl .inputDone
        lda #0
        sta FirePrev
        lda #STATE_TITLE
        sta State
        bne .inputDone
.release:
        lda #$80
        sta FirePrev
.inputDone:
        sta HMCLR
.wv:
        bit TIMINT
        bpl .wv
        lda #0
        sta WSYNC
        sta VBLANK
        ldx #SCORE_TOP
        jsr BlankLines1
        jsr DigitBlock1         ; 15 lines
        ldx #SCORE_BOTTOM
        jsr BlankLines1
        jsr AnnexOverscan
        lda State
        cmp #STATE_SCORE
        bne .out
        jmp ScoreFrame
.out:
        jmp Bank1Entry          ; the title, in this bank

; Tens1: A = 0..99. Returns Y = tens, A = ones.
Tens1:
        SUBROUTINE
        ldy #0
.t:
        cmp #10
        bcc .done
        sbc #10
        iny
        bne .t
.done:
        rts

; SetGlyph1: A = glyph (10 = blank), X = TPtr slot offset. Game 1's
; SetGlyph.
SetGlyph1:
        SUBROUTINE
        sta Temp
        asl
        asl
        asl
        sec
        sbc Temp                ; A = glyph * 7
        clc
        adc #<DigitFont1
        sta TPtr,x
        lda #>DigitFont1
        adc #0
        sta TPtr+1,x
        rts

; BlankLines1: X = how many scanlines of nothing
BlankLines1:
        SUBROUTINE
.b:
        sta WSYNC
        dex
        bne .b
        rts

; DigitBlock1: fourteen scanlines of six-glyph 48px sprite text (VDEL
; cascade, three close copies per player), rows from the TPtr glyph
; pointers. Game 1's DigitBlock, verbatim: its stores land where the
; copies are drawn only at Game 1's positions (48 and 56).
DigitBlock1:
        SUBROUTINE
        lda #$0E
        sta COLUP0
        sta COLUP1
        lda #6
        sta BoxIdx              ; glyph row (stored bottom-up)
.drow:
        ldy BoxIdx
        lda (TPtr),y
        sta GRP0                ; VDEL: pending until GRP1 write
        sta WSYNC               ; ---- row, first scanline
        lda (TPtr+2),y
        sta GRP1
        lda (TPtr+4),y
        sta GRP0
        lda (TPtr+6),y
        sta Temp
        lda (TPtr+8),y
        tax
        lda (TPtr+10),y
        tay
        lda Temp
        sta GRP1
        stx GRP0
        sty GRP1
        sta GRP0
        ldy BoxIdx
        lda (TPtr),y
        sta GRP0
        sta WSYNC               ; ---- row, second scanline
        lda (TPtr+2),y
        sta GRP1
        lda (TPtr+4),y
        sta GRP0
        lda (TPtr+6),y
        sta Temp
        lda (TPtr+8),y
        tax
        lda (TPtr+10),y
        tay
        lda Temp
        sta GRP1
        stx GRP0
        sty GRP1
        sta GRP0
        dec BoxIdx
        bpl .drow
        lda #0
        sta WSYNC               ; end the last row's line here (@~65):
        sta GRP0                ; Game 1 clears and returns first and
        sta GRP1                ; its next WSYNC lands late, a 263rd
        sta GRP0                ; line. The clear is in hblank now.
        rts                     ; GRP0 twice: with VDEL on, P1 shows its
                                ; old copy, which only a GRP0 write
                                ; updates. Game 1's sixth glyph is always
                                ; blank, so it never showed; "FF HTO"
                                ; ends on a digit, and left three white
                                ; stripes down the screen

; ---------------------------------------------------------------
; AnnexOverscan: the shared blank-and-wait tail of both annex frames.
; ---------------------------------------------------------------

AnnexOverscan:
        SUBROUTINE
        sta WSYNC               ; finish the last visible line cleanly
AnnexOverscanNow:               ; (or already into the next: blanking
        lda #2                  ; @~11 is still before the first pixel)
        sta VBLANK
        lda #0
        sta GRP0
        sta GRP1
        sta ENAM0
        sta ENAM1
        sta ENABL
        sta PF0
        sta PF1
        sta PF2
        sta VDELP0              ; the score's digits delay both players;
        sta VDELP1              ; nothing else may inherit that
        lda #28
        sta TIM64T
.waitOS:
        bit TIMINT
        bpl .waitOS
        rts

; ---------------------------------------------------------------
; LoadStory1: A = screen id. Points the six plane pointers at the
; generated text data and centers the block vertically. (Game 1's
; LoadStory, verbatim; lives in the annex, like everything it reads.)
; ---------------------------------------------------------------

LoadStory1:
        SUBROUTINE
        tay
        lda StoryLo,y
        sta TPtr
        lda StoryHi,y
        sta TPtr+1
        lda StoryLen,y
        sta TextEnd
        lda StoryStride,y
        sta Temp
        ldx #0
.mk:
        lda TPtr,x
        clc
        adc Temp
        sta TPtr+2,x
        lda TPtr+1,x
        adc #0
        sta TPtr+3,x
        inx
        inx
        cpx #10
        bne .mk
        lda #96
        sec
        sbc TextEnd
        lsr
        sta TextTop
        rts

; ---------------------------------------------------------------
; TitleKernel: the series signature (decision #28) — Game 1's big
; 7-row STELLA logo on this game's greyscale dusk gradient, with the
; game's word set small beneath:
;
;       [ sky gradient ]
;       S T E L L A          <- big (LogoPF* tables, ported from G1)
;       [ sky ]
;       TOGETHER             <- small, white (text pipeline, screen 0)
;       [ sky gradient ]
;
; Five fixed zones, 40+112+8+12+20 = 192 scanlines; each zone's lines
; are cycle-safe on their own terms (the logo lines are G1's proven
; fixed-cycle feed; the subtitle lines are the story kernel's).
; ---------------------------------------------------------------

TitleKernel:
        SUBROUTINE
        lda #0
        sta GRP0
        sta GRP1
        sta ENAM0
        sta ENAM1
        sta ENABL
        sta PF0
        sta PF1
        sta PF2
        ; --- top sky: 40 scanlines, gradient by band -------------
        ldx #0
.sky1:
        sta WSYNC
        txa                     ; band = scanline >> 4
        lsr
        lsr
        lsr
        lsr
        tay
        lda SkyGrad,y
        sta COLUBK
        inx
        cpx #40
        bne .sky1
        ; --- the big STELLA: 7 rows x 16 scanlines ---------------
        lda SkyGrad+4           ; hold a mid-dusk shade behind it
        sta COLUBK
        ldy #0                  ; Y = logo row
        lda #8
        sta BandLine
        ldx #56                 ; 56 du pairs = 112 scanlines
.lloop:
        sta WSYNC               ; ---- line 1: fixed-cycle feed
        lda LogoColr,y          ; per-row neutral highlight
        sta COLUPF              ; @7
        lda LogoPF0L,y
        sta PF0                 ; @15
        lda LogoPF1L,y
        sta PF1                 ; @22
        lda LogoPF2L,y
        sta PF2                 ; @29
        nop
        nop
        nop
        lda LogoPF0R,y
        sta PF0                 ; @42
        lda LogoPF1R,y
        sta PF1                 ; @49
        nop
        lda LogoPF2R,y
        sta PF2                 ; @58
        sta WSYNC               ; ---- line 2: feed again
        lda LogoPF0L,y
        sta PF0
        lda LogoPF1L,y
        sta PF1
        lda LogoPF2L,y
        sta PF2
        nop
        nop
        nop
        lda LogoPF0R,y
        sta PF0
        lda LogoPF1R,y
        sta PF1
        nop
        lda LogoPF2R,y
        sta PF2
        dec BandLine
        bne .lhold
        lda #8
        sta BandLine
        iny
.lhold:
        dex
        bne .lloop
        ; --- gap sky: 8 scanlines --------------------------------
        ldx #8                  ; the logo's last line ends at ~cycle 66,
.gap:                           ; so the clear waits for the next line:
        sta WSYNC               ; before it, it ran that line's WSYNC
        lda #0                  ; late, and every title frame was 263
        sta PF0
        sta PF1
        sta PF2
        lda SkyGrad+9
        sta COLUBK              ; @17, before the first visible pixel
        dex
        bne .gap
        ; --- the game's word, small and white: 12 scanlines ------
        lda #COL_TEXT
        sta COLUPF
        ldy #0                  ; rows 0-5 of story screen 0
.sub:
        sta WSYNC               ; ---- line A (story kernel feed)
        lda (TPtr),y
        sta PF0
        lda (TPtr+2),y
        sta PF1
        lda (TPtr+4),y
        sta PF2
        lda (TPtr+6),y
        sta PF0
        lda (TPtr+8),y
        sta PF1
        nop
        lda (TPtr+10),y
        sta PF2
        sta WSYNC               ; ---- line B
        lda (TPtr),y
        sta PF0
        lda (TPtr+2),y
        sta PF1
        lda (TPtr+4),y
        sta PF2
        lda (TPtr+6),y
        sta PF0
        lda (TPtr+8),y
        sta PF1
        nop
        lda (TPtr+10),y
        sta PF2
        iny
        cpy #6
        bne .sub
        lda #0                  ; clear below the subtitle
        sta PF0
        sta PF1
        sta PF2
        ; --- bottom sky: 20 scanlines, gradient resumes, and the ---
        ; --- player count stands on it (TitleFrame placed them) ---
        ldx #0
        lda SkyGrad+10          ; line 172's band (172 >> 4)
.sky2:
        sta WSYNC
        sta COLUBK              ; @3
        lda TitleG0,x
        sta GRP0                ; @10: well before either figure
        lda TitleG1,x
        and Temp                ; joystick 2's figure, or nobody
        sta GRP1                ; @20
        inx
        txa                     ; the NEXT line's colour, ready for
        clc                     ; its first cycles (absolute line =
        adc #172                ; 172 + X)
        lsr
        lsr
        lsr
        lsr
        tay
        lda SkyGrad,y
        cpx #20
        bne .sky2
        rts

; ---------------------------------------------------------------
; StoryKernel: narration text on the asymmetric playfield. All six
; PF bytes re-fed every scanline from the generated plane data (an
; asymmetric playfield must be re-fed or the right half bleeds into
; the left). Ported verbatim from game 1. White text on black.
; ---------------------------------------------------------------

StoryKernel:
        SUBROUTINE
        lda #0
        sta GRP0
        sta GRP1
        sta ENAM0
        sta ENAM1
        sta ENABL
        sta PF0
        sta PF1
        sta PF2
        sta COLUBK
        ldx #0
        ldy TextEnd             ; blank row until the text block starts
.sloop:
        sta WSYNC               ; ---- line 1
        lda (TPtr),y
        sta PF0
        lda (TPtr+2),y
        sta PF1
        lda (TPtr+4),y
        sta PF2
        lda (TPtr+6),y
        sta PF0
        lda (TPtr+8),y
        sta PF1
        nop
        lda (TPtr+10),y
        sta PF2
        sta WSYNC               ; ---- line 2
        lda (TPtr),y
        sta PF0
        lda (TPtr+2),y
        sta PF1
        lda (TPtr+4),y
        sta PF2
        lda (TPtr+6),y
        sta PF0
        lda (TPtr+8),y
        sta PF1
        nop
        lda (TPtr+10),y
        sta PF2
        inx
        cpx TextTop
        bne .noStart
        ldy #$FF                ; so the iny below lands on row 0
.noStart:
        cpy TextEnd
        beq .hold               ; stay on the blank row
        iny
.hold:
        cpx #SCREEN_DU
        bne .sloop
        rts

; ---------------------------------------------------------------
; AnnexJob: bank 0 calls into the annex with Y = a job, through
; GoAnnex; every job ends `jmp GoBackBank0`, which returns to bank 0's
; caller. Jobs may use bank-1 subroutines but not bank-0 ones: bank 0
; keeps those calls and asks the annex again (decision #51).
; ---------------------------------------------------------------
AnnexJob:
        SUBROUTINE
        dey
        bpl .1
        jmp WakeSetup           ; JOB_WAKESETUP = 0
.1:     bne .2
        jmp WakePre             ; JOB_WAKEPRE   = 1
.2:     dey
        bne .3
        jmp WakePost            ; JOB_WAKEPOST  = 2
.3:     dey
        bne .4
        jmp UpdateSound         ; JOB_SOUND     = 3
.4:                             ; JOB_NEXTFLOOR = 4: the endless game's
        lda Mode                ; floor is done. Count it (to 63), draw
        and #$3F                ; another, and bank 0 loads it next frame
        cmp #$3F
        bcs .capped
        inc Mode
.capped:
        jsr PickFloor
        lda #STATE_LOAD
        sta State
        jmp GoBackBank0

; PickFloor: FloorSeq = a floor at random, never the one just played.
; The frame counter is the dice: when a floor ends, or fire is pressed
; on the title, depends on the player to the frame.
PickFloor:
        SUBROUTINE
        lda FrameCtr
        eor RunLo
.mod:
        cmp #NUM_FLOORS
        bcc .got
        sbc #NUM_FLOORS         ; carry set by the cmp
        bcs .mod
.got:
        cmp FloorSeq
        bne .new
        tax                     ; the same floor again: the next one
        inx
        txa
        cmp #NUM_FLOORS
        bcc .new
        lda #0
.new:
        sta FloorSeq
        rts

; SetPlayers1: bank 0's SetPlayers, for the title's SELECT.
SetPlayers1:
        SUBROUTINE
        ldx #$FF
        bit Mode
        bvc .one
        ldx #1
.one:   stx Active2
        rts

; ---------------------------------------------------------------
; UpdateSound: game 1's one-channel effect engine — jump, land, and
; the floor fanfare. Nothing can cut the fanfare off: STATE_DONE runs
; neither ReadInput nor UpdatePhysics, so no jump or landing happens
; while it plays (game 1 needs an explicit guard for this; here the
; state machine gives it for free).
; ---------------------------------------------------------------

UpdateSound:                    ; JOB_SOUND, in the annex since
        SUBROUTINE              ; decision #51: RAM and TIA only
        lda SoundT
        bne .active
        lda #0
        sta AUDV0
        sta SoundId
        jmp GoBackBank0
.active:
        dec SoundT
        lda SoundId
        cmp #1
        beq .jump
        cmp #2
        beq .land
        cmp #4
        beq .blip
        cmp #5
        beq .chime
        ; floor fanfare: low note then high note. Game 1's two notes
        ; verbatim — decision #26 gives the series one goal mechanic,
        ; so it gets one sound of completion too.
        lda #12
        sta AUDC0
        lda SoundT
        cmp #8
        bcs .note1
        lda #11
        bne .setf
.note1:
        lda #15
.setf:
        sta AUDF0
        lda #8
        sta AUDV0
        jmp GoBackBank0
.jump:
        lda #4                  ; jump: rising pure tone
        sta AUDC0
        lda #8
        clc
        adc SoundT
        sta AUDF0
        lda #6
        sta AUDV0
        jmp GoBackBank0
.land:
        lda #6                  ; land: a low thump
        sta AUDC0
        lda #25
        sta AUDF0
        lda #8
        sta AUDV0
        jmp GoBackBank0
.blip:
        lda #1                  ; portal: a short buzzy chirp — the one
        sta AUDC0               ; machine timbre in a game of voices
        lda #20
        sta AUDF0
        lda #5
        sta AUDV0
        jmp GoBackBank0
.chime:
        lda #4                  ; world-swap: a pure tone stepping with
        sta AUDC0               ; the swap — rising back into world A,
        lda SoundT              ; falling into B (the workbench's
        ldy CurWorld            ; signature, kept: the two truths have
        bne .down               ; two pitches)
        lda #16
        sec
        sbc SoundT
        jmp .setf0
.down:
        lda #10
        clc
        adc SoundT
.setf0:
        sta AUDF0
        lda #7
        sta AUDV0
        jmp GoBackBank0

; WakeSetup: the opening's first frame, after bank 0's LoadFloor.
WakeSetup:
        lda #2
        sta Active              ; Marcus is the sleeper: P0, solid
        ldx #11
        lda #0
.dark:
        sta SkyGrad,x           ; the sky starts black...
        dex
        bpl .dark
        sta PFColor             ; ...and so do the platforms
        sta WakePhase
        sta WakeT
        lda #<BlackPF
        sta PFColPtr
        lda #>BlackPF
        sta PFColPtr+1
        lda #200                ; park Stella and Alex below the
        sta CharY               ; visible screen (kernel draws
        sta CharY+1             ; nothing at y=200; no physics runs
        lda #STATE_WAKE         ; for them until phase 3)
        sta State
        jmp GoBackBank0

; WakePre: fire skips; phases 0-2 (the black, the sky, the eyes).
; X = 0 draw, 1 physics (phase 3+), 2 skip to play.
WakePre:
        SUBROUTINE
        lda INPT4               ; a fresh fire press skips the opening
        and #$80
        bne .arm
        bit FirePrev
        bpl .run                ; still held from the title: ignore
        lda #0
        sta FirePrev
        ldx #2
        jmp GoBackBank0
.arm:
        lda #$80
        sta FirePrev
.run:
        ldx #0                  ; the answer, unless phase 3+
        lda WakePhase
        cmp #3
        bcs .physics
        cmp #1
        beq .p1
        cmp #2
        beq .p2
        ; --- phase 0: hold the black -------------------------------
        inc WakeT
        lda WakeT
        cmp #WAKE_BLACK
        bcc .done
        lda #1
        sta WakePhase
        lda #0
        sta WakeT
        beq .done
.p1:
        ; --- phase 1: the sky assembles, horizon (band 11) first ---
        lda WakeT
        and #7
        bne .p1t                ; one new band every 8 frames
        lda WakeT
        lsr
        lsr
        lsr
        sta Temp                ; n = 0..11
        lda #11
        sec
        sbc Temp
        tay                     ; band 11 - n
        lda GradOfs1,y
        clc
        adc #FLOOR1_SKY
        sta SkyGrad,y
.p1t:
        inc WakeT
        lda WakeT
        cmp #96                 ; 12 bands x 8 frames
        bcc .done
        lda #2
        sta WakePhase
        lda #0
        sta WakeT
        lda #PFA_COLOR          ; the sky stands: platforms appear
        sta PFColor             ; (plain grey — the home lamps only
        lda #<GreyPF            ; begin once the player has control)
        sta PFColPtr
        lda #>GreyPF
        sta PFColPtr+1
        bne .done
.p2:
        ; --- phase 2: eyes open (the forcing below stops) ----------
        inc WakeT
        lda WakeT
        cmp #WAKE_EYES
        bcc .done
        lda #3
        sta WakePhase
        lda #0
        sta WakeT
        sta CharY               ; Stella appears at the top of the
        sta CharYLo             ; sky above her spawn x and falls
        sta CharVYHi
        sta CharVYLo
        sta OnGround
        beq .done
.physics:
        inx
.done:
        jmp GoBackBank0

; WakePost: after bank 0's physics, phases 3-4.
; X = 0 draw, 2 the opening is over.
WakePost:
        SUBROUTINE
        ldx #0
        lda WakePhase
        cmp #4
        beq .p4
        ; --- phase 3: Stella falls; keep Alex parked ---------------
        lda #200
        sta CharY+1
        lda #0
        sta CharVYHi+1
        sta CharVYLo+1
        lda OnGround
        beq .done
        lda #4                  ; she landed (real thump): Alex's turn
        sta WakePhase
        lda #85                 ; ground level (feet on the floor)
        sta CharY+1
        lda #0
        sta CharX+1             ; from the left edge...
        sta CharVYHi+1
        sta CharVYLo+1
        lda #1
        sta OnGround+1
        sta CharFace+1
        bne .done
.p4:
        ; --- phase 4: Alex slides in to his spawn ------------------
        lda CharX+1
        clc
        adc #2
        sta CharX+1
        cmp #32
        bcc .done
        ldx #2
.done:
        jmp GoBackBank0

; Game 1's digit font (rows bottom-up), for the score. 77 bytes in
; one page: a page-crossing (TPtr),y costs a cycle and would push the
; 48px stores off their pixels.
        ALIGN 128
DigitFont1:
        .byte $3C,$66,$66,$66,$66,$66,$3C   ; 0
        .byte $7E,$18,$18,$18,$18,$38,$18   ; 1
        .byte $7E,$60,$30,$0C,$06,$66,$3C   ; 2
        .byte $3C,$66,$06,$1C,$06,$66,$3C   ; 3
        .byte $0C,$0C,$7E,$6C,$3C,$1C,$0C   ; 4
        .byte $3C,$66,$06,$06,$7C,$60,$7E   ; 5
        .byte $3C,$66,$66,$7C,$60,$66,$3C   ; 6
        .byte $30,$30,$30,$18,$0C,$06,$7E   ; 7
        .byte $3C,$66,$66,$3C,$66,$66,$3C   ; 8
        .byte $3C,$66,$06,$3E,$66,$66,$3C   ; 9
        .byte $00,$00,$00,$00,$00,$00,$00   ; 10: blank

; ---------------------------------------------------------------
; Annex data: the logo (ported from Game 1; 8-byte tables must not
; cross a page), its neutral highlight ramp, and this bank's copy of
; the sky gradient offsets (two banks can't read each other's ROM).
; ---------------------------------------------------------------
        ALIGN 8
LogoPF0L:   .byte $80,$40,$40,$80,$00,$40,$80
            ds 1
LogoPF1L:   .byte $CF,$22,$02,$C2,$22,$22,$C2
            ds 1
LogoPF2L:   .byte $7D,$04,$04,$3C,$04,$04,$7C
            ds 1
LogoPF0R:   .byte $10,$10,$10,$10,$10,$10,$F0
            ds 1
LogoPF1R:   .byte $20,$20,$20,$20,$20,$20,$BE
            ds 1
LogoPF2R:   .byte $0E,$11,$11,$1F,$11,$11,$11
            ds 1
; The mark is lit in the neutral ramp for Games 1-3 and BLOOMS into
; the full Atari rainbow in Game 4, when the world itself gains colour
; (decision #28, revised). The rainbow's per-row banding survives,
; transposed into the channel every player can see.
LogoColr:   .byte $08,$0A,$0C,$0E,$0C,$0A,$08

GradOfs1:   .byte 0,0,0,2,2,2,4,4,6,6,8,8  ; == GradOfs (bank 0's copy
                                            ; lives beside BuildSky)

; The title's player count: Stella (tall, facing right) and, with two
; players, Alex (flat, facing left), feet on the same line, so the
; second player reads as a second character arriving beside the first.
; One row per bottom-sky scanline.
TitleG0:    .byte 0,0,0,0,$FF,EYES_R,$FF,$FF,$FF,$FF,$FF,$FF
            .byte $FF,$FF,$FF,$FF,0,0,0,0
TitleG1:    .byte 0,0,0,0,0,0,0,0,0,0,0,0
            .byte $FF,EYES_L,$FF,$FF,0,0,0,0

; SetHorizPos1: the annex's copy of SetHorizPos (A = x, X = object).
SetHorizPos1:
        SUBROUTINE
        sta WSYNC
        sec
.div:
        sbc #15
        bcs .div
        eor #7
        asl
        asl
        asl
        asl
        sta HMP0,x
        sta RESP0,x
        rts

        include "text.inc"      ; every screen, including the title's
        include "storytab.inc"  ; LoadStory1's pointer tables

; ---------------------------------------------------------------
; Bank 1 hotspots + vectors (identical to bank 0's: whichever bank is
; mapped at power-on, RESET lands on ColdStart and the stub forces
; bank 0).
; ---------------------------------------------------------------

        ORG $1FF8
        RORG $FFF8
        .byte 0, 0              ; $1FF8/$1FF9: the hotspots
        .word ColdStart         ; NMI (unused on the 2600)
        .word ColdStart         ; RESET
        .word ColdStart         ; IRQ (unused)
