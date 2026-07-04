; ---------------------------------------------------------------
; Stella Was Alone — game 1 of 4, Stella's Evolution
; Atari 2600, 4K ROM, no bankswitching
;
; v0.2: title screen, five levels with staged character intro
; (Stella alone -> Alex appears -> cooperation), goal markers,
; solid-wall collision so Alex's low-gap ability works, and TIA
; sound effects.
;
; Story beats (creative brief): Awakening, Exploration, Discovery,
; Connection, Ascent. Narration text screens come in a later rev.
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
NUM_LEVELS  = 5

STATE_TITLE = 0
STATE_PLAY  = 1
STATE_DONE  = 2         ; level-complete pause
STATE_WIN   = 3         ; finished all levels

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
;   +65 G0X, +66 G0Y, +67 G1X, +68 G1Y
; A box with top==bottom is one-way (land on top, pass sideways
; and from below). top=$FF is an unused pad entry.

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
BandLine    ds 1        ; kernel band countdown / title row index
RowIdx      ds 1
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

        lda #$30
        sta NUSIZ0      ; Stella: normal player, 8px missile (goal)
        lda #$35
        sta NUSIZ1      ; Alex: double-width player, 8px missile
        lda #COL_PF
        sta COLUPF
        lda #$80
        sta FirePrev
        ; State = STATE_TITLE (0) from the RAM clear

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
        jsr WinLogic
        jmp .logicDone
.doTitle:
        jsr TitleLogic
        jmp .logicDone
.doPlay:
        jsr ReadInput
        jsr UpdatePhysics
        jsr CheckGoals
        jsr UpdateSound
        jsr PositionSprites
        lda #0
        sta COLUBK
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
        lda #1
        sta CTRLPF      ; mirrored playfield in-game
        jsr GameKernel
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
        sta COLUBK
        lda INPT4
        and #$80
        bne .release
        bit FirePrev
        bpl .done
        lda #0
        sta Level
        sta FirePrev
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
        inc Level
        lda Level
        cmp #NUM_LEVELS
        bcs .win
        jsr LoadLevel
        lda #STATE_PLAY
        sta State
        rts
.win:
        lda #STATE_WIN
        sta State
        lda #240
        sta StateTimer
        rts

WinLogic:
        SUBROUTINE
        jsr UpdateSound
        lda FrameCtr
        sta COLUBK              ; celebrate: cycle the background
        dec StateTimer
        beq .toTitle
        rts
.toTitle:
        lda #0
        sta COLUBK
        lda #STATE_TITLE
        sta State
        rts

; ---------------------------------------------------------------
; LoadLevel: point the kernel and collision code at the level
; record, then place characters and goals.
; ---------------------------------------------------------------

LoadLevel:
        SUBROUTINE
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
        iny
        lda (PF0Ptr),y
        sta GoalX
        iny
        lda (PF0Ptr),y
        sta GoalY
        sta GoalDY
        iny
        lda (PF0Ptr),y
        sta GoalX+1
        iny
        lda (PF0Ptr),y
        sta GoalY+1
        sta GoalDY+1

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
        lda #$FF
        sta GoalDY+1            ; hide Alex's goal marker
        lda #$E0
        sta CharY+1             ; park Alex offscreen
.twoChars:
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
        tya
        clc
        adc #6
        tay
        lda (PlatPtr),y         ; left
        sta LV
        tya
        clc
        adc #6
        tay
        lda (PlatPtr),y         ; right
        sta RV
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
        adc #12
        tay
        lda (PlatPtr),y         ; left
        sta LV
        tya
        clc
        adc #6
        tay
        lda (PlatPtr),y         ; right
        sta RV
        lda CharX,x
        cmp RV
        bcs .landNext
        lda CharX,x
        clc
        adc WidthTbl,x
        cmp LV
        bcc .landNext
        beq .landNext
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
        tya
        clc
        adc #6
        tay
        lda (PlatPtr),y         ; left
        sta LV
        tya
        clc
        adc #6
        tay
        lda (PlatPtr),y         ; right
        sta RV
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
        lda #1                  ; reached!
        sta GoalDone,x
        lda #$FF
        sta GoalDY,x
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
        ldy #0
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
        iny
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
        sbc CharY
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
        sbc CharY+1
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
        ldx #0
        lda #7
        sta RowIdx
.tloop:
        sta WSYNC               ; ---- line 1: cycle-anchored writes
        ldy RowIdx
        lda LogoPF0L,y
        sta PF0                 ; @10
        lda LogoPF1L,y
        sta PF1                 ; @17
        lda LogoPF2L,y
        sta PF2                 ; @24
        nop
        lda LogoPF0R,y
        sta PF0                 ; @33
        lda LogoPF1R,y
        sta PF1                 ; @40
        nop
        nop
        lda LogoPF2R,y
        sta PF2                 ; @51
        sta WSYNC               ; ---- line 2: pick next row
        inx
        txa
        sec
        sbc #LOGO_TOP
        bcc .blank
        cmp #LOGO_H
        bcs .blank
        lsr
        lsr
        lsr
        jmp .store
.blank:
        lda #7
.store:
        sta RowIdx
        cpx #SCREEN_DU
        bne .tloop
        rts

; ---------------------------------------------------------------
; Character data (index 0 = Stella, 1 = Alex)
; ---------------------------------------------------------------

HeightTbl:  .byte STELLA_H, ALEX_H
WidthTbl:   .byte 8, 16
SpeedTbl:   .byte 1, 2              ; Stella slow, Alex fast
MaxXTbl:    .byte 156-8, 156-16
JumpHiTbl:  .byte $FD, $FE          ; Stella -2.5 du/fr, Alex -1.75
JumpLoTbl:  .byte $80, $40
ColP0Tbl:   .byte $36, $32          ; Stella red: bright when active
ColP1Tbl:   .byte $C2, $C8          ; Alex green: bright when active

; ---------------------------------------------------------------
; Title logo: "STELLA", 5x7 font on the 40-column playfield.
; Row 7 is blank (used for all non-logo lines).
; ---------------------------------------------------------------

LogoPF0L:   .byte $80,$40,$40,$80,$00,$40,$80,$00
LogoPF1L:   .byte $CF,$22,$02,$C2,$22,$22,$C2,$00
LogoPF2L:   .byte $7D,$04,$04,$3C,$04,$04,$7C,$00
LogoPF0R:   .byte $10,$10,$10,$10,$10,$10,$F0,$00
LogoPF1R:   .byte $20,$20,$20,$20,$20,$20,$BE,$00
LogoPF2R:   .byte $0E,$11,$11,$1F,$11,$11,$11,$00

; ---------------------------------------------------------------
; Levels. Bands are 16 scanlines; the playfield is mirrored.
; Walls: PF0 $10 (4px each side). Ground: band 11, solid.
; ---------------------------------------------------------------

LvlPtrLo:   .byte <Level1, <Level2, <Level3, <Level4, <Level5
LvlPtrHi:   .byte >Level1, >Level2, >Level3, >Level4, >Level5

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

; --- Level 2 "Exploration": climb ledges to the high perch -----
Level2:
        .byte $10,$10,$10,$10,$10,$10,$10,$30,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte 88, 72, 72, 56, 56, $FF
        .byte 96, 72, 72, 56, 56, $FF
        .byte 0,  32, 112,0,  152,0
        .byte 160,48, 128,8,  160,0
        .byte 1
        .byte 74, 88-STELLA_H
        .byte 80, 85
        .byte 0,  53                      ; goal on the left perch
        .byte 80, $FF

; --- Level 3 "Discovery": Alex appears; only he fits under the
;     pillar (8 du gap; Stella is 9 du tall) ---------------------
Level3:
        .byte $10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$00,$00,$00,$00,$E0,$E0,$E0,$E0,$E0,$00,$FF
        .byte 88, 40, $FF,$FF,$FF,$FF
        .byte 96, 80, $FF,$FF,$FF,$FF
        .byte 0,  68, 0,  0,  0,  0
        .byte 160,92, 0,  0,  0,  0
        .byte 2
        .byte 60, 88-STELLA_H
        .byte 40, 88-ALEX_H
        .byte 24, 85                      ; Stella's goal: her side
        .byte 124,85                      ; Alex's goal: past the pillar

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

; ---------------------------------------------------------------
; Vectors
; ---------------------------------------------------------------

        ORG $FFFA
        .word Reset             ; NMI (unused on the 2600)
        .word Reset             ; RESET
        .word Reset             ; IRQ (unused)
