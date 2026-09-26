; SPDX-License-Identifier: BSD-3-Clause
; Three-voice chord sample for sdk/audio.inc: a looping C major pattern on
; channels F, D and C; a channel-C effect interrupts the C voice at frame 100.
        .filename.jr "JR200-CHORD"
        .include "../../../sdk/jr200.inc"

JR_AUDIO:           .equ    0x1400
CHORD_SNAPSHOT:     .equ    0x1420      ; JR_AUDIO copied at frame 100
CHORD_FRAMES:       .equ    0x1440
CHORD_STATUS:       .equ    0x1441

        .org    0x1000
start:
        JSR     jr_audio_init
        CLR     [CHORD_FRAMES]
        CLR     [CHORD_STATUS]
        LDX     chord_song
        JSR     jr_music_play
chord_loop:
        JSR     jr_frame_wait
        JSR     jr_sfx_tick
        INC     [CHORD_FRAMES]
        LDAA    [CHORD_FRAMES]
        CMPA    100
        BNE     chord_check_end
        LDX     JR_AUDIO
chord_copy:
        LDAA    [X]
        STAA    [X + 0x20]
        INX
        CPX     JR_AUDIO + JR_AUDIO_SIZE
        BNE     chord_copy
        LDX     chord_beep
        JSR     jr_sfx_play
        BRA     chord_loop
chord_check_end:
        CMPA    200
        BNE     chord_loop
        JSR     jr_music_stop
        LDAA    1
        STAA    [CHORD_STATUS]
        RTS

chord_song:
        .db     1
        .dw     chord_melody, chord_harmony, chord_bass
chord_melody:
        .db     AU_C5, 15, AU_E5, 15, AU_G5, 15, AU_C6, 15, 0, 0
chord_harmony:
        .db     AU_E4, 30, AU_G4, 30, 0, 0
chord_bass:
        .db     AU_C3, 60, 0, 0
chord_beep:
        .db     120, 10, 90, 10, 0, 0

        .include "../../../sdk/frame.inc"
        .include "../../../sdk/audio.inc"
        .include "../../../sdk/audio_notes.inc"
