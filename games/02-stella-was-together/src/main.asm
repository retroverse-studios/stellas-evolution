; ---------------------------------------------------------------
; Stella Was Together — game 2 of 4, Stella's Evolution
; Atari 2600, 8K ROM, F8 bankswitching (2 x 4K banks)
;
; v0.0: the F8 skeleton. Two banks, each drawing its own stable
; 262-line NTSC frame — bank 0 in Stella red, bank 1 in Marcus
; blue — and the fire button hops between them. Nothing else yet:
; this ROM exists to prove the bankswitch plumbing on real
; hardware before any game moves in.
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
;   Fire        switch banks (watch the world change color)
;   RESET       cold start (back to bank 0)
; ---------------------------------------------------------------

        processor 6502
        include "vcs.h"

; ---------------------------------------------------------------
; Constants
; ---------------------------------------------------------------

BANK0HOT    = $FFF8     ; F8 hotspots ($1FF8/$1FF9 mirrored):
BANK1HOT    = $FFF9     ; reading either one swaps the 4K window

COL_BANK0   = $42       ; Stella red — bank 0's calling card
COL_BANK1   = $84       ; Marcus blue — bank 1's calling card
COL_PF      = $0E       ; platforms: white (as in game 1)

SKY_LINES   = 176       ; kernel: open air above ...
FLOOR_LINES = 16        ; ... a solid floor. 176 + 16 = 192 visible

; ---------------------------------------------------------------
; RAM ($80-$FF). Both banks share the one 128-byte RAM — that is
; the whole trick: RAM is the only thing that survives a switch.
; ---------------------------------------------------------------

        SEG.U VARS
        ORG $80

FirePrev    ds 1        ; last INPT4 bit 7 ($80 = released)
FrameCtr    ds 1
CurBank     ds 1        ; which world is on screen (0 or 1) —
                        ; the kernel doesn't need it, game logic will

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
        ; CurBank = 0 from the RAM clear; first frame starts clean

; ---------------------------------------------------------------
; Bank 0 frame loop. Same skeleton as game 1: 3 lines VSYNC,
; ~37 lines vertical blank (logic runs here), 192 visible, ~30
; overscan = 262. A bank switch happens inside vertical blank:
; bank 1 lands at Bank1Entry with the RIOT timer still running
; and finishes this same frame — no glitch line on the way over.
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

        lda INPT4       ; fire (edge-triggered) = switch banks
        and #$80
        bne .release
        bit FirePrev
        bpl .fireDone   ; still held from last frame
        lda #0
        sta FirePrev
        jmp GoBank1     ; see you on the other side
.release:
        lda #$80
        sta FirePrev
.fireDone:

Bank0Entry:             ; bank 1 arrives here (via GoBank0)
        lda #0
        sta CurBank
        lda #COL_BANK0
        sta COLUBK      ; Stella red: you are in bank 0
        lda #COL_PF
        sta COLUPF
        lda #1
        sta CTRLPF      ; mirrored playfield

.waitVB:
        lda INTIM
        bne .waitVB
        sta WSYNC
        sta VBLANK      ; A=0: beam on

        jsr Kernel0

        lda #2          ; overscan
        sta VBLANK
        lda #35
        sta TIM64T      ; ~30 scanlines
.waitOS:
        lda INTIM
        bne .waitOS
        jmp Bank0Loop

; ---------------------------------------------------------------
; Bank 0 kernel: 192 scanlines. Open sky over a solid floor,
; with a pair of mirrored pillars so the two worlds differ in
; shape as well as color.
; ---------------------------------------------------------------

Kernel0:
        SUBROUTINE
        lda #%00010000  ; a thin outer wall
        sta PF0
        lda #%01000010  ; two pillars per half, mirrored
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
        lda #0          ; blank the playfield before overscan
        sta PF0
        sta PF1
        sta PF2
        rts

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
        sei                     ; ColdStart
        cld
        lda BANK0HOT
        jmp Bank0Init

        IF * - Bank1Top != STUB_SIZE
        ECHO "F8 stubs drifted between banks — fix before flashing!"
        ERR
        ENDIF

; ---------------------------------------------------------------
; Bank 1 frame loop — the same 262-line skeleton as bank 0, in
; Marcus blue. Deliberately duplicated rather than shared: once
; real code moves in, each bank owns its own kernel and the
; trampolines above are the only common ground.
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

        lda INPT4       ; fire (edge-triggered) = switch banks
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
