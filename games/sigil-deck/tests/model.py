# SPDX-License-Identifier: MIT
"""SIGIL DECK rules model (jr100dev games/sigil_deck/src 1.6.1).

The rules follow upstream src/main.asm and src/cards.asm, whose card
arithmetic upstream replay.py (card_result) and check_rules.py state
independently: the new run (HP 60, the eight-card deck), a battle's start
(the deck copied to the draw pile, the enemy from BATTLE_ORDER, intent
enemy & 1), the turn (shield cleared unless retained, thorns cleared,
energy 3, draw up to four empty slots), a card (cost, attack with strength,
the finisher, echo doubling and vulnerable +50% against the enemy shield,
block up to 99, the special, then discard or exhaust), END TURN (discard
the hand, clear the enemy shield, poison, the intent's action, thorns,
weak and vulnerable down, next intent, defeat before victory, next turn),
the reward (three different random cards or REST +10, then +4 and the next
battle) and the victory after the tenth battle. Draws and rewards use the
upstream PRNG (rng << 1, XOR 0x1D on carry): a draw takes the pile slot
rng mod count and moves the pile's last card into it, a reward card is
rng mod 24.

Upstream seeds the PRNG with its timer (TICK OR 1) at every new run; this
port uses the music position, kept as `seed`. ORIGINS lists the seeds the
model's runs start from; replays read the emulator's seeds and set them.

state_bytes() mirrors src/main.asm: sub (0 battle, 1 reward, 2 deck view),
selected, battle, hp, shield, energy, turn, enemy, enemy_hp, enemy_shield,
enemy_attack, enemy_guard, intent, poison, weak, vulnerable, strength,
thorns, echo, retain, the four pile counts (deck, draw, discard, exhaust),
rng, seed, played, rewards[3], hand[4] (255 empty) and the four piles of
24 cards.

`frames` counts the animation frames an action plays (not part of the state).
"""
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    'sigil_deck_data', Path(__file__).resolve().parent / 'data.py')
data = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(data)

LEVELS = 1
MAX_HP = 60
EMPTY = 255
PILE = 24
SCENE_FRAMES = 16                    # upstream SIGIL_SCENE: one card effect
BATTLE, REWARD, DECK_VIEW = range(3)
LAYOUT = [('sub', 1), ('selected', 1), ('battle', 1), ('hp', 1), ('shield', 1),
          ('energy', 1), ('turn', 1), ('enemy', 1), ('enemy_hp', 1), ('enemy_shield', 1),
          ('enemy_attack', 1), ('enemy_guard', 1), ('intent', 1), ('poison', 1), ('weak', 1),
          ('vulnerable', 1), ('strength', 1), ('thorns', 1), ('echo', 1), ('retain', 1),
          ('deck_count', 1), ('draw_count', 1), ('discard_count', 1), ('exhaust_count', 1),
          ('rng', 1), ('seed', 1), ('played', 1), ('rewards', 3), ('hand', 4),
          ('deck', PILE), ('draw', PILE), ('discard', PILE), ('exhaust', PILE)]
SIZE = sum(n for _, n in LAYOUT)
DEATH_MESSAGE = 'THE RITUAL FAILED'


class SigilDeck:
    port = None
    ORIGINS = [1]

    def __init__(self):
        self.runs = 0
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)
        self.frames = 0

    # ------------------------------------------------------------ run
    def init(self):
        """NEW_RUN and START_BATTLE."""
        origins = type(self).ORIGINS
        self.seed = origins[min(self.runs, len(origins) - 1)] | 1
        self.runs += 1
        self.rng = self.seed
        self.hp = MAX_HP
        self.battle = self.played = 0
        self.deck_count = len(data.INITIAL_DECK)
        self.deck[:self.deck_count] = data.INITIAL_DECK
        self.start_battle()

    def start_battle(self):
        for name in ('shield', 'enemy_shield', 'poison', 'weak', 'vulnerable', 'strength',
                     'thorns', 'echo', 'retain', 'discard_count', 'exhaust_count',
                     'selected', 'turn'):
            setattr(self, name, 0)
        self.sub = BATTLE
        self.draw_count = self.deck_count
        self.draw[:self.deck_count] = self.deck[:self.deck_count]
        self.enemy = data.BATTLE_ORDER[self.battle]
        self.intent = self.enemy & 1
        _, self.enemy_hp, self.enemy_attack, self.enemy_guard = data.ENEMIES[self.enemy]
        self.hand = [EMPTY] * 4
        self.player_turn()

    def next_random(self):
        self.rng = ((self.rng << 1) ^ (0x1D if self.rng & 128 else 0)) & 255
        return self.rng

    # ------------------------------------------------------------ piles
    def draw_one(self):
        if not self.draw_count:
            if not self.discard_count:
                return EMPTY
            self.draw_count = self.discard_count
            self.draw[:self.draw_count] = self.discard[:self.draw_count]
            self.discard_count = 0
        index = self.next_random() % self.draw_count
        card = self.draw[index]
        self.draw_count -= 1
        self.draw[index] = self.draw[self.draw_count]
        return card

    def draw_hand(self, count):
        for slot in range(4):
            if self.hand[slot] != EMPTY:
                continue
            card = self.draw_one()
            self.hand[slot] = card
            if card == EMPTY:
                return
            if self.turn:
                self.frames += SCENE_FRAMES
            count -= 1
            if not count:
                return

    def discard_card(self, card):
        self.discard[self.discard_count] = card
        self.discard_count += 1

    def player_turn(self):
        if not self.retain:
            self.shield = 0
        self.retain = self.thorns = 0
        self.energy = 3
        self.draw_hand(4)
        if self.turn != 255:
            self.turn += 1

    # ------------------------------------------------------------ input
    def act(self, action):
        self.frames = 0
        if self.sub == DECK_VIEW:
            self.sub = BATTLE
        elif self.sub == REWARD:
            if action == 3:
                self.selected = (self.selected - 1) % 4
            elif action == 4:
                self.selected = (self.selected + 1) % 4
            elif action == 5:
                if self.selected == 3:
                    self.heal(10)
                else:
                    self.deck[self.deck_count] = self.rewards[self.selected]
                    self.deck_count += 1
                self.heal(4)
                self.battle += 1
                self.start_battle()
        elif action == 3:
            self.selected = (self.selected - 1) % 5
        elif action == 4:
            self.selected = (self.selected + 1) % 5
        elif action == 6:
            self.selected = 4
        elif action == 1:
            self.sub = DECK_VIEW
        elif action == 5:
            if self.selected == 4:
                self.enemy_turn()
            else:
                self.play_card()

    def heal(self, value):
        self.hp = min(MAX_HP, self.hp + value)

    def hurt_enemy(self, damage):
        if damage <= self.enemy_shield:
            self.enemy_shield -= damage
            return
        self.enemy_hp = max(0, self.enemy_hp - (damage - self.enemy_shield))
        self.enemy_shield = 0

    def play_card(self):
        card = self.hand[self.selected]
        if card == EMPTY:
            return
        _, cost, attack, block, special, value, exhaust, _ = data.CARDS[card]
        if self.energy < cost:
            return
        self.energy -= cost
        self.played = min(255, self.played + 1)
        self.hand[self.selected] = EMPTY
        if attack:
            damage = attack + self.strength
            if special == 12 and self.enemy_hp <= 12:
                damage += 12
            if self.echo:
                damage = damage * 2 & 255
                self.echo = 0
            if self.vulnerable:
                damage = (damage + (damage >> 1)) & 255
            self.hurt_enemy(damage)
            self.frames += SCENE_FRAMES
        if block:
            self.shield = min(99, self.shield + block)
            self.frames += SCENE_FRAMES
        if special == 1:
            self.heal(value)
            self.frames += SCENE_FRAMES
        elif special == 2:
            self.energy = min(9, self.energy + value)
        elif special == 3:
            self.poison = min(99, self.poison + value)
        elif special == 4:
            self.energy += 1
            self.draw_hand(1)
        elif special == 5:
            self.thorns = (self.thorns + value) & 255
        elif special == 6:
            self.vulnerable = 2
        elif special == 7:
            self.echo = 1
        elif special == 8:
            self.retain = 1
        elif special == 9:
            self.strength = min(20, self.strength + value)
        elif special == 10:
            self.weak = 2
        elif special == 11:
            self.draw_hand(value)
        if exhaust:
            self.exhaust[self.exhaust_count] = card
            self.exhaust_count += 1
        else:
            self.discard_card(card)
        self.check_victory()

    def enemy_turn(self):
        for slot in range(4):
            if self.hand[slot] != EMPTY:
                self.discard_card(self.hand[slot])
                self.hand[slot] = EMPTY
        self.enemy_shield = 0
        if self.poison:
            self.enemy_hp = max(0, self.enemy_hp - self.poison)
            self.poison -= 1
            self.frames += SCENE_FRAMES
            if self.check_victory():
                return
        if self.intent == 1:
            self.enemy_shield = self.enemy_guard
        else:
            damage = self.enemy_attack + (2 if self.intent else 0)
            if self.weak:
                damage = max(0, damage - 3)
            if damage <= self.shield:
                self.shield -= damage
            else:
                self.hp = max(0, self.hp - (damage - self.shield))
                self.shield = 0
            self.hurt_enemy(self.thorns)
        if self.weak:
            self.weak -= 1
        if self.vulnerable:
            self.vulnerable -= 1
        self.intent = (self.intent + 1) % 3
        self.frames += SCENE_FRAMES
        if self.check_victory():
            return
        self.player_turn()

    def check_victory(self):
        """True when the battle ended (defeat first, then the enemy's defeat)."""
        if not self.hp:
            self.port.lose(DEATH_MESSAGE)
            return True
        if self.enemy_hp:
            return False
        self.selected = 0
        if self.battle == 9:
            self.port.win()
            return True
        self.sub = REWARD
        self.rewards[0] = self.random_card()
        while True:
            self.rewards[1] = self.random_card()
            if self.rewards[1] != self.rewards[0]:
                break
        while True:
            self.rewards[2] = self.random_card()
            if self.rewards[2] not in self.rewards[:2]:
                break
        return True

    def random_card(self):
        return self.next_random() % 24

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(v & 0xff for v in out).hex()
