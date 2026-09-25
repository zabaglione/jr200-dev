# SPDX-License-Identifier: BSD-3-Clause
"""Local acceptance selection and candidate integrity checks."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from local_accept import AcceptanceError, select_profiles, verify_package  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]


class LocalAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.expectations = json.loads((ROOT / 'games/side-catch/tests/expectations.json')
                                       .read_text(encoding='utf-8'))

    def test_quick_and_full_selection(self):
        quick = select_profiles(self.expectations, 0x1000, 'quick', [])
        self.assertEqual([item['profile'] for item in quick],
                         ['local-rom-title', 'local-rom-play'])
        self.assertTrue(all(item['mode'] == 'rom-cassette' for item in quick))
        full = select_profiles(self.expectations, 0x1000, 'full', [])
        self.assertEqual(len(full), len(self.expectations['runtime']['profiles']))
        with self.assertRaisesRegex(AcceptanceError, 'owned-ROM'):
            select_profiles(self.expectations, 0x1000, 'quick', ['synthetic-ci'])
        with self.assertRaisesRegex(AcceptanceError, 'only available'):
            select_profiles(self.expectations, 0x1000, 'full', ['local-rom-title'])

    def test_package_checks_internal_and_artifact_hashes(self):
        cjr = b'fixture-cjr'
        digest = hashlib.sha256(cjr).hexdigest()
        expectations = 'a' * 64
        release = {
            'project': 'demo', 'version': '1.0.0', 'release_ready': False,
            'artifact': {'sha256': digest, 'size': len(cjr)},
            'source': {'expectations_sha256': expectations},
            'verification': {'runtime_profiles': [{'profile': 'local-rom-title'}]},
        }
        prefix = 'demo-1.0.0/'
        entries = {'demo.cjr': cjr, 'README.md': b'readme',
                   'game.json': b'{}', 'LICENSE': b'license',
                   'BUILD_REPORT.json': b'{}',
                   'VERIFICATION/local-rom-title.json': b'{}',
                   'RELEASE.json': json.dumps(release).encode('utf-8')}
        sums = ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n'
                       for name, data in sorted(entries.items())).encode('ascii')
        entries['SHA256SUMS'] = sums
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'candidate.zip'
            with zipfile.ZipFile(archive, 'w') as output:
                for name, data in entries.items():
                    output.writestr(prefix + name, data)
            result = verify_package(archive, 'demo', '1.0.0', 'demo.cjr', digest,
                                    expectations, {'local-rom-title'})
            self.assertFalse(result['release_ready'])
            self.assertEqual(result['sha256'], hashlib.sha256(archive.read_bytes()).hexdigest())
            with self.assertRaisesRegex(AcceptanceError, 'differs'):
                verify_package(archive, 'demo', '1.0.0', 'demo.cjr', '0' * 64,
                               expectations, {'local-rom-title'})
            with self.assertRaisesRegex(AcceptanceError, 'inventory|differs'):
                verify_package(archive, 'demo', '1.0.0', 'demo.cjr', digest,
                               expectations, {'local-rom-play'})
            with self.assertRaisesRegex(AcceptanceError, 'current source'):
                verify_package(archive, 'demo', '1.0.0', 'demo.cjr', digest,
                               expectations, {'local-rom-title'},
                               {'README.md': b'current readme'})
            with zipfile.ZipFile(archive, 'w') as output:
                for name, data in entries.items():
                    output.writestr(prefix + name, b'changed' if name == 'demo.cjr'
                                    else data)
            with self.assertRaisesRegex(AcceptanceError, 'checksum|hash'):
                verify_package(archive, 'demo', '1.0.0', 'demo.cjr', digest,
                               expectations, {'local-rom-title'})
            with zipfile.ZipFile(archive, 'w') as output:
                for name, data in entries.items():
                    output.writestr(prefix + name, data)
                output.writestr(prefix + 'ROM.bin', b'not allowed')
            with self.assertRaisesRegex(AcceptanceError, 'inventory'):
                verify_package(archive, 'demo', '1.0.0', 'demo.cjr', digest,
                               expectations, {'local-rom-title'})


if __name__ == '__main__':
    unittest.main()
