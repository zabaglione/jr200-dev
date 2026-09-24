; SPDX-License-Identifier: BSD-3-Clause
; Busy-wait frame pacing. JR_FRAME_LOOPS iterations of DEX/BNE take 8 cycles
; each; 2790 iterations are about 1/60 s at the fixed emulator's 1,339,285 Hz
; CPU clock. Work done between waits adds to the frame. This is not a
; wall-clock or hardware timing guarantee.
;
; jr_frame_wait
;   Waits one frame. Preserves A and B. Clobbers X.

JR_FRAME_LOOPS:     .equ    2790

jr_frame_wait:
        LDX     JR_FRAME_LOOPS
jr_frame_wait_loop:
        DEX
        BNE     jr_frame_wait_loop
        RTS
