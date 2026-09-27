# SPDX-License-Identifier: BSD-3-Clause
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from ci_plan import git_paths, select, validate_registry
from check_repository import check


def target(name, kind='game', deps=()):
    root = ('sdk/' if kind == 'sdk' else 'games/') + name
    return {'id': name, 'kind': kind, 'depends_on': list(deps),
            'project': root, 'runner': 'jr200-project',
            'build_inputs': [root + '/src/**', root + '/assets/**', root + '/build.json'],
            'test_inputs': [root + '/tests/**'],
            'doc_inputs': [root + '/README.md', root + '/game.json', root + '/media/**']}


def registry():
    return {'schema_version': 2, 'targets': [target('sound', 'sdk'),
            target('engine', 'sdk', ('sound',)), target('alpha', deps=('engine',)),
            target('beta')]}


class SelectionTests(unittest.TestCase):
    def test_docs_only(self):
        plan = select(registry(), ['README.md', 'docs/guide.md'])
        self.assertEqual(plan['build_candidates'], [])
        self.assertEqual(plan['test_candidates'], [])
        self.assertTrue(plan['docs'])

    def test_single_game(self):
        plan = select(registry(), ['games/alpha/src/main.asm'])
        self.assertEqual(plan['build_candidates'], ['alpha'])
        self.assertEqual(plan['test_candidates'], ['alpha'])

    def test_transitive_shared_dependency(self):
        self.assertEqual(select(registry(), ['sdk/sound/src/play.asm'])['build_candidates'],
                         ['alpha', 'engine', 'sound'])

    def test_game_test_only(self):
        p = select(registry(), ['games/alpha/tests/replay.json'])
        self.assertEqual(p['build_candidates'], [])
        self.assertEqual(p['test_candidates'], ['alpha'])

    def test_sdk_test_only(self):
        p = select(registry(), ['sdk/sound/tests/smoke.py'])
        self.assertEqual(p['build_candidates'], [])
        self.assertEqual(p['test_candidates'], ['sound'])

    def test_embedded_png_vs_gallery(self):
        self.assertEqual(select(registry(), ['games/alpha/assets/player.png'])['build_candidates'], ['alpha'])
        p = select(registry(), ['games/alpha/media/screen.png'])
        self.assertEqual(p['build_candidates'], [])
        self.assertTrue(p['wiki'])

    def test_declared_markdown_is_build_input(self):
        r = registry()
        r['targets'][2]['build_inputs'].append('docs/embedded.md')
        self.assertEqual(select(r, ['docs/embedded.md'])['build_candidates'], ['alpha'])

    def test_metadata_only(self):
        p = select(registry(), ['games/alpha/game.json'])
        self.assertEqual(p['build_candidates'], [])
        self.assertTrue(p['wiki'])

    def test_build_config(self):
        self.assertEqual(select(registry(), ['games/alpha/build.json'])['build_candidates'], ['alpha'])

    def test_wiki_generator(self):
        p = select(registry(), ['tools/wiki/render.py'])
        self.assertTrue(p['wiki'])
        self.assertEqual(p['build_candidates'], [])

    def test_unknown_fails_closed(self):
        p = select(registry(), ['new-tool.py'])
        self.assertEqual(len(p['build_candidates']), 4)
        self.assertEqual(p['unclassified_paths'], ['new-tool.py'])

    def test_policy_changes(self):
        for path in ('ci/targets.json', '.github/workflows/ci.yml', 'toolchain.lock.json',
                     'tools/game_project.py', 'rules/jr200.json',
                     'templates/minimal/src/main.asm', 'mk/game.mk'):
            self.assertEqual(len(select(registry(), [path])['build_candidates']), 4)

    def test_declared_runner_change_is_test_only(self):
        plan = select(registry(), ['emulator.lock.json'])
        self.assertEqual(plan['build_candidates'], [])
        self.assertEqual(len(plan['test_candidates']), 4)

    def test_runner_adapter_and_png_change_test_every_target(self):
        for path in ('tools/emulator_runner.py', 'tools/jr200_wasm_runner.mjs',
                     'tools/png_rgba.py', 'ci/runner.lock.json'):
            with self.subTest(path=path):
                plan = select(registry(), [path])
                self.assertEqual(plan['build_candidates'], [])
                self.assertEqual(len(plan['test_candidates']), 4)

    def test_empty_registry(self):
        p = select({'schema_version': 1, 'targets': []}, ['README.md'])
        self.assertEqual(p['build_candidates'], [])
        self.assertTrue(p['advisory_only'])

    def test_no_change_is_not_a_receipt(self):
        p = select(registry(), [])
        self.assertTrue(p['advisory_only'])
        self.assertNotIn('verified', p)
        self.assertEqual(p['test_candidates'], [])

    def test_force_full(self):
        self.assertEqual(len(select(registry(), [], True)['build_candidates']), 4)

    def test_duplicate_paths_are_stable(self):
        a = select(registry(), ['games/alpha/src/main.asm'])
        b = select(registry(), ['games/alpha/src/main.asm'] * 2)
        self.assertEqual(a, b)

    def test_multiple_owners(self):
        r = registry()
        r['targets'][2]['build_inputs'].append('shared/palette.json')
        r['targets'][3]['build_inputs'].append('shared/palette.json')
        self.assertEqual(select(r, ['shared/palette.json'])['build_candidates'], ['alpha', 'beta'])

    def test_reject_bad_graphs(self):
        bad = []
        r = registry(); r['targets'].append(copy.deepcopy(r['targets'][0])); bad.append(r)
        r = registry(); r['targets'][0]['depends_on'] = ['missing']; bad.append(r)
        r = registry(); r['targets'][0]['depends_on'] = ['alpha']; bad.append(r)
        r = registry(); r['targets'][0]['build_inputs'] = ['../private/**']; bad.append(r)
        r = registry(); r['targets'][0]['id'] = 'alpha;echo'; bad.append(r)
        r = registry(); r['schema_version'] = True; bad.append(r)
        for value in bad:
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_registry(value)

    def test_reject_unsafe_paths(self):
        for path in ('/tmp/private', '../secret', 'games/../secret', 'a\\b', 'C:/file', 'a\nfile'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                select(registry(), [path])

    def test_repository_presentation_changes_build_nothing(self):
        root = Path(__file__).resolve().parents[1]
        registered = json.loads((root / 'ci/targets.json').read_text(encoding='utf-8'))
        changed = ['tools/wiki/generate.py', 'tools/wiki/genres.json']
        for game in sorted(path.parents[1].name for path in root.glob('games/*/media/gallery.json')):
            changed += [f'games/{game}/README.md', f'games/{game}/media/gallery.json',
                        f'games/{game}/media/goal.webm', f'games/{game}/media/README.md']
        games = [path for path in root.glob('games/*/game.json')
                 if (path.parent / 'media/gallery.json').exists()]
        self.assertGreaterEqual(len(games), 9)
        self.assertEqual(len(changed), 2 + len(games) * 4)
        plan = select(registered, changed)
        self.assertEqual(plan['build_candidates'], [])
        self.assertEqual(plan['test_candidates'], [])
        self.assertEqual(plan['unclassified_paths'], [])
        self.assertTrue(plan['wiki'])
        self.assertEqual(select(registered, ['games/relic-dive/src/main.asm'])[
            'build_candidates'], ['relic-dive'])
        self.assertEqual(select(registered, ['games/seed-merge/src/main.asm'])[
            'build_candidates'], ['seed-merge'])
        self.assertEqual(select(registered, ['games/quiet-route/src/main.asm'])[
            'build_candidates'], ['quiet-route'])

    def test_initial_contract(self):
        check(Path(__file__).resolve().parents[1])

    def test_repository_accepts_registered_sample_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'AGENTS.md',
                         'docs/DEVELOPMENT.md', 'docs/CI.md', 'docs/JRASM.md',
                         'docs/PORTING.md', 'docs/PROJECTS.md', 'docs/RELEASE_AUDIT.md', 'docs/RUNNER.md',
                         'docs/WIKI.md', 'rules/README.md'):
                path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('x')
            source_root = Path(__file__).resolve().parents[1]
            shutil.copy2(source_root / 'rules/jr200.json', root / 'rules/jr200.json')
            shutil.copytree(source_root / 'templates/minimal', root / 'templates/minimal',
                            ignore=shutil.ignore_patterns('build'))
            shutil.copytree(source_root / 'sdk', root / 'sdk')
            shutil.copytree(source_root / 'samples', root / 'samples',
                            ignore=shutil.ignore_patterns('build'))
            (root / 'ci').mkdir(); (root / 'games').mkdir()
            for game in sorted((source_root / 'games').iterdir()):
                if game.is_dir():
                    shutil.copytree(game, root / 'games' / game.name,
                                    ignore=shutil.ignore_patterns('build'))
            shutil.copy2(source_root / 'ci/targets.json', root / 'ci/targets.json')
            shutil.copy2(source_root / 'ci/runner.lock.json', root / 'ci/runner.lock.json')
            shutil.copy2(source_root / 'emulator.lock.json', root / 'emulator.lock.json')
            fixture = root / 'tests/fixtures/jrasm/minimal.asm'
            fixture.parent.mkdir(parents=True); fixture.write_text('x')
            lock = json.loads((source_root / 'toolchain.lock.json').read_text())
            lock['jrasm']['fixture']['source'] = 'tests/fixtures/jrasm/minimal.asm'
            lock['jrasm']['fixture']['inputs'] = {
                'tests/fixtures/jrasm/minimal.asm': hashlib.sha256(b'x').hexdigest()
            }
            (root / 'toolchain.lock.json').write_text(json.dumps(lock))
            shutil.copy2(source_root / 'games/catalog.json', root / 'games/catalog.json')
            check(root)
            targets = json.loads((root / 'ci/targets.json').read_text())
            targets['targets'][0]['project'] = 'templates/missing'
            (root / 'ci/targets.json').write_text(json.dumps(targets))
            with self.assertRaisesRegex(ValueError, '[Pp]roject'):
                check(root)


class GitDiffTests(unittest.TestCase):
    def test_deleted_renamed_and_initial_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL).decode().strip()
            git('init'); git('config', 'user.email', 'test@example.invalid'); git('config', 'user.name', 'Test')
            (root / 'old.asm').write_text('nop\n'); (root / 'removed.asm').write_text('rts\n')
            git('add', 'old.asm', 'removed.asm'); git('commit', '-m', 'base'); base = git('rev-parse', 'HEAD')
            (root / 'old.asm').rename(root / 'new.asm'); (root / 'removed.asm').unlink()
            git('add', '-A'); git('commit', '-m', 'rename and delete')
            self.assertEqual(sorted(git_paths(root, base)), ['new.asm', 'old.asm', 'removed.asm'])
            self.assertEqual(git_paths(root, '0' * 40), ['new.asm'])
            self.assertEqual(git_paths(root, ''), ['new.asm'])
            with self.assertRaises(ValueError):
                git_paths(root, '--help')
            with self.assertRaises(subprocess.CalledProcessError):
                git_paths(root, 'f' * 40)


if __name__ == '__main__':
    unittest.main()
