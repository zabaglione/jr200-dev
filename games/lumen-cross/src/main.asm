; SPDX-License-Identifier: MIT
; LUMEN CROSS for JR-200: a port of jr100dev games/lumen_cross/rules.py 2.0.0.
; Rules, stage generation, the sixty-press limit and the PAR table follow the
; upstream source; display, input and sound use the JR-200 port SDK.
        .filename.jr "LUMEN-CROSS"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    18
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    21
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state: b[25], s.cursor, s.moves, s.flash, s.pose, s.ready.
LC_BOARD:           .equ    GAME_STATE
LC_CURSOR:          .equ    GAME_STATE + 25
LC_MOVES:           .equ    GAME_STATE + 26
LC_FLASH:           .equ    GAME_STATE + 27
LC_POSE:            .equ    GAME_STATE + 28
LC_READY:           .equ    GAME_STATE + 29
; Work bytes for the rules (never touched by drawing).
LC_POS:             .equ    GAME_STATE + 32
LC_CELL:            .equ    GAME_STATE + 33
LC_NEW:             .equ    GAME_STATE + 34
LC_FRAME:           .equ    GAME_STATE + 35
LC_COL:             .equ    GAME_STATE + 36
LC_I:               .equ    GAME_STATE + 37
LC_T:               .equ    GAME_STATE + 38
; Work bytes for drawing (never touched by the rules).
LC_DI:              .equ    GAME_STATE + 48
LC_DX:              .equ    GAME_STATE + 49
LC_DY:              .equ    GAME_STATE + 50
LC_DCODE:           .equ    GAME_STATE + 51
LC_DPOS:            .equ    GAME_STATE + 52
LC_DCOL:            .equ    GAME_STATE + 53
LC_DK:              .equ    GAME_STATE + 54

LC_LIMIT:           .equ    60
LC_TILE_UNLIT:      .equ    0x80
LC_TILE_LIT:        .equ    0x84
LC_TILE_POSE:       .equ    0x88
LC_ATTR_UNLIT:      .equ    0x41
LC_ATTR_LIT:        .equ    0x46
LC_ATTR_FLASH:      .equ    0x45
LC_ATTR_TEXT:       .equ    0x07
LC_ATTR_LABEL:      .equ    0x04
LC_ATTR_TITLE:      .equ    0x06
LC_ATTR_MARK:       .equ    0x03

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_font_install
        LDX     lc_patterns
        LDAA    LC_TILE_UNLIT
        LDAB    28
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; init: for i in range(4 + level // 3): cross((level*7 + i*11 + 3) % 25)
game_init:
        CLR     [LC_I]
lc_init_loop:
        LDAA    [JR_PORT_LEVEL]
        LDAB    3
        JSR     jr_divmod8
        ADDA    4
        CMPA    [LC_I]
        BLS     lc_init_done
        LDAA    [JR_PORT_LEVEL]
        LDAB    7
        JSR     jr_mul8
        STAA    [LC_T]
        LDAA    [LC_I]
        LDAB    11
        JSR     jr_mul8
        ADDA    [LC_T]
        ADDA    3
        LDAB    25
        JSR     jr_divmod8
        TBA
        JSR     lc_cross
        INC     [LC_I]
        BRA     lc_init_loop
lc_init_done:
        LDAA    1
        STAA    [LC_READY]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     lc_press
        CMPA    JR_KEY_BACK
        BEQ     lc_act_done
        LDAA    [LC_CURSOR]
        LDAB    5
        JSR     jr_divmod8
        STAB    [LC_COL]
        LDAA    [JR_PORT_ACTION]
        LDAB    [LC_CURSOR]
        CMPA    JR_KEY_UP
        BNE     lc_act_down
        CMPB    5
        BCS     lc_act_done
        SUBB    5
        BRA     lc_act_store
lc_act_down:
        CMPA    JR_KEY_DOWN
        BNE     lc_act_left
        CMPB    20
        BCC     lc_act_done
        ADDB    5
        BRA     lc_act_store
lc_act_left:
        CMPA    JR_KEY_LEFT
        BNE     lc_act_right
        TST     [LC_COL]
        BEQ     lc_act_done
        DECB
        BRA     lc_act_store
lc_act_right:
        CMPA    JR_KEY_RIGHT
        BNE     lc_act_done
        LDAA    [LC_COL]
        CMPA    4
        BCC     lc_act_done
        INCB
lc_act_store:
        STAB    [LC_CURSOR]
lc_act_done:
        RTS

lc_press:
        LDAA    [LC_CURSOR]
        JSR     lc_cross
        INC     [LC_MOVES]
        LDAA    1
        JSR     jr_port_sound
        LDX     LC_BOARD
        CLRB
lc_count:
        LDAA    [X]
        BEQ     lc_count_next
        INCB
lc_count_next:
        INX
        CPX     LC_BOARD + 25
        BNE     lc_count
        TSTB
        BNE     lc_press_limit
        JMP     jr_port_win
lc_press_limit:
        LDAA    [LC_MOVES]
        CMPA    LC_LIMIT
        BCS     lc_act_done
        LDX     lc_txt_lose
        JMP     jr_port_lose

; A = position. Toggles the cell and its orthogonal neighbours.
lc_cross:
        STAA    [LC_POS]
        JSR     lc_toggle
        LDAA    [LC_POS]
        CMPA    5
        BCS     lc_cross_down
        SUBA    5
        JSR     lc_toggle
lc_cross_down:
        LDAA    [LC_POS]
        CMPA    20
        BCC     lc_cross_left
        ADDA    5
        JSR     lc_toggle
lc_cross_left:
        LDAA    [LC_POS]
        LDAB    5
        JSR     jr_divmod8
        STAB    [LC_COL]
        TSTB
        BEQ     lc_cross_right
        LDAA    [LC_POS]
        DECA
        JSR     lc_toggle
lc_cross_right:
        LDAA    [LC_COL]
        CMPA    4
        BCC     lc_cross_done
        LDAA    [LC_POS]
        INCA
        JSR     lc_toggle
lc_cross_done:
        RTS

; A = position. b[pos] ^= 1, then the five-pose flip when the stage is ready.
lc_toggle:
        STAA    [LC_CELL]
        LDX     LC_BOARD
        JSR     jr_add_x_a
        LDAA    [X]
        EORA    1
        STAA    [X]
        STAA    [LC_NEW]
        TST     [LC_READY]
        BEQ     lc_toggle_done
        LDAA    [LC_CELL]
        INCA
        STAA    [LC_FLASH]
        CLRA
        JSR     jr_port_sound
        CLR     [LC_FRAME]
lc_toggle_frame:
        LDAA    [LC_FRAME]
        TST     [LC_NEW]
        BEQ     lc_toggle_off
        INCA
        BRA     lc_toggle_pose
lc_toggle_off:
        NEGA
        ADDA    5
lc_toggle_pose:
        STAA    [LC_POSE]
        LDAA    2
        JSR     jr_port_animate
        INC     [LC_FRAME]
        LDAA    [LC_FRAME]
        CMPA    5
        BNE     lc_toggle_frame
        CLR     [LC_FLASH]
lc_toggle_done:
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    LC_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     lc_hud
        JSR     jr_gfx_lines
        LDAA    LC_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; board
        CLR     [LC_DI]
        LDAA    4
        STAA    [LC_DY]
lc_draw_row:
        LDAA    1
        STAA    [LC_DX]
lc_draw_cell:
        LDAA    [LC_DI]
        INCA
        CMPA    [LC_FLASH]
        BNE     lc_draw_state
        LDAA    [LC_POSE]
        DECA
        ASLA
        ASLA
        ADDA    LC_TILE_POSE
        LDAB    LC_ATTR_FLASH
        BRA     lc_draw_tile
lc_draw_state:
        LDX     LC_BOARD
        LDAA    [LC_DI]
        JSR     jr_add_x_a
        LDAA    LC_TILE_UNLIT
        LDAB    LC_ATTR_UNLIT
        TST     [X]
        BEQ     lc_draw_tile
        LDAA    LC_TILE_LIT
        LDAB    LC_ATTR_LIT
lc_draw_tile:
        STAA    [LC_DCODE]
        STAB    [JR_RT_COLOR]
        LDAA    [LC_DX]
        LDAB    [LC_DY]
        JSR     jr_gfx_at
        LDAA    [LC_DCODE]
        JSR     jr_gfx_tile
        INC     [LC_DI]
        LDAA    [LC_DX]
        ADDA    3
        STAA    [LC_DX]
        CMPA    16
        BNE     lc_draw_cell
        LDAA    [LC_DY]
        ADDA    3
        STAA    [LC_DY]
        CMPA    19
        BNE     lc_draw_row
        ; cursor at (cursor % 5 * 3, 4 + cursor // 5 * 3)
        LDAA    LC_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [LC_CURSOR]
        JSR     lc_cell_xy
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        ; counters
        LDAA    23
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [LC_MOVES]
        JSR     jr_gfx_dec2
        LDAA    23
        LDAB    13
        JSR     jr_gfx_at
        LDAA    LC_LIMIT
        SUBA    [LC_MOVES]
        JSR     jr_gfx_dec2
        LDAA    24
        LDAB    17
        JSR     jr_gfx_at
        JSR     lc_par
        JSR     jr_gfx_dec2
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     lc_draw_marks
        CMPA    JR_MODE_CLEAR
        BNE     lc_draw_done
        JSR     lc_par
        CMPA    [LC_MOVES]
        BCS     lc_draw_done
        LDAA    LC_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    2
        LDAB    20
        JSR     jr_gfx_at
        LDX     lc_txt_perfect
        JMP     jr_gfx_text
lc_draw_done:
        RTS

; Preview: '^' under every light the cursor's cross would flip.
lc_draw_marks:
        LDAA    LC_ATTR_MARK
        STAA    [JR_RT_COLOR]
        LDAA    [LC_CURSOR]
        LDAB    5
        JSR     jr_divmod8
        STAB    [LC_DCOL]
        LDAA    [LC_CURSOR]
        JSR     lc_mark
        LDAA    [LC_CURSOR]
        CMPA    5
        BCS     lc_marks_down
        SUBA    5
        JSR     lc_mark
lc_marks_down:
        LDAA    [LC_CURSOR]
        CMPA    20
        BCC     lc_marks_left
        ADDA    5
        JSR     lc_mark
lc_marks_left:
        TST     [LC_DCOL]
        BEQ     lc_marks_right
        LDAA    [LC_CURSOR]
        DECA
        JSR     lc_mark
lc_marks_right:
        LDAA    [LC_DCOL]
        CMPA    4
        BCC     lc_draw_done
        LDAA    [LC_CURSOR]
        INCA
        JMP     lc_mark

; A = position: '^' at (2 + pos % 5 * 3, 6 + pos // 5 * 3).
lc_mark:
        JSR     lc_cell_xy
        ADDA    2
        ADDB    2
        JSR     jr_gfx_at
        LDAA    0x5e
        JMP     jr_gfx_putc

; A = position -> A = pos % 5 * 3, B = 4 + pos // 5 * 3.
lc_cell_xy:
        LDAB    5
        JSR     jr_divmod8
        STAB    [LC_DK]
        TAB
        ASLA
        ABA
        ADDA    4
        TAB
        LDAA    [LC_DK]
        STAB    [LC_DK]
        TAB
        ASLA
        ABA
        LDAB    [LC_DK]
        RTS

; A = PAR of the current stage.
lc_par:
        LDX     lc_pars
        LDAA    [JR_PORT_LEVEL]
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

game_draw_title:
        LDAA    0x20
        LDAB    LC_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    LC_ATTR_LIT
        STAA    [JR_RT_COLOR]
        LDX     lc_title_tiles
        STX     [JR_RT_TABLE]
lc_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     lc_title_text
        LDAB    [X + 1]
        JSR     jr_gfx_at
        LDAA    LC_TILE_LIT
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     lc_title_tile
lc_title_text:
        LDX     lc_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    LC_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     lc_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

lc_pars:
        .db     4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9

lc_hud:
        .db     1, 0, LC_ATTR_TITLE
        .dw     lc_txt_name
        .db     23, 0, LC_ATTR_LABEL
        .dw     lc_txt_stage
        .db     20, 3, LC_ATTR_LABEL
        .dw     lc_txt_array
        .db     21, 6, LC_ATTR_LABEL
        .dw     lc_txt_presses
        .db     21, 12, LC_ATTR_LABEL
        .dw     lc_txt_remain
        .db     19, 16, LC_ATTR_LABEL
        .dw     lc_txt_par
        .db     0xff

lc_title_tiles:
        .db     14, 3, 14, 6, 11, 6, 17, 6, 14, 9
        .db     0xff
lc_title_lines:
        .db     10, 12, LC_ATTR_TITLE
        .dw     lc_txt_name
        .db     6, 14, LC_ATTR_LABEL
        .dw     lc_txt_tagline
        .db     8, 17, LC_ATTR_TEXT
        .dw     lc_txt_start
        .db     5, 19, LC_ATTR_TEXT
        .dw     lc_txt_howto
        .db     4, 22, LC_ATTR_UNLIT & 0x07
        .dw     lc_txt_credit
        .db     0xff
lc_help_lines:
        .db     9, 2, LC_ATTR_TITLE
        .dw     lc_txt_name
        .db     2, 5, LC_ATTR_TEXT
        .dw     lc_help_1
        .db     2, 7, LC_ATTR_TEXT
        .dw     lc_help_2
        .db     2, 9, LC_ATTR_TEXT
        .dw     lc_help_3
        .db     2, 11, LC_ATTR_TEXT
        .dw     lc_help_4
        .db     2, 13, LC_ATTR_TEXT
        .dw     lc_help_5
        .db     2, 15, LC_ATTR_TEXT
        .dw     lc_help_6
        .db     2, 17, LC_ATTR_TEXT
        .dw     lc_help_7
        .db     2, 20, LC_ATTR_LABEL
        .dw     lc_help_back
        .db     0xff

lc_txt_name:
        .db     "LUMEN CROSS", 0
lc_txt_stage:
        .db     "STAGE", 0
lc_txt_array:
        .db     "CROSS ARRAY", 0
lc_txt_presses:
        .db     "PRESSES", 0
lc_txt_remain:
        .db     "REMAIN", 0
lc_txt_par:
        .db     "PAR", 0
lc_txt_perfect:
        .db     "PERFECT CIRCUIT", 0
lc_txt_lose:
        .db     "SIXTY SWITCHES WERE NOT ENOUGH", 0
lc_txt_tagline:
        .db     "SWITCH EVERY LIGHT OFF", 0
lc_txt_start:
        .db     "RETURN : START", 0
lc_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
lc_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
lc_help_1:
        .db     "WASD : SELECT A CELL", 0
lc_help_2:
        .db     "RETURN : FLIP CROSS", 0
lc_help_3:
        .db     "A CROSS FLIPS FIVE LIGHTS.", 0
lc_help_4:
        .db     "SWITCH EVERY LIGHT OFF.", 0
lc_help_5:
        .db     "SIXTY PRESSES PER PANEL.", 0
lc_help_6:
        .db     "SPACE : RESTART THIS PANEL", 0
lc_help_7:
        .db     "CTRL+C : BACK TO BASIC", 0
lc_help_back:
        .db     "ANY KEY : TITLE", 0

game_sfx_table:
        .dw     lc_sfx_flip, lc_sfx_press, lc_sfx_win, lc_sfx_lose
lc_sfx_flip:
        .db     70, 1, 0, 0
lc_sfx_press:
        .db     110, 2, 90, 2, 0, 0
lc_sfx_win:
        .db     120, 6, 95, 6, 80, 6, 60, 14, 0, 0
lc_sfx_lose:
        .db     120, 8, 160, 8, 220, 18, 0, 0

        .include "art.inc"
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
