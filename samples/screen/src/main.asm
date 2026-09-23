; SPDX-License-Identifier: BSD-3-Clause
        .filename.jr "JR200-SCREEN"
        .include "../../../sdk/jr200.inc"

SAMPLE_STATUS:          .equ    0x1200
SAMPLE_CELL:            .equ    0xc250

        .org    0x1000
start:
        LDX     sample_glyph
        LDAA    0x20
        JSR     jr_pcg_define
        BCC     screen_failed
        JSR     jr_screen_clear
        LDX     sample_glyph
        LDAA    0x00
        JSR     jr_pcg_define
        BCS     screen_failed
        LDX     SAMPLE_CELL
        LDAA    0x00
        LDAB    JR200_ATTR_USER_WHITE
        JSR     jr_screen_put
        LDAA    1
        STAA    [SAMPLE_STATUS]
        RTS
screen_failed:
        CLRA
        STAA    [SAMPLE_STATUS]
        RTS

sample_glyph:
        .db     0x18, 0x3c, 0x7e, 0xdb, 0xff, 0x24, 0x5a, 0xa5

        .include "../../../sdk/screen.inc"
