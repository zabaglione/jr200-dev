; SPDX-License-Identifier: BSD-3-Clause
        .filename.jr "DEVKIT"
        .include "minimal.inc"
        .org    0x1000

start:
        LDAA    0x2a
        STAA    [0xc100]
        RTS

        fixture_bytes 0x12,0x34
music:
        .db     m"O3 L4 CDE;"
