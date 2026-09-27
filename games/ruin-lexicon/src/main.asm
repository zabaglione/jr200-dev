; SPDX-License-Identifier: MIT
; RUIN LEXICON for JR-200: a port of jr100dev games/ruin_lexicon/rules.py 2.1.0.
; The inscription table, the value dials, the four-step check and the five
; tries follow the upstream source; display, colour and three-voice sound use
; the JR-200 port SDK.
        .filename.jr "RUIN-LEXICON"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    20
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then b[4] and d[4].
RL_CURSOR:          .equ    GAME_STATE
RL_TURNING:         .equ    GAME_STATE + 1
RL_CHECK:           .equ    GAME_STATE + 2
RL_ERRORS:          .equ    GAME_STATE + 3
RL_B:               .equ    GAME_STATE + 4
RL_D:               .equ    GAME_STATE + 8
; Rule and drawing work bytes.
RL_K:               .equ    GAME_STATE + 16
RL_OK:              .equ    GAME_STATE + 17
RL_DI:              .equ    GAME_STATE + 24
RL_DY:              .equ    GAME_STATE + 25
RL_DW:              .equ    GAME_STATE + 26

RL_TILE_PILLAR:     .equ    0x80
RL_TILE_TABLET:     .equ    0x84
RL_ATTR_PILLAR:     .equ    0x47
RL_ATTR_TABLET:     .equ    0x46
; the inscription stone: blue; the lexicon tablet: magenta
RL_ATTR_STONE:      .equ    0x0f
RL_ATTR_RUNE:       .equ    0x0e
RL_ATTR_SUM:        .equ    0x0d
RL_ATTR_RIGHT:      .equ    0x0c
RL_ATTR_WRONG:      .equ    0x0a
RL_ATTR_LEX:        .equ    0x1f
RL_ATTR_VALUE:      .equ    0x1e
RL_ATTR_TEXT:       .equ    0x07
RL_ATTR_LABEL:      .equ    0x04
RL_ATTR_TITLE:      .equ    0x06
RL_ATTR_DIM:        .equ    0x05
RL_ATTR_BAD:        .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     rl_patterns
        LDAA    RL_TILE_PILLAR
        LDAB    8
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    [JR_PORT_LEVEL]
        ASLA
        ASLA
        LDX     rl_table
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [RL_D]
        LDAA    [X + 1]
        STAA    [RL_D + 1]
        LDAA    [X + 2]
        STAA    [RL_D + 2]
        LDAA    [X + 3]
        STAA    [RL_D + 3]
        LDAA    1
        STAA    [RL_B]
        STAA    [RL_B + 1]
        STAA    [RL_B + 2]
        STAA    [RL_B + 3]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_LEFT
        BNE     rl_act_right
        LDAA    [RL_CURSOR]
        ADDA    3
        BRA     rl_act_cursor
rl_act_right:
        CMPA    JR_KEY_RIGHT
        BNE     rl_act_turn
        LDAA    [RL_CURSOR]
        INCA
rl_act_cursor:
        ANDA    3
        STAA    [RL_CURSOR]
        RTS
rl_act_turn:
        CMPA    JR_KEY_UP
        BEQ     rl_dial
        CMPA    JR_KEY_DOWN
        BEQ     rl_dial
        CMPA    JR_KEY_CONFIRM
        BEQ     rl_verify
        RTS
rl_dial:
        ; the dial turns: W counts up, S down, through 1-4
        PSHA
        LDAA    1
        STAA    [RL_TURNING]
        CLRA
        JSR     jr_port_sound
        LDAA    4
        JSR     jr_port_animate
        CLR     [RL_TURNING]
        LDAA    [RL_CURSOR]
        LDX     RL_B
        JSR     jr_add_x_a
        PULA
        CMPA    JR_KEY_UP
        BNE     rl_turn_down
        LDAA    [X]
        INCA
        CMPA    5
        BCS     rl_turn_store
        LDAA    1
        BRA     rl_turn_store
rl_turn_down:
        LDAA    [X]
        DECA
        BNE     rl_turn_store
        LDAA    4
rl_turn_store:
        STAA    [X]
        RTS

; compare each value in turn; all four right wins, else one try is used.
rl_verify:
        LDAA    1
        STAA    [RL_OK]
        CLR     [RL_K]
rl_check_step:
        LDAA    [RL_K]
        INCA
        STAA    [RL_CHECK]
        CLRA
        JSR     jr_port_sound
        LDAA    8
        JSR     jr_port_animate
        LDAA    [RL_K]
        LDX     RL_B
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    [X + 4]
        BEQ     rl_check_next
        CLR     [RL_OK]
rl_check_next:
        INC     [RL_K]
        LDAA    [RL_K]
        CMPA    4
        BNE     rl_check_step
        CLR     [RL_CHECK]
        TST     [RL_OK]
        BEQ     rl_check_wrong
        JMP     jr_port_win
rl_check_wrong:
        INC     [RL_ERRORS]
        LDX     rl_sfx_buzz
        JSR     jr_sfx_play
        LDAA    [RL_ERRORS]
        CMPA    5
        BNE     rl_check_done
        LDX     rl_txt_lose
        JMP     jr_port_lose
rl_check_done:
        RTS

; ---------------------------------------------------------------- drawing

; A = attribute, B = first row, RL_DW = rows: blank columns 1-16 (stone)
; or 18-29 (tablet) chosen by X = x, width.
rl_panel:
        STAA    [JR_RT_COLOR]
        STAB    [RL_DY]
rl_panel_row:
        LDAA    [X]
        LDAB    [RL_DY]
        STX     [JR_RT_TABLE]
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        LDAB    [X + 1]
rl_panel_col:
        PSHB
        LDAA    0x20
        JSR     jr_gfx_putc
        PULB
        DECB
        BNE     rl_panel_col
        LDX     [JR_RT_TABLE]
        INC     [RL_DY]
        DEC     [RL_DW]
        BNE     rl_panel_row
        RTS

; A = character, B = x, RL_DY = y.
rl_put:
        PSHA
        TBA
        LDAB    [RL_DY]
        JSR     jr_gfx_at
        PULA
        JMP     jr_gfx_putc

game_draw:
        LDAA    0x20
        LDAB    RL_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     rl_hud
        JSR     jr_gfx_lines
        LDAA    RL_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        LDAA    15
        STAA    [RL_DW]
        LDX     rl_stone_box
        LDAA    RL_ATTR_STONE
        LDAB    4
        JSR     rl_panel
        LDAA    15
        STAA    [RL_DW]
        LDX     rl_tablet_box
        LDAA    RL_ATTR_LEX
        LDAB    3
        JSR     rl_panel
        ; the three sums: A+B, B+C, C+D, with a mark once a try was used
        CLR     [RL_DI]
rl_draw_sum:
        LDAA    [RL_DI]
        ASLA
        ASLA
        ADDA    5
        STAA    [RL_DY]
        LDAA    RL_ATTR_RUNE
        STAA    [JR_RT_COLOR]
        LDAA    [RL_DI]
        ADDA    0x41
        LDAB    3
        JSR     rl_put
        LDAA    [RL_DI]
        ADDA    0x42
        LDAB    7
        JSR     rl_put
        LDAA    RL_ATTR_STONE
        STAA    [JR_RT_COLOR]
        LDAA    0x2b
        LDAB    5
        JSR     rl_put
        LDAA    0x3d
        LDAB    9
        JSR     rl_put
        LDAA    RL_ATTR_SUM
        STAA    [JR_RT_COLOR]
        LDAA    11
        LDAB    [RL_DY]
        JSR     jr_gfx_at
        LDAA    [RL_DI]
        LDX     RL_D
        JSR     jr_add_x_a
        LDAA    [X]
        ADDA    [X + 1]
        JSR     jr_gfx_dec2
        TST     [RL_ERRORS]
        BEQ     rl_draw_sum_next
        LDAA    [RL_DI]
        LDX     RL_B
        JSR     jr_add_x_a
        LDAA    [X]
        ADDA    [X + 1]
        LDAB    [X + 4]
        ADDB    [X + 5]
        CBA
        BNE     rl_draw_wrong
        LDAA    RL_ATTR_RIGHT
        STAA    [JR_RT_COLOR]
        LDAA    0x2a
        BRA     rl_draw_mark
rl_draw_wrong:
        LDAA    RL_ATTR_WRONG
        STAA    [JR_RT_COLOR]
        LDAA    0x58
rl_draw_mark:
        LDAB    15
        JSR     rl_put
rl_draw_sum_next:
        INC     [RL_DI]
        LDAA    [RL_DI]
        CMPA    3
        BEQ     rl_draw_order
        JMP     rl_draw_sum
rl_draw_order:
        ; A < D or A > D
        LDAA    17
        STAA    [RL_DY]
        LDAA    RL_ATTR_RUNE
        STAA    [JR_RT_COLOR]
        LDAA    0x41
        LDAB    3
        JSR     rl_put
        LDAA    0x44
        LDAB    7
        JSR     rl_put
        LDAA    RL_ATTR_SUM
        STAA    [JR_RT_COLOR]
        LDAA    0x3e
        LDAB    [RL_D]
        CMPB    [RL_D + 3]
        BCC     rl_draw_order_put
        LDAA    0x3c
rl_draw_order_put:
        LDAB    5
        JSR     rl_put
        ; the lexicon: A-D with their dials
        CLR     [RL_DI]
rl_draw_letter:
        LDAA    [RL_DI]
        ASLA
        ASLA
        ADDA    4
        STAA    [RL_DY]
        LDAA    RL_ATTR_LEX
        STAA    [JR_RT_COLOR]
        LDAA    [RL_DI]
        ADDA    0x41
        LDAB    21
        JSR     rl_put
        LDAA    RL_ATTR_VALUE
        STAA    [JR_RT_COLOR]
        LDAA    0x2d
        TST     [RL_TURNING]
        BEQ     rl_draw_value
        LDAB    [RL_DI]
        CMPB    [RL_CURSOR]
        BEQ     rl_draw_value_put
rl_draw_value:
        LDAA    [RL_DI]
        LDX     RL_B
        JSR     jr_add_x_a
        LDAA    [X]
        ADDA    0x30
rl_draw_value_put:
        LDAB    25
        JSR     rl_put
        INC     [RL_DI]
        LDAA    [RL_DI]
        CMPA    4
        BNE     rl_draw_letter
        LDAA    RL_ATTR_VALUE
        STAA    [JR_RT_COLOR]
        LDAA    [RL_CURSOR]
        ASLA
        ASLA
        ADDA    4
        STAA    [RL_DY]
        LDAA    0x3e
        LDAB    19
        JSR     rl_put
        TST     [RL_CHECK]
        BEQ     rl_draw_tries
        LDAA    [RL_CHECK]
        DECA
        ASLA
        ASLA
        ADDA    4
        STAA    [RL_DY]
        LDAA    0x2a
        LDAB    28
        JSR     rl_put
rl_draw_tries:
        LDAA    RL_ATTR_TEXT
        LDAB    [RL_ERRORS]
        CMPB    4
        BCS     rl_draw_tries_colour
        LDAA    RL_ATTR_BAD
rl_draw_tries_colour:
        STAA    [JR_RT_COLOR]
        LDAA    27
        LDAB    20
        JSR     jr_gfx_at
        LDAA    5
        SUBA    [RL_ERRORS]
        JMP     jr_gfx_dec2

game_draw_title:
        LDX     rl_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    RL_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    RL_ATTR_PILLAR
        STAA    [JR_RT_COLOR]
        LDAA    8
        LDAB    3
        JSR     jr_gfx_at
        LDAA    RL_TILE_PILLAR
        JSR     jr_gfx_tile
        LDAA    22
        LDAB    3
        JSR     jr_gfx_at
        LDAA    RL_TILE_PILLAR
        JSR     jr_gfx_tile
        LDAA    RL_ATTR_TABLET
        STAA    [JR_RT_COLOR]
        LDAA    15
        LDAB    3
        JSR     jr_gfx_at
        LDAA    RL_TILE_TABLET
        JSR     jr_gfx_tile
        LDX     rl_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    RL_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     rl_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

rl_table:
        .db     1, 2, 4, 3, 1, 3, 2, 4, 1, 3, 4, 2, 1, 4, 2, 3, 1, 4, 3, 2
        .db     2, 1, 3, 4, 2, 3, 1, 4, 2, 3, 4, 1, 2, 4, 1, 3, 2, 4, 3, 1
        .db     3, 1, 2, 4, 3, 1, 4, 2, 3, 2, 1, 4, 3, 2, 4, 1, 3, 4, 2, 1
        .db     4, 1, 2, 3, 4, 1, 3, 2, 4, 2, 1, 3, 4, 2, 3, 1, 4, 3, 1, 2
; x, width
rl_stone_box:
        .db     1, 16
rl_tablet_box:
        .db     18, 12

rl_hud:
        .db     1, 0, RL_ATTR_TITLE
        .dw     rl_txt_name
        .db     22, 0, RL_ATTR_LABEL
        .dw     rl_txt_ruin
        .db     1, 2, RL_ATTR_LABEL
        .dw     rl_txt_inscriptions
        .db     19, 2, RL_ATTR_LABEL
        .dw     rl_txt_lexicon
        .db     20, 20, RL_ATTR_LABEL
        .dw     rl_txt_tries
        .db     0xff
rl_title_lines:
        .db     10, 8, RL_ATTR_TITLE
        .dw     rl_txt_name
        .db     4, 10, RL_ATTR_LABEL
        .dw     rl_txt_tagline
        .db     8, 15, RL_ATTR_TEXT
        .dw     rl_txt_start
        .db     5, 17, RL_ATTR_TEXT
        .dw     rl_txt_howto
        .db     4, 22, RL_ATTR_DIM
        .dw     rl_txt_credit
        .db     0xff
rl_help_lines:
        .db     10, 2, RL_ATTR_TITLE
        .dw     rl_txt_name
        .db     1, 5, RL_ATTR_TEXT
        .dw     rl_help_1
        .db     1, 7, RL_ATTR_TEXT
        .dw     rl_help_2
        .db     1, 9, RL_ATTR_TEXT
        .dw     rl_help_3
        .db     1, 11, RL_ATTR_TEXT
        .dw     rl_help_4
        .db     1, 13, RL_ATTR_TEXT
        .dw     rl_help_5
        .db     1, 15, RL_ATTR_TEXT
        .dw     rl_help_6
        .db     1, 17, RL_ATTR_TEXT
        .dw     rl_help_7
        .db     1, 21, RL_ATTR_LABEL
        .dw     rl_help_back
        .db     0xff

rl_txt_name:
        .db     "RUIN LEXICON", 0
rl_txt_ruin:
        .db     "RUIN", 0
rl_txt_inscriptions:
        .db     "INSCRIPTIONS", 0
rl_txt_lexicon:
        .db     "LEXICON", 0
rl_txt_tries:
        .db     "TRIES", 0
rl_txt_lose:
        .db     "FIVE DICTIONARIES REJECTED", 0
rl_txt_tagline:
        .db     "FOUR RUNES, VALUES 1 TO 4", 0
rl_txt_start:
        .db     "RETURN : START", 0
rl_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
rl_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
rl_help_1:
        .db     "A/D : SELECT A LETTER", 0
rl_help_2:
        .db     "W/S : CHANGE ITS VALUE 1 TO 4", 0
rl_help_3:
        .db     "USE EACH VALUE EXACTLY ONCE.", 0
rl_help_4:
        .db     "THREE SUMS AND A<D OR A>D", 0
rl_help_5:
        .db     "RETURN : CHECK YOUR DICTIONARY", 0
rl_help_6:
        .db     "FIVE WRONG GUESSES LOSE.", 0
rl_help_7:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
rl_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     rl_sfx_click, rl_sfx_click, rl_jingle_win, rl_jingle_lose
rl_sfx_click:
        .db     110, 2, 0, 0
rl_sfx_buzz:
        .db     240, 6, 0, 2, 240, 6, 0, 0

; Title: an old modal chant in D dorian, quarter note = 18 frames, looping.
rl_title_song:
        .db     1
        .dw     rl_title_melody, rl_title_harmony, rl_title_bass
rl_title_melody:
        .db     AU_D5, 18, AU_F5, 18, AU_G5, 18, AU_A5, 36, AU_G5, 18
        .db     AU_F5, 18, AU_E5, 18, AU_D5, 36, AU_C5, 18
        .db     AU_D5, 18, AU_E5, 18, AU_F5, 36, AU_E5, 18
        .db     AU_C5, 18, AU_B4, 18, AU_D5, 54, 0, 0
rl_title_harmony:
        .db     AU_A4, 54, AU_D5, 54, AU_A4, 54, AU_G4, 54
        .db     AU_A4, 54, AU_C5, 54, AU_G4, 36, AU_A4, 54, 0, 0
rl_title_bass:
        .db     AU_D3, 54, AU_D3, 54, AU_C3, 54, AU_G2, 54
        .db     AU_D3, 54, AU_A2, 54, AU_G2, 36, AU_D3, 54, 0, 0

; Deciphered: D major arpeggio over the tonic (54 frames).
rl_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     rl_win_melody, rl_win_harmony, rl_win_bass
rl_win_melody:
        .db     AU_D5, 8, AU_FS5, 8, AU_A5, 8, AU_D6, 30, 0, 0
rl_win_harmony:
        .db     AU_A4, 8, AU_D5, 8, AU_FS5, 8, AU_A5, 30, 0, 0
rl_win_bass:
        .db     AU_D3, 24, AU_D2, 30, 0, 0
rl_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     rl_lose_melody, rl_lose_harmony, rl_lose_bass
rl_lose_melody:
        .db     AU_A4, 12, AU_G4, 12, AU_F4, 12, AU_E4, 30, 0, 0
rl_lose_harmony:
        .db     AU_F4, 12, AU_E4, 12, AU_D4, 12, AU_CS4, 30, 0, 0
rl_lose_bass:
        .db     AU_D3, 36, AU_A2, 30, 0, 0

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
