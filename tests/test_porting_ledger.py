# SPDX-License-Identifier: BSD-3-Clause
"""Static checks for the JR100dev porting ledger; not a port or playtest."""
from collections import Counter
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / 'docs/porting/jr100-ledger.json'
GENRES = ['puzzle', 'tabletop', 'tactics', 'action', 'exploration', 'management']
WAVE1 = {'lumen-cross': 21, 'corner-crown': 22, 'circuit-works': 23,
         'hearth-zero': 24, 'brick-pulse': 25, 'relic-dive': 14}


class PortingLedgerTests(unittest.TestCase):
    def setUp(self):
        self.ledger = json.loads(LEDGER.read_text(encoding='utf-8'))
        self.games = self.ledger['games']

    def test_upstream_is_pinned(self):
        upstream = self.ledger['upstream']
        self.assertEqual(upstream['repository'], 'https://github.com/zabaglione/jr100dev')
        self.assertRegex(upstream['revision'], r'^[0-9a-f]{40}$')
        self.assertEqual(set(upstream['inputs']),
                         {'collection.json', 'library.json', 'SOURCES.md'})
        for digest in upstream['inputs'].values():
            self.assertRegex(digest, r'^[0-9a-f]{64}$')
        self.assertTrue(self.ledger['assessment'].startswith('metadata'))

    def test_all_51_games_are_unique_and_classified(self):
        self.assertEqual(len(self.games), 51)
        for key in ('id', 'jr100_directory', 'title'):
            values = [game[key] for game in self.games]
            self.assertEqual(len(values), len(set(values)), key)
        self.assertEqual(self.ledger['genres'], GENRES)
        self.assertEqual(set(Counter(g['genre'] for g in self.games)), set(GENRES))
        methods = Counter(g['source_method'] for g in self.games)
        self.assertEqual(methods, {'rules': 44, 'asm': 7})
        for game in self.games:
            self.assertRegex(game['id'], r'^[a-z0-9]+(-[a-z0-9]+)*$')
            self.assertEqual(game['id'], game['jr100_directory'].replace('_', '-'))
            self.assertIn(game['timing'], ('turn', 'realtime'))
            self.assertIn(game['difficulty'], ('low', 'medium', 'high'))
            self.assertTrue(game['summary_ja'])
            self.assertTrue(game['sdk_needs'])
            if game['source_method'] == 'asm':
                self.assertEqual(game['aux_sources'], [])

    def test_wave_boundaries(self):
        wave1 = {g['id']: g for g in self.games if g['wave'] == 1}
        self.assertEqual({k: v['issue'] for k, v in wave1.items()}, WAVE1)
        self.assertEqual({g['genre'] for g in wave1.values()}, set(GENRES))
        for game in wave1.values():
            self.assertEqual(game['jr200_project'], 'games/' + game['id'])
            self.assertIn(game['status'], ('planned', 'ported-dev', 'ported'))
        wave2 = [g for g in self.games if g['wave'] == 2]
        self.assertEqual(len(wave2), 45)
        for game in wave2:
            stage = (62 if game['source_method'] == 'asm'
                     else 61 if game['timing'] == 'realtime'
                     else 59 if game['difficulty'] == 'low' else 60)
            self.assertEqual(game['issue'], stage, game['id'])
            self.assertIn(game['status'], ('planned', 'ported-dev', 'ported'))
            expected = None if game['status'] == 'planned' else 'games/' + game['id']
            self.assertEqual(game['jr200_project'], expected, game['id'])
        self.assertEqual(Counter(g['issue'] for g in wave2), {59: 20, 60: 8, 61: 11, 62: 6})
        self.assertEqual([s['id'] for s in self.ledger['separate']], ['side-catch'])
        self.assertNotIn('side-catch', {g['id'] for g in self.games})

    def test_ported_projects_exist(self):
        for game in self.games:
            if game['status'] in ('ported-dev', 'ported'):
                self.assertTrue((ROOT / game['jr200_project'] / 'UPSTREAM.md').is_file())

    def test_status_matches_projects_and_catalog(self):
        catalog = json.loads((ROOT / 'games/catalog.json').read_text(encoding='utf-8'))
        verified = {g['id'] for g in catalog['games'] if g['status'] == 'verified'}
        projects = {path.parent.name for path in ROOT.glob('games/*/UPSTREAM.md')}
        for game in self.games:
            with self.subTest(game=game['id']):
                self.assertEqual(game['status'] == 'ported', game['id'] in verified)
                self.assertEqual(game['status'] != 'planned', game['id'] in projects)

    def test_porting_contract_names_forbidden_carryover(self):
        text = (ROOT / 'docs/PORTING.md').read_text(encoding='utf-8')
        for word in ('PRG', 'VIA', 'ADX', 'CTRL+C', 'コンパイラ'):
            self.assertIn(word, text)
        for name in WAVE1:
            title = name.upper().replace('-', ' ')
            self.assertTrue(re.search(re.escape(title), text), title)


if __name__ == '__main__':
    unittest.main()
