# SPDX-License-Identifier: BSD-3-Clause
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from wiki.check_candidates import candidates, check_cjr
from wiki.generate import ROOT, WikiError
from wiki.public_check import SITE, WIKI_RAW, check_public


class CandidateCheckTests(unittest.TestCase):
    def test_selects_new_versions_and_artifacts_without_fetching_public_assets(self):
        entry = {'id': 'side-catch', 'version': '0.1.2', 'artifact_sha256': 'a' * 64,
                 'status': 'verified'}
        other = {**entry, 'id': 'brick-pulse'}
        draft = {**entry, 'id': 'draft-game', 'status': 'draft'}
        new_version = {**entry, 'version': '0.1.3'}
        new_artifact = {**other, 'artifact_sha256': 'b' * 64}
        new_game = {**entry, 'id': 'new-game', 'status': 'candidate'}
        previous = json.dumps({'games': [entry, other, draft]}).encode()
        with patch('wiki.check_candidates.subprocess.check_output', return_value=previous), \
                patch('wiki.check_candidates.catalog_entries',
                      return_value=[new_version, new_artifact, new_game, draft]), \
                patch('urllib.request.urlopen', side_effect=AssertionError('unexpected network')):
            self.assertEqual(candidates(ROOT, '1' * 40),
                             [new_version, new_artifact, new_game])
            with patch('wiki.check_candidates.catalog_entries', return_value=[entry, other]):
                self.assertEqual(candidates(ROOT, '1' * 40), [])

    def test_build_must_match_catalog_cjr_hash(self):
        entry = {'id': 'side-catch', '_project': ROOT / 'games/side-catch',
                 'artifact_sha256': 'a' * 64}
        artifact = {'sha256': 'a' * 64}
        with patch('wiki.check_candidates.build_project',
                   return_value=(None, {'artifact': artifact})):
            check_cjr(ROOT, entry, 'jrasm')
            artifact['sha256'] = 'b' * 64
            with self.assertRaisesRegex(WikiError, 'candidate CJR hash mismatch'):
                check_cjr(ROOT, entry, 'jrasm')

    def test_publication_step_requires_successful_public_asset_check(self):
        workflow = (ROOT / '.github/workflows/wiki-sync.yml').read_text(encoding='utf-8')
        validation, publication = workflow.split('\n  publish:\n', maxsplit=1)
        self.assertIn('tools/wiki/check_candidates.py', validation)
        self.assertNotIn('tools/wiki/public_check.py', validation)
        self.assertNotIn('contents: write', validation)
        gate, synchronization = publication.split('- name: Synchronize only generated Wiki files')
        self.assertIn('id: public-assets', gate)
        self.assertIn('tools/wiki/public_check.py', gate)
        self.assertIn("if: steps.public-assets.outcome == 'success'", synchronization)


class PublicCheckTests(unittest.TestCase):
    def setUp(self):
        self.cjr = b'fixed-cjr'
        self.package = b'fixed-package'
        self.entry = {
            'id': 'side-catch', 'version': '0.1.2',
            'artifact_sha256': hashlib.sha256(self.cjr).hexdigest(),
            'package': {'file': 'side-catch-0.1.2.zip',
                        'release_url': 'https://github.com/example/release.zip',
                        'sha256': hashlib.sha256(self.package).hexdigest()},
            'wiki': {'publish': True},
        }
        self.catalog = {'schemaVersion': 1, 'games': [{
            'id': 'side-catch', 'version': '0.1.2',
            'path': 'games/side-catch/0.1.2/side-catch.cjr',
            'sha256': self.entry['artifact_sha256'],
        }]}
        self.responses = {
            SITE + 'game-catalog.json': json.dumps(self.catalog).encode(),
            SITE + 'games/side-catch/0.1.2/side-catch.cjr': self.cjr,
            self.entry['package']['release_url']: self.package,
            WIKI_RAW + 'Game-side-catch.md': b'generated-page',
        }

    def check(self, after=False, **kwargs):
        def fetch(url, limit):
            value = self.responses[url]
            self.assertLessEqual(len(value), limit)
            return value

        with patch('wiki.public_check.catalog_entries', return_value=[self.entry]), \
                patch('wiki.public_check.render_pages',
                      return_value=({'Game-side-catch.md': b'generated-page'}, [])):
            return check_public(Path('/unused'), after_wiki_push=after,
                                fetch=fetch, expected_commit='a' * 40, **kwargs)

    def test_preflight_and_post_push(self):
        self.assertEqual(self.check(), {'games': 1, 'cjr': 1, 'packages': 1,
                                        'wiki_files': 0})
        self.assertEqual(self.check(after=True)['wiki_files'], 1)

    def test_old_pages_version_fails_before_staging_packages(self):
        self.catalog['games'][0]['version'] = '0.1.1'
        self.responses[SITE + 'game-catalog.json'] = json.dumps(self.catalog).encode()
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / 'packages'
            with self.assertRaisesRegex(WikiError, 'Public catalog differs'):
                self.check(packages_dir=destination)
            self.assertFalse(destination.exists())

    def test_public_hash_mismatches_fail_before_staging_packages(self):
        for url, message in (
                (SITE + 'games/side-catch/0.1.2/side-catch.cjr', 'Public CJR hash mismatch'),
                (self.entry['package']['release_url'], 'Public release hash mismatch')):
            with self.subTest(url=url), tempfile.TemporaryDirectory() as temporary:
                destination = Path(temporary) / 'packages'
                with patch.dict(self.responses, {url: b'wrong'}):
                    with self.assertRaisesRegex(WikiError, message):
                        self.check(packages_dir=destination)
                self.assertFalse(destination.exists())

    def test_missing_wiki_update_fails_post_push(self):
        self.responses[WIKI_RAW + 'Game-side-catch.md'] = b'old-page'
        with self.assertRaisesRegex(WikiError, 'Public Wiki file differs'):
            self.check(after=True)

    def test_duplicate_catalog_id_fails(self):
        self.catalog['games'].append(dict(self.catalog['games'][0]))
        self.responses[SITE + 'game-catalog.json'] = json.dumps(self.catalog).encode()
        with self.assertRaisesRegex(WikiError, 'duplicate'):
            self.check()

    def test_approved_selection_is_exact(self):
        self.assertEqual(self.check(approved_games='side-catch@0.1.2')['games'], 1)
        with self.assertRaisesRegex(WikiError, 'Approved game selection differs'):
            self.check(approved_games='side-catch@0.1.1')

    def test_package_download_is_immutable(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            self.entry['package']['file'] = 'side-catch-0.1.2.zip'
            self.check(packages_dir=folder)
            self.assertEqual((folder / 'side-catch-0.1.2.zip').read_bytes(), self.package)
            (folder / 'side-catch-0.1.2.zip').write_bytes(b'other')
            with self.assertRaisesRegex(WikiError, 'Existing package differs'):
                self.check(packages_dir=folder)


if __name__ == '__main__':
    unittest.main()
