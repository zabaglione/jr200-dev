; SPDX-License-Identifier: MIT
; CARGO BALANCE for JR-200: a port of jr100dev games/cargo_balance/rules.py 2.0.0.
; The crate sequences, torque, wind, tolerance and fares follow the upstream
; source; display, colour and three-voice sound use the JR-200 port SDK.
        .filename.jr "CARGO-BALANCE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    6
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py).
CB_WEIGHT:          .equ    GAME_STATE
CB_WIND:            .equ    GAME_STATE + 1
CB_TOL:             .equ    GAME_STATE + 2
CB_CURSOR:          .equ    GAME_STATE + 3
CB_LEFT:            .equ    GAME_STATE + 4
CB_RIGHT:           .equ    GAME_STATE + 5
CB_LOADS:           .equ    GAME_STATE + 6
CB_FARE:            .equ    GAME_STATE + 7
CB_NOTICE:          .equ    GAME_STATE + 8
CB_B:               .equ    GAME_STATE + 9      ; b[16] crate weights by hold
CB_C:               .equ    GAME_STATE + 25     ; c[4] crates per hold
CB_TILT:            .equ    GAME_STATE + 29
; Flight effect and rule work bytes.
CB_EFFECT:          .equ    GAME_STATE + 32
CB_EX:              .equ    GAME_STATE + 33
CB_EY:              .equ    GAME_STATE + 34
CB_FY:              .equ    GAME_STATE + 35
CB_TY:              .equ    GAME_STATE + 36
CB_FRAME:           .equ    GAME_STATE + 37
CB_IA:              .equ    GAME_STATE + 38
CB_T:               .equ    GAME_STATE + 39
CB_EW:              .equ    GAME_STATE + 40
; Drawing work bytes.
CB_DI:              .equ    GAME_STATE + 48
CB_DJ:              .equ    GAME_STATE + 49
CB_DY:              .equ    GAME_STATE + 50
CB_DW:              .equ    GAME_STATE + 51
CB_DPORT:           .equ    GAME_STATE + 52
CB_DDELTA:          .equ    GAME_STATE + 53

CB_TILE_CRATE:      .equ    0x80
CB_TILE_HOOK:       .equ    0x84
CB_ATTR_HOOK:       .equ    0x46
CB_ATTR_CRANE:      .equ    0x06
CB_ATTR_TEXT:       .equ    0x07
CB_ATTR_LABEL:      .equ    0x04
CB_ATTR_TITLE:      .equ    0x06
CB_ATTR_DIM:        .equ    0x05
CB_ATTR_PORT:       .equ    0x02        ; port side: red
CB_ATTR_STARBOARD:  .equ    0x04        ; starboard side: green
CB_ATTR_MID:        .equ    0x07
CB_ATTR_BAD:        .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     cb_patterns
        LDAA    CB_TILE_CRATE
        LDAB    8
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        CLRA
        JSR     cb_cargo
        STAA    [CB_WEIGHT]
        LDAA    [JR_PORT_LEVEL]
        LDAB    3
        JSR     jr_divmod8
        STAB    [CB_WIND]
        LDAA    [JR_PORT_LEVEL]
        LSRA
        NEGA
        ADDA    10
        STAA    [CB_TOL]
        RTS

; A = index within the voyage -> A = cargo[level * 12 + index].
cb_cargo:
        STAA    [CB_T]
        LDAA    [JR_PORT_LEVEL]
        LDAB    12
        JSR     jr_mul8
        ADDA    [CB_T]
        LDX     cb_cargo_table
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_LEFT
        BNE     cb_act_right
        LDAA    [CB_CURSOR]
        ADDA    3
        BRA     cb_act_cursor
cb_act_right:
        CMPA    JR_KEY_RIGHT
        BNE     cb_act_drop
        LDAA    [CB_CURSOR]
        INCA
cb_act_cursor:
        ANDA    3
        STAA    [CB_CURSOR]
        RTS
cb_act_drop:
        CMPA    JR_KEY_CONFIRM
        BEQ     cb_drop
        RTS

cb_drop:
        LDAA    [CB_CURSOR]
        LDX     CB_C
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    4
        BCS     cb_drop_go
        LDAA    1
        STAA    [CB_NOTICE]
        LDX     cb_sfx_full
        JMP     jr_sfx_play
cb_drop_go:
        CLR     [CB_NOTICE]
        CLRA
        JSR     jr_port_sound
        ; the crate falls from row 3 to its place on the deck
        LDAA    [CB_WEIGHT]
        STAA    [CB_EW]
        LDAA    3
        STAA    [CB_FY]
        LDAA    [CB_CURSOR]
        JSR     cb_deck_height
        SUBA    2
        STAA    [CB_TY]
        LDAA    [CB_CURSOR]
        LDX     CB_C
        JSR     jr_add_x_a
        LDAA    [X]
        ASLA
        NEGA
        ADDA    [CB_TY]
        STAA    [CB_TY]
        LDAA    [CB_CURSOR]
        JSR     cb_column_x
        STAA    [CB_EX]
        LDAA    1
        STAA    [CB_EFFECT]
        CLR     [CB_FRAME]
cb_fall_frame:
        LDAA    [CB_FY]
        LDAB    [CB_TY]
        JSR     cb_interp
        STAA    [CB_EY]
        LDAA    3
        JSR     jr_port_animate
        INC     [CB_FRAME]
        LDAA    [CB_FRAME]
        CMPA    5
        BNE     cb_fall_frame
        CLR     [CB_EFFECT]
        ; b[hold * 4 + c[hold]] = weight; c[hold] += 1
        LDAA    [CB_CURSOR]
        LDX     CB_C
        JSR     jr_add_x_a
        LDAB    [X]
        INC     [X]
        LDAA    [CB_CURSOR]
        ASLA
        ASLA
        ABA
        LDX     CB_B
        JSR     jr_add_x_a
        LDAA    [CB_WEIGHT]
        STAA    [X]
        ; torque: three times in the outer holds
        LDAB    [CB_CURSOR]
        BEQ     cb_drop_outer
        CMPB    3
        BNE     cb_drop_side
cb_drop_outer:
        ASLA
        ADDA    [CB_WEIGHT]
cb_drop_side:
        LDAB    [CB_CURSOR]
        CMPB    2
        BCC     cb_drop_right
        ADDA    [CB_LEFT]
        STAA    [CB_LEFT]
        BRA     cb_drop_fare
cb_drop_right:
        ADDA    [CB_RIGHT]
        STAA    [CB_RIGHT]
cb_drop_fare:
        INC     [CB_LOADS]
        LDAA    [CB_WEIGHT]
        LDAB    [CB_CURSOR]
        BEQ     cb_drop_double
        CMPB    3
        BNE     cb_drop_pay
cb_drop_double:
        ASLA
cb_drop_pay:
        ADDA    [CB_FARE]
        STAA    [CB_FARE]
        LDAA    1
        JSR     jr_port_sound
        ; the ship rolls: frames with tilt 0, 1, 0
        CLR     [CB_FRAME]
cb_roll_frame:
        CLR     [CB_TILT]
        LDAA    [CB_FRAME]
        CMPA    1
        BNE     cb_roll_wait
        INC     [CB_TILT]
cb_roll_wait:
        LDAA    6
        JSR     jr_port_animate
        INC     [CB_FRAME]
        LDAA    [CB_FRAME]
        CMPA    3
        BNE     cb_roll_frame
        CLR     [CB_TILT]
        ; tipped when left + wind > right + tol or right > left + wind + tol
        LDAA    [CB_LEFT]
        ADDA    [CB_WIND]
        LDAB    [CB_RIGHT]
        ADDB    [CB_TOL]
        CBA
        BHI     cb_tipped
        LDAA    [CB_LEFT]
        ADDA    [CB_WIND]
        ADDA    [CB_TOL]
        LDAB    [CB_RIGHT]
        CBA
        BCS     cb_tipped
        LDAA    [CB_LOADS]
        CMPA    12
        BNE     cb_next_crate
        JMP     jr_port_win
cb_tipped:
        LDX     cb_txt_lose
        JSR     jr_port_lose
cb_next_crate:
        LDAA    [CB_LOADS]
        CMPA    12
        BCC     cb_drop_done
        JSR     cb_cargo
        STAA    [CB_WEIGHT]
cb_drop_done:
        RTS

; A = from, B = to -> A = from + (to - from) * frame // 4 (upstream flight()).
cb_interp:
        STAA    [CB_IA]
        CBA
        BHI     cb_interp_back
        SUBB    [CB_IA]
        TBA
        LDAB    [CB_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        ADDA    [CB_IA]
        RTS
cb_interp_back:
        SBA
        LDAB    [CB_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        NEGA
        ADDA    [CB_IA]
        RTS

; A = hold -> A = 3 + hold * 6.
cb_column_x:
        TAB
        ASLA
        ABA
        ASLA
        ADDA    3
        RTS

; A = hold -> A = deck row (16-18): the side with more weight sinks.
cb_deck_height:
        PSHA
        LDAA    [CB_LEFT]
        ADDA    [CB_WIND]
        STAA    [CB_T]
        SUBA    [CB_RIGHT]
        BCC     cb_deck_delta
        NEGA
cb_deck_delta:
        PULB
        CMPA    1
        BLS     cb_deck_level
        TST     [CB_TILT]
        BNE     cb_deck_level
        CMPB    1
        BEQ     cb_deck_level
        CMPB    2
        BEQ     cb_deck_level
        ; column 0: 18 if port > right else 16; column 3 the other way
        LDAA    [CB_T]
        CMPA    [CB_RIGHT]
        BHI     cb_deck_port_low
        LDAA    16
        CMPB    0
        BEQ     cb_deck_done
        LDAA    18
        RTS
cb_deck_port_low:
        LDAA    18
        CMPB    0
        BEQ     cb_deck_done
        LDAA    16
        RTS
cb_deck_level:
        LDAA    17
cb_deck_done:
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    CB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cb_hud
        JSR     jr_gfx_lines
        LDAA    CB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; the deck: port third red, middle white, starboard third green
        CLR     [CB_DI]
cb_draw_deck:
        LDAA    [CB_DI]
        CLRB
        LDX     cb_zone_port
        CMPA    10
        BCS     cb_draw_deck_zone
        LDAB    1
        LDX     cb_zone_mid
        CMPA    20
        BCS     cb_draw_deck_zone
        LDAB    3
        LDX     cb_zone_star
cb_draw_deck_zone:
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        TBA
        JSR     cb_deck_height
        TAB
        LDAA    [CB_DI]
        INCA
        JSR     jr_gfx_at
        LDAA    0x5f
        JSR     jr_gfx_putc
        INC     [CB_DI]
        LDAA    [CB_DI]
        CMPA    30
        BNE     cb_draw_deck
        ; crates in each hold, coloured by weight
        CLR     [CB_DI]
cb_draw_hold:
        LDAA    [CB_DI]
        JSR     cb_deck_height
        SUBA    2
        STAA    [CB_DY]
        CLR     [CB_DJ]
cb_draw_crate:
        LDAA    [CB_DI]
        LDX     CB_C
        JSR     jr_add_x_a
        LDAA    [CB_DJ]
        CMPA    [X]
        BCC     cb_draw_hold_next
        LDAA    [CB_DI]
        ASLA
        ASLA
        ADDA    [CB_DJ]
        LDX     CB_B
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [CB_DW]
        JSR     cb_draw_one
        DEC     [CB_DY]
        DEC     [CB_DY]
        INC     [CB_DJ]
        BRA     cb_draw_crate
cb_draw_hold_next:
        INC     [CB_DI]
        LDAA    [CB_DI]
        CMPA    4
        BNE     cb_draw_hold
        ; the falling crate
        TST     [CB_EFFECT]
        BEQ     cb_draw_crane
        LDAA    [CB_EW]
        STAA    [CB_DW]
        LDAA    [CB_EY]
        STAA    [CB_DY]
        LDAA    [CB_EX]
        JSR     cb_draw_at
cb_draw_crane:
        LDAA    CB_ATTR_CRANE
        STAA    [JR_RT_COLOR]
        LDAA    [CB_CURSOR]
        JSR     cb_column_x
        LDAB    7
        JSR     jr_gfx_at
        LDAA    0x56
        JSR     jr_gfx_putc
        TST     [CB_NOTICE]
        BEQ     cb_draw_numbers
        LDAA    CB_ATTR_BAD
        STAA    [JR_RT_COLOR]
        LDAA    10
        LDAB    7
        JSR     jr_gfx_at
        LDX     cb_txt_full
        JSR     jr_gfx_text
cb_draw_numbers:
        LDAA    CB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDX     cb_numbers
        STX     [JR_RT_TABLE]
cb_draw_number:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     cb_draw_next_crates
        LDAB    [X + 1]
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        LDX     [X + 2]
        LDAA    [X]
        JSR     jr_gfx_dec2
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     cb_draw_number
cb_draw_next_crates:
        ; NEXT: cargo[min(11, loads + 1)] and cargo[min(11, loads + 2)]
        LDAA    12
        LDAB    6
        JSR     jr_gfx_at
        LDAA    [CB_LOADS]
        INCA
        JSR     cb_draw_next_digit
        LDAA    14
        LDAB    6
        JSR     jr_gfx_at
        LDAA    [CB_LOADS]
        INCA
        INCA
        JSR     cb_draw_next_digit
        LDAA    CB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    18
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [CB_WIND]
        ADDA    0x30
        JSR     jr_gfx_putc
        ; balance bar: '^' left of 21 when port is heavier
        LDAA    [CB_LEFT]
        ADDA    [CB_WIND]
        STAA    [CB_DPORT]
        SUBA    [CB_RIGHT]
        BCC     cb_draw_delta
        NEGA
cb_draw_delta:
        CMPA    8
        BLS     cb_draw_delta_ok
        LDAA    8
cb_draw_delta_ok:
        STAA    [CB_DDELTA]
        LDAB    CB_ATTR_STARBOARD
        LDAA    [CB_DDELTA]
        CMPA    6
        BCS     cb_draw_mark_colour
        LDAB    CB_ATTR_BAD
cb_draw_mark_colour:
        STAB    [JR_RT_COLOR]
        LDAA    [CB_DPORT]
        CMPA    [CB_RIGHT]
        BHI     cb_draw_mark_port
        LDAA    21
        ADDA    [CB_DDELTA]
        BRA     cb_draw_mark
cb_draw_mark_port:
        LDAA    21
        SUBA    [CB_DDELTA]
cb_draw_mark:
        LDAB    21
        JSR     jr_gfx_at
        LDAA    0x5e
        JMP     jr_gfx_putc

; A = index -> the next crate's weight digit in its colour.
cb_draw_next_digit:
        CMPA    12
        BCS     cb_draw_next_have
        LDAA    11
cb_draw_next_have:
        JSR     cb_cargo
        PSHA
        JSR     cb_weight_attr
        PULA
        ADDA    0x30
        JMP     jr_gfx_putc

; CB_DW = weight -> JR_RT_COLOR = its text colour (1 green, 2 yellow, 3 red).
cb_weight_attr:
        LDX     cb_weight_colours - 1
        LDAA    [CB_DW]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        RTS

; Crate of weight CB_DW at hold CB_DI, row CB_DY.
cb_draw_one:
        LDAA    [CB_DI]
        JSR     cb_column_x
; A = x, CB_DY = y: crate tile with its weight digit on the top-left cell.
cb_draw_at:
        PSHA
        LDX     cb_weight_colours - 1
        LDAA    [CB_DW]
        JSR     jr_add_x_a
        LDAA    [X]
        ORAA    0x40
        STAA    [JR_RT_COLOR]
        PULA
        PSHA
        LDAB    [CB_DY]
        JSR     jr_gfx_at
        LDAA    CB_TILE_CRATE
        JSR     jr_gfx_tile
        JSR     cb_weight_attr
        PULA
        LDAB    [CB_DY]
        JSR     jr_gfx_at
        LDAA    [CB_DW]
        ADDA    0x30
        JMP     jr_gfx_putc

game_draw_title:
        LDX     cb_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    CB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    1
        STAA    [CB_DW]
        CLR     [CB_DI]
        LDAA    3
        STAA    [CB_DY]
        JSR     cb_draw_one
        LDAA    2
        STAA    [CB_DW]
        LDAA    1
        STAA    [CB_DI]
        JSR     cb_draw_one
        LDAA    3
        STAA    [CB_DW]
        LDAA    2
        STAA    [CB_DI]
        JSR     cb_draw_one
        LDAA    CB_ATTR_HOOK
        STAA    [JR_RT_COLOR]
        LDAA    21
        LDAB    3
        JSR     jr_gfx_at
        LDAA    CB_TILE_HOOK
        JSR     jr_gfx_tile
        LDX     cb_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    CB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     cb_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

cb_cargo_table:
        .db     1, 2, 3, 1, 3, 2, 2, 1, 3, 2, 1, 3, 2, 3, 1, 2, 1, 3, 3, 2, 1, 3, 2, 1
        .db     3, 1, 2, 3, 2, 1, 1, 3, 2, 1, 3, 2, 1, 3, 2, 2, 3, 1, 3, 1, 2, 2, 1, 3
        .db     2, 1, 3, 3, 1, 2, 1, 2, 3, 3, 2, 1, 3, 2, 1, 1, 2, 3, 2, 3, 1, 1, 3, 2
cb_weight_colours:
        .db     0x04, 0x06, 0x02
cb_zone_port:
        .db     CB_ATTR_PORT
cb_zone_mid:
        .db     CB_ATTR_MID
cb_zone_star:
        .db     CB_ATTR_STARBOARD

; x, y, value address for the two-digit numbers
cb_numbers:
        .db     12, 4
        .dw     CB_WEIGHT
        .db     26, 4
        .dw     CB_LOADS
        .db     7, 19
        .dw     CB_LEFT
        .db     26, 19
        .dw     CB_RIGHT
        .db     6, 2
        .dw     CB_FARE
        .db     27, 2
        .dw     CB_TOL
        .db     0xff

cb_hud:
        .db     1, 0, CB_ATTR_TITLE
        .dw     cb_txt_name
        .db     22, 0, CB_ATTR_LABEL
        .dw     cb_txt_voyage
        .db     1, 2, CB_ATTR_LABEL
        .dw     cb_txt_fare
        .db     13, 2, CB_ATTR_LABEL
        .dw     cb_txt_wind
        .db     21, 2, CB_ATTR_LABEL
        .dw     cb_txt_limit
        .db     1, 4, CB_ATTR_LABEL
        .dw     cb_txt_load
        .db     19, 4, CB_ATTR_LABEL
        .dw     cb_txt_loaded
        .db     7, 6, CB_ATTR_LABEL
        .dw     cb_txt_next
        .db     2, 19, CB_ATTR_PORT
        .dw     cb_txt_port
        .db     15, 19, CB_ATTR_STARBOARD
        .dw     cb_txt_starboard
        .db     2, 21, CB_ATTR_LABEL
        .dw     cb_txt_balance
        .db     0xff
cb_title_lines:
        .db     9, 8, CB_ATTR_TITLE
        .dw     cb_txt_name
        .db     4, 10, CB_ATTR_LABEL
        .dw     cb_txt_tagline
        .db     8, 15, CB_ATTR_TEXT
        .dw     cb_txt_start
        .db     5, 17, CB_ATTR_TEXT
        .dw     cb_txt_howto
        .db     4, 22, CB_ATTR_DIM
        .dw     cb_txt_credit
        .db     0xff
cb_help_lines:
        .db     9, 2, CB_ATTR_TITLE
        .dw     cb_txt_name
        .db     1, 5, CB_ATTR_TEXT
        .dw     cb_help_1
        .db     1, 7, CB_ATTR_TEXT
        .dw     cb_help_2
        .db     1, 9, CB_ATTR_TEXT
        .dw     cb_help_3
        .db     1, 11, CB_ATTR_TEXT
        .dw     cb_help_4
        .db     1, 13, CB_ATTR_TEXT
        .dw     cb_help_5
        .db     1, 15, CB_ATTR_TEXT
        .dw     cb_help_6
        .db     1, 17, CB_ATTR_TEXT
        .dw     cb_help_7
        .db     1, 19, CB_ATTR_TEXT
        .dw     cb_help_8
        .db     1, 21, CB_ATTR_LABEL
        .dw     cb_help_back
        .db     0xff

cb_txt_name:
        .db     "CARGO BALANCE", 0
cb_txt_voyage:
        .db     "VOYAGE", 0
cb_txt_fare:
        .db     "FARE", 0
cb_txt_wind:
        .db     "WIND", 0
cb_txt_limit:
        .db     "LIMIT", 0
cb_txt_load:
        .db     "NEXT LOAD", 0
cb_txt_loaded:
        .db     "LOADED", 0
cb_txt_next:
        .db     "NEXT", 0
cb_txt_port:
        .db     "PORT", 0
cb_txt_starboard:
        .db     "STARBOARD", 0
cb_txt_balance:
        .db     "BALANCE    [.................]", 0
cb_txt_full:
        .db     "HOLD FULL", 0
cb_txt_lose:
        .db     "THE LOAD TIPPED THE SHIP", 0
cb_txt_tagline:
        .db     "LOAD TWELVE WITHOUT TIPPING", 0
cb_txt_start:
        .db     "RETURN : START", 0
cb_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
cb_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
cb_help_1:
        .db     "A/D : CRANE  RETURN : DROP", 0
cb_help_2:
        .db     "OUTER HOLDS: DOUBLE FARE,", 0
cb_help_3:
        .db     "BUT THREE TIMES THE TORQUE.", 0
cb_help_4:
        .db     "NEXT TWO CRATES ARE SHOWN.", 0
cb_help_5:
        .db     "WIND ADDS TO THE PORT LEAN.", 0
cb_help_6:
        .db     "LOAD TWELVE WITHOUT TIPPING.", 0
cb_help_7:
        .db     "SIX VOYAGES, TIGHTER LIMITS.", 0
cb_help_8:
        .db     "SPACE : RESTART  CTRL+C : BASIC", 0
cb_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     cb_sfx_drop, cb_sfx_land, cb_jingle_win, cb_jingle_lose
cb_sfx_drop:
        .db     150, 2, 130, 2, 0, 0
cb_sfx_land:
        .db     220, 3, 0, 1, 180, 4, 0, 0
cb_sfx_full:
        .db     240, 6, 0, 2, 240, 6, 0, 0

; Title: a sea shanty in G major, quarter note = 20 frames, looping.
cb_title_song:
        .db     1
        .dw     cb_title_melody, cb_title_harmony, cb_title_bass
cb_title_melody:
        .db     AU_D5, 20, AU_G5, 20, AU_G5, 20, AU_B5, 20
        .db     AU_A5, 20, AU_G5, 20, AU_E5, 40
        .db     AU_D5, 20, AU_G5, 20, AU_B5, 20, AU_D6, 20
        .db     AU_C6, 20, AU_A5, 20, AU_G5, 40, 0, 0
cb_title_harmony:
        .db     AU_B4, 40, AU_D5, 40, AU_C5, 40, AU_C5, 40
        .db     AU_B4, 40, AU_D5, 40, AU_E5, 40, AU_B4, 40, 0, 0
cb_title_bass:
        .db     AU_G2, 20, AU_D3, 20, AU_G2, 20, AU_D3, 20
        .db     AU_C3, 20, AU_G2, 20, AU_C3, 20, AU_E3, 20
        .db     AU_G2, 20, AU_D3, 20, AU_G2, 20, AU_B2, 20
        .db     AU_D3, 20, AU_D3, 20, AU_G2, 40, 0, 0

; Set sail: rising G major arpeggio over a held tonic (54 frames).
cb_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     cb_win_melody, cb_win_harmony, cb_win_bass
cb_win_melody:
        .db     AU_G5, 8, AU_B5, 8, AU_D6, 8, AU_G6, 30, 0, 0
cb_win_harmony:
        .db     AU_D5, 8, AU_G5, 8, AU_B5, 8, AU_D6, 30, 0, 0
cb_win_bass:
        .db     AU_G3, 24, AU_G2, 30, 0, 0
cb_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     cb_lose_melody, cb_lose_harmony, cb_lose_bass
cb_lose_melody:
        .db     AU_D5, 12, AU_C5, 12, AU_AS4, 12, AU_A4, 30, 0, 0
cb_lose_harmony:
        .db     AU_AS4, 12, AU_A4, 12, AU_G4, 12, AU_FS4, 30, 0, 0
cb_lose_bass:
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
