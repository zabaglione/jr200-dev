; SPDX-License-Identifier: MIT
; FIVE FORGE for JR-200: a port of jr100dev games/five_forge/rules.py 1.6.1.
; Five-in-a-row detection, the rival's attack * 3 + defence choice, the stone
; drop and the blinking five follow the upstream source; display, colour and
; three-voice sound use the JR-200 port SDK.
        .filename.jr "FIVE-FORGE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4740
JR_AUDIO:           .equ    0x4740
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    1
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    21
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then one byte per cell:
; bits 0-1 the stone (1 you, 2 rival), bit 2 part of the completed five.
FF_CURSOR:          .equ    GAME_STATE
FF_STONES:          .equ    GAME_STATE + 1
FF_LAST:            .equ    GAME_STATE + 2
FF_PLACING:         .equ    GAME_STATE + 3
FF_POSE:            .equ    GAME_STATE + 4
FF_WINNER:          .equ    GAME_STATE + 5
FF_BLINK:           .equ    GAME_STATE + 6
FF_CELLS:           .equ    GAME_STATE + 7
; Rule work bytes.
FF_RPOS:            .equ    GAME_STATE + 72
FF_RAYDIR:          .equ    GAME_STATE + 73
FF_RX:              .equ    GAME_STATE + 74
FF_RY:              .equ    GAME_STATE + 75
FF_CNT:             .equ    GAME_STATE + 76
FF_P:               .equ    GAME_STATE + 77
FF_MARK:            .equ    GAME_STATE + 78
FF_BEST:            .equ    GAME_STATE + 79
FF_CHOSEN:          .equ    GAME_STATE + 80
FF_I:               .equ    GAME_STATE + 81
FF_ATTACK:          .equ    GAME_STATE + 82
FF_VALUE:           .equ    GAME_STATE + 83
FF_AXIS:            .equ    GAME_STATE + 84
FF_SIDE:            .equ    GAME_STATE + 85
FF_LBEST:           .equ    GAME_STATE + 86
FF_LPOS:            .equ    GAME_STATE + 87
FF_FRAME:           .equ    GAME_STATE + 88
FF_K:               .equ    GAME_STATE + 89
FF_STEP:            .equ    GAME_STATE + 90
FF_CPOS:            .equ    GAME_STATE + 91
; Drawing work bytes.
FF_DI:              .equ    GAME_STATE + 100
FF_DCODE:           .equ    GAME_STATE + 101
FF_DX:              .equ    GAME_STATE + 102
FF_DY:              .equ    GAME_STATE + 103

FF_TILE_GRID:       .equ    0x80
FF_TILE_OWN:        .equ    0x84
FF_TILE_RIVAL:      .equ    0x88
FF_TILE_CURSOR:     .equ    0x8c
FF_TILE_SQUASH:     .equ    0x90        ; + 4 for the rival
FF_ATTR_BOARD:      .equ    0x70        ; black lines on a yellow board
FF_ATTR_OWN:        .equ    0x77        ; white stones
FF_ATTR_RIVAL:      .equ    0x70        ; black stones
FF_ATTR_CURSOR:     .equ    0x72
FF_ATTR_OWN_HI:     .equ    0x6f        ; the stone being placed: cyan ground
FF_ATTR_RIVAL_HI:   .equ    0x68
FF_ATTR_OWN_FIVE:   .equ    0x5f        ; the completed five: magenta ground
FF_ATTR_RIVAL_FIVE: .equ    0x58
FF_ATTR_TEXT:       .equ    0x07
FF_ATTR_LABEL:      .equ    0x04
FF_ATTR_TITLE:      .equ    0x06
FF_ATTR_DIM:        .equ    0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     ff_patterns
        LDAA    FF_TILE_GRID
        LDAB    24
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    27
        STAA    [FF_CURSOR]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        TSTA
        BEQ     ff_act_done
        CMPA    JR_KEY_CONFIRM
        BEQ     ff_confirm
        BCC     ff_act_done
        TAB
        LDAA    [FF_CURSOR]
        JSR     ff_move
        STAA    [FF_CURSOR]
ff_act_done:
        RTS

ff_confirm:
        LDAA    [FF_CURSOR]
        JSR     ff_cell
        LDAA    [X]
        BNE     ff_act_done
        LDAA    [FF_CURSOR]
        LDAB    1
        JSR     ff_place
        LDAA    [FF_CURSOR]
        LDAB    1
        JSR     ff_complete
        TSTA
        BNE     ff_act_done
        ; the rival: first empty cell with the best attack * 3 + defence
        CLR     [FF_BEST]
        LDAA    0xff
        STAA    [FF_CHOSEN]
        CLR     [FF_I]
ff_rival_cell:
        LDAA    [FF_I]
        JSR     ff_cell
        LDAA    [X]
        BNE     ff_rival_next
        LDAA    [FF_I]
        LDAB    2
        JSR     ff_line
        STAA    [FF_ATTACK]
        LDAA    [FF_I]
        LDAB    1
        JSR     ff_line
        ; A = defence
        PSHA
        LDAB    [FF_ATTACK]
        ASLB
        ADDB    [FF_ATTACK]
        ABA
        STAA    [FF_VALUE]
        PULA
        CMPA    5
        BCS     ff_rival_attack
        LDAA    100
        STAA    [FF_VALUE]
ff_rival_attack:
        LDAA    [FF_ATTACK]
        CMPA    5
        BCS     ff_rival_compare
        LDAA    120
        STAA    [FF_VALUE]
ff_rival_compare:
        LDAA    [FF_VALUE]
        CMPA    [FF_BEST]
        BLS     ff_rival_next
        STAA    [FF_BEST]
        LDAA    [FF_I]
        STAA    [FF_CHOSEN]
ff_rival_next:
        INC     [FF_I]
        LDAA    [FF_I]
        CMPA    64
        BNE     ff_rival_cell
        LDAA    [FF_CHOSEN]
        CMPA    0xff
        BEQ     ff_rival_none
        LDAB    2
        JSR     ff_place
        LDAA    [FF_CHOSEN]
        LDAB    2
        JMP     ff_complete
ff_rival_none:
        LDAA    [FF_STONES]
        CMPA    64
        BCC     ff_act_done_near186
        JMP     ff_act_done
ff_act_done_near186:
        LDX     ff_txt_full
        JMP     jr_port_lose

; A = cell -> X = its byte.
ff_cell:
        LDX     FF_CELLS
        JMP     jr_add_x_a

; A = position, B = mark: drop the stone in four poses.
ff_place:
        STAA    [FF_LAST]
        STAB    [FF_PLACING]
        JSR     ff_cell
        LDAA    [FF_PLACING]
        STAA    [X]
        INC     [FF_STONES]
        CLRA
        JSR     jr_port_sound
        CLR     [FF_FRAME]
ff_place_frame:
        LDAA    [FF_PLACING]
        DECA
        ASLA
        ASLA
        ADDA    [FF_FRAME]
        INCA
        STAA    [FF_POSE]
        LDAA    [FF_FRAME]
        CMPA    2
        BNE     ff_place_wait
        LDAA    1
        JSR     jr_port_sound
ff_place_wait:
        LDAA    8
        LDAB    [FF_FRAME]
        CMPB    3
        BNE     ff_place_animate
        LDAA    12
ff_place_animate:
        JSR     jr_port_animate
        INC     [FF_FRAME]
        LDAA    [FF_FRAME]
        CMPA    4
        BNE     ff_place_frame
        CLR     [FF_PLACING]
        RTS

; A = position, B = mark -> A = best line through it (the cell counts as one).
ff_line:
        STAA    [FF_LPOS]
        STAB    [FF_MARK]
        CLR     [FF_LBEST]
        CLR     [FF_AXIS]
ff_line_axis:
        LDAA    [FF_LPOS]
        LDAB    [FF_AXIS]
        ASLB
        JSR     ff_count_ray
        STAA    [FF_K]
        LDAA    [FF_LPOS]
        LDAB    [FF_AXIS]
        ASLB
        INCB
        JSR     ff_count_ray
        ADDA    [FF_K]
        INCA
        CMPA    [FF_LBEST]
        BLS     ff_line_next
        STAA    [FF_LBEST]
ff_line_next:
        INC     [FF_AXIS]
        LDAA    [FF_AXIS]
        CMPA    4
        BNE     ff_line_axis
        LDAA    [FF_LBEST]
        RTS

; A = position, B = direction, FF_MARK -> A = stones of the mark in a row.
ff_count_ray:
        STAA    [FF_P]
        STAB    [FF_STEP]
        CLR     [FF_CNT]
ff_count_step:
        LDAA    [FF_CNT]
        CMPA    7
        BCC     ff_count_done
        LDAA    [FF_P]
        LDAB    [FF_STEP]
        JSR     ff_ray
        CMPA    0xff
        BEQ     ff_count_done
        STAA    [FF_P]
        JSR     ff_cell
        LDAA    [X]
        ANDA    3
        CMPA    [FF_MARK]
        BNE     ff_count_done
        INC     [FF_CNT]
        BRA     ff_count_step
ff_count_done:
        LDAA    [FF_CNT]
        RTS

; A = position, B = mark -> A = 1 when it completed five (then the game ends).
ff_complete:
        STAA    [FF_CPOS]
        PSHB
        JSR     ff_line
        PULB
        CMPA    5
        BCC     ff_complete_mark
        CLRA
        RTS
ff_complete_mark:
        STAB    [FF_WINNER]
        LDAA    [FF_CPOS]
        JSR     ff_cell
        LDAA    [X]
        ORAA    4
        STAA    [X]
        CLR     [FF_AXIS]
ff_complete_axis:
        LDAA    [FF_CPOS]
        LDAB    [FF_AXIS]
        ASLB
        JSR     ff_count_ray
        STAA    [FF_K]
        LDAA    [FF_CPOS]
        LDAB    [FF_AXIS]
        ASLB
        INCB
        JSR     ff_count_ray
        ADDA    [FF_K]
        CMPA    4
        BCS     ff_complete_next
        ; mark both rays of this axis
        CLR     [FF_SIDE]
ff_complete_side:
        LDAA    [FF_CPOS]
        STAA    [FF_P]
ff_complete_step:
        LDAA    [FF_P]
        LDAB    [FF_AXIS]
        ASLB
        ADDB    [FF_SIDE]
        JSR     ff_ray
        CMPA    0xff
        BEQ     ff_complete_side_next
        STAA    [FF_P]
        JSR     ff_cell
        LDAA    [X]
        ANDA    3
        CMPA    [FF_MARK]
        BNE     ff_complete_side_next
        LDAA    [X]
        ORAA    4
        STAA    [X]
        BRA     ff_complete_step
ff_complete_side_next:
        INC     [FF_SIDE]
        LDAA    [FF_SIDE]
        CMPA    2
        BNE     ff_complete_side
ff_complete_next:
        INC     [FF_AXIS]
        LDAA    [FF_AXIS]
        CMPA    4
        BNE     ff_complete_axis
        ; the five blinks three times
        LDAA    3
        STAA    [FF_I]
ff_complete_blink:
        LDAA    1
        STAA    [FF_BLINK]
        CLRA
        JSR     jr_port_sound
        LDAA    12
        JSR     jr_port_animate
        CLR     [FF_BLINK]
        LDAA    16
        JSR     jr_port_animate
        DEC     [FF_I]
        BNE     ff_complete_blink
        LDAA    24
        JSR     jr_port_animate
        LDAA    [FF_WINNER]
        CMPA    1
        BNE     ff_complete_lose
        JSR     jr_port_win
        LDAA    1
        RTS
ff_complete_lose:
        LDX     ff_txt_rival_five
        JSR     jr_port_lose
        LDAA    1
        RTS

; A = position, B = action 1-4 -> A = moved position (8x8, stops at edges).
ff_move:
        STAA    [FF_P]
        CMPB    JR_KEY_UP
        BNE     ff_move_down
        CMPA    8
        BCS     ff_move_done
        SUBA    8
        RTS
ff_move_down:
        CMPB    JR_KEY_DOWN
        BNE     ff_move_side
        CMPA    56
        BCC     ff_move_done
        ADDA    8
        RTS
ff_move_side:
        ANDA    7
        CMPB    JR_KEY_LEFT
        BNE     ff_move_right
        TSTA
        BEQ     ff_move_stay
        LDAA    [FF_P]
        DECA
        RTS
ff_move_right:
        CMPA    7
        BCC     ff_move_stay
        LDAA    [FF_P]
        INCA
        RTS
ff_move_stay:
        LDAA    [FF_P]
ff_move_done:
        RTS

; A = position, B = direction 0-7 -> A = the neighbour, or 0xff off the board.
ff_ray:
        STAA    [FF_RPOS]
        STAB    [FF_RAYDIR]
        TAB
        ANDB    7
        STAB    [FF_RX]
        LSRA
        LSRA
        LSRA
        STAA    [FF_RY]
        LDAA    [FF_RAYDIR]
        BEQ     ff_ray_east
        CMPA    1
        BEQ     ff_ray_west
        CMPA    2
        BEQ     ff_ray_south
        CMPA    3
        BEQ     ff_ray_north
        CMPA    4
        BEQ     ff_ray_southeast
        CMPA    5
        BEQ     ff_ray_northwest
        CMPA    6
        BEQ     ff_ray_southwest
        BRA     ff_ray_northeast
ff_ray_east:
        LDAA    [FF_RX]
        CMPA    7
        BCC     ff_ray_none
        LDAA    1
        BRA     ff_ray_add
ff_ray_west:
        TST     [FF_RX]
        BEQ     ff_ray_none
        LDAA    0xff
        BRA     ff_ray_add
ff_ray_south:
        LDAA    [FF_RY]
        CMPA    7
        BCC     ff_ray_none
        LDAA    8
        BRA     ff_ray_add
ff_ray_north:
        TST     [FF_RY]
        BEQ     ff_ray_none
        LDAA    0xf8
        BRA     ff_ray_add
ff_ray_southeast:
        LDAA    [FF_RX]
        CMPA    7
        BCC     ff_ray_none
        LDAA    [FF_RY]
        CMPA    7
        BCC     ff_ray_none
        LDAA    9
        BRA     ff_ray_add
ff_ray_northwest:
        TST     [FF_RX]
        BEQ     ff_ray_none
        TST     [FF_RY]
        BEQ     ff_ray_none
        LDAA    0xf7
        BRA     ff_ray_add
ff_ray_southwest:
        TST     [FF_RX]
        BEQ     ff_ray_none
        LDAA    [FF_RY]
        CMPA    7
        BCC     ff_ray_none
        LDAA    7
        BRA     ff_ray_add
ff_ray_northeast:
        LDAA    [FF_RX]
        CMPA    7
        BCC     ff_ray_none
        TST     [FF_RY]
        BEQ     ff_ray_none
        LDAA    0xf9
ff_ray_add:
        ADDA    [FF_RPOS]
        RTS
ff_ray_none:
        LDAA    0xff
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    FF_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ff_hud
        JSR     jr_gfx_lines
        CLR     [FF_DI]
ff_draw_cell:
        LDAA    [FF_DI]
        JSR     ff_cell
        LDAA    [X]
        STAA    [FF_DCODE]
        ; A = stone, B = look offset: 0 plain, 1 highlighted, 2 five, 3 cursor
        ANDA    3
        CLRB
        TST     [FF_WINNER]
        BEQ     ff_draw_placing
        LDAA    [FF_DCODE]
        ANDA    4
        BEQ     ff_draw_plain
        LDAB    2
        TST     [FF_BLINK]
        BEQ     ff_draw_plain
        CLR     [FF_DCODE]
        CLRB
        BRA     ff_draw_plain
ff_draw_placing:
        TST     [FF_PLACING]
        BEQ     ff_draw_cursor
        LDAA    [FF_DI]
        CMPA    [FF_LAST]
        BNE     ff_draw_plain
        ; the falling stone: above the cell, landed, squashed, settled
        LDAA    [FF_POSE]
        DECA
        ANDA    3
        BNE     ff_draw_landed
        CLR     [FF_DCODE]
        BRA     ff_draw_plain
ff_draw_landed:
        LDAB    1
        CMPA    2
        BNE     ff_draw_plain
        LDAB    4
        BRA     ff_draw_plain
ff_draw_cursor:
        LDAA    [FF_DI]
        CMPA    [FF_CURSOR]
        BNE     ff_draw_plain
        LDAB    1
        LDAA    [FF_DCODE]
        ANDA    3
        BNE     ff_draw_plain
        LDAB    3
ff_draw_plain:
        ; look = ff_looks[stone * 5 + offset]: code, attribute
        LDAA    [FF_DCODE]
        ANDA    3
        STAB    [FF_DX]
        LDAB    5
        JSR     jr_mul8
        ADDA    [FF_DX]
        ASLA
        LDX     ff_looks
        JSR     jr_add_x_a
        LDAA    [X + 1]
        STAA    [JR_RT_COLOR]
        LDAA    [X]
        STAA    [FF_DCODE]
        LDAA    [FF_DI]
        JSR     ff_cell_xy
        JSR     jr_gfx_at
        LDAA    [FF_DCODE]
        JSR     jr_gfx_tile
        INC     [FF_DI]
        LDAA    [FF_DI]
        CMPA    64
        BEQ     ff_draw_cell_near587
        JMP     ff_draw_cell
ff_draw_cell_near587:
        ; the stone above its cell in the first pose
        TST     [FF_PLACING]
        BEQ     ff_draw_panel
        LDAA    [FF_POSE]
        DECA
        ANDA    3
        BNE     ff_draw_panel
        LDAA    [FF_PLACING]
        LDAB    5
        JSR     jr_mul8
        INCA
        ASLA
        LDX     ff_looks
        JSR     jr_add_x_a
        LDAA    [X + 1]
        STAA    [JR_RT_COLOR]
        LDAA    [X]
        STAA    [FF_DCODE]
        LDAA    [FF_LAST]
        JSR     ff_cell_xy
        DECB
        JSR     jr_gfx_at
        LDAA    [FF_DCODE]
        JSR     jr_gfx_tile
ff_draw_panel:
        LDAA    FF_ATTR_OWN
        STAA    [JR_RT_COLOR]
        LDAA    22
        LDAB    5
        JSR     jr_gfx_at
        LDAA    FF_TILE_OWN
        JSR     jr_gfx_tile
        LDAA    FF_ATTR_RIVAL
        STAA    [JR_RT_COLOR]
        LDAA    22
        LDAB    11
        JSR     jr_gfx_at
        LDAA    FF_TILE_RIVAL
        JSR     jr_gfx_tile
        LDAA    FF_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    27
        LDAB    6
        JSR     jr_gfx_at
        LDAA    [FF_STONES]
        INCA
        LSRA
        JSR     jr_gfx_dec2
        LDAA    27
        LDAB    12
        JSR     jr_gfx_at
        LDAA    [FF_STONES]
        LSRA
        JSR     jr_gfx_dec2
        ; whose move it is
        LDAA    3
        TST     [FF_WINNER]
        BEQ     ff_draw_turn
        LDAA    0
ff_draw_turn:
        LDAB    [FF_PLACING]
        BEQ     ff_draw_status
        TBA
ff_draw_status:
        ; 0 last move, 1 your move, 2 rival move, 3 your turn
        STAA    [FF_DX]
        LDX     ff_status_attr
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [FF_DX]
        ASLA
        LDX     ff_status_text
        JSR     jr_add_x_a
        LDX     [X]
        STX     [JR_RT_TABLE]
        LDAA    21
        LDAB    16
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        JSR     jr_gfx_text
        ; CELL: the placed stone while placing or after five, else the cursor
        LDAA    FF_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [FF_CURSOR]
        TST     [FF_PLACING]
        BNE     ff_draw_cell_last
        TST     [FF_WINNER]
        BEQ     ff_draw_cell_name
ff_draw_cell_last:
        LDAA    [FF_LAST]
ff_draw_cell_name:
        STAA    [FF_DX]
        LDAA    27
        LDAB    18
        JSR     jr_gfx_at
        LDAA    [FF_DX]
        ANDA    7
        ADDA    0x41
        JSR     jr_gfx_putc
        LDAA    [FF_DX]
        LSRA
        LSRA
        LSRA
        ADDA    0x31
        JMP     jr_gfx_putc

; A = cell -> A = 1 + cell % 8 * 2, B = 4 + cell // 8 * 2.
ff_cell_xy:
        TAB
        LSRB
        LSRB
        LSRB
        ASLB
        ADDB    4
        ANDA    7
        ASLA
        INCA
        RTS

game_draw_title:
        LDX     ff_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    FF_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ff_title_tiles
        STX     [JR_RT_TABLE]
ff_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     ff_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [FF_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [FF_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     ff_title_tile
ff_title_text:
        LDX     ff_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    FF_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ff_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; per stone (empty, you, rival): plain, highlighted, five, cursor, squashed
ff_looks:
        .db     FF_TILE_GRID, FF_ATTR_BOARD, FF_TILE_GRID, FF_ATTR_BOARD
        .db     FF_TILE_GRID, FF_ATTR_BOARD, FF_TILE_CURSOR, FF_ATTR_CURSOR
        .db     FF_TILE_GRID, FF_ATTR_BOARD
        .db     FF_TILE_OWN, FF_ATTR_OWN, FF_TILE_OWN, FF_ATTR_OWN_HI
        .db     FF_TILE_OWN, FF_ATTR_OWN_FIVE, FF_TILE_OWN, FF_ATTR_OWN_HI
        .db     FF_TILE_SQUASH, FF_ATTR_OWN_HI
        .db     FF_TILE_RIVAL, FF_ATTR_RIVAL, FF_TILE_RIVAL, FF_ATTR_RIVAL_HI
        .db     FF_TILE_RIVAL, FF_ATTR_RIVAL_FIVE, FF_TILE_RIVAL, FF_ATTR_RIVAL_HI
        .db     FF_TILE_SQUASH + 4, FF_ATTR_RIVAL_HI

ff_status_text:
        .dw     ff_txt_last, ff_txt_your_move, ff_txt_rival_move, ff_txt_your_turn
ff_status_attr:
        .db     0x04, 0x06, 0x02, 0x07

; x, attribute, code, y
ff_title_tiles:
        .db     10, FF_ATTR_OWN, FF_TILE_OWN, 3
        .db     12, FF_ATTR_OWN, FF_TILE_OWN, 3
        .db     14, FF_ATTR_OWN_FIVE, FF_TILE_OWN, 3
        .db     16, FF_ATTR_OWN, FF_TILE_OWN, 3
        .db     18, FF_ATTR_OWN, FF_TILE_OWN, 3
        .db     14, FF_ATTR_RIVAL, FF_TILE_RIVAL, 5
        .db     0xff

ff_hud:
        .db     1, 0, FF_ATTR_TITLE
        .dw     ff_txt_name
        .db     25, 5, FF_ATTR_LABEL
        .dw     ff_txt_you
        .db     25, 11, FF_ATTR_LABEL
        .dw     ff_txt_rival
        .db     21, 18, FF_ATTR_LABEL
        .dw     ff_txt_cell
        .db     0xff
ff_title_lines:
        .db     11, 8, FF_ATTR_TITLE
        .dw     ff_txt_name
        .db     5, 10, FF_ATTR_LABEL
        .dw     ff_txt_tagline
        .db     8, 15, FF_ATTR_TEXT
        .dw     ff_txt_start
        .db     5, 17, FF_ATTR_TEXT
        .dw     ff_txt_howto
        .db     4, 22, FF_ATTR_DIM
        .dw     ff_txt_credit
        .db     0xff
ff_help_lines:
        .db     11, 2, FF_ATTR_TITLE
        .dw     ff_txt_name
        .db     1, 5, FF_ATTR_TEXT
        .dw     ff_help_1
        .db     1, 7, FF_ATTR_TEXT
        .dw     ff_help_2
        .db     1, 9, FF_ATTR_TEXT
        .dw     ff_help_3
        .db     1, 11, FF_ATTR_TEXT
        .dw     ff_help_4
        .db     1, 13, FF_ATTR_TEXT
        .dw     ff_help_5
        .db     1, 15, FF_ATTR_TEXT
        .dw     ff_help_6
        .db     1, 17, FF_ATTR_TEXT
        .dw     ff_help_7
        .db     1, 21, FF_ATTR_LABEL
        .dw     ff_help_back
        .db     0xff

ff_txt_name:
        .db     "FIVE FORGE", 0
ff_txt_you:
        .db     "YOU", 0
ff_txt_rival:
        .db     "RIVAL", 0
ff_txt_cell:
        .db     "CELL", 0
ff_txt_last:
        .db     "LAST MOVE", 0
ff_txt_your_move:
        .db     "YOUR MOVE", 0
ff_txt_rival_move:
        .db     "RIVAL MOVE", 0
ff_txt_your_turn:
        .db     "YOUR TURN", 0
ff_txt_rival_five:
        .db     "RIVAL COMPLETED FIVE", 0
ff_txt_full:
        .db     "BOARD FULL - NO FIVE", 0
ff_txt_tagline:
        .db     "FIVE IN A ROW ON 8X8", 0
ff_txt_start:
        .db     "RETURN : START", 0
ff_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
ff_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
ff_help_1:
        .db     "WASD : SELECT A CELL", 0
ff_help_2:
        .db     "RETURN : PLACE YOUR STONE", 0
ff_help_3:
        .db     "MAKE FIVE IN ANY DIRECTION.", 0
ff_help_4:
        .db     "THE RIVAL BLOCKS IMMEDIATE WINS", 0
ff_help_5:
        .db     "AND BUILDS ITS OWN THREATS.", 0
ff_help_6:
        .db     "A FULL BOARD WITHOUT FIVE LOSES", 0
ff_help_7:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
ff_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     ff_sfx_drop, ff_sfx_land, ff_jingle_win, ff_jingle_lose
ff_sfx_drop:
        .db     100, 2, 80, 2, 0, 0
ff_sfx_land:
        .db     230, 3, 0, 0

; Title: a stately march in B flat major, quarter note = 16 frames, looping.
ff_title_song:
        .db     1
        .dw     ff_title_melody, ff_title_harmony, ff_title_bass
ff_title_melody:
        .db     AU_F5, 24, AU_D5, 8, AU_AS4, 16, AU_D5, 16
        .db     AU_F5, 16, AU_AS5, 16, AU_A5, 32
        .db     AU_G5, 24, AU_F5, 8, AU_DS5, 16, AU_C5, 16
        .db     AU_D5, 16, AU_C5, 16, AU_AS4, 32, 0, 0
ff_title_harmony:
        .db     AU_D5, 32, AU_F4, 32, AU_D5, 32, AU_F5, 32
        .db     AU_DS5, 32, AU_A4, 32, AU_F4, 32, AU_D4, 32, 0, 0
ff_title_bass:
        .db     AU_AS2, 16, AU_F2, 16, AU_AS2, 16, AU_F2, 16
        .db     AU_D3, 16, AU_D3, 16, AU_F3, 16, AU_F2, 16
        .db     AU_DS3, 16, AU_AS2, 16, AU_C3, 16, AU_A2, 16
        .db     AU_F2, 16, AU_F2, 16, AU_AS2, 32, 0, 0

; Five: B flat major arpeggio over the tonic (54 frames).
ff_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     ff_win_melody, ff_win_harmony, ff_win_bass
ff_win_melody:
        .db     AU_AS4, 8, AU_D5, 8, AU_F5, 8, AU_AS5, 30, 0, 0
ff_win_harmony:
        .db     AU_F4, 8, AU_AS4, 8, AU_D5, 8, AU_F5, 30, 0, 0
ff_win_bass:
        .db     AU_AS2, 24, AU_AS3, 30, 0, 0
ff_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     ff_lose_melody, ff_lose_harmony, ff_lose_bass
ff_lose_melody:
        .db     AU_F5, 12, AU_DS5, 12, AU_CS5, 12, AU_C5, 30, 0, 0
ff_lose_harmony:
        .db     AU_CS5, 12, AU_C5, 12, AU_AS4, 12, AU_A4, 30, 0, 0
ff_lose_bass:
        .db     AU_AS2, 36, AU_F2, 30, 0, 0

        .include "art.inc"
        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys.inc"
        .include "../../../sdk/gfx.inc"
        .include "../../../sdk/font.inc"
        .include "../../../sdk/pcg.inc"
        .include "../../../sdk/frame.inc"
        .include "../../../sdk/math.inc"
        .include "../../../sdk/sound.inc"
        .include "../../../sdk/audio.inc"
        .include "../../../sdk/audio_notes.inc"
        .include "../../../sdk/port.inc"
        .include "../../../sdk/font_data.inc"
