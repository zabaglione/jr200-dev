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
        '51e145510d6e353d3d39f628c37bc1c4260aac09e95e8bbfe98d5a7ad46a9770',
    'games/corner-crown/media/goal.webm':
        '6a3a3491d88888ebeb9f3e1901e56c9526e7178e3a41e7d7f07d513f3a33804b',
    'games/circuit-works/media/goal.webm':
        '6e8ff67afc9e63623b431a12f0164967b1b74d1400e484aae65e64aaad5a59a9',
    'games/hearth-zero/media/goal.webm':
        '93043abe86e8d7016f7ea43769ec36900baa60200b2ccb0a964fb2214dab54c0',
    'games/brick-pulse/media/goal.webm':
        '9b44712be6c30e7ea59a952c30e1d8487a7e0634cd98cec7e3500923df11f6b7',
    'games/abyss-signal/media/goal.webm':
        '895349338fb91c65dba56fa29ea9000cd5e92d14a3e49e9e2f8678b0a7b231e0',
    'games/auction-house/media/goal.webm':
        '6aab45beb0051c622d36ee7546a4e736488eacc31be3b0f2270e51efa67de24d',
    'games/cargo-balance/media/goal.webm':
        'b193ffbc74c68ff6e191cceb5dd2691cf27d27f284f16c231d1af3655d53e2d1',
    'games/chain-suit/media/goal.webm':
        '7f50a93770f216c5289fe73ce5bd89f2592d0fa580f5331c3e6d4d630cc9ceae',
    'games/chrono-breach/media/goal.webm':
        'f1849328f840c21ee1e02cc1061e9494d5d6662f647f9b756356b9981a06ce3e',
    'games/compass-rose/media/goal.webm':
        '5030caec20d412b39dbd57cc63036d0d7e140a76d043e0ee8948c5d94be93df1',
    'games/dice-relic/media/goal.webm':
        'a26d21902d89bd8319fe75065173d0964eb90759d1b847687e6a19b651f90f73',
    'games/echo-parry/media/goal.webm':
        'f6acee83149dc5305b5b06d02e8b01535b0b40cfe75b84f3f4edf4f6b3314168',
    'games/five-forge/media/goal.webm':
        '596e4580a36e7dfdfba3ba10d85898e1f68933514c51951d41c37d7637074631',
    'games/frost-steps/media/goal.webm':
        '3f8287ec062ed0b73e2e96ffeca30f7bb92091ff08dccbf59b865bcec688f2d3',
    'games/fuse-box/media/goal.webm':
        '33fc3b5b0874d2f7e61db66816c284b0e3481ea7cedd0635667852902127bba2',
    'games/gate-runner/media/goal.webm':
        '59e0de30160aa662a125d73ac446b49c454c8431ed439d39218ff77f6d144743',
    'games/glyph-shift/media/goal.webm':
        '26d3467ccad25cbaf432ece76aa532afb183afe9ed8a6bc2b84fc425455526b2',
    'games/gravity-well/media/goal.webm':
        '5638141a25846a551a703f8b2e0fb9dc153594bdeac8df7c0b6e06e9e7c47e67',
    'games/iron-script/media/goal.webm':
        '24992a81dabd7bac73329f31f658ea81cf70ce1ac50fe8655fd93a80367c4dc0',
    'games/loop-ten/media/goal.webm':
        '42e3f7897823c51c3b5fcf457bb501494b1011806cf2748bc70268b2b2e58084',
    'games/lunar-touchdown/media/goal.webm':
        'b7a1e46c5411ded03dbc0874c475c49307c323df623da0d924ce9f9a3da8d70e',
    'games/magnet-vault/media/goal.webm':
        '5761778d8c6632de284fd0233eebc91b74a6f4312e37f3554d402ba458dcb773',
    'games/memory-mosaic/media/goal.webm':
        '38a72c970057b6658ad02271373e9f84ee42525265b151d96e5ca0a6d6cc1d78',
    'games/metro-weave/media/goal.webm':
        '551dfdb21cb21d934ca12ced03046493125648f757744fea4f4d2c1349034ac1',
    'games/mirror-relic/media/goal.webm':
        'd2f6f3beeac26dea99af2f243755fad91ec46dbccdff27b79a2430b8548c1cff',
    'games/night-swarm/media/goal.webm':
        '6ad9c517bb8fcfed7bf83eef4ff82338baa48c8b566b64b54cd38bc815e6167f',
    'games/number-vault/media/goal.webm':
        'f28f0e7341f2abe281f46126ded27f6db39f621e83242a49b45f27b83bee7bac',
    'games/orbit-dodge/media/goal.webm':
        '8959b74cab229d5918a568a3f3508d2946828095ce4e953c9dba65459f038c93',
    'games/orbit-draft/media/goal.webm':
        'b944d96f31947dc982e6e17061547db0042d61f37fb66e30ede390d700b24518',
    'games/orchard-days/media/goal.webm':
        'f7b99cd9013a702c3c03d4c2772d7e816d24bea2d003403a54013a51da76edc0',
    'games/peg-garden/media/goal.webm':
        'df6eb916c90f457f9711953d466c3bdcc7a5627c6ac8cd7252d5c85118d58a1e',
    'games/pendulum-port/media/goal.webm':
        'ce2ef26413971a23832cf0d1409cdac07fe8c02445c90695c2122b16d237fd7e',
    'games/phase-pairs/media/goal.webm':
        '6b2e46a3db40eb8ac82dcc5751694d91b08cf43b1c8267ac6fea131cb961cda9',
    'games/potion-path/media/goal.webm':
        '4860e1d9718aa0901608b6247d83bd3bd4aff8ad91c1a966cbb22510ca0661ef',
    'games/prism-trace/media/goal.webm':
        '9f50ea394843880e0fb3d08e37184ab1cf7f9196b464d125c6125152487775b0',
    'games/quiet-route/media/goal.webm':
        '55bb52cb5745031c2fd34cad4d06c6a4faaea70d0551d27e07eb45ecedc1036b',
    'games/ribbon-snake/media/goal.webm':
        'fbe772148b9ba0fe8f28afb9150aa1cfaf33e17645292096ed8ec542a281151b',
    'games/ruin-lexicon/media/goal.webm':
        '16499c47a313f3071dfcd1528fe6091e69bfcd79a3e407ab5f7c8d6d67a65a36',
    'games/sand-rescue/media/goal.webm':
        '25f6131ea57a58a7d469eae6e96cbd988c99f9aa257c17d9d9eddeb2940f93cc',
    'games/seed-merge/media/goal.webm':
        'fc966350c3b366bf67bbf6cf5acc96d08dfe32daf97fee55ed78641b9ec19414',
    'games/shadow-archive/media/goal.webm':
        '446ff3736f28ab2d192a4e392d8a5a72f950492a6f59bd59f604716dc329e801',
    'games/sigil-deck/media/goal.webm':
        '2ec854cfdf2516cd43bcf98d6ba88a59a45d0e54e7479dad4ff63b568d5507cb',
    'games/star-lance/media/goal.webm':
        '85b7c74c31323ac6db46df1e98ca74a65269604e6393135f32e7c09c44daa681',
    'games/stone-balance/media/goal.webm':
        'ff3a0516b50b223c0576f468706516061f88c89b6ca35c853d06e83eaf7f51f0',
    'games/tidal-nets/media/goal.webm':
        '6c4583e82ddb47c845d6c24680fff1f1cb671bcf514dfddab8b9fd3e22315a60',
    'games/tide-bridge/media/goal.webm':
        '48534db902e3ef6141e710a225674ec6d4c77f9bd0910fa9d9ec54fe2da9c277',
    'games/trace-blade/media/goal.webm':
        '778ae0b640ed267da485c73cc210cacfc97cec813211d23c21724b2a9357a9cc',
    'games/twenty-one/media/goal.webm':
        '58016bf0224fd5617900bb961caf0c47c896f51979aaa276d200637f8fedb0bf',
    'games/word-foundry/media/goal.webm':
        'f95230de82053597378ba1dfcf66bd6974123259e8caee1566b1d0a412840b7f',
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
