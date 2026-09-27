; SPDX-License-Identifier: MIT
; METRO WEAVE for JR-200: a port of jr100dev games/metro_weave/rules.py 2.0.0.
; Three shifts of eight trains, the destination deck from the seeded
; generator, two points and their stops, automatic braking, platform
; unloading, express trains and their deadline, the chain bonus, hearts,
; the quota and the medals follow the upstream source, one upstream tick per
; game_tick. Upstream's entropy() is the position of the song playing when
; the shift starts (0 in the self test and the demo). Rules are checked by
; the in-program self test (sdk/selftest.inc, title key T); P plays the
; shift-1 demo.
        .filename.jr "METRO-WEAVE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x46a0
JR_AUDIO:           .equ    0x46c0
JR_TEST:            .equ    0x46e0
JR_TEST_OUT:        .equ    0x5000
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    3
; Upstream ticks every 10 frames; one tick here is GAME_RATE idle frames plus
; the render (see README).
GAME_RATE:          .equ    6
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_TEST_SIZE:     .equ    56
GAME_TEST_LIMIT:    .equ    2000
GAME_TEST_HELD:     .equ    MW_HELD

; Upstream state (tests/model.py LAYOUT), then work bytes.
MW_HP:              .equ    GAME_STATE
MW_ORIGIN:          .equ    GAME_STATE + 1
MW_SEED:            .equ    GAME_STATE + 2
MW_CAPACITY:        .equ    GAME_STATE + 3
MW_INTERVAL:        .equ    GAME_STATE + 4
MW_QUOTA:           .equ    GAME_STATE + 5
MW_ISSUED:          .equ    GAME_STATE + 6
MW_ACTIVE:          .equ    GAME_STATE + 7
MW_COOL:            .equ    GAME_STATE + 8
MW_NOTICE:          .equ    GAME_STATE + 9
MW_NOTICE_TIME:     .equ    GAME_STATE + 10
MW_CURSOR:          .equ    GAME_STATE + 11
MW_ARRIVAL:         .equ    GAME_STATE + 12
MW_DONE:            .equ    GAME_STATE + 13
MW_REWARD:          .equ    GAME_STATE + 14
MW_CHAIN:           .equ    GAME_STATE + 15
MW_SCORE:           .equ    GAME_STATE + 16
MW_MEDAL:           .equ    GAME_STATE + 17
MW_AGE:             .equ    GAME_STATE + 18
MW_B:               .equ    GAME_STATE + 19     ; trains (18)
MW_C:               .equ    GAME_STATE + 37     ; points, stops, busy, deck (19)
MW_HELD:            .equ    GAME_STATE + 60     ; unused (no held keys)
MW_I:               .equ    GAME_STATE + 61
MW_J:               .equ    GAME_STATE + 62
MW_T:               .equ    GAME_STATE + 63
MW_NX:              .equ    GAME_STATE + 64
MW_NY:              .equ    GAME_STATE + 65
MW_EXPRESS:         .equ    GAME_STATE + 66
MW_FLASH:           .equ    GAME_STATE + 67     ; platform + 1 flashing
MW_FLASH_ATTR:      .equ    GAME_STATE + 68
MW_GOALS:           .equ    GAME_STATE + 69
MW_DI:              .equ    GAME_STATE + 70
MW_DT:              .equ    GAME_STATE + 71
MW_DY:              .equ    GAME_STATE + 72
MW_MSG:             .equ    GAME_STATE + 73     ; 2 bytes

MW_TILE_TRAIN:      .equ    0x80
MW_TILE_STATION:    .equ    0x84        ; A, B, C 4 codes apart
MW_CHAR_TRACK:      .equ    0x90
MW_CHAR_DIAGONAL:   .equ    0x91
MW_CHAR_JOIN:       .equ    0x92
MW_CHAR_POINT:      .equ    0x93        ; straight, turned
MW_CHAR_RIGHT:      .equ    0x95
MW_CHAR_DOWN:       .equ    0x96
MW_CHAR_LAMP_ON:    .equ    0x97
MW_CHAR_LAMP_OFF:   .equ    0x98
MW_ATTR_TRACK:      .equ    0x45
MW_ATTR_TRAIN:      .equ    0x47
MW_ATTR_EXPRESS:    .equ    0x42
MW_ATTR_STATION:    .equ    0x44
MW_ATTR_LIT:        .equ    0x7c        ; green on white: a train heads there
MW_ATTR_POINT:      .equ    0x46
MW_ATTR_LAMP:       .equ    0x46
MW_ATTR_SPARK:      .equ    0x6e        ; yellow on green
MW_ATTR_HIT:        .equ    0x72        ; red on yellow
MW_ATTR_TEXT:       .equ    0x07
MW_ATTR_LABEL:      .equ    0x04
MW_ATTR_TITLE:      .equ    0x06
MW_ATTR_DIM:        .equ    0x05
MW_ATTR_WARN:       .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     mw_patterns
        LDAA    MW_TILE_TRAIN
        LDAB    25
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; origin = entropy(): (voice 0 offset * 8 + frames left) of the song playing
; when the shift starts, or 0 for the self test and the demo.
; seed = origin ^ (37 + level * 17).
game_init:
        LDAA    [JR_AU_VOICE + 1]
        SUBA    [JR_AU_VOICE + 4]
        ASLA
        ASLA
        ASLA
        ADDA    [JR_AU_VOICE + 2]
        STAA    [MW_ORIGIN]
        JSR     jr_music_stop
        JSR     jr_test_level
        TST     [JR_TEST_QUIET]
        BNE     mw_init_fixed
        TST     [JR_TEST_DEMO]
        BEQ     mw_init_seed
mw_init_fixed:
        CLR     [MW_ORIGIN]
mw_init_seed:
        LDAA    [JR_PORT_LEVEL]
        LDAB    17
        JSR     jr_mul8
        ADDA    37
        EORA    [MW_ORIGIN]
        STAA    [MW_SEED]
        LDAA    3
        STAA    [MW_HP]
        LDAA    [JR_PORT_LEVEL]
        ADDA    2
        CMPA    3
        BLS     mw_init_capacity
        LDAA    3
mw_init_capacity:
        STAA    [MW_CAPACITY]
        LDAA    [JR_PORT_LEVEL]
        ASLA
        ASLA
        ASLA
        NEGA
        ADDA    24
        STAA    [MW_INTERVAL]
        LDAA    [JR_PORT_LEVEL]
        ASLA
        ADDA    [JR_PORT_LEVEL]
        ASLA
        ADDA    24
        STAA    [MW_QUOTA]
        JSR     mw_rand3
        STAA    [MW_C + 16]
        JSR     mw_rand3
        STAA    [MW_C + 17]
        JSR     mw_rand3
        STAA    [MW_C + 18]
        CLRA
        JMP     mw_dispatch

; -> A = rand() % 3 (seed = seed * 5 + 1).
mw_rand3:
        LDAA    [MW_SEED]
        ASLA
        ASLA
        ADDA    [MW_SEED]
        INCA
        STAA    [MW_SEED]
mw_rand3_mod:
        CMPA    3
        BCS     mw_rand3_done
        SUBA    3
        BRA     mw_rand3_mod
mw_rand3_done:
        RTS

; A = express (0 or 1): send the next train from the depot if there is room.
mw_dispatch:
        STAA    [MW_EXPRESS]
        LDAA    [MW_ISSUED]
        CMPA    8
        BNE     mw_act_done_near190
        JMP     mw_act_done
mw_act_done_near190:
        LDAA    [MW_ACTIVE]
        CMPA    [MW_CAPACITY]
        BNE     mw_act_done_near195
        JMP     mw_act_done
mw_act_done_near195:
        LDX     MW_B
mw_dispatch_clear:
        LDAA    [X]
        BEQ     mw_dispatch_next
        CMPA    5
        BCC     mw_act_done_near203
        JMP     mw_act_done
mw_act_done_near203:
mw_dispatch_next:
        INX
        CPX     MW_B + 3
        BNE     mw_dispatch_clear
        LDX     MW_B
mw_dispatch_slot:
        TST     [X]
        BEQ     mw_dispatch_place
        INX
        CPX     MW_B + 3
        BNE     mw_dispatch_slot
        RTS
mw_dispatch_place:
        LDAA    2
        STAA    [X]
        LDAA    5
        STAA    [X + 3]
        CLR     [X + 6]
        LDAA    [MW_C + 16]
        STAA    [X + 9]
        LDAA    32
        STAA    [X + 12]
        LDAA    [MW_EXPRESS]
        STAA    [X + 15]
        LDAA    [MW_C + 17]
        STAA    [MW_C + 16]
        LDAA    [MW_C + 18]
        STAA    [MW_C + 17]
        JSR     mw_rand3
        STAA    [MW_C + 18]
        INC     [MW_ISSUED]
        INC     [MW_ACTIVE]
        LDAA    [MW_INTERVAL]
        STAA    [MW_COOL]
        CLRA
        TST     [MW_EXPRESS]
        BEQ     mw_dispatch_notice
        LDAA    4
mw_dispatch_notice:
        STAA    [MW_NOTICE]
        LDAA    8
        STAA    [MW_NOTICE_TIME]
        TST     [MW_EXPRESS]
        BEQ     mw_dispatch_sound
        LDX     mw_sfx_express
        JMP     jr_sfx_play
mw_dispatch_sound:
        CLRA
        JMP     jr_port_sound

game_raw_key:
        JMP     jr_test_raw_key

game_act:
        CMPA    JR_KEY_DOWN
        BHI     mw_act_stop
        TSTA
        BEQ     mw_act_done
        LDAA    [MW_CURSOR]
        EORA    1
        STAA    [MW_CURSOR]
        RTS
mw_act_stop:
        CMPA    JR_KEY_LEFT
        BNE     mw_act_point
        LDX     MW_C + 2
        BRA     mw_act_toggle
mw_act_point:
        CMPA    JR_KEY_RIGHT
        BNE     mw_act_express
        LDX     MW_C
mw_act_toggle:
        LDAA    [MW_CURSOR]
        JSR     jr_add_x_a
        LDAA    [X]
        EORA    1
        STAA    [X]
        CLRA
        JMP     jr_port_sound
mw_act_express:
        CMPA    JR_KEY_CONFIRM
        BNE     mw_act_done
        LDAA    1
        JMP     mw_dispatch
mw_act_done:
        RTS

; MW_I = train: it reaches the platform (track 0-2).
mw_arrive:
        LDX     MW_B
        LDAA    [MW_I]
        JSR     jr_add_x_a
        LDAA    [MW_I]
        INCA
        STAA    [MW_ARRIVAL]
        LDAB    [X + 6]
        STX     [MW_MSG]
        LDX     MW_C + 8
        TBA
        JSR     jr_add_x_a
        LDAA    12
        STAA    [X]
        LDX     [MW_MSG]
        INC     [MW_DONE]
        DEC     [MW_ACTIVE]
        CLR     [MW_REWARD]
        LDAA    [X + 6]
        CMPA    [X + 9]
        BEQ     mw_arrive_right
        LDAA    2
        BRA     mw_arrive_notice
mw_arrive_right:
        LDAA    [X + 15]
        CMPA    2
        BNE     mw_arrive_on_time
        LDAA    3
        BRA     mw_arrive_notice
mw_arrive_on_time:
        ; chain up to 3; 2 points (4 for an express) times the chain
        LDAA    [MW_CHAIN]
        CMPA    3
        BCC     mw_arrive_chain
        INC     [MW_CHAIN]
mw_arrive_chain:
        LDAA    [MW_CHAIN]
        ASLA
        TST     [X + 15]
        BEQ     mw_arrive_reward
        ASLA
mw_arrive_reward:
        STAA    [MW_REWARD]
        ADDA    [MW_SCORE]
        STAA    [MW_SCORE]
        LDAA    1
mw_arrive_notice:
        STAA    [MW_NOTICE]
        LDAA    10
        STAA    [MW_NOTICE_TIME]
        LDAA    [X + 6]
        INCA
        STAA    [MW_FLASH]
        TST     [MW_REWARD]
        BEQ     mw_arrive_miss
        LDAA    MW_ATTR_SPARK
        STAA    [MW_FLASH_ATTR]
        LDAA    1
        JSR     jr_port_sound
        LDAA    12
        BRA     mw_arrive_show
mw_arrive_miss:
        DEC     [MW_HP]
        CLR     [MW_CHAIN]
        LDAA    MW_ATTR_HIT
        STAA    [MW_FLASH_ATTR]
        LDX     mw_sfx_miss
        JSR     jr_sfx_play
        LDAA    30
mw_arrive_show:
        JSR     jr_test_animate
        CLR     [MW_FLASH]
        TST     [MW_HP]
        BNE     mw_arrive_shift
        LDX     mw_txt_late
        LDAA    [MW_NOTICE]
        CMPA    3
        BEQ     mw_arrive_lose
        LDX     mw_txt_wrong
mw_arrive_lose:
        JMP     jr_port_lose
mw_arrive_shift:
        LDAA    [MW_DONE]
        CMPA    8
        BNE     mw_arrive_clear
        LDAA    [MW_SCORE]
        CMPA    [MW_QUOTA]
        BCC     mw_arrive_medal
        LDX     mw_txt_quota
        JMP     jr_port_lose
mw_arrive_medal:
        LDAB    1
        CMPA    44
        BCS     mw_arrive_won
        INCB
        CMPA    60
        BCS     mw_arrive_won
        INCB
mw_arrive_won:
        STAB    [MW_MEDAL]
        JMP     jr_port_win
mw_arrive_clear:
        LDX     MW_B
        LDAA    [MW_I]
        JSR     jr_add_x_a
        CLR     [X]
        RTS

; MW_I = train: one step along its track, held at a stopped point, a busy
; platform or too close to another train.
mw_advance:
        LDX     MW_B
        LDAA    [MW_I]
        JSR     jr_add_x_a
        LDAA    [X + 15]
        CMPA    1
        BNE     mw_advance_point_1
        TST     [X + 12]
        BEQ     mw_advance_late
        DEC     [X + 12]
        BRA     mw_advance_point_1
mw_advance_late:
        LDAA    2
        STAA    [X + 15]
mw_advance_point_1:
        LDAA    [X]
        CMPA    8
        BNE     mw_advance_point_2
        LDAA    [X + 3]
        CMPA    5
        BNE     mw_advance_point_2
        TST     [MW_C + 2]
        BEQ     mw_act_done_near426
        JMP     mw_act_done
mw_act_done_near426:
        LDAA    [MW_C]
        STAA    [X + 6]
mw_advance_point_2:
        LDAA    [X]
        CMPA    17
        BNE     mw_advance_platform
        LDAA    [X + 3]
        CMPA    10
        BNE     mw_advance_platform
        TST     [MW_C + 3]
        BEQ     mw_act_done_near439
        JMP     mw_act_done
mw_act_done_near439:
        LDAA    [MW_C + 1]
        INCA
        STAA    [X + 6]
mw_advance_platform:
        LDAA    [X]
        CMPA    25
        BNE     mw_advance_step
        STX     [MW_MSG]
        LDAA    [X + 6]
        LDX     MW_C + 8
        JSR     jr_add_x_a
        TST     [X]
        BEQ     mw_act_done_near454
        JMP     mw_act_done
mw_act_done_near454:
        LDX     [MW_MSG]
mw_advance_step:
        ; next place: one column on, one row down until its track's row
        LDAA    [X]
        INCA
        STAA    [MW_NX]
        LDAA    [X + 6]
        STAA    [MW_T]
        ASLA
        ASLA
        ADDA    [MW_T]
        ADDA    5
        STAA    [MW_T]
        LDAA    [X + 3]
        CMPA    [MW_T]
        BCC     mw_advance_row
        INCA
mw_advance_row:
        STAA    [MW_NY]
        ; automatic braking
        CLR     [MW_J]
mw_advance_other:
        LDAA    [MW_J]
        CMPA    [MW_I]
        BEQ     mw_advance_other_next
        LDX     MW_B
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     mw_advance_other_next
        SUBA    [MW_NX]
        BCC     mw_advance_dx
        NEGA
mw_advance_dx:
        CMPA    3
        BCC     mw_advance_other_next
        LDAA    [X + 3]
        SUBA    [MW_NY]
        BCC     mw_advance_dy
        NEGA
mw_advance_dy:
        CMPA    2
        BCC     mw_act_done_near498
        JMP     mw_act_done
mw_act_done_near498:
mw_advance_other_next:
        INC     [MW_J]
        LDAA    [MW_J]
        CMPA    3
        BNE     mw_advance_other
        LDX     MW_B
        LDAA    [MW_I]
        JSR     jr_add_x_a
        LDAA    [MW_NX]
        STAA    [X]
        LDAB    [MW_NY]
        STAB    [X + 3]
        CMPA    26
        BEQ     mw_act_done_near514
        JMP     mw_act_done
mw_act_done_near514:
        JMP     mw_arrive

game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     mw_act_done_near523
        JMP     mw_act_done
mw_act_done_near523:
        CLR     [MW_ARRIVAL]
        INC     [MW_AGE]
        TST     [MW_NOTICE_TIME]
        BEQ     mw_tick_cool
        DEC     [MW_NOTICE_TIME]
mw_tick_cool:
        TST     [MW_COOL]
        BEQ     mw_tick_busy
        DEC     [MW_COOL]
mw_tick_busy:
        LDX     MW_C + 8
mw_tick_busy_next:
        TST     [X]
        BEQ     mw_tick_busy_step
        DEC     [X]
mw_tick_busy_step:
        INX
        CPX     MW_C + 11
        BNE     mw_tick_busy_next
        CLR     [MW_I]
mw_tick_train:
        LDX     MW_B
        LDAA    [MW_I]
        JSR     jr_add_x_a
        TST     [X]
        BEQ     mw_tick_train_next
        JSR     mw_advance
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     mw_act_done_near555
        JMP     mw_act_done
mw_act_done_near555:
mw_tick_train_next:
        INC     [MW_I]
        LDAA    [MW_I]
        CMPA    3
        BNE     mw_tick_train
        TST     [MW_COOL]
        BEQ     mw_act_done_near564
        JMP     mw_act_done
mw_act_done_near564:
        CLRA
        JMP     mw_dispatch

; ---------------------------------------------------------------- drawing

; A = code, B = count, at the cursor.
mw_run:
        STAA    [MW_DT]
mw_run_next:
        LDAA    [MW_DT]
        JSR     jr_gfx_putc
        DECB
        BNE     mw_run_next
        RTS

; A = x, B = y of the top of a diagonal of 4 cells, then the joint below it.
mw_diagonal:
        STAA    [MW_DT]
        STAB    [MW_DY]
        LDAB    4
        STAB    [MW_J]
mw_diagonal_next:
        LDAA    [MW_DT]
        LDAB    [MW_DY]
        JSR     jr_gfx_at
        LDAA    MW_CHAR_DIAGONAL
        JSR     jr_gfx_putc
        INC     [MW_DT]
        INC     [MW_DY]
        DEC     [MW_J]
        BNE     mw_diagonal_next
        LDAA    [MW_DT]
        LDAB    [MW_DY]
        JSR     jr_gfx_at
        LDAA    MW_CHAR_JOIN
        JMP     jr_gfx_putc

game_draw:
        LDAA    0x20
        LDAB    MW_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     mw_hud
        JSR     jr_gfx_lines
        ; which stations a running train heads for
        CLR     [MW_GOALS]
        LDX     MW_B
mw_draw_goal:
        TST     [X]
        BEQ     mw_draw_goal_next
        LDAB    1
        LDAA    [X + 9]
mw_draw_goal_bit:
        BEQ     mw_draw_goal_set
        ASLB
        DECA
        BRA     mw_draw_goal_bit
mw_draw_goal_set:
        ORAB    [MW_GOALS]
        STAB    [MW_GOALS]
mw_draw_goal_next:
        INX
        CPX     MW_B + 3
        BNE     mw_draw_goal
        ; the track as the points are set
        LDAA    MW_ATTR_TRACK
        STAA    [JR_RT_COLOR]
        LDAA    3
        LDAB    6
        JSR     jr_gfx_at
        LDAB    25
        TST     [MW_C]
        BEQ     mw_draw_main
        LDAB    6
mw_draw_main:
        LDAA    MW_CHAR_TRACK
        JSR     mw_run
        TST     [MW_C]
        BEQ     mw_draw_points
        LDAA    10
        LDAB    7
        JSR     mw_diagonal
        LDAA    15
        LDAB    11
        JSR     jr_gfx_at
        LDAB    13
        TST     [MW_C + 1]
        BEQ     mw_draw_middle
        LDAB    3
mw_draw_middle:
        LDAA    MW_CHAR_TRACK
        JSR     mw_run
        TST     [MW_C + 1]
        BEQ     mw_draw_points
        LDAA    19
        LDAB    12
        JSR     mw_diagonal
        LDAA    24
        LDAB    16
        JSR     jr_gfx_at
        LDAB    4
        LDAA    MW_CHAR_TRACK
        JSR     mw_run
mw_draw_points:
        ; both points: setting, arrow, STOP / GO
        CLR     [MW_DI]
mw_draw_point:
        LDAA    [MW_DI]
        ASLA
        ASLA
        ASLA
        ADDA    [MW_DI]
        ADDA    9
        STAA    [MW_DT]
        LDAA    [MW_DI]
        ASLA
        ASLA
        ADDA    [MW_DI]
        ADDA    4
        STAA    [MW_DY]
        LDAA    MW_ATTR_POINT
        STAA    [JR_RT_COLOR]
        LDX     MW_C
        LDAA    [MW_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [MW_J]
        LDAA    [MW_DT]
        LDAB    [MW_DY]
        ADDB    2
        JSR     jr_gfx_at
        LDAA    [MW_J]
        ADDA    MW_CHAR_POINT
        JSR     jr_gfx_putc
        LDAA    [MW_DT]
        LDAB    [MW_DY]
        JSR     jr_gfx_at
        LDAA    MW_CHAR_RIGHT
        TST     [MW_J]
        BEQ     mw_draw_point_arrow
        LDAA    MW_CHAR_DOWN
mw_draw_point_arrow:
        JSR     jr_gfx_putc
        LDAA    MW_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    [MW_DT]
        ADDA    2
        LDAB    [MW_DY]
        DECB
        JSR     jr_gfx_at
        LDX     MW_C + 2
        LDAA    [MW_DI]
        JSR     jr_add_x_a
        LDX     mw_txt_go
        TST     [X]
        BEQ     mw_draw_point_text
        LDX     mw_txt_stop
        LDAA    MW_ATTR_WARN
        STAA    [JR_RT_COLOR]
mw_draw_point_text:
        JSR     jr_gfx_text
        INC     [MW_DI]
        LDAA    [MW_DI]
        CMPA    2
        BEQ     mw_draw_point_near730
        JMP     mw_draw_point
mw_draw_point_near730:
        ; the selected point
        LDAA    MW_ATTR_EXPRESS
        STAA    [JR_RT_COLOR]
        LDAA    [MW_CURSOR]
        ASLA
        ASLA
        ASLA
        ADDA    [MW_CURSOR]
        ADDA    6
        LDAB    [MW_CURSOR]
        ASLB
        ASLB
        ADDB    [MW_CURSOR]
        ADDB    3
        JSR     jr_gfx_at
        LDAA    MW_CHAR_RIGHT
        JSR     jr_gfx_putc
        ; the stations, busy or awaited
        CLR     [MW_DI]
mw_draw_station:
        LDAA    [MW_DI]
        ASLA
        ASLA
        ADDA    [MW_DI]
        ADDA    5
        STAA    [MW_DY]
        LDAA    MW_ATTR_STATION
        LDAB    [MW_DI]
        INCB
        CMPB    [MW_FLASH]
        BNE     mw_draw_station_lit
        LDAA    [MW_FLASH_ATTR]
        BRA     mw_draw_station_colour
mw_draw_station_lit:
        JSR     mw_goal_bit
        BEQ     mw_draw_station_plain
        LDAA    MW_ATTR_LIT
        BRA     mw_draw_station_colour
mw_draw_station_plain:
        LDAA    MW_ATTR_STATION
mw_draw_station_colour:
        STAA    [JR_RT_COLOR]
        LDAA    29
        LDAB    [MW_DY]
        JSR     jr_gfx_at
        LDAA    [MW_DI]
        ASLA
        ASLA
        ADDA    MW_TILE_STATION
        JSR     jr_gfx_tile
        LDX     MW_C + 8
        LDAA    [MW_DI]
        JSR     jr_add_x_a
        TST     [X]
        BEQ     mw_draw_station_goal
        LDAA    MW_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    [MW_DY]
        SUBB    2
        JSR     jr_gfx_at
        LDX     mw_txt_busy
        JSR     jr_gfx_text
mw_draw_station_goal:
        JSR     mw_goal_bit
        BEQ     mw_draw_station_next
        LDAA    MW_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    28
        LDAB    [MW_DY]
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDAA    MW_ATTR_LAMP
        STAA    [JR_RT_COLOR]
        LDAA    MW_CHAR_LAMP_ON
        LDAB    [MW_AGE]
        ANDB    1
        BNE     mw_draw_lamps
        LDAA    MW_CHAR_LAMP_OFF
mw_draw_lamps:
        STAA    [MW_T]
        LDAA    28
        LDAB    [MW_DY]
        DECB
        JSR     jr_gfx_at
        LDAB    4
        LDAA    [MW_T]
        JSR     mw_run
        LDAA    28
        LDAB    [MW_DY]
        ADDB    2
        JSR     jr_gfx_at
        LDAB    4
        LDAA    [MW_T]
        JSR     mw_run
mw_draw_station_next:
        INC     [MW_DI]
        LDAA    [MW_DI]
        CMPA    3
        BEQ     mw_draw_trains
        JMP     mw_draw_station
mw_draw_trains:
        CLR     [MW_DI]
mw_draw_train:
        LDX     MW_B
        LDAA    [MW_DI]
        JSR     jr_add_x_a
        TST     [X]
        BNE     mw_draw_train_on
        JMP     mw_draw_train_next
mw_draw_train_on:
        STX     [MW_MSG]
        LDAA    MW_ATTR_TRAIN
        TST     [X + 15]
        BEQ     mw_draw_train_colour
        LDAA    MW_ATTR_EXPRESS
mw_draw_train_colour:
        STAA    [JR_RT_COLOR]
        LDAA    [X]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    MW_TILE_TRAIN
        JSR     jr_gfx_tile
        ; the label above it and the list on the left
        LDAA    MW_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDX     [MW_MSG]
        LDAA    [X]
        LDAB    [X + 3]
        DECB
        JSR     jr_gfx_at
        JSR     mw_train_label
        LDAA    1
        LDAB    [MW_DI]
        ASLB
        ADDB    10
        STAB    [MW_DY]
        JSR     jr_gfx_at
        LDAA    [MW_DI]
        ADDA    0x31
        JSR     jr_gfx_putc
        LDAA    0x20
        JSR     jr_gfx_putc
        LDX     [MW_MSG]
        LDAA    [X + 9]
        ADDA    0x41
        JSR     jr_gfx_putc
        LDAA    0x20
        JSR     jr_gfx_putc
        LDX     [MW_MSG]
        TST     [X + 15]
        BNE     mw_draw_train_express
        LDX     mw_txt_reg
        JSR     jr_gfx_text
        BRA     mw_draw_train_next
mw_draw_train_express:
        ; margin = deadline - distance to the platform (0 when late)
        LDAA    0x2b
        LDAB    [X + 15]
        CMPB    1
        BEQ     mw_draw_train_mark
        LDAA    0x21
mw_draw_train_mark:
        JSR     jr_gfx_putc
        LDX     [MW_MSG]
        LDAA    26
        SUBA    [X]
        STAA    [MW_T]
        LDAA    [X + 12]
        SUBA    [MW_T]
        BCC     mw_draw_train_margin
        CLRA
mw_draw_train_margin:
        JSR     jr_gfx_dec2
mw_draw_train_next:
        INC     [MW_DI]
        LDAA    [MW_DI]
        CMPA    3
        BEQ     mw_draw_panel
        JMP     mw_draw_train
mw_draw_panel:
        LDAA    MW_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    4
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [MW_HP]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    11
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [MW_DONE]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    24
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [MW_CHAIN]
        BNE     mw_draw_chain
        INCA
mw_draw_chain:
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    5
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [MW_SCORE]
        JSR     jr_gfx_dec3
        LDAA    11
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [MW_QUOTA]
        JSR     jr_gfx_dec2
        ; the next three destinations (dashes past the eighth train)
        CLR     [MW_DI]
mw_draw_deck:
        LDAA    [MW_DI]
        ASLA
        ADDA    6
        LDAB    21
        JSR     jr_gfx_at
        LDAA    [MW_ISSUED]
        ADDA    [MW_DI]
        LDAB    0x2d
        CMPA    8
        BCC     mw_draw_deck_letter
        LDX     MW_C + 16
        LDAA    [MW_DI]
        JSR     jr_add_x_a
        LDAB    [X]
        ADDB    0x41
mw_draw_deck_letter:
        TBA
        JSR     jr_gfx_putc
        INC     [MW_DI]
        LDAA    [MW_DI]
        CMPA    3
        BNE     mw_draw_deck
        LDAA    18
        LDAB    21
        JSR     jr_gfx_at
        LDAA    [MW_COOL]
        JSR     jr_gfx_dec2
        ; row 2: the medal, or the latest notice
        LDAA    MW_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_CLEAR
        BEQ     mw_draw_medal
        CMPA    JR_MODE_END
        BNE     mw_draw_notice
mw_draw_medal:
        LDX     mw_medals - 2
        LDAA    [MW_MEDAL]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        BRA     mw_draw_demo
mw_draw_notice:
        TST     [MW_NOTICE_TIME]
        BEQ     mw_draw_demo
        LDX     mw_notices - 2
        LDAA    [MW_NOTICE]
        BEQ     mw_draw_demo
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        LDAA    [MW_NOTICE]
        CMPA    1
        BNE     mw_draw_demo
        LDAA    12
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [MW_REWARD]
        JSR     jr_gfx_dec2
        LDAA    16
        LDAB    2
        JSR     jr_gfx_at
        LDX     mw_txt_chain
        JSR     jr_gfx_text
mw_draw_demo:
        TST     [JR_TEST_DEMO]
        BEQ     mw_draw_done
        LDAA    MW_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDX     mw_txt_demo
        JSR     jr_gfx_text
mw_draw_done:
        RTS

; MW_DI = station -> Z clear when a running train heads there.
mw_goal_bit:
        LDAA    [MW_GOALS]
        LDAB    [MW_DI]
mw_goal_bit_shift:
        BEQ     mw_goal_bit_test
        LSRA
        DECB
        BRA     mw_goal_bit_shift
mw_goal_bit_test:
        ANDA    1
        RTS

; [MW_MSG] = train: its number and destination letter at the cursor.
mw_train_label:
        LDAA    [MW_DI]
        ADDA    0x31
        JSR     jr_gfx_putc
        LDX     [MW_MSG]
        LDAA    [X + 9]
        ADDA    0x41
        JMP     jr_gfx_putc

game_draw_title:
        LDX     mw_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    MW_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    MW_ATTR_TRACK
        STAA    [JR_RT_COLOR]
        LDAA    4
        LDAB    4
        JSR     jr_gfx_at
        LDAB    22
        LDAA    MW_CHAR_TRACK
        JSR     mw_run
        LDAA    MW_ATTR_TRAIN
        STAA    [JR_RT_COLOR]
        LDAA    8
        LDAB    3
        JSR     jr_gfx_at
        LDAA    MW_TILE_TRAIN
        JSR     jr_gfx_tile
        LDAA    MW_ATTR_EXPRESS
        STAA    [JR_RT_COLOR]
        LDAA    16
        LDAB    3
        JSR     jr_gfx_at
        LDAA    MW_TILE_TRAIN
        JSR     jr_gfx_tile
        LDAA    MW_ATTR_LIT
        STAA    [JR_RT_COLOR]
        LDAA    26
        LDAB    3
        JSR     jr_gfx_at
        LDAA    MW_TILE_STATION
        JSR     jr_gfx_tile
        LDX     mw_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    MW_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     mw_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

mw_notices:
        .dw     mw_txt_delivered, mw_txt_wrong_station, mw_txt_express_late, mw_txt_departed
mw_medals:
        .dw     mw_txt_bronze, mw_txt_silver, mw_txt_gold

mw_hud:
        .db     1, 0, MW_ATTR_TITLE
        .dw     mw_txt_name
        .db     1, 8, MW_ATTR_LABEL
        .dw     mw_txt_trains
        .db     1, 9, MW_ATTR_DIM
        .dw     mw_txt_id
        .db     1, 19, MW_ATTR_LABEL
        .dw     mw_txt_row19
        .db     1, 20, MW_ATTR_LABEL
        .dw     mw_txt_row20
        .db     1, 21, MW_ATTR_LABEL
        .dw     mw_txt_row21
        .db     0xff
mw_title_lines:
        .db     10, 8, MW_ATTR_TITLE
        .dw     mw_txt_name
        .db     3, 10, MW_ATTR_LABEL
        .dw     mw_txt_tagline
        .db     4, 13, MW_ATTR_TEXT
        .dw     mw_txt_start
        .db     4, 15, MW_ATTR_TEXT
        .dw     mw_txt_howto
        .db     4, 17, MW_ATTR_DIM
        .dw     mw_txt_demo_hint
        .db     4, 19, MW_ATTR_DIM
        .dw     mw_txt_credit
        .db     0xff
mw_help_lines:
        .db     10, 1, MW_ATTR_TITLE
        .dw     mw_txt_name
        .db     1, 3, MW_ATTR_TEXT
        .dw     mw_help_1
        .db     1, 5, MW_ATTR_TEXT
        .dw     mw_help_2
        .db     1, 7, MW_ATTR_TEXT
        .dw     mw_help_3
        .db     1, 9, MW_ATTR_TEXT
        .dw     mw_help_4
        .db     1, 11, MW_ATTR_TEXT
        .dw     mw_help_5
        .db     1, 13, MW_ATTR_TEXT
        .dw     mw_help_6
        .db     1, 15, MW_ATTR_TEXT
        .dw     mw_help_7
        .db     1, 17, MW_ATTR_TEXT
        .dw     mw_help_8
        .db     1, 19, MW_ATTR_TEXT
        .dw     mw_help_9
        .db     1, 21, MW_ATTR_LABEL
        .dw     mw_help_back
        .db     0xff

mw_txt_name:
        .db     "METRO WEAVE", 0
mw_txt_trains:
        .db     "TRAINS", 0
mw_txt_id:
        .db     "ID TO WAIT", 0
mw_txt_row19:
        .db     "HP   DONE  /8  CHAIN X", 0
mw_txt_row20:
        .db     "PTS     /      TARGET", 0
mw_txt_row21:
        .db     "NEXT         AUTO", 0
mw_txt_stop:
        .db     "STOP", 0
mw_txt_go:
        .db     "GO", 0
mw_txt_busy:
        .db     "BUSY", 0
mw_txt_reg:
        .db     "REG", 0
mw_txt_delivered:
        .db     "DELIVERED +", 0
mw_txt_chain:
        .db     "CHAIN BONUS!", 0
mw_txt_wrong_station:
        .db     "WRONG STATION! CHAIN LOST", 0
mw_txt_express_late:
        .db     "EXPRESS LATE! CHAIN LOST", 0
mw_txt_departed:
        .db     "EXPRESS DEPARTED", 0
mw_txt_gold:
        .db     "GOLD DISPATCHER!", 0
mw_txt_silver:
        .db     "SILVER DISPATCHER!", 0
mw_txt_bronze:
        .db     "BRONZE DISPATCHER!", 0
mw_txt_demo:
        .db     "DEMO", 0
mw_txt_late:
        .db     "EXPRESS LATE", 0
mw_txt_wrong:
        .db     "WRONG PLATFORM", 0
mw_txt_quota:
        .db     "NOT ENOUGH POINTS THIS SHIFT", 0
mw_txt_tagline:
        .db     "SWITCH, HOLD, DELIVER ON TIME", 0
mw_txt_start:
        .db     "RETURN : START", 0
mw_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
mw_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
mw_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
mw_help_1:
        .db     "W/S: SELECT POINT 1 OR 2.", 0
mw_help_2:
        .db     "D: SWITCH TRACK. A: STOP/GO.", 0
mw_help_3:
        .db     "RETURN: SEND AN EXPRESS.", 0
mw_help_4:
        .db     "MATCH TRAIN AND STATION LETTERS", 0
mw_help_5:
        .db     "BUSY: WAIT FOR UNLOADING.", 0
mw_help_6:
        .db     "REG 2PTS / EXPRESS 4PTS / X3", 0
mw_help_7:
        .db     "LATE/WRONG: -1 HP, CHAIN LOST.", 0
mw_help_8:
        .db     "8 TRAINS: TARGET 24 / 30 / 36.", 0
mw_help_9:
        .db     "SILVER:44 / GOLD:60 POINTS.", 0
mw_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     mw_sfx_click, mw_sfx_deliver, mw_jingle_win, mw_jingle_lose
mw_sfx_click:
        .db     70, 1, 0, 0
mw_sfx_deliver:
        .db     40, 3, 30, 3, 24, 8, 0, 0
mw_sfx_express:
        .db     50, 2, 40, 2, 50, 2, 40, 2, 0, 0
mw_sfx_miss:
        .db     160, 4, 220, 8, 0, 0

; Title: a busy station tune in G major, eighth note = 8 frames, looping.
mw_title_song:
        .db     1
        .dw     mw_title_melody, mw_title_harmony, mw_title_bass
mw_title_melody:
        .db     AU_G4, 8, AU_B4, 8, AU_D5, 8, AU_G5, 8, AU_FS5, 8, AU_D5, 8, AU_E5, 16
        .db     AU_C5, 8, AU_E5, 8, AU_G5, 8, AU_E5, 8, AU_D5, 32
        .db     AU_G4, 8, AU_B4, 8, AU_D5, 8, AU_G5, 8, AU_A5, 8, AU_FS5, 8, AU_G5, 16
        .db     AU_E5, 8, AU_C5, 8, AU_A4, 8, AU_FS4, 8, AU_G4, 32, 0, 0
mw_title_harmony:
        .db     AU_D4, 32, AU_B4, 32, AU_G4, 32, AU_FS4, 32
        .db     AU_B4, 32, AU_D5, 32, AU_C5, 32, AU_B4, 32, 0, 0
mw_title_bass:
        .db     AU_G2, 16, AU_D3, 16, AU_B2, 16, AU_C3, 16, AU_C3, 16, AU_A2, 16, AU_D3, 32
        .db     AU_G2, 16, AU_D3, 16, AU_E3, 16, AU_C3, 16, AU_A2, 16, AU_D3, 16, AU_G2, 32, 0, 0

; Shift complete: G major departure bell.
mw_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     mw_win_melody, mw_win_harmony, mw_win_bass
mw_win_melody:
        .db     AU_D5, 6, AU_G5, 6, AU_B5, 6, AU_D6, 12, AU_G6, 30, 0, 0
mw_win_harmony:
        .db     AU_B4, 12, AU_D5, 18, AU_B5, 30, 0, 0
mw_win_bass:
        .db     AU_G3, 12, AU_D3, 18, AU_G2, 30, 0, 0
mw_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     mw_lose_melody, mw_lose_harmony, mw_lose_bass
mw_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
mw_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
mw_lose_bass:
        .db     AU_FS3, 36, AU_CS3, 30, 0, 0


        .include "selftest.inc"
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
        .include "../../../sdk/selftest.inc"
        .include "../../../sdk/font_data.inc"
