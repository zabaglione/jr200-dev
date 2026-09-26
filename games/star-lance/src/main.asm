; SPDX-License-Identifier: MIT
; STAR LANCE for JR-200: a port of jr100dev games/star_lance/rules.py 4.0.0.
; Six waves of eighteen ships marching side to side and dropping, armored
; front rows, the charging shooter and its aimed bolts (three from wave 3),
; light and heavy shots, weapon heat and the jam, the cooling reward for
; stopping a charge and the hull follow the upstream source, one upstream
; tick per game_tick. Held A / D / W / RETURN come from the keyboard MCU scan
; (sdk/keyscan.inc, one key at a time); key presses are kept as taps like
; upstream. Rules are checked by the in-program self test (sdk/selftest.inc,
; title key T); P plays the wave-1 demo.
        .filename.jr "STAR-LANCE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4740
JR_AUDIO:           .equ    0x4740
JR_TEST:            .equ    0x4760
JR_TEST_OUT:        .equ    0x5000
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    6
; Upstream ticks every 4 frames; one tick here is GAME_RATE idle frames plus
; the render and the key scan (see README).
GAME_RATE:          .equ    1
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    1
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_TEST_SIZE:     .equ    131
GAME_TEST_LIMIT:    .equ    3000
GAME_TEST_HELD:     .equ    SL_HELD

; Upstream state (tests/model.py LAYOUT), then drawing-only bytes.
SL_SHIP:            .equ    GAME_STATE
SL_HP:              .equ    GAME_STATE + 1
SL_LEFT:            .equ    GAME_STATE + 2
SL_SHIFT:           .equ    GAME_STATE + 3
SL_DIRECTION:       .equ    GAME_STATE + 4
SL_TARGET:          .equ    GAME_STATE + 5
SL_WAIT:            .equ    GAME_STATE + 6
SL_TAP:             .equ    GAME_STATE + 7
SL_COOL:            .equ    GAME_STATE + 8
SL_HEAT:            .equ    GAME_STATE + 9
SL_JAM:             .equ    GAME_STATE + 10
SL_NOTICE:          .equ    GAME_STATE + 11
SL_TIME:            .equ    GAME_STATE + 12
SL_AGE:             .equ    GAME_STATE + 13
SL_DROP:            .equ    GAME_STATE + 14
SL_CHARGE:          .equ    GAME_STATE + 15
SL_SHIELD:          .equ    GAME_STATE + 16
SL_MARCH:           .equ    GAME_STATE + 17
SL_FINISH:          .equ    GAME_STATE + 18
SL_D:               .equ    GAME_STATE + 19     ; shots: y, x, power (24)
SL_C:               .equ    GAME_STATE + 43     ; bolts (64)
SL_B:               .equ    GAME_STATE + 107    ; hull, flash, blast x, y (120)
SL_HELD:            .equ    GAME_STATE + 228    ; buttons() mask held
SL_KEYS:            .equ    GAME_STATE + 229
SL_I:               .equ    GAME_STATE + 230
SL_K:               .equ    GAME_STATE + 231
SL_T:               .equ    GAME_STATE + 232
SL_U:               .equ    GAME_STATE + 233
SL_X:               .equ    GAME_STATE + 234
SL_Y:               .equ    GAME_STATE + 235
SL_AIM:             .equ    GAME_STATE + 236
SL_BEST:            .equ    GAME_STATE + 237
SL_POWER:           .equ    GAME_STATE + 238
SL_HIT:             .equ    GAME_STATE + 239
SL_FLASH:           .equ    GAME_STATE + 240
SL_DI:              .equ    GAME_STATE + 241
SL_DX:              .equ    GAME_STATE + 242
SL_DY:              .equ    GAME_STATE + 243
SL_DCODE:           .equ    GAME_STATE + 244

SL_TILE_ENEMY:      .equ    0x80
SL_TILE_ARMOR:      .equ    0x84
SL_TILE_SHIP:       .equ    0x88
SL_TILE_FLASH:      .equ    0x8c
SL_TILE_BOOM:       .equ    0x90        ; three phases, 4 codes apart
SL_CHAR_LIGHT:      .equ    0x9c
SL_CHAR_HEAVY:      .equ    0x9d
SL_CHAR_BOLT:       .equ    0x9e        ; and 0x9f
SL_ATTR_ENEMY:      .equ    0x45
SL_ATTR_ARMOR:      .equ    0x43
SL_ATTR_SHIP:       .equ    0x47
SL_ATTR_FLASH:      .equ    0x42
SL_ATTR_BOOM:       .equ    0x46
SL_ATTR_SHOT:       .equ    0x46
SL_ATTR_BOLT:       .equ    0x42
SL_ATTR_HIT:        .equ    0x72        ; red on yellow
SL_ATTR_TEXT:       .equ    0x07
SL_ATTR_LABEL:      .equ    0x04
SL_ATTR_TITLE:      .equ    0x06
SL_ATTR_DIM:        .equ    0x05
SL_ATTR_WARN:       .equ    0x02
SL_ATTR_STAR:       .equ    0x01

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_keyscan_init
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     sl_patterns
        LDAA    SL_TILE_ENEMY
        LDAB    32
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        JSR     jr_test_level
        LDAA    14
        STAA    [SL_SHIP]
        LDAA    3
        STAA    [SL_HP]
        LDAA    18
        STAA    [SL_LEFT]
        LDAA    4
        STAA    [SL_SHIFT]
        LDAA    1
        STAA    [SL_DIRECTION]
        LDAA    255
        STAA    [SL_TARGET]
        LDAA    24
        STAA    [SL_WAIT]
        ; six ships per row of eight; the front row (two rows from wave 4) armored
        CLR     [SL_I]
sl_init_fleet:
        LDX     SL_B
        LDAA    [SL_I]
        JSR     jr_add_x_a
        CLRB
        LDAA    [SL_I]
        ANDA    7
        CMPA    6
        BCC     sl_init_hull
        LDAB    1
        LDAA    [SL_I]
        CMPA    8
        BCS     sl_init_armor
        CMPA    16
        BCC     sl_init_hull
        LDAA    [JR_PORT_LEVEL]
        CMPA    3
        BCS     sl_init_hull
sl_init_armor:
        LDAB    2
sl_init_hull:
        STAB    [X]
        INC     [SL_I]
        LDAA    [SL_I]
        CMPA    24
        BNE     sl_init_fleet
        RTS

game_raw_key:
        JMP     jr_test_raw_key

; Key presses are kept as taps until the next tick.
game_act:
        LDAB    2
        CMPA    JR_KEY_LEFT
        BEQ     sl_act_tap
        LDAB    1
        CMPA    JR_KEY_RIGHT
        BEQ     sl_act_tap
        LDAB    16
        CMPA    JR_KEY_CONFIRM
        BEQ     sl_act_tap
        LDAB    4
        CMPA    JR_KEY_UP
        BNE     sl_act_done
sl_act_tap:
        ORAB    [SL_TAP]
        STAB    [SL_TAP]
sl_act_done:
        RTS

; A = 0-5: the upstream sound effects (shot, hit, heavy, hot, cool, warning).
sl_sound:
        ASLA
        LDX     sl_sounds
        JSR     jr_add_x_a
        LDX     [X]
        JMP     jr_sfx_play

; A = power: a shot from the lance into the first free slot.
sl_fire:
        STAA    [SL_POWER]
        LDX     SL_D
sl_fire_slot:
        TST     [X]
        BEQ     sl_fire_place
        INX
        CPX     SL_D + 3
        BNE     sl_fire_slot
        RTS
sl_fire_place:
        LDAA    19
        STAA    [X]
        LDAA    [SL_SHIP]
        INCA
        STAA    [X + 8]
        LDAA    [SL_POWER]
        STAA    [X + 16]
        LDAB    4
        LDAA    [SL_POWER]
        CMPA    1
        BEQ     sl_fire_light
        LDAB    7
        LDAA    5
        BRA     sl_fire_heat
sl_fire_light:
        LDAA    3
sl_fire_heat:
        STAB    [SL_COOL]
        ADDA    [SL_HEAT]
        STAA    [SL_HEAT]
        CLRA
        LDAB    [SL_POWER]
        CMPB    1
        BEQ     sl_fire_sound
        LDAA    2
sl_fire_sound:
        JSR     sl_sound
        LDAA    [SL_HEAT]
        CMPA    12
        BCS     sl_act_done
        LDAA    12
        STAA    [SL_HEAT]
        LDAA    28
        STAA    [SL_JAM]
        LDAA    3
        JMP     sl_sound

; SL_I = ship, SL_POWER = power: hit it; a destroyed charging shooter cools.
sl_strike:
        LDX     SL_B
        LDAA    [SL_I]
        JSR     jr_add_x_a
        LDAA    [X]
        SUBA    [SL_POWER]
        BHI     sl_strike_hull
        CLRA
sl_strike_hull:
        STAA    [X]
        LDAA    6
        STAA    [X + 32]
        LDAA    [SL_I]
        ANDA    7
        ASLA
        ASLA
        ADDA    [SL_SHIFT]
        STAA    [X + 64]
        JSR     sl_row_y
        STAA    [X + 96]
        LDAA    1
        JSR     sl_sound
        LDX     SL_B
        LDAA    [SL_I]
        JSR     jr_add_x_a
        TST     [X]
        BEQ     sl_act_done_near269
        JMP     sl_act_done
sl_act_done_near269:
        DEC     [SL_LEFT]
        LDAA    [SL_TARGET]
        CMPA    [SL_I]
        BEQ     sl_act_done_near275
        JMP     sl_act_done
sl_act_done_near275:
        LDAA    255
        STAA    [SL_TARGET]
        LDAA    12
        STAA    [SL_WAIT]
        LDAA    [SL_HEAT]
        SUBA    4
        BHI     sl_strike_cool
        CLRA
sl_strike_cool:
        STAA    [SL_HEAT]
        CLR     [SL_JAM]
        LDAA    16
        STAA    [SL_NOTICE]
        LDAA    4
        JMP     sl_sound

; SL_I = ship -> A = 3 + row * 3 + drop.
sl_row_y:
        LDAA    [SL_I]
        LSRA
        LSRA
        LSRA
        STAA    [SL_T]
        ASLA
        ADDA    [SL_T]
        ADDA    3
        ADDA    [SL_DROP]
        RTS

; The shots climb one row; one that enters a ship strikes it.
sl_shots:
        CLR     [SL_K]
sl_shots_next:
        LDX     SL_D
        LDAA    [SL_K]
        JSR     jr_add_x_a
        TST     [X]
        BEQ     sl_shots_step
        DEC     [X]
        LDAA    [X + 8]
        SUBA    [SL_SHIFT]
        BCS     sl_shots_step
        STAA    [SL_X]
        LDAA    [X]
        SUBA    3
        BCS     sl_shots_step
        SUBA    [SL_DROP]
        BCS     sl_shots_step
        STAA    [SL_Y]
        LDAA    [SL_X]
        CMPA    24
        BCC     sl_shots_step
        ANDA    3
        CMPA    2
        BCC     sl_shots_step
        LDAA    [SL_Y]
        CMPA    9
        BCC     sl_shots_step
        CLRB
sl_shots_row:
        CMPA    3
        BCS     sl_shots_band
        SUBA    3
        ADDB    8
        BRA     sl_shots_row
sl_shots_band:
        CMPA    2
        BCC     sl_shots_step
        LDAA    [SL_X]
        LSRA
        LSRA
        ABA
        STAA    [SL_I]
        LDX     SL_B
        JSR     jr_add_x_a
        TST     [X]
        BEQ     sl_shots_step
        LDX     SL_D
        LDAA    [SL_K]
        JSR     jr_add_x_a
        LDAA    [X + 16]
        STAA    [SL_POWER]
        CLR     [X]
        JSR     sl_strike
sl_shots_step:
        INC     [SL_K]
        LDAA    [SL_K]
        CMPA    3
        BNE     sl_shots_next
        RTS

; SL_X, SL_Y, SL_AIM: a bolt into the first free slot, stepping like a line.
sl_launch:
        LDX     SL_C
sl_launch_slot:
        TST     [X]
        BEQ     sl_launch_place
        INX
        CPX     SL_C + 6
        BNE     sl_launch_slot
        RTS
sl_launch_place:
        LDAA    [SL_Y]
        STAA    [X]
        LDAA    [SL_X]
        STAA    [X + 8]
        LDAB    1
        LDAA    [SL_AIM]
        SUBA    [SL_X]
        BCC     sl_launch_dx
        NEGA
        LDAB    255
sl_launch_dx:
        STAA    [X + 24]
        STAB    [X + 32]
        LDAA    20
        SUBA    [SL_Y]
        STAA    [X + 48]
        CMPA    [X + 24]
        BCC     sl_launch_steps
        LDAA    [X + 24]
sl_launch_steps:
        STAA    [X + 16]
        CLR     [X + 40]
        CLR     [X + 56]
        RTS

; The fleet picks the ship nearest the lance, charges it and fires.
sl_attack:
        LDAA    [SL_TARGET]
        CMPA    255
        BNE     sl_attack_charge
        TST     [SL_WAIT]
        BEQ     sl_attack_pick
        DEC     [SL_WAIT]
        RTS
sl_attack_pick:
        LDAA    255
        STAA    [SL_BEST]
        LDAA    23
        STAA    [SL_I]
sl_attack_ship:
        LDX     SL_B
        LDAA    [SL_I]
        JSR     jr_add_x_a
        TST     [X]
        BEQ     sl_attack_next
        LDAA    [SL_I]
        ANDA    7
        ASLA
        ASLA
        ADDA    [SL_SHIFT]
        SUBA    [SL_SHIP]
        BCC     sl_attack_distance
        NEGA
sl_attack_distance:
        CMPA    [SL_BEST]
        BCC     sl_attack_next
        STAA    [SL_BEST]
        LDAA    [SL_I]
        STAA    [SL_TARGET]
sl_attack_next:
        DEC     [SL_I]
        LDAA    [SL_I]
        CMPA    255
        BNE     sl_attack_ship
        LDAA    18
        SUBA    [JR_PORT_LEVEL]
        STAA    [SL_CHARGE]
        LDAA    5
        JMP     sl_sound
sl_attack_charge:
        DEC     [SL_CHARGE]
        BEQ     sl_act_done_near451
        JMP     sl_act_done
sl_act_done_near451:
        LDAA    [SL_TARGET]
        STAA    [SL_I]
        ANDA    7
        ASLA
        ASLA
        ADDA    [SL_SHIFT]
        INCA
        STAA    [SL_X]
        JSR     sl_row_y
        ADDA    2
        STAA    [SL_Y]
        LDAA    [SL_SHIP]
        INCA
        STAA    [SL_AIM]
        JSR     sl_launch
        LDAA    [JR_PORT_LEVEL]
        CMPA    2
        BCS     sl_attack_done
        ; from wave 3 two more bolts fan out
        LDAA    [SL_SHIP]
        CMPA    4
        BCC     sl_attack_left
        LDAA    4
sl_attack_left:
        SUBA    3
        STAA    [SL_AIM]
        JSR     sl_launch
        LDAA    [SL_SHIP]
        ADDA    5
        CMPA    30
        BLS     sl_attack_right
        LDAA    30
sl_attack_right:
        STAA    [SL_AIM]
        JSR     sl_launch
sl_attack_done:
        LDAA    255
        STAA    [SL_TARGET]
        LDAA    [JR_PORT_LEVEL]
        STAA    [SL_T]
        ASLA
        ADDA    [SL_T]
        NEGA
        ADDA    24
        STAA    [SL_WAIT]
        LDAA    2
        JMP     sl_sound

; The bolts step down (and sideways); one reaching row 20 over the lance hits.
sl_bolts:
        CLR     [SL_HIT]
        LDX     SL_C
sl_bolts_next:
        TST     [X]
        BEQ     sl_bolts_step
        LDAA    [X + 56]
        ADDA    [X + 48]
        CMPA    [X + 16]
        BCS     sl_bolts_y
        SUBA    [X + 16]
        INC     [X]
sl_bolts_y:
        STAA    [X + 56]
        LDAA    [X + 40]
        ADDA    [X + 24]
        CMPA    [X + 16]
        BCS     sl_bolts_x
        SUBA    [X + 16]
        LDAB    [X + 8]
        ADDB    [X + 32]
        STAB    [X + 8]
sl_bolts_x:
        STAA    [X + 40]
        LDAA    [X + 8]
        CMPA    31
        BCC     sl_bolts_gone
        LDAA    [X]
        CMPA    20
        BCS     sl_bolts_step
        LDAA    [X + 8]
        CMPA    [SL_SHIP]
        BCS     sl_bolts_gone
        LDAB    [SL_SHIP]
        INCB
        CBA
        BHI     sl_bolts_gone
        LDAA    1
        STAA    [SL_HIT]
sl_bolts_gone:
        CLR     [X]
sl_bolts_step:
        INX
        CPX     SL_C + 6
        BNE     sl_bolts_next
        TST     [SL_HIT]
        BNE     sl_act_done_near549
        JMP     sl_act_done
sl_act_done_near549:
        TST     [SL_SHIELD]
        BEQ     sl_act_done_near553
        JMP     sl_act_done
sl_act_done_near553:
        DEC     [SL_HP]
        LDAA    24
        STAA    [SL_SHIELD]
        LDAA    3
        JSR     sl_sound
        LDAA    1
        STAA    [SL_FLASH]
        LDAA    8
        JSR     jr_test_animate
        CLR     [SL_FLASH]
        RTS

game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     sl_act_done_near572
        JMP     sl_act_done
sl_act_done_near572:
        TST     [JR_TEST_QUIET]
        BNE     sl_tick_rules
        LDAA    [JR_TEST_DEMO]
        CMPA    2
        BEQ     sl_tick_rules
        ; buttons() from the MCU scan: D 1, A 2, W 4, RETURN 16
        JSR     jr_keyscan
        CLRB
        CMPA    0x0d
        BNE     sl_tick_scan_letter
        LDAB    16
        BRA     sl_tick_scan_store
sl_tick_scan_letter:
        ORAA    0x20
        CMPA    0x64
        BNE     sl_tick_scan_a
        LDAB    1
sl_tick_scan_a:
        CMPA    0x61
        BNE     sl_tick_scan_w
        LDAB    2
sl_tick_scan_w:
        CMPA    0x77
        BNE     sl_tick_scan_store
        LDAB    4
sl_tick_scan_store:
        STAB    [SL_HELD]
sl_tick_rules:
        LDAA    [SL_HELD]
        ORAA    [SL_TAP]
        STAA    [SL_KEYS]
        CLR     [SL_TAP]
        INC     [SL_TIME]
        INC     [SL_AGE]
        LDAA    [SL_AGE]
        CMPA    240
        BNE     sl_tick_cool
        CLR     [SL_AGE]
        INC     [SL_DROP]
sl_tick_cool:
        TST     [SL_COOL]
        BEQ     sl_tick_jam
        DEC     [SL_COOL]
sl_tick_jam:
        TST     [SL_JAM]
        BEQ     sl_tick_heat
        DEC     [SL_JAM]
sl_tick_heat:
        TST     [SL_HEAT]
        BEQ     sl_tick_notice
        LDAA    [SL_TIME]
        LDAB    3
        TST     [SL_JAM]
        BEQ     sl_tick_heat_mask
        LDAB    1
sl_tick_heat_mask:
        STAB    [SL_T]
        ANDA    [SL_T]
        BNE     sl_tick_notice
        DEC     [SL_HEAT]
sl_tick_notice:
        TST     [SL_NOTICE]
        BEQ     sl_tick_shield
        DEC     [SL_NOTICE]
sl_tick_shield:
        TST     [SL_SHIELD]
        BEQ     sl_tick_flash
        DEC     [SL_SHIELD]
sl_tick_flash:
        LDX     SL_B + 32
sl_tick_flash_next:
        TST     [X]
        BEQ     sl_tick_flash_step
        DEC     [X]
sl_tick_flash_step:
        INX
        CPX     SL_B + 56
        BNE     sl_tick_flash_next
        ; move with A / D (not both), then fire: heavy (W) before light
        LDAA    [SL_KEYS]
        ANDA    3
        CMPA    2
        BNE     sl_tick_right
        LDAA    [SL_SHIP]
        CMPA    2
        BCS     sl_tick_fire
        DEC     [SL_SHIP]
        BRA     sl_tick_fire
sl_tick_right:
        CMPA    1
        BNE     sl_tick_fire
        LDAA    [SL_SHIP]
        CMPA    29
        BCC     sl_tick_fire
        INC     [SL_SHIP]
sl_tick_fire:
        TST     [SL_COOL]
        BNE     sl_tick_march
        TST     [SL_JAM]
        BNE     sl_tick_march
        LDAA    [SL_KEYS]
        BITA    4
        BEQ     sl_tick_light
        LDAA    2
        JSR     sl_fire
        BRA     sl_tick_march
sl_tick_light:
        BITA    16
        BEQ     sl_tick_march
        LDAA    1
        JSR     sl_fire
sl_tick_march:
        INC     [SL_MARCH]
        LDAA    [SL_MARCH]
        CMPA    6
        BNE     sl_tick_shots
        CLR     [SL_MARCH]
        LDAA    [SL_SHIFT]
        INCA
        TST     [SL_DIRECTION]
        BNE     sl_tick_shift
        SUBA    2
sl_tick_shift:
        STAA    [SL_SHIFT]
        CMPA    1
        BEQ     sl_tick_turn
        CMPA    9
        BNE     sl_tick_shots
sl_tick_turn:
        LDAA    [SL_DIRECTION]
        EORA    1
        STAA    [SL_DIRECTION]
sl_tick_shots:
        JSR     sl_shots
        TST     [SL_LEFT]
        BEQ     sl_tick_finish
        JSR     sl_attack
        LDAA    [SL_TIME]
        ANDA    1
        BNE     sl_tick_outcome
        JSR     sl_bolts
sl_tick_outcome:
        TST     [SL_HP]
        BNE     sl_tick_fleet
        LDX     sl_txt_hit
        JMP     jr_port_lose
sl_tick_fleet:
        LDAA    [SL_DROP]
        CMPA    6
        BNE     sl_tick_done
        LDX     sl_txt_fleet
        JMP     jr_port_lose
sl_tick_finish:
        ; the last explosion plays out before the jingle
        INC     [SL_FINISH]
        LDAA    [SL_FINISH]
        CMPA    7
        BNE     sl_tick_done
        JMP     jr_port_win
sl_tick_done:
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    SL_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sl_hud
        JSR     jr_gfx_lines
        LDAA    SL_ATTR_STAR
        STAA    [JR_RT_COLOR]
        LDX     sl_stars
        STX     [JR_RT_TABLE]
sl_draw_star:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     sl_draw_fleet
        LDAB    [X + 1]
        INX
        INX
        STX     [JR_RT_TABLE]
        JSR     jr_gfx_at
        LDAA    0x2e
        JSR     jr_gfx_putc
        BRA     sl_draw_star
sl_draw_fleet:
        CLR     [SL_DI]
sl_draw_ship:
        LDX     SL_B
        LDAA    [SL_DI]
        JSR     jr_add_x_a
        TST     [X]
        BEQ     sl_draw_blast
        ; a ship: armored or not, flashing when hit or charging
        LDAA    SL_ATTR_ENEMY
        LDAB    SL_TILE_ENEMY
        PSHA
        LDAA    [X]
        CMPA    2
        PULA
        BCS     sl_draw_ship_kind
        LDAA    SL_ATTR_ARMOR
        LDAB    SL_TILE_ARMOR
sl_draw_ship_kind:
        STAA    [JR_RT_COLOR]
        STAB    [SL_DCODE]
        LDAA    [X + 32]
        ANDA    1
        BNE     sl_draw_ship_flash
        LDAA    [SL_DI]
        CMPA    [SL_TARGET]
        BNE     sl_draw_ship_at
        LDAA    [SL_CHARGE]
        ANDA    3
        CMPA    2
        BCC     sl_draw_ship_at
sl_draw_ship_flash:
        LDAA    SL_ATTR_FLASH
        STAA    [JR_RT_COLOR]
        LDAA    SL_TILE_FLASH
        STAA    [SL_DCODE]
sl_draw_ship_at:
        LDAA    [SL_DI]
        STAA    [SL_I]
        JSR     sl_row_y
        TAB
        LDAA    [SL_DI]
        ANDA    7
        ASLA
        ASLA
        ADDA    [SL_SHIFT]
        BRA     sl_draw_ship_put
sl_draw_blast:
        ; an explosion where a ship was destroyed (phases by the flash count)
        LDAA    [X + 32]
        BEQ     sl_draw_ship_next
        DECA
        LSRA
        STAA    [SL_T]
        LDAA    SL_TILE_BOOM + 8
        SUBA    [SL_T]
        SUBA    [SL_T]
        SUBA    [SL_T]
        SUBA    [SL_T]
        STAA    [SL_DCODE]
        LDAA    SL_ATTR_BOOM
        STAA    [JR_RT_COLOR]
        LDAA    [X + 64]
        LDAB    [X + 96]
sl_draw_ship_put:
        JSR     jr_gfx_at
        LDAA    [SL_DCODE]
        JSR     jr_gfx_tile
sl_draw_ship_next:
        INC     [SL_DI]
        LDAA    [SL_DI]
        CMPA    24
        BEQ     sl_draw_ship_near834
        JMP     sl_draw_ship
sl_draw_ship_near834:
        ; the lance (blinking while shielded)
        LDAA    [SL_SHIELD]
        ANDA    1
        BNE     sl_draw_shots
        LDAA    SL_ATTR_SHIP
        TST     [SL_FLASH]
        BEQ     sl_draw_lance
        LDAA    SL_ATTR_HIT
sl_draw_lance:
        STAA    [JR_RT_COLOR]
        LDAA    [SL_SHIP]
        LDAB    20
        JSR     jr_gfx_at
        LDAA    SL_TILE_SHIP
        JSR     jr_gfx_tile
sl_draw_shots:
        LDAA    SL_ATTR_SHOT
        STAA    [JR_RT_COLOR]
        LDX     SL_D
sl_draw_shot:
        LDAA    [X]
        BEQ     sl_draw_shot_next
        STX     [JR_RT_TABLE]
        LDAB    SL_CHAR_LIGHT
        LDAA    [X + 16]
        CMPA    1
        BEQ     sl_draw_shot_char
        LDAB    SL_CHAR_HEAVY
sl_draw_shot_char:
        STAB    [SL_DCODE]
        LDAB    [X]
        LDAA    [X + 8]
        JSR     jr_gfx_at
        LDAA    [SL_DCODE]
        JSR     jr_gfx_putc
        LDX     [JR_RT_TABLE]
sl_draw_shot_next:
        INX
        CPX     SL_D + 3
        BNE     sl_draw_shot
        LDAA    SL_ATTR_BOLT
        STAA    [JR_RT_COLOR]
        LDX     SL_C
sl_draw_bolt:
        LDAB    [X]
        BEQ     sl_draw_bolt_next
        STX     [JR_RT_TABLE]
        LDAA    [X + 8]
        JSR     jr_gfx_at
        LDAA    [SL_TIME]
        ANDA    1
        ADDA    SL_CHAR_BOLT
        JSR     jr_gfx_putc
        LDX     [JR_RT_TABLE]
sl_draw_bolt_next:
        INX
        CPX     SL_C + 6
        BNE     sl_draw_bolt
        ; the panel: hull, enemies left, heat and the weapon notice
        LDAA    SL_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        ADDA    0x31
        JSR     jr_gfx_putc
        LDAA    6
        LDAB    22
        JSR     jr_gfx_at
        LDAB    [SL_HP]
        BEQ     sl_draw_enemies
sl_draw_hull:
        LDAA    0x2a
        JSR     jr_gfx_putc
        DECB
        BNE     sl_draw_hull
sl_draw_enemies:
        LDAA    18
        LDAB    22
        JSR     jr_gfx_at
        LDAA    [SL_LEFT]
        JSR     jr_gfx_dec2
        LDAA    SL_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    7
        LDAB    23
        JSR     jr_gfx_at
        LDAB    [SL_HEAT]
        BEQ     sl_draw_notice
sl_draw_heat:
        LDAA    0x2a
        JSR     jr_gfx_putc
        DECB
        BNE     sl_draw_heat
sl_draw_notice:
        LDAA    22
        LDAB    23
        JSR     jr_gfx_at
        LDX     sl_txt_cooling
        TST     [SL_JAM]
        BNE     sl_draw_notice_text
        LDX     sl_txt_cool
        TST     [SL_NOTICE]
        BNE     sl_draw_notice_text
        LDX     sl_txt_hull_hit
        TST     [SL_SHIELD]
        BEQ     sl_draw_demo
sl_draw_notice_text:
        JSR     jr_gfx_text
sl_draw_demo:
        TST     [JR_TEST_DEMO]
        BEQ     sl_draw_done
        LDAA    SL_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    14
        CLRB
        JSR     jr_gfx_at
        LDX     sl_txt_demo
        JSR     jr_gfx_text
sl_draw_done:
        RTS

game_draw_title:
        LDX     sl_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    SL_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sl_title_tiles
        STX     [JR_RT_TABLE]
sl_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     sl_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [SL_DCODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [SL_DCODE]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     sl_title_tile
sl_title_text:
        LDX     sl_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    SL_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sl_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

sl_sounds:
        .dw     sl_sfx_shot, sl_sfx_hit, sl_sfx_heavy, sl_sfx_hot, sl_sfx_cool, sl_sfx_warning

; x, y of the background stars
sl_stars:
        .db     2, 4, 30, 6, 7, 11, 27, 13, 1, 17, 22, 17, 12, 15, 31, 19, 0xff

; x, attribute, code, y
sl_title_tiles:
        .db     6, SL_ATTR_ARMOR, SL_TILE_ARMOR, 2
        .db     10, SL_ATTR_ENEMY, SL_TILE_ENEMY, 2
        .db     14, SL_ATTR_FLASH, SL_TILE_FLASH, 2
        .db     18, SL_ATTR_ENEMY, SL_TILE_ENEMY, 2
        .db     22, SL_ATTR_ARMOR, SL_TILE_ARMOR, 2
        .db     15, SL_ATTR_SHIP, SL_TILE_SHIP, 5
        .db     0xff

sl_hud:
        .db     0, 0, SL_ATTR_TITLE
        .dw     sl_txt_name
        .db     24, 0, SL_ATTR_LABEL
        .dw     sl_txt_wave
        .db     1, 22, SL_ATTR_LABEL
        .dw     sl_txt_counts
        .db     1, 23, SL_ATTR_LABEL
        .dw     sl_txt_heat
        .db     0xff
sl_title_lines:
        .db     11, 8, SL_ATTR_TITLE
        .dw     sl_txt_name
        .db     0, 10, SL_ATTR_LABEL
        .dw     sl_txt_tagline
        .db     4, 13, SL_ATTR_TEXT
        .dw     sl_txt_start
        .db     4, 15, SL_ATTR_TEXT
        .dw     sl_txt_howto
        .db     4, 17, SL_ATTR_DIM
        .dw     sl_txt_demo_hint
        .db     4, 19, SL_ATTR_DIM
        .dw     sl_txt_credit
        .db     0xff
sl_help_lines:
        .db     11, 1, SL_ATTR_TITLE
        .dw     sl_txt_name
        .db     1, 3, SL_ATTR_TEXT
        .dw     sl_help_1
        .db     1, 5, SL_ATTR_TEXT
        .dw     sl_help_2
        .db     1, 7, SL_ATTR_TEXT
        .dw     sl_help_3
        .db     1, 9, SL_ATTR_TEXT
        .dw     sl_help_4
        .db     1, 11, SL_ATTR_TEXT
        .dw     sl_help_5
        .db     1, 13, SL_ATTR_TEXT
        .dw     sl_help_6
        .db     1, 15, SL_ATTR_TEXT
        .dw     sl_help_7
        .db     1, 17, SL_ATTR_TEXT
        .dw     sl_help_8
        .db     1, 21, SL_ATTR_LABEL
        .dw     sl_help_back
        .db     0xff

sl_txt_name:
        .db     "STAR LANCE", 0
sl_txt_wave:
        .db     "WAVE", 0
sl_txt_counts:
        .db     "HULL     ENEMIES", 0
sl_txt_heat:
        .db     "HEAT [            ]", 0
sl_txt_cooling:
        .db     "COOLING", 0
sl_txt_cool:
        .db     "COOL +4", 0
sl_txt_hull_hit:
        .db     "HIT", 0
sl_txt_demo:
        .db     "DEMO", 0
sl_txt_hit:
        .db     "HIT BY ENEMY SHOT", 0
sl_txt_fleet:
        .db     "THE FLEET BROKE THROUGH", 0
sl_txt_tagline:
        .db     "AIM, FIRE, KEEP YOUR LANCE COOL", 0
sl_txt_start:
        .db     "RETURN : START", 0
sl_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
sl_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
sl_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
sl_help_1:
        .db     "A/D: HOLD TO MOVE", 0
sl_help_2:
        .db     "RETURN : FIRE / W : HEAVY SHOT", 0
sl_help_3:
        .db     "DAMAGE/HEAT: SHOT 1/3 HEAVY 2/5", 0
sl_help_4:
        .db     "FULL HEAT LOCKS YOUR WEAPONS.", 0
sl_help_5:
        .db     "FLASHING ENEMY : ABOUT TO FIRE", 0
sl_help_6:
        .db     "STOP ITS SHOT : COOL FOUR HEAT", 0
sl_help_7:
        .db     "3 HULL / 18 SHIPS / SIX WAVES", 0
sl_help_8:
        .db     "SPACE : RETRY THE WAVE", 0
sl_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     sl_sfx_shot, sl_sfx_hit, sl_jingle_win, sl_jingle_lose
sl_sfx_shot:
        .db     30, 1, 40, 1, 0, 0
sl_sfx_hit:
        .db     90, 1, 70, 1, 50, 2, 0, 0
sl_sfx_heavy:
        .db     60, 2, 80, 2, 100, 2, 0, 0
sl_sfx_hot:
        .db     200, 3, 0, 1, 200, 3, 0, 1, 200, 3, 0, 0
sl_sfx_cool:
        .db     40, 2, 32, 2, 26, 2, 20, 6, 0, 0
sl_sfx_warning:
        .db     120, 2, 100, 2, 0, 0

; Title: a heroic space march in B-flat major, eighth note = 8 frames, looping.
sl_title_song:
        .db     1
        .dw     sl_title_melody, sl_title_harmony, sl_title_bass
sl_title_melody:
        .db     AU_F4, 8, AU_AS4, 8, AU_D5, 8, AU_F5, 8, AU_AS5, 16, AU_A5, 8, AU_G5, 8
        .db     AU_F5, 16, AU_DS5, 8, AU_D5, 8, AU_C5, 32
        .db     AU_F4, 8, AU_A4, 8, AU_C5, 8, AU_F5, 8, AU_A5, 16, AU_G5, 8, AU_F5, 8
        .db     AU_DS5, 16, AU_D5, 8, AU_C5, 8, AU_AS4, 32, 0, 0
sl_title_harmony:
        .db     AU_D4, 32, AU_F4, 32, AU_G4, 32, AU_A4, 32
        .db     AU_C4, 32, AU_F4, 32, AU_A4, 32, AU_D4, 32, 0, 0
sl_title_bass:
        .db     AU_AS2, 16, AU_F2, 16, AU_AS2, 16, AU_D3, 16, AU_DS3, 16, AU_C3, 16, AU_F2, 32
        .db     AU_F2, 16, AU_C3, 16, AU_F2, 16, AU_A2, 16, AU_DS3, 16, AU_F2, 16, AU_AS2, 32, 0, 0

; Wave cleared: B-flat major fanfare.
sl_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     sl_win_melody, sl_win_harmony, sl_win_bass
sl_win_melody:
        .db     AU_F4, 6, AU_AS4, 6, AU_D5, 6, AU_F5, 12, AU_AS5, 30, 0, 0
sl_win_harmony:
        .db     AU_D4, 12, AU_F4, 18, AU_D5, 30, 0, 0
sl_win_bass:
        .db     AU_AS2, 12, AU_F2, 18, AU_AS2, 30, 0, 0
sl_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     sl_lose_melody, sl_lose_harmony, sl_lose_bass
sl_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
sl_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
sl_lose_bass:
        .db     AU_FS3, 36, AU_CS3, 30, 0, 0


        .include "selftest.inc"
        .include "art.inc"
        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys.inc"
        .include "../../../sdk/keyscan.inc"
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
