# SPDX-License-Identifier: MIT
"""DICE RELIC rules model (jr100dev games/dice_relic/model.py and src/main.asm 1.7.1).

The combat, rerolls, enemy attack, rewards, forge and heal prices and the
PRNG (rng = rng << 1, XOR 0x1D on carry; a die shows its face rng % 6) are
upstream model.py. DiceRelic adds what upstream keeps in src/main.asm: the
selected die and role (A/D, W/S, wrapping), the automatic move to the next
unused die, ERROR for a refused use, the ROLES shown under the dice, the
workshop (die and face selection) and its FORGE/HEAL/NEXT/BACK menu.

Upstream seeds the PRNG with its timer (TICK OR 1) at NEW_GAME; this port
uses the title song's position, kept as `seed`. ORIGIN is the seed the model
starts from; replays read the emulator's seed and set it.

state_bytes() mirrors src/main.asm: hp, shield, coins, battle, enemy_hp,
enemy_attack, turn, rerolls, used, rng, seed, selected, choice, face, menu,
sub (0 battle, 1 workshop, 2 workshop menu), error, dice[3], faces[18],
roles[3] (role + 1 of each used die).

`frames` counts the animation frames an action plays (not part of the state).
"""
ENEMIES = [('DUST IMP', 14, 3), ('STONE EYE', 18, 4), ('BRASS IDOL', 22, 4),
           ('BONE WARD', 25, 5), ('SALT WITCH', 27, 5), ('JADE FANG', 30, 6),
           ('IRON SHADE', 33, 6), ('RELIC GUARD', 37, 7), ('THE FIRST KING', 48, 8)]
LEVELS = 1
MAX_HP = 42
LAYOUT = [('hp', 1), ('shield', 1), ('coins', 1), ('battle', 1), ('enemy_hp', 1),
          ('enemy_attack', 1), ('turn', 1), ('rerolls', 1), ('used', 1), ('rng', 1),
          ('seed', 1), ('selected', 1), ('choice', 1), ('face', 1), ('menu', 1), ('sub', 1),
          ('error', 1), ('dice', 3), ('faces', 18), ('roles', 3)]
SIZE = sum(n for _, n in LAYOUT)
BATTLE, WORKSHOP, SERVICES = range(3)
ROLL_FRAMES = 24                     # upstream: 6 steps of 4 ticks
EFFECT_FRAMES = {'attack': 8, 'hit': 12, 'guard': 12, 'heal': 12, 'strike': 10,
                 'blocked': 12, 'damage': 12, 'victory': 16, 'reward': 16, 'defeat': 16}


class DiceRelic:
    port = None
    ORIGIN = 1

    def __init__(self):
        self.reset()

    def reset(self):
        for name, length in LAYOUT:
            setattr(self, name, 0 if length == 1 else [0] * length)
        self.frames = 0

    def init(self):
        """NEW_GAME, NEW_BATTLE, NEW_TURN."""
        self.battle = self.coins = 0
        self.hp = MAX_HP
        self.seed = self.rng = type(self).ORIGIN | 1
        self.faces = [1, 2, 3, 4, 5, 6] * 3
        self.new_battle()

    def new_battle(self):
        _, self.enemy_hp, self.enemy_attack = ENEMIES[self.battle]
        self.turn = self.shield = self.selected = self.choice = 0
        self.sub = BATTLE
        self.new_turn()

    def roll(self, index):
        self.rng = ((self.rng << 1) ^ (0x1D if self.rng & 128 else 0)) & 255
        self.dice[index] = self.faces[index * 6 + self.rng % 6]

    def new_turn(self):
        self.turn = (self.turn + 1) % 256
        self.used = 0
        self.roles = [0, 0, 0]
        self.rerolls = 1
        for i in range(3):
            self.roll(i)
        self.frames += ROLL_FRAMES

    def act(self, action):
        self.frames = 0
        self.error = 0
        if self.sub == BATTLE:
            self.battle_act(action)
        elif self.sub == WORKSHOP:
            if action in (3, 4):
                self.selected = (self.selected + (2 if action == 3 else 1)) % 3
            elif action in (1, 2):
                self.face = (self.face + (5 if action == 1 else 1)) % 6
            elif action == 5:
                self.sub, self.menu = SERVICES, 0
        else:
            if action in (3, 4):
                self.menu = (self.menu + (3 if action == 3 else 1)) % 4
            elif action == 6:
                self.sub = WORKSHOP
            elif action == 5:
                self.service()

    def battle_act(self, action):
        if action in (3, 4):
            self.selected = (self.selected + (2 if action == 3 else 1)) % 3
        elif action in (1, 2):
            self.choice = (self.choice + (3 if action == 1 else 1)) % 4
        elif action == 5:
            self.use(self.selected, self.choice)

    def use(self, i, choice):
        if self.used >> i & 1:
            self.error = 1
            return
        if choice == 3:
            if not self.rerolls:
                self.error = 1
                return
            self.rerolls -= 1
            self.roll(i)
            self.frames += ROLL_FRAMES
            return
        value = self.dice[i]
        self.used |= 1 << i
        self.roles[i] = choice + 1
        if choice == 0:
            self.frames += EFFECT_FRAMES['attack'] + EFFECT_FRAMES['hit']
            self.enemy_hp = max(0, self.enemy_hp - value)
            if not self.enemy_hp:
                self.hp = min(MAX_HP, self.hp + 2)
                self.coins = (self.coins + 3) & 0xff
                self.frames += EFFECT_FRAMES['victory'] + EFFECT_FRAMES['reward']
                self.selected = self.face = self.menu = 0
                if self.battle == 8:
                    self.port.win()
                else:
                    self.sub = WORKSHOP
                return
        elif choice == 1:
            self.shield = (self.shield + value) & 0xff
            self.frames += EFFECT_FRAMES['guard']
        else:
            self.hp = min(MAX_HP, self.hp + value)
            self.frames += EFFECT_FRAMES['heal']
        if self.used == 7:
            attack = self.enemy_attack + (2 if self.turn % 4 == 0 else 0)
            damage = max(0, attack - self.shield)
            self.frames += EFFECT_FRAMES['strike']
            if self.shield:
                self.frames += EFFECT_FRAMES['blocked']
            if damage:
                self.frames += EFFECT_FRAMES['damage']
                self.hp = max(0, self.hp - damage)
                if not self.hp:
                    self.frames += EFFECT_FRAMES['defeat']
                    self.port.lose('DEFEATED BY THE GUARDIAN')
                    return
            self.shield = 0
            self.new_turn()
            return
        # AUTO_SELECT: the next unused die to the right
        self.selected = (self.selected + 1) % 3
        while self.used >> self.selected & 1:
            self.selected = (self.selected + 1) % 3

    def service(self):
        if self.menu == 0:                      # FORGE: 3 gold, +2 up to 9
            index = self.selected * 6 + self.face
            if self.coins < 3 or self.faces[index] >= 9:
                self.error = 1
                return
            self.faces[index] = min(9, self.faces[index] + 2)
            self.coins -= 3
            self.sub = WORKSHOP
        elif self.menu == 1:                    # HEAL: 2 gold, +6
            if self.coins < 2 or self.hp == MAX_HP:
                self.error = 1
                return
            self.hp = min(MAX_HP, self.hp + 6)
            self.coins -= 2
            self.sub = WORKSHOP
        elif self.menu == 2:                    # NEXT
            self.battle += 1
            self.new_battle()
        else:                                   # BACK
            self.sub = WORKSHOP

    def state_bytes(self):
        out = []
        for name, length in LAYOUT:
            value = getattr(self, name)
            out += [value] if length == 1 else value
        return bytes(v & 0xff for v in out).hex()
