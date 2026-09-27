; SPDX-License-Identifier: MIT
; GRAVITY WELL for JR-200: a port of jr100dev games/gravity_well/rules.py 1.7.1.
; The forty wells (upstream levels.json), tilting the room so both balls roll
; together (up to six steps, swept in upstream order), the two sockets,
; optional runes, moves against par and the star rating follow the upstream
; source. The ranked campaign (stage map, best ratings and passwords) is
; sdk/ranked.inc; display, colour and three-voice sound use the JR-200 port SDK.
        .filename.jr "GRAVITY-WELL"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4740
JR_AUDIO:           .equ    0x4740
JR_RANK:            .equ    0x4760
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    40
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_PASSWORD_TAG:  .equ    0xa4
GAME_STAR_CODE:     .equ    0x10
GAME_STAR_ATTR:     .equ    0x46

; Upstream state (same order as tests/model.py), then b[64], c[0-63] (balls)
; and c[64-127] (where each ball rolls from); the stage's balls, runes and par
; follow.
GW_FILLED:          .equ    GAME_STATE
GW_PAR:             .equ    GAME_STATE + 1
RANK_MOVES:         .equ    GAME_STATE + 2
RANK_OVERFLOW:      .equ    GAME_STATE + 3
RANK_RUNES:         .equ    GAME_STATE + 4
RANK_STARS:         .equ    GAME_STATE + 5
GW_B:               .equ    GAME_STATE + 6
GW_C:               .equ    GAME_STATE + 70
GW_TAIL:            .equ    GAME_STATE + 198    ; d[64-69]
RANK_RUNE_A:        .equ    GW_TAIL + 3
RANK_RUNE_B:        .equ    GW_TAIL + 4
RANK_PAR:           .equ    GW_TAIL + 5
; Rule and drawing work bytes.
GW_I:               .equ    GAME_STATE + 204
GW_T:               .equ    GAME_STATE + 205
GW_K:               .equ    GAME_STATE + 206
GW_N:               .equ    GAME_STATE + 207
GW_ACT:             .equ    GAME_STATE + 208
GW_STEP:            .equ    GAME_STATE + 209
GW_MOVED:           .equ    GAME_STATE + 210
GW_CHANGED:         .equ    GAME_STATE + 211
GW_DI:              .equ    GAME_STATE + 212
GW_DCODE:           .equ    GAME_STATE + 213
GW_DX:              .equ    GAME_STATE + 214
GW_DT:              .equ    GAME_STATE + 215
GW_DY:              .equ    GAME_STATE + 216

GW_TILE_FLOOR:      .equ    0x80
GW_TILE_WALL:       .equ    0x84
GW_TILE_SOCKET:     .equ    0x88
GW_TILE_BALL:       .equ    0x8c
GW_TILE_RUNE:       .equ    0x90
GW_ATTR_FLOOR:      .equ    0x41
GW_ATTR_WALL:       .equ    0x47
GW_ATTR_SOCKET:     .equ    0x43
GW_ATTR_BALL:       .equ    0x45        ; a cyan steel ball
GW_ATTR_BALL_IN:    .equ    0x67        ; a ball in its socket: white on green
GW_ATTR_RUNE:       .equ    0x46
GW_ATTR_TEXT:       .equ    0x07
GW_ATTR_LABEL:      .equ    0x04
GW_ATTR_TITLE:      .equ    0x06
GW_ATTR_DIM:        .equ    0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     gw_patterns
        LDAA    GW_TILE_FLOOR
        LDAB    20
        JSR     jr_pcg_load
        LDX     jr_rank_star_patterns
        LDAA    GAME_STAR_CODE
        LDAB    2
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; A = stage -> X = its packed data (38 bytes).
gw_stage:
        STAA    [GW_T]
        LDX     gw_levels
gw_stage_next:
        TST     [GW_T]
        BEQ     gw_stage_done
        LDAA    38
        JSR     jr_add_x_a
        DEC     [GW_T]
        BRA     gw_stage_next
gw_stage_done:
        RTS

game_level_par:
        JSR     gw_stage
        LDAA    [X + 37]
        RTS

game_init:
        JSR     jr_music_stop
        LDAA    [JR_PORT_LEVEL]
        JSR     gw_stage
        CLR     [GW_I]
gw_init_unpack:
        LDAA    [X]
        STX     [JR_RT_TABLE]
        PSHA
        LDAA    [GW_I]
        ASLA
        LDX     GW_B
        JSR     jr_add_x_a
        PULA
        TAB
        LSRA
        LSRA
        LSRA
        LSRA
        STAA    [X]
        ANDB    15
        STAB    [X + 1]
        LDX     [JR_RT_TABLE]
        INX
        INC     [GW_I]
        LDAA    [GW_I]
        CMPA    32
        BNE     gw_init_unpack
        CLRB
gw_init_tail:
        LDAA    [X]
        STX     [JR_RT_TABLE]
        PSHA
        TBA
        LDX     GW_TAIL
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        LDX     [JR_RT_TABLE]
        INX
        INCB
        CMPB    6
        BNE     gw_init_tail
        JSR     gw_origins
        LDAA    [GW_TAIL]
        JSR     gw_cell
        LDAA    1
        STAA    [X + 64]
        LDAA    [GW_TAIL + 1]
        JSR     gw_cell
        LDAA    1
        STAA    [X + 64]
        LDAA    [RANK_PAR]
        STAA    [GW_PAR]
        RTS

; c[64 + i] = i: every ball rests on its own cell.
gw_origins:
        LDX     GW_C
        CLRA
gw_origins_next:
        STAA    [X + 64]
        INX
        INCA
        CMPA    64
        BNE     gw_origins_next
        RTS

; A = cell -> X = b[cell]; c[cell] is [X + 64], c[64 + cell] is [X + 128].
gw_cell:
        LDX     GW_B
        JMP     jr_add_x_a

game_raw_key:
game_tick:
        RTS

; Tilt: up to six sweeps, each rolling every free ball one cell (from the far
; side for down and right, as upstream), with a step of animation per sweep.
game_act:
        TSTA
        BNE     gw_act_done_near193
        JMP     gw_act_done
gw_act_done_near193:
        CMPA    JR_KEY_CONFIRM
        BCS     gw_act_done_near197
        JMP     gw_act_done
gw_act_done_near197:
        STAA    [GW_ACT]
        CLR     [GW_CHANGED]
        LDAA    6
        STAA    [GW_STEP]
gw_act_sweep:
        CLR     [GW_MOVED]
        CLR     [GW_K]
gw_act_ball:
        LDAA    [GW_K]
        LDAB    [GW_ACT]
        CMPB    JR_KEY_DOWN
        BEQ     gw_act_reverse
        CMPB    JR_KEY_RIGHT
        BNE     gw_act_index
gw_act_reverse:
        EORA    63
gw_act_index:
        STAA    [GW_I]
        JSR     gw_cell
        TST     [X + 64]
        BEQ     gw_act_next
        LDAA    [GW_I]
        LDAB    [GW_ACT]
        JSR     gw_move
        STAA    [GW_N]
        JSR     gw_cell
        LDAA    [X]
        CMPA    1
        BEQ     gw_act_next
        TST     [X + 64]
        BNE     gw_act_next
        LDAA    1
        STAA    [X + 64]
        STAA    [GW_MOVED]
        STAA    [GW_CHANGED]
        LDAA    [GW_I]
        STAA    [X + 128]
        JSR     gw_cell
        CLR     [X + 64]
        LDAA    [GW_N]
        JSR     jr_rank_take
gw_act_next:
        INC     [GW_K]
        LDAA    [GW_K]
        CMPA    64
        BNE     gw_act_ball
        ; nothing rolled: later sweeps cannot roll either
        TST     [GW_MOVED]
        BEQ     gw_act_settled
        CLRA
        JSR     jr_port_sound
        LDAA    2
        JSR     jr_port_animate
        JSR     gw_origins
        DEC     [GW_STEP]
        BNE     gw_act_sweep
gw_act_settled:
        TST     [GW_CHANGED]
        BEQ     gw_act_sockets
        JSR     jr_rank_spend
        LDAA    1
        JSR     jr_port_sound
gw_act_sockets:
        ; both sockets hold a ball: the well is filled
        CLR     [GW_FILLED]
        LDX     GW_B
gw_act_socket:
        LDAA    [X]
        CMPA    3
        BNE     gw_act_socket_next
        TST     [X + 64]
        BEQ     gw_act_socket_next
        INC     [GW_FILLED]
gw_act_socket_next:
        INX
        CPX     GW_B + 64
        BNE     gw_act_socket
        LDAA    [GW_FILLED]
        CMPA    2
        BNE     gw_act_done
        JMP     jr_rank_clear
gw_act_done:
        RTS

; A = position, B = action 1-4 -> A = moved position (8x8, stops at edges).
gw_move:
        STAA    [GW_T]
        CMPB    JR_KEY_UP
        BNE     gw_move_down
        CMPA    8
        BCS     gw_move_done
        SUBA    8
        RTS
gw_move_down:
        CMPB    JR_KEY_DOWN
        BNE     gw_move_side
        CMPA    56
        BCC     gw_move_done
        ADDA    8
        RTS
gw_move_side:
        ANDA    7
        CMPB    JR_KEY_LEFT
        BNE     gw_move_right
        TSTA
        BEQ     gw_move_stay
        LDAA    [GW_T]
        DECA
        RTS
gw_move_right:
        CMPA    7
        BCC     gw_move_stay
        LDAA    [GW_T]
        INCA
        RTS
gw_move_stay:
        LDAA    [GW_T]
gw_move_done:
        RTS

; ---------------------------------------------------------------- drawing

; A = cell, B = the cell it rolls from -> A = x, B = y half-way between them
; (the board starts at column 1).
gw_between:
        STAB    [GW_DX]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        STAA    [GW_DT]
        STAB    [GW_DY]
        LDAA    [GW_DX]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        ADDA    [GW_DT]
        INCA
        ADDB    [GW_DY]
        ADDB    3
        RTS

game_draw:
        LDAA    0x20
        LDAB    GW_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     gw_hud
        JSR     jr_gfx_lines
        CLR     [GW_DI]
gw_draw_cell:
        LDAA    [GW_DI]
        JSR     gw_cell
        LDAA    [X]
        ASLA
        LDX     gw_looks
        JSR     jr_add_x_a
        LDAB    [X + 1]
        LDAA    [X]
        STAA    [GW_DCODE]
        LDAA    [GW_DI]
        CMPA    [RANK_RUNE_A]
        BNE     gw_draw_rune_b
        LDAA    [RANK_RUNES]
        ANDA    1
        BNE     gw_draw_put
        BRA     gw_draw_rune
gw_draw_rune_b:
        CMPA    [RANK_RUNE_B]
        BNE     gw_draw_put
        LDAA    [RANK_RUNES]
        ANDA    2
        BNE     gw_draw_put
gw_draw_rune:
        LDAA    GW_TILE_RUNE
        STAA    [GW_DCODE]
        LDAB    GW_ATTR_RUNE
gw_draw_put:
        STAB    [JR_RT_COLOR]
        LDAA    [GW_DI]
        TAB
        JSR     gw_between
        JSR     jr_gfx_at
        LDAA    [GW_DCODE]
        JSR     jr_gfx_tile
        INC     [GW_DI]
        LDAA    [GW_DI]
        CMPA    64
        BNE     gw_draw_cell
        ; the balls, half-way along a roll
        CLR     [GW_DI]
gw_draw_ball:
        LDAA    [GW_DI]
        JSR     gw_cell
        TST     [X + 64]
        BEQ     gw_draw_ball_next
        LDAB    GW_ATTR_BALL
        LDAA    [X]
        CMPA    3
        BNE     gw_draw_ball_colour
        LDAA    [X + 128]
        CMPA    [GW_DI]
        BNE     gw_draw_ball_colour
        LDAB    GW_ATTR_BALL_IN
gw_draw_ball_colour:
        STAB    [JR_RT_COLOR]
        LDAB    [X + 128]
        LDAA    [GW_DI]
        JSR     gw_between
        JSR     jr_gfx_at
        LDAA    GW_TILE_BALL
        JSR     jr_gfx_tile
gw_draw_ball_next:
        INC     [GW_DI]
        LDAA    [GW_DI]
        CMPA    64
        BNE     gw_draw_ball
        ; the panel: filled sockets, the ball and the rune
        LDAA    GW_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    28
        LDAB    5
        JSR     jr_gfx_at
        LDAA    [GW_FILLED]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    GW_ATTR_BALL
        STAA    [JR_RT_COLOR]
        LDAA    20
        LDAB    12
        JSR     jr_gfx_at
        LDAA    GW_TILE_BALL
        JSR     jr_gfx_tile
        LDAA    GW_ATTR_RUNE
        STAA    [JR_RT_COLOR]
        LDAA    25
        LDAB    12
        JSR     jr_gfx_at
        LDAA    GW_TILE_RUNE
        JSR     jr_gfx_tile
        JMP     jr_rank_hud

game_draw_title:
        LDX     gw_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    GW_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     gw_title_tiles
        STX     [JR_RT_TABLE]
gw_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     gw_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [GW_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [GW_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     gw_title_tile
gw_title_text:
        LDX     gw_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    GW_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     gw_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

game_key_table:
        .db     0x78, 7, 0x66, 8, 0
game_title_text:
        .db     "GRAVITY WELL", 0
; by cell kind 0-3: code, attribute
gw_looks:
        .db     GW_TILE_FLOOR, GW_ATTR_FLOOR, GW_TILE_WALL, GW_ATTR_WALL
        .db     GW_TILE_FLOOR, GW_ATTR_FLOOR, GW_TILE_SOCKET, GW_ATTR_SOCKET

; x, attribute, code, y: a ball dropping down a shaft into its socket
gw_title_tiles:
        .db     12, GW_ATTR_WALL, GW_TILE_WALL, 1
        .db     14, GW_ATTR_BALL, GW_TILE_BALL, 1
        .db     16, GW_ATTR_WALL, GW_TILE_WALL, 1
        .db     12, GW_ATTR_WALL, GW_TILE_WALL, 3
        .db     14, GW_ATTR_FLOOR, GW_TILE_FLOOR, 3
        .db     16, GW_ATTR_WALL, GW_TILE_WALL, 3
        .db     12, GW_ATTR_WALL, GW_TILE_WALL, 5
        .db     14, GW_ATTR_BALL_IN, GW_TILE_BALL, 5
        .db     16, GW_ATTR_WALL, GW_TILE_WALL, 5
        .db     20, GW_ATTR_RUNE, GW_TILE_RUNE, 3
        .db     8, GW_ATTR_SOCKET, GW_TILE_SOCKET, 3
        .db     0xff

gw_hud:
        .db     1, 0, GW_ATTR_TITLE
        .dw     game_title_text
        .db     20, 3, GW_ATTR_LABEL
        .dw     gw_txt_gravity
        .db     20, 5, GW_ATTR_LABEL
        .dw     gw_txt_sockets
        .db     19, 16, GW_ATTR_DIM
        .dw     gw_txt_roll
        .db     0xff
gw_title_lines:
        .db     10, 8, GW_ATTR_TITLE
        .dw     game_title_text
        .db     2, 10, GW_ATTR_LABEL
        .dw     gw_txt_tagline
        .db     4, 15, GW_ATTR_TEXT
        .dw     gw_txt_start
        .db     4, 17, GW_ATTR_DIM
        .dw     gw_txt_credit
        .db     0xff
gw_help_lines:
        .db     10, 1, GW_ATTR_TITLE
        .dw     game_title_text
        .db     1, 3, GW_ATTR_TEXT
        .dw     gw_help_1
        .db     1, 5, GW_ATTR_TEXT
        .dw     gw_help_2
        .db     1, 7, GW_ATTR_TEXT
        .dw     gw_help_3
        .db     1, 9, GW_ATTR_TEXT
        .dw     gw_help_4
        .db     1, 11, GW_ATTR_TEXT
        .dw     gw_help_5
        .db     1, 13, GW_ATTR_TEXT
        .dw     gw_help_6
        .db     1, 15, GW_ATTR_TEXT
        .dw     gw_help_7
        .db     1, 17, GW_ATTR_TEXT
        .dw     gw_help_8
        .db     1, 19, GW_ATTR_TEXT
        .dw     gw_help_9
        .db     1, 21, GW_ATTR_LABEL
        .dw     gw_help_back
        .db     0xff

gw_txt_gravity:
        .db     "GRAVITY", 0
gw_txt_sockets:
        .db     "SOCKETS  /2", 0
gw_txt_roll:
        .db     "ROLL / RUNE", 0
gw_txt_tagline:
        .db     "TILT THE ROOM, ROLL BOTH BALLS", 0
gw_txt_start:
        .db     "RETURN : PLAY THE STAGE", 0
gw_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
gw_help_1:
        .db     "WASD : TILT THE ROOM", 0
gw_help_2:
        .db     "BOTH BALLS ROLL TOGETHER.", 0
gw_help_3:
        .db     "FILL BOTH DIAMOND SOCKETS.", 0
gw_help_4:
        .db     "ROLL OVER OPTIONAL RUNES.", 0
gw_help_5:
        .db     "PAR OR LESS = TWO STARS.", 0
gw_help_6:
        .db     "PLUS BOTH RUNES = THREE STARS.", 0
gw_help_7:
        .db     "OVER PAR = CLEAR / ONE STAR.", 0
gw_help_8:
        .db     "SPACE RETRY / F STAGE SELECT", 0
gw_help_9:
        .db     "X : PASSWORD (TITLE / MAP)", 0
gw_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     gw_sfx_roll, gw_sfx_settle, gw_jingle_win, gw_jingle_lose
gw_sfx_roll:
        .db     90, 1, 80, 1, 0, 0
gw_sfx_settle:
        .db     54, 3, 72, 6, 0, 0

; Title: a tumbling waltz in A minor, eighth note = 8 frames, looping.
gw_title_song:
        .db     1
        .dw     gw_title_melody, gw_title_harmony, gw_title_bass
gw_title_melody:
        .db     AU_E5, 16, AU_C5, 8, AU_A4, 8, AU_E4, 16
        .db     AU_F5, 16, AU_D5, 8, AU_B4, 8, AU_F4, 16
        .db     AU_E5, 8, AU_D5, 8, AU_C5, 8, AU_B4, 8, AU_A4, 8, AU_GS4, 8
        .db     AU_A4, 24, AU_E4, 8, AU_A4, 16, 0, 0
gw_title_harmony:
        .db     AU_C5, 48, AU_D5, 48, AU_C5, 24, AU_B4, 24, AU_C5, 48, 0, 0
gw_title_bass:
        .db     AU_A2, 16, AU_E3, 16, AU_E3, 16, AU_D2, 16, AU_A2, 16, AU_A2, 16
        .db     AU_A2, 16, AU_E3, 16, AU_E2, 16, AU_A2, 16, AU_E3, 16, AU_A3, 16, 0, 0

; Well filled: A major arpeggio over the tonic (54 frames).
gw_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     gw_win_melody, gw_win_harmony, gw_win_bass
gw_win_melody:
        .db     AU_A5, 8, AU_CS6, 8, AU_E6, 8, AU_A6, 30, 0, 0
gw_win_harmony:
        .db     AU_E5, 8, AU_A5, 8, AU_CS6, 8, AU_E6, 30, 0, 0
gw_win_bass:
        .db     AU_A3, 24, AU_A2, 30, 0, 0
gw_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     gw_lose_melody, gw_lose_harmony, gw_lose_bass
gw_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
gw_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
gw_lose_bass:
        .db     AU_FS3, 36, AU_CS3, 30, 0, 0

        .include "art.inc"
        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys_ext.inc"
        .include "../../../sdk/gfx.inc"
        .include "../../../sdk/font.inc"
        .include "../../../sdk/pcg.inc"
        .include "../../../sdk/frame.inc"
        .include "../../../sdk/math.inc"
        .include "../../../sdk/sound.inc"
        .include "../../../sdk/audio.inc"
        .include "../../../sdk/audio_notes.inc"
        .include "../../../sdk/ranked.inc"
        .include "../../../sdk/font_data.inc"
