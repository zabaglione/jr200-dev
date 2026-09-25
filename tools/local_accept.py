#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Build and accept one game locally with owned ROM/font and a fixed runner.

This command never publishes, fetches an emulator, or copies ROM/font assets.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import zipfile

from emulator_runner import (RunnerError, load_lock, run, validate_expectations,
                             verify_bundle)
from game_project import (ProjectError, address, build_project, package_project,
                          read_json, write_json)
from jrasm_tool import sha256_file
from wiki.generate import WikiError, package_sums, safe_archive_names


class AcceptanceError(ValueError):
    """A local acceptance condition was not met."""


def select_profiles(expectations: dict, entry: int, mode: str,
                    requested: list[str]) -> list[dict]:
    raw = expectations.get('runtime', {}).get('profiles', [])
    if not isinstance(raw, list) or not raw:
        raise AcceptanceError('No runtime profiles are declared')
    if any(not isinstance(item, dict) or not isinstance(item.get('profile'), str)
           for item in raw):
        raise AcceptanceError('Invalid runtime profile declaration')
    checked = [validate_expectations(expectations, entry, item.get('profile'))
               for item in raw]
    by_name = {item['profile']: item for item in checked}
    if len(by_name) != len(checked):
        raise AcceptanceError('Duplicate runtime profile')
    local = [item for item in checked if item['mode'] == 'rom-cassette']
    if not local:
        raise AcceptanceError('Owned-ROM cassette profile is required')
    if mode == 'full':
        if requested:
            raise AcceptanceError('--profile is only available in quick mode')
        selected = checked
    elif requested:
        if len(set(requested)) != len(requested) or any(name not in by_name for name in requested):
            raise AcceptanceError('Unknown or duplicate selected profile')
        selected = [by_name[name] for name in requested]
    else:
        title = next((item for item in local if 'title' in item['profile']), None)
        play = next((item for item in local if 'play' in item['profile']), None)
        selected = list(dict.fromkeys(
            item['profile'] for item in (title, play) if item is not None))
        selected = [by_name[name] for name in selected] if selected else local[:2]
    if not any(item['mode'] == 'rom-cassette' for item in selected):
        raise AcceptanceError('Selection must include an owned-ROM cassette profile')
    if mode == 'quick' and not any(item['expect']['framebuffer_sha256'] for item in selected):
        raise AcceptanceError('Quick selection needs a verified screen profile')
    return selected


def verify_package(path: Path, project_id: str, version: str,
                   cjr_name: str, cjr_sha256: str, expectations_sha256: str,
                   profiles: set[str], current_members: dict[str, bytes] | None = None) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 16 * 1024 * 1024:
        raise AcceptanceError('Package is missing, unsafe, or too large')
    prefix = f'{project_id}-{version}/'
    try:
        with zipfile.ZipFile(path) as archive:
            if any(item.flag_bits & 1 for item in archive.infolist()):
                raise AcceptanceError('Encrypted packages are not accepted')
            names = set(safe_archive_names(archive))
            required = {'README.md', 'game.json', 'LICENSE', 'BUILD_REPORT.json',
                        'RELEASE.json', 'SHA256SUMS', cjr_name}
            required.update(f'VERIFICATION/{name}.json' for name in profiles)
            required.update((current_members or {}).keys())
            if names != {prefix + name for name in required}:
                raise AcceptanceError('Package inventory does not match the selected game')
            package_sums(archive, prefix, names)
            for name, content in (current_members or {}).items():
                if prefix + name not in names or archive.read(prefix + name) != content:
                    raise AcceptanceError(f'Package member differs from current source: {name}')
            cjr = archive.read(prefix + cjr_name)
            release = json.loads(archive.read(prefix + 'RELEASE.json').decode('utf-8'))
            if not isinstance(release, dict):
                raise AcceptanceError('Package release manifest is invalid')
            artifact = release.get('artifact')
            source = release.get('source')
            verification = release.get('verification')
            records = (verification.get('runtime_profiles')
                       if isinstance(verification, dict) else None)
            if (not isinstance(artifact, dict) or not isinstance(source, dict)
                    or not isinstance(records, list)
                    or any(not isinstance(item, dict)
                           or not isinstance(item.get('profile'), str)
                           for item in records)):
                raise AcceptanceError('Package release manifest is invalid')
            if (hashlib.sha256(cjr).hexdigest() != cjr_sha256
                    or release.get('project') != project_id
                    or release.get('version') != version
                    or artifact.get('sha256') != cjr_sha256
                    or artifact.get('size') != len(cjr)
                    or source.get('expectations_sha256') != expectations_sha256
                    or {item.get('profile') for item in records} != profiles):
                raise AcceptanceError('Package CJR or release manifest differs from the build')
    except (OSError, RuntimeError, zipfile.BadZipFile, UnicodeDecodeError,
            json.JSONDecodeError, WikiError) as exc:
        raise AcceptanceError(f'Package validation failed: {exc}') from exc
    return {'file': path.name, 'sha256': sha256_file(path),
            'release_ready': release.get('release_ready') is True}


def accept(project: Path, bundle: Path, rom: Path, font: Path,
           jrasm: str | None = None, mode: str = 'quick',
           profiles: list[str] | None = None, capture: bool = False,
           self_font: Path | None = None, package_path: Path | None = None) -> dict:
    if not rom.is_file() or not font.is_file() or rom.is_symlink() or font.is_symlink():
        raise AcceptanceError('Owned ROM and font must be regular local files')
    if capture and (self_font is None or not self_font.is_file()):
        raise AcceptanceError('--capture requires --self-font')
    if self_font is not None and not capture:
        raise AcceptanceError('--self-font requires --capture')
    verify_bundle(bundle, load_lock())
    spec, build = build_project(project, jrasm)
    if mode == 'full' and spec.metadata['schema_version'] != 2:
        raise AcceptanceError('Full candidate packaging requires game metadata schema 2')
    entry = address(spec.config['entry_address'], 'entry address')
    expectations = read_json(spec.project / 'tests/expectations.json', 'runtime expectations')
    selected = select_profiles(expectations, entry, mode, profiles or [])
    package_target = (package_path if package_path is not None else
                      spec.project / 'build/package' /
                      f'{spec.config["id"]}-{spec.metadata["version"]}.zip')
    if mode == 'full' and package_path is None and (package_target.exists()
                                                     or package_target.is_symlink()):
        raise AcceptanceError('Existing package will not be overwritten; pass --package '
                              'to validate it or move it aside')
    if mode == 'full' and package_path is None and (package_target.parent /
            ('.' + package_target.name + '.tmp')).exists():
        raise AcceptanceError('Existing temporary package will not be overwritten')
    capture_dir = None
    if capture:
        parent = spec.project / 'build/local-accept'
        parent.mkdir(parents=True, exist_ok=True)
        capture_dir = Path(tempfile.mkdtemp(prefix='run-', dir=parent))
    results = []
    for item in selected:
        local = item['mode'] == 'rom-cassette'
        image = (capture_dir / (item['profile'] + '.png') if capture_dir and local
                 and item['expect']['framebuffer_sha256'] else None)
        report = run(spec.project, bundle, os.environ.get('NODE', 'node'),
                     Path(__file__).resolve().parent / 'jr200_wasm_runner.mjs',
                     Path(__file__).resolve().parents[1] / 'emulator.lock.json',
                     profile=item['profile'], rom=rom if local else None,
                     font=font if local else None, screenshot=image,
                     self_font=self_font if image else None)
        results.append({'profile': item['profile'], 'mode': item['mode'],
                        'framebuffer_sha256': report['result']['framebuffer_sha256'],
                        'cassette_path': report['verification']['cassette_path'],
                        'screenshot': str(image.relative_to(spec.project)) if image else None})
    package_result = None
    if mode == 'full' and package_path is None:
        created = package_project(spec.project, jrasm)
        if created != package_target:
            raise AcceptanceError('Unexpected package destination')
    if mode == 'full' or package_path is not None:
        root = spec.repository_root
        license_path = (root / 'LICENSE' if spec.metadata['license'] == 'BSD-3-Clause'
                        else spec.project / 'LICENSE')
        current_members = {
            'README.md': (spec.project / 'README.md').read_bytes(),
            'game.json': (spec.project / 'game.json').read_bytes(),
            'BUILD_REPORT.json': (spec.project / 'build/build-report.json').read_bytes(),
            'LICENSE': license_path.read_bytes(),
        }
        if spec.metadata['license'] != 'BSD-3-Clause' and spec.sdk_inputs:
            current_members['THIRD_PARTY_NOTICES.md'] = (
                spec.project / 'THIRD_PARTY_NOTICES.md').read_bytes()
            current_members['LICENSES/BSD-3-Clause.txt'] = (root / 'LICENSE').read_bytes()
        if mode == 'full':
            for item in selected:
                name = item['profile']
                current_members[f'VERIFICATION/{name}.json'] = (
                    spec.project / 'build/runtime-reports' / f'{name}.json').read_bytes()
        package_result = verify_package(
            package_target, spec.config['id'], spec.metadata['version'],
            spec.config['output'], build['artifact']['sha256'],
            sha256_file(spec.project / 'tests/expectations.json'),
            {item['profile'] for item in expectations['runtime']['profiles']},
            current_members)
    summary = {'project': spec.config['id'], 'mode': mode,
               'cjr_sha256': build['artifact']['sha256'], 'profiles': results,
               'package': package_result, 'hardware': 'not_run'}
    if capture_dir:
        write_json(capture_dir / 'acceptance.json', summary)
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--bundle', type=Path,
                        default=Path(os.environ['JR200_RUNNER_BUNDLE'])
                        if os.environ.get('JR200_RUNNER_BUNDLE') else None)
    parser.add_argument('--rom', type=Path, required=True)
    parser.add_argument('--font', type=Path, required=True)
    parser.add_argument('--jrasm', default=os.environ.get('JRASM'))
    parser.add_argument('--mode', choices=('quick', 'full'), default='quick')
    parser.add_argument('--profile', action='append', default=[])
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--self-font', type=Path)
    parser.add_argument('--package', type=Path)
    args = parser.parse_args(argv)
    if args.bundle is None:
        parser.error('--bundle or JR200_RUNNER_BUNDLE is required')
    try:
        result = accept(args.project, args.bundle, args.rom, args.font,
                        args.jrasm, args.mode, args.profile, args.capture,
                        args.self_font, args.package)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (AcceptanceError, ProjectError, RunnerError, OSError) as exc:
        print(f'Local acceptance failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
