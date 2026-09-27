; SPDX-License-Identifier: MIT
; LUNAR TOUCHDOWN for JR-200: a port of jr100dev games/lunar_touchdown/rules.py 2.0.0.
; Six landing sites, gravity every third tick, thrust and fuel, the crosswind
; of the later sites, the wide pad and the narrow star pad, the landing speed
; limit and the score follow the upstream source, one upstream tick per
; game_tick. Rules are checked by the in-program self test (sdk/selftest.inc,
; title key T); P plays the site-1 demo.
        .filename.jr "LUNAR-TOUCHDOWN"
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
; Upstream falls every 15 frames; one tick here is GAME_RATE idle frames plus
; the render and the descent glide (see README).
GAME_RATE:          .equ    6
GAME_SPACE_RESET:   .equ    1
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    2
GAME_TEST_SIZE:     .equ    14
GAME_TEST_LIMIT:    .equ    1000
GAME_TEST_HELD:     .equ    LT_HELD

; Upstream state (tests/model.py LAYOUT), then drawing-only bytes.
LT_X:               .equ    GAME_STATE
LT_TARGET:          .equ    GAME_STATE + 1
LT_NARROW:          .equ    GAME_STATE + 2
LT_WIDTH:           .equ    GAME_STATE + 3
LT_FUEL:            .equ    GAME_STATE + 4
LT_WIND:            .equ    GAME_STATE + 5
LT_SPEED:           .equ    GAME_STATE + 6
LT_FLAME:           .equ    GAME_STATE + 7
LT_TIME:            .equ    GAME_STATE + 8
LT_HEIGHT:          .equ    GAME_STATE + 9
LT_MIDDLE:          .equ    GAME_STATE + 10
LT_DESCENDING:      .equ    GAME_STATE + 11
LT_LANDED:          .equ    GAME_STATE + 12
LT_SCORE:           .equ    GAME_STATE + 13
LT_SPARK:           .equ    GAME_STATE + 16
LT_HIT:             .equ    GAME_STATE + 17
LT_HELD:            .equ    GAME_STATE + 18     ; unused (no held keys)
LT_OLD:             .equ    GAME_STATE + 19
LT_PRECISE:         .equ    GAME_STATE + 20
LT_T:               .equ    GAME_STATE + 21
LT_MSG:             .equ    GAME_STATE + 22     ; 2 bytes
LT_DI:              .equ    GAME_STATE + 24
LT_DY:              .equ    GAME_STATE + 25

LT_TILE_LANDER:     .equ    0x80
LT_CHAR_FLAME_BIG:  .equ    0x84
LT_CHAR_FLAME:      .equ    0x85
LT_CHAR_PAD:        .equ    0x86
LT_CHAR_GROUND:     .equ    0x87
LT_CHAR_STAR:       .equ    0x88
LT_CHAR_SKY:        .equ    0x89
LT_ATTR_LANDER:     .equ    0x47
LT_ATTR_FLAME:      .equ    0x42
LT_ATTR_PAD:        .equ    0x44
LT_ATTR_NARROW:     .equ    0x46
LT_ATTR_GROUND:     .equ    0x45
LT_ATTR_SKY:        .equ    0x41
LT_ATTR_SPARK:      .equ    0x74        ; green on yellow
LT_ATTR_HIT:        .equ    0x72        ; red on yellow
LT_ATTR_TEXT:       .equ    0x07
LT_ATTR_LABEL:      .equ    0x04
LT_ATTR_TITLE:      .equ    0x06
LT_ATTR_DIM:        .equ    0x05
LT_ATTR_WARN:       .equ    0x02

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        JSR     jr_test_init
        LDX     lt_patterns
        LDAA    LT_TILE_LANDER
        LDAB    10
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

game_init:
        JSR     jr_music_stop
        JSR     jr_test_level
        LDAA    3
        STAA    [LT_X]
        LDAA    [JR_PORT_LEVEL]
        STAA    [LT_T]
        ASLA
        ADDA    [LT_T]
        ADDA    7
        STAA    [LT_TARGET]
        LDAB    24
        CMPA    18
        BCS     lt_init_narrow
        LDAB    5
lt_init_narrow:
        STAB    [LT_NARROW]
        LDAB    3
        LDAA    [JR_PORT_LEVEL]
        CMPA    3
        BCS     lt_init_width
        LDAB    2
lt_init_width:
        STAB    [LT_WIDTH]
        LDAA    22
        STAA    [LT_FUEL]
        LDAA    [JR_PORT_LEVEL]
        ANDA    1
        STAA    [LT_WIND]
        RTS

game_raw_key:
        JMP     jr_test_raw_key

game_act:
        LDAB    [LT_X]
        STAB    [LT_OLD]
        CMPA    JR_KEY_LEFT
        BNE     lt_act_right
        TSTB
        BEQ     lt_act_moved
        DEC     [LT_X]
        BRA     lt_act_moved
lt_act_right:
        CMPA    JR_KEY_RIGHT
        BNE     lt_act_thrust
        CMPB    28
        BCC     lt_act_moved
        INC     [LT_X]
        BRA     lt_act_moved
lt_act_thrust:
        CMPA    JR_KEY_UP
        BEQ     lt_act_burn
        CMPA    JR_KEY_CONFIRM
        BNE     lt_act_moved
lt_act_burn:
        TST     [LT_FUEL]
        BEQ     lt_act_moved
        LDAA    [LT_SPEED]
        SUBA    2
        BCC     lt_act_speed
        CLRA
lt_act_speed:
        STAA    [LT_SPEED]
        DEC     [LT_FUEL]
        LDAA    2
        STAA    [LT_FLAME]
        CLRA
        JSR     jr_port_sound
        LDAA    3
        JSR     jr_test_animate
lt_act_moved:
        LDAA    [LT_X]
        CMPA    [LT_OLD]
        BEQ     lt_act_done
        CLRA
        JMP     jr_port_sound
lt_act_done:
        RTS

; A = value, B = divisor -> A = value mod divisor.
lt_mod:
        STAB    [LT_T]
lt_mod_next:
        CMPA    [LT_T]
        BCS     lt_act_done
        SUBA    [LT_T]
        BRA     lt_mod_next

game_tick:
        JSR     jr_test_demo_step
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_PLAY
        BNE     lt_act_done
        INC     [LT_TIME]
        TST     [LT_FLAME]
        BEQ     lt_tick_gravity
        DEC     [LT_FLAME]
lt_tick_gravity:
        LDAA    [LT_TIME]
        LDAB    3
        JSR     lt_mod
        TSTA
        BNE     lt_tick_wind
        LDAA    [LT_SPEED]
        CMPA    5
        BCC     lt_tick_wind
        INC     [LT_SPEED]
lt_tick_wind:
        TST     [JR_PORT_LEVEL]
        BEQ     lt_tick_turn
        LDAA    [LT_TIME]
        ANDA    3
        BNE     lt_tick_turn
        LDAA    [LT_X]
        TST     [LT_WIND]
        BEQ     lt_tick_west
        CMPA    28
        BCC     lt_tick_turn
        INC     [LT_X]
        BRA     lt_tick_turn
lt_tick_west:
        TSTA
        BEQ     lt_tick_turn
        DEC     [LT_X]
lt_tick_turn:
        LDAB    16
        LDAA    [JR_PORT_LEVEL]
        CMPA    3
        BCS     lt_tick_period
        LDAB    12
lt_tick_period:
        LDAA    [LT_TIME]
        JSR     lt_mod
        TSTA
        BNE     lt_tick_fall
        LDAA    [LT_WIND]
        EORA    1
        STAA    [LT_WIND]
lt_tick_fall:
        LDAB    [LT_HEIGHT]
        TBA
        ADDA    [LT_SPEED]
        CMPA    30
        BCS     lt_tick_height
        LDAA    30
lt_tick_height:
        STAA    [LT_HEIGHT]
        ABA
        LSRA
        STAA    [LT_MIDDLE]
        LDAA    1
        STAA    [LT_DESCENDING]
        LDAA    2
        JSR     jr_test_animate
        CLR     [LT_DESCENDING]
        LDAA    [LT_HEIGHT]
        CMPA    30
        BCC     lt_act_done_near251
        JMP     lt_act_done
lt_act_done_near251:
        ; on the ground: a pad (wide or the star pad) at speed 2 or less
        CLR     [LT_PRECISE]
        LDAA    [LT_X]
        CMPA    [LT_NARROW]
        BNE     lt_tick_regular
        INC     [LT_PRECISE]
        BRA     lt_tick_pad
lt_tick_regular:
        CMPA    [LT_TARGET]
        BCS     lt_tick_crash
        LDAB    [LT_TARGET]
        ADDB    [LT_WIDTH]
        CBA
        BHI     lt_tick_crash
lt_tick_pad:
        LDAA    [LT_SPEED]
        CMPA    3
        BCC     lt_tick_crash
        LDAA    1
        STAA    [LT_LANDED]
        LDAA    [LT_FUEL]
        TST     [LT_PRECISE]
        BEQ     lt_tick_soft
        ADDA    10
lt_tick_soft:
        LDAB    [LT_SPEED]
        CMPB    2
        BCC     lt_tick_score
        ADDA    4
lt_tick_score:
        STAA    [LT_SCORE]
        LDAA    1
        JSR     jr_port_sound
        LDAA    1
        STAA    [LT_SPARK]
        LDAA    24
        JSR     jr_test_animate
        CLR     [LT_SPARK]
        JMP     jr_port_win
lt_tick_crash:
        LDX     lt_txt_pad
        LDAA    [LT_SPEED]
        CMPA    3
        BCS     lt_tick_crash_show
        LDX     lt_txt_speed
lt_tick_crash_show:
        STX     [LT_MSG]
        LDAA    1
        STAA    [LT_HIT]
        LDX     lt_sfx_crash
        JSR     jr_sfx_play
        LDAA    8
        JSR     jr_test_animate
        LDX     [LT_MSG]
        JMP     jr_port_lose

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    LT_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     lt_hud
        JSR     jr_gfx_lines
        ; sky dots
        LDAA    LT_ATTR_SKY
        STAA    [JR_RT_COLOR]
        LDX     lt_sky
        STX     [JR_RT_TABLE]
lt_draw_sky:
        LDX     [JR_RT_TABLE]
        LDAA    [X]
        CMPA    0xff
        BEQ     lt_draw_ground
        LDAB    [X + 1]
        INX
        INX
        STX     [JR_RT_TABLE]
        JSR     jr_gfx_at
        LDAA    LT_CHAR_SKY
        JSR     jr_gfx_putc
        BRA     lt_draw_sky
lt_draw_ground:
        LDAA    LT_ATTR_GROUND
        STAA    [JR_RT_COLOR]
        CLRA
        LDAB    22
        JSR     jr_gfx_at
        LDAB    32
lt_draw_ground_next:
        LDAA    LT_CHAR_GROUND
        JSR     jr_gfx_putc
        DECB
        BNE     lt_draw_ground_next
        ; the wide pad (width + 2 cells), the star pad and its marker
        LDAA    LT_ATTR_PAD
        STAA    [JR_RT_COLOR]
        LDAA    [LT_TARGET]
        LDAB    21
        JSR     jr_gfx_at
        LDAB    [LT_WIDTH]
        ADDB    2
lt_draw_pad:
        LDAA    LT_CHAR_PAD
        JSR     jr_gfx_putc
        DECB
        BNE     lt_draw_pad
        LDAA    LT_ATTR_NARROW
        STAA    [JR_RT_COLOR]
        LDAA    [LT_NARROW]
        LDAB    21
        JSR     jr_gfx_at
        LDAA    LT_CHAR_PAD
        JSR     jr_gfx_putc
        JSR     jr_gfx_putc
        LDAA    [LT_NARROW]
        LDAB    22
        JSR     jr_gfx_at
        LDAA    LT_CHAR_STAR
        JSR     jr_gfx_putc
        ; the lander (half-way while descending) and its flame
        LDAA    [LT_HEIGHT]
        TST     [LT_DESCENDING]
        BEQ     lt_draw_lander
        LDAA    [LT_MIDDLE]
lt_draw_lander:
        LSRA
        STAA    [LT_DY]
        LDAA    LT_ATTR_LANDER
        TST     [LT_SPARK]
        BEQ     lt_draw_lander_hit
        LDAA    LT_ATTR_SPARK
lt_draw_lander_hit:
        TST     [LT_HIT]
        BEQ     lt_draw_lander_colour
        LDAA    LT_ATTR_HIT
lt_draw_lander_colour:
        STAA    [JR_RT_COLOR]
        LDAA    [LT_X]
        LDAB    [LT_DY]
        ADDB    4
        JSR     jr_gfx_at
        LDAA    LT_TILE_LANDER
        JSR     jr_gfx_tile
        LDAA    [LT_FLAME]
        BEQ     lt_draw_panel
        LDAB    LT_ATTR_FLAME
        STAB    [JR_RT_COLOR]
        LDAB    LT_CHAR_FLAME_BIG
        CMPA    1
        BNE     lt_draw_flame
        LDAB    LT_CHAR_FLAME
lt_draw_flame:
        STAB    [LT_DI]
        LDAA    [LT_X]
        LDAB    [LT_DY]
        ADDB    6
        JSR     jr_gfx_at
        LDAA    [LT_DI]
        JSR     jr_gfx_putc
        JSR     jr_gfx_putc
lt_draw_panel:
        LDAA    LT_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    5
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [LT_FUEL]
        JSR     jr_gfx_dec2
        LDAA    LT_ATTR_TEXT
        LDAB    [LT_SPEED]
        CMPB    3
        BCS     lt_draw_speed
        LDAA    LT_ATTR_WARN
lt_draw_speed:
        STAA    [JR_RT_COLOR]
        LDAA    13
        LDAB    2
        JSR     jr_gfx_at
        LDAA    [LT_SPEED]
        JSR     jr_gfx_dec2
        LDAA    LT_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    20
        LDAB    2
        JSR     jr_gfx_at
        LDAA    30
        SUBA    [LT_HEIGHT]
        JSR     jr_gfx_dec2
        LDAA    29
        LDAB    2
        JSR     jr_gfx_at
        LDAA    0x2d
        TST     [JR_PORT_LEVEL]
        BEQ     lt_draw_wind
        LDAA    0x3c
        TST     [LT_WIND]
        BEQ     lt_draw_wind
        LDAA    0x3e
lt_draw_wind:
        JSR     jr_gfx_putc
        TST     [LT_LANDED]
        BEQ     lt_draw_demo
        LDAA    LT_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    4
        LDAB    15
        JSR     jr_gfx_at
        LDX     lt_txt_touchdown
        JSR     jr_gfx_text
        LDAA    21
        LDAB    15
        JSR     jr_gfx_at
        LDAA    [LT_SCORE]
        JSR     jr_gfx_dec2
lt_draw_demo:
        TST     [JR_TEST_DEMO]
        BEQ     lt_draw_done
        LDAA    LT_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDX     lt_txt_demo
        JSR     jr_gfx_text
lt_draw_done:
        RTS

game_draw_title:
        LDX     lt_title_song
        JSR     jr_music_play
game_test_draw:
        LDAA    0x20
        LDAB    LT_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    LT_ATTR_LANDER
        STAA    [JR_RT_COLOR]
        LDAA    15
        LDAB    2
        JSR     jr_gfx_at
        LDAA    LT_TILE_LANDER
        JSR     jr_gfx_tile
        LDAA    LT_ATTR_FLAME
        STAA    [JR_RT_COLOR]
        LDAA    15
        LDAB    4
        JSR     jr_gfx_at
        LDAA    LT_CHAR_FLAME_BIG
        JSR     jr_gfx_putc
        JSR     jr_gfx_putc
        LDAA    LT_ATTR_PAD
        STAA    [JR_RT_COLOR]
        LDAA    13
        LDAB    6
        JSR     jr_gfx_at
        LDAB    6
lt_title_pad:
        LDAA    LT_CHAR_PAD
        JSR     jr_gfx_putc
        DECB
        BNE     lt_title_pad
        LDX     lt_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    LT_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     lt_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; x, y of the sky dots
lt_sky:
        .db     3, 5, 11, 4, 26, 6, 30, 9, 7, 10, 18, 8, 23, 12, 2, 14
        .db     13, 16, 28, 15, 9, 18, 20, 17, 0xff

lt_hud:
        .db     1, 0, LT_ATTR_TITLE
        .dw     lt_txt_name
        .db     0, 2, LT_ATTR_LABEL
        .dw     lt_txt_gauges
        .db     0xff
lt_title_lines:
        .db     8, 8, LT_ATTR_TITLE
        .dw     lt_txt_name
        .db     3, 10, LT_ATTR_LABEL
        .dw     lt_txt_tagline
        .db     4, 13, LT_ATTR_TEXT
        .dw     lt_txt_start
        .db     4, 15, LT_ATTR_TEXT
        .dw     lt_txt_howto
        .db     4, 17, LT_ATTR_DIM
        .dw     lt_txt_demo_hint
        .db     4, 19, LT_ATTR_DIM
        .dw     lt_txt_credit
        .db     0xff
lt_help_lines:
        .db     8, 1, LT_ATTR_TITLE
        .dw     lt_txt_name
        .db     1, 3, LT_ATTR_TEXT
        .dw     lt_help_1
        .db     1, 5, LT_ATTR_TEXT
        .dw     lt_help_2
        .db     1, 7, LT_ATTR_TEXT
        .dw     lt_help_3
        .db     1, 9, LT_ATTR_TEXT
        .dw     lt_help_4
        .db     1, 11, LT_ATTR_TEXT
        .dw     lt_help_5
        .db     1, 13, LT_ATTR_TEXT
        .dw     lt_help_6
        .db     1, 15, LT_ATTR_TEXT
        .dw     lt_help_7
        .db     1, 17, LT_ATTR_TEXT
        .dw     lt_help_8
        .db     1, 21, LT_ATTR_LABEL
        .dw     lt_help_back
        .db     0xff

lt_txt_name:
        .db     "LUNAR TOUCHDOWN", 0
lt_txt_gauges:
        .db     "FUEL    FALL    ALT    WIND", 0
lt_txt_touchdown:
        .db     "TOUCHDOWN! SCORE", 0
lt_txt_demo:
        .db     "DEMO", 0
lt_txt_speed:
        .db     "DESCENT SPEED TOO HIGH", 0
lt_txt_pad:
        .db     "MISSED BOTH LANDING PADS", 0
lt_txt_tagline:
        .db     "THRUST, STEER, LAND SOFTLY", 0
lt_txt_start:
        .db     "RETURN : START", 0
lt_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
lt_txt_demo_hint:
        .db     "P : DEMO   T : SELF TEST", 0
lt_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
lt_help_1:
        .db     "A/D : HORIZONTAL CONTROL", 0
lt_help_2:
        .db     "W / RETURN : THRUST (-2 SPEED)", 0
lt_help_3:
        .db     "LAND WITH A SPEED OF 0 TO 2.", 0
lt_help_4:
        .db     "WIDE PAD: SAFE / * PAD: +10", 0
lt_help_5:
        .db     "KEEP FUEL FOR A HIGHER SCORE.", 0
lt_help_6:
        .db     "LATER SITES HAVE CROSSWINDS.", 0
lt_help_7:
        .db     "WATCH THE WIND ARROW CHANGE.", 0
lt_help_8:
        .db     "SPACE : RETRY THE SITE", 0
lt_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     lt_sfx_thrust, lt_sfx_land, lt_jingle_win, lt_jingle_lose
lt_sfx_thrust:
        .db     220, 2, 200, 2, 0, 0
lt_sfx_land:
        .db     60, 3, 45, 3, 30, 8, 0, 0
lt_sfx_crash:
        .db     180, 2, 240, 2, 200, 2, 250, 6, 0, 0

; Title: a slow space theme in E minor, eighth note = 8 frames, looping.
lt_title_song:
        .db     1
        .dw     lt_title_melody, lt_title_harmony, lt_title_bass
lt_title_melody:
        .db     AU_E5, 16, AU_B4, 8, AU_E5, 8, AU_FS5, 16, AU_G5, 16
        .db     AU_FS5, 8, AU_E5, 8, AU_D5, 8, AU_B4, 8, AU_A4, 32
        .db     AU_G4, 16, AU_A4, 8, AU_B4, 8, AU_D5, 16, AU_E5, 16
        .db     AU_D5, 8, AU_B4, 8, AU_A4, 8, AU_FS4, 8, AU_E4, 32, 0, 0
lt_title_harmony:
        .db     AU_G4, 32, AU_B4, 32, AU_A4, 32, AU_FS4, 32
        .db     AU_E4, 32, AU_G4, 32, AU_FS4, 32, AU_B3, 32, 0, 0
lt_title_bass:
        .db     AU_E2, 32, AU_E3, 32, AU_D2, 32, AU_D3, 32
        .db     AU_C3, 32, AU_G2, 32, AU_B2, 32, AU_E2, 32, 0, 0

; Touchdown: E major rising call.
lt_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     lt_win_melody, lt_win_harmony, lt_win_bass
lt_win_melody:
        .db     AU_B4, 6, AU_E5, 6, AU_GS5, 6, AU_B5, 12, AU_E6, 30, 0, 0
lt_win_harmony:
        .db     AU_GS4, 12, AU_B4, 18, AU_GS5, 30, 0, 0
lt_win_bass:
        .db     AU_E3, 12, AU_B2, 18, AU_E2, 30, 0, 0
lt_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     lt_lose_melody, lt_lose_harmony, lt_lose_bass
lt_lose_melody:
        .db     AU_CS5, 12, AU_B4, 12, AU_A4, 12, AU_GS4, 30, 0, 0
lt_lose_harmony:
        .db     AU_A4, 12, AU_GS4, 12, AU_FS4, 12, AU_F4, 30, 0, 0
lt_lose_bass:
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
