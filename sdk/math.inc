; SPDX-License-Identifier: BSD-3-Clause
; Unsigned 8-bit helpers with M6800 instructions only.
;
; jr_mul8
;   Input: A, B. Output: A = low byte of A*B. Clobbers B. Preserves X.
; jr_divmod8
;   Input: A = dividend, B = divisor (non-zero).
;   Output: A = quotient, B = remainder. Preserves X.
;   Requires session.inc for the work byte.

JR_RT_MATH:         .equ    JR_RT + 26

jr_mul8:
        STAA    [JR_RT_MATH]
        CLRA
jr_mul8_loop:
        TSTB
        BEQ     jr_mul8_done
        ADDA    [JR_RT_MATH]
        DECB
        BRA     jr_mul8_loop
jr_mul8_done:
        RTS

jr_divmod8:
        STAB    [JR_RT_MATH]
        CLRB
jr_divmod8_loop:
        CMPA    [JR_RT_MATH]
        BCS     jr_divmod8_done
        SUBA    [JR_RT_MATH]
        INCB
        BRA     jr_divmod8_loop
jr_divmod8_done:
        PSHB
        TAB
        PULA
        RTS

; jr_add_x_a
;   Input: X, A. Output: X = X + A (unsigned). Preserves B. Clobbers A.
;   Requires session.inc for the work word.

JR_RT_ADDX:         .equ    JR_RT + 30

jr_add_x_a:
        STX     [JR_RT_ADDX]
        ADDA    [JR_RT_ADDX + 1]
        STAA    [JR_RT_ADDX + 1]
        BCC     jr_add_x_a_done
        INC     [JR_RT_ADDX]
jr_add_x_a_done:
        LDX     [JR_RT_ADDX]
        RTS
