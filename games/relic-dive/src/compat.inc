; SPDX-License-Identifier: MIT
; M6800 replacements for the MB8861H ADX forms used by the JR-100 source.

ADDX16:
    .macro operand
    STX [ADDX_WORK]
    PSHA
    PSHB
    LDAB [ADDX_WORK + 1]
    LDAA [ADDX_WORK]
    ADDB [operand + 1]
    ADCA [operand]
    STAB [ADDX_WORK + 1]
    STAA [ADDX_WORK]
    PULB
    PULA
    LDX [ADDX_WORK]
    .end

ADDX8:
    .macro value
    STX [ADDX_WORK]
    PSHA
    PSHB
    LDAB [ADDX_WORK + 1]
    LDAA [ADDX_WORK]
    ADDB value
    ADCA 0
    STAB [ADDX_WORK + 1]
    STAA [ADDX_WORK]
    PULB
    PULA
    LDX [ADDX_WORK]
    .end
