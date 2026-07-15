; ---------------------------------------------------------------
; Stella Was Together — game 2 of 4, Stella's Evolution
; Atari 2600, 8K ROM, F8 bankswitching (2 x 4K banks)
;
; v0.2 "one level, two worlds": the decision-gate prototype for
; docs/decisions.md #9. Every floor now has TWO geometries — world
; A (warm, gradient brightening toward the horizon) and world B
; (cool, gradient running the OPPOSITE way) — and pushing UP inside
; a blinking portal column swaps the world while every character
; position/velocity stays put in RAM: the entire pitch. Three
; Stella-only toggle floors (T1 locked room, T2 wall-here/path-
; there, T3 the mid-air switch) sit after the v0.1-visual Meeting
; Place sandbox; SELECT advances floors, reaching your marker
; advances automatically.
;
; Architecture (the measured choice — see DESIGN-KICKOFF.md): the
; whole engine and the kernel live in bank 0. The kernel draws the
; playfield through pointers, so a toggle floor points PF1/PF2 at a
; 24-byte RAM copy (PFRam) while PF0 — the outer frame + floor, which
; never differs between worlds — stays in ROM. On each switch PFRam
; is refilled: world A's PF1/PF2 art is copied from bank 0, world B's
; lives in bank 1 and is fetched by a jsr (GoCopyB) into CopyBWorker
; there, returning through the byte-identical GoBackBank0 stub. Both
; worlds' collision boxes stay in bank 0 beside the physics; PlatPtr
; is repointed at the current world's set. Nothing else crosses banks
; — bank 1 is data + the copy worker; its old frame loop is now dead
; plumbing kept only to prove the F8 layout. (A per-world FLOOR would
; need a third RAM plane; the 128-byte RAM, shared with the stack,
; has no room, so T3 forces its mid-air switch with per-world
; interior platforms over a shared floor instead — see the report.)
;
; F8 in one breath: the 6507 sees a 4K window at $1000-$1FFF
; (mirrored at $F000-$FFFF, which is how this file addresses it).
; Touching $1FF8 maps bank 0 into the window; touching $1FF9 maps
; bank 1. The swap is instant — the very next opcode fetch comes
; from the other bank — so any code that executes across a switch
; must be byte-identical at the same addresses in both banks.
; Those shared bytes are the trampoline stubs at the top of each
; bank below.
;
; Engine code: MIT (see repository LICENSE).
; Story/characters: CC BY-NC-SA 4.0 (see repository LICENSE-DOCS).
;
; Controls:
;   Left/Right  move active character
;   Fire        jump
;   Up          inside a shimmering portal column: swap worlds on the
;               toggle floors (T1-T3); on the portal floors (P1, WP1)
;               instead TELEPORT to the linked column's mouth (same
;               world). WP1 also has W1's open, wrapping left/right edges
;   Down+Fire   cycle Stella -> Alex -> Marcus (the three-character
;               floors: the Meeting Place and Act 1 Floor 1; the
;               Stella-only toggle floors make it a no-op)
;   SELECT      advance to the next floor (prototype UI). The active
;               (player-controlled) character always draws on P0 (solid,
;               never flickers); the two idle characters share P1.
;   SELECT count from boot: 7 presses reaches Act 1 Floor 1
;   RESET       cold start
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

COL_BANK0   = $42       ; Stella red — bank 0's calling card
COL_BANK1   = $84       ; Marcus blue — bank 1's calling card
COL_PF      = $0E       ; bank 1's placeholder platforms

SKY_LINES   = 176       ; bank 1's placeholder kernel shape
FLOOR_LINES = 16

; --- decision-gate (#9) toggle-floor constants -------------------
NUM_FLOORS  = 8         ; 0 = Meeting Place; 1-3 = toggle floors T1-T3;
                        ; 4 = W1, the screen-wrap prototype floor;
                        ; 5 = P1, the in-screen portal (teleport) floor;
                        ; 6 = WP1, wrap AND portal composed on one floor;
                        ; 7 = Act 1 Floor 1 "Together Again" (FLOOR1_IDX):
                        ;     the first REAL floor — three characters,
                        ;     three per-colour homes, one cooperative beat
FLOOR1_IDX  = 7         ; Act 1 Floor 1 "Together Again": the first REAL
                        ; floor — three characters, per-colour homes,
                        ; appended after the six prototype floors.
FLOOR1_SKY  = $62       ; Act 1 dusk violet (blue stays Marcus's alone)
PORTAL_BIT  = $08       ; PF1 bit 3: the blinking portal column
PORTAL_CLR  = $F7       ; ~PORTAL_BIT, to knock the portal bit out
SKYA_BASE   = $34       ; world A warm sky base (brightens DOWNward,
                        ; toward the horizon)
SKYB_BASE   = $94       ; world B cool sky base (brightens UPward —
                        ; the opposite-gradient which-world tell)
PFA_COLOR   = $2C       ; world A warm tan platforms
PFB_COLOR   = $A8       ; world B cool blue-grey platforms
GOAL_COL    = $46       ; Stella's red: her own-color goal marker

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

; --- wrap-floor (W1) constants ----------------------------------
; On the wrap floor x is taken modulo the 160px screen instead of
; being clamped. Steps are 1px, so NewX only ever lands just past an
; edge: NewX >= WRAP_HI is a byte-underflow off the LEFT edge (-k, as
; 256-k) -> add 160 to get 160-k; WRAP_W..WRAP_HI-1 overflowed off the
; RIGHT edge -> subtract 160; below WRAP_W is in-range and untouched.
WRAP_W      = 160
WRAP_HI     = 200

; Level record layout (66 bytes each):
;   +0  12 bytes PF0 per band     +36  6 bytes box top (du)
;   +12 12 bytes PF1 per band     +42  6 bytes box bottom (du)
;   +24 12 bytes PF2 per band     +48  6 bytes box left x
;                                 +54  6 bytes box right x (excl)
;   +60 SX,SY, AX,AY, MX,MY       (three spawn points)
; A box with top==bottom is one-way; top=$FF is an unused pad
; entry. Same shape as game 1's record minus goals (v0.1 has none
; yet) plus Marcus's spawn.

; ---------------------------------------------------------------
; RAM ($80-$FF). Both banks share the one 128-byte RAM — that is
; the whole trick: RAM is the only thing that survives a switch.
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
CurBank     ds 1        ; which world is on screen (0 or 1)
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

; --- physics / logic scratch ------------------------------------
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

; --- decision-gate toggle-floor state ---------------------------
; PFRam is the whole trick: the kernel draws the two mutable
; playfield planes from RAM. PF0 (outer frame + floor) is world-
; invariant and stays in ROM; only PF1 (which carries the blinking
; portal column) and PF2 (which carries the interior geometry that
; differs between worlds) live here — 24 bytes, the header's plan.
PFRam       ds 24       ; PF1Ram[12] then PF2Ram[12] (PF2Ram=PFRam+12)
FloorIdx    ds 1        ; 0 = Meeting Place; >=1 = a toggle floor
UpPrev      ds 1        ; edge latch for the UP switch verb
SelectPrev  ds 1        ; edge latch for SELECT (advance floor)
ActiveM1    ds 1        ; physics loop bound: 2 on floor 0, 0 elsewhere
PFColor     ds 1        ; COLUPF for the current floor+world
SrcPtr      ds 2        ; scratch pointer for the world-art copy
WrapMode    ds 1        ; per-floor edge mode: 0 = clamp, 1 = screen-wrap
; --- active->P0 slot: the kernel draws P0 from these, filled each
; vblank from whichever character is ACTIVE. So the player-controlled
; character is always the solid, never-flickering P0; the two inactive
; characters time-share P1 (they flicker only when they overlap each
; other). On the Stella-only prototype floors Active=0=Stella, so P0
; stays Stella exactly as before.
P0Top       ds 1
P0Hgt       ds 1
P0Eye       ds 1
; --- per-band platform color (COLUPF). The kernel steps COLUPF per
; band from a 12-byte ROM table via this pointer (parallel to how it
; steps COLUBK from SkyGrad) — so a floor can tint individual bands.
; Floor 1 points it at a table that paints each character's home ledge
; its own colour (repointed each frame between a bright/dim pair to
; make the homes pulse); every other floor points it at a uniform
; 12x PFColor table, so nothing changes visually there.
PFColPtr    ds 2

; ===============================================================
; BANK 0 — file $0000-$0FFF, mapped at $F000-$FFFF
; ===============================================================

        SEG BANK0
        ORG $0000
        RORG $F000

; ---------------------------------------------------------------
; F8 trampoline stubs. MUST be byte-identical at the same
; addresses in both banks: execution crosses banks inside these
; routines — the hotspot access swaps ROM mid-stream, and the
; next opcode fetch comes from the other bank's copy. Bank 1
; carries an unlabeled duplicate; a length check below it catches
; drift at assembly time (keep the *contents* in sync by hand).
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
        sta UpPrev
        sta SelectPrev
        lda #0
        sta FloorIdx    ; boot into floor 0 (the Meeting Place demo)
        jsr LoadFloor   ; straight into the demo — no title screen

; ---------------------------------------------------------------
; Bank 0 frame loop. Same skeleton as game 1: 3 lines VSYNC,
; ~37 lines vertical blank (logic runs here), 192 visible, ~30
; overscan = 262.
; ---------------------------------------------------------------

Bank0Loop:
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
        lda SWCHB       ; console RESET switch cold-starts
        lsr
        bcs .noReset
        jmp ColdStart
.noReset:
        lda SWCHB       ; SELECT advances floors (prototype UI)
        and #%00000010
        bne .selRel
        bit SelectPrev
        bpl .selDone
        inc FloorIdx
        lda FloorIdx
        cmp #NUM_FLOORS
        bcc .selLoad
        lda #0
        sta FloorIdx
.selLoad:
        lda #0
        sta SelectPrev
        jsr LoadFloor
        jmp .selDone
.selRel:
        lda #$80
        sta SelectPrev
.selDone:

        jsr ReadInput
        jsr ReadSwitch  ; UP inside a portal zone swaps worlds
        jsr UpdatePhysics
        jsr CheckGoal   ; reaching the marker advances the floor
        jsr UpdateSound
        jsr BlinkPortal ; pulse the portal column in PF1Ram
        jsr PrepSprites ; draw params + P1 multiplexer + positioning

Bank0Entry:             ; bank 1 arrives here (via GoBank0)
        lda #0
        sta CurBank
        lda #1
        sta CTRLPF      ; mirrored playfield
        lda PFColor     ; per-floor+world platform color
        sta COLUPF

.waitVB:
        lda INTIM
        bne .waitVB
        sta WSYNC
        sta VBLANK      ; A=0: beam on

        jsr GameKernel

        lda #2          ; overscan
        sta VBLANK
        lda #0
        sta GRP0
        sta GRP1
        lda #35
        sta TIM64T      ; ~30 scanlines
.waitOS:
        lda INTIM
        bne .waitOS
        jmp Bank0Loop

; ---------------------------------------------------------------
; LoadLevel: point the kernel and collision code at the demo
; level record, place the three characters, and build the banded
; sky gradient in RAM from the per-level palette.
; ---------------------------------------------------------------

LoadLevel:
        SUBROUTINE
        lda #<Level1
        sta PF0Ptr
        lda #>Level1
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

        ldy #60                 ; three spawn points
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
        sta NUSIZ0              ; Stella: one 8px copy, always
        sta VDELP0
        sta VDELP1

        ; per-level palette -> the banded sky gradient. Base sky
        ; color from the level table, brightening toward the
        ; horizon in 2-luma steps (5 shades over 12 bands).
        ldx #0                  ; demo = level 0
        lda LvlSkyTbl,x
        sta Temp
        ldx #11
.grad:
        lda GradOfs,x
        clc
        adc Temp
        sta SkyGrad,x
        dex
        bpl .grad
        lda #2                  ; floor 0 runs all three characters
        sta ActiveM1
        lda LvlPFTbl            ; warm tan platforms, as v0.1
        sta PFColor
        lda #<AllPFA            ; uniform per-band COLUPF (no marker tint)
        sta PFColPtr
        lda #>AllPFA
        sta PFColPtr+1
        rts

; ---------------------------------------------------------------
; ReadInput: move the active character (with solid-box blocking),
; fire jumps, down+fire cycles through all three characters.
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
        lda FloorIdx            ; cycling works on the three-character
        beq .doCycle            ; floors (0 and Floor 1); the Stella-only
        cmp #FLOOR1_IDX         ; toggle floors 1-6 make it a no-op
        bne .pressed
.doCycle:
        lda Active              ; the game 1 switch verb, extended:
        clc                     ; Stella -> Alex -> Marcus -> ...
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

; WalkSpeed: X = char. A = this frame's step in pixels. Marcus
; walks 1.5px/frame the cheap way: an extra pixel every other
; frame (SpeedHalfTbl masks FrameCtr's low bit per character).
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
; (Straight port from game 1.)
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
; UpdatePhysics: gravity + vertical motion for all three
; characters; head bonks against solid boxes while rising, swept
; landing on box tops — or on either friend's head — while
; falling. Game 1's two-character code, generalized.
; ---------------------------------------------------------------

UpdatePhysics:
        SUBROUTINE
        ldx ActiveM1            ; 2 = all three (floor 0); 0 = Stella
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
        ; no box caught us — maybe a friend's head did. Each
        ; character has two possible perches now; test both.
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

; HeadTest: can falling character X land on character Y's head
; this frame? Uses PrevFeet/NewFeet from the caller's sweep.
; Returns carry set (and TopV = the head's y) on a hit.
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
        cmp #3
        bcs .switch             ; 3 = chime into A, 4 = chime into B
        lda #4                  ; jump: rising pure tone
        sta AUDC0
        lda #8
        clc
        adc SoundT
        sta AUDF0
        lda #6
        sta AUDV0
        rts
.switch:
        lda #4                  ; pure tone, a short pitch sweep
        sta AUDC0
        lda SoundId
        cmp #4
        beq .toB
        lda #4                  ; into A: pitch rises (AUDF falls) as it
        clc                     ; resolves — 12 down to 4
        adc SoundT
        jmp .swv
.toB:
        lda #10                 ; into B: pitch falls (AUDF rises) — 2 up
        sec                     ; to 10
        sbc SoundT
.swv:
        sta AUDF0
        lda #7
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
; 1. Per character: drawn top/height (squash & stretch) and this
;    frame's eye byte (facing + blink).
; 2. The P1 multiplexer. P0 is Stella's alone. Alex and Marcus
;    share P1:
;      - vertically separated (>= 2 du gap): P1 opens the frame as
;        the upper of the two; at RepoDU (the first du past the
;        upper sprite) the kernel spends one du repositioning P1
;        onto the lower one. All three draw solid at 60Hz.
;      - overlapping (or gap < 2 du, no room to hop): RepoDU=$FF
;        and P1 alternates tenants each frame — 30Hz flicker, only
;        when scanlines actually collide (the design doc's rule).
;    RepoDU is nudged off band boundaries so the hop never eats a
;    playfield update.
; 3. Horizontal positioning for P0 and P1's first tenant.
; ---------------------------------------------------------------

PrepSprites:
        SUBROUTINE
        lda FloorIdx            ; Floor 1: pulse the home ledges by
        cmp #FLOOR1_IDX         ; swapping the per-band COLUPF table
        bne .noPulse            ; between a bright and a dim copy
        lda FrameCtr
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

        lda FloorIdx            ; prototype floors 1-6: P1 is the single
        beq .mux                ; goal marker, not the inactive pair.
        cmp #FLOOR1_IDX         ; floor 0 and Floor 1 (idx 7) run all
        beq .mux                ; three characters -> the P1 multiplexer.
        jsr PrepGoal
        jmp .position

        ; ---- the P1 multiplexer: the two INACTIVE characters ----
.mux:
        ldy Active
        ldx OtherATbl,y         ; the two characters that are NOT active
        lda OtherBTbl,y         ; (OtherA/B already list "the other two")
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

; CharColor: X = char. A = its color, brighter luma when active
; (game 1's convention).
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
;
; Line 1 of each pair: playfield band switch + sky gradient step
; (both start inside hblank). Line 2: GRP0 (Stella) and GRP1
; (P1's current tenant), pattern = solid $FF except the eye row.
;
; The mid-frame P1 hop takes over exactly one du (two scanlines):
;   repo line 1: the divide-by-15 RESP1 hit + HMP1 (the game 1
;     SetHorizPos, inlined so post-WSYNC timing is identical)
;   repo line 2: HMOVE @3, then Stella still draws, and P1's slot
;     variables are swapped to the second tenant
; RepoDU never lands on a band boundary (PrepSprites shifts it),
; so repo line 2's dec keeps the band counter honest and no PF
; update is ever missed.
;
; Cycle notes (worst cases, 76/line):
;   line 1, band boundary: 45 — COLUBK @16 (hblank); PF0 @24, one
;     cycle past the beam but bit 4 (the wall) never changes
;     between bands so nothing shows; PF1 @32 / PF2 @40 are game
;     1's proven boundary timing (level data keeps PF1 bits 7-5
;     and PF2 bits 0-1 quiet across boundaries; the floor line's
;     $FF rows show the same 1-line corner nick game 1 shipped
;     with)
;   line 2, normal: <= 64 (two eye-row draws + loop tail)
;   repo line 1: <= 72 for x <= 148 — THE TIGHTEST LINE HERE
;   repo line 2: <= 69
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
        sta HMOVE               ; @3 — fine shift (costs the usual
                                ; 8px HMOVE bar at the left edge
                                ; of this one scanline)
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

; ---------------------------------------------------------------
; Per-level palette + gradient shape. One level so far, but the
; tables are the 8K contract: sky and platform color per level.
; ---------------------------------------------------------------

LvlSkyTbl:  .byte $62               ; dusk violet at the zenith —
                                    ; blue is Marcus's color, the
                                    ; sky must not compete with him
LvlPFTbl:   .byte $2C               ; warm tan platforms
GradOfs:    .byte 0,0,0,2,2,2,4,4,6,6,8,8  ; brighter toward the
                                    ; horizon: 5 shades, subtle

; ---------------------------------------------------------------
; The demo level: "The Meeting Place". Ground, a center pedestal
; (Marcus starts on it: instant vertical separation), two side
; ledges and a high center platform — heights picked so Stella,
; Marcus and Alex each top out at different tiers, and so Alex
; and Marcus overlap scanlines the moment Marcus hops down.
; ---------------------------------------------------------------

Level1:
        .byte $10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$F0
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$1F,$00,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$F0,$00,$00,$C0,$C0,$FF
        .byte 88, 48, 64, 64,  72, $FF    ; box tops
        .byte 96, 56, 72, 72,  88, $FF    ; box bottoms
        .byte 0,  64, 28, 112, 72, 0      ; box left
        .byte 160,96, 48, 132, 88, 0      ; box right (excl)
        .byte 20, 88-STELLA_H             ; Stella: ground, left
        .byte 40, 88-ALEX_H               ; Alex: ground, mid-left
        .byte 76, 72-MARCUS_H             ; Marcus: on the pedestal

; ===============================================================
; DECISION-GATE (#9) TOGGLE FLOORS — engine + data (bank 0)
;
; A toggle floor is one room with two geometries. PF0 (outer frame
; + floor) is world-invariant and drawn straight from ROM. The two
; mutable planes — PF1 (portal column) and PF2 (interior walls) —
; are drawn from the 24-byte PFRam, refilled on every world switch:
; world A's art is copied here from bank 0, world B's is fetched by
; a jsr into bank 1 (CopyBWorker) through the byte-identical stubs.
; Both worlds' collision boxes live in bank 0 beside the physics;
; PlatPtr is repointed at the current world's set on each switch.
; Character X/Y/velocity never move in RAM across a switch — that
; persistence is the whole mechanic.
; ===============================================================

; ---------------------------------------------------------------
; LoadFloor: dispatch on FloorIdx. 0 = the Meeting Place demo
; (unchanged v0.1 path); >=1 = a Stella-only toggle floor.
; ---------------------------------------------------------------

LoadFloor:
        SUBROUTINE
        ldx FloorIdx
        lda WrapTbl,x           ; per-floor edge mode (0 clamp / 1 wrap)
        sta WrapMode
        lda FloorIdx
        beq .toLevel            ; floor 0: the v0.1 sandbox, intact
        cmp #FLOOR1_IDX
        bne .toToggle
        jmp LoadFloor1          ; floor 7: Act 1 Floor 1 (three chars)
.toToggle:
        jmp LoadToggleFloor     ; floors 1-6: the Stella-only prototypes
.toLevel:
        jmp LoadLevel

; ---------------------------------------------------------------
; LoadToggleFloor: place Stella, point the kernel at PF0 art + the
; PFRam planes, park the unused friends off-screen, then LoadWorld
; fills PFRam / boxes / palette for world A.
; ---------------------------------------------------------------

LoadToggleFloor:
        SUBROUTINE
        ldx FloorIdx
        lda StartXTbl,x
        sta CharX               ; Stella = index 0
        lda StartYTbl,x
        sta CharY
        lda #0
        sta CharYLo
        sta CharVYHi
        sta CharVYLo
        sta SquashT
        sta Active
        sta CurBank             ; every floor opens in world A
        sta SoundId
        sta SoundT
        sta ActiveM1            ; Stella-only physics
        sta NUSIZ0
        sta VDELP0
        sta VDELP1
        lda #1
        sta OnGround
        sta CharFace            ; wake facing right

        lda #200                ; park Alex & Marcus below the world
        sta CharY+1             ; so no head-perch and never drawn
        sta CharY+2
        lda #0
        sta CharX+1
        sta CharX+2
        sta CharVYHi+1
        sta CharVYHi+2
        sta CharVYLo+1
        sta CharVYLo+2
        sta OnGround+1
        sta OnGround+2

        lda PF0ArtLoTbl,x       ; PF0 (frame+floor) from ROM
        sta PF0Ptr
        lda PF0ArtHiTbl,x
        sta PF0Ptr+1
        lda #<PFRam             ; PF1 <- PF1Ram, PF2 <- PF2Ram
        sta PF1Ptr
        lda #>PFRam
        sta PF1Ptr+1
        lda #<(PFRam+12)
        sta PF2Ptr
        lda #>(PFRam+12)
        sta PF2Ptr+1
        ; fall through to LoadWorld for world A

; ---------------------------------------------------------------
; LoadWorld: for the current FloorIdx + CurBank, repoint PlatPtr at
; that world's collision boxes, refill PFRam from that world's art
; (bank 0 for A, bank 1 for B), and rebuild the palette + gradient.
; ---------------------------------------------------------------

LoadWorld:
        SUBROUTINE
        ldx FloorIdx
        lda CurBank
        bne .boxB
        lda BoxALoTbl,x
        sta PlatPtr
        lda BoxAHiTbl,x
        sta PlatPtr+1
        jsr CopyWorldA
        jmp .pal
.boxB:
        lda BoxBLoTbl,x
        sta PlatPtr
        lda BoxBHiTbl,x
        sta PlatPtr+1
        jsr GoCopyB             ; cross to bank 1, copy, come back
.pal:
        jmp SetPalette

; CopyWorldA: 24 bytes of world A art (PF1[12] then PF2[12]) from
; bank 0 ROM into PFRam.
CopyWorldA:
        SUBROUTINE
        ldx FloorIdx
        lda WAArtLoTbl,x
        sta SrcPtr
        lda WAArtHiTbl,x
        sta SrcPtr+1
        ldy #23
.cw:
        lda (SrcPtr),y
        sta PFRam,y
        dey
        bpl .cw
        rts

; SetPalette: world A warm sky brightening toward the horizon;
; world B cool sky brightening the OTHER way (the which-world tell).
SetPalette:
        SUBROUTINE
        lda CurBank
        bne .worldB
        lda #PFA_COLOR
        sta PFColor
        lda #<AllPFA            ; uniform warm-tan per-band COLUPF
        sta PFColPtr
        lda #>AllPFA
        sta PFColPtr+1
        ldx #11
.aloop:
        lda GradOfs,x
        clc
        adc #SKYA_BASE
        sta SkyGrad,x
        dex
        bpl .aloop
        rts
.worldB:
        lda #PFB_COLOR
        sta PFColor
        lda #<AllPFB            ; uniform cool blue-grey per-band COLUPF
        sta PFColPtr
        lda #>AllPFB
        sta PFColPtr+1
        ldx #11
        ldy #0
.bloop:
        lda GradOfs,y           ; reversed index: bright end up top
        clc
        adc #SKYB_BASE
        sta SkyGrad,x
        iny
        dex
        bpl .bloop
        rts

; ---------------------------------------------------------------
; ReadSwitch: UP (edge) while Stella stands in a portal x-range
; swaps worlds. No ground requirement, so the same verb serves the
; mid-air switch on later floors.
; ---------------------------------------------------------------

ReadSwitch:
        SUBROUTINE
        lda FloorIdx
        beq .done               ; floor 0 has no portals
        cmp #FLOOR1_IDX
        beq .done               ; Floor 1: no portals, no world-swap
        lda SWCHA
        and #%00010000          ; UP (active low)
        bne .release
        bit UpPrev
        bpl .done               ; already handled while held
        jsr InPortal
        bcc .clear
        ldx FloorIdx            ; P1 (portal floor) TELEPORTS in-screen
        lda TeleportTbl,x       ; instead of swapping worlds
        beq .swap
        jsr DoTeleport
        jmp .clear
.swap:
        jsr DoSwitch
.clear:
        lda #0
        sta UpPrev
        rts
.release:
        lda #$80
        sta UpPrev
.done:
        rts

; InPortal: carry set if Stella's left edge is inside EITHER of this
; floor's two portal x-ranges (a floor with one portal parks the
; second range at 255..255, which no position can enter).
InPortal:
        SUBROUTINE
        ldx FloorIdx
        lda CharX
        cmp PortalLTbl,x
        bcc .try2
        cmp PortalRTbl,x
        bcc .yes
.try2:
        lda CharX
        cmp Portal2LTbl,x
        bcc .out
        cmp Portal2RTbl,x
        bcs .out
.yes:
        sec
        rts
.out:
        clc
        rts

; DoSwitch: flip the world flag, sound the switch chime (rising into
; world A, falling into world B), then LoadWorld does the rest.
DoSwitch:
        SUBROUTINE
        lda CurBank
        eor #1
        sta CurBank
        clc
        adc #3                  ; CurBank 0 -> SoundId 3 (A), 1 -> 4 (B)
        sta SoundId
        lda #8
        sta SoundT
        jmp LoadWorld

; ---------------------------------------------------------------
; DoTeleport: the in-screen PORTAL verb (floor P1). Stella is inside
; one of this floor's two linked portal columns; UP teleports her x,y
; to the OTHER portal's mouth. Unlike DoSwitch this is a pure position
; move: SAME world, SAME palette, SAME collision set, NO F8 bank
; switch (a portal needs only one bank — it never touches BANK1HOT).
; She arrives standing, velocity zeroed, with a short settle-squash and
; the switch chime, so the landing reads as a deliberate grounding.
; ---------------------------------------------------------------

DoTeleport:
        SUBROUTINE
        ldx FloorIdx
        lda CharX               ; which mouth is she standing in?
        cmp PortalLTbl,x        ; portal A range = [PortalL, PortalR)
        bcc .useB               ; below A -> she must be in portal B
        cmp PortalRTbl,x
        bcs .useB               ; at/above A's right edge -> portal B
        lda MouthBXTbl,x        ; in A: come out at B's mouth
        sta CharX
        lda MouthBYTbl,x
        sta CharY
        jmp .settle
.useB:
        lda MouthAXTbl,x        ; in B: come out at A's mouth
        sta CharX
        lda MouthAYTbl,x
        sta CharY
.settle:
        lda #0                  ; land clean at the destination mouth
        sta CharYLo
        sta CharVYHi
        sta CharVYLo
        lda #1
        sta OnGround            ; grounded on arrival (physics re-seats
                                ; her on the mouth's platform this frame)
        lda #3
        sta SquashT             ; a few frames of settle-squash
        lda #3                  ; reuse the switch chime as a portal blip
        sta SoundId
        lda #8
        sta SoundT
        rts

; ---------------------------------------------------------------
; CheckGoal: has Stella overlapped this floor's marker? If so,
; advance to the next floor (wraps at NUM_FLOORS).
; ---------------------------------------------------------------

CheckGoal:
        SUBROUTINE
        lda FloorIdx
        beq .done
        cmp #FLOOR1_IDX
        bne .notF1
        jmp CheckGoal3          ; Floor 1: all three on their own homes
.notF1:
        lda OnGround            ; the marker only counts when Stella is
        beq .done               ; STANDING on it — never mid-jump
        ldx FloorIdx
        lda GoalXTbl,x          ; x overlap: CharX < GoalX+8 ...
        clc
        adc #8
        sta Temp
        lda CharX
        cmp Temp
        bcs .done
        lda CharX               ; ... and CharX+8 > GoalX
        clc
        adc #8
        sta Temp
        lda GoalXTbl,x
        cmp Temp
        bcs .done
        lda GoalYTbl,x          ; y overlap: CharY < GoalY+GoalH ...
        clc
        adc GoalHTbl,x
        sta Temp
        lda CharY
        cmp Temp
        bcs .done
        lda CharY               ; ... and CharY+STELLA_H > GoalY
        clc
        adc #STELLA_H
        sta Temp
        lda GoalYTbl,x
        cmp Temp
        bcs .done
        inc FloorIdx            ; reached: next floor
        lda FloorIdx
        cmp #NUM_FLOORS
        bcc .adv
        lda #0
        sta FloorIdx
.adv:
        jsr LoadFloor
.done:
        rts

; ---------------------------------------------------------------
; BlinkPortal: pulse this floor's portal bit through the top 11
; bands of its plane (PortalPlaneTbl selects PF1Ram=0 or PF2Ram=12;
; the floor band, base+11, is left solid). One bit, but the mirrored
; playfield draws it as a column on each half of the screen.
; A plain ~0.5 s blink — smaller than the shimmer it replaced, and a
; quiet foreshadow of Flicker (game 3): the portal, too, is only ever
; half-present.
; ---------------------------------------------------------------

BlinkPortal:
        SUBROUTINE
        lda FloorIdx
        beq .done
        cmp #FLOOR1_IDX
        beq .done               ; Floor 1 has no portal column to pulse
        ldy FloorIdx
        lda FrameCtr
        and #%00010000          ; ~0.5 s on, 0.5 s off at 60 Hz
        beq .off
        lda PortalMaskTbl,y
        jmp .have
.off:
        lda #0
.have:
        sta Temp                ; portal bit to OR in this frame
        lda PortalClrTbl,y
        sta CY                  ; the knock-out mask (scratch)
        lda PortalPlaneTbl,y
        clc
        adc #10
        tax                     ; X = PFRam index of the top band
        ldy #11
.loop:
        lda PFRam,x
        and CY                  ; clear the old portal bit, keep walls
        ora Temp
        sta PFRam,x
        dex
        dey
        bne .loop
.done:
        rts

; ---------------------------------------------------------------
; PrepGoal: fill the P1 slot with this floor's static red marker
; (no mid-frame hop; the kernel draws it like any P1 tenant).
; ---------------------------------------------------------------

PrepGoal:
        SUBROUTINE
        lda #$FF
        sta RepoDU              ; no P1 reposition hop this frame
        ldx FloorIdx
        lda GoalYTbl,x
        sta P1Top
        lda GoalHTbl,x
        sta P1Hgt
        lda #$FF
        sta P1Eye               ; solid block: reads as a marker
        lda GoalXTbl,x
        sta P1XA
        lda #0
        sta NUSIZ1              ; one 8px copy — matches the 8px goal
                                ; collision box exactly (no visual lie)
        lda FrameCtr            ; the marker breathes red so it reads
        and #$10                ; as a target, not a static second
        beq .gdim               ; Stella; ~0.5s cycle, never fully off
        lda #$4E                ; bright red at the peak
        bne .gset
.gdim:
        lda #$44                ; deep red at the trough
.gset:
        sta COLUP1
        rts

; ---------------------------------------------------------------
; Toggle-floor data tables (index 0 = the Meeting Place, a dummy
; row; index 1 = T1). Extend per floor for T2/T3.
; ---------------------------------------------------------------

;              floor:  0   T1    T2    T3    W1    P1   WP1
StartXTbl:  .byte      0,  16,   16,   16,   16,   16,   16
StartYTbl:  .byte      0,  79,   79,   79,   79,   79,   79   ; 88 - STELLA_H
GoalXTbl:   .byte      0, 136,  136,   76,  112,   64,  112   ; WP1: on the
GoalYTbl:   .byte      0,  82,   82,   49,   82,   26,   26   ; RIGHT shelf,
GoalHTbl:   .byte      0,   6,    6,    9,    6,    6,    6   ; past the wall
PortalLTbl: .byte      0,  24,   44,   40,  255,   28,   28   ; WP1 portal A
PortalRTbl: .byte      0,  45,   54,   56,  255,   37,   37   ; = left column
Portal2LTbl: .byte   255, 255,  105,  255,  255,  120,  120   ; WP1 portal B
Portal2RTbl: .byte   255, 255,  115,  255,  255,  129,  129   ; = right column
PortalPlaneTbl: .byte  0,   0,   12,    0,    0,    0,    0   ; PF1Ram=0
PortalMaskTbl:  .byte  0, $08,  $01,  $02,  $00,  $08,  $08   ; PF1 bit3 pair
PortalClrTbl:   .byte  0, $F7,  $FE,  $FD,  $FF,  $F7,  $F7   ; (~mask)
WrapTbl:    .byte      0,   0,    0,    0,    1,    0,    1,  1  ; F1: wrap ON

; --- portal-teleport data (floors 5 P1 and 6 WP1 are teleport floors) ----
; TeleportTbl picks the UP verb: 0 = world-swap (T*), 1 = in-screen
; teleport (P1, WP1). MouthA/B are the two linked portal mouths: UP inside
; portal A drops Stella at B's mouth and vice versa. On WP1 each column is
; a vertical lift to its OWN side's shelf half — left col -> left shelf,
; right col -> right shelf — and the central wall splits the shelf, so the
; near (left) lift strands you on the wrong side of the goal.
TeleportTbl: .byte     0,   0,    0,    0,    0,    1,    1
MouthAXTbl:  .byte     0,   0,    0,    0,    0,   32,  124   ; WP1 A: RIGHT
MouthAYTbl:  .byte     0,   0,    0,    0,    0,   79,   23   ; shelf (from B)
MouthBXTbl:  .byte     0,   0,    0,    0,    0,  124,   32   ; WP1 B: LEFT
MouthBYTbl:  .byte     0,   0,    0,    0,    0,   23,   23   ; shelf (from A)

PF0ArtLoTbl: .byte 0, <PF0ArtT1, <PF0ArtT1, <PF0ArtT1, <PF0ArtWrap, <PF0ArtP1, <PF0ArtWP1
PF0ArtHiTbl: .byte 0, >PF0ArtT1, >PF0ArtT1, >PF0ArtT1, >PF0ArtWrap, >PF0ArtP1, >PF0ArtWP1
WAArtLoTbl:  .byte 0, <WAArtT1, <WAArtT2, <WAArtT3, <WAArtWrap, <WAArtP1, <WAArtWP1
WAArtHiTbl:  .byte 0, >WAArtT1, >WAArtT2, >WAArtT3, >WAArtWrap, >WAArtP1, >WAArtWP1
BoxALoTbl:   .byte 0, <T1ABoxes, <T2ABoxes, <T3ABoxes, <WrapBoxes, <P1Boxes, <WP1Boxes
BoxAHiTbl:   .byte 0, >T1ABoxes, >T2ABoxes, >T3ABoxes, >WrapBoxes, >P1Boxes, >WP1Boxes
BoxBLoTbl:   .byte 0, <T1BBoxes, <T2BBoxes, <T3BBoxes, <WrapBoxes, <P1Boxes, <WP1Boxes
BoxBHiTbl:   .byte 0, >T1BBoxes, >T2BBoxes, >T3BBoxes, >WrapBoxes, >P1Boxes, >WP1Boxes

; T1 "the locked room": outer frame (PF0 bit4) + solid floor.
PF0ArtT1:
        .byte $10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$F0

; World A PF1[12] then PF2[12]: PF1 clear (portal blinks in live),
; PF2 bit7 is the central divider that walls the goal off; the
; floor band is solid in both planes.
WAArtT1:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$FF

; T1 collision boxes (SoA: 6 tops, 6 bottoms, 6 lefts, 6 rights).
; World A: ground box + the full-height central divider (px 76-84).
T1ABoxes:
        .byte 88,  0, $FF,$FF,$FF,$FF
        .byte 96, 88, $FF,$FF,$FF,$FF
        .byte  0, 76,   0,  0,  0,  0
        .byte 160,84,   0,  0,  0,  0
; World B: ground box only — the divider is gone, the path opens.
T1BBoxes:
        .byte 88, $FF,$FF,$FF,$FF,$FF
        .byte 96, $FF,$FF,$FF,$FF,$FF
        .byte  0,   0,  0,  0,  0,  0
        .byte 160,  0,  0,  0,  0,  0

; T2 "wall here, path there": a corridor crossed only by alternating
; worlds at two portals. World A walls (PF2 bit2 -> px 56-59 and its
; mirror px 100-103) and world B walls (PF1 bit2 -> px 36-39 & mirror
; px 120-123) interleave, so no single world crosses. The blink lives
; in PF2 bit0 (px 48-51 / 108-111), one column per portal.
WAArtT2:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$FF
T2ABoxes:
        .byte  88,  0,  0, $FF,$FF,$FF
        .byte  96, 88, 88, $FF,$FF,$FF
        .byte   0, 56,100,   0,  0,  0
        .byte 160, 60,104,   0,  0,  0
T2BBoxes:
        .byte  88,  0,  0, $FF,$FF,$FF
        .byte  96, 88, 88, $FF,$FF,$FF
        .byte   0, 36,120,   0,  0,  0
        .byte 160, 40,124,   0,  0,  0

; T3 "the twist": the forced mid-air switch. World A gives Stella a
; left step (PF1 bits2-7 -> px 16-39, bands 8-10) to launch from; only
; world B holds the tall central pillar (PF2 bits2-7 -> px 56-79 &
; mirror, top ~du58) that reaches the goal. The pillar top is too high
; to gain from the floor, so she must jump off the step and flip worlds
; in mid-air over the gap. Blink: PF1 bit1 (px 40-43 / 116-119).
WAArtT3:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$FC,$FC,$FC,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
T3ABoxes:
        .byte  88, 68, 68, $FF,$FF,$FF
        .byte  96, 88, 88, $FF,$FF,$FF
        .byte   0, 16,119,   0,  0,  0
        .byte 160, 40,144,   0,  0,  0
T3BBoxes:
        .byte  88, 58, $FF,$FF,$FF,$FF
        .byte  96, 88, $FF,$FF,$FF,$FF
        .byte   0, 56,   0,  0,  0,  0
        .byte 160,104,   0,  0,  0,  0

; ---------------------------------------------------------------
; W1 "the long way around" — the screen-wrap prototype floor.
;
; One full-height wall stands dead centre. It is PF2 bit7 (px 76-79);
; because the playfield is drawn MIRRORED (CTRLPF reflect), its
; reflection lands flush at px 80-83, so the wall reads as ONE 8px
; pillar straddling the mirror axis — no phantom double, no confusing
; symmetry. Stella starts left of it (x=16); her pulsing red marker
; (reused PrepGoal) sits right of it (x=112). The direct rightward
; path is walled and the wall reaches the ceiling, so it can't be
; jumped; the outer frame is OPEN on this floor (PF0 top bands clear,
; not $10 as the other floors), so she can walk OFF the left edge,
; WRAP to the right edge, and reach the marker from its right — the
; long way around. WrapMode (from WrapTbl) makes the edges modular
; instead of clamped; there is no portal and no world swap (one
; geometry). The solver proves the wrap is genuinely required.
;
; ASYMMETRIC-PF NOTE: a non-mirrored playfield (the wall drawn once,
; not reflection-doubled) would need a per-scanline mid-line rewrite
; of PF0/PF1/PF2 for the right half, at precise beam cycles. The
; shared GameKernel's draw line already runs ~64 of 76 cycles on the
; sprite/eye logic (see the kernel's cycle notes) and updates PF only
; per 8-du band, not per line — asymmetric PF would demand a rewrite
; EVERY scanline interleaved with those draws, which does not fit the
; tuned kernel cleanly. So this floor uses the documented FALLBACK:
; a wall centred ON the mirror axis, which the existing mirrored
; kernel already renders as a single clean pillar. Zero kernel cost.
; ---------------------------------------------------------------

; PF0 (frame+floor): OPEN edges — top 11 bands clear so Stella can
; exit left AND right; floor band $F0 (with PF1/PF2 $FF -> full floor).
PF0ArtWrap:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0

; World A PF1[12] then PF2[12]: PF1 clear; PF2 bit7 is the central
; wall through the top 11 bands; floor band solid in both planes.
WAArtWrap:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$FF

; W1 collision boxes: full-width ground box + the full-height central
; wall (px 76-84, top 0 down to the floor at 88).
WrapBoxes:
        .byte 88,  0, $FF,$FF,$FF,$FF
        .byte 96, 88, $FF,$FF,$FF,$FF
        .byte  0, 76,   0,  0,  0,  0
        .byte 160,84,   0,  0,  0,  0

; ---------------------------------------------------------------
; P1 "the shortcut" — the in-screen PORTAL (teleport) floor.
;
; ONE world, bank 0 only: a portal is a linked PAIR of columns on the
; SAME screen, so no second geometry and no F8 switch are needed (this
; floor never touches BANK1HOT). The two columns are the ONE mirrored
; portal bit (PF1 bit3 = px 32-35 and its reflection px 124-127), drawn
; by the shared BlinkPortal shimmer so the pair reads as visually
; identical and linked. UP inside either column runs DoTeleport, which
; sets Stella's x,y to the OTHER column's mouth — same colors, same
; world, the legible opposite of the world-swap's full-screen change.
;
; Load-bearing layout (mirror-clean, no phantoms — the shelf is drawn
; FULL WIDTH, so its reflection completes it instead of doubling it):
;   - a full-width high SHELF on band 4 (collision top 32) holds the
;     pulsing red goal (reused PrepGoal marker). It floats: no stairs,
;     and at ~22 du Stella's jump apex (head to y~57) never reaches the
;     shelf underside (y 40), so it is UNreachable by walking or jumping
;   - portal A sits on the GROUND under the left column; portal B is up
;     inside the right column, its mouth ON the shelf. The ONLY route to
;     the goal is: stand in A, press UP, arrive at B up top, walk to the
;     marker. The solver proves goal-unreachable with the portal off.
; ---------------------------------------------------------------

; PF0 (frame+floor): outer walls (bit4) on the open bands, the shelf
; band 4 filled full ($F0), floor band $F0.
PF0ArtP1:
        .byte $10,$10,$10,$10,$F0,$10,$10,$10,$10,$10,$10,$F0

; World-A PF1[12] then PF2[12]: both clear except band 4 (the shelf,
; full width) and band 11 (the floor). The portal bit blinks into PF1
; live via BlinkPortal across bands 0-10, drawing the two columns.
WAArtP1:
        .byte $00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$FF

; P1 collision boxes: full-width ground (top 88) + the floating full-
; width shelf (top 32, bottom 40). No world-B variant — single world,
; so BoxB points here too.
P1Boxes:
        .byte 88, 32, $FF,$FF,$FF,$FF
        .byte 96, 40, $FF,$FF,$FF,$FF
        .byte  0,  0,   0,  0,  0,  0
        .byte 160,160,  0,  0,  0,  0

; ---------------------------------------------------------------
; WP1 "both at once" — wrap AND portal composed on ONE floor.
;
; This is the first taste of Game 2's layering (decisions.md #18):
; wrap is the always-on baseline, the portal layers on top. WP1 fuses
; W1's mechanism and P1's, unchanged, purely through the per-floor data
; tables — WrapTbl[6]=1 (open, modular edges via ReadInput's .wrapEdge)
; AND TeleportTbl[6]=1 (UP runs DoTeleport). Single world, bank 0 only,
; mirrored playfield, Stella-only, pulsing red goal.
;
; The screen (all features mirror-clean — on the axis or full width, so
; every reflection COMPLETES a feature instead of doubling it):
;   - a FULL-HEIGHT central WALL on the mirror axis (PF2 bit7 -> px 76-79,
;     reflected flush to px 80-83 = one 8px pillar). It reaches the ceiling
;     (can't be jumped over) and splits BOTH the ground and the shelf into
;     a left half and a right half. This is W1's wall, verbatim.
;   - a FULL-WIDTH floating SHELF on band 4 (collision top 32) carrying the
;     pulsing goal on its RIGHT half (x 112). It floats at ~22 du above the
;     jump apex, so it is unreachable by walking or jumping — only a portal
;     lift reaches it. This is P1's shelf, verbatim.
;   - OPEN left/right edges (PF0 top bands clear, as W1) so x is modular:
;     walk off one edge, arrive at the other — the ONLY way around the wall.
;   - the ONE mirrored portal bit (PF1 bit3 -> px 32-35 and px 124-127) draws
;     two shimmer columns, one each side of the wall. Each column is a
;     vertical LIFT to its own side's shelf half: left col -> LEFT shelf,
;     right col -> RIGHT shelf (the goal side).
;
; WHY IT NEEDS BOTH (the composition — proved by tools/check_levels.py):
;   Stella starts on the left ground (x 16). The wall blocks the direct
;   walk right; the shelf is too high to jump. The goal sits on the RIGHT
;   shelf, past the wall.
;     * The near (LEFT) column lifts her only to the LEFT shelf — walled
;       off from the goal. A dead climb on its own.
;     * The far (RIGHT) column lifts to the goal side, but it is past the
;       wall: she must WRAP (off the left edge, arrive the right edge) to
;       reach it, THEN teleport up. Wrap gets her around; the portal gets
;       her up. Two composing routes, both needing BOTH verbs:
;         GROUND route: wrap left->right on the ground, ride the right
;                       column up to the goal shelf.
;         SKY route:    ride the left column to the left shelf, then wrap
;                       across the sky (the shelf is full width) to the goal.
;   Neither verb alone finishes: with the edges walled (no wrap) she is
;   trapped in the left half; with no portal she can never leave the ground.
; ---------------------------------------------------------------

; PF0 (frame+floor): OPEN edges (top bands clear -> wrap), the shelf band
; 4 filled full ($F0), the floor band $F0.
PF0ArtWP1:
        .byte $00,$00,$00,$00,$F0,$00,$00,$00,$00,$00,$00,$F0

; World-A PF1[12] then PF2[12]. PF1: shelf band 4 ($FF) + floor ($FF); the
; portal bit blinks into bands 0-10 live via BlinkPortal, drawing the two
; columns. PF2: the full-height central wall (bit7) through bands 0-10,
; the shelf band ($FF) and floor ($FF).
WAArtWP1:
        .byte $00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$FF
        .byte $80,$80,$80,$80,$FF,$80,$80,$80,$80,$80,$80,$FF

; WP1 collision boxes (SoA: 6 tops, 6 bottoms, 6 lefts, 6 rights):
; full-width ground (top 88) + full-width floating shelf (top 32, bot 40)
; + the full-height central wall (px 76-84, top 0 down to the floor 88).
; Single world, so BoxB points here too.
WP1Boxes:
        .byte 88, 32,  0, $FF,$FF,$FF
        .byte 96, 40, 88, $FF,$FF,$FF
        .byte  0,  0, 76,   0,  0,  0
        .byte 160,160,84,   0,  0,  0

; ===============================================================
; ACT 1, FLOOR 1 — "Together Again" (FLOOR1_IDX = 7)
;
; The first REAL floor. All three characters, controllable (Down+Fire
; cycles Stella -> Alex -> Marcus), on a clean mirrored screen with
; wrap ON. Three per-colour HOMES form a central totem: three centred
; 8px one-way ledges (px 76-83, drawn by PF2 bit7 mirrored) stacked at
; three heights, each tinted its owner's colour by the kernel's per-band
; COLUPF (red = Stella top ledge 76, blue = Marcus mid ledge 68, green =
; Alex high ledge 60). The floor completes only when ALL THREE stand on
; their own-colour ledge (CheckGoal3).
;
; The cooperative beat (gentle — one beat): Alex's weak jump (~10 du)
; cannot reach the first ledge (top 76, a 12 du rise) from the ground,
; while Marcus (~15) and Stella (~22) can. So a friend must stand on the
; centre ground as a stepstool; Alex hops onto their head and up onto the
; ledge, then climbs 76 -> 68 -> 60 to his green home. The booster then
; climbs to its own home. tools/check_levels.py proves Alex needs the
; boost (unsolvable solo, solvable with a helper) while Stella and Marcus
; finish alone — a genuine, load-bearing "not alone" beat.
; ===============================================================

; LoadFloor1: place the three characters on the ground, point the kernel
; at the Floor-1 record (PF art + one-way ledges + spawns), run all three
; through physics, and build the Act 1 sky + the pulsing home palette.
LoadFloor1:
        SUBROUTINE
        lda #<Floor1Rec
        sta PF0Ptr
        lda #>Floor1Rec
        sta PF0Ptr+1
        lda PF0Ptr              ; PF1 <- +12, PF2 <- +24, boxes <- +36
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
        sta CurBank
        sta NUSIZ0
        sta VDELP0
        sta VDELP1
        lda #2                  ; all three characters have physics
        sta ActiveM1

        lda #FLOOR1_SKY         ; Act 1 dusk sky -> banded gradient
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

; CheckGoal3: Floor 1 completes only when EACH character is grounded on
; ITS OWN colour ledge. A grounded character's CharY is exactly its
; ledge-top minus its height, and each ledge sits at a unique height, so
; matching CharY to the per-character home value uniquely identifies "on
; its own ledge" (standing on the ground or on a friend's ledge/head all
; give a different CharY). All three match -> advance to the next floor.
CheckGoal3:
        SUBROUTINE
        ldx #NUM_CHARS-1
.loop:
        lda OnGround,x
        beq .done               ; someone airborne: not yet
        lda CharY,x
        cmp Floor1HomeCharY,x
        bne .done               ; someone not on its own home ledge
        dex
        bpl .loop
        inc FloorIdx            ; all three home: next floor (wraps)
        lda FloorIdx
        cmp #NUM_FLOORS
        bcc .adv
        lda #0
        sta FloorIdx
.adv:
        jsr LoadFloor
.done:
        rts

; Per-character CharY when standing on its own home ledge (ledge top
; minus character height): Stella 76-9, Alex 60-3, Marcus 68-6.
Floor1HomeCharY:  .byte 67, 57, 62

; Uniform per-band COLUPF tables (no marker tint) for every other floor:
; world A warm tan, world B cool blue-grey. The kernel steps COLUPF from
; one of these so those floors look exactly as before.
AllPFA:  .byte $2C,$2C,$2C,$2C,$2C,$2C,$2C,$2C,$2C,$2C,$2C,$2C
AllPFB:  .byte $A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8

; Floor 1 per-band COLUPF: platform tan everywhere except the three home
; bands — band 7 = Alex green, band 8 = Marcus blue, band 9 = Stella red.
; PrepSprites swaps between these two copies ~2x/second so the homes pulse.
Floor1PFBri:  .byte $2C,$2C,$2C,$2C,$2C,$2C,$2C,$CC,$8A,$4A,$2C,$2C
Floor1PFDim:  .byte $2C,$2C,$2C,$2C,$2C,$2C,$2C,$C8,$86,$46,$2C,$2C

; The Floor-1 level record (same 66-byte layout as Level1). Open frame
; (wrap), a full-width floor, and three centred one-way home ledges.
;   PF0: open edges (top bands clear so x wraps); floor band = $F0
;   PF1: floor band only ($FF); the outer floor half
;   PF2: home-ledge bit7 on bands 7/8/9 (px 76-83 via the mirror); floor $FF
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
; Bank 0 hotspots + vectors
; ---------------------------------------------------------------

        ORG $0FF8
        RORG $FFF8
        .byte 0, 0              ; $1FF8/$1FF9: the hotspots live
                                ; here — contents never execute
        .word ColdStart         ; NMI (unused on the 2600)
        .word ColdStart         ; RESET
        .word ColdStart         ; IRQ (unused)

; ===============================================================
; BANK 1 — file $1000-$1FFF, also mapped at $F000-$FFFF
; ===============================================================

        SEG BANK1
        ORG $1000
        RORG $F000

; ---------------------------------------------------------------
; F8 trampoline stubs — byte-for-byte copy of the bank 0 stubs
; above. Edit them together or not at all. Unlabeled: the bank 0
; labels (GoBank1/GoBank0/ColdStart) resolve to these same
; addresses, so a jmp from bank 1 code executes this copy.
; ---------------------------------------------------------------

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

; ---------------------------------------------------------------
; Bank 1 frame loop — still the skeleton's placeholder frame in
; Marcus blue. Unreachable from the v0.1 demo (fire is jump now,
; not a bank toggle: decision #9 is still open), but it keeps the
; plumbing proven and the 8192-byte layout honest.
; ---------------------------------------------------------------

Bank1Loop:
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
        lda SWCHB       ; console RESET switch cold-starts
        lsr
        bcs .noReset
        jmp ColdStart   ; runs this bank's stub copy -> bank 0
.noReset:

        lda INPT4       ; fire (edge-triggered) = back to bank 0
        and #$80
        bne .release
        bit FirePrev
        bpl .fireDone
        lda #0
        sta FirePrev
        jmp GoBank0     ; back to the red world
.release:
        lda #$80
        sta FirePrev
.fireDone:

Bank1Entry:             ; bank 0 arrives here (via GoBank1)
        lda #1
        sta CurBank
        lda #COL_BANK1
        sta COLUBK      ; Marcus blue: you are in bank 1
        lda #COL_PF
        sta COLUPF
        lda #1
        sta CTRLPF      ; mirrored playfield

.waitVB:
        lda INTIM
        bne .waitVB
        sta WSYNC
        sta VBLANK      ; A=0: beam on

        jsr Kernel1

        lda #2          ; overscan
        sta VBLANK
        lda #35
        sta TIM64T      ; ~30 scanlines
.waitOS:
        lda INTIM
        bne .waitOS
        jmp Bank1Loop

; ---------------------------------------------------------------
; Bank 1 kernel: 192 scanlines. Same sky-and-floor frame but a
; different pillar layout — the parallel world is the same place,
; arranged differently. That's the whole 8K thesis in one screen.
; ---------------------------------------------------------------

Kernel1:
        SUBROUTINE
        lda #%00010000  ; the same thin outer wall
        sta PF0
        lda #%00011000  ; one wide central pillar per half
        sta PF1
        lda #0
        sta PF2
        ldx #SKY_LINES
.sky:
        sta WSYNC
        dex
        bne .sky
        lda #$FF        ; the floor
        sta PF0
        sta PF1
        sta PF2
        ldx #FLOOR_LINES
.floor:
        sta WSYNC
        dex
        bne .floor
        lda #0
        sta PF0
        sta PF1
        sta PF2
        rts

; ---------------------------------------------------------------
; CopyBWorker: bank 1's half of the world-B fetch. Entered only via
; GoCopyB (bank already switched to 1); copies this floor's 24-byte
; world B art into the shared PFRam, then returns to bank 0 through
; the identical GoBackBank0 stub. FloorIdx, SrcPtr and PFRam are all
; RAM, shared across the switch — bank 1 owns only the art here.
; ---------------------------------------------------------------

CopyBWorker:
        SUBROUTINE
        ldx FloorIdx
        lda WBArtLoTbl,x
        sta SrcPtr
        lda WBArtHiTbl,x
        sta SrcPtr+1
        ldy #23
.cw:
        lda (SrcPtr),y
        sta PFRam,y
        dey
        bpl .cw
        jmp GoBackBank0

WBArtLoTbl: .byte 0, <WBArtT1, <WBArtT2, <WBArtT3, <WBArtWrap, <WBArtP1, <WBArtWP1
WBArtHiTbl: .byte 0, >WBArtT1, >WBArtT2, >WBArtT3, >WBArtWrap, >WBArtP1, >WBArtWP1

; World B PF1[12] then PF2[12] per toggle floor. Floor band solid in
; both planes; the interior is what the switch reveals.
; T1: interior clear (the divider is gone — the path opens).
WBArtT1:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
; T2: the world B walls — PF1 bit2 (px 36-39 and its mirror 120-123).
WBArtT2:
        .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
; T3: the tall central pillar — PF2 bits2-7 (px 56-79 & mirror), the
; only footing that reaches the goal.
WBArtT3:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$00,$00,$00,$00,$00,$00,$FC,$FC,$FC,$FC,$FF
; W1: never fetched (the wrap floor never leaves world A / CurBank 0);
; a copy of its world A so the F8 table stays uniform and any stray
; switch would be harmless.
WBArtWrap:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF
        .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$FF
; P1: never fetched either (the portal floor is single-world, bank 0
; only, and never switches). A copy of its world-A art keeps the F8
; table uniform and any stray switch harmless.
WBArtP1:
        .byte $00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$FF
        .byte $00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$FF
; WP1: never fetched (single world, bank 0, wrap+portal never switch a
; world). A copy of its world-A art keeps the F8 table uniform.
WBArtWP1:
        .byte $00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$FF
        .byte $80,$80,$80,$80,$FF,$80,$80,$80,$80,$80,$80,$FF

; ---------------------------------------------------------------
; Bank 1 hotspots + vectors (identical to bank 0's: whichever
; bank is mapped at power-on, RESET lands on ColdStart and the
; stub forces bank 0)
; ---------------------------------------------------------------

        ORG $1FF8
        RORG $FFF8
        .byte 0, 0              ; $1FF8/$1FF9: the hotspots
        .word ColdStart         ; NMI (unused on the 2600)
        .word ColdStart         ; RESET
        .word ColdStart         ; IRQ (unused)
