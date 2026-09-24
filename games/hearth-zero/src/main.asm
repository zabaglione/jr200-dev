; SPDX-License-Identifier: MIT
; HEARTH ZERO for JR-200: a port of jr100dev games/hearth_zero/rules.py 2.1.0.
; Jobs, resource caps, insulation, the three twelve-night cold waves, the
; order of the day and both loss causes follow the upstream source.
        .filename.jr "HEARTH-ZERO"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4680
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    3
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    21
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state: food, wood, heat, insulation, choice, notice, phase, day,
; fire_frame, effect, effect_kind, effect_x, effect_y.
HZ_FOOD:            .equ    GAME_STATE
HZ_WOOD:            .equ    GAME_STATE + 1
HZ_HEAT:            .equ    GAME_STATE + 2
HZ_WALL:            .equ    GAME_STATE + 3
HZ_CHOICE:          .equ    GAME_STATE + 4
HZ_NOTICE:          .equ    GAME_STATE + 5
HZ_PHASE:           .equ    GAME_STATE + 6
HZ_DAY:             .equ    GAME_STATE + 7
HZ_FIRE:            .equ    GAME_STATE + 8
HZ_EFFECT:          .equ    GAME_STATE + 9
HZ_EKIND:           .equ    GAME_STATE + 10
HZ_EX:              .equ    GAME_STATE + 11
HZ_EY:              .equ    GAME_STATE + 12
; Rule work bytes.
HZ_COST:            .equ    GAME_STATE + 16
HZ_FRAME:           .equ    GAME_STATE + 17
HZ_X0:              .equ    GAME_STATE + 18
HZ_T:               .equ    GAME_STATE + 19
; Drawing work bytes.
HZ_DI:              .equ    GAME_STATE + 32
HZ_DX:              .equ    GAME_STATE + 33
HZ_DY:              .equ    GAME_STATE + 34
HZ_DN:              .equ    GAME_STATE + 35

HZ_DAYS:            .equ    12
HZ_TILE_WOOD:       .equ    0x80
HZ_TILE_FIRE:       .equ    0x88
HZ_ATTR_TEXT:       .equ    0x07
HZ_ATTR_LABEL:      .equ    0x04
HZ_ATTR_TITLE:      .equ    0x06
HZ_ATTR_COLD:       .equ    0x05
HZ_ATTR_WARN:       .equ    0x02
HZ_ATTR_FLAME:      .equ    0x46
HZ_ATTR_EMBER:      .equ    0x42

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_font_install
        LDX     hz_patterns
        LDAA    HZ_TILE_WOOD
        LDAB    16
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        LDAA    10
        STAA    [HZ_FOOD]
        LDAA    8
        STAA    [HZ_WOOD]
        LDAA    12
        STAA    [HZ_HEAT]
game_tick:
        RTS

game_act:
        CMPA    JR_KEY_CONFIRM
        BEQ     hz_job
        CMPA    JR_KEY_UP
        BEQ     hz_prev
        CMPA    JR_KEY_LEFT
        BEQ     hz_prev
        LDAA    [HZ_CHOICE]
        INCA
        BRA     hz_choose
hz_prev:
        LDAA    [HZ_CHOICE]
        ADDA    3
hz_choose:
        ANDA    3
        STAA    [HZ_CHOICE]
        RTS

hz_job:
        CLR     [HZ_NOTICE]
        LDAA    [HZ_CHOICE]
        CMPA    2
        BNE     hz_job_wall
        LDAA    [HZ_WOOD]
        CMPA    3
        BCC     hz_job_ok
        LDAA    1
        BRA     hz_job_refuse
hz_job_wall:
        CMPA    3
        BNE     hz_job_ok
        LDAA    [HZ_WOOD]
        CMPA    4
        BCS     hz_job_wall_refuse
        LDAA    [HZ_WALL]
        CMPA    2
        BCS     hz_job_ok
hz_job_wall_refuse:
        LDAA    2
hz_job_refuse:
        STAA    [HZ_NOTICE]
        LDAA    3
        JMP     jr_port_sound

hz_job_ok:
        LDAA    1
        STAA    [HZ_PHASE]
        CLRA
        JSR     jr_port_sound
        JSR     hz_flight
        LDAA    [HZ_CHOICE]
        BNE     hz_job_food
        LDAA    [HZ_WOOD]
        ADDA    7
        CMPA    30
        BLS     hz_job_wood_store
        LDAA    30
hz_job_wood_store:
        STAA    [HZ_WOOD]
        BRA     hz_job_done
hz_job_food:
        CMPA    1
        BNE     hz_job_fire
        LDAA    [HZ_FOOD]
        ADDA    7
        CMPA    30
        BLS     hz_job_food_store
        LDAA    30
hz_job_food_store:
        STAA    [HZ_FOOD]
        BRA     hz_job_done
hz_job_fire:
        CMPA    2
        BNE     hz_job_build
        LDAA    [HZ_WOOD]
        SUBA    3
        STAA    [HZ_WOOD]
        LDAA    [HZ_HEAT]
        ADDA    9
        CMPA    24
        BLS     hz_job_heat_store
        LDAA    24
hz_job_heat_store:
        STAA    [HZ_HEAT]
        BRA     hz_job_done
hz_job_build:
        LDAA    [HZ_WOOD]
        SUBA    4
        STAA    [HZ_WOOD]
        INC     [HZ_WALL]
hz_job_done:
        LDAA    1
        JSR     jr_port_sound
        LDAA    18
        JSR     jr_port_animate
        ; night: cost = weather[level * 12 + day] - insulation
        LDAA    2
        STAA    [HZ_PHASE]
        CLRA
        JSR     hz_weather
        SUBA    [HZ_WALL]
        STAA    [HZ_COST]
        CLR     [HZ_FRAME]
hz_night_frame:
        LDAA    [HZ_FRAME]
        ANDA    1
        STAA    [HZ_FIRE]
        LDAA    5
        JSR     jr_port_animate
        INC     [HZ_FRAME]
        LDAA    [HZ_FRAME]
        CMPA    3
        BNE     hz_night_frame
        LDAA    [HZ_FOOD]
        CMPA    2
        BCC     hz_night_eat
        LDX     hz_txt_no_food
        JMP     jr_port_lose
hz_night_eat:
        SUBA    2
        STAA    [HZ_FOOD]
        CLRA
        JSR     jr_port_sound
        LDAA    12
        JSR     jr_port_animate
        LDAA    [HZ_HEAT]
        CMPA    [HZ_COST]
        BHI     hz_night_warm
        CLR     [HZ_HEAT]
        LDX     hz_txt_no_heat
        JMP     jr_port_lose
hz_night_warm:
        SUBA    [HZ_COST]
        STAA    [HZ_HEAT]
        CLRA
        JSR     jr_port_sound
        LDAA    12
        JSR     jr_port_animate
        INC     [HZ_DAY]
        CLR     [HZ_PHASE]
        LDAA    [HZ_DAY]
        CMPA    HZ_DAYS
        BNE     hz_act_done
        JMP     jr_port_win
hz_act_done:
        RTS

; A = offset -> A = weather[level * 12 + day + offset].
hz_weather:
        STAA    [HZ_T]
        LDAA    [JR_PORT_LEVEL]
        LDAB    HZ_DAYS
        JSR     jr_mul8
        ADDA    [HZ_DAY]
        ADDA    [HZ_T]
        LDX     hz_weather_table
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

; flight(2 + choice * 8, 19, 5, 12, kind) over five frames of animate(3).
hz_flight:
        LDAA    1
        STAA    [HZ_EFFECT]
        LDX     hz_flight_kinds
        LDAA    [HZ_CHOICE]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [HZ_EKIND]
        LDAA    [HZ_CHOICE]
        ASLA
        ASLA
        ASLA
        ADDA    2
        STAA    [HZ_X0]
        CLR     [HZ_FRAME]
hz_flight_frame:
        LDAA    [HZ_X0]
        CMPA    5
        BHI     hz_flight_left
        ; x + (5 - x) * frame // 4
        LDAA    5
        SUBA    [HZ_X0]
        LDAB    [HZ_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        ADDA    [HZ_X0]
        BRA     hz_flight_x
hz_flight_left:
        ; x - (x - 5) * frame // 4
        SUBA    5
        LDAB    [HZ_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        STAA    [HZ_T]
        LDAA    [HZ_X0]
        SUBA    [HZ_T]
hz_flight_x:
        STAA    [HZ_EX]
        ; 19 - (19 - 12) * frame // 4
        LDAA    7
        LDAB    [HZ_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        STAA    [HZ_T]
        LDAA    19
        SUBA    [HZ_T]
        STAA    [HZ_EY]
        LDAA    3
        JSR     jr_port_animate
        INC     [HZ_FRAME]
        LDAA    [HZ_FRAME]
        CMPA    5
        BNE     hz_flight_frame
        CLR     [HZ_EFFECT]
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    HZ_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     hz_hud
        JSR     jr_gfx_lines
        LDAA    HZ_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    28
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; face(3, 1 + fire_frame): the hearth picture in codes 0x00-0x0F
        LDX     hz_hearth
        TST     [HZ_FIRE]
        BEQ     hz_draw_hearth_frame
        LDX     hz_hearth + 128
hz_draw_hearth_frame:
        CLRA
        LDAB    16
        JSR     jr_pcg_load
        CLR     [HZ_DN]
        LDAA    3
        STAA    [HZ_DY]
hz_draw_hearth_row:
        LDAA    HZ_ATTR_FLAME
        LDAB    [HZ_DY]
        CMPB    5
        BCS     hz_draw_hearth_color
        LDAA    HZ_ATTR_EMBER
hz_draw_hearth_color:
        STAA    [JR_RT_COLOR]
        LDAA    4
        JSR     jr_gfx_at
        LDAB    4
hz_draw_hearth_cell:
        LDAA    [HZ_DN]
        JSR     jr_gfx_putc
        INC     [HZ_DN]
        DECB
        BNE     hz_draw_hearth_cell
        INC     [HZ_DY]
        LDAA    [HZ_DY]
        CMPA    7
        BNE     hz_draw_hearth_row
        ; heat blocks: tile(3 + i % 4 * 2, 16 - i // 4 * 2, 3) for heat // 2
        LDAA    HZ_ATTR_FLAME
        STAA    [JR_RT_COLOR]
        CLR     [HZ_DI]
hz_draw_heat:
        LDAA    [HZ_HEAT]
        LSRA
        CMPA    [HZ_DI]
        BLS     hz_draw_stats
        LDAA    [HZ_DI]
        ANDA    3
        ASLA
        ADDA    3
        LDAB    [HZ_DI]
        LSRB
        LSRB
        ASLB
        NEGB
        ADDB    16
        JSR     jr_gfx_at
        LDAA    HZ_TILE_FIRE
        JSR     jr_gfx_tile
        INC     [HZ_DI]
        BRA     hz_draw_heat
hz_draw_stats:
        LDAA    HZ_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    26
        LDAB    4
        JSR     jr_gfx_at
        LDAA    [HZ_FOOD]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [HZ_WOOD]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    10
        JSR     jr_gfx_at
        LDAA    [HZ_HEAT]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    13
        JSR     jr_gfx_at
        LDAA    [HZ_WALL]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    18
        JSR     jr_gfx_at
        LDAA    [HZ_DAY]
        JSR     jr_gfx_dec2
        ; forecast: tonight and the next two nights while day + i < 12
        LDAA    HZ_ATTR_COLD
        STAA    [JR_RT_COLOR]
        CLR     [HZ_DI]
hz_draw_forecast:
        LDAA    [HZ_DAY]
        ADDA    [HZ_DI]
        CMPA    HZ_DAYS
        BCC     hz_draw_cursor
        LDAA    [HZ_DI]
        ASLA
        ASLA
        ADDA    18
        LDAB    16
        JSR     jr_gfx_at
        LDAA    [HZ_DI]
        JSR     hz_weather_draw
        ADDA    0x30
        JSR     jr_gfx_putc
        INC     [HZ_DI]
        LDAA    [HZ_DI]
        CMPA    3
        BNE     hz_draw_forecast
hz_draw_cursor:
        LDAA    HZ_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    [HZ_CHOICE]
        ASLA
        ASLA
        ASLA
        INCA
        LDAB    20
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        ; notice / phase line
        LDX     hz_txt_fire_wood
        LDAA    HZ_ATTR_WARN
        LDAB    [HZ_NOTICE]
        CMPB    1
        BEQ     hz_draw_note
        LDX     hz_txt_wall_wood
        CMPB    2
        BEQ     hz_draw_note
        LDAB    [HZ_PHASE]
        LDX     hz_txt_work
        LDAA    HZ_ATTR_LABEL
        CMPB    1
        BEQ     hz_draw_note
        CMPB    2
        BNE     hz_draw_effect
        LDX     hz_txt_night
        LDAA    HZ_ATTR_COLD
hz_draw_note:
        STAA    [JR_RT_COLOR]
        STX     [JR_RT_TABLE]
        LDAA    1
        LDAB    21
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        JSR     jr_gfx_text
        LDAA    [HZ_PHASE]
        CMPA    2
        BNE     hz_draw_effect
        ; snow: '*' at (3 + x * 2, 6 + (x + fire_frame) % 3)
        LDAA    HZ_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        CLR     [HZ_DI]
hz_draw_snow:
        LDAA    [HZ_DI]
        ADDA    [HZ_FIRE]
        CMPA    3
        BCS     hz_draw_snow_row
        SUBA    3
hz_draw_snow_row:
        ADDA    6
        TAB
        LDAA    [HZ_DI]
        ASLA
        ADDA    3
        JSR     jr_gfx_at
        LDAA    0x2a
        JSR     jr_gfx_putc
        INC     [HZ_DI]
        LDAA    [HZ_DI]
        CMPA    5
        BNE     hz_draw_snow
hz_draw_effect:
        TST     [HZ_EFFECT]
        BEQ     hz_draw_done
        LDX     hz_kind_tiles
        LDAA    [HZ_EKIND]
        ASLA
        JSR     jr_add_x_a
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAA    [X]
        STAA    [HZ_DN]
        LDAA    [HZ_EX]
        LDAB    [HZ_EY]
        JSR     jr_gfx_at
        LDAA    [HZ_DN]
        JMP     jr_gfx_tile
hz_draw_done:
        RTS

; Drawing copy of hz_weather (does not touch rule bytes).
hz_weather_draw:
        STAA    [HZ_DN]
        LDAA    [JR_PORT_LEVEL]
        LDAB    HZ_DAYS
        JSR     jr_mul8
        ADDA    [HZ_DAY]
        ADDA    [HZ_DN]
        LDX     hz_weather_table
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

game_draw_title:
        LDAA    0x20
        LDAB    HZ_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     hz_hearth
        CLRA
        LDAB    16
        JSR     jr_pcg_load
        CLR     [HZ_DN]
        LDAA    3
        STAA    [HZ_DY]
hz_title_row:
        LDAA    HZ_ATTR_FLAME
        LDAB    [HZ_DY]
        CMPB    5
        BCS     hz_title_color
        LDAA    HZ_ATTR_EMBER
hz_title_color:
        STAA    [JR_RT_COLOR]
        LDAA    14
        JSR     jr_gfx_at
        LDAB    4
hz_title_cell:
        LDAA    [HZ_DN]
        JSR     jr_gfx_putc
        INC     [HZ_DN]
        DECB
        BNE     hz_title_cell
        INC     [HZ_DY]
        LDAA    [HZ_DY]
        CMPA    7
        BNE     hz_title_row
        LDX     hz_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    HZ_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     hz_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; game.json dataTables.weather (three waves x twelve nights).
hz_weather_table:
        .db     4, 5, 6, 4, 7, 5, 4, 6, 5, 7, 4, 6
        .db     5, 4, 7, 5, 6, 4, 7, 4, 6, 5, 7, 5
        .db     4, 6, 5, 7, 4, 6, 5, 7, 6, 4, 7, 6
; Upstream flight kinds for wood, food, fire, wall.
hz_flight_kinds:
        .db     4, 1, 3, 6
; kind -> tile, attribute (kinds 1, 3, 4 and 6 are used).
hz_kind_tiles:
        .db     0x80, 0x42, 0x84, 0x44, 0x80, 0x42, 0x88, 0x46
        .db     0x80, 0x42, 0x80, 0x42, 0x8c, 0x47

hz_hud:
        .db     1, 0, HZ_ATTR_TITLE
        .dw     hz_txt_name
        .db     23, 0, HZ_ATTR_LABEL
        .dw     hz_txt_wave
        .db     2, 2, HZ_ATTR_LABEL
        .dw     hz_txt_last
        .db     14, 4, 0x04
        .dw     hz_txt_food
        .db     14, 7, 0x02
        .dw     hz_txt_wood
        .db     14, 10, 0x06
        .dw     hz_txt_heat
        .db     14, 13, 0x07
        .dw     hz_txt_wall
        .db     14, 15, HZ_ATTR_COLD
        .dw     hz_txt_cold
        .db     19, 18, HZ_ATTR_LABEL
        .dw     hz_txt_day
        .db     0, 19, HZ_ATTR_TEXT
        .dw     hz_txt_jobs
        .db     0xff
hz_title_lines:
        .db     10, 9, HZ_ATTR_TITLE
        .dw     hz_txt_name
        .db     5, 11, HZ_ATTR_COLD
        .dw     hz_txt_tagline
        .db     8, 15, HZ_ATTR_TEXT
        .dw     hz_txt_start
        .db     5, 17, HZ_ATTR_TEXT
        .dw     hz_txt_howto
        .db     4, 22, 0x01
        .dw     hz_txt_credit
        .db     0xff
hz_help_lines:
        .db     10, 2, HZ_ATTR_TITLE
        .dw     hz_txt_name
        .db     2, 5, HZ_ATTR_TEXT
        .dw     hz_help_1
        .db     2, 7, HZ_ATTR_TEXT
        .dw     hz_help_2
        .db     2, 9, HZ_ATTR_TEXT
        .dw     hz_help_3
        .db     2, 11, HZ_ATTR_TEXT
        .dw     hz_help_4
        .db     2, 13, HZ_ATTR_TEXT
        .dw     hz_help_5
        .db     2, 15, HZ_ATTR_TEXT
        .dw     hz_help_6
        .db     2, 17, HZ_ATTR_TEXT
        .dw     hz_help_7
        .db     2, 20, HZ_ATTR_LABEL
        .dw     hz_help_back
        .db     0xff

hz_txt_name:
        .db     "HEARTH ZERO", 0
hz_txt_wave:
        .db     "WAVE", 0
hz_txt_last:
        .db     "THE LAST HEARTH", 0
hz_txt_food:
        .db     "FOOD", 0
hz_txt_wood:
        .db     "WOOD", 0
hz_txt_heat:
        .db     "HEAT", 0
hz_txt_wall:
        .db     "WALL", 0
hz_txt_cold:
        .db     "COLD NOW/NEXT", 0
hz_txt_day:
        .db     "DAY", 0
hz_txt_jobs:
        .db     "WOOD    FOOD    FIRE    WALL", 0
hz_txt_fire_wood:
        .db     "FIRE NEEDS THREE WOOD", 0
hz_txt_wall_wood:
        .db     "WALL: FOUR WOOD, MAX TWO", 0
hz_txt_work:
        .db     "WORK COMPLETE", 0
hz_txt_night:
        .db     "NIGHTFALL", 0
hz_txt_no_food:
        .db     "NO FOOD LEFT FOR THE NIGHT", 0
hz_txt_no_heat:
        .db     "THE NIGHT EXTINGUISHED THE HEARTH", 0
hz_txt_tagline:
        .db     "SURVIVE TWELVE NIGHTS", 0
hz_txt_start:
        .db     "RETURN : START", 0
hz_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
hz_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
hz_help_1:
        .db     "WASD : SELECT A DAILY JOB", 0
hz_help_2:
        .db     "RETURN : SPEND ONE DAY", 0
hz_help_3:
        .db     "WOOD +7 / FOOD +7 / EAT 2", 0
hz_help_4:
        .db     "FIRE: 3 WOOD GIVES 9 HEAT", 0
hz_help_5:
        .db     "WALL: 4 WOOD SAVES 1 HEAT", 0
hz_help_6:
        .db     "READ COLD, SURVIVE 12 NIGHTS.", 0
hz_help_7:
        .db     "SPACE RESTART / ESC TO BASIC", 0
hz_help_back:
        .db     "ANY KEY : TITLE", 0

game_sfx_table:
        .dw     hz_sfx_tick, hz_sfx_work, hz_sfx_win, hz_sfx_lose
hz_sfx_tick:
        .db     90, 2, 0, 0
hz_sfx_work:
        .db     130, 3, 100, 4, 0, 0
hz_sfx_win:
        .db     120, 6, 95, 6, 80, 6, 60, 14, 0, 0
hz_sfx_lose:
        .db     120, 8, 160, 8, 220, 18, 0, 0

        .include "art.inc"
        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys.inc"
        .include "../../../sdk/gfx.inc"
        .include "../../../sdk/font.inc"
        .include "../../../sdk/pcg.inc"
        .include "../../../sdk/frame.inc"
        .include "../../../sdk/math.inc"
        .include "../../../sdk/sound.inc"
        .include "../../../sdk/sfx.inc"
        .include "../../../sdk/port.inc"
        .include "../../../sdk/font_data.inc"
