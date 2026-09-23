; SPDX-License-Identifier: BSD-3-Clause
        .filename.jr "JR200-INPUT"
        .include "../../../sdk/jr200.inc"

SAMPLE_STATUS:          .equ    0x1200

        .org    0x1000
start:
        LDAA    0x61
        LDX     4096
        JSR     jr_key_wait
        STAA    [SAMPLE_STATUS]
        RTS

        .include "../../../sdk/input.inc"
