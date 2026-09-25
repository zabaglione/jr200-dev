#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Validate fixed game packages and render or sync generated Wiki pages."""
from __future__ import annotations

import argparse
import hashlib
import html
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
from typing import Any
from urllib.parse import urlparse
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from game_project import (ProjectError, address, parse_cjr, validate_metadata,
                          validate_project)
from jrasm_tool import sha256_file
from png_rgba import PngError, decode_rgba


ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'games/catalog.json'
MANIFEST = '.jr200-generated.json'
SAFE_ID = re.compile(r'[a-z][a-z0-9-]{0,31}')
HEX64 = re.compile(r'[0-9a-f]{64}')
SEMVER = re.compile(r'(\d+)\.(\d+)\.(\d+)')
GENERATED_FILE = re.compile(
    r'(?:Home|_Sidebar|All-Games|Games|Controls|Play|Presentation|Quality-Review|Licenses|'
    r'Genre-[A-Z][a-z]{1,31}|Game-[a-z][a-z0-9-]{0,31})\.md|'
    r'media/[a-z][a-z0-9-]{0,63}\.(?:png|webm)')
EMULATOR_URL = 'https://zabaglione.github.io/jr200-web-emulator/'
REPOSITORY_URL = 'https://github.com/zabaglione/jr200-dev'
SOURCE_URL = REPOSITORY_URL + '/blob/main/'
TREE_URL = REPOSITORY_URL + '/tree/main/'
UPSTREAM_URL = ('https://github.com/zabaglione/jr100dev/blob/'
                '9a3921c4371d84c55fc468879dbed2f00fe42960/')
GENRES = Path(__file__).resolve().with_name('genres.json')
MAX_GALLERY_BYTES = 10_000_000


class WikiError(ValueError):
    """Expected catalog, package, render, or local-sync failure."""


def read_json(path: Path, description: str, *, max_bytes: int | None = None) -> Any:
    try:
        if max_bytes is None:
            source = path.read_text(encoding='utf-8')
        else:
            with path.open('rb') as stream:
                data = stream.read(max_bytes + 1)
            if len(data) > max_bytes:
                raise WikiError(f'{description} exceeds the gallery size limit')
            source = data.decode('utf-8')
        return json.loads(source)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise WikiError(f'Cannot read {description}: {path}: {exc}') from exc


def https_url(value: Any) -> bool:
    if not isinstance(value, str) or any(character.isspace() for character in value):
        return False
    parsed = urlparse(value)
    return (parsed.scheme == 'https' and bool(parsed.netloc) and not parsed.username
            and not parsed.password and not parsed.fragment)


def release_url(value: Any, filename: str) -> bool:
    if not https_url(value):
        return False
    parsed = urlparse(value)
    return (parsed.hostname == 'github.com' and parsed.query == ''
            and parsed.path.startswith('/zabaglione/jr200-dev/releases/download/')
            and PurePosixPath(parsed.path).name == filename)


def semantic_version(value: Any) -> tuple[int, int, int] | None:
    match = SEMVER.fullmatch(value) if isinstance(value, str) else None
    return tuple(int(match.group(index)) for index in range(1, 4)) if match else None


def commit_is_ancestor(root: Path, ancestor: Any, descendant: Any) -> bool:
    if (not isinstance(ancestor, str) or not isinstance(descendant, str)
            or re.fullmatch(r'[0-9a-f]{40}', ancestor) is None
            or re.fullmatch(r'[0-9a-f]{40}', descendant) is None):
        return False
    try:
        result = subprocess.run(
            ['git', 'merge-base', '--is-ancestor', ancestor, descendant], cwd=root,
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, check=False,
            timeout=10)
    except (OSError, subprocess.SubprocessError) as exc:
        raise WikiError(f'Cannot verify published source ancestry: {exc}') from exc
    if result.returncode not in (0, 1):
        raise WikiError('Cannot verify published source ancestry')
    return result.returncode == 0


def catalog_entries(root: Path) -> list[dict[str, Any]]:
    catalog = read_json(root / 'games/catalog.json', 'game catalog')
    if (not isinstance(catalog, dict)
            or set(catalog) != {'schema_version', 'games'}
            or catalog['schema_version'] != 2
            or not isinstance(catalog['games'], list)):
        raise WikiError('Unsupported game catalog')
    entries = []
    identifiers = set()
    slugs = set()
    expected_fields = {'id', 'project', 'status', 'version', 'genre',
                       'artifact_sha256', 'package', 'wiki'}
    for item in catalog['games']:
        if not isinstance(item, dict) or set(item) != expected_fields:
            raise WikiError('Invalid game catalog entry fields')
        identifier = item['id']
        project_text = item['project']
        package = item['package']
        wiki = item['wiki']
        screenshot = wiki.get('screenshot') if isinstance(wiki, dict) else None
        if (not isinstance(identifier, str) or SAFE_ID.fullmatch(identifier) is None
                or identifier in identifiers
                or project_text != f'games/{identifier}'
                or item['status'] not in ('draft', 'candidate', 'verified')
                or not isinstance(item['version'], str)
                or not isinstance(item['genre'], str)
                or SAFE_ID.fullmatch(item['genre']) is None
                or not isinstance(item['artifact_sha256'], str)
                or HEX64.fullmatch(item['artifact_sha256']) is None
                or not isinstance(package, dict)
                or set(package) != {'file', 'sha256', 'release_url'}
                or package['file'] != f'{identifier}-{item["version"]}.zip'
                or not isinstance(package['sha256'], str)
                or HEX64.fullmatch(package['sha256']) is None
                or (package['release_url'] is not None
                    and not release_url(package['release_url'], package['file']))
                or not isinstance(wiki, dict)
                or set(wiki) != {'slug', 'publish', 'play_url', 'screenshot'}
                or not isinstance(wiki['slug'], str)
                or SAFE_ID.fullmatch(wiki['slug']) is None
                or wiki['slug'] in slugs
                or type(wiki['publish']) is not bool
                or (wiki['play_url'] is not None
                    and (not wiki['publish']
                         or wiki['play_url'] not in (
                             f'{EMULATOR_URL}?game={identifier}',
                             f'{EMULATOR_URL}?game={identifier}&launch=1')))
                or not isinstance(screenshot, dict)
                or set(screenshot) != {'file', 'sha256', 'framebuffer_sha256',
                                       'profile'}
                or not isinstance(screenshot['file'], str)
                or re.fullmatch(r'media/[a-z][a-z0-9-]{0,31}\.png',
                                screenshot['file']) is None
                or not isinstance(screenshot['sha256'], str)
                or HEX64.fullmatch(screenshot['sha256']) is None
                or not isinstance(screenshot['framebuffer_sha256'], str)
                or HEX64.fullmatch(screenshot['framebuffer_sha256']) is None
                or not isinstance(screenshot['profile'], str)
                or SAFE_ID.fullmatch(screenshot['profile']) is None
                or (wiki['publish'] and item['status'] != 'verified')
                or (wiki['publish'] and package['release_url'] is None)):
            raise WikiError(f'Invalid game catalog entry: {identifier!r}')
        project = (root / project_text).resolve()
        try:
            project.relative_to(root.resolve())
            spec = validate_project(project, root / 'rules/jr200.json', root)
        except (ValueError, ProjectError) as exc:
            raise WikiError(f'{identifier}: invalid project: {exc}') from exc
        metadata = spec.metadata
        if (metadata['schema_version'] != 2
                or metadata['id'] != identifier
                or metadata['version'] != item['version']
                or metadata['genre'] != item['genre']
                or metadata['release']['status'] != item['status']
                or ((metadata['release']['publication'] == 'published')
                    != wiki['publish'])):
            raise WikiError(f'{identifier}: catalog and game metadata disagree')
        screenshot_path = project / screenshot['file']
        if not screenshot_path.is_file() or screenshot_path.is_symlink():
            raise WikiError(f'{identifier}: fixed screenshot is missing')
        screenshot_bytes = screenshot_path.read_bytes()
        try:
            width, height, pixels = decode_rgba(screenshot_bytes)
        except PngError as exc:
            raise WikiError(f'{identifier}: invalid screenshot: {exc}') from exc
        if (sha256_file(screenshot_path) != screenshot['sha256']
                or (width, height) != (320, 224)
                or hashlib.sha256(pixels).hexdigest()
                != screenshot['framebuffer_sha256']):
            raise WikiError(f'{identifier}: screenshot hash contract mismatch')
        identifiers.add(identifier)
        slugs.add(wiki['slug'])
        entries.append({**item, '_metadata': metadata, '_project': project,
                        '_spec': spec,
                        '_screenshot': screenshot_bytes})
    return entries


def safe_archive_names(archive: zipfile.ZipFile) -> list[str]:
    infos = archive.infolist()
    names = [item.filename for item in infos]
    if len(names) != len(set(names)):
        raise WikiError('Package contains duplicate archive entries')
    total = 0
    for item in infos:
        name = item.filename
        path = PurePosixPath(name)
        mode = (item.external_attr >> 16) & 0o170000
        if (not name or path.is_absolute() or '\\' in name
                or any(part in ('', '.', '..') for part in path.parts)
                or item.is_dir() or mode not in (0, 0o100000)
                or item.file_size > 20_000_000
                or (item.file_size > 1_000_000
                    and item.file_size > max(item.compress_size, 1) * 1000)):
            raise WikiError(f'Package contains an unsafe path: {name!r}')
        total += item.file_size
    if total > 50_000_000:
        raise WikiError('Package uncompressed size exceeds the limit')
    if archive.testzip() is not None:
        raise WikiError('Package contains a corrupt member')
    return names


def package_sums(archive: zipfile.ZipFile, prefix: str,
                 names: set[str]) -> None:
    checksum_name = prefix + 'SHA256SUMS'
    try:
        lines = archive.read(checksum_name).decode('ascii').splitlines()
    except (KeyError, UnicodeDecodeError) as exc:
        raise WikiError('Package checksum manifest cannot be read') from exc
    expected = names - {checksum_name}
    recorded = {}
    for line in lines:
        match = re.fullmatch(r'([0-9a-f]{64})  ([^\r\n]+)', line)
        if match is None:
            raise WikiError('Package checksum manifest is invalid')
        name = prefix + match.group(2)
        if name in recorded or name not in expected:
            raise WikiError('Package checksum manifest has an unexpected path')
        recorded[name] = match.group(1)
    if set(recorded) != expected:
        raise WikiError('Package checksum manifest is incomplete')
    for name, digest in recorded.items():
        if hashlib.sha256(archive.read(name)).hexdigest() != digest:
            raise WikiError(f'Package member hash mismatch: {name}')


def validate_runtime_report(entry: dict[str, Any], release: dict[str, Any],
                            record: Any, payload: bytes) -> dict[str, Any]:
    expected_fields = {'profile', 'mode', 'evidence', 'report', 'report_sha256'}
    if (not isinstance(record, dict) or set(record) != expected_fields
            or not isinstance(record['profile'], str)
            or SAFE_ID.fullmatch(record['profile']) is None
            or record['mode'] not in ('synthetic-injection', 'rom-cassette')
            or record['evidence'] not in ('emulator', 'emulator_with_local_rom')
            or record['report'] != f'VERIFICATION/{record["profile"]}.json'
            or not isinstance(record['report_sha256'], str)
            or HEX64.fullmatch(record['report_sha256']) is None
            or hashlib.sha256(payload).hexdigest() != record['report_sha256']):
        raise WikiError(f'{entry["id"]}: invalid runtime profile record')
    try:
        value = json.loads(payload.decode('utf-8'))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise WikiError(f'{entry["id"]}: invalid runtime report JSON') from exc
    result = value.get('result', {}) if isinstance(value, dict) else {}
    runner = value.get('runner', {}) if isinstance(value, dict) else {}
    verification = value.get('verification', {}) if isinstance(value, dict) else {}
    expected_evidence = ('emulator' if record['mode'] == 'synthetic-injection'
                         else 'emulator_with_local_rom')
    expected_cassette = ('memory_injection' if record['mode'] == 'synthetic-injection'
                         else 'normal')
    if (not isinstance(value, dict) or value.get('schema_version') != 1
            or value.get('project') != entry['id']
            or value.get('profile') != record['profile']
            or value.get('mode') != record['mode']
            or value.get('artifact_sha256') != entry['artifact_sha256']
            or not isinstance(value.get('expectations_sha256'), str)
            or HEX64.fullmatch(value['expectations_sha256']) is None
            or result.get('status') != 'passed'
            or result.get('profile') != record['profile']
            or result.get('mode') != record['mode']
            or result.get('evidence') != expected_evidence
            or result.get('artifact_sha256') != entry['artifact_sha256']
            or result.get('hardware') != 'not_run'
            or verification.get('emulator') != 'passed'
            or verification.get('hardware') != 'not_run'
            or verification.get('cassette_path') != expected_cassette
            or runner.get('version')
            != release.get('compatibility', {}).get('runner_version')
            or runner.get('source_revision')
            != release.get('compatibility', {}).get('emulator_source_revision')):
        raise WikiError(f'{entry["id"]}: runtime report contract mismatch')
    return value


def package_path(root: Path, entry: dict[str, Any], packages: Path | None) -> Path:
    if packages is not None:
        directory = packages.resolve()
        path = (directory / entry['package']['file']).resolve()
        try:
            path.relative_to(directory)
        except ValueError as exc:
            raise WikiError('Package path leaves the package directory') from exc
        return path
    return entry['_project'] / 'build/package' / entry['package']['file']


def package_license_paths(root: Path, entry: dict[str, Any]) -> dict[str, Path]:
    if entry['_metadata']['license'] == 'BSD-3-Clause':
        return {'LICENSE': root / 'LICENSE'}
    paths = {'LICENSE': entry['_project'] / 'LICENSE'}
    if entry['_spec'].sdk_inputs:
        paths['THIRD_PARTY_NOTICES.md'] = entry['_project'] / 'THIRD_PARTY_NOTICES.md'
        paths['LICENSES/BSD-3-Clause.txt'] = root / 'LICENSE'
    return paths


def load_package(root: Path, entry: dict[str, Any], packages: Path | None,
                 require_release_ready: bool,
                 expected_commit: str | None = None) -> dict[str, Any]:
    path = package_path(root, entry, packages)
    if not path.is_file() or path.is_symlink():
        raise WikiError(f'{entry["id"]}: fixed package is missing')
    if sha256_file(path) != entry['package']['sha256']:
        raise WikiError(f'{entry["id"]}: package hash mismatch')
    prefix = f'{entry["id"]}-{entry["version"]}/'
    license_paths = package_license_paths(root, entry)
    fixed = {
        prefix + name for name in (
            'BUILD_REPORT.json', 'README.md', 'RELEASE.json',
            'SHA256SUMS', 'game.json', entry['_metadata']['distribution']['file'])
    }
    fixed.update(prefix + name for name in license_paths)
    try:
        with zipfile.ZipFile(path) as archive:
            names = set(safe_archive_names(archive))
            if not fixed.issubset(names):
                raise WikiError(f'{entry["id"]}: package is missing required files')
            release = json.loads(archive.read(prefix + 'RELEASE.json').decode('utf-8'))
            metadata = json.loads(archive.read(prefix + 'game.json').decode('utf-8'))
            build_report = json.loads(
                archive.read(prefix + 'BUILD_REPORT.json').decode('utf-8'))
            archive.read(prefix + 'README.md').decode('utf-8')
            for name, license_path in license_paths.items():
                if archive.read(prefix + name) != license_path.read_bytes():
                    raise WikiError(f'{entry["id"]}: package license or notice mismatch')
            artifact = archive.read(prefix + entry['_metadata']['distribution']['file'])
            parsed_artifact = parse_cjr(artifact)
            packaged_metadata = validate_metadata(metadata, entry['_spec'].config)
            runtime_records = (release.get('verification', {}).get('runtime_profiles', [])
                               if isinstance(release, dict) else [])
            if not isinstance(runtime_records, list) or len(runtime_records) < 2:
                raise WikiError(f'{entry["id"]}: runtime evidence is incomplete')
            reports = {}
            report_names = set()
            for record in runtime_records:
                report_name = (record.get('report') if isinstance(record, dict)
                               else None)
                archive_name = prefix + report_name if isinstance(report_name, str) else ''
                if archive_name not in names or archive_name in report_names:
                    raise WikiError(f'{entry["id"]}: runtime report is missing or duplicated')
                report_names.add(archive_name)
                reports[record['profile']] = validate_runtime_report(
                    entry, release, record, archive.read(archive_name))
            if names != fixed | report_names:
                raise WikiError(f'{entry["id"]}: package has unexpected members')
            package_sums(archive, prefix, names)
    except (OSError, zipfile.BadZipFile, UnicodeDecodeError, json.JSONDecodeError,
            ProjectError) as exc:
        raise WikiError(f'{entry["id"]}: package cannot be inspected: {exc}') from exc
    profiles = release.get('verification', {}).get('runtime_profiles', [])
    evidence = {item.get('evidence') for item in profiles if isinstance(item, dict)}
    source = release.get('source', {})
    artifact_record = release.get('artifact', {})
    compatibility = release.get('compatibility', {})
    runner_version = semantic_version(compatibility.get('runner_version'))
    minimum_runner = semantic_version(
        entry['_metadata']['release']['minimum_runner_version'])
    screenshot_profile = entry['wiki']['screenshot']['profile']
    screenshot_report = reports.get(screenshot_profile, {}).get('result', {})
    expectation_hashes = {
        value.get('expectations_sha256') for value in reports.values()
        if isinstance(value, dict)
    }
    entry_address = address(entry['_metadata']['run']['entry_address'], 'entry address')
    artifact_blocks = parsed_artifact['blocks']
    immutable_metadata = {
        key for key in entry['_metadata'] if key not in ('title', 'summary', 'genre')
    }
    source_is_eligible = (not require_release_ready or commit_is_ancestor(
        root, source.get('commit'), expected_commit))
    if (not isinstance(release, dict) or release.get('schema_version') != 1
            or any(packaged_metadata.get(key) != entry['_metadata'].get(key)
                   for key in immutable_metadata)
            or release.get('project') != entry['id']
            or release.get('version') != entry['version']
            or release.get('status') != entry['status']
            or artifact_record.get('file') != entry['_metadata']['distribution']['file']
            or artifact_record.get('sha256') != entry['artifact_sha256']
            or artifact_record.get('size') != len(artifact)
            or hashlib.sha256(artifact).hexdigest() != entry['artifact_sha256']
            or not artifact_blocks
            or artifact_blocks[0].start
            != address(entry['_metadata']['load']['address'], 'load address')
            or not any(block.start <= entry_address <= block.end
                       for block in artifact_blocks)
            or build_report.get('schema_version') != 1
            or build_report.get('project') != entry['id']
            or build_report.get('artifact', {}).get('sha256')
            != entry['artifact_sha256']
            or build_report.get('verification', {}).get('assembler') != 'passed'
            or build_report.get('verification', {}).get('cjr_layout') != 'passed'
            or release.get('license') != entry['_metadata']['license']
            or release.get('wav') != entry['_metadata']['release']['wav']
            or release.get('publication') != entry['_metadata']['release']['publication']
            or release.get('verification', {}).get('hardware') != 'not_run'
            or evidence != {'emulator', 'emulator_with_local_rom'}
            or len(reports) != len(profiles)
            or screenshot_report.get('mode') not in ('synthetic-injection',
                                                    'rom-cassette')
            or screenshot_report.get('framebuffer_sha256')
            != entry['wiki']['screenshot']['framebuffer_sha256']
            or compatibility.get('sdk_contract')
            != entry['_metadata']['release']['sdk_contract']
            or compatibility.get('runner_contract')
            != entry['_metadata']['release']['runner_contract']
            or runner_version is None or minimum_runner is None
            or runner_version < minimum_runner
            or compatibility.get('jrasm_version')
            != build_report.get('toolchain', {}).get('version')
            or compatibility.get('jrasm_revision')
            != build_report.get('toolchain', {}).get('revision')
            or not isinstance(compatibility.get('emulator_source_revision'), str)
            or re.fullmatch(r'[0-9a-f]{40}', compatibility['emulator_source_revision']) is None
            or not isinstance(source.get('commit'), str)
            or re.fullmatch(r'[0-9a-f]{40}', source['commit']) is None
            or source.get('repository') != 'https://github.com/zabaglione/jr200-dev'
            or source.get('tree_state') not in ('clean', 'dirty')
            or not isinstance(source.get('snapshot_sha256'), str)
            or HEX64.fullmatch(source['snapshot_sha256']) is None
            or not isinstance(source.get('expectations_sha256'), str)
            or HEX64.fullmatch(source['expectations_sha256']) is None
            or expectation_hashes != {source['expectations_sha256']}
            or type(release.get('release_ready')) is not bool
            or release.get('release_ready') != (source.get('tree_state') == 'clean')
            or (require_release_ready and release.get('release_ready') is not True)
            or not source_is_eligible):
        raise WikiError(f'{entry["id"]}: package release contract mismatch')
    return {
        'release': release,
        'readme': (entry['_project'] / 'README.md').read_text(encoding='utf-8'),
        'path': path,
    }


TIERS = {
    'published': '公開',
    'candidate': '候補版（非公開プレビュー）',
    'development': '開発中（非公開プレビュー）',
}
SCENE_ROLES = ('title', 'play', 'goal')
MEDIA_NAME = re.compile(r'[a-z][a-z0-9-]{0,31}\.(png|webm)')
README_REQUIRED = ('目的と勝敗', '操作', '起動', '検証の範囲', 'ライセンス')
DEVELOPER_DOCS = (
    ('docs/DEVELOPMENT.md', '開発環境と作業の流れ'),
    ('docs/JRASM.md', 'jrasm（外部アセンブラ）の導入'),
    ('docs/PROJECTS.md', '作品プロジェクトの構成とbuild'),
    ('docs/RUNNER.md', '固定エミュレータrunnerと期待値'),
    ('docs/PORTING.md', 'JR-100作品の移植契約'),
    ('rules/README.md', 'JR-200の規則データ'),
    ('samples', 'SDKのサンプル'),
)
LINK = re.compile(r'\]\(([^)\s]*)\)')
ATTRIBUTE_LINK = re.compile(r'\b(?:src|href)="([^"]*)"')
IMAGE_TAG = re.compile(r'<img\b[^>]*>')
FENCE = re.compile(r'^```.*?^```[^\n]*$', re.MULTILINE | re.DOTALL)


def load_genres(path: Path = GENRES) -> list[dict[str, str]]:
    value = read_json(path, 'genre definitions')
    if (not isinstance(value, dict) or set(value) != {'schema_version', 'genres'}
            or value['schema_version'] != 1 or not isinstance(value['genres'], list)):
        raise WikiError('Invalid genre definitions')
    genres = []
    for item in value['genres']:
        if (not isinstance(item, dict)
                or set(item) != {'id', 'page', 'title', 'description'}
                or not isinstance(item['id'], str)
                or SAFE_ID.fullmatch(item['id']) is None
                or item['page'] != 'Genre-' + item['id'].capitalize()
                or not all(isinstance(item[key], str) and item[key].strip()
                           for key in ('title', 'description'))
                or item['id'] in {genre['id'] for genre in genres}):
            raise WikiError('Invalid genre definition')
        genres.append(item)
    return genres


def runtime_profiles(project: Path, *, max_bytes: int | None = None) -> dict[str, dict[str, Any]]:
    value = read_json(project / 'tests/expectations.json', 'runtime expectations',
                      max_bytes=max_bytes)
    try:
        return {item['profile']: item for item in value['runtime']['profiles']}
    except (TypeError, KeyError) as exc:
        raise WikiError(f'{project.name}: invalid runtime expectations') from exc


def load_gallery(project: Path) -> dict[str, Any] | None:
    """Verified scenes and video tied to fixed ROM-less synthetic profiles."""
    path = project / 'media/gallery.json'
    if not path.exists():
        return None
    if path.is_symlink():
        raise WikiError(f'{project.name}: gallery manifest is a symlink')
    value = read_json(path, 'gallery manifest', max_bytes=MAX_GALLERY_BYTES)
    profiles = runtime_profiles(project, max_bytes=MAX_GALLERY_BYTES)
    if (not isinstance(value, dict) or value.get('schema_version') not in (1, 2)
            or not set(value) <= {'schema_version', 'capture', 'scenes', 'video'}
            or not isinstance(value.get('scenes'), list) or not value['scenes']):
        raise WikiError(f'{project.name}: invalid gallery manifest')
    capture = value.get('capture')
    if value['schema_version'] == 1:
        if capture is not None:
            raise WikiError(f'{project.name}: legacy gallery has unexpected capture data')
        capture_mode = 'synthetic-injection'
    else:
        source = ROOT / 'sdk/font_data.inc'
        if (not isinstance(capture, dict)
                or set(capture) != {'mode', 'artifact_sha256', 'glyph_source',
                                    'glyph_source_sha256'}
                or capture['mode'] != 'rom-cassette'
                or capture['glyph_source'] != 'sdk/font_data.inc'
                or not source.is_file()
                or sha256_file(source) != capture['glyph_source_sha256']
                or not isinstance(capture['artifact_sha256'], str)
                or HEX64.fullmatch(capture['artifact_sha256']) is None):
            raise WikiError(f'{project.name}: invalid ROM capture provenance')
        capture_mode = 'rom-cassette'

    def media(file: Any, suffix: str) -> bytes:
        match = MEDIA_NAME.fullmatch(file) if isinstance(file, str) else None
        if match is None or match.group(1) != suffix:
            raise WikiError(f'{project.name}: unsafe gallery file name: {file!r}')
        target = project / 'media' / file
        if not target.is_file() or target.is_symlink():
            raise WikiError(f'{project.name}: gallery file is missing: {file}')
        with target.open('rb') as stream:
            data = stream.read(MAX_GALLERY_BYTES + 1)
        if len(data) > MAX_GALLERY_BYTES:
            raise WikiError(f'{project.name}: gallery media exceeds the size limit')
        return data

    def capture_profile(profile: Any) -> dict[str, Any]:
        record = profiles.get(profile) if isinstance(profile, str) else None
        if record is None or record.get('mode') != capture_mode:
            raise WikiError(f'{project.name}: gallery profile mode mismatch: '
                            f'{profile!r}')
        return record

    scenes = []
    for scene in value['scenes']:
        if (not isinstance(scene, dict)
                or set(scene) != {'id', 'file', 'profile', 'role', 'caption',
                                  'sha256', 'framebuffer_sha256'}
                or not isinstance(scene['id'], str)
                or SAFE_ID.fullmatch(scene['id']) is None
                or scene['id'] in {item['id'] for item in scenes}
                or scene['role'] not in SCENE_ROLES
                or not isinstance(scene['caption'], str) or not scene['caption'].strip()):
            raise WikiError(f'{project.name}: invalid gallery scene')
        data = media(scene['file'], 'png')
        try:
            width, height, pixels = decode_rgba(data)
        except PngError as exc:
            raise WikiError(f'{project.name}: invalid gallery image: {exc}') from exc
        framebuffer = hashlib.sha256(pixels).hexdigest()
        if (hashlib.sha256(data).hexdigest() != scene['sha256']
                or (width, height) != (320, 224)
                or framebuffer != scene['framebuffer_sha256']
                or capture_profile(scene['profile'])['expect'].get('framebuffer_sha256')
                != framebuffer):
            raise WikiError(f'{project.name}: gallery scene {scene["id"]} does not match '
                            'its fixed framebuffer')
        scenes.append({**scene, 'bytes': data})
    video = value.get('video')
    if video is not None:
        fields = {'file', 'profile', 'fps', 'speed', 'seconds', 'frames',
                  'frames_sha256', 'pcm_sha256', 'sha256', 'caption'}
        if capture_mode == 'rom-cassette':
            fields |= {'mode', 'artifact_sha256', 'start_cycle'}
        if (not isinstance(video, dict) or set(video) != fields
                or not isinstance(video['caption'], str) or not video['caption'].strip()
                or not all(isinstance(video[key], (int, float)) and video[key] > 0
                           for key in ('fps', 'speed', 'seconds', 'frames'))
                or video['seconds'] > 60):
            raise WikiError(f'{project.name}: invalid gallery video')
        profile = capture_profile(video['profile'])
        if capture_mode == 'rom-cassette' and (
                video['mode'] != capture_mode
                or video['artifact_sha256'] != capture['artifact_sha256']
                or not isinstance(video['start_cycle'], int)
                or not 0 < video['start_cycle'] < profile['max_cycles']):
            raise WikiError(f'{project.name}: invalid ROM video provenance')
        data = media(video['file'], 'webm')
        if data[:4] != b'\x1a\x45\xdf\xa3' or hashlib.sha256(data).hexdigest() != video['sha256']:
            raise WikiError(f'{project.name}: gallery video hash mismatch')
        video = {**video, 'bytes': data}
    return {'scenes': scenes, 'video': video, 'capture': capture}


def readme_parts(value: str) -> tuple[str, list[tuple[str, str]]]:
    """Split a README into its intro and level-2 sections, ignoring fenced code."""
    lines = value.strip().splitlines()
    if lines and lines[0].startswith('# '):
        lines = lines[1:]
    intro: list[str] = []
    sections: list[tuple[str, list[str]]] = []
    fenced = False
    for line in lines:
        if line.startswith('```'):
            fenced = not fenced
        if not fenced and line.startswith('## '):
            sections.append((line[3:].strip(), []))
        elif sections:
            sections[-1][1].append(line)
        else:
            intro.append(line)
    return ('\n'.join(intro).strip(),
            [(title, '\n'.join(body).strip()) for title, body in sections])


def rewrite_readme(value: str, project: str) -> str:
    """Demote headings and point README-relative links at the source repository."""
    output = []
    fenced = False
    for line in value.splitlines():
        if line.startswith('```'):
            fenced = not fenced
        if not fenced and line.startswith('#'):
            line = '#' + line
        if not fenced:
            def replace(match: re.Match[str]) -> str:
                target = match.group(1)
                if target.startswith(('https://', '#')) or not target:
                    return match.group(0)
                path = PurePosixPath(project, target)
                parts: list[str] = []
                for part in path.parts:
                    if part == '..':
                        if not parts:
                            raise WikiError(f'{project}: README link leaves the repository')
                        parts.pop()
                    elif part != '.':
                        parts.append(part)
                return f']({SOURCE_URL}{"/".join(parts)})'
            line = LINK.sub(replace, line)
        output.append(line)
    return '\n'.join(output)


def join_lines(lines: list[str]) -> str:
    text = ''
    for line in (line.strip() for line in lines):
        if text and line and text[-1].isascii() and line[0].isascii():
            text += ' '
        text += line
    return text


def first_paragraph(intro: str, fallback: str) -> str:
    paragraph = intro.split('\n\n', 1)[0].strip()
    return join_lines(paragraph.splitlines()) if paragraph else fallback


def first_sentence(paragraph: str) -> str:
    end = paragraph.find('。')
    return paragraph if end < 0 else paragraph[:end + 1]


def development_entries(root: Path, catalog_ids: set[str]) -> list[dict[str, Any]]:
    entries = []
    for metadata_path in sorted((root / 'games').glob('*/game.json')):
        project = metadata_path.parent
        if project.name in catalog_ids:
            continue
        if SAFE_ID.fullmatch(project.name) is None or project.is_symlink():
            raise WikiError(f'Unsafe game project directory: {project.name}')
        try:
            spec = validate_project(project, root / 'rules/jr200.json', root)
        except ProjectError as exc:
            raise WikiError(f'{project.name}: invalid project: {exc}') from exc
        metadata = spec.metadata
        if (metadata['schema_version'] != 2 or metadata['id'] != project.name
                or metadata['release']['status'] != 'draft'
                or metadata['release']['publication'] != 'not-published'):
            raise WikiError(f'{project.name}: games outside the catalog must be '
                            'schema 2, draft and not published')
        gallery = load_gallery(project)
        if gallery is None:
            raise WikiError(f'{project.name}: development preview requires a gallery')
        readme = (project / 'README.md').read_text(encoding='utf-8')
        titles = {title for title, _ in readme_parts(readme)[1]}
        missing = [title for title in README_REQUIRED if title not in titles]
        if missing:
            raise WikiError(f'{project.name}: README lacks sections: {", ".join(missing)}')
        thumbnail = next((scene for scene in gallery['scenes'] if scene['role'] == 'play'),
                         gallery['scenes'][0])
        entries.append({
            'id': project.name, 'version': metadata['version'], 'status': 'draft',
            'genre': metadata['genre'], 'tier': 'development',
            'wiki': {'slug': project.name, 'publish': False, 'play_url': None},
            '_metadata': metadata, '_project': project, '_spec': spec,
            '_gallery': gallery, '_thumbnail': thumbnail['bytes'],
            '_thumbnail_scene': thumbnail['id'], '_readme': readme, '_package': None,
        })
    return entries


def card(entry: dict[str, Any], genre: dict[str, str]) -> list[str]:
    title = entry['_metadata']['title']
    slug = entry['wiki']['slug']
    alt = html.escape(f'{title}のゲーム画面', quote=True)
    links = [f'[遊び方と画面](Game-{slug})']
    if entry['wiki']['play_url'] is not None:
        links.append(f'[遊ぶ]({entry["wiki"]["play_url"]})')
    return [
        f'### [{title}](Game-{slug})', '',
        f'<a href="Game-{slug}"><img src="media/{slug}.png" alt="{alt}" width="320"></a>', '',
        first_sentence(entry['_intro']), '',
        f'- ジャンル: [{genre["title"]}]({genre["page"]}) / 版: `{entry["version"]}` / '
        f'状態: {TIERS[entry["tier"]]}',
        '- ' + ' / '.join(links), '',
    ]


def tier_sections(entries: list[dict[str, Any]], genres: dict[str, dict[str, str]],
                  empty: str) -> list[str]:
    lines = ['## 公開作品', '']
    published = [entry for entry in entries if entry['tier'] == 'published']
    if not published:
        lines.extend([empty, ''])
    for entry in published:
        lines.extend(card(entry, genres[entry['genre']]))
    for tier in ('candidate', 'development'):
        selected = [entry for entry in entries if entry['tier'] == tier]
        if selected:
            lines.extend([f'## {TIERS[tier]}', '',
                          '> 公開作品ではありません。CJRとパッケージは配布していません。', ''])
            for entry in selected:
                lines.extend(card(entry, genres[entry['genre']]))
    return lines


def verification_rows(entry: dict[str, Any]) -> list[str]:
    profiles = runtime_profiles(entry['_project'])
    synthetic = sum(1 for item in profiles.values() if item.get('mode') == 'synthetic-injection')
    local = sum(1 for item in profiles.values() if item.get('mode') == 'rom-cassette')
    package = entry['_package']
    if package is None:
        rom = ('profile定義あり、実行記録なし' if local else 'profileなし')
    else:
        rom = '固定パッケージに実行記録あり'
    return [f'| ROMなし合成実行（固定エミュレータ） | {synthetic} profileの期待値 |',
            f'| 所有ROM/FONTでの通常MLOAD/USR | {rom} |',
            '| 物理JR-200 | 未実施 |']


def license_link(entry: dict[str, Any]) -> str:
    if entry['_metadata']['license'] == 'BSD-3-Clause':
        return f'[BSD-3-Clause]({SOURCE_URL}LICENSE)'
    license_id = entry['_metadata']['license']
    return (f'[{license_id}]({SOURCE_URL}games/{entry["id"]}/LICENSE)。'
            '組み込むSDKはBSD-3-Clause')


def render_game(entry: dict[str, Any], genre: dict[str, str]) -> str:
    metadata = entry['_metadata']
    slug = entry['wiki']['slug']
    title = metadata['title']
    package = entry['_package']
    lines = [f'# {title}', '', f'[Home](Home) › [{genre["title"]}]({genre["page"]}) › {title}', '']
    if entry['tier'] == 'candidate':
        lines.extend(['> 非公開の候補版プレビューです。公開ダウンロードはありません。', ''])
    elif entry['tier'] == 'development':
        lines.extend(['> 開発中の版のプレビューです。CJRとパッケージは配布していません。', ''])
    lines.extend([entry['_intro'], '',
                  '| 項目 | 内容 |', '| --- | --- |',
                  f'| 状態 | {TIERS[entry["tier"]]} |',
                  f'| 版 | `{entry["version"]}` |',
                  f'| ジャンル | [{genre["title"]}]({genre["page"]}) |',
                  f'| ライセンス | {license_link(entry)} |'])
    if package is not None:
        lines.extend([f'| CJR SHA-256 | `{entry["artifact_sha256"]}` |',
                      f'| Package SHA-256 | `{entry["package"]["sha256"]}` |'])
    lines.extend([f'| 起動 | `{metadata["distribution"]["file"]}`を`MLOAD`し、'
                  f'`{metadata["run"]["command"]}` |', '', '## 遊ぶ', ''])
    if entry['tier'] == 'development':
        lines.extend(['配布前の開発版です。開発者は'
                      f'[作品プロジェクトの手順]({SOURCE_URL}docs/PROJECTS.md)でCJRをbuildし、'
                      'ローカルで確認できます。', ''])
    elif entry['package']['release_url'] is None:
        lines.extend(['パッケージは公開していません。手元でbuildしたCJRを手動で読み込みます。', ''])
    else:
        lines.extend([f'[固定パッケージをダウンロード]({entry["package"]["release_url"]})', ''])
    if entry['tier'] != 'development':
        if entry['wiki']['play_url'] is None:
            lines.extend([f'[Webエミュレータを開く]({EMULATOR_URL})（CJRは手動で選択）。',
                          '[CJRのセットと実行手順](Play)。',
                          '作品IDによるワンクリックのセットは、この版の公開CJRとURLの到達性が'
                          '確認されるまで無効です。', ''])
        else:
            if entry['wiki']['play_url'].endswith('&launch=1'):
                lines.extend([f'[遊ぶ（起動支援）]({entry["wiki"]["play_url"]})',
                              '保存済みの対応ROM・フォントがあれば、通常MLOADと作品固有USRを'
                              '自動入力します。初回は手元のROM・フォントを選択してください。'
                              '未対応ROMや失敗時は手動実行できます。[詳しい手順](Play)。', ''])
            else:
                lines.extend([f'[エミュレータにCJRをセット]({entry["wiki"]["play_url"]})',
                              'ROM・フォントは利用者が用意し、セット後にMLOADと作品の実行コマンドを'
                              '入力してください。[詳しい手順](Play)。', ''])
    lines.extend(['## 画面', ''])
    for scene in entry['_scenes']:
        alt = html.escape(f'{title}: {scene["caption"]}', quote=True)
        lines.extend([f'<img src="{scene["path"]}" alt="{alt}" width="640">', '',
                      scene['caption'], ''])
    gallery = entry['_gallery']
    rom_capture = (gallery is not None and gallery.get('capture') is not None
                   and gallery['capture']['mode'] == 'rom-cassette')
    if rom_capture:
        lines.extend(['所有ROM/FONTをローカルで読み込み、通常MLOAD/USRで実行した'
                      '固定エミュレータの320×224画面です。画面の文字は作品の自作字形です。'
                      '物理JR-200での表示は未確認です。', ''])
    else:
        lines.extend(['固定エミュレータのROMなし合成実行から取得した320×224の画面です。'
                      '物理JR-200での表示は未確認です。', ''])
    video = entry['_video']
    if video is not None:
        speed = '等速' if video['speed'] == 1 else f'{video["speed"]}倍速'
        lines.extend(['## 動画', '',
                      f'[{video["caption"]}]({video["path"]})（WebM、音付き、'
                      f'{video["seconds"]}秒、{speed}）', '',
                      '映像と音は固定エミュレータが同じreplayで出力したもので、後から描き足したり'
                      '音を差し替えたりしていません。', ''])
    guide = '\n\n'.join(f'## {heading}\n\n{body}'
                          for heading, body in readme_parts(entry['_readme'])[1])
    lines.extend(['## 遊び方', '',
                  (rewrite_readme(guide, f'games/{entry["id"]}').rstrip()
                   or '作品のREADMEを参照してください。'),
                  '', '## 版と検証', '', '| 区分 | 状態 |', '| --- | --- |',
                  *verification_rows(entry), ''])
    if package is not None:
        release = package['release']
        lines.extend([f'- Source commit: `{release["source"]["commit"]}`',
                      f'- Source snapshot SHA-256: `{release["source"]["snapshot_sha256"]}`',
                      f'- Runner: `{release["compatibility"]["runner_version"]}`',
                      f'- Emulator source: '
                      f'`{release["compatibility"]["emulator_source_revision"]}`', ''])
    lines.extend(['## ソース', '',
                  f'[作品のソース]({TREE_URL}games/{entry["id"]})・'
                  f'[品質と検証範囲](Quality-Review)・[ライセンス](Licenses)', ''])
    return '\n'.join(lines)


def check_links(root: Path, files: dict[str, bytes]) -> None:
    """Every internal page/media link and repository link must resolve."""
    pages = {name[:-3] for name in files if name.endswith('.md')}
    for name, content in sorted(files.items()):
        if not name.endswith('.md'):
            continue
        text = content.decode('utf-8')
        if not text.startswith('# ') and name != '_Sidebar.md':
            raise WikiError(f'{name}: page must start with a level-1 heading')
        if 'pyjr100emu' in text or re.search(r'\.prg\b', text, re.IGNORECASE):
            raise WikiError(f'{name}: JR-100 play URL or PRG reference')
        scanned = FENCE.sub('', text)
        for tag in IMAGE_TAG.findall(scanned):
            alt = re.search(r'\balt="([^"]*)"', tag)
            if alt is None or not alt.group(1).strip():
                raise WikiError(f'{name}: image without alt text')
        for target in LINK.findall(scanned) + ATTRIBUTE_LINK.findall(scanned):
            if target.startswith('https://'):
                for prefix in (SOURCE_URL, TREE_URL):
                    if target.startswith(prefix):
                        relative = target[len(prefix):].split('#', 1)[0]
                        path = root.joinpath(*PurePosixPath(relative).parts)
                        if not relative or '..' in PurePosixPath(relative).parts or not path.exists():
                            raise WikiError(f'{name}: broken repository link: {target}')
                        break
                else:
                    if not (target.startswith((EMULATOR_URL, UPSTREAM_URL))
                            or release_url(target, PurePosixPath(urlparse(target).path).name)):
                        raise WikiError(f'{name}: link outside the allowed set: {target}')
            elif target.startswith('#'):
                continue
            else:
                base = target.split('#', 1)[0]
                if base.startswith('media/') and base in files:
                    continue
                if base in pages:
                    continue
                raise WikiError(f'{name}: broken Wiki link: {target}')


def render_pages(root: Path, packages: Path | None,
                 include_candidates: bool,
                 expected_commit: str | None = None,
                 include_development: bool = False) -> tuple[dict[str, bytes], list[dict[str, Any]]]:
    genres_list = load_genres()
    genres = {genre['id']: genre for genre in genres_list}
    catalog = catalog_entries(root)
    selected = []
    for entry in catalog:
        if entry['genre'] not in genres:
            raise WikiError(f'{entry["id"]}: unknown genre {entry["genre"]!r}')
        if entry['status'] == 'draft':
            raise WikiError(f'{entry["id"]}: draft games cannot be rendered')
        if entry['wiki']['publish']:
            selected.append({**entry, 'tier': 'published'})
        elif include_candidates and entry['status'] == 'candidate':
            selected.append({**entry, 'tier': 'candidate'})
    for entry in selected:
        entry['_package'] = load_package(
            root, entry, packages, require_release_ready=entry['wiki']['publish'],
            expected_commit=expected_commit)
        entry['_readme'] = entry['_package']['readme']
        entry['_gallery'] = load_gallery(entry['_project'])
        entry['_thumbnail'] = entry['_screenshot']
        entry['_thumbnail_scene'] = None
    if include_development:
        for entry in development_entries(root, {item['id'] for item in catalog}):
            if entry['genre'] not in genres:
                raise WikiError(f'{entry["id"]}: unknown genre {entry["genre"]!r}')
            selected.append(entry)
    files: dict[str, bytes] = {}
    for entry in selected:
        slug = entry['wiki']['slug']
        metadata = entry['_metadata']
        entry['_intro'] = first_paragraph(readme_parts(entry['_readme'])[0], metadata['summary'])
        files[f'media/{slug}.png'] = entry['_thumbnail']
        gallery = entry['_gallery']
        if gallery is None:
            entry['_scenes'] = [{'path': f'media/{slug}.png',
                                 'caption': 'ROMなし合成実行の画面'}]
            entry['_video'] = None
            continue
        entry['_scenes'] = []
        for scene in gallery['scenes']:
            if scene['id'] == entry['_thumbnail_scene']:
                path = f'media/{slug}.png'
            else:
                path = f'media/{slug}-{scene["id"]}.png'
                files[path] = scene['bytes']
            entry['_scenes'].append({'path': path, 'caption': scene['caption']})
        video = gallery['video']
        if video is None:
            entry['_video'] = None
        else:
            path = f'media/{slug}-{PurePosixPath(video["file"]).stem}.webm'
            files[path] = video['bytes']
            entry['_video'] = {**video, 'path': path}
    selected.sort(key=lambda entry: (entry['_metadata']['title'], entry['id']))
    preview = any(entry['tier'] != 'published' for entry in selected)
    published = [entry for entry in selected if entry['tier'] == 'published']
    availability = ('検証済みの公開ゲームはまだありません。' if not published
                    else '検証済みの公開ゲームを作品一覧から選べます。')
    if preview:
        availability += 'この表示は未公開の版を含むローカルプレビューです。配布リンクではありません。'
    counts = {genre: [entry for entry in selected if entry['genre'] == genre]
              for genre in genres}
    genre_rows = ['| ジャンル | 公開作品 | ' + ('プレビュー | ' if preview else '') + '内容 |',
                  '| --- | ---: | ' + ('---: | ' if preview else '') + '--- |']
    for genre in genres_list:
        items = counts[genre['id']]
        public = sum(1 for entry in items if entry['tier'] == 'published')
        extra = f'{len(items) - public} | ' if preview else ''
        genre_rows.append(f'| [{genre["title"]}]({genre["page"]}) | {public} | {extra}'
                          f'{genre["description"]} |')
    developer = [f'- [{label}]({(TREE_URL if not path.endswith(".md") else SOURCE_URL) + path})'
                 for path, label in DEVELOPER_DOCS]
    files['Home.md'] = '\n'.join([
        '# JR-200ゲーム開発 Wiki', '',
        f'JR-200向けに作った・移植したゲームの遊び方と開発情報です。{availability}', '',
        '## はじめての人へ', '',
        '1. [Webエミュレータでの実行手順](Play)で、ROM・フォントの用意とCJRの読み込み方を確認します。',
        '2. [操作](Controls)で作品ごとのキーを確認します。作品によって使うキーが違います。',
        '3. 下のジャンルか[全作品の一覧](All-Games)から作品を選びます。', '',
        '## ジャンル', '', *genre_rows, '',
        *tier_sections(selected, genres, '公開作品準備中'),
        '## もっと知る', '',
        '- [全作品の一覧](All-Games)', '- [映像と音](Presentation)',
        '- [品質と検証範囲](Quality-Review)', '- [ライセンスと配布境界](Licenses)',
        '- [ゲーム一覧（旧ページ）](Games)', '',
        '## 開発者向け', '', *developer, '',
        f'[JR-200 Web Emulatorを開く]({EMULATOR_URL})', '',
    ]).encode('utf-8')
    files['_Sidebar.md'] = '\n'.join([
        '**[Home](Home)**', '', '- [全作品](All-Games)',
        *[f'- [{genre["title"]}]({genre["page"]})' for genre in genres_list],
        '- [操作](Controls)', '- [エミュレータで遊ぶ](Play)', '- [映像と音](Presentation)',
        '- [品質と検証範囲](Quality-Review)', '- [ライセンス](Licenses)',
        f'- [開発者向け]({SOURCE_URL}docs/DEVELOPMENT.md)', '',
    ]).encode('utf-8')
    for genre in genres_list:
        files[f'{genre["page"]}.md'] = '\n'.join([
            f'# {genre["title"]}', '', f'[Home](Home) › {genre["title"]}', '',
            genre['description'], '',
            *tier_sections(counts[genre['id']], genres, '公開作品準備中'),
        ]).encode('utf-8')
    rows = ['| 作品 | ジャンル | 状態 | 版 | 紹介 |', '| --- | --- | --- | --- | --- |']
    for entry in selected:
        genre = genres[entry['genre']]
        rows.append(f'| [{entry["_metadata"]["title"]}](Game-{entry["wiki"]["slug"]}) | '
                    f'[{genre["title"]}]({genre["page"]}) | {TIERS[entry["tier"]]} | '
                    f'`{entry["version"]}` | {first_sentence(entry["_intro"])} |')
    files['All-Games.md'] = '\n'.join([
        '# 全作品', '', '[Home](Home) › 全作品', '',
        'タイトル順の一覧です。' + ('この表示は未公開の版を含むローカルプレビューです。'
                           if preview else ''), '',
        *(rows if selected else ['公開作品準備中']), '',
    ]).encode('utf-8')
    files['Games.md'] = '\n'.join([
        '# ゲーム一覧', '',
        '作品の一覧は[全作品](All-Games)とジャンル別のページにまとめています。', '',
        *[f'- [{genre["title"]}]({genre["page"]})（公開'
          f'{sum(1 for entry in counts[genre["id"]] if entry["tier"] == "published")}件）'
          for genre in genres_list], '',
    ]).encode('utf-8')
    controls = ['# 操作', '', '[Home](Home) › 操作', '',
                '## 共通', '',
                '- 作品ごとに使うキーが違います。全作品がWASDやジョイスティックに対応しているわけではありません。',
                '- CJRを`MLOAD`で読み込み、作品ページの実行コマンド（例: `A=USR($1000)`）で始めます。',
                '- ゲームを終えてBASICへ戻るキーも作品ごとに違います。下の表で確認してください。', '',
                '## 作品別', '']
    for entry in selected:
        body = dict(readme_parts(entry['_readme'])[1]).get('操作')
        controls.extend([f'### [{entry["_metadata"]["title"]}](Game-{entry["wiki"]["slug"]})', '',
                         rewrite_readme(body, f'games/{entry["id"]}') if body
                         else '作品ページの説明を参照してください。', ''])
    if not selected:
        controls.extend(['公開作品準備中', ''])
    files['Controls.md'] = '\n'.join(controls).encode('utf-8')
    presentation = ['# 映像と音', '', '[Home](Home) › 映像と音', '',
                    '各作品の画面と動画は、固定版の[JR-200 Web Emulator](' + EMULATOR_URL + ')で'
                    '決まった操作を再生して記録したものです。撮影時に所有ROM/FONTを使用したかは'
                    '作品ページに記載しています。ROM/FONTそのものは配布しません。音は作品が実際に'
                    '鳴らしたPCMです。速度を変えた動画は倍率を記載します。物理JR-200の'
                    '表示と音は確認していません。', '']
    for entry in selected:
        presentation.extend([f'## [{entry["_metadata"]["title"]}](Game-{entry["wiki"]["slug"]})',
                             '', f'状態: {TIERS[entry["tier"]]}', ''])
        for scene in entry['_scenes']:
            alt = html.escape(f'{entry["_metadata"]["title"]}: {scene["caption"]}', quote=True)
            presentation.extend([f'<img src="{scene["path"]}" alt="{alt}" width="320">', '',
                                 scene['caption'], ''])
        video = entry['_video']
        if video is not None:
            presentation.extend([f'[動画: {video["caption"]}]({video["path"]})'
                                 f'（{video["seconds"]}秒）', ''])
    if not selected:
        presentation.extend(['公開作品準備中', ''])
    files['Presentation.md'] = '\n'.join(presentation).encode('utf-8')
    quality = ['# 品質と検証範囲', '', '[Home](Home) › 品質と検証範囲', '',
               '## 検証の方法', '',
               '- **ROMなし合成実行**: 固定版エミュレータにCJRを直接置き、決まったキー入力を'
               '再生して、メモリ・画面hash・音を期待値と照合します。'
               f'（[runnerの説明]({SOURCE_URL}docs/RUNNER.md)）',
               '- **移植作品の期待値**: JR-100版の規則を写したPythonモデルが計算します。'
               'エミュレータの出力を期待値にはしません。'
               f'（[移植契約]({SOURCE_URL}docs/PORTING.md)）',
               '- **所有ROM/FONTでの実行**: 利用者が権利を持つROM・フォントで通常の`MLOAD`と'
               '`USR`を確かめます。ROM・フォントはリポジトリに含めません。',
               '- **物理JR-200**: どの作品もまだ確認していません。', '',
               '## 作品別', '',
               '| 作品 | 状態 | ROMなし合成実行 | 所有ROM/FONT | 物理JR-200 |',
               '| --- | --- | --- | --- | --- |']
    for entry in selected:
        cells = [row.split(' | ')[1].rstrip(' |') for row in verification_rows(entry)]
        quality.append(f'| [{entry["_metadata"]["title"]}](Game-{entry["wiki"]["slug"]}) | '
                       f'{TIERS[entry["tier"]]} | {" | ".join(cells)} |')
    quality.append('')
    files['Quality-Review.md'] = '\n'.join(quality).encode('utf-8')
    game_rows = [f'| {entry["_metadata"]["title"]} | {license_link(entry)} |'
                 for entry in selected]
    files['Licenses.md'] = '\n'.join([
        '# ライセンスと配布境界', '',
        '| 対象 | ライセンス・確認先 |', '| --- | --- |',
        f'| jr200-devの共通コード・SDK | [BSD-3-Clause]({SOURCE_URL}LICENSE) |',
        *game_rows,
        f'| JR-100版の移植元 | [jr100dev（MIT、固定revision）]({UPSTREAM_URL}games/LICENSE) |',
        f'| Webエミュレータ | [BSD-3-Clause]({EMULATOR_URL}LICENSE.txt)、'
        f'[第三者表記]({EMULATOR_URL}THIRD_PARTY_NOTICES.md) |',
        f'| FIND VJR-200由来部分 | [FINDの原文条件]({EMULATOR_URL}LICENSES/VJR200.txt) |',
        f'| MAME MC6800由来部分 | [BSD-3-Clause]({EMULATOR_URL}LICENSES/MAME_BSD-3-Clause.txt) |',
        f'| Emscripten生成JavaScript | [MIT・UIUC/NCSA]({EMULATOR_URL}LICENSES/Emscripten-6.0.9.txt) |',
        f'| リンクされたlibc++abi | [Apache-2.0 WITH LLVM-exception]'
        f'({EMULATOR_URL}LICENSES/libcxxabi-6.0.9.txt) |',
        '| jrasm | 利用する外部ツール。ライセンス未確認のため再配布しません |', '',
        'メーカーROM・フォント、商用テープ、利用者録音は配布しません。'
        'ゲームのCJRを公開するときは、作品ごとの固定版と含まれるSDKのライセンス全文を確認します。', '',
    ]).encode('utf-8')
    files['Play.md'] = PLAY_PAGE.encode('utf-8')
    for entry in selected:
        files[f'Game-{entry["wiki"]["slug"]}.md'] = render_game(
            entry, genres[entry['genre']]).encode('utf-8')
    check_links(root, files)
    summary = [{
        'id': entry['id'], 'version': entry['version'], 'status': entry['status'],
        'tier': entry['tier'], 'publish': entry['wiki']['publish'],
        'artifact_sha256': entry.get('artifact_sha256'),
        'package_sha256': entry['package']['sha256'] if 'package' in entry else None,
    } for entry in selected]
    return files, summary


PLAY_PAGE = (
    '# Webエミュレータで動かす\n\n'
    '[Home](Home) › エミュレータで遊ぶ\n\n'
    'ROMとフォント、商用ソフトは同梱していません。利用権のあるファイルを手元で選択してください。\n\n'
    '1. 作品別のセット用リンクを先に開きます。公開CJRが検証後、通常カセットへ自動マウントされます。'
    f'セット用リンクがない版は[JR-200 Web Emulator]({EMULATOR_URL})を開き、'
    '「04 カセット」でCJRを選んで「マウント」を押します。\n'
    '2. 「02 起動データ」でROMとフォントを選び、「起動」を押します。'
    '事前保存したROM・フォントを復元する場合も、画面の状態を確認してください。\n'
    '3. マシン語CJRならJR BASICで `MLOAD` を入力します。'
    '読み込み後、作品ページに記載された実行コマンドを入力します。\n\n'
    'URLだけでROMやフォントを取得・配布せず、CJRを自動実行しません。'
    '「高速ロード」は通常のカセット信号経路を通らない別機能です。\n\n'
    '## うまく動かないとき\n\n'
    '- `MLOAD`の後に何も起きない: カセットがマウントされているか、ROMで起動しているかを確認します。\n'
    '- キーが効かない: 作品ごとの[操作](Controls)を確認します。\n'
    '- 音が出ない: ブラウザーの音声がページ操作の後に有効になるかを確認します。\n'
)


def generated_manifest(files: dict[str, bytes]) -> dict[str, Any]:
    return {'schema_version': 2, 'files': {
        name: hashlib.sha256(value).hexdigest()
        for name, value in sorted(files.items())}}


def previous_files(directory: Path) -> dict[str, str]:
    path = directory / MANIFEST
    if not path.exists():
        return {}
    if path.is_symlink():
        raise WikiError('Refusing generated manifest symlink')
    value = read_json(path, 'generated page manifest')
    if (isinstance(value, dict) and set(value) == {'schema_version', 'pages'}
            and value['schema_version'] == 1):
        records = value['pages']
    elif (isinstance(value, dict) and set(value) == {'schema_version', 'files'}
          and value['schema_version'] == 2):
        records = value['files']
    else:
        raise WikiError('Invalid generated file manifest')
    if (not isinstance(records, dict)
            or any(GENERATED_FILE.fullmatch(name) is None
                   or not isinstance(digest, str) or HEX64.fullmatch(digest) is None
                   for name, digest in records.items())):
        raise WikiError('Invalid generated file manifest')
    return dict(records)


def generated_path(directory: Path, name: str) -> Path:
    if GENERATED_FILE.fullmatch(name) is None:
        raise WikiError(f'Unsafe generated file name: {name}')
    path = directory.joinpath(*PurePosixPath(name).parts)
    parent = path.parent
    while parent != directory:
        if parent.exists() and parent.is_symlink():
            raise WikiError(f'Refusing generated path through symlink: {name}')
        parent = parent.parent
    return path


def sync_plan(directory: Path, files: dict[str, bytes]) -> dict[str, list[str]]:
    previous = previous_files(directory)
    added = []
    updated = []
    unchanged = []
    for name, content in sorted(files.items()):
        path = generated_path(directory, name)
        if path.is_symlink():
            raise WikiError(f'Refusing generated file symlink: {name}')
        if not path.exists():
            added.append(name)
        elif not path.is_file():
            raise WikiError(f'Refusing non-file generated path: {name}')
        else:
            current = path.read_bytes()
            if name not in previous:
                if name == 'Home.md' and not previous and current == content:
                    unchanged.append(name)
                    continue
                raise WikiError(f'Refusing to overwrite an unowned Wiki file: {name}')
            if hashlib.sha256(current).hexdigest() != previous[name]:
                raise WikiError(f'Refusing to overwrite a locally modified generated file: {name}')
            (unchanged if current == content else updated).append(name)
    deleted = sorted(set(previous) - set(files))
    for name in deleted:
        path = generated_path(directory, name)
        if (path.is_symlink() or not path.is_file()
                or hashlib.sha256(path.read_bytes()).hexdigest() != previous[name]):
            raise WikiError(f'Refusing to delete a modified generated file: {name}')
    return {'add': added, 'update': updated, 'delete': deleted,
            'unchanged': unchanged}


def atomic_write(path: Path, value: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
            mode='wb', dir=path.parent,
            prefix='.' + path.name + '.', delete=False) as output:
        temporary = Path(output.name)
        output.write(value)
    temporary.replace(path)


def apply_files(directory: Path, files: dict[str, bytes]) -> dict[str, list[str]]:
    if directory.is_symlink():
        raise WikiError('Refusing a symlink output directory')
    directory.mkdir(parents=True, exist_ok=True)
    plan = sync_plan(directory, files)
    for name in plan['delete']:
        path = generated_path(directory, name)
        if path.is_symlink() or not path.is_file():
            raise WikiError(f'Refusing unsafe stale generated file: {name}')
        path.unlink()
    for name, content in files.items():
        atomic_write(generated_path(directory, name), content)
    atomic_write(directory / MANIFEST, json.dumps(
        generated_manifest(files), indent=2, sort_keys=True).encode('utf-8') + b'\n')
    return plan


def require_git_worktree(path: Path, clean: bool) -> None:
    try:
        def git(*arguments: str) -> str:
            result = subprocess.run(
                ['git', *arguments], cwd=path, capture_output=True, text=True,
                check=False, timeout=10)
            if result.returncode != 0:
                raise WikiError('Wiki synchronization requires a Git worktree')
            return result.stdout.strip()

        top = Path(git('rev-parse', '--show-toplevel')).resolve()
        origin = git('remote', 'get-url', 'origin')
        status = git('status', '--porcelain=v1', '--untracked-files=all')
    except (OSError, subprocess.SubprocessError) as exc:
        raise WikiError(f'Cannot inspect Wiki worktree: {exc}') from exc
    allowed_origins = {
        'https://github.com/zabaglione/jr200-dev.wiki.git',
        'git@github.com:zabaglione/jr200-dev.wiki.git',
    }
    if top != path or origin not in allowed_origins:
        raise WikiError('Wiki worktree root or origin does not match the canonical Wiki')
    if clean and status:
        raise WikiError('Wiki worktree must be clean before applying generated files')


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument('--root', type=Path, default=ROOT)
    value.add_argument('--packages', type=Path)
    value.add_argument('--include-candidates', action='store_true')
    value.add_argument('--include-development', action='store_true',
                       help='local preview only: add draft games with verified galleries')
    value.add_argument('--expected-commit')
    commands = value.add_subparsers(dest='command', required=True)
    commands.add_parser('check')
    render = commands.add_parser('render')
    render.add_argument('--output', type=Path, required=True)
    sync = commands.add_parser('sync')
    sync.add_argument('--wiki', type=Path, required=True)
    sync.add_argument('--apply', action='store_true')
    return value


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        root = args.root.resolve()
        packages = args.packages.resolve() if args.packages else None
        if (args.expected_commit is not None
                and re.fullmatch(r'[0-9a-f]{40}', args.expected_commit) is None):
            raise WikiError('Expected commit must be a full lowercase SHA')
        if args.include_development and args.command == 'sync':
            raise WikiError('Development previews cannot be synchronized to the Wiki')
        files, games = render_pages(
            root, packages, args.include_candidates, args.expected_commit,
            args.include_development)
        if args.command == 'check':
            print(json.dumps({'status': 'passed', 'games': games,
                              'files': sorted(files)}, sort_keys=True))
        elif args.command == 'render':
            plan = apply_files(args.output.resolve(), files)
            print(json.dumps({'status': 'rendered', 'changes': plan,
                              'games': games}, sort_keys=True))
        else:
            wiki = args.wiki.resolve()
            require_git_worktree(wiki, clean=args.apply)
            plan = sync_plan(wiki, files)
            if args.apply:
                plan = apply_files(wiki, files)
            print(json.dumps({'status': 'applied' if args.apply else 'dry-run',
                              'changes': plan, 'games': games}, sort_keys=True))
    except (WikiError, OSError, subprocess.SubprocessError) as exc:
        print(f'Wiki generation failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
