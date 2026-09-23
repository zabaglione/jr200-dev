; SPDX-License-Identifier: BSD-3-Clause
        .filename.jr "JR200-JOYSTICK"
        .include "../../../sdk/jr200.inc"

SAMPLE_RAW_1P:         .equ    0x1400
SAMPLE_RAW_2P:         .equ    0x1401
SAMPLE_PRESSED_1P:     .equ    0x1402
SAMPLE_PRESSED_2P:     .equ    0x1403
SAMPLE_STATUS:         .equ    0x1404

SAMPLE_TITLE_CELL:     .equ    0xc128
SAMPLE_HEADER_CELL:    .equ    0xc164
SAMPLE_1P_CELL:        .equ    0xc180
SAMPLE_2P_CELL:        .equ    0xc1c0
SAMPLE_FOOTER_CELL:    .equ    0xc386
SAMPLE_1P_MARKER:      .equ    0xc184
SAMPLE_2P_MARKER:      .equ    0xc1c4
SAMPLE_1P_ATTRIBUTE:   .equ    0xc580
SAMPLE_2P_ATTRIBUTE:   .equ    0xc5c0

SAMPLE_ATTR_CYAN:      .equ    0x05
SAMPLE_ATTR_YELLOW:    .equ    0x06
SAMPLE_LINE_LENGTH:    .equ    20
SAMPLE_RETURN_KEY:     .equ    0x0d

        .org    0x1000
start:
        JMP     sample_initialize
sample_done:
        RTS

sample_initialize:
        CLRA
        STAA    [SAMPLE_STATUS]
        JSR     jr_screen_clear

        LDX     sample_title
        STX     [sample_text_source]
        LDX     SAMPLE_TITLE_CELL
        STX     [sample_text_destination]
        JSR     sample_copy_text

        LDX     sample_header
        STX     [sample_text_source]
        LDX     SAMPLE_HEADER_CELL
        STX     [sample_text_destination]
        JSR     sample_copy_text

        LDX     sample_1p_text
        STX     [sample_text_source]
        LDX     SAMPLE_1P_CELL
        STX     [sample_text_destination]
        JSR     sample_copy_text

        LDX     sample_2p_text
        STX     [sample_text_source]
        LDX     SAMPLE_2P_CELL
        STX     [sample_text_destination]
        JSR     sample_copy_text

        LDX     sample_footer
        STX     [sample_text_source]
        LDX     SAMPLE_FOOTER_CELL
        STX     [sample_text_destination]
        JSR     sample_copy_text

        LDX     SAMPLE_1P_ATTRIBUTE
        LDAA    SAMPLE_ATTR_CYAN
        LDAB    SAMPLE_LINE_LENGTH
        JSR     sample_fill_attributes
        LDX     SAMPLE_2P_ATTRIBUTE
        LDAA    SAMPLE_ATTR_YELLOW
        LDAB    SAMPLE_LINE_LENGTH
        JSR     sample_fill_attributes

; Ignore the RETURN that launched USR until the ROM reports its release.
sample_wait_return_release:
        JSR     jr_joystick_scan
        LDAA    [JR200_ROM_INPUT_KEY]
        CMPA    SAMPLE_RETURN_KEY
        BEQ     sample_wait_return_release

sample_loop:
        JSR     jr_joystick_scan
        STAA    [SAMPLE_RAW_1P]
        STAB    [SAMPLE_RAW_2P]

        JSR     jr_joystick_pressed
        STAA    [SAMPLE_PRESSED_1P]
        TBA
        JSR     jr_joystick_pressed
        STAA    [SAMPLE_PRESSED_2P]

        LDAA    [SAMPLE_PRESSED_1P]
        LDAB    [SAMPLE_RAW_1P]
        LDX     SAMPLE_1P_MARKER
        JSR     sample_draw_player
        LDAA    [SAMPLE_PRESSED_2P]
        LDAB    [SAMPLE_RAW_2P]
        LDX     SAMPLE_2P_MARKER
        JSR     sample_draw_player

        LDAA    [JR200_ROM_INPUT_KEY]
        CMPA    SAMPLE_RETURN_KEY
        BNE     sample_loop
        LDAA    1
        STAA    [SAMPLE_STATUS]
        JMP     sample_done

; Input: source and destination pointer variables. Copies a zero-terminated string.
sample_copy_text:
        LDX     [sample_text_source]
        LDAA    [X]
        BEQ     sample_copy_text_done
        INX
        STX     [sample_text_source]
        LDX     [sample_text_destination]
        STAA    [X]
        INX
        STX     [sample_text_destination]
        BRA     sample_copy_text
sample_copy_text_done:
        RTS

; Input: X = first attribute, A = attribute value, B = cell count.
sample_fill_attributes:
        STAA    [X]
        INX
        DECB
        BNE     sample_fill_attributes
        RTS

; Input: A = pressed bits, B = raw state, X = first marker cell.
sample_draw_player:
        STAA    [sample_draw_state]
        STAB    [sample_draw_raw]
        STX     [sample_draw_destination]
        LDX     sample_button_labels
        STX     [sample_draw_source]
        LDAB    6
sample_draw_button:
        LDX     [sample_draw_source]
        LDAA    [X]
        INX
        STX     [sample_draw_source]
        PSHA
        LDAA    [sample_draw_state]
        LSRA
        STAA    [sample_draw_state]
        BCC     sample_draw_button_off
        PULA
        BRA     sample_draw_button_store
sample_draw_button_off:
        PULA
        LDAA    0x2e
sample_draw_button_store:
        LDX     [sample_draw_destination]
        STAA    [X]
        INX
        INX
        STX     [sample_draw_destination]
        DECB
        BNE     sample_draw_button
        INX
        INX
        LDAA    [sample_draw_raw]
        JSR     sample_draw_hex
        RTS

; Input: A = byte, X = two output cells.
sample_draw_hex:
        PSHA
        LSRA
        LSRA
        LSRA
        LSRA
        JSR     sample_draw_nibble
        PULA
        ANDA    0x0f
        JSR     sample_draw_nibble
        RTS

sample_draw_nibble:
        CMPA    10
        BCS     sample_draw_digit
        ADDA    0x37
        BRA     sample_draw_nibble_store
sample_draw_digit:
        ADDA    0x30
sample_draw_nibble_store:
        STAA    [X]
        INX
        RTS

sample_title:
        .db     "JOYSTICK SAMPLE", 0
sample_header:
        .db     "U D L R A B   RAW", 0
sample_1p_text:
        .db     "1P: . . . . . .   FF", 0
sample_2p_text:
        .db     "2P: . . . . . .   FF", 0
sample_footer:
        .db     "PRESS RETURN TO EXIT", 0
sample_button_labels:
        .db     "UDLRAB"

sample_text_source:
        .dw     0
sample_text_destination:
        .dw     0
sample_draw_source:
        .dw     0
sample_draw_destination:
        .dw     0
sample_draw_state:
        .db     0
sample_draw_raw:
        .db     0

        .include "../../../sdk/screen.inc"
        .include "../../../sdk/joystick.inc"
