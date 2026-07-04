; ---------------------------------------------------------------
; Stella Was Alone — game 1 of 4, Stella's Evolution
; Atari 2600, 4K ROM, no bankswitching
;
; v0.1 sandbox: Stella and Alex in one room. Move, jump, land on
; platforms, switch characters with Down+Fire. No goals, levels,
; or narration yet — this is the tracer bullet.
;
; Engine code: MIT (see repository LICENSE).
; Story/characters: CC BY-NC-SA 4.0 (see repository LICENSE-DOCS).
;
; Controls:
;   Left/Right  move active character
;   Fire        jump
;   Down+Fire   switch character
; ---------------------------------------------------------------

        processor 6502
        include "vcs.h"

; ---------------------------------------------------------------
; Constants
;
; The 192 visible scanlines are drawn as 96 double-lines ("du").
; All vertical positions and physics use du units, with 8.8
; fixed-point for the fractional parts.
; ---------------------------------------------------------------

SCREEN_DU   = 96
STELLA_H    = 9         ; tall red rectangle: 8px wide, 18 scanlines tall
ALEX_H      = 3         ; flat green rectangle: 16px wide, 6 scanlines tall

GRAV_LO     = $30       ; gravity 0.1875 du/frame^2
MAXFALL     = 3         ; terminal fall speed, du/frame

MIN_X       = 4         ; the playfield walls are 4px wide
NUM_PLATS   = 6

COL_PF      = $0E       ; platforms: white
COL_BK      = $00       ; background: black

; ---------------------------------------------------------------
; RAM ($80-$FF). Character arrays are indexed 0=Stella, 1=Alex.
; ---------------------------------------------------------------

        SEG.U VARS
        ORG $80

CharX       ds 2        ; x pixel of left edge (0-159)
CharY       ds 2        ; y in du of top edge (0-95)
CharYLo     ds 2        ; y fraction
CharVYHi    ds 2        ; vertical speed, signed du/frame
CharVYLo    ds 2        ; vertical speed fraction
OnGround    ds 2        ; nonzero when standing on something
Active      ds 1        ; which character the player controls
FirePrev    ds 1        ; fire button state last frame ($80 = up)
BandLine    ds 1        ; kernel: du lines left in current band
PrevFeet    ds 1        ; physics scratch
NewFeet     ds 1        ; physics scratch

; ---------------------------------------------------------------
; Code
; ---------------------------------------------------------------

        SEG CODE
        ORG $F000

Reset:
        sei
        cld
        ldx #0
        txa
.clear:
        dex
        txs
        pha
        bne .clear      ; clears TIA + RAM, leaves SP=$FF

        lda #1
        sta CTRLPF      ; mirrored playfield
        lda #$05
        sta NUSIZ1      ; Alex is a double-width player (16px)
        lda #COL_PF
        sta COLUPF
        lda #COL_BK
        sta COLUBK

        ; both characters start standing on the ground (top = du 88)
        lda #60
        sta CharX
        lda #88-STELLA_H
        sta CharY
        lda #96
        sta CharX+1
        lda #88-ALEX_H
        sta CharY+1
        lda #1
        sta OnGround
        sta OnGround+1
        lda #$80
        sta FirePrev

; ---------------------------------------------------------------
; Frame loop: 3 vsync + ~37 vblank + 192 kernel + ~30 overscan
; ---------------------------------------------------------------

MainLoop:
        lda #2
        sta VBLANK      ; beam off
        sta VSYNC
        sta WSYNC
        sta WSYNC
        sta WSYNC
        lda #0
        sta VSYNC
        lda #44
        sta TIM64T      ; ~37 scanlines of vertical blank

        jsr ReadInput
        jsr UpdatePhysics
        jsr PositionSprites

.waitVB:
        lda INTIM
        bne .waitVB
        sta WSYNC
        sta VBLANK      ; A=0: beam on

; --- kernel: 96 double-lines, playfield in 12 bands of 8 du ----
        ldx #0          ; du line counter
        ldy #0          ; current band
        lda #9          ; du lines until the first band switch
        sta BandLine
        lda PF0Tbl
        sta PF0
        lda PF1Tbl
        sta PF1
        lda PF2Tbl
        sta PF2

KernelLoop:
        sta WSYNC               ; ---- first scanline of the pair
        dec BandLine
        bne .noBand
        iny                     ; next band: PF writes land in hblank
        lda PF0Tbl,y
        sta PF0
        lda PF1Tbl,y
        sta PF1
        lda PF2Tbl,y
        sta PF2
        lda #8
        sta BandLine
.noBand:
        sta WSYNC               ; ---- second scanline of the pair
        txa                     ; Stella: draw if du in [CharY, CharY+H)
        sec
        sbc CharY
        cmp #STELLA_H
        bcs .noP0
        lda #$FF
        bne .setP0
.noP0:
        lda #0
.setP0:
        sta GRP0
        txa                     ; Alex
        sec
        sbc CharY+1
        cmp #ALEX_H
        bcs .noP1
        lda #$FF
        bne .setP1
.noP1:
        lda #0
.setP1:
        sta GRP1
        inx
        cpx #SCREEN_DU
        bne KernelLoop

; --- overscan ---------------------------------------------------
        lda #2
        sta VBLANK
        lda #0
        sta GRP0
        sta GRP1
        lda #35
        sta TIM64T      ; ~30 scanlines
.waitOS:
        lda INTIM
        bne .waitOS
        jmp MainLoop

; ---------------------------------------------------------------
; ReadInput: joystick moves the active character, fire jumps,
; down+fire switches. The active character is drawn brighter.
; ---------------------------------------------------------------

ReadInput:
        ldx Active
        lda ColP0Tbl,x
        sta COLUP0
        lda ColP1Tbl,x
        sta COLUP1

        lda SWCHA
        and #%01000000          ; joystick left (active low)
        bne .noLeft
        lda CharX,x
        sec
        sbc SpeedTbl,x
        cmp #MIN_X
        bcs .storeL
        lda #MIN_X
.storeL:
        sta CharX,x
.noLeft:
        lda SWCHA
        and #%10000000          ; joystick right
        bne .noRight
        lda CharX,x
        clc
        adc SpeedTbl,x
        cmp MaxXTbl,x
        bcc .storeR
        lda MaxXTbl,x
.storeR:
        sta CharX,x
.noRight:

        lda INPT4
        and #$80                ; $00 = pressed, $80 = up
        bne .release
        bit FirePrev            ; already down last frame?
        bpl .done               ; yes: not a new press
        lda SWCHA
        and #%00100000          ; holding down? (active low)
        beq .switch
        lda OnGround,x          ; fire alone: jump if grounded
        beq .pressed
        lda JumpHiTbl,x
        sta CharVYHi,x
        lda JumpLoTbl,x
        sta CharVYLo,x
        lda #0
        sta OnGround,x
        beq .pressed            ; always taken
.switch:
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
; UpdatePhysics: gravity, movement, and landing for both
; characters. Landing sweeps the feet from their previous to new
; position so fast falls can't tunnel through a surface.
; ---------------------------------------------------------------

UpdatePhysics:
        ldx #1
.charLoop:
        lda CharY,x             ; remember where the feet started
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

        bpl .checkLand          ; bonked the ceiling?
        lda #0
        sta CharY,x
        sta CharYLo,x
        sta CharVYHi,x
        sta CharVYLo,x
.checkLand:
        lda CharVYHi,x          ; only land while falling/resting
        bmi .nextChar
        lda CharY,x
        clc
        adc HeightTbl,x
        sta NewFeet

        ldy #NUM_PLATS-1
.platLoop:
        lda PlatTopTbl,y
        cmp PrevFeet
        bcc .nextPlat           ; surface above where we started
        cmp NewFeet
        beq .overlap
        bcs .nextPlat           ; feet haven't reached it yet
.overlap:
        lda CharX,x             ; horizontal overlap?
        cmp PlatRTbl,y
        bcs .nextPlat
        lda CharX,x
        clc
        adc WidthTbl,x
        cmp PlatLTbl,y
        bcc .nextPlat
        beq .nextPlat
        lda PlatTopTbl,y        ; land on it
        sec
        sbc HeightTbl,x
        sta CharY,x
        lda #0
        sta CharYLo,x
        sta CharVYHi,x
        sta CharVYLo,x
        lda #1
        sta OnGround,x
        bne .nextChar           ; always taken
.nextPlat:
        dey
        bpl .platLoop
        lda #0
        sta OnGround,x
.nextChar:
        dex
        bmi .doneChars
        jmp .charLoop           ; loop body too long for a branch
.doneChars:
        rts

; ---------------------------------------------------------------
; PositionSprites: coarse + fine horizontal positioning, once per
; frame during vblank.
; ---------------------------------------------------------------

PositionSprites:
        lda CharX
        ldx #0
        jsr SetHorizPos
        lda CharX+1
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

; A = x pixel (0-159), X = object (0=P0, 1=P1)
SetHorizPos:
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
; Level: 12 mirrored playfield bands of 16 scanlines each.
; Walls down both sides, ground across the bottom, a low center
; block both characters can reach, side ledges only Stella can
; reach, and high corner perches reached by climbing the ledges.
; ---------------------------------------------------------------

PF0Tbl:     .byte $10,$10,$10,$10,$10,$10,$10,$30,$10,$10,$10,$F0
PF1Tbl:     .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$00,$FF
PF2Tbl:     .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$FF

; collision surfaces: top edge (du), left x, right x (exclusive)
PlatTopTbl: .byte 88,  80,  72,  72,  56,  56
PlatLTbl:   .byte 0,   72,  32,  112, 0,   152
PlatRTbl:   .byte 160, 88,  48,  128, 8,   160

; ---------------------------------------------------------------
; Vectors
; ---------------------------------------------------------------

        ORG $FFFA
        .word Reset             ; NMI (unused on the 2600)
        .word Reset             ; RESET
        .word Reset             ; IRQ (unused)
