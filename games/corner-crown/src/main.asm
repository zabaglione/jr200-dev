; SPDX-License-Identifier: MIT
; CORNER CROWN for JR-200: a port of jr100dev games/corner_crown/rules.py 1.5.1.
; Legal moves, eight-direction flips, passing, the biggest-capture rival and
; the end rule (more discs wins, a tie loses) follow the upstream source.
        .filename.jr "CORNER-CROWN"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4740
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    1
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    21
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state: b[64], cursor, white, black, placed, placing, flip,
; flipping, flip_frame.
CC_B:               .equ    GAME_STATE
CC_CURSOR:          .equ    GAME_STATE + 64
CC_WHITE:           .equ    GAME_STATE + 65
CC_BLACK:           .equ    GAME_STATE + 66
CC_PLACED:          .equ    GAME_STATE + 67
CC_PLACING:         .equ    GAME_STATE + 68
CC_FLIP:            .equ    GAME_STATE + 69
CC_FLIPPING:        .equ    GAME_STATE + 70
CC_FRAME:           .equ    GAME_STATE + 71
; Rule work bytes.
CC_POS:             .equ    GAME_STATE + 80
CC_MARK:            .equ    GAME_STATE + 81
CC_APPLY:           .equ    GAME_STATE + 82
CC_TOTAL:           .equ    GAME_STATE + 83
CC_DIR:             .equ    GAME_STATE + 84
CC_COUNT:           .equ    GAME_STATE + 85
CC_P:               .equ    GAME_STATE + 86
CC_K:               .equ    GAME_STATE + 87
CC_PHASE:           .equ    GAME_STATE + 88
CC_BEST:            .equ    GAME_STATE + 89
CC_CHOSEN:          .equ    GAME_STATE + 90
CC_SCAN:            .equ    GAME_STATE + 91
CC_SCAN2:           .equ    GAME_STATE + 92
CC_AVMARK:          .equ    GAME_STATE + 93
CC_RX:              .equ    GAME_STATE + 94
CC_RY:              .equ    GAME_STATE + 95
CC_RPOS:            .equ    GAME_STATE + 96
RC_POS:             .equ    GAME_STATE + 97
RC_DIR:             .equ    GAME_STATE + 98
RC_MARK:            .equ    GAME_STATE + 99
RC_P:               .equ    GAME_STATE + 100
RC_N:               .equ    GAME_STATE + 101
RC_K:               .equ    GAME_STATE + 102
CC_COL:             .equ    GAME_STATE + 103
CC_RAYDIR:          .equ    GAME_STATE + 104
; Drawing work bytes.
CC_DI:              .equ    GAME_STATE + 112
CC_DX:              .equ    GAME_STATE + 113
CC_DY:              .equ    GAME_STATE + 114
CC_DCODE:           .equ    GAME_STATE + 115
CC_DK:              .equ    GAME_STATE + 116

CC_TILE_EMPTY:      .equ    0x80
CC_TILE_CORNER:     .equ    0x84
CC_TILE_YOU:        .equ    0x88
CC_TILE_RIVAL:      .equ    0x8c
CC_TILE_FLIP:       .equ    0x00
CC_ATTR_EMPTY:      .equ    0x60
CC_ATTR_CORNER:     .equ    0x66
CC_ATTR_YOU:        .equ    0x67
CC_ATTR_RIVAL:      .equ    0x60
CC_ATTR_FLIP:       .equ    0x66
CC_ATTR_CURSOR:     .equ    0x26
CC_ATTR_TEXT:       .equ    0x07
CC_ATTR_LABEL:      .equ    0x04
CC_ATTR_TITLE:      .equ    0x06

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_font_install
        LDX     cc_patterns
        LDAA    CC_TILE_EMPTY
        LDAB    16
        JSR     jr_pcg_load
        LDAA    1
        JSR     cc_flip_face
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        LDAA    2
        STAA    [CC_B + 27]
        STAA    [CC_B + 36]
        LDAA    1
        STAA    [CC_B + 28]
        STAA    [CC_B + 35]
        LDAA    19
        STAA    [CC_CURSOR]
        JMP     cc_totals

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     cc_place
        BCC     cc_act_done
        JSR     cc_move
cc_act_done:
        RTS

; A = action 1-4: move(cursor, action, 8, 8).
cc_move:
        LDAB    [CC_CURSOR]
        CMPA    JR_KEY_UP
        BNE     cc_move_down
        CMPB    8
        BCS     cc_act_done
        SUBB    8
        BRA     cc_move_store
cc_move_down:
        CMPA    JR_KEY_DOWN
        BNE     cc_move_left
        CMPB    56
        BCC     cc_act_done
        ADDB    8
        BRA     cc_move_store
cc_move_left:
        STAB    [CC_COL]
        ANDB    7
        CMPA    JR_KEY_LEFT
        BNE     cc_move_right
        TSTB
        BEQ     cc_act_done
        DEC     [CC_COL]
        BRA     cc_move_col
cc_move_right:
        CMPB    7
        BCC     cc_act_done
        INC     [CC_COL]
cc_move_col:
        LDAB    [CC_COL]
cc_move_store:
        STAB    [CC_CURSOR]
        RTS

cc_place:
        LDAA    [CC_CURSOR]
        LDAB    1
        JSR     cc_probe
        TSTA
        BNE     cc_place_legal
        LDAA    1
        JSR     cc_available
        TSTA
        BEQ     cc_rival
        LDAA    3
        JMP     jr_port_sound
cc_place_legal:
        LDAA    [CC_CURSOR]
        LDAB    1
        JSR     cc_commit
; The rival takes the first square with the most flips.
cc_rival:
        CLR     [CC_BEST]
        LDAA    0xff
        STAA    [CC_CHOSEN]
        CLR     [CC_SCAN2]
cc_rival_scan:
        LDAA    [CC_SCAN2]
        LDAB    2
        JSR     cc_probe
        CMPA    [CC_BEST]
        BLS     cc_rival_next
        STAA    [CC_BEST]
        LDAA    [CC_SCAN2]
        STAA    [CC_CHOSEN]
cc_rival_next:
        INC     [CC_SCAN2]
        LDAA    [CC_SCAN2]
        CMPA    64
        BNE     cc_rival_scan
        LDAA    [CC_CHOSEN]
        CMPA    0xff
        BEQ     cc_rival_done
        LDAB    2
        JSR     cc_commit
cc_rival_done:
        JSR     cc_totals
        LDAA    1
        JSR     jr_port_sound
        LDAA    1
        JSR     cc_available
        TSTA
        BNE     cc_rival_return
        LDAA    2
        JSR     cc_available
        TSTA
        BNE     cc_rival_return
        LDAA    [CC_WHITE]
        CMPA    [CC_BLACK]
        BLS     cc_lost
        JMP     jr_port_win
cc_lost:
        LDX     0
        JMP     jr_port_lose
cc_rival_return:
        RTS

; A = position, B = mark: flips(pos, mark, 0).
cc_probe:
        STAA    [CC_POS]
        STAB    [CC_MARK]
        CLR     [CC_APPLY]
        JMP     cc_flips

; A = position, B = mark: flips(pos, mark, 1) with the upstream effects.
cc_commit:
        STAA    [CC_POS]
        STAB    [CC_MARK]
        LDAA    1
        STAA    [CC_APPLY]

cc_flips:
        LDX     CC_B
        LDAA    [CC_POS]
        JSR     jr_add_x_a
        TST     [X]
        BEQ     cc_flips_empty
        CLRA
        RTS
cc_flips_empty:
        TST     [CC_APPLY]
        BEQ     cc_flips_scan
        LDAA    [CC_POS]
        STAA    [CC_PLACED]
        LDAA    [CC_MARK]
        STAA    [CC_PLACING]
        CLRA
        JSR     jr_port_sound
        LDAA    8
        JSR     jr_port_animate
cc_flips_scan:
        CLR     [CC_TOTAL]
        CLR     [CC_DIR]
cc_flips_direction:
        LDAA    [CC_POS]
        STAA    [RC_POS]
        LDAA    [CC_DIR]
        STAA    [RC_DIR]
        LDAA    [CC_MARK]
        STAA    [RC_MARK]
        JSR     cc_ray_count
        STAA    [CC_COUNT]
        ADDA    [CC_TOTAL]
        STAA    [CC_TOTAL]
        TST     [CC_APPLY]
        BEQ     cc_flips_next
        LDAA    [CC_POS]
        STAA    [CC_P]
        LDAA    [CC_COUNT]
        STAA    [CC_K]
cc_flips_disc:
        TST     [CC_K]
        BEQ     cc_flips_next
        LDAA    [CC_P]
        LDAB    [CC_DIR]
        JSR     cc_ray
        STAA    [CC_P]
        STAA    [CC_FLIP]
        LDAA    1
        STAA    [CC_FLIPPING]
        CLR     [CC_PHASE]
cc_flips_phase:
        LDAA    [CC_PHASE]
        LDAB    [CC_MARK]
        CMPB    2
        BNE     cc_flips_to_you
        INCA
        BRA     cc_flips_frame
cc_flips_to_you:
        NEGA
        ADDA    5
cc_flips_frame:
        STAA    [CC_FRAME]
        JSR     cc_flip_face
        LDAA    3
        TST     [CC_PHASE]
        BNE     cc_flips_hold
        JSR     jr_port_animate
        BRA     cc_flips_phase_next
cc_flips_hold:
        JSR     jr_port_hold
cc_flips_phase_next:
        INC     [CC_PHASE]
        LDAA    [CC_PHASE]
        CMPA    5
        BNE     cc_flips_phase
        LDX     CC_B
        LDAA    [CC_P]
        JSR     jr_add_x_a
        LDAA    [CC_MARK]
        STAA    [X]
        CLR     [CC_FLIPPING]
        JSR     cc_totals
        CLRA
        JSR     jr_port_sound
        LDAA    4
        JSR     jr_port_animate
        DEC     [CC_K]
        JMP     cc_flips_disc
cc_flips_next:
        INC     [CC_DIR]
        LDAA    [CC_DIR]
        CMPA    8
        BEQ     cc_flips_finish
        JMP     cc_flips_direction
cc_flips_finish:
        TST     [CC_APPLY]
        BEQ     cc_flips_done
        TST     [CC_TOTAL]
        BEQ     cc_flips_done
        LDX     CC_B
        LDAA    [CC_POS]
        JSR     jr_add_x_a
        LDAA    [CC_MARK]
        STAA    [X]
        CLR     [CC_PLACING]
        JSR     cc_totals
        LDAA    10
        JSR     jr_port_animate
cc_flips_done:
        LDAA    [CC_TOTAL]
        RTS

; RC_POS, RC_DIR, RC_MARK -> A = discs bracketed in that direction.
cc_ray_count:
        LDAA    [RC_POS]
        LDAB    [RC_DIR]
        JSR     cc_ray
        STAA    [RC_P]
        CLR     [RC_N]
        LDAA    7
        STAA    [RC_K]
cc_ray_count_step:
        LDAA    [RC_P]
        CMPA    0xff
        BEQ     cc_ray_count_zero
        LDX     CC_B
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     cc_ray_count_zero
        CMPA    [RC_MARK]
        BEQ     cc_ray_count_found
        INC     [RC_N]
        LDAA    [RC_P]
        LDAB    [RC_DIR]
        JSR     cc_ray
        STAA    [RC_P]
        DEC     [RC_K]
        BNE     cc_ray_count_step
cc_ray_count_zero:
        CLRA
        RTS
cc_ray_count_found:
        LDAA    [RC_N]
        RTS

; A = position, B = direction 0-7 -> A = neighbour or 0xFF off the board.
cc_ray:
        STAA    [CC_RPOS]
        STAB    [CC_RAYDIR]
        TAB
        ANDB    7
        STAB    [CC_RX]
        LSRA
        LSRA
        LSRA
        STAA    [CC_RY]
        LDAA    [CC_RAYDIR]
        BEQ     cc_ray_east
        CMPA    1
        BEQ     cc_ray_west
        CMPA    2
        BEQ     cc_ray_south
        CMPA    3
        BEQ     cc_ray_north
        CMPA    4
        BEQ     cc_ray_southeast
        CMPA    5
        BEQ     cc_ray_northwest
        CMPA    6
        BEQ     cc_ray_southwest
        BRA     cc_ray_northeast
cc_ray_east:
        LDAA    [CC_RX]
        CMPA    7
        BCC     cc_ray_none
        LDAA    1
        BRA     cc_ray_add
cc_ray_west:
        TST     [CC_RX]
        BEQ     cc_ray_none
        LDAA    0xff
        BRA     cc_ray_add
cc_ray_south:
        LDAA    [CC_RY]
        CMPA    7
        BCC     cc_ray_none
        LDAA    8
        BRA     cc_ray_add
cc_ray_north:
        TST     [CC_RY]
        BEQ     cc_ray_none
        LDAA    0xf8
        BRA     cc_ray_add
cc_ray_southeast:
        LDAA    [CC_RX]
        CMPA    7
        BCC     cc_ray_none
        LDAA    [CC_RY]
        CMPA    7
        BCC     cc_ray_none
        LDAA    9
        BRA     cc_ray_add
cc_ray_northwest:
        TST     [CC_RX]
        BEQ     cc_ray_none
        TST     [CC_RY]
        BEQ     cc_ray_none
        LDAA    0xf7
        BRA     cc_ray_add
cc_ray_southwest:
        TST     [CC_RX]
        BEQ     cc_ray_none
        LDAA    [CC_RY]
        CMPA    7
        BCC     cc_ray_none
        LDAA    7
        BRA     cc_ray_add
cc_ray_northeast:
        LDAA    [CC_RX]
        CMPA    7
        BCC     cc_ray_none
        TST     [CC_RY]
        BEQ     cc_ray_none
        LDAA    0xf9
cc_ray_add:
        ADDA    [CC_RPOS]
        RTS
cc_ray_none:
        LDAA    0xff
        RTS

; A = mark -> A = 1 when the mark has any legal move.
cc_available:
        STAA    [CC_AVMARK]
        CLR     [CC_SCAN]
cc_available_scan:
        LDAA    [CC_SCAN]
        LDAB    [CC_AVMARK]
        JSR     cc_probe
        TSTA
        BNE     cc_available_yes
        INC     [CC_SCAN]
        LDAA    [CC_SCAN]
        CMPA    64
        BNE     cc_available_scan
        CLRA
        RTS
cc_available_yes:
        LDAA    1
        RTS

cc_totals:
        CLR     [CC_WHITE]
        CLR     [CC_BLACK]
        LDX     CC_B
cc_totals_loop:
        LDAA    [X]
        CMPA    1
        BNE     cc_totals_black
        INC     [CC_WHITE]
cc_totals_black:
        CMPA    2
        BNE     cc_totals_next
        INC     [CC_BLACK]
cc_totals_next:
        INX
        CPX     CC_B + 64
        BNE     cc_totals_loop
        RTS

; A = pose 1-5: load the pose into user codes 0x00-0x03 (upstream flip()).
cc_flip_face:
        DECA
        ASLA
        ASLA
        ASLA
        ASLA
        ASLA
        LDX     cc_poses
        JSR     jr_add_x_a
        LDAA    CC_TILE_FLIP
        LDAB    4
        JMP     jr_pcg_load

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    CC_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cc_hud
        JSR     jr_gfx_lines
        CLR     [CC_DI]
cc_draw_cell:
        LDX     CC_B
        LDAA    [CC_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        BNE     cc_draw_disc
        LDAA    [CC_DI]
        JSR     cc_is_corner
        BEQ     cc_draw_corner
        LDAA    CC_TILE_EMPTY
        LDAB    CC_ATTR_EMPTY
        BRA     cc_draw_tile
cc_draw_corner:
        LDAA    CC_TILE_CORNER
        LDAB    CC_ATTR_CORNER
        BRA     cc_draw_tile
cc_draw_disc:
        JSR     cc_disc_tile
cc_draw_tile:
        STAA    [CC_DCODE]
        STAB    [JR_RT_COLOR]
        LDAA    [CC_DI]
        JSR     cc_cell_at
        LDAA    [CC_DCODE]
        JSR     jr_gfx_tile
        INC     [CC_DI]
        LDAA    [CC_DI]
        CMPA    64
        BNE     cc_draw_cell
        TST     [CC_PLACING]
        BEQ     cc_draw_flip
        LDAA    [CC_PLACING]
        JSR     cc_disc_tile
        STAA    [CC_DCODE]
        STAB    [JR_RT_COLOR]
        LDAA    [CC_PLACED]
        JSR     cc_cell_at
        LDAA    [CC_DCODE]
        JSR     jr_gfx_tile
cc_draw_flip:
        TST     [CC_FLIPPING]
        BEQ     cc_draw_cursor
        LDAA    CC_ATTR_FLIP
        STAA    [JR_RT_COLOR]
        LDAA    [CC_FLIP]
        JSR     cc_cell_at
        LDAA    CC_TILE_FLIP
        JSR     jr_gfx_tile
cc_draw_cursor:
        LDAA    CC_ATTR_CURSOR
        STAA    [JR_RT_COLOR]
        LDAA    [CC_CURSOR]
        JSR     cc_cell_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDAA    CC_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [CC_WHITE]
        JSR     jr_gfx_dec3
        LDAA    24
        LDAB    14
        JSR     jr_gfx_at
        LDAA    [CC_BLACK]
        JMP     jr_gfx_dec3

; A = mark 1/2 -> A = tile code, B = attribute.
cc_disc_tile:
        CMPA    1
        BNE     cc_disc_rival
        LDAA    CC_TILE_YOU
        LDAB    CC_ATTR_YOU
        RTS
cc_disc_rival:
        LDAA    CC_TILE_RIVAL
        LDAB    CC_ATTR_RIVAL
        RTS

; A = position -> Z set for the four corners.
cc_is_corner:
        CMPA    0
        BEQ     cc_is_corner_done
        CMPA    7
        BEQ     cc_is_corner_done
        CMPA    56
        BEQ     cc_is_corner_done
        CMPA    63
cc_is_corner_done:
        RTS

; A = position -> cursor at (pos % 8 * 2, 3 + pos // 8 * 2).
cc_cell_at:
        TAB
        ANDA    7
        ASLA
        LSRB
        LSRB
        LSRB
        ASLB
        ADDB    3
        JMP     jr_gfx_at

game_draw_title:
        LDAA    0x20
        LDAB    CC_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cc_title_tiles
        STX     [JR_RT_TABLE]
cc_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     cc_title_text
        LDAB    [X + 3]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 1]
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        LDAA    [X + 2]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     cc_title_tile
cc_title_text:
        LDX     cc_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    CC_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cc_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

cc_hud:
        .db     1, 0, CC_ATTR_TITLE
        .dw     cc_txt_name
        .db     19, 3, CC_ATTR_LABEL
        .dw     cc_txt_match
        .db     20, 6, CC_ATTR_LABEL
        .dw     cc_txt_you
        .db     20, 13, CC_ATTR_LABEL
        .dw     cc_txt_rival
        .db     18, 17, 0x03
        .dw     cc_txt_corner_hint
        .db     0xff

; column, row, tile, attribute
cc_title_tiles:
        .db     11, 3, CC_TILE_CORNER, CC_ATTR_CORNER
        .db     13, 3, CC_TILE_YOU, CC_ATTR_YOU
        .db     15, 3, CC_TILE_RIVAL, CC_ATTR_RIVAL
        .db     17, 3, CC_TILE_CORNER, CC_ATTR_CORNER
        .db     11, 5, CC_TILE_RIVAL, CC_ATTR_RIVAL
        .db     13, 5, CC_TILE_EMPTY, CC_ATTR_EMPTY
        .db     15, 5, CC_TILE_EMPTY, CC_ATTR_EMPTY
        .db     17, 5, CC_TILE_YOU, CC_ATTR_YOU
        .db     0xff
cc_title_lines:
        .db     10, 9, CC_ATTR_TITLE
        .dw     cc_txt_name
        .db     5, 11, CC_ATTR_LABEL
        .dw     cc_txt_tagline
        .db     8, 15, CC_ATTR_TEXT
        .dw     cc_txt_start
        .db     5, 17, CC_ATTR_TEXT
        .dw     cc_txt_howto
        .db     4, 22, 0x01
        .dw     cc_txt_credit
        .db     0xff
cc_help_lines:
        .db     9, 2, CC_ATTR_TITLE
        .dw     cc_txt_name
        .db     2, 5, CC_ATTR_TEXT
        .dw     cc_help_1
        .db     2, 7, CC_ATTR_TEXT
        .dw     cc_help_2
        .db     2, 9, CC_ATTR_TEXT
        .dw     cc_help_3
        .db     2, 11, CC_ATTR_TEXT
        .dw     cc_help_4
        .db     2, 13, CC_ATTR_TEXT
        .dw     cc_help_5
        .db     2, 15, CC_ATTR_TEXT
        .dw     cc_help_6
        .db     2, 17, CC_ATTR_TEXT
        .dw     cc_help_7
        .db     2, 20, CC_ATTR_LABEL
        .dw     cc_help_back
        .db     0xff

cc_txt_name:
        .db     "CORNER CROWN", 0
cc_txt_match:
        .db     "CROWN MATCH", 0
cc_txt_you:
        .db     "YOU  (O)", 0
cc_txt_rival:
        .db     "RIVAL(@)", 0
cc_txt_corner_hint:
        .db     "+ CORNERS", 0
cc_txt_tagline:
        .db     "BRACKET AND FLIP DISCS", 0
cc_txt_start:
        .db     "RETURN : START", 0
cc_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
cc_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
cc_help_1:
        .db     "WASD : CHOOSE A CELL", 0
cc_help_2:
        .db     "RETURN : PLACE AND FLIP", 0
cc_help_3:
        .db     "BRACKET RIVAL DISCS TO FLIP.", 0
cc_help_4:
        .db     "MORE DISCS AT THE END WINS.", 0
cc_help_5:
        .db     "RETURN PASSES IF NO MOVE.", 0
cc_help_6:
        .db     "THE RIVAL FAVORS BIG CAPTURES", 0
cc_help_7:
        .db     "SPACE RESTART / CTRL+C EXIT", 0
cc_help_back:
        .db     "ANY KEY : TITLE", 0

game_sfx_table:
        .dw     cc_sfx_flip, cc_sfx_turn, cc_sfx_win, cc_sfx_lose
cc_sfx_flip:
        .db     80, 1, 0, 0
cc_sfx_turn:
        .db     140, 2, 110, 3, 0, 0
cc_sfx_win:
        .db     120, 6, 95, 6, 80, 6, 60, 14, 0, 0
cc_sfx_lose:
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
