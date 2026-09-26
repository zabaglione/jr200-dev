; SPDX-License-Identifier: MIT
; QUIET ROUTE for JR-200, based on jr100dev games/quiet_route/rules.py 2.0.0.
        .filename.jr "QUIET-ROUTE"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ 0x3000
JR_SAVE:            .equ 0x3600
JR_RT:              .equ 0x4600
GAME_STATE:         .equ 0x4640
GAME_STATE_END:     .equ 0x4700
JR_STACK_TOP:       .equ 0x4fff
GAME_LEVELS:        .equ 6
GAME_RATE:          .equ 0
GAME_SPACE_RESET:   .equ 1
GAME_STATUS_ROW:    .equ 21
GAME_STATUS_ATTR:   .equ 0x06
GAME_RENDER_FRAMES: .equ 2

QR_BOARD:           .equ GAME_STATE
QR_POS:             .equ GAME_STATE+64
QR_ORIGIN:          .equ GAME_STATE+65
QR_GUARD:           .equ GAME_STATE+66
QR_GUARD_ORIGIN:    .equ GAME_STATE+67
QR_GUARD_FACE:      .equ GAME_STATE+68
QR_DIRECTION:       .equ GAME_STATE+69
QR_BATTERY:         .equ GAME_STATE+70
QR_CACHE:           .equ GAME_STATE+71
QR_QUIET:           .equ GAME_STATE+72
QR_KEY:             .equ GAME_STATE+73
QR_INTEL:           .equ GAME_STATE+74
QR_ALERT:           .equ GAME_STATE+75
QR_FACING:          .equ GAME_STATE+76
QR_ACTION:          .equ GAME_STATE+77
QR_NEXT:            .equ GAME_STATE+78
QR_COST:            .equ GAME_STATE+79
QR_I:               .equ GAME_STATE+80
QR_HOLE_1:          .equ GAME_STATE+81
QR_HOLE_2:          .equ GAME_STATE+82
QR_STEP_POS:        .equ GAME_STATE+83
QR_STEP_ACTION:     .equ GAME_STATE+84
QR_PY:              .equ GAME_STATE+85
QR_PX:              .equ GAME_STATE+86
QR_GY:              .equ GAME_STATE+87
QR_GX:              .equ GAME_STATE+88
QR_DIST:            .equ GAME_STATE+89
QR_DRAW_I:          .equ GAME_STATE+90
QR_DRAW_X:          .equ GAME_STATE+91
QR_DRAW_Y:          .equ GAME_STATE+92
QR_DRAW_COLOR:      .equ GAME_STATE+93

        .org 0x1000
start:
        JSR jr_session_enter
        JSR jr_font_install
        JMP jr_port_run

game_init:
        LDAA 9
        STAA [QR_POS]
        STAA [QR_ORIGIN]
        LDAA [JR_PORT_LEVEL]
        ADDA 49
        STAA [QR_GUARD]
        STAA [QR_GUARD_ORIGIN]
        LDAA 4
        STAA [QR_DIRECTION]
        STAA [QR_GUARD_FACE]
        LDAA 2
        STAA [QR_FACING]
        LDAA [JR_PORT_LEVEL]
        ASLA
        STAA [QR_COST]
        LDAA 42
        SUBA [QR_COST]
        STAA [QR_BATTERY]
        LDAA [JR_PORT_LEVEL]
        ADDA 33
        STAA [QR_CACHE]
        ; Corridor openings: (1+2*level)%6 and (4+level)%6.
        LDAA [JR_PORT_LEVEL]
        ASLA
        INCA
        LDAB 6
        JSR jr_divmod8
        STAB [QR_HOLE_1]
        LDAA [JR_PORT_LEVEL]
        ADDA 4
        LDAB 6
        JSR jr_divmod8
        STAB [QR_HOLE_2]
        CLR [QR_I]
qr_init_box:
        LDAA [QR_I]
        LDAB 8
        JSR jr_divmod8
        TSTA
        BEQ qr_init_wall
        CMPA 7
        BEQ qr_init_wall
        TSTB
        BEQ qr_init_wall
        CMPB 7
        BEQ qr_init_wall
        CLRA
        BRA qr_init_store
qr_init_wall:
        LDAA 1
qr_init_store:
        STAA [QR_NEXT]
        LDX QR_BOARD
        LDAA [QR_I]
        JSR jr_add_x_a
        LDAA [QR_NEXT]
        STAA [X]
        INC [QR_I]
        LDAA [QR_I]
        CMPA 64
        BCS qr_init_box
        CLR [QR_I]
qr_init_corridors:
        LDAA [QR_I]
        CMPA [QR_HOLE_1]
        BEQ qr_init_first_gap
        LDAA 1
        BRA qr_init_first_store
qr_init_first_gap:
        CLRA
qr_init_first_store:
        STAA [QR_NEXT]
        LDX QR_BOARD+25
        LDAA [QR_I]
        JSR jr_add_x_a
        LDAA [QR_NEXT]
        STAA [X]
        LDAA [QR_I]
        CMPA [QR_HOLE_2]
        BEQ qr_init_second_gap
        LDAA 1
        BRA qr_init_second_store
qr_init_second_gap:
        CLRA
qr_init_second_store:
        STAA [QR_NEXT]
        LDX QR_BOARD+41
        LDAA [QR_I]
        JSR jr_add_x_a
        LDAA [QR_NEXT]
        STAA [X]
        INC [QR_I]
        LDAA [QR_I]
        CMPA 6
        BCS qr_init_corridors
        LDAA 3
        STAA [QR_BOARD+14]
        LDAA 6
        STAA [QR_BOARD+54]
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CMPA JR_KEY_CONFIRM
        BNE qr_direction_action
        LDAA [QR_QUIET]
        EORA 1
        STAA [QR_QUIET]
        LDAA 1
        JMP jr_port_sound
qr_direction_action:
        CMPA JR_KEY_CONFIRM
        BCS qr_action_move
        RTS
qr_action_move:
        STAA [QR_ACTION]
        STAA [QR_FACING]
        LDAA [QR_POS]
        STAA [QR_STEP_POS]
        LDAA [QR_ACTION]
        STAA [QR_STEP_ACTION]
        JSR qr_step
        STAA [QR_NEXT]
        LDX QR_BOARD
        JSR jr_add_x_a
        LDAA [X]
        CMPA 1
        BNE qr_action_open
        RTS
qr_action_open:
        LDAA [QR_POS]
        STAA [QR_ORIGIN]
        LDAA [QR_NEXT]
        STAA [QR_POS]
        LDAA 1
        TST [QR_QUIET]
        BEQ qr_set_cost
        INCA
qr_set_cost:
        STAA [QR_COST]
        LDAA [QR_BATTERY]
        CMPA [QR_COST]
        BHI qr_battery_ok
        LDAA [QR_POS]
        STAA [QR_ORIGIN]
        LDX qr_txt_battery_loss
        JMP jr_port_lose
qr_battery_ok:
        SUBA [QR_COST]
        STAA [QR_BATTERY]
        LDAA [QR_POS]
        CMPA 14
        BNE qr_check_cache
        TST [QR_KEY]
        BNE qr_check_cache
        LDAA 1
        STAA [QR_KEY]
        JSR jr_port_sound
qr_check_cache:
        LDAA [QR_POS]
        CMPA [QR_CACHE]
        BNE qr_check_exit
        LDAA 255
        STAA [QR_CACHE]
        LDAA 1
        STAA [QR_INTEL]
        LDAA [QR_BATTERY]
        ADDA 6
        CMPA 50
        BLS qr_cache_battery
        LDAA 50
qr_cache_battery:
        STAA [QR_BATTERY]
        LDAA 1
        JSR jr_port_sound
qr_check_exit:
        LDAA [QR_POS]
        CMPA 54
        BNE qr_guard_response
        TST [QR_KEY]
        BEQ qr_guard_response
        LDAA [QR_POS]
        STAA [QR_ORIGIN]
        JMP jr_port_win
qr_guard_response:
        JSR qr_distance
        LDAA 5
        TST [QR_QUIET]
        BEQ qr_alert_limit
        LDAA 2
qr_alert_limit:
        CMPA [QR_DIST]
        BHI qr_alert_on
        CLR [QR_ALERT]
        BRA qr_guard_choose
qr_alert_on:
        LDAA 1
        STAA [QR_ALERT]
qr_guard_choose:
        TST [QR_ALERT]
        BEQ qr_patrol
        LDAA [QR_GY]
        CMPA [QR_PY]
        BHI qr_guard_up
        BCS qr_guard_down
        LDAA [QR_GX]
        CMPA [QR_PX]
        BHI qr_guard_left
        BRA qr_guard_right
qr_guard_up:
        LDAA 1
        BRA qr_guard_step
qr_guard_down:
        LDAA 2
        BRA qr_guard_step
qr_guard_left:
        LDAA 3
        BRA qr_guard_step
qr_guard_right:
        LDAA 4
        BRA qr_guard_step
qr_patrol:
        LDAA [QR_GUARD]
        CMPA 49
        BNE qr_patrol_right_end
        LDAA 4
        STAA [QR_DIRECTION]
qr_patrol_right_end:
        LDAA [QR_GUARD]
        CMPA 54
        BNE qr_patrol_use
        LDAA 3
        STAA [QR_DIRECTION]
qr_patrol_use:
        LDAA [QR_DIRECTION]
qr_guard_step:
        STAA [QR_GUARD_FACE]
        STAA [QR_STEP_ACTION]
        LDAA [QR_GUARD]
        STAA [QR_STEP_POS]
        JSR qr_step
        STAA [QR_NEXT]
        LDX QR_BOARD
        JSR jr_add_x_a
        LDAA [X]
        CMPA 1
        BEQ qr_guard_collision
        LDAA [QR_GUARD]
        STAA [QR_GUARD_ORIGIN]
        LDAA [QR_NEXT]
        STAA [QR_GUARD]
qr_guard_collision:
        LDAA [QR_POS]
        STAA [QR_ORIGIN]
        LDAA [QR_GUARD]
        STAA [QR_GUARD_ORIGIN]
        CMPA [QR_POS]
        BNE qr_move_effect
        LDX qr_txt_guard_loss
        JMP jr_port_lose
qr_move_effect:
        CLRA
        JSR jr_port_sound
        LDAA 4
        JMP jr_port_animate
qr_action_done:
        RTS

qr_step:
        LDAA [QR_STEP_ACTION]
        CMPA 1
        BNE qr_step_down
        LDAA [QR_STEP_POS]
        CMPA 8
        BCS qr_step_same
        SUBA 8
        RTS
qr_step_down:
        CMPA 2
        BNE qr_step_left
        LDAA [QR_STEP_POS]
        CMPA 56
        BCC qr_step_same
        ADDA 8
        RTS
qr_step_left:
        CMPA 3
        BNE qr_step_right
        LDAA [QR_STEP_POS]
        ANDA 7
        BEQ qr_step_same
        LDAA [QR_STEP_POS]
        DECA
        RTS
qr_step_right:
        LDAA [QR_STEP_POS]
        ANDA 7
        CMPA 7
        BEQ qr_step_same
        LDAA [QR_STEP_POS]
        INCA
        RTS
qr_step_same:
        LDAA [QR_STEP_POS]
        RTS

; Manhattan distance. The row/column values also drive guard pursuit.
qr_distance:
        LDAA [QR_POS]
        LDAB 8
        JSR jr_divmod8
        STAA [QR_PY]
        STAB [QR_PX]
        LDAA [QR_GUARD]
        LDAB 8
        JSR jr_divmod8
        STAA [QR_GY]
        STAB [QR_GX]
        LDAA [QR_PY]
        CMPA [QR_GY]
        BCC qr_dist_row
        LDAA [QR_GY]
        SUBA [QR_PY]
        BRA qr_dist_col_start
qr_dist_row:
        SUBA [QR_GY]
qr_dist_col_start:
        STAA [QR_DIST]
        LDAA [QR_PX]
        CMPA [QR_GX]
        BCC qr_dist_col
        LDAA [QR_GX]
        SUBA [QR_PX]
        BRA qr_dist_end
qr_dist_col:
        SUBA [QR_GX]
qr_dist_end:
        ADDA [QR_DIST]
        STAA [QR_DIST]
        RTS

game_draw:
        LDAA 0x20
        LDAB 0x07
        JSR jr_gfx_fill
        LDX qr_hud_lines
        JSR jr_gfx_lines
        LDAA 0x06
        STAA [JR_RT_COLOR]
        LDAA 9
        LDAB 1
        JSR jr_gfx_at
        LDAA [JR_PORT_LEVEL]
        ADDA 0x31
        JSR jr_gfx_putc
        CLR [QR_DRAW_I]
qr_draw_loop:
        LDAA [QR_DRAW_I]
        LDAB 8
        JSR jr_divmod8
        ASLA
        ADDA 3
        STAA [QR_DRAW_Y]
        TBA
        ASLA
        ADDA 3
        STAA [QR_DRAW_X]
        LDAA [QR_DRAW_I]
        LDX QR_BOARD
        JSR jr_add_x_a
        LDAA [X]
        LDX qr_tile_floor
        LDAB 0x07
        CMPA 1
        BNE qr_draw_file
        LDX qr_tile_wall
        LDAB 0x01
        BRA qr_draw_overlay
qr_draw_file:
        CMPA 3
        BNE qr_draw_exit
        TST [QR_KEY]
        BNE qr_draw_overlay
        LDX qr_tile_file
        LDAB 0x06
        BRA qr_draw_overlay
qr_draw_exit:
        CMPA 6
        BNE qr_draw_overlay
        LDX qr_tile_exit
        LDAB 0x04
qr_draw_overlay:
        STAB [QR_DRAW_COLOR]
        LDAA [QR_DRAW_I]
        CMPA [QR_CACHE]
        BNE qr_draw_guard
        LDX qr_tile_cache
        LDAA 0x05
        STAA [QR_DRAW_COLOR]
qr_draw_guard:
        LDAA [QR_DRAW_I]
        CMPA [QR_GUARD]
        BNE qr_draw_player
        LDX qr_tile_guard
        LDAA 0x02
        STAA [QR_DRAW_COLOR]
qr_draw_player:
        LDAA [QR_DRAW_I]
        CMPA [QR_POS]
        BNE qr_draw_tile
        LDX qr_tile_player
        LDAA 0x03
        STAA [QR_DRAW_COLOR]
qr_draw_tile:
        STX [JR_RT_TABLE]
        LDAA [QR_DRAW_COLOR]
        STAA [JR_RT_COLOR]
        LDAA [QR_DRAW_X]
        LDAB [QR_DRAW_Y]
        JSR jr_gfx_at
        LDX [JR_RT_TABLE]
        JSR jr_gfx_text
        INC [QR_DRAW_I]
        LDAA [QR_DRAW_I]
        CMPA 64
        BCC qr_draw_hud
        JMP qr_draw_loop
qr_draw_hud:
        LDAA 0x06
        STAA [JR_RT_COLOR]
        LDAA 25
        LDAB 4
        JSR jr_gfx_at
        LDAA [QR_BATTERY]
        JSR jr_gfx_dec3
        LDAA 21
        LDAB 10
        JSR jr_gfx_at
        TST [QR_QUIET]
        BEQ qr_draw_normal
        LDX qr_txt_quiet
        BRA qr_draw_walk
qr_draw_normal:
        LDX qr_txt_normal
qr_draw_walk:
        JSR jr_gfx_text
        LDAA 21
        LDAB 14
        JSR jr_gfx_at
        TST [QR_KEY]
        BEQ qr_draw_no_file
        LDX qr_txt_taken
        BRA qr_draw_file_state
qr_draw_no_file:
        LDX qr_txt_get_file
qr_draw_file_state:
        JSR jr_gfx_text
        LDAA 21
        LDAB 18
        JSR jr_gfx_at
        TST [QR_INTEL]
        BEQ qr_draw_no_intel
        LDX qr_txt_intel_yes
        BRA qr_draw_intel
qr_draw_no_intel:
        LDX qr_txt_intel_no
qr_draw_intel:
        JSR jr_gfx_text
        LDAA [JR_PORT_MODE]
        CMPA JR_MODE_CLEAR
        BEQ qr_draw_result
        CMPA JR_MODE_END
        BEQ qr_draw_result
        TST [QR_ALERT]
        BEQ qr_draw_done
        LDAA 20
        LDAB 19
        JSR jr_gfx_at
        LDX qr_txt_alert
        JSR jr_gfx_text
        BRA qr_draw_done
qr_draw_result:
        LDAA 20
        LDAB 19
        JSR jr_gfx_at
        LDX qr_txt_escaped
        TST [QR_INTEL]
        BEQ qr_draw_result_text
        LDX qr_txt_all_intel
qr_draw_result_text:
        JSR jr_gfx_text
qr_draw_done:
        RTS

game_draw_title:
        LDAA 0x20
        LDAB 0x07
        JSR jr_gfx_fill
        LDX qr_title_lines
        JMP jr_gfx_lines
game_draw_help:
        LDAA 0x20
        LDAB 0x07
        JSR jr_gfx_fill
        LDX qr_help_lines
        JMP jr_gfx_lines

qr_tile_floor:      .db ". ",0
qr_tile_wall:       .db "##",0
qr_tile_file:       .db "F!",0
qr_tile_exit:       .db "EX",0
qr_tile_cache:      .db "B+",0
qr_tile_guard:      .db "GG",0
qr_tile_player:     .db "PP",0
qr_hud_lines:
        .db 9,0,0x06
        .dw qr_txt_name
        .db 3,1,0x04
        .dw qr_txt_route_label
        .db 3,2,0x04
        .dw qr_txt_route
        .db 20,4,0x04
        .dw qr_txt_battery
        .db 20,8,0x04
        .dw qr_txt_walk
        .db 20,12,0x04
        .dw qr_txt_file
        .db 20,16,0x04
        .dw qr_txt_intel
        .db 1,22,0x07
        .dw qr_txt_bottom
        .db 0xff
qr_title_lines:
        .db 9,3,0x06
        .dw qr_txt_name
        .db 7,7,0x03
        .dw qr_txt_mission
        .db 4,11,0x04
        .dw qr_txt_six
        .db 8,16,0x07
        .dw qr_txt_start
        .db 4,19,0x07
        .dw qr_txt_howto
        .db 3,22,0x04
        .dw qr_txt_credit
        .db 0xff
qr_help_lines:
        .db 9,2,0x06
        .dw qr_txt_name
        .db 3,5,0x07
        .dw qr_help_1
        .db 3,8,0x07
        .dw qr_help_2
        .db 3,11,0x07
        .dw qr_help_3
        .db 3,14,0x07
        .dw qr_help_4
        .db 3,17,0x07
        .dw qr_help_5
        .db 3,20,0x07
        .dw qr_help_6
        .db 5,22,0x04
        .dw qr_help_back
        .db 0xff
qr_txt_name:        .db "QUIET ROUTE",0
qr_txt_mission:     .db "FIND FILE - REACH EXIT",0
qr_txt_six:         .db "SIX ROUTES. ONE GUARD.",0
qr_txt_start:       .db "RETURN : START",0
qr_txt_howto:       .db "W/A/S/D : HOW TO PLAY",0
qr_txt_credit:      .db "JR-200 PORT OF JR100DEV",0
qr_txt_route:       .db "F!:FILE  B+:CACHE  EX:EXIT",0
qr_txt_route_label: .db "ROUTE",0
qr_txt_battery:     .db "BATTERY",0
qr_txt_walk:        .db "WALK",0
qr_txt_file:        .db "FILE",0
qr_txt_intel:       .db "INTEL",0
qr_txt_bottom:      .db "SPACE:RESTART  CTRL+C:BASIC",0
qr_txt_quiet:       .db "SILENT",0
qr_txt_normal:      .db "NORMAL",0
qr_txt_taken:       .db "TAKEN",0
qr_txt_get_file:    .db "GET FILE",0
qr_txt_intel_yes:   .db "FOUND",0
qr_txt_intel_no:    .db "NONE",0
qr_txt_alert:       .db "HEARD",0
qr_txt_escaped:     .db "ESCAPED",0
qr_txt_all_intel:   .db "ALL INTEL",0
qr_txt_battery_loss:.db "BATTERY EXHAUSTED",0
qr_txt_guard_loss:  .db "CAUGHT BY THE GUARD",0
qr_help_1:          .db "WASD : MOVE ONE STEP",0
qr_help_2:          .db "RETURN: TOGGLE QUIET WALK",0
qr_help_3:          .db "NORMAL:1 POWER, NOISE <5",0
qr_help_4:          .db "SILENT:2 POWER, NOISE <2",0
qr_help_5:          .db "FIND F! THEN REACH EX",0
qr_help_6:          .db "B+ GIVES INTEL AND POWER",0
qr_help_back:       .db "ANY KEY : TITLE",0

game_sfx_table:
        .dw qr_sfx_step,qr_sfx_use,qr_sfx_win,qr_sfx_lose
qr_sfx_step:        .db 130,2,0,0
qr_sfx_use:         .db 100,3,80,3,0,0
qr_sfx_win:         .db 104,5,88,5,72,5,52,12,0,0
qr_sfx_lose:        .db 120,7,170,7,215,16,0,0

        .include "../../../sdk/session.inc"
        .include "../../../sdk/keys.inc"
        .include "../../../sdk/gfx.inc"
        .include "../../../sdk/font.inc"
        .include "../../../sdk/frame.inc"
        .include "../../../sdk/math.inc"
        .include "../../../sdk/sound.inc"
        .include "../../../sdk/sfx.inc"
        .include "../../../sdk/port.inc"
        .include "../../../sdk/font_data.inc"
