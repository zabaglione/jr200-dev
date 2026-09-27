; SPDX-License-Identifier: MIT
; SIGIL DECK for JR-200: a port of jr100dev games/sigil_deck 1.6.1.
; Ten battles with a growing deck: four cards a turn, three energy, the 24
; cards' attack, shield and specials (heal, energy, poison, draw, thorns,
; vulnerable, echo, retain, strength, weak, the finisher), the enemy's
; intent cycle, poison before its action, defeat before victory, the
; reward of three different cards or REST, the eight enemies and the draw
; and reward PRNG follow upstream src/main.asm and src/cards.asm (see
; tests/model.py). Display, colour and three-voice sound use the JR-200
; port SDK.
        .filename.jr "SIGIL-DECK"
        .include "../../../sdk/jr200.inc"

; The code needs more than 8KB: the work area starts at $4000.
JR_SHADOW:          .equ    0x4000
JR_SAVE:            .equ    0x4600
JR_RT:              .equ    0x5600
GAME_STATE:         .equ    0x5640
GAME_STATE_END:     .equ    0x5700
JR_AUDIO:           .equ    0x5700
JR_STACK_TOP:       .equ    0x5fff

GAME_LEVELS:        .equ    1
GAME_RATE:          .equ    0
GAME_SPACE_RESET:   .equ    0       ; SPACE selects END TURN, as upstream
GAME_STATUS_ROW:    .equ    23
GAME_STATUS_ATTR:   .equ    0x06
GAME_RENDER_FRAMES: .equ    4

; Upstream state (same order as tests/model.py LAYOUT).
SD_SUB:             .equ    GAME_STATE          ; 0 battle, 1 reward, 2 deck view
SD_SEL:             .equ    GAME_STATE + 1
SD_BATTLE:          .equ    GAME_STATE + 2
SD_HP:              .equ    GAME_STATE + 3
SD_SHIELD:          .equ    GAME_STATE + 4
SD_ENERGY:          .equ    GAME_STATE + 5
SD_TURN:            .equ    GAME_STATE + 6
SD_ENEMY:           .equ    GAME_STATE + 7
SD_EHP:             .equ    GAME_STATE + 8
SD_ESHIELD:         .equ    GAME_STATE + 9
SD_EATK:            .equ    GAME_STATE + 10
SD_EGUARD:          .equ    GAME_STATE + 11
SD_INTENT:          .equ    GAME_STATE + 12     ; 0 attack, 1 shield, 2 heavy
SD_POISON:          .equ    GAME_STATE + 13
SD_WEAK:            .equ    GAME_STATE + 14
SD_VULN:            .equ    GAME_STATE + 15
SD_STR:             .equ    GAME_STATE + 16
SD_THORNS:          .equ    GAME_STATE + 17
SD_ECHO:            .equ    GAME_STATE + 18
SD_RETAIN:          .equ    GAME_STATE + 19
SD_DECKN:           .equ    GAME_STATE + 20
SD_DRAWN:           .equ    GAME_STATE + 21
SD_DISCN:           .equ    GAME_STATE + 22
SD_EXHN:            .equ    GAME_STATE + 23
SD_RNG:             .equ    GAME_STATE + 24
SD_SEED:            .equ    GAME_STATE + 25
SD_PLAYED:          .equ    GAME_STATE + 26
SD_REWARDS:         .equ    GAME_STATE + 27
SD_HAND:            .equ    GAME_STATE + 30
SD_DECK:            .equ    GAME_STATE + 34
SD_DRAW:            .equ    GAME_STATE + 58
SD_DISC:            .equ    GAME_STATE + 82
SD_EXH:             .equ    GAME_STATE + 106
; Rule work bytes.
SD_CARD:            .equ    GAME_STATE + 130
SD_CPTR:            .equ    GAME_STATE + 131    ; 2 bytes: the card's stats
SD_DMG:             .equ    GAME_STATE + 133
SD_I:               .equ    GAME_STATE + 134
SD_SLOT:            .equ    GAME_STATE + 135
SD_MORE:            .equ    GAME_STATE + 136
SD_T:               .equ    GAME_STATE + 137
SD_PTR2:            .equ    GAME_STATE + 138    ; 2 bytes
; Effect bytes (set by the rules, read by game_draw).
SD_FX:              .equ    GAME_STATE + 140
SD_FXSLOT:          .equ    GAME_STATE + 141
; Drawing work bytes.
SD_DI:              .equ    GAME_STATE + 144
SD_DX:              .equ    GAME_STATE + 145
SD_DY:              .equ    GAME_STATE + 146
SD_DPTR:            .equ    GAME_STATE + 147    ; 2 bytes
SD_DCARD:           .equ    GAME_STATE + 149
SD_DCPTR:           .equ    GAME_STATE + 150    ; 2 bytes
SD_DV:              .equ    GAME_STATE + 152
SD_DATTR:           .equ    GAME_STATE + 153
SD_DN:              .equ    GAME_STATE + 154
SD_DFULL:           .equ    GAME_STATE + 155    ; draw cards as playable

SD_REWARD:          .equ    1
SD_DECK_VIEW:       .equ    2
SD_EMPTY:           .equ    255
SD_MAX_HP:          .equ    60
SD_SCENE_FRAMES:    .equ    16      ; upstream SIGIL_SCENE: one card effect

SD_FX_HIT:          .equ    1       ; the enemy takes damage
SD_FX_GUARD:        .equ    2       ; the player's shield grows
SD_FX_HEAL:         .equ    3
SD_FX_POISON:       .equ    4       ; poison bites the enemy
SD_FX_ENEMY:        .equ    5       ; the enemy acts
SD_FX_DRAW:         .equ    6       ; a card lands in slot SD_FXSLOT

SD_QUAD:            .equ    0x80
SD_ICON_SWORD:      .equ    0x90
SD_ICON_SHIELD:     .equ    0x91
SD_ICON_SIGIL:      .equ    0x92
SD_ICON_HEART:      .equ    0x93
SD_ICON_BOLT:       .equ    0x94
SD_ICON_DROP:       .equ    0x95
SD_EDGE_H:          .equ    0x96
SD_EDGE_V:          .equ    0x97
SD_CORNER_TL:       .equ    0x98
SD_CORNER_TR:       .equ    0x99
SD_CORNER_BL:       .equ    0x9a
SD_CORNER_BR:       .equ    0x9b
SD_ARROW_DOWN:      .equ    0x9c
SD_ARROW_RIGHT:     .equ    0x9d
SD_ICON_SPARK:      .equ    0x9e
SD_ICON_CROSS:      .equ    0x9f
SD_SLASH:           .equ    0x00    ; second PCG bank: two slash frames
SD_STAR:            .equ    0x02
SD_DIAMOND:         .equ    0x03

SD_ATTR_TEXT:       .equ    0x07
SD_ATTR_LABEL:      .equ    0x05
SD_ATTR_TITLE:      .equ    0x06
SD_ATTR_DIM:        .equ    0x01
SD_ATTR_HP:         .equ    0x04
SD_ATTR_HURT:       .equ    0x02
SD_ATTR_SHIELD:     .equ    0x05
SD_ATTR_ENERGY:     .equ    0x06
SD_ATTR_POISON:     .equ    0x03
SD_ATTR_PICK:       .equ    0x46
SD_ATTR_FRAME:      .equ    0x43

        .org    0x1000
start:
        JSR     jr_session_enter
        JSR     jr_audio_init
        JSR     jr_font_install
        LDX     sd_patterns
        LDAA    SD_QUAD
        LDAB    32
        JSR     jr_pcg_load
        LDX     sd_patterns_low
        LDAA    SD_SLASH
        LDAB    4
        JSR     jr_pcg_load
        JMP     jr_port_run

; ---------------------------------------------------------------- rules

; NEW_RUN: HP 60, the eight-card deck; the seed is the music's position.
game_init:
        LDAA    [JR_AU_VOICE + 1]
        EORA    [JR_AU_VOICE + 2]
        ORAA    1
        STAA    [SD_SEED]
        STAA    [SD_RNG]
        LDAA    SD_MAX_HP
        STAA    [SD_HP]
        LDAA    8
        STAA    [SD_DECKN]
        LDX     sd_initial_deck
        STX     [JR_RT_SRC]
        LDX     SD_DECK
        STX     [JR_RT_DST]
        LDX     8
        STX     [JR_RT_COUNT]
        JSR     jr_copy
        ; fall through

; START_BATTLE: fresh statuses, the deck as the draw pile, the enemy, a hand.
sd_start_battle:
        LDX     sd_battle_song
        JSR     jr_music_play
        CLR     [SD_SHIELD]
        CLR     [SD_ESHIELD]
        LDX     SD_POISON
sd_start_clear:
        CLR     [X]
        INX
        CPX     SD_DECKN
        BNE     sd_start_clear
        CLR     [SD_DISCN]
        CLR     [SD_EXHN]
        CLR     [SD_SEL]
        CLR     [SD_TURN]
        CLR     [SD_SUB]
        LDAA    [SD_DECKN]
        STAA    [SD_DRAWN]
        LDX     SD_DECK
        STX     [JR_RT_SRC]
        LDX     SD_DRAW
        STX     [JR_RT_DST]
        LDX     [SD_DECKN - 1]      ; high byte: SD_RETAIN, cleared above
        STX     [JR_RT_COUNT]
        JSR     jr_copy
        LDX     sd_battle_order
        LDAA    [SD_BATTLE]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [SD_ENEMY]
        ANDA    1
        STAA    [SD_INTENT]
        LDAA    [SD_ENEMY]
        TAB
        ASLA
        STAA    [SD_T]
        ADDB    [SD_T]
        TBA
        LDX     sd_enemies
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [SD_EHP]
        LDAA    [X + 1]
        STAA    [SD_EATK]
        LDAA    [X + 2]
        STAA    [SD_EGUARD]
        LDAA    SD_EMPTY
        STAA    [SD_HAND]
        STAA    [SD_HAND + 1]
        STAA    [SD_HAND + 2]
        STAA    [SD_HAND + 3]
        ; fall through

; PLAYER_TURN: shield gone unless retained, energy 3, draw up to four.
sd_player_turn:
        TST     [SD_RETAIN]
        BNE     sd_player_retains
        CLR     [SD_SHIELD]
sd_player_retains:
        CLR     [SD_RETAIN]
        CLR     [SD_THORNS]
        LDAA    3
        STAA    [SD_ENERGY]
        LDAA    4
        JSR     sd_draw_hand
        LDAA    [SD_TURN]
        CMPA    255
        BEQ     sd_player_turn_done
        INC     [SD_TURN]
sd_player_turn_done:
game_raw_key:
game_tick:
        RTS

sd_next_random:
        LDAA    [SD_RNG]
        ASLA
        BCC     sd_random_store
        EORA    0x1d
sd_random_store:
        STAA    [SD_RNG]
        RTS

; A = card -> X = its six stats. Uses no memory (game_draw calls it too).
sd_card_stats:
        TAB
        ASLA
        ABA
        ASLA
        LDX     sd_cards
        JMP     jr_add_x_a

; DRAW_ONE: A = a card from the draw pile (the discards reshuffled when it is
; empty) or SD_EMPTY. The pile's last card fills the taken slot.
sd_draw_one:
        TST     [SD_DRAWN]
        BNE     sd_draw_pick
        LDAA    [SD_DISCN]
        BEQ     sd_draw_none
        STAA    [SD_DRAWN]
        CLR     [SD_DISCN]
        LDX     SD_DISC
        STX     [JR_RT_SRC]
        LDX     SD_DRAW
        STX     [JR_RT_DST]
        LDAB    [SD_DRAWN]
        CLRA
        STAA    [SD_PTR2]
        STAB    [SD_PTR2 + 1]
        LDX     [SD_PTR2]
        STX     [JR_RT_COUNT]
        JSR     jr_copy
sd_draw_pick:
        JSR     sd_next_random
sd_draw_mod:
        CMPA    [SD_DRAWN]
        BCS     sd_draw_take
        SUBA    [SD_DRAWN]
        BRA     sd_draw_mod
sd_draw_take:
        LDX     SD_DRAW
        JSR     jr_add_x_a
        LDAB    [X]
        PSHB
        STX     [SD_PTR2]
        DEC     [SD_DRAWN]
        LDX     SD_DRAW
        LDAA    [SD_DRAWN]
        JSR     jr_add_x_a
        LDAA    [X]
        LDX     [SD_PTR2]
        STAA    [X]
        PULA
        RTS
sd_draw_none:
        LDAA    SD_EMPTY
        RTS

; DRAW_HAND: A = cards to draw into the empty slots, in slot order. After
; the first turn each card is shown landing.
sd_draw_hand:
        STAA    [SD_MORE]
        CLR     [SD_SLOT]
sd_draw_hand_slot:
        LDX     SD_HAND
        LDAA    [SD_SLOT]
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    SD_EMPTY
        BNE     sd_draw_hand_next
        JSR     sd_draw_one
        LDX     SD_HAND
        PSHA
        LDAA    [SD_SLOT]
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        CMPA    SD_EMPTY
        BEQ     sd_draw_hand_done
        TST     [SD_TURN]
        BEQ     sd_draw_hand_count
        LDAA    [SD_SLOT]
        STAA    [SD_FXSLOT]
        LDAA    SD_FX_DRAW
        JSR     sd_scene
sd_draw_hand_count:
        DEC     [SD_MORE]
        BEQ     sd_draw_hand_done
sd_draw_hand_next:
        INC     [SD_SLOT]
        LDAA    [SD_SLOT]
        CMPA    4
        BCS     sd_draw_hand_slot
sd_draw_hand_done:
        RTS

; A = effect: one visible step (upstream SIGIL_SCENE).
sd_scene:
        STAA    [SD_FX]
        LDAA    SD_SCENE_FRAMES
        JSR     jr_port_animate
        CLR     [SD_FX]
        RTS

; A = card -> the end of the discard pile.
sd_discard:
        LDX     SD_DISC
        PSHA
        LDAA    [SD_DISCN]
        JSR     jr_add_x_a
        PULA
        STAA    [X]
        INC     [SD_DISCN]
        RTS

; A = HP to heal, up to 60.
sd_heal:
        ADDA    [SD_HP]
        CMPA    SD_MAX_HP
        BCS     sd_heal_store
        LDAA    SD_MAX_HP
sd_heal_store:
        STAA    [SD_HP]
        RTS

; HURT_ENEMY: SD_DMG against the enemy's shield, the rest to its HP.
sd_hurt_enemy:
        LDAA    [SD_DMG]
        CMPA    [SD_ESHIELD]
        BHI     sd_hurt_through
        LDAA    [SD_ESHIELD]
        SUBA    [SD_DMG]
        STAA    [SD_ESHIELD]
        RTS
sd_hurt_through:
        SUBA    [SD_ESHIELD]
        STAA    [SD_DMG]
        CLR     [SD_ESHIELD]
        LDAA    [SD_EHP]
        SUBA    [SD_DMG]
        BCC     sd_hurt_store
        CLRA
sd_hurt_store:
        STAA    [SD_EHP]
        RTS

game_act:
        LDAB    [SD_SUB]
        BEQ     sd_act_battle
        CMPB    SD_DECK_VIEW
        BNE     sd_act_reward
        CLR     [SD_SUB]            ; any key leaves the deck view
        RTS
sd_act_reward:
        CMPA    JR_KEY_LEFT
        BNE     sd_reward_right
        DEC     [SD_SEL]
        BPL     sd_act_move
        LDAA    3
        STAA    [SD_SEL]
        BRA     sd_act_move
sd_reward_right:
        CMPA    JR_KEY_RIGHT
        BNE     sd_reward_take
        INC     [SD_SEL]
        LDAA    [SD_SEL]
        CMPA    4
        BCS     sd_act_move
        CLR     [SD_SEL]
        BRA     sd_act_move
sd_reward_take:
        CMPA    JR_KEY_CONFIRM
        BNE     sd_act_done
        LDAA    [SD_SEL]
        CMPA    3
        BNE     sd_reward_card
        LDAA    10                  ; REST
        JSR     sd_heal
        BRA     sd_reward_next
sd_reward_card:
        LDX     SD_REWARDS
        JSR     jr_add_x_a
        LDAB    [X]
        LDX     SD_DECK
        LDAA    [SD_DECKN]
        JSR     jr_add_x_a
        STAB    [X]
        INC     [SD_DECKN]
sd_reward_next:
        LDAA    4
        JSR     sd_heal
        INC     [SD_BATTLE]
        JMP     sd_start_battle

sd_act_battle:
        CMPA    JR_KEY_LEFT
        BNE     sd_battle_right
        DEC     [SD_SEL]
        BPL     sd_act_move
        LDAA    4
        STAA    [SD_SEL]
        BRA     sd_act_move
sd_battle_right:
        CMPA    JR_KEY_RIGHT
        BNE     sd_battle_end
        INC     [SD_SEL]
        LDAA    [SD_SEL]
        CMPA    5
        BCS     sd_act_move
        CLR     [SD_SEL]
        BRA     sd_act_move
sd_battle_end:
        CMPA    JR_KEY_BACK
        BNE     sd_battle_deck
        LDAA    4
        STAA    [SD_SEL]
sd_act_move:
        LDX     sd_sfx_menu
        JMP     jr_sfx_play
sd_battle_deck:
        CMPA    JR_KEY_UP
        BNE     sd_battle_use
        LDAA    SD_DECK_VIEW
        STAA    [SD_SUB]
        BRA     sd_act_move
sd_battle_use:
        CMPA    JR_KEY_CONFIRM
        BNE     sd_act_done
        LDAA    [SD_SEL]
        CMPA    4
        BNE     sd_play_card
        JMP     sd_enemy_turn
sd_act_done:
        RTS

; PLAY_CARD: the selected card if it is there and affordable.
sd_play_card:
        LDX     SD_HAND
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    SD_EMPTY
        BEQ     sd_cannot_play
        STAA    [SD_CARD]
        JSR     sd_card_stats
        STX     [SD_CPTR]
        LDAA    [SD_ENERGY]
        CMPA    [X]
        BCC     sd_play_pay
sd_cannot_play:
        LDX     sd_sfx_empty
        JMP     jr_sfx_play
sd_play_pay:
        SUBA    [X]
        STAA    [SD_ENERGY]
        LDAA    [SD_PLAYED]
        CMPA    255
        BEQ     sd_play_remove
        INC     [SD_PLAYED]
sd_play_remove:
        LDX     SD_HAND
        LDAA    [SD_SEL]
        JSR     jr_add_x_a
        LDAA    SD_EMPTY
        STAA    [X]
        ; attack: strength, the finisher, echo, then vulnerable
        LDX     [SD_CPTR]
        LDAA    [X + 1]
        BEQ     sd_play_block
        ADDA    [SD_STR]
        STAA    [SD_DMG]
        LDAA    [X + 3]
        CMPA    12
        BNE     sd_play_echo
        LDAA    [SD_EHP]
        CMPA    12
        BHI     sd_play_echo
        LDAA    [SD_DMG]
        ADDA    12
        STAA    [SD_DMG]
sd_play_echo:
        TST     [SD_ECHO]
        BEQ     sd_play_vuln
        ASL     [SD_DMG]
        CLR     [SD_ECHO]
sd_play_vuln:
        TST     [SD_VULN]
        BEQ     sd_play_hit
        LDAA    [SD_DMG]
        LSRA
        ADDA    [SD_DMG]
        STAA    [SD_DMG]
sd_play_hit:
        JSR     sd_hurt_enemy
        LDX     sd_sfx_shot
        JSR     jr_sfx_play
        LDAA    SD_FX_HIT
        JSR     sd_scene
sd_play_block:
        LDX     [SD_CPTR]
        LDAA    [X + 2]
        BEQ     sd_play_special
        ADDA    [SD_SHIELD]
        CMPA    99
        BCS     sd_play_shield
        LDAA    99
sd_play_shield:
        STAA    [SD_SHIELD]
        LDX     sd_sfx_shield
        JSR     jr_sfx_play
        LDAA    SD_FX_GUARD
        JSR     sd_scene
sd_play_special:
        LDX     [SD_CPTR]
        LDAB    [X + 4]             ; value
        LDAA    [X + 3]
        BNE     sd_play_done_near568
        JMP     sd_play_done
sd_play_done_near568:
        CMPA    1
        BNE     sd_play_energy
        TBA
        JSR     sd_heal
        LDX     sd_sfx_heal
        JSR     jr_sfx_play
        LDAA    SD_FX_HEAL
        JSR     sd_scene
        JMP     sd_play_done
sd_play_energy:
        CMPA    2
        BNE     sd_play_poison
        ADDB    [SD_ENERGY]
        CMPB    9
        BCS     sd_play_energy_store
        LDAB    9
sd_play_energy_store:
        STAB    [SD_ENERGY]
        BRA     sd_play_done
sd_play_poison:
        CMPA    3
        BNE     sd_play_haste
        ADDB    [SD_POISON]
        CMPB    99
        BCS     sd_play_poison_store
        LDAB    99
sd_play_poison_store:
        STAB    [SD_POISON]
        LDX     sd_sfx_poison
        JSR     jr_sfx_play
        BRA     sd_play_done
sd_play_haste:
        CMPA    4
        BNE     sd_play_thorn
        INC     [SD_ENERGY]
        LDAA    1
        JSR     sd_draw_hand
        BRA     sd_play_done
sd_play_thorn:
        CMPA    5
        BNE     sd_play_vulnerable
        ADDB    [SD_THORNS]
        STAB    [SD_THORNS]
        BRA     sd_play_done
sd_play_vulnerable:
        CMPA    6
        BNE     sd_play_double
        LDAA    2
        STAA    [SD_VULN]
        BRA     sd_play_done
sd_play_double:
        CMPA    7
        BNE     sd_play_retain
        LDAA    1
        STAA    [SD_ECHO]
        BRA     sd_play_done
sd_play_retain:
        CMPA    8
        BNE     sd_play_strength
        LDAA    1
        STAA    [SD_RETAIN]
        BRA     sd_play_done
sd_play_strength:
        CMPA    9
        BNE     sd_play_weak
        ADDB    [SD_STR]
        CMPB    20
        BCS     sd_play_strength_store
        LDAB    20
sd_play_strength_store:
        STAB    [SD_STR]
        BRA     sd_play_done
sd_play_weak:
        CMPA    10
        BNE     sd_play_draw
        LDAA    2
        STAA    [SD_WEAK]
        BRA     sd_play_done
sd_play_draw:
        CMPA    11
        BNE     sd_play_done
        TBA
        JSR     sd_draw_hand
sd_play_done:
        ; the card goes to the discards, or out of this battle
        LDX     [SD_CPTR]
        LDAA    [SD_CARD]
        TST     [X + 5]
        BNE     sd_play_exhaust
        JSR     sd_discard
        JMP     sd_check
sd_play_exhaust:
        LDX     SD_EXH
        LDAA    [SD_EXHN]
        JSR     jr_add_x_a
        LDAA    [SD_CARD]
        STAA    [X]
        INC     [SD_EXHN]
        JMP     sd_check

; ENEMY_TURN: the hand discarded, poison, the intent, thorns, statuses down.
sd_enemy_turn:
        CLR     [SD_SLOT]
sd_enemy_discard:
        LDX     SD_HAND
        LDAA    [SD_SLOT]
        JSR     jr_add_x_a
        LDAA    [X]
        CMPA    SD_EMPTY
        BEQ     sd_enemy_discard_next
        LDAB    SD_EMPTY
        STAB    [X]
        JSR     sd_discard
sd_enemy_discard_next:
        INC     [SD_SLOT]
        LDAA    [SD_SLOT]
        CMPA    4
        BCS     sd_enemy_discard
        CLR     [SD_ESHIELD]
        TST     [SD_POISON]
        BEQ     sd_enemy_intent
        LDAA    [SD_EHP]
        SUBA    [SD_POISON]
        BCC     sd_enemy_poisoned
        CLRA
sd_enemy_poisoned:
        STAA    [SD_EHP]
        DEC     [SD_POISON]
        LDX     sd_sfx_poison
        JSR     jr_sfx_play
        LDAA    SD_FX_POISON
        JSR     sd_scene
        JSR     sd_check
        BEQ     sd_enemy_intent
        RTS
sd_enemy_intent:
        LDAA    [SD_INTENT]
        CMPA    1
        BEQ     sd_enemy_block
        LDAA    [SD_EATK]
        TST     [SD_INTENT]
        BEQ     sd_enemy_weaken
        ADDA    2
sd_enemy_weaken:
        TST     [SD_WEAK]
        BEQ     sd_enemy_damage
        SUBA    3
        BCC     sd_enemy_damage
        CLRA
sd_enemy_damage:
        STAA    [SD_DMG]
        CMPA    [SD_SHIELD]
        BHI     sd_enemy_through
        LDAA    [SD_SHIELD]
        SUBA    [SD_DMG]
        STAA    [SD_SHIELD]
        BRA     sd_enemy_thorns
sd_enemy_through:
        SUBA    [SD_SHIELD]
        STAA    [SD_DMG]
        CLR     [SD_SHIELD]
        LDAA    [SD_HP]
        SUBA    [SD_DMG]
        BCC     sd_enemy_hp
        CLRA
sd_enemy_hp:
        STAA    [SD_HP]
        LDX     sd_sfx_hit
        JSR     jr_sfx_play
sd_enemy_thorns:
        LDAA    [SD_THORNS]
        STAA    [SD_DMG]
        JSR     sd_hurt_enemy
        BRA     sd_enemy_finish
sd_enemy_block:
        LDAA    [SD_EGUARD]
        STAA    [SD_ESHIELD]
        LDX     sd_sfx_shield
        JSR     jr_sfx_play
sd_enemy_finish:
        TST     [SD_WEAK]
        BEQ     sd_enemy_vuln
        DEC     [SD_WEAK]
sd_enemy_vuln:
        TST     [SD_VULN]
        BEQ     sd_enemy_next
        DEC     [SD_VULN]
sd_enemy_next:
        LDAA    SD_FX_ENEMY
        JSR     sd_scene
        INC     [SD_INTENT]
        LDAA    [SD_INTENT]
        CMPA    3
        BCS     sd_enemy_checked
        CLR     [SD_INTENT]
sd_enemy_checked:
        JSR     sd_check
        BNE     sd_enemy_done
        JMP     sd_player_turn
sd_enemy_done:
        RTS

; CHECK_VICTORY: defeat first; the enemy's defeat gives the reward, or the
; run's victory after the tenth battle. Z clear when the battle ended.
sd_check:
        TST     [SD_HP]
        BNE     sd_check_enemy
        LDX     sd_txt_failed
        JSR     jr_port_lose
        LDAA    1
        RTS
sd_check_enemy:
        TST     [SD_EHP]
        BEQ     sd_check_won
        CLRA
        RTS
sd_check_won:
        CLR     [SD_SEL]
        LDAA    [SD_BATTLE]
        CMPA    9
        BNE     sd_check_reward
        JSR     jr_port_win
        LDAA    1
        RTS
sd_check_reward:
        LDAA    SD_REWARD
        STAA    [SD_SUB]
        LDAA    2
        JSR     jr_port_sound
        JSR     sd_random_card
        STAA    [SD_REWARDS]
sd_check_second:
        JSR     sd_random_card
        CMPA    [SD_REWARDS]
        BEQ     sd_check_second
        STAA    [SD_REWARDS + 1]
sd_check_third:
        JSR     sd_random_card
        CMPA    [SD_REWARDS]
        BEQ     sd_check_third
        CMPA    [SD_REWARDS + 1]
        BEQ     sd_check_third
        STAA    [SD_REWARDS + 2]
        LDAA    1
        RTS

sd_random_card:
        JSR     sd_next_random
sd_random_mod:
        CMPA    24
        BCS     sd_random_done
        SUBA    24
        BRA     sd_random_mod
sd_random_done:
        RTS

; ---------------------------------------------------------------- drawing

; A = value at column SD_DX, row SD_DY in colour B (two digits).
sd_num2:
        STAB    [JR_RT_COLOR]
        PSHA
        LDAA    [SD_DX]
        LDAB    [SD_DY]
        JSR     jr_gfx_at
        PULA
        JMP     jr_gfx_dec2

; X = entry table (.db column, row, colour, state offset), 0xff ends:
; two-digit numbers from the state.
sd_numbers:
        STX     [SD_DPTR]
sd_numbers_next:
        LDX     [SD_DPTR]
        LDAA    [X]
        CMPA    0xff
        BEQ     sd_numbers_done
        STAA    [SD_DX]
        LDAA    [X + 1]
        STAA    [SD_DY]
        LDAB    [X + 2]
        LDAA    [X + 3]
        LDX     GAME_STATE
        JSR     jr_add_x_a
        LDAA    [X]
        JSR     sd_num2
        LDX     [SD_DPTR]
        INX
        INX
        INX
        INX
        STX     [SD_DPTR]
        BRA     sd_numbers_next
sd_numbers_done:
        RTS

; A = code, B = attribute at SD_DX / SD_DY; SD_DX moves on.
sd_put:
        PSHA
        STAB    [JR_RT_COLOR]
        LDAA    [SD_DX]
        LDAB    [SD_DY]
        JSR     jr_gfx_at
        PULA
        JSR     jr_gfx_putc
        INC     [SD_DX]
        RTS

game_draw:
        LDAA    0x20
        LDAB    SD_ATTR_TEXT
        JSR     jr_gfx_fill
        LDAA    [JR_PORT_MODE]
        CMPA    JR_MODE_LOST
        BNE     sd_draw_won
        JSR     sd_draw_ornament
        LDX     sd_death_lines
        JMP     jr_gfx_lines
sd_draw_won:
        CMPA    JR_MODE_CLEAR
        BCS     sd_draw_scene
        JSR     sd_draw_ornament
        LDX     sd_win_lines
        JSR     jr_gfx_lines
        LDAA    SD_ATTR_TITLE
        STAA    [JR_RT_COLOR]
        LDAA    22
        LDAB    11
        JSR     jr_gfx_at
        LDAA    [SD_PLAYED]
        JSR     jr_gfx_dec3
        LDAA    23
        LDAB    14
        JSR     jr_gfx_at
        LDAA    [SD_HP]
        JMP     jr_gfx_dec2
sd_draw_scene:
        LDAA    [SD_SUB]
        CMPA    SD_REWARD
        BNE     sd_draw_scene_deck
        JMP     sd_draw_reward
sd_draw_scene_deck:
        CMPA    SD_DECK_VIEW
        BNE     sd_draw_battle
        JMP     sd_draw_deck

sd_draw_battle:
        LDX     sd_hud_lines
        JSR     jr_gfx_lines
        LDX     sd_hud_numbers
        JSR     sd_numbers
        ; the battle number, and HP / shield coloured by the effect
        LDAA    2
        STAA    [SD_DX]
        LDAA    1
        STAA    [SD_DY]
        LDAA    [SD_BATTLE]
        INCA
        LDAB    SD_ATTR_TEXT
        JSR     sd_num2
        LDAA    3
        STAA    [SD_DX]
        CLR     [SD_DY]
        LDAB    SD_ATTR_HP
        LDAA    [SD_FX]
        CMPA    SD_FX_HEAL
        BEQ     sd_draw_hp
        CMPA    SD_FX_ENEMY
        BNE     sd_draw_hp_plain
        LDAA    [SD_INTENT]
        CMPA    1
        BEQ     sd_draw_hp_plain
        LDAB    SD_ATTR_HURT
        BRA     sd_draw_hp
sd_draw_hp_plain:
        LDAB    SD_ATTR_HP
sd_draw_hp:
        LDAA    [SD_HP]
        JSR     sd_num2
        LDAA    13
        STAA    [SD_DX]
        LDAB    SD_ATTR_SHIELD
        LDAA    [SD_FX]
        CMPA    SD_FX_GUARD
        BNE     sd_draw_shield
        LDAB    SD_ATTR_TEXT
sd_draw_shield:
        LDAA    [SD_SHIELD]
        JSR     sd_num2
        ; the effect's icon beside HP or shield
        LDAA    [SD_FX]
        CMPA    SD_FX_HEAL
        BNE     sd_draw_fx_guard
        LDAA    6
        STAA    [SD_DX]
        LDAA    SD_ICON_CROSS
        LDAB    0x44
        JSR     sd_put
sd_draw_fx_guard:
        LDAA    [SD_FX]
        CMPA    SD_FX_GUARD
        BNE     sd_draw_enemy
        LDAA    16
        STAA    [SD_DX]
        LDAA    SD_ICON_SHIELD
        LDAB    0x45
        JSR     sd_put
sd_draw_enemy:
        ; name and figure in the enemy's colour
        LDX     sd_enemy_colours
        LDAA    [SD_ENEMY]
        JSR     jr_add_x_a
        LDAB    [X]
        LDAA    [SD_FX]
        CMPA    SD_FX_HIT
        BNE     sd_draw_enemy_poison
        LDAB    0x42
sd_draw_enemy_poison:
        CMPA    SD_FX_POISON
        BNE     sd_draw_enemy_colour
        LDAB    0x43
sd_draw_enemy_colour:
        STAB    [SD_DATTR]
        ANDB    7
        STAB    [JR_RT_COLOR]
        LDAA    9
        LDAB    2
        JSR     jr_gfx_at
        LDX     sd_enemy_names
        LDAA    [SD_ENEMY]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        LDAA    [SD_DATTR]
        STAA    [JR_RT_COLOR]
        LDX     sd_monsters
        LDAA    [SD_ENEMY]
        ASLA
        ASLA
        ASLA
        ASLA
        ASLA
        ASLA
        JSR     jr_add_x_a
        STX     [SD_DPTR]
        LDAA    3
        STAA    [SD_DY]
sd_draw_monster_row:
        LDAA    12
        LDAB    [SD_DY]
        JSR     jr_gfx_at
        LDAB    8
sd_draw_monster_cell:
        LDX     [SD_DPTR]
        LDAA    [X]
        INX
        STX     [SD_DPTR]
        JSR     jr_gfx_putc
        DECB
        BNE     sd_draw_monster_cell
        INC     [SD_DY]
        LDAA    [SD_DY]
        CMPA    11
        BNE     sd_draw_monster_row
        ; a slash over the enemy while it is hit
        LDAA    [SD_FX]
        CMPA    SD_FX_HIT
        BNE     sd_draw_intent
        LDAA    0x47
        STAA    [JR_RT_COLOR]
        LDAA    14
        STAA    [SD_DX]
        LDAA    5
        STAA    [SD_DY]
sd_draw_slash:
        LDAA    [SD_DX]
        LDAB    [SD_DY]
        JSR     jr_gfx_at
        LDAA    SD_SLASH + 1
        JSR     jr_gfx_putc
        INC     [SD_DX]
        INC     [SD_DY]
        LDAA    [SD_DY]
        CMPA    9
        BNE     sd_draw_slash
sd_draw_intent:
        ; NEXT: the intent's value (weak lowers an attack by 3)
        LDX     sd_txt_next_attack
        LDAB    SD_ATTR_HURT
        LDAA    [SD_EATK]
        STAA    [SD_DV]
        LDAA    [SD_INTENT]
        CMPA    1
        BNE     sd_draw_intent_attack
        LDX     sd_txt_next_shield
        LDAB    SD_ATTR_SHIELD
        LDAA    [SD_EGUARD]
        STAA    [SD_DV]
        BRA     sd_draw_intent_text
sd_draw_intent_attack:
        TSTA
        BEQ     sd_draw_intent_weak
        INC     [SD_DV]
        INC     [SD_DV]
sd_draw_intent_weak:
        TST     [SD_WEAK]
        BEQ     sd_draw_intent_text
        LDAA    [SD_DV]
        SUBA    3
        BCC     sd_draw_intent_store
        CLRA
sd_draw_intent_store:
        STAA    [SD_DV]
sd_draw_intent_text:
        PSHB
        LDAA    [SD_FX]
        CMPA    SD_FX_ENEMY
        BNE     sd_draw_intent_colour
        PULB
        LDAB    SD_ATTR_TITLE
        PSHB
sd_draw_intent_colour:
        PULB
        STAB    [JR_RT_COLOR]
        STX     [SD_DPTR]
        LDAA    7
        LDAB    11
        JSR     jr_gfx_at
        LDX     [SD_DPTR]
        JSR     jr_gfx_text
        LDAA    20
        STAA    [SD_DX]
        LDAA    11
        STAA    [SD_DY]
        LDAB    [JR_RT_COLOR]
        LDAA    [SD_DV]
        JSR     sd_num2
        ; the hand
        CLR     [SD_DI]
sd_draw_hand_card:
        LDX     SD_HAND
        LDAA    [SD_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [SD_DCARD]
        LDAA    [SD_DI]
        ASLA
        ASLA
        ASLA
        STAA    [SD_DX]
        LDAA    13
        STAA    [SD_DY]
        CLR     [SD_DFULL]
        ; the card landing now is drawn white
        LDAA    [SD_FX]
        CMPA    SD_FX_DRAW
        BNE     sd_draw_hand_put
        LDAA    [SD_FXSLOT]
        CMPA    [SD_DI]
        BNE     sd_draw_hand_put
        LDAA    2
        STAA    [SD_DFULL]
sd_draw_hand_put:
        JSR     sd_draw_card
        INC     [SD_DI]
        LDAA    [SD_DI]
        CMPA    4
        BNE     sd_draw_hand_card
        ; the selection and its description
        LDAA    [SD_SEL]
        CMPA    4
        BEQ     sd_draw_end_pick
        ASLA
        ASLA
        ASLA
        ADDA    3
        STAA    [SD_DX]
        LDAA    12
        STAA    [SD_DY]
        LDAA    SD_ARROW_DOWN
        LDAB    SD_ATTR_PICK
        JSR     sd_put
        LDX     SD_HAND
        LDAA    [SD_SEL]
        JSR     jr_add_x_a
        LDAA    [X]
        LDX     sd_txt_empty
        CMPA    SD_EMPTY
        BEQ     sd_draw_description
        LDX     sd_card_texts
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        BRA     sd_draw_description
sd_draw_end_pick:
        LDAA    9
        STAA    [SD_DX]
        LDAA    19
        STAA    [SD_DY]
        LDAA    SD_ARROW_RIGHT
        LDAB    SD_ATTR_PICK
        JSR     sd_put
        LDX     sd_txt_end_turn
sd_draw_description:
        STX     [SD_DPTR]
        LDAA    SD_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    21
        JSR     jr_gfx_at
        LDX     [SD_DPTR]
        JMP     jr_gfx_text

; A card panel, 8 x 6, at SD_DX / SD_DY: SD_DCARD (SD_EMPTY: an empty
; frame), SD_DFULL 0 in play (a card it cannot pay for is dim), 1 always
; bright, 2 white (landing).
sd_draw_card:
        LDAA    SD_ATTR_DIM
        LDAB    [SD_DCARD]
        CMPB    SD_EMPTY
        BEQ     sd_draw_card_frame
        TBA
        JSR     sd_card_stats
        STX     [SD_DCPTR]
        ; the frame's colour: attack red, shield cyan, other magenta
        LDAA    3
        TST     [X + 1]
        BEQ     sd_draw_card_block
        LDAA    2
        BRA     sd_draw_card_afford
sd_draw_card_block:
        TST     [X + 2]
        BEQ     sd_draw_card_afford
        LDAA    5
sd_draw_card_afford:
        LDAB    [SD_DFULL]
        BNE     sd_draw_card_white
        LDAB    [SD_ENERGY]
        CMPB    [X]
        BCC     sd_draw_card_frame
        LDAA    SD_ATTR_DIM
        BRA     sd_draw_card_frame
sd_draw_card_white:
        CMPB    2
        BNE     sd_draw_card_frame
        LDAA    7
sd_draw_card_frame:
        ORAA    0x40
        STAA    [SD_DATTR]
        STAA    [JR_RT_COLOR]
        ; top edge
        LDAA    [SD_DX]
        LDAB    [SD_DY]
        JSR     jr_gfx_at
        LDAA    SD_CORNER_TL
        JSR     jr_gfx_putc
        LDAA    SD_EDGE_H
        LDAB    6
sd_draw_card_top:
        JSR     jr_gfx_putc
        DECB
        BNE     sd_draw_card_top
        LDAA    SD_CORNER_TR
        JSR     jr_gfx_putc
        ; sides
        LDAA    4
        STAA    [SD_DN]
sd_draw_card_side:
        LDAA    [SD_DY]
        ADDA    [SD_DN]
        TAB
        LDAA    [SD_DX]
        JSR     jr_gfx_at
        LDAA    SD_EDGE_V
        JSR     jr_gfx_putc
        LDAA    [SD_DY]
        ADDA    [SD_DN]
        TAB
        LDAA    [SD_DX]
        ADDA    7
        JSR     jr_gfx_at
        LDAA    SD_EDGE_V
        JSR     jr_gfx_putc
        DEC     [SD_DN]
        BNE     sd_draw_card_side
        ; bottom edge
        LDAB    [SD_DY]
        ADDB    5
        LDAA    [SD_DX]
        JSR     jr_gfx_at
        LDAA    SD_CORNER_BL
        JSR     jr_gfx_putc
        LDAA    SD_EDGE_H
        LDAB    6
sd_draw_card_bottom:
        JSR     jr_gfx_putc
        DECB
        BNE     sd_draw_card_bottom
        LDAA    SD_CORNER_BR
        JSR     jr_gfx_putc
        LDAA    [SD_DCARD]
        CMPA    SD_EMPTY
        BNE     sd_draw_card_face
        RTS
sd_draw_card_face:
        ; name
        LDAA    SD_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [SD_DX]
        INCA
        LDAB    [SD_DY]
        INCB
        JSR     jr_gfx_at
        LDX     sd_card_names
        LDAA    [SD_DCARD]
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        ; cost: a bolt and the energy
        LDAA    [SD_DX]
        INCA
        LDAB    [SD_DY]
        ADDB    2
        JSR     jr_gfx_at
        LDAA    0x46
        STAA    [JR_RT_COLOR]
        LDAA    SD_ICON_BOLT
        JSR     jr_gfx_putc
        LDAA    SD_ATTR_ENERGY
        STAA    [JR_RT_COLOR]
        LDX     [SD_DCPTR]
        LDAA    [X]
        ADDA    0x30
        JSR     jr_gfx_putc
        LDX     sd_txt_en
        JSR     jr_gfx_text
        ; the main number: attack, shield or the special's value
        LDX     [SD_DCPTR]
        LDAB    SD_ICON_SIGIL
        LDAA    [X + 1]
        BEQ     sd_draw_card_shield
        LDAB    SD_ICON_SWORD
        BRA     sd_draw_card_stat
sd_draw_card_shield:
        LDAA    [X + 2]
        BEQ     sd_draw_card_sigil
        LDAB    SD_ICON_SHIELD
        BRA     sd_draw_card_stat
sd_draw_card_sigil:
        LDAA    [X + 4]
sd_draw_card_stat:
        STAA    [SD_DV]
        STAB    [SD_DN]
        LDAA    [SD_DX]
        ADDA    2
        LDAB    [SD_DY]
        ADDB    3
        JSR     jr_gfx_at
        LDAA    [SD_DATTR]
        STAA    [JR_RT_COLOR]
        LDAA    [SD_DN]
        JSR     jr_gfx_putc
        LDAA    SD_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [SD_DX]
        ADDA    4
        LDAB    [SD_DY]
        ADDB    3
        JSR     jr_gfx_at
        LDAA    [SD_DV]
        JSR     jr_gfx_dec2
        ; exhaust mark
        LDX     [SD_DCPTR]
        TST     [X + 5]
        BEQ     sd_draw_card_done
        LDAA    SD_ATTR_LABEL
        STAA    [JR_RT_COLOR]
        LDAA    [SD_DX]
        ADDA    2
        LDAB    [SD_DY]
        ADDB    4
        JSR     jr_gfx_at
        LDX     sd_txt_exh
        JSR     jr_gfx_text
sd_draw_card_done:
        RTS

sd_draw_reward:
        JSR     sd_draw_ornament
        LDX     sd_reward_lines
        JSR     jr_gfx_lines
        CLR     [SD_DI]
sd_draw_reward_card:
        LDX     SD_REWARDS
        LDAA    [SD_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        STAA    [SD_DCARD]
        LDAA    [SD_DI]
        ASLA
        ASLA
        ASLA
        ADDA    4
        STAA    [SD_DX]
        LDAA    8
        STAA    [SD_DY]
        LDAA    1
        STAA    [SD_DFULL]
        JSR     sd_draw_card
        INC     [SD_DI]
        LDAA    [SD_DI]
        CMPA    3
        BNE     sd_draw_reward_card
        LDAA    [SD_SEL]
        CMPA    3
        BEQ     sd_draw_rest_pick
        ASLA
        ASLA
        ASLA
        ADDA    7
        STAA    [SD_DX]
        LDAA    7
        STAA    [SD_DY]
        LDAA    SD_ARROW_DOWN
        LDAB    SD_ATTR_PICK
        JSR     sd_put
        LDAA    SD_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    1
        LDAB    15
        JSR     jr_gfx_at
        LDX     SD_REWARDS
        LDAA    [SD_SEL]
        JSR     jr_add_x_a
        LDAA    [X]
        LDX     sd_card_texts
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JMP     jr_gfx_text
sd_draw_rest_pick:
        LDAA    4
        STAA    [SD_DX]
        LDAA    18
        STAA    [SD_DY]
        LDAA    SD_ARROW_RIGHT
        LDAB    SD_ATTR_PICK
        JMP     sd_put

sd_draw_deck:
        LDX     sd_deck_lines
        JSR     jr_gfx_lines
        CLR     [SD_DI]
sd_draw_deck_card:
        LDAA    [SD_DI]
        CMPA    [SD_DECKN]
        BCC     sd_draw_deck_done
        LDAB    1
        CMPA    12
        BCS     sd_draw_deck_column
        SUBA    12
        LDAB    17
sd_draw_deck_column:
        ADDA    6
        STAA    [SD_DY]
        STAB    [SD_DX]
        LDAA    [SD_DI]
        INCA
        LDAB    SD_ATTR_LABEL
        JSR     sd_num2
        LDAA    SD_ATTR_TEXT
        STAA    [JR_RT_COLOR]
        LDAA    [SD_DX]
        ADDA    3
        LDAB    [SD_DY]
        JSR     jr_gfx_at
        LDX     SD_DECK
        LDAA    [SD_DI]
        JSR     jr_add_x_a
        LDAA    [X]
        LDX     sd_card_names
        ASLA
        JSR     jr_add_x_a
        LDX     [X]
        JSR     jr_gfx_text
        INC     [SD_DI]
        BRA     sd_draw_deck_card
sd_draw_deck_done:
        RTS

; A frame of card edges around the screen (rows 0-22).
sd_draw_ornament:
        LDAA    SD_ATTR_FRAME
        STAA    [JR_RT_COLOR]
        CLRA
        CLRB
        JSR     jr_gfx_at
        LDAA    SD_CORNER_TL
        JSR     jr_gfx_putc
        LDAA    SD_EDGE_H
        LDAB    30
sd_ornament_top:
        JSR     jr_gfx_putc
        DECB
        BNE     sd_ornament_top
        LDAA    SD_CORNER_TR
        JSR     jr_gfx_putc
        LDAA    1
        STAA    [SD_DN]
sd_ornament_side:
        CLRA
        LDAB    [SD_DN]
        JSR     jr_gfx_at
        LDAA    SD_EDGE_V
        JSR     jr_gfx_putc
        LDAA    31
        LDAB    [SD_DN]
        JSR     jr_gfx_at
        LDAA    SD_EDGE_V
        JSR     jr_gfx_putc
        INC     [SD_DN]
        LDAA    [SD_DN]
        CMPA    22
        BNE     sd_ornament_side
        CLRA
        LDAB    22
        JSR     jr_gfx_at
        LDAA    SD_CORNER_BL
        JSR     jr_gfx_putc
        LDAA    SD_EDGE_H
        LDAB    30
sd_ornament_bottom:
        JSR     jr_gfx_putc
        DECB
        BNE     sd_ornament_bottom
        LDAA    SD_CORNER_BR
        JMP     jr_gfx_putc

; X = logo (.db width, then 4 rows of quarter blocks), A = column, B = row.
sd_draw_logo:
        STAA    [SD_DX]
        STAB    [SD_DY]
        LDAA    [X]
        STAA    [SD_DV]
        INX
        STX     [SD_DPTR]
        LDAA    4
        STAA    [SD_DN]
sd_logo_row:
        LDAA    [SD_DX]
        LDAB    [SD_DY]
        JSR     jr_gfx_at
        LDAB    [SD_DV]
sd_logo_cell:
        LDX     [SD_DPTR]
        LDAA    [X]
        INX
        STX     [SD_DPTR]
        JSR     jr_gfx_putc
        DECB
        BNE     sd_logo_cell
        INC     [SD_DY]
        DEC     [SD_DN]
        BNE     sd_logo_row
        RTS

game_draw_title:
        LDX     sd_title_song
        JSR     jr_music_play
        LDAA    0x20
        LDAB    SD_ATTR_TEXT
        JSR     jr_gfx_fill
        JSR     sd_draw_ornament
        LDAA    0x46
        STAA    [JR_RT_COLOR]
        LDX     sd_logo_sigil
        LDAA    8
        LDAB    3
        JSR     sd_draw_logo
        LDAA    0x43
        STAA    [JR_RT_COLOR]
        LDX     sd_logo_deck
        LDAA    10
        LDAB    8
        JSR     sd_draw_logo
        ; the four kinds of card
        LDX     sd_title_icons
        STX     [SD_DPTR]
sd_title_icon:
        LDX     [SD_DPTR]
        LDAA    [X]
        CMPA    0xff
        BEQ     sd_title_text
        STAA    [SD_DX]
        LDAB    [X + 1]
        LDAA    [X + 2]
        INX
        INX
        INX
        STX     [SD_DPTR]
        PSHA
        LDAA    13
        STAA    [SD_DY]
        PULA
        JSR     sd_put
        BRA     sd_title_icon
sd_title_text:
        LDX     sd_title_lines
        JMP     jr_gfx_lines

game_draw_help:
        LDAA    0x20
        LDAB    SD_ATTR_TEXT
        JSR     jr_gfx_fill
        LDX     sd_help_lines
        JMP     jr_gfx_lines

; ---------------------------------------------------------------- data

; per enemy: the figure's attribute
sd_enemy_colours:
        .db     0x47, 0x45, 0x46, 0x44, 0x43, 0x47, 0x46, 0x42

; column, attribute, code
sd_title_icons:
        .db     10, 0x42, SD_ICON_SWORD, 13, 0x45, SD_ICON_SHIELD
        .db     16, 0x43, SD_ICON_SIGIL, 19, 0x44, SD_ICON_HEART
        .db     22, 0x46, SD_ICON_BOLT, 0xff

; column, row, colour, state offset
sd_hud_numbers:
        .db     24, 0, SD_ATTR_ENERGY, 5
        .db     12, 1, SD_ATTR_TEXT, 21
        .db     22, 1, SD_ATTR_TEXT, 22
        .db     28, 1, SD_ATTR_TEXT, 23
        .db     4, 4, SD_ATTR_TEXT, 8
        .db     4, 6, SD_ATTR_SHIELD, 9
        .db     4, 8, SD_ATTR_POISON, 13
        .db     4, 10, SD_ATTR_TEXT, 14
        .db     25, 4, SD_ATTR_TEXT, 16
        .db     25, 6, SD_ATTR_TEXT, 15
        .db     25, 8, SD_ATTR_TEXT, 18
        .db     25, 10, SD_ATTR_TEXT, 17
        .db     0xff

sd_hud_lines:
        .db     0, 0, SD_ATTR_LABEL
        .dw     sd_txt_hp
        .db     10, 0, SD_ATTR_LABEL
        .dw     sd_txt_sh
        .db     21, 0, SD_ATTR_LABEL
        .dw     sd_txt_en
        .db     0, 1, SD_ATTR_LABEL
        .dw     sd_txt_f
        .db     7, 1, SD_ATTR_LABEL
        .dw     sd_txt_draw
        .db     17, 1, SD_ATTR_LABEL
        .dw     sd_txt_used
        .db     26, 1, SD_ATTR_LABEL
        .dw     sd_txt_x
        .db     1, 3, SD_ATTR_LABEL
        .dw     sd_txt_enemy_hp
        .db     1, 5, SD_ATTR_LABEL
        .dw     sd_txt_shield
        .db     1, 7, SD_ATTR_LABEL
        .dw     sd_txt_poison
        .db     1, 9, SD_ATTR_LABEL
        .dw     sd_txt_weak
        .db     22, 3, SD_ATTR_LABEL
        .dw     sd_txt_str
        .db     22, 5, SD_ATTR_LABEL
        .dw     sd_txt_vul
        .db     22, 7, SD_ATTR_LABEL
        .dw     sd_txt_echo
        .db     22, 9, SD_ATTR_LABEL
        .dw     sd_txt_thorn
        .db     11, 19, SD_ATTR_TITLE
        .dw     sd_txt_end_label
        .db     0xff
sd_reward_lines:
        .db     7, 3, SD_ATTR_TITLE
        .dw     sd_txt_reward_1
        .db     4, 5, SD_ATTR_LABEL
        .dw     sd_txt_reward_2
        .db     6, 18, SD_ATTR_TEXT
        .dw     sd_txt_reward_3
        .db     2, 20, SD_ATTR_LABEL
        .dw     sd_txt_reward_4
        .db     0xff
sd_death_lines:
        .db     8, 5, SD_ATTR_HURT
        .dw     sd_txt_failed
        .db     5, 8, SD_ATTR_TEXT
        .dw     sd_txt_death_2
        .db     5, 13, SD_ATTR_LABEL
        .dw     sd_txt_death_3
        .db     0xff
sd_win_lines:
        .db     7, 4, SD_ATTR_TITLE
        .dw     sd_txt_win_1
        .db     3, 7, SD_ATTR_TEXT
        .dw     sd_txt_win_2
        .db     6, 11, SD_ATTR_LABEL
        .dw     sd_txt_win_3
        .db     6, 14, SD_ATTR_LABEL
        .dw     sd_txt_win_4
        .db     0xff
sd_deck_lines:
        .db     11, 1, SD_ATTR_TITLE
        .dw     sd_txt_deck_1
        .db     1, 3, SD_ATTR_LABEL
        .dw     sd_txt_deck_2
        .db     1, 20, SD_ATTR_LABEL
        .dw     sd_txt_deck_3
        .db     5, 22, SD_ATTR_TEXT
        .dw     sd_txt_deck_4
        .db     0xff
sd_title_lines:
        .db     5, 15, SD_ATTR_LABEL
        .dw     sd_txt_tagline
        .db     2, 16, SD_ATTR_TEXT
        .dw     sd_txt_tagline_2
        .db     9, 18, SD_ATTR_TEXT
        .dw     sd_txt_start
        .db     5, 19, SD_ATTR_TEXT
        .dw     sd_txt_howto
        .db     5, 21, SD_ATTR_LABEL
        .dw     sd_txt_credit
        .db     0xff
sd_help_lines:
        .db     11, 1, SD_ATTR_TITLE
        .dw     sd_txt_name
        .db     1, 3, SD_ATTR_TEXT
        .dw     sd_help_1
        .db     1, 5, SD_ATTR_TEXT
        .dw     sd_help_2
        .db     1, 6, SD_ATTR_TEXT
        .dw     sd_help_3
        .db     1, 7, SD_ATTR_TEXT
        .dw     sd_help_4
        .db     1, 8, SD_ATTR_TEXT
        .dw     sd_help_5
        .db     1, 10, SD_ATTR_TEXT
        .dw     sd_help_6
        .db     1, 11, SD_ATTR_TEXT
        .dw     sd_help_7
        .db     1, 12, SD_ATTR_TEXT
        .dw     sd_help_8
        .db     1, 13, SD_ATTR_TEXT
        .dw     sd_help_9
        .db     1, 15, SD_ATTR_TEXT
        .dw     sd_help_10
        .db     1, 16, SD_ATTR_TEXT
        .dw     sd_help_11
        .db     1, 17, SD_ATTR_TEXT
        .dw     sd_help_12
        .db     1, 18, SD_ATTR_TEXT
        .dw     sd_help_13
        .db     1, 20, SD_ATTR_TEXT
        .dw     sd_help_14
        .db     8, 22, SD_ATTR_LABEL
        .dw     sd_help_back
        .db     0xff

sd_txt_name:
        .db     "SIGIL DECK", 0
sd_txt_hp:
        .db     "HP", 0
sd_txt_sh:
        .db     "SH", 0
sd_txt_en:
        .db     "EN", 0
sd_txt_f:
        .db     "F", 0
sd_txt_draw:
        .db     "DRAW", 0
sd_txt_used:
        .db     "USED", 0
sd_txt_x:
        .db     "X", 0
sd_txt_enemy_hp:
        .db     "ENEMY HP", 0
sd_txt_shield:
        .db     "SHIELD", 0
sd_txt_poison:
        .db     "POISON", 0
sd_txt_weak:
        .db     "WEAK", 0
sd_txt_str:
        .db     "STR", 0
sd_txt_vul:
        .db     "VUL", 0
sd_txt_echo:
        .db     "ECHO", 0
sd_txt_thorn:
        .db     "THORN", 0
sd_txt_end_label:
        .db     "END TURN", 0
sd_txt_next_attack:
        .db     "NEXT: ATTACK", 0
sd_txt_next_shield:
        .db     "NEXT: SHIELD", 0
sd_txt_empty:
        .db     "EMPTY SLOT", 0
sd_txt_end_turn:
        .db     "DISCARD HAND. ENEMY ACTS.", 0
sd_txt_exh:
        .db     "EXH", 0
sd_txt_reward_1:
        .db     "A NEW SIGIL AWAITS", 0
sd_txt_reward_2:
        .db     "CHOOSE ONE CARD OR REST", 0
sd_txt_reward_3:
        .db     "REST: HEAL 10 HP", 0
sd_txt_reward_4:
        .db     "EVERY VICTORY ALSO HEALS 4 HP", 0
sd_txt_failed:
        .db     "THE RITUAL FAILED", 0
sd_txt_death_2:
        .db     "YOUR SIGILS FALL SILENT", 0
sd_txt_death_3:
        .db     "RETURN: BEGIN AGAIN?", 0
sd_txt_win_1:
        .db     "THE VOID IS SEALED", 0
sd_txt_win_2:
        .db     "TEN BATTLES. ONE TRUE DECK.", 0
sd_txt_win_3:
        .db     "CARDS PLAYED", 0
sd_txt_win_4:
        .db     "FINAL HP", 0
sd_txt_deck_1:
        .db     "YOUR DECK", 0
sd_txt_deck_2:
        .db     "CARDS RETURN EACH BATTLE.", 0
sd_txt_deck_3:
        .db     "EXHAUST LASTS ONE BATTLE.", 0
sd_txt_deck_4:
        .db     "ANY KEY: RETURN", 0
sd_txt_tagline:
        .db     "A RITUAL IN YOUR HAND", 0
sd_txt_tagline_2:
        .db     "BUILD A DECK. BREAK THE VOID.", 0
sd_txt_start:
        .db     "RETURN : BEGIN", 0
sd_txt_howto:
        .db     "OTHER KEY : FIELD GUIDE", 0
sd_txt_credit:
        .db     "JR-200 PORT OF JR100DEV", 0
sd_help_1:
        .db     "TEN BATTLES. BUILD YOUR DECK.", 0
sd_help_2:
        .db     "A/D : SELECT A CARD", 0
sd_help_3:
        .db     "RETURN : PLAY / CONFIRM", 0
sd_help_4:
        .db     "SPACE : SELECT END TURN", 0
sd_help_5:
        .db     "W : VIEW YOUR DECK", 0
sd_help_6:
        .db     "ENERGY RETURNS TO 3 EACH TURN.", 0
sd_help_7:
        .db     "UNUSED CARDS ARE DISCARDED.", 0
sd_help_8:
        .db     "DRAW PILE EMPTY? RECYCLE USED.", 0
sd_help_9:
        .db     "EXHAUSTED CARDS STAY OUT.", 0
sd_help_10:
        .db     "SHIELD EXPIRES NEXT TURN.", 0
sd_help_11:
        .db     "POISON BYPASSES ENEMY SHIELD.", 0
sd_help_12:
        .db     "VULNERABLE: +50% ATTACK HIT.", 0
sd_help_13:
        .db     "WEAK: ENEMY ATTACK -3.", 0
sd_help_14:
        .db     "WIN: PICK A CARD OR REST.", 0
sd_help_back:
        .db     "ANY KEY : TITLE", 0

        .include "data.inc"

; ---------------------------------------------------------------- sound

game_sfx_table:
        .dw     sd_sfx_menu, sd_sfx_shot, sd_jingle_win, sd_jingle_lose
sd_sfx_menu:
        .db     90, 1, 0, 0
sd_sfx_shot:
        .db     30, 1, 45, 2, 70, 2, 0, 0
sd_sfx_shield:
        .db     120, 2, 100, 2, 90, 3, 0, 0
sd_sfx_heal:
        .db     80, 3, 70, 3, 55, 5, 0, 0
sd_sfx_poison:
        .db     60, 2, 62, 2, 110, 5, 0, 0
sd_sfx_hit:
        .db     160, 3, 200, 2, 240, 5, 0, 0
sd_sfx_empty:
        .db     230, 3, 0, 0

sd_title_song:      .equ    sd_music_title
sd_battle_song:     .equ    sd_music_battle

; Victory: D major.
sd_jingle_win:
        .db     JR_AU_SONG_MARK, 0
        .dw     sd_win_melody, sd_win_harmony, sd_win_bass
sd_win_melody:
        .db     AU_A5, 8, AU_D6, 8, AU_FS6, 8, AU_A6, 30, 0, 0
sd_win_harmony:
        .db     AU_FS5, 8, AU_A5, 8, AU_D6, 8, AU_FS6, 30, 0, 0
sd_win_bass:
        .db     AU_D3, 24, AU_D2, 30, 0, 0
; The ritual failed: a falling D minor figure.
sd_jingle_lose:
        .db     JR_AU_SONG_MARK, 0
        .dw     sd_lose_melody, sd_lose_harmony, sd_lose_bass
sd_lose_melody:
        .db     AU_A5, 12, AU_GS5, 12, AU_G5, 12, AU_F5, 30, 0, 0
sd_lose_harmony:
        .db     AU_F5, 12, AU_E5, 12, AU_DS5, 12, AU_D5, 30, 0, 0
sd_lose_bass:
        .db     AU_D3, 36, AU_D2, 30, 0, 0

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
