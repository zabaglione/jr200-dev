; SPDX-License-Identifier: BSD-3-Clause
        .filename.jr "JR200-SOUND"
        .include "../../../sdk/jr200.inc"

SAMPLE_STATUS:          .equ    0x1200

        .org    0x1000
start:
        CLRA
        JSR     jr_sound_c_start
        BCC     sound_failed
        LDAA    213
        JSR     jr_sound_c_start
        BCS     sound_failed
        LDX     4000
        JSR     jr_wait_x
        JSR     jr_sound_c_stop
        LDAA    1
        STAA    [SAMPLE_STATUS]
        RTS
sound_failed:
        JSR     jr_sound_all_stop
        CLRA
        STAA    [SAMPLE_STATUS]
        RTS

        .include "../../../sdk/sound.inc"
        .include "../../../sdk/timing.inc"
