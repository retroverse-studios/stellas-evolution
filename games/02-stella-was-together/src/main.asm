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
;   * the TITLE (decision #28): Game 1's big rainbow STELLA logo on
;     this game's dusk-violet gradient sky, the word TOGETHER set
;     small beneath — no menu, fire starts (decision #22);
;   * the WAKING-MARCUS opening (DESIGN-KICKOFF): a recreation of
;     Game 1's epilogue — black screen, the small blue square — that
;     the world assembles itself around: the sky gradient builds band
;     by band, Marcus's eyes appear (the moment he wakes), Stella
;     drops in, Alex slides in, and Floor 1 begins. Fire skips it;
;   * floors that play IN ORDER (not SELECT-cycled), walked from a
;     clean FLOOR TABLE (record + narration id + act);
;   * a between-floor NARRATION text screen (Game 1's text kernel +
;     tools/gentext.py pipeline, ported);
;   * ALL OF ACT 1 (three floors, decision #18's 3/3/3/1 shape):
;       Floor 1 "Together Again"  — coop: the head-boost carries over
;       Floor 2 "The Low Door"    — Marcus's gift (decision #21): a
;         tunnel under a slab only he can enter — Stella is 1 du too
;         tall for the slot, Alex's jump is 6 du too weak for the sill
;       Floor 3 "The Wall"        — the wrap twist: a wall to the sky
;         splits the world, Alex wakes alone on the far side, and the
;         only way to him is off the edge of the screen — the banked
;         "decoy platforms, wrap is the answer" puzzle
;   * boot flow: title -> wake-up -> floors 1-2-3 (each followed by
;     its narration) -> back to the title.
;
; Adding Floor 4+ is: one row in each Floor* table + one Floor?Rec
; record + one Floor?HomeCharY + one Floor?PFBri/Dim pair + one
; narration string in tools/gentext.py's SCREENS + one FLOOR_DEFS row
; in tools/check_levels.py. Act order (docs/decisions.md #18):
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
;   SELECT      reserved for future variation (no-op)
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
                        ; (game kernel — decision #26's closing image is
                        ; all three standing home together, so the game
                        ; holds on it instead of cutting to text)

; --- floor sequencing ------------------------------------------
NUM_FLOORS  = 3         ; Act 1 complete: Together Again / The Low
                        ; Door / The Wall

; --- wake-up opening timing (frames) ---------------------------
WAKE_BLACK  = 80        ; phase 0: black screen, Marcus alone
WAKE_EYES   = 70        ; phase 2: eyes open before Stella arrives

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
PFA_COLOR   = $0A       ; platforms: the one luma no character owns
COL_TEXT    = $0E       ; narration text: white

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

Active      ds 1
FirePrev    ds 1
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
StoryAfter  ds 1        ; after a narration: 0 = next floor, 1 = title
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

StateTimer  ds 1        ; STATE_DONE: frames left in the completion beat

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
; STUB_SIZE check there catches drift at assembly time. These stubs
; ARE the world-swap capability's core; a future Act-3 floor fills in
; CopyBWorker + world data in bank 1 (see the git tag for the proven
; implementation).
; ---------------------------------------------------------------

GoBank1:                ; jmp here from bank 0 code -> Bank1Entry
        lda BANK1HOT    ; the switch: A gets garbage, who cares
        jmp Bank1Entry  ; fetched from bank 1's identical copy
GoBank0:                ; jmp here from bank 1 code -> Bank0Entry
        lda BANK0HOT
        jmp Bank0Entry
GoCopyB:                ; jsr here from bank 0 to pull world B art:
        lda BANK1HOT    ; map bank 1, then the identical stub's jmp
        jmp CopyBWorker ; lands in bank 1's copy worker
GoBackBank0:            ; jmp here from bank 1 to return to the caller
        lda BANK0HOT    ; map bank 0; the rts is fetched from bank 0's
        rts             ; identical stub and pops GoCopyB's return
ColdStart:              ; RESET vector target in both banks
        sei
        cld
        lda BANK0HOT    ; force bank 0 before touching anything
        jmp Bank0Init

STUB_SIZE = * - GoBank1

; ---------------------------------------------------------------
; Bank 0 cold start
; ---------------------------------------------------------------

Bank0Init:
        SUBROUTINE
        ldx #0
        txa
.clear:
        dex
        txs
        pha
        bne .clear      ; clears TIA + RAM, leaves SP=$FF

        lda #$80
        sta FirePrev
        lda #STATE_TITLE
        sta State       ; boot to the title (TitleLogic builds the sky
                        ; gradient + points the text kernel at the logo)

; ---------------------------------------------------------------
; Frame loop. Same 262-line skeleton as game 1: 3 lines VSYNC,
; ~37 lines vertical blank (logic runs here), 192 visible, ~30
; overscan. The kernel is chosen by State: the title and narration
; use the asymmetric-playfield text kernels, play uses GameKernel.
; ---------------------------------------------------------------

MainLoop:
        SUBROUTINE
        lda #2
        sta VBLANK
        sta VSYNC
        sta WSYNC
        sta WSYNC
        sta WSYNC
        lda #0
        sta VSYNC
        lda #44
        sta TIM64T      ; ~37 scanlines of vertical blank

        inc FrameCtr
        lda SWCHB       ; console RESET returns to the title
        lsr
        bcs .noReset
        jmp ColdStart
.noReset:
        lda State
        cmp #STATE_PLAY
        beq .doPlay
        cmp #STATE_STORY
        beq .doStory
        cmp #STATE_WAKE
        beq .doWake
        cmp #STATE_DONE
        beq .doDone
        jsr TitleLogic
        jmp .logicDone
.doDone:
        jsr DoneLogic
        jmp .logicDone
.doWake:
        jsr WakeLogic
        jmp .logicDone
.doStory:
        jsr StoryLogic
        jmp .logicDone
.doPlay:
        jsr ReadInput
        jsr UpdatePhysics
        jsr CheckGoal   ; all three home -> narration, then next floor
        jsr UpdateSound
        jsr PrepSprites ; draw params + P1 multiplexer + positioning
.logicDone:

        lda State
        cmp #STATE_PLAY
        beq .kPlay
        cmp #STATE_WAKE
        beq .kPlay              ; the opening runs on the game kernel
        cmp #STATE_DONE
        beq .kPlay              ; ...and so does the completion beat
        cmp #STATE_STORY
        beq .kStory
        ; ---- title kernel ----
        lda #0
        sta CTRLPF      ; asymmetric playfield for the logo
.wv0:
        lda INTIM
        bne .wv0
        sta WSYNC
        sta VBLANK      ; A=0: beam on
        jsr TitleKernel
        jmp Overscan
.kStory:
        lda #0
        sta CTRLPF      ; asymmetric playfield for text
        lda #COL_TEXT
        sta COLUPF
.wv1:
        lda INTIM
        bne .wv1
        sta WSYNC
        sta VBLANK
        jsr StoryKernel
        jmp Overscan
.kPlay:
Bank0Entry:             ; bank 1 would arrive here (via GoBank0)
        lda #1
        sta CTRLPF      ; mirrored playfield
        lda PFColor     ; per-floor platform color (kernel steps it)
        sta COLUPF
.wv2:
        lda INTIM
        bne .wv2
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
        lda #34         ; one unit shorter: the WSYNC above took a
        sta TIM64T      ; line; the pre-kernel WSYNC re-aligns
.waitOS:
        lda INTIM
        bne .waitOS
        jmp MainLoop

; ===============================================================
; TITLE + NARRATION logic
; ===============================================================

; ---------------------------------------------------------------
; TitleLogic: build the dusk-violet sky gradient, point the text
; kernel at the "STELLA WAS TOGETHER" logo (story screen 0), and
; start the game on fire. No menu (decision #22).
; ---------------------------------------------------------------

TitleLogic:
        SUBROUTINE
        lda #TITLE_SKY          ; dusk violet -> banded gradient in RAM
        sta Temp
        ldx #11
.grad:
        lda GradOfs,x
        clc
        adc Temp
        sta SkyGrad,x
        dex
        bpl .grad
        lda #0                  ; screen 0 = the logo
        jsr LoadStory

        lda INPT4
        and #$80
        bne .release
        bit FirePrev
        bpl .done
        lda #0
        sta FirePrev
        sta FloorSeq            ; start at the first floor...
        jsr WakeInit            ; ...via the waking-Marcus opening
        rts
.release:
        lda #$80
        sta FirePrev
.done:
        rts

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

WakeInit:
        SUBROUTINE
        jsr LoadFloor           ; Floor 1 data (FloorSeq = 0)
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
        rts

WakeLogic:
        SUBROUTINE
        lda INPT4               ; a fresh fire press skips the opening
        and #$80
        bne .arm
        bit FirePrev
        bpl .run                ; still held from the title: ignore
        lda #0
        sta FirePrev
        jmp .finish
.arm:
        lda #$80
        sta FirePrev
.run:
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
        bcc .p0d
        lda #1
        sta WakePhase
        lda #0
        sta WakeT
.p0d:
        jmp .draw
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
        tax                     ; band 11 - n
        lda GradOfs,x
        clc
        adc #FLOOR1_SKY
        sta SkyGrad,x
.p1t:
        inc WakeT
        lda WakeT
        cmp #96                 ; 12 bands x 8 frames
        bcc .draw
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
        bne .draw
.p2:
        ; --- phase 2: eyes open (the forcing below stops) ----------
        inc WakeT
        lda WakeT
        cmp #WAKE_EYES
        bcc .draw
        lda #3
        sta WakePhase
        lda #0
        sta WakeT
        sta CharY               ; Stella appears at the top of the
        sta CharYLo             ; sky above her spawn x and falls
        sta CharVYHi
        sta CharVYLo
        sta OnGround
        beq .draw
.physics:
        jsr UpdatePhysics
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
        beq .draw
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
        bne .draw
.p4:
        ; --- phase 4: Alex slides in to his spawn ------------------
        lda CharX+1
        clc
        adc #2
        sta CharX+1
        cmp #32
        bcc .draw
.finish:
        jsr LoadFloor           ; clean re-arm; positions = spawns
        lda #STATE_PLAY
        sta State
        jsr PrepSprites         ; lamps + sprite slots valid THIS
        rts                     ; frame (PFColRam was still text)
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

; ---------------------------------------------------------------
; StoryLogic: hold on the narration until fire, then continue —
; to the next floor, or (after the last floor) back to the title.
; ---------------------------------------------------------------

StoryLogic:
        SUBROUTINE
        lda INPT4
        and #$80
        bne .release
        bit FirePrev
        bpl .done
        lda #0
        sta FirePrev
        lda StoryAfter
        bne .toTitle
        jsr LoadFloor           ; FloorSeq already advanced by CheckGoal
        lda #STATE_PLAY
        sta State
        jsr PrepSprites         ; rebuild the lamps NOW — PFColRam
        rts                     ; still holds the narration pointers
.toTitle:
        lda #STATE_TITLE
        sta State
        rts
.release:
        lda #$80
        sta FirePrev
.done:
        rts

; ---------------------------------------------------------------
; LoadStory: A = screen id. Points the six plane pointers at the
; generated text data and centers the block vertically. (Ported
; verbatim from game 1's narration kernel.)
; ---------------------------------------------------------------

LoadStory:
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
        lda #0
        sta Active
        sta SoundId
        sta SoundT
        sta NUSIZ0
        sta VDELP0
        sta VDELP1
        lda #2                  ; all three characters have physics
        sta ActiveM1

        ldx FloorSeq            ; per-floor sky base -> banded gradient
        lda FloorSkyTbl,x
        sta Temp
        ldx #11
.grad:
        lda GradOfs,x
        clc
        adc Temp
        sta SkyGrad,x
        dex
        bpl .grad
        lda #PFA_COLOR
        sta PFColor
        lda #<PFColRam          ; the kernel's per-band COLUPF table
        sta PFColPtr            ; lives in RAM (the home lamps),
        lda #>PFColRam          ; rebuilt by PrepSprites every frame
        sta PFColPtr+1
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
        ; homes is the image decision #26 exists for. LoadStory waits
        ; for DoneLogic: TPtr overlays PFColRam, so the narration
        ; pointers would trample the lamps we are still drawing.
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
        jsr UpdateSound
        lda StateTimer          ; the breath: sky base +0 / +2 luma
        and #$08                ; (bigger would carry the luma nibble
        lsr                     ; into the next HUE — dusk violet must
        lsr                     ; stay dusk violet)
        sta Temp
        ldx FloorSeq
        lda FloorSkyTbl,x
        clc
        adc Temp
        sta Temp
        ldx #11
.grad:
        lda GradOfs,x
        clc
        adc Temp
        sta SkyGrad,x
        dex
        bpl .grad
        jsr PrepSprites         ; keep the P1 multiplexer running: if
                                ; the two inactive characters overlap,
                                ; a frozen P1 would show only one of
                                ; them for the whole beat — and this is
                                ; the beat where all three must be seen
        dec StateTimer
        beq .advance
        rts
.advance:
        ldx FloorSeq            ; the lamps are finished; TPtr may now
        lda FloorStoryTbl,x     ; take PFColRam's bytes back
        jsr LoadStory
        inc FloorSeq
        lda FloorSeq
        cmp #NUM_FLOORS
        bcc .more
        lda #1                  ; past the last floor -> back to title
        sta StoryAfter
        jmp .toStory
.more:
        lda #0                  ; more floors -> play the next one
        sta StoryAfter
.toStory:
        lda #STATE_STORY
        sta State
        rts

; ---------------------------------------------------------------
; ReadInput: move the active character (with solid-box blocking and
; the always-on wrap edges), fire jumps, down+fire cycles Stella ->
; Alex -> Marcus.
; ---------------------------------------------------------------

ReadInput:
        SUBROUTINE
        ldx Active
        lda CharX,x
        sta NewX
        lda #$FF
        sta MoveDir
        lda SWCHA
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
        lda SWCHA
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

        lda INPT4
        and #$80
        bne .release
        bit FirePrev
        bpl .done
        lda SWCHA
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
        lda Active              ; the game 1 switch verb, extended to
        clc                     ; three: Stella -> Alex -> Marcus -> ...
        adc #1
        cmp #NUM_CHARS
        bcc .setA
        lda #0
.setA:
        sta Active
.pressed:
        lda #0
        sta FirePrev
        rts
.release:
        lda #$80
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
; UpdateSound: game 1's one-channel effect engine — jump, land, and
; the floor fanfare. Nothing can cut the fanfare off: STATE_DONE runs
; neither ReadInput nor UpdatePhysics, so no jump or landing happens
; while it plays (game 1 needs an explicit guard for this; here the
; state machine gives it for free).
; ---------------------------------------------------------------

UpdateSound:
        SUBROUTINE
        lda SoundT
        bne .active
        lda #0
        sta AUDV0
        sta SoundId
        rts
.active:
        dec SoundT
        lda SoundId
        cmp #1
        beq .jump
        cmp #2
        beq .land
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
        rts
.jump:
        lda #4                  ; jump: rising pure tone
        sta AUDC0
        lda #8
        clc
        adc SoundT
        sta AUDF0
        lda #6
        sta AUDV0
        rts
.land:
        lda #6                  ; land: a low thump
        sta AUDC0
        lda #25
        sta AUDF0
        lda #8
        sta AUDV0
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
        lda MulThree,x          ; this character's lamp band here
        clc
        adc FloorSeq
        tay
        lda FloorBandByChar,y
        sta Temp
        jsr AtHome              ; the one home test, shared with
        bcc .vac                ; CheckGoal — lamp and rule agree
        lda ColBriTbl,x         ; home: the lamp holds steady
        bne .put
.vac:
        cpx Active              ; vacant: blink — fast for YOUR home
        beq .fast
        lda FrameCtr
        and #$20                ; slow: the to-do list
        jmp .test
.fast:
        lda FrameCtr
        and #$08                ; fast: "this one is yours"
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
        lda CharFace,x
        bne .faceR
        cpx Active              ; awake eyes for the active
        beq .wideL              ; character, narrowed for idle
        lda #EYES_LSQ
        bne .setEye
.wideL:
        lda #EYES_L
        bne .setEye
.faceR:
        cpx Active
        beq .wideR
        lda #EYES_RSQ
        bne .setEye
.wideR:
        lda #EYES_R
        bne .setEye
.blink:
        lda #$FF                ; eyes shut: solid body
.setEye:
        sta EyeByte,x
        dex
        bpl .each

        ldx Active              ; P0 = the ACTIVE character: solid,
        lda DrawY,x             ; never multiplexed, so it never
        sta P0Top               ; flickers. The two INACTIVE characters
        lda DrawH,x             ; time-share P1 below.
        sta P0Hgt
        lda EyeByte,x
        sta P0Eye
        lda NusizTbl,x
        sta NUSIZ0              ; active may be Alex (double width)
        jsr CharColor           ; active = bright luma
        sta COLUP0

        ; ---- the P1 multiplexer: the two INACTIVE characters ----
.mux:
        ldy Active
        ldx OtherATbl,y         ; the two characters that are NOT active
        lda OtherBTbl,y
        tay
        lda DrawY,x             ; order them by drawn top:
        cmp DrawY,y
        bcc .order              ; X already the upper one
        stx Temp                ; else swap X <-> Y
        tya
        tax
        ldy Temp
.order:                         ; X = upper, Y = lower
        lda DrawY,x
        clc
        adc DrawH,x
        sta RepoDU              ; first du past the upper sprite
        clc
        adc #2                  ; hop needs 1 du + 1 du of margin
        cmp DrawY,y
        bcc .solid
        beq .solid
        ; overlap: alternate the two inactive tenants at 30Hz
        lda #$FF
        sta RepoDU
        lda FrameCtr
        and #1
        beq .fill               ; even frame: show X (the upper one)
        tya                     ; odd frame: show Y (the lower one)
        tax
.fill:
        jsr FillP1              ; P1 = tonight's tenant, whole frame
        jmp .position
.solid:
        lda RepoDU              ; never hop on a band boundary OR the
        and #7                  ; prefetch line before it — both line
        beq .bump1              ; 1s are busy now
        cmp #7
        bne .noShift
        inc RepoDU              ; du==7 mod 8: +2, landing on ==1
.bump1:
        inc RepoDU              ; (the 2-du gap margin absorbs +1;
.noShift:                       ; the rare +2 case can clip the lower
                                ; sprite's first line — cosmetic)
        sty Temp
        jsr FillP1              ; P1 opens as the upper character...
        ldx Temp                ; ...and hops to the lower at RepoDU
        lda CharX,x
        sta P1X2
        lda DrawY,x
        sta P1Y2
        lda DrawH,x
        sta P1H2
        lda EyeByte,x
        sta P1Eye2
        jsr CharColor
        sta P1Col2
        lda NusizTbl,x
        sta P1Nu2

.position:
        ldx Active              ; P0 = the active character
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
        jsr CharColor
        ldy RepoDU              ; 30Hz flicker dims the pair; lift
        iny                     ; time-shared tenants ($FF -> 0) a
        bne .noBoost            ; gentle 2 luma. More would whiten
        clc                     ; the hue into pastel — saturation
        adc #2                  ; lives at mid luma on the TIA
.noBoost:
        sta COLUP1
        rts

; CharColor: X = char. A = its color, brighter luma when active.
CharColor:
        SUBROUTINE
        cpx Active
        beq .bright
        lda ColDimTbl,x
        rts
.bright:
        lda ColBriTbl,x
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
        iny                     ; prefetch band 1 (still in vblank)
        lda SkyGrad,y
        sta KSky
        lda (PF0Ptr),y
        sta KPF0
        lda (PF1Ptr),y
        sta KPF1
        lda (PF2Ptr),y
        sta KPF2
        lda (PFColPtr),y
        sta KCol
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
; TitleKernel: the series signature (decision #28) — Game 1's big
; 7-row STELLA logo, worn in the Atari rainbow, on THIS game's
; dusk-violet gradient sky, with the game's word set small beneath:
;
;       [ sky gradient ]
;       S T E L L A          <- big, rainbow (LogoPF* tables,
;       [ sky ]                 ported from Game 1)
;       TOGETHER             <- small, white (text pipeline, the
;       [ sky gradient ]        one-row story screen 0)
;
; Five fixed zones, 40+112+8+12+20 = 192 scanlines; each zone's
; lines are cycle-safe on their own terms (the logo lines are
; G1's proven fixed-cycle feed; the subtitle lines are the story
; kernel's proven feed).
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
        lda LogoColr,y          ; per-row rainbow
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
        lda #0                  ; clear the playfield below the logo
        sta PF0
        sta PF1
        sta PF2
        ; --- gap sky: 8 scanlines --------------------------------
        lda SkyGrad+9
        sta COLUBK
        ldx #8
.gap:
        sta WSYNC
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
        ; --- bottom sky: 20 scanlines, gradient resumes ----------
        ldx #0
.sky2:
        sta WSYNC
        txa                     ; absolute line = 172 + X
        clc
        adc #172
        lsr
        lsr
        lsr
        lsr
        tay
        lda SkyGrad,y
        sta COLUBK
        inx
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
OtherATbl:  .byte 1, 0, 0           ; the two possible head-perches
OtherBTbl:  .byte 2, 2, 1           ; for each character

; per-band gradient shape: brighter toward the horizon (5 shades)
GradOfs:    .byte 0,0,0,2,2,2,4,4,6,6,8,8

; ---------------------------------------------------------------
; The big STELLA logo, ported from Game 1 (5x7 font on the 40-column
; asymmetric playfield; row 7 blank) — the series signature mark,
; decision #28. 8-byte tables must not cross a page.
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
; Per-row logo shading. The Atari rainbow is NOT spent here: under the
; colour-means-agency rule a rainbow mark is colour used as decoration,
; the exact habit the rule breaks. So the mark is lit in the neutral
; ramp for Games 1-3 and BLOOMS into the full rainbow in Game 4, when
; the world itself gains colour. #28 said the mark never changes; it is
; stronger for changing exactly once, at the end — a thing that never
; changes is a rule, a thing that changes once is an event.
; The rainbow's per-row banding survives, transposed into the channel
; every player can see: a highlight brightest through the middle rows.
LogoColr:   .byte $08,$0A,$0C,$0E,$0C,$0A,$08

; ===============================================================
; FLOOR TABLE — the game walks this in order (FloorSeq).
; Each floor: record ptr, per-character home-CharY table, wrap flag,
; sky base, its post-floor narration screen, and its act. Adding a
; floor = one entry in each of these + a Floor?Rec + a Floor?HomeCharY
; + a narration string in tools/gentext.py.
; ===============================================================

FloorRecLo:   .byte <Floor1Rec, <Floor2Rec, <Floor3Rec
FloorRecHi:   .byte >Floor1Rec, >Floor2Rec, >Floor3Rec
FloorHomeLo:  .byte <Floor1Home, <Floor2Home, <Floor3Home
FloorHomeHi:  .byte >Floor1Home, >Floor2Home, >Floor3Home
FloorWrapTbl: .byte 1, 1, 1           ; Act 1: wrap is the baseline
FloorSkyTbl:  .byte FLOOR1_SKY, FLOOR1_SKY, FLOOR1_SKY
FloorStoryTbl: .byte 1, 2, 3          ; narration after each floor
FloorActTbl:  .byte 1, 1, 1           ; Act 1 (framework metadata)
; char*3 — indexes both FloorBandByChar (char*3 + floor) and each
; floor's Floor?Home table (three bytes per character).
MulThree:     .byte 0, 3, 6
; The lamp band for each character on each floor (char*3 + floor);
; PrepSprites paints these bands as the colour-blind-safe home lamps.
FloorBandByChar:
        .byte 9, 7, 6           ; Stella: F1 low totem / F2 slab / F3 b3
        .byte 8, 9, 8           ; Alex:   F1 mid totem / F2 sill / F3 b2
        .byte 7, 8, 10          ; Marcus: F1 top totem / F2 heart / F3 b1

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
; The cooperative beat (one gentle beat): Alex's weak jump (~10 du)
; cannot reach the first ledge (top 76, a 12 du rise) from the ground,
; while Marcus (16) and Stella (21) can. So a friend stands on the
; centre ground as a stepstool; Alex hops onto their head and onto the
; ledge, then hops 76 -> 68 to his green home; Marcus climbs on to
; 58. tools/check_levels.py proves Alex needs the boost while Stella
; and Marcus finish alone — a genuine, load-bearing "not alone" beat.
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
        .byte 67, 76,  84       ; Stella: low ledge, the narrow column
        .byte 65, 72,  88       ; Alex:   mid ledge, double-wide (echo)
        .byte 52, 76,  84       ; Marcus: top ledge, crowning the totem

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
        .byte $00,$00,$00,$00,$00,$00,$00,$80,$C0,$80,$00,$FF
        .byte  88, 76, 68, 58, $FF,$FF    ; box tops  (ledges one-way:
        .byte  96, 76, 68, 58, $FF,$FF    ; box bottoms   top == bottom)
        .byte   0, 76, 72, 76,   0,   0   ; box lefts
        .byte 160, 84, 88, 84,   0,   0   ; box rights (excl)
        .byte 20, 79                      ; Stella: ground, left
        .byte 40, 85                      ; Alex: ground, mid-left
        .byte 60, 82                      ; Marcus: ground, centre-left

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
; rise his jump cannot make, and every friend is behind the wall.
; The answer is the floor's name in negative: the world is a
; cylinder — walk AWAY from the wall, off the edge of the screen,
; and arrive beside him. The solver proves the floor UNSOLVABLE
; with wrap off: the twist is load-bearing, not decoration.
; ===============================================================

; home CharY + x extent: the three buttress stairs, Stella b3 48-9,
; Alex b2 64-3, Marcus b1 80-6
Floor3Home:
        .byte 39, 68,  92       ; Stella: b3, the top stair
        .byte 61, 64,  96       ; Alex:   b2, the middle stair
        .byte 74, 56, 104       ; Marcus: b1, the bottom stair

; Lamp bands (FloorBandByChar): 6 = b3 (Stella), 8 = b2 (Alex),
; 10 = b1 (Marcus) — the wall wears each stair's lamp as a painted
; course at its height.
Floor3Rec:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$C0,$C0,$C0,$C0,$C0,$E0,$C0,$F0,$C0,$FC,$FF
        .byte  88,  8, 80, 64, 48,$FF     ; tops: ground,wall,b1,b2,b3
        .byte  96, 88, 88, 70, 54,$FF     ; bottoms
        .byte   0, 72, 56, 64, 68,  0     ; lefts
        .byte 160, 88,104, 96, 92,  0     ; rights (excl)
        .byte 12, 79                      ; Stella: ground, far left
        .byte 140, 85                     ; Alex: ALONE past the wall
        .byte 28, 82                      ; Marcus: ground, left

; ---------------------------------------------------------------
; Narration text (generated by tools/gentext.py):
;   screen 0 = the "STELLA WAS TOGETHER" title logo
;   screen 1 = the between-floor narration after Floor 1
; ---------------------------------------------------------------

        include "text.inc"

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
; The skeleton keeps only the F8 world-swap plumbing here: the
; byte-identical trampoline stubs (so the 8192-byte F8 layout stays
; honest and a future Act-3 floor can switch worlds) plus the minimal
; Bank1Entry / CopyBWorker targets the stubs name. The prototype
; world-swap floors' bank-1 data + real copy worker live in the
; `game2-workbench` git tag.
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
        lda BANK1HOT            ; GoCopyB
        jmp CopyBWorker
        lda BANK0HOT            ; GoBackBank0
        rts
        sei                     ; ColdStart
        cld
        lda BANK0HOT
        jmp Bank0Init

        IF * - Bank1Top != STUB_SIZE
        ECHO "F8 stubs drifted between banks — fix before flashing!"
        ERR
        ENDIF

; Minimal bank-1 targets the stubs reference. Neither is reached by
; the shipped floors (no world-swap floor is built yet); they exist so
; the F8 call/return shape is preserved and the file assembles. A real
; Act-3 floor replaces CopyBWorker with the 24-byte world-B fetch and
; Bank1Entry with a bank-1 frame (see the git tag).
Bank1Entry:
        jmp GoBank0             ; nothing in bank 1 yet: hop back
CopyBWorker:
        jmp GoBackBank0         ; no world data yet: return to caller

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
