; ---------------------------------------------------------------
; The tune, channel 1 (decision #16, amended 2026-11-25).
;
; One byte per step. 0-31 is a TIA pitch for a pure tone (AUDC 12):
; the HIGHER the number, the LOWER the note. $80 is a rest. Every
; step is struck, so a note written twice is played twice. The engine
; counts steps in TuneStep; the 8-bit frame counter alone can only
; count to seven steps, which was all the old four-note drone needed.
;
; Three numbers describe how a tune is played:
;   TEMPO  shifts right on the frame counter that make one step:
;          5 = a step every 32 frames, 4 = every 16
;   STRIKE frames at the start of a step that a note is loud (5, then 2)
;   HURRY  1 = the tempo doubles while the clock is low (the signal the
;          old drone gave: when the music runs, run with it), 0 = never
;
; AUDITION SCAFFOLDING - still here, costs nothing in the ROM:
;   TUNE = n here, or `make tunes` for one ROM per tune in build/
;   `make preview` renders each to build/tune-previews/
;   TUNE = 0 is the old four-note drone; 2 and 3 lost to the lament.
;
; CHOSEN 2026-11-25: the lament, at the tempo it had when the clock
; was low. It was drafted slow (TEMPO 5) and heard both ways; the
; quicker one won, so it is written TEMPO 4 with the two-frame strike
; that doubling gave it. HURRY still doubles it from there.
;
; What the numbers are, on NTSC (clock 30.1 kHz):
;   31 Bb4  30 B4  28 C5  26 C#5  25 D5  23 Eb5  22 E5  20/21 F5
;   18 G5   17 Ab5 16 A5  15 Bb5  14 B5  13 C6  12 D6  11 Eb6  10 F6
; A TIA pure tone cannot play every note in tune. F5 (35-46 cents
; out either way) and C6 (48 cents sharp) are the weak ones, so these
; tunes lean on the notes that land within 30, and on C minor and Bb
; major, where the thirds come out truest.
; ---------------------------------------------------------------

        IFNDEF TUNE
TUNE    = 1                     ; which tune is in the ROM (0-3)
        ENDIF

        IF TUNE = 0
TEMPO   = 5                     ; the drone has its own code; these two
STRIKE  = 4                     ; are unused there, but defined
        ENDIF
        IF TUNE = 1
TEMPO   = 4
STRIKE  = 2
        ENDIF
        IF TUNE > 1
TEMPO   = 4
STRIKE  = 4
        ENDIF
HURRY   = 1

; --- 0: the old drone, for A/B -----------------------------------
; A four-note rising figure on a buzzy tone, a little lower each
; level (the engine adds 23 - 2*level), twice as fast under time
; pressure. Not a tune: a hum that climbs.

        IF TUNE = 0
ArpOff: .byte 8,5,3,0
        ENDIF

; --- 1: "LAMENT" - C minor (TEMPO 4: 8.5 s a loop) ---------------
; The loneliest of the drafts, and the one chosen. Each note is
; struck twice, then a breath. One long sigh: up a minor third, up
; a major third, then down step by step for two phrases, ending on
; the lowest note the chip can play. Two thirds of it is silence.
;
;        C5 C5  .  Eb5 Eb5 .  G5 G5
;        Bb5 Bb5 . Ab5 Ab5 . G5 G5
;        F5 F5  .  Eb5 Eb5 .  C5 C5
;         .   .  .  Bb4 Bb4 Bb4  .   .   .

        IF TUNE = 1
Tune:   .byte 28, 28,$80, 23, 23,$80, 18, 18
        .byte 15, 15,$80, 17, 17,$80, 18, 18
        .byte 20, 20,$80, 23, 23,$80, 28, 28
        .byte $80,$80, 31, 31, 31,$80,$80,$80
        ENDIF

; --- 2: "WALK" - C minor pentatonic (TEMPO 4, 8.5 s) -------------
; A note, a rest, a note, a rest: something pacing the room. Same
; key as the lament, so the two could be compared for density alone.
;
;        C5  .  Eb5 .  G5  .  Eb5 .
;        Bb5 .  G5  .  Eb5 .  G5  .
;        Ab5 .  G5  .  F5  .  Eb5 .
;        C5  .   .  .  Bb4 .  C5  .

        IF TUNE = 2
Tune:   .byte 28,$80, 23,$80, 18,$80, 23,$80
        .byte 15,$80, 18,$80, 23,$80, 18,$80
        .byte 17,$80, 18,$80, 20,$80, 23,$80
        .byte 28,$80,$80,$80, 31,$80, 28,$80
        ENDIF

; --- 3: "HOPE" - Bb major, arcing up (TEMPO 4, 8.5 s) ------------
; The only major-key draft, and the highest: it reaches Eb6, a
; ninth above where the others sit. An arch up to D6, then to Eb6,
; then down to where it started.
;
;        F5  .  Bb5 .  D6  .  Bb5 .
;        Eb6 .  D6  .  Bb5 .  G5  .
;        F5  .  G5  .  Bb5 .  D6  .
;        Eb6 Eb6 .   .   D6 .  Bb5 .

        IF TUNE = 3
Tune:   .byte 20,$80, 15,$80, 12,$80, 15,$80
        .byte 11,$80, 12,$80, 15,$80, 18,$80
        .byte 20,$80, 18,$80, 15,$80, 12,$80
        .byte 11, 11,$80,$80, 12,$80, 15,$80
        ENDIF
