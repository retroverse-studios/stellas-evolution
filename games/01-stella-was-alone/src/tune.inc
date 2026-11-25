; ---------------------------------------------------------------
; The tune, channel 1 (decision #16, amended 2026-11-25): the lament.
;
; One byte per step. 0-31 is a TIA pitch for a pure tone (AUDC 12):
; the HIGHER the number, the LOWER the note. $80 is a rest. Every
; step is struck, so a note written twice is played twice. The engine
; counts steps in TuneStep; the 8-bit frame counter alone can only
; count to seven steps, which was all the old four-note drone needed.
;
;   TEMPO  shifts right on the frame counter that make one step:
;          5 = a step every 32 frames, 4 = every 16
;   STRIKE frames at the start of a step that a note is loud (5, then 2)
;   HURRY  1 = the tempo doubles while the clock is low (the signal the
;          old drone gave: when the music runs, run with it), 0 = never
;
; `make preview` renders it to build/tune-previews/, at tempo and as it
; plays while the clock is low.
;
; CHOSEN 2026-11-25, by ear, from three drafts (the other two, and the
; old drone to A/B against, are in the history of commit c3aa78a). It
; was drafted slow (TEMPO 5) and heard both ways; the quicker one won,
; so it is written TEMPO 4 with the two-frame strike that doubling
; gave it. HURRY still doubles it from there.
;
; C minor. Each note is struck twice, then a breath. One long sigh:
; up a minor third, up a major third, then down step by step for two
; phrases, ending on the lowest note the chip can play. Two thirds of
; the 8.5-second loop is silence.
;
;        C5 C5  .  Eb5 Eb5 .  G5 G5
;        Bb5 Bb5 . Ab5 Ab5 . G5 G5
;        F5 F5  .  Eb5 Eb5 .  C5 C5
;         .   .  .  Bb4 Bb4 Bb4  .   .   .
;
; What the numbers are, on NTSC (clock 30.1 kHz):
;   31 Bb4  30 B4  28 C5  26 C#5  25 D5  23 Eb5  22 E5  20/21 F5
;   18 G5   17 Ab5 16 A5  15 Bb5  14 B5  13 C6  12 D6  11 Eb6  10 F6
; A TIA pure tone cannot play every note in tune. F5 (35-46 cents
; out either way) and C6 (48 cents sharp) are the weak ones, so this
; leans on the notes that land within 30, and on C minor, where the
; thirds come out truest.
; ---------------------------------------------------------------

TEMPO   = 4
STRIKE  = 2
HURRY   = 1

Tune:   .byte 28, 28,$80, 23, 23,$80, 18, 18
        .byte 15, 15,$80, 17, 17,$80, 18, 18
        .byte 20, 20,$80, 23, 23,$80, 28, 28
        .byte $80,$80, 31, 31, 31,$80,$80,$80
