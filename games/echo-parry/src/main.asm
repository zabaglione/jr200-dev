; SPDX-License-Identifier: MIT
; ECHO PARRY for JR-200: a port of jr100dev games/echo_parry/rules.py 2.0.0.
; Six duels, the ready / attack / recovery rhythm, high and low guards, the
; parry window (late parries and third chains deal two), the evade, feints
; from duel 3 and the attack pattern table follow the upstream source, one
; upstream tick per game_tick. Rules are checked by the in-program self test
; (sdk/selftest.inc, title key T); P plays the duel-1 demo.
        .filename.jr "ECHO-PARRY"
        .include "../../../sdk/jr200.inc"

JR_SHADOW:          .equ    0x3000
JR_SAVE:            .equ    0x3600
JR_RT:              .equ    0x4600
GAME_STATE:         .equ    0x4640
GAME_STATE_END:     .equ    0x4680
JR_AUDIO:           .equ    0x46c0
JR_TEST:            .equ    0x46e0
JR_TEST_OUT:        .equ    0x5000
JR_STACK_TOP:       .equ    0x4fff

GAME_LEVELS:        .equ    6
; Upstream ticks every 12 frames; one tick here is GAME_RATE idle frames plus
; the render (see README).
GAME_RATE:          .equ    7
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_TEST_SIZE:     .equ    12
GAME_TEST_LIMIT:    .equ    1000
GAME_TEST_HELD:     .equ    EP_HELD

; Upstream state (tests/model.py LAYOUT), then drawing-only bytes.
EP_HP:              .equ    GAME_STATE
EP_ENEMY:           .equ    GAME_STATE + 1
EP_ATTACK:          .equ    GAME_STATE + 2
EP_STANCE:          .equ    GAME_STATE + 3
EP_PHASE:           .equ    GAME_STATE + 4
EP_GUARDED:         .equ    GAME_STATE + 5
EP_EVADE:           .equ    GAME_STATE + 6
EP_COMBO:           .equ    GAME_STATE + 7
EP_AGE:             .equ    GAME_STATE + 8
EP_TURN:            .equ    GAME_STATE + 9
EP_FEINT:           .equ    GAME_STATE + 10
EP_COUNTER:         .equ    GAME_STATE + 11
EP_FLY:             .equ    GAME_STATE + 16
EP_FX:              .equ    GAME_STATE + 17
EP_FY:              .equ    GAME_STATE + 18
EP_F1:              .equ    GAME_STATE + 19
EP_HIT:             .equ    GAME_STATE + 20     ; 1 duellist, 2 knight flashes
EP_HELD:            .equ    GAME_STATE + 21     ; unused (no held keys)
EP_T:               .equ    GAME_STATE + 22
EP_DAMAGE:          .equ    GAME_STATE + 23
EP_DI:              .equ    GAME_STATE + 24

EP_TILE_HERO:       .equ    0x80
EP_TILE_KNIGHT:     .equ    0x84
EP_CHAR_ARMOR:      .equ    0x88
EP_CHAR_SLASH:      .equ    0x89
EP_CHAR_FLOOR:      .equ    0x8a
EP_ATTR_HERO:       .equ    0x47
EP_ATTR_KNIGHT:     .equ    0x43
EP_ATTR_ARMOR:      .equ    0x45
EP_ATTR_SLASH:      .equ    0x46
EP_ATTR_FLOOR:      .equ    0x41
EP_ATTR_HIT:        .equ    0x72        ; red on yellow
EP_ATTR_TEXT:       .equ    0x07
EP_ATTR_LABEL:      .equ    0x04
EP_ATTR_TITLE:      .equ    0x06
EP_ATTR_DIM:        .equ    0x05
EP_ATTR_WARN:       .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     ep_patterns
        LDAA    EP_TILE_HERO
        LDAB    11
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        JSR     jr_test_level
        LDAA    4
        STAA    [EP_HP]
        LDAA    [JR_PORT_LEVEL]
        ADDA    6
        STAA    [EP_ENEMY]
        LDAA    [JR_PORT_LEVEL]
        JSR     ep_pattern
        STAA    [EP_ATTACK]
        RTS

; A = index -> A = pattern[index % 8].
ep_pattern:
        ANDA    7
        LDX     ep_patterns_table
        JSR     jr_add_x_a
        LDAA    [X]
        RTS

game_raw_key:
        JMP     jr_test_raw_key

game_act:
        CMPA    JR_KEY_UP
        BNE     ep_act_low
        CLR     [EP_STANCE]
        RTS
ep_act_low:
        CMPA    JR_KEY_DOWN
        BNE     ep_act_evade
        LDAA    1
        STAA    [EP_STANCE]
        RTS
ep_act_evade:
        CMPA    JR_KEY_LEFT
        BNE     ep_act_parry
        LDAA    [EP_PHASE]
        CMPA    2
        BCS     ep_act_done_near127
        JMP     ep_act_done
ep_act_done_near127:
        TST     [EP_GUARDED]
        BEQ     ep_act_done_near131
        JMP     ep_act_done
ep_act_done_near131:
        LDAA    1
        STAA    [EP_EVADE]
        STAA    [EP_GUARDED]
        CLR     [EP_COMBO]
        CLRA
        JSR     jr_port_sound
        LDAA    5
        LDAB    1
        JMP     ep_flight_hero
ep_act_parry:
        CMPA    JR_KEY_CONFIRM
        BNE     ep_act_done
        TST     [EP_GUARDED]
        BNE     ep_act_done
        LDAA    [EP_PHASE]
        CMPA    1
        BNE     ep_act_hurt
        LDAA    [EP_STANCE]
        CMPA    [EP_ATTACK]
        BNE     ep_act_hurt
        ; a parry: chain up to 3, two damage late in the window or on chain 3
        LDAA    [EP_COMBO]
        CMPA    3
        BCC     ep_act_chain
        INC     [EP_COMBO]
ep_act_chain:
        LDAB    1
        LDAA    [EP_AGE]
        CMPA    1
        BEQ     ep_act_double
        LDAA    [EP_COMBO]
        CMPA    3
        BNE     ep_act_damage
ep_act_double:
        LDAB    2
ep_act_damage:
        STAB    [EP_DAMAGE]
        LDAA    [EP_ENEMY]
        SBA
        BCC     ep_act_armor
        CLRA
ep_act_armor:
        STAA    [EP_ENEMY]
        LDAA    1
        STAA    [EP_GUARDED]
        STAB    [EP_COUNTER]
        LDAA    1
        JSR     jr_port_sound
        LDAA    8
        JSR     jr_test_animate
        LDAA    7
        LDAB    24
        JSR     ep_flight_hero
        LDAA    2
        STAA    [EP_HIT]
        LDAA    6
        TST     [EP_ENEMY]
        BNE     ep_act_impact
        LDAA    12
ep_act_impact:
        JSR     jr_test_animate
        CLR     [EP_HIT]
        TST     [EP_ENEMY]
        BNE     ep_act_riposte_done
        JSR     jr_port_win
ep_act_riposte_done:
        CLR     [EP_COUNTER]
ep_act_done:
        RTS
ep_act_hurt:
        DEC     [EP_HP]
        CLR     [EP_COMBO]
        LDAA    1
        STAA    [EP_GUARDED]
        JSR     ep_hurt
        TST     [EP_HP]
        BNE     ep_act_done
        LDX     ep_txt_parry
        JMP     jr_port_lose

; The duellist is hit: a sound and a flash.
ep_hurt:
        LDX     ep_sfx_hurt
        JSR     jr_sfx_play
        LDAA    1
        STAA    [EP_HIT]
        LDAA    6
        JSR     jr_test_animate
        CLR     [EP_HIT]
        RTS

; A = from x, B = to x on the duellist's row: a slash flies across.
ep_flight_hero:
        STAB    [EP_F1]
        STAA    [EP_FX]
        LDAA    [EP_STANCE]
        BRA     ep_flight
; A = from x, B = to x on the knight's row.
ep_flight_knight:
        STAB    [EP_F1]
        STAA    [EP_FX]
        LDAA    [EP_ATTACK]
ep_flight:
        ; y = 14 - row * 3
        STAA    [EP_T]
        ASLA
        ADDA    [EP_T]
        NEGA
        ADDA    14
        STAA    [EP_FY]
        LDAA    1
        STAA    [EP_FLY]
        LDAA    2
        JSR     jr_test_animate
        LDAA    [EP_FX]
        ADDA    [EP_F1]
        LSRA
        STAA    [EP_FX]
        LDAA    2
        JSR     jr_test_animate
        LDAA    [EP_F1]
        STAA    [EP_FX]
        LDAA    2
        JSR     jr_test_animate
        CLR     [EP_FLY]
        RTS

game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BEQ     ep_act_done_near265
        JMP     ep_act_done
ep_act_done_near265:
        INC     [EP_AGE]
        ; a feint on every third turn from duel 3
        TST     [EP_PHASE]
        BNE     ep_tick_phase
        LDAA    [EP_AGE]
        CMPA    2
        BNE     ep_tick_phase
        LDAA    [JR_PORT_LEVEL]
        CMPA    2
        BCS     ep_tick_phase
        LDAA    [EP_TURN]
ep_tick_mod:
        CMPA    3
        BCS     ep_tick_turn_mod
        SUBA    3
        BRA     ep_tick_mod
ep_tick_turn_mod:
        CMPA    1
        BNE     ep_tick_phase
        LDAA    [EP_ATTACK]
        EORA    1
        STAA    [EP_ATTACK]
        LDAA    1
        STAA    [EP_FEINT]
        LDX     ep_sfx_warn
        JSR     jr_sfx_play
        LDAA    12
        JSR     jr_test_animate
ep_tick_phase:
        LDAA    [EP_PHASE]
        BNE     ep_tick_attack
        ; ready: the attack comes after 4 ticks (3 from duel 5)
        LDAB    4
        LDAA    [JR_PORT_LEVEL]
        CMPA    4
        BCS     ep_tick_ready
        LDAB    3
ep_tick_ready:
        LDAA    [EP_AGE]
        CBA
        BCC     ep_act_done_near308
        JMP     ep_act_done
ep_act_done_near308:
        LDAA    1
        STAA    [EP_PHASE]
        CLR     [EP_AGE]
        LDX     ep_sfx_warn
        JSR     jr_sfx_play
        LDAA    23
        LDAB    7
        JMP     ep_flight_knight
ep_tick_attack:
        CMPA    1
        BNE     ep_tick_recovery
        LDAA    [EP_AGE]
        CMPA    2
        BCC     ep_act_done_near324
        JMP     ep_act_done
ep_act_done_near324:
        TST     [EP_GUARDED]
        BNE     ep_tick_to_recovery
        DEC     [EP_HP]
        CLR     [EP_COMBO]
        JSR     ep_hurt
        TST     [EP_HP]
        BNE     ep_tick_to_recovery
        LDX     ep_txt_window
        JMP     jr_port_lose
ep_tick_to_recovery:
        LDAA    2
        STAA    [EP_PHASE]
        CLR     [EP_AGE]
        RTS
ep_tick_recovery:
        LDAA    [EP_AGE]
        CMPA    3
        BCC     ep_act_done_near344
        JMP     ep_act_done
ep_act_done_near344:
        CLR     [EP_PHASE]
        CLR     [EP_AGE]
        INC     [EP_TURN]
        LDAA    [JR_PORT_LEVEL]
        STAA    [EP_T]
        ASLA
        ADDA    [EP_T]
        ADDA    [EP_TURN]
        JSR     ep_pattern
        STAA    [EP_ATTACK]
        CLR     [EP_GUARDED]
        CLR     [EP_EVADE]
        CLR     [EP_FEINT]
        RTS

; ---------------------------------------------------------------- drawing

; A = row (stance or attack) -> B = y (14 - row * 3).
ep_row_y:
        STAA    [EP_T]
        ASLA
        ADDA    [EP_T]
        NEGA
        ADDA    14
        TAB
        RTS

game_draw:
        LDAA    0x20
        LDAB    EP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ep_hud
        JSR     jr_gfx_lines
        LDAA    EP_ATTR_FLOOR
        STAA    [JR_RT_COLOR]
        CLRA
        LDAB    16
        JSR     jr_gfx_at
        LDAB    32
ep_draw_floor:
        LDAA    EP_CHAR_FLOOR
        JSR     jr_gfx_putc
        DECB
        BNE     ep_draw_floor
        ; the knight's armor
        LDAA    EP_ATTR_ARMOR
        STAA    [JR_RT_COLOR]
        LDAA    10
        LDAB    5
        JSR     jr_gfx_at
        LDAB    [EP_ENEMY]
        BEQ     ep_draw_hero
ep_draw_armor:
        LDAA    EP_CHAR_ARMOR
        JSR     jr_gfx_putc
        DECB
        BNE     ep_draw_armor
ep_draw_hero:
        LDAA    EP_ATTR_HERO
        LDAB    [EP_HIT]
        CMPB    1
        BNE     ep_draw_hero_colour
        LDAA    EP_ATTR_HIT
ep_draw_hero_colour:
        STAA    [JR_RT_COLOR]
        LDAA    [EP_STANCE]
        JSR     ep_row_y
        LDAA    5
        TST     [EP_EVADE]
        BEQ     ep_draw_hero_at
        LDAA    1
ep_draw_hero_at:
        JSR     jr_gfx_at
        LDAA    EP_TILE_HERO
        JSR     jr_gfx_tile
        LDAA    EP_ATTR_KNIGHT
        LDAB    [EP_HIT]
        CMPB    2
        BNE     ep_draw_knight_colour
        LDAA    EP_ATTR_HIT
ep_draw_knight_colour:
        STAA    [JR_RT_COLOR]
        LDAA    [EP_ATTACK]
        JSR     ep_row_y
        LDAA    24
        JSR     jr_gfx_at
        LDAA    EP_TILE_KNIGHT
        JSR     jr_gfx_tile
        TST     [EP_FLY]
        BEQ     ep_draw_phase
        LDAA    EP_ATTR_SLASH
        STAA    [JR_RT_COLOR]
        LDAA    [EP_FX]
        LDAB    [EP_FY]
        JSR     jr_gfx_at
        LDAA    EP_CHAR_SLASH
        JSR     jr_gfx_putc
ep_draw_phase:
        ; the rhythm: READY / FEINT / ATTACK (COUNTER!) / RECOVERY
        LDAA    EP_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    11
        LDAB    9
        JSR     jr_gfx_at
        LDAA    [EP_PHASE]
        BNE     ep_draw_attack
        LDX     ep_txt_ready
        TST     [EP_FEINT]
        BEQ     ep_draw_phase_text
        LDX     ep_txt_feint
        BRA     ep_draw_phase_text
ep_draw_attack:
        CMPA    1
        BNE     ep_draw_recovery
        LDX     ep_txt_attack
        JSR     jr_gfx_text
        LDAA    [EP_AGE]
        CMPA    1
        BNE     ep_draw_panel
        LDAA    EP_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    11
        LDAB    11
        JSR     jr_gfx_at
        LDX     ep_txt_counter
        BRA     ep_draw_phase_text
ep_draw_recovery:
        LDX     ep_txt_recovery
ep_draw_phase_text:
        JSR     jr_gfx_text
ep_draw_panel:
        LDAA    EP_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    9
        LDAB    7
        JSR     jr_gfx_at
        LDAA    [EP_COMBO]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    9
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [EP_HP]
        JSR     jr_gfx_dec2
        LDAA    25
        LDAB    19
        JSR     jr_gfx_at
        LDAA    [EP_ENEMY]
        JSR     jr_gfx_dec2
        LDAA    EP_ATTR_LABEL
        STAA    [JR_RT_COLOR]
        TST     [EP_COUNTER]
        BEQ     ep_draw_evaded
        LDAA    10
        LDAB    13
        JSR     jr_gfx_at
        LDX     ep_txt_riposte
        JSR     jr_gfx_text
        LDAA    [EP_COUNTER]
        ADDA    0x30
        JSR     jr_gfx_putc
ep_draw_evaded:
        TST     [EP_EVADE]
        BEQ     ep_draw_demo
        LDAA    11
        LDAB    13
        JSR     jr_gfx_at
        LDX     ep_txt_evaded
        JSR     jr_gfx_text
ep_draw_demo:
        TST     [JR_TEST_DEMO]
        BEQ     ep_draw_done
        LDAA    EP_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDX     ep_txt_demo
        JSR     jr_gfx_text
ep_draw_done:
        RTS

game_draw_title:
        LDX     ep_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    EP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    EP_ATTR_HERO
        STAA    [JR_RT_COLOR]
        LDAA    9
        LDAB    3
        JSR     jr_gfx_at
        LDAA    EP_TILE_HERO
        JSR     jr_gfx_tile
        LDAA    EP_ATTR_SLASH
        STAA    [JR_RT_COLOR]
        LDAA    14
        LDAB    3
        JSR     jr_gfx_at
        LDAA    EP_CHAR_SLASH
        JSR     jr_gfx_putc
        JSR     jr_gfx_putc
        LDAA    EP_ATTR_KNIGHT
        STAA    [JR_RT_COLOR]
        LDAA    19
        LDAB    3
        JSR     jr_gfx_at
        LDAA    EP_TILE_KNIGHT
        JSR     jr_gfx_tile
        LDX     ep_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    EP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     ep_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; upstream game.json dataTables.pattern: 0 high, 1 low attack
ep_patterns_table:
        .db     0, 1, 1, 0, 1, 0, 0, 1

ep_hud:
        .db     1, 0, EP_ATTR_TITLE
        .dw     ep_txt_name
        .db     3, 2, EP_ATTR_LABEL
        .dw     ep_txt_duel
        .db     8, 2, EP_ATTR_KNIGHT - 0x40
        .dw     ep_txt_knight
        .db     3, 7, EP_ATTR_LABEL
        .dw     ep_txt_chain
        .db     2, 19, EP_ATTR_LABEL
        .dw     ep_txt_hearts
        .db     17, 19, EP_ATTR_LABEL
        .dw     ep_txt_armor
        .db     0xff
ep_title_lines:
        .db     11, 8, EP_ATTR_TITLE
        .dw     ep_txt_name
        .db     3, 10, EP_ATTR_LABEL
        .dw     ep_txt_tagline
        .db     4, 13, EP_ATTR_TEXT
        .dw     ep_txt_start
        .db     4, 15, EP_ATTR_TEXT
        .dw     ep_txt_howto
        .db     4, 17, EP_ATTR_DIM
        .dw     ep_txt_demo_hint
        .db     4, 19, EP_ATTR_DIM
        .dw     ep_txt_credit
        .db     0xff
ep_help_lines:
        .db     11, 1, EP_ATTR_TITLE
        .dw     ep_txt_name
        .db     1, 3, EP_ATTR_TEXT
        .dw     ep_help_1
        .db     1, 5, EP_ATTR_TEXT
        .dw     ep_help_2
        .db     1, 7, EP_ATTR_TEXT
        .dw     ep_help_3
        .db     1, 9, EP_ATTR_TEXT
        .dw     ep_help_4
        .db     1, 11, EP_ATTR_TEXT
        .dw     ep_help_5
        .db     1, 13, EP_ATTR_TEXT
        .dw     ep_help_6
        .db     1, 15, EP_ATTR_TEXT
        .dw     ep_help_7
        .db     1, 17, EP_ATTR_TEXT
        .dw     ep_help_8
        .db     1, 21, EP_ATTR_LABEL
        .dw     ep_help_back
        .db     0xff

ep_txt_name:
        .db     "ECHO PARRY", 0
ep_txt_duel:
        .db     "DUEL", 0
ep_txt_knight:
        .db     "THE ECHO KNIGHT", 0
ep_txt_chain:
        .db     "CHAIN", 0
ep_txt_hearts:
        .db     "HEARTS", 0
ep_txt_armor:
        .db     "ARMOR", 0
ep_txt_ready:
        .db     "READY", 0
ep_txt_feint:
        .db     "FEINT", 0
ep_txt_attack:
        .db     "ATTACK", 0
ep_txt_counter:
        .db     "COUNTER!", 0
ep_txt_recovery:
        .db     "RECOVERY", 0
ep_txt_riposte:
        .db     "RIPOSTE +", 0
ep_txt_evaded:
        .db     "EVADED", 0
ep_txt_demo:
        .db     "DEMO", 0
ep_txt_parry:
        .db     "WRONG GUARD OR EARLY PARRY", 0
ep_txt_window:
        .db     "MISSED THE PARRY WINDOW", 0
ep_txt_tagline:
        .db     "GUARD, WAIT, PARRY THE ECHO", 0
ep_txt_start:
        .db     "RETURN : START", 0
ep_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
ep_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
ep_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
ep_help_1:
        .db     "W : HIGH GUARD / S : LOW GUARD", 0
ep_help_2:
        .db     "RETURN : PARRY DURING ATTACK", 0
ep_help_3:
        .db     "A : STEP BACK, NO COUNTER", 0
ep_help_4:
        .db     "LATE PARRY OR THIRD CHAIN: +2", 0
ep_help_5:
        .db     "WATCH THE WEAPON AFTER A FEINT.", 0
ep_help_6:
        .db     "SIX KNIGHTS USE NEW RHYTHMS.", 0
ep_help_7:
        .db     "FOUR HEARTS FOR EACH DUEL.", 0
ep_help_8:
        .db     "SPACE : RETRY THE DUEL", 0
ep_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     ep_sfx_step, ep_sfx_parry, ep_jingle_win, ep_jingle_lose
ep_sfx_step:
        .db     90, 2, 0, 0
ep_sfx_parry:
        .db     30, 2, 24, 2, 20, 6, 0, 0
ep_sfx_warn:
        .db     80, 3, 0, 1, 80, 3, 0, 0
ep_sfx_hurt:
        .db     160, 3, 220, 6, 0, 0

; Title: a duelling march in A minor, eighth note = 8 frames, looping.
ep_title_song:
        .db     1
        .dw     ep_title_melody, ep_title_harmony, ep_title_bass
ep_title_melody:
        .db     AU_A4, 8, AU_E5, 8, AU_A5, 16, AU_G5, 8, AU_F5, 8, AU_E5, 16
        .db     AU_D5, 8, AU_F5, 8, AU_E5, 8, AU_C5, 8, AU_B4, 32
        .db     AU_A4, 8, AU_C5, 8, AU_E5, 16, AU_D5, 8, AU_C5, 8, AU_B4, 16
        .db     AU_C5, 8, AU_B4, 8, AU_GS4, 8, AU_B4, 8, AU_A4, 32, 0, 0
ep_title_harmony:
        .db     AU_C5, 32, AU_C5, 32, AU_A4, 32, AU_GS4, 32
        .db     AU_E4, 32, AU_G4, 32, AU_E4, 32, AU_E4, 32, 0, 0
ep_title_bass:
        .db     AU_A2, 16, AU_E3, 16, AU_A2, 16, AU_C3, 16, AU_D3, 16, AU_A2, 16, AU_E3, 16, AU_E2, 16
        .db     AU_A2, 16, AU_E3, 16, AU_A2, 16, AU_G2, 16, AU_E2, 16, AU_E3, 16, AU_A2, 32, 0, 0

; Knight defeated: A major flourish.
ep_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     ep_win_melody, ep_win_harmony, ep_win_bass
ep_win_melody:
        .db     AU_E5, 6, AU_A5, 6, AU_CS6, 6, AU_E6, 12, AU_A6, 30, 0, 0
ep_win_harmony:
        .db     AU_CS5, 12, AU_E5, 18, AU_CS6, 30, 0, 0
ep_win_bass:
        .db     AU_A3, 12, AU_E3, 18, AU_A2, 30, 0, 0
ep_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     ep_lose_melody, ep_lose_harmony, ep_lose_bass
ep_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
ep_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
ep_lose_bass:
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
