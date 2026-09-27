; SPDX-License-Identifier: MIT
; SHADOW ARCHIVE for JR-200: a port of jr100dev games/shadow_archive/rules.py 2.1.0.
; The twelve cases, suspects, culprits and the file/accuse rules follow the
; upstream source; display, colour and three-voice sound use the JR-200 SDK.
        .filename.jr "SHADOW-ARCHIVE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    12
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py).
SA_CULPRIT:         .equ    GAME_STATE
SA_CHOOSING:        .equ    GAME_STATE + 1      ; s.mode_choice
SA_CHOICE:          .equ    GAME_STATE + 2
SA_FILE:            .equ    GAME_STATE + 3
SA_ACCUSING:        .equ    GAME_STATE + 4
SA_READ:            .equ    GAME_STATE + 5
SA_B:               .equ    GAME_STATE + 6      ; b[6] trait sets
SA_C:               .equ    GAME_STATE + 12     ; c[3] opened files
SA_OPENING:         .equ    GAME_STATE + 15
SA_PAGE:            .equ    GAME_STATE + 16
; Effect and work bytes.
SA_EFFECT:          .equ    GAME_STATE + 20
SA_EPHASE:          .equ    GAME_STATE + 21
SA_EX:              .equ    GAME_STATE + 22
SA_EY:              .equ    GAME_STATE + 23
SA_FRAME:           .equ    GAME_STATE + 24
; Drawing work bytes.
SA_DI:              .equ    GAME_STATE + 32
SA_DX:              .equ    GAME_STATE + 33
SA_DY:              .equ    GAME_STATE + 34
SA_DT:              .equ    GAME_STATE + 35
SA_DMASK:           .equ    GAME_STATE + 36
SA_DWRONG:          .equ    GAME_STATE + 37
SA_DBITS:           .equ    GAME_STATE + 38
SA_DCUL:            .equ    GAME_STATE + 39

SA_TILE_FACE:       .equ    0x80        ; + 4 * (b - 1)
SA_TILE_SPARK:      .equ    0x00
SA_ATTR_FACE:       .equ    0x47
SA_ATTR_WRONG:      .equ    0x42        ; red portrait: contradicted
SA_ATTR_SPARK:      .equ    0x46
SA_ATTR_YES:        .equ    0x04
SA_ATTR_NO:         .equ    0x02
SA_ATTR_MARK:       .equ    0x02
SA_ATTR_PAPER:      .equ    0x07
SA_ATTR_TEXT:       .equ    0x07
SA_ATTR_LABEL:      .equ    0x04
SA_ATTR_TITLE:      .equ    0x06
SA_ATTR_DIM:        .equ    0x05
SA_ATTR_MODE:       .equ    0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     sa_patterns
        LDAA    SA_TILE_FACE
        LDAB    24
        JSR     jr_pcg_load
        LDX     sa_spark_patterns
        CLRA
        LDAB    12
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    [JR_PORT_LEVEL]
        LDX     sa_who
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [SA_CULPRIT]
        LDAA    [JR_PORT_LEVEL]
        LDAB    6
        JSR     jr_mul8
        LDX     sa_suspects
        JSR     jr_add_x_a
        LDAB    0
sa_init_suspect:
        LDAA    [X]
        PSHA
        STX     [SA_EX]
        LDX     SA_B
        TBA
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        LDX     [SA_EX]
        INX
        INCB
        CMPB    6
        BNE     sa_init_suspect
        CLR     [SA_EX]
        CLR     [SA_EY]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_DOWN
        BHI     sa_act_select
        LDAA    [SA_CHOOSING]
        EORA    1
        STAA    [SA_CHOOSING]
        CLRA
        JMP     jr_port_sound
sa_act_select:
        CMPA    JR_KEY_RIGHT
        BHI     sa_act_confirm
        TST     [SA_CHOOSING]
        BEQ     sa_act_file
        ; choice = (choice + (5 if left else 1)) % 6
        LDAB    1
        CMPA    JR_KEY_LEFT
        BNE     sa_act_choice
        LDAB    5
sa_act_choice:
        ADDB    [SA_CHOICE]
        CMPB    6
        BCS     sa_act_choice_store
        SUBB    6
sa_act_choice_store:
        STAB    [SA_CHOICE]
        RTS
sa_act_file:
        LDAB    1
        CMPA    JR_KEY_LEFT
        BNE     sa_act_file_add
        LDAB    2
sa_act_file_add:
        ADDB    [SA_FILE]
        CMPB    3
        BCS     sa_act_file_store
        SUBB    3
sa_act_file_store:
        STAB    [SA_FILE]
        RTS
sa_act_confirm:
        CMPA    JR_KEY_CONFIRM
        BNE     sa_act_done
        TST     [SA_CHOOSING]
        BEQ     sa_open
        LDAA    1
        STAA    [SA_ACCUSING]
        CLRA
        JSR     jr_port_sound
        LDAA    24
        JSR     jr_port_animate
        LDAA    [SA_CHOICE]
        CMPA    [SA_CULPRIT]
        BNE     sa_wrong
        JSR     sa_sparkle
        JMP     jr_port_win
sa_wrong:
        LDX     sa_txt_lose
        JMP     jr_port_lose
sa_open:
        LDAA    [SA_FILE]
        LDX     SA_C
        JSR     jr_add_x_a
        TST     [X]
        BEQ     sa_open_file
        CLRA
        JMP     jr_port_sound
sa_open_file:
        LDAA    1
        STAA    [SA_OPENING]
        CLR     [SA_FRAME]
sa_open_page:
        LDAA    [SA_FRAME]
        STAA    [SA_PAGE]
        CLRA
        JSR     jr_port_sound
        LDAA    6
        JSR     jr_port_animate
        INC     [SA_FRAME]
        LDAA    [SA_FRAME]
        CMPA    3
        BNE     sa_open_page
        LDAA    [SA_FILE]
        LDX     SA_C
        JSR     jr_add_x_a
        LDAA    1
        STAA    [X]
        INC     [SA_READ]
        CLR     [SA_OPENING]
        LDAA    1
        JMP     jr_port_sound
sa_act_done:
        RTS

; sparkle at the accused: three phases of animate(4).
sa_sparkle:
        LDAA    [SA_CHOICE]
        JSR     sa_suspect_xy
        STAA    [SA_EX]
        STAB    [SA_EY]
        LDAA    2
        STAA    [SA_EFFECT]
        CLR     [SA_FRAME]
sa_sparkle_phase:
        LDAA    [SA_FRAME]
        STAA    [SA_EPHASE]
        LDAA    4
        JSR     jr_port_animate
        INC     [SA_FRAME]
        LDAA    [SA_FRAME]
        CMPA    3
        BNE     sa_sparkle_phase
        CLR     [SA_EFFECT]
        RTS

; A = suspect -> A = 2 + i % 3 * 5, B = 4 + i // 3 * 6.
sa_suspect_xy:
        LDAB    4
        CMPA    3
        BCS     sa_suspect_col
        SUBA    3
        LDAB    10
sa_suspect_col:
        PSHB
        TAB
        ASLA
        ASLA
        ABA
        ADDA    2
        PULB
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    SA_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sa_hud
        JSR     jr_gfx_lines
        LDAA    SA_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; the culprit's traits, for the contradiction marks
        LDAA    [SA_CULPRIT]
        LDX     SA_B
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [SA_DCUL]
        CLR     [SA_DI]
sa_draw_suspect:
        LDAA    [SA_DI]
        JSR     sa_suspect_xy
        STAA    [SA_DX]
        STAB    [SA_DY]
        LDAA    [SA_DI]
        LDX     SA_B
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [SA_DBITS]
        ; wrong when an opened file's trait differs from the culprit's
        CLR     [SA_DWRONG]
        EORA    [SA_DCUL]
        STAA    [SA_DMASK]
        LDX     SA_C
        LDAB    1
sa_draw_wrong:
        TST     [X]
        BEQ     sa_draw_wrong_next
        TBA
        ANDA    [SA_DMASK]
        BEQ     sa_draw_wrong_next
        INC     [SA_DWRONG]
sa_draw_wrong_next:
        INX
        ASLB
        CMPB    8
        BNE     sa_draw_wrong
        ; portrait
        LDAA    SA_ATTR_FACE
        TST     [SA_DWRONG]
        BEQ     sa_draw_face
        LDAA    SA_ATTR_WRONG
sa_draw_face:
        STAA    [JR_RT_COLOR]
        LDAA    [SA_DX]
        LDAB    [SA_DY]
        JSR     jr_gfx_at
        LDAA    [SA_DBITS]
        DECA
        ASLA
        ASLA
        ADDA    SA_TILE_FACE
        JSR     jr_gfx_tile
        ; name letter, and X when contradicted
        LDAA    SA_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [SA_DX]
        LDAB    [SA_DY]
        ADDB    2
        JSR     jr_gfx_at
        LDAA    [SA_DI]
        ADDA    0x41
        JSR     jr_gfx_putc
        TST     [SA_DWRONG]
        BEQ     sa_draw_traits
        LDAA    SA_ATTR_MARK
        STAA    [JR_RT_COLOR]
        LDAA    0x58
        JSR     jr_gfx_putc
sa_draw_traits:
        ; Y/N for hat, glasses, tie at (x - 1 .. x + 1, y + 3)
        LDAA    [SA_DX]
        DECA
        LDAB    [SA_DY]
        ADDB    3
        JSR     jr_gfx_at
        LDAB    1
sa_draw_trait:
        LDAA    SA_ATTR_NO
        STAA    [JR_RT_COLOR]
        LDAA    0x4e
        STAB    [SA_DT]
        PSHA
        TBA
        ANDA    [SA_DBITS]
        PULA
        BEQ     sa_draw_trait_put
        LDAA    SA_ATTR_YES
        STAA    [JR_RT_COLOR]
        LDAA    0x59
sa_draw_trait_put:
        JSR     jr_gfx_putc
        LDAB    [SA_DT]
        ASLB
        CMPB    8
        BNE     sa_draw_trait
        INC     [SA_DI]
        LDAA    [SA_DI]
        CMPA    6
        BEQ     sa_draw_cursor
        JMP     sa_draw_suspect
sa_draw_cursor:
        LDAA    SA_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        TST     [SA_CHOOSING]
        BEQ     sa_draw_file_cursor
        LDAA    [SA_CHOICE]
        JSR     sa_suspect_xy
        DECA
        BRA     sa_draw_cursor_put
sa_draw_file_cursor:
        LDAA    [SA_FILE]
        ASLA
        ASLA
        ADDA    6
        TAB
        LDAA    17
sa_draw_cursor_put:
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        ; opened files show the culprit's answer
        CLR     [SA_DI]
        LDAB    1
        STAB    [SA_DT]
sa_draw_answer:
        LDX     SA_C
        LDAA    [SA_DI]
        JSR     jr_add_x_a
        TST     [X]
        BEQ     sa_draw_answer_next
        LDAA    [SA_DI]
        ASLA
        ASLA
        ADDA    7
        TAB
        LDAA    20
        JSR     jr_gfx_at
        LDAA    [SA_DT]
        ANDA    [SA_DCUL]
        BEQ     sa_draw_no
        LDAA    SA_ATTR_YES
        STAA    [JR_RT_COLOR]
        LDX     sa_txt_yes
        BRA     sa_draw_answer_text
sa_draw_no:
        LDAA    SA_ATTR_NO
        STAA    [JR_RT_COLOR]
        LDX     sa_txt_no
sa_draw_answer_text:
        JSR     jr_gfx_text
sa_draw_answer_next:
        ASL     [SA_DT]
        INC     [SA_DI]
        LDAA    [SA_DI]
        CMPA    3
        BNE     sa_draw_answer
        ; files read, mode line
        LDAA    SA_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    12
        LDAB    18
        JSR     jr_gfx_at
        LDAA    [SA_READ]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    SA_ATTR_MODE
        STAA    [JR_RT_COLOR]
        LDAA    2
        LDAB    20
        JSR     jr_gfx_at
        TST     [SA_CHOOSING]
        BEQ     sa_draw_mode_file
        LDX     sa_txt_accuse
        JSR     jr_gfx_text
        LDAA    10
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [SA_CHOICE]
        ADDA    0x41
        JSR     jr_gfx_putc
        BRA     sa_draw_paper
sa_draw_mode_file:
        LDX     sa_txt_open_file
        JSR     jr_gfx_text
        LDAA    12
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [SA_FILE]
        ADDA    0x31
        JSR     jr_gfx_putc
sa_draw_paper:
        TST     [SA_OPENING]
        BEQ     sa_draw_rating
        LDAA    SA_ATTR_PAPER
        STAA    [JR_RT_COLOR]
        LDAB    18
        SUBB    [SA_PAGE]
        LDAA    19
        JSR     jr_gfx_at
        LDX     sa_txt_paper
        JSR     jr_gfx_text
sa_draw_rating:
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_CLEAR
        BNE     sa_draw_accused
        LDAA    SA_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    13
        LDAB    20
        JSR     jr_gfx_at
        LDX     sa_txt_gold
        LDAA    [SA_READ]
        CMPA    2
        BLS     sa_draw_rating_text
        LDX     sa_txt_closed
sa_draw_rating_text:
        JSR     jr_gfx_text
sa_draw_accused:
        TST     [SA_ACCUSING]
        BEQ     sa_draw_effect
        LDAA    SA_ATTR_MARK
        STAA    [JR_RT_COLOR]
        LDAA    [SA_CHOICE]
        JSR     sa_suspect_xy
        ADDA    2
        JSR     jr_gfx_at
        LDAA    0x21
        JSR     jr_gfx_putc
sa_draw_effect:
        TST     [SA_EFFECT]
        BEQ     sa_draw_done
        LDAA    SA_ATTR_SPARK
        STAA    [JR_RT_COLOR]
        LDAA    [SA_EX]
        LDAB    [SA_EY]
        JSR     jr_gfx_at
        LDAA    [SA_EPHASE]
        ASLA
        ASLA
        JMP     jr_gfx_tile
sa_draw_done:
        RTS

game_draw_title:
        LDX     sa_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    SA_ATTR_TEXT
        JSR     jr_gfx_fill
        CLR     [SA_DI]
sa_title_face:
        LDAA    SA_ATTR_FACE
        LDAB    [SA_DI]
        CMPB    4
        BNE     sa_title_face_color
        LDAA    SA_ATTR_WRONG
sa_title_face_color:
        STAA    [JR_RT_COLOR]
        LDAA    [SA_DI]
        LDAB    5
        JSR     jr_mul8
        ADDA    2
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [SA_DI]
        ASLA
        ASLA
        ADDA    SA_TILE_FACE
        JSR     jr_gfx_tile
        INC     [SA_DI]
        LDAA    [SA_DI]
        CMPA    6
        BNE     sa_title_face
        LDX     sa_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    SA_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sa_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

sa_suspects:
        .db     1, 2, 3, 4, 5, 6, 5, 2, 6, 4, 3, 1, 3, 4, 6, 1, 5, 2, 6, 3, 4, 5, 2, 1
        .db     4, 5, 2, 6, 3, 1, 1, 3, 6, 2, 4, 5, 3, 4, 1, 6, 2, 5, 4, 6, 3, 5, 1, 2
        .db     1, 2, 5, 6, 4, 3, 4, 5, 6, 1, 2, 3, 3, 6, 1, 2, 4, 5, 1, 5, 2, 6, 3, 4
sa_who:
        .db     2, 1, 3, 0, 1, 4, 0, 5, 0, 2, 5, 5

sa_hud:
        .db     1, 0, SA_ATTR_TITLE
        .dw     sa_txt_name
        .db     24, 0, SA_ATTR_LABEL
        .dw     sa_txt_case
        .db     1, 2, SA_ATTR_LABEL
        .dw     sa_txt_six
        .db     19, 3, SA_ATTR_LABEL
        .dw     sa_txt_files
        .db     18, 6, SA_ATTR_TEXT
        .dw     sa_txt_hat
        .db     18, 10, SA_ATTR_TEXT
        .dw     sa_txt_glasses
        .db     18, 14, SA_ATTR_TEXT
        .dw     sa_txt_tie
        .db     1, 18, SA_ATTR_LABEL
        .dw     sa_txt_read
        .db     0xff
sa_title_lines:
        .db     9, 8, SA_ATTR_TITLE
        .dw     sa_txt_name
        .db     4, 10, SA_ATTR_LABEL
        .dw     sa_txt_tagline
        .db     8, 15, SA_ATTR_TEXT
        .dw     sa_txt_start
        .db     5, 17, SA_ATTR_TEXT
        .dw     sa_txt_howto
        .db     4, 22, SA_ATTR_DIM
        .dw     sa_txt_credit
        .db     0xff
sa_help_lines:
        .db     9, 2, SA_ATTR_TITLE
        .dw     sa_txt_name
        .db     1, 5, SA_ATTR_TEXT
        .dw     sa_help_1
        .db     1, 7, SA_ATTR_TEXT
        .dw     sa_help_2
        .db     1, 9, SA_ATTR_TEXT
        .dw     sa_help_3
        .db     1, 11, SA_ATTR_TEXT
        .dw     sa_help_4
        .db     1, 13, SA_ATTR_TEXT
        .dw     sa_help_5
        .db     1, 15, SA_ATTR_TEXT
        .dw     sa_help_6
        .db     1, 17, SA_ATTR_TEXT
        .dw     sa_help_7
        .db     1, 19, SA_ATTR_TEXT
        .dw     sa_help_8
        .db     1, 21, SA_ATTR_LABEL
        .dw     sa_help_back
        .db     0xff

sa_txt_name:
        .db     "SHADOW ARCHIVE", 0
sa_txt_case:
        .db     "CASE", 0
sa_txt_six:
        .db     "SIX SUSPECTS", 0
sa_txt_files:
        .db     "CASE FILES", 0
sa_txt_hat:
        .db     "1 HAT", 0
sa_txt_glasses:
        .db     "2 GLASSES", 0
sa_txt_tie:
        .db     "3 TIE", 0
sa_txt_read:
        .db     "FILES READ", 0
sa_txt_yes:
        .db     "YES", 0
sa_txt_no:
        .db     "NO", 0
sa_txt_accuse:
        .db     "ACCUSE", 0
sa_txt_open_file:
        .db     "OPEN FILE", 0
sa_txt_paper:
        .db     "__________", 0
sa_txt_gold:
        .db     "GOLD DETECTIVE", 0
sa_txt_closed:
        .db     "CASE CLOSED", 0
sa_txt_lose:
        .db     "THE SUSPECT DOES NOT FIT", 0
sa_txt_tagline:
        .db     "HAT, GLASSES OR TIE?", 0
sa_txt_start:
        .db     "RETURN : START", 0
sa_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
sa_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
sa_help_1:
        .db     "W/S : FILES OR ACCUSE MODE", 0
sa_help_2:
        .db     "A/D : SELECT FILE OR SUSPECT", 0
sa_help_3:
        .db     "RETURN : OPEN OR ACCUSE", 0
sa_help_4:
        .db     "CLUES: HAT, GLASSES, TIE.", 0
sa_help_5:
        .db     "RED X: CONTRADICTED SUSPECT.", 0
sa_help_6:
        .db     "SOLVE WITH TWO FILES: GOLD.", 0
sa_help_7:
        .db     "WRONG SUSPECT: CASE FAILED.", 0
sa_help_8:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
sa_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     sa_sfx_page, sa_sfx_file, sa_jingle_win, sa_jingle_lose
sa_sfx_page:
        .db     85, 2, 0, 0
sa_sfx_file:
        .db     120, 3, 0, 1, 95, 5, 0, 0

; Title: a slow B minor walk, quarter note = 24 frames, looping.
sa_title_song:
        .db     1
        .dw     sa_title_melody, sa_title_harmony, sa_title_bass
sa_title_melody:
        .db     AU_FS5, 24, AU_D5, 24, AU_B4, 24, AU_CS5, 24
        .db     AU_D5, 36, AU_E5, 12, AU_FS5, 48
        .db     AU_G5, 24, AU_FS5, 24, AU_E5, 24, AU_D5, 24
        .db     AU_CS5, 72, 0, 24, 0, 0
sa_title_harmony:
        .db     AU_D5, 48, AU_FS4, 48, AU_B4, 48, AU_A4, 48
        .db     AU_B4, 48, AU_G4, 48, AU_AS4, 72, 0, 24, 0, 0
sa_title_bass:
        .db     AU_B2, 24, AU_FS3, 24, AU_B2, 24, AU_FS3, 24
        .db     AU_G2, 24, AU_D3, 24, AU_D3, 24, AU_A2, 24
        .db     AU_E3, 24, AU_B2, 24, AU_E3, 24, AU_B2, 24
        .db     AU_FS2, 72, 0, 24, 0, 0

; Case closed: rising B major arpeggio over a held tonic (54 frames).
sa_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     sa_win_melody, sa_win_harmony, sa_win_bass
sa_win_melody:
        .db     AU_B4, 8, AU_DS5, 8, AU_FS5, 8, AU_B5, 30, 0, 0
sa_win_harmony:
        .db     AU_FS4, 8, AU_B4, 8, AU_DS5, 8, AU_FS5, 30, 0, 0
sa_win_bass:
        .db     AU_B2, 24, AU_B2, 30, 0, 0
sa_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     sa_lose_melody, sa_lose_harmony, sa_lose_bass
sa_lose_melody:
        .db     AU_FS5, 12, AU_E5, 12, AU_D5, 12, AU_CS5, 30, 0, 0
sa_lose_harmony:
        .db     AU_D5, 12, AU_CS5, 12, AU_B4, 12, AU_AS4, 30, 0, 0
sa_lose_bass:
        .db     AU_B2, 36, AU_FS2, 30, 0, 0

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
