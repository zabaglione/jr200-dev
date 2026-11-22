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
# Exact gallery files reviewed for publication. Adding a new
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
    'games/abyss-signal/media/goal.webm':
        '3ab3f8f3580697bec87d39172e495f0dae4d4daab76e9feace168efe4ace9278',
    'games/auction-house/media/goal.webm':
        'c65205053ef36b2707266a48cd8b248fe6c9fcf19c736e1aa4f56c5aea8793ec',
    'games/cargo-balance/media/goal.webm':
        'cf04b241ba837d0b146a38ae06952a05711172b19281fcccb90562ac34de089e',
    'games/chain-suit/media/goal.webm':
        '5da65349065c17f621fb7ffffc7af55bab4020c37dbbf122d148d62b8a5565bd',
    'games/chrono-breach/media/goal.webm':
        '0ec9e527f96d7f7d7483cfe6590b81b651aba33ebf7a086ad827aa3d51efa3d3',
    'games/compass-rose/media/goal.webm':
        'ee22fdebb8f24880e1bb65dd2e46caf39ed46e49799635fe8b4f3b356edd551d',
    'games/dice-relic/media/goal.webm':
        '6fb636e9d4a3bf04651f99548783be43eb3bcd8ee11e6234794c5401a1eab491',
    'games/echo-parry/media/goal.webm':
        'd96d02d3575cd6f8f9e0898c9f62f16e2a34837b93d3a76198968736690ee61d',
    'games/five-forge/media/goal.webm':
        'ed6b6fe1631647156f96fc13d6603a63e7907b0546b7bf1453474055f356fdf8',
    'games/frost-steps/media/goal.webm':
        'c6b9185bfdeb65badd35f62fc9f7fbd74c1430a7fa5c6f93554909d92702aadb',
    'games/fuse-box/media/goal.webm':
        '096ee0b506eed7670b53fe4d093f39fb8d68e3da5a333ede40ddbbbe5976f235',
    'games/gate-runner/media/goal.webm':
        'bf310951316fe665a7da157747967d4dcf73ca695d4d904ce4b1a671c779877e',
    'games/glyph-shift/media/goal.webm':
        'b5b4b923c12251ca04c6947c07061d6c151945b28e5973db4245db75bbd37634',
    'games/gravity-well/media/goal.webm':
        '4a3ee535bc30da0db5921f74347cc3eb9dcda6c5fcaf0684a94dfd785bdfd72d',
    'games/iron-script/media/goal.webm':
        '1cada940c8674897d51f1904fce0efad689e1ac421ceb09ac528b6c5e234d46d',
    'games/loop-ten/media/goal.webm':
        'baf76ce820c291b7d17e5a320b5e229224073d90189a5c110d709a059745702b',
    'games/lunar-touchdown/media/goal.webm':
        '9373ae2bfcfc01008e7bb5165dd04732fcfe421b987ddc5c1571216d7226b6a7',
    'games/magnet-vault/media/goal.webm':
        'fff73b5f0e5dd97718152715091a830f0c0cbff4076f769ac6e58b9e3a949310',
    'games/memory-mosaic/media/goal.webm':
        '05dab94115e01943292a94b365b95eebc4e58d78a3fbf766bc5742e070bfd2ab',
    'games/metro-weave/media/goal.webm':
        '6b85161481d2c8e3784b4098bee3bac6caa9e6c2bc4688c147f955b2cf250f87',
    'games/mirror-relic/media/goal.webm':
        '85c62d86924b5a77367cd2907e6fd8702c7a415f70c2d473914b93b5e5fa0e64',
    'games/night-swarm/media/goal.webm':
        '0384651508e166b0763e603dc0a3d8d81dc1223bc49cb68789cd0979e14e133c',
    'games/number-vault/media/goal.webm':
        '819b7c30eb669f82a4f992b965676981fc3d6e4f19fc0a30ba22b38e3333bfba',
    'games/orbit-dodge/media/goal.webm':
        'f91730d42b28aa73d54c6e943307b82e6fd7fe857b1a4d477e6a153026553468',
    'games/orbit-draft/media/goal.webm':
        '88cdb5cd80cf98030e4dfbfd83e6a1f86cf9e24ec11fbe2fa7f7e45eb13e8c0e',
    'games/orchard-days/media/goal.webm':
        'c76157602c6a4ef1bd424eaa5c446f6998242835024d7e5e2f849ced4082420c',
    'games/peg-garden/media/goal.webm':
        '761f0dbe0d9f0fa9dcc4bb3b38b1b9552812dbcc9dac5c3fefd64ec3160fffd1',
    'games/pendulum-port/media/goal.webm':
        '4be19d9891fcb9159e787e744869e39b040f06d53038ae6688f57404daffb531',
    'games/phase-pairs/media/goal.webm':
        'a879709a332555e5546ec9b760441528e906ba13403f45ffa2d9409b1987460f',
    'games/potion-path/media/goal.webm':
        '7f20091484c632ca6fbcec2eab420a2cd81332ae3b95d45326a2b057e2d51f10',
    'games/prism-trace/media/goal.webm':
        'bb6e355891219199e22e1c3be0da82d812e514e9456406750a4e53fa0b2bd4d0',
    'games/quiet-route/media/goal.webm':
        'd0fed30e7afa59e9c1841b871ef783bb9b38970d3d44b50118b5f3f8e249fd51',
    'games/ribbon-snake/media/goal.webm':
        '848c63cedaa2fbc57ec2890602c85be03e3dcc07e0f1137fb1a0ff455eea554d',
    'games/ruin-lexicon/media/goal.webm':
        '8125687fccd95f65299b31b99a68ff924f49190ab01a9a2fccb3385efd7650da',
    'games/sand-rescue/media/goal.webm':
        'c6b81b1b68c9fcc4caf491bd243d524f768674fa3930d9a87c7b297c760220f2',
    'games/seed-merge/media/goal.webm':
        '27c77aec18b29267a56db3a9b2897d5f25459bb0defdf421b0ddbd895d97549a',
    'games/shadow-archive/media/goal.webm':
        '0799fbf6e49d2adbded5e26178794c947188ccf86ea4a5b0c16ab8ab89e3898a',
    'games/sigil-deck/media/goal.webm':
        '2b73cb76091717fb51d47760567ed9f5bca52624bd62ccbb1ecbe2523ca6fc8a',
    'games/star-lance/media/goal.webm':
        '9ac19d881a1766e73e9e4832f4b719e3715cef84c35852068d1bdee6b58eeff3',
    'games/stone-balance/media/goal.webm':
        '1754b175771311e50b766a68d6be3dcd2f7d8158d398d6faf683954c6339ab7b',
    'games/tidal-nets/media/goal.webm':
        '270c1a2136d2c50ac90a5de345fd020e120c8f183ccd002985e73e1a5541dc99',
    'games/tide-bridge/media/goal.webm':
        '5c4b46ebe0c48c9f21fcd43266bb9b0486c81e10d582c286fb19d015ba03978c',
    'games/trace-blade/media/goal.webm':
        'cce278ac5d788748150665bf88be83d4485866584c6465b119db73c02310a6a7',
    'games/twenty-one/media/goal.webm':
        '99b898f598baabb92728807613bbf25255f674c5cfe3d2aea573c72475169c06',
    'games/word-foundry/media/goal.webm':
        '8a058c27764145c6b4814cc881dfc552e0e9d950f26ae59281f6a953e53f4dd2',
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
                        report: dict[str, Any],
                        fixed_packages: dict[str, dict[str, Any]]) -> set[str]:
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
            gallery = load_gallery(project, fixed_package=fixed_packages.get(project.name))
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


def inspect_candidate_files(root: Path, paths: list[str], report: dict[str, Any],
                            fixed_packages: dict[str, dict[str, Any]] | None = None) -> None:
    gallery_videos = gallery_video_paths(root, paths, report, fixed_packages or {})
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


def inspect_packages(root: Path, report: dict[str, Any]) -> dict[str, dict[str, Any]]:
    packages = []
    fixed_packages = {}
    for entry in catalog_entries(root):
        package = load_package(root, entry, None, require_release_ready=False)
        if entry['wiki']['publish']:
            fixed_packages[entry['id']] = package
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
    return fixed_packages


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
    fixed_packages = inspect_packages(root, report)
    inspect_candidate_files(root, paths, report, fixed_packages)
    inspect_history(root, report)
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
