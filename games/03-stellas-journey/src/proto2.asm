; ---------------------------------------------------------------
; Stella's Journey -- prototype 2: through the static
; Game 3 of 4, Stella's Evolution. Atari 2600, 16K, F6 (4 x 4K banks)
; with the Superchip: 128 bytes more RAM on the cartridge (F6SC)
;
; A test ROM, not the game. Prototype 1's tall room (decision #61),
; with the second question from DESIGN-KICKOFF.md: can Flicker carry
; a stack through the corruption, and what does it cost?
;
;   * THE CORRUPTION is a band of static from wall to wall, in a colour
;     that is nobody's (#27). The room's playfield comes in four
;     versions that differ only in the static; the view picks one every
;     four frames. Touching it sends a character back to the last lamp
;     it stood on (its home, or where it started).
;   * FLICKER passes through it, and so does anything in a stack with
;     Flicker in it (#29): standing on Flicker, or Flicker standing on
;     you, or a tower with Flicker anywhere in it.
;   * A STACK WITH FLICKER IN IT MOVES AS ONE (#29). Whoever is held
;     walks the whole stack, at its base's pace. Fire jumps the whole
;     stack, from its base, except for the one on top: it jumps off
;     alone. Only while the stack stands: nobody jumps in mid-air.
;     Off the stack and still in the static, it goes back to its lamp:
;     that is the ending's rule, in miniature.
;   * A stack without Flicker is as it always was: stand on a friend,
;     and if the friend walks away, you fall.
;   * The kernel now stores a band's colour inside horizontal blank, so
;     prototype 1's rule (nothing left of pixel 48 under a lamp) goes.
;
; Not in this prototype: a ceiling bumping a stack's upper members,
; bodies that block, gates, sound, two players.
;
; Controls: left and right walk, fire jumps, down and fire changes
; character, console RESET starts the room again.
;
; Engine code: MIT (see repository LICENSE).
; Story/characters: CC BY-NC-SA 4.0 (see repository LICENSE-DOCS).
; ---------------------------------------------------------------

        processor 6502
        include "vcs.h"

BANK0HOT    = $FFF6     ; F6: reading $1FF6-$1FF9 maps bank 0-3

; THE SUPERCHIP (decision #62). 128 bytes of RAM on the cartridge, in
; the first 256 bytes of every bank: write at $F000-$F07F, read the
; same byte back at $F080-$F0FF. Reading the write half writes
; whatever is on the bus, so nothing ever does. Code starts at $F100.
SC_W        = $F000
SC_R        = $F080
LampW       = SC_W + 0  ; COLUPF for each of the room's 32 bands: grey,
LampR       = SC_R + 0  ; the static's colour, or a home's lamp. Made
                        ; once at power-on; each frame rewrites only
                        ; the four homes' bands. The kernel reads it
                        ; through PFColPtr, offset to the view like
                        ; the playfield. (Prototype 1 rebuilt the 13
                        ; bands in view every frame, in zero page.)
CheckXW     = SC_W + 32 ; each character's last lamp: where the static
CheckXR     = SC_R + 32 ; sends it back to
CheckYW     = SC_W + 36
CheckYR     = SC_R + 36
HeadsW      = SC_W + 40 ; OnHead as FindStacks last saw it: when nobody's
HeadsR      = SC_R + 40 ; footing has changed, there's nothing to find

; vertical units are du, a double scanline, with 8.8 fixed point for
; speed, as in Games 1 and 2. A room's y runs 0-255, top to bottom.
SCREEN_DU   = 96
ROOM_BANDS  = 32
VIEW_MAX    = ROOM_BANDS*8 - SCREEN_DU     ; 160: the view's lowest top

NUM_CHARS   = 4         ; 0 Stella, 1 Alex, 2 Marcus, 3 Flicker
FLICKER     = 3
STELLA_H    = 9         ; heights in du, widths in pixels. tools/
ALEX_H      = 3         ; genroom.py reads these, so the room's homes
MARCUS_H    = 6         ; agree with the characters standing on them
FLICKER_H   = 4
STELLA_W    = 8
ALEX_W      = 16
MARCUS_W    = 8
FLICKER_W   = 6

EYES_L      = %10101111 ; Games 1 and 2: two dark pixels each way,
EYES_R      = %11110101 ; one when the character is not held
EYES_LSQ    = %10111111
EYES_RSQ    = %11111101
FLICK_BODY  = %11111100 ; Flicker: 6 px wide, rounded top and bottom
FLICK_RIM   = %01111000
FLICK_L     = %10101100
FLICK_R     = %11010100
FLICK_LSQ   = %10111100
FLICK_RSQ   = %11110100

GRAV_LO     = $30       ; gravity 0.1875 du/frame^2
MAXFALL     = 3         ; du/frame
MIN_X       = 4         ; the walls are 4 px, and x is clamped to them

CAM_DEAD    = 12        ; the held character can drift this far from
CAM_STEP    = 3         ; the middle before the view moves, at most 3
PAN_STEP    = 2         ; du a frame (the fastest fall); 2 for the pan
PAN_HOLD    = 90        ; frames on the homes before the pan

PFA_COLOR   = $0A       ; platforms: the luma no character owns (#27)
CORRUPT_COL = $1C       ; the static: gold, luma C. The first colour that
                        ; is nobody's (#27), and a brightness no
                        ; character has, so Flicker shows inside it
LAMP_OFF    = $02

VB_TIM      = 48        ; about 40 lines of vertical blank, 193 drawn,
OS_TIM      = 28        ; about 24 of overscan. Prototype 1 had 51 and
                        ; 26; stacks and the static cost overscan time,
                        ; and the lamps' home test moved there. 28, not
                        ; 29: at 29 the overscan wait ends at cycle
                        ; 59-65 of its line, close enough to the end
                        ; that some frames ran 263 lines. At 28 it ends
                        ; past cycle 70, always on the same side

; ---------------------------------------------------------------
; RAM
; ---------------------------------------------------------------

        SEG.U VARS
        ORG $80

CharX       ds 4        ; left edge, pixels
CharY       ds 4        ; top edge, room du
CharYLo     ds 4
CharVYHi    ds 4        ; signed du/frame
CharVYLo    ds 4
OnGround    ds 4
CharFace    ds 4        ; 0 left, 1 right
SquashT     ds 4        ; landing squash, frames left

Active      ds 1        ; the held character
FirePrev    ds 1        ; bit 7: fire released since the last press
FrameCtr    ds 1
ViewY       ds 1        ; the room du at the top of the screen
PanT        ds 1        ; frames left holding on the homes
CamStep     ds 1        ; how far the view may move this frame

PF0Ptr      ds 2        ; the room's tables, each offset to the band
PF1Ptr      ds 2        ; at the top of the view, so the kernel
PF2Ptr      ds 2        ; counts bands from 0 whatever the scroll
SkyPtr      ds 2
PFColPtr    ds 2        ; -> LampR, in the Superchip

; --- the kernel's inputs, rebuilt each vertical blank
BandLine    ds 1        ; du left in this band
KBand       ds 1        ; band index within the view
P0Top       ds 1        ; P0: top on screen (mod 256), height, and a
P0Hgt       ds 1        ; pointer to this frame's picture
P0Gfx       ds 2
P1Top       ds 1        ; P1's current tenant, the same
P1Hgt       ds 1
P1Gfx       ds 2
RepoDU      ds 1        ; the du P1 moves to its next tenant ($FF never)
Hop2        ds 1        ; ...and the du after that
Q1Pos       ds 1        ; P1's second tenant: where (HopPosTbl), top,
Q1Top       ds 1        ; height, picture, colour, size
Q1Hgt       ds 1
Q1Gfx       ds 1
Q1Col       ds 1
Q1Nu        ds 1
Q2Pos       ds 1        ; ...and its third
Q2Top       ds 1
Q2Hgt       ds 1
Q2Gfx       ds 1
Q2Col       ds 1
Q2Nu        ds 1
DrawY       ds 4        ; each character's top on screen, mod 256: a
                        ; little above the view is 250-255
DrawH       ds 4        ; drawn height (squash and stretch)
GfxLo       ds 4        ; this frame's picture (facing, eyes, blink)
Age         ds 4        ; frames since each was last drawn
Chain       ds 3        ; P1's tenants this frame, top to bottom
OnHead      ds 4        ; whose head each stands on, $FF for none
Fused       ds 1        ; a bit per character in Flicker's stack: they
                        ; phase, and move as one
Static      ds 1        ; which version of the playfield: the static
Rnd         ds 1        ; an 8-bit LFSR for the static
BackN       ds 1        ; how many times the static has sent someone
                        ; back (for the harness)
Moved       ds 1        ; a bit per character the stick moved this
                        ; frame: physics skips one standing still
HomeMask    ds 1        ; a bit per character standing home, one
                        ; character a frame (MarkLamps)
FRoot       ds 1        ; the bottom of Flicker's stack
StackY0     ds 1        ; its y before physics: the carried move by
                        ; however far it moved
StackG0     ds 1        ; and whether it stood

; --- scratch
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
RamEnd

; The kernel's band prefetch slots are physics scratch: physics runs
; in overscan, the kernel after vertical blank, and they never meet.
KSky        = PrevFeet
KPF0        = NewFeet
KPF1        = PrevTop
KPF2        = TopV
KCol        = BotV
; PrepSprites' working bytes, physics scratch too
Own0        = PrevFeet  ; P0's character this frame, $FF for none
ChN         = NewFeet   ; how many tenants P1 has
Cand        = PrevTop   ; a bit per character still to place
Cnd         = BotV      ; the one being tried
BandTop     = MoveDir   ; the room band at the top of the view
P1XA        = BoxIdx    ; P1's first tenant's x
Pad         = PrevTop   ; ReadInput: SWCHA, read once

        IF RamEnd > $F6
          ECHO "RAM: variables end at ", RamEnd, ", leaving too little stack"
          ERR
        ENDIF

; ===============================================================
; BANK 0
; ===============================================================

        SEG BANK0
        ORG $0000
        RORG $F000
        ds 256, 0               ; the Superchip's window. Zeros: a bank
                                ; whose first 128 bytes repeat as its
                                ; next 128 is how Stella and Gopher2600
                                ; recognise a Superchip cartridge

; The reset stub. Banks 1-3 carry the same bytes at the same address,
; so whichever bank the console powers up in, the switch to bank 0
; happens inside this stub and the jmp is fetched from bank 0.
ColdStart:
        sei
        cld
        lda BANK0HOT
        jmp Bank0Init

; A = x pixel (0-159), X = object (0 P0, 1 P1). Its loop is timed to
; the cycle, so it must not cross a page: a branch that does takes a
; cycle more each time round. (Prototype 2 found this the hard way:
; code added elsewhere pushed the loop over a page, and P0 drew 9 px
; right.) The assembly fails if it ever crosses again.
SetHorizPos:
        SUBROUTINE
        sta WSYNC
        sec
.div:
        sbc #15
        bcs .div
        IF >* != >.div
          ECHO "SetHorizPos: the loop crosses a page"
          ERR
        ENDIF
        eor #7
        asl
        asl
        asl
        asl
        sta HMP0,x
        sta RESP0,x
        rts

Bank0Init:
        SUBROUTINE
        ldx #0
        txa
.clear:
        dex
        txs
        pha
        bne .clear              ; TIA and RAM to 0, SP = $FF
        ldx #127                ; the Superchip powers up with noise
.clearSC:
        sta SC_W,x              ; (A = 0 from the clear above)
        dex
        bpl .clearSC
        lda #>GfxPage
        sta P0Gfx+1
        sta P1Gfx+1
        ldy #ROOM_BANDS-1       ; the room's colours: grey...
        lda #PFA_COLOR
.grey:
        sta LampW,y
        dey
        bpl .grey
        ldx #0                  ; ...and the static's
.cor:
        ldy CorBands,x
        bmi .corDone
        lda #CORRUPT_COL
        sta LampW,y
        inx
        bne .cor
.corDone:
        lda #>LampR
        sta PFColPtr+1
        ldx #NUM_CHARS-1
.spawn:
        lda SpawnX,x
        sta CharX,x
        lda SpawnY,x
        sta CharY,x
        lda SpawnX,x            ; the first lamp is where it starts
        sta CheckXW,x
        lda SpawnY,x
        sta CheckYW,x
        lda #$FF
        sta OnHead,x
        lda #1
        sta OnGround,x
        sta CharFace,x
        dex
        bpl .spawn
        ldx #NUM_CHARS-1
.heads:
        lda #$FF
        sta HeadsW,x
        dex
        bpl .heads
        lda #1<<FLICKER         ; Flicker, alone, is its own stack
        sta Fused
        lda #FLICKER
        sta FRoot
        lda #$A5
        sta Rnd
        lda #PAN_HOLD
        sta PanT
        lda #PAN_STEP
        sta CamStep
        lda #$80
        sta FirePrev
        sta WSYNC

; ---------------------------------------------------------------
; The frame: 3 lines of VSYNC, vertical blank (the view, the sprites),
; 192 drawn, overscan (the stick, physics).
; ---------------------------------------------------------------

MainLoop:
        SUBROUTINE
        sta WSYNC               ; VSYNC from a line's start: otherwise the
        lda #2                  ; frame's length depends on where in its
        sta VBLANK              ; line the overscan timer ran out, and
        sta VSYNC               ; moving a tick between the two halves
                                ; gave frames of 261 and 263 lines
        sta WSYNC
        sta WSYNC
        sta WSYNC
        lda #0
        sta VSYNC
        lda #VB_TIM
        sta TIM64T
        inc FrameCtr
        lda #1
        sta CTRLPF              ; mirrored playfield (every frame, so a
                                ; picture of any one frame knows it)
        lda SWCHB               ; console RESET: the room again
        lsr
        bcs .noReset
        jmp ColdStart
.noReset:
        jsr UpdateCamera
        jsr PrepSprites
        ; band 0 of the view, and how much of it shows
        ldy #0
        sty KBand
        lda (SkyPtr),y
        sta COLUBK
        lda (PFColPtr),y
        sta COLUPF
        lda (PF0Ptr),y
        sta PF0
        lda (PF1Ptr),y
        sta PF1
        lda (PF2Ptr),y
        sta PF2
        lda ViewY
        and #7
        eor #$FF
        clc
        adc #9                  ; 8 - (ViewY mod 8): the du left in the
        sta BandLine            ; first band, which counts down to 0
.wv:
        bit TIMINT
        bpl .wv
        lda #0
        sta WSYNC
        sta VBLANK
        jsr GameKernel

        sta WSYNC
        lda #2
        sta VBLANK
        lda #0
        sta GRP0
        sta GRP1
        sta PF0
        sta PF1
        sta PF2
        lda #OS_TIM
        sta TIM64T
        jsr ReadInput           ; the stick, then physics: the same order
        jsr UpdatePhysics       ; as reading it at the top of the frame,
                                ; and vertical blank needs the room
        jsr StackFollow         ; the carried sit on whoever carries them
        jsr NewStacks           ; who is in Flicker's stack now
        jsr TouchStatic         ; anyone else in the static goes back
        jsr MarkLamps           ; and a home stood on is the new lamp
.wo:
        bit TIMINT
        bpl .wo
        jmp MainLoop

; ---------------------------------------------------------------
; ReadInput: the held character walks, jumps, or hands over.
; ---------------------------------------------------------------

ReadInput:
        SUBROUTINE
        lda PanT
        beq .live
        lda INPT4               ; fire cuts the hold short
        bmi .wait
        lda #0
        sta PanT
        sta FirePrev            ; and is not also a jump
.wait:
        rts
.live:
        lda SWCHA
        sta Pad
        ldx Active              ; about to jump off Flicker's stack? Then
        lda INPT4               ; no walk this frame: the jump-off has a
        bmi .walk               ; stack to re-find and the static to
        bit FirePrev            ; check, and the walk would move all of
        bpl .walk               ; the stack first (decision #63)
        lda Pad
        and #%00100000
        beq .walk
        lda OnHead,x
        bmi .walk
        lda Fused
        and BitTbl,x
        beq .walk
        jmp .noMove
.walk:
        lda Fused               ; the walker: the held character, or the
        and BitTbl,x            ; base of Flicker's stack if it is in it
        beq .walker
        ldx FRoot
.walker:
        lda #0
        sta Temp                ; the step, signed
        lda Pad
        and #%01000000          ; left (active low)
        bne .noLeft
        jsr WalkSpeed
        eor #$FF
        clc
        adc #1
        sta Temp
        ldy Active
        lda #0
        sta CharFace,y
.noLeft:
        lda Pad
        and #%10000000          ; right
        bne .noRight
        jsr WalkSpeed
        sta Temp
        ldy Active
        lda #1
        sta CharFace,y
.noRight:
        lda Temp
        bne .stepping
        jmp .noMove
.stepping:
        ldx Active
        lda Fused
        and BitTbl,x
        bne .stackWalk
        jsr TryStep             ; alone: as far as it can go
        clc
        adc CharX,x
        sta CharX,x
        lda Moved
        ora BitTbl,x
        sta Moved
        jmp .noMove
.stackWalk:                     ; together: as far as every one of
        ldx #NUM_CHARS-1        ; them can go. Its own test, not TryStep:
.sw1:                           ; a stack moves 2 px at most, so all
        lda Fused               ; that matters is the gap to the
        and BitTbl,x            ; nearest edge ahead, and TryStep for
        bne .member             ; each member was the costliest thing
        jmp .sw2                ; in a frame (decision #63)
.member:
        lda Temp                ; the screen's edges
        bmi .eL
        lda MaxXTbl,x           ; room on the right: MaxX - x, never < 0
        sec
        sbc CharX,x
        cmp Temp
        bcs .solids
        sta Temp
        jmp .solids
.eL:
        lda #MIN_X              ; room on the left: MIN_X - x, never > 0
        sec
        sbc CharX,x
        beq .stuck
        cmp Temp                ; both below 0: the larger is the nearer
        bcc .solids
        sta Temp
.solids:
        lda CharY,x             ; beside no solid: done with this one
        cmp #SOLID_BOT
        bcs .sw2
        sta CY
        clc
        adc HeightTbl,x
        cmp #SOLID_TOP
        bcc .sw2
        beq .sw2
        sta CYH
        ldy #0
.sb:
        lda SolidList,y
        bmi .sw2
        sty BoxIdx
        tay
        lda BoxTop,y
        cmp CYH
        bcs .sn                 ; top at or below the feet
        lda BoxBot,y
        cmp CY
        bcc .sn                 ; bottom at or above the head
        beq .sn
        lda Temp
        bmi .sL
        lda CharX,x             ; walking right: the box's left edge,
        clc                     ; if it is to the right
        adc WidthTbl,x
        sta RV
        lda BoxL,y
        sec
        sbc RV
        bcc .sn
        cmp Temp
        bcs .sn
        sta Temp
        jmp .sn
.sL:
        lda CharX,x             ; walking left: the box's right edge, if
        sec                     ; it is to the left
        sbc BoxR,y
        bcc .sn
        sta LV                  ; the gap
        lda #0
        sec
        sbc Temp                ; the step's size
        cmp LV
        bcc .sn
        beq .sn
        lda #0
        sec
        sbc LV
        sta Temp
.sn:
        ldy BoxIdx
        iny
        bne .sb
.sw2:
        dex
        bmi .sw2done
        jmp .sw1
.stuck:
        jmp .noMove
.sw2done:
        lda Temp
        beq .stuck
        ldx #NUM_CHARS-1
.sw3:
        lda Fused
        and BitTbl,x
        beq .sw4
        lda CharX,x
        clc
        adc Temp
        sta CharX,x
.sw4:
        dex
        bpl .sw3
        lda Moved
        ora Fused
        sta Moved
.noMove:
        ldx Active
        lda INPT4
        bmi .release
        bit FirePrev
        bpl .done               ; still held from the last press
        lda #0
        sta FirePrev
        lda Pad
        and #%00100000          ; down and fire: the next character
        beq .switch
        lda OnGround,x
        beq .done
        lda Fused               ; in Flicker's stack, the stack is one
        and BitTbl,x            ; body: fire jumps it, from its bottom,
        beq .jump               ; whoever pressed it. Only the top can
        ldy #NUM_CHARS-1        ; leave: it jumps off alone
.onMe:
        txa
        cmp OnHead,y
        beq .whole              ; someone stands on it: not the top
        dey
        bpl .onMe
        lda OnHead,x
        bmi .whole              ; the bottom
        lda #$FF                ; the top, jumping off
        sta OnHead,x
        jsr FindStacks          ; at once: the stack without it. And off
        ldx Active              ; the stack it no longer phases: if it
        lda BackN               ; is in the static, it goes back now,
        pha                     ; before its jump can carry it clear
        jsr TouchOne
        pla
        cmp BackN
        bne .done
        beq .jump
.whole:
        ldx FRoot
.jump:
        lda JumpHiTbl,x
        sta CharVYHi,x
        lda JumpLoTbl,x
        sta CharVYLo,x
        lda #0
        sta OnGround,x
        rts
.switch:
        inx
        txa
        and #NUM_CHARS-1
        sta Active
        rts
.release:
        lda #$80
        sta FirePrev
.done:
        rts

; TryStep: X = char, Temp = a step (signed). A = how much of it X can
; take: walls and solid boxes stop it, and the answer is never past
; the step or behind it.
TryStep:
        SUBROUTINE
        lda CharX,x
        clc
        adc Temp
        sta NewX
        ldy #1
        lda Temp
        bpl .dir
        ldy #0
.dir:
        sty MoveDir
        jsr ClampBoxes
        lda NewX
        cmp #MIN_X
        bcs .a
        lda #MIN_X
.a:
        cmp MaxXTbl,x
        bcc .b
        lda MaxXTbl,x
.b:
        sec
        sbc CharX,x
        sta LV
        lda Temp
        bmi .neg
        lda LV
        bmi .zero
        cmp Temp
        bcc .ok
        lda Temp
.ok:
        rts
.neg:
        lda LV
        bpl .zero
        cmp Temp
        bcs .ok
        lda Temp
        rts
.zero:
        lda #0
        rts

; WalkSpeed: X = char. A = this frame's step. Marcus and Flicker walk
; 1.5 px a frame: an extra pixel every other frame. A stack walks at
; its base's pace.
WalkSpeed:
        lda FrameCtr
        and SpeedHalfTbl,x
        and #1
        clc
        adc SpeedTbl,x
        rts

; ClampBoxes: X = char, NewX = where it would walk, MoveDir = 0 left,
; 1 right. A solid box in the way stops it at the box's edge.
ClampBoxes:
        SUBROUTINE
        lda CharY,x
        cmp #SOLID_BOT          ; above or below every solid: nothing to
        bcs .done               ; walk into
        sta CY
        clc
        adc HeightTbl,x
        cmp #SOLID_TOP
        bcc .done
        beq .done
        sta CYH
        ldy #0
.loop:
        lda SolidList,y
        bmi .done
        sty BoxIdx
        tay
        lda BoxTop,y
        cmp CYH
        bcs .next               ; top at or below the feet
        lda BoxBot,y
        cmp CY
        bcc .next               ; bottom at or above the head
        beq .next
        lda NewX
        cmp BoxR,y
        bcs .next
        clc
        adc WidthTbl,x
        cmp BoxL,y
        bcc .next
        beq .next
        lda MoveDir
        beq .fromRight
        lda BoxL,y
        sec
        sbc WidthTbl,x
        sta NewX
        jmp .next
.fromRight:
        lda BoxR,y
        sta NewX
.next:
        ldy BoxIdx
        iny
        bne .loop
.done:
        rts

; ---------------------------------------------------------------
; UpdateCamera: the view follows the held character. It moves only
; when the character drifts more than CAM_DEAD du from the middle,
; and never past the top or bottom of the room.
; ---------------------------------------------------------------

UpdateCamera:
        SUBROUTINE
        lda PanT
        beq .follow
        dec PanT
        rts
.follow:
        ldy #CAM_DEAD           ; the dead zone, unless the view is up
        ldx Active              ; against the top or bottom of the room:
        lda CharY,x             ; there it goes all the way, so the
        clc                     ; floor and the ceiling come into view
        adc HalfHTbl,x
        sec
        sbc #SCREEN_DU/2
        bcs .c1
        lda #0
.c1:
        cmp #VIEW_MAX
        bcc .c2
        lda #VIEW_MAX
.c2:
        cmp #0
        beq .edge
        cmp #VIEW_MAX
        bne .mid
.edge:
        ldy #0
.mid:
        sty Temp
        sec
        sbc ViewY               ; where the view wants to be, from here
        beq .settled
        bcc .up
        cmp Temp
        beq .settled
        bcc .settled
        sbc Temp                ; (carry set) the distance past the dead
        cmp CamStep             ; zone, at most a step
        bcc .down
        lda CamStep
.down:
        clc
        adc ViewY
        sta ViewY
        rts
.up:
        eor #$FF                ; (carry clear) negate
        adc #1
        cmp Temp
        beq .settled
        bcc .settled
        sbc Temp
        cmp CamStep
        bcc .up2
        lda CamStep
.up2:
        sta Temp
        lda ViewY
        sec
        sbc Temp
        sta ViewY
        rts
.settled:
        lda #CAM_STEP           ; the pan is over: full speed from now
        sta CamStep
        rts

; ---------------------------------------------------------------
; PrepSprites: everything the kernel needs, rebuilt each vertical
; blank.
;   1. The room's tables, offset to the view's top band.
;   2. The lamps of the homes in view.
;   3. Each character's top on screen, height and picture.
;   4. Who is drawn: P0 is the held character if it is in view this
;      frame. P1 takes up to three more, top to bottom, wherever one
;      ends at least two du (plus a nudge off the band lines) before
;      the next begins. A character that fits nowhere waits; the one
;      that has waited longest is placed first.
;   5. P0 and P1's first tenant are positioned.
; ---------------------------------------------------------------

PrepSprites:
        SUBROUTINE
        lda FrameCtr            ; the static moves 15 times a second:
        and #3                  ; every fourth frame it takes another
        bne .still              ; of the four versions, never the same
        lda Rnd                 ; one twice running
        asl
        bcc .lfsr
        eor #$1D
.lfsr:
        sta Rnd
        and #3
        cmp Static
        bne .take
        eor #1
.take:
        sta Static
.still:
        lda ViewY
        lsr
        lsr
        lsr
        sta BandTop
        lda Static              ; the version's 32 bands, from the
        asl                     ; view's top band
        asl
        asl
        asl
        asl
        clc
        adc BandTop
        sta Temp
        clc
        adc #<RoomPF0
        sta PF0Ptr
        lda #>RoomPF0
        adc #0
        sta PF0Ptr+1
        lda Temp
        clc
        adc #<RoomPF1
        sta PF1Ptr
        lda #>RoomPF1
        adc #0
        sta PF1Ptr+1
        lda Temp
        clc
        adc #<RoomPF2
        sta PF2Ptr
        lda #>RoomPF2
        adc #0
        sta PF2Ptr+1
        lda BandTop
        clc
        adc #<RoomSky
        sta SkyPtr
        lda #>RoomSky
        adc #0
        sta SkyPtr+1
        lda BandTop
        clc
        adc #<LampR             ; (LampR is $F080: never carries)
        sta PFColPtr

; ---- the lamps. A home's band in its owner's colour: steady with its
; owner on it, blinking without, fast for the held character's own.
        ldx #NUM_CHARS-1
.lamp:
        ldy HomeBand,x
        lda HomeMask
        and BitTbl,x
        bne .lit
        cpx Active
        beq .fast
        lda FrameCtr
        and #$40                ; slow, 0.47 Hz: still to do
        jmp .test
.fast:
        lda FrameCtr
        and #$10                ; fast, 1.88 Hz: this one is yours
.test:
        bne .lit
        lda #LAMP_OFF
        bne .put
.lit:
        lda ColTbl,x
.put:
        sta LampW,y
        dex
        bpl .lamp

; ---- each character: top on screen, height, picture
        ldx #NUM_CHARS-1
.each:
        lda HeightTbl,x
        sta Temp
        lda CharY,x
        sta CY
        lda SquashT,x
        beq .noSquash
        dec SquashT,x
        inc CY                  ; landing: 1 du shorter, feet planted
        dec Temp
        jmp .eyes
.noSquash:
        lda CharVYHi,x
        bpl .eyes
        lda CY                  ; rising: 1 du taller
        beq .eyes
        dec CY
        inc Temp
.eyes:
        lda Temp
        sta DrawH,x
        lda CY
        sec
        sbc ViewY
        sta DrawY,x
        lda FrameCtr            ; blink: 4 frames in every 128
        and #$7F
        cmp #4
        bcc .blink
        lda CharFace,x
        cpx Active
        beq .pick
        ora #2                  ; not held: narrowed eyes
        bne .pick
.blink:
        lda #4
.pick:
        clc
        adc Mul5,x
        tay
        lda GfxLoTbl,y
        sta GfxLo,x
        dex
        bpl .each

; ---- who is in view this frame: a bit each in Cand
        lda #0
        sta Cand
        ldx #NUM_CHARS-1
.vis:
        cpx #FLICKER
        bne .there
        lda FrameCtr            ; Flicker is there on even frames only
        lsr
        bcs .hidden
.there:
        lda DrawY,x
        cmp #SCREEN_DU
        bcc .seen
        clc                     ; below the view, or above it: seen
        adc DrawH,x             ; only if it pokes down past the top
        bcc .hidden
        beq .hidden
.seen:
        sec
        bcs .roll
.hidden:
        clc
.roll:
        rol Cand
        dex
        bpl .vis

; ---- P0: the held character if it is there; otherwise whoever has
; waited longest (Flicker's off frames, or a pan away from the held)
        ldx Active
        lda Cand
        and BitTbl,x
        bne .own
        jsr PickOldest
.own:
        stx Own0
        txa
        bmi .p1
        lda BitTbl,x
        eor #$FF
        and Cand
        sta Cand

; ---- P1's tenants: oldest first, each kept if P1 can reach it
.p1:
        lda #0
        sta ChN
.try:
        jsr PickOldest
        txa
        bmi .chained
        lda BitTbl,x
        eor #$FF
        and Cand
        sta Cand
        stx Cnd
        lda ChN
        beq .keep
        lda Chain
        jsr Separable
        bcc .try
        lda ChN
        cmp #2
        bcc .keep
        lda Chain+1
        jsr Separable
        bcc .try
.keep:
        ldy ChN
        lda Cnd
        sta Chain,y
        inc ChN
        bne .try
.chained:
        lda ChN                 ; top to bottom
        cmp #2
        bcc .sorted
        ldy #0
        jsr OrderPair
        lda ChN
        cmp #3
        bcc .sorted
        ldy #1
        jsr OrderPair
        ldy #0
        jsr OrderPair
.sorted:

; ---- ages: everyone waits a frame longer, except who is drawn
        ldx #NUM_CHARS-1
.age:
        lda Age,x
        cmp #$FF
        beq .old
        inc Age,x
.old:
        dex
        bpl .age
        lda #0
        ldx Own0
        bmi .z1
        sta Age,x
.z1:
        ldy ChN
.z2:
        dey
        bmi .z3
        ldx Chain,y
        sta Age,x
        jmp .z2
.z3:

; ---- fill P1's slots
        lda #$FF
        sta RepoDU
        sta Hop2
        lda #0
        sta P1Hgt
        sta P1XA
        lda ChN
        beq .p1done
        ldx Chain
        lda DrawY,x
        sta P1Top
        lda DrawH,x
        sta P1Hgt
        lda GfxLo,x
        sta P1Gfx
        lda ColTbl,x
        sta COLUP1
        lda NusizTbl,x
        sta NUSIZ1
        lda CharX,x
        sta P1XA
        lda ChN
        cmp #2
        bcc .p1done
        jsr HopAfter
        sta RepoDU
        ldx Chain+1
        ldy CharX,x
        lda HopPosTbl,y
        sta Q1Pos
        lda DrawY,x
        sta Q1Top
        lda DrawH,x
        sta Q1Hgt
        lda GfxLo,x
        sta Q1Gfx
        lda ColTbl,x
        sta Q1Col
        lda NusizTbl,x
        sta Q1Nu
        lda ChN
        cmp #3
        bcc .p1done
        jsr HopAfter
        sta Hop2
        ldx Chain+2
        ldy CharX,x
        lda HopPosTbl,y
        sta Q2Pos
        lda DrawY,x
        sta Q2Top
        lda DrawH,x
        sta Q2Hgt
        lda GfxLo,x
        sta Q2Gfx
        lda ColTbl,x
        sta Q2Col
        lda NusizTbl,x
        sta Q2Nu
.p1done:

; ---- P0
        lda #0
        sta P0Hgt
        ldx Own0
        bmi .p0none
        lda DrawY,x
        sta P0Top
        lda DrawH,x
        sta P0Hgt
        lda GfxLo,x
        sta P0Gfx
        lda ColTbl,x
        sta COLUP0
        lda NusizTbl,x
        sta NUSIZ0
        lda CharX,x
        jmp .p0at               ; (not bpl: x is 128 or more on the right)
.p0none:
        lda #0
.p0at:
        ldx #0
        jsr SetHorizPos
        lda P1XA
        ldx #1
        jsr SetHorizPos
        sta WSYNC
        sta HMOVE
        ldx #6                  ; HMCLR waits 24 cycles after HMOVE
.hm:
        dex
        bne .hm
        sta HMCLR
        rts

; PickOldest: X = the character in Cand that has waited longest (the
; lowest index on a tie), or $FF if Cand is empty.
PickOldest:
        SUBROUTINE
        ldx #$FF
        lda Cand
        beq .none
        ldy #NUM_CHARS-1
.l:
        lda Cand
        and BitTbl,y
        beq .n
        cpx #$FF
        beq .take
        lda Age,y
        cmp Age,x
        bcc .n
.take:
        tya
        tax
.n:
        dey
        bpl .l
.none:
        rts

; Separable: A = a tenant already kept, Cnd = a candidate. Carry set
; if P1 can draw both in one frame: the upper one's hop, nudged off the
; band lines, plus the two du a hop takes, ends at or before the lower
; one's top. Compared with every top shifted 16 down, so a character
; poking in from above the view (top 250-255) sorts first.
Separable:
        SUBROUTINE
        tax                     ; X = kept
        ldy Cnd                 ; Y = candidate
        lda DrawY,x
        clc
        adc #16
        sta LV
        lda DrawY,y
        clc
        adc #16
        cmp LV
        bcs .keptUpper
        tya                     ; the candidate is the upper one; LV
        tax                     ; already holds the lower one's top
        jmp .test
.keptUpper:
        sta LV                  ; the candidate is the lower one
.test:
        jsr HopAfter            ; X = the upper one
        clc
        adc #16+2
        cmp LV
        beq .yes
        bcc .yes
        clc
        rts
.yes:
        sec
        rts

; HopAfter: X = a tenant. A = the du P1 can move away from it: one
; past its bottom on screen, nudged so that neither du of the hop is a
; band's prefetch line or boundary line, which the hop has no time
; for. The du past the bottom is there because the hop's first line
; still shows the du before it: a hop right at the bottom would move
; P1 while the last row was on screen and cut its second line.
HopAfter:
        lda DrawY,x
        sec                     ; +1
        adc DrawH,x
        sta TopV
        clc
        adc ViewY               ; (du + ViewY) mod 8 = where in its band
        and #7
        tay
        lda TopV
        clc
        adc NudgeTbl,y
        rts
NudgeTbl:   .byte 1, 0, 0, 0, 0, 0, 3, 2

; OrderPair: Y = i. Puts Chain[i] and Chain[i+1] top to bottom.
OrderPair:
        SUBROUTINE
        ldx Chain,y
        lda DrawY,x
        clc
        adc #16
        sta LV
        ldx Chain+1,y
        lda DrawY,x
        clc
        adc #16
        cmp LV
        bcs .ok
        lda Chain,y
        stx Chain,y
        sta Chain+1,y
.ok:
        rts

; AtHome: X = char. Carry set if it stands on its home.
AtHome:
        SUBROUTINE
        lda OnGround,x
        beq .no
        lda CharY,x
        cmp HomeY,x
        bne .no
        lda CharX,x
        cmp HomeR,x
        bcs .no
        clc
        adc WidthTbl,x
        cmp HomeL,x
        bcc .no
        beq .no
        sec
        rts
.no:
        clc
        rts


; ---------------------------------------------------------------
; GameKernel: 96 du, two lines each.
;
; Line 1 of a du keeps the bands. On a band's last line 1 it fetches
; the next band's sky, playfield and colour (indexed loads); that du's
; line 2 draws, and runs straight into the new band's first line,
; which stores all five inside horizontal blank. (Prototype 1 found out
; whether a du was a band's first by counting at the top of line 1,
; and its colour store fell at pixel 46.) Line 2 draws P0 and P1 from
; their pictures.
;
; Where P1 hops to its next tenant, the hop takes two du: line 1
; moves P1, line 2 draws P0 and gives P1 the new tenant's top, height,
; picture, colour and size, line 3 moves the queue up, line 4 draws
; P0. P1 draws nothing for those two du, which is why tenants need a
; gap. PrepSprites keeps a hop off the band lines.
; ---------------------------------------------------------------

GameKernel:
        SUBROUTINE
        ldx #0
.kloop:
        sta WSYNC               ; ---- line 1
        dec BandLine
        beq .prefetch
.line2:
        sta WSYNC               ; ---- line 2
        txa
        sec
        sbc P0Top
        cmp P0Hgt
        bcs .p0off
        tay
        lda (P0Gfx),y
        .byte $2C               ; skip the lda #0 (a read of $00A9: RAM)
.p0off:
        lda #0
        sta GRP0
        txa
        sec
        sbc P1Top
        cmp P1Hgt
        bcs .p1off
        tay
        lda (P1Gfx),y
        .byte $2C
.p1off:
        lda #0
        sta GRP1
        inx
        cpx RepoDU
        beq .hop
        cpx #SCREEN_DU
        bne .kloop
        rts

.prefetch:                      ; a band's last line 1: fetch the next
        inc KBand               ; band's sky, playfield and colour
        ldy KBand
        lda (SkyPtr),y
        sta KSky
        lda (PF0Ptr),y
        sta KPF0
        lda (PF1Ptr),y
        sta KPF1
        lda (PF2Ptr),y
        sta KPF2
        lda (PFColPtr),y
        sta KCol
        sta WSYNC               ; ---- its line 2, as .line2
        txa
        sec
        sbc P0Top
        cmp P0Hgt
        bcs .q0off
        tay
        lda (P0Gfx),y
        .byte $2C
.q0off:
        lda #0
        sta GRP0
        txa
        sec
        sbc P1Top
        cmp P1Hgt
        bcs .q1off
        tay
        lda (P1Gfx),y
        .byte $2C
.q1off:
        lda #0
        sta GRP1
        inx                     ; (never a hop on the next du: HopAfter
        cpx #SCREEN_DU          ; keeps hops off it)
        beq .end
        sta WSYNC               ; ---- the new band's line 1: all five
        lda KSky                ; stores inside horizontal blank, so
        sta COLUBK              ; @6  a colour change shows on the
        lda KCol                ;     band's first line, whatever is
        sta COLUPF              ; @12 drawn at its left
        lda KPF0
        sta PF0                 ; @18
        lda KPF1
        sta PF1                 ; @24
        lda KPF2
        sta PF2                 ; @30
        lda #7
        sta BandLine
        jmp .line2
.end:
        rts

.hop:                           ; (GRP1 is already 0: the du before
        lda Q1Pos               ; a hop is past the tenant's bottom)
        sta HMP1                ; the fine shift: the high nibble (the
        and #$0F                ; TIA ignores the low one)
        tay                     ; the coarse count
        sta WSYNC               ; ---- hop line 1: move P1
.hdly:
        dey
        bne .hdly
        IF >* != >.hdly
          ECHO "the hop's delay loop crosses a page"
          ERR
        ENDIF
        sta RESP1               ; lands on cycle 5n+1: 71 at x 150
        sta WSYNC               ; ---- hop line 2
        sta HMOVE
        dec BandLine            ; (line 1's count, skipped above)
        txa
        sec
        sbc P0Top
        cmp P0Hgt
        bcs .h0off
        tay
        lda (P0Gfx),y
        .byte $2C
.h0off:
        lda #0
        sta GRP0
        lda Q1Top               ; P1 becomes the next tenant
        sta P1Top
        lda Q1Hgt
        sta P1Hgt
        lda Q1Gfx
        sta P1Gfx
        lda Q1Col
        sta COLUP1
        lda Q1Nu
        sta NUSIZ1
        inx
        sta WSYNC               ; ---- hop line 3: the next du's line 1
        dec BandLine
        sta HMCLR
        lda Q2Pos               ; the queue moves up
        sta Q1Pos
        lda Q2Top
        sta Q1Top
        lda Q2Hgt
        sta Q1Hgt
        lda Q2Gfx
        sta Q1Gfx
        lda Q2Col
        sta Q1Col
        lda Q2Nu
        sta Q1Nu
        lda Hop2
        sta RepoDU
        sta WSYNC               ; ---- hop line 4
        txa
        sec
        sbc P0Top
        cmp P0Hgt
        bcs .h1off
        tay
        lda (P0Gfx),y
        .byte $2C
.h1off:
        lda #0
        sta GRP0
        inx
        jmp .kloop              ; (a hop never ends on the last du)

; ---------------------------------------------------------------
; UpdatePhysics: gravity, then a swept landing on box tops or a
; friend's head while falling, or a bump on a solid box's underside
; while rising. As Game 2, with four characters and a taller room:
; the landing only looks at boxes whose tops are in the bands the
; feet passed through (BandStart), and the bump only at solids.
; ---------------------------------------------------------------

UpdatePhysics:
        SUBROUTINE
        ldx FRoot
        lda CharY,x
        sta StackY0
        lda OnGround,x
        sta StackG0
        ldx #NUM_CHARS-1
.charLoop:
        lda Fused               ; carried in Flicker's stack: its base
        and BitTbl,x            ; moves it (StackFollow)
        beq .free
        lda OnHead,x
        bmi .free
        jmp .nextChar
.free:
        lda OnGround,x          ; standing still on a box: nothing can
        beq .phys               ; have changed, so nothing to work out.
        lda OnHead,x            ; (On a friend's head it can: the friend
        bpl .phys               ; may have walked.)
        lda Moved
        and BitTbl,x
        bne .phys
        jmp .nextChar
.phys:
        lda #$FF                ; on nobody, until it lands on someone
        sta OnHead,x
        lda CharY,x
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
        bmi .apply
        cmp #MAXFALL
        bcc .apply
        lda #MAXFALL
        sta CharVYHi,x
        lda #0
        sta CharVYLo,x
.apply:
        lda CharYLo,x           ; y += vy
        clc
        adc CharVYLo,x
        sta CharYLo,x
        lda CharY,x
        adc CharVYHi,x
        ldy CharVYHi,x
        bpl .store              ; falling
        bcs .store              ; rising, still in the room
        lda #0                  ; rose past the room's top: stop there
        sta CharYLo,x
        sta CharVYHi,x
        sta CharVYLo,x
.store:
        sta CharY,x
        lda CharVYHi,x
        bpl .land
        jmp .bump

; --- falling: the first box top the feet reached
.land:
        lda CharY,x
        clc
        adc HeightTbl,x
        sta NewFeet
        lsr
        lsr
        lsr
        tay
        lda BandStart+1,y
        sta BoxIdx              ; one past the last box to look at
        lda PrevFeet
        lsr
        lsr
        lsr
        tay
        lda BandStart,y
        tay
.landLoop:
        cpy BoxIdx
        bcs .heads
        lda BoxTop,y
        cmp PrevFeet
        bcc .landNext           ; above where the feet started
        cmp NewFeet
        beq .reach
        bcs .heads              ; past the feet, and so is every later box
.reach:
        sta TopV
        lda CharX,x
        cmp BoxR,y
        bcs .landNext
        clc
        adc WidthTbl,x
        cmp BoxL,y
        bcc .landNext
        beq .landNext
        jmp .doLand
.landNext:
        iny
        bne .landLoop
.heads:                         ; no box: maybe a friend's head
        stx CYH
        ldy #NUM_CHARS-1
.head:                          ; (HeadTest, inline: called three
        cpy CYH                 ; times for every character in the
        beq .headNext           ; air, its jsr and rts were worth
        lda CharY,y             ; saving)
        cmp PrevFeet
        bcc .headNext           ; the head is above where the feet were
        cmp NewFeet
        beq .hHit
        bcs .headNext           ; the feet haven't reached it
.hHit:
        sta TopV
        lda CharX,y
        clc
        adc WidthTbl,y
        sta RV
        lda CharX,x
        cmp RV
        bcs .headNext
        clc
        adc WidthTbl,x
        cmp CharX,y
        bcc .headNext
        beq .headNext
        jmp .onHead
.headNext:
        dey
        bpl .head
        lda #0
        sta OnGround,x
        jmp .nextChar
.onHead:
        tya
        sta OnHead,x
.doLand:
        lda OnGround,x
        bne .quiet
        lda CharVYHi,x
        cmp #1
        bcc .quiet
        lda #4
        sta SquashT,x
.quiet:
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

; --- rising: bump the head on a solid box's underside
.bump:
        lda PrevFeet
        sec
        sbc HeightTbl,x
        sta PrevTop
        ldy #0
.bumpLoop:
        lda SolidList,y
        bmi .nextChar
        sty BoxIdx
        tay
        lda BoxBot,y
        sta BotV
        lda PrevTop
        cmp BotV
        bcc .bumpNext           ; the head was already above it
        lda CharY,x
        cmp BotV
        bcs .bumpNext           ; not up to it yet
        lda CharX,x
        cmp BoxR,y
        bcs .bumpNext
        clc
        adc WidthTbl,x
        cmp BoxL,y
        bcc .bumpNext
        beq .bumpNext
        lda BotV
        sta CharY,x
        lda #0
        sta CharYLo,x
        sta CharVYHi,x
        sta CharVYLo,x
        jmp .nextChar
.bumpNext:
        ldy BoxIdx
        iny
        bne .bumpLoop

.nextChar:
        dex
        bmi .done
        jmp .charLoop
.done:
        lda #0
        sta Moved
        rts

; StackFollow: the carried in Flicker's stack move up or down by as
; much as its bottom did, and stand when it stands. They move as one
; body, so one pass does it. Standing only when the bottom stands is
; the rule of Games 1 and 2, where nobody jumps in mid-air: a rider
; can jump off a stack that stands, not one that is falling or rising.
StackFollow:
        SUBROUTINE
        lda Fused
        cmp #1<<FLICKER         ; Flicker alone: nobody carried
        beq .done
        ldx FRoot
        lda OnGround,x
        sta RV
        lda CharY,x
        sec
        sbc StackY0
        sta LV
        bne .follow             ; the bottom moved up or down, or
        lda RV                  ; took off or landed: follow it.
        cmp StackG0             ; Otherwise (walking on the level,
        beq .done               ; standing) there is nothing to do
.follow:
        ldx #NUM_CHARS-1
.m:
        lda Fused
        and BitTbl,x
        beq .n
        lda OnHead,x
        bmi .n                  ; the bottom itself
        lda RV
        sta OnGround,x
        lda CharY,x
        clc
        adc LV
        sta CharY,x
.n:
        dex
        bpl .m
.done:
        rts

; NewStacks: FindStacks, if a footing changed that touches Flicker's
; stack: one of its members' footing, or someone landing on a member.
; A stack that only walks or falls keeps its shape, and finding it
; again cost a four-high tower four lines of overscan a frame. Changes
; elsewhere (Stella landing on Alex, with Flicker apart) are noted and
; nothing more.
NewStacks:
        SUBROUTINE
        ldx #NUM_CHARS-1
.cmp:
        lda OnHead,x
        cmp HeadsR,x
        beq .same
        lda Fused               ; one of the stack's own
        and BitTbl,x
        bne FindStacks
        ldy OnHead,x            ; on one of the stack's own
        bmi .note
        lda Fused
        and BitTbl,y
        bne FindStacks
.note:
        lda OnHead,x
        sta HeadsW,x
.same:
        dex
        bpl .cmp
        rts

; FindStacks: the bottom of Flicker's stack, and who is in it. Nobody
; can stand on someone who stands on them, so every walk down should
; end; each is cut at four steps all the same, because a hang is the
; worst way to find out otherwise. (The harness found one, by placing
; characters by hand: two each recorded as standing on the other.)
FindStacks:
        SUBROUTINE
        ldx #NUM_CHARS-1
.save:
        lda OnHead,x
        sta HeadsW,x
        dex
        bpl .save
        lda OnHead              ; nobody on anybody: Flicker's stack is
        and OnHead+1            ; Flicker
        and OnHead+2
        and OnHead+3
        cmp #$FF
        bne .some
        lda #FLICKER
        sta FRoot
        lda #1<<FLICKER
        sta Fused
        rts
.some:
        ldy #FLICKER
        lda #NUM_CHARS
        sta LV
.f:
        lda OnHead,y
        bmi .fr
        tay
        dec LV
        bne .f
.fr:
        sty FRoot
        lda #0
        sta Fused
        ldx #NUM_CHARS-1
.c:
        txa
        tay
        lda #NUM_CHARS
        sta LV
.e:
        lda OnHead,y
        bmi .b
        tay
        dec LV
        bne .e
.b:
        cpy FRoot
        bne .n
        lda Fused
        ora BitTbl,x
        sta Fused
.n:
        dex
        bpl .c
        rts

; TouchStatic: anyone not in Flicker's stack who touches the static
; goes back to its last lamp.
TouchStatic:
        SUBROUTINE
        ldx #NUM_CHARS-1
.c:
        lda Fused
        and BitTbl,x
        bne .next
        jsr TouchOne
.next:
        dex
        bpl .c
        rts

; TouchOne: X = a character not in Flicker's stack. If it touches the
; static, back to its last lamp. Keeps X.
TouchOne:
        SUBROUTINE
        lda CharY,x             ; above or below all of it: no
        cmp #COR_BOT
        bcs .no
        clc
        adc HeightTbl,x
        cmp #COR_TOP
        bcc .no
        beq .no
        ldy #COR_N-1
.box:
        lda CharY,x
        cmp CorBot,y
        bcs .nb                 ; its top is below the static
        clc
        adc HeightTbl,x
        cmp CorTop,y
        bcc .nb                 ; its feet are above it
        beq .nb
        lda CharX,x
        cmp CorR,y
        bcs .nb
        clc
        adc WidthTbl,x
        cmp CorL,y
        bcc .nb
        beq .nb
        lda CheckXR,x           ; back to the lamp
        sta CharX,x
        lda CheckYR,x
        sta CharY,x
        lda #0
        sta CharYLo,x
        sta CharVYHi,x
        sta CharVYLo,x
        sta SquashT,x
        lda #1
        sta OnGround,x
        lda #$FF
        sta OnHead,x
        lda Moved
        ora BitTbl,x
        sta Moved
        inc BackN
        rts
.nb:
        dey
        bpl .box
.no:
        rts

; MarkLamps: who stands on their home, one character a frame in
; turn: its lamp steadies, and its home becomes the place the static
; sends it back to. Four frames late at most, a fifteenth of a second.
MarkLamps:
        SUBROUTINE
        lda FrameCtr
        and #NUM_CHARS-1
        tax
        lda BitTbl,x
        eor #$FF
        and HomeMask
        sta HomeMask
        jsr AtHome
        bcc .n
        lda HomeMask
        ora BitTbl,x
        sta HomeMask
        lda CharX,x
        sta CheckXW,x
        lda CharY,x
        sta CheckYW,x
.n:
        rts

; ---------------------------------------------------------------
; Character data: 0 Stella, 1 Alex, 2 Marcus, 3 Flicker
; ---------------------------------------------------------------

HeightTbl:  .byte STELLA_H, ALEX_H, MARCUS_H, FLICKER_H
HalfHTbl:   .byte STELLA_H/2, ALEX_H/2, MARCUS_H/2, FLICKER_H/2
WidthTbl:   .byte STELLA_W, ALEX_W, MARCUS_W, FLICKER_W
SpeedTbl:   .byte 1, 2, 1, 1
SpeedHalfTbl: .byte 0, 0, 1, 1
MaxXTbl:    .byte 156-STELLA_W, 156-ALEX_W, 156-MARCUS_W, 156-FLICKER_W
JumpHiTbl:  .byte $FD, $FE, $FD, $FD    ; Stella -2.875 (rise 21 du),
JumpLoTbl:  .byte $20, $10, $80, $80    ; Alex -1.94 (10), Marcus -2.5
                                        ; (16); Flicker as Marcus for now
ColTbl:     .byte $38, $CE, $84, $66    ; luma 8, E, 4 and 6: four steps
                                        ; of brightness, none of them the
                                        ; platforms' A (#27)
NusizTbl:   .byte $00, $05, $00, $00    ; Alex is drawn double width
Mul5:       .byte 0, 5, 10, 15

; HopPosTbl[x]: how a hop puts P1 at x. The low nibble is a count n:
; the hop counts it down in a five-cycle loop and strikes RESP1 on
; cycle 5n+1, which puts P1 at 15n-60, or at 3 when that cycle is still
; in horizontal blank (n = 4). The high nibble is HMP1's shift for the
; rest of the way, -7 to +7. A table, because the hop's line has no
; time to divide, and vertical blank has little more: SetHorizPos
; strikes RESP1 at cycle 74 for x 150, and the hop's next WSYNC would
; land on the line after.
HopPosTbl:
HX      SET 0
        REPEAT 160
HN      SET (HX + 67) / 15
HT      SET HX + 67 - HN * 15
        IF HN == 4
HV      SET 10 - HT
        ELSE
HV      SET 7 - HT
        ENDIF
        .byte ((HV & $0F) << 4) | HN
HX      SET HX + 1
        REPEND
BitTbl:     .byte 1, 2, 4, 8

        include "room2.inc"

; ---------------------------------------------------------------
; The pictures, one page so a pointer's high byte never changes. Each
; is a character's height plus one row, for the stretch of a jump.
; Five each: facing left, right, left narrowed, right narrowed, blink.
; ---------------------------------------------------------------

        ALIGN 256
GfxPage:
StellaL:    .byte $FF,EYES_L,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
StellaR:    .byte $FF,EYES_R,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
StellaLS:   .byte $FF,EYES_LSQ,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
StellaRS:   .byte $FF,EYES_RSQ,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
StellaB:    .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
AlexL:      .byte $FF,EYES_L,$FF,$FF
AlexR:      .byte $FF,EYES_R,$FF,$FF
AlexLS:     .byte $FF,EYES_LSQ,$FF,$FF
AlexRS:     .byte $FF,EYES_RSQ,$FF,$FF
AlexB:      .byte $FF,$FF,$FF,$FF
MarcusL:    .byte $FF,EYES_L,$FF,$FF,$FF,$FF,$FF
MarcusR:    .byte $FF,EYES_R,$FF,$FF,$FF,$FF,$FF
MarcusLS:   .byte $FF,EYES_LSQ,$FF,$FF,$FF,$FF,$FF
MarcusRS:   .byte $FF,EYES_RSQ,$FF,$FF,$FF,$FF,$FF
MarcusB:    .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF
FlickL:     .byte FLICK_RIM,FLICK_L,FLICK_BODY,FLICK_RIM,0
FlickR:     .byte FLICK_RIM,FLICK_R,FLICK_BODY,FLICK_RIM,0
FlickLS:    .byte FLICK_RIM,FLICK_LSQ,FLICK_BODY,FLICK_RIM,0
FlickRS:    .byte FLICK_RIM,FLICK_RSQ,FLICK_BODY,FLICK_RIM,0
FlickB:     .byte FLICK_RIM,FLICK_BODY,FLICK_BODY,FLICK_RIM,0
GfxEnd:
        IF >GfxEnd != >GfxPage
          ECHO "the pictures cross a page"
          ERR
        ENDIF

GfxLoTbl:   .byte <StellaL,<StellaR,<StellaLS,<StellaRS,<StellaB
            .byte <AlexL,<AlexR,<AlexLS,<AlexRS,<AlexB
            .byte <MarcusL,<MarcusR,<MarcusLS,<MarcusRS,<MarcusB
            .byte <FlickL,<FlickR,<FlickLS,<FlickRS,<FlickB

Bank0End:
        ECHO "bank 0:", ($FFF6 - Bank0End), "bytes free"

        ORG $0FF6
        RORG $FFF6
        .byte 0, 0, 0, 0        ; the hotspots: never code, never data
        .word 0
        .word ColdStart         ; RESET
        .word ColdStart         ; IRQ/BRK

; ===============================================================
; BANKS 1-3: empty but for the reset stub and the vectors
; ===============================================================

        MAC EMPTYBANK
        SEG BANK{1}
        ORG {1}*$1000
        RORG $F000
        ds 256, 0               ; the Superchip's window, as bank 0
        sei                     ; ColdStart's bytes, at its address
        cld
        lda BANK0HOT
        jmp Bank0Init
        ORG {1}*$1000+$0FF6
        RORG $FFF6
        .byte 0, 0, 0, 0
        .word 0
        .word ColdStart
        .word ColdStart
        ENDM

        EMPTYBANK 1
        EMPTYBANK 2
        EMPTYBANK 3
