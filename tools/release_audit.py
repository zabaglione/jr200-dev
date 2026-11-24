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
        '1fbc637d7bf2018808cb41902829122632200407598706dc9a4176c3c7e516e3',
    'games/relic-dive/media/goal.webm':
        '5cb2930519bad2efb482fb0e028935129623f8ca47b09dfb729b361c2f577232',
    'games/lumen-cross/media/goal.webm':
        '3d713af507f8678bfd8e63bff602c51e70017aef4148389174cf81fae8c975c4',
    'games/corner-crown/media/goal.webm':
        '1fe267048eedc9f70fe986c728af7dc5fc9f31fc1de9fe3c7bcdbcd6afea46f5',
    'games/circuit-works/media/goal.webm':
        '78765893821522b370d6a2e2cced86cb60e1d0d59a4d12968d93079df16d1a4b',
    'games/hearth-zero/media/goal.webm':
        'c9e8dc04da44395ce5adaf015396e972787693c4900d91faaaaaabb6437c729a',
    'games/brick-pulse/media/goal.webm':
        'b7a5081f9242bb48a35c631bbbd3f941a5acb2c54d4cb85b81eda4e076297fb5',
    'games/abyss-signal/media/goal.webm':
        '9ecb41740abf5c8b69620a2d92953b767983cb33b219416777410e09819ca695',
    'games/auction-house/media/goal.webm':
        'a95ed2a6fbb316d8886d0422c03766d39943d6bb7ba2c5283a66c26e79efcb23',
    'games/cargo-balance/media/goal.webm':
        'c9792d1f3cdeaefe6dbda14ee681322f4f2015e2f5e7945ea2ae5d36e104c539',
    'games/chain-suit/media/goal.webm':
        '7b13320cf2e2c6950549537799f286fb96df817d33092af7182875c7f7e5e4ea',
    'games/chrono-breach/media/goal.webm':
        'd7bc3985618f5166e10a5cf1b29ba943aca48d9407d012ae5614a0d96c78ddc8',
    'games/compass-rose/media/goal.webm':
        '8fec9abb15fd3bba0d2279e57c23da4149947f6692653cedf5d1fb47e30f8913',
    'games/dice-relic/media/goal.webm':
        '3a2e1a46472f9bb5f0cc4b7e39bed9b511f10114d9fad98c5fba7cd8a0eaa868',
    'games/echo-parry/media/goal.webm':
        '54c7cc7f95dae973ecd385d5ed785e32f915ebd18c8bae81416fb11de6dd5e3b',
    'games/five-forge/media/goal.webm':
        '9a1b825880c93deab33b111c6c08b2a42327bb4722d9c348419e9c31f16b1bba',
    'games/frost-steps/media/goal.webm':
        'ffcdd753cac448aacd1ee22318cfcac7e7a009b549bd7d60eac0b61439ff5948',
    'games/fuse-box/media/goal.webm':
        '9f523c5ef890fd1f7b057c48d91f796a107cd077ae25e86672b42021c8d50232',
    'games/gate-runner/media/goal.webm':
        'febe38ed7b6b48d62ea0c2cdc8b0979cd17f97fffd2ed76ce3666f012b198409',
    'games/glyph-shift/media/goal.webm':
        'b3088e1ed5b978fb897eb3e0874c70063eab95edfa5b1ae188c0528376b23f3e',
    'games/gravity-well/media/goal.webm':
        '6b3a39736e39fb3efac9a7246cc343421b3b58b4509c7484f0aeb9c394f9dfdc',
    'games/iron-script/media/goal.webm':
        '00efded33bf647573043a8c8362b51f25c7c2fc64335e8e64057203784869557',
    'games/loop-ten/media/goal.webm':
        '7ac1cfa8709d8dc410da2fe1898e363b22645b018ac35e79664005c453b17047',
    'games/lunar-touchdown/media/goal.webm':
        'bc3c75416c42666fb849a03cd7e040095c64da94174cc82834dba9e525e26198',
    'games/magnet-vault/media/goal.webm':
        'b7e1e18ec4a2d1c32933b5e60e7151cdaadc96b0c077a0badcba4c5e47e9c1e3',
    'games/memory-mosaic/media/goal.webm':
        'ffb213a5fc0f25d642901f99c3321c4365724b034b4ea76ea859fc2131d720ea',
    'games/metro-weave/media/goal.webm':
        'd7cc2a1cc68f2d056f1e76b4beda14f9b1fbae40eed84e0aa2da9edcf66d2103',
    'games/mirror-relic/media/goal.webm':
        '874754fff45bb538f1ea55dbe9b30f0efb1c9275dbe5fa1f1f011cf6f8c37f92',
    'games/night-swarm/media/goal.webm':
        '6b6813b5cc0573e70076f58792953cfe149aa0a10eba0d31529449fb94e63641',
    'games/number-vault/media/goal.webm':
        'b56768b0f4dcae294b9b69c84d9b3d6b7d4838fc71ade43e4d995a7b2be3375c',
    'games/orbit-dodge/media/goal.webm':
        'f98ba2f6acd2f52bcebcbcf9f344ccfd76c7df2a755436c0050b53f99abaff69',
    'games/orbit-draft/media/goal.webm':
        '547a7da9652e5b66598fa7de6b8acbce675b0d7081ca2a03bc13993921813e02',
    'games/orchard-days/media/goal.webm':
        '95217d49a1df5a5db7c6d7907edac02bb60e715e8b2126a3dbac0eefd6c82188',
    'games/peg-garden/media/goal.webm':
        'd10b9bd182da23bf12a82ff2f6656fea5f583250d02f8dbb46a29638eca93a90',
    'games/pendulum-port/media/goal.webm':
        'cec61a03c1f02a5e9cdc138d74a57befdbd9403a38da338a75a32c4a016551b8',
    'games/phase-pairs/media/goal.webm':
        '85dd5b82a4ee3086171931fb52072ee2298cf931cb9ce206947fc5a13af84746',
    'games/potion-path/media/goal.webm':
        'b08b15a23909550f4c344af17280521d6f65cd9a4b77b5a3b9803e2d4d9b85c3',
    'games/prism-trace/media/goal.webm':
        'f5fbb7af07b9883e7c422721d3e353c42ced0aa6a660a924e71e894608252de4',
    'games/quiet-route/media/goal.webm':
        'e4ac5e1b3169f8878c8405bcd8598afe433c25641da2f005b8c6d3798ea2a9d3',
    'games/ribbon-snake/media/goal.webm':
        '378f1222a98d189a5c0312d71850a1b389ded9e11369ff9e7fcdad5fdc4d9cb6',
    'games/ruin-lexicon/media/goal.webm':
        'cfd34f9dc71589ffdea8567438040d37603ad58d25cf02fe2c7103783eafa581',
    'games/sand-rescue/media/goal.webm':
        '80bbf9072bf7c763ce620bd7a2ee2c1d10160a85566d8d4426aceb74fe5aff00',
    'games/seed-merge/media/goal.webm':
        'efc79e7024d5e3cc1a741bbc210071f1f79d815190ca7c8cc603b88ceee54628',
    'games/shadow-archive/media/goal.webm':
        '00756929d73f1b91385e57d8f351c54527a6fb89a6a801860846a1a7d77f642b',
    'games/sigil-deck/media/goal.webm':
        'c175cd4e839fda9f365a9e10953579290f984470c17a5e6f16467aa46aa16e06',
    'games/star-lance/media/goal.webm':
        '24c3abfeea88534922b6cda937e3f85ad890336880d03a89f21dc8972863ea0d',
    'games/stone-balance/media/goal.webm':
        '14a4364249ffd9a9c4279ff4c8535a8719480c707cf6daa91086868e0e8e1230',
    'games/tidal-nets/media/goal.webm':
        '7a6aca1bdebb5511ed5b76cab781a8e5a2393fd30532932f65123cff95e41bd2',
    'games/tide-bridge/media/goal.webm':
        '0c5d82e8961bd2a45ed1af85192baa9e184950f66da228ca56fc05187a3c5d6d',
    'games/trace-blade/media/goal.webm':
        '25fe4f453e12973ec0cb894517a6ce5c3071179f814c45010f363226f33d29d2',
    'games/twenty-one/media/goal.webm':
        '145658aedbab630c2610030fc005380cc50b1c95e73adcf7c04c79130abdf1ef',
    'games/word-foundry/media/goal.webm':
        '5e73f450b0f22c1753dcb7bdd5bb8a6a1722535578902fb154582da09e67b2f6',
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
