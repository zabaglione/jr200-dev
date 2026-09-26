#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Audit the current release candidate without committing or publishing it."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from typing import Any
import zipfile

from png_rgba import PngError, decode_rgba
from wiki.generate import WikiError, catalog_entries, load_gallery, load_package


ROOT = Path(__file__).resolve().parents[1]
MAX_CANDIDATE_BYTES = 10_000_000
TEXT_LIMIT = 2_000_000
CODE_SUFFIXES = {'.asm', '.inc', '.mjs', '.py'}
SUPPORTED_LICENSES = {'BSD-3-Clause', 'MIT'}
# Exact gallery files reviewed for the seven-game publication. Adding a new
# video or changing its bytes requires a new content/provenance review.
REVIEWED_GALLERY_VIDEOS = {
    'games/side-catch/media/goal.webm':
        '6737e0b01cf8813519a613f0e48081e16db13199d6893b3e0cf1b5db39327ff7',
    'games/relic-dive/media/goal.webm':
        '5cb2930519bad2efb482fb0e028935129623f8ca47b09dfb729b361c2f577232',
    'games/lumen-cross/media/goal.webm':
        'e3ce1c7d3104bfab628984bc1110b01dc45168d259dbf6ea78ba0f5b723cbb13',
    'games/corner-crown/media/goal.webm':
        '58d69d6d4c4a70489246b313f88190061584d649960ae3abfc8c27d9fb614f32',
    'games/circuit-works/media/goal.webm':
        '74608f22e6a260433f1314af25aad883aca0b64e8573cfd3cdb10f811d609223',
    'games/hearth-zero/media/goal.webm':
        'a6f46d240e1030d4d182579a9d8a0f775dd94a9ff47ef63b2bf98bc76f66a3c9',
    'games/brick-pulse/media/goal.webm':
        'f288f5c24b133b403b01640c628725a122f8694e19c517b05d29dfa5d6e0ccf8',
}
FORBIDDEN_SUFFIXES = {'.bin', '.cas', '.cjr', '.key', '.p12', '.pem', '.pfx',
                      '.rom', '.tap', '.wav', '.zip'}
SECRET_PATTERNS = (
    re.compile(r'sk-(?:proj-)?[A-Za-z0-9_-]{20,}'),
    re.compile(r'github_pat_[A-Za-z0-9_]{20,}'),
    re.compile(r'gh[pousr]_[A-Za-z0-9]{20,}'),
    re.compile(r'AKIA[0-9A-Z]{16}'),
    re.compile(r'AIza[0-9A-Za-z_-]{30,}'),
    re.compile(r'xox[baprs]-[0-9A-Za-z-]{10,}'),
    re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
)
ABSOLUTE_PATH = re.compile(
    r'(?:/' + r'Users/[^/\s]+/|/' + r'home/[^/\s]+/|'
    + r'[A-Za-z]:\\' + r'Users\\[^\\\s]+\\)')
EMAIL = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
ALLOWED_EMAIL = re.compile(
    r'(?:@(example\.(?:com|org|net)|example\.invalid)|@users\.noreply\.github\.com)$',
    re.IGNORECASE)


class AuditError(ValueError):
    """Expected audit setup or repository failure."""


def git(root: Path, *arguments: str, binary: bool = False) -> str | bytes:
    try:
        return subprocess.check_output(
            ['git', *arguments], cwd=root, stderr=subprocess.PIPE,
            text=not binary)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise AuditError(f'Git inspection failed: {arguments[0]}') from exc


def candidate_paths(root: Path) -> list[str]:
    output = git(root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z',
                 binary=True)
    paths = [item.decode('utf-8') for item in output.split(b'\0') if item]
    if (not paths or len(paths) != len(set(paths))
            or any(PurePosixPath(path).is_absolute() or '\\' in path
                   or any(part in ('', '.', '..') for part in PurePosixPath(path).parts)
                   for path in paths)):
        raise AuditError('Candidate file inventory is empty, duplicated, or unsafe')
    return sorted(paths)


def unsafe_candidate_path(path: str) -> bool:
    value = PurePosixPath(path)
    lower_parts = tuple(part.lower() for part in value.parts)
    return (value.suffix.lower() in FORBIDDEN_SUFFIXES
            or any(part in ('.env', 'local-assets', 'local-data', 'recordings')
                   for part in lower_parts)
            or any(part.startswith('.env.') and not part.endswith('.example')
                   for part in lower_parts))


def scan_text(label: str, text: str) -> tuple[list[str], list[str]]:
    blocks = []
    warnings = []
    if any(pattern.search(text) for pattern in SECRET_PATTERNS):
        blocks.append(f'secret-like value in {label}')
    paths = list(ABSOLUTE_PATH.finditer(text))
    # An older test revision contained this literal synthetic path. Keep the
    # historical fixture from blocking an audit without exempting other paths.
    fixture_label = label in ('tests/test_release_audit.py',
                              'history:tests/test_release_audit.py')
    fixture_path = '/Us' + 'ers/private/recording.webm'
    if any(not (fixture_label and text.startswith(fixture_path, match.start())
                and (match.start() + len(fixture_path) == len(text)
                     or not text[match.start() + len(fixture_path)].isalnum()))
           for match in paths):
        blocks.append(f'personal absolute path in {label}')
    if any(match.group(0).lower() != 'git@github.com'
           and not ALLOWED_EMAIL.search(match.group(0))
           for match in EMAIL.finditer(text)):
        warnings.append(f'non-placeholder email in {label}')
    return blocks, warnings


def binary_payload(data: bytes) -> bool:
    return b'\0' in data[:8192]


def project_license(root: Path, project: str) -> str:
    metadata_path = root / project / 'game.json'
    if not metadata_path.is_file():
        return 'BSD-3-Clause'
    try:
        metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AuditError(f'Cannot read project license: {project}') from exc
    license_id = metadata.get('license')
    if license_id not in SUPPORTED_LICENSES:
        raise AuditError(f'Unsupported project license: {project}')
    return license_id


def expected_spdx(root: Path, relative: str) -> str:
    parts = PurePosixPath(relative).parts
    if len(parts) >= 3 and parts[0] == 'games':
        return project_license(root, '/'.join(parts[:2]))
    return 'BSD-3-Clause'


def gallery_video_paths(root: Path, paths: list[str],
                        report: dict[str, Any]) -> set[str]:
    """Identify gallery-matched videos without treating them as provenance proof."""
    inventory = set(paths)
    matched = set()
    for manifest in sorted((root / 'games').glob('*/media/gallery.json')):
        project = manifest.parent.parent
        label = manifest.relative_to(root).as_posix()
        if re.fullmatch(r'games/[a-z][a-z0-9-]{0,31}/media/gallery\.json', label) is None:
            report['blocks'].append('unsafe gallery manifest path')
            continue
        if project.is_symlink() or manifest.parent.is_symlink():
            report['blocks'].append(f'symlinked gallery directory: {label}')
            continue
        try:
            gallery = load_gallery(project)
        except WikiError:
            report['blocks'].append(f'invalid gallery contract: {label}')
            continue
        video = gallery['video'] if gallery is not None else None
        if video is None:
            continue
        relative = (project / 'media' / video['file']).relative_to(root).as_posix()
        if relative not in inventory:
            report['blocks'].append(f'gallery video outside candidate inventory: {relative}')
            continue
        matched.add(relative)
    report['scope']['gallery_matched_videos'] = len(matched)
    return matched


def inspect_candidate_files(root: Path, paths: list[str], report: dict[str, Any]) -> None:
    gallery_videos = gallery_video_paths(root, paths, report)
    for relative in paths:
        path = root / relative
        if path.is_symlink() or not path.is_file():
            report['blocks'].append(f'non-regular candidate file: {relative}')
            continue
        if unsafe_candidate_path(relative):
            report['blocks'].append(f'forbidden candidate path: {relative}')
        with path.open('rb') as stream:
            data = stream.read(MAX_CANDIDATE_BYTES + 1)
        if len(data) > MAX_CANDIDATE_BYTES:
            report['blocks'].append(f'oversized candidate file: {relative}')
            continue
        if path.suffix.lower() == '.webm':
            if relative not in gallery_videos:
                report['blocks'].append(f'unreviewed binary candidate: {relative}')
                continue
            blocks, warnings = scan_text(relative, data.decode('latin-1'))
            report['blocks'].extend(blocks)
            report['warnings'].extend(warnings)
            if REVIEWED_GALLERY_VIDEOS.get(relative) != hashlib.sha256(data).hexdigest():
                report['publication_gates'].append(
                    f'{relative}: gallery hash matches, but video content and origin '
                    'lack independent review')
            continue
        if path.suffix.lower() == '.png':
            try:
                decode_rgba(data)
            except PngError:
                report['blocks'].append(f'non-contract PNG candidate: {relative}')
            continue
        if binary_payload(data):
            report['blocks'].append(f'unreviewed binary candidate: {relative}')
            continue
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError:
            report['blocks'].append(f'non-UTF-8 candidate: {relative}')
            continue
        blocks, warnings = scan_text(relative, text)
        report['blocks'].extend(blocks)
        report['warnings'].extend(warnings)
        if path.suffix.lower() in CODE_SUFFIXES:
            license_id = expected_spdx(root, relative)
            marker = f'SPDX-License-Identifier: {license_id}'
            if marker not in text[:300]:
                report['blocks'].append(
                    f'missing {license_id} SPDX identifier: {relative}')


def inspect_history(root: Path, report: dict[str, Any]) -> None:
    objects = git(root, 'rev-list', '--objects', '--all').splitlines()
    inspected = 0
    for line in objects:
        identifier, separator, path = line.partition(' ')
        if not separator:
            continue
        if unsafe_candidate_path(path):
            report['blocks'].append(f'forbidden path in Git history: {path}')
        try:
            kind = git(root, 'cat-file', '-t', identifier).strip()
            size = int(git(root, 'cat-file', '-s', identifier).strip())
        except (AuditError, ValueError):
            report['warnings'].append(f'cannot inspect historical object: {path}')
            continue
        if kind != 'blob' or size > TEXT_LIMIT:
            continue
        data = git(root, 'cat-file', 'blob', identifier, binary=True)
        inspected += 1
        if binary_payload(data):
            continue
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError:
            continue
        blocks, warnings = scan_text(f'history:{path}', text)
        report['blocks'].extend(blocks)
        report['warnings'].extend(warnings)
    emails = {item for item in git(root, 'log', '--all', '--format=%ae').splitlines()
              if item}
    if any(not email.lower().endswith('@users.noreply.github.com') for email in emails):
        report['warnings'].append('Git history contains non-noreply author metadata')
    report['scope']['history_text_blobs'] = inspected


def inspect_packages(root: Path, report: dict[str, Any]) -> None:
    packages = []
    for entry in catalog_entries(root):
        package = load_package(root, entry, None, require_release_ready=False)
        release = package['release']
        path = package['path']
        license_id = project_license(root, entry['project'])
        license_path = (root / 'LICENSE' if license_id == 'BSD-3-Clause'
                        else root / entry['project'] / 'LICENSE')
        expected_license = license_path.read_bytes()
        with zipfile.ZipFile(path) as archive:
            prefix = f'{entry["id"]}-{entry["version"]}/'
            if archive.read(prefix + 'LICENSE') != expected_license:
                report['blocks'].append(
                    f'{entry["id"]}: package license differs from project')
            for name in archive.namelist():
                data = archive.read(name)
                if len(data) > TEXT_LIMIT or binary_payload(data):
                    continue
                try:
                    text = data.decode('utf-8')
                except UnicodeDecodeError:
                    continue
                blocks, warnings = scan_text(f'package:{name}', text)
                report['blocks'].extend(blocks)
                report['warnings'].extend(warnings)
        if (entry['status'] != 'verified' or entry['wiki']['publish'] is not True
                or release['publication'] != 'published'
                or release['release_ready'] is not True):
            report['publication_gates'].append(
                f'{entry["id"]}: candidate is not a clean verified published release')
        packages.append({'id': entry['id'], 'version': entry['version'],
                         'release_ready': release['release_ready'],
                         'hardware': release['verification']['hardware']})
    report['scope']['packages'] = packages


def audit(root: Path) -> dict[str, Any]:
    root = root.resolve()
    if Path(git(root, 'rev-parse', '--show-toplevel').strip()).resolve() != root:
        raise AuditError('Audit root must be the Git worktree root')
    paths = candidate_paths(root)
    report: dict[str, Any] = {
        'schema_version': 1,
        'scope': {'candidate_files': len(paths)},
        'blocks': [],
        'warnings': [],
        'publication_gates': [],
        'checks': {
            'current_tree_and_untracked': 'scanned',
            'git_history': 'scanned',
            'fixed_packages': 'scanned',
            'remote_ci': 'not_run',
            'fresh_clone': 'not_run',
            'hardware': 'not_run',
        },
    }
    remote = git(root, 'remote', 'get-url', 'origin').strip()
    if not re.search(r'github\.com(?::|/)zabaglione/jr200-dev(?:\.git)?$', remote):
        report['blocks'].append('origin does not identify the canonical GitHub repository')
    try:
        configured_email = git(root, 'config', '--get', 'user.email').strip()
    except AuditError:
        configured_email = ''
    if not configured_email.lower().endswith('@users.noreply.github.com'):
        report['blocks'].append('future GitHub commit identity is not configured as noreply')
    inspect_candidate_files(root, paths, report)
    inspect_history(root, report)
    inspect_packages(root, report)
    emulator = json.loads((root / 'emulator.lock.json').read_text(encoding='utf-8'))
    if emulator.get('source', {}).get('availability') != 'release':
        report['publication_gates'].append('fixed emulator runner release asset is unavailable')
    report['blocks'] = sorted(set(report['blocks']))
    report['warnings'] = sorted(set(report['warnings']))
    report['publication_gates'] = sorted(set(report['publication_gates']))
    report['publication_ready'] = not report['blocks'] and not report['publication_gates']
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--strict', action='store_true',
                        help='Return nonzero when publication is not ready')
    args = parser.parse_args(argv)
    try:
        report = audit(args.root)
        print(json.dumps(report, indent=2, sort_keys=True))
        return 1 if args.strict and not report['publication_ready'] else 0
    except (AuditError, WikiError, OSError, json.JSONDecodeError,
            zipfile.BadZipFile) as exc:
        print(f'Release audit failed: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
