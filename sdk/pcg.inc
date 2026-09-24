; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc and session.inc. User patterns are drawn with attribute
; mode 0x40: codes 0x00-0x1F read $C000-$C0FF and codes 0x80-0x9F read
; $C400-$C4FF (fixed emulator rendering; see rules/README.md).
;
; jr_pcg_load
;   Input: X = pattern table, A = first user code (0x00-0x1F or 0x80-0x9F),
;   B = number of 8-byte patterns (1-32, must stay inside one bank).
;   Clobbers A, B and X.

jr_pcg_load:
        STX     [JR_RT_SRC]
        PSHB
        TAB
        LSRA
        LSRA
        LSRA
        LSRA
        LSRA
        ANDB    0x1f
        ASLB
        ASLB
        ASLB
        ADDA    JR200_PCG_BANK0 >> 8
        STAA    [JR_RT_DST]
        STAB    [JR_RT_DST + 1]
        PULB
        CLRA
        ASLB
        ROLA
        ASLB
        ROLA
        ASLB
        ROLA
        STAA    [JR_RT_COUNT]
        STAB    [JR_RT_COUNT + 1]
        JMP     jr_copy
