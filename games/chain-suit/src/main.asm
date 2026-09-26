; SPDX-License-Identifier: MIT
; CHAIN SUIT for JR-200: a port of jr100dev games/chain_suit/rules.py 1.6.1.
; The dealt ranks and suits, redraws, hand evaluation and points follow the
; upstream source; display, colour and three-voice sound use the JR-200 port
; SDK.
        .filename.jr "CHAIN-SUIT"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    1
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then b[5], c[5], d[5].
CS_TARGET:          .equ    GAME_STATE
CS_ROUND:           .equ    GAME_STATE + 1
CS_DRAWS:           .equ    GAME_STATE + 2
CS_DISCARDS:        .equ    GAME_STATE + 3
CS_SCORING:         .equ    GAME_STATE + 4
CS_POINTS:          .equ    GAME_STATE + 5
CS_HAND:            .equ    GAME_STATE + 6
CS_CURSOR:          .equ    GAME_STATE + 7
CS_FLIPPING:        .equ    GAME_STATE + 8
CS_SCORE:           .equ    GAME_STATE + 9
CS_BLINK:           .equ    GAME_STATE + 10
CS_B:               .equ    GAME_STATE + 11
CS_C:               .equ    GAME_STATE + 16
CS_D:               .equ    GAME_STATE + 21
; Rule work bytes.
CS_I:               .equ    GAME_STATE + 32
CS_J:               .equ    GAME_STATE + 33
CS_COUNT:           .equ    GAME_STATE + 34
CS_PAIRS:           .equ    GAME_STATE + 35
CS_LARGEST:         .equ    GAME_STATE + 36
CS_SAME:            .equ    GAME_STATE + 37
CS_T:               .equ    GAME_STATE + 38
CS_K:               .equ    GAME_STATE + 39
; Drawing work bytes.
CS_DI:              .equ    GAME_STATE + 48
CS_DX:              .equ    GAME_STATE + 49
CS_DL:              .equ    GAME_STATE + 50
CS_DR:              .equ    GAME_STATE + 51
CS_DY:              .equ    GAME_STATE + 52
CS_DT:              .equ    GAME_STATE + 53

CS_TILE_SUIT:       .equ    0x80        ; + 4 * suit: spade, heart, diamond, club
CS_ATTR_CARD:       .equ    0x38        ; black on a white card
CS_ATTR_CARD_RED:   .equ    0x3a        ; red on a white card
CS_ATTR_SUIT:       .equ    0x78
CS_ATTR_SUIT_RED:   .equ    0x7a
CS_ATTR_TEXT:       .equ    0x07
CS_ATTR_LABEL:      .equ    0x04
CS_ATTR_TITLE:      .equ    0x06
CS_ATTR_DIM:        .equ    0x05
CS_ATTR_PICK:       .equ    0x06
CS_ATTR_GOOD:       .equ    0x04

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     cs_patterns
        LDAA    CS_TILE_SUIT
        LDAB    16
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    25
        STAA    [CS_TARGET]
; b[i] = 1 + (round * 3 + i * 5 + draws * 7) % 13, c[i] = (i + round + draws) % 4
cs_deal:
        CLR     [CS_I]
cs_deal_card:
        LDAA    [CS_DRAWS]
        LDAB    7
        JSR     jr_mul8
        STAA    [CS_T]
        LDAA    [CS_ROUND]
        LDAB    3
        JSR     jr_mul8
        ADDA    [CS_T]
        STAA    [CS_T]
        LDAA    [CS_I]
        LDAB    5
        JSR     jr_mul8
        ADDA    [CS_T]
        LDAB    13
        JSR     jr_divmod8
        INCB
        LDAA    [CS_I]
        LDX     CS_B
        JSR     jr_add_x_a
        STAB    [X]
        LDAA    [CS_I]
        ADDA    [CS_ROUND]
        ADDA    [CS_DRAWS]
        ANDA    3
        STAA    [X + 5]
        INC     [CS_I]
        LDAA    [CS_I]
        CMPA    5
        BNE     cs_deal_card
        LDAA    2
        STAA    [CS_DISCARDS]
        CLR     [CS_SCORING]
        JMP     cs_evaluate

; pairs among equal ranks, the largest group, and whether all suits match.
cs_evaluate:
        CLR     [CS_PAIRS]
        CLR     [CS_LARGEST]
        LDAA    1
        STAA    [CS_SAME]
        CLR     [CS_I]
cs_eval_i:
        CLR     [CS_COUNT]
        CLR     [CS_J]
cs_eval_j:
        LDAA    [CS_I]
        LDX     CS_B
        JSR     jr_add_x_a
        LDAB    [X]
        LDAA    [CS_J]
        LDX     CS_B
        JSR     jr_add_x_a
        CMPB    [X]
        BNE     cs_eval_j_next
        INC     [CS_COUNT]
        LDAA    [CS_I]
        CMPA    [CS_J]
        BCC     cs_eval_j_next
        INC     [CS_PAIRS]
cs_eval_j_next:
        INC     [CS_J]
        LDAA    [CS_J]
        CMPA    5
        BNE     cs_eval_j
        LDAA    [CS_I]
        LDX     CS_B
        JSR     jr_add_x_a
        CLRB
        LDAA    [CS_COUNT]
        CMPA    2
        BCS     cs_eval_mark
        LDAB    1
cs_eval_mark:
        STAB    [X + 10]
        CMPA    [CS_LARGEST]
        BLS     cs_eval_suit
        STAA    [CS_LARGEST]
cs_eval_suit:
        LDAA    [X + 5]
        CMPA    [CS_C]
        BEQ     cs_eval_i_next
        CLR     [CS_SAME]
cs_eval_i_next:
        INC     [CS_I]
        LDAA    [CS_I]
        CMPA    5
        BNE     cs_eval_i
        LDAA    3
        STAA    [CS_POINTS]
        CLR     [CS_HAND]
        LDAA    [CS_PAIRS]
        CMPA    1
        BNE     cs_eval_multi
        LDAA    8
        STAA    [CS_POINTS]
        LDAA    1
        STAA    [CS_HAND]
        BRA     cs_eval_flush
cs_eval_multi:
        BCS     cs_eval_flush
        LDAA    16
        STAA    [CS_POINTS]
        ; two pairs, or three / full house / four / five of a kind
        LDAB    2
        LDAA    [CS_LARGEST]
        CMPA    3
        BNE     cs_eval_four
        LDAB    3
        LDAA    [CS_PAIRS]
        CMPA    4
        BNE     cs_eval_hand
        LDAB    4
        BRA     cs_eval_hand
cs_eval_four:
        CMPA    4
        BNE     cs_eval_five
        LDAB    5
cs_eval_five:
        CMPA    5
        BNE     cs_eval_hand
        LDAB    6
cs_eval_hand:
        STAB    [CS_HAND]
cs_eval_flush:
        TST     [CS_SAME]
        BEQ     cs_eval_done
        LDAA    25
        STAA    [CS_POINTS]
        LDAA    7
        STAA    [CS_HAND]
        LDAA    1
        STAA    [CS_D]
        STAA    [CS_D + 1]
        STAA    [CS_D + 2]
        STAA    [CS_D + 3]
        STAA    [CS_D + 4]
cs_eval_done:
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_LEFT
        BNE     cs_act_right
        LDAA    [CS_CURSOR]
        ADDA    4
        BRA     cs_act_cursor
cs_act_right:
        CMPA    JR_KEY_RIGHT
        BNE     cs_act_redraw
        LDAA    [CS_CURSOR]
        INCA
cs_act_cursor:
        CMPA    5
        BCS     cs_act_store
        SUBA    5
cs_act_store:
        STAA    [CS_CURSOR]
        RTS
cs_act_redraw:
        CMPA    JR_KEY_UP
        BNE     cs_act_score
        TST     [CS_DISCARDS]
        BNE     cs_act_done_near254
        JMP     cs_act_done
cs_act_done_near254:
        ; the card turns edge-on, is replaced and opens again
        LDAA    1
        STAA    [CS_FLIPPING]
        CLRA
        JSR     jr_port_sound
        LDAA    6
        JSR     jr_port_animate
        LDAA    2
        STAA    [CS_FLIPPING]
        LDAA    6
        JSR     jr_port_animate
        INC     [CS_DRAWS]
        LDAA    [CS_DRAWS]
        LDAB    7
        JSR     jr_mul8
        STAA    [CS_T]
        LDAA    [CS_CURSOR]
        LDAB    3
        JSR     jr_mul8
        ADDA    [CS_T]
        ADDA    [CS_ROUND]
        LDAB    13
        JSR     jr_divmod8
        INCB
        LDAA    [CS_CURSOR]
        LDX     CS_B
        JSR     jr_add_x_a
        STAB    [X]
        LDAA    [CS_DRAWS]
        ADDA    [CS_CURSOR]
        ANDA    3
        STAA    [X + 5]
        DEC     [CS_DISCARDS]
        LDAA    1
        STAA    [CS_FLIPPING]
        LDAA    6
        JSR     jr_port_animate
        CLR     [CS_FLIPPING]
        JSR     cs_evaluate
        LDAA    8
        JMP     jr_port_animate
cs_act_score:
        CMPA    JR_KEY_CONFIRM
        BNE     cs_act_done
        LDAA    1
        STAA    [CS_SCORING]
        LDAA    [CS_SCORE]
        ADDA    [CS_POINTS]
        STAA    [CS_SCORE]
        LDAA    1
        JSR     jr_port_sound
        LDAA    2
        STAA    [CS_K]
cs_score_blink:
        LDAA    1
        STAA    [CS_BLINK]
        LDAA    12
        JSR     jr_port_animate
        CLR     [CS_BLINK]
        LDAA    12
        JSR     jr_port_animate
        DEC     [CS_K]
        BNE     cs_score_blink
        LDAA    60
        JSR     jr_port_animate
        INC     [CS_ROUND]
        LDAA    [CS_ROUND]
        CMPA    3
        BEQ     cs_score_end
        JMP     cs_deal
cs_score_end:
        LDAA    [CS_SCORE]
        CMPA    [CS_TARGET]
        BCS     cs_score_lose
        JMP     jr_port_win
cs_score_lose:
        LDX     cs_txt_lose
        JMP     jr_port_lose
cs_act_done:
        RTS

; ---------------------------------------------------------------- drawing

; A = value, at the cursor: two digits, or a space and one digit below ten.
cs_small_number:
        CMPA    10
        BCC     cs_small_two
        PSHA
        LDAA    0x20
        JSR     jr_gfx_putc
        PULA
        ADDA    0x30
        JMP     jr_gfx_putc
cs_small_two:
        JMP     jr_gfx_dec2

game_draw:
        LDAA    0x20
        LDAB    CS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cs_hud
        JSR     jr_gfx_lines
        LDAA    CS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    6
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [CS_ROUND]
        CMPA    3
        BCS     cs_draw_round
        LDAA    2
cs_draw_round:
        ADDA    0x31
        JSR     jr_gfx_putc
        ; five white cards; the one being replaced narrows to its edge
        CLR     [CS_DI]
cs_draw_card:
        LDAA    [CS_DI]
        LDAB    6
        JSR     jr_mul8
        INCA
        STAA    [CS_DX]
        STAA    [CS_DL]
        ADDA    4
        STAA    [CS_DR]
        CLR     [CS_DT]
        TST     [CS_FLIPPING]
        BEQ     cs_draw_face
        LDAA    [CS_DI]
        CMPA    [CS_CURSOR]
        BNE     cs_draw_face
        INC     [CS_DT]
        INC     [CS_DL]
        DEC     [CS_DR]
        LDAA    [CS_FLIPPING]
        CMPA    2
        BNE     cs_draw_face
        INC     [CS_DL]
        DEC     [CS_DR]
cs_draw_face:
        LDAA    CS_ATTR_CARD
        STAA    [JR_RT_COLOR]
        LDAA    5
        STAA    [CS_DY]
cs_draw_row:
        LDAA    [CS_DL]
        LDAB    [CS_DY]
        JSR     jr_gfx_at
        LDAB    [CS_DL]
cs_draw_col:
        PSHB
        LDAA    0x20
        JSR     jr_gfx_putc
        PULB
        INCB
        CMPB    [CS_DR]
        BLS     cs_draw_col
        INC     [CS_DY]
        LDAA    [CS_DY]
        CMPA    12
        BNE     cs_draw_row
        TST     [CS_DT]
        BNE     cs_draw_mark
        ; rank and suit: hearts and diamonds in red
        LDAA    [CS_DI]
        LDX     CS_B
        JSR     jr_add_x_a
        LDAA    [X + 5]
        STAA    [CS_DT]
        LDAB    CS_ATTR_CARD
        DECA
        CMPA    2
        BCC     cs_draw_rank
        LDAB    CS_ATTR_CARD_RED
cs_draw_rank:
        STAB    [JR_RT_COLOR]
        LDAA    [CS_DX]
        INCA
        LDAB    6
        JSR     jr_gfx_at
        LDAA    [CS_DI]
        LDX     CS_B
        JSR     jr_add_x_a
        LDAA    [X]
        JSR     cs_small_number
        LDAB    CS_ATTR_SUIT
        LDAA    [CS_DT]
        DECA
        CMPA    2
        BCC     cs_draw_suit
        LDAB    CS_ATTR_SUIT_RED
cs_draw_suit:
        STAB    [JR_RT_COLOR]
        LDAA    [CS_DX]
        INCA
        LDAB    8
        JSR     jr_gfx_at
        LDAA    [CS_DT]
        ASLA
        ASLA
        ADDA    CS_TILE_SUIT
        JSR     jr_gfx_tile
cs_draw_mark:
        ; '*' under a matching card, hidden while it blinks
        TST     [CS_BLINK]
        BNE     cs_draw_next
        LDAA    [CS_DI]
        LDX     CS_D
        JSR     jr_add_x_a
        TST     [X]
        BEQ     cs_draw_next
        LDAA    CS_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [CS_DX]
        ADDA    2
        LDAB    12
        JSR     jr_gfx_at
        LDAA    0x2a
        JSR     jr_gfx_putc
cs_draw_next:
        INC     [CS_DI]
        LDAA    [CS_DI]
        CMPA    5
        BEQ     cs_draw_cursor
        JMP     cs_draw_card
cs_draw_cursor:
        TST     [CS_SCORING]
        BNE     cs_draw_hand
        LDAA    CS_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [CS_CURSOR]
        LDAB    6
        JSR     jr_mul8
        ADDA    3
        LDAB    4
        JSR     jr_gfx_at
        LDAA    0x56
        JSR     jr_gfx_putc
cs_draw_hand:
        LDAA    [CS_HAND]
        LDX     cs_hand_attr
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    14
        JSR     jr_gfx_at
        LDAA    [CS_HAND]
        ASLA
        LDX     cs_hand_text
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        LDAA    24
        LDAB    14
        JSR     jr_gfx_at
        LDAA    0x2b
        JSR     jr_gfx_putc
        LDAA    [CS_POINTS]
        JSR     cs_small_number
        LDAA    CS_ATTR_TEXT
        LDX     cs_txt_ready
        TST     [CS_SCORING]
        BEQ     cs_draw_ready
        LDAA    CS_ATTR_PICK
        LDX     cs_txt_scored
cs_draw_ready:
        STAA    [JR_RT_COLOR]
        STX     [JR_RT_TABLE]
        LDAA    1
        LDAB    15
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        JSR     jr_gfx_text
        ; score (green once it reaches the goal), goal and redraws
        LDAA    CS_ATTR_TEXT
        LDAB    [CS_SCORE]
        CMPB    [CS_TARGET]
        BCS     cs_draw_score
        LDAA    CS_ATTR_GOOD
cs_draw_score:
        STAA    [JR_RT_COLOR]
        LDAA    6
        LDAB    18
        JSR     jr_gfx_at
        LDAA    [CS_SCORE]
        JSR     cs_small_number
        LDAA    CS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    16
        LDAB    18
        JSR     jr_gfx_at
        LDAA    [CS_TARGET]
        JSR     cs_small_number
        LDAA    27
        LDAB    18
        JSR     jr_gfx_at
        LDAA    [CS_DISCARDS]
        JMP     cs_small_number

game_draw_title:
        LDX     cs_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    CS_ATTR_TEXT
        JSR     jr_gfx_fill
        CLR     [CS_DI]
cs_title_suit:
        LDAB    CS_ATTR_SUIT
        LDAA    [CS_DI]
        DECA
        CMPA    2
        BCC     cs_title_colour
        LDAB    CS_ATTR_SUIT_RED
cs_title_colour:
        STAB    [JR_RT_COLOR]
        LDAA    [CS_DI]
        ASLA
        ASLA
        ADDA    9
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [CS_DI]
        ASLA
        ASLA
        ADDA    CS_TILE_SUIT
        JSR     jr_gfx_tile
        INC     [CS_DI]
        LDAA    [CS_DI]
        CMPA    4
        BNE     cs_title_suit
        LDX     cs_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    CS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cs_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

cs_hand_text:
        .dw     cs_txt_no_pair, cs_txt_one_pair, cs_txt_two_pairs, cs_txt_three
        .dw     cs_txt_full_house, cs_txt_four, cs_txt_five, cs_txt_flush
cs_hand_attr:
        .db     0x07, 0x05, 0x04, 0x04, 0x06, 0x06, 0x06, 0x03

cs_hud:
        .db     1, 0, CS_ATTR_TITLE
        .dw     cs_txt_name
        .db     1, 2, CS_ATTR_LABEL
        .dw     cs_txt_hand
        .db     7, 2, CS_ATTR_DIM
        .dw     cs_txt_matching
        .db     28, 14, CS_ATTR_LABEL
        .dw     cs_txt_pts
        .db     1, 17, CS_ATTR_LABEL
        .dw     cs_txt_labels
        .db     0xff
cs_title_lines:
        .db     11, 8, CS_ATTR_TITLE
        .dw     cs_txt_name
        .db     3, 10, CS_ATTR_LABEL
        .dw     cs_txt_tagline
        .db     8, 15, CS_ATTR_TEXT
        .dw     cs_txt_start
        .db     5, 17, CS_ATTR_TEXT
        .dw     cs_txt_howto
        .db     4, 22, CS_ATTR_DIM
        .dw     cs_txt_credit
        .db     0xff
cs_help_lines:
        .db     11, 2, CS_ATTR_TITLE
        .dw     cs_txt_name
        .db     1, 5, CS_ATTR_TEXT
        .dw     cs_help_1
        .db     1, 7, CS_ATTR_TEXT
        .dw     cs_help_2
        .db     1, 9, CS_ATTR_TEXT
        .dw     cs_help_3
        .db     1, 11, CS_ATTR_TEXT
        .dw     cs_help_4
        .db     1, 13, CS_ATTR_TEXT
        .dw     cs_help_5
        .db     1, 15, CS_ATTR_TEXT
        .dw     cs_help_6
        .db     1, 17, CS_ATTR_TEXT
        .dw     cs_help_7
        .db     1, 21, CS_ATTR_LABEL
        .dw     cs_help_back
        .db     0xff

cs_txt_name:
        .db     "CHAIN SUIT", 0
cs_txt_hand:
        .db     "HAND", 0
cs_txt_matching:
        .db     "/3  * = MATCHING CARDS", 0
cs_txt_pts:
        .db     "PTS", 0
cs_txt_labels:
        .db     "SCORE      GOAL       REDRAWS", 0
cs_txt_no_pair:
        .db     "NO PAIR", 0
cs_txt_one_pair:
        .db     "ONE PAIR", 0
cs_txt_two_pairs:
        .db     "TWO PAIRS", 0
cs_txt_three:
        .db     "THREE OF A KIND", 0
cs_txt_full_house:
        .db     "FULL HOUSE", 0
cs_txt_four:
        .db     "FOUR OF A KIND", 0
cs_txt_five:
        .db     "FIVE OF A KIND", 0
cs_txt_flush:
        .db     "FLUSH / SAME SUIT", 0
cs_txt_ready:
        .db     "HAND READY", 0
cs_txt_scored:
        .db     "HAND SCORED!", 0
cs_txt_lose:
        .db     "TOTAL BELOW 25", 0
cs_txt_tagline:
        .db     "25 POINTS IN THREE HANDS", 0
cs_txt_start:
        .db     "RETURN : START", 0
cs_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
cs_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
cs_help_1:
        .db     "A/D : CHOOSE A CARD", 0
cs_help_2:
        .db     "W : REPLACE IT (TWICE/HAND)", 0
cs_help_3:
        .db     "RETURN : SCORE THE HAND", 0
cs_help_4:
        .db     "HIGH 3 / PAIR 8 / MULTI 16", 0
cs_help_5:
        .db     "ALL SAME SUIT SCORES 25.", 0
cs_help_6:
        .db     "MAKE 25 POINTS IN THREE HANDS.", 0
cs_help_7:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
cs_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     cs_sfx_flip, cs_sfx_score, cs_jingle_win, cs_jingle_lose
cs_sfx_flip:
        .db     90, 2, 0, 1, 70, 2, 0, 0
cs_sfx_score:
        .db     60, 4, 48, 4, 40, 4, 30, 8, 0, 0

; Title: a jaunty card-room tune in C major, eighth note = 8 frames, looping.
cs_title_song:
        .db     1
        .dw     cs_title_melody, cs_title_harmony, cs_title_bass
cs_title_melody:
        .db     AU_E5, 8, AU_G5, 8, AU_C6, 16, AU_B5, 8, AU_A5, 8, AU_G5, 16
        .db     AU_F5, 8, AU_A5, 8, AU_D6, 16, AU_C6, 8, AU_B5, 8, AU_C6, 16
        .db     AU_E5, 8, AU_G5, 8, AU_C6, 16, AU_A5, 8, AU_F5, 8, AU_D5, 16
        .db     AU_G5, 8, AU_F5, 8, AU_E5, 8, AU_D5, 8, AU_C5, 32, 0, 0
cs_title_harmony:
        .db     AU_C5, 32, AU_E5, 32, AU_D5, 32, AU_E5, 32
        .db     AU_C5, 32, AU_C5, 32, AU_B4, 32, AU_G4, 32, 0, 0
cs_title_bass:
        .db     AU_C3, 16, AU_G2, 16, AU_C3, 16, AU_E3, 16
        .db     AU_F2, 16, AU_A2, 16, AU_G2, 16, AU_C3, 16
        .db     AU_C3, 16, AU_E3, 16, AU_F2, 16, AU_D3, 16
        .db     AU_G2, 16, AU_G2, 16, AU_C3, 32, 0, 0

; Winning total: C major arpeggio over the tonic (54 frames).
cs_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     cs_win_melody, cs_win_harmony, cs_win_bass
cs_win_melody:
        .db     AU_C5, 8, AU_E5, 8, AU_G5, 8, AU_C6, 30, 0, 0
cs_win_harmony:
        .db     AU_G4, 8, AU_C5, 8, AU_E5, 8, AU_G5, 30, 0, 0
cs_win_bass:
        .db     AU_C3, 24, AU_C2, 30, 0, 0
cs_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     cs_lose_melody, cs_lose_harmony, cs_lose_bass
cs_lose_melody:
        .db     AU_G4, 12, AU_F4, 12, AU_DS4, 12, AU_D4, 30, 0, 0
cs_lose_harmony:
        .db     AU_DS4, 12, AU_D4, 12, AU_C4, 12, AU_B3, 30, 0, 0
cs_lose_bass:
        .db     AU_C3, 36, AU_G2, 30, 0, 0

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
