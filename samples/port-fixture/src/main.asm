; SPDX-License-Identifier: BSD-3-Clause
; Two-stage 3x3 cross-toggle fixture for the port SDK: session, keys, shadow
; screen, own font, PCG tiles, animation, confirmation, sound and BASIC return.
        .filename.jr "PORT-FIX"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x2000
JR_SAVE:            .equ    0x2600
JR_RT:              .equ    0x3600
GAME_STATE:         .equ    0x3640
GAME_STATE_END:     .equ    0x3680
JR_STACK_TOP:       .equ    0x37ff

GAME_LEVELS:        .equ    2
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    21
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

FX_BOARD:           .equ    GAME_STATE
FX_CURSOR:          .equ    GAME_STATE + 9
FX_MOVES:           .equ    GAME_STATE + 10
FX_FLASH:           .equ    GAME_STATE + 11
FX_INDEX:           .equ    GAME_STATE + 12
FX_POS:             .equ    GAME_STATE + 13
FX_COL:             .equ    GAME_STATE + 14
FX_ROW:             .equ    GAME_STATE + 15

FX_TEXT:            .equ    0x07
FX_OFF:             .equ    0x41
FX_ON:              .equ    0x46
FX_HOT:             .equ    0x42
FX_LIMIT:           .equ    9

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_font_install
        LDX     fx_patterns
        LDAA    0x80
        LDAB    8
        JSR     jr_pcg_load
        JMP     jr_port_run

game_init:
        LDAA    4
        STAA    [FX_CURSOR]
        TST     [JR_PORT_LEVEL]
        BNE     game_init_second
        LDAA    4
        JMP     fx_cross
game_init_second:
        CLRA
        JSR     fx_cross
        LDAA    8
        JMP     fx_cross

game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     fx_press
        LDAB    [FX_CURSOR]
        STAB    [FX_POS]
        JSR     fx_move
        LDAA    [FX_POS]
        STAA    [FX_CURSOR]
        LDAA    0
        JMP     jr_port_sound

fx_press:
        LDAA    [FX_CURSOR]
        INCA
        STAA    [FX_FLASH]
        LDAA    [FX_CURSOR]
        JSR     fx_cross
        LDAA    1
        JSR     jr_port_sound
        LDAA    6
        JSR     jr_port_animate
        CLR     [FX_FLASH]
        INC     [FX_MOVES]
        LDX     FX_BOARD
        CLRB
fx_count:
        LDAA    [X]
        BEQ     fx_count_next
        INCB
fx_count_next:
        INX
        CPX     FX_BOARD + 9
        BNE     fx_count
        TSTB
        BNE     fx_not_clear
        JMP     jr_port_win
fx_not_clear:
        LDAA    [FX_MOVES]
        CMPA    FX_LIMIT
        BCS     fx_press_done
        LDX     fx_lose_text
        JMP     jr_port_lose
fx_press_done:
        RTS

; A = action 1-4 applied to FX_POS on the 3x3 board; edges do not move.
fx_move:
        PSHA
        LDAA    [FX_POS]
        LDAB    3
        JSR     jr_divmod8
        STAB    [FX_COL]
        PULA
        LDAB    [FX_POS]
        CMPA    JR_KEY_UP
        BNE     fx_move_down
        CMPB    3
        BCS     fx_move_done
        SUBB    3
        BRA     fx_move_store
fx_move_down:
        CMPA    JR_KEY_DOWN
        BNE     fx_move_left
        CMPB    6
        BCC     fx_move_done
        ADDB    3
        BRA     fx_move_store
fx_move_left:
        CMPA    JR_KEY_LEFT
        BNE     fx_move_right
        TST     [FX_COL]
        BEQ     fx_move_done
        DECB
        BRA     fx_move_store
fx_move_right:
        CMPA    JR_KEY_RIGHT
        BNE     fx_move_done
        LDAA    [FX_COL]
        CMPA    2
        BCC     fx_move_done
        INCB
fx_move_store:
        STAB    [FX_POS]
fx_move_done:
        RTS

; A = position. Toggles it and its orthogonal neighbours inside the board.
fx_cross:
        STAA    [FX_INDEX]
        JSR     fx_toggle
        LDAA    1
fx_cross_next:
        STAA    [FX_ROW]
        LDAB    [FX_INDEX]
        STAB    [FX_POS]
        JSR     fx_move
        LDAA    [FX_POS]
        CMPA    [FX_INDEX]
        BEQ     fx_cross_skip
        JSR     fx_toggle
fx_cross_skip:
        LDAA    [FX_ROW]
        INCA
        CMPA    5
        BNE     fx_cross_next
        RTS

fx_toggle:
        LDX     FX_BOARD
        JSR     jr_add_x_a
        LDAA    [X]
        EORA    1
        STAA    [X]
        RTS

game_draw:
        LDAA    0x20
        LDAB    FX_TEXT
        JSR     jr_gfx_fill
        LDX     fx_hud
        JSR     jr_gfx_lines
        LDAA    FX_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        LDAA    7
        LDAB    17
        JSR     jr_gfx_at
        LDAA    [FX_MOVES]
        JSR     jr_gfx_dec2
        CLR     [FX_INDEX]
        LDAB    6
        STAB    [FX_ROW]
fx_draw_row:
        LDAA    10
        STAA    [FX_COL]
fx_draw_cell:
        LDX     FX_BOARD
        LDAA    [FX_INDEX]
        JSR     jr_add_x_a
        LDAB    FX_OFF
        LDAA    0x80
        TST     [X]
        BEQ     fx_draw_color
        LDAB    FX_ON
        LDAA    0x84
fx_draw_color:
        PSHA
        LDAA    [FX_INDEX]
        INCA
        CMPA    [FX_FLASH]
        BNE     fx_draw_keep
        LDAB    FX_HOT
fx_draw_keep:
        STAB    [JR_RT_COLOR]
        LDAA    [FX_COL]
        LDAB    [FX_ROW]
        JSR     jr_gfx_at
        PULA
        JSR     jr_gfx_tile
        LDAA    [FX_INDEX]
        CMPA    [FX_CURSOR]
        BNE     fx_draw_advance
        LDAA    FX_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [FX_COL]
        DECA
        LDAB    [FX_ROW]
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
fx_draw_advance:
        INC     [FX_INDEX]
        LDAA    [FX_COL]
        ADDA    4
        STAA    [FX_COL]
        CMPA    22
        BNE     fx_draw_cell
        LDAB    [FX_ROW]
        ADDB    3
        STAB    [FX_ROW]
        CMPB    15
        BNE     fx_draw_row
        RTS

game_draw_title:
        LDAA    0x20
        LDAB    FX_TEXT
        JSR     jr_gfx_fill
        LDX     fx_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    FX_TEXT
        JSR     jr_gfx_fill
        LDX     fx_help_lines
        JMP     jr_gfx_lines

fx_hud:
        .db     1, 0, 0x05
        .dw     fx_txt_name
        .db     21, 0, FX_TEXT
        .dw     fx_txt_stage
        .db     1, 17, FX_TEXT
        .dw     fx_txt_moves
        .db     0xff
fx_title_lines:
        .db     10, 8, 0x06
        .dw     fx_txt_name
        .db     4, 14, FX_TEXT
        .dw     fx_start
        .db     4, 16, FX_TEXT
        .dw     fx_help_hint
        .db     0xff
fx_help_lines:
        .db     2, 4, FX_TEXT
        .dw     fx_help_1
        .db     2, 6, FX_TEXT
        .dw     fx_help_2
        .db     2, 8, FX_TEXT
        .dw     fx_help_3
        .db     0xff
fx_txt_name:
        .db     "PORT FIXTURE", 0
fx_txt_stage:
        .db     "STAGE", 0
fx_txt_moves:
        .db     "MOVES", 0
fx_start:
        .db     "RETURN : START", 0
fx_help_hint:
        .db     "W/A/S/D : HOW TO PLAY", 0
fx_help_1:
        .db     "WASD : SELECT A CELL", 0
fx_help_2:
        .db     "RETURN : FLIP A CROSS", 0
fx_help_3:
        .db     "ESC : RETURN TO BASIC", 0
fx_lose_text:
        .db     "OUT OF MOVES - RETURN RETRY", 0

game_sfx_table:
        .dw     fx_sfx_move, fx_sfx_use, fx_sfx_win, fx_sfx_lose
fx_sfx_move:
        .db     120, 2, 0, 0
fx_sfx_use:
        .db     90, 3, 70, 3, 0, 0
fx_sfx_win:
        .db     120, 6, 90, 6, 70, 6, 60, 12, 0, 0
fx_sfx_lose:
        .db     100, 8, 150, 8, 200, 16, 0, 0

; Tile 0x80-0x83: unlit frame. Tile 0x84-0x87: lit block.
fx_patterns:
        .db     0xff, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
        .db     0xff, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01
        .db     0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0xff
        .db     0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0xff
        .db     0xff, 0xff, 0xc3, 0xdb, 0xdb, 0xc3, 0xff, 0xff
        .db     0xff, 0xff, 0xc3, 0xdb, 0xdb, 0xc3, 0xff, 0xff
        .db     0xff, 0xff, 0xc3, 0xdb, 0xdb, 0xc3, 0xff, 0xff
        .db     0xff, 0xff, 0xc3, 0xdb, 0xdb, 0xc3, 0xff, 0xff

        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys.inc"
        .include "../../../sdk/gfx.inc"
        .include "../../../sdk/font.inc"
        .include "../../../sdk/pcg.inc"
        .include "../../../sdk/frame.inc"
        .include "../../../sdk/math.inc"
        .include "../../../sdk/sound.inc"
        .include "../../../sdk/sfx.inc"
        .include "../../../sdk/port.inc"
        .include "../../../sdk/font_data.inc"
