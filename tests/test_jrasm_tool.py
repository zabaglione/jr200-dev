# SPDX-License-Identifier: BSD-3-Clause
import copy
import json
from pathlib import Path
import stat
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from jrasm_tool import ToolError, inspect, load_lock, resolve_executable, validate_lock
from build_jrasm import cmake_arguments


ROOT = Path(__file__).resolve().parents[1]


class JrasmToolTests(unittest.TestCase):
    def make_executable(self, directory: Path, banner: str) -> Path:
        path = directory / 'path with spaces' / 'jrasm'
        path.parent.mkdir()
        path.write_text(
            '#!/usr/bin/env python3\n'
            'import sys\n'
            f'print({banner!r}, file=sys.stderr)\n'
            'raise SystemExit(1)\n',
            encoding='utf-8',
        )
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
        return path

    def test_repository_lock_is_valid(self):
        lock = load_lock(ROOT / 'toolchain.lock.json')
        self.assertEqual(lock['version'], '1.0.2')
        self.assertFalse(lock['redistribution'])

    def test_platform_build_flags_are_locked(self):
        lock = load_lock(ROOT / 'toolchain.lock.json')
        mac = cmake_arguments(lock, 'Darwin', Path('/source path'), Path('/build path'))
        linux = cmake_arguments(lock, 'Linux', Path('/source path'), Path('/build path'))
        self.assertFalse(any(arg.startswith('-DCMAKE_CXX_FLAGS=') for arg in mac))
        self.assertIn('-fno-delete-null-pointer-checks', linux[-1])
        with self.assertRaisesRegex(ToolError, 'Unsupported'):
            cmake_arguments(lock, 'Plan9', Path('/source'), Path('/build'))

    def test_explicit_path_with_spaces(self):
        lock = load_lock(ROOT / 'toolchain.lock.json')
        with tempfile.TemporaryDirectory() as directory:
            executable = self.make_executable(Path(directory), lock['banner'])
            resolved = resolve_executable(str(executable), {})
            self.assertEqual(resolved, executable.resolve())
            self.assertEqual(inspect(resolved, lock)['banner'], lock['banner'])

    def test_environment_path(self):
        lock = load_lock(ROOT / 'toolchain.lock.json')
        with tempfile.TemporaryDirectory() as directory:
            executable = self.make_executable(Path(directory), lock['banner'])
            self.assertEqual(resolve_executable(None, {'JRASM': str(executable)}), executable.resolve())

    def test_missing_tool_has_actionable_error(self):
        with self.assertRaisesRegex(ToolError, 'set JRASM or pass --jrasm'):
            resolve_executable(None, {'PATH': ''})
        with self.assertRaisesRegex(ToolError, 'JRASM executable was not found'):
            resolve_executable(None, {'JRASM': '/missing/jrasm', 'PATH': ''})

    def test_version_mismatch_is_rejected(self):
        lock = load_lock(ROOT / 'toolchain.lock.json')
        with tempfile.TemporaryDirectory() as directory:
            executable = self.make_executable(Path(directory), 'JR-200 Assembler 0.0.0')
            with self.assertRaisesRegex(ToolError, 'version mismatch'):
                inspect(executable, lock)

    def test_rejects_malformed_locks(self):
        raw = json.loads((ROOT / 'toolchain.lock.json').read_text(encoding='utf-8'))
        values = []
        item = copy.deepcopy(raw); item['schema_version'] = True; values.append(item)
        item = copy.deepcopy(raw); item['jrasm']['revision'] = 'main'; values.append(item)
        item = copy.deepcopy(raw); item['jrasm']['fixture']['source'] = '../private.asm'; values.append(item)
        item = copy.deepcopy(raw); item['jrasm']['fixture']['sha256'] = 'bad'; values.append(item)
        item = copy.deepcopy(raw); item['jrasm']['redistribution'] = 'false'; values.append(item)
        item = copy.deepcopy(raw); item['jrasm']['build']['platforms'] = {}; values.append(item)
        for value in values:
            with self.subTest(value=value), self.assertRaises(ToolError):
                validate_lock(value, ROOT)


if __name__ == '__main__':
    unittest.main()
