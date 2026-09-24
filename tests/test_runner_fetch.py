# SPDX-License-Identifier: BSD-3-Clause
import copy
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from runner_fetch import (FetchError, REQUIRED_FILES, fetch, redirect_url,
                          release_url, unpack_verified, download, main)


ROOT = Path(__file__).resolve().parents[1]
RELEASE_URL = ('https://github.com/zabaglione/jr200-web-emulator/'
               'releases/download/runner-v0.3.0/jr200-runner-v0.3.0.zip')


class FetchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.lock = json.loads((ROOT / 'emulator.lock.json').read_text())
        self.files = {name: ('notice:' + name).encode() for name in REQUIRED_FILES}
        self.files['jr200_codec.mjs'] = b'export default function() {}'
        self.files['jr200_codec.wasm'] = b'\x00asm\x01\x00\x00\x00'
        for item in self.lock['module_files']:
            data = self.files[item['path']]
            item['size'] = len(data)
            item['sha256'] = hashlib.sha256(data).hexdigest()
        for item in self.lock['notice_files']:
            data = self.files[item['path']]
            item['size'] = len(data)
            item['sha256'] = hashlib.sha256(data).hexdigest()
        self.lock['source']['availability'] = 'release'
        self.lock['source']['release_asset'] = RELEASE_URL
        self.archive = self.root / 'candidate.zip'
        self.write_archive()
        self.lock_path = self.root / 'emulator.lock.json'
        self.write_lock()

    def tearDown(self):
        self.temporary.cleanup()

    def write_archive(self):
        with zipfile.ZipFile(self.archive, 'w', zipfile.ZIP_DEFLATED) as bundle:
            for name, data in sorted(self.files.items()):
                bundle.writestr(name, data)
        self.lock['source']['release_sha256'] = hashlib.sha256(
            self.archive.read_bytes()).hexdigest()

    def write_lock(self):
        self.lock_path.write_text(json.dumps(self.lock), encoding='utf-8')

    def test_pinned_archive_installs_without_network_or_emulator_build(self):
        output = self.root / 'fixed-runner'
        with patch('runner_fetch.download', side_effect=lambda _u, dst, _d:
                   shutil.copy2(self.archive, dst)) as downloader:
            self.assertEqual(fetch(self.lock_path, output), output)
            self.assertEqual(fetch(self.lock_path, output), output)
        downloader.assert_called_once()
        self.assertEqual({p.relative_to(output).as_posix() for p in output.rglob('*')
                          if p.is_file()}, REQUIRED_FILES)

    def test_missing_notice_extra_rom_and_traversal_are_rejected(self):
        for mutation in ('missing', 'rom', 'traversal'):
            with self.subTest(mutation=mutation):
                files = copy.deepcopy(self.files)
                if mutation == 'missing':
                    del files['LICENSE.txt']
                elif mutation == 'rom':
                    files['JR200.rom'] = b'secret'
                else:
                    files['../outside'] = b'bad'
                self.files = files
                self.write_archive()
                with self.assertRaisesRegex(FetchError, 'inventory'):
                    unpack_verified(self.archive, self.root / 'unpack', self.lock)
                self.files = {name: ('notice:' + name).encode() for name in REQUIRED_FILES}
                self.files['jr200_codec.mjs'] = b'export default function() {}'
                self.files['jr200_codec.wasm'] = b'\x00asm\x01\x00\x00\x00'

    def test_digest_mismatch_does_not_replace_existing_output(self):
        output = self.root / 'fixed-runner'
        output.mkdir()
        (output / 'keep').write_text('original')
        with self.assertRaisesRegex(FetchError, 'refusing overwrite'):
            fetch(self.lock_path, output)
        self.assertEqual((output / 'keep').read_text(), 'original')
        self.assertEqual(list(output.iterdir()), [output / 'keep'])

    def test_corrupt_candidate_never_installs(self):
        output = self.root / 'fixed-runner'
        self.lock['source']['release_sha256'] = '0' * 64
        self.write_lock()
        with patch('runner_fetch.download', side_effect=lambda _u, dst, _d:
                   shutil.copy2(self.archive, dst)):
            with self.assertRaisesRegex(FetchError, 'SHA-256'):
                fetch(self.lock_path, output)
        self.assertFalse(output.exists())

    def test_notice_tampering_invalidates_existing_output(self):
        output = self.root / 'fixed-runner'
        with patch('runner_fetch.download', side_effect=lambda _u, dst, _d:
                   shutil.copy2(self.archive, dst)):
            fetch(self.lock_path, output)
        (output / 'LICENSE.txt').write_text('changed')
        with self.assertRaisesRegex(FetchError, 'refusing overwrite'):
            fetch(self.lock_path, output)

    def test_existing_output_with_unlisted_rom_is_rejected(self):
        output = self.root / 'fixed-runner'
        with patch('runner_fetch.download', side_effect=lambda _u, dst, _d:
                   shutil.copy2(self.archive, dst)):
            fetch(self.lock_path, output)
        (output / 'unlisted.rom').write_bytes(b'not in the approved inventory')
        with self.assertRaisesRegex(FetchError, 'refusing overwrite'):
            fetch(self.lock_path, output)

    def test_duplicate_and_symlink_entries_are_rejected(self):
        for kind in ('duplicate', 'symlink'):
            with self.subTest(kind=kind):
                with zipfile.ZipFile(self.archive, 'w') as bundle:
                    for name, data in sorted(self.files.items()):
                        if kind == 'symlink' and name == 'LICENSE.txt':
                            info = zipfile.ZipInfo(name)
                            info.create_system = 3
                            info.external_attr = (0o120777 << 16)
                            bundle.writestr(info, b'../secret')
                        else:
                            bundle.writestr(name, data)
                    if kind == 'duplicate':
                        bundle.writestr('LICENSE.txt', b'duplicate')
                self.lock['source']['release_sha256'] = hashlib.sha256(
                    self.archive.read_bytes()).hexdigest()
                with self.assertRaises(FetchError):
                    unpack_verified(self.archive, self.root / 'unpack', self.lock)

    def test_local_only_does_not_download(self):
        self.lock['source'].update(availability='local_build_only',
                                   release_asset=None, release_sha256=None)
        self.write_lock()
        with patch('runner_fetch.download') as downloader:
            self.assertIsNone(fetch(self.lock_path, self.root / 'bundle'))
        downloader.assert_not_called()

    def test_ci_skips_release_for_explicit_local_rom_only_target(self):
        runner_path = self.root / 'runner.lock.json'
        shutil.copy2(ROOT / 'ci/runner.lock.json', runner_path)
        with patch('runner_fetch.fetch') as downloader:
            result = main(['--lock', str(self.lock_path), '--runner-lock',
                           str(runner_path), '--target', 'joystick-sample',
                           '--output', str(self.root / 'bundle')])
        self.assertEqual(result, 0)
        downloader.assert_not_called()

    def test_expired_after_eof_is_not_success(self):
        response = MagicMock()
        response.geturl.return_value = RELEASE_URL
        response.read1.return_value = b''
        opener = MagicMock()
        opener.open.return_value.__enter__.return_value = response
        with (patch('runner_fetch.request.build_opener', return_value=opener),
              patch('runner_fetch.time.monotonic', side_effect=[0, 0, 61])):
            with self.assertRaisesRegex(FetchError, 'time limit'):
                download(RELEASE_URL, self.root / 'slow.zip', '0' * 64)

    def test_rejects_unapproved_urls_and_redirects(self):
        for url in ('http://github.com/zabaglione/jr200-web-emulator/releases/'
                    'download/v1/jr200-runner-v1.zip',
                    'https://evil.example/release.zip',
                    'https://github.com/other/repo/releases/download/v1/'
                    'jr200-runner-v1.zip', RELEASE_URL + '?token=secret',
                    'https://github.com:invalid/zabaglione/jr200-web-emulator/'
                    'releases/download/v1/jr200-runner-v1.zip'):
            with self.subTest(url=url), self.assertRaises(FetchError):
                release_url(url)
        with self.assertRaises(FetchError):
            redirect_url('http://release-assets.githubusercontent.com/file')
        with self.assertRaises(FetchError):
            redirect_url('https://attacker.example/file')


if __name__ == '__main__':
    unittest.main()
