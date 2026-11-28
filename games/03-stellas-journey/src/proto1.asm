; ---------------------------------------------------------------
; Stella's Journey -- prototype 1: the tall room
; Game 3 of 4, Stella's Evolution. Atari 2600, 16K, F6 (4 x 4K banks)
; with the Superchip: 128 bytes more RAM on the cartridge (F6SC)
;
; A test ROM, not the game. It answers the first question in
; DESIGN-KICKOFF.md: can one drawing loop scroll a room taller than
; the screen and draw four characters with the TIA's two sprites?
;
;   * The room is 32 bands, 256 du, two and two-thirds screens. The
;     view is 96 du and moves a du at a time, so the drawing loop
;     starts part of the way into a band.
;   * Four characters: Stella, Alex, Marcus, and Flicker, a small
;     circle that is there only on even frames (decision #29).
;   * P0 is the held character and is drawn on every frame. P1 draws
;     up to three of the others in one frame, moving between them
;     where they are apart vertically. Those that overlap take turns,
;     the one left out longest first.
;   * The view follows the held character. On entry it holds on the
;     homes at the top of the room, then pans down to the cast.
;
; Not in this prototype: carrying, phasing, bodies that block,
; corruption, gates, sound, two players, and the markers at the edge
; of the view for characters out of it.
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
LampW       = SC_W + 0  ; COLUPF for the 13 bands a scrolled view
LampR       = SC_R + 0  ; touches: grey, or a home's lamp. The kernel
                        ; reads it through PFColPtr, an indexed load
                        ; like any other, so cartridge RAM costs it
                        ; nothing
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
LAMP_OFF    = $02

VB_TIM      = 51        ; about 43 lines of vertical blank, 193 drawn,
OS_TIM      = 26        ; about 22 of overscan. Game 2's 49 and 28,
                        ; with two ticks moved to vertical blank, where
                        ; four characters cost more than physics does

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
HomeMask    = CYH       ; a bit per character standing home
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
        lda #<LampR
        sta PFColPtr
        lda #>LampR
        sta PFColPtr+1
        ldx #NUM_CHARS-1
.spawn:
        lda SpawnX,x
        sta CharX,x
        lda SpawnY,x
        sta CharY,x
        lda #1
        sta OnGround,x
        sta CharFace,x
        dex
        bpl .spawn
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
        lda #2
        sta VBLANK
        sta VSYNC
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
        adc #10                 ; 9 - (ViewY mod 8): the first band
        sta BandLine            ; shows 8 - (ViewY mod 8) du
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
        ldx Active
        lda CharX,x
        sta NewX
        lda #$FF
        sta MoveDir
        lda SWCHA
        sta Pad
        and #%01000000          ; left (active low)
        bne .noLeft
        lda #0
        sta MoveDir
        sta CharFace,x
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
        clc
        adc NewX
        sta NewX
.noRight:
        lda MoveDir
        bmi .noMove
        jsr ClampBoxes
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

; WalkSpeed: X = char. A = this frame's step. Marcus and Flicker walk
; 1.5 px a frame: an extra pixel every other frame.
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
        sta CY
        clc
        adc HeightTbl,x
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
        lda ViewY
        lsr
        lsr
        lsr
        sta BandTop
        clc
        adc #<RoomPF0
        sta PF0Ptr
        lda #>RoomPF0
        adc #0
        sta PF0Ptr+1
        lda BandTop
        clc
        adc #<RoomPF1
        sta PF1Ptr
        lda #>RoomPF1
        adc #0
        sta PF1Ptr+1
        lda BandTop
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

; ---- the lamps. A home's band in its owner's colour: steady with its
; owner on it, blinking without, fast for the held character's own.
        ldy #12
        lda #PFA_COLOR
.grey:
        sta LampW,y
        dey
        bpl .grey
        lda #0
        sta HomeMask
        ldx #NUM_CHARS-1
.lamp:
        jsr AtHome
        rol HomeMask
        lda HomeBand,x
        sec
        sbc BandTop
        cmp #13
        bcs .lampNext           ; not in view
        tay
        lda HomeMask
        lsr                     ; this character's bit, just rolled in
        bcs .lit
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
.lampNext:
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

; A = x pixel (0-159), X = object (0 P0, 1 P1)
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
; GameKernel: 96 du, two lines each.
;
; Line 1 of a du keeps the bands: on the line before a band begins it
; fetches the band's sky, playfield and lamp (indexed loads), and on
; the band's first line it stores them, inside horizontal blank.
; Line 2 draws P0 and P1 from their pictures.
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
        beq .swap
        lda BandLine
        cmp #1
        beq .prefetch
        bne .line2
.swap:
        lda KSky
        sta COLUBK              ; @14, inside horizontal blank
        lda KPF0
        sta PF0                 ; @20
        lda KPF1
        sta PF1                 ; @26, before it shows at px 16
        lda KPF2
        sta PF2                 ; @32, before px 32
        lda KCol
        sta COLUPF
        lda #8
        sta BandLine
        bne .line2
.prefetch:
        inc KBand
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

.hop:                           ; (GRP1 is already 0: the du before
        lda Q1Pos               ; a hop is past the tenant's bottom)
        sta HMP1                ; the fine shift: the high nibble (the
        and #$0F                ; TIA ignores the low one)
        tay                     ; the coarse count
        sta WSYNC               ; ---- hop line 1: move P1
.hdly:
        dey
        bne .hdly
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
        ldx #NUM_CHARS-1
.charLoop:
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
.head:
        cpy CYH
        beq .headNext
        jsr HeadTest
        bcs .doLand
.headNext:
        dey
        bpl .head
        lda #0
        sta OnGround,x
        jmp .nextChar
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
        rts

; HeadTest: can falling character X land on character Y's head? Uses
; PrevFeet and NewFeet. Carry set, and TopV = the head, if so. Keeps
; X and Y.
HeadTest:
        SUBROUTINE
        lda CharY,y
        sta TopV
        cmp PrevFeet
        bcc .no
        cmp NewFeet
        beq .hit
        bcs .no
.hit:
        lda CharX,y
        clc
        adc WidthTbl,y
        sta RV
        lda CharX,x
        cmp RV
        bcs .no
        clc
        adc WidthTbl,x
        cmp CharX,y
        bcc .no
        beq .no
        sec
        rts
.no:
        clc
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

        include "room1.inc"

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
