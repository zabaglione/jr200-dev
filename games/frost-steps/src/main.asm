; SPDX-License-Identifier: MIT
; FROST STEPS for JR-200: a port of jr100dev games/frost_steps/rules.py 1.7.2.
; The forty chambers (upstream levels.json), sliding to the next wall,
; crystals, optional runes, moves against par and the three-star rating
; follow the upstream source. The ranked campaign (stage map, best ratings
; and passwords) is sdk/ranked.inc; display, colour and three-voice sound use
; the JR-200 port SDK.
        .filename.jr "FROST-STEPS"
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
GAME_PASSWORD_TAG:  .equ    0x41
GAME_STAR_CODE:     .equ    0x00
GAME_STAR_ATTR:     .equ    0x46

; Upstream state (same order as tests/model.py), then b[64], c[64] and the
; stage's d[70].
FS_FACING:          .equ    GAME_STATE
FS_POS:             .equ    GAME_STATE + 1
FS_ORIGIN:          .equ    GAME_STATE + 2
FS_LEFT:            .equ    GAME_STATE + 3
FS_PAR:             .equ    GAME_STATE + 4
RANK_MOVES:         .equ    GAME_STATE + 5
RANK_OVERFLOW:      .equ    GAME_STATE + 6
RANK_RUNES:         .equ    GAME_STATE + 7
RANK_STARS:         .equ    GAME_STATE + 8
FS_B:               .equ    GAME_STATE + 9
FS_C:               .equ    GAME_STATE + 73
FS_D:               .equ    GAME_STATE + 137
RANK_RUNE_A:        .equ    FS_D + 67
RANK_RUNE_B:        .equ    FS_D + 68
RANK_PAR:           .equ    FS_D + 69
; Rule and drawing work bytes.
FS_I:               .equ    GAME_STATE + 208
FS_T:               .equ    GAME_STATE + 209
FS_BEFORE:          .equ    GAME_STATE + 210
FS_STEP:            .equ    GAME_STATE + 211
FS_ACTION:          .equ    GAME_STATE + 212
FS_DI:              .equ    GAME_STATE + 220
FS_DCODE:           .equ    GAME_STATE + 221

FS_TILE_ICE:        .equ    0x80
FS_TILE_WALL:       .equ    0x84
FS_TILE_CRYSTAL:    .equ    0x88
FS_TILE_RUNE:       .equ    0x8c
FS_TILE_HERO:       .equ    0x90        ; + 4 * (facing - 1)
FS_ATTR_ICE:        .equ    0x4d        ; cyan frost on blue ice
FS_ATTR_WALL:       .equ    0x47
FS_ATTR_CRYSTAL:    .equ    0x4b        ; magenta crystal on ice
FS_ATTR_RUNE:       .equ    0x4e        ; yellow rune on ice
FS_ATTR_HERO:       .equ    0x4f
FS_ATTR_TEXT:       .equ    0x07
FS_ATTR_LABEL:      .equ    0x04
FS_ATTR_TITLE:      .equ    0x06
FS_ATTR_DIM:        .equ    0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     fs_patterns
        LDAA    FS_TILE_ICE
        LDAB    32
        JSR     jr_pcg_load
        LDX     jr_rank_star_patterns
        LDAA    GAME_STAR_CODE
        LDAB    2
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; A = stage -> X = its packed data (38 bytes).
fs_stage:
        LDAB    38
        STAA    [FS_T]
        LDX     fs_levels
fs_stage_next:
        TST     [FS_T]
        BEQ     fs_stage_done
        TBA
        JSR     jr_add_x_a
        DEC     [FS_T]
        LDAB    38
        BRA     fs_stage_next
fs_stage_done:
        RTS

game_level_par:
        JSR     fs_stage
        LDAA    [X + 37]
        RTS

game_init:
        JSR     jr_music_stop
        ; d[0-63] from nibbles, d[64-69] as they are
        LDAA    [JR_PORT_LEVEL]
        JSR     fs_stage
        CLR     [FS_I]
fs_init_unpack:
        LDAA    [X]
        PSHA
        LSRA
        LSRA
        LSRA
        LSRA
        STX     [JR_RT_TABLE]
        PSHA
        LDAA    [FS_I]
        ASLA
        LDX     FS_D
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        PULA
        ANDA    15
        STAA    [X + 1]
        LDX     [JR_RT_TABLE]
        INX
        INC     [FS_I]
        LDAA    [FS_I]
        CMPA    32
        BNE     fs_init_unpack
        CLRB
fs_init_tail:
        LDAA    [X]
        STX     [JR_RT_TABLE]
        PSHA
        TBA
        LDX     FS_D + 64
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        LDX     [JR_RT_TABLE]
        INX
        INCB
        CMPB    6
        BNE     fs_init_tail
        ; walls into b, crystals into c
        CLR     [FS_I]
fs_init_cells:
        LDAA    [FS_I]
        LDX     FS_D
        JSR     jr_add_x_a
        LDAA    [X]
        LDX     FS_B
        PSHA
        LDAA    [FS_I]
        JSR     jr_add_x_a
        PULA
        CMPA    1
        BNE     fs_init_crystal
        STAA    [X]
fs_init_crystal:
        CMPA    3
        BNE     fs_init_next
        LDAA    1
        STAA    [X + 64]
        INC     [FS_LEFT]
fs_init_next:
        INC     [FS_I]
        LDAA    [FS_I]
        CMPA    64
        BNE     fs_init_cells
        LDAA    2
        STAA    [FS_FACING]
        LDAA    [FS_D + 64]
        STAA    [FS_POS]
        STAA    [FS_ORIGIN]
        LDAA    [FS_D + 69]
        STAA    [FS_PAR]
        RTS

game_raw_key:
game_tick:
        RTS

; Slide up to seven cells until a wall; one slide is one move.
game_act:
        CMPA    JR_KEY_CONFIRM
        BCS     fs_act_done_near196
        JMP     fs_act_done
fs_act_done_near196:
        TSTA
        BEQ     fs_act_done
        STAA    [FS_FACING]
        STAA    [FS_ACTION]
        LDAA    [FS_POS]
        STAA    [FS_BEFORE]
        LDAA    7
        STAA    [FS_STEP]
fs_slide:
        LDAA    [FS_POS]
        LDAB    [FS_ACTION]
        JSR     fs_move
        CMPA    [FS_POS]
        BEQ     fs_slide_next
        STAA    [FS_T]
        LDX     FS_B
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    1
        BEQ     fs_slide_next
        LDAA    [FS_POS]
        CMPA    [FS_BEFORE]
        BNE     fs_slide_go
        JSR     jr_rank_spend
fs_slide_go:
        LDAA    [FS_POS]
        STAA    [FS_ORIGIN]
        LDAA    [FS_T]
        STAA    [FS_POS]
        JSR     jr_rank_take
        LDAA    [FS_POS]
        LDX     FS_C
        JSR     jr_add_x_a
        TST     [X]
        BEQ     fs_slide_ice
        CLR     [X]
        DEC     [FS_LEFT]
        LDAA    1
        JSR     jr_port_sound
        BRA     fs_slide_show
fs_slide_ice:
        CLRA
        JSR     jr_port_sound
fs_slide_show:
        LDAA    2
        JSR     jr_port_animate
        LDAA    [FS_POS]
        STAA    [FS_ORIGIN]
fs_slide_next:
        DEC     [FS_STEP]
        BNE     fs_slide
        TST     [FS_LEFT]
        BNE     fs_act_done
        JMP     jr_rank_clear
fs_act_done:
        RTS

; A = position, B = action 1-4 -> A = moved position (8x8, stops at edges).
fs_move:
        STAA    [FS_I]
        CMPB    JR_KEY_UP
        BNE     fs_move_down
        CMPA    8
        BCS     fs_move_done
        SUBA    8
        RTS
fs_move_down:
        CMPB    JR_KEY_DOWN
        BNE     fs_move_side
        CMPA    56
        BCC     fs_move_done
        ADDA    8
        RTS
fs_move_side:
        ANDA    7
        CMPB    JR_KEY_LEFT
        BNE     fs_move_right
        TSTA
        BEQ     fs_move_stay
        LDAA    [FS_I]
        DECA
        RTS
fs_move_right:
        CMPA    7
        BCC     fs_move_stay
        LDAA    [FS_I]
        INCA
        RTS
fs_move_stay:
        LDAA    [FS_I]
fs_move_done:
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    FS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     fs_hud
        JSR     jr_gfx_lines
        ; the chamber: ice, walls, crystals and the runes still to take
        CLR     [FS_DI]
fs_draw_cell:
        LDAA    [FS_DI]
        LDX     FS_B
        JSR     jr_add_x_a
        LDAA    FS_TILE_ICE
        LDAB    FS_ATTR_ICE
        TST     [X]
        BEQ     fs_draw_crystal
        LDAA    FS_TILE_WALL
        LDAB    FS_ATTR_WALL
fs_draw_crystal:
        TST     [X + 64]
        BEQ     fs_draw_rune
        LDAA    FS_TILE_CRYSTAL
        LDAB    FS_ATTR_CRYSTAL
fs_draw_rune:
        STAA    [FS_DCODE]
        LDAA    [FS_DI]
        CMPA    [RANK_RUNE_A]
        BNE     fs_draw_rune_b
        LDAA    [RANK_RUNES]
        ANDA    1
        BNE     fs_draw_put
        BRA     fs_draw_rune_tile
fs_draw_rune_b:
        CMPA    [RANK_RUNE_B]
        BNE     fs_draw_put
        LDAA    [RANK_RUNES]
        ANDA    2
        BNE     fs_draw_put
fs_draw_rune_tile:
        LDAA    FS_TILE_RUNE
        STAA    [FS_DCODE]
        LDAB    FS_ATTR_RUNE
fs_draw_put:
        STAB    [JR_RT_COLOR]
        LDAA    [FS_DI]
        TAB
        LSRB
        LSRB
        LSRB
        ASLB
        ADDB    3
        ANDA    7
        ASLA
        JSR     jr_gfx_at
        LDAA    [FS_DCODE]
        JSR     jr_gfx_tile
        INC     [FS_DI]
        LDAA    [FS_DI]
        CMPA    64
        BNE     fs_draw_cell
        ; the skater, half-way between cells while sliding
        LDAA    FS_ATTR_HERO
        STAA    [JR_RT_COLOR]
        LDAA    [FS_POS]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        STAA    [FS_DI]
        STAB    [FS_DCODE]
        LDAA    [FS_ORIGIN]
        TAB
        ANDA    7
        LSRB
        LSRB
        LSRB
        ADDA    [FS_DI]
        ADDB    [FS_DCODE]
        ADDB    3
        JSR     jr_gfx_at
        LDAA    [FS_FACING]
        DECA
        ASLA
        ASLA
        ADDA    FS_TILE_HERO
        JSR     jr_gfx_tile
        ; the compass: crystals left
        LDAA    FS_ATTR_CRYSTAL
        STAA    [JR_RT_COLOR]
        LDAA    20
        LDAB    7
        JSR     jr_gfx_at
        LDAA    FS_TILE_CRYSTAL
        JSR     jr_gfx_tile
        LDAA    FS_ATTR_RUNE
        STAA    [JR_RT_COLOR]
        LDAA    22
        LDAB    13
        JSR     jr_gfx_at
        LDAA    FS_TILE_RUNE
        JSR     jr_gfx_tile
        LDAA    FS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [FS_LEFT]
        JSR     jr_gfx_dec2
        JMP     jr_rank_hud

game_draw_title:
        LDX     fs_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    FS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     fs_title_tiles
        STX     [JR_RT_TABLE]
fs_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     fs_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [FS_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [FS_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     fs_title_tile
fs_title_text:
        LDX     fs_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    FS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     fs_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

game_key_table:
        .db     0x78, 7, 0x66, 8, 0
game_title_text:
        .db     "FROST STEPS", 0

; x, attribute, code, y
fs_title_tiles:
        .db     8, FS_ATTR_ICE, FS_TILE_ICE, 3
        .db     10, FS_ATTR_HERO, FS_TILE_HERO + 12, 3
        .db     12, FS_ATTR_ICE, FS_TILE_ICE, 3
        .db     14, FS_ATTR_CRYSTAL, FS_TILE_CRYSTAL, 3
        .db     16, FS_ATTR_ICE, FS_TILE_ICE, 3
        .db     18, FS_ATTR_RUNE, FS_TILE_RUNE, 3
        .db     20, FS_ATTR_WALL, FS_TILE_WALL, 3
        .db     0xff

fs_hud:
        .db     1, 0, FS_ATTR_TITLE
        .dw     game_title_text
        .db     19, 3, FS_ATTR_LABEL
        .dw     fs_txt_compass
        .db     20, 5, FS_ATTR_LABEL
        .dw     fs_txt_crystals
        .db     19, 11, FS_ATTR_LABEL
        .dw     fs_txt_runes
        .db     19, 16, FS_ATTR_DIM
        .dw     fs_txt_optional
        .db     0xff
fs_title_lines:
        .db     10, 8, FS_ATTR_TITLE
        .dw     game_title_text
        .db     3, 10, FS_ATTR_LABEL
        .dw     fs_txt_tagline
        .db     4, 15, FS_ATTR_TEXT
        .dw     fs_txt_start
        .db     4, 17, FS_ATTR_DIM
        .dw     fs_txt_credit
        .db     0xff
fs_help_lines:
        .db     10, 1, FS_ATTR_TITLE
        .dw     game_title_text
        .db     1, 3, FS_ATTR_TEXT
        .dw     fs_help_1
        .db     1, 5, FS_ATTR_TEXT
        .dw     fs_help_2
        .db     1, 7, FS_ATTR_TEXT
        .dw     fs_help_3
        .db     1, 9, FS_ATTR_TEXT
        .dw     fs_help_4
        .db     1, 11, FS_ATTR_TEXT
        .dw     fs_help_5
        .db     1, 13, FS_ATTR_TEXT
        .dw     fs_help_6
        .db     1, 15, FS_ATTR_TEXT
        .dw     fs_help_7
        .db     1, 17, FS_ATTR_TEXT
        .dw     fs_help_8
        .db     1, 19, FS_ATTR_TEXT
        .dw     fs_help_9
        .db     1, 21, FS_ATTR_LABEL
        .dw     fs_help_back
        .db     0xff

fs_txt_compass:
        .db     "ICE COMPASS", 0
fs_txt_crystals:
        .db     "CRYSTALS", 0
fs_txt_runes:
        .db     "ICE RUNES", 0
fs_txt_optional:
        .db     "OPTIONAL", 0
fs_txt_tagline:
        .db     "SLIDE TO EVERY CRYSTAL", 0
fs_txt_start:
        .db     "RETURN : PLAY THE STAGE", 0
fs_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
fs_help_1:
        .db     "WASD : SLIDE TO A WALL", 0
fs_help_2:
        .db     "TAKE ALL DIAMOND CRYSTALS.", 0
fs_help_3:
        .db     "ROUND RUNES ARE OPTIONAL.", 0
fs_help_4:
        .db     "PAR OR LESS = TWO STARS.", 0
fs_help_5:
        .db     "PLUS BOTH RUNES = THREE STARS.", 0
fs_help_6:
        .db     "OVER PAR = CLEAR / ONE STAR.", 0
fs_help_7:
        .db     "SPACE RETRY / F STAGE SELECT", 0
fs_help_8:
        .db     "X : PASSWORD (TITLE / MAP)", 0
fs_help_9:
        .db     "CTRL+C : BASIC", 0
fs_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     fs_sfx_slide, fs_sfx_crystal, fs_jingle_win, fs_jingle_lose
fs_sfx_slide:
        .db     60, 1, 0, 0
fs_sfx_crystal:
        .db     40, 3, 32, 3, 27, 6, 0, 0

; Title: a crystalline waltz in F sharp minor, quarter note = 12 frames, looping.
fs_title_song:
        .db     1
        .dw     fs_title_melody, fs_title_harmony, fs_title_bass
fs_title_melody:
        .db     AU_CS6, 12, AU_A5, 12, AU_FS5, 12, AU_B5, 24, AU_GS5, 12
        .db     AU_A5, 12, AU_FS5, 12, AU_CS5, 12, AU_D5, 24, AU_E5, 12
        .db     AU_FS5, 12, AU_A5, 12, AU_CS6, 12, AU_B5, 24, AU_GS5, 12
        .db     AU_FS5, 36, 0, 36, 0, 0
fs_title_harmony:
        .db     AU_A4, 36, AU_D5, 36, AU_CS5, 36, AU_B4, 36
        .db     AU_A4, 36, AU_GS4, 36, AU_A4, 36, 0, 36, 0, 0
fs_title_bass:
        .db     AU_FS2, 12, AU_CS3, 12, AU_CS3, 12, AU_B2, 12, AU_D3, 12, AU_D3, 12
        .db     AU_FS2, 12, AU_CS3, 12, AU_CS3, 12, AU_B2, 12, AU_D3, 12, AU_D3, 12
        .db     AU_A2, 12, AU_CS3, 12, AU_E3, 12, AU_CS2, 12, AU_GS2, 12, AU_B2, 12
        .db     AU_FS2, 36, 0, 36, 0, 0

; Chamber clear: F sharp major arpeggio over the tonic (54 frames).
fs_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     fs_win_melody, fs_win_harmony, fs_win_bass
fs_win_melody:
        .db     AU_FS5, 8, AU_AS5, 8, AU_CS6, 8, AU_FS6, 30, 0, 0
fs_win_harmony:
        .db     AU_CS5, 8, AU_FS5, 8, AU_AS5, 8, AU_CS6, 30, 0, 0
fs_win_bass:
        .db     AU_FS3, 24, AU_FS2, 30, 0, 0
fs_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     fs_lose_melody, fs_lose_harmony, fs_lose_bass
fs_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
fs_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
fs_lose_bass:
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
