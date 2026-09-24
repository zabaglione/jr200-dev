; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc.
; These routines read the current key-data latch. They do not start the
; key + joystick ROM scan, acknowledge interrupts, change the IRQ mask, or
; consume a BASIC input buffer. Use joystick.inc for joystick ports.
;
; jr_key_read
;   Output: A = current key-data latch. Preserves B and X.
;
; jr_key_wait
;   Input: A = expected latch value, X = polling limit.
;   Output: A = 1 when matched, A = 0 on timeout.
;   Clobbers B and X. Preserves S.

jr_key_read:
        LDAA    [JR200_KEY_DATA]
        RTS

jr_key_wait:
        TAB
        CPX     0
        BEQ     jr_key_wait_timeout
jr_key_wait_loop:
        LDAA    [JR200_KEY_DATA]
        CBA
        BEQ     jr_key_wait_found
        DEX
        BNE     jr_key_wait_loop
jr_key_wait_timeout:
        CLRA
        RTS
jr_key_wait_found:
        LDAA    1
        RTS
