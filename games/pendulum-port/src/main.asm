; SPDX-License-Identifier: MIT
; PENDULUM PORT for JR-200: a port of jr100dev games/pendulum_port/rules.py 2.0.0.
; Six routes of harbour decks, the swing (one step per tick), the three rope
; lengths, the predicted landing, centre and edge scores, three ropes (lives)
; and the narrow decks of the later routes follow the upstream source. The
; jump is resolved in game_act while its flight is shown. Rules are checked
; by the in-program self test (sdk/selftest.inc, title key T); P plays the
; route-1 demo.
        .filename.jr "PENDULUM-PORT"
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
; Upstream swings every 6 frames; one tick here is GAME_RATE idle frames plus
; the render (see README).
GAME_RATE:          .equ    3
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_TEST_SIZE:     .equ    10
GAME_TEST_LIMIT:    .equ    1000
GAME_TEST_HELD:     .equ    PP_HELD

; Upstream state (tests/model.py LAYOUT), then drawing-only bytes.
PP_HP:              .equ    GAME_STATE
PP_ROPE:            .equ    GAME_STATE + 1
PP_TARGET:          .equ    GAME_STATE + 2
PP_WIDTH:           .equ    GAME_STATE + 3
PP_SWING:           .equ    GAME_STATE + 4
PP_DIRECTION:       .equ    GAME_STATE + 5
PP_PORTS:           .equ    GAME_STATE + 6
PP_SCORE:           .equ    GAME_STATE + 7
PP_DEST:            .equ    GAME_STATE + 8
PP_AIRBORNE:        .equ    GAME_STATE + 9
PP_FLY:             .equ    GAME_STATE + 16     ; 1 while the jumper flies
PP_FX:              .equ    GAME_STATE + 17
PP_FY:              .equ    GAME_STATE + 18
PP_SPARK:           .equ    GAME_STATE + 19
PP_HIT:             .equ    GAME_STATE + 20
PP_HELD:            .equ    GAME_STATE + 21     ; unused (no held keys)
PP_T:               .equ    GAME_STATE + 22
PP_DI:              .equ    GAME_STATE + 24
PP_DX:              .equ    GAME_STATE + 25
PP_DD:              .equ    GAME_STATE + 26
PP_DT:              .equ    GAME_STATE + 27

PP_TILE_PIVOT:      .equ    0x80
PP_TILE_JUMPER:     .equ    0x84
PP_TILE_DECK:       .equ    0x88
PP_TILE_CENTRE:     .equ    0x8c
PP_CHAR_ROPE:       .equ    0x90
PP_CHAR_MARK:       .equ    0x91
PP_CHAR_WAVE:       .equ    0x92
PP_ATTR_PIVOT:      .equ    0x45
PP_ATTR_JUMPER:     .equ    0x47
PP_ATTR_DECK:       .equ    0x46
PP_ATTR_CENTRE:     .equ    0x44
PP_ATTR_ROPE:       .equ    0x46
PP_ATTR_MARK:       .equ    0x42
PP_ATTR_WAVE:       .equ    0x4d        ; cyan on blue
PP_ATTR_SPARK:      .equ    0x74        ; green on yellow
PP_ATTR_HIT:        .equ    0x4f        ; white on blue
PP_ATTR_TEXT:       .equ    0x07
PP_ATTR_LABEL:      .equ    0x04
PP_ATTR_TITLE:      .equ    0x06
PP_ATTR_DIM:        .equ    0x05
PP_ATTR_WARN:       .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     pp_patterns
        LDAA    PP_TILE_PIVOT
        LDAB    19
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        JSR     jr_test_level
        LDAA    3
        STAA    [PP_HP]
        LDAA    2
        STAA    [PP_ROPE]

; A new port: target = 4 + (ports * 7 + level * 3 + 6) % 9, width 1 unless a
; later route (level 3+) is on every third port.
pp_new_port:
        LDAA    [JR_PORT_LEVEL]
        STAA    [PP_T]
        ASLA
        ADDA    [PP_T]
        ADDA    6
        LDAB    [PP_PORTS]
pp_new_port_sum:
        TSTB
        BEQ     pp_new_port_mod
        ADDA    7
        DECB
        BRA     pp_new_port_sum
pp_new_port_mod:
        CMPA    9
        BCS     pp_new_port_target
        SUBA    9
        BRA     pp_new_port_mod
pp_new_port_target:
        ADDA    4
        STAA    [PP_TARGET]
        LDAB    1
        LDAA    [JR_PORT_LEVEL]
        CMPA    3
        BCS     pp_new_port_width
        LDAA    [PP_PORTS]
pp_new_port_three:
        CMPA    3
        BCS     pp_new_port_rest
        SUBA    3
        BRA     pp_new_port_three
pp_new_port_rest:
        TSTA
        BNE     pp_new_port_width
        CLRB
pp_new_port_width:
        STAB    [PP_WIDTH]
        CLR     [PP_SWING]
        LDAA    1
        STAA    [PP_DIRECTION]
        RTS

; -> A = where a release now lands (0-15).
pp_landing:
        TST     [PP_DIRECTION]
        BEQ     pp_landing_back
        LDAA    [PP_SWING]
        ADDA    [PP_ROPE]
        CMPA    15
        BCS     pp_landing_done
        LDAA    15
        RTS
pp_landing_back:
        LDAA    [PP_SWING]
        SUBA    [PP_ROPE]
        BCC     pp_landing_done
        CLRA
pp_landing_done:
        RTS

game_raw_key:
        JMP     jr_test_raw_key

game_act:
        CMPA    JR_KEY_LEFT
        BNE     pp_act_longer
        LDAA    [PP_ROPE]
        CMPA    2
        BCC     pp_act_done_near171
        JMP     pp_act_done
pp_act_done_near171:
        DEC     [PP_ROPE]
        CLRA
        JMP     jr_port_sound
pp_act_longer:
        CMPA    JR_KEY_RIGHT
        BNE     pp_act_jump
        LDAA    [PP_ROPE]
        CMPA    3
        BCS     pp_act_done_near182
        JMP     pp_act_done
pp_act_done_near182:
        INC     [PP_ROPE]
        CLRA
        JMP     jr_port_sound
pp_act_jump:
        CMPA    JR_KEY_CONFIRM
        BEQ     pp_act_done_near190
        JMP     pp_act_done
pp_act_done_near190:
        JSR     pp_landing
        STAA    [PP_DEST]
        LDAA    1
        STAA    [PP_AIRBORNE]
        CLRA
        JSR     jr_port_sound
        ; the flight: up over the apex (swing + dest, 8) and down to the deck
        LDAA    [PP_SWING]
        ADDA    [PP_DEST]
        STAA    [PP_T]
        LDAA    [PP_SWING]
        ASLA
        ADDA    [PP_T]
        LSRA
        LDAB    10
        JSR     pp_flight
        LDAA    [PP_T]
        LDAB    8
        JSR     pp_flight
        LDAA    [PP_DEST]
        ASLA
        ADDA    [PP_T]
        LSRA
        LDAB    12
        JSR     pp_flight
        CLR     [PP_FLY]
        LDAA    2
        STAA    [PP_AIRBORNE]
        ; dest + width >= target and dest <= target + width
        LDAA    [PP_DEST]
        ADDA    [PP_WIDTH]
        CMPA    [PP_TARGET]
        BCS     pp_act_miss
        LDAA    [PP_TARGET]
        ADDA    [PP_WIDTH]
        CMPA    [PP_DEST]
        BCS     pp_act_miss
        LDAB    1
        LDAA    [PP_DEST]
        CMPA    [PP_TARGET]
        BNE     pp_act_score
        INCB
pp_act_score:
        ADDB    [PP_SCORE]
        STAB    [PP_SCORE]
        LDAA    1
        JSR     jr_port_sound
        LDAA    1
        STAA    [PP_SPARK]
        LDAA    16
        JSR     jr_test_animate
        CLR     [PP_SPARK]
        INC     [PP_PORTS]
        LDAA    [JR_PORT_LEVEL]
        ADDA    6
        CMPA    [PP_PORTS]
        BNE     pp_act_next
        CLR     [PP_AIRBORNE]
        JMP     jr_port_win
pp_act_next:
        JSR     pp_new_port
        CLR     [PP_AIRBORNE]
        RTS
pp_act_miss:
        DEC     [PP_HP]
        LDAA    [PP_DEST]
        ASLA
        LDAB    20
        JSR     pp_flight
        CLR     [PP_FLY]
        LDAA    1
        STAA    [PP_HIT]
        LDX     pp_sfx_splash
        JSR     jr_sfx_play
        LDAA    8
        JSR     jr_test_animate
        CLR     [PP_HIT]
        CLR     [PP_AIRBORNE]
        TST     [PP_HP]
        BNE     pp_act_done
        LDX     pp_txt_loss
        JMP     jr_port_lose
pp_act_done:
        RTS

; A = x, B = y: show the jumper there for a moment of the flight.
pp_flight:
        STAA    [PP_FX]
        STAB    [PP_FY]
        LDAA    1
        STAA    [PP_FLY]
        LDAA    3
        JMP     jr_test_animate

game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     pp_act_done
        LDAA    [PP_SWING]
        CMPA    15
        BNE     pp_tick_low
        CLR     [PP_DIRECTION]
pp_tick_low:
        TSTA
        BNE     pp_tick_step
        LDAB    1
        STAB    [PP_DIRECTION]
pp_tick_step:
        TST     [PP_DIRECTION]
        BEQ     pp_tick_back
        INC     [PP_SWING]
        RTS
pp_tick_back:
        DEC     [PP_SWING]
        RTS

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    PP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     pp_hud
        JSR     jr_gfx_lines
        ; the sea
        LDAA    PP_ATTR_WAVE
        STAA    [JR_RT_COLOR]
        CLRA
        LDAB    21
        JSR     jr_gfx_at
        LDAB    32
pp_draw_wave:
        LDAA    PP_CHAR_WAVE
        JSR     jr_gfx_putc
        DECB
        BNE     pp_draw_wave
        LDAA    PP_ATTR_PIVOT
        STAA    [JR_RT_COLOR]
        LDAA    14
        LDAB    3
        JSR     jr_gfx_at
        LDAA    PP_TILE_PIVOT
        JSR     jr_gfx_tile
        ; the rope: x = 15 +- |swing * 2 - 15| * i / 8 on rows 5-12
        LDAA    PP_ATTR_ROPE
        STAA    [JR_RT_COLOR]
        LDAA    [PP_SWING]
        ASLA
        SUBA    15
        BCC     pp_draw_rope_right
        NEGA
        STAA    [PP_DD]
        LDAA    0xff
        BRA     pp_draw_rope_side
pp_draw_rope_right:
        STAA    [PP_DD]
        CLRA
pp_draw_rope_side:
        STAA    [PP_DX]
        CLR     [PP_DI]
        CLR     [PP_DT]
pp_draw_rope:
        LDAA    [PP_DT]
        LSRA
        LSRA
        LSRA
        TST     [PP_DX]
        BEQ     pp_draw_rope_x
        NEGA
pp_draw_rope_x:
        ADDA    15
        LDAB    [PP_DI]
        ADDB    5
        JSR     jr_gfx_at
        LDAA    PP_CHAR_ROPE
        JSR     jr_gfx_putc
        LDAA    [PP_DT]
        ADDA    [PP_DD]
        STAA    [PP_DT]
        INC     [PP_DI]
        LDAA    [PP_DI]
        CMPA    8
        BNE     pp_draw_rope
        ; the decks, the centre and the predicted landing
        LDAA    PP_ATTR_DECK
        STAA    [JR_RT_COLOR]
        LDAA    [PP_TARGET]
        SUBA    [PP_WIDTH]
        ASLA
        LDAB    18
        JSR     jr_gfx_at
        LDAB    [PP_WIDTH]
        ASLB
        INCB
pp_draw_deck:
        LDAA    PP_TILE_DECK
        JSR     jr_gfx_tile
        DECB
        BNE     pp_draw_deck
        LDAA    PP_ATTR_CENTRE
        TST     [PP_SPARK]
        BEQ     pp_draw_centre
        LDAA    PP_ATTR_SPARK
pp_draw_centre:
        STAA    [JR_RT_COLOR]
        LDAA    [PP_TARGET]
        ASLA
        LDAB    18
        JSR     jr_gfx_at
        LDAA    PP_TILE_CENTRE
        JSR     jr_gfx_tile
        LDAA    PP_ATTR_MARK
        STAA    [JR_RT_COLOR]
        JSR     pp_landing
        ASLA
        LDAB    17
        JSR     jr_gfx_at
        LDAA    PP_CHAR_MARK
        JSR     jr_gfx_putc
        ; the jumper: swinging, flying, on the deck or in the sea
        LDAA    PP_ATTR_JUMPER
        TST     [PP_HIT]
        BEQ     pp_draw_jumper_colour
        LDAA    PP_ATTR_HIT
pp_draw_jumper_colour:
        STAA    [JR_RT_COLOR]
        TST     [PP_FLY]
        BEQ     pp_draw_jumper_rest
        LDAA    [PP_FX]
        LDAB    [PP_FY]
        BRA     pp_draw_jumper_at
pp_draw_jumper_rest:
        LDAA    [PP_AIRBORNE]
        BEQ     pp_draw_jumper_swing
        CMPA    2
        BNE     pp_draw_panel
        LDAA    [PP_DEST]
        ASLA
        LDAB    16
        TST     [PP_HIT]
        BEQ     pp_draw_jumper_at
        LDAB    20
        BRA     pp_draw_jumper_at
pp_draw_jumper_swing:
        LDAA    [PP_SWING]
        ASLA
        LDAB    13
pp_draw_jumper_at:
        JSR     jr_gfx_at
        LDAA    PP_TILE_JUMPER
        JSR     jr_gfx_tile
pp_draw_panel:
        LDAA    PP_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    5
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [PP_ROPE]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    8
        LDAB    2
        JSR     jr_gfx_at
        LDAA    0x3c
        TST     [PP_DIRECTION]
        BEQ     pp_draw_arrow
        LDAA    0x3e
pp_draw_arrow:
        JSR     jr_gfx_putc
        LDAA    27
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [PP_SCORE]
        JSR     jr_gfx_dec3
        LDAA    9
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [PP_HP]
        JSR     jr_gfx_dec2
        LDAA    25
        LDAB    20
        JSR     jr_gfx_at
        LDAA    [PP_PORTS]
        JSR     jr_gfx_dec2
        TST     [JR_TEST_DEMO]
        BEQ     pp_draw_done
        LDAA    PP_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDX     pp_txt_demo
        JSR     jr_gfx_text
pp_draw_done:
        RTS

game_draw_title:
        LDX     pp_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    PP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     pp_title_tiles
        STX     [JR_RT_TABLE]
pp_title_tile:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     pp_title_text
        LDAB    [X + 1]
        STAB    [JR_RT_COLOR]
        LDAB    [X + 2]
        STAB    [PP_DD]
        LDAB    [X + 3]
        JSR     jr_gfx_at
        LDAA    [PP_DD]
        JSR     jr_gfx_tile
        LDX     [JR_RT_TABLE]
        INX
        INX
        INX
        INX
        STX     [JR_RT_TABLE]
        BRA     pp_title_tile
pp_title_text:
        LDX     pp_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    PP_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     pp_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; x, attribute, code, y: a jumper leaving the pivot for a deck
pp_title_tiles:
        .db     8, PP_ATTR_PIVOT, PP_TILE_PIVOT, 1
        .db     14, PP_ATTR_JUMPER, PP_TILE_JUMPER, 3
        .db     20, PP_ATTR_DECK, PP_TILE_DECK, 5
        .db     22, PP_ATTR_CENTRE, PP_TILE_CENTRE, 5
        .db     24, PP_ATTR_DECK, PP_TILE_DECK, 5
        .db     0xff

pp_hud:
        .db     1, 0, PP_ATTR_TITLE
        .dw     pp_txt_name
        .db     0, 2, PP_ATTR_LABEL
        .dw     pp_txt_rope
        .db     19, 2, PP_ATTR_LABEL
        .dw     pp_txt_centre
        .db     1, 20, PP_ATTR_LABEL
        .dw     pp_txt_ropes
        .db     17, 20, PP_ATTR_LABEL
        .dw     pp_txt_ports
        .db     0xff
pp_title_lines:
        .db     9, 8, PP_ATTR_TITLE
        .dw     pp_txt_name
        .db     3, 10, PP_ATTR_LABEL
        .dw     pp_txt_tagline
        .db     4, 13, PP_ATTR_TEXT
        .dw     pp_txt_start
        .db     4, 15, PP_ATTR_TEXT
        .dw     pp_txt_howto
        .db     4, 17, PP_ATTR_DIM
        .dw     pp_txt_demo_hint
        .db     4, 19, PP_ATTR_DIM
        .dw     pp_txt_credit
        .db     0xff
pp_help_lines:
        .db     9, 1, PP_ATTR_TITLE
        .dw     pp_txt_name
        .db     1, 3, PP_ATTR_TEXT
        .dw     pp_help_1
        .db     1, 5, PP_ATTR_TEXT
        .dw     pp_help_2
        .db     1, 7, PP_ATTR_TEXT
        .dw     pp_help_3
        .db     1, 9, PP_ATTR_TEXT
        .dw     pp_help_4
        .db     1, 11, PP_ATTR_TEXT
        .dw     pp_help_5
        .db     1, 13, PP_ATTR_TEXT
        .dw     pp_help_6
        .db     1, 15, PP_ATTR_TEXT
        .dw     pp_help_7
        .db     1, 17, PP_ATTR_TEXT
        .dw     pp_help_8
        .db     1, 21, PP_ATTR_LABEL
        .dw     pp_help_back
        .db     0xff

pp_txt_name:
        .db     "PENDULUM PORT", 0
pp_txt_rope:
        .db     "ROPE", 0
pp_txt_centre:
        .db     "CENTRE", 0
pp_txt_ropes:
        .db     "ROPES", 0
pp_txt_ports:
        .db     "PORTS", 0
pp_txt_demo:
        .db     "DEMO", 0
pp_txt_loss:
        .db     "THE JUMP MISSED THE PORT", 0
pp_txt_tagline:
        .db     "SWING, LET GO, LAND ON DECK", 0
pp_txt_start:
        .db     "RETURN : START", 0
pp_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
pp_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
pp_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
pp_help_1:
        .db     "A/D : SHORTEN / LENGTHEN ROPE", 0
pp_help_2:
        .db     "RETURN : RELEASE THE SWING", 0
pp_help_3:
        .db     "MOMENTUM CARRIES THE JUMP.", 0
pp_help_4:
        .db     "THE V MARK PREDICTS LANDING.", 0
pp_help_5:
        .db     "HIT THE CENTRE FOR TWO POINTS.", 0
pp_help_6:
        .db     "LATER PORTS HAVE SMALLER DECKS.", 0
pp_help_7:
        .db     "SIX ROUTES / THREE ROPES EACH.", 0
pp_help_8:
        .db     "SPACE : RETRY THE ROUTE", 0
pp_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     pp_sfx_rope, pp_sfx_land, pp_jingle_win, pp_jingle_lose
pp_sfx_rope:
        .db     70, 2, 0, 0
pp_sfx_land:
        .db     50, 2, 40, 2, 33, 2, 25, 6, 0, 0
pp_sfx_splash:
        .db     150, 2, 200, 2, 250, 6, 0, 0

; Title: a sea shanty in D minor, eighth note = 8 frames, looping.
pp_title_song:
        .db     1
        .dw     pp_title_melody, pp_title_harmony, pp_title_bass
pp_title_melody:
        .db     AU_A4, 8, AU_D5, 16, AU_D5, 8, AU_E5, 8, AU_F5, 8, AU_D5, 16
        .db     AU_C5, 8, AU_A4, 16, AU_C5, 8, AU_D5, 8, AU_E5, 8, AU_C5, 16
        .db     AU_A4, 8, AU_D5, 16, AU_D5, 8, AU_F5, 8, AU_A5, 8, AU_G5, 16
        .db     AU_F5, 8, AU_E5, 8, AU_C5, 8, AU_D5, 32, 0, 0
pp_title_harmony:
        .db     AU_F4, 48, AU_E4, 48, AU_F4, 48, AU_A4, 24, AU_F4, 24, 0, 0
pp_title_bass:
        .db     AU_D3, 24, AU_A2, 24, AU_C3, 24, AU_G2, 24
        .db     AU_D3, 24, AU_AS2, 24, AU_A2, 24, AU_D3, 24, 0, 0

; Route finished: D major fanfare.
pp_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     pp_win_melody, pp_win_harmony, pp_win_bass
pp_win_melody:
        .db     AU_A4, 6, AU_D5, 6, AU_FS5, 6, AU_A5, 12, AU_D6, 30, 0, 0
pp_win_harmony:
        .db     AU_FS4, 12, AU_A4, 18, AU_FS5, 30, 0, 0
pp_win_bass:
        .db     AU_D3, 12, AU_A2, 18, AU_D2, 30, 0, 0
pp_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     pp_lose_melody, pp_lose_harmony, pp_lose_bass
pp_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
pp_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
pp_lose_bass:
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
