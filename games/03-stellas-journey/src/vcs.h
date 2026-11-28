; vcs.h — Atari 2600 (TIA + RIOT) hardware register equates
; Part of Stella's Evolution. MIT licensed (see repository LICENSE).

;----------------------------------------------------------------
; TIA — write registers
;----------------------------------------------------------------
VSYNC   = $00   ; vertical sync set-clear
VBLANK  = $01   ; vertical blank set-clear
WSYNC   = $02   ; wait for leading edge of horizontal blank (strobe)
RSYNC   = $03   ; reset horizontal sync counter (strobe)
NUSIZ0  = $04   ; number-size player-missile 0
NUSIZ1  = $05   ; number-size player-missile 1
COLUP0  = $06   ; color-lum player 0 / missile 0
COLUP1  = $07   ; color-lum player 1 / missile 1
COLUPF  = $08   ; color-lum playfield / ball
COLUBK  = $09   ; color-lum background
CTRLPF  = $0A   ; control playfield, ball size, collisions
REFP0   = $0B   ; reflect player 0
REFP1   = $0C   ; reflect player 1
PF0     = $0D   ; playfield register byte 0 (bits 4-7, leftmost first)
PF1     = $0E   ; playfield register byte 1 (bit 7 leftmost)
PF2     = $0F   ; playfield register byte 2 (bit 0 leftmost)
RESP0   = $10   ; reset player 0 (strobe)
RESP1   = $11   ; reset player 1 (strobe)
RESM0   = $12   ; reset missile 0 (strobe)
RESM1   = $13   ; reset missile 1 (strobe)
RESBL   = $14   ; reset ball (strobe)
AUDC0   = $15   ; audio control 0
AUDC1   = $16   ; audio control 1
AUDF0   = $17   ; audio frequency 0
AUDF1   = $18   ; audio frequency 1
AUDV0   = $19   ; audio volume 0
AUDV1   = $1A   ; audio volume 1
GRP0    = $1B   ; graphics register player 0
GRP1    = $1C   ; graphics register player 1
ENAM0   = $1D   ; enable missile 0
ENAM1   = $1E   ; enable missile 1
ENABL   = $1F   ; enable ball
HMP0    = $20   ; horizontal motion player 0
HMP1    = $21   ; horizontal motion player 1
HMM0    = $22   ; horizontal motion missile 0
HMM1    = $23   ; horizontal motion missile 1
HMBL    = $24   ; horizontal motion ball
VDELP0  = $25   ; vertical delay player 0
VDELP1  = $26   ; vertical delay player 1
VDELBL  = $27   ; vertical delay ball
RESMP0  = $28   ; reset missile 0 to player 0
RESMP1  = $29   ; reset missile 1 to player 1
HMOVE   = $2A   ; apply horizontal motion (strobe)
HMCLR   = $2B   ; clear horizontal motion registers (strobe)
CXCLR   = $2C   ; clear collision latches (strobe)

;----------------------------------------------------------------
; TIA — read registers
;----------------------------------------------------------------
CXM0P   = $30   ; collision M0-P1, M0-P0
CXM1P   = $31   ; collision M1-P0, M1-P1
CXP0FB  = $32   ; collision P0-PF, P0-BL
CXP1FB  = $33   ; collision P1-PF, P1-BL
CXM0FB  = $34   ; collision M0-PF, M0-BL
CXM1FB  = $35   ; collision M1-PF, M1-BL
CXBLPF  = $36   ; collision BL-PF
CXPPMM  = $37   ; collision P0-P1, M0-M1
INPT0   = $38   ; paddle 0 pot port
INPT1   = $39   ; paddle 1 pot port
INPT2   = $3A   ; paddle 2 pot port
INPT3   = $3B   ; paddle 3 pot port
INPT4   = $3C   ; joystick 0 fire button (bit 7, active low)
INPT5   = $3D   ; joystick 1 fire button (bit 7, active low)

;----------------------------------------------------------------
; RIOT (6532) — I/O and timer
;----------------------------------------------------------------
SWCHA   = $0280 ; port A: joysticks (P0 high nibble: R L D U, active low)
SWACNT  = $0281 ; port A data direction
SWCHB   = $0282 ; port B: console switches
SWBCNT  = $0283 ; port B data direction
INTIM   = $0284 ; timer read
TIMINT  = $0285 ; timer interrupt flag
TIM1T   = $0294 ; set timer, /1 clocks
TIM8T   = $0295 ; set timer, /8 clocks
TIM64T  = $0296 ; set timer, /64 clocks
T1024T  = $0297 ; set timer, /1024 clocks
