; SPDX-License-Identifier: MIT
; MEMORY MOSAIC for JR-200: a port of jr100dev games/memory_mosaic/rules.py 3.0.0.
; The seeded shuffle, the two-card turn, chains and the miss limit follow the
; upstream source; display, colour and three-voice sound use the JR-200 port
; SDK. Upstream's entropy() (the JR-100 timer) is replaced by the position of
; the title song when a stage starts.
        .filename.jr "MEMORY-MOSAIC"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
MM_LOG:             .equ    0x4720      ; count, then each sampled origin
MM_LOG_MAX:         .equ    31
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    10
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py).
MM_ORIGIN:          .equ    GAME_STATE
MM_SEED:            .equ    GAME_STATE + 1
MM_FIRST:           .equ    GAME_STATE + 2
MM_SECOND:          .equ    GAME_STATE + 3
MM_TURNING:         .equ    GAME_STATE + 4
MM_LEFT:            .equ    GAME_STATE + 5
MM_LIMIT:           .equ    GAME_STATE + 6
MM_CURSOR:          .equ    GAME_STATE + 7
MM_CHAIN:           .equ    GAME_STATE + 8
MM_BEST:            .equ    GAME_STATE + 9
MM_ERRORS:          .equ    GAME_STATE + 10
MM_NOTICE:          .equ    GAME_STATE + 11
MM_POSE:            .equ    GAME_STATE + 12
MM_B:               .equ    GAME_STATE + 13     ; b[16] motifs
MM_C:               .equ    GAME_STATE + 29     ; c[16] face up
; Effect and rule work bytes.
MM_EFFECT:          .equ    GAME_STATE + 45
MM_EX:              .equ    GAME_STATE + 46
MM_EY:              .equ    GAME_STATE + 47
MM_EPHASE:          .equ    GAME_STATE + 48
MM_FRAME:           .equ    GAME_STATE + 49
MM_I:               .equ    GAME_STATE + 50
MM_J:               .equ    GAME_STATE + 51
MM_T:               .equ    GAME_STATE + 52
MM_POS:             .equ    GAME_STATE + 53
MM_REVEAL:          .equ    GAME_STATE + 54
MM_MP:              .equ    GAME_STATE + 55
MM_MA:              .equ    GAME_STATE + 56
MM_MC:              .equ    GAME_STATE + 57
; Drawing work bytes.
MM_DI:              .equ    GAME_STATE + 64
MM_DCODE:           .equ    GAME_STATE + 65

MM_NONE:            .equ    255
MM_TILE_BACK:       .equ    0x80
MM_TILE_POSE:       .equ    0x80        ; + 4 * (pose - 1)
MM_TILE_SPARK:      .equ    0x94
MM_ATTR_BACK:       .equ    0x41
MM_ATTR_TURN:       .equ    0x47
MM_ATTR_SPARK:      .equ    0x46
MM_ATTR_TEXT:       .equ    0x07
MM_ATTR_LABEL:      .equ    0x04
MM_ATTR_TITLE:      .equ    0x06
MM_ATTR_DIM:        .equ    0x05
MM_ATTR_GOOD:       .equ    0x04
MM_ATTR_BAD:        .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        CLR     [MM_LOG]
        JSR     jr_font_install
        LDX     mm_patterns
        LDAA    0x80
        LDAB    32
        JSR     jr_pcg_load
        LDX     mm_motif_patterns
        CLRA
        LDAB    32
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        ; origin = entropy(): voice 0 offset * 8 + frames left of the song
        LDAA    [JR_AU_VOICE + 1]
        SUBA    [JR_AU_VOICE + 4]
        ASLA
        ASLA
        ASLA
        ADDA    [JR_AU_VOICE + 2]
        STAA    [MM_ORIGIN]
        JSR     jr_music_stop
        LDAB    [MM_LOG]
        CMPB    MM_LOG_MAX
        BCC     mm_init_seed
        INC     [MM_LOG]
        LDX     MM_LOG + 1
        LDAA    [MM_LOG]
        DECA
        JSR     jr_add_x_a
        LDAA    [MM_ORIGIN]
        STAA    [X]
mm_init_seed:
        LDAA    [JR_PORT_LEVEL]
        LDAB    17
        JSR     jr_mul8
        EORA    [MM_ORIGIN]
        STAA    [MM_SEED]
        ; b[i] = i // 2
        LDX     MM_B
        CLRA
mm_init_card:
        TAB
        LSRB
        STAB    [X]
        INX
        INCA
        CMPA    16
        BNE     mm_init_card
        ; for i in range(15): seed = seed * 109 + 89; j = seed % (16 - i);
        ; swap b[15 - i] and b[j]
        CLR     [MM_I]
mm_init_shuffle:
        LDAA    [MM_SEED]
        LDAB    109
        JSR     jr_mul8
        ADDA    89
        STAA    [MM_SEED]
        LDAB    16
        SUBB    [MM_I]
        JSR     jr_divmod8
        STAB    [MM_J]
        LDAA    15
        SUBA    [MM_I]
        LDX     MM_B
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [MM_T]
        STX     [MM_EX]             ; &b[15 - i] (EX/EY unused until play)
        LDAA    [MM_J]
        LDX     MM_B
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    [MM_T]
        STAB    [X]
        LDX     [MM_EX]
        STAA    [X]
        INC     [MM_I]
        LDAA    [MM_I]
        CMPA    15
        BNE     mm_init_shuffle
        CLR     [MM_EX]
        CLR     [MM_EY]
        LDAA    MM_NONE
        STAA    [MM_FIRST]
        STAA    [MM_SECOND]
        STAA    [MM_TURNING]
        LDAA    8
        STAA    [MM_LEFT]
        LDAA    [JR_PORT_LEVEL]
        LDAB    3
        JSR     jr_divmod8
        NEGA
        ADDA    12
        STAA    [MM_LIMIT]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     mm_confirm
        BCC     mm_act_done
        TAB
        LDAA    [MM_CURSOR]
        JSR     mm_move
        STAA    [MM_CURSOR]
mm_act_done:
        RTS

mm_confirm:
        CLR     [MM_NOTICE]
        LDAA    [MM_SECOND]
        CMPA    MM_NONE
        BEQ     mm_confirm_open
        ; close an unmatched pair, then clear the selection
        LDAA    [MM_FIRST]
        JSR     mm_value
        STAA    [MM_T]
        LDAA    [MM_SECOND]
        JSR     mm_value
        CMPA    [MM_T]
        BEQ     mm_confirm_clear
        LDAA    [MM_FIRST]
        CLRB
        JSR     mm_turn
        LDAA    [MM_SECOND]
        CLRB
        JSR     mm_turn
mm_confirm_clear:
        LDAA    MM_NONE
        STAA    [MM_FIRST]
        STAA    [MM_SECOND]
        RTS
mm_confirm_open:
        LDAA    [MM_CURSOR]
        LDX     MM_C
        JSR     jr_add_x_a
        TST     [X]
        BNE     mm_act_done
        LDAA    [MM_CURSOR]
        LDAB    1
        JSR     mm_turn
        LDAA    [MM_FIRST]
        CMPA    MM_NONE
        BNE     mm_confirm_second
        LDAA    [MM_CURSOR]
        STAA    [MM_FIRST]
        RTS
mm_confirm_second:
        LDAA    [MM_CURSOR]
        STAA    [MM_SECOND]
        LDAA    [MM_FIRST]
        JSR     mm_value
        STAA    [MM_T]
        LDAA    [MM_SECOND]
        JSR     mm_value
        CMPA    [MM_T]
        BNE     mm_mismatch
        DEC     [MM_LEFT]
        INC     [MM_CHAIN]
        LDAA    [MM_CHAIN]
        CMPA    [MM_BEST]
        BLS     mm_match_notice
        STAA    [MM_BEST]
mm_match_notice:
        LDAA    1
        STAA    [MM_NOTICE]
        LDAA    1
        JSR     jr_port_sound
        LDAA    [MM_FIRST]
        JSR     mm_sparkle
        LDAA    [MM_SECOND]
        JSR     mm_sparkle
        BRA     mm_check_end
mm_mismatch:
        INC     [MM_ERRORS]
        CLR     [MM_CHAIN]
        LDAA    2
        STAA    [MM_NOTICE]
        LDX     mm_sfx_miss
        JSR     jr_sfx_play
        LDAA    18
        JSR     jr_port_animate
mm_check_end:
        TST     [MM_LEFT]
        BNE     mm_check_limit
        JMP     jr_port_win
mm_check_limit:
        LDAA    [MM_ERRORS]
        CMPA    [MM_LIMIT]
        BCC     mm_act_done_near274
        JMP     mm_act_done
mm_act_done_near274:
        LDX     mm_txt_lose
        JMP     jr_port_lose

; A = card -> A = b[card]. Clobbers X.
mm_value:
        LDX     MM_B
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

; A = card, B = 1 reveal / 0 hide: five poses of animate(3), then c[card] = B.
mm_turn:
        STAA    [MM_TURNING]
        STAA    [MM_POS]
        STAB    [MM_REVEAL]
        CLRA
        JSR     jr_port_sound
        CLR     [MM_FRAME]
mm_turn_frame:
        LDAA    [MM_FRAME]
        TST     [MM_REVEAL]
        BEQ     mm_turn_hide
        INCA
        BRA     mm_turn_pose
mm_turn_hide:
        NEGA
        ADDA    5
mm_turn_pose:
        STAA    [MM_POSE]
        LDAA    3
        JSR     jr_port_animate
        INC     [MM_FRAME]
        LDAA    [MM_FRAME]
        CMPA    5
        BNE     mm_turn_frame
        LDAA    MM_NONE
        STAA    [MM_TURNING]
        LDAA    [MM_POS]
        LDX     MM_C
        JSR     jr_add_x_a
        LDAA    [MM_REVEAL]
        STAA    [X]
        RTS

; A = card: three sparkle phases of animate(4) over it.
mm_sparkle:
        JSR     mm_card_xy
        STAA    [MM_EX]
        STAB    [MM_EY]
        LDAA    2
        STAA    [MM_EFFECT]
        CLR     [MM_FRAME]
mm_sparkle_phase:
        LDAA    [MM_FRAME]
        STAA    [MM_EPHASE]
        LDAA    4
        JSR     jr_port_animate
        INC     [MM_FRAME]
        LDAA    [MM_FRAME]
        CMPA    3
        BNE     mm_sparkle_phase
        CLR     [MM_EFFECT]
        RTS

; A = position, B = action 1-4 -> A = moved position (4x4, stops at edges).
mm_move:
        STAA    [MM_MP]
        STAB    [MM_MA]
        ANDA    3
        STAA    [MM_MC]
        LDAA    [MM_MP]
        CMPB    JR_KEY_UP
        BNE     mm_move_down
        CMPA    4
        BCS     mm_move_done
        SUBA    4
        RTS
mm_move_down:
        CMPB    JR_KEY_DOWN
        BNE     mm_move_left
        CMPA    12
        BCC     mm_move_done
        ADDA    4
        RTS
mm_move_left:
        CMPB    JR_KEY_LEFT
        BNE     mm_move_right
        TST     [MM_MC]
        BEQ     mm_move_done
        DECA
        RTS
mm_move_right:
        CMPB    JR_KEY_RIGHT
        BNE     mm_move_done
        LDAB    [MM_MC]
        CMPB    3
        BCC     mm_move_done
        INCA
mm_move_done:
        RTS

; A = card -> A = 2 + i % 4 * 4, B = 4 + i // 4 * 4.
mm_card_xy:
        TAB
        ANDB    0x0c
        ADDB    4
        ANDA    3
        ASLA
        ASLA
        ADDA    2
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    MM_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     mm_hud
        JSR     jr_gfx_lines
        LDAA    MM_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        CLR     [MM_DI]
mm_draw_card:
        LDAA    [MM_DI]
        CMPA    [MM_TURNING]
        BNE     mm_draw_face
        LDAA    [MM_POSE]
        DECA
        ASLA
        ASLA
        ADDA    MM_TILE_POSE
        LDAB    MM_ATTR_TURN
        BRA     mm_draw_tile
mm_draw_face:
        LDX     MM_C
        JSR     jr_add_x_a
        LDAA    MM_TILE_BACK
        LDAB    MM_ATTR_BACK
        TST     [X]
        BEQ     mm_draw_tile
        LDAA    [MM_DI]
        JSR     mm_value
        PSHA
        LDX     mm_motif_attr
        JSR     jr_add_x_a
        LDAB    [X]
        PULA
        ASLA
        ASLA
mm_draw_tile:
        STAA    [MM_DCODE]
        STAB    [JR_RT_COLOR]
        LDAA    [MM_DI]
        JSR     mm_card_xy
        JSR     jr_gfx_at
        LDAA    [MM_DCODE]
        JSR     jr_gfx_tile
        INC     [MM_DI]
        LDAA    [MM_DI]
        CMPA    16
        BNE     mm_draw_card
        ; cursor '>' at (1 + i % 4 * 4, 4 + i // 4 * 4)
        LDAA    MM_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [MM_CURSOR]
        JSR     mm_card_xy
        DECA
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        ; pairs found, misses / limit, chain
        LDAA    24
        LDAB    7
        JSR     jr_gfx_at
        LDAA    8
        SUBA    [MM_LEFT]
        JSR     jr_gfx_dec2
        LDAA    23
        LDAB    14
        JSR     jr_gfx_at
        LDAA    [MM_ERRORS]
        JSR     jr_gfx_dec2
        LDAA    0x2f
        JSR     jr_gfx_putc
        LDAA    [MM_LIMIT]
        JSR     jr_gfx_dec2
        LDAA    27
        LDAB    17
        JSR     jr_gfx_at
        LDAA    [MM_CHAIN]
        ADDA    0x30
        JSR     jr_gfx_putc
        ; notice on row 20
        LDAA    1
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_CLEAR
        BNE     mm_draw_notice
        LDAA    MM_ATTR_GOOD
        STAA    [JR_RT_COLOR]
        LDX     mm_txt_all
        JSR     jr_gfx_text
        BRA     mm_draw_effect
mm_draw_notice:
        LDAA    [MM_NOTICE]
        BEQ     mm_draw_effect
        LDAB    MM_ATTR_GOOD
        LDX     mm_txt_matched
        CMPA    1
        BEQ     mm_draw_notice_text
        LDAB    MM_ATTR_BAD
        LDX     mm_txt_mismatch
mm_draw_notice_text:
        STAB    [JR_RT_COLOR]
        JSR     jr_gfx_text
mm_draw_effect:
        TST     [MM_EFFECT]
        BEQ     mm_draw_done
        LDAA    MM_ATTR_SPARK
        STAA    [JR_RT_COLOR]
        LDAA    [MM_EX]
        LDAB    [MM_EY]
        JSR     jr_gfx_at
        LDAA    [MM_EPHASE]
        ASLA
        ASLA
        ADDA    MM_TILE_SPARK
        JMP     jr_gfx_tile
mm_draw_done:
        RTS

game_draw_title:
        LDX     mm_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    MM_ATTR_TEXT
        JSR     jr_gfx_fill
        ; the eight motifs in their colours
        CLR     [MM_DI]
mm_title_motif:
        LDX     mm_motif_attr
        LDAA    [MM_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [MM_DI]
        ASLA
        ASLA
        INCA
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [MM_DI]
        ASLA
        ASLA
        JSR     jr_gfx_tile
        INC     [MM_DI]
        LDAA    [MM_DI]
        CMPA    8
        BNE     mm_title_motif
        LDX     mm_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    MM_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     mm_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; Motif colours: red, green, yellow, cyan, magenta, white, blue on white,
; black on yellow.
mm_motif_attr:
        .db     0x42, 0x44, 0x46, 0x45, 0x43, 0x47, 0x79, 0x70

mm_hud:
        .db     1, 0, MM_ATTR_TITLE
        .dw     mm_txt_name
        .db     23, 0, MM_ATTR_LABEL
        .dw     mm_txt_table
        .db     21, 3, MM_ATTR_LABEL
        .dw     mm_txt_archive
        .db     21, 6, MM_ATTR_LABEL
        .dw     mm_txt_pairs
        .db     21, 13, MM_ATTR_LABEL
        .dw     mm_txt_misses
        .db     20, 17, MM_ATTR_LABEL
        .dw     mm_txt_chain
        .db     0xff
mm_title_lines:
        .db     9, 8, MM_ATTR_TITLE
        .dw     mm_txt_name
        .db     5, 10, MM_ATTR_LABEL
        .dw     mm_txt_tagline
        .db     8, 15, MM_ATTR_TEXT
        .dw     mm_txt_start
        .db     5, 17, MM_ATTR_TEXT
        .dw     mm_txt_howto
        .db     4, 22, MM_ATTR_DIM
        .dw     mm_txt_credit
        .db     0xff
mm_help_lines:
        .db     9, 2, MM_ATTR_TITLE
        .dw     mm_txt_name
        .db     1, 5, MM_ATTR_TEXT
        .dw     mm_help_1
        .db     1, 7, MM_ATTR_TEXT
        .dw     mm_help_2
        .db     1, 9, MM_ATTR_TEXT
        .dw     mm_help_3
        .db     1, 11, MM_ATTR_TEXT
        .dw     mm_help_4
        .db     1, 13, MM_ATTR_TEXT
        .dw     mm_help_5
        .db     1, 15, MM_ATTR_TEXT
        .dw     mm_help_6
        .db     1, 17, MM_ATTR_TEXT
        .dw     mm_help_7
        .db     1, 20, MM_ATTR_LABEL
        .dw     mm_help_back
        .db     0xff

mm_txt_name:
        .db     "MEMORY MOSAIC", 0
mm_txt_table:
        .db     "TABLE", 0
mm_txt_archive:
        .db     "ARCHIVE", 0
mm_txt_pairs:
        .db     "PAIRS", 0
mm_txt_misses:
        .db     "MISSES", 0
mm_txt_chain:
        .db     "CHAIN", 0
mm_txt_all:
        .db     "ALL EIGHT PAIRS FOUND", 0
mm_txt_matched:
        .db     "MATCHED!", 0
mm_txt_mismatch:
        .db     "MISMATCH", 0
mm_txt_lose:
        .db     "TOO MANY PAIRS DID NOT MATCH", 0
mm_txt_tagline:
        .db     "FIND EIGHT MATCHING PAIRS", 0
mm_txt_start:
        .db     "RETURN : START", 0
mm_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
mm_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
mm_help_1:
        .db     "WASD : CHOOSE  RETURN : TURN", 0
mm_help_2:
        .db     "FIND EIGHT MATCHING PAIRS.", 0
mm_help_3:
        .db     "RETURN CLOSES UNMATCHED PAIRS.", 0
mm_help_4:
        .db     "MATCH PAIRS TO BUILD A CHAIN.", 0
mm_help_5:
        .db     "THE DECK CHANGES EVERY GAME.", 0
mm_help_6:
        .db     "LATER TABLES: FEWER MISSES.", 0
mm_help_7:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
mm_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     mm_sfx_turn, mm_sfx_match, mm_jingle_win, mm_jingle_lose
mm_sfx_turn:
        .db     75, 2, 0, 0
mm_sfx_match:
        .db     90, 3, 70, 3, 55, 6, 0, 0
mm_sfx_miss:
        .db     200, 5, 0, 2, 240, 8, 0, 0

; Title: four bars in G major, eighth note = 12 frames, looping.
mm_title_song:
        .db     1
        .dw     mm_title_melody, mm_title_harmony, mm_title_bass
mm_title_melody:
        .db     AU_B5, 12, AU_D6, 12, AU_B5, 12, AU_G5, 12, AU_A5, 24, AU_FS5, 24
        .db     AU_G5, 12, AU_B5, 12, AU_E6, 12, AU_D6, 12, AU_C6, 24, AU_A5, 24
        .db     AU_B5, 12, AU_D6, 12, AU_G6, 12, AU_FS6, 12, AU_E6, 24, AU_C6, 24
        .db     AU_D6, 72, 0, 24, 0, 0
mm_title_harmony:
        .db     AU_G5, 48, AU_D5, 48, AU_E5, 48, AU_E5, 48
        .db     AU_G5, 48, AU_A5, 48, AU_FS5, 72, 0, 24, 0, 0
mm_title_bass:
        .db     AU_G3, 24, AU_D3, 24, AU_D3, 24, AU_A2, 24
        .db     AU_E3, 24, AU_B2, 24, AU_C3, 24, AU_A2, 24
        .db     AU_G3, 24, AU_B2, 24, AU_C3, 24, AU_A2, 24
        .db     AU_D3, 72, 0, 24, 0, 0

; Clear: rising G major arpeggio over a held tonic (54 frames).
mm_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     mm_win_melody, mm_win_harmony, mm_win_bass
mm_win_melody:
        .db     AU_G5, 8, AU_B5, 8, AU_D6, 8, AU_G6, 30, 0, 0
mm_win_harmony:
        .db     AU_D5, 8, AU_G5, 8, AU_B5, 8, AU_D6, 30, 0, 0
mm_win_bass:
        .db     AU_G3, 24, AU_G2, 30, 0, 0
mm_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     mm_lose_melody, mm_lose_harmony, mm_lose_bass
mm_lose_melody:
        .db     AU_D5, 12, AU_C5, 12, AU_AS4, 12, AU_A4, 30, 0, 0
mm_lose_harmony:
        .db     AU_AS4, 12, AU_A4, 12, AU_G4, 12, AU_FS4, 30, 0, 0
mm_lose_bass:
        .db     AU_G3, 36, AU_D3, 30, 0, 0

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
