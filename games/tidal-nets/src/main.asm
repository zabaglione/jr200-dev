; SPDX-License-Identifier: MIT
; TIDAL NETS for JR-200: a port of jr100dev games/tidal_nets/rules.py 3.0.0.
; Tides, the two shoals, fine and wide nets, rope and the quotas follow the
; upstream source; display, colour and three-voice sound use the JR-200 SDK.
        .filename.jr "TIDAL-NETS"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    3
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    22
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py).
TN_FISH:            .equ    GAME_STATE
TN_DEEP:            .equ    GAME_STATE + 1
TN_ROPE:            .equ    GAME_STATE + 2
TN_QUOTA:           .equ    GAME_STATE + 3
TN_TIDE:            .equ    GAME_STATE + 4
TN_FORCE:           .equ    GAME_STATE + 5
TN_CURSOR:          .equ    GAME_STATE + 6
TN_WIDE:            .equ    GAME_STATE + 7
TN_CASTS:           .equ    GAME_STATE + 8
TN_CATCH:           .equ    GAME_STATE + 9
TN_NOTICE:          .equ    GAME_STATE + 10
TN_CASTING:         .equ    GAME_STATE + 11
TN_SWIMMING:        .equ    GAME_STATE + 12
; Flight effect and rule work bytes.
TN_EFFECT:          .equ    GAME_STATE + 16
TN_ECODE:           .equ    GAME_STATE + 17
TN_EATTR:           .equ    GAME_STATE + 18
TN_EX:              .equ    GAME_STATE + 19
TN_EY:              .equ    GAME_STATE + 20
TN_FX:              .equ    GAME_STATE + 21
TN_FY:              .equ    GAME_STATE + 22
TN_TX:              .equ    GAME_STATE + 23
TN_TY:              .equ    GAME_STATE + 24
TN_FRAME:           .equ    GAME_STATE + 25
TN_IA:              .equ    GAME_STATE + 26
TN_LANDING:         .equ    GAME_STATE + 27
TN_BELOW:           .equ    GAME_STATE + 28
TN_GAIN:            .equ    GAME_STATE + 29
TN_STEP:            .equ    GAME_STATE + 30
; Drawing work bytes.
TN_DI:              .equ    GAME_STATE + 40

TN_TILE_WAVE:       .equ    0x80
TN_TILE_FISH:       .equ    0x84
TN_TILE_NET:        .equ    0x88
TN_ATTR_WAVE:       .equ    0x4d        ; cyan waves on blue water
TN_ATTR_SHOAL:      .equ    0x46        ; yellow shoal fish
TN_ATTR_DEEP:       .equ    0x43        ; magenta deep fish
TN_ATTR_NET:        .equ    0x47
TN_ATTR_TEXT:       .equ    0x07
TN_ATTR_LABEL:      .equ    0x04
TN_ATTR_TITLE:      .equ    0x06
TN_ATTR_DIM:        .equ    0x05
TN_ATTR_TIDE:       .equ    0x05
TN_ATTR_GOOD:       .equ    0x04
TN_ATTR_BAD:        .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     tn_patterns
        LDAA    TN_TILE_WAVE
        LDAB    12
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        LDAA    [JR_PORT_LEVEL]
        ASLA
        ADDA    3
        ANDA    7
        STAA    [TN_FISH]
        LDAA    [JR_PORT_LEVEL]
        LDAB    3
        JSR     jr_mul8
        STAA    [TN_STEP]
        INCA
        ANDA    7
        STAA    [TN_DEEP]
        LDAA    12
        STAA    [TN_ROPE]
        LDAA    [TN_STEP]
        ADDA    30
        STAA    [TN_QUOTA]
        JMP     tn_current

; tide = 1 if (casts + level) % 3 == 0 else 7; force = 1 + (casts + level) % 2
tn_current:
        LDAA    [TN_CASTS]
        ADDA    [JR_PORT_LEVEL]
        PSHA
        ANDA    1
        INCA
        STAA    [TN_FORCE]
        PULA
        LDAB    3
        JSR     jr_divmod8
        LDAA    7
        TSTB
        BNE     tn_current_store
        LDAA    1
tn_current_store:
        STAA    [TN_TIDE]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_LEFT
        BNE     tn_act_right
        LDAA    [TN_CURSOR]
        ADDA    7
        BRA     tn_act_cursor
tn_act_right:
        CMPA    JR_KEY_RIGHT
        BNE     tn_act_width
        LDAA    [TN_CURSOR]
        INCA
tn_act_cursor:
        ANDA    7
        STAA    [TN_CURSOR]
        RTS
tn_act_width:
        CMPA    JR_KEY_DOWN
        BHI     tn_act_cast
        LDAA    [TN_WIDE]
        EORA    1
        STAA    [TN_WIDE]
        CLRA
        JMP     jr_port_sound
tn_act_cast:
        CMPA    JR_KEY_CONFIRM
        BEQ     tn_cast
        RTS

tn_cast:
        LDAB    1
        TST     [TN_WIDE]
        BEQ     tn_cast_cost
        LDAB    2
tn_cast_cost:
        LDAA    [TN_ROPE]
        SBA
        BCC     tn_cast_go
        LDAA    7
        STAA    [TN_NOTICE]
        LDX     tn_sfx_empty
        JMP     jr_sfx_play
tn_cast_go:
        STAA    [TN_ROPE]
        CLR     [TN_NOTICE]
        LDAA    1
        STAA    [TN_CASTING]
        CLRA
        JSR     jr_port_sound
        ; the net sinks: flight(cursor * 4, 14 -> cursor * 4, 10)
        LDAA    [TN_CURSOR]
        ASLA
        ASLA
        STAA    [TN_FX]
        STAA    [TN_TX]
        LDAA    14
        STAA    [TN_FY]
        LDAA    10
        STAA    [TN_TY]
        LDAA    TN_TILE_NET
        LDAB    TN_ATTR_NET
        JSR     tn_flight
        CLR     [TN_CASTING]
        ; landing = (fish + tide * force) % 8, below = (deep + tide * force * 2) % 8
        LDAA    [TN_TIDE]
        LDAB    [TN_FORCE]
        JSR     jr_mul8
        STAA    [TN_STEP]
        ADDA    [TN_FISH]
        ANDA    7
        STAA    [TN_LANDING]
        LDAA    [TN_STEP]
        ASLA
        ADDA    [TN_DEEP]
        ANDA    7
        STAA    [TN_BELOW]
        LDAA    1
        STAA    [TN_SWIMMING]
        LDAA    [TN_FISH]
        ASLA
        ASLA
        STAA    [TN_FX]
        LDAA    [TN_LANDING]
        ASLA
        ASLA
        STAA    [TN_TX]
        LDAA    7
        STAA    [TN_FY]
        STAA    [TN_TY]
        LDAA    TN_TILE_FISH
        LDAB    TN_ATTR_SHOAL
        JSR     tn_flight
        LDAA    [TN_LANDING]
        STAA    [TN_FISH]
        LDAA    2
        STAA    [TN_SWIMMING]
        LDAA    [TN_DEEP]
        ASLA
        ASLA
        STAA    [TN_FX]
        LDAA    [TN_BELOW]
        ASLA
        ASLA
        STAA    [TN_TX]
        LDAA    10
        STAA    [TN_FY]
        STAA    [TN_TY]
        LDAA    TN_TILE_FISH
        LDAB    TN_ATTR_DEEP
        JSR     tn_flight
        LDAA    [TN_BELOW]
        STAA    [TN_DEEP]
        CLR     [TN_SWIMMING]
        ; gain 2 for the shoal, 4 for the deep fish, under the net
        CLR     [TN_GAIN]
        LDAA    [TN_LANDING]
        JSR     tn_under_net
        BNE     tn_cast_deep
        LDAA    2
        STAA    [TN_GAIN]
tn_cast_deep:
        LDAA    [TN_BELOW]
        JSR     tn_under_net
        BNE     tn_cast_result
        LDAA    [TN_GAIN]
        ADDA    4
        STAA    [TN_GAIN]
tn_cast_result:
        LDAA    [TN_GAIN]
        BEQ     tn_cast_miss
        STAA    [TN_NOTICE]
        LDAA    1
        JSR     jr_port_sound
        LDAA    [TN_CURSOR]
        ASLA
        ASLA
        STAA    [TN_FX]
        LDAA    10
        STAA    [TN_FY]
        LDAA    12
        STAA    [TN_TX]
        LDAA    19
        STAA    [TN_TY]
        LDAA    TN_TILE_NET
        LDAB    TN_ATTR_SHOAL
        JSR     tn_flight
        LDAA    [TN_CATCH]
        ADDA    [TN_GAIN]
        STAA    [TN_CATCH]
        BRA     tn_cast_settle
tn_cast_miss:
        LDX     tn_sfx_empty
        JSR     jr_sfx_play
tn_cast_settle:
        LDAA    16
        JSR     jr_port_animate
        INC     [TN_CASTS]
        ; fish = (fish * 3 + 5 + level) % 8, deep = (deep * 5 + 3 + level) % 8
        LDAA    [TN_FISH]
        LDAB    3
        JSR     jr_mul8
        ADDA    5
        ADDA    [JR_PORT_LEVEL]
        ANDA    7
        STAA    [TN_FISH]
        LDAA    [TN_DEEP]
        LDAB    5
        JSR     jr_mul8
        ADDA    3
        ADDA    [JR_PORT_LEVEL]
        ANDA    7
        STAA    [TN_DEEP]
        JSR     tn_current
        LDAA    [TN_CATCH]
        CMPA    [TN_QUOTA]
        BCS     tn_cast_limit
        JMP     jr_port_win
tn_cast_limit:
        LDAA    [TN_CASTS]
        CMPA    9
        BEQ     tn_cast_lost
        TST     [TN_ROPE]
        BNE     tn_cast_done
tn_cast_lost:
        LDX     tn_txt_lose
        JMP     jr_port_lose
tn_cast_done:
        RTS

; A = column: Z set when the net covers it (cursor, or cursor + 1 when wide).
tn_under_net:
        CMPA    [TN_CURSOR]
        BEQ     tn_under_done
        TST     [TN_WIDE]
        BEQ     tn_under_no
        DECA
        ANDA    7
        CMPA    [TN_CURSOR]
        RTS
tn_under_no:
        LDAA    1
tn_under_done:
        RTS

; A = tile, B = attribute: moves from (FX, FY) to (TX, TY) in five animate(3).
tn_flight:
        STAA    [TN_ECODE]
        STAB    [TN_EATTR]
        LDAA    1
        STAA    [TN_EFFECT]
        CLR     [TN_FRAME]
tn_flight_frame:
        LDAA    [TN_FX]
        LDAB    [TN_TX]
        JSR     tn_interp
        STAA    [TN_EX]
        LDAA    [TN_FY]
        LDAB    [TN_TY]
        JSR     tn_interp
        STAA    [TN_EY]
        LDAA    3
        JSR     jr_port_animate
        INC     [TN_FRAME]
        LDAA    [TN_FRAME]
        CMPA    5
        BNE     tn_flight_frame
        CLR     [TN_EFFECT]
        RTS

; A = from, B = to -> A = from + (to - from) * frame // 4 (upstream flight()).
tn_interp:
        STAA    [TN_IA]
        CBA
        BHI     tn_interp_back
        SUBB    [TN_IA]
        TBA
        LDAB    [TN_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        ADDA    [TN_IA]
        RTS
tn_interp_back:
        SBA
        LDAB    [TN_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        NEGA
        ADDA    [TN_IA]
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    TN_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     tn_hud
        JSR     jr_gfx_lines
        LDAA    TN_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; the sea (rows 7-13) and the column numbers
        CLR     [TN_DI]
tn_draw_column:
        LDAA    TN_ATTR_WAVE
        STAA    [JR_RT_COLOR]
        LDAA    [TN_DI]
        ASLA
        ASLA
        LDAB    12
        JSR     jr_gfx_at
        LDAA    TN_TILE_WAVE
        JSR     jr_gfx_tile
        LDAA    TN_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [TN_DI]
        ASLA
        ASLA
        LDAB    17
        JSR     jr_gfx_at
        LDAA    [TN_DI]
        ADDA    0x31
        JSR     jr_gfx_putc
        INC     [TN_DI]
        LDAA    [TN_DI]
        CMPA    8
        BNE     tn_draw_column
        ; the shoal (row 7) and the deep fish (row 10)
        LDAA    [TN_SWIMMING]
        CMPA    1
        BEQ     tn_draw_deep
        LDAA    TN_ATTR_SHOAL
        STAA    [JR_RT_COLOR]
        LDAA    [TN_FISH]
        ASLA
        ASLA
        LDAB    7
        JSR     jr_gfx_at
        LDAA    TN_TILE_FISH
        JSR     jr_gfx_tile
tn_draw_deep:
        LDAA    [TN_SWIMMING]
        CMPA    2
        BEQ     tn_draw_net
        LDAA    TN_ATTR_DEEP
        STAA    [JR_RT_COLOR]
        LDAA    [TN_DEEP]
        ASLA
        ASLA
        LDAB    10
        JSR     jr_gfx_at
        LDAA    TN_TILE_FISH
        JSR     jr_gfx_tile
tn_draw_net:
        TST     [TN_CASTING]
        BNE     tn_draw_hud
        LDAA    TN_ATTR_NET
        STAA    [JR_RT_COLOR]
        LDAA    [TN_CURSOR]
        ASLA
        ASLA
        LDAB    14
        JSR     jr_gfx_at
        LDAA    TN_TILE_NET
        JSR     jr_gfx_tile
        TST     [TN_WIDE]
        BEQ     tn_draw_hud
        LDAA    [TN_CURSOR]
        INCA
        ANDA    7
        ASLA
        ASLA
        LDAB    14
        JSR     jr_gfx_at
        LDAA    TN_TILE_NET
        JSR     jr_gfx_tile
tn_draw_hud:
        LDAA    TN_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    7
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [TN_QUOTA]
        JSR     jr_gfx_dec2
        LDAA    24
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [TN_ROPE]
        JSR     jr_gfx_dec2
        LDAA    TN_ATTR_TIDE
        STAA    [JR_RT_COLOR]
        LDAA    6
        LDAB    4
        JSR     jr_gfx_at
        LDAA    0x3e
        LDAB    [TN_TIDE]
        CMPB    1
        BEQ     tn_draw_tide
        LDAA    0x3c
tn_draw_tide:
        JSR     jr_gfx_putc
        LDAA    8
        LDAB    4
        JSR     jr_gfx_at
        LDAA    [TN_FORCE]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    TN_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    19
        LDAB    4
        JSR     jr_gfx_at
        LDX     tn_txt_fine
        TST     [TN_WIDE]
        BEQ     tn_draw_width
        LDX     tn_txt_wide
tn_draw_width:
        JSR     jr_gfx_text
        LDAA    12
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [TN_CATCH]
        JSR     jr_gfx_dec2
        LDAA    28
        LDAB    19
        JSR     jr_gfx_at
        LDAA    9
        SUBA    [TN_CASTS]
        JSR     jr_gfx_dec2
        ; notice on row 20
        LDAA    1
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [TN_NOTICE]
        BEQ     tn_draw_effect
        CMPA    7
        BNE     tn_draw_caught
        LDAA    TN_ATTR_BAD
        STAA    [JR_RT_COLOR]
        LDX     tn_txt_rope
        JSR     jr_gfx_text
        BRA     tn_draw_effect
tn_draw_caught:
        LDAA    TN_ATTR_GOOD
        STAA    [JR_RT_COLOR]
        LDX     tn_txt_caught
        JSR     jr_gfx_text
        LDAA    [TN_NOTICE]
        ADDA    0x30
        JSR     jr_gfx_putc
tn_draw_effect:
        TST     [TN_EFFECT]
        BEQ     tn_draw_done
        LDAA    [TN_EATTR]
        STAA    [JR_RT_COLOR]
        LDAA    [TN_EX]
        LDAB    [TN_EY]
        JSR     jr_gfx_at
        LDAA    [TN_ECODE]
        JMP     jr_gfx_tile
tn_draw_done:
        RTS

game_draw_title:
        LDX     tn_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    TN_ATTR_TEXT
        JSR     jr_gfx_fill
        CLR     [TN_DI]
tn_title_wave:
        LDAA    TN_ATTR_WAVE
        STAA    [JR_RT_COLOR]
        LDAA    [TN_DI]
        ASLA
        ASLA
        LDAB    5
        JSR     jr_gfx_at
        LDAA    TN_TILE_WAVE
        JSR     jr_gfx_tile
        INC     [TN_DI]
        LDAA    [TN_DI]
        CMPA    8
        BNE     tn_title_wave
        LDAA    TN_ATTR_SHOAL
        STAA    [JR_RT_COLOR]
        LDAA    9
        LDAB    3
        JSR     jr_gfx_at
        LDAA    TN_TILE_FISH
        JSR     jr_gfx_tile
        LDAA    TN_ATTR_DEEP
        STAA    [JR_RT_COLOR]
        LDAA    21
        LDAB    3
        JSR     jr_gfx_at
        LDAA    TN_TILE_FISH
        JSR     jr_gfx_tile
        LDX     tn_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    TN_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     tn_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

tn_hud:
        .db     1, 0, TN_ATTR_TITLE
        .dw     tn_txt_name
        .db     24, 0, TN_ATTR_LABEL
        .dw     tn_txt_trip
        .db     1, 2, TN_ATTR_LABEL
        .dw     tn_txt_quota
        .db     18, 2, TN_ATTR_LABEL
        .dw     tn_txt_rope_label
        .db     1, 4, TN_ATTR_LABEL
        .dw     tn_txt_tide
        .db     21, 6, TN_ATTR_SHOAL & 0x07
        .dw     tn_txt_shoal
        .db     21, 9, TN_ATTR_DEEP & 0x07
        .dw     tn_txt_deep
        .db     1, 19, TN_ATTR_LABEL
        .dw     tn_txt_fish
        .db     19, 19, TN_ATTR_LABEL
        .dw     tn_txt_casts
        .db     0xff
tn_title_lines:
        .db     11, 9, TN_ATTR_TITLE
        .dw     tn_txt_name
        .db     4, 11, TN_ATTR_LABEL
        .dw     tn_txt_tagline
        .db     8, 15, TN_ATTR_TEXT
        .dw     tn_txt_start
        .db     5, 17, TN_ATTR_TEXT
        .dw     tn_txt_howto
        .db     4, 22, TN_ATTR_DIM
        .dw     tn_txt_credit
        .db     0xff
tn_help_lines:
        .db     11, 1, TN_ATTR_TITLE
        .dw     tn_txt_name
        .db     1, 4, TN_ATTR_TEXT
        .dw     tn_help_1
        .db     1, 6, TN_ATTR_TEXT
        .dw     tn_help_2
        .db     1, 8, TN_ATTR_TEXT
        .dw     tn_help_3
        .db     1, 10, TN_ATTR_TEXT
        .dw     tn_help_4
        .db     1, 12, TN_ATTR_TEXT
        .dw     tn_help_5
        .db     1, 14, TN_ATTR_TEXT
        .dw     tn_help_6
        .db     1, 16, TN_ATTR_TEXT
        .dw     tn_help_7
        .db     1, 18, TN_ATTR_TEXT
        .dw     tn_help_8
        .db     1, 20, TN_ATTR_TEXT
        .dw     tn_help_9
        .db     1, 22, TN_ATTR_LABEL
        .dw     tn_help_back
        .db     0xff

tn_txt_name:
        .db     "TIDAL NETS", 0
tn_txt_trip:
        .db     "TRIP", 0
tn_txt_quota:
        .db     "QUOTA", 0
tn_txt_rope_label:
        .db     "ROPE", 0
tn_txt_tide:
        .db     "TIDE", 0
tn_txt_fine:
        .db     "FINE NET", 0
tn_txt_wide:
        .db     "WIDE NET", 0
tn_txt_shoal:
        .db     "SHOAL +2", 0
tn_txt_deep:
        .db     "DEEP +4", 0
tn_txt_fish:
        .db     "FISH", 0
tn_txt_casts:
        .db     "CASTS", 0
tn_txt_rope:
        .db     "NOT ENOUGH ROPE", 0
tn_txt_caught:
        .db     "CAUGHT +", 0
tn_txt_lose:
        .db     "THE FISHING TRIP MISSED QUOTA", 0
tn_txt_tagline:
        .db     "READ THE TIDE, CAST THE NET", 0
tn_txt_start:
        .db     "RETURN : START", 0
tn_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
tn_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
tn_help_1:
        .db     "A/D : PLACE NET  W/S : WIDTH", 0
tn_help_2:
        .db     "RETURN : CAST THROUGH THE TIDE", 0
tn_help_3:
        .db     "FINE NET: ONE COLUMN, ONE ROPE", 0
tn_help_4:
        .db     "WIDE NET: TWO COLUMNS, TWO ROPE", 0
tn_help_5:
        .db     "DEEP FISH DRIFT TWICE AS FAR.", 0
tn_help_6:
        .db     "SHOAL +2 / DEEP +4 / BOTH +6", 0
tn_help_7:
        .db     "NINE CASTS AND TWELVE ROPE.", 0
tn_help_8:
        .db     "THREE TRIPS, HIGHER QUOTAS.", 0
tn_help_9:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
tn_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     tn_sfx_splash, tn_sfx_catch, tn_jingle_win, tn_jingle_lose
tn_sfx_splash:
        .db     200, 2, 160, 2, 0, 0
tn_sfx_catch:
        .db     70, 3, 55, 3, 45, 6, 0, 0
tn_sfx_empty:
        .db     230, 6, 0, 2, 240, 6, 0, 0

; Title: a lilting sea song in D major, 6/8 feel, eighth note = 12 frames.
tn_title_song:
        .db     1
        .dw     tn_title_melody, tn_title_harmony, tn_title_bass
tn_title_melody:
        .db     AU_D5, 24, AU_FS5, 12, AU_A5, 24, AU_FS5, 12
        .db     AU_G5, 24, AU_E5, 12, AU_CS5, 36
        .db     AU_D5, 24, AU_FS5, 12, AU_B5, 24, AU_A5, 12
        .db     AU_D5, 72, 0, 0
tn_title_harmony:
        .db     AU_A4, 36, AU_D5, 36, AU_B4, 36, AU_A4, 36
        .db     AU_A4, 36, AU_D5, 36, AU_FS4, 72, 0, 0
tn_title_bass:
        .db     AU_D3, 36, AU_A2, 36, AU_G2, 36, AU_A2, 36
        .db     AU_D3, 36, AU_G2, 36, AU_D2, 72, 0, 0

; Quota met: rising D major arpeggio over a held tonic (54 frames).
tn_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     tn_win_melody, tn_win_harmony, tn_win_bass
tn_win_melody:
        .db     AU_D5, 8, AU_FS5, 8, AU_A5, 8, AU_D6, 30, 0, 0
tn_win_harmony:
        .db     AU_A4, 8, AU_D5, 8, AU_FS5, 8, AU_A5, 30, 0, 0
tn_win_bass:
        .db     AU_D3, 24, AU_D2, 30, 0, 0
tn_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     tn_lose_melody, tn_lose_harmony, tn_lose_bass
tn_lose_melody:
        .db     AU_A4, 12, AU_G4, 12, AU_F4, 12, AU_E4, 30, 0, 0
tn_lose_harmony:
        .db     AU_F4, 12, AU_E4, 12, AU_D4, 12, AU_CS4, 30, 0, 0
tn_lose_bass:
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
