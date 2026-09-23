# SPDX-License-Identifier: BSD-3-Clause
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from release_audit import expected_spdx, scan_text, unsafe_candidate_path


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


if __name__ == '__main__':
    unittest.main()
