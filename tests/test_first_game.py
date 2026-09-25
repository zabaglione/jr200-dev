# SPDX-License-Identifier: BSD-3-Clause
import hashlib
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
from ci_plan import select
from game_project import ProjectError, build_project, package_project, validate_project


ROOT = Path(__file__).resolve().parents[1]
BANNER = 'JR-200 Assembler 1.0.2 Copyright (C) 2018 ypsitau'


def cjr(payload=b'\x01\x39', start=0x1000):
    name = b'SIDE-CATCH'.ljust(16, b'\0')
    header = bytearray(b'\x02\x2a\x00\x1a\xff\xff' + name + b'\x01\x00' + b'\xff' * 8)
    header.append(sum(header) & 0xff)
    block = bytearray((2, 0x2a, 1, len(payload), start >> 8, start & 0xff))
    block.extend(payload)
    block.append(sum(block) & 0xff)
    end = start + len(payload)
    return bytes(header + block + bytes((2, 0x2a, 0xff, 0xff, end >> 8, end & 0xff)))


class FirstGameTests(unittest.TestCase):
    def test_package_instructions_cover_every_required_profile(self):
        project = ROOT / 'games/side-catch'
        readme = (project / 'README.md').read_text(encoding='utf-8')
        expectations = json.loads(
            (project / 'tests/expectations.json').read_text(encoding='utf-8'))
        self.assertEqual(expectations['runtime']['default_profile'], 'synthetic-ci')
        self.assertIn('make run', readme)
        for item in expectations['runtime']['profiles']:
            if item['profile'] != 'synthetic-ci':
                self.assertIn(f"--profile {item['profile']}", readme)
        self.assertIn('--rom', readme)
        self.assertIn('--font', readme)
        self.assertIn('make package', readme)

    def test_game_metadata_and_declared_dependencies_are_valid(self):
        spec = validate_project(
            ROOT / 'games/side-catch', ROOT / 'rules/jr200.json', ROOT)
        self.assertEqual(spec.metadata['schema_version'], 2)
        self.assertEqual(spec.metadata['release']['status'], 'candidate')
        self.assertEqual(spec.metadata['release']['publication'], 'not-published')
        self.assertEqual(spec.metadata['verification'], {
            'emulator': 'passed', 'hardware': 'not_run'})
        self.assertEqual(spec.sdk_inputs, (
            'sdk/font.inc', 'sdk/font_data.inc', 'sdk/input.inc', 'sdk/jr200.inc',
            'sdk/screen.inc', 'sdk/session.inc', 'sdk/sound.inc', 'sdk/timing.inc'))

    def test_game_source_and_docs_have_separate_ci_effects(self):
        registry = json.loads((ROOT / 'ci/targets.json').read_text(encoding='utf-8'))
        source = select(registry, ['games/side-catch/src/main.asm'])
        self.assertEqual(source['build_candidates'], ['side-catch'])
        docs = select(registry, ['games/side-catch/README.md'])
        self.assertEqual(docs['build_candidates'], [])
        self.assertEqual(docs['test_candidates'], [])
        self.assertTrue(docs['wiki'])

    def test_release_package_binds_both_runtime_evidence_classes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / 'games/side-catch'
            project.parent.mkdir(parents=True)
            shutil.copytree(ROOT / 'games/side-catch', project,
                            ignore=shutil.ignore_patterns('build'))
            shutil.copytree(ROOT / 'sdk', root / 'sdk')
            shutil.copytree(ROOT / 'tests/fixtures', root / 'tests/fixtures')
            (root / 'rules').mkdir()
            shutil.copy2(ROOT / 'rules/jr200.json', root / 'rules/jr200.json')
            shutil.copy2(ROOT / 'toolchain.lock.json', root / 'toolchain.lock.json')
            shutil.copy2(ROOT / 'LICENSE', root / 'LICENSE')
            executable = root / 'fake-jrasm'
            executable.write_text(
                '#!/usr/bin/env python3\n'
                'import pathlib, sys\n'
                f'BANNER = {BANNER!r}\n'
                f'DATA = bytes.fromhex({cjr().hex()!r})\n'
                'if len(sys.argv) == 1:\n'
                '    print(BANNER)\n'
                '    print("usage: jrasm [option] source")\n'
                '    raise SystemExit(0)\n'
                'output = sys.argv[sys.argv.index("-o") + 1]\n'
                'pathlib.Path(output).write_bytes(DATA)\n'
                'print("[Symbol List]")\n'
                'print("1000  start")\n',
                encoding='utf-8')
            executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
            subprocess.check_call(['git', 'init'], cwd=root,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.check_call(['git', 'config', 'user.email', 'test@example.invalid'], cwd=root)
            subprocess.check_call(['git', 'config', 'user.name', 'Test'], cwd=root)
            subprocess.check_call(['git', 'add', '.'], cwd=root)
            subprocess.check_call(['git', 'commit', '-m', 'fixture'], cwd=root,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            _, build = build_project(
                project, str(executable), root / 'toolchain.lock.json',
                root / 'rules/jr200.json', root)
            artifact_hash = build['artifact']['sha256']
            reports = project / 'build/runtime-reports'
            reports.mkdir()
            profiles = json.loads((project / 'tests/expectations.json').read_text())[
                'runtime']['profiles']
            for item in profiles:
                profile = item['profile']
                mode = item['mode']
                evidence = ('emulator' if mode == 'synthetic-injection'
                            else 'emulator_with_local_rom')
                value = {
                    'schema_version': 1,
                    'project': 'side-catch',
                    'profile': profile,
                    'mode': mode,
                    'artifact_sha256': artifact_hash,
                    'expectations_sha256': hashlib.sha256(
                        (project / 'tests/expectations.json').read_bytes()).hexdigest(),
                    'runner': {'version': '0.2.0', 'source_revision': '1' * 40},
                    'result': {
                        'status': 'passed', 'profile': profile,
                        'mode': mode,
                        'artifact_sha256': artifact_hash,
                        'evidence': evidence, 'hardware': 'not_run'},
                    'verification': {'emulator': 'passed', 'hardware': 'not_run'},
                }
                (reports / f'{profile}.json').write_text(
                    json.dumps(value, sort_keys=True) + '\n', encoding='utf-8')
            package = package_project(
                project, str(executable), root / 'toolchain.lock.json',
                root / 'rules/jr200.json', root)
            with zipfile.ZipFile(package) as archive:
                prefix = 'side-catch-0.1.1/'
                manifest = json.loads(archive.read(prefix + 'RELEASE.json'))
                self.assertEqual(manifest['artifact']['file'], 'side-catch.cjr')
                self.assertEqual(manifest['artifact']['sha256'], artifact_hash)
                self.assertFalse(manifest['release_ready'])
                self.assertEqual(
                    {item['evidence'] for item in
                     manifest['verification']['runtime_profiles']},
                    {'emulator', 'emulator_with_local_rom'})
                names = set(archive.namelist())
                self.assertIn(prefix + 'VERIFICATION/synthetic-ci.json', names)
                self.assertIn(prefix + 'VERIFICATION/synthetic-screenshot.json', names)
                self.assertIn(prefix + 'VERIFICATION/local-rom-basic-return.json', names)
                self.assertIn(prefix + 'VERIFICATION/local-rom-title.json', names)
                self.assertEqual(
                    hashlib.sha256(archive.read(prefix + 'side-catch.cjr')).hexdigest(),
                    artifact_hash)
            metadata_path = project / 'game.json'
            metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
            metadata['release']['wav'] = 'required'
            metadata_path.write_text(json.dumps(metadata) + '\n', encoding='utf-8')
            with self.assertRaisesRegex(ProjectError, 'WAV-required'):
                package_project(
                    project, str(executable), root / 'toolchain.lock.json',
                    root / 'rules/jr200.json', root)


if __name__ == '__main__':
    unittest.main()
