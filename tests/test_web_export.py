# SPDX-License-Identifier: BSD-3-Clause
"""Web catalog export: approval, verification state, immutability, one-game scope."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import web_export  # noqa: E402
from test_wiki import WikiFixture  # noqa: E402

OTHER = {'id': 'other-game', 'title': 'OTHER', 'version': '1.0.0',
         'path': 'games/other-game/1.0.0/other-game.cjr', 'sha256': 'a' * 64,
         'runCommand': 'A=USR($1000)'}


class WebExportTests(unittest.TestCase):
    def setUp(self):
        self.fixture = WikiFixture()
        self.root = self.fixture.root
        self.temp = tempfile.TemporaryDirectory()
        self.out = Path(self.temp.name)
        self.site_catalog = self.out / 'site-catalog.json'
        self.site_catalog.write_text(json.dumps({'schemaVersion': 1, 'games': [OTHER]}))
        self.commit = self.git_commit()

    def tearDown(self):
        self.fixture.close()
        self.temp.cleanup()

    def git_commit(self):
        import subprocess
        run = lambda *a: subprocess.run(['git', *a], cwd=self.root, check=True,  # noqa: E731
                                        capture_output=True, text=True).stdout.strip()
        run('init', '-q')
        run('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit',
            '-q', '--allow-empty', '-m', 'x')
        return run('rev-parse', 'HEAD')

    def publish(self, status='verified', ready=True):
        entry = self.fixture.catalog['games'][0]
        self.fixture.metadata['release']['status'] = status
        self.fixture.metadata['release']['publication'] = 'published'
        self.fixture.metadata_path.write_text(json.dumps(self.fixture.metadata, indent=2))
        entry['status'] = status
        entry['wiki']['publish'] = True
        entry['package']['release_url'] = (
            'https://github.com/zabaglione/jr200-dev/releases/download/'
            'side-catch-0.1.0/side-catch-0.1.0.zip')
        self.fixture.write_package(ready=ready, source_commit=self.commit)

    def plan(self, approval='side-catch@0.1.0', site=None, version='0.1.0',
             preview=False):
        return web_export.plan_export(self.root, 'side-catch', version, approval,
                                      self.site_catalog, site,
                                      expected_commit=self.commit, preview=preview)

    def test_exports_verified_version_and_keeps_other_games(self):
        self.publish()
        plan = self.plan()
        self.assertEqual(plan['catalog_action'], 'add')
        self.assertEqual(plan['catalog']['games'][0], OTHER)
        entry = plan['catalog']['games'][1]
        self.assertEqual(entry['path'], 'games/side-catch/0.1.0/side-catch.cjr')
        self.assertEqual(entry['runCommand'], 'A=USR($1000)')
        cjr = plan['files'][entry['path']]
        self.assertEqual(hashlib.sha256(cjr).hexdigest(), entry['sha256'])
        self.assertIn('games/side-catch/0.1.0/LICENSE.txt', plan['files'])
        web_export.write_export(plan, self.out / 'stage')
        manifest = json.loads((self.out / 'stage/export-manifest.json').read_text())
        self.assertEqual(set(manifest['files']), set(plan['files']))
        self.assertEqual(manifest['schema_version'], 2)
        self.assertEqual(manifest['mode'], 'release')
        self.assertEqual(manifest['base_catalog_sha256'], hashlib.sha256(
            self.site_catalog.read_bytes()).hexdigest())
        self.assertEqual(manifest['source']['cjr_size'], len(cjr))
        self.assertEqual(manifest['source']['runner_contract'], 1)
        staged = {p.relative_to(self.out / 'stage').as_posix()
                  for p in (self.out / 'stage').rglob('*') if p.is_file()}
        self.assertFalse({p for p in staged if p.endswith(('.zip', '.rom', '.asm'))})

    def test_requires_matching_explicit_approval(self):
        self.publish()
        for approval in ('', 'side-catch', 'side-catch@0.2.0', 'other@0.1.0'):
            with self.subTest(approval=approval), self.assertRaises(web_export.ExportError):
                self.plan(approval=approval)

    def test_title_marker_is_versioned_in_catalog_and_notice(self):
        self.publish()
        plan = web_export.plan_export(
            self.root, 'side-catch', '0.1.0', 'side-catch@0.1.0',
            self.site_catalog, expected_commit=self.commit,
            title_marker='SIDE CATCH')
        self.assertEqual(plan['entry']['titleMarker'], 'SIDE CATCH')
        self.assertEqual(plan['notice']['title_marker'], 'SIDE CATCH')
        with self.assertRaisesRegex(web_export.ExportError, 'Title marker'):
            web_export.plan_export(
                self.root, 'side-catch', '0.1.0', 'side-catch@0.1.0',
                self.site_catalog, expected_commit=self.commit,
                title_marker='bad\nmarker')

    def test_rejects_candidate_and_unpublished_versions(self):
        with self.assertRaisesRegex(web_export.ExportError, 'only verified'):
            self.plan()

    def test_candidate_preview_is_local_only(self):
        self.fixture.write_package(ready=True, source_commit=self.commit)
        plan = self.plan(preview=True)
        self.assertEqual(plan['mode'], 'preview')
        self.assertEqual(plan['notice']['mode'], 'preview')
        self.assertEqual(plan['notice']['license'], 'BSD-3-Clause')
        web_export.write_export(plan, self.out / 'preview')
        manifest = json.loads((self.out / 'preview/export-manifest.json').read_text())
        self.assertEqual(manifest['mode'], 'preview')

    def test_requires_expected_commit_and_rejects_symlink_output(self):
        self.publish()
        with self.assertRaisesRegex(web_export.ExportError, 'expected source commit'):
            web_export.plan_export(self.root, 'side-catch', '0.1.0',
                                   'side-catch@0.1.0', self.site_catalog)
        target = self.out / 'linked-output'
        target.symlink_to(self.out, target_is_directory=True)
        with self.assertRaisesRegex(web_export.ExportError, 'Unsafe staging output'):
            web_export.write_export(self.plan(), target)

    def test_rejects_version_mismatch(self):
        self.publish()
        with self.assertRaisesRegex(web_export.ExportError, 'catalog version'):
            self.plan(approval='side-catch@0.2.0', version='0.2.0')

    def test_rejects_runner_version_newer_than_pinned_web_runner(self):
        self.publish()
        self.fixture.metadata['release']['minimum_runner_version'] = '99.0.0'
        self.fixture.metadata_path.write_text(json.dumps(self.fixture.metadata, indent=2))
        with self.assertRaisesRegex(web_export.ExportError, 'below required'):
            self.plan()

    def test_fixed_paths_are_immutable_but_identical_reruns_are_noops(self):
        self.publish()
        plan = self.plan()
        site = self.out / 'site'
        web_export.write_export(plan, site)
        again = self.plan(site=site)
        self.assertEqual(set(again['actions'].values()), {'unchanged'})
        target = site / 'games/side-catch/0.1.0/side-catch.cjr'
        target.write_bytes(b'tampered')
        with self.assertRaisesRegex(web_export.ExportError, 'immutable'):
            self.plan(site=site)
        target.unlink()
        target.symlink_to(self.site_catalog)
        with self.assertRaisesRegex(web_export.ExportError, 'Unsafe existing file'):
            self.plan(site=site)

    def test_rejects_invalid_site_catalogs(self):
        self.publish()
        cases = [
            {'games': []},
            {'schemaVersion': 1, 'games': [OTHER, OTHER]},
            {'schemaVersion': 1, 'games': [{**OTHER, 'path': '../x.cjr'}]},
            {'schemaVersion': 1, 'games': [{**OTHER, 'runCommand': 'RUN'}]},
        ]
        for value in cases:
            with self.subTest(value=value):
                self.site_catalog.write_text(json.dumps(value))
                with self.assertRaises(web_export.ExportError):
                    self.plan()

    def test_rejects_package_hash_mismatch(self):
        self.publish()
        self.fixture.catalog['games'][0]['package']['sha256'] = '0' * 64
        self.fixture.write_catalog()
        with self.assertRaises(web_export.ExportError):
            self.plan()


if __name__ == '__main__':
    unittest.main()
