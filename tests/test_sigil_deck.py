# SPDX-License-Identifier: BSD-3-Clause
"""SIGIL DECK: upstream card rules and fixtures, piles, replays and sound."""
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'games/sigil-deck'
sys.path.insert(0, str(ROOT / 'tests'))
from port_model import PLAY, CLEAR, LOST, PortModel, check_expectations, load_game_model  # noqa: E402

sd = load_game_model('sigil-deck')
EXPECTATIONS = json.loads((PROJECT / 'tests/expectations.json').read_text())
PROFILES = {p['profile']: p for p in EXPECTATIONS['runtime']['profiles']}


def seed_of(profile):
    return bytes.fromhex(PROFILES[profile]['expect']['memory']['state'])[25]


# every run starts from the emulator's seed; a retry reseeds (the second seed)
SEEDS = [seed_of('synthetic-start'), seed_of('synthetic-lost-retry')]
FIELDS = ('hp', 'shield', 'energy', 'enemy_hp', 'enemy_shield', 'poison', 'weak', 'vulnerable',
          'strength', 'thorns', 'echo', 'retain')


def make(seeds=None):
    sd.SigilDeck.ORIGINS = seeds or SEEDS
    return PortModel(sd.SigilDeck(), sd.LEVELS, False)


def card_result(before, card):
    """Upstream replay.py card_result (attack, block and the specials)."""
    s = dict(before)
    _, cost, attack, block, special, value, _, _ = card
    s['energy'] -= cost
    if attack:
        attack += s['strength']
        if special == 12 and s['enemy_hp'] <= 12:
            attack += 12
        if s['echo']:
            attack *= 2
            s['echo'] = 0
        if s['vulnerable']:
            attack += attack // 2
        absorbed = min(s['enemy_shield'], attack)
        s['enemy_shield'] -= absorbed
        s['enemy_hp'] = max(0, s['enemy_hp'] - (attack - absorbed))
    s['shield'] = min(99, s['shield'] + block)
    if special == 1:
        s['hp'] = min(60, s['hp'] + value)
    elif special == 2:
        s['energy'] = min(9, s['energy'] + value)
    elif special == 3:
        s['poison'] = min(99, s['poison'] + value)
    elif special == 4:
        s['energy'] += 1
    elif special == 5:
        s['thorns'] += value
    elif special == 6:
        s['vulnerable'] = 2
    elif special == 7:
        s['echo'] = 1
    elif special == 8:
        s['retain'] = 1
    elif special == 9:
        s['strength'] = min(20, s['strength'] + value)
    elif special == 10:
        s['weak'] = 2
    return s


def fixture(card=0, **changes):
    """check_rules.py's fixture: a four-card deck, three cards to draw."""
    port = make()
    port.key(13)
    game = port.game
    values = dict(hp=31, shield=7, energy=3, enemy_hp=80, enemy_shield=5, poison=4, weak=1,
                  vulnerable=1, strength=2, thorns=3, echo=1, retain=0, deck_count=4,
                  draw_count=3, discard_count=0, exhaust_count=0, selected=0, intent=0)
    values.update(changes)
    for key, value in values.items():
        setattr(game, key, value)
    game.deck[:4] = [card, 0, 1, 2]
    game.draw[:3] = [0, 1, 2]
    game.hand = [card, 255, 255, 255]
    return game, port


def state(game):
    return {k: getattr(game, k) for k in FIELDS}


def conserved(case, game):
    piles = Counter(c for c in game.hand if c != 255)
    for pile, count in (('draw', 'draw_count'), ('discard', 'discard_count'),
                        ('exhaust', 'exhaust_count')):
        piles.update(getattr(game, pile)[:getattr(game, count)])
    case.assertEqual(piles, Counter(game.deck[:game.deck_count]))


class SigilDeckRuleTests(unittest.TestCase):
    def test_data_matches_upstream(self):
        self.assertEqual((len(sd.data.CARDS), len(sd.data.ENEMIES), len(sd.data.MONSTERS)),
                         (24, 8, 8))
        self.assertEqual(sd.data.ENEMIES[7], ('VOID SOVEREIGN', 61, 10, 8))
        self.assertEqual(sd.data.CARDS[23][:7], ('FINISH', 1, 4, 0, 12, 12, 0))

    def test_every_card_like_check_rules(self):
        for card_id, card in enumerate(sd.data.CARDS):
            with self.subTest(card=card[0]):
                game, _ = fixture(card_id)
                game.turn = 1
                expected = card_result(state(game), card)
                game.act(5)
                self.assertEqual(state(game), expected)
                conserved(self, game)
                self.assertEqual((game.exhaust_count, game.discard_count),
                                 (card[6], 1 - card[6]))
                drawn = 1 if card[4] == 4 else 2 if card[4] == 11 else 0
                self.assertEqual(sum(c != 255 for c in game.hand), drawn)
                if drawn:
                    self.assertNotIn(card_id, game.hand)

    def test_energy_caps_and_finisher(self):
        game, _ = fixture(20, energy=2)
        before = (state(game), list(game.hand))
        game.act(5)
        self.assertEqual((state(game), game.hand), before)
        for card, field, start, cap in ((21, 'shield', 98, 99), (19, 'hp', 59, 60),
                                        (15, 'strength', 19, 20), (22, 'poison', 98, 99)):
            game, _ = fixture(card, **{field: start})
            game.act(5)
            self.assertEqual(getattr(game, field), cap)
        for hp, expected in ((12, 0), (13, 9)):
            game, _ = fixture(23, enemy_hp=hp, enemy_shield=0, strength=0, vulnerable=0, echo=0)
            game.act(5)
            self.assertEqual(game.enemy_hp, expected)

    def test_enemy_intents_and_statuses(self):
        for intent in range(3):
            for retain in (0, 1):
                game, _ = fixture(intent=intent, retain=retain)
                expected = state(game)
                expected['enemy_shield'] = 0
                expected['enemy_hp'] -= expected['poison']
                expected['poison'] -= 1
                if intent == 1:
                    expected['enemy_shield'] = game.enemy_guard
                else:
                    incoming = max(0, game.enemy_attack + (2 if intent == 2 else 0) - 3)
                    absorbed = min(expected['shield'], incoming)
                    expected['shield'] -= absorbed
                    expected['hp'] -= incoming - absorbed
                    expected['enemy_hp'] -= expected['thorns']
                expected['weak'] -= 1
                expected['vulnerable'] -= 1
                if not retain:
                    expected['shield'] = 0
                expected.update(thorns=0, retain=0, energy=3)
                game.selected = 4
                game.act(5)
                self.assertEqual(state(game), expected, (intent, retain))
                conserved(self, game)

    def test_defeat_first_poison_victory_rest_and_exhaust(self):
        game, port = fixture(0, enemy_hp=1, enemy_shield=0, hp=10, shield=0, poison=0,
                             thorns=1, weak=0)
        game.enemy_attack = 20
        game.selected = 4
        game.act(5)
        self.assertEqual((port.mode, game.hp, game.enemy_hp), (LOST, 0, 0))
        game, port = fixture(0, enemy_hp=1, poison=1, hp=1, shield=0, weak=0)
        game.selected = 4
        game.act(5)
        self.assertEqual((game.sub, game.hp, len(set(game.rewards))), (sd.REWARD, 1, 3))
        game.act(3)
        game.act(5)
        self.assertEqual((game.hp, game.battle, game.exhaust_count), (15, 1, 0))
        game, port = fixture(18, enemy_hp=1, poison=1, hp=40)
        game.act(5)
        self.assertEqual(game.exhaust_count, 1)
        game.selected = 4
        game.act(5)
        game.selected = 3
        game.act(5)
        self.assertEqual((game.exhaust_count, game.battle), (0, 1))
        conserved(self, game)

    def test_data_include_is_generated(self):
        result = subprocess.run([sys.executable, str(PROJECT / 'tests/make_data.py'), '--check'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


class SigilDeckExpectationTests(unittest.TestCase):
    def memory(self, name):
        return PROFILES[name]['expect']['memory']

    def test_replays_are_model_predictions(self):
        check_expectations(self, EXPECTATIONS, make)

    def test_ten_battles_and_retry(self):
        state_bytes = bytes.fromhex(self.memory('synthetic-ten-battles')['state'])
        self.assertEqual((self.memory('synthetic-ten-battles')['mode'], state_bytes[2]),
                         (f'{CLEAR:02x}', 9))
        self.assertEqual(self.memory('synthetic-lost')['mode'], f'{LOST:02x}')
        self.assertEqual(self.memory('synthetic-lost-retry')['mode'], f'{PLAY:02x}')

    def test_three_voice_title_and_jingles_and_silent_exit(self):
        for name in ('synthetic-title', 'synthetic-first-win', 'synthetic-lost',
                     'synthetic-ten-battles'):
            self.assertEqual(PROFILES[name]['expect']['pcm']['minimum_peak'], 21000)
        memory = self.memory('synthetic-exit')
        self.assertEqual([memory[f'channel-{c}'] for c in 'cdf'], ['00'] * 3)


if __name__ == '__main__':
    unittest.main()
