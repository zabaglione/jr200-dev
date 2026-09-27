; SPDX-License-Identifier: MIT
; TRACE BLADE for JR-200: a port of jr100dev games/trace_blade 1.6.1.
; Upstream is hand-written JR-100 assembly with no Python rules module; the
; thirty rooms, the one-stroke path from (1, 1), walls and visited cells,
; undo, the CUT/UNDO/RESET/TITLE/BACK menu with its NO-first questions,
; the cut that needs every target marked and the path ending on the exit,
; and the strike that follows the path one cell every five frames follow
; the upstream source (see tests/model.py). Display, colour and
; three-voice sound use the JR-200 port SDK.
        .filename.jr "TRACE-BLADE"
        .include "../../../sdk/jr200.inc"

; Rooms and self-test routes need more than 8 KB of code, so the work area
; starts at 0x4000 (code 0x1000-0x3fff, as in IRON SCRIPT).
JR_SHADOW:          .equ    0x4000
JR_SAVE:            .equ    0x4600
JR_RT:              .equ    0x5600
GAME_STATE:         .equ    0x5640
GAME_STATE_END:     .equ    0x57c0
JR_AUDIO:           .equ    0x57c0
JR_TEST:            .equ    0x57e0
JR_TEST_OUT:        .equ    0x6000
JR_STACK_TOP:       .equ    0x5fff

GAME_LEVELS:        .equ    30
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    0       ; SPACE is undo, as upstream
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    4       ; a full render takes about four frames
GAME_TEST_SIZE:     .equ    118     ; scalars and the map
GAME_TEST_LIMIT:    .equ    10
GAME_TEST_HELD:     .equ    TB_HELD

; Upstream state (same order as tests/model.py LAYOUT).
TB_X:               .equ    GAME_STATE
TB_Y:               .equ    GAME_STATE + 1
TB_LEN:             .equ    GAME_STATE + 2
TB_TARGETS:         .equ    GAME_STATE + 3
TB_MARKED:          .equ    GAME_STATE + 4
TB_COMBO:           .equ    GAME_STATE + 5
TB_MENU:            .equ    GAME_STATE + 6
TB_SUB:             .equ    GAME_STATE + 7      ; 0 plan, 1 menu, 2 cut, 3/4 question
TB_CHOICE:          .equ    GAME_STATE + 8      ; 1 YES
TB_ERROR:           .equ    GAME_STATE + 9
TB_MAP:             .equ    GAME_STATE + 10
TB_SEEN:            .equ    GAME_STATE + 118
TB_TRAIL:           .equ    GAME_STATE + 226
; Work bytes.
TB_CELL:            .equ    GAME_STATE + 334
TB_I:               .equ    GAME_STATE + 335
TB_K:               .equ    GAME_STATE + 336
TB_FX:              .equ    GAME_STATE + 337    ; burst stage 1-3 at the blade
TB_COL:             .equ    GAME_STATE + 338
TB_ROW:             .equ    GAME_STATE + 339
TB_CODE:            .equ    GAME_STATE + 340
TB_PTR:             .equ    GAME_STATE + 341    ; 2 bytes
TB_BYTE:            .equ    GAME_STATE + 343
TB_SCR:             .equ    GAME_STATE + 344    ; 2 bytes
TB_ATR:             .equ    GAME_STATE + 346    ; 2 bytes
TB_POS:             .equ    GAME_STATE + 348    ; the cut's path step (game_draw uses TB_I)
TB_HELD:            .equ    GAME_STATE + 349    ; unused (no held keys)

TB_SUB_PLAN:        .equ    0
TB_SUB_MENU:        .equ    1
TB_SUB_CUT:         .equ    2
TB_SUB_RESET:       .equ    3
TB_SUB_TITLE:       .equ    4
TB_START:           .equ    13
TB_STEP_FRAMES:     .equ    5
TB_BURST_FRAMES:    .equ    4       ; three stages

TB_TILE_FLOOR:      .equ    0x80
TB_TILE_WALL:       .equ    0x84
TB_TILE_TARGET:     .equ    0x88
TB_TILE_MARKED:     .equ    0x8c
TB_TILE_EXIT:       .equ    0x90
TB_TILE_TRAIL:      .equ    0x94
TB_TILE_BLADE:      .equ    0x98
TB_TILE_FLASH:      .equ    0x9c    ; then shards, dust
TB_ATTR_FLOOR:      .equ    0x47
TB_ATTR_WALL:       .equ    0x41
TB_ATTR_TARGET:     .equ    0x42
TB_ATTR_MARKED:     .equ    0x46
TB_ATTR_EXIT:       .equ    0x43
TB_ATTR_TRAIL:      .equ    0x45
TB_ATTR_BLADE:      .equ    0x47
TB_ATTR_BURST:      .equ    0x46
TB_ATTR_TEXT:       .equ    0x07
TB_ATTR_LABEL:      .equ    0x04
TB_ATTR_TITLE:      .equ    0x06
TB_ATTR_DIM:        .equ    0x05
TB_ATTR_PICK:       .equ    0x06
TB_ATTR_BAD:        .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     tb_patterns
        LDAA    TB_TILE_FLOOR
        LDAB    40
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; Unpack the room (27 bytes, four 2-bit cells each) and count its targets.
game_init:
        JSR     jr_music_stop
        JSR     jr_test_level
        ; room * 27 passes 255, so step X one room at a time
        LDX     tb_rooms
        LDAB    [JR_PORT_LEVEL]
        BEQ     tb_init_found
tb_init_seek:
        LDAA    27
        JSR     jr_add_x_a
        DECB
        BNE     tb_init_seek
tb_init_found:
        STX     [TB_PTR]
        LDX     TB_MAP
        STX     [JR_RT_DST]
        LDAA    27
        STAA    [TB_I]
tb_init_byte:
        LDX     [TB_PTR]
        LDAA    [X]
        INX
        STX     [TB_PTR]
        STAA    [TB_BYTE]
        LDAB    4
tb_init_cell:
        LDAA    [TB_BYTE]
        LSRA
        LSRA
        LSRA
        LSRA
        LSRA
        LSRA
        LDX     [JR_RT_DST]
        STAA    [X]
        INX
        STX     [JR_RT_DST]
        CMPA    2
        BNE     tb_init_shift
        INC     [TB_TARGETS]
tb_init_shift:
        LDAA    [TB_BYTE]
        ASLA
        ASLA
        STAA    [TB_BYTE]
        DECB
        BNE     tb_init_cell
        DEC     [TB_I]
        BNE     tb_init_byte
        ; fall through

; RESET_PATH: only the plan is cleared; the map is unchanged.
tb_reset_path:
        LDX     TB_SEEN
        LDAB    108
tb_reset_clear:
        CLR     [X]
        INX
        DECB
        BNE     tb_reset_clear
        LDAA    1
        STAA    [TB_X]
        STAA    [TB_Y]
        STAA    [TB_SEEN + TB_START]
        LDAA    TB_START
        STAA    [TB_TRAIL]
        CLR     [TB_SUB]
        CLR     [TB_LEN]
        CLR     [TB_MARKED]
        CLR     [TB_COMBO]
        CLR     [TB_ERROR]
        RTS

; T runs the self test (every room's upstream route, without drawing). The
; P demo of sdk/selftest.inc is not offered: turns have no tick to pace it.
game_raw_key:
        TBA
        ORAA    0x20
        CMPA    0x70
        BNE     tb_raw_key_test
        CLRA
        RTS
tb_raw_key_test:
        CLRA
        JMP     jr_test_raw_key

game_tick:
        RTS

game_act:
        STAA    [TB_K]
        LDAB    [TB_SUB]
        BNE     tb_act_menu
        ; planning
        CMPA    JR_KEY_CONFIRM
        BNE     tb_act_undo
        LDAA    TB_SUB_MENU
        STAA    [TB_SUB]
        CLR     [TB_MENU]
        RTS
tb_act_undo:
        CMPA    JR_KEY_BACK
        BNE     tb_act_cut
        JMP     tb_undo
tb_act_cut:
        CMPA    8
        BNE     tb_act_move
        JMP     tb_execute
tb_act_move:
        CMPA    JR_KEY_RIGHT
        BHI     tb_act_done
        JMP     tb_step
tb_act_done:
        RTS

tb_act_menu:
        CMPB    TB_SUB_MENU
        BNE     tb_act_question
        CMPA    JR_KEY_UP
        BNE     tb_act_menu_down
        DEC     [TB_MENU]
        BPL     tb_act_done
        LDAA    4
        STAA    [TB_MENU]
        RTS
tb_act_menu_down:
        CMPA    JR_KEY_DOWN
        BNE     tb_act_menu_back
        INC     [TB_MENU]
        LDAA    [TB_MENU]
        CMPA    5
        BCS     tb_act_done
        CLR     [TB_MENU]
        RTS
tb_act_menu_back:
        CMPA    JR_KEY_BACK
        BEQ     tb_close_menu
        CMPA    JR_KEY_CONFIRM
        BNE     tb_act_done
        LDAA    [TB_MENU]
        BNE     tb_act_menu_undo
        JMP     tb_execute
tb_act_menu_undo:
        CMPA    1
        BNE     tb_act_menu_reset
        JMP     tb_undo
tb_act_menu_reset:
        CMPA    4
        BEQ     tb_close_menu
        ADDA    1                   ; 2 RESET -> 3, 3 TITLE -> 4
        STAA    [TB_SUB]
        CLR     [TB_CHOICE]
        RTS
tb_close_menu:
        CLR     [TB_SUB]
        RTS

; RESET? / TITLE?: A picks YES, D picks NO, RETURN answers, SPACE cancels.
tb_act_question:
        CMPB    TB_SUB_CUT
        BEQ     tb_act_done
        CMPA    JR_KEY_LEFT
        BNE     tb_act_question_no
        LDAA    1
        STAA    [TB_CHOICE]
        RTS
tb_act_question_no:
        CMPA    JR_KEY_RIGHT
        BNE     tb_act_question_back
        CLR     [TB_CHOICE]
        RTS
tb_act_question_back:
        CMPA    JR_KEY_BACK
        BEQ     tb_act_question_menu
        CMPA    JR_KEY_CONFIRM
        BNE     tb_act_done
        TST     [TB_CHOICE]
        BNE     tb_act_question_yes
tb_act_question_menu:
        LDAA    TB_SUB_MENU
        STAA    [TB_SUB]
        RTS
tb_act_question_yes:
        LDAA    [TB_SUB]
        CMPA    TB_SUB_RESET
        BNE     tb_act_title
        LDX     tb_sfx_undo
        JSR     jr_sfx_play
        JMP     tb_reset_path
tb_act_title:
        ; leave the stage for the title: drop game_act's return address
        INS
        INS
        JMP     jr_port_title

tb_invalid:
        LDAA    1
        STAA    [TB_ERROR]
        LDX     tb_sfx_empty
        JMP     jr_sfx_play

; X = base, A = cell -> X = base + cell, A = [X].
tb_at:
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

; A = cell -> TB_X, TB_Y.
tb_place:
        CLR     [TB_Y]
tb_place_row:
        CMPA    12
        BCS     tb_place_done
        SUBA    12
        INC     [TB_Y]
        BRA     tb_place_row
tb_place_done:
        STAA    [TB_X]
        RTS

; ADD_STEP: walls and visited cells refuse the step.
tb_step:
        LDAA    [TB_Y]
        LDAB    12
        JSR     jr_mul8
        ADDA    [TB_X]
        LDAB    [TB_K]
        CMPB    JR_KEY_UP
        BNE     tb_step_down
        SUBA    12
        BRA     tb_step_try
tb_step_down:
        CMPB    JR_KEY_DOWN
        BNE     tb_step_left
        ADDA    12
        BRA     tb_step_try
tb_step_left:
        CMPB    JR_KEY_LEFT
        BNE     tb_step_right
        DECA
        BRA     tb_step_try
tb_step_right:
        INCA
tb_step_try:
        STAA    [TB_CELL]
        LDX     TB_MAP
        JSR     tb_at
        CMPA    1
        BEQ     tb_invalid
        LDAA    [TB_CELL]
        LDX     TB_SEEN
        JSR     tb_at
        TSTA
        BNE     tb_invalid
        LDAA    1
        STAA    [X]
        INC     [TB_LEN]
        LDAA    [TB_LEN]
        LDX     TB_TRAIL
        JSR     jr_add_x_a
        LDAA    [TB_CELL]
        STAA    [X]
        LDX     TB_MAP
        JSR     tb_at
        CMPA    2
        BNE     tb_step_move
        INC     [TB_MARKED]
tb_step_move:
        LDAA    [TB_CELL]
        JSR     tb_place
        CLR     [TB_ERROR]
        LDX     tb_sfx_step
        JMP     jr_sfx_play

tb_undo:
        LDAA    [TB_LEN]
        BNE     tb_invalid_near357
        JMP     tb_invalid
tb_invalid_near357:
        LDX     TB_TRAIL
        JSR     tb_at
        STAA    [TB_CELL]
        LDX     TB_SEEN
        JSR     jr_add_x_a
        CLR     [X]
        LDAA    [TB_CELL]
        LDX     TB_MAP
        JSR     tb_at
        CMPA    2
        BNE     tb_undo_back
        DEC     [TB_MARKED]
tb_undo_back:
        DEC     [TB_LEN]
        LDAA    [TB_LEN]
        LDX     TB_TRAIL
        JSR     tb_at
        JSR     tb_place
        CLR     [TB_SUB]
        CLR     [TB_ERROR]
        LDX     tb_sfx_undo
        JMP     jr_sfx_play

; EXECUTE: every target marked and the path ends on the exit; then the
; blade follows the path, one cell every five frames, and cuts the targets.
tb_execute:
        LDAA    [TB_MARKED]
        CMPA    [TB_TARGETS]
        BNE     tb_execute_refused
        LDAA    [TB_Y]
        LDAB    12
        JSR     jr_mul8
        ADDA    [TB_X]
        LDX     TB_MAP
        JSR     tb_at
        CMPA    3
        BEQ     tb_execute_go
tb_execute_refused:
        JMP     tb_invalid
tb_execute_go:
        LDAA    TB_SUB_CUT
        STAA    [TB_SUB]
        CLR     [TB_COMBO]
        CLR     [TB_POS]
tb_execute_step:
        INC     [TB_POS]
        LDAA    [TB_POS]
        LDX     TB_TRAIL
        JSR     tb_at
        STAA    [TB_CELL]
        JSR     tb_place
        LDAA    TB_STEP_FRAMES
        JSR     jr_test_animate
        LDAA    [TB_CELL]
        LDX     TB_MAP
        JSR     tb_at
        CMPA    2
        BNE     tb_execute_next
        CLR     [X]
        INC     [TB_COMBO]
        LDX     tb_sfx_cut
        JSR     jr_sfx_play
        LDAA    1
        STAA    [TB_FX]
tb_execute_burst:
        LDAA    TB_BURST_FRAMES
        JSR     jr_test_animate
        INC     [TB_FX]
        LDAA    [TB_FX]
        CMPA    4
        BNE     tb_execute_burst
        CLR     [TB_FX]
tb_execute_next:
        LDAA    [TB_POS]
        CMPA    [TB_LEN]
        BNE     tb_execute_step
        JMP     jr_port_win

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    TB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     tb_hud
        JSR     jr_gfx_lines
        LDAA    TB_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [JR_PORT_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; the numbers under TARGET, MARKED, PATH and COMBO
        LDAA    TB_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    26
        LDAB    4
        JSR     jr_gfx_at
        LDAA    [TB_TARGETS]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [TB_MARKED]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    10
        JSR     jr_gfx_at
        LDAA    [TB_LEN]
        JSR     jr_gfx_dec2
        LDAA    26
        LDAB    13
        JSR     jr_gfx_at
        LDAA    [TB_COMBO]
        JSR     jr_gfx_dec2
        ; the room, two columns and two rows per cell from row 2, written
        ; straight into the shadow screen (codes, and attributes 0x300 on)
        LDX     TB_MAP
        STX     [TB_PTR]
        LDX     JR_SHADOW + 64
        STX     [TB_SCR]
        LDX     JR_SHADOW + 0x340
        STX     [TB_ATR]
        LDAA    12
        STAA    [TB_COL]
        LDAA    108
        STAA    [TB_I]
tb_draw_cell:
        LDX     [TB_PTR]
        LDAB    [X]
        ASLB
        TST     [X + 108]           ; on the path
        BEQ     tb_draw_look
        CMPB    4                   ; a target: corner marks
        BEQ     tb_draw_mark
        TSTB
        BNE     tb_draw_look
        LDAB    8                   ; floor: trail
        BRA     tb_draw_look
tb_draw_mark:
        LDAB    10
tb_draw_look:
        INX
        STX     [TB_PTR]
        LDX     tb_cell_tiles
        STAB    [TB_CODE]
        LDAA    [TB_CODE]
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    [X + 1]
        LDX     [TB_ATR]
        STAB    [X]
        STAB    [X + 1]
        STAB    [X + 32]
        STAB    [X + 33]
        INX
        INX
        STX     [TB_ATR]
        LDX     [TB_SCR]
        STAA    [X]
        INCA
        STAA    [X + 1]
        INCA
        STAA    [X + 32]
        INCA
        STAA    [X + 33]
        INX
        INX
        DEC     [TB_COL]
        BNE     tb_draw_same_row
        LDAA    12
        STAA    [TB_COL]
        LDAA    40
        JSR     jr_add_x_a
        STX     [TB_SCR]
        LDX     [TB_ATR]
        LDAA    40
        JSR     jr_add_x_a
        STX     [TB_ATR]
        BRA     tb_draw_row_done
tb_draw_same_row:
        STX     [TB_SCR]
tb_draw_row_done:
        DEC     [TB_I]
        BNE     tb_draw_cell
        ; the blade, or the burst of a cut target
        LDAA    TB_ATTR_BLADE
        LDAB    TB_TILE_BLADE
        TST     [TB_FX]
        BEQ     tb_draw_blade
        LDAA    [TB_FX]
        DECA
        ASLA
        ASLA
        ADDA    TB_TILE_FLASH
        TAB
        LDAA    TB_ATTR_BURST
tb_draw_blade:
        STAA    [JR_RT_COLOR]
        STAB    [TB_CODE]
        LDAA    [TB_X]
        ASLA
        LDAB    [TB_Y]
        ASLB
        ADDB    2
        JSR     jr_gfx_at
        LDAA    [TB_CODE]
        JSR     jr_gfx_tile
        ; the menu and its questions
        LDAA    [TB_SUB]
        BEQ     tb_draw_message
        CMPA    TB_SUB_CUT
        BEQ     tb_draw_message
        LDX     tb_menu_lines
        JSR     jr_gfx_lines
        LDAA    TB_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [TB_MENU]
        ADDA    15
        TAB
        LDAA    25
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDAA    [TB_SUB]
        CMPA    TB_SUB_RESET
        BCS     tb_draw_message
        BNE     tb_draw_ask_title
        LDX     tb_ask_reset_lines
        BRA     tb_draw_question
tb_draw_ask_title:
        LDX     tb_ask_title_lines
tb_draw_question:
        JSR     jr_gfx_lines
        LDAA    TB_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    14
        TST     [TB_CHOICE]
        BNE     tb_draw_choice
        LDAA    20
tb_draw_choice:
        LDAB    20
        JSR     jr_gfx_at
        LDAA    0x3e
        JMP     jr_gfx_putc
tb_draw_message:
        LDX     tb_txt_strike
        LDAA    [TB_SUB]
        CMPA    TB_SUB_CUT
        BNE     tb_draw_error
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     tb_draw_text
        LDX     tb_txt_end
        CMPA    JR_MODE_END
        BEQ     tb_draw_text
        RTS
tb_draw_error:
        TST     [TB_ERROR]
        BEQ     tb_draw_done
        LDX     tb_txt_error
tb_draw_text:
        STX     [TB_PTR]
        LDAA    TB_ATTR_BAD
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    21
        JSR     jr_gfx_at
        LDX     [TB_PTR]
        JMP     jr_gfx_text
tb_draw_done:
        RTS

game_draw_title:
        LDX     tb_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    TB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     tb_title_tiles
        STX     [TB_PTR]
tb_title_tile:
        LDX     [TB_PTR]
        LDAA    [X]
        CMPA    0xff
        BEQ     tb_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [TB_CODE]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [TB_CODE]
        JSR     jr_gfx_tile
        LDX     [TB_PTR]
        INX
        INX
        INX
        INX
        STX     [TB_PTR]
        BRA     tb_title_tile
tb_title_text:
        LDX     tb_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    TB_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     tb_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

game_key_table:
        .db     0x66, 8, 0          ; F: cut

; map value (then trail, marked target) -> tile, attribute
tb_cell_tiles:
        .db     TB_TILE_FLOOR, TB_ATTR_FLOOR, TB_TILE_WALL, TB_ATTR_WALL
        .db     TB_TILE_TARGET, TB_ATTR_TARGET, TB_TILE_EXIT, TB_ATTR_EXIT
        .db     TB_TILE_TRAIL, TB_ATTR_TRAIL, TB_TILE_MARKED, TB_ATTR_MARKED

; x, attribute, code, y: the blade cutting through a line of targets
tb_title_tiles:
        .db     6, TB_ATTR_TRAIL, TB_TILE_TRAIL, 4
        .db     9, TB_ATTR_BURST, TB_TILE_FLASH, 4
        .db     12, TB_ATTR_TRAIL, TB_TILE_TRAIL, 4
        .db     15, TB_ATTR_BLADE, TB_TILE_BLADE, 4
        .db     18, TB_ATTR_TARGET, TB_TILE_TARGET, 4
        .db     21, TB_ATTR_TARGET, TB_TILE_TARGET, 4
        .db     24, TB_ATTR_EXIT, TB_TILE_EXIT, 4
        .db     0xff

tb_hud:
        .db     1, 0, TB_ATTR_TITLE
        .dw     tb_txt_name
        .db     25, 0, TB_ATTR_LABEL
        .dw     tb_txt_cut
        .db     25, 3, TB_ATTR_LABEL
        .dw     tb_txt_target
        .db     25, 6, TB_ATTR_LABEL
        .dw     tb_txt_marked
        .db     25, 9, TB_ATTR_LABEL
        .dw     tb_txt_path
        .db     25, 12, TB_ATTR_LABEL
        .dw     tb_txt_combo
        .db     1, 22, TB_ATTR_DIM
        .dw     tb_txt_keys
        .db     0xff
tb_menu_lines:
        .db     26, 15, TB_ATTR_TEXT
        .dw     tb_txt_menu_cut
        .db     26, 16, TB_ATTR_TEXT
        .dw     tb_txt_menu_undo
        .db     26, 17, TB_ATTR_TEXT
        .dw     tb_txt_menu_reset
        .db     26, 18, TB_ATTR_TEXT
        .dw     tb_txt_menu_title
        .db     26, 19, TB_ATTR_TEXT
        .dw     tb_txt_menu_back
        .db     0xff
tb_ask_reset_lines:
        .db     1, 20, TB_ATTR_TITLE
        .dw     tb_txt_ask_reset
        .db     0xff
tb_ask_title_lines:
        .db     1, 20, TB_ATTR_TITLE
        .dw     tb_txt_ask_title
        .db     0xff
tb_title_lines:
        .db     10, 8, TB_ATTR_TITLE
        .dw     tb_txt_name
        .db     4, 10, TB_ATTR_LABEL
        .dw     tb_txt_tagline
        .db     8, 14, TB_ATTR_TEXT
        .dw     tb_txt_start
        .db     4, 16, TB_ATTR_TEXT
        .dw     tb_txt_howto
        .db     4, 19, TB_ATTR_DIM
        .dw     tb_txt_test
        .db     4, 22, TB_ATTR_DIM
        .dw     tb_txt_credit
        .db     0xff
tb_help_lines:
        .db     10, 1, TB_ATTR_TITLE
        .dw     tb_txt_name
        .db     1, 3, TB_ATTR_TEXT
        .dw     tb_help_1
        .db     1, 5, TB_ATTR_TEXT
        .dw     tb_help_2
        .db     1, 7, TB_ATTR_TEXT
        .dw     tb_help_3
        .db     1, 9, TB_ATTR_TEXT
        .dw     tb_help_4
        .db     1, 11, TB_ATTR_TEXT
        .dw     tb_help_5
        .db     1, 13, TB_ATTR_TEXT
        .dw     tb_help_6
        .db     1, 15, TB_ATTR_TEXT
        .dw     tb_help_7
        .db     1, 17, TB_ATTR_TEXT
        .dw     tb_help_8
        .db     1, 21, TB_ATTR_LABEL
        .dw     tb_help_back
        .db     0xff

tb_txt_name:
        .db     "TRACE BLADE", 0
tb_txt_cut:
        .db     "CUT", 0
tb_txt_target:
        .db     "TARGET", 0
tb_txt_marked:
        .db     "MARKED", 0
tb_txt_path:
        .db     "PATH", 0
tb_txt_combo:
        .db     "COMBO", 0
tb_txt_keys:
        .db     "SPC UNDO  F CUT  RET MENU", 0
tb_txt_menu_cut:
        .db     "CUT", 0
tb_txt_menu_undo:
        .db     "UNDO", 0
tb_txt_menu_reset:
        .db     "RESET", 0
tb_txt_menu_title:
        .db     "TITLE", 0
tb_txt_menu_back:
        .db     "BACK", 0
tb_txt_ask_reset:
        .db     "RESET PATH?   YES   NO", 0
tb_txt_ask_title:
        .db     "TO TITLE?     YES   NO", 0
tb_txt_error:
        .db     "CHECK PATH AND ALL TARGETS", 0
tb_txt_strike:
        .db     "STRIKE IN MOTION", 0
tb_txt_end:
        .db     "ALL THIRTY ROOMS CUT", 0
tb_txt_tagline:
        .db     "ONE STROKE, EVERY TARGET", 0
tb_txt_start:
        .db     "RETURN : START", 0
tb_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
tb_txt_test:
        .db     "T : SELF TEST", 0
tb_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
tb_help_1:
        .db     "W/A/S/D: EXTEND THE PATH.", 0
tb_help_2:
        .db     "WALLS AND USED CELLS BLOCK IT.", 0
tb_help_3:
        .db     "SPACE: UNDO ONE STEP.", 0
tb_help_4:
        .db     "PASS EVERY RED TARGET AND END", 0
tb_help_5:
        .db     "ON THE EXIT, THEN F: CUT.", 0
tb_help_6:
        .db     "RETURN: MENU (CUT UNDO RESET", 0
tb_help_7:
        .db     "TITLE BACK), W/S AND RETURN.", 0
tb_help_8:
        .db     "THIRTY ROOMS. ESC: BASIC.", 0
tb_help_back:
        .db     "ANY KEY : TITLE", 0

        .include "rooms.inc"
        .include "selftest.inc"

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     tb_sfx_step, tb_sfx_cut, tb_jingle_win, tb_jingle_win
tb_sfx_step:
        .db     80, 1, 0, 0
tb_sfx_empty:
        .db     220, 2, 250, 4, 0, 0
tb_sfx_undo:
        .db     100, 1, 130, 2, 0, 0
tb_sfx_cut:
        .db     20, 1, 40, 1, 30, 1, 60, 3, 0, 0

; Title: a march in E minor, eighth note = 8 frames, looping.
tb_title_song:
        .db     1
        .dw     tb_title_melody, tb_title_harmony, tb_title_bass
tb_title_melody:
        .db     AU_E5, 8, AU_E5, 8, AU_G5, 8, AU_B5, 8, AU_A5, 16, AU_G5, 8, AU_FS5, 8
        .db     AU_E5, 16, AU_B4, 16, AU_E5, 32
        .db     AU_G5, 8, AU_G5, 8, AU_B5, 8, AU_D6, 8, AU_C6, 16, AU_B5, 8, AU_A5, 8
        .db     AU_B5, 16, AU_DS5, 16, AU_E5, 32, 0, 0
tb_title_harmony:
        .db     AU_B4, 32, AU_C5, 32, AU_B4, 32, AU_G4, 32
        .db     AU_D5, 32, AU_E5, 32, AU_FS4, 32, AU_G4, 32, 0, 0
tb_title_bass:
        .db     AU_E3, 16, AU_B2, 16, AU_A2, 16, AU_C3, 16, AU_E3, 16, AU_B2, 16, AU_E2, 32
        .db     AU_G2, 16, AU_D3, 16, AU_A2, 16, AU_E3, 16, AU_B2, 32, AU_E2, 32, 0, 0

; Room cut: a rising E major flourish.
tb_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     tb_win_melody, tb_win_harmony, tb_win_bass
tb_win_melody:
        .db     AU_B5, 6, AU_E6, 6, AU_GS6, 6, AU_B6, 30, 0, 0
tb_win_harmony:
        .db     AU_GS5, 6, AU_B5, 6, AU_E6, 6, AU_GS6, 30, 0, 0
tb_win_bass:
        .db     AU_E3, 18, AU_E2, 30, 0, 0

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
        .include "../../../sdk/selftest.inc"
        .include "../../../sdk/font_data.inc"
