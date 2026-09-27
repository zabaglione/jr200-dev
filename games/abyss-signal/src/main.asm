; SPDX-License-Identifier: MIT
; ABYSS SIGNAL for JR-200: a port of jr100dev games/abyss_signal 1.6.1.
; The 32x32 sea, rocks, the four currents, oxygen and hull, the sonar that
; widens the view for six actions and draws the hunter, quiet running, the
; hunter's patrol and pursuit, records from an adjacent cell and the return
; to base follow the upstream model.py and M6800 source (see
; tests/model.py); the control panel, discovery photos and questions
; follow upstream src/main.asm. Display, colour and three-voice sound use
; the JR-200 port SDK.
        .filename.jr "ABYSS-SIGNAL"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x46a0
JR_AUDIO:           .equ    0x46c0
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    1
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    0       ; SPACE opens the panel, as upstream
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    3

; Upstream state (same order as tests/model.py LAYOUT).
AS_X:               .equ    GAME_STATE
AS_Y:               .equ    GAME_STATE + 1
AS_OXYGEN:          .equ    GAME_STATE + 2
AS_HULL:            .equ    GAME_STATE + 3
AS_FLAGS:           .equ    GAME_STATE + 4
AS_SIGHT:           .equ    GAME_STATE + 5
AS_NOISE:           .equ    GAME_STATE + 6
AS_QUIET:           .equ    GAME_STATE + 7
AS_TURN:            .equ    GAME_STATE + 8
AS_HX:              .equ    GAME_STATE + 9
AS_HY:              .equ    GAME_STATE + 10
AS_GRACE:           .equ    GAME_STATE + 11
AS_SAMPLES:         .equ    GAME_STATE + 12
AS_SUB:             .equ    GAME_STATE + 13     ; 0 sea, 1 panel, 2 photo, 3/4 question
AS_MENU:            .equ    GAME_STATE + 14
AS_CHOICE:          .equ    GAME_STATE + 15
AS_PHOTO:           .equ    GAME_STATE + 16
AS_STATUS:          .equ    GAME_STATE + 17
; Rule work bytes.
AS_K:               .equ    GAME_STATE + 24
AS_CX:              .equ    GAME_STATE + 25
AS_CY:              .equ    GAME_STATE + 26
AS_TX:              .equ    GAME_STATE + 27
AS_TY:              .equ    GAME_STATE + 28
AS_I:               .equ    GAME_STATE + 29
AS_SWEEP:           .equ    GAME_STATE + 30     ; sonar sweep column
; Drawing work bytes (game_draw runs inside effects: never shared with rules).
AS_VX:              .equ    GAME_STATE + 40
AS_VY:              .equ    GAME_STATE + 41
AS_RAD:             .equ    GAME_STATE + 42
AS_DC:              .equ    GAME_STATE + 43
AS_DR:              .equ    GAME_STATE + 44
AS_WX:              .equ    GAME_STATE + 45
AS_WY:              .equ    GAME_STATE + 46
AS_DCODE:           .equ    GAME_STATE + 47
AS_DATTR:           .equ    GAME_STATE + 48
AS_LETTER:          .equ    GAME_STATE + 49
AS_DPTR:            .equ    GAME_STATE + 50     ; 2 bytes
AS_DI:              .equ    GAME_STATE + 52
AS_TGX:             .equ    GAME_STATE + 53
AS_TGY:             .equ    GAME_STATE + 54
AS_TGI:             .equ    GAME_STATE + 55

AS_SUB_SEA:         .equ    0
AS_SUB_PANEL:       .equ    1
AS_SUB_PHOTO:       .equ    2
AS_SUB_RESTART:     .equ    3
AS_SUB_TITLE:       .equ    4

AS_TILE_SUB:        .equ    0x80
AS_TILE_ROCK:       .equ    0x84
AS_TILE_SITE:       .equ    0x88
AS_TILE_HUNTER:     .equ    0x8c
AS_TILE_FOG:        .equ    0x90
AS_TILE_CURRENT:    .equ    0x94
AS_CHAR_BAR:        .equ    0x98
AS_CHAR_HULL:       .equ    0x99
AS_CHAR_DIVIDER:    .equ    0x9a
AS_CHAR_RULE:       .equ    0x9b
AS_CHAR_SWEEP:      .equ    0x9c
AS_TILE_SEABED:     .equ    0x00    ; discovery scenes, second PCG bank
AS_TILE_KELP:       .equ    0x04
AS_TILE_MAST:       .equ    0x08
AS_TILE_ARCH:       .equ    0x0c
AS_TILE_CRYSTAL:    .equ    0x10
AS_TILE_DISH:       .equ    0x14
AS_TILE_ORB:        .equ    0x18
AS_TILE_FISH:       .equ    0x1c
AS_ATTR_SUB:        .equ    0x46
AS_ATTR_ROCK:       .equ    0x41
AS_ATTR_SITE:       .equ    0x45
AS_ATTR_BASE:       .equ    0x44
AS_ATTR_HUNTER:     .equ    0x42
AS_ATTR_FOG:        .equ    0x41
AS_ATTR_CURRENT:    .equ    0x45
AS_ATTR_BAR:        .equ    0x45
AS_ATTR_LOW:        .equ    0x42
AS_ATTR_HULL:       .equ    0x46
AS_ATTR_RULE:       .equ    0x41
AS_ATTR_SWEEP:      .equ    0x46
AS_ATTR_TEXT:       .equ    0x07
AS_ATTR_LABEL:      .equ    0x04
AS_ATTR_TITLE:      .equ    0x06
AS_ATTR_DIM:        .equ    0x05
AS_ATTR_WARN:       .equ    0x02
AS_ATTR_PICK:       .equ    0x06

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     as_patterns
        LDAA    AS_TILE_SUB
        LDAB    29
        JSR     jr_pcg_load
        LDX     as_scene_patterns
        LDAA    AS_TILE_SEABED
        LDAB    32
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; NEW_MISSION.
game_init:
        JSR     jr_music_stop
        LDX     GAME_STATE
as_init_clear:
        CLR     [X]
        INX
        CPX     GAME_STATE + 24
        BNE     as_init_clear
        LDAA    2
        STAA    [AS_X]
        STAA    [AS_Y]
        LDAA    220
        STAA    [AS_OXYGEN]
        LDAA    5
        STAA    [AS_HULL]
        LDAA    22
        STAA    [AS_HX]
        LDAA    16
        STAA    [AS_HY]
game_raw_key:
game_tick:
        RTS

; A = x, B = y -> A = the sea cell (4 bits). Uses X and the stack only.
as_cell:
        PSHA
        LDX     as_rows
        ASLB
        TBA
        JSR     jr_add_x_a
        LDX     [X]
        PULA
        PSHA
        LSRA
        JSR     jr_add_x_a
        LDAA    [X]
        PULB
        RORB
        BCS     as_cell_low
        LSRA
        LSRA
        LSRA
        LSRA
as_cell_low:
        ANDA    0x0f
        RTS

; A = x, B = y -> A = Manhattan distance from the submarine.
as_dist:
        SUBA    [AS_X]
        BCC     as_dist_x
        NEGA
as_dist_x:
        PSHA
        TBA
        SUBA    [AS_Y]
        BCC     as_dist_y
        NEGA
as_dist_y:
        PULB
        ABA
        RTS

; A = oxygen spent (floored at 0).
as_spend:
        STAA    [AS_I]
        LDAA    [AS_OXYGEN]
        SUBA    [AS_I]
        BCC     as_spend_store
        CLRA
as_spend_store:
        STAA    [AS_OXYGEN]
        RTS

as_damage:
        TST     [AS_HULL]
        BEQ     as_damage_done
        DEC     [AS_HULL]
        LDX     as_sfx_hit
        JMP     jr_sfx_play
as_damage_done:
        RTS

; AS_K = direction: AS_CX / AS_CY one step from the submarine.
as_step_cursor:
        LDAA    [AS_X]
        STAA    [AS_CX]
        LDAA    [AS_Y]
        STAA    [AS_CY]
; AS_K = direction: step AS_CX / AS_CY.
as_step:
        LDAA    [AS_K]
        CMPA    1
        BNE     as_step_down
        DEC     [AS_CY]
        RTS
as_step_down:
        CMPA    2
        BNE     as_step_left
        INC     [AS_CY]
        RTS
as_step_left:
        CMPA    3
        BNE     as_step_right
        DEC     [AS_CX]
        RTS
as_step_right:
        INC     [AS_CX]
        RTS

game_act:
        STAA    [AS_K]
        LDAB    [AS_SUB]
        BNE     as_act_panel
        ; at sea
        CMPA    JR_KEY_CONFIRM
        BEQ     as_open_panel
        CMPA    JR_KEY_BACK
        BEQ     as_open_panel
        JMP     as_take_turn
as_open_panel:
        LDAA    AS_SUB_PANEL
        STAA    [AS_SUB]
        CLR     [AS_MENU]
        LDX     as_sfx_menu
        JMP     jr_sfx_play

as_act_panel:
        CMPB    AS_SUB_PANEL
        BNE     as_act_photo
        LDX     as_sfx_menu
        JSR     jr_sfx_play
        LDAA    [AS_K]
        CMPA    JR_KEY_UP
        BNE     as_act_panel_down
        DEC     [AS_MENU]
        BPL     as_act_done
        LDAA    5
        STAA    [AS_MENU]
        RTS
as_act_panel_down:
        CMPA    JR_KEY_DOWN
        BNE     as_act_panel_back
        INC     [AS_MENU]
        LDAA    [AS_MENU]
        CMPA    6
        BCS     as_act_done
        CLR     [AS_MENU]
        RTS
as_act_panel_back:
        CMPA    JR_KEY_BACK
        BEQ     as_to_sea
        CMPA    JR_KEY_CONFIRM
        BNE     as_act_done
        LDAB    [AS_MENU]
        CMPB    4
        BCC     as_act_question
        LDX     as_panel_actions
        TBA
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [AS_K]
        JMP     as_take_turn
as_act_question:
        DECB                        ; RESTART 4 -> 3, TITLE 5 -> 4
        STAB    [AS_SUB]
        CLR     [AS_CHOICE]
        RTS
as_to_sea:
        CLR     [AS_SUB]
as_act_done:
        RTS

as_act_photo:
        CMPB    AS_SUB_PHOTO
        BNE     as_act_answer
        CMPA    JR_KEY_CONFIRM
        BEQ     as_to_sea
        CMPA    JR_KEY_BACK
        BEQ     as_to_sea
        RTS

; RESTART? / TITLE?: A picks YES, D picks NO, RETURN answers, SPACE cancels.
as_act_answer:
        CMPA    JR_KEY_LEFT
        BNE     as_act_answer_no
        LDAA    1
        STAA    [AS_CHOICE]
        RTS
as_act_answer_no:
        CMPA    JR_KEY_RIGHT
        BNE     as_act_answer_back
        CLR     [AS_CHOICE]
        RTS
as_act_answer_back:
        CMPA    JR_KEY_BACK
        BEQ     as_act_answer_panel
        CMPA    JR_KEY_CONFIRM
        BNE     as_act_done
        TST     [AS_CHOICE]
        BNE     as_act_answer_yes
as_act_answer_panel:
        LDAA    AS_SUB_PANEL
        STAA    [AS_SUB]
        RTS
as_act_answer_yes:
        LDAA    [AS_SUB]
        CMPA    AS_SUB_RESTART
        BNE     as_act_title
        JMP     game_init
as_act_title:
        ; leave the mission for the title: drop game_act's return address
        INS
        INS
        JMP     jr_port_title

; AS_K = upstream action 1-4 move, 7 wait, 8 sonar, 9 record, 10 quiet.
as_take_turn:
        CLR     [AS_SUB]
        LDAA    [AS_K]
        CMPA    10
        BNE     as_take_turn_record
        LDAA    [AS_QUIET]
        EORA    1
        STAA    [AS_QUIET]
        RTS
as_take_turn_record:
        CMPA    9
        BNE     as_turn_sonar
        JMP     as_record
as_turn_sonar:
        CMPA    8
        BNE     as_navigate
        LDAA    7
        STAA    [AS_SIGHT]
        LDAA    9
        STAA    [AS_NOISE]
        LDAA    2
        JSR     as_spend
        LDX     as_sfx_sonar
        JSR     jr_sfx_play
        JSR     as_world_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     as_act_done
        ; the sweep crosses the view, a line every other column; only the
        ; line is written to the shadow screen, so a step is one present
        ; and a frame (the sea stands still meanwhile)
        JSR     jr_port_render
        CLR     [AS_SWEEP]
as_turn_sweep:
        LDX     JR_SHADOW + 64
        LDAA    [AS_SWEEP]
        JSR     jr_add_x_a
        LDAA    AS_CHAR_SWEEP
        JSR     as_sweep_column
        LDX     JR_SHADOW + 0x340
        LDAA    [AS_SWEEP]
        JSR     jr_add_x_a
        LDAA    AS_ATTR_SWEEP
        JSR     as_sweep_column
        JSR     jr_gfx_present
        LDAA    1
        JSR     jr_port_hold
        LDAA    [AS_SWEEP]
        ADDA    2
        STAA    [AS_SWEEP]
        CMPA    20
        BNE     as_turn_sweep
        RTS

; X = shadow cell in row 2, A = byte: down the 18 rows of the view.
as_sweep_column:
        LDAB    18
as_sweep_cell:
        STAA    [X]
        PSHA
        LDAA    32
        JSR     jr_add_x_a
        PULA
        DECB
        BNE     as_sweep_cell
        RTS

; NAVIGATE: moves and wait cost 1 oxygen (2 when quiet); rocks damage.
as_navigate:
        CMPA    JR_KEY_RIGHT
        BLS     as_navigate_go
        CMPA    7
        BEQ     as_act_done_near397
        JMP     as_act_done
as_act_done_near397:
as_navigate_go:
        CLR     [AS_STATUS]
        LDAA    [AS_QUIET]
        INCA
        JSR     as_spend
        LDAA    [AS_K]
        CMPA    7
        BEQ     as_world_step
        JSR     as_step_cursor
        LDAA    [AS_CX]
        LDAB    [AS_CY]
        JSR     as_cell
        CMPA    1
        BNE     as_navigate_move
        JSR     as_damage
        BRA     as_world_step
as_navigate_move:
        LDAA    [AS_CX]
        STAA    [AS_X]
        LDAA    [AS_CY]
        STAA    [AS_Y]
        LDX     as_sfx_move
        JSR     jr_sfx_play
        ; fall through

; WORLD_STEP: counters, the current, the hunter, contact, the mission.
as_world_step:
        INC     [AS_TURN]
        TST     [AS_SIGHT]
        BEQ     as_world_noise
        DEC     [AS_SIGHT]
as_world_noise:
        TST     [AS_NOISE]
        BEQ     as_world_grace
        DEC     [AS_NOISE]
as_world_grace:
        TST     [AS_GRACE]
        BEQ     as_world_current
        DEC     [AS_GRACE]
as_world_current:
        LDAA    [AS_X]
        LDAB    [AS_Y]
        JSR     as_cell
        CMPA    2
        BCS     as_world_hunter
        CMPA    6
        BCC     as_world_hunter
        LDX     as_current_dirs - 2
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [AS_K]
        JSR     as_step_cursor
        LDAA    [AS_CX]
        LDAB    [AS_CY]
        JSR     as_cell
        CMPA    1
        BEQ     as_world_hunter
        LDAA    [AS_CX]
        STAA    [AS_X]
        LDAA    [AS_CY]
        STAA    [AS_Y]
        LDAA    1
        JSR     as_spend
        LDX     as_sfx_current
        JSR     jr_sfx_play
as_world_hunter:
        LDAA    [AS_TURN]
        TST     [AS_QUIET]
        BEQ     as_world_fast
        ANDA    3
        BNE     as_world_contact
        BRA     as_world_move
as_world_fast:
        BITA    1
        BNE     as_world_contact
as_world_move:
        JSR     as_move_hunter
as_world_contact:
        LDAA    [AS_HX]
        LDAB    [AS_HY]
        JSR     as_dist
        CMPA    1
        BHI     as_world_mission
        TST     [AS_GRACE]
        BNE     as_world_mission
        JSR     as_damage
        LDAA    4
        STAA    [AS_GRACE]
as_world_mission:
        TST     [AS_HULL]
        BEQ     as_world_lost
        TST     [AS_OXYGEN]
        BEQ     as_world_lost
        LDAA    [AS_FLAGS]
        CMPA    31
        BNE     as_world_warning
        LDAA    [AS_X]
        CMPA    2
        BNE     as_world_warning
        LDAA    [AS_Y]
        CMPA    2
        BNE     as_world_warning
        JMP     jr_port_win
as_world_lost:
        LDX     as_txt_lost
        JMP     jr_port_lose
as_world_warning:
        ; every fourth turn: low oxygen or the hunter within six
        LDAA    [AS_TURN]
        ANDA    3
        BNE     as_world_done
        LDAA    [AS_OXYGEN]
        CMPA    30
        BLS     as_world_alarm
        LDAA    [AS_HX]
        LDAB    [AS_HY]
        JSR     as_dist
        CMPA    6
        BHI     as_world_done
as_world_alarm:
        LDX     as_sfx_warning
        JMP     jr_sfx_play
as_world_done:
        RTS

; MOVE_HUNTER: chase within six or while the sonar echoes, else patrol.
as_move_hunter:
        LDAA    [AS_HX]
        LDAB    [AS_HY]
        JSR     as_dist
        CMPA    6
        BLS     as_hunter_chase
        TST     [AS_NOISE]
        BNE     as_hunter_chase
        ; patrol between two points, switching every 16 turns
        LDAA    [AS_TURN]
        BITA    16
        BNE     as_hunter_patrol_far
        LDAA    18
        LDAB    14
        BRA     as_hunter_target
as_hunter_patrol_far:
        LDAA    22
        LDAB    20
        BRA     as_hunter_target
as_hunter_chase:
        LDAA    [AS_X]
        LDAB    [AS_Y]
as_hunter_target:
        STAA    [AS_TX]
        STAB    [AS_TY]
        LDAA    [AS_HX]
        STAA    [AS_CX]
        LDAA    [AS_HY]
        STAA    [AS_CY]
        LDAA    [AS_HX]
        CMPA    [AS_TX]
        BEQ     as_hunter_y
        BHI     as_hunter_left
        INC     [AS_CX]
        BRA     as_hunter_test_x
as_hunter_left:
        DEC     [AS_CX]
as_hunter_test_x:
        LDAA    [AS_CX]
        LDAB    [AS_CY]
        JSR     as_cell
        CMPA    1
        BNE     as_hunter_store
        LDAA    [AS_HX]
        STAA    [AS_CX]
as_hunter_y:
        LDAA    [AS_HY]
        CMPA    [AS_TY]
        BEQ     as_hunter_done
        BHI     as_hunter_up
        INC     [AS_CY]
        BRA     as_hunter_test_y
as_hunter_up:
        DEC     [AS_CY]
as_hunter_test_y:
        LDAA    [AS_CX]
        LDAB    [AS_CY]
        JSR     as_cell
        CMPA    1
        BEQ     as_hunter_done
as_hunter_store:
        LDAA    [AS_CX]
        STAA    [AS_HX]
        LDAA    [AS_CY]
        STAA    [AS_HY]
as_hunter_done:
        RTS

; RECORD_SITE: the first unrecorded site within one cell.
as_record:
        CLR     [AS_I]
as_record_scan:
        LDX     as_site_x
        LDAA    [AS_I]
        JSR     jr_add_x_a
        LDAA    [X]
        PSHA
        LDX     as_site_y
        LDAA    [AS_I]
        JSR     jr_add_x_a
        LDAB    [X]
        PULA
        JSR     as_dist
        CMPA    1
        BHI     as_record_next
        LDX     as_bits
        LDAA    [AS_I]
        JSR     jr_add_x_a
        LDAA    [X]
        BITA    [AS_FLAGS]
        BNE     as_record_next
        ORAA    [AS_FLAGS]
        STAA    [AS_FLAGS]
        LDAA    [AS_I]
        STAA    [AS_PHOTO]
        INC     [AS_SAMPLES]
        LDAA    2
        JSR     as_spend
        JSR     as_world_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     as_record_done
        LDAA    AS_SUB_PHOTO
        STAA    [AS_SUB]
        LDX     as_sfx_record
        JMP     jr_sfx_play
as_record_next:
        INC     [AS_I]
        LDAA    [AS_I]
        CMPA    5
        BCS     as_record_scan
        LDAA    1
        STAA    [AS_STATUS]
        LDX     as_sfx_empty
        JMP     jr_sfx_play
as_record_done:
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    AS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    [AS_SUB]
        CMPA    AS_SUB_PHOTO
        BNE     as_draw_sea
        JMP     as_draw_photo
as_draw_sea:
        LDX     as_hud
        JSR     jr_gfx_lines
        ; rules on rows 1 and 20, the divider in column 20
        LDAA    AS_ATTR_RULE
        STAA    [JR_RT_COLOR]
        CLRA
        LDAB    1
        JSR     as_draw_rule
        CLRA
        LDAB    20
        JSR     as_draw_rule
        LDAA    2
        STAA    [AS_DR]
as_draw_divider:
        LDAA    20
        LDAB    [AS_DR]
        JSR     jr_gfx_at
        LDAA    AS_CHAR_DIVIDER
        JSR     jr_gfx_putc
        INC     [AS_DR]
        LDAA    [AS_DR]
        CMPA    20
        BNE     as_draw_divider
        JSR     as_draw_gauges
        JSR     as_draw_view
        LDAA    [AS_SUB]
        BEQ     as_draw_result
        JSR     as_draw_panel
as_draw_result:
        ; the result under the view once the mission is over
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     as_draw_done
        LDAA    AS_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    22
        JSR     jr_gfx_at
        LDX     as_txt_win
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_LOST
        BNE     as_draw_result_text
        LDX     as_txt_salvaged
as_draw_result_text:
        JSR     jr_gfx_text
        LDAA    [AS_SAMPLES]
        LDAB    [JR_PORT_MODE]
        CMPB    JR_MODE_LOST
        BEQ     as_draw_result_value
        LDAA    [AS_OXYGEN]
as_draw_result_value:
        JMP     jr_gfx_dec3
as_draw_done:
        RTS

; A = column, B = row: a rule to the right edge.
as_draw_rule:
        JSR     jr_gfx_at
        LDAB    32
as_draw_rule_cell:
        LDAA    AS_CHAR_RULE
        JSR     jr_gfx_putc
        DECB
        BNE     as_draw_rule_cell
        RTS

as_draw_gauges:
        ; O2: the value, a bar of one cell per 20, !!! at 30 or less
        LDAA    AS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    3
        CLRB
        JSR     jr_gfx_at
        LDAA    [AS_OXYGEN]
        JSR     jr_gfx_dec3
        LDAA    AS_ATTR_BAR
        LDAB    [AS_OXYGEN]
        CMPB    30
        BHI     as_draw_bar_colour
        LDAA    AS_ATTR_LOW
as_draw_bar_colour:
        STAA    [JR_RT_COLOR]
        LDAA    7
        CLRB
        JSR     jr_gfx_at
        LDAA    [AS_OXYGEN]
        LDAB    20
        JSR     jr_divmod8
        TAB
        TSTB
        BEQ     as_draw_alarm
as_draw_bar:
        LDAA    AS_CHAR_BAR
        JSR     jr_gfx_putc
        DECB
        BNE     as_draw_bar
as_draw_alarm:
        LDAA    [AS_OXYGEN]
        CMPA    30
        BHI     as_draw_hull
        LDAA    AS_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    19
        CLRB
        JSR     jr_gfx_at
        LDX     as_txt_alarm
        JSR     jr_gfx_text
as_draw_hull:
        LDAA    AS_ATTR_HULL
        STAA    [JR_RT_COLOR]
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDAB    [AS_HULL]
        BEQ     as_draw_depth
as_draw_hull_icon:
        LDAA    AS_CHAR_HULL
        JSR     jr_gfx_putc
        DECB
        BNE     as_draw_hull_icon
as_draw_depth:
        LDAA    AS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    23
        LDAB    6
        JSR     jr_gfx_at
        LDAA    [AS_Y]
        ASLA
        ADDA    [AS_Y]
        ADDA    10
        JSR     jr_gfx_dec3
        ; the next unrecorded site (or the base): range and bearing
        CLR     [AS_TGI]
as_draw_target:
        LDX     as_bits
        LDAA    [AS_TGI]
        JSR     jr_add_x_a
        LDAA    [X]
        BITA    [AS_FLAGS]
        BEQ     as_draw_target_site
        INC     [AS_TGI]
        LDAA    [AS_TGI]
        CMPA    5
        BNE     as_draw_target
        LDAA    2
        STAA    [AS_TGX]
        STAA    [AS_TGY]
        BRA     as_draw_range
as_draw_target_site:
        LDX     as_site_x
        LDAA    [AS_TGI]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [AS_TGX]
        LDX     as_site_y
        LDAA    [AS_TGI]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [AS_TGY]
as_draw_range:
        LDAA    23
        LDAB    9
        JSR     jr_gfx_at
        LDAA    [AS_TGX]
        LDAB    [AS_TGY]
        JSR     as_dist
        JSR     jr_gfx_dec3
        ; bearing: N 1, S 2, W 4, E 8
        CLRB
        LDAA    [AS_TGX]
        CMPA    [AS_X]
        BEQ     as_draw_bearing_y
        LDAB    4
        BCS     as_draw_bearing_y
        LDAB    8
as_draw_bearing_y:
        LDAA    [AS_TGY]
        CMPA    [AS_Y]
        BEQ     as_draw_bearing
        BCS     as_draw_bearing_n
        ORAB    2
        BRA     as_draw_bearing
as_draw_bearing_n:
        ORAB    1
as_draw_bearing:
        STAB    [AS_DI]
        LDAA    23
        LDAB    11
        JSR     jr_gfx_at
        LDX     as_bearing_names
        LDAA    [AS_DI]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        LDAA    22
        LDAB    13
        JSR     jr_gfx_at
        LDAA    [AS_SAMPLES]
        JSR     jr_gfx_dec3
        ; engine, contact, sonar
        LDAA    22
        LDAB    16
        JSR     jr_gfx_at
        LDX     as_txt_cruise
        TST     [AS_QUIET]
        BEQ     as_draw_engine
        LDX     as_txt_silent
as_draw_engine:
        JSR     jr_gfx_text
        LDAA    22
        LDAB    17
        JSR     jr_gfx_at
        LDAA    [AS_HX]
        LDAB    [AS_HY]
        JSR     as_dist
        LDX     as_txt_clear
        CMPA    6
        BHI     as_draw_contact
        LDAA    AS_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDX     as_txt_contact
as_draw_contact:
        JSR     jr_gfx_text
        LDAA    AS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    22
        LDAB    19
        JSR     jr_gfx_at
        LDX     as_txt_ready
        TST     [AS_SIGHT]
        BEQ     as_draw_sonar
        LDX     as_txt_active
as_draw_sonar:
        JSR     jr_gfx_text
        ; row 21: where to, or no site in range
        LDAA    AS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        TST     [AS_STATUS]
        BEQ     as_draw_to
        LDAA    AS_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    3
        LDAB    21
        JSR     jr_gfx_at
        LDX     as_txt_none
        JMP     jr_gfx_text
as_draw_to:
        LDAA    4
        LDAB    21
        JSR     jr_gfx_at
        LDX     as_site_names
        LDAA    [AS_TGI]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JMP     jr_gfx_text

; The view: 10 x 9 cells around the submarine, radius 2 (6 with sonar).
as_draw_view:
        LDAA    [AS_X]
        SUBA    4
        BCC     as_draw_view_x
        CLRA
as_draw_view_x:
        CMPA    22
        BLS     as_draw_view_xs
        LDAA    22
as_draw_view_xs:
        STAA    [AS_VX]
        LDAA    [AS_Y]
        SUBA    4
        BCC     as_draw_view_y
        CLRA
as_draw_view_y:
        CMPA    23
        BLS     as_draw_view_ys
        LDAA    23
as_draw_view_ys:
        STAA    [AS_VY]
        LDAA    2
        TST     [AS_SIGHT]
        BEQ     as_draw_view_radius
        LDAA    6
as_draw_view_radius:
        STAA    [AS_RAD]
        CLR     [AS_DR]
as_draw_view_row:
        CLR     [AS_DC]
as_draw_view_cell:
        CLR     [AS_LETTER]
        LDAA    [AS_DC]
        ADDA    [AS_VX]
        STAA    [AS_WX]
        LDAA    [AS_DR]
        ADDA    [AS_VY]
        STAA    [AS_WY]
        LDAA    [AS_WX]
        LDAB    [AS_WY]
        JSR     as_dist
        CMPA    [AS_RAD]
        BLS     as_draw_view_seen
        LDAA    AS_TILE_FOG
        LDAB    AS_ATTR_FOG
        BRA     as_draw_view_put
as_draw_view_seen:
        LDAA    [AS_WX]
        LDAB    [AS_WY]
        JSR     as_cell
        ASLA
        LDX     as_sea_tiles
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    [X + 1]
        STAA    [AS_DCODE]
        STAB    [AS_DATTR]
        ; a current carries its letter in the lower right
        LDAA    [AS_WX]
        LDAB    [AS_WY]
        JSR     as_cell
        CMPA    2
        BCS     as_draw_view_hunter
        CMPA    6
        BCC     as_draw_view_hunter
        LDX     as_current_letters - 2
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [AS_LETTER]
as_draw_view_hunter:
        LDAA    [AS_WX]
        CMPA    [AS_HX]
        BNE     as_draw_view_sub
        LDAA    [AS_WY]
        CMPA    [AS_HY]
        BNE     as_draw_view_sub
        LDAA    AS_TILE_HUNTER
        LDAB    AS_ATTR_HUNTER
        BRA     as_draw_view_actor
as_draw_view_sub:
        LDAA    [AS_WX]
        CMPA    [AS_X]
        BNE     as_draw_view_code
        LDAA    [AS_WY]
        CMPA    [AS_Y]
        BNE     as_draw_view_code
        LDAA    AS_TILE_SUB
        LDAB    AS_ATTR_SUB
as_draw_view_actor:
        STAA    [AS_DCODE]
        STAB    [AS_DATTR]
        CLR     [AS_LETTER]
as_draw_view_code:
        LDAA    [AS_DCODE]
        LDAB    [AS_DATTR]
as_draw_view_put:
        STAA    [AS_DCODE]
        STAB    [JR_RT_COLOR]
        LDAA    [AS_DC]
        ASLA
        LDAB    [AS_DR]
        ASLB
        ADDB    2
        JSR     jr_gfx_at
        LDAA    [AS_DCODE]
        CMPA    0x20
        BEQ     as_draw_view_water
        JSR     jr_gfx_tile
        BRA     as_draw_view_letter
as_draw_view_water:
        ; open water: blank
as_draw_view_letter:
        TST     [AS_LETTER]
        BEQ     as_draw_view_next
        LDAA    AS_ATTR_DIM
        STAA    [JR_RT_COLOR]
        LDAA    [AS_DC]
        ASLA
        INCA
        LDAB    [AS_DR]
        ASLB
        ADDB    3
        JSR     jr_gfx_at
        LDAA    [AS_LETTER]
        JSR     jr_gfx_putc
as_draw_view_next:
        INC     [AS_DC]
        LDAA    [AS_DC]
        CMPA    10
        BEQ     as_draw_view_row_done
        JMP     as_draw_view_cell
as_draw_view_row_done:
        INC     [AS_DR]
        LDAA    [AS_DR]
        CMPA    9
        BEQ     as_draw_view_sweep
        JMP     as_draw_view_row
as_draw_view_sweep:
as_draw_view_done:
        RTS

; The control panel over the view, and its question.
as_draw_panel:
        LDAA    AS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    5
        STAA    [AS_DR]
as_draw_panel_row:
        LDAA    1
        LDAB    [AS_DR]
        JSR     jr_gfx_at
        LDAB    18
as_draw_panel_cell:
        LDAA    0x20
        JSR     jr_gfx_putc
        DECB
        BNE     as_draw_panel_cell
        INC     [AS_DR]
        LDAA    [AS_DR]
        CMPA    19
        BNE     as_draw_panel_row
        LDX     as_panel_lines
        JSR     jr_gfx_lines
        LDAA    AS_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [AS_MENU]
        ASLA
        ADDA    7
        TAB
        LDAA    2
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDAA    [AS_SUB]
        CMPA    AS_SUB_RESTART
        BCS     as_draw_panel_done
        BNE     as_draw_panel_title
        LDX     as_ask_restart_lines
        BRA     as_draw_panel_ask
as_draw_panel_title:
        LDX     as_ask_title_lines
as_draw_panel_ask:
        JSR     jr_gfx_lines
        LDAA    AS_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    10
        TST     [AS_CHOICE]
        BNE     as_draw_panel_choice
        LDAA    15
as_draw_panel_choice:
        LDAB    18
        JSR     jr_gfx_at
        LDAA    0x3e
        JMP     jr_gfx_putc
as_draw_panel_done:
        RTS

; A discovery: the site's name, its scene over the seabed and a caption.
as_draw_photo:
        LDAA    AS_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    2
        LDAB    1
        JSR     jr_gfx_at
        LDX     as_site_names
        LDAA    [AS_PHOTO]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        ; the seabed along rows 18-19
        LDAA    AS_ATTR_ROCK
        STAA    [JR_RT_COLOR]
        CLR     [AS_DC]
as_draw_photo_bed:
        LDAA    [AS_DC]
        LDAB    18
        JSR     jr_gfx_at
        LDAA    AS_TILE_SEABED
        JSR     jr_gfx_tile
        LDAA    [AS_DC]
        ADDA    2
        STAA    [AS_DC]
        CMPA    32
        BNE     as_draw_photo_bed
        ; the scene: x, y, tile, attribute ... 0xff
        LDX     as_scenes
        LDAA    [AS_PHOTO]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     as_draw_scene
        LDAA    AS_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    21
        JSR     jr_gfx_at
        LDX     as_captions
        LDAA    [AS_PHOTO]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        LDAA    AS_ATTR_DIM
        STAA    [JR_RT_COLOR]
        LDAA    3
        LDAB    22
        JSR     jr_gfx_at
        LDX     as_txt_archive
        JMP     jr_gfx_text

; X = scene: x, y, tile, attribute ... 0xff.
as_draw_scene:
        STX     [AS_DPTR]
as_draw_scene_tile:
        LDX     [AS_DPTR]
        LDAA    [X]
        CMPA    0xff
        BEQ     as_draw_scene_done
        LDAB    [X + 3]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [AS_DCODE]
        LDAB    [X + 1]
        JSR     jr_gfx_at
        LDAA    [AS_DCODE]
        JSR     jr_gfx_tile
        LDX     [AS_DPTR]
        INX
        INX
        INX
        INX
        STX     [AS_DPTR]
        BRA     as_draw_scene_tile
as_draw_scene_done:
        RTS

game_draw_title:
        LDX     as_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    AS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     as_title_scene
        JSR     as_draw_scene
        LDX     as_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    AS_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     as_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

game_key_table:
        .db     0x66, 8, 0x78, 7, 0         ; F: sonar, X: wait

; panel items 0-3 -> upstream actions (sonar, record, quiet, wait)
as_panel_actions:
        .db     8, 9, 10, 7
as_bits:
        .db     1, 2, 4, 8, 16
; currents 2-5 push east, south, west, north
as_current_dirs:
        .db     4, 2, 3, 1
as_current_letters:
        .db     0x45, 0x53, 0x57, 0x4e
; sea cell 0-11 -> tile, attribute (0x20 is open water)
as_sea_tiles:
        .db     0x20, AS_ATTR_TEXT, AS_TILE_ROCK, AS_ATTR_ROCK
        .db     AS_TILE_CURRENT, AS_ATTR_CURRENT, AS_TILE_CURRENT, AS_ATTR_CURRENT
        .db     AS_TILE_CURRENT, AS_ATTR_CURRENT, AS_TILE_CURRENT, AS_ATTR_CURRENT
        .db     AS_TILE_SITE, AS_ATTR_BASE, AS_TILE_SITE, AS_ATTR_SITE
        .db     AS_TILE_SITE, AS_ATTR_SITE, AS_TILE_SITE, AS_ATTR_SITE
        .db     AS_TILE_SITE, AS_ATTR_SITE, AS_TILE_SITE, AS_ATTR_SITE
as_bearing_names:
        .dw     as_txt_here, as_txt_n, as_txt_s, as_txt_q, as_txt_w, as_txt_nw
        .dw     as_txt_sw, as_txt_q, as_txt_e, as_txt_ne, as_txt_se

; discovery scenes: x, y, tile, attribute ... 0xff
as_scenes:
        .dw     as_scene_relay, as_scene_gate, as_scene_garden, as_scene_array, as_scene_sun
as_scene_relay:
        .db     14, 6, AS_TILE_MAST, 0x47, 14, 8, AS_TILE_MAST, 0x47
        .db     14, 10, AS_TILE_MAST, 0x47, 14, 12, AS_TILE_MAST, 0x47
        .db     14, 14, AS_TILE_MAST, 0x47, 14, 16, AS_TILE_MAST, 0x47
        .db     4, 16, AS_TILE_KELP, 0x44, 24, 16, AS_TILE_KELP, 0x44
        .db     8, 9, AS_TILE_FISH, 0x45, 0xff
as_scene_gate:
        .db     10, 8, AS_TILE_ARCH, 0x47, 12, 8, AS_TILE_ARCH, 0x47
        .db     10, 10, AS_TILE_ARCH, 0x47, 12, 10, AS_TILE_ARCH, 0x47
        .db     10, 12, AS_TILE_ARCH, 0x47, 12, 12, AS_TILE_ARCH, 0x47
        .db     10, 14, AS_TILE_ARCH, 0x47, 12, 14, AS_TILE_ARCH, 0x47
        .db     10, 16, AS_TILE_ARCH, 0x47, 12, 16, AS_TILE_ARCH, 0x47
        .db     20, 16, AS_TILE_ARCH, 0x41, 22, 16, AS_TILE_ARCH, 0x41
        .db     4, 16, AS_TILE_KELP, 0x44, 0xff
as_scene_garden:
        .db     4, 16, AS_TILE_CRYSTAL, 0x45, 8, 14, AS_TILE_CRYSTAL, 0x43
        .db     8, 16, AS_TILE_CRYSTAL, 0x45, 12, 12, AS_TILE_CRYSTAL, 0x45
        .db     12, 14, AS_TILE_CRYSTAL, 0x43, 12, 16, AS_TILE_CRYSTAL, 0x45
        .db     18, 14, AS_TILE_CRYSTAL, 0x43, 18, 16, AS_TILE_CRYSTAL, 0x45
        .db     24, 16, AS_TILE_CRYSTAL, 0x43, 22, 7, AS_TILE_FISH, 0x46, 0xff
as_scene_array:
        .db     4, 14, AS_TILE_DISH, 0x47, 10, 12, AS_TILE_DISH, 0x47
        .db     16, 14, AS_TILE_DISH, 0x47, 22, 12, AS_TILE_DISH, 0x47
        .db     10, 14, AS_TILE_DISH, 0x41, 22, 14, AS_TILE_DISH, 0x41
        .db     26, 16, AS_TILE_KELP, 0x44, 16, 6, AS_TILE_FISH, 0x45, 0xff
as_scene_sun:
        .db     14, 8, AS_TILE_ORB, 0x43, 12, 10, AS_TILE_ORB, 0x41
        .db     16, 10, AS_TILE_ORB, 0x41, 14, 12, AS_TILE_ORB, 0x43
        .db     6, 16, AS_TILE_KELP, 0x44, 24, 16, AS_TILE_KELP, 0x44
        .db     14, 16, AS_TILE_CRYSTAL, 0x42, 0xff
as_title_scene:
        .db     4, 3, AS_TILE_FISH, 0x45, 10, 4, AS_TILE_SUB, AS_ATTR_SUB
        .db     16, 3, AS_TILE_SITE, AS_ATTR_SITE, 22, 4, AS_TILE_HUNTER, AS_ATTR_HUNTER
        .db     26, 3, AS_TILE_ROCK, AS_ATTR_ROCK, 0xff
as_captions:
        .dw     as_cap_0, as_cap_1, as_cap_2, as_cap_3, as_cap_4
as_cap_0:
        .db     "A MAST STILL PULSES IN THE DARK", 0
as_cap_1:
        .db     "AN ARCH TO A CITY NO ONE MAPPED", 0
as_cap_2:
        .db     "CRYSTALS BLOOM WITHOUT LIGHT", 0
as_cap_3:
        .db     "DISHES STILL FACE A LOST SKY", 0
as_cap_4:
        .db     "A DARK ORB HUMS UNDER THE SAND", 0

as_hud:
        .db     0, 0, AS_ATTR_LABEL
        .dw     as_txt_o2
        .db     23, 0, AS_ATTR_LABEL
        .dw     as_txt_hull
        .db     22, 2, AS_ATTR_TITLE
        .dw     as_txt_abyss
        .db     22, 3, AS_ATTR_TITLE
        .dw     as_txt_signal
        .db     22, 5, AS_ATTR_LABEL
        .dw     as_txt_depth
        .db     25, 7, AS_ATTR_DIM
        .dw     as_txt_metres
        .db     22, 8, AS_ATTR_LABEL
        .dw     as_txt_range
        .db     22, 10, AS_ATTR_LABEL
        .dw     as_txt_bearing
        .db     22, 12, AS_ATTR_LABEL
        .dw     as_txt_samples
        .db     26, 13, AS_ATTR_DIM
        .dw     as_txt_of5
        .db     22, 15, AS_ATTR_LABEL
        .dw     as_txt_engine
        .db     22, 18, AS_ATTR_LABEL
        .dw     as_txt_sonar
        .db     0, 21, AS_ATTR_LABEL
        .dw     as_txt_to
        .db     0xff
as_panel_lines:
        .db     3, 5, AS_ATTR_TITLE
        .dw     as_txt_panel
        .db     4, 7, AS_ATTR_TEXT
        .dw     as_txt_m0
        .db     4, 9, AS_ATTR_TEXT
        .dw     as_txt_m1
        .db     4, 11, AS_ATTR_TEXT
        .dw     as_txt_m2
        .db     4, 13, AS_ATTR_TEXT
        .dw     as_txt_m3
        .db     4, 15, AS_ATTR_TEXT
        .dw     as_txt_m4
        .db     4, 17, AS_ATTR_TEXT
        .dw     as_txt_m5
        .db     0xff
as_ask_restart_lines:
        .db     2, 18, AS_ATTR_WARN
        .dw     as_txt_ask_restart
        .db     0xff
as_ask_title_lines:
        .db     2, 18, AS_ATTR_WARN
        .dw     as_txt_ask_title
        .db     0xff
as_title_lines:
        .db     9, 8, AS_ATTR_TITLE
        .dw     as_txt_name
        .db     3, 10, AS_ATTR_LABEL
        .dw     as_txt_tagline
        .db     8, 14, AS_ATTR_TEXT
        .dw     as_txt_start
        .db     4, 16, AS_ATTR_TEXT
        .dw     as_txt_howto
        .db     4, 22, AS_ATTR_DIM
        .dw     as_txt_credit
        .db     0xff
as_help_lines:
        .db     10, 1, AS_ATTR_TITLE
        .dw     as_txt_name
        .db     1, 3, AS_ATTR_TEXT
        .dw     as_help_1
        .db     1, 5, AS_ATTR_TEXT
        .dw     as_help_2
        .db     1, 6, AS_ATTR_TEXT
        .dw     as_help_3
        .db     1, 7, AS_ATTR_TEXT
        .dw     as_help_4
        .db     1, 9, AS_ATTR_TEXT
        .dw     as_help_5
        .db     1, 10, AS_ATTR_TEXT
        .dw     as_help_6
        .db     1, 11, AS_ATTR_TEXT
        .dw     as_help_7
        .db     1, 13, AS_ATTR_TEXT
        .dw     as_help_8
        .db     1, 14, AS_ATTR_TEXT
        .dw     as_help_9
        .db     1, 15, AS_ATTR_TEXT
        .dw     as_help_10
        .db     1, 17, AS_ATTR_TEXT
        .dw     as_help_11
        .db     1, 18, AS_ATTR_TEXT
        .dw     as_help_12
        .db     1, 20, AS_ATTR_TEXT
        .dw     as_help_13
        .db     7, 22, AS_ATTR_LABEL
        .dw     as_help_back
        .db     0xff

as_txt_name:
        .db     "ABYSS SIGNAL", 0
as_txt_o2:
        .db     "O2", 0
as_txt_hull:
        .db     "HULL", 0
as_txt_alarm:
        .db     "!!!", 0
as_txt_abyss:
        .db     "ABYSS", 0
as_txt_signal:
        .db     "SIGNAL", 0
as_txt_depth:
        .db     "DEPTH", 0
as_txt_metres:
        .db     "X10 M", 0
as_txt_range:
        .db     "RANGE", 0
as_txt_bearing:
        .db     "BEARING", 0
as_txt_samples:
        .db     "SAMPLES", 0
as_txt_of5:
        .db     "/005", 0
as_txt_engine:
        .db     "ENGINE", 0
as_txt_sonar:
        .db     "SONAR", 0
as_txt_to:
        .db     "TO:", 0
as_txt_cruise:
        .db     "CRUISE", 0
as_txt_silent:
        .db     "SILENT", 0
as_txt_ready:
        .db     "READY", 0
as_txt_active:
        .db     "ACTIVE", 0
as_txt_contact:
        .db     "CONTACT", 0
as_txt_clear:
        .db     "CLEAR", 0
as_txt_none:
        .db     "NO SITE IN RECORDING RANGE", 0
as_txt_here:
        .db     "HERE", 0
as_txt_n:
        .db     "N", 0
as_txt_s:
        .db     "S", 0
as_txt_q:
        .db     "?", 0
as_txt_w:
        .db     "W", 0
as_txt_nw:
        .db     "NW", 0
as_txt_sw:
        .db     "SW", 0
as_txt_e:
        .db     "E", 0
as_txt_ne:
        .db     "NE", 0
as_txt_se:
        .db     "SE", 0
as_txt_panel:
        .db     "CONTROL PANEL", 0
as_txt_m0:
        .db     "SONAR PING", 0
as_txt_m1:
        .db     "RECORD SITE", 0
as_txt_m2:
        .db     "QUIET MODE", 0
as_txt_m3:
        .db     "WAIT", 0
as_txt_m4:
        .db     "RESTART", 0
as_txt_m5:
        .db     "TITLE", 0
as_txt_ask_restart:
        .db     "RESTART?  YES  NO", 0
as_txt_ask_title:
        .db     "TITLE?    YES  NO", 0
as_txt_archive:
        .db     "ARCHIVE SAVED / RETURN", 0
as_txt_lost:
        .db     "CONNECTION LOST", 0
as_txt_salvaged:
        .db     "RECORDS SALVAGED ", 0
as_txt_win:
        .db     "SURVEY COMPLETE, O2 LEFT ", 0
as_txt_tagline:
        .db     "FIVE SIGNALS. ONE WAY HOME.", 0
as_txt_start:
        .db     "RETURN : DIVE", 0
as_txt_howto:
        .db     "OTHER KEY : FIELD GUIDE", 0
as_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
as_help_1:
        .db     "SURVEY FIVE SITES. RETURN HOME.", 0
as_help_2:
        .db     "W/A/S/D : MOVE ONE CELL", 0
as_help_3:
        .db     "RETURN/SPACE : CONTROL PANEL", 0
as_help_4:
        .db     "F : SONAR   X : WAIT", 0
as_help_5:
        .db     "RECORD FROM AN ADJACENT CELL.", 0
as_help_6:
        .db     "ROCK IMPACTS DAMAGE THE HULL.", 0
as_help_7:
        .db     "CURRENTS PUSH AND COST 1 O2.", 0
as_help_8:
        .db     "EACH MOVE / WAIT COSTS 1 O2.", 0
as_help_9:
        .db     "QUIET: COST 2, SLOWER PURSUER.", 0
as_help_10:
        .db     "SONAR / RECORD COST 2 O2.", 0
as_help_11:
        .db     "SONAR REVEALS FOR SIX ACTIONS.", 0
as_help_12:
        .db     "ITS NOISE ATTRACTS THE HUNTER.", 0
as_help_13:
        .db     "PANELS AND PHOTOS PAUSE TIME.", 0
as_help_back:
        .db     "ANY KEY : TITLE", 0

        .include "world.inc"

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     as_sfx_move, as_sfx_record, as_jingle_win, as_jingle_lose
as_sfx_move:
        .db     110, 1, 0, 0
as_sfx_menu:
        .db     70, 1, 0, 0
as_sfx_hit:
        .db     230, 3, 250, 2, 240, 4, 0, 0
as_sfx_sonar:
        .db     30, 3, 0, 6, 30, 2, 0, 0
as_sfx_current:
        .db     150, 2, 130, 2, 0, 0
as_sfx_record:
        .db     60, 3, 45, 3, 34, 3, 30, 6, 0, 0
as_sfx_empty:
        .db     220, 3, 0, 0
as_sfx_warning:
        .db     90, 2, 0, 2, 90, 2, 0, 0

; Title: a slow D minor descent, quarter note = 16 frames, looping.
as_title_song:
        .db     1
        .dw     as_title_melody, as_title_harmony, as_title_bass
as_title_melody:
        .db     AU_A5, 16, AU_F5, 16, AU_E5, 16, AU_D5, 16, AU_C5, 32, AU_D5, 32
        .db     AU_F5, 16, AU_E5, 16, AU_D5, 16, AU_CS5, 16, AU_D5, 64, 0, 0
as_title_harmony:
        .db     AU_D5, 32, AU_A4, 32, AU_A4, 32, AU_F4, 32
        .db     AU_A4, 32, AU_G4, 32, AU_A4, 64, 0, 0
as_title_bass:
        .db     AU_D3, 32, AU_C3, 32, AU_AS2, 32, AU_A2, 32
        .db     AU_F2, 32, AU_A2, 32, AU_D2, 64, 0, 0

; Survey complete: a rising D major chord.
as_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     as_win_melody, as_win_harmony, as_win_bass
as_win_melody:
        .db     AU_A5, 8, AU_D6, 8, AU_FS6, 8, AU_A6, 30, 0, 0
as_win_harmony:
        .db     AU_FS5, 8, AU_A5, 8, AU_D6, 8, AU_FS6, 30, 0, 0
as_win_bass:
        .db     AU_D3, 24, AU_D2, 30, 0, 0
; Connection lost: a sinking figure.
as_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     as_lose_melody, as_lose_harmony, as_lose_bass
as_lose_melody:
        .db     AU_D5, 12, AU_CS5, 12, AU_C5, 12, AU_B4, 30, 0, 0
as_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_G4, 12, AU_FS4, 30, 0, 0
as_lose_bass:
        .db     AU_D3, 36, AU_D2, 30, 0, 0

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
        .include "../../../sdk/port.inc"
        .include "../../../sdk/font_data.inc"
