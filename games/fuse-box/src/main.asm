; SPDX-License-Identifier: MIT
; FUSE BOX for JR-200: a port of jr100dev games/fuse_box/rules.py 1.6.1.
; Panel generation, the row/column count rule and the flip sequence follow
; the upstream source; display, colour and three-voice sound use the SDK.
        .filename.jr "FUSE-BOX"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    10
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    21
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state: b[25] switches, d[25] target, s.cursor, s.moves,
; s.flipping, s.flip_frame.
FB_B:               .equ    GAME_STATE
FB_D:               .equ    GAME_STATE + 25
FB_CURSOR:          .equ    GAME_STATE + 50
FB_MOVES:           .equ    GAME_STATE + 51
FB_FLIPPING:        .equ    GAME_STATE + 52
FB_FRAME:           .equ    GAME_STATE + 53
; Rule work bytes.
FB_I:               .equ    GAME_STATE + 56
FB_J:               .equ    GAME_STATE + 57
FB_PHASE:           .equ    GAME_STATE + 58
FB_OK:              .equ    GAME_STATE + 59
FB_MP:              .equ    GAME_STATE + 60
FB_MA:              .equ    GAME_STATE + 61
FB_MC:              .equ    GAME_STATE + 62
FB_ROW:             .equ    GAME_STATE + 63
FB_WANT:            .equ    GAME_STATE + 64
FB_COL:             .equ    GAME_STATE + 65
FB_GOAL:            .equ    GAME_STATE + 66
; Drawing work bytes.
FB_DI:              .equ    GAME_STATE + 72
FB_DK:              .equ    GAME_STATE + 73
FB_DCODE:           .equ    GAME_STATE + 74
FB_DROW:            .equ    GAME_STATE + 75
FB_DCOL:            .equ    GAME_STATE + 76
FB_DFROW:           .equ    GAME_STATE + 77
FB_DFCOL:           .equ    GAME_STATE + 78
FB_DJ:              .equ    GAME_STATE + 79

FB_TILE_OFF:        .equ    0x80
FB_TILE_ON:         .equ    0x84
FB_ATTR_OFF:        .equ    0x41        ; blue socket
FB_ATTR_ON:         .equ    0x46        ; yellow lit fuse
FB_ATTR_FLIP:       .equ    0x47        ; white while turning
FB_ATTR_CLUE:       .equ    0x07        ; white digit on black
FB_ATTR_MATCH:      .equ    0x20        ; black digit on green: count matched
FB_ATTR_TEXT:       .equ    0x07
FB_ATTR_LABEL:      .equ    0x04
FB_ATTR_TITLE:      .equ    0x06
FB_ATTR_DIM:        .equ    0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     fb_patterns
        LDAA    FB_TILE_OFF
        LDAB    20
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; d[i] = 1 if (i * 3 + i // 5 + level) % 7 < 3 else 0
game_init:
        JSR     jr_music_stop
        CLR     [FB_I]
fb_init_cell:
        LDAA    [FB_I]
        LDAB    5
        JSR     jr_divmod8
        STAA    [FB_J]
        LDAA    [FB_I]
        ASLA
        ADDA    [FB_I]
        ADDA    [FB_J]
        ADDA    [JR_PORT_LEVEL]
        LDAB    7
        JSR     jr_divmod8
        CLRA
        CMPB    3
        BCC     fb_init_store
        INCA
fb_init_store:
        PSHA
        LDAA    [FB_I]
        LDX     FB_D
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        INC     [FB_I]
        LDAA    [FB_I]
        CMPA    25
        BNE     fb_init_cell
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     fb_flip
        BCC     fb_act_done
        TAB
        LDAA    [FB_CURSOR]
        JSR     fb_move
        STAA    [FB_CURSOR]
fb_act_done:
        RTS

fb_flip:
        LDAA    1
        STAA    [FB_FLIPPING]
        CLRA
        JSR     jr_port_sound
        CLR     [FB_PHASE]
fb_flip_phase:
        ; flip_frame = phase + 1 if b[cursor] == 0 else 5 - phase
        LDAA    [FB_CURSOR]
        LDX     FB_B
        JSR     jr_add_x_a
        LDAA    [FB_PHASE]
        TST     [X]
        BNE     fb_flip_down
        INCA
        BRA     fb_flip_store
fb_flip_down:
        NEGA
        ADDA    5
fb_flip_store:
        STAA    [FB_FRAME]
        LDAA    3
        TST     [FB_PHASE]
        BNE     fb_flip_hold
        JSR     jr_port_animate
        BRA     fb_flip_next
fb_flip_hold:
        JSR     jr_port_hold
fb_flip_next:
        INC     [FB_PHASE]
        LDAA    [FB_PHASE]
        CMPA    5
        BNE     fb_flip_phase
        LDAA    [FB_CURSOR]
        LDX     FB_B
        JSR     jr_add_x_a
        LDAA    [X]
        EORA    1
        STAA    [X]
        CLR     [FB_FLIPPING]
        INC     [FB_MOVES]
        ; correct when every row and column count equals the target's
        CLR     [FB_I]
fb_check_line:
        LDAA    [FB_I]
        JSR     fb_line_counts
        LDAA    [FB_ROW]
        CMPA    [FB_WANT]
        BNE     fb_check_wrong
        LDAA    [FB_COL]
        CMPA    [FB_GOAL]
        BNE     fb_check_wrong
        INC     [FB_I]
        LDAA    [FB_I]
        CMPA    5
        BNE     fb_check_line
        JSR     jr_port_win
fb_check_wrong:
        LDAA    1
        JMP     jr_port_sound

; A = line i. Output FB_ROW = sum b[i*5+j], FB_WANT = sum d[i*5+j],
; FB_COL = sum b[j*5+i], FB_GOAL = sum d[j*5+i].
fb_line_counts:
        STAA    [FB_MC]
        CLR     [FB_ROW]
        CLR     [FB_WANT]
        CLR     [FB_COL]
        CLR     [FB_GOAL]
        LDAB    5
        JSR     jr_mul8                 ; A = i * 5
        LDX     FB_B
        JSR     jr_add_x_a
        LDAB    5
fb_count_row:
        LDAA    [X]
        ADDA    [FB_ROW]
        STAA    [FB_ROW]
        LDAA    [X + 25]
        ADDA    [FB_WANT]
        STAA    [FB_WANT]
        INX
        DECB
        BNE     fb_count_row
        LDAA    [FB_MC]
        LDX     FB_B
        JSR     jr_add_x_a
        LDAB    5
fb_count_col:
        LDAA    [X]
        ADDA    [FB_COL]
        STAA    [FB_COL]
        LDAA    [X + 25]
        ADDA    [FB_GOAL]
        STAA    [FB_GOAL]
        INX
        INX
        INX
        INX
        INX
        DECB
        BNE     fb_count_col
        RTS

; A = position, B = action 1-4 -> A = moved position (5x5, stops at edges).
fb_move:
        STAA    [FB_MP]
        STAB    [FB_MA]
        LDAB    5
        JSR     jr_divmod8
        STAB    [FB_MC]
        LDAA    [FB_MP]
        LDAB    [FB_MA]
        CMPB    JR_KEY_UP
        BNE     fb_move_down
        CMPA    5
        BCS     fb_move_done
        SUBA    5
        RTS
fb_move_down:
        CMPB    JR_KEY_DOWN
        BNE     fb_move_left
        CMPA    20
        BCC     fb_move_done
        ADDA    5
        RTS
fb_move_left:
        CMPB    JR_KEY_LEFT
        BNE     fb_move_right
        TST     [FB_MC]
        BEQ     fb_move_done
        DECA
        RTS
fb_move_right:
        CMPB    JR_KEY_RIGHT
        BNE     fb_move_done
        LDAB    [FB_MC]
        CMPB    4
        BCC     fb_move_done
        INCA
fb_move_done:
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    FB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     fb_hud
        JSR     jr_gfx_lines
        LDAA    FB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; switches at (5 + i % 5 * 3, 5 + i // 5 * 3)
        CLR     [FB_DI]
fb_draw_cell:
        LDAA    [FB_DI]
        LDX     FB_B
        JSR     jr_add_x_a
        LDAA    FB_TILE_OFF
        LDAB    FB_ATTR_OFF
        TST     [X]
        BEQ     fb_draw_pose
        LDAA    FB_TILE_ON
        LDAB    FB_ATTR_ON
fb_draw_pose:
        TST     [FB_FLIPPING]
        BEQ     fb_draw_tile
        PSHA
        LDAA    [FB_DI]
        CMPA    [FB_CURSOR]
        PULA
        BNE     fb_draw_tile
        LDX     fb_pose_codes - 1
        LDAA    [FB_FRAME]
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    FB_ATTR_FLIP
fb_draw_tile:
        STAA    [FB_DCODE]
        STAB    [JR_RT_COLOR]
        LDAA    [FB_DI]
        JSR     fb_cell_xy
        JSR     jr_gfx_at
        LDAA    [FB_DCODE]
        JSR     jr_gfx_tile
        INC     [FB_DI]
        LDAA    [FB_DI]
        CMPA    25
        BNE     fb_draw_cell
        ; cursor '>' at (4 + i % 5 * 3, 5 + i // 5 * 3)
        LDAA    FB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [FB_CURSOR]
        JSR     fb_cell_xy
        DECA
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        ; clues: row count at (2, 5 + i * 3), column count at (5 + i * 3, 2)
        CLR     [FB_DI]
fb_draw_clue:
        LDAA    [FB_DI]
        JSR     fb_draw_counts
        LDAA    [FB_DI]
        ASLA
        ADDA    [FB_DI]
        ADDA    5
        STAA    [FB_DK]
        LDAA    [FB_DROW]
        LDAB    [FB_DFROW]
        JSR     fb_clue_color
        LDAA    2
        LDAB    [FB_DK]
        JSR     jr_gfx_at
        LDAA    [FB_DROW]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    [FB_DCOL]
        LDAB    [FB_DFCOL]
        JSR     fb_clue_color
        LDAA    [FB_DK]
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [FB_DCOL]
        ADDA    0x30
        JSR     jr_gfx_putc
        INC     [FB_DI]
        LDAA    [FB_DI]
        CMPA    5
        BNE     fb_draw_clue
        LDAA    FB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    25
        LDAB    10
        JSR     jr_gfx_at
        LDAA    [FB_MOVES]
        JMP     jr_gfx_dec3

; A = target count, B = filled count: matched clues are drawn inverted.
fb_clue_color:
        CBA
        BEQ     fb_clue_match
        LDAA    FB_ATTR_CLUE
        BRA     fb_clue_store
fb_clue_match:
        LDAA    FB_ATTR_MATCH
fb_clue_store:
        STAA    [JR_RT_COLOR]
        RTS

; A = line. Drawing-side counts: FB_DROW/FB_DCOL targets, FB_DFROW/FB_DFCOL filled.
fb_draw_counts:
        STAA    [FB_DJ]
        CLR     [FB_DROW]
        CLR     [FB_DCOL]
        CLR     [FB_DFROW]
        CLR     [FB_DFCOL]
        LDAB    5
        JSR     jr_mul8
        LDX     FB_B
        JSR     jr_add_x_a
        LDAB    5
fb_dcount_row:
        LDAA    [X]
        ADDA    [FB_DFROW]
        STAA    [FB_DFROW]
        LDAA    [X + 25]
        ADDA    [FB_DROW]
        STAA    [FB_DROW]
        INX
        DECB
        BNE     fb_dcount_row
        LDAA    [FB_DJ]
        LDX     FB_B
        JSR     jr_add_x_a
        LDAB    5
fb_dcount_col:
        LDAA    [X]
        ADDA    [FB_DFCOL]
        STAA    [FB_DFCOL]
        LDAA    [X + 25]
        ADDA    [FB_DCOL]
        STAA    [FB_DCOL]
        INX
        INX
        INX
        INX
        INX
        DECB
        BNE     fb_dcount_col
        RTS

; A = cell -> A = 5 + cell % 5 * 3, B = 5 + cell // 5 * 3.
fb_cell_xy:
        LDAB    5
        JSR     jr_divmod8
        STAB    [FB_DK]
        TAB
        ASLA
        ABA
        ADDA    5
        TAB
        LDAA    [FB_DK]
        STAB    [FB_DK]
        TAB
        ASLA
        ABA
        ADDA    5
        LDAB    [FB_DK]
        RTS

game_draw_title:
        LDX     fb_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    FB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     fb_title_tiles
        STX     [JR_RT_TABLE]
fb_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     fb_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [FB_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [FB_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     fb_title_tile
fb_title_text:
        LDX     fb_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    FB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     fb_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; flip_frame 1-5: off, off narrowing, edge, on narrowing, on.
fb_pose_codes:
        .db     0x80, 0x88, 0x8c, 0x90, 0x84

fb_hud:
        .db     1, 0, FB_ATTR_TITLE
        .dw     fb_txt_name
        .db     23, 0, FB_ATTR_LABEL
        .dw     fb_txt_stage
        .db     22, 3, FB_ATTR_LABEL
        .dw     fb_txt_matrix
        .db     22, 9, FB_ATTR_LABEL
        .dw     fb_txt_flips
        .db     21, 14, FB_ATTR_TITLE
        .dw     fb_txt_key_on
        .db     21, 15, FB_ATTR_TEXT
        .dw     fb_txt_key_off
        .db     21, 16, FB_ATTR_MATCH
        .dw     fb_txt_key_match
        .db     0xff

; x, attribute, tile, y
fb_title_tiles:
        .db     7, FB_ATTR_ON, FB_TILE_ON, 3
        .db     10, FB_ATTR_OFF, FB_TILE_OFF, 3
        .db     13, FB_ATTR_ON, FB_TILE_ON, 3
        .db     16, FB_ATTR_FLIP, 0x8c, 3
        .db     19, FB_ATTR_OFF, FB_TILE_OFF, 3
        .db     22, FB_ATTR_ON, FB_TILE_ON, 3
        .db     0xff
fb_title_lines:
        .db     12, 8, FB_ATTR_TITLE
        .dw     fb_txt_name
        .db     4, 10, FB_ATTR_LABEL
        .dw     fb_txt_tagline
        .db     8, 15, FB_ATTR_TEXT
        .dw     fb_txt_start
        .db     5, 17, FB_ATTR_TEXT
        .dw     fb_txt_howto
        .db     4, 22, FB_ATTR_DIM
        .dw     fb_txt_credit
        .db     0xff
fb_help_lines:
        .db     11, 2, FB_ATTR_TITLE
        .dw     fb_txt_name
        .db     1, 5, FB_ATTR_TEXT
        .dw     fb_help_1
        .db     1, 7, FB_ATTR_TEXT
        .dw     fb_help_2
        .db     1, 9, FB_ATTR_TEXT
        .dw     fb_help_3
        .db     1, 11, FB_ATTR_TEXT
        .dw     fb_help_4
        .db     1, 13, FB_ATTR_TEXT
        .dw     fb_help_5
        .db     1, 15, FB_ATTR_TEXT
        .dw     fb_help_6
        .db     1, 17, FB_ATTR_TEXT
        .dw     fb_help_7
        .db     1, 19, FB_ATTR_TEXT
        .dw     fb_help_8
        .db     1, 21, FB_ATTR_LABEL
        .dw     fb_help_back
        .db     0xff

fb_txt_name:
        .db     "FUSE BOX", 0
fb_txt_stage:
        .db     "STAGE", 0
fb_txt_matrix:
        .db     "MATRIX", 0
fb_txt_flips:
        .db     "FLIPS", 0
fb_txt_key_on:
        .db     "ON  LIT", 0
fb_txt_key_off:
        .db     "OFF DARK", 0
fb_txt_key_match:
        .db     "MATCH", 0
fb_txt_tagline:
        .db     "MATCH EVERY ROW AND COLUMN", 0
fb_txt_start:
        .db     "RETURN : START", 0
fb_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
fb_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
fb_help_1:
        .db     "WASD : SELECT A SWITCH", 0
fb_help_2:
        .db     "RETURN : ON OR OFF", 0
fb_help_3:
        .db     "MATCH THE COUNT IN EVERY ROW", 0
fb_help_4:
        .db     "AND THE COUNT IN EVERY COLUMN.", 0
fb_help_5:
        .db     "ANY MATCHING WIRING IS VALID.", 0
fb_help_6:
        .db     "MATCHED COUNTS TURN GREEN.", 0
fb_help_7:
        .db     "SPACE : CLEAR THE PANEL", 0
fb_help_8:
        .db     "CTRL+C : BACK TO BASIC", 0
fb_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     fb_sfx_click, fb_sfx_set, fb_jingle_win, fb_jingle_lose
fb_sfx_click:
        .db     40, 2, 0, 0
fb_sfx_set:
        .db     80, 2, 0, 1, 60, 3, 0, 0

; Title: four bars in E minor, eighth note = 12 frames, looping.
fb_title_song:
        .db     1
        .dw     fb_title_melody, fb_title_harmony, fb_title_bass
fb_title_melody:
        .db     AU_E5, 12, AU_G5, 12, AU_B5, 12, AU_E6, 12, AU_D6, 24, AU_B5, 24
        .db     AU_C6, 12, AU_B5, 12, AU_A5, 12, AU_G5, 12, AU_FS5, 24, AU_D5, 24
        .db     AU_E5, 12, AU_G5, 12, AU_B5, 12, AU_E6, 12, AU_FS6, 24, AU_D6, 24
        .db     AU_E6, 72, 0, 24, 0, 0
fb_title_harmony:
        .db     AU_B4, 48, AU_G4, 48, AU_A4, 48, AU_FS4, 48
        .db     AU_B4, 48, AU_A4, 48, AU_B4, 72, 0, 24, 0, 0
fb_title_bass:
        .db     AU_E3, 18, 0, 6, AU_E3, 18, 0, 6, AU_E3, 18, 0, 6, AU_E3, 18, 0, 6
        .db     AU_C3, 18, 0, 6, AU_C3, 18, 0, 6, AU_D3, 18, 0, 6, AU_D3, 18, 0, 6
        .db     AU_E3, 18, 0, 6, AU_E3, 18, 0, 6, AU_D3, 18, 0, 6, AU_D3, 18, 0, 6
        .db     AU_E2, 72, 0, 24, 0, 0

; Clear: rising E major arpeggio over a held tonic (54 frames).
fb_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     fb_win_melody, fb_win_harmony, fb_win_bass
fb_win_melody:
        .db     AU_E5, 8, AU_GS5, 8, AU_B5, 8, AU_E6, 30, 0, 0
fb_win_harmony:
        .db     AU_B4, 8, AU_E5, 8, AU_GS5, 8, AU_B5, 30, 0, 0
fb_win_bass:
        .db     AU_E3, 24, AU_E2, 30, 0, 0
fb_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     fb_lose_melody, fb_lose_harmony, fb_lose_bass
fb_lose_melody:
        .db     AU_B4, 12, AU_A4, 12, AU_G4, 12, AU_FS4, 30, 0, 0
fb_lose_harmony:
        .db     AU_D4, 12, AU_C4, 12, AU_B3, 12, AU_A3, 30, 0, 0
fb_lose_bass:
        .db     AU_B2, 36, AU_B2, 30, 0, 0

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
