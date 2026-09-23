; SPDX-License-Identifier: BSD-3-Clause
        .filename.jr "JR200-GAMELOOP"
        .include "../../../sdk/jr200.inc"

SAMPLE_STATUS:          .equ    0x1200
SAMPLE_FRAME:           .equ    0x1201
SAMPLE_RETURN_PROOF:    .equ    0x1202
SAMPLE_CELL:            .equ    0xc250

        .org    0x1000
start:
        CLRA
        STAA    [SAMPLE_STATUS]
        STAA    [SAMPLE_FRAME]
        STAA    [SAMPLE_RETURN_PROOF]
        JSR     jr_screen_clear
        LDX     sample_glyph
        LDAA    0x00
        JSR     jr_pcg_define
        BCS     game_loop_done
        LDAA    213
        JSR     jr_sound_c_start
        BCS     game_loop_done

game_loop:
        LDX     256
        JSR     jr_wait_x
        INC     [SAMPLE_FRAME]
        LDAA    [SAMPLE_FRAME]
        ANDA    1
        BEQ     game_loop_blank
        LDAA    0x00
        LDAB    JR200_ATTR_USER_WHITE
        BRA     game_loop_draw
game_loop_blank:
        LDAA    JR200_CHAR_SPACE
        LDAB    JR200_ATTR_STANDARD_WHITE
game_loop_draw:
        LDX     SAMPLE_CELL
        JSR     jr_screen_put
        JSR     jr_key_read
        CMPA    0x71
        BNE     game_loop
        LDAA    1
        STAA    [SAMPLE_STATUS]
game_loop_done:
        JSR     jr_sound_all_stop
        RTS

sample_glyph:
        .db     0x18, 0x3c, 0x7e, 0xdb, 0xff, 0x24, 0x5a, 0xa5

        .include "../../../sdk/screen.inc"
        .include "../../../sdk/input.inc"
        .include "../../../sdk/sound.inc"
        .include "../../../sdk/timing.inc"

        .org    0x1180
return_probe:
        LDAA    0xa5
        STAA    [SAMPLE_RETURN_PROOF]
        RTS
