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
;   * a rainbow TITLE screen ("STELLA WAS TOGETHER") on this game's
;     dusk-violet banded gradient sky — no menu, fire starts (decision
;     #22: Game 2 stays switch-driven);
;   * floors that play IN ORDER (not SELECT-cycled), walked from a
;     clean FLOOR TABLE (record + narration id + act);
;   * a between-floor NARRATION text screen (Game 1's text kernel +
;     tools/gentext.py pipeline, ported);
;   * boot flow: title -> Act 1 Floor 1 "Together Again" -> narration
;     -> (only one real floor so far) back to the title.
;
; Adding Floor 2, 3... is: one row in each Floor* table + one Floor?Rec
; record + one Floor?HomeCharY table + one narration string in
; tools/gentext.py's SCREENS. Act order (docs/decisions.md #18):
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
;   Fire        title: start ; narration: continue ; in play: jump
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

; --- floor sequencing ------------------------------------------
NUM_FLOORS  = 1         ; real floors built so far (Act 1 Floor 1)

FLOOR1_SKY  = $62       ; Act 1 dusk violet (blue stays Marcus's alone)
TITLE_SKY   = $62       ; the title shares Act 1's dusk-violet sky
PFA_COLOR   = $2C       ; warm tan platforms (initial COLUPF)
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
SoundId     ds 1        ; 1=jump 2=land
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
        jsr TitleLogic
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
        lda #2
        sta VBLANK
        lda #0
        sta GRP0
        sta GRP1
        sta ENAM0
        sta ENAM1
        sta ENABL
        lda #35
        sta TIM64T      ; ~30 scanlines
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
        sta FloorSeq            ; start at the first floor
        jsr LoadFloor
        lda #STATE_PLAY
        sta State
        rts
.release:
        lda #$80
        sta FirePrev
.done:
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
        rts
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
        lda #<Floor1PFDim       ; PrepSprites re-picks bright/dim per frame
        sta PFColPtr
        lda #>Floor1PFDim
        sta PFColPtr+1
        rts

; ---------------------------------------------------------------
; CheckGoal: a three-character floor completes when EACH character
; is grounded on ITS OWN colour home ledge (per-character CharY equals
; the floor's home value). All home -> show this floor's narration,
; then advance FloorSeq (looping back to the title after the last
; real floor).
; ---------------------------------------------------------------

CheckGoal:
        SUBROUTINE
        ldx #NUM_CHARS-1
.loop:
        lda OnGround,x
        beq .done               ; someone airborne: not yet
        txa
        tay
        lda CharY,x
        cmp (HomePtr),y
        bne .done               ; someone not on its own home ledge
        dex
        bpl .loop
        ; all three home: narration, then the next floor
        ldx FloorSeq
        lda FloorStoryTbl,x
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
.done:
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
; UpdateSound: game 1's one-channel effect engine, jump + land.
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
        cmp #2
        beq .land
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
        lda FrameCtr            ; pulse the home ledges: bright/dim
        and #$10                ; ~0.5s on / 0.5s off
        beq .pulseDim
        lda #<Floor1PFBri
        sta PFColPtr
        lda #>Floor1PFBri
        sta PFColPtr+1
        jmp .noPulse
.pulseDim:
        lda #<Floor1PFDim
        sta PFColPtr
        lda #>Floor1PFDim
        sta PFColPtr+1
.noPulse:
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
        lda RepoDU              ; never hop on a band boundary —
        and #7                  ; that line 1 is busy with PF writes
        bne .noShift
        inc RepoDU              ; (gap margin guarantees the +1 fits)
.noShift:
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
.kloop:
        sta WSYNC               ; ---- line 1
        dec BandLine
        bne .noBand
        iny                     ; next band:
        lda SkyGrad,y           ; gradient step (@16, in hblank)
        sta COLUBK
        lda (PF0Ptr),y
        sta PF0                 ; @24 (bit-4 wall constant: safe)
        lda (PF1Ptr),y
        sta PF1                 ; @32
        lda (PF2Ptr),y
        sta PF2                 ; @40
        lda (PFColPtr),y        ; @48 platform colour for this band —
        sta COLUPF              ; Floor 1 tints its centred home ledges
        lda #8                  ; (px 76-83, drawn @48+) their own colour
        sta BandLine
.noBand:
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
; TitleKernel: the rainbow logo "STELLA WAS TOGETHER" on this game's
; dusk-violet banded gradient sky — "evolve game 1's rainbow-logo
; technique" onto a coloured sky (decision #22: no menu, fire starts).
;
; Two zones so every scanline stays cycle-safe (the asymmetric-PF logo
; lines are already near the 76-cycle limit, so no per-band colour
; step can share them):
;   * SKY (du outside the logo block): playfield blank, COLUBK stepped
;     down the dusk gradient by band (band = du>>3 -> SkyGrad). These
;     lines are light — the gradient lives here, top and bottom.
;   * LOGO (the centred 18-du text block): the three words drawn on the
;     asymmetric playfield (all six PF bytes re-fed each scanline, as
;     game 1's text kernel), COLUPF stepped down a per-row Atari
;     rainbow (RainbowRow), COLUBK held at the mid-sky dusk colour. The
;     logo row is computed in line 1's slack and reused in line 2, so
;     line 2 has room for the loop's bookkeeping.
;
; Frame: exactly 96 du x 2 WSYNCs = 192 visible lines in both zones,
; and every WSYNC-to-WSYNC segment is <= 76 cycles, so the 262-line
; frame is stable. NewX holds the saved logo row.
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
        lda SkyGrad             ; top gradient colour for scanline 0
        sta COLUBK
        lda TextTop             ; BotV = first du past the logo block
        clc
        adc TextEnd
        sta BotV
        ldx #0                  ; X = du counter (0..95)
.tloop:
        cpx TextTop             ; above the logo block -> sky
        bcc .sky
        cpx BotV                ; below the logo block -> sky
        bcs .sky
        ; ---- LOGO du: three words on the asymmetric playfield ----
        sta WSYNC               ; ---- line 1
        txa                     ; Y = logo row = du - TextTop
        sec
        sbc TextTop
        tay
        sty NewX                ; save the row for line 2
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
        lda (TPtr+10),y
        sta PF2
        lda RainbowRow,y        ; per-row rainbow logo colour
        sta COLUPF
        sta WSYNC               ; ---- line 2 (re-feed asymmetric PF)
        ldy NewX
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
        lda (TPtr+10),y
        sta PF2
        jmp .duEnd
.sky:
        sta WSYNC               ; ---- line 1: blank PF, gradient step
        lda #0
        sta PF0
        sta PF1
        sta PF2
        txa                     ; band = du >> 3 -> dusk gradient
        lsr
        lsr
        lsr
        tay
        lda SkyGrad,y
        sta COLUBK
        sta WSYNC               ; ---- line 2
.duEnd:
        inx
        cpx #SCREEN_DU
        bne .tloop
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
JumpHiTbl:  .byte $FD, $FE, $FD     ; Stella -2.875 (apex ~22 du),
JumpLoTbl:  .byte $20, $10, $A0     ; Alex -1.9375 (~10),
                                    ; Marcus -2.375 (~15): highest,
                                    ; lowest, and in between
ColBriTbl:  .byte $46, $C8, $86     ; active = brighter luma, but
ColDimTbl:  .byte $42, $C4, $82     ; kept mid-range: high TIA luma
                                    ; whitens a hue, it does not
                                    ; strengthen it
NusizTbl:   .byte $00, $05, $00     ; Alex is double-width on P1
OtherATbl:  .byte 1, 0, 0           ; the two possible head-perches
OtherBTbl:  .byte 2, 2, 1           ; for each character

; per-band gradient shape: brighter toward the horizon (5 shades)
GradOfs:    .byte 0,0,0,2,2,2,4,4,6,6,8,8

; per-row logo rainbow (indexed by logo row 0..TextEnd-1 = up to 18):
; the Atari hue wheel at mid luma, a few rows per hue so each of the
; three title words sweeps its own part of the rainbow.
RainbowRow: .byte $46,$46,$36,$36,$26,$26,$C6,$C6,$A6,$A6,$86,$86
            .byte $76,$76,$66,$66,$56,$56,$56,$56

; ===============================================================
; FLOOR TABLE — the game walks this in order (FloorSeq).
; Each floor: record ptr, per-character home-CharY table, wrap flag,
; sky base, its post-floor narration screen, and its act. Adding a
; floor = one entry in each of these + a Floor?Rec + a Floor?HomeCharY
; + a narration string in tools/gentext.py.
; ===============================================================

FloorRecLo:   .byte <Floor1Rec
FloorRecHi:   .byte >Floor1Rec
FloorHomeLo:  .byte <Floor1HomeCharY
FloorHomeHi:  .byte >Floor1HomeCharY
FloorWrapTbl: .byte 1                 ; Act 1: wrap is the baseline
FloorSkyTbl:  .byte FLOOR1_SKY
FloorStoryTbl: .byte 1                ; narration screen 1 follows Floor 1
FloorActTbl:  .byte 1                 ; Act 1 (framework metadata)

; ===============================================================
; ACT 1, FLOOR 1 — "Together Again"
;
; The first REAL floor. All three characters, controllable (Down+Fire
; cycles Stella -> Alex -> Marcus), on a clean mirrored screen with
; wrap ON. Three per-colour HOMES form a central totem: three centred
; 8px one-way ledges (px 76-83, drawn by PF2 bit7 mirrored) stacked at
; three heights, each tinted its owner's colour by the kernel's
; per-band COLUPF (red = Stella top ledge 76, blue = Marcus mid ledge
; 68, green = Alex high ledge 60). Completes only when ALL THREE stand
; on their own-colour ledge.
;
; The cooperative beat (one gentle beat): Alex's weak jump (~10 du)
; cannot reach the first ledge (top 76, a 12 du rise) from the ground,
; while Marcus (~15) and Stella (~22) can. So a friend stands on the
; centre ground as a stepstool; Alex hops onto their head and onto the
; ledge, then climbs 76 -> 68 -> 60 to his green home. tools/
; check_levels.py proves Alex needs the boost while Stella and Marcus
; finish alone — a genuine, load-bearing "not alone" beat.
; ===============================================================

; Per-character CharY when standing on its own home ledge (ledge top
; minus character height): Stella 76-9, Alex 60-3, Marcus 68-6.
Floor1HomeCharY:  .byte 67, 57, 62

; Floor 1 per-band COLUPF: platform tan everywhere except the three
; home bands — band 7 = Alex green, band 8 = Marcus blue, band 9 =
; Stella red. PrepSprites swaps these ~2x/second so the homes pulse.
Floor1PFBri:  .byte $2C,$2C,$2C,$2C,$2C,$2C,$2C,$CC,$8A,$4A,$2C,$2C
Floor1PFDim:  .byte $2C,$2C,$2C,$2C,$2C,$2C,$2C,$C8,$86,$46,$2C,$2C

; The Floor-1 level record (66-byte layout). Open frame (wrap), a
; full-width floor, and three centred one-way home ledges.
;   PF0: open edges (top bands clear so x wraps); floor band = $F0
;   PF1: floor band only ($FF)
;   PF2: home-ledge bit7 on bands 7/8/9 (px 76-83 via the mirror); $FF floor
Floor1Rec:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$00,$FF
        .byte  88, 76, 68, 60, $FF,$FF    ; box tops  (ledges one-way:
        .byte  96, 76, 68, 60, $FF,$FF    ; box bottoms   top == bottom)
        .byte   0, 76, 76, 76,   0,   0   ; box lefts
        .byte 160, 84, 84, 84,   0,   0   ; box rights (excl)
        .byte 20, 79                      ; Stella: ground, left
        .byte 40, 85                      ; Alex: ground, mid-left
        .byte 60, 82                      ; Marcus: ground, centre-left

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
