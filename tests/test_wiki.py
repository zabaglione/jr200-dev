# SPDX-License-Identifier: BSD-3-Clause
import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from wiki.generate import (WikiError, apply_files, render_pages,
                           require_git_worktree, sync_plan)


ROOT = Path(__file__).resolve().parents[1]
GENRE_PAGES = ['Genre-Action.md', 'Genre-Exploration.md', 'Genre-Management.md',
               'Genre-Puzzle.md', 'Genre-Tabletop.md', 'Genre-Tactics.md']
BASE_PAGES = ['All-Games.md', 'Controls.md', 'Games.md', 'Home.md', 'Licenses.md',
              'Play.md', 'Presentation.md', 'Quality-Review.md', '_Sidebar.md', *GENRE_PAGES]
DEVELOPMENT = {'brick-pulse': 'Genre-Action', 'circuit-works': 'Genre-Tactics',
               'corner-crown': 'Genre-Tabletop', 'hearth-zero': 'Genre-Management',
               'lumen-cross': 'Genre-Puzzle', 'relic-dive': 'Genre-Exploration'}


def make_cjr(payload=b'\x01\x39', start=0x1000):
    name = b'SIDE-CATCH'.ljust(16, b'\0')
    header = bytearray(b'\x02\x2a\x00\x1a\xff\xff' + name + b'\x01\x00' + b'\xff' * 8)
    header.append(sum(header) & 0xff)
    block = bytearray((2, 0x2a, 1, len(payload), start >> 8, start & 0xff))
    block.extend(payload)
    block.append(sum(block) & 0xff)
    end = start + len(payload)
    return bytes(header + block + bytes((2, 0x2a, 0xff, 0xff, end >> 8, end & 0xff)))


class WikiFixture:
    def __init__(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / 'games').mkdir()
        shutil.copytree(ROOT / 'games/side-catch', self.root / 'games/side-catch',
                        ignore=shutil.ignore_patterns('build'))
        shutil.copytree(ROOT / 'sdk', self.root / 'sdk')
        shutil.copytree(ROOT / 'rules', self.root / 'rules')
        shutil.copytree(ROOT / 'docs', self.root / 'docs')
        (self.root / 'samples').mkdir()
        shutil.copy2(ROOT / 'LICENSE', self.root / 'LICENSE')
        self.metadata_path = self.root / 'games/side-catch/game.json'
        self.metadata = json.loads(self.metadata_path.read_text(encoding='utf-8'))
        self.artifact = make_cjr()
        self.artifact_sha256 = hashlib.sha256(self.artifact).hexdigest()
        self.expectations_sha256 = hashlib.sha256(
            (self.root / 'games/side-catch/tests/expectations.json').read_bytes()
        ).hexdigest()
        screenshot = self.root / 'games/side-catch/media/screenshot.png'
        self.screenshot_sha256 = hashlib.sha256(screenshot.read_bytes()).hexdigest()
        self.framebuffer_sha256 = (
            '62f18ea1658dbbe8c53cf90b104b727134d3c2cec71a45ffc8fb53607c69b575')
        self.package = (self.root / 'games/side-catch/build/package/'
                        'side-catch-0.1.0.zip')
        self.catalog = {
            'schema_version': 2,
            'games': [{
                'id': 'side-catch', 'project': 'games/side-catch',
                'status': 'candidate', 'version': '0.1.0', 'genre': 'action',
                'artifact_sha256': self.artifact_sha256,
                'package': {'file': 'side-catch-0.1.0.zip', 'sha256': '0' * 64,
                            'release_url': None},
                'wiki': {'slug': 'side-catch', 'publish': False, 'play_url': None,
                         'screenshot': {
                             'file': 'media/screenshot.png',
                             'sha256': self.screenshot_sha256,
                             'framebuffer_sha256': self.framebuffer_sha256,
                             'profile': 'synthetic-screenshot',
                         }},
            }],
        }
        self.write_package()

    def close(self):
        self.temporary.cleanup()

    def add_development_games(self):
        for project in sorted(ROOT.glob('games/*/game.json')):
            name = project.parent.name
            if name != 'side-catch':
                shutil.copytree(project.parent, self.root / 'games' / name,
                                ignore=shutil.ignore_patterns('build', '__pycache__'))
                if name == 'relic-dive':
                    metadata_path = self.root / 'games' / name / 'game.json'
                    metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
                    metadata['release']['status'] = 'draft'
                    metadata_path.write_text(json.dumps(metadata) + '\n', encoding='utf-8')

    def report(self, profile, mode, evidence, framebuffer='0' * 64):
        cassette = 'memory_injection' if mode == 'synthetic-injection' else 'normal'
        return {
            'schema_version': 1, 'project': 'side-catch', 'profile': profile,
            'mode': mode, 'artifact_sha256': self.artifact_sha256,
            'expectations_sha256': self.expectations_sha256,
            'runner': {'version': '0.2.0', 'source_revision': '1' * 40},
            'result': {
                'status': 'passed', 'profile': profile, 'mode': mode,
                'evidence': evidence, 'artifact_sha256': self.artifact_sha256,
                'framebuffer_sha256': framebuffer, 'hardware': 'not_run',
            },
            'verification': {'emulator': 'passed', 'hardware': 'not_run',
                             'cassette_path': cassette},
        }

    def write_package(self, extra_name=None, ready=False, source_commit=None):
        reports = [
            self.report('synthetic-ci', 'synthetic-injection', 'emulator'),
            self.report('synthetic-screenshot', 'synthetic-injection', 'emulator',
                        self.framebuffer_sha256),
            self.report('local-rom-basic-return', 'rom-cassette',
                        'emulator_with_local_rom'),
        ]
        release_profiles = []
        project = self.root / 'games/side-catch'
        license_id = self.metadata['license']
        entries = {
            'LICENSE': (project / 'LICENSE' if license_id != 'BSD-3-Clause'
                        else self.root / 'LICENSE').read_bytes(),
            'README.md': (project / 'README.md').read_bytes(),
            'game.json': self.metadata_path.read_bytes(),
            'side-catch.cjr': self.artifact,
        }
        if license_id != 'BSD-3-Clause':
            entries['THIRD_PARTY_NOTICES.md'] = (
                project / 'THIRD_PARTY_NOTICES.md').read_bytes()
            entries['LICENSES/BSD-3-Clause.txt'] = (self.root / 'LICENSE').read_bytes()
        for report in reports:
            name = f'VERIFICATION/{report["profile"]}.json'
            payload = (json.dumps(report, sort_keys=True) + '\n').encode('utf-8')
            entries[name] = payload
            release_profiles.append({
                'profile': report['profile'], 'mode': report['mode'],
                'evidence': report['result']['evidence'], 'report': name,
                'report_sha256': hashlib.sha256(payload).hexdigest(),
            })
        release = {
            'schema_version': 1, 'project': 'side-catch', 'version': '0.1.0',
            'status': self.metadata['release']['status'],
            'artifact': {'file': 'side-catch.cjr',
                         'sha256': self.artifact_sha256,
                         'size': len(self.artifact)},
            'source': {'repository': 'https://github.com/zabaglione/jr200-dev',
                       'commit': source_commit or '2' * 40,
                       'tree_state': 'clean' if ready else 'dirty',
                       'snapshot_sha256': '3' * 64,
                       'expectations_sha256': self.expectations_sha256},
            'compatibility': {'sdk_contract': 1, 'runner_contract': 1,
                              'runner_version': '0.2.0',
                              'emulator_source_revision': '1' * 40,
                              'jrasm_version': '1.0.2',
                              'jrasm_revision': '4' * 40},
            'verification': {'runtime_profiles': release_profiles,
                             'hardware': 'not_run'},
            'license': license_id, 'wav': 'not-required',
            'publication': self.metadata['release']['publication'],
            'release_ready': ready,
        }
        build_report = {
            'schema_version': 1, 'project': 'side-catch',
            'artifact': {'sha256': self.artifact_sha256},
            'toolchain': {'version': '1.0.2', 'revision': '4' * 40},
            'verification': {'assembler': 'passed', 'cjr_layout': 'passed'},
        }
        entries['BUILD_REPORT.json'] = (
            json.dumps(build_report, sort_keys=True) + '\n').encode()
        entries['RELEASE.json'] = (json.dumps(release, sort_keys=True) + '\n').encode()
        entries['SHA256SUMS'] = ''.join(
            f'{hashlib.sha256(payload).hexdigest()}  {name}\n'
            for name, payload in sorted(entries.items())
        ).encode('ascii')
        if extra_name is not None:
            entries[extra_name] = b'unsafe'
        self.package.parent.mkdir(parents=True, exist_ok=True)
        prefix = 'side-catch-0.1.0/'
        with zipfile.ZipFile(self.package, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, payload in sorted(entries.items()):
                archive.writestr(prefix + name, payload)
        self.catalog['games'][0]['package']['sha256'] = hashlib.sha256(
            self.package.read_bytes()).hexdigest()
        self.write_catalog()

    def write_catalog(self):
        (self.root / 'games/catalog.json').write_text(
            json.dumps(self.catalog, indent=2) + '\n', encoding='utf-8')


class WikiGenerationTests(unittest.TestCase):
    def setUp(self):
        self.fixture = WikiFixture()

    def tearDown(self):
        self.fixture.close()

    def test_candidate_requires_explicit_preview_and_includes_verified_image(self):
        public_files, public_games = render_pages(self.fixture.root, None, False)
        self.assertEqual(sorted(public_files), sorted(BASE_PAGES))
        self.assertEqual(public_games, [])
        files, games = render_pages(self.fixture.root, None, True)
        self.assertEqual(sorted(files), sorted(
            BASE_PAGES + ['Game-side-catch.md', 'media/side-catch.png']))
        page = files['Game-side-catch.md'].decode('utf-8')
        self.assertIn('非公開の候補版プレビュー', page)
        self.assertIn('media/side-catch.png', page)
        self.assertIn('物理JR-200での表示は未確認', page)
        self.assertNotIn('?game=side-catch', page)
        self.assertIn('https://zabaglione.github.io/jr200-web-emulator/', page)
        self.assertIn('CJRは手動で選択', page)
        self.assertIn('MLOAD', files['Play.md'].decode('utf-8'))
        self.assertLess(files['Play.md'].decode('utf-8').index('1. 作品別'),
                        files['Play.md'].decode('utf-8').index('2. 「02 起動データ」'))
        self.assertIn('検証済みの公開ゲームはまだありません',
                      public_files['Home.md'].decode('utf-8'))
        for name, content in public_files.items():
            if name.startswith('Genre-'):
                self.assertIn('公開作品準備中', content.decode('utf-8'))
        self.assertEqual(files['media/side-catch.png'],
                         (self.fixture.root / 'games/side-catch/media/screenshot.png').read_bytes())
        self.assertEqual([item['id'] for item in games], ['side-catch'])

    def test_candidate_can_reuse_a_named_verified_capture(self):
        project = self.fixture.root / 'games/side-catch'
        shutil.copyfile(project / 'media/screenshot.png',
                        project / 'media/gameplay.png')
        self.fixture.catalog['games'][0]['wiki']['screenshot']['file'] = (
            'media/gameplay.png')
        self.fixture.write_catalog()
        files, _ = render_pages(self.fixture.root, None, True)
        self.assertEqual(files['media/side-catch.png'],
                         (project / 'media/gameplay.png').read_bytes())

    def test_candidate_rejects_unsafe_capture_path(self):
        self.fixture.catalog['games'][0]['wiki']['screenshot']['file'] = (
            'media/../screenshot.png')
        self.fixture.write_catalog()
        with self.assertRaisesRegex(WikiError, 'Invalid game catalog entry'):
            render_pages(self.fixture.root, None, True)

    def test_rejects_outer_hash_mismatch(self):
        self.fixture.catalog['games'][0]['package']['sha256'] = 'f' * 64
        self.fixture.write_catalog()
        with self.assertRaisesRegex(WikiError, 'package hash mismatch'):
            render_pages(self.fixture.root, None, True)

    def test_mit_sdk_package_requires_exact_license_and_notices(self):
        project = self.fixture.root / 'games/side-catch'
        self.fixture.metadata['license'] = 'MIT'
        self.fixture.metadata_path.write_text(
            json.dumps(self.fixture.metadata) + '\n', encoding='utf-8')
        (project / 'LICENSE').write_bytes((ROOT / 'games/relic-dive/LICENSE').read_bytes())
        sdk_inputs = json.loads((project / 'build.json').read_text(encoding='utf-8'))[
            'inputs']['sdk']
        notice = project / 'THIRD_PARTY_NOTICES.md'
        notice.write_text('BSD-3-Clause\n' + '\n'.join(sdk_inputs) + '\n',
                          encoding='utf-8')
        self.fixture.write_package()
        files, games = render_pages(self.fixture.root, None, True)
        self.assertEqual([game['id'] for game in games], ['side-catch'])
        self.assertIn('MIT', files['Game-side-catch.md'].decode('utf-8'))
        original_notice = notice.read_bytes()
        notice.write_text('BSD-3-Clause\n' + '\n'.join(sdk_inputs) + '\nchanged\n',
                          encoding='utf-8')
        with self.assertRaisesRegex(WikiError, 'license or notice mismatch'):
            render_pages(self.fixture.root, None, True)
        notice.write_bytes(original_notice)
        (project / 'LICENSE').write_text('changed MIT text\n', encoding='utf-8')
        with self.assertRaisesRegex(WikiError, 'license or notice mismatch'):
            render_pages(self.fixture.root, None, True)

    def test_presentation_only_changes_reuse_fixed_package(self):
        readme = self.fixture.root / 'games/side-catch/README.md'
        readme.write_text('# SIDE CATCH\n\nUpdated guide only.\n', encoding='utf-8')
        self.fixture.metadata['title'] = 'SIDE CATCH UPDATED'
        self.fixture.metadata['summary'] = 'Updated catalog copy without a game rebuild.'
        self.fixture.metadata['genre'] = 'puzzle'
        self.fixture.metadata_path.write_text(
            json.dumps(self.fixture.metadata) + '\n', encoding='utf-8')
        self.fixture.catalog['games'][0]['genre'] = 'puzzle'
        self.fixture.write_catalog()
        files, _ = render_pages(self.fixture.root, None, True)
        page = files['Game-side-catch.md'].decode('utf-8')
        self.assertIn('# SIDE CATCH UPDATED', page)
        self.assertIn('Updated guide only.', page)
        self.assertIn('[Home](Home) › [パズル](Genre-Puzzle) › SIDE CATCH UPDATED', page)
        self.assertIn('Game-side-catch', files['Genre-Puzzle.md'].decode('utf-8'))
        self.assertNotIn('Game-side-catch', files['Genre-Action.md'].decode('utf-8'))
        self.fixture.metadata['genre'] = 'arcade'
        self.fixture.metadata_path.write_text(
            json.dumps(self.fixture.metadata) + '\n', encoding='utf-8')
        self.fixture.catalog['games'][0]['genre'] = 'arcade'
        self.fixture.write_catalog()
        with self.assertRaisesRegex(WikiError, 'unknown genre'):
            render_pages(self.fixture.root, None, True)

    def test_rejects_unsafe_archive_member(self):
        self.fixture.write_package('../escape')
        with self.assertRaisesRegex(WikiError, 'unsafe path'):
            render_pages(self.fixture.root, None, True)

    def test_published_page_requires_clean_source_ancestry(self):
        self.fixture.metadata['release']['status'] = 'verified'
        self.fixture.metadata['release']['publication'] = 'published'
        self.fixture.metadata_path.write_text(
            json.dumps(self.fixture.metadata) + '\n', encoding='utf-8')
        item = self.fixture.catalog['games'][0]
        item['status'] = 'verified'
        item['wiki']['publish'] = True
        item['package']['release_url'] = (
            'https://github.com/zabaglione/jr200-dev/releases/download/'
            'v0.1.0/side-catch-0.1.0.zip')
        self.fixture.write_catalog()
        (self.fixture.root / '.gitignore').write_text('build/\n', encoding='utf-8')
        subprocess.check_call(['git', 'init'], cwd=self.fixture.root,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.check_call(['git', 'add', '.'], cwd=self.fixture.root)
        subprocess.check_call(
            ['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
             'commit', '-m', 'release source'], cwd=self.fixture.root,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        source_commit = subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=self.fixture.root, text=True).strip()
        self.fixture.write_package(ready=True, source_commit=source_commit)
        subprocess.check_call(['git', 'add', 'games/catalog.json'], cwd=self.fixture.root)
        subprocess.check_call(
            ['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
             'commit', '-m', 'catalog hash'], cwd=self.fixture.root,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        current_commit = subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=self.fixture.root, text=True).strip()
        with self.assertRaisesRegex(WikiError, 'release contract mismatch'):
            render_pages(self.fixture.root, None, False)
        files, games = render_pages(
            self.fixture.root, None, False, expected_commit=current_commit)
        self.assertIn('[固定パッケージをダウンロード]',
                      files['Game-side-catch.md'].decode('utf-8'))
        self.assertTrue(games[0]['publish'])
        self.assertIn('検証済みの公開ゲームを作品一覧から選べます',
                      files['Home.md'].decode('utf-8'))
        item['wiki']['play_url'] = (
            'https://zabaglione.github.io/jr200-web-emulator/?game=side-catch')
        self.fixture.write_catalog()
        linked_files, _ = render_pages(
            self.fixture.root, None, False, expected_commit=current_commit)
        self.assertIn(item['wiki']['play_url'],
                      linked_files['Game-side-catch.md'].decode('utf-8'))
        item['wiki']['play_url'] = (
            'https://example.test/?game=side-catch')
        self.fixture.write_catalog()
        with self.assertRaisesRegex(WikiError, 'Invalid game catalog'):
            render_pages(self.fixture.root, None, False, expected_commit=current_commit)

    def test_rejects_draft_and_structurally_broken_link(self):
        metadata = self.fixture.metadata
        metadata['release']['status'] = 'draft'
        self.fixture.metadata_path.write_text(
            json.dumps(metadata) + '\n', encoding='utf-8')
        self.fixture.catalog['games'][0]['status'] = 'draft'
        self.fixture.write_catalog()
        with self.assertRaisesRegex(WikiError, 'draft games'):
            render_pages(self.fixture.root, None, True)
        self.fixture.catalog['games'][0]['package']['release_url'] = 'http://invalid.test/a.zip'
        self.fixture.write_catalog()
        with self.assertRaisesRegex(WikiError, 'Invalid game catalog'):
            render_pages(self.fixture.root, None, True)

    def test_candidate_rejects_direct_game_link(self):
        self.fixture.catalog['games'][0]['wiki']['play_url'] = (
            'https://zabaglione.github.io/jr200-web-emulator/?game=side-catch')
        self.fixture.write_catalog()
        with self.assertRaisesRegex(WikiError, 'Invalid game catalog'):
            render_pages(self.fixture.root, None, True)

    def test_sync_updates_only_generated_files_and_preserves_handwritten_pages(self):
        files, _ = render_pages(self.fixture.root, None, True)
        wiki = self.fixture.root / 'wiki'
        wiki.mkdir()
        subprocess.check_call(['git', 'init'], cwd=wiki, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL)
        subprocess.check_call(
            ['git', 'remote', 'add', 'origin',
             'https://github.com/zabaglione/jr200-dev.wiki.git'], cwd=wiki)
        (wiki / 'Notes.md').write_text('handwritten\n', encoding='utf-8')
        (wiki / 'Game-old.md').write_text('old generated\n', encoding='utf-8')
        (wiki / '.jr200-generated.json').write_text(json.dumps({
            'schema_version': 2,
            'files': {'Game-old.md': hashlib.sha256(b'old generated\n').hexdigest()},
        }) + '\n', encoding='utf-8')
        subprocess.check_call(['git', 'add', '.'], cwd=wiki)
        subprocess.check_call(
            ['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
             'commit', '-m', 'fixture'], cwd=wiki, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL)
        require_git_worktree(wiki.resolve(), clean=True)
        plan = apply_files(wiki, files)
        self.assertEqual(plan['delete'], ['Game-old.md'])
        self.assertEqual((wiki / 'Notes.md').read_text(encoding='utf-8'), 'handwritten\n')
        self.assertFalse((wiki / 'Game-old.md').exists())
        second = sync_plan(wiki, files)
        self.assertEqual(second['add'] + second['update'] + second['delete'], [])
        self.assertEqual(second['unchanged'], sorted(files))
        (wiki / 'Home.md').write_text('manual edit\n', encoding='utf-8')
        with self.assertRaisesRegex(WikiError, 'locally modified'):
            sync_plan(wiki, files)
        with self.assertRaisesRegex(WikiError, 'must be clean'):
            require_git_worktree(wiki.resolve(), clean=True)

    def test_sync_refuses_unowned_generated_name_collision(self):
        files, _ = render_pages(self.fixture.root, None, True)
        wiki = self.fixture.root / 'collision'
        wiki.mkdir()
        (wiki / 'Home.md').write_text('handwritten home\n', encoding='utf-8')
        with self.assertRaisesRegex(WikiError, 'unowned Wiki file'):
            sync_plan(wiki, files)

    def test_initial_wiki_home_can_be_adopted_only_when_identical(self):
        files, _ = render_pages(self.fixture.root, None, False)
        wiki = self.fixture.root / 'initial-wiki'
        wiki.mkdir()
        (wiki / 'Home.md').write_bytes(files['Home.md'])
        plan = sync_plan(wiki, files)
        self.assertEqual(plan['unchanged'], ['Home.md'])
        self.assertEqual(plan['add'], sorted(set(BASE_PAGES) - {'Home.md'}))
        (wiki / 'Home.md').write_text('different\n', encoding='utf-8')
        with self.assertRaisesRegex(WikiError, 'unowned Wiki file'):
            sync_plan(wiki, files)


class SevenGamePreviewTests(unittest.TestCase):
    """The six-genre structure with one candidate and six development ports."""

    def setUp(self):
        self.fixture = WikiFixture()
        self.fixture.add_development_games()

    def tearDown(self):
        self.fixture.close()

    def render(self):
        return render_pages(self.fixture.root, None, True, include_development=True)

    def test_home_genres_all_games_and_pages_agree(self):
        files, games = self.render()
        self.assertEqual(sorted(item['id'] for item in games),
                         sorted([*DEVELOPMENT, 'side-catch']))
        self.assertEqual({item['id']: item['tier'] for item in games}['side-catch'],
                         'candidate')
        self.assertTrue(set(BASE_PAGES) <= set(files))
        home = files['Home.md'].decode('utf-8')
        all_games = files['All-Games.md'].decode('utf-8')
        for game, genre in {**DEVELOPMENT, 'side-catch': 'Genre-Action'}.items():
            page = files[f'Game-{game}.md'].decode('utf-8')
            self.assertIn(f'](Game-{game})', home)
            self.assertIn(f'](Game-{game})', all_games)
            self.assertIn(f'](Game-{game})', files[genre + '.md'].decode('utf-8'))
            for other in GENRE_PAGES:
                if other != genre + '.md':
                    self.assertNotIn(f'](Game-{game})', files[other].decode('utf-8'))
            self.assertIn(f'[Home](Home) › [', page)
            self.assertIn(f']({genre}) › ', page)
            self.assertEqual(page.count('\n# '), 0)
            self.assertIn(f'](Game-{game})', files['Controls.md'].decode('utf-8'))
            self.assertIn(f'](Game-{game})', files['Quality-Review.md'].decode('utf-8'))
        self.assertIn('| [アクション](Genre-Action) | 0 | 2 |', home)
        self.assertIn('| [探索](Genre-Exploration) | 0 | 1 |', home)
        self.assertIn('公開作品準備中', home)
        self.assertNotIn('?game=', ''.join(value.decode('utf-8')
                                           for name, value in files.items()
                                           if name.endswith('.md')))

    def test_development_pages_show_three_scenes_video_and_game_specific_controls(self):
        files, _ = self.render()
        for game in DEVELOPMENT:
            gallery = json.loads((self.fixture.root / 'games' / game /
                                  'media/gallery.json').read_text(encoding='utf-8'))
            page = files[f'Game-{game}.md'].decode('utf-8')
            images = re.findall(r'<img src="([^"]+)" alt="([^"]+)"', page)
            self.assertGreaterEqual(len(images), 3)
            for source, alt in images:
                self.assertIn(source, files)
                self.assertTrue(alt.strip())
            video = f'media/{game}-goal.webm'
            self.assertEqual(files[video], (self.fixture.root / 'games' / game / 'media' /
                                            gallery['video']['file']).read_bytes())
            self.assertIn(f']({video})', page)
            self.assertIn('開発中の版のプレビュー', page)
            self.assertIn('### 操作', page)
            self.assertIn('| 物理JR-200 | 未実施 |', page)
        relic = files['Game-relic-dive.md'].decode('utf-8')
        self.assertIn('`S` | その場で1ターン待つ', relic)
        self.assertIn('ジョイスティックは', relic)
        self.assertIn('`A` / `D`（押し続ける）', files['Game-brick-pulse.md'].decode('utf-8'))

    def test_rendering_is_deterministic_and_sync_reruns_without_changes(self):
        first, _ = self.render()
        second, _ = self.render()
        self.assertEqual(first, second)
        output = self.fixture.root / 'preview'
        apply_files(output, first)
        plan = sync_plan(output, second)
        self.assertEqual(plan['add'] + plan['update'] + plan['delete'], [])
        public, _ = render_pages(self.fixture.root, None, False)
        plan = sync_plan(output, public)
        self.assertIn('Game-relic-dive.md', plan['delete'])
        self.assertIn('media/relic-dive-goal.webm', plan['delete'])

    def test_development_preview_is_never_synchronized(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / 'tools/wiki/generate.py'), '--root',
             str(self.fixture.root), '--include-development', 'sync', '--wiki',
             str(self.fixture.root / 'wiki')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('cannot be synchronized', result.stderr)

    def test_detects_stale_gallery_broken_links_and_missing_sections(self):
        media = self.fixture.root / 'games/relic-dive/media'
        original = (media / 'combat.png').read_bytes()
        (media / 'combat.png').write_bytes((media / 'title.png').read_bytes())
        with self.assertRaisesRegex(WikiError, 'gallery scene combat'):
            self.render()
        (media / 'combat.png').write_bytes(original)
        video = media / 'goal.webm'
        video.write_bytes(video.read_bytes() + b'\0')
        with self.assertRaisesRegex(WikiError, 'video hash mismatch'):
            self.render()
        video.write_bytes(video.read_bytes()[:-1])
        readme = self.fixture.root / 'games/relic-dive/README.md'
        text = readme.read_text(encoding='utf-8')
        readme.write_text(text + '\n[missing](MISSING.md)\n', encoding='utf-8')
        with self.assertRaisesRegex(WikiError, 'broken repository link'):
            self.render()
        readme.write_text(text + '\n[play](https://zabaglione.github.io/pyjr100emu/)\n',
                          encoding='utf-8')
        with self.assertRaisesRegex(WikiError, 'JR-100 play URL'):
            self.render()
        readme.write_text(text.replace('## 操作', '## Keys'), encoding='utf-8')
        with self.assertRaisesRegex(WikiError, 'README lacks sections: 操作'):
            self.render()
        readme.write_text(text, encoding='utf-8')
        metadata_path = self.fixture.root / 'games/relic-dive/game.json'
        metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
        metadata['release']['status'] = 'candidate'
        metadata_path.write_text(json.dumps(metadata) + '\n', encoding='utf-8')
        with self.assertRaisesRegex(WikiError, 'outside the catalog'):
            self.render()


if __name__ == '__main__':
    unittest.main()
