; SPDX-License-Identifier: BSD-3-Clause
; Busy wait for deterministic CPU-loop timing. This is not a real-time delay API.
;
; jr_wait_x
;   Input: X = loop count. Zero returns immediately.
;   Output: X = 0. Preserves A, B, and S.

jr_wait_x:
        CPX     0
        BEQ     jr_wait_x_done
jr_wait_x_loop:
        DEX
        BNE     jr_wait_x_loop
jr_wait_x_done:
        RTS
