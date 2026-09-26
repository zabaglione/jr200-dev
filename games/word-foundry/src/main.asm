; SPDX-License-Identifier: MIT
; WORD FOUNDRY for JR-200: a port of jr100dev games/word_foundry/rules.py 2.0.0.
; The sixteen words, routes, via words and PAR + 2 limit follow the upstream
; source; display, colour and three-voice sound use the JR-200 port SDK.
        .filename.jr "WORD-FOUNDRY"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    16
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py).
WF_WORD:            .equ    GAME_STATE
WF_GOAL:            .equ    GAME_STATE + 1
WF_VIA:             .equ    GAME_STATE + 2
WF_LIMIT:           .equ    GAME_STATE + 3
WF_CURSOR:          .equ    GAME_STATE + 4
WF_STEPS:           .equ    GAME_STATE + 5
WF_FORGED:          .equ    GAME_STATE + 6
WF_OLD:             .equ    GAME_STATE + 7
WF_CHANGING:        .equ    GAME_STATE + 8
WF_LIFT:            .equ    GAME_STATE + 9
WF_EFFECT:          .equ    GAME_STATE + 10
WF_PHASE:           .equ    GAME_STATE + 11
WF_HIST:            .equ    GAME_STATE + 12     ; d[16]
; Shared work bytes (never held across an animation).
WF_A:               .equ    GAME_STATE + 32
WF_B:               .equ    GAME_STATE + 33
WF_N:               .equ    GAME_STATE + 34
WF_PA:              .equ    GAME_STATE + 35
WF_PB:              .equ    GAME_STATE + 37
WF_MP:              .equ    GAME_STATE + 39
WF_MA:              .equ    GAME_STATE + 40
WF_MC:              .equ    GAME_STATE + 41
WF_FRAME:           .equ    GAME_STATE + 42
; Drawing work bytes.
WF_DI:              .equ    GAME_STATE + 48
WF_DJ:              .equ    GAME_STATE + 49
WF_DX:              .equ    GAME_STATE + 50
WF_DY:              .equ    GAME_STATE + 51
WF_DSTART:          .equ    GAME_STATE + 52
WF_DK:              .equ    GAME_STATE + 53

WF_ATTR_CURRENT:    .equ    0x0e        ; yellow on blue card
WF_ATTR_TARGET:     .equ    0x17        ; white on red card
WF_ATTR_VIA:        .equ    0x1f        ; white on magenta card
WF_ATTR_NEXT:       .equ    0x20        ; black on green: one letter away
WF_ATTR_WORD:       .equ    0x07
WF_ATTR_NOW:        .equ    0x0e        ; the current word inside the grid
WF_ATTR_LIFT:       .equ    0x06
WF_ATTR_SPARK:      .equ    0x46
WF_ATTR_HIST:       .equ    0x05
WF_ATTR_TEXT:       .equ    0x07
WF_ATTR_LABEL:      .equ    0x04
WF_ATTR_TITLE:      .equ    0x06
WF_ATTR_DIM:        .equ    0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     wf_patterns
        LDAA    0x80
        LDAB    12
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    [JR_PORT_LEVEL]
        LDX     wf_starts
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [WF_WORD]
        STAA    [WF_HIST]
        LDAA    [X + 16]
        STAA    [WF_GOAL]
        LDAA    [X + 32]
        STAA    [WF_VIA]
        LDAA    [X + 48]
        ADDA    2
        STAA    [WF_LIMIT]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     wf_replace
        BCC     wf_act_done
        TAB
        LDAA    [WF_CURSOR]
        JSR     wf_move
        STAA    [WF_CURSOR]
wf_act_done:
        RTS

wf_replace:
        LDAA    [WF_WORD]
        LDAB    [WF_CURSOR]
        JSR     wf_diff
        CMPA    1
        BEQ     wf_change
        LDX     wf_sfx_buzz
        JMP     jr_sfx_play
wf_change:
        LDAA    [WF_WORD]
        STAA    [WF_OLD]
        LDAA    1
        STAA    [WF_CHANGING]
        CLR     [WF_FRAME]
wf_change_frame:
        LDAA    [WF_FRAME]
        STAA    [WF_LIFT]
        CLRA
        JSR     jr_port_sound
        LDAA    4
        JSR     jr_port_animate
        INC     [WF_FRAME]
        LDAA    [WF_FRAME]
        CMPA    3
        BNE     wf_change_frame
        LDAA    [WF_CURSOR]
        STAA    [WF_WORD]
        CLR     [WF_CHANGING]
        INC     [WF_STEPS]
        LDAA    [WF_STEPS]
        LDX     WF_HIST
        JSR     jr_add_x_a
        LDAA    [WF_WORD]
        STAA    [X]
        LDAA    1
        JSR     jr_port_sound
        LDAA    [WF_WORD]
        CMPA    [WF_VIA]
        BNE     wf_check_goal
        LDAA    1
        STAA    [WF_FORGED]
        JSR     wf_sparkle
wf_check_goal:
        LDAA    [WF_WORD]
        CMPA    [WF_GOAL]
        BNE     wf_check_limit
        TST     [WF_FORGED]
        BEQ     wf_check_limit
        JMP     jr_port_win
wf_check_limit:
        LDAA    [WF_STEPS]
        CMPA    [WF_LIMIT]
        BNE     wf_check_done
        LDX     wf_txt_lose
        JMP     jr_port_lose
wf_check_done:
        RTS

; sparkle(12, 3): three phases of animate(4).
wf_sparkle:
        LDAA    2
        STAA    [WF_EFFECT]
        CLR     [WF_FRAME]
wf_sparkle_phase:
        LDAA    [WF_FRAME]
        STAA    [WF_PHASE]
        LDAA    4
        JSR     jr_port_animate
        INC     [WF_FRAME]
        LDAA    [WF_FRAME]
        CMPA    3
        BNE     wf_sparkle_phase
        CLR     [WF_EFFECT]
        RTS

; A, B = words -> A = number of differing letters. Clobbers B and X.
wf_diff:
        STAB    [WF_B]
        JSR     wf_word_x
        STX     [WF_PA]
        LDAA    [WF_B]
        JSR     wf_word_x
        CLR     [WF_N]
        LDAB    3
wf_diff_letter:
        LDAA    [X]
        STX     [WF_PB]
        LDX     [WF_PA]
        CMPA    [X]
        BEQ     wf_diff_same
        INC     [WF_N]
wf_diff_same:
        INX
        STX     [WF_PA]
        LDX     [WF_PB]
        INX
        DECB
        BNE     wf_diff_letter
        LDAA    [WF_N]
        RTS

; A = word -> X = &words[word * 3]. Clobbers A and B.
wf_word_x:
        LDAB    3
        JSR     jr_mul8
        LDX     wf_words
        JMP     jr_add_x_a

; A = position, B = action 1-4 -> A = moved position (4x4, stops at edges).
wf_move:
        STAA    [WF_MP]
        STAB    [WF_MA]
        ANDA    3
        STAA    [WF_MC]
        LDAA    [WF_MP]
        CMPB    JR_KEY_UP
        BNE     wf_move_down
        CMPA    4
        BCS     wf_move_done
        SUBA    4
        RTS
wf_move_down:
        CMPB    JR_KEY_DOWN
        BNE     wf_move_left
        CMPA    12
        BCC     wf_move_done
        ADDA    4
        RTS
wf_move_left:
        CMPB    JR_KEY_LEFT
        BNE     wf_move_right
        TST     [WF_MC]
        BEQ     wf_move_done
        DECA
        RTS
wf_move_right:
        CMPB    JR_KEY_RIGHT
        BNE     wf_move_done
        LDAB    [WF_MC]
        CMPB    3
        BCC     wf_move_done
        INCA
wf_move_done:
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    WF_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     wf_hud
        JSR     jr_gfx_lines
        LDAA    WF_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; current word card (11-15, 3), target card (25-29, 3), via card (6-10, 5)
        LDAA    WF_ATTR_CURRENT
        LDAB    [WF_WORD]
        LDX     wf_card_current
        JSR     wf_draw_card
        LDAA    WF_ATTR_TARGET
        LDAB    [WF_GOAL]
        LDX     wf_card_target
        JSR     wf_draw_card
        LDAA    WF_ATTR_VIA
        LDAB    [WF_VIA]
        LDX     wf_card_via
        JSR     wf_draw_card
        TST     [WF_FORGED]
        BEQ     wf_draw_par
        LDAA    WF_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    11
        LDAB    5
        JSR     jr_gfx_at
        LDAA    0x2a
        JSR     jr_gfx_putc
wf_draw_par:
        LDAA    WF_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    20
        LDAB    5
        JSR     jr_gfx_at
        LDAA    [WF_LIMIT]
        SUBA    2
        JSR     jr_gfx_dec2
        LDAA    29
        LDAB    5
        JSR     jr_gfx_at
        LDAA    [WF_LIMIT]
        SUBA    [WF_STEPS]
        JSR     jr_gfx_dec2
        ; the sixteen words at (2 + i % 4 * 8, 8 + i // 4 * 3)
        CLR     [WF_DI]
wf_draw_word:
        LDAA    [WF_DI]
        JSR     wf_grid_xy
        STAA    [WF_DX]
        STAB    [WF_DY]
        LDAA    [WF_WORD]
        LDAB    [WF_DI]
        JSR     wf_diff
        LDAB    WF_ATTR_WORD
        TSTA
        BNE     wf_draw_word_one
        LDAB    WF_ATTR_NOW
wf_draw_word_one:
        CMPA    1
        BNE     wf_draw_word_text
        ; '*' at (6 + i % 4 * 8, ...) marks a legal next word
        LDAA    WF_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    [WF_DX]
        ADDA    4
        LDAB    [WF_DY]
        JSR     jr_gfx_at
        LDAA    0x2a
        JSR     jr_gfx_putc
        LDAB    WF_ATTR_NEXT
wf_draw_word_text:
        STAB    [JR_RT_COLOR]
        LDAA    [WF_DX]
        LDAB    [WF_DY]
        JSR     jr_gfx_at
        LDAA    [WF_DI]
        JSR     wf_put_word
        INC     [WF_DI]
        LDAA    [WF_DI]
        CMPA    16
        BNE     wf_draw_word
        ; cursor '>' at (1 + i % 4 * 8, 8 + i // 4 * 3)
        LDAA    WF_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [WF_CURSOR]
        JSR     wf_grid_xy
        DECA
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        ; steps and the last eight words of the ladder on row 19
        LDAA    25
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [WF_STEPS]
        JSR     jr_gfx_dec2
        LDAA    WF_ATTR_HIST
        STAA    [JR_RT_COLOR]
        CLRA
        LDAB    [WF_STEPS]
        CMPB    7
        BCS     wf_draw_hist_start
        TBA
        SUBA    7
wf_draw_hist_start:
        STAA    [WF_DSTART]
        CLR     [WF_DJ]
wf_draw_hist:
        LDAA    [WF_DSTART]
        ADDA    [WF_DJ]
        CMPA    [WF_STEPS]
        BHI     wf_draw_effects
        LDX     WF_HIST
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [WF_DK]
        LDAA    [WF_DJ]
        ASLA
        ASLA
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [WF_DK]
        JSR     wf_put_word
        INC     [WF_DJ]
        LDAA    [WF_DJ]
        CMPA    8
        BNE     wf_draw_hist
wf_draw_effects:
        LDAA    [WF_EFFECT]
        CMPA    2
        BNE     wf_draw_lift
        LDAA    WF_ATTR_SPARK
        STAA    [JR_RT_COLOR]
        LDAA    12
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [WF_PHASE]
        ASLA
        ASLA
        ADDA    0x80
        JSR     jr_gfx_tile
wf_draw_lift:
        TST     [WF_CHANGING]
        BEQ     wf_draw_done
        ; the changed letters float down under the current word
        LDAA    WF_ATTR_LIFT
        STAA    [JR_RT_COLOR]
        CLR     [WF_DJ]
wf_draw_lift_letter:
        LDAA    [WF_OLD]
        JSR     wf_word_x
        LDAA    [WF_DJ]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [WF_DK]
        LDAA    [WF_CURSOR]
        JSR     wf_word_x
        LDAA    [WF_DJ]
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    [WF_DK]
        BEQ     wf_draw_lift_next
        STAA    [WF_DK]
        LDAA    [WF_DJ]
        ADDA    12
        LDAB    [WF_LIFT]
        ADDB    4
        JSR     jr_gfx_at
        LDAA    [WF_DK]
        JSR     jr_gfx_putc
wf_draw_lift_next:
        INC     [WF_DJ]
        LDAA    [WF_DJ]
        CMPA    3
        BNE     wf_draw_lift_letter
wf_draw_done:
        RTS

; A = attribute, B = word, X = card position (x, y). Draws " WRD " in colour.
wf_draw_card:
        STAA    [JR_RT_COLOR]
        STAB    [WF_DK]
        LDAA    [X]
        LDAB    [X + 1]
        JSR     jr_gfx_at
        LDAA    0x20
        JSR     jr_gfx_putc
        LDAA    [WF_DK]
        JSR     wf_put_word
        LDAA    0x20
        JMP     jr_gfx_putc

; A = word: three letters at the cursor.
wf_put_word:
        JSR     wf_word_x
        LDAB    3
wf_put_letter:
        LDAA    [X]
        STX     [WF_PB]
        JSR     jr_gfx_putc
        LDX     [WF_PB]
        INX
        DECB
        BNE     wf_put_letter
        RTS

; A = grid index -> A = 2 + i % 4 * 8, B = 8 + i // 4 * 3.
wf_grid_xy:
        PSHA
        LSRA
        LSRA
        TAB
        ASLA
        ABA
        ADDA    8
        TAB
        PULA
        ANDA    3
        ASLA
        ASLA
        ASLA
        ADDA    2
        RTS

game_draw_title:
        LDX     wf_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    WF_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     wf_title_lines
        JSR     jr_gfx_lines
        LDAA    WF_ATTR_CURRENT
        LDAB    0
        LDX     wf_title_card_1
        JSR     wf_draw_card
        LDAA    WF_ATTR_VIA
        LDAB    1
        LDX     wf_title_card_2
        JSR     wf_draw_card
        LDAA    WF_ATTR_NEXT
        LDAB    2
        LDX     wf_title_card_3
        JSR     wf_draw_card
        LDAA    WF_ATTR_TARGET
        LDAB    3
        LDX     wf_title_card_4
        JMP     wf_draw_card

game_draw_help:
        LDAA    0x20
        LDAB    WF_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     wf_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

wf_words:
        .db     "CATCOTCOGDOGDOTDATBATBOTBAGBOGBIGDIGPIGPITSITSAT"
; starts[16], goals[16], via[16], pars[16] in consecutive rows.
wf_starts:
        .db     0, 1, 3, 5, 9, 11, 13, 15, 7, 2, 8, 10, 4, 12, 14, 6
        .db     12, 2, 14, 10, 1, 14, 11, 4, 0, 9, 13, 13, 1, 13, 13, 8
        .db     1, 11, 6, 1, 12, 7, 4, 10, 13, 13, 4, 1, 13, 1, 2, 2
        .db     5, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7, 8, 8, 8, 5

wf_card_current:
        .db     11, 3
wf_card_target:
        .db     25, 3
wf_card_via:
        .db     6, 5
wf_title_card_1:
        .db     4, 5
wf_title_card_2:
        .db     11, 5
wf_title_card_3:
        .db     18, 5
wf_title_card_4:
        .db     25, 5

wf_hud:
        .db     1, 0, WF_ATTR_TITLE
        .dw     wf_txt_name
        .db     23, 0, WF_ATTR_LABEL
        .dw     wf_txt_stage
        .db     1, 3, WF_ATTR_LABEL
        .dw     wf_txt_current
        .db     18, 3, WF_ATTR_LABEL
        .dw     wf_txt_target
        .db     2, 5, WF_ATTR_LABEL
        .dw     wf_txt_via
        .db     16, 5, WF_ATTR_LABEL
        .dw     wf_txt_par
        .db     24, 5, WF_ATTR_LABEL
        .dw     wf_txt_left
        .db     18, 20, WF_ATTR_LABEL
        .dw     wf_txt_steps
        .db     0xff
wf_title_lines:
        .db     10, 9, WF_ATTR_TITLE
        .dw     wf_txt_name
        .db     3, 11, WF_ATTR_LABEL
        .dw     wf_txt_tagline
        .db     8, 15, WF_ATTR_TEXT
        .dw     wf_txt_start
        .db     5, 17, WF_ATTR_TEXT
        .dw     wf_txt_howto
        .db     4, 22, WF_ATTR_DIM
        .dw     wf_txt_credit
        .db     9, 5, WF_ATTR_DIM
        .dw     wf_txt_arrows
        .db     0xff
wf_help_lines:
        .db     10, 2, WF_ATTR_TITLE
        .dw     wf_txt_name
        .db     1, 5, WF_ATTR_TEXT
        .dw     wf_help_1
        .db     1, 7, WF_ATTR_TEXT
        .dw     wf_help_2
        .db     1, 9, WF_ATTR_TEXT
        .dw     wf_help_3
        .db     1, 11, WF_ATTR_TEXT
        .dw     wf_help_4
        .db     1, 13, WF_ATTR_TEXT
        .dw     wf_help_5
        .db     1, 15, WF_ATTR_TEXT
        .dw     wf_help_6
        .db     1, 17, WF_ATTR_TEXT
        .dw     wf_help_7
        .db     1, 20, WF_ATTR_LABEL
        .dw     wf_help_back
        .db     0xff

wf_txt_name:
        .db     "WORD FOUNDRY", 0
wf_txt_stage:
        .db     "STAGE", 0
wf_txt_current:
        .db     "CURRENT", 0
wf_txt_target:
        .db     "TARGET", 0
wf_txt_via:
        .db     "VIA", 0
wf_txt_par:
        .db     "PAR", 0
wf_txt_left:
        .db     "LEFT", 0
wf_txt_steps:
        .db     "STEPS", 0
wf_txt_lose:
        .db     "WORD LADDER RAN OUT OF STEPS", 0
wf_txt_tagline:
        .db     "CHANGE ONE LETTER AT A TIME", 0
wf_txt_arrows:
        .db     ">      >      >", 0
wf_txt_start:
        .db     "RETURN : START", 0
wf_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
wf_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
wf_help_1:
        .db     "WASD : WORD  RETURN : REPLACE", 0
wf_help_2:
        .db     "CHANGE EXACTLY ONE LETTER.", 0
wf_help_3:
        .db     "REACH VIA BEFORE THE TARGET.", 0
wf_help_4:
        .db     "GREEN * WORDS ARE NEXT STEPS.", 0
wf_help_5:
        .db     "PAR + TWO STEPS IS THE LIMIT.", 0
wf_help_6:
        .db     "SPACE : RESTART THIS LADDER", 0
wf_help_7:
        .db     "CTRL+C : BACK TO BASIC", 0
wf_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     wf_sfx_lift, wf_sfx_set, wf_jingle_win, wf_jingle_lose
wf_sfx_lift:
        .db     70, 2, 0, 0
wf_sfx_set:
        .db     100, 3, 0, 1, 75, 4, 0, 0
wf_sfx_buzz:
        .db     220, 4, 0, 2, 220, 6, 0, 0

; Title: four bars in A minor, quarter note = 20 frames, looping.
wf_title_song:
        .db     1
        .dw     wf_title_melody, wf_title_harmony, wf_title_bass
wf_title_melody:
        .db     AU_A5, 20, AU_E5, 20, AU_A5, 20, AU_C6, 20
        .db     AU_B5, 40, AU_G5, 40
        .db     AU_A5, 20, AU_C6, 20, AU_E6, 20, AU_D6, 20
        .db     AU_C6, 60, 0, 20, 0, 0
wf_title_harmony:
        .db     AU_C5, 40, AU_E5, 40, AU_D5, 40, AU_B4, 40
        .db     AU_C5, 40, AU_A4, 40, AU_E5, 60, 0, 20, 0, 0
wf_title_bass:
        .db     AU_A2, 20, AU_A3, 20, AU_A2, 20, AU_A3, 20
        .db     AU_G2, 20, AU_G3, 20, AU_G2, 20, AU_G3, 20
        .db     AU_F2, 20, AU_F3, 20, AU_F2, 20, AU_F3, 20
        .db     AU_E2, 20, AU_E3, 20, AU_E2, 20, 0, 20, 0, 0

; Clear: rising A major arpeggio over a held tonic (54 frames).
wf_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     wf_win_melody, wf_win_harmony, wf_win_bass
wf_win_melody:
        .db     AU_A5, 8, AU_CS6, 8, AU_E6, 8, AU_A6, 30, 0, 0
wf_win_harmony:
        .db     AU_E5, 8, AU_A5, 8, AU_CS6, 8, AU_E6, 30, 0, 0
wf_win_bass:
        .db     AU_A3, 24, AU_A2, 30, 0, 0
; Out of steps: a falling A minor line (66 frames).
wf_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     wf_lose_melody, wf_lose_harmony, wf_lose_bass
wf_lose_melody:
        .db     AU_A4, 12, AU_G4, 12, AU_F4, 12, AU_E4, 30, 0, 0
wf_lose_harmony:
        .db     AU_C4, 12, AU_B3, 12, AU_A3, 12, AU_GS3, 30, 0, 0
wf_lose_bass:
        .db     AU_A2, 36, AU_E2, 30, 0, 0

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
