# SPDX-License-Identifier: BSD-3-Clause
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from release_audit import (expected_spdx, inspect_candidate_files, scan_text,
                           unsafe_candidate_path)


ROOT = Path(__file__).resolve().parents[1]
VIDEO = 'games/lumen-cross/media/goal.webm'


class ReleaseAuditTests(unittest.TestCase):
    def test_forbidden_distribution_and_private_paths(self):
        for value in ('local-data/ROM.bin', 'games/demo/build/demo.cjr',
                      'capture.wav', '.env.production', 'keys/private.pem'):
            self.assertTrue(unsafe_candidate_path(value), value)
        for value in ('games/demo/media/screenshot.png', '.env.example',
                      'tests/fixture.asm'):
            self.assertFalse(unsafe_candidate_path(value), value)

    def test_secret_and_personal_path_are_reported_without_value(self):
        secret = 'ghp_' + 'A' * 24
        private_path = '/Us' + 'ers/private/work/file'
        blocks, warnings = scan_text(
            'candidate.txt', f'token={secret}\npath={private_path}\n')
        self.assertEqual(warnings, [])
        self.assertEqual(blocks, [
            'secret-like value in candidate.txt',
            'personal absolute path in candidate.txt',
        ])
        self.assertNotIn(secret, '\n'.join(blocks))

    def test_placeholder_email_is_allowed_but_real_domain_warns(self):
        self.assertEqual(scan_text('test.py', 'test@example.invalid'), ([], []))
        real_email = 'person@' + 'company.test'
        self.assertEqual(scan_text('doc.md', real_email),
                         ([], ['non-placeholder email in doc.md']))

    def test_game_source_uses_declared_project_spdx(self):
        from tempfile import TemporaryDirectory

        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            project = root / 'games/demo'
            project.mkdir(parents=True)
            (project / 'game.json').write_text(
                '{"license": "MIT"}\n', encoding='utf-8')
            self.assertEqual(expected_spdx(root, 'games/demo/src/main.asm'), 'MIT')
            self.assertEqual(expected_spdx(root, 'tools/check.py'), 'BSD-3-Clause')


class GalleryVideoAuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.project = self.root / 'games/lumen-cross'
        self.project.mkdir(parents=True)
        shutil.copytree(ROOT / 'games/lumen-cross/media', self.project / 'media')
        (self.project / 'tests').mkdir()
        shutil.copy2(ROOT / 'games/lumen-cross/tests/expectations.json',
                     self.project / 'tests/expectations.json')
        self.video = self.root / VIDEO
        self.manifest = self.project / 'media/gallery.json'

    def inspect(self, *paths):
        report = {'blocks': [], 'warnings': [], 'publication_gates': [], 'scope': {}}
        inspect_candidate_files(self.root, list(paths or (VIDEO,)), report)
        return report

    def test_matching_gallery_video_remains_a_publication_gate(self):
        report = self.inspect()
        self.assertEqual(report['blocks'], [])
        self.assertEqual(report['scope']['gallery_matched_videos'], 1)
        self.assertEqual(len(report['publication_gates']), 1)
        self.assertIn('lack independent review', report['publication_gates'][0])

    def test_unlisted_video_is_blocked(self):
        extra = 'games/lumen-cross/media/extra.webm'
        shutil.copy2(self.video, self.root / extra)
        report = self.inspect(VIDEO, extra)
        self.assertIn(f'unreviewed binary candidate: {extra}', report['blocks'])

    def test_manifest_video_outside_candidate_inventory_is_blocked(self):
        report = self.inspect('games/lumen-cross/media/title.png')
        self.assertIn(f'gallery video outside candidate inventory: {VIDEO}',
                      report['blocks'])

    def test_invalid_gallery_error_does_not_echo_secret_or_private_path(self):
        manifest = json.loads(self.manifest.read_text(encoding='utf-8'))
        secret = 'ghp_' + 'A' * 24
        for unsafe in (secret + '.webm', '/Users/private/recording.webm'):
            manifest['video']['file'] = unsafe
            self.manifest.write_text(json.dumps(manifest), encoding='utf-8')
            report = self.inspect()
            self.assertTrue(report['blocks'])
            self.assertNotIn(unsafe, json.dumps(report))

    def test_hash_mismatch_and_fake_webm_are_blocked(self):
        original = self.video.read_bytes()
        self.video.write_bytes(original[:-1] + bytes((original[-1] ^ 1,)))
        self.assertTrue(self.inspect()['blocks'])
        self.video.write_bytes(b'FAKE' + original[4:])
        manifest = json.loads(self.manifest.read_text(encoding='utf-8'))
        manifest['video']['sha256'] = hashlib.sha256(self.video.read_bytes()).hexdigest()
        self.manifest.write_text(json.dumps(manifest), encoding='utf-8')
        self.assertTrue(self.inspect()['blocks'])

    def test_rom_profile_is_not_gallery_evidence(self):
        manifest = json.loads(self.manifest.read_text(encoding='utf-8'))
        expectations_path = self.project / 'tests/expectations.json'
        expectations = json.loads(expectations_path.read_text(encoding='utf-8'))
        for profile in expectations['runtime']['profiles']:
            if profile['profile'] == manifest['video']['profile']:
                profile['mode'] = 'rom-cassette'
        expectations_path.write_text(json.dumps(expectations), encoding='utf-8')
        self.assertTrue(self.inspect()['blocks'])

    def test_video_or_parent_symlink_is_blocked(self):
        backing = self.root / 'backing.webm'
        self.video.rename(backing)
        self.video.symlink_to(backing)
        self.assertTrue(self.inspect()['blocks'])
        self.video.unlink()
        backing.rename(self.video)
        media = self.project / 'media'
        backing_media = self.project / 'media-real'
        media.rename(backing_media)
        media.symlink_to(backing_media.name, target_is_directory=True)
        self.assertTrue(self.inspect()['blocks'])

    def test_embedded_secret_is_blocked_even_with_matching_manifest(self):
        self.video.write_bytes(self.video.read_bytes() + b'ghp_' + b'A' * 24)
        manifest = json.loads(self.manifest.read_text(encoding='utf-8'))
        manifest['video']['sha256'] = hashlib.sha256(self.video.read_bytes()).hexdigest()
        self.manifest.write_text(json.dumps(manifest), encoding='utf-8')
        report = self.inspect()
        self.assertIn(f'secret-like value in {VIDEO}', report['blocks'])

    def test_oversized_gallery_inputs_are_rejected_before_full_read(self):
        for path in (self.manifest, self.project / 'tests/expectations.json',
                     self.video):
            with self.subTest(path=path.name):
                original = path.read_bytes()
                try:
                    with path.open('wb') as stream:
                        stream.truncate(10_000_001)
                    report = self.inspect()
                    self.assertIn('invalid gallery contract: '
                                  'games/lumen-cross/media/gallery.json',
                                  report['blocks'])
                finally:
                    path.write_bytes(original)

    def test_oversized_unlisted_candidate_is_rejected_before_full_read(self):
        extra = 'games/lumen-cross/media/extra.webm'
        with (self.root / extra).open('wb') as stream:
            stream.truncate(10_000_001)
        report = self.inspect(VIDEO, extra)
        self.assertIn(f'oversized candidate file: {extra}', report['blocks'])


if __name__ == '__main__':
    unittest.main()
