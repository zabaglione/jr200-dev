# SPDX-License-Identifier: BSD-3-Clause
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from game_project import (ProjectError, ProjectSpec, build_project, clean_project,
                          create_project, package_project, parse_cjr,
                          snapshot_presentation_paths, source_snapshot_digest,
                          validate_project)


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / 'templates/minimal'
BANNER = 'JR-200 Assembler 1.0.2 Copyright (C) 2018 ypsitau'


def cjr(payload=b'\x01\x39', start=0x1000):
    name = b'JR200-MINIMAL'.ljust(16, b'\0')
    header = bytearray(b'\x02\x2a\x00\x1a\xff\xff' + name + b'\x01\x00' + b'\xff' * 8)
    header.append(sum(header) & 0xff)
    block = bytearray((0x02, 0x2a, 0x01, len(payload), start >> 8, start & 0xff))
    block.extend(payload)
    block.append(sum(block) & 0xff)
    end = start + len(payload)
    footer = bytes((0x02, 0x2a, 0xff, 0xff, end >> 8, end & 0xff))
    return bytes(header + block + footer)


class ProjectFixture:
    def __init__(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.project = self.root / 'project'
        shutil.copytree(TEMPLATE, self.project, ignore=shutil.ignore_patterns('build'))

    def close(self):
        self.temporary.cleanup()

    def json(self, relative):
        return json.loads((self.project / relative).read_text(encoding='utf-8'))

    def write_json(self, relative, value):
        (self.project / relative).write_text(
            json.dumps(value, indent=2) + '\n', encoding='utf-8')

    def fake_jrasm(self, payload=None):
        executable = self.root / 'tool with spaces' / 'jrasm'
        executable.parent.mkdir()
        data = (payload if payload is not None else cjr()).hex()
        executable.write_text(
            '#!/usr/bin/env python3\n'
            'import pathlib, sys\n'
            f'BANNER = {BANNER!r}\n'
            f'DATA = bytes.fromhex({data!r})\n'
            'if len(sys.argv) == 1:\n'
            '    print(BANNER)\n'
            '    print("usage: jrasm [option] source")\n'
            '    raise SystemExit(0)\n'
            'output = sys.argv[sys.argv.index("-o") + 1]\n'
            'pathlib.Path(output).write_bytes(DATA)\n'
            'print(f"{output} was created")\n'
            'print("[Symbol List]")\n'
            'print("1000  start")\n',
            encoding='utf-8')
        executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
        return executable


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.fixture = ProjectFixture()

    def tearDown(self):
        self.fixture.close()

    def test_release_snapshot_excludes_ignored_python_cache(self):
        root = self.fixture.root
        project = self.fixture.project
        (root / '.gitignore').write_text('__pycache__/\n', encoding='utf-8')
        (project / 'tests').mkdir(exist_ok=True)
        (project / 'tests/model.py').write_text('VALUE = 1\n', encoding='utf-8')
        subprocess.check_call(['git', 'init'], cwd=root,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.check_call(['git', 'add', 'project/tests/model.py'], cwd=root)
        (project / 'tests/new.txt').write_text('new source\n', encoding='utf-8')
        cache = project / 'tests/__pycache__'
        cache.mkdir()
        (cache / 'model.pyc').write_bytes(b'ignored local bytecode')
        spec = ProjectSpec(project, root, {}, {}, {}, (), (), (), ())
        paths = snapshot_presentation_paths(spec)
        self.assertIn('tests/model.py', paths)
        self.assertIn('tests/new.txt', paths)
        self.assertNotIn('tests/__pycache__/model.pyc', paths)
        original = source_snapshot_digest(spec, {'inputs': []})
        (cache / 'model.pyc').write_bytes(b'different ignored bytecode')
        self.assertEqual(source_snapshot_digest(spec, {'inputs': []}), original)
        (project / 'tests/model.py').write_text('VALUE = 2\n', encoding='utf-8')
        self.assertNotEqual(source_snapshot_digest(spec, {'inputs': []}), original)

    def test_minimal_template_is_structurally_valid_without_rom_or_tool(self):
        spec = validate_project(self.fixture.project)
        self.assertEqual(spec.config['id'], 'minimal')
        self.assertEqual(spec.assembly_inputs, ('src/jr200.inc', 'src/main.asm'))
        self.assertEqual(spec.sdk_inputs, ())
        self.assertEqual(spec.asset_inputs, ())

    def test_accepts_exact_declared_repository_sdk_include(self):
        sdk = self.fixture.root / 'sdk'
        sdk.mkdir()
        (sdk / 'screen.inc').write_text('SDK_VALUE: .equ 1\n', encoding='utf-8')
        source = self.fixture.project / 'src/main.asm'
        source.write_text(source.read_text().replace(
            '.include "jr200.inc"',
            '.include "jr200.inc"\n        .include "../../sdk/screen.inc"'),
            encoding='utf-8')
        config = self.fixture.json('build.json')
        config['inputs']['sdk'] = ['sdk/screen.inc']
        self.fixture.write_json('build.json', config)
        spec = validate_project(
            self.fixture.project, repository_root=self.fixture.root)
        self.assertEqual(spec.sdk_inputs, ('sdk/screen.inc',))

    def test_rejects_undeclared_repository_sdk_include(self):
        sdk = self.fixture.root / 'sdk'
        sdk.mkdir()
        (sdk / 'screen.inc').write_text('SDK_VALUE: .equ 1\n', encoding='utf-8')
        source = self.fixture.project / 'src/main.asm'
        source.write_text(source.read_text().replace(
            '.include "jr200.inc"',
            '.include "jr200.inc"\n        .include "../../sdk/screen.inc"'),
            encoding='utf-8')
        with self.assertRaisesRegex(ProjectError, 'SDK dependency mismatch'):
            validate_project(self.fixture.project, repository_root=self.fixture.root)

    def test_rejects_overlapping_regions(self):
        config = self.fixture.json('build.json')
        config['regions'].append(
            {'name': 'overlap', 'kind': 'data', 'start': '0x10f0', 'end': '0x11ff'})
        self.fixture.write_json('build.json', config)
        with self.assertRaisesRegex(ProjectError, 'Overlapping'):
            validate_project(self.fixture.project)

    def test_rejects_entry_outside_code(self):
        config = self.fixture.json('build.json')
        config['entry_address'] = '0x1100'
        self.fixture.write_json('build.json', config)
        with self.assertRaisesRegex(ProjectError, 'Entry address'):
            validate_project(self.fixture.project)

    def test_rejects_reserved_memory(self):
        config = self.fixture.json('build.json')
        config['load_address'] = '0x0700'
        config['entry_address'] = '0x0700'
        config['regions'][0]['start'] = '0x0700'
        config['regions'][0]['end'] = '0x07ff'
        config['execution']['command'] = 'A=USR($0700)'
        self.fixture.write_json('build.json', config)
        with self.assertRaisesRegex(ProjectError, 'not loadable'):
            validate_project(self.fixture.project)

    def test_rejects_forbidden_instruction(self):
        source = self.fixture.project / 'src/main.asm'
        source.write_text(source.read_text() + '\n        NBA\n', encoding='utf-8')
        with self.assertRaisesRegex(ProjectError, 'Forbidden instruction NBA'):
            validate_project(self.fixture.project)

    def test_rejects_missing_include(self):
        source = self.fixture.project / 'src/main.asm'
        source.write_text('.include "missing.inc"\n.org 0x1000\nstart: RTS\n', encoding='utf-8')
        with self.assertRaisesRegex(ProjectError, 'Missing assembly dependency'):
            validate_project(self.fixture.project)

    def test_rejects_undeclared_include(self):
        (self.fixture.project / 'src/extra.inc').write_text('VALUE: .equ 1\n', encoding='utf-8')
        source = self.fixture.project / 'src/main.asm'
        source.write_text(source.read_text().replace(
            '.include "jr200.inc"', '.include "jr200.inc"\n        .include "extra.inc"'),
            encoding='utf-8')
        with self.assertRaisesRegex(ProjectError, 'Assembly dependency mismatch'):
            validate_project(self.fixture.project)

    def test_rejects_unlisted_asset(self):
        (self.fixture.project / 'assets/payload.bin').write_bytes(b'original data')
        with self.assertRaisesRegex(ProjectError, 'Asset manifest mismatch'):
            validate_project(self.fixture.project)

    def test_accepts_mit_game_with_project_license(self):
        metadata = self.fixture.json('game.json')
        metadata['license'] = 'MIT'
        self.fixture.write_json('game.json', metadata)
        (self.fixture.project / 'LICENSE').write_text(
            'MIT License\n\nCopyright test\n', encoding='utf-8')
        spec = validate_project(self.fixture.project)
        self.assertEqual(spec.metadata['license'], 'MIT')

    def test_rejects_mit_game_without_project_license(self):
        metadata = self.fixture.json('game.json')
        metadata['license'] = 'MIT'
        self.fixture.write_json('game.json', metadata)
        with self.assertRaisesRegex(ProjectError, 'requires a project LICENSE'):
            validate_project(self.fixture.project)

    def test_rejects_mit_sdk_game_without_third_party_notice(self):
        sdk = self.fixture.root / 'sdk'
        sdk.mkdir()
        (sdk / 'screen.inc').write_text(
            '; SPDX-License-Identifier: BSD-3-Clause\nSDK_VALUE: .equ 1\n',
            encoding='utf-8')
        source = self.fixture.project / 'src/main.asm'
        source.write_text(source.read_text().replace(
            '.include "jr200.inc"',
            '.include "jr200.inc"\n        .include "../../sdk/screen.inc"'),
            encoding='utf-8')
        config = self.fixture.json('build.json')
        config['inputs']['sdk'] = ['sdk/screen.inc']
        self.fixture.write_json('build.json', config)
        metadata = self.fixture.json('game.json')
        metadata['license'] = 'MIT'
        self.fixture.write_json('game.json', metadata)
        (self.fixture.project / 'LICENSE').write_text('MIT License\n', encoding='utf-8')
        with self.assertRaisesRegex(ProjectError, 'THIRD_PARTY_NOTICES'):
            validate_project(
                self.fixture.project, repository_root=self.fixture.root)


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.fixture = ProjectFixture()

    def tearDown(self):
        self.fixture.close()

    def test_parse_cjr_rejects_bad_checksum(self):
        data = bytearray(cjr())
        data[32] ^= 1
        with self.assertRaisesRegex(ProjectError, 'header checksum'):
            parse_cjr(bytes(data))

    def test_build_writes_only_selected_project_build_directory(self):
        other = self.fixture.root / 'other'
        shutil.copytree(TEMPLATE, other, ignore=shutil.ignore_patterns('build'))
        executable = self.fixture.fake_jrasm()
        spec, report = build_project(self.fixture.project, str(executable))
        self.assertTrue(spec.output.is_file())
        self.assertFalse((other / 'build').exists())
        self.assertEqual(report['artifact']['sha256'],
                         'ee52c1721560d611a2376cd8c6f371677bd00c3a42d179131c6adc46d0286710')
        self.assertEqual(report['verification']['emulator'], 'not_run')
        self.assertEqual(report['verification']['hardware'], 'not_run')

    def test_build_rejects_cjr_outside_declared_region(self):
        executable = self.fixture.fake_jrasm(cjr(start=0x1100))
        with self.assertRaisesRegex(ProjectError, 'first block'):
            build_project(self.fixture.project, str(executable))

    def test_package_contains_artifact_metadata_license_and_receipt(self):
        executable = self.fixture.fake_jrasm()
        package = package_project(self.fixture.project, str(executable))
        with zipfile.ZipFile(package) as archive:
            names = set(archive.namelist())
            prefix = 'minimal-0.0.0-dev/'
            self.assertEqual(names, {
                prefix + 'minimal.cjr', prefix + 'README.md', prefix + 'game.json',
                prefix + 'LICENSE', prefix + 'BUILD_REPORT.json', prefix + 'SHA256SUMS'})
            report = json.loads(archive.read(prefix + 'BUILD_REPORT.json'))
            self.assertEqual(report['verification']['assembler'], 'passed')
            self.assertEqual(report['verification']['emulator'], 'not_run')
        self.assertTrue(clean_project(self.fixture.project))
        self.assertFalse((self.fixture.project / 'build').exists())
        self.assertFalse(clean_project(self.fixture.project))

    def test_package_uses_project_license_for_mit_game(self):
        metadata = self.fixture.json('game.json')
        metadata['license'] = 'MIT'
        self.fixture.write_json('game.json', metadata)
        project_license = b'MIT License\n\nCopyright fixture\n'
        (self.fixture.project / 'LICENSE').write_bytes(project_license)
        executable = self.fixture.fake_jrasm()
        package = package_project(self.fixture.project, str(executable))
        with zipfile.ZipFile(package) as archive:
            self.assertEqual(
                archive.read('minimal-0.0.0-dev/LICENSE'), project_license)

    def test_mit_sdk_package_includes_notice_and_bsd_license(self):
        sdk = self.fixture.root / 'sdk'
        sdk.mkdir()
        (sdk / 'screen.inc').write_text(
            '; SPDX-License-Identifier: BSD-3-Clause\nSDK_VALUE: .equ 1\n',
            encoding='utf-8')
        source = self.fixture.project / 'src/main.asm'
        source.write_text(source.read_text().replace(
            '.include "jr200.inc"',
            '.include "jr200.inc"\n        .include "../../sdk/screen.inc"'),
            encoding='utf-8')
        config = self.fixture.json('build.json')
        config['inputs']['sdk'] = ['sdk/screen.inc']
        self.fixture.write_json('build.json', config)
        metadata = self.fixture.json('game.json')
        metadata['license'] = 'MIT'
        self.fixture.write_json('game.json', metadata)
        project_license = b'MIT License\n\nCopyright fixture\n'
        bsd_license = b'BSD 3-Clause License\n\nCopyright SDK fixture\n'
        (self.fixture.project / 'LICENSE').write_bytes(project_license)
        (self.fixture.project / 'THIRD_PARTY_NOTICES.md').write_text(
            'sdk/screen.inc is BSD-3-Clause.\n', encoding='utf-8')
        (self.fixture.root / 'LICENSE').write_bytes(bsd_license)
        executable = self.fixture.fake_jrasm()
        package = package_project(
            self.fixture.project, str(executable),
            repository_root=self.fixture.root)
        with zipfile.ZipFile(package) as archive:
            prefix = 'minimal-0.0.0-dev/'
            self.assertEqual(archive.read(prefix + 'LICENSE'), project_license)
            self.assertEqual(
                archive.read(prefix + 'LICENSES/BSD-3-Clause.txt'), bsd_license)
            self.assertIn(
                b'sdk/screen.inc',
                archive.read(prefix + 'THIRD_PARTY_NOTICES.md'))

    def test_create_project_updates_identity_and_validates(self):
        target = self.fixture.root / 'created'
        created = create_project('new-game', 'New Game', target)
        spec = validate_project(created)
        self.assertEqual(spec.config['id'], 'new-game')
        self.assertEqual(spec.config['output'], 'new-game.cjr')
        self.assertEqual(spec.metadata['title'], 'New Game')
        self.assertIn('new-game.cjr', (created / 'README.md').read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
