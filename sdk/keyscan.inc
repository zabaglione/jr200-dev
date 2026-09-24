; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc and session.inc. Held-key state from the keyboard MCU.
; The KTEST/KACK handshake on $C803 asks the MCU for three bytes (current key,
; joystick 1, joystick 2); each arrives as a Key-On event about 100 cycles
; later. This is the transfer the BASIC ROM input scan uses; the edge pattern
; and delay are taken from the fixed emulator (MN1544 model), not measured on
; hardware. Only bits 0 (KACK) and 1 (KTEST) are changed; bit 6 is kept.
;
; jr_keyscan_init
;   Call once after jr_session_enter. On a machine where BASIC has already
;   initialised the MCU this is one ordinary scan. In the ROM-less emulator
;   profile it drains the MCU's start-up font transfer so later scans work.
;   Clobbers A, B and X.
; jr_keyscan
;   Output: A = code of the key held now (0 when none), carry set when the
;   MCU did not answer (A then keeps the previous result). Consumes the
;   Key-On events of the transfer. Clobbers B and X.

JR_RT_SCAN_BASE:    .equ    JR_RT + 45
JR_RT_SCAN_KEY:     .equ    JR_RT + 46
JR200_KEY_TEST:     .equ    0x02
JR200_KEY_ACK:      .equ    0x01
JR_SCAN_WAIT:       .equ    40

jr_keyscan_init:
        LDAA    [JR200_KEY_CONTROL]
        ANDA    0x40
        STAA    [JR_RT_SCAN_BASE]
        CLR     [JR_RT_SCAN_KEY]
        LDAA    [JR200_KEY_IRQ_STATUS]
        JSR     jr_keyscan_test
        JSR     jr_keyscan_answer
        ; Keep acknowledging while the MCU answers (at most one font transfer).
        LDX     2100
jr_keyscan_init_loop:
        STX     [JR_RT_TMP]
        JSR     jr_keyscan_ack
        JSR     jr_keyscan_answer
        BCS     jr_keyscan_init_done
        LDX     [JR_RT_TMP]
        DEX
        BNE     jr_keyscan_init_loop
jr_keyscan_init_done:
        RTS

jr_keyscan:
        JSR     jr_keyscan_test
        JSR     jr_keyscan_answer
        BCS     jr_keyscan_stale
        STAA    [JR_RT_SCAN_KEY]
        JSR     jr_keyscan_ack
        JSR     jr_keyscan_answer
        JSR     jr_keyscan_ack
        JSR     jr_keyscan_answer
        LDAA    [JR_RT_SCAN_KEY]
        CLC
        RTS
jr_keyscan_stale:
        LDAA    [JR_RT_SCAN_KEY]
        SEC
        RTS

; Writes 0, 0, KTEST, 0, KTEST so the MCU sees exactly one KTEST edge.
jr_keyscan_test:
        LDAA    [JR_RT_SCAN_BASE]
        STAA    [JR200_KEY_CONTROL]
        STAA    [JR200_KEY_CONTROL]
        ORAA    JR200_KEY_TEST
        STAA    [JR200_KEY_CONTROL]
        ANDA    0xfd
        STAA    [JR200_KEY_CONTROL]
        ORAA    JR200_KEY_TEST
        STAA    [JR200_KEY_CONTROL]
        RTS

; Writes KACK, 0, KACK for one KACK edge (the KTEST bit stays low).
jr_keyscan_ack:
        LDAA    [JR_RT_SCAN_BASE]
        ORAA    JR200_KEY_ACK
        STAA    [JR200_KEY_CONTROL]
        ANDA    0xfe
        STAA    [JR200_KEY_CONTROL]
        ORAA    JR200_KEY_ACK
        STAA    [JR200_KEY_CONTROL]
        RTS

; Waits for the Key-On event of one transferred byte. A = byte, carry clear;
; carry set on timeout.
jr_keyscan_answer:
        LDAB    JR_SCAN_WAIT
jr_keyscan_answer_wait:
        LDAA    [JR200_KEY_IRQ_STATUS]
        BITA    1
        BNE     jr_keyscan_answer_got
        DECB
        BNE     jr_keyscan_answer_wait
        SEC
        RTS
jr_keyscan_answer_got:
        LDAA    [JR200_KEY_DATA]
        CLC
        RTS
