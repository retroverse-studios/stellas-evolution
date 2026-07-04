; ---------------------------------------------------------------
; Stella Was Alone — game 1 of 4, Stella's Evolution
; Atari 2600, 4K ROM, no bankswitching
;
; v0.4: ten solver-verified levels, in-game narration screens (the
; 4K script), character stacking, a rising level drone, timed mode
; on the left difficulty switch, alternate goal spots for variety,
; and a certain blue square waiting at the end.
;
; Build runs tools/check_levels.py: every level and goal variant is
; proven completable (including boost order) or the build fails.
;
; Engine code: MIT (see repository LICENSE).
; Story/characters: CC BY-NC-SA 4.0 (see repository LICENSE-DOCS).
;
; Controls:
;   Left/Right  move active character
;   Fire        jump (on title: start game)
;   Down+Fire   switch character (levels with both characters)
; ---------------------------------------------------------------

        processor 6502
        include "vcs.h"

; ---------------------------------------------------------------
; Constants. The 192 visible scanlines are 96 double-lines ("du");
; all vertical positions/physics are in du with 8.8 fixed point.
; ---------------------------------------------------------------

SCREEN_DU   = 96
STELLA_H    = 9         ; tall red rectangle: 8px wide, 18 scanlines
ALEX_H      = 3         ; flat green rectangle: 16px wide, 6 scanlines
GOAL_H      = 3         ; goal markers: 8px wide, 6 scanlines

GRAV_LO     = $30       ; gravity 0.1875 du/frame^2
MAXFALL     = 3         ; terminal fall speed, du/frame

MIN_X       = 4         ; outer walls are 4px, handled by clamping
NUM_PLATS   = 6         ; collision boxes per level (pad with $FF)
NUM_LEVELS  = 10
HIDE_Y      = $70       ; a du the kernel can never match: hides things

STATE_TITLE = 0
STATE_PLAY  = 1
STATE_DONE  = 2         ; level-complete pause
STATE_WIN   = 3         ; finished all levels
STATE_STORY = 4         ; narration screen

LOGO_TOP    = 24        ; title logo: du 24-79, 7 rows of 8 du
LOGO_H      = 56

COL_PF      = $0E       ; platforms: white
COL_LOGO    = $36       ; title logo: Stella red

; Level record layout (69 bytes each):
;   +0  12 bytes PF0 per band     +36  6 bytes box top (du)
;   +12 12 bytes PF1 per band     +42  6 bytes box bottom (du)
;   +24 12 bytes PF2 per band     +48  6 bytes box left x
;                                 +54  6 bytes box right x (excl)
;   +60 charCount, +61 SX, +62 SY, +63 AX, +64 AY,
;   +65 G0X, +66 G0Y, +67 G1X, +68 G1Y   (primary goal spots)
;   +69 G0X, +70 G0Y, +71 G1X, +72 G1Y   (alternate goal spots)
; One of the two goal layouts is picked at level load for variety;
; both must pass tools/check_levels.py. A box with top==bottom is
; one-way (land on top, pass sideways and from below). top=$FF is
; an unused pad entry.

; ---------------------------------------------------------------
; RAM ($80-$FF). Character arrays: index 0 = Stella, 1 = Alex.
; ---------------------------------------------------------------

        SEG.U VARS
        ORG $80

CharX       ds 2        ; x pixel of left edge
CharY       ds 2        ; y du of top edge
CharYLo     ds 2
CharVYHi    ds 2        ; signed du/frame
CharVYLo    ds 2
OnGround    ds 2
GoalX       ds 2        ; goal boxes (8px wide, GOAL_H du tall)
GoalY       ds 2
GoalDY      ds 2        ; y used by the kernel; $FF hides a marker
GoalDone    ds 2
Active      ds 1
FirePrev    ds 1
State       ds 1
StateTimer  ds 1
Level       ds 1
CharCount   ds 1
FrameCtr    ds 1
SoundId     ds 1        ; 1=jump 2=land 3=goal
SoundT      ds 1
PF0Ptr      ds 2        ; -> level record base (PF0 bands)
PF1Ptr      ds 2
PF2Ptr      ds 2
PlatPtr     ds 2        ; -> collision boxes
BandLine    ds 1        ; kernel band countdown / title row counter
PrevFeet    ds 1        ; physics scratch
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
TPtr        ds 12       ; story kernel: six playfield plane pointers
TextEnd     ds 1        ; index of the blank byte in each plane
TextTop     ds 1        ; first du of the text block
StoryAfter  ds 1        ; 0 = play Level next, 1 = the win screen
TimerSec    ds 1        ; timed mode
TimerFrm    ds 1
ExitOrder   ds 1        ; 0 any; 1 Stella exits last; 2 Alex last
TimedFlag   ds 1        ; SELECT: 0 = story game, 1 = endless game
SelPrev     ds 1
Rand        ds 1        ; endless mode's level shuffler
Quest       ds 1        ; 0 first run; 1 = the world turned over
CharDrawY   ds 2        ; kernel y for each character (flipped in Q2)
Band0       ds 1        ; kernel: first playfield band (0 or 11)
BandStep    ds 1        ; kernel: band direction (+1 or -1)
TFrm        ds 1        ; run clock: frames, then seconds in digits
SecOnes     ds 1
SecTens     ds 1
SecHund     ds 1
SqCol       ds 1        ; the epilogue square's breathing color

; ---------------------------------------------------------------
; Code
; ---------------------------------------------------------------

        SEG CODE
        ORG $F000

Reset:
        SUBROUTINE
        sei
        cld
        ldx #0
        txa
.clear:
        dex
        txs
        pha
        bne .clear      ; clears TIA + RAM, leaves SP=$FF

        lda #$80
        sta FirePrev
        ; State = STATE_TITLE (0) from the RAM clear; NUSIZ, VDEL
        ; and colors are all (re)set by the title and LoadLevel

; ---------------------------------------------------------------
; Frame loop
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
        lda SWCHB       ; console RESET switch restarts
        lsr
        bcs .noReset
        jmp Reset
.noReset:

        lda State
        beq .doTitle
        cmp #STATE_PLAY
        beq .doPlay
        cmp #STATE_DONE
        beq .doDone
        cmp #STATE_STORY
        beq .doStory
        jsr WinLogic
        jmp .logicDone
.doTitle:
        jsr TitleLogic
        jmp .logicDone
.doStory:
        jsr StoryLogic
        jmp .logicDone
.doPlay:
        lda SWCHB               ; console SELECT restarts the level
        and #2
        bne .noSel
        jsr LoadLevel
.noSel:
        jsr ReadInput
        jsr UpdatePhysics
        jsr CheckGoals
        jsr UpdateSound
        jsr PositionSprites
        jsr PlayExtras
        jmp .logicDone
.doDone:
        jsr DoneLogic
.logicDone:

.waitVB:
        lda INTIM
        bne .waitVB
        sta WSYNC
        sta VBLANK      ; A=0: beam on

        lda State
        beq .titleK
        cmp #STATE_STORY
        beq .storyK
        cmp #STATE_WIN
        bne .gameK
        jsr WinKernel
        jmp Overscan
.gameK:
        lda #1
        sta CTRLPF      ; mirrored playfield in-game
        lda #COL_PF
        sta COLUPF      ; back to white (the title dyes it red)
        jsr GameKernel
        jmp Overscan
.storyK:
        lda #0
        sta CTRLPF      ; asymmetric playfield for text
        lda #COL_PF
        sta COLUPF
        jsr StoryKernel
        jmp Overscan
.titleK:
        lda #0
        sta CTRLPF      ; asymmetric playfield for the logo
        lda #COL_LOGO
        sta COLUPF
        jsr TitleKernel

Overscan:
        lda #2
        sta VBLANK
        lda #0
        sta GRP0
        sta GRP1
        sta ENAM0
        sta ENAM1
        lda #35
        sta TIM64T      ; ~30 scanlines
.waitOS:
        lda INTIM
        bne .waitOS
        jmp MainLoop

; ---------------------------------------------------------------
; Title: big "STELLA" logo, fire starts the game
; ---------------------------------------------------------------

TitleLogic:
        SUBROUTINE
        lda #0
        sta AUDV1
        lda SWCHB               ; SELECT toggles the game variation
        and #2
        bne .selUp
        lda SelPrev
        beq .selHeld
        lda TimedFlag
        eor #1
        sta TimedFlag
.selHeld:
        lda #0
        sta SelPrev
        beq .selDone
.selUp:
        lda #2
        sta SelPrev
.selDone:
        lda #0                  ; ember background = timed
        ldy TimedFlag
        beq .bg
        lda #$20
.bg:
        sta COLUBK
        lda INPT4
        and #$80
        bne .release
        bit FirePrev
        bpl .done
        lda #0
        sta Level
        sta FirePrev
        sta Quest               ; a fresh run, clock/count zeroed
        sta TFrm
        sta SecOnes
        sta SecTens
        sta SecHund
        lda FrameCtr
        ora #1
        sta Rand                ; seed from the player's timing
        lda TimedFlag
        beq .story
        jsr NextRandom          ; endless: straight into the shuffle
        jsr LoadLevel
        lda #STATE_PLAY
        sta State
        rts
.story:
        jsr EnterLevel
        rts
.release:
        lda #$80
        sta FirePrev
.done:
        rts

; ---------------------------------------------------------------
; NextRandom: endless mode — pick a random level and a random
; orientation (upright or upside-down) for the next round.
; ---------------------------------------------------------------

NextRandom:
        SUBROUTINE
        lda Rand
        lsr
        bcc .noEor
        eor #$B4                ; 8-bit LFSR
.noEor:
        sta Rand
        and #1
        sta Quest               ; heads: the world turns over
        lda Rand
.mod:
        cmp #NUM_LEVELS
        bcc .got
        sbc #NUM_LEVELS
        jmp .mod
.got:
        sta Level
        rts

; ---------------------------------------------------------------
; EnterLevel: show the level's narration screen first, if it has
; one; otherwise drop straight into play.
; ---------------------------------------------------------------

EnterLevel:
        SUBROUTINE
        lda Quest               ; quest 2 skips the narration
        bne .direct
        ldx Level
        lda LvlStory,x
        cmp #$FF
        beq .direct
        jsr LoadStory
        lda #0
        sta StoryAfter
        lda #STATE_STORY
        sta State
        rts
.direct:
        jsr LoadLevel
        lda #STATE_PLAY
        sta State
        rts

; ---------------------------------------------------------------
; StoryLogic: hold on the text until fire, then continue.
; ---------------------------------------------------------------

StoryLogic:
        SUBROUTINE
        lda #0
        sta COLUBK
        sta AUDV1
        lda INPT4
        and #$80
        bne .release
        bit FirePrev
        bpl .done
        lda #0
        sta FirePrev
        lda StoryAfter
        beq .playNext
        cmp #2
        beq .quest2
        jsr EnterWin            ; 1: the stranger is waiting
        rts
.quest2:
        lda #1                  ; 2: the world turns over —
        sta Quest               ;    same levels, upside-down,
        lda #0                  ;    the clock keeps counting
        sta Level
        jsr LoadLevel
        lda #STATE_PLAY
        sta State
        rts
.playNext:
        jsr LoadLevel
        lda #STATE_PLAY
        sta State
        rts
.release:
        lda #$80
        sta FirePrev
.done:
        rts

; ---------------------------------------------------------------
; EnterWin: the final screen — a question mark, the run's number
; (seconds in the story game, levels survived in endless), and a
; small blue square, breathing.
; ---------------------------------------------------------------

EnterWin:
        SUBROUTINE
        lda #HIDE_Y             ; everyone has gone on ahead...
        sta GoalDY
        sta GoalDY+1
        lda #76
        sta GoalX+1             ; ...a small blue square waits
        lda #48
        sta CharX
        lda #56
        sta CharX+1
        lda #$03
        sta NUSIZ0              ; three close copies of each player
        lda #$33
        sta NUSIZ1              ; (and keep the 8px missile square)
        lda #1
        sta VDELP0
        sta VDELP1
        lda #11                 ; glyph pointers: ? _ H T O _
        ldx #0
        jsr SetGlyph
        lda #10
        ldx #2
        jsr SetGlyph
        lda SecHund
        ldx #4
        jsr SetGlyph
        lda SecTens
        ldx #6
        jsr SetGlyph
        lda SecOnes
        ldx #8
        jsr SetGlyph
        lda #10
        ldx #10
        jsr SetGlyph
        lda #60                 ; a beat before fire is accepted
        sta StateTimer
        lda #STATE_WIN
        sta State
        rts

; SetGlyph: A = digit (10 = blank), X = TPtr slot offset
SetGlyph:
        SUBROUTINE
        sta Temp
        asl
        asl
        asl
        sec
        sbc Temp                ; A = digit * 7
        clc
        adc #<DigitFont
        sta TPtr,x
        lda #>DigitFont
        adc #0
        sta TPtr+1,x
        rts

; ---------------------------------------------------------------
; LoadStory: A = screen id. Points the six plane pointers at the
; generated text data and centers the block vertically.
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

; ---------------------------------------------------------------
; Level-complete pause, then next level (or the win screen)
; ---------------------------------------------------------------

DoneLogic:
        SUBROUTINE
        jsr UpdateSound
        lda StateTimer
        and #$08
        sta COLUBK              ; gentle pulse
        dec StateTimer
        beq .advance
        rts
.advance:
        lda #0
        sta COLUBK
        lda TimedFlag
        beq .storyAdv
        jsr IncDigits           ; endless: one more level survived
        jsr NextRandom
        jsr LoadLevel
        lda #STATE_PLAY
        sta State
        rts
.storyAdv:
        inc Level
        lda Level
        cmp #NUM_LEVELS
        bcs .ending
        jsr EnterLevel
        rts
.ending:
        lda #4                  ; "THE WORLD SHIFTED. CHANGED." ...
        jsr LoadStory
        lda #2                  ; ...and then it literally does
        ldy Quest
        beq .after
        lda #1                  ; both worlds done: the stranger
.after:
        sta StoryAfter
        lda #STATE_STORY
        sta State
        rts

WinLogic:
        SUBROUTINE
        jsr UpdateSound
        lda #0
        sta AUDV1
        sta COLUBK
        lda #$33
        sta NUSIZ1              ; the kernel drops this to $30 for
                                ; the square; digits need it back
        lda FrameCtr            ; the stranger, breathing quietly
        lsr
        lsr
        lsr
        lsr
        and #3
        ora #$84
        sta SqCol
        jsr PositionSprites
        lda StateTimer
        beq .fireCheck
        dec StateTimer
        rts
.fireCheck:                     ; linger until the player is ready
        lda INPT4
        and #$80
        bne .release
        bit FirePrev
        bpl .done
        lda #0
        sta FirePrev
        sta Quest
        lda #STATE_TITLE
        sta State
.done:
        rts
.release:
        lda #$80
        sta FirePrev
        rts

; ---------------------------------------------------------------
; LoadLevel: point the kernel and collision code at the level
; record, then place characters and goals.
; ---------------------------------------------------------------

LoadLevel:
        SUBROUTINE
        lda #$30
        sta NUSIZ0              ; undo the epilogue's text setup
        lda #$35
        sta NUSIZ1
        lda #0
        sta VDELP0
        sta VDELP1
        ldy Quest               ; quest 2: the world turned over
        beq .upright
        lda #11
        sta Band0
        lda #$FF
        sta BandStep
        bne .oriented
.upright:
        lda #0
        sta Band0
        lda #1
        sta BandStep
.oriented:
        ldx Level
        lda LvlPtrLo,x
        sta PF0Ptr
        lda LvlPtrHi,x
        sta PF0Ptr+1
        lda PF0Ptr
        clc
        adc #12
        sta PF1Ptr
        lda PF0Ptr+1
        adc #0
        sta PF1Ptr+1
        lda PF0Ptr
        clc
        adc #24
        sta PF2Ptr
        lda PF0Ptr+1
        adc #0
        sta PF2Ptr+1
        lda PF0Ptr
        clc
        adc #36
        sta PlatPtr
        lda PF0Ptr+1
        adc #0
        sta PlatPtr+1

        ldy #60
        lda (PF0Ptr),y          ; charCount
        sta CharCount
        iny
        lda (PF0Ptr),y
        sta CharX
        iny
        lda (PF0Ptr),y
        sta CharY
        iny
        lda (PF0Ptr),y
        sta CharX+1
        iny
        lda (PF0Ptr),y
        sta CharY+1

        lda FrameCtr            ; entropy from the player's timing:
        and #1                  ; primary or alternate goal spots
        beq .primary
        ldy #69
        bne .readGoals
.primary:
        ldy #65
.readGoals:
        lda (PF0Ptr),y
        sta GoalX
        iny
        lda (PF0Ptr),y
        sta GoalY
        jsr FlipG
        sta GoalDY
        iny
        lda (PF0Ptr),y
        sta GoalX+1
        iny
        lda (PF0Ptr),y
        sta GoalY+1
        jsr FlipG
        sta GoalDY+1

        lda #60                 ; timed mode gets a minute per level
        sta TimerSec
        sta TimerFrm
        ldy #73
        lda (PF0Ptr),y          ; exit-order lock for boost levels
        sta ExitOrder

        lda #0
        sta CharYLo
        sta CharYLo+1
        sta CharVYHi
        sta CharVYHi+1
        sta CharVYLo
        sta CharVYLo+1
        sta GoalDone
        sta GoalDone+1
        sta Active
        sta SoundId
        sta SoundT
        lda #1
        sta OnGround
        sta OnGround+1

        lda CharCount
        cmp #2
        beq .twoChars
        lda #HIDE_Y
        sta GoalDY+1            ; hide Alex's goal marker
        sta CharY+1             ; park Alex offscreen
.twoChars:
        lda CharY               ; seed the kernel draw positions
        sta CharDrawY
        lda CharY+1
        sta CharDrawY+1
        rts

; IncDigits: bump the three-digit number (run seconds, or levels
; survived in endless mode), pegged at 999.
IncDigits:
        SUBROUTINE
        inc SecOnes
        lda SecOnes
        cmp #10
        bcc .out
        lda #0
        sta SecOnes
        inc SecTens
        lda SecTens
        cmp #10
        bcc .out
        lda #0
        sta SecTens
        inc SecHund
        lda SecHund
        cmp #10
        bcc .out
        lda #9
        sta SecHund
        sta SecTens
        sta SecOnes
.out:
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

; FlipG: A = a goal's y — returns the y the kernel should draw it
; at, which in quest 2 is mirrored top-for-bottom.
; MUST preserve X and Y: LoadLevel calls it mid-way through walking
; the level record with Y (that clobber put every Alex goal at the
; playfield-data bytes — the floating-marker bug).
FlipG:
        SUBROUTINE
        sta Temp
        lda Quest
        beq .out
        lda #96-GOAL_H
        sec
        sbc Temp
        rts
.out:
        lda Temp
        rts

; ---------------------------------------------------------------
; ReadInput: move the active character (with solid-box blocking),
; fire jumps, down+fire switches when both characters are present.
; ---------------------------------------------------------------

ReadInput:
        SUBROUTINE
        ldx Active
        lda ColP0Tbl,x
        sta COLUP0
        lda ColP1Tbl,x
        sta COLUP1

        lda CharX,x
        sta NewX
        lda #$FF
        sta MoveDir
        lda SWCHA
        and #%01000000          ; left (active low)
        bne .noLeft
        lda #0
        sta MoveDir
        lda NewX
        sec
        sbc SpeedTbl,x
        sta NewX
.noLeft:
        lda SWCHA
        and #%10000000          ; right
        bne .noRight
        lda #1
        sta MoveDir
        lda NewX
        clc
        adc SpeedTbl,x
        sta NewX
.noRight:
        lda MoveDir
        cmp #$FF
        beq .noMove
        jsr ClampBoxes          ; solid walls block sideways motion
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
        lda SoundT              ; jump sound (don't cut a fanfare)
        beq .jsnd
        lda SoundId
        cmp #3
        beq .pressed
.jsnd:
        lda #1
        sta SoundId
        lda #10
        sta SoundT
        jmp .pressed
.switch:
        lda CharCount
        cmp #2
        bne .pressed            ; no one to switch to yet
        lda Active
        eor #1
        tay
        lda GoalDone,y          ; can't control someone who exited
        bne .pressed
        sty Active
.pressed:
        lda #0
        sta FirePrev
        rts
.release:
        lda #$80
        sta FirePrev
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

; ---------------------------------------------------------------
; UpdatePhysics: gravity + vertical motion for each present
; character; head bonks against solid boxes while rising, swept
; landing on box tops while falling.
; ---------------------------------------------------------------

UpdatePhysics:
        SUBROUTINE
        ldx CharCount
        dex
.charLoop:
        lda GoalDone,x          ; exited characters are gone
        beq .alive
        jmp .nextChar
.alive:
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
        ; landed. thump if this was a real fall
        lda OnGround,x
        bne .noSnd
        lda CharVYHi,x
        cmp #1
        bcc .noSnd
        lda SoundT
        beq .lsnd
        lda SoundId
        cmp #3
        beq .noSnd
.lsnd:
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
        ; no box caught us — maybe the other character's head did
        lda CharCount
        cmp #2
        bne .airborne
        txa
        eor #1
        tay                     ; Y = the other character
        lda GoalDone,y
        bne .airborne           ; already exited
        lda CharY,y             ; their head as a one-way surface
        sta TopV
        cmp PrevFeet
        bcc .airborne
        cmp NewFeet
        beq .headHit
        bcs .airborne
.headHit:
        lda CharX,y
        clc
        adc WidthTbl,y
        sta RV
        lda CharX,x
        cmp RV
        bcs .airborne
        lda CharX,x
        clc
        adc WidthTbl,x
        cmp CharX,y
        bcc .airborne
        beq .airborne
        jmp .doLand             ; standing on a friend
.airborne:
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

; ---------------------------------------------------------------
; CheckGoals: each present character against its own goal box.
; When everyone present has reached theirs, the level is complete.
; ---------------------------------------------------------------

CheckGoals:
        SUBROUTINE
        ldx CharCount
        dex
.gloop:
        lda GoalDone,x
        bne .gnext
        lda GoalX,x
        clc
        adc #8
        sta Temp
        lda CharX,x
        cmp Temp
        bcs .gnext
        lda CharX,x
        clc
        adc WidthTbl,x
        cmp GoalX,x
        bcc .gnext
        beq .gnext
        lda GoalY,x
        clc
        adc #GOAL_H
        sta Temp
        lda CharY,x
        cmp Temp
        bcs .gnext
        lda CharY,x
        clc
        adc HeightTbl,x
        cmp GoalY,x
        bcc .gnext
        beq .gnext
        ; exit-order lock: the needed helper can't leave first
        lda ExitOrder
        beq .free
        sec
        sbc #1
        sta Temp
        cpx Temp
        bne .free               ; not the locked character
        txa
        eor #1
        tay
        lda GoalDone,y
        bne .free               ; partner is home: unlocked now
        lda SoundT              ; denied: buzz, stay in the level
        bne .gnext
        lda #4
        sta SoundId
        lda #6
        sta SoundT
        jmp .gnext
.free:
        lda #1                  ; reached!
        sta GoalDone,x
        lda #HIDE_Y
        sta GoalDY,x
        sta CharY,x             ; the character exits with it
        lda CharCount
        cmp #2
        bne .snd
        txa                     ; hand control to whoever is left
        eor #1
        sta Active
.snd:
        lda #3
        sta SoundId
        lda #16
        sta SoundT
.gnext:
        dex
        bpl .gloop

        lda GoalDone
        beq .out
        lda CharCount
        cmp #2
        bne .complete
        lda GoalDone+1
        beq .out
.complete:
        lda #STATE_DONE
        sta State
        lda #90
        sta StateTimer
.out:
        rts

; ---------------------------------------------------------------
; UpdateSound: tiny one-channel effect engine.
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
        cmp #4
        beq .denied
        ; goal fanfare: low note then high note
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
        lda #4
        sta AUDC0
        lda #8
        clc
        adc SoundT              ; falling timer = rising pitch
        sta AUDF0
        lda #6
        sta AUDV0
        rts
.land:
        lda #6
        sta AUDC0
        lda #25
        sta AUDF0
        lda #8
        sta AUDV0
        rts
.denied:
        lda #2                  ; flat "not yet" buzz
        sta AUDC0
        lda #28
        sta AUDF0
        lda #5
        sta AUDV0
        rts

; ---------------------------------------------------------------
; PlayExtras: the level drone (channel 1, rising pitch per level —
; the world waking up) and timed mode (left difficulty switch A:
; one minute per level, the background creeping red near the end).
; ---------------------------------------------------------------

PlayExtras:
        SUBROUTINE
        lda TimedFlag           ; endless: the digits count levels,
        bne .clock              ; not seconds
        inc TFrm                ; story: the run clock
        lda TFrm
        cmp #60
        bcc .clock
        lda #0
        sta TFrm
        jsr IncDigits
.clock:

        ldx #1                  ; kernel draw positions (flipped in
.dy:                            ; quest 2 — the view, not the world)
        lda CharY,x
        ldy Quest
        beq .keepY
        sta Temp
        lda #96
        sec
        sbc Temp
        sec
        sbc HeightTbl,x
.keepY:
        sta CharDrawY,x
        dex
        bpl .dy

        lda SWCHB               ; timed if left difficulty A, or
        and #$40                ; playing the endless game
        bne .timed
        lda TimedFlag
        bne .timed
        lda #0
        beq .setT
.timed:
        lda #1
.setT:
        sta Temp

        ; drone: a slow four-note rising figure, transposed up each
        ; level; under time pressure the figure doubles its tempo
        lda #1
        sta AUDC1
        lda FrameCtr
        ldx Temp
        beq .calm
        ldy TimerSec
        cpy #16
        bcs .calm
        asl
.calm:
        lsr
        lsr
        lsr
        lsr
        lsr
        and #3
        tay
        lda #23                 ; drone base = 23 - 2*level
        sec
        sbc Level
        sbc Level
        clc
        adc ArpOff,y
        sta AUDF1
        lda #2
        sta AUDV1

        lda #0
        sta COLUBK
        lda Temp
        beq .noTimer
        dec TimerFrm
        bne .creep
        lda #60
        sta TimerFrm
        dec TimerSec
        bne .creep
        lda TimedFlag
        beq .again
        jsr EnterWin            ; endless: the run ends here
        rts
.again:
        jsr LoadLevel           ; time's up — the level starts over
        rts
.creep:
        lda TimerSec
        cmp #16
        bcs .noTimer
        lda #16
        sec
        sbc TimerSec
        ora #$40
        sta COLUBK              ; red creeps in as time runs out
.noTimer:

        ; a locked goal blinks until the partner is home
        ldx ExitOrder
        beq .noLock
        dex                     ; X = the character who exits last
        lda GoalDone,x
        bne .noLock             ; already gone: leave it hidden
        txa
        eor #1
        tay
        lda GoalDone,y
        bne .steady             ; partner home: unlocked, steady
        lda FrameCtr
        and #2
        bne .blinkOff
.steady:
        lda GoalY,x
        jsr FlipG
        sta GoalDY,x
        rts
.blinkOff:
        lda #HIDE_Y
        sta GoalDY,x
.noLock:
        rts

; ---------------------------------------------------------------
; PositionSprites: players and goal missiles, during vblank.
; ---------------------------------------------------------------

PositionSprites:
        SUBROUTINE
        lda CharX
        ldx #0
        jsr SetHorizPos
        lda CharX+1
        ldx #1
        jsr SetHorizPos
        lda GoalX
        ldx #2
        jsr SetHorizPos
        lda GoalX+1
        ldx #3
        jsr SetHorizPos
        sta WSYNC
        sta HMOVE
        ldx #6                  ; HMCLR must wait 24+ cycles
.wait:
        dex
        bne .wait
        sta HMCLR
        rts

; A = x pixel (0-159), X = object (0=P0 1=P1 2=M0 3=M1)
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
; GameKernel: 96 double-lines. Line 1 of each pair handles the
; playfield band switch (inside hblank) and goal marker 0; line 2
; draws both characters and goal marker 1.
; ---------------------------------------------------------------

GameKernel:
        SUBROUTINE
        ldx #0
        ldy Band0               ; quest 2 walks the bands backwards
        lda #9
        sta BandLine
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
        tya
        clc
        adc BandStep
        tay
        lda (PF0Ptr),y
        sta PF0
        lda (PF1Ptr),y
        sta PF1
        lda (PF2Ptr),y
        sta PF2
        lda #8
        sta BandLine
.noBand:
        txa                     ; goal marker 0 (missile 0)
        sec
        sbc GoalDY
        cmp #GOAL_H
        bcs .nm0
        lda #2
        bne .sm0
.nm0:
        lda #0
.sm0:
        sta ENAM0
        sta WSYNC               ; ---- line 2
        txa                     ; Stella
        sec
        sbc CharDrawY
        cmp #STELLA_H
        bcs .np0
        lda #$FF
        bne .sp0
.np0:
        lda #0
.sp0:
        sta GRP0
        txa                     ; Alex
        sec
        sbc CharDrawY+1
        cmp #ALEX_H
        bcs .np1
        lda #$FF
        bne .sp1
.np1:
        lda #0
.sp1:
        sta GRP1
        txa                     ; goal marker 1 (missile 1)
        sec
        sbc GoalDY+1
        cmp #GOAL_H
        bcs .nm1
        lda #2
        bne .sm1
.nm1:
        lda #0
.sm1:
        sta ENAM1
        inx
        cpx #SCREEN_DU
        bne .kloop
        rts

; ---------------------------------------------------------------
; TitleKernel: asymmetric 40-bit playfield spelling STELLA.
; Line 1 rewrites all six PF bytes at fixed cycles; line 2 works
; out which logo row the next pair falls in (row 7 = blank).
; ---------------------------------------------------------------

TitleKernel:
        SUBROUTINE
        lda #0
        sta PF0
        sta PF1
        sta PF2
        ldx #46                 ; blank sky above the logo
        jsr BlankLines
        ldy #0                  ; seven logo rows, 8 du each
        lda #8
        sta BandLine
        ldx #56
.tloop:
        sta WSYNC               ; ---- line 1: cycle-anchored writes
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
        sta WSYNC               ; ---- line 2: the same six writes —
        lda LogoPF0L,y          ; asymmetric playfields need feeding
        sta PF0                 ; every single scanline
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
        bne .hold
        lda #8
        sta BandLine
        iny
.hold:
        dex
        bne .tloop
        lda #0                  ; clear the playfield below the logo
        sta PF0
        sta PF1
        sta PF2
        ldx #34
        jsr BlankLines
        rts

; ---------------------------------------------------------------
; WinKernel: the epilogue. A void, the run time in the classic
; 48-pixel six-glyph display (three close-spaced copies of each
; player, VDEL-cascaded), and below it a small blue square.
; 30 + 14 + 76 + 8 + 64 = 192 scanlines.
; ---------------------------------------------------------------

WinKernel:
        SUBROUTINE
        lda #0
        sta PF0
        sta PF1
        sta PF2
        sta GRP0
        sta GRP1
        sta ENAM0
        sta ENAM1
        ldx #30
        jsr BlankLines
        jsr DigitBlock          ; the run time, in white
        ldx #76
        jsr BlankLines
        lda #$30                ; single 8px missile — the digits'
        sta NUSIZ1              ; three-copy mode was tripling him
        lda SqCol               ; the stranger
        sta COLUP1
        lda #2
        sta ENAM1
        ldx #8
        jsr BlankLines
        lda #0
        sta ENAM1
        ldx #64
        jsr BlankLines
        rts

; BlankLines: X = how many scanlines of nothing
BlankLines:
        SUBROUTINE
.b:
        sta WSYNC
        dex
        bne .b
        rts

; ---------------------------------------------------------------
; DigitBlock: fourteen scanlines of six-glyph 48px sprite text
; (VDEL cascade, three close copies per player), rows from the
; TPtr glyph pointers. Used by the epilogue clock and the title
; caption.
; ---------------------------------------------------------------

DigitBlock:
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
        sta GRP0
        sta GRP1
        rts

; ---------------------------------------------------------------
; StoryKernel: narration text on the asymmetric playfield. Line 1
; of each pair rewrites all six PF bytes at fixed cycles from the
; generated plane data; line 2 picks the next row index (TextEnd
; is a blank byte, used for every non-text line).
; ---------------------------------------------------------------

StoryKernel:
        SUBROUTINE
        ldx #0
        ldy TextEnd             ; blank row until the text block starts
.sloop:
        sta WSYNC               ; ---- line 1: cycle-anchored writes
        lda (TPtr),y
        sta PF0                 ; @8
        lda (TPtr+2),y
        sta PF1                 ; @16
        lda (TPtr+4),y
        sta PF2                 ; @24
        lda (TPtr+6),y
        sta PF0                 ; @32
        lda (TPtr+8),y
        sta PF1                 ; @40
        nop
        lda (TPtr+10),y
        sta PF2                 ; @50
        sta WSYNC               ; ---- line 2: the same six writes —
        lda (TPtr),y            ; an asymmetric playfield must be
        sta PF0                 ; re-fed on EVERY scanline or the
        lda (TPtr+2),y          ; right-half values bleed into the
        sta PF1                 ; left half of alternate lines
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
; Character data (index 0 = Stella, 1 = Alex)
; ---------------------------------------------------------------

HeightTbl:  .byte STELLA_H, ALEX_H
WidthTbl:   .byte 8, 16
SpeedTbl:   .byte 1, 2              ; Stella slow, Alex fast
MaxXTbl:    .byte 156-8, 156-16
JumpHiTbl:  .byte $FD, $FE          ; Stella -2.875 du/fr, Alex -1.9375
JumpLoTbl:  .byte $20, $10          ; Stella clears 16 du (24 needs Alex's
                                    ; back); Alex clears 10 — enough to
                                    ; board Stella's head (9) but nowhere
                                    ; near the 16 du ledges
ColP0Tbl:   .byte $36, $32          ; Stella red: bright when active
ColP1Tbl:   .byte $C2, $C8          ; Alex green: bright when active

; 8x7 digit glyphs for the epilogue clock, rows stored BOTTOM-UP
; (the win kernel walks its row counter 6 -> 0). Glyph 10 = blank.
DigitFont:
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
        .byte $18,$00,$18,$0C,$06,$66,$3C   ; 11: ?

ArpOff:     .byte 8,5,3,0                       ; four-note rising figure
LvlStory:   .byte 0,1,2,$FF,$FF,3,$FF,$FF,$FF,$FF ; narration screens

; ---------------------------------------------------------------
; Title logo: "STELLA", 5x7 font on the 40-column playfield.
; Row 7 is blank (used for all non-logo lines).
; ---------------------------------------------------------------

; The seven logo rows (blank padding now lives in the kernel's
; section loops). 8-byte tables can't cross a page.
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
; per-row logo colors: the Atari rainbow
LogoColr:   .byte $46,$36,$26,$16,$C6,$86,$66

; ---------------------------------------------------------------
; Levels. Bands are 16 scanlines; the playfield is mirrored.
; Walls: PF0 $10 (4px each side). Ground: band 11, solid.
; ---------------------------------------------------------------

LvlPtrLo:   .byte <Level1, <Level2, <Level3, <Level4, <Level5
            .byte <Level6, <Level7, <Level8, <Level9, <Level10
LvlPtrHi:   .byte >Level1, >Level2, >Level3, >Level4, >Level5
            .byte >Level6, >Level7, >Level8, >Level9, >Level10

; --- Level 1 "Awakening": Stella alone; jump onto the block ----
Level1:
        .byte $10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$FF
        .byte 88, 80, $FF,$FF,$FF,$FF     ; box tops
        .byte 96, 88, $FF,$FF,$FF,$FF     ; box bottoms
        .byte 0,  72, 0,  0,  0,  0      ; box left
        .byte 160,88, 0,  0,  0,  0      ; box right
        .byte 1                           ; Stella only
        .byte 20, 88-STELLA_H             ; Stella start
        .byte 80, 85                      ; (Alex unused)
        .byte 76, 77                      ; Stella's goal: on the block
        .byte 80, $FF                     ; (no second goal)
        .byte 120,85, 80,85               ; alt: ground, far right
        .byte 0                           ; no exit-order lock

; --- Level 2 "Exploration": climb wide ledges to the high perch.
;     Far above, out of any reach, hang structures she can only
;     look at — there had to be more --------------------------- --
Level2:
        .byte $10,$10,$10,$10,$10,$10,$10,$30,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$1F,$00,$FF
        .byte $00,$00,$18,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte 88, 72, 72, 56, 56, $FF
        .byte 96, 72, 72, 56, 56, $FF
        .byte 0,  28, 112,0,  152,0
        .byte 160,48, 132,8,  160,0
        .byte 1
        .byte 74, 88-STELLA_H
        .byte 80, 85
        .byte 0,  53                      ; goal on the left perch
        .byte 80, $FF
        .byte 152,53, 80,85               ; alt: the right perch
        .byte 0                           ; no exit-order lock

; --- Level 3 "Discovery": Alex appears; only he fits under the
;     pillar (8 du gap; Stella is 9 du tall). His goal sits on a
;     corner step: jump at the far wall and it catches you -------
Level3:
        .byte $10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$70,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$00,$00,$00,$00,$E0,$E0,$E0,$E0,$E0,$00,$FF
        .byte 88, 40, 80, 80, $FF,$FF
        .byte 96, 80, 88, 88, $FF,$FF
        .byte 0,  68, 4,  148,0,  0
        .byte 160,92, 12, 156,0,  0
        .byte 2
        .byte 60, 88-STELLA_H
        .byte 30, 88-ALEX_H
        .byte 24, 85                      ; Stella's goal: her side
        .byte 146,77                      ; Alex's: the far corner step
        .byte 16, 85, 124,85              ; alt: near left / past pillar
        .byte 0                           ; no exit-order lock

; --- Level 4 "Connection": Stella climbs to her perch while
;     Alex slips under the pillar to his goal --------------------
Level4:
        .byte $10,$10,$10,$10,$10,$10,$10,$30,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$00,$FF
        .byte $00,$00,$00,$00,$00,$E0,$E0,$E0,$E0,$E0,$00,$FF
        .byte 88, 40, 72, 72, 56, 56
        .byte 96, 80, 72, 72, 56, 56
        .byte 0,  68, 32, 112,0,  152
        .byte 160,92, 48, 128,8,  160
        .byte 2
        .byte 20, 88-STELLA_H
        .byte 30, 88-ALEX_H
        .byte 0,  53                      ; Stella: left perch
        .byte 130,85                      ; Alex: far right, under
        .byte 0,  53, 100,85              ; alt: Alex just past it
        .byte 0                           ; no exit-order lock

; --- Level 5 "Ascent": Stella climbs the tower Alex slips
;     beneath — both routes through the same obstacle ------------
Level5:
        .byte $10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$F8,$F8,$F8,$00,$FF
        .byte 88, 56, 72, 72, $FF,$FF
        .byte 96, 80, 72, 72, $FF,$FF
        .byte 0,  60, 32, 112,0,  0
        .byte 160,100,48, 128,0,  0
        .byte 2
        .byte 10, 88-STELLA_H
        .byte 20, 88-ALEX_H
        .byte 76, 53                      ; Stella: top of the tower
        .byte 130,85                      ; Alex: beyond it
        .byte 76, 53, 150,85              ; alt: Alex to the corner
        .byte 0                           ; no exit-order lock

; --- Level 6 "Boost": the ledges are beyond Alex's jump — he has
;     to leap from Stella's head. (Do his goal before hers!) -----
Level6:
        .byte $10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte 88, 72, 72, $FF,$FF,$FF
        .byte 96, 72, 72, $FF,$FF,$FF
        .byte 0,  112,40, 0,  0,  0
        .byte 160,120,48, 0,  0,  0
        .byte 2
        .byte 80, 88-STELLA_H
        .byte 60, 88-ALEX_H
        .byte 20, 85                      ; Stella: ground, far left
        .byte 110,69                      ; Alex: the high right ledge
        .byte 140,85, 34,69               ; alt: mirrored
        .byte 1                           ; Stella must exit last

; --- Level 7 "Lift": the perch is above even Stella's jump — she
;     needs the extra height from Alex's back. (Her goal first!) -
Level7:
        .byte $10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte 88, 64, 64, $FF,$FF,$FF
        .byte 96, 64, 64, $FF,$FF,$FF
        .byte 0,  112,40, 0,  0,  0
        .byte 160,120,48, 0,  0,  0
        .byte 2
        .byte 60, 88-STELLA_H
        .byte 80, 88-ALEX_H
        .byte 110,61                      ; Stella: the high right perch
        .byte 20, 85                      ; Alex: ground, far left
        .byte 42, 61, 140,85              ; alt: mirrored
        .byte 2                           ; Alex must exit last

; --- Level 8 "Steps": Alex's goal is up on the far ledge — he
;     crosses under the tower, then needs Stella (who crossed over
;     it) as his step. Send him home first --------------------- --
Level8:
        .byte $10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$F8,$F8,$F8,$00,$FF
        .byte 88, 56, 72, 72, $FF,$FF
        .byte 96, 80, 72, 72, $FF,$FF
        .byte 0,  60, 32, 112,0,  0
        .byte 160,100,48, 128,0,  0
        .byte 2
        .byte 10, 88-STELLA_H
        .byte 20, 88-ALEX_H
        .byte 76, 53                      ; Stella: top of the tower
        .byte 114,69                      ; Alex: the high right ledge
        .byte 76, 53, 34, 69              ; alt: the left ledge instead
        .byte 1                           ; Stella must exit last

; --- Level 9 "Patience": Stella's perch needs Alex's back before
;     he leaves for his own goal beyond the pillar ---------------
Level9:
        .byte $10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$FF
        .byte $00,$00,$00,$00,$00,$E0,$E0,$E0,$E0,$E0,$00,$FF
        .byte 88, 40, 64, 64, $FF,$FF
        .byte 96, 80, 64, 64, $FF,$FF
        .byte 0,  68, 40, 112,0,  0
        .byte 160,92, 48, 120,0,  0
        .byte 2
        .byte 30, 88-STELLA_H
        .byte 50, 88-ALEX_H
        .byte 42, 61                      ; Stella: the left perch, lifted
        .byte 124,85                      ; Alex: beyond the pillar, after
        .byte 42, 61, 144,85              ; alt: Alex further along
        .byte 2                           ; Alex must exit last

; --- Level 10 "The Exit": over the tower and under it, and both
;     goals waiting side by side beyond ---------------------------
Level10:
        .byte $10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$00,$FF
        .byte $00,$81,$00,$00,$00,$00,$00,$F8,$F8,$F8,$00,$FF
        .byte 88, 56, 72, 72, $FF,$FF
        .byte 96, 80, 72, 72, $FF,$FF
        .byte 0,  60, 32, 112,0,  0
        .byte 160,100,48, 128,0,  0
        .byte 2
        .byte 10, 88-STELLA_H
        .byte 20, 88-ALEX_H
        .byte 118,85                      ; side by side, at the exit
        .byte 130,85
        .byte 130,85, 118,85              ; alt: swapped
        .byte 0                           ; no exit-order lock

; ---------------------------------------------------------------
; Narration text (generated by tools/gentext.py)
; ---------------------------------------------------------------

        include "text.inc"

; ---------------------------------------------------------------
; Vectors
; ---------------------------------------------------------------

        ORG $FFFA
        .word Reset             ; NMI (unused on the 2600)
        .word Reset             ; RESET
        .word Reset             ; IRQ (unused)
