; SPDX-License-Identifier: MIT
; NUMBER VAULT for JR-200: a port of jr100dev games/number_vault/rules.py 2.1.0.
; The code derivation, exact/near scoring, six-row history and ten-try limit
; follow the upstream source; display, colour and three-voice sound use the
; JR-200 port SDK. Upstream's entropy() (the JR-100 timer) is replaced by the
; position of the title song when a stage starts.
        .filename.jr "NUMBER-VAULT"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
JR_INPUT:          .equ    JR_RT + 0x300
GAME_INPUT_POLICY: .equ    jr_input_default_policy
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
NV_LOG:             .equ    0x4720      ; count, then each sampled origin
NV_LOG_MAX:         .equ    31
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    10
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py).
NV_ORIGIN:          .equ    GAME_STATE
NV_SECRET:          .equ    GAME_STATE + 1
NV_CURSOR:          .equ    GAME_STATE + 2
NV_EXACT:           .equ    GAME_STATE + 3
NV_NEAR:            .equ    GAME_STATE + 4
NV_TRIES:           .equ    GAME_STATE + 5
NV_B:               .equ    GAME_STATE + 6      ; b[4] dials
NV_D:               .equ    GAME_STATE + 10     ; d[4] code
NV_HIST:            .equ    GAME_STATE + 14     ; c[32..67]
NV_SPIN:            .equ    GAME_STATE + 50
NV_SCAN:            .equ    GAME_STATE + 51
NV_OPENING:         .equ    GAME_STATE + 52
NV_CG:              .equ    GAME_STATE + 53     ; c[0..3] guess used
NV_CS:              .equ    GAME_STATE + 57     ; c[4..7] code used
; Effect and rule work bytes.
NV_EFFECT:          .equ    GAME_STATE + 61
NV_EPHASE:          .equ    GAME_STATE + 62
NV_I:               .equ    GAME_STATE + 63
NV_J:               .equ    GAME_STATE + 64
NV_T:               .equ    GAME_STATE + 65
NV_FRAME:           .equ    GAME_STATE + 66
; Drawing work bytes.
NV_DI:              .equ    GAME_STATE + 72
NV_DX:              .equ    GAME_STATE + 73
NV_DY:              .equ    GAME_STATE + 74
NV_DP:              .equ    GAME_STATE + 75
NV_ROWP:            .equ    GAME_STATE + 76

NV_TILE_DOOR:       .equ    0x80
NV_TILE_SPARK:      .equ    0x00
NV_ATTR_DOOR:       .equ    0x46
NV_ATTR_SPARK:      .equ    0x46
NV_ATTR_DIAL:       .equ    0x07
NV_ATTR_CURSOR:     .equ    0x06
NV_ATTR_EXACT:      .equ    0x04
NV_ATTR_NEAR:       .equ    0x06
NV_ATTR_TEXT:       .equ    0x07
NV_ATTR_LABEL:      .equ    0x04
NV_ATTR_TITLE:      .equ    0x06
NV_ATTR_DIM:        .equ    0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        CLR     [NV_LOG]
        JSR     jr_font_install
        LDX     nv_patterns
        LDAA    NV_TILE_DOOR
        LDAB    12
        JSR     jr_pcg_load
        LDX     nv_spark_patterns
        CLRA
        LDAB    12
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; origin = entropy(): (voice 0 offset * 8 + frames left) of the song playing
; when the stage starts. secret = origin ^ (level * 23 + 17).
game_init:
        LDAA    [JR_AU_VOICE + 1]
        SUBA    [JR_AU_VOICE + 4]
        ASLA
        ASLA
        ASLA
        ADDA    [JR_AU_VOICE + 2]
        STAA    [NV_ORIGIN]
        JSR     jr_music_stop
        LDAB    [NV_LOG]
        CMPB    NV_LOG_MAX
        BCC     nv_init_code
        INC     [NV_LOG]
        LDX     NV_LOG + 1
        LDAA    [NV_LOG]
        DECA
        JSR     jr_add_x_a
        LDAA    [NV_ORIGIN]
        STAA    [X]
nv_init_code:
        LDAA    [JR_PORT_LEVEL]
        LDAB    23
        JSR     jr_mul8
        ADDA    17
        EORA    [NV_ORIGIN]
        STAA    [NV_SECRET]
        ; d[i] = 1 + (secret >> (i * 2)) % 4, b[i] = 1
        LDX     NV_B
        LDAB    4
nv_init_digit:
        PSHA
        ANDA    3
        INCA
        STAA    [X + 4]
        LDAA    1
        STAA    [X]
        PULA
        LSRA
        LSRA
        INX
        DECB
        BNE     nv_init_digit
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_LEFT
        BNE     nv_act_right
        LDAA    [NV_CURSOR]
        ADDA    3
        BRA     nv_act_cursor
nv_act_right:
        CMPA    JR_KEY_RIGHT
        BNE     nv_act_up
        LDAA    [NV_CURSOR]
        INCA
nv_act_cursor:
        ANDA    3
        STAA    [NV_CURSOR]
        RTS
nv_act_up:
        CMPA    JR_KEY_UP
        BNE     nv_act_down
        LDAB    1
        BRA     nv_act_spin
nv_act_down:
        CMPA    JR_KEY_DOWN
        BNE     nv_act_test
        LDAB    3
nv_act_spin:
        ; up: b % 4 + 1, down: (b + 2) % 4 + 1
        STAB    [NV_T]
        LDAA    1
        STAA    [NV_SPIN]
        CLRA
        JSR     jr_port_sound
        LDAA    4
        JSR     jr_port_animate
        LDAA    [NV_CURSOR]
        LDX     NV_B
        JSR     jr_add_x_a
        LDAA    [X]
        ADDA    [NV_T]
        DECA
        ANDA    3
        INCA
        STAA    [X]
        CLR     [NV_SPIN]
        RTS
nv_act_test:
        CMPA    JR_KEY_CONFIRM
        BEQ     nv_test
        RTS

nv_test:
        CLR     [NV_EXACT]
        CLR     [NV_NEAR]
        LDX     NV_CG
        LDAB    8
nv_test_clear:
        CLR     [X]
        INX
        DECB
        BNE     nv_test_clear
        ; exact matches
        LDX     NV_B
        LDAB    4
nv_test_exact:
        LDAA    [X]
        CMPA    [X + 4]
        BNE     nv_test_exact_next
        INC     [NV_EXACT]
        LDAA    1
        STAA    [X + 47]            ; c[i] (NV_CG = NV_B + 47)
        STAA    [X + 51]            ; c[i + 4]
nv_test_exact_next:
        INX
        DECB
        BNE     nv_test_exact
        ; near matches: each code digit counts once
        CLR     [NV_I]
nv_test_near_i:
        LDX     NV_CG
        LDAA    [NV_I]
        JSR     jr_add_x_a
        TST     [X]
        BNE     nv_test_near_next_i
        CLR     [NV_J]
nv_test_near_j:
        LDX     NV_CG
        LDAA    [NV_I]
        JSR     jr_add_x_a
        TST     [X]
        BNE     nv_test_near_next_j
        LDX     NV_CS
        LDAA    [NV_J]
        JSR     jr_add_x_a
        TST     [X]
        BNE     nv_test_near_next_j
        LDX     NV_B
        LDAA    [NV_I]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [NV_T]
        LDX     NV_D
        LDAA    [NV_J]
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    [NV_T]
        BNE     nv_test_near_next_j
        LDAA    1
        STAA    [X + 47]            ; c[j + 4] (NV_CS = NV_D + 47)
        LDX     NV_CG
        LDAA    [NV_I]
        JSR     jr_add_x_a
        LDAA    1
        STAA    [X]
        INC     [NV_NEAR]
nv_test_near_next_j:
        INC     [NV_J]
        LDAA    [NV_J]
        CMPA    4
        BNE     nv_test_near_j
nv_test_near_next_i:
        INC     [NV_I]
        LDAA    [NV_I]
        CMPA    4
        BNE     nv_test_near_i
        ; history: shift six-byte rows up, append this code and its score
        LDX     NV_HIST
nv_test_shift:
        LDAA    [X + 6]
        STAA    [X]
        INX
        CPX     NV_HIST + 30
        BNE     nv_test_shift
        CLR     [NV_I]
nv_test_scan:
        LDX     NV_B
        LDAA    [NV_I]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [X + 38]            ; c[62 + i] (NV_HIST + 30 = NV_B + 38)
        LDAA    [NV_I]
        INCA
        STAA    [NV_SCAN]
        CLRA
        JSR     jr_port_sound
        LDAA    5
        JSR     jr_port_animate
        INC     [NV_I]
        LDAA    [NV_I]
        CMPA    4
        BNE     nv_test_scan
        LDAA    [NV_EXACT]
        STAA    [NV_HIST + 34]
        LDAA    [NV_NEAR]
        STAA    [NV_HIST + 35]
        CLR     [NV_SCAN]
        INC     [NV_TRIES]
        LDAA    1
        JSR     jr_port_sound
        LDAA    [NV_EXACT]
        CMPA    4
        BNE     nv_test_limit
        CLR     [NV_FRAME]
nv_test_open:
        INC     [NV_FRAME]
        LDAA    [NV_FRAME]
        STAA    [NV_OPENING]
        LDAA    10
        JSR     jr_port_animate
        LDAA    [NV_FRAME]
        CMPA    3
        BNE     nv_test_open
        JSR     nv_sparkle
        JMP     jr_port_win
nv_test_limit:
        LDAA    [NV_TRIES]
        CMPA    10
        BCS     nv_test_done
        LDX     nv_txt_lose
        JMP     jr_port_lose
nv_test_done:
        RTS

; sparkle(14, 3): three phases of animate(4).
nv_sparkle:
        LDAA    2
        STAA    [NV_EFFECT]
        CLR     [NV_FRAME]
nv_sparkle_phase:
        LDAA    [NV_FRAME]
        STAA    [NV_EPHASE]
        LDAA    4
        JSR     jr_port_animate
        INC     [NV_FRAME]
        LDAA    [NV_FRAME]
        CMPA    3
        BNE     nv_sparkle_phase
        CLR     [NV_EFFECT]
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    NV_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     nv_hud
        JSR     jr_gfx_lines
        LDAA    NV_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; four dials at x = 3 + i * 7
        CLR     [NV_DI]
nv_draw_dial:
        LDAA    [NV_DI]
        LDAB    7
        JSR     jr_mul8
        ADDA    3
        STAA    [NV_DX]
        LDAA    NV_ATTR_DIAL
        STAA    [JR_RT_COLOR]
        LDAA    [NV_DX]
        LDAB    4
        JSR     jr_gfx_at
        LDX     nv_txt_rim
        JSR     jr_gfx_text
        LDAA    [NV_DX]
        LDAB    5
        JSR     jr_gfx_at
        LDAA    0x5b
        JSR     jr_gfx_putc
        ; digit in its colour, '-' while this dial spins
        LDX     NV_B
        LDAA    [NV_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [NV_DP]
        LDX     nv_digit_attr - 1
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [NV_DP]
        ADDA    0x30
        TST     [NV_SPIN]
        BEQ     nv_draw_digit
        LDAB    [NV_DI]
        CMPB    [NV_CURSOR]
        BNE     nv_draw_digit
        LDAA    0x2d
nv_draw_digit:
        JSR     jr_gfx_putc
        LDAA    NV_ATTR_DIAL
        STAA    [JR_RT_COLOR]
        LDAA    0x5d
        JSR     jr_gfx_putc
        LDAA    [NV_DI]
        INCA
        CMPA    [NV_SCAN]
        BNE     nv_draw_dial_next
        LDAA    NV_ATTR_CURSOR
        STAA    [JR_RT_COLOR]
        LDAA    [NV_DX]
        LDAB    6
        JSR     jr_gfx_at
        LDAA    0x2a
        JSR     jr_gfx_putc
nv_draw_dial_next:
        INC     [NV_DI]
        LDAA    [NV_DI]
        CMPA    4
        BEQ     nv_draw_dial_near410
        JMP     nv_draw_dial
nv_draw_dial_near410:
        ; 'V' above the selected dial
        LDAA    NV_ATTR_CURSOR
        STAA    [JR_RT_COLOR]
        LDAA    [NV_CURSOR]
        LDAB    7
        JSR     jr_mul8
        ADDA    4
        LDAB    3
        JSR     jr_gfx_at
        LDAA    0x56
        JSR     jr_gfx_putc
        ; history rows at y = 10 + row * 2
        CLR     [NV_DI]
nv_draw_row:
        LDAA    [NV_DI]
        LDAB    6
        JSR     jr_mul8
        LDX     NV_HIST
        JSR     jr_add_x_a
        STX     [NV_ROWP]
        TST     [X]
        BEQ     nv_draw_row_next
        LDAA    [NV_DI]
        ASLA
        ADDA    10
        STAA    [NV_DY]
        CLR     [NV_DX]
nv_draw_row_digit:
        LDX     [NV_ROWP]
        LDAA    [NV_DX]
        JSR     jr_add_x_a
        LDAA    [X]
        PSHA
        LDX     nv_digit_attr - 1
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [NV_DX]
        LDAB    3
        JSR     jr_mul8
        ADDA    3
        LDAB    [NV_DY]
        JSR     jr_gfx_at
        PULA
        ADDA    0x30
        JSR     jr_gfx_putc
        INC     [NV_DX]
        LDAA    [NV_DX]
        CMPA    4
        BNE     nv_draw_row_digit
        LDAA    NV_ATTR_EXACT
        STAA    [JR_RT_COLOR]
        LDAA    21
        LDAB    [NV_DY]
        JSR     jr_gfx_at
        LDX     [NV_ROWP]
        LDAA    [X + 4]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    NV_ATTR_NEAR
        STAA    [JR_RT_COLOR]
        LDAA    27
        LDAB    [NV_DY]
        JSR     jr_gfx_at
        LDX     [NV_ROWP]
        LDAA    [X + 5]
        ADDA    0x30
        JSR     jr_gfx_putc
nv_draw_row_next:
        INC     [NV_DI]
        LDAA    [NV_DI]
        CMPA    6
        BEQ     nv_draw_row_near485
        JMP     nv_draw_row
nv_draw_row_near485:
        LDAA    NV_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    14
        LDAB    22
        JSR     jr_gfx_at
        LDAA    10
        SUBA    [NV_TRIES]
        JSR     jr_gfx_dec2
        ; the vault door opens in three steps
        LDAA    [NV_OPENING]
        BEQ     nv_draw_effect
        DECA
        ASLA
        ASLA
        ADDA    NV_TILE_DOOR
        PSHA
        LDAA    NV_ATTR_DOOR
        STAA    [JR_RT_COLOR]
        LDAA    14
        LDAB    4
        JSR     jr_gfx_at
        PULA
        JSR     jr_gfx_tile
        LDAA    NV_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    11
        LDAB    6
        JSR     jr_gfx_at
        LDX     nv_txt_open
        JSR     jr_gfx_text
nv_draw_effect:
        LDAA    [NV_EFFECT]
        BEQ     nv_draw_done
        LDAA    NV_ATTR_SPARK
        STAA    [JR_RT_COLOR]
        LDAA    14
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [NV_EPHASE]
        ASLA
        ASLA
        JMP     jr_gfx_tile
nv_draw_done:
        RTS

game_draw_title:
        LDX     nv_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    NV_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    NV_ATTR_DOOR
        STAA    [JR_RT_COLOR]
        LDAA    15
        LDAB    3
        JSR     jr_gfx_at
        LDAA    NV_TILE_DOOR
        JSR     jr_gfx_tile
        LDX     nv_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    NV_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     nv_help_diagram
        JSR     jr_guide_draw
        LDX     nv_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; Digit colours 1-4: red, green, yellow, cyan.
nv_digit_attr:
        .db     0x02, 0x04, 0x06, 0x05

nv_hud:
        .db     1, 0, NV_ATTR_TITLE
        .dw     nv_txt_name
        .db     23, 0, NV_ATTR_LABEL
        .dw     nv_txt_vault
        .db     2, 8, NV_ATTR_LABEL
        .dw     nv_txt_history
        .db     2, 22, NV_ATTR_LABEL
        .dw     nv_txt_tries
        .db     0xff
nv_title_lines:
        .db     10, 8, NV_ATTR_TITLE
        .dw     nv_txt_name
        .db     3, 10, NV_ATTR_LABEL
        .dw     nv_txt_tagline
        .db     8, 12, NV_ATTR_TEXT
        .dw     nv_txt_sample
        .db     8, 15, NV_ATTR_TEXT
        .dw     nv_txt_start
        .db     5, 17, NV_ATTR_TEXT
        .dw     nv_txt_howto
        .db     4, 22, NV_ATTR_DIM
        .dw     nv_txt_credit
        .db     0xff
nv_help_lines:
        .db     10, 1, NV_ATTR_TITLE
        .dw     nv_txt_name
        .db     2, 4, NV_ATTR_LABEL
        .dw     nv_help_label_1
        .db     2, 8, NV_ATTR_LABEL
        .dw     nv_help_label_2
        .db     10, 12, NV_ATTR_TEXT
        .dw     nv_help_label_3
        .db     19, 12, NV_ATTR_TEXT
        .dw     nv_help_label_4
        .db     2, 16, NV_ATTR_TEXT
        .dw     nv_help_label_5
        .db     2, 18, NV_ATTR_TEXT
        .dw     nv_help_label_6
        .db     2, 20, NV_ATTR_TEXT
        .dw     nv_help_label_7
        .db     2, 22, NV_ATTR_LABEL
        .dw     nv_help_label_8
        .db     0xff
nv_help_label_1:
        .db     "CODE", 0
nv_help_label_2:
        .db     "TRY", 0
nv_help_label_3:
        .db     "EXACT", 0
nv_help_label_4:
        .db     "NEAR X2", 0
nv_help_label_5:
        .db     "A/D DIAL  W/S 1-4  RETURN TEST", 0
nv_help_label_6:
        .db     "OPEN WITHIN 10 TRIES", 0
nv_help_label_7:
        .db     "SPACE RETRY  CTRL+C BASIC", 0
nv_help_label_8:
        .db     "ANY KEY TO TITLE", 0

nv_help_diagram:
; One exact match, two swapped digits, and a digit absent from the code.
        .db     10, 4, NV_ATTR_EXACT, 1, 0x31
        .db     13, 4, NV_ATTR_NEAR, 1, 0x32
        .db     16, 4, NV_ATTR_NEAR, 1, 0x33
        .db     19, 4, NV_ATTR_TEXT, 1, 0x34
        .db     10, 8, NV_ATTR_EXACT, 1, 0x31
        .db     13, 8, NV_ATTR_NEAR, 1, 0x33
        .db     16, 8, NV_ATTR_NEAR, 1, 0x32
        .db     19, 8, NV_ATTR_TEXT, 1, 0x33
        .db     10, 5, 0xa4, 1, 0x24
        .db     10, 6, 0xa4, 1, 0x24
        .db     10, 7, 0xa4, 1, 0x24
        .db     13, 5, 0x86, 1, 0x06
        .db     14, 6, 0x80, 2, 0x36, 0x36
        .db     16, 7, 0x86, 1, 0x06
        .db     16, 5, 0xb0, 1, 0x30
        .db     13, 7, 0xb0, 1, 0x30
        .db     10, 11, 0xa4, 1, 0x24
        .db     19, 11, 0xb6, 2, 0x36, 0x36
        .db     25, 0x80 + 5, NV_ATTR_DOOR, 1, NV_TILE_DOOR
        .db     0xff

nv_txt_name:
        .db     "NUMBER VAULT", 0
nv_txt_vault:
        .db     "VAULT", 0
nv_txt_rim:
        .db     "___", 0
nv_txt_history:
        .db     "LAST SIX CODES    EXACT NEAR", 0
nv_txt_tries:
        .db     "TRIES LEFT", 0
nv_txt_open:
        .db     "VAULT OPEN", 0
nv_txt_lose:
        .db     "TEN CODES DID NOT OPEN VAULT", 0
nv_txt_tagline:
        .db     "FOUR DIALS, DIGITS ONE TO FOUR", 0
nv_txt_sample:
        .db     "EXACT 2   NEAR 1", 0
nv_txt_start:
        .db     "RETURN : START", 0
nv_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
nv_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     nv_sfx_click, nv_sfx_score, nv_jingle_win, nv_jingle_lose
nv_sfx_click:
        .db     50, 1, 0, 0
nv_sfx_score:
        .db     130, 3, 0, 1, 100, 5, 0, 0

; Title: four bars in C minor, eighth note = 12 frames, looping.
nv_title_song:
        .db     1
        .dw     nv_title_melody, nv_title_harmony, nv_title_bass
nv_title_melody:
        .db     AU_C5, 12, AU_DS5, 12, AU_G5, 12, AU_C6, 12, AU_AS5, 24, AU_G5, 24
        .db     AU_GS5, 12, AU_G5, 12, AU_F5, 12, AU_DS5, 12, AU_D5, 24, AU_B4, 24
        .db     AU_C5, 12, AU_DS5, 12, AU_G5, 12, AU_C6, 12, AU_D6, 24, AU_B5, 24
        .db     AU_C6, 72, 0, 24, 0, 0
nv_title_harmony:
        .db     AU_G4, 48, AU_DS4, 48, AU_F4, 48, AU_G4, 48
        .db     AU_G4, 48, AU_F4, 48, AU_DS4, 72, 0, 24, 0, 0
nv_title_bass:
        .db     AU_C3, 24, AU_G2, 24, AU_C3, 24, AU_G2, 24
        .db     AU_F2, 24, AU_C3, 24, AU_G2, 24, AU_D3, 24
        .db     AU_C3, 24, AU_G2, 24, AU_G2, 24, AU_G3, 24
        .db     AU_C3, 72, 0, 24, 0, 0

; Clear: rising C major arpeggio over a held tonic (54 frames).
nv_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     nv_win_melody, nv_win_harmony, nv_win_bass
nv_win_melody:
        .db     AU_C5, 8, AU_E5, 8, AU_G5, 8, AU_C6, 30, 0, 0
nv_win_harmony:
        .db     AU_G4, 8, AU_C5, 8, AU_E5, 8, AU_G5, 30, 0, 0
nv_win_bass:
        .db     AU_C3, 24, AU_C2, 30, 0, 0
nv_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     nv_lose_melody, nv_lose_harmony, nv_lose_bass
nv_lose_melody:
        .db     AU_G4, 12, AU_F4, 12, AU_DS4, 12, AU_D4, 30, 0, 0
nv_lose_harmony:
        .db     AU_DS4, 12, AU_D4, 12, AU_C4, 12, AU_B3, 30, 0, 0
nv_lose_bass:
        .db     AU_C3, 36, AU_G2, 30, 0, 0

        .include "art.inc"
        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys.inc"
        .include "../../../sdk/gfx_buffered.inc"
        .include "../../../sdk/font.inc"
        .include "../../../sdk/pcg.inc"
        .include "../../../sdk/frame.inc"
        .include "../../../sdk/math.inc"
        .include "../../../sdk/sound.inc"
        .include "../../../sdk/audio.inc"
        .include "../../../sdk/audio_notes.inc"
        .include "../../../sdk/port_buffered.inc"
        .include "../../../sdk/guide.inc"
        .include "../../../sdk/font_data.inc"
