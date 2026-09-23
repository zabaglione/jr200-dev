; SPDX-License-Identifier: BSD-3-Clause
; Requires jr200.inc and the initialized JR-200 BASIC ROM/FONT environment.
; The ROM scan entry updates the direct-page input bytes used by JR-200 BASIC.
;
; jr_joystick_scan
;   Output: A = player 1 active-low state, B = player 2 active-low state.
;   Clobbers X and condition codes through the ROM routine. Preserves S.
;
; jr_joystick_pressed
;   Input: A = active-low joystick state.
;   Output: A = pressed bits, limited to directions and buttons A/B.
;   Preserves B, X, and S.

JR200_ROM_INPUT_SCAN:       .equ    0xe8cb
JR200_ROM_INPUT_KEY:        .equ    0x0001
JR200_ROM_INPUT_JOYSTICK1:  .equ    0x0002
JR200_ROM_INPUT_JOYSTICK2:  .equ    0x0003

JR200_JOYSTICK_UP:          .equ    0x01
JR200_JOYSTICK_DOWN:        .equ    0x02
JR200_JOYSTICK_LEFT:        .equ    0x04
JR200_JOYSTICK_RIGHT:       .equ    0x08
JR200_JOYSTICK_BUTTON_A:    .equ    0x10
JR200_JOYSTICK_BUTTON_B:    .equ    0x20
JR200_JOYSTICK_ALL:         .equ    0x3f
JR200_JOYSTICK_NEUTRAL:     .equ    0xff

jr_joystick_scan:
        JSR     JR200_ROM_INPUT_SCAN
        LDAA    [JR200_ROM_INPUT_JOYSTICK2]
        TAB
        LDAA    [JR200_ROM_INPUT_JOYSTICK1]
        RTS

jr_joystick_pressed:
        COMA
        ANDA    JR200_JOYSTICK_ALL
        RTS
