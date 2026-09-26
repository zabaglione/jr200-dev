; SPDX-License-Identifier: BSD-3-Clause
; Development self test and scripted demo for real-time ports on port.inc.
; Requires port.inc (and what it requires) and session.inc.
;
; Key and tick timing depends on cycles, so real-time rules are checked inside
; the program instead of by timed key replays:
;   fixtures  start a stage, write (state offset, value) pairs, apply one
;             operation and store GAME_TEST_SIZE state bytes and the mode;
;   scripts   play each stage from its start with a tick-synchronised input
;             script and store the state, the mode and the tick count.
; tests/selftest_model.py runs the same data on the Python model. Nothing is
; drawn and effects are skipped while JR_TEST_QUIET is set.
;
; Operation byte: 0 = one game_tick; 1-15 = game_act with that action;
; 0x80 + h = store h at GAME_TEST_HELD (held direction), then one game_tick.
; Fixture table: level, operation, pair count, pairs; 0xFF ends.
; Script (one per stage, .dw table game_scripts): (wait, operation) entries,
; 0xFF ends. Before each tick the next entry's wait counts down; at 0 its
; operation is applied (a held operation only stores h and does not tick).
; After the script the stage keeps ticking until it leaves play or reaches
; GAME_TEST_LIMIT ticks (a 16-bit count).
;
; The game supplies:
;   JR_TEST (16 bytes outside GAME_STATE), JR_TEST_OUT (result address),
;   GAME_TEST_SIZE, GAME_TEST_LIMIT, GAME_TEST_HELD, game_fixtures,
;   game_scripts, game_test_draw (the title for the progress message);
;   game_raw_key may JMP jr_test_raw_key (T runs the test, P plays the
;   stage-1 demo); game_init calls jr_test_level; game_tick starts with
;   JSR jr_test_demo_step and returns unless JR_PORT_MODE is still play (a
;   scripted input can end the stage); effects use jr_test_animate /
;   jr_test_hold.
;
; jr_test_init       from the game's start, before jr_port_run
; jr_test_run        run fixtures and scripts, then show the title (A = 0)
; jr_test_raw_key    B = raw title key -> A = action (P) or 0
; jr_test_level      from game_init: arms the demo for one stage only
; jr_test_demo_step  from game_tick: applies the demo script's due inputs
; jr_test_animate    jr_port_animate unless quiet
; jr_test_hold       jr_port_hold unless quiet

JR_TEST_QUIET:      .equ    JR_TEST
JR_TEST_DEMO:       .equ    JR_TEST + 1     ; 1 armed, 2 playing, 0 off
JR_TEST_SCRIPT:     .equ    JR_TEST + 2
JR_TEST_WAIT:       .equ    JR_TEST + 4
JR_TEST_FIX:        .equ    JR_TEST + 6
JR_TEST_PTR:        .equ    JR_TEST + 8
JR_TEST_TICKS:      .equ    JR_TEST + 10
JR_TEST_STAGE:      .equ    JR_TEST + 12
JR_TEST_PAIRS:      .equ    JR_TEST + 13
JR_TEST_MSG:        .equ    JR_TEST + 14

jr_test_init:
        CLR     [JR_TEST_QUIET]
        CLR     [JR_TEST_DEMO]
        RTS

jr_test_raw_key:
        TBA
        ORAA    0x20
        CMPA    0x74
        BEQ     jr_test_run
        CMPA    0x70
        BNE     jr_test_raw_ignore
        LDAA    1
        STAA    [JR_TEST_DEMO]
        LDAA    JR_KEY_CONFIRM
        RTS
jr_test_raw_ignore:
        CLRA
        RTS

jr_test_run:
        LDAA    1
        STAA    [JR_TEST_QUIET]
        CLR     [JR_TEST_DEMO]
        LDX     jr_test_txt_running
        JSR     jr_test_message
        LDX     game_fixtures
        STX     [JR_TEST_FIX]
        LDX     JR_TEST_OUT
        STX     [JR_TEST_PTR]
jr_test_fixture:
        LDX     [JR_TEST_FIX]
        LDAA    [X]
        CMPA    0xff
        BEQ     jr_test_scripts
        JSR     jr_test_start
        LDX     [JR_TEST_FIX]
        LDAA    [X + 1]
        STAA    [JR_TEST_STAGE]
        LDAA    [X + 2]
        STAA    [JR_TEST_PAIRS]
        INX
        INX
        INX
jr_test_pair:
        TST     [JR_TEST_PAIRS]
        BEQ     jr_test_fixture_op
        LDAA    [X]
        LDAB    [X + 1]
        INX
        INX
        STX     [JR_TEST_FIX]
        LDX     GAME_STATE
        JSR     jr_add_x_a
        STAB    [X]
        LDX     [JR_TEST_FIX]
        DEC     [JR_TEST_PAIRS]
        BRA     jr_test_pair
jr_test_fixture_op:
        STX     [JR_TEST_FIX]
        LDAA    [JR_TEST_STAGE]
        JSR     jr_test_op_tick
        JSR     jr_test_store
        BRA     jr_test_fixture
jr_test_scripts:
        CLR     [JR_TEST_STAGE]
jr_test_next_stage:
        LDAA    [JR_TEST_STAGE]
        JSR     jr_test_start
        LDAA    [JR_TEST_STAGE]
        JSR     jr_test_script_load
        CLR     [JR_TEST_TICKS]
        CLR     [JR_TEST_TICKS + 1]
jr_test_stage_tick:
        JSR     jr_test_script_due
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     jr_test_stage_store
        JSR     game_tick
        LDX     [JR_TEST_TICKS]
        INX
        STX     [JR_TEST_TICKS]
        LDAA    [JR_TEST_TICKS + 1]
        BNE     jr_test_stage_check
        JSR     jr_keys_poll
        CMPA    JR_KEY_EXIT
        BNE     jr_test_stage_check
        JMP     jr_session_leave
jr_test_stage_check:
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     jr_test_stage_store
        LDX     [JR_TEST_TICKS]
        CPX     GAME_TEST_LIMIT
        BNE     jr_test_stage_tick
jr_test_stage_store:
        JSR     jr_test_store
        LDX     [JR_TEST_PTR]
        LDAA    [JR_TEST_TICKS]
        STAA    [X]
        LDAA    [JR_TEST_TICKS + 1]
        STAA    [X + 1]
        INX
        INX
        STX     [JR_TEST_PTR]
        INC     [JR_TEST_STAGE]
        LDAA    [JR_TEST_STAGE]
        CMPA    GAME_LEVELS
        BNE     jr_test_next_stage
        CLR     [JR_TEST_QUIET]
        CLR     [JR_PORT_MODE]
        CLR     [JR_PORT_LEVEL]
        JSR     jr_sfx_stop
        LDX     jr_test_txt_done
        JSR     jr_test_message
        CLRA
        RTS

; A = operation: act, or store the held direction and tick, or tick.
jr_test_op_tick:
        TSTA
        BEQ     jr_test_op_tick_run
        BPL     jr_test_op_act
        ANDA    0x7f
        STAA    [GAME_TEST_HELD]
jr_test_op_tick_run:
        JMP     game_tick
jr_test_op_act:
        JMP     game_act

; A = stage: point JR_TEST_SCRIPT at its script and load the first wait.
jr_test_script_load:
        ASLA
        LDX     game_scripts
        JSR     jr_add_x_a
        LDX     [X]
        STX     [JR_TEST_SCRIPT]
        LDAA    [X]
        STAA    [JR_TEST_WAIT]
        RTS

; Apply every script entry whose wait has run out, then count one tick down.
jr_test_script_due:
        LDX     [JR_TEST_SCRIPT]
        LDAA    [X]
        CMPA    0xff
        BEQ     jr_test_script_done
        TST     [JR_TEST_WAIT]
        BNE     jr_test_script_count
        LDAA    [X + 1]
        INX
        INX
        STX     [JR_TEST_SCRIPT]
        LDAB    [X]
        STAB    [JR_TEST_WAIT]
        TSTA
        BPL     jr_test_script_act
        ANDA    0x7f
        STAA    [GAME_TEST_HELD]
        BRA     jr_test_script_due
jr_test_script_act:
        JSR     game_act
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     jr_test_script_due
        RTS
jr_test_script_count:
        DEC     [JR_TEST_WAIT]
jr_test_script_done:
        RTS

; A = stage: clear the stage state and run game_init, like port.inc.
jr_test_start:
        STAA    [JR_PORT_LEVEL]
        LDX     GAME_STATE
jr_test_start_clear:
        CLR     [X]
        INX
        CPX     GAME_STATE_END
        BNE     jr_test_start_clear
        LDAA    JR_MODE_PLAY
        STAA    [JR_PORT_MODE]
        JMP     game_init

; Copy GAME_TEST_SIZE state bytes and the mode to JR_TEST_PTR and advance it.
jr_test_store:
        LDX     GAME_STATE
        STX     [JR_RT_SRC]
        LDX     [JR_TEST_PTR]
        STX     [JR_RT_DST]
        LDX     GAME_TEST_SIZE
        STX     [JR_RT_COUNT]
        JSR     jr_copy
        LDX     [JR_RT_COUNT]
        LDAA    [JR_PORT_MODE]
        STAA    [X]
        INX
        STX     [JR_TEST_PTR]
        RTS

jr_test_message:
        STX     [JR_TEST_MSG]
        JSR     game_test_draw
        LDAA    0x06
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    GAME_STATUS_ROW
        JSR     jr_gfx_at
        LDX     [JR_TEST_MSG]
        JSR     jr_gfx_text
        JMP     jr_gfx_present

; From game_init: a demo armed on the title plays this stage only.
jr_test_level:
        LDAA    [JR_TEST_DEMO]
        BEQ     jr_test_level_done
        CMPA    1
        BNE     jr_test_level_off
        INC     [JR_TEST_DEMO]
        LDAA    [JR_PORT_LEVEL]
        JMP     jr_test_script_load
jr_test_level_off:
        CLR     [JR_TEST_DEMO]
jr_test_level_done:
        RTS

; From game_tick (before the rules): feed the demo script.
jr_test_demo_step:
        LDAA    [JR_TEST_DEMO]
        CMPA    2
        BNE     jr_test_level_done
        LDAA    [JR_TEST_QUIET]
        BNE     jr_test_level_done
        JMP     jr_test_script_due

jr_test_animate:
        TST     [JR_TEST_QUIET]
        BNE     jr_test_level_done
        JMP     jr_port_animate

jr_test_hold:
        TST     [JR_TEST_QUIET]
        BNE     jr_test_level_done
        JMP     jr_port_hold

jr_test_txt_running:
        .db     "SELF TEST RUNNING", 0
jr_test_txt_done:
        .db     "SELF TEST DONE", 0
