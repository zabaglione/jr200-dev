; SPDX-License-Identifier: MIT
; DICE RELIC for JR-200: a port of jr100dev games/dice_relic 1.7.1.
; Three dice a turn, each used once for ATTACK, GUARD or HEAL (or one
; REROLL a turn), the enemy's strike after the third die (+2 every fourth
; turn) against the guard, nine guardians, the victory reward and the
; workshop's FORGE (+2 to a face, up to 9) and HEAL follow the upstream
; model.py and M6800 source (see tests/model.py), including the PRNG.
; Display, colour and three-voice sound use the JR-200 port SDK.
        .filename.jr "DICE-RELIC"
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
GAME_SPACE_RESET:   .equ    0       ; SPACE closes the workshop menu, as upstream
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    3

; Upstream state (same order as tests/model.py LAYOUT).
DR_HP:              .equ    GAME_STATE
DR_SHIELD:          .equ    GAME_STATE + 1
DR_COINS:           .equ    GAME_STATE + 2
DR_BATTLE:          .equ    GAME_STATE + 3
DR_EHP:             .equ    GAME_STATE + 4
DR_EATK:            .equ    GAME_STATE + 5
DR_TURN:            .equ    GAME_STATE + 6
DR_REROLLS:         .equ    GAME_STATE + 7
DR_USED:            .equ    GAME_STATE + 8
DR_RNG:             .equ    GAME_STATE + 9
DR_SEED:            .equ    GAME_STATE + 10
DR_SEL:             .equ    GAME_STATE + 11
DR_CHOICE:          .equ    GAME_STATE + 12
DR_FACE:            .equ    GAME_STATE + 13
DR_MENU:            .equ    GAME_STATE + 14
DR_SUB:             .equ    GAME_STATE + 15     ; 0 battle, 1 workshop, 2 menu
DR_ERROR:           .equ    GAME_STATE + 16
DR_DICE:            .equ    GAME_STATE + 17
DR_FACES:           .equ    GAME_STATE + 20
DR_ROLES:           .equ    GAME_STATE + 38
; Rule and effect bytes (game_draw reads the effect bytes, never writes them).
DR_I:               .equ    GAME_STATE + 48
DR_VAL:             .equ    GAME_STATE + 49
DR_ATK:             .equ    GAME_STATE + 50
DR_DMG:             .equ    GAME_STATE + 51
DR_EV_KIND:         .equ    GAME_STATE + 52
DR_EV_VALUE:        .equ    GAME_STATE + 53
DR_EV_BEFORE:       .equ    GAME_STATE + 54
DR_EV_AFTER:        .equ    GAME_STATE + 55
DR_ROLLING:         .equ    GAME_STATE + 56     ; dice still rolling (mask)
DR_FX:              .equ    GAME_STATE + 57     ; effect step
; Drawing work bytes.
DR_DI:              .equ    GAME_STATE + 64
DR_DX:              .equ    GAME_STATE + 65
DR_DY:              .equ    GAME_STATE + 66
DR_DV:              .equ    GAME_STATE + 67
DR_DPTR:            .equ    GAME_STATE + 68     ; 2 bytes
DR_DM:              .equ    GAME_STATE + 70     ; the drawn die's bit

DR_SUB_WORKSHOP:    .equ    1
DR_SUB_MENU:        .equ    2
DR_MAX_HP:          .equ    42
; effect kinds (as upstream SHOW_EFFECT) and their frames
DR_EV_ATTACK:       .equ    1
DR_EV_HIT:          .equ    2
DR_EV_GUARD:        .equ    3
DR_EV_HEAL:         .equ    4
DR_EV_STRIKE:       .equ    5
DR_EV_BLOCKED:      .equ    6
DR_EV_DAMAGE:       .equ    7
DR_EV_VICTORY:      .equ    8
DR_EV_REWARD:       .equ    9
DR_EV_DEFEAT:       .equ    10

DR_CHAR_BOX:        .equ    0x80    ; TL, top, TR, left, right, BL, bottom, BR
DR_TILE_GUARDIAN:   .equ    0x88
DR_TILE_KING:       .equ    0x8c
DR_TILE_HERO:       .equ    0x90
DR_TILE_SHIELD:     .equ    0x94
DR_CHAR_BOLT:       .equ    0x98
DR_CHAR_SPARK:      .equ    0x99
DR_CHAR_COIN:       .equ    0x9a
DR_CHAR_HEART:      .equ    0x9b
DR_ATTR_DIE:        .equ    0x47
DR_ATTR_PICKED:     .equ    0x46
DR_ATTR_SPENT:      .equ    0x41
DR_ATTR_HERO:       .equ    0x44
DR_ATTR_SHIELD:     .equ    0x45
DR_ATTR_BOLT:       .equ    0x46
DR_ATTR_HIT:        .equ    0x42
DR_ATTR_HEART:      .equ    0x42
DR_ATTR_COIN:       .equ    0x46
DR_ATTR_TEXT:       .equ    0x07
DR_ATTR_LABEL:      .equ    0x04
DR_ATTR_TITLE:      .equ    0x06
DR_ATTR_DIM:        .equ    0x05
DR_ATTR_PICK:       .equ    0x06
DR_ATTR_WARN:       .equ    0x02
DR_ATTR_DIGIT:      .equ    0x07
DR_ATTR_DIGIT_PICK: .equ    0x06
DR_ATTR_DIGIT_SPENT: .equ   0x05

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     dr_patterns
        LDAA    DR_CHAR_BOX
        LDAB    28
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; NEW_GAME: the seed is the title song's position (upstream: its timer).
game_init:
        LDAA    [JR_AU_VOICE + 1]
        EORA    [JR_AU_VOICE + 2]
        ORAA    1
        STAA    [DR_SEED]
        STAA    [DR_RNG]
        LDX     dr_battle_song
        JSR     jr_music_play
        CLR     [DR_BATTLE]
        CLR     [DR_COINS]
        LDAA    DR_MAX_HP
        STAA    [DR_HP]
        LDX     DR_FACES
        LDAB    3
dr_init_die:
        LDAA    1
dr_init_face:
        STAA    [X]
        INX
        INCA
        CMPA    7
        BNE     dr_init_face
        DECB
        BNE     dr_init_die
        ; fall through

dr_new_battle:
        LDX     dr_enemies
        LDAA    [DR_BATTLE]
        ASLA
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [DR_EHP]
        LDAA    [X + 1]
        STAA    [DR_EATK]
        CLR     [DR_TURN]
        CLR     [DR_SHIELD]
        CLR     [DR_SEL]
        CLR     [DR_CHOICE]
        CLR     [DR_SUB]
        CLR     [DR_EV_KIND]
        ; fall through

; NEW_TURN: three fresh dice, one reroll.
dr_new_turn:
        INC     [DR_TURN]
        CLR     [DR_USED]
        CLR     [DR_ROLES]
        CLR     [DR_ROLES + 1]
        CLR     [DR_ROLES + 2]
        LDAA    1
        STAA    [DR_REROLLS]
        CLRA
        JSR     dr_roll
        LDAA    1
        JSR     dr_roll
        LDAA    2
        JSR     dr_roll
        LDAA    7
        JMP     dr_roll_show

; A = die: RANDOM, then the face rng % 6 of that die.
dr_roll:
        STAA    [DR_I]
        LDAA    [DR_RNG]
        ASLA
        BCC     dr_roll_store
        EORA    0x1d
dr_roll_store:
        STAA    [DR_RNG]
dr_roll_mod:
        CMPA    6
        BCS     dr_roll_face
        SUBA    6
        BRA     dr_roll_mod
dr_roll_face:
        STAA    [DR_VAL]
        LDAA    [DR_I]
        LDAB    6
        JSR     jr_mul8
        ADDA    [DR_VAL]
        LDX     DR_FACES
        JSR     jr_add_x_a
        LDAB    [X]
        LDX     DR_DICE
        LDAA    [DR_I]
        JSR     jr_add_x_a
        STAB    [X]
        RTS

; A = dice mask: the roll animation (six steps of four frames).
dr_roll_show:
        STAA    [DR_ROLLING]
        LDX     dr_sfx_roll
        JSR     jr_sfx_play
        LDAA    6
        STAA    [DR_FX]
dr_roll_show_step:
        LDAA    4
        JSR     jr_port_animate
        DEC     [DR_FX]
        BNE     dr_roll_show_step
        CLR     [DR_ROLLING]
        RTS

; A = effect kind: show it for its frames.
dr_effect:
        STAA    [DR_EV_KIND]
        LDX     dr_effect_frames - 1
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [DR_FX]
dr_effect_step:
        LDAA    2
        JSR     jr_port_animate
        DEC     [DR_FX]
        DEC     [DR_FX]
        BNE     dr_effect_step
        RTS

game_raw_key:
game_tick:
        RTS

game_act:
        CLR     [DR_ERROR]
        STAA    [DR_VAL]
        LDAB    [DR_SUB]
        BEQ     dr_act_battle
        JMP     dr_act_workshop
dr_act_battle:
        CMPA    JR_KEY_LEFT
        BNE     dr_act_right
        LDAA    [DR_SEL]
        ADDA    2
        BRA     dr_act_select
dr_act_right:
        CMPA    JR_KEY_RIGHT
        BNE     dr_act_up
        LDAA    [DR_SEL]
        INCA
dr_act_select:
        CMPA    3
        BCS     dr_act_select_store
        SUBA    3
dr_act_select_store:
        STAA    [DR_SEL]
        RTS
dr_act_up:
        CMPA    JR_KEY_UP
        BNE     dr_act_down
        LDAA    [DR_CHOICE]
        ADDA    3
        BRA     dr_act_role
dr_act_down:
        CMPA    JR_KEY_DOWN
        BNE     dr_act_use
        LDAA    [DR_CHOICE]
        INCA
dr_act_role:
        ANDA    3
        STAA    [DR_CHOICE]
        RTS
dr_act_use:
        CMPA    JR_KEY_CONFIRM
        BEQ     dr_use
        RTS

dr_invalid:
        LDAA    1
        STAA    [DR_ERROR]
        LDX     dr_sfx_empty
        JMP     jr_sfx_play

; USE_DIE: the selected die for the chosen role.
dr_use:
        LDX     dr_bits
        LDAA    [DR_SEL]
        JSR     jr_add_x_a
        LDAA    [X]
        BITA    [DR_USED]
        BNE     dr_invalid
        STAA    [DR_I]
        LDAB    [DR_CHOICE]
        CMPB    3
        BNE     dr_use_die
        ; REROLL: once a turn, an unused die
        TST     [DR_REROLLS]
        BEQ     dr_invalid
        DEC     [DR_REROLLS]
        LDAA    [DR_SEL]
        JSR     dr_roll
        LDX     dr_bits
        LDAA    [DR_SEL]
        JSR     jr_add_x_a
        LDAA    [X]
        JMP     dr_roll_show
dr_use_die:
        ORAA    [DR_USED]
        STAA    [DR_USED]
        LDX     DR_ROLES
        LDAA    [DR_SEL]
        JSR     jr_add_x_a
        LDAA    [DR_CHOICE]
        INCA
        STAA    [X]
        LDX     DR_DICE
        LDAA    [DR_SEL]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [DR_VAL]
        STAA    [DR_EV_VALUE]
        LDAA    [DR_CHOICE]
        BEQ     dr_attack
        CMPA    1
        BEQ     dr_guard
        ; HEAL, up to 42
        LDAA    [DR_HP]
        STAA    [DR_EV_BEFORE]
        ADDA    [DR_VAL]
        CMPA    DR_MAX_HP
        BLS     dr_heal_store
        LDAA    DR_MAX_HP
dr_heal_store:
        STAA    [DR_HP]
        STAA    [DR_EV_AFTER]
        SUBA    [DR_EV_BEFORE]
        STAA    [DR_EV_VALUE]
        LDX     dr_sfx_heal
        JSR     jr_sfx_play
        LDAA    DR_EV_HEAL
        JSR     dr_effect
        BRA     dr_used_check
dr_guard:
        LDAA    [DR_SHIELD]
        STAA    [DR_EV_BEFORE]
        ADDA    [DR_VAL]
        STAA    [DR_SHIELD]
        STAA    [DR_EV_AFTER]
        LDX     dr_sfx_guard
        JSR     jr_sfx_play
        LDAA    DR_EV_GUARD
        JSR     dr_effect
        BRA     dr_used_check
dr_attack:
        LDAA    [DR_EHP]
        STAA    [DR_EV_BEFORE]
        STAA    [DR_EV_AFTER]
        LDAA    DR_EV_ATTACK
        JSR     dr_effect
        LDAA    [DR_EHP]
        SUBA    [DR_VAL]
        BHI     dr_attack_store
        CLRA
dr_attack_store:
        STAA    [DR_EHP]
        STAA    [DR_EV_AFTER]
        LDAA    [DR_EV_BEFORE]
        SUBA    [DR_EV_AFTER]
        STAA    [DR_EV_VALUE]
        LDX     dr_sfx_hit
        JSR     jr_sfx_play
        LDAA    DR_EV_HIT
        JSR     dr_effect
        TST     [DR_EHP]
        BNE     dr_used_check
        JMP     dr_victory
dr_used_check:
        LDAA    [DR_USED]
        CMPA    7
        BEQ     dr_enemy
        ; AUTO_SELECT: the next unused die to the right
dr_auto:
        LDAA    [DR_SEL]
        INCA
        CMPA    3
        BCS     dr_auto_store
        CLRA
dr_auto_store:
        STAA    [DR_SEL]
        LDX     dr_bits
        JSR     jr_add_x_a
        LDAA    [X]
        BITA    [DR_USED]
        BNE     dr_auto
        RTS

; The enemy strikes: +2 every fourth turn, less the guard.
dr_enemy:
        LDAA    [DR_EATK]
        LDAB    [DR_TURN]
        ANDB    3
        BNE     dr_enemy_attack
        ADDA    2
dr_enemy_attack:
        STAA    [DR_ATK]
        STAA    [DR_EV_VALUE]
        SUBA    [DR_SHIELD]
        BHI     dr_enemy_damage
        CLRA
dr_enemy_damage:
        STAA    [DR_DMG]
        LDAA    DR_EV_STRIKE
        JSR     dr_effect
        TST     [DR_SHIELD]
        BEQ     dr_enemy_apply
        LDAA    [DR_ATK]
        STAA    [DR_EV_BEFORE]
        SUBA    [DR_DMG]
        STAA    [DR_EV_VALUE]
        LDAA    [DR_DMG]
        STAA    [DR_EV_AFTER]
        LDX     dr_sfx_guard
        JSR     jr_sfx_play
        LDAA    DR_EV_BLOCKED
        JSR     dr_effect
dr_enemy_apply:
        TST     [DR_DMG]
        BEQ     dr_enemy_done
        LDAA    [DR_HP]
        STAA    [DR_EV_BEFORE]
        SUBA    [DR_DMG]
        BHI     dr_enemy_hp
        CLRA
dr_enemy_hp:
        STAA    [DR_HP]
        STAA    [DR_EV_AFTER]
        LDAA    [DR_EV_BEFORE]
        SUBA    [DR_EV_AFTER]
        STAA    [DR_EV_VALUE]
        LDX     dr_sfx_damage
        JSR     jr_sfx_play
        LDAA    DR_EV_DAMAGE
        JSR     dr_effect
        TST     [DR_HP]
        BNE     dr_enemy_done
        LDAA    DR_EV_DEFEAT
        JSR     dr_effect
        LDX     dr_txt_defeat
        JMP     jr_port_lose
dr_enemy_done:
        CLR     [DR_SHIELD]
        JMP     dr_new_turn

; VICTORY: +2 HP, +3 gold, then the workshop (or the end after the king).
dr_victory:
        LDAA    DR_EV_VICTORY
        JSR     dr_effect
        LDAA    [DR_HP]
        ADDA    2
        CMPA    DR_MAX_HP
        BLS     dr_victory_hp
        LDAA    DR_MAX_HP
dr_victory_hp:
        STAA    [DR_HP]
        LDAA    [DR_COINS]
        ADDA    3
        STAA    [DR_COINS]
        LDX     dr_sfx_reward
        JSR     jr_sfx_play
        LDAA    DR_EV_REWARD
        JSR     dr_effect
        CLR     [DR_SEL]
        CLR     [DR_FACE]
        CLR     [DR_MENU]
        LDAA    [DR_BATTLE]
        CMPA    8
        BNE     dr_victory_shop
        JMP     jr_port_win
dr_victory_shop:
        LDAA    DR_SUB_WORKSHOP
        STAA    [DR_SUB]
        RTS

; The workshop: A/D die, W/S face, RETURN opens FORGE/HEAL/NEXT/BACK.
dr_act_workshop:
        CMPB    DR_SUB_WORKSHOP
        BNE     dr_act_menu
        CMPA    JR_KEY_LEFT
        BNE     dr_shop_right
        LDAA    [DR_SEL]
        ADDA    2
        JMP     dr_act_select
dr_shop_right:
        CMPA    JR_KEY_RIGHT
        BNE     dr_shop_up
        LDAA    [DR_SEL]
        INCA
        JMP     dr_act_select
dr_shop_up:
        CMPA    JR_KEY_UP
        BNE     dr_shop_down
        LDAA    [DR_FACE]
        ADDA    5
        BRA     dr_shop_face
dr_shop_down:
        CMPA    JR_KEY_DOWN
        BNE     dr_shop_open
        LDAA    [DR_FACE]
        INCA
dr_shop_face:
        CMPA    6
        BCS     dr_shop_face_store
        SUBA    6
dr_shop_face_store:
        STAA    [DR_FACE]
        RTS
dr_shop_open:
        CMPA    JR_KEY_CONFIRM
        BNE     dr_shop_done
        LDAA    DR_SUB_MENU
        STAA    [DR_SUB]
        CLR     [DR_MENU]
dr_shop_done:
        RTS

dr_act_menu:
        CMPA    JR_KEY_LEFT
        BNE     dr_menu_right
        LDAA    [DR_MENU]
        ADDA    3
        BRA     dr_menu_store
dr_menu_right:
        CMPA    JR_KEY_RIGHT
        BNE     dr_menu_back
        LDAA    [DR_MENU]
        INCA
dr_menu_store:
        ANDA    3
        STAA    [DR_MENU]
        RTS
dr_menu_back:
        CMPA    JR_KEY_BACK
        BEQ     dr_menu_close
        CMPA    JR_KEY_CONFIRM
        BNE     dr_shop_done
        LDAA    [DR_MENU]
        BEQ     dr_forge
        CMPA    1
        BEQ     dr_buy_heal
        CMPA    2
        BNE     dr_menu_close
        ; NEXT
        INC     [DR_BATTLE]
        JMP     dr_new_battle
dr_menu_close:
        LDAA    DR_SUB_WORKSHOP
        STAA    [DR_SUB]
        RTS
dr_forge:
        LDAA    [DR_COINS]
        CMPA    3
        BCS     dr_menu_invalid
        LDAA    [DR_SEL]
        LDAB    6
        JSR     jr_mul8
        ADDA    [DR_FACE]
        LDX     DR_FACES
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    9
        BCC     dr_menu_invalid
        ADDA    2
        CMPA    9
        BLS     dr_forge_store
        LDAA    9
dr_forge_store:
        STAA    [X]
        LDAA    [DR_COINS]
        SUBA    3
        STAA    [DR_COINS]
        LDX     dr_sfx_forge
        JSR     jr_sfx_play
        BRA     dr_menu_close
dr_buy_heal:
        LDAA    [DR_COINS]
        CMPA    2
        BCS     dr_menu_invalid
        LDAA    [DR_HP]
        CMPA    DR_MAX_HP
        BEQ     dr_menu_invalid
        ADDA    6
        CMPA    DR_MAX_HP
        BLS     dr_buy_heal_store
        LDAA    DR_MAX_HP
dr_buy_heal_store:
        STAA    [DR_HP]
        LDAA    [DR_COINS]
        SUBA    2
        STAA    [DR_COINS]
        LDX     dr_sfx_heal
        JSR     jr_sfx_play
        BRA     dr_menu_close
dr_menu_invalid:
        JMP     dr_invalid

; ---------------------------------------------------------------- drawing

game_draw:
        LDAA    0x20
        LDAB    DR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    [DR_SUB]
        BEQ     dr_draw_battle
        JMP     dr_draw_workshop
dr_draw_battle:
        LDX     dr_battle_lines
        JSR     jr_gfx_lines
        LDAA    DR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    28
        CLRB
        JSR     jr_gfx_at
        LDAA    [DR_BATTLE]
        INCA
        ADDA    0x30
        JSR     jr_gfx_putc
        ; the guardian's name, HP and this turn's attack
        LDAA    DR_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    2
        JSR     jr_gfx_at
        LDX     dr_enemy_names
        LDAA    [DR_BATTLE]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        LDAA    DR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    4
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [DR_EHP]
        JSR     jr_gfx_dec2
        LDAA    6
        LDAB    4
        JSR     jr_gfx_at
        LDAA    [DR_EATK]
        LDAB    [DR_TURN]
        ANDB    3
        BNE     dr_draw_next
        ADDA    2
dr_draw_next:
        JSR     jr_gfx_dec2
        ; you: HP, guard, gold
        LDAA    25
        LDAB    3
        JSR     jr_gfx_at
        LDAA    [DR_HP]
        JSR     jr_gfx_dec2
        LDAA    28
        LDAB    4
        JSR     jr_gfx_at
        LDAA    [DR_SHIELD]
        JSR     jr_gfx_dec2
        LDAA    27
        LDAB    5
        JSR     jr_gfx_at
        LDAA    [DR_COINS]
        JSR     jr_gfx_dec3
        JSR     dr_draw_figures
        ; the dice
        CLR     [DR_DI]
dr_draw_die:
        JSR     dr_draw_one_die
        INC     [DR_DI]
        LDAA    [DR_DI]
        CMPA    3
        BNE     dr_draw_die
        ; rerolls and turn
        LDAA    DR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    8
        LDAB    16
        JSR     jr_gfx_at
        LDAA    [DR_REROLLS]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDAA    27
        LDAB    16
        JSR     jr_gfx_at
        LDAA    [DR_TURN]
        JSR     jr_gfx_dec3
        JSR     dr_draw_event
        JMP     dr_draw_error

; The guardian (flashing when hit), the hero (flashing when hurt), the
; guard's shield, and the bolt, spark or strike of the current effect.
dr_draw_figures:
        LDAA    [DR_EV_KIND]
        CMPA    DR_EV_HIT
        BNE     dr_draw_enemy_colour
        LDAA    [DR_FX]
        ANDA    2
        BEQ     dr_draw_enemy_colour
        LDAA    DR_ATTR_HIT
        BRA     dr_draw_enemy_attr
dr_draw_enemy_colour:
        LDX     dr_enemy_attrs
        LDAA    [DR_BATTLE]
        JSR     jr_add_x_a
        LDAA    [X]
dr_draw_enemy_attr:
        STAA    [JR_RT_COLOR]
        TST     [DR_EHP]
        BEQ     dr_draw_hero
        LDAA    6
        LDAB    7
        JSR     jr_gfx_at
        LDAA    DR_TILE_GUARDIAN
        LDAB    [DR_BATTLE]
        CMPB    8
        BNE     dr_draw_enemy_tile
        LDAA    DR_TILE_KING
dr_draw_enemy_tile:
        JSR     jr_gfx_tile
dr_draw_hero:
        LDAA    DR_ATTR_HERO
        LDAB    [DR_EV_KIND]
        CMPB    DR_EV_DAMAGE
        BNE     dr_draw_hero_attr
        LDAB    [DR_FX]
        ANDB    2
        BEQ     dr_draw_hero_attr
        LDAA    DR_ATTR_HIT
dr_draw_hero_attr:
        STAA    [JR_RT_COLOR]
        LDAA    24
        LDAB    [DR_EV_KIND]
        CMPB    DR_EV_ATTACK
        BNE     dr_draw_hero_at
        LDAA    22                  ; the lunge
dr_draw_hero_at:
        LDAB    7
        JSR     jr_gfx_at
        LDAA    DR_TILE_HERO
        JSR     jr_gfx_tile
        TST     [DR_SHIELD]
        BEQ     dr_draw_bolt
        LDAA    DR_ATTR_SHIELD
        STAA    [JR_RT_COLOR]
        LDAA    20
        LDAB    7
        JSR     jr_gfx_at
        LDAA    DR_TILE_SHIELD
        JSR     jr_gfx_tile
dr_draw_bolt:
        TST     [DR_FX]             ; only while the effect plays
        BEQ     dr_draw_figures_done
        LDAA    [DR_EV_KIND]
        CMPA    DR_EV_ATTACK
        BEQ     dr_draw_bolt_left
        CMPA    DR_EV_STRIKE
        BEQ     dr_draw_bolt_right
        CMPA    DR_EV_HEAL
        BNE     dr_draw_figures_done
        ; the heal rises over the hero
        LDAA    DR_ATTR_BOLT
        STAA    [JR_RT_COLOR]
        LDAA    25
        LDAB    [DR_FX]
        LSRB
        ADDB    2
        JSR     jr_gfx_at
        LDAA    DR_CHAR_SPARK
        JMP     jr_gfx_putc
dr_draw_bolt_left:
        LDAA    [DR_FX]             ; 8 .. 2: from the hero to the guardian
        ASLA
        ADDA    4
        BRA     dr_draw_bolt_put
dr_draw_bolt_right:
        LDAA    [DR_FX]             ; 10 .. 2: from the guardian to the hero
        ASLA
        NEGA
        ADDA    26
dr_draw_bolt_put:
        PSHA
        LDAA    DR_ATTR_BOLT
        STAA    [JR_RT_COLOR]
        PULA
        LDAB    8
        JSR     jr_gfx_at
        LDAA    DR_CHAR_BOLT
        JMP     jr_gfx_putc
dr_draw_figures_done:
        RTS

; DR_DI = die: its box, its value (rolling while DR_ROLLING says so) and
; its role below.
dr_draw_one_die:
        LDAA    [DR_DI]
        LDAB    9
        JSR     jr_mul8
        ADDA    5
        STAA    [DR_DX]
        ; box colour: picked, spent or plain
        LDX     dr_bits
        LDAA    [DR_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [DR_DM]
        LDAB    DR_ATTR_SPENT
        BITA    [DR_USED]
        BNE     dr_draw_die_colour
        LDAB    DR_ATTR_DIE
        LDAA    [DR_DI]
        CMPA    [DR_SEL]
        BNE     dr_draw_die_colour
        LDAB    DR_ATTR_PICKED
dr_draw_die_colour:
        STAB    [JR_RT_COLOR]
        LDAA    [DR_DX]
        LDAB    11
        JSR     dr_draw_box
        ; the value
        LDAA    DR_ATTR_DIGIT
        STAA    [JR_RT_COLOR]
        LDAA    [DR_DX]
        INCA
        LDAB    12
        JSR     jr_gfx_at
        LDX     DR_DICE
        LDAA    [DR_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    [DR_DM]
        BITB    [DR_ROLLING]
        BEQ     dr_draw_die_value
        LDAA    [DR_FX]             ; a tumbling face while it rolls
        ADDA    [DR_DI]
        ADDA    [DR_DI]
        ANDA    7
        INCA
dr_draw_die_value:
        ADDA    0x30
        JSR     jr_gfx_putc
        ; the role: *ROLE once used, >ROLE on the picked die
        LDX     DR_ROLES
        LDAA    [DR_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        BEQ     dr_draw_die_pick
        DECA
        STAA    [DR_DV]
        LDAA    0x2a
        LDAB    DR_ATTR_DIM
        BRA     dr_draw_die_role
dr_draw_die_pick:
        LDAA    [DR_DI]
        CMPA    [DR_SEL]
        BNE     dr_draw_die_done
        LDAA    [DR_CHOICE]
        STAA    [DR_DV]
        LDAA    0x3e
        LDAB    DR_ATTR_PICK
dr_draw_die_role:
        STAB    [JR_RT_COLOR]
        PSHA
        LDAA    [DR_DX]
        DECA
        LDAB    14
        JSR     jr_gfx_at
        PULA
        JSR     jr_gfx_putc
        LDX     dr_role_names
        LDAA    [DR_DV]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JMP     jr_gfx_text
dr_draw_die_done:
        RTS

; A = column, B = row: a 3 x 3 die box (the centre is left for the value).
dr_draw_box:
        STAA    [DR_DY]
        STAB    [DR_DV]
        JSR     jr_gfx_at
        LDAA    DR_CHAR_BOX
        JSR     jr_gfx_putc
        LDAA    DR_CHAR_BOX + 1
        JSR     jr_gfx_putc
        LDAA    DR_CHAR_BOX + 2
        JSR     jr_gfx_putc
        LDAA    [DR_DY]
        LDAB    [DR_DV]
        INCB
        JSR     jr_gfx_at
        LDAA    DR_CHAR_BOX + 3
        JSR     jr_gfx_putc
        LDAA    0x20
        JSR     jr_gfx_putc
        LDAA    DR_CHAR_BOX + 4
        JSR     jr_gfx_putc
        LDAA    [DR_DY]
        LDAB    [DR_DV]
        ADDB    2
        JSR     jr_gfx_at
        LDAA    DR_CHAR_BOX + 5
        JSR     jr_gfx_putc
        LDAA    DR_CHAR_BOX + 6
        JSR     jr_gfx_putc
        LDAA    DR_CHAR_BOX + 7
        JMP     jr_gfx_putc

; The last effect: its name, value and BEFORE > AFTER.
dr_draw_event:
        LDAA    [DR_EV_KIND]
        BEQ     dr_draw_event_done
        LDAA    DR_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    18
        JSR     jr_gfx_at
        LDX     dr_event_names - 2
        LDAA    [DR_EV_KIND]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        LDAA    [DR_EV_KIND]
        CMPA    DR_EV_VICTORY
        BCC     dr_draw_event_done
        LDAA    DR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    0x20
        JSR     jr_gfx_putc
        LDAA    [DR_EV_VALUE]
        JSR     jr_gfx_dec2
        LDAA    [DR_EV_KIND]
        CMPA    DR_EV_STRIKE
        BEQ     dr_draw_event_done
        LDAA    0x20
        JSR     jr_gfx_putc
        JSR     jr_gfx_putc
        LDAA    [DR_EV_BEFORE]
        JSR     jr_gfx_dec2
        LDX     dr_txt_arrow
        JSR     jr_gfx_text
        LDAA    [DR_EV_AFTER]
        JMP     jr_gfx_dec2
dr_draw_event_done:
        RTS

dr_draw_error:
        TST     [DR_ERROR]
        BEQ     dr_draw_error_done
        LDAA    DR_ATTR_WARN
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    20
        JSR     jr_gfx_at
        LDX     dr_txt_refused
        JMP     jr_gfx_text
dr_draw_error_done:
        RTS

; The workshop: all 18 faces, the chosen one large, the services.
dr_draw_workshop:
        LDX     dr_workshop_lines
        JSR     jr_gfx_lines
        LDAA    DR_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    27
        CLRB
        JSR     jr_gfx_at
        LDAA    [DR_COINS]
        JSR     jr_gfx_dec3
        LDAA    26
        LDAB    1
        JSR     jr_gfx_at
        LDAA    [DR_HP]
        JSR     jr_gfx_dec2
        CLR     [DR_DI]
dr_draw_faces:
        ; DR_DI = die * 6 + face
        LDAA    [DR_DI]
        LDAB    6
        JSR     jr_divmod8          ; A = die, B = face
        STAB    [DR_DY]
        STAA    [DR_DV]
        LDAB    9
        JSR     jr_mul8
        ADDA    6
        STAA    [DR_DX]
        LDAA    DR_ATTR_TEXT
        LDAB    [DR_DV]
        CMPB    [DR_SEL]
        BNE     dr_draw_face_colour
        LDAB    [DR_DY]
        CMPB    [DR_FACE]
        BNE     dr_draw_face_colour
        ; the chosen face: a marker
        LDAA    DR_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDAA    [DR_DX]
        DECA
        LDAB    [DR_DY]
        ADDB    5
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDAA    DR_ATTR_PICK
dr_draw_face_colour:
        STAA    [JR_RT_COLOR]
        LDAA    [DR_DX]
        LDAB    [DR_DY]
        ADDB    5
        JSR     jr_gfx_at
        LDX     DR_FACES
        LDAA    [DR_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        ADDA    0x30
        JSR     jr_gfx_putc
        INC     [DR_DI]
        LDAA    [DR_DI]
        CMPA    18
        BNE     dr_draw_faces
        ; the chosen face, large
        LDAA    DR_ATTR_PICKED
        STAA    [JR_RT_COLOR]
        LDAA    14
        LDAB    13
        JSR     dr_draw_box
        LDAA    DR_ATTR_DIGIT_PICK
        STAA    [JR_RT_COLOR]
        LDAA    15
        LDAB    14
        JSR     jr_gfx_at
        LDAA    [DR_SEL]
        LDAB    6
        JSR     jr_mul8
        ADDA    [DR_FACE]
        LDX     DR_FACES
        JSR     jr_add_x_a
        LDAA    [X]
        ADDA    0x30
        JSR     jr_gfx_putc
        ; the services
        LDX     dr_service_lines
        JSR     jr_gfx_lines
        LDAA    [DR_SUB]
        CMPA    DR_SUB_MENU
        BNE     dr_draw_shop_hint
        LDAA    DR_ATTR_PICK
        STAA    [JR_RT_COLOR]
        LDX     dr_service_marks
        LDAA    [DR_MENU]
        JSR     jr_add_x_a
        LDAA    [X]
        LDAB    18
        JSR     jr_gfx_at
        LDAA    0x3e
        JSR     jr_gfx_putc
        LDX     dr_menu_hint_lines
        BRA     dr_draw_shop_lines
dr_draw_shop_hint:
        LDX     dr_shop_hint_lines
dr_draw_shop_lines:
        JSR     jr_gfx_lines
        JMP     dr_draw_error

game_draw_title:
        LDX     dr_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    DR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    DR_ATTR_DIE
        STAA    [JR_RT_COLOR]
        LDAA    8
        LDAB    3
        JSR     dr_draw_box
        LDAA    14
        LDAB    3
        JSR     dr_draw_box
        LDAA    20
        LDAB    3
        JSR     dr_draw_box
        LDX     dr_title_lines
        JSR     jr_gfx_lines
        ; three faces in the title dice
        LDAA    DR_ATTR_DIGIT_PICK
        STAA    [JR_RT_COLOR]
        LDAA    9
        LDAB    4
        JSR     jr_gfx_at
        LDAA    0x36
        JSR     jr_gfx_putc
        LDAA    15
        LDAB    4
        JSR     jr_gfx_at
        LDAA    0x39
        JSR     jr_gfx_putc
        LDAA    21
        LDAB    4
        JSR     jr_gfx_at
        LDAA    0x33
        JMP     jr_gfx_putc

game_draw_help:
        LDAA    0x20
        LDAB    DR_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     dr_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

dr_bits:
        .db     1, 2, 4
; upstream enemies.json: HP, attack
dr_enemies:
        .db     14, 3, 18, 4, 22, 4, 25, 5, 27, 5, 30, 6, 33, 6, 37, 7, 48, 8
dr_enemy_attrs:
        .db     0x46, 0x47, 0x46, 0x47, 0x47, 0x44, 0x41, 0x45, 0x43
dr_enemy_names:
        .dw     dr_enemy_0, dr_enemy_1, dr_enemy_2, dr_enemy_3, dr_enemy_4
        .dw     dr_enemy_5, dr_enemy_6, dr_enemy_7, dr_enemy_8
dr_enemy_0:
        .db     "DUST IMP", 0
dr_enemy_1:
        .db     "STONE EYE", 0
dr_enemy_2:
        .db     "BRASS IDOL", 0
dr_enemy_3:
        .db     "BONE WARD", 0
dr_enemy_4:
        .db     "SALT WITCH", 0
dr_enemy_5:
        .db     "JADE FANG", 0
dr_enemy_6:
        .db     "IRON SHADE", 0
dr_enemy_7:
        .db     "RELIC GUARD", 0
dr_enemy_8:
        .db     "THE FIRST KING", 0
; effect kind 1-10 -> frames (as tests/model.py EFFECT_FRAMES)
dr_effect_frames:
        .db     8, 12, 12, 12, 10, 12, 12, 16, 16, 16
dr_event_names:
        .dw     dr_txt_ev_attack, dr_txt_ev_attack, dr_txt_ev_guard, dr_txt_ev_heal, dr_txt_ev_strike
        .dw     dr_txt_ev_blocked, dr_txt_ev_damage, dr_txt_ev_victory, dr_txt_ev_reward, dr_txt_ev_defeat
dr_role_names:
        .dw     dr_role_attack, dr_role_guard, dr_role_heal, dr_role_reroll
dr_service_marks:
        .db     1, 10, 18, 24

dr_battle_lines:
        .db     1, 0, DR_ATTR_TITLE
        .dw     dr_txt_name
        .db     20, 0, DR_ATTR_LABEL
        .dw     dr_txt_battle
        .db     29, 0, DR_ATTR_DIM
        .dw     dr_txt_of9
        .db     1, 3, DR_ATTR_LABEL
        .dw     dr_txt_hp
        .db     1, 4, DR_ATTR_LABEL
        .dw     dr_txt_next
        .db     22, 2, DR_ATTR_TITLE
        .dw     dr_txt_you
        .db     22, 3, DR_ATTR_LABEL
        .dw     dr_txt_hp
        .db     27, 3, DR_ATTR_DIM
        .dw     dr_txt_max
        .db     22, 4, DR_ATTR_LABEL
        .dw     dr_txt_guard
        .db     22, 5, DR_ATTR_LABEL
        .dw     dr_txt_gold
        .db     1, 16, DR_ATTR_LABEL
        .dw     dr_txt_reroll
        .db     22, 16, DR_ATTR_LABEL
        .dw     dr_txt_turn
        .db     1, 21, DR_ATTR_DIM
        .dw     dr_txt_battle_keys
        .db     0xff
dr_workshop_lines:
        .db     1, 0, DR_ATTR_TITLE
        .dw     dr_txt_workshop
        .db     22, 0, DR_ATTR_LABEL
        .dw     dr_txt_gold
        .db     22, 1, DR_ATTR_LABEL
        .dw     dr_txt_hp
        .db     3, 3, DR_ATTR_LABEL
        .dw     dr_txt_die1
        .db     12, 3, DR_ATTR_LABEL
        .dw     dr_txt_die2
        .db     21, 3, DR_ATTR_LABEL
        .dw     dr_txt_die3
        .db     0xff
dr_service_lines:
        .db     2, 18, DR_ATTR_TEXT
        .dw     dr_txt_services
        .db     0xff
dr_shop_hint_lines:
        .db     1, 21, DR_ATTR_DIM
        .dw     dr_txt_shop_keys
        .db     0xff
dr_menu_hint_lines:
        .db     1, 21, DR_ATTR_DIM
        .dw     dr_txt_menu_keys
        .db     0xff
dr_title_lines:
        .db     10, 8, DR_ATTR_TITLE
        .dw     dr_txt_name
        .db     2, 10, DR_ATTR_LABEL
        .dw     dr_txt_tagline
        .db     8, 14, DR_ATTR_TEXT
        .dw     dr_txt_start
        .db     4, 16, DR_ATTR_TEXT
        .dw     dr_txt_howto
        .db     4, 22, DR_ATTR_DIM
        .dw     dr_txt_credit
        .db     0xff
dr_help_lines:
        .db     11, 1, DR_ATTR_TITLE
        .dw     dr_txt_name
        .db     1, 3, DR_ATTR_TEXT
        .dw     dr_help_1
        .db     1, 4, DR_ATTR_TEXT
        .dw     dr_help_2
        .db     1, 6, DR_ATTR_TEXT
        .dw     dr_help_3
        .db     1, 7, DR_ATTR_TEXT
        .dw     dr_help_4
        .db     1, 9, DR_ATTR_TEXT
        .dw     dr_help_5
        .db     1, 10, DR_ATTR_TEXT
        .dw     dr_help_6
        .db     1, 12, DR_ATTR_TEXT
        .dw     dr_help_7
        .db     1, 13, DR_ATTR_TEXT
        .dw     dr_help_8
        .db     1, 15, DR_ATTR_TEXT
        .dw     dr_help_9
        .db     1, 16, DR_ATTR_TEXT
        .dw     dr_help_10
        .db     1, 18, DR_ATTR_TEXT
        .dw     dr_help_11
        .db     8, 21, DR_ATTR_LABEL
        .dw     dr_help_back
        .db     0xff

dr_txt_name:
        .db     "DICE RELIC", 0
dr_txt_battle:
        .db     "BATTLE", 0
dr_txt_of9:
        .db     "/9", 0
dr_txt_hp:
        .db     "HP", 0
dr_txt_max:
        .db     "/42", 0
dr_txt_next:
        .db     "NEXT", 0
dr_txt_you:
        .db     "YOU", 0
dr_txt_guard:
        .db     "GUARD", 0
dr_txt_gold:
        .db     "GOLD", 0
dr_txt_reroll:
        .db     "REROLL", 0
dr_txt_turn:
        .db     "TURN", 0
dr_txt_battle_keys:
        .db     "A/D DIE  W/S ROLE  RETURN USE", 0
dr_txt_workshop:
        .db     "WORKSHOP", 0
dr_txt_die1:
        .db     "DIE 1", 0
dr_txt_die2:
        .db     "DIE 2", 0
dr_txt_die3:
        .db     "DIE 3", 0
dr_txt_services:
        .db     "FORGE 3G HEAL 2G NEXT  BACK", 0
dr_txt_shop_keys:
        .db     "A/D DIE W/S FACE RETURN MENU", 0
dr_txt_menu_keys:
        .db     "A/D PICK RETURN OK SPACE BACK", 0
dr_txt_arrow:
        .db     " > ", 0
dr_txt_refused:
        .db     "NOT POSSIBLE", 0
dr_txt_defeat:
        .db     "DEFEATED BY THE GUARDIAN", 0
dr_role_attack:
        .db     "ATTACK", 0
dr_role_guard:
        .db     "GUARD", 0
dr_role_heal:
        .db     "HEAL", 0
dr_role_reroll:
        .db     "REROLL", 0
dr_txt_ev_attack:
        .db     "ATTACK", 0
dr_txt_ev_guard:
        .db     "GUARD", 0
dr_txt_ev_heal:
        .db     "HEAL", 0
dr_txt_ev_strike:
        .db     "ENEMY ATTACK", 0
dr_txt_ev_blocked:
        .db     "BLOCKED", 0
dr_txt_ev_damage:
        .db     "DAMAGE", 0
dr_txt_ev_victory:
        .db     "VICTORY", 0
dr_txt_ev_reward:
        .db     "HP +2  GOLD +3", 0
dr_txt_ev_defeat:
        .db     "YOU FALL", 0
dr_txt_tagline:
        .db     "ROLL, ASSIGN, FORGE THE FACES", 0
dr_txt_start:
        .db     "RETURN : START", 0
dr_txt_howto:
        .db     "OTHER KEY : HOW TO PLAY", 0
dr_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
dr_help_1:
        .db     "A/D PICKS A DIE, W/S A ROLE,", 0
dr_help_2:
        .db     "RETURN USES IT (ONCE A TURN).", 0
dr_help_3:
        .db     "ATTACK HITS, GUARD BLOCKS THE", 0
dr_help_4:
        .db     "NEXT ATTACK, HEAL ADDS HP.", 0
dr_help_5:
        .db     "REROLL: ONE UNUSED DIE A TURN.", 0
dr_help_6:
        .db     "AFTER THE THIRD DIE IT STRIKES.", 0
dr_help_7:
        .db     "EVERY 4TH TURN IT HITS +2.", 0
dr_help_8:
        .db     "A WIN: HP +2, GOLD +3.", 0
dr_help_9:
        .db     "WORKSHOP: FORGE A FACE +2 (3G,", 0
dr_help_10:
        .db     "UP TO 9) OR HEAL 6 HP (2G).", 0
dr_help_11:
        .db     "NINE GUARDIANS. ESC: BASIC.", 0
dr_help_back:
        .db     "ANY KEY : TITLE", 0

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     dr_sfx_roll, dr_sfx_hit, dr_jingle_win, dr_jingle_lose
dr_sfx_roll:
        .db     60, 1, 90, 1, 50, 1, 80, 1, 40, 1, 70, 2, 0, 0
dr_sfx_hit:
        .db     160, 2, 200, 2, 240, 3, 0, 0
dr_sfx_guard:
        .db     110, 3, 100, 4, 0, 0
dr_sfx_heal:
        .db     60, 2, 45, 2, 34, 4, 0, 0
dr_sfx_damage:
        .db     240, 3, 250, 5, 0, 0
dr_sfx_empty:
        .db     220, 3, 0, 0
dr_sfx_forge:
        .db     30, 2, 0, 2, 30, 2, 0, 2, 25, 6, 0, 0
dr_sfx_reward:
        .db     45, 3, 36, 3, 30, 6, 0, 0

; Title: a stately march in G minor, quarter note = 16 frames, looping.
dr_title_song:
        .db     1
        .dw     dr_title_melody, dr_title_harmony, dr_title_bass
dr_title_melody:
        .db     AU_G5, 16, AU_D5, 8, AU_G5, 8, AU_AS5, 16, AU_A5, 16
        .db     AU_G5, 16, AU_FS5, 16, AU_G5, 32
        .db     AU_AS5, 16, AU_A5, 8, AU_G5, 8, AU_F5, 16, AU_DS5, 16
        .db     AU_D5, 16, AU_FS5, 16, AU_G5, 32, 0, 0
dr_title_harmony:
        .db     AU_D5, 32, AU_D5, 32, AU_C5, 32, AU_AS4, 32
        .db     AU_D5, 32, AU_C5, 32, AU_A4, 32, AU_AS4, 32, 0, 0
dr_title_bass:
        .db     AU_G2, 32, AU_G3, 32, AU_A2, 32, AU_G2, 32
        .db     AU_AS2, 32, AU_C3, 32, AU_D3, 32, AU_G2, 32, 0, 0

; Battle: a driving figure in D minor, looping.
dr_battle_song:
        .db     1
        .dw     dr_battle_melody, dr_battle_harmony, dr_battle_bass
dr_battle_melody:
        .db     AU_D5, 8, AU_F5, 8, AU_A5, 8, AU_F5, 8, AU_E5, 8, AU_G5, 8, AU_AS5, 16
        .db     AU_A5, 8, AU_G5, 8, AU_F5, 8, AU_E5, 8, AU_D5, 32, 0, 0
dr_battle_harmony:
        .db     AU_A4, 32, AU_AS4, 32, AU_A4, 32, AU_F4, 32, 0, 0
dr_battle_bass:
        .db     AU_D3, 8, AU_D3, 8, AU_A2, 8, AU_D3, 8, AU_C3, 8, AU_C3, 8, AU_G2, 16
        .db     AU_A2, 8, AU_A2, 8, AU_E3, 8, AU_A2, 8, AU_D3, 32, 0, 0

; The king falls: a G major fanfare.
dr_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     dr_win_melody, dr_win_harmony, dr_win_bass
dr_win_melody:
        .db     AU_D6, 6, AU_B5, 6, AU_D6, 6, AU_G6, 30, 0, 0
dr_win_harmony:
        .db     AU_B5, 6, AU_G5, 6, AU_B5, 6, AU_D6, 30, 0, 0
dr_win_bass:
        .db     AU_G3, 18, AU_G2, 30, 0, 0
; Defeat: a falling G minor figure.
dr_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     dr_lose_melody, dr_lose_harmony, dr_lose_bass
dr_lose_melody:
        .db     AU_G5, 12, AU_F5, 12, AU_DS5, 12, AU_D5, 30, 0, 0
dr_lose_harmony:
        .db     AU_D5, 12, AU_C5, 12, AU_AS4, 12, AU_A4, 30, 0, 0
dr_lose_bass:
        .db     AU_G3, 36, AU_G2, 30, 0, 0

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
