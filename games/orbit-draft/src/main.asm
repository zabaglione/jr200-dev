; SPDX-License-Identifier: MIT
; ORBIT DRAFT for JR-200: a port of jr100dev games/orbit_draft/rules.py 3.0.1.
; The seeded card stream, the drop, row and column spins, three-in-a-line
; clears, falling chains, spins, score and the rising goal follow the
; upstream source; display, colour and three-voice sound use the JR-200 port
; SDK. Upstream's entropy() (the JR-100 timer) is replaced by the position of
; the title song when a game starts.
;
; Upstream is endless: after a clear, RETURN calls advance() and keeps the
; board and score. sdk/port.inc starts every stage from a cleared work area,
; so the upstream state lives outside it (OR_KEEP); game_init continues when
; the port has just moved one stage past the kept level, and otherwise starts
; over at level 0 like upstream's init().
        .filename.jr "ORBIT-DRAFT"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4700
JR_AUDIO:           .equ    0x4700
OR_LOG:             .equ    0x4720      ; count, then each sampled origin
OR_LOG_MAX:         .equ    31
OR_KEEP:            .equ    0x4740      ; upstream state, kept between stages
OR_KEEP_SIZE:       .equ    81
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    255
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2

; Upstream state (same order as tests/model.py), then b[16], c[16], d[21].
OR_LEVEL:           .equ    OR_KEEP
OR_ORIGIN:          .equ    OR_KEEP + 1
OR_RNG_LO:          .equ    OR_KEEP + 2
OR_RNG_HI:          .equ    OR_KEEP + 3
OR_SPINS:           .equ    OR_KEEP + 4
OR_TARGET:          .equ    OR_KEEP + 5
OR_PROGRESS:        .equ    OR_KEEP + 6
OR_LINES:           .equ    OR_KEEP + 7
OR_FALLING:         .equ    OR_KEEP + 8
OR_SLIDE:           .equ    OR_KEEP + 9
OR_POINTS:          .equ    OR_KEEP + 10
OR_SCORE_LO:        .equ    OR_KEEP + 11
OR_SCORE_HI:        .equ    OR_KEEP + 12
OR_CHAIN:           .equ    OR_KEEP + 13
OR_GLOW:            .equ    OR_KEEP + 14
OR_NOTICE:          .equ    OR_KEEP + 15
OR_TOOL:            .equ    OR_KEEP + 16
OR_PHASE:           .equ    OR_KEEP + 17
OR_CURSOR:          .equ    OR_KEEP + 18
OR_CELL:            .equ    OR_KEEP + 19
OR_OFFER:           .equ    OR_KEEP + 20
OR_CARD:            .equ    OR_KEEP + 21
OR_FLYING:          .equ    OR_KEEP + 22
OR_FX:              .equ    OR_KEEP + 23
OR_FY:              .equ    OR_KEEP + 24
OR_AXIS:            .equ    OR_KEEP + 25
OR_ORBIT:           .equ    OR_KEEP + 26
OR_ROTATING:        .equ    OR_KEEP + 27
OR_B:               .equ    OR_KEEP + 28
OR_C:               .equ    OR_KEEP + 44
OR_D:               .equ    OR_KEEP + 60
; Rule work bytes (cleared each stage).
OR_I:               .equ    GAME_STATE
OR_K:               .equ    GAME_STATE + 1
OR_T:               .equ    GAME_STATE + 2
OR_CHANGED:         .equ    GAME_STATE + 3
OR_STEP:            .equ    GAME_STATE + 4
OR_FRAME:           .equ    GAME_STATE + 5
OR_WAVE:            .equ    GAME_STATE + 6
OR_COUNT:           .equ    GAME_STATE + 7
OR_FIRST:           .equ    GAME_STATE + 8
OR_STRIDE:          .equ    GAME_STATE + 9
OR_LAST:            .equ    GAME_STATE + 10
OR_SAVED:           .equ    GAME_STATE + 11
OR_POS:             .equ    GAME_STATE + 12
OR_BOTTOM:          .equ    GAME_STATE + 13
OR_A:               .equ    GAME_STATE + 14
OR_M:               .equ    GAME_STATE + 15
OR_E:               .equ    GAME_STATE + 16
OR_DEALT:           .equ    GAME_STATE + 17
; Drawing work bytes.
OR_DI:              .equ    GAME_STATE + 32
OR_DQ:              .equ    GAME_STATE + 33
OR_DX:              .equ    GAME_STATE + 34
OR_DY:              .equ    GAME_STATE + 35
OR_DCODE:           .equ    GAME_STATE + 36
OR_DCOL:            .equ    GAME_STATE + 37
OR_DROW:            .equ    GAME_STATE + 38

OR_EMPTY:           .equ    0xff
OR_TILE_CARD:       .equ    0x80        ; + 4 * kind
OR_TILE_BURST:      .equ    0x94        ; + 4 * phase
OR_ATTR_BURST:      .equ    0x47
OR_ATTR_TEXT:       .equ    0x07
OR_ATTR_LABEL:      .equ    0x04
OR_ATTR_TITLE:      .equ    0x06
OR_ATTR_DIM:        .equ    0x05
OR_ATTR_PICK:       .equ    0x06
OR_ATTR_GOOD:       .equ    0x04
OR_ATTR_BAD:        .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        CLR     [OR_LOG]
        LDAA    0xfe
        STAA    [OR_LEVEL]
        JSR     jr_font_install
        LDX     or_patterns
        LDAA    OR_TILE_CARD
        LDAB    32
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        ; continue after a clear: the port has just moved one stage on
        LDAA    [JR_PORT_LEVEL]
        BEQ     or_init_fresh
        LDAB    [OR_LEVEL]
        INCB
        CBA
        BNE     or_init_fresh
        JMP     or_advance
or_init_fresh:
        ; origin = entropy(): (voice 0 offset * 8 + frames left) of the song
        LDAA    [JR_AU_VOICE + 1]
        SUBA    [JR_AU_VOICE + 4]
        ASLA
        ASLA
        ASLA
        ADDA    [JR_AU_VOICE + 2]
        PSHA
        JSR     jr_music_stop
        LDX     OR_KEEP
or_init_clear:
        CLR     [X]
        INX
        CPX     OR_KEEP + OR_KEEP_SIZE
        BNE     or_init_clear
        CLR     [JR_PORT_LEVEL]
        PULA
        STAA    [OR_ORIGIN]
        LDAB    [OR_LOG]
        CMPB    OR_LOG_MAX
        BCC     or_init_rng
        INC     [OR_LOG]
        LDX     OR_LOG + 1
        LDAA    [OR_LOG]
        DECA
        JSR     jr_add_x_a
        LDAA    [OR_ORIGIN]
        STAA    [X]
or_init_rng:
        LDAA    [OR_ORIGIN]
        ORAA    1
        STAA    [OR_RNG_LO]
        LDAA    [OR_ORIGIN]
        EORA    165
        STAA    [OR_RNG_HI]
        LDAA    2
        STAA    [OR_SPINS]
        LDAA    12
        STAA    [OR_TARGET]
        LDX     OR_B
        LDAA    OR_EMPTY
or_init_board:
        STAA    [X]
        INX
        CPX     OR_B + 16
        BNE     or_init_board
        ; the bottom row: first, first + 1, ... (mod 5)
        JSR     or_deal
        STAA    [OR_DEALT]
        CLR     [OR_I]
or_init_row:
        LDAA    [OR_DEALT]
        ADDA    [OR_I]
        JSR     or_mod5
        LDAB    [OR_I]
        LDX     OR_B + 12
        PSHA
        TBA
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        INC     [OR_I]
        LDAA    [OR_I]
        CMPA    4
        BNE     or_init_row
        CLR     [OR_I]
or_init_offer:
        JSR     or_deal
        PSHA
        LDAA    [OR_I]
        LDX     OR_D + 16
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        INC     [OR_I]
        LDAA    [OR_I]
        CMPA    5
        BNE     or_init_offer
        LDAA    [OR_DEALT]
        ADDA    4
        JSR     or_mod5
        STAA    [OR_D + 16]
        LDAA    [OR_D + 17]
        ANDA    3
        ADDA    [OR_DEALT]
        JSR     or_mod5
        STAA    [OR_D + 17]
        LDAA    [OR_D + 16]
        STAA    [OR_CARD]
        RTS

or_advance:
        LDAA    [OR_LEVEL]
        CMPA    254
        BCC     or_advance_target
        INC     [OR_LEVEL]
or_advance_target:
        LDAA    [OR_TARGET]
        ADDA    6
        CMPA    60
        BLS     or_advance_store
        LDAA    60
or_advance_store:
        STAA    [OR_TARGET]
        CLR     [OR_PROGRESS]
        RTS

; A -> A % 5.
or_mod5:
        LDAB    5
        JSR     jr_divmod8
        TBA
        RTS

; four steps of the 16-bit shift register -> A = (lo ^ hi) % 5.
or_deal:
        LDAB    4
or_deal_step:
        LDAA    [OR_RNG_HI]
        LSRA
        STAA    [OR_RNG_HI]
        LDAA    [OR_RNG_LO]
        RORA
        STAA    [OR_RNG_LO]
        BCC     or_deal_next
        LDAA    [OR_RNG_HI]
        EORA    180
        STAA    [OR_RNG_HI]
or_deal_next:
        DECB
        BNE     or_deal_step
        LDAA    [OR_RNG_LO]
        EORA    [OR_RNG_HI]
        JMP     or_mod5

; A = cell -> X = b[cell].
or_slot:
        LDX     OR_B
        JMP     jr_add_x_a

; lines: every row, column and diagonal triple of one kind; c marks its cells.
or_evaluate:
        CLR     [OR_LINES]
        LDX     OR_C
or_eval_clear:
        CLR     [X]
        INX
        CPX     OR_C + 16
        BNE     or_eval_clear
        LDX     or_paths
        STX     [JR_RT_TABLE]
or_eval_path:
        LDX     [JR_RT_TABLE]
        CPX     or_paths_end
        BEQ     or_eval_done
        LDAA    [X]
        STAA    [OR_A]
        LDAA    [X + 1]
        STAA    [OR_M]
        LDAA    [X + 2]
        STAA    [OR_E]
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        LDAA    [OR_A]
        JSR     or_slot
        LDAB    [X]
        CMPB    OR_EMPTY
        BEQ     or_eval_path
        LDAA    [OR_M]
        JSR     or_slot
        CMPB    [X]
        BNE     or_eval_path
        LDAA    [OR_E]
        JSR     or_slot
        CMPB    [X]
        BNE     or_eval_path
        INC     [OR_LINES]
        LDAA    1
        STAA    [X + 16]
        PSHA
        LDAA    [OR_A]
        JSR     or_slot
        PULA
        STAA    [X + 16]
        PSHA
        LDAA    [OR_M]
        JSR     or_slot
        PULA
        STAA    [X + 16]
        BRA     or_eval_path
or_eval_done:
        RTS

; up to three steps: every card over an empty cell drops one row together.
or_settle:
        LDAA    3
        STAA    [OR_STEP]
or_settle_step:
        LDX     OR_D
or_settle_clear:
        CLR     [X]
        INX
        CPX     OR_D + 16
        BNE     or_settle_clear
        CLR     [OR_CHANGED]
        LDAA    11
        STAA    [OR_I]
or_settle_mark:
        LDAA    [OR_I]
        JSR     or_slot
        LDAA    [X]
        CMPA    OR_EMPTY
        BEQ     or_settle_mark_next
        LDAA    [X + 4]
        CMPA    OR_EMPTY
        BNE     or_settle_mark_next
        LDAA    1
        STAA    [X + 32]
        STAA    [OR_CHANGED]
or_settle_mark_next:
        DEC     [OR_I]
        BPL     or_settle_mark
        TST     [OR_CHANGED]
        BNE     or_settle_fall
        RTS
or_settle_fall:
        LDAA    1
        STAA    [OR_FALLING]
        CLR     [OR_FRAME]
or_settle_frame:
        LDAA    [OR_FRAME]
        ASLA
        STAA    [OR_SLIDE]
        LDAA    3
        JSR     jr_port_animate
        INC     [OR_FRAME]
        LDAA    [OR_FRAME]
        CMPA    3
        BNE     or_settle_frame
        LDAA    11
        STAA    [OR_I]
or_settle_move:
        LDAA    [OR_I]
        JSR     or_slot
        TST     [X + 32]
        BEQ     or_settle_move_next
        LDAA    [X]
        STAA    [X + 4]
        LDAA    OR_EMPTY
        STAA    [X]
or_settle_move_next:
        DEC     [OR_I]
        BPL     or_settle_move
        CLR     [OR_FALLING]
        CLRA
        JSR     jr_port_sound
        DEC     [OR_STEP]
        BNE     or_settle_step
        RTS

; progress = min(progress + points, 99); the score counts to 9999.
or_credit:
        LDAA    [OR_PROGRESS]
        ADDA    [OR_POINTS]
        CMPA    99
        BLS     or_credit_progress
        LDAA    99
or_credit_progress:
        STAA    [OR_PROGRESS]
        LDAA    [OR_SCORE_LO]
        ADDA    [OR_POINTS]
        STAA    [OR_SCORE_LO]
        CMPA    100
        BCS     or_credit_done
        LDAB    [OR_SCORE_HI]
        CMPB    99
        BNE     or_credit_carry
        LDAA    99
        STAA    [OR_SCORE_LO]
        RTS
or_credit_carry:
        SUBA    100
        STAA    [OR_SCORE_LO]
        INC     [OR_SCORE_HI]
or_credit_done:
        RTS

; up to five waves: clear lines (settling first when none), glow, score, drop.
or_resolve:
        CLR     [OR_CHAIN]
        CLR     [OR_POINTS]
        LDAA    5
        STAA    [OR_WAVE]
or_resolve_wave:
        JSR     or_evaluate
        TST     [OR_LINES]
        BNE     or_resolve_clear
        JSR     or_settle
        JSR     or_evaluate
        TST     [OR_LINES]
        BNE     or_resolve_clear
        RTS
or_resolve_clear:
        INC     [OR_CHAIN]
        LDX     or_sfx_line
        LDAA    [OR_CHAIN]
        CMPA    1
        BEQ     or_resolve_sound
        LDX     or_sfx_chain
or_resolve_sound:
        JSR     jr_sfx_play
        LDAA    1
        STAA    [OR_GLOW]
or_resolve_glow:
        LDAA    5
        JSR     jr_port_animate
        INC     [OR_GLOW]
        LDAA    [OR_GLOW]
        CMPA    4
        BNE     or_resolve_glow
        CLR     [OR_COUNT]
        LDX     OR_B
or_resolve_take:
        TST     [X + 16]
        BEQ     or_resolve_take_next
        LDAA    OR_EMPTY
        STAA    [X]
        INC     [OR_COUNT]
        CLR     [X + 16]
or_resolve_take_next:
        INX
        CPX     OR_B + 16
        BNE     or_resolve_take
        CLR     [OR_GLOW]
        ; points = count * 2 * chain + (lines - 1) * 2
        LDAA    [OR_COUNT]
        ASLA
        LDAB    [OR_CHAIN]
        JSR     jr_mul8
        LDAB    [OR_LINES]
        DECB
        ASLB
        ABA
        STAA    [OR_POINTS]
        JSR     or_credit
        LDAA    [OR_SPINS]
        CMPA    4
        BCC     or_resolve_rest
        INC     [OR_SPINS]
or_resolve_rest:
        LDAA    10
        JSR     jr_port_animate
        JSR     or_settle
        DEC     [OR_WAVE]
        BEQ     or_resolve_wave_near490
        JMP     or_resolve_wave
or_resolve_wave_near490:
        RTS

; the goal, or a full board: lost without spins, else the ROW / COL hint.
or_finish:
        LDAA    [OR_PROGRESS]
        CMPA    [OR_TARGET]
        BCS     or_finish_board
        JMP     jr_port_win
or_finish_board:
        LDX     OR_B
or_finish_scan:
        LDAA    [X]
        CMPA    OR_EMPTY
        BEQ     or_finish_done
        INX
        CPX     OR_B + 16
        BNE     or_finish_scan
        TST     [OR_SPINS]
        BNE     or_finish_hint
        LDX     or_txt_lose
        JMP     jr_port_lose
or_finish_hint:
        TST     [OR_TOOL]
        BNE     or_finish_notice
        LDAA    1
        STAA    [OR_PHASE]
        LDAA    17
        STAA    [OR_CURSOR]
or_finish_notice:
        LDAA    2
        STAA    [OR_NOTICE]
or_finish_done:
        RTS

; drop the card into the lowest empty cell of the cursor's column.
or_place:
        LDAA    OR_EMPTY
        STAA    [OR_POS]
        CLR     [OR_I]
or_place_row:
        LDAA    [OR_I]
        ASLA
        ASLA
        LDAB    [OR_CURSOR]
        ANDB    3
        ABA
        STAA    [OR_T]
        JSR     or_slot
        LDAA    [X]
        CMPA    OR_EMPTY
        BNE     or_place_row_next
        LDAA    [OR_T]
        STAA    [OR_POS]
or_place_row_next:
        INC     [OR_I]
        LDAA    [OR_I]
        CMPA    4
        BNE     or_place_row
        LDAA    [OR_POS]
        CMPA    OR_EMPTY
        BNE     or_place_fly
        LDAA    3
        STAA    [OR_NOTICE]
        CLRA
        JMP     jr_port_sound
or_place_fly:
        LDAA    1
        STAA    [OR_FLYING]
        LDAA    [OR_POS]
        ANDA    3
        LDAB    5
        JSR     jr_mul8
        ADDA    2
        STAA    [OR_FX]
        LDAA    [OR_POS]
        LSRA
        LSRA
        ASLA
        ASLA
        ADDA    4
        STAA    [OR_BOTTOM]
        CLRA
        JSR     jr_port_sound
        CLR     [OR_FRAME]
or_place_frame:
        ; fy = 3 + (bottom - 3) * frame // 4
        LDAA    [OR_BOTTOM]
        SUBA    3
        LDAB    [OR_FRAME]
        JSR     jr_mul8
        LSRA
        LSRA
        ADDA    3
        STAA    [OR_FY]
        LDAA    3
        JSR     jr_port_animate
        INC     [OR_FRAME]
        LDAA    [OR_FRAME]
        CMPA    5
        BNE     or_place_frame
        CLR     [OR_FLYING]
        LDAA    [OR_POS]
        JSR     or_slot
        LDAA    [OR_CARD]
        STAA    [X]
        JSR     or_resolve
        ; the used offer takes the first NEXT card; a new card joins NEXT
        LDAA    [OR_OFFER]
        LDX     OR_D + 16
        JSR     jr_add_x_a
        LDAA    [OR_D + 18]
        STAA    [X]
        LDAA    [OR_D + 19]
        STAA    [OR_D + 18]
        LDAA    [OR_D + 20]
        STAA    [OR_D + 19]
        JSR     or_deal
        STAA    [OR_D + 20]
        LDAA    [OR_OFFER]
        LDX     OR_D + 16
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [OR_CARD]
        CLR     [OR_PHASE]
        JMP     or_finish

; spin the cursor's row right (ROW) or column down (COL) by one.
or_rotate:
        TST     [OR_SPINS]
        BNE     or_rotate_line
        LDAA    1
        STAA    [OR_NOTICE]
        CLRA
        JMP     jr_port_sound
or_rotate_line:
        LDAA    [OR_TOOL]
        DECA
        STAA    [OR_AXIS]
        BNE     or_rotate_col
        LDAA    [OR_CURSOR]
        LSRA
        LSRA
        STAA    [OR_ORBIT]
        ASLA
        ASLA
        STAA    [OR_FIRST]
        LDAA    1
        STAA    [OR_STRIDE]
        BRA     or_rotate_same
or_rotate_col:
        LDAA    [OR_CURSOR]
        ANDA    3
        STAA    [OR_ORBIT]
        STAA    [OR_FIRST]
        LDAA    4
        STAA    [OR_STRIDE]
or_rotate_same:
        ; four equal cards (or four empty cells) do not spend a spin
        LDAA    [OR_FIRST]
        JSR     or_slot
        LDAB    [X]
        LDAA    3
        STAA    [OR_I]
        LDAA    [OR_FIRST]
or_rotate_same_next:
        ADDA    [OR_STRIDE]
        PSHA
        JSR     or_slot
        PULA
        CMPB    [X]
        BNE     or_rotate_go
        DEC     [OR_I]
        BNE     or_rotate_same_next
        LDAA    4
        STAA    [OR_NOTICE]
        CLRA
        JMP     jr_port_sound
or_rotate_go:
        LDAA    1
        STAA    [OR_ROTATING]
        CLRA
        JSR     jr_port_sound
        CLR     [OR_FRAME]
or_rotate_frame:
        ; slide = frame * (5 for a row, 4 for a column) // 3
        LDAA    [OR_FRAME]
        LDAB    5
        TST     [OR_AXIS]
        BEQ     or_rotate_slide
        LDAB    4
or_rotate_slide:
        JSR     jr_mul8
        LDAB    3
        JSR     jr_divmod8
        STAA    [OR_SLIDE]
        LDAA    4
        JSR     jr_port_animate
        INC     [OR_FRAME]
        LDAA    [OR_FRAME]
        CMPA    4
        BNE     or_rotate_frame
        ; last = first + 3 * stride; shift towards last, wrap the last to first
        LDAA    [OR_STRIDE]
        LDAB    3
        JSR     jr_mul8
        ADDA    [OR_FIRST]
        STAA    [OR_LAST]
        JSR     or_slot
        LDAA    [X]
        STAA    [OR_SAVED]
        LDAA    3
        STAA    [OR_I]
or_rotate_shift:
        LDAA    [OR_LAST]
        SUBA    [OR_STRIDE]
        STAA    [OR_T]
        JSR     or_slot
        LDAB    [X]
        LDAA    [OR_LAST]
        JSR     or_slot
        STAB    [X]
        LDAA    [OR_T]
        STAA    [OR_LAST]
        DEC     [OR_I]
        BNE     or_rotate_shift
        LDAA    [OR_FIRST]
        JSR     or_slot
        LDAA    [OR_SAVED]
        STAA    [X]
        CLR     [OR_ROTATING]
        DEC     [OR_SPINS]
        JSR     or_resolve
        JMP     or_finish

game_raw_key:
game_tick:
        RTS

game_act:
        CLR     [OR_NOTICE]
        TST     [OR_PHASE]
        BNE     or_act_board
        ; choosing between the two offers
        CMPA    JR_KEY_LEFT
        BEQ     or_act_offer
        CMPA    JR_KEY_RIGHT
        BNE     or_act_select
or_act_offer:
        LDAA    1
        SUBA    [OR_OFFER]
        STAA    [OR_OFFER]
        LDX     OR_D + 16
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [OR_CARD]
        CLRA
        JMP     jr_port_sound
or_act_select:
        CMPA    JR_KEY_CONFIRM
        BNE     or_act_menu
        LDAA    1
        STAA    [OR_PHASE]
        LDAA    [OR_CELL]
        STAA    [OR_CURSOR]
        RTS
or_act_menu:
        CMPA    JR_KEY_DOWN
        BNE     or_act_done
        LDAA    1
        STAA    [OR_PHASE]
        LDAA    16
        STAA    [OR_CURSOR]
or_act_done:
        RTS
or_act_board:
        CMPA    JR_KEY_CONFIRM
        BEQ     or_act_confirm
        BCC     or_act_done
        TSTA
        BEQ     or_act_done
        TAB
        LDAA    [OR_CURSOR]
        JSR     or_move
        CMPA    18
        BLS     or_act_cursor
        LDAA    18
or_act_cursor:
        STAA    [OR_CURSOR]
        CMPA    16
        BCC     or_act_done
        STAA    [OR_CELL]
        RTS
or_act_confirm:
        LDAA    [OR_CURSOR]
        CMPA    16
        BCS     or_act_use
        ; the menu: CARD, ROW or COL
        SUBA    16
        STAA    [OR_TOOL]
        LDAA    [OR_CELL]
        STAA    [OR_CURSOR]
        TST     [OR_TOOL]
        BNE     or_act_done
        CLR     [OR_PHASE]
        RTS
or_act_use:
        TST     [OR_TOOL]
        BNE     or_act_rotate
        JMP     or_place
or_act_rotate:
        JMP     or_rotate

; A = position, B = action 1-4 -> A = moved position (4 wide, 5 tall).
or_move:
        STAA    [OR_T]
        CMPB    JR_KEY_UP
        BNE     or_move_down
        CMPA    4
        BCS     or_move_done
        SUBA    4
        RTS
or_move_down:
        CMPB    JR_KEY_DOWN
        BNE     or_move_side
        CMPA    16
        BCC     or_move_done
        ADDA    4
        RTS
or_move_side:
        ANDA    3
        CMPB    JR_KEY_LEFT
        BNE     or_move_right
        TSTA
        BEQ     or_move_stay
        LDAA    [OR_T]
        DECA
        RTS
or_move_right:
        CMPA    3
        BCC     or_move_stay
        LDAA    [OR_T]
        INCA
        RTS
or_move_stay:
        LDAA    [OR_T]
or_move_done:
        RTS

; ---------------------------------------------------------------- drawing

; A = kind -> JR_RT_COLOR = its PCG attribute.
or_kind_colour:
        LDX     or_kind_attr
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        RTS

game_draw:
        LDAA    0x20
        LDAB    OR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     or_hud
        JSR     jr_gfx_lines
        CLR     [OR_DI]
or_draw_cell:
        LDAA    [OR_DI]
        JSR     or_slot
        LDAA    [X]
        CMPA    OR_EMPTY
        BNE     or_draw_card
        JMP     or_draw_next
or_draw_card:
        STAA    [OR_DCODE]
        ; sliding in a spin or a fall: four quarters, wrapped around the board
        TST     [OR_FALLING]
        BEQ     or_draw_spin
        TST     [X + 32]
        BNE     or_draw_moving
        JMP     or_draw_still
or_draw_spin:
        TST     [OR_ROTATING]
        BNE     or_draw_still_near875
        JMP     or_draw_still
or_draw_still_near875:
        LDAA    [OR_DI]
        TST     [OR_AXIS]
        BNE     or_draw_spin_col
        LSRA
        LSRA
        BRA     or_draw_spin_line
or_draw_spin_col:
        ANDA    3
or_draw_spin_line:
        CMPA    [OR_ORBIT]
        BNE     or_draw_still
or_draw_moving:
        LDAA    [OR_DCODE]
        JSR     or_kind_colour
        CLR     [OR_DQ]
or_draw_quarter:
        ; x = pos % 4 * 5 + quad % 2, y = pos // 4 * 4 + quad // 2
        LDAA    [OR_DI]
        ANDA    3
        LDAB    5
        JSR     jr_mul8
        LDAB    [OR_DQ]
        ANDB    1
        ABA
        STAA    [OR_DX]
        LDAA    [OR_DI]
        ANDA    0x0c
        LDAB    [OR_DQ]
        LSRB
        ABA
        STAA    [OR_DY]
        TST     [OR_FALLING]
        BNE     or_draw_quarter_down
        TST     [OR_AXIS]
        BNE     or_draw_quarter_down
        LDAA    [OR_DX]
        ADDA    [OR_SLIDE]
        CMPA    20
        BCS     or_draw_quarter_x
        SUBA    20
or_draw_quarter_x:
        STAA    [OR_DX]
        BRA     or_draw_quarter_put
or_draw_quarter_down:
        LDAA    [OR_DY]
        ADDA    [OR_SLIDE]
        ANDA    15
        STAA    [OR_DY]
or_draw_quarter_put:
        LDAA    [OR_DX]
        ADDA    2
        LDAB    [OR_DY]
        ADDB    4
        JSR     jr_gfx_at
        LDAA    [OR_DCODE]
        ASLA
        ASLA
        ADDA    OR_TILE_CARD
        ADDA    [OR_DQ]
        JSR     jr_gfx_putc
        INC     [OR_DQ]
        LDAA    [OR_DQ]
        CMPA    4
        BNE     or_draw_quarter
        BRA     or_draw_next
or_draw_still:
        ; the card's letter above its picture, or a burst while it clears
        LDAA    [OR_DI]
        ANDA    3
        LDAB    5
        JSR     jr_mul8
        ADDA    2
        STAA    [OR_DX]
        LDAA    [OR_DI]
        ANDA    0x0c
        ADDA    3
        STAA    [OR_DY]
        LDAA    [OR_DCODE]
        LDX     or_kind_text
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [OR_DX]
        LDAB    [OR_DY]
        JSR     jr_gfx_at
        LDAA    [OR_DCODE]
        ADDA    0x41
        JSR     jr_gfx_putc
        LDAA    [OR_DCODE]
        JSR     or_kind_colour
        LDAA    [OR_DCODE]
        ASLA
        ASLA
        ADDA    OR_TILE_CARD
        STAA    [OR_DCODE]
        TST     [OR_GLOW]
        BEQ     or_draw_picture
        LDAA    [OR_DI]
        JSR     or_slot
        TST     [X + 16]
        BEQ     or_draw_picture
        LDAA    OR_ATTR_BURST
        STAA    [JR_RT_COLOR]
        LDAA    [OR_GLOW]
        DECA
        ASLA
        ASLA
        ADDA    OR_TILE_BURST
        STAA    [OR_DCODE]
or_draw_picture:
        LDAA    [OR_DX]
        LDAB    [OR_DY]
        INCB
        JSR     jr_gfx_at
        LDAA    [OR_DCODE]
        JSR     jr_gfx_tile
or_draw_next:
        INC     [OR_DI]
        LDAA    [OR_DI]
        CMPA    16
        BEQ     or_draw_flying
        JMP     or_draw_cell
or_draw_flying:
        TST     [OR_FLYING]
        BEQ     or_draw_markers
        LDAA    [OR_CARD]
        JSR     or_kind_colour
        LDAA    [OR_FX]
        LDAB    [OR_FY]
        JSR     jr_gfx_at
        LDAA    [OR_CARD]
        ASLA
        ASLA
        ADDA    OR_TILE_CARD
        JSR     jr_gfx_tile
or_draw_markers:
        ; the cursor: the drop cell for CARD, the row or column for ROW / COL
        TST     [OR_PHASE]
        BNE     or_draw_offers_near1016
        JMP     or_draw_offers
or_draw_offers_near1016:
        LDAA    [OR_CURSOR]
        CMPA    16
        BCS     or_draw_offers_near1021
        JMP     or_draw_offers
or_draw_offers_near1021:
        ANDA    3
        STAA    [OR_DCOL]
        LDAA    [OR_CURSOR]
        LSRA
        LSRA
        STAA    [OR_DROW]
        TST     [OR_TOOL]
        BNE     or_draw_line_marks
        CLR     [OR_DI]
or_draw_drop_row:
        LDAA    [OR_DI]
        ASLA
        ASLA
        ADDA    [OR_DCOL]
        JSR     or_slot
        LDAA    [X]
        CMPA    OR_EMPTY
        BNE     or_draw_drop_next
        LDAA    [OR_DI]
        STAA    [OR_DROW]
or_draw_drop_next:
        INC     [OR_DI]
        LDAA    [OR_DI]
        CMPA    4
        BNE     or_draw_drop_row
or_draw_line_marks:
        LDAA    OR_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [OR_DCOL]
        LDAB    5
        JSR     jr_mul8
        STAA    [OR_DX]
        LDAA    [OR_TOOL]
        CMPA    2
        BNE     or_draw_side_marks
        LDAA    [OR_DX]
        ADDA    2
        LDAB    2
        JSR     jr_gfx_at
        LDAA    0x56
        JSR     jr_gfx_putc
        LDAA    [OR_DX]
        ADDA    2
        LDAB    19
        JSR     jr_gfx_at
        LDAA    0x5e
        JSR     jr_gfx_putc
        BRA     or_draw_offers
or_draw_side_marks:
        LDAA    [OR_DROW]
        ASLA
        ASLA
        ADDA    4
        STAA    [OR_DY]
        LDAA    [OR_DX]
        TST     [OR_TOOL]
        BEQ     or_draw_left_mark
        CLRA
or_draw_left_mark:
        LDAB    [OR_DY]
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDAA    [OR_DX]
        ADDA    5
        TST     [OR_TOOL]
        BEQ     or_draw_right_mark
        LDAA    20
or_draw_right_mark:
        LDAB    [OR_DY]
        JSR     jr_gfx_at
        LDAA    0x3c
        JSR     jr_gfx_putc
or_draw_offers:
        ; the two offers with their letters, the pick mark and NEXT
        CLR     [OR_DI]
or_draw_offer:
        LDAA    [OR_DI]
        LDX     OR_D + 16
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [OR_DCODE]
        JSR     or_kind_colour
        LDAA    [OR_DI]
        ASLA
        ASLA
        ADDA    23
        STAA    [OR_DX]
        LDAB    5
        JSR     jr_gfx_at
        LDAA    [OR_DCODE]
        ASLA
        ASLA
        ADDA    OR_TILE_CARD
        JSR     jr_gfx_tile
        LDAA    [OR_DCODE]
        LDX     or_kind_text
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [OR_DX]
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [OR_DCODE]
        ADDA    0x41
        JSR     jr_gfx_putc
        INC     [OR_DI]
        LDAA    [OR_DI]
        CMPA    2
        BNE     or_draw_offer
        LDAA    OR_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [OR_OFFER]
        ASLA
        ASLA
        ADDA    23
        LDAB    4
        JSR     jr_gfx_at
        LDAA    0x56
        JSR     jr_gfx_putc
        CLR     [OR_DI]
or_draw_next_card:
        LDAA    [OR_DI]
        LDX     OR_D + 18
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [OR_DCODE]
        LDX     or_kind_text
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [JR_RT_COLOR]
        LDAA    [OR_DI]
        ADDA    27
        LDAB    8
        JSR     jr_gfx_at
        LDAA    [OR_DCODE]
        ADDA    0x41
        JSR     jr_gfx_putc
        INC     [OR_DI]
        LDAA    [OR_DI]
        CMPA    3
        BNE     or_draw_next_card
        ; score, chain, progress / goal and spins
        LDAA    OR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    13
        JSR     jr_gfx_at
        LDAA    [OR_SCORE_HI]
        JSR     jr_gfx_dec2
        LDAA    [OR_SCORE_LO]
        JSR     jr_gfx_dec2
        LDAA    29
        LDAB    14
        JSR     jr_gfx_at
        LDAA    [OR_CHAIN]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    OR_ATTR_TEXT
        LDAB    [OR_PROGRESS]
        CMPB    [OR_TARGET]
        BCS     or_draw_progress
        LDAA    OR_ATTR_GOOD
or_draw_progress:
        STAA    [JR_RT_COLOR]
        LDAA    26
        LDAB    17
        JSR     jr_gfx_at
        LDAA    [OR_PROGRESS]
        JSR     jr_gfx_dec2
        LDAA    OR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        LDAB    17
        JSR     jr_gfx_at
        LDAA    [OR_TARGET]
        JSR     jr_gfx_dec2
        LDAA    OR_ATTR_TEXT
        TST     [OR_SPINS]
        BNE     or_draw_spins
        LDAA    OR_ATTR_BAD
or_draw_spins:
        STAA    [JR_RT_COLOR]
        LDAA    27
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [OR_SPINS]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    OR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    29
        CLRB
        JSR     jr_gfx_at
        LDAA    [OR_LEVEL]
        INCA
        JSR     jr_gfx_dec2
        ; the menu with the tool in brackets, and the notice
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     or_draw_done
        LDAA    OR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    21
        JSR     jr_gfx_at
        LDX     or_txt_menu
        JSR     jr_gfx_text
        LDAA    OR_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [OR_TOOL]
        LDAB    6
        JSR     jr_mul8
        STAA    [OR_DX]
        LDAB    21
        JSR     jr_gfx_at
        LDAA    0x5b
        JSR     jr_gfx_putc
        LDAA    [OR_DX]
        ADDA    5
        LDAB    21
        JSR     jr_gfx_at
        LDAA    0x5d
        JSR     jr_gfx_putc
        TST     [OR_PHASE]
        BEQ     or_draw_notice
        LDAA    [OR_CURSOR]
        CMPA    16
        BCS     or_draw_notice
        SUBA    16
        LDAB    6
        JSR     jr_mul8
        LDAB    21
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
or_draw_notice:
        LDAA    [OR_NOTICE]
        BEQ     or_draw_done
        LDAB    OR_ATTR_BAD
        STAB    [JR_RT_COLOR]
        DECA
        ASLA
        LDX     or_notice_text
        JSR     jr_add_x_a
        LDX     [X]
        STX     [JR_RT_TABLE]
        CLRA
        LDAB    22
        JSR     jr_gfx_at
        LDX     [JR_RT_TABLE]
        JMP     jr_gfx_text
or_draw_done:
        RTS

game_draw_title:
        LDX     or_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    OR_ATTR_TEXT
        JSR     jr_gfx_fill
        CLR     [OR_DI]
or_title_card:
        LDAA    [OR_DI]
        JSR     or_kind_colour
        LDAA    [OR_DI]
        ASLA
        ASLA
        ADDA    6
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [OR_DI]
        ASLA
        ASLA
        ADDA    OR_TILE_CARD
        JSR     jr_gfx_tile
        INC     [OR_DI]
        LDAA    [OR_DI]
        CMPA    5
        BNE     or_title_card
        LDX     or_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    OR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     or_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

or_paths:
        .db     0, 1, 2, 1, 2, 3, 4, 5, 6, 5, 6, 7, 8, 9, 10, 9, 10, 11
        .db     12, 13, 14, 13, 14, 15, 0, 4, 8, 1, 5, 9, 2, 6, 10, 3, 7, 11
        .db     4, 8, 12, 5, 9, 13, 6, 10, 14, 7, 11, 15, 0, 5, 10, 1, 6, 11
        .db     4, 9, 14, 5, 10, 15, 2, 5, 8, 3, 6, 9, 6, 9, 12, 7, 10, 13
or_paths_end:
; planet red, star yellow, moon cyan, comet green, sun magenta
or_kind_attr:
        .db     0x42, 0x46, 0x45, 0x44, 0x43
or_kind_text:
        .db     0x02, 0x06, 0x05, 0x04, 0x03
or_notice_text:
        .dw     or_txt_no_spins, or_txt_full, or_txt_column, or_txt_same

or_hud:
        .db     1, 0, OR_ATTR_TITLE
        .dw     or_txt_name
        .db     23, 0, OR_ATTR_LABEL
        .dw     or_txt_round
        .db     22, 2, OR_ATTR_LABEL
        .dw     or_txt_pick
        .db     22, 8, OR_ATTR_LABEL
        .dw     or_txt_next
        .db     23, 11, OR_ATTR_LABEL
        .dw     or_txt_score
        .db     23, 14, OR_ATTR_LABEL
        .dw     or_txt_chain
        .db     23, 16, OR_ATTR_LABEL
        .dw     or_txt_goal
        .db     28, 17, OR_ATTR_DIM
        .dw     or_txt_slash
        .db     21, 19, OR_ATTR_LABEL
        .dw     or_txt_spins
        .db     0xff
or_title_lines:
        .db     10, 8, OR_ATTR_TITLE
        .dw     or_txt_name
        .db     3, 10, OR_ATTR_LABEL
        .dw     or_txt_tagline
        .db     8, 15, OR_ATTR_TEXT
        .dw     or_txt_start
        .db     5, 17, OR_ATTR_TEXT
        .dw     or_txt_howto
        .db     4, 22, OR_ATTR_DIM
        .dw     or_txt_credit
        .db     0xff
or_help_lines:
        .db     10, 1, OR_ATTR_TITLE
        .dw     or_txt_name
        .db     1, 3, OR_ATTR_TEXT
        .dw     or_help_1
        .db     1, 5, OR_ATTR_TEXT
        .dw     or_help_2
        .db     1, 7, OR_ATTR_TEXT
        .dw     or_help_3
        .db     1, 9, OR_ATTR_TEXT
        .dw     or_help_4
        .db     1, 11, OR_ATTR_TEXT
        .dw     or_help_5
        .db     1, 13, OR_ATTR_TEXT
        .dw     or_help_6
        .db     1, 15, OR_ATTR_TEXT
        .dw     or_help_7
        .db     1, 17, OR_ATTR_TEXT
        .dw     or_help_8
        .db     1, 19, OR_ATTR_TEXT
        .dw     or_help_9
        .db     1, 21, OR_ATTR_LABEL
        .dw     or_help_back
        .db     0xff

or_txt_name:
        .db     "ORBIT DRAFT", 0
or_txt_round:
        .db     "ROUND", 0
or_txt_pick:
        .db     "PICK", 0
or_txt_next:
        .db     "NEXT", 0
or_txt_score:
        .db     "SCORE", 0
or_txt_chain:
        .db     "CHAIN", 0
or_txt_goal:
        .db     "GOAL", 0
or_txt_slash:
        .db     "/", 0
or_txt_spins:
        .db     "SPINS", 0
or_txt_menu:
        .db     "CARD  ROW   COL", 0
or_txt_no_spins:
        .db     "NO SPINS: CLEAR A LINE TO EARN", 0
or_txt_full:
        .db     "FULL BOARD: USE ROW / COL", 0
or_txt_column:
        .db     "COLUMN FULL: PICK ANOTHER", 0
or_txt_same:
        .db     "SAME CARDS: NO SPIN USED", 0
or_txt_lose:
        .db     "FULL BOARD - NO SPINS", 0
or_txt_tagline:
        .db     "THREE IN A LINE, CHAIN ON", 0
or_txt_start:
        .db     "RETURN : START", 0
or_txt_howto:
        .db     "W/A/S/D : HOW TO PLAY", 0
or_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
or_help_1:
        .db     "A/D PICK 1/2. RETURN SELECT.", 0
or_help_2:
        .db     "CARD: PICK COLUMN. RET DROP.", 0
or_help_3:
        .db     "3 SAME: ROW / COL / DIAGONAL.", 0
or_help_4:
        .db     "FALLING CARDS CAN CHAIN AGAIN.", 0
or_help_5:
        .db     "WASD TO MENU: CARD / ROW / COL.", 0
or_help_6:
        .db     "ROW / COL STAY UNTIL CARD.", 0
or_help_7:
        .db     "CLEAR LINES TO EARN SPINS.", 0
or_help_8:
        .db     "REACH GOAL. KEEP BOARD + SCORE.", 0
or_help_9:
        .db     "SPACE : NEW GAME  CTRL+C : BASIC", 0
or_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     or_sfx_tick, or_sfx_line, or_jingle_win, or_jingle_lose
or_sfx_tick:
        .db     120, 2, 0, 0
or_sfx_line:
        .db     60, 3, 50, 3, 40, 6, 0, 0
or_sfx_chain:
        .db     50, 3, 40, 3, 33, 3, 25, 8, 0, 0

; Title: a floating space waltz in E flat major, quarter note = 12 frames, looping.
or_title_song:
        .db     1
        .dw     or_title_melody, or_title_harmony, or_title_bass
or_title_melody:
        .db     AU_G5, 24, AU_AS5, 12, AU_DS6, 24, AU_D6, 12
        .db     AU_C6, 24, AU_AS5, 12, AU_G5, 36
        .db     AU_GS5, 24, AU_C6, 12, AU_F6, 24, AU_DS6, 12
        .db     AU_D6, 24, AU_F5, 12, AU_DS5, 36, 0, 0
or_title_harmony:
        .db     AU_DS5, 36, AU_G5, 36, AU_GS5, 36, AU_DS5, 36
        .db     AU_C5, 36, AU_GS5, 36, AU_AS4, 36, AU_G4, 36, 0, 0
or_title_bass:
        .db     AU_DS3, 12, AU_AS3, 12, AU_AS3, 12, AU_DS3, 12, AU_AS3, 12, AU_AS3, 12
        .db     AU_GS2, 12, AU_DS3, 12, AU_DS3, 12, AU_DS3, 12, AU_AS3, 12, AU_AS3, 12
        .db     AU_F3, 12, AU_C3, 12, AU_C3, 12, AU_GS2, 12, AU_DS3, 12, AU_DS3, 12
        .db     AU_AS2, 12, AU_F3, 12, AU_F3, 12, AU_DS3, 36, 0, 0

; Goal reached: E flat major arpeggio over the tonic (54 frames).
or_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     or_win_melody, or_win_harmony, or_win_bass
or_win_melody:
        .db     AU_DS5, 8, AU_G5, 8, AU_AS5, 8, AU_DS6, 30, 0, 0
or_win_harmony:
        .db     AU_AS4, 8, AU_DS5, 8, AU_G5, 8, AU_AS5, 30, 0, 0
or_win_bass:
        .db     AU_DS3, 24, AU_DS2, 30, 0, 0
or_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     or_lose_melody, or_lose_harmony, or_lose_bass
or_lose_melody:
        .db     AU_AS4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
or_lose_harmony:
        .db     AU_FS4, 12, AU_F4, 12, AU_DS4, 12, AU_D4, 30, 0, 0
or_lose_bass:
        .db     AU_DS3, 36, AU_AS2, 30, 0, 0

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
