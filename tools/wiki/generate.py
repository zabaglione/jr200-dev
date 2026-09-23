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
    r'(?:Home|Games|Play|Licenses|Game-[a-z][a-z0-9-]{0,31})\.md|'
    r'media/[a-z][a-z0-9-]{0,31}\.png')
EMULATOR_URL = 'https://zabaglione.github.io/jr200-web-emulator/'


class WikiError(ValueError):
    """Expected catalog, package, render, or local-sync failure."""


def read_json(path: Path, description: str) -> Any:
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
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
                         or wiki['play_url'] != f'{EMULATOR_URL}?game={identifier}'))
                or not isinstance(screenshot, dict)
                or set(screenshot) != {'file', 'sha256', 'framebuffer_sha256',
                                       'profile'}
                or screenshot['file'] != 'media/screenshot.png'
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
            or screenshot_report.get('mode') != 'synthetic-injection'
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


def readme_body(value: str) -> str:
    lines = value.strip().splitlines()
    if lines and lines[0].startswith('# '):
        lines = lines[1:]
    return '\n'.join(lines).strip() + '\n'


def render_game(entry: dict[str, Any], package: dict[str, Any]) -> str:
    metadata = entry['_metadata']
    release = package['release']
    candidate = not entry['wiki']['publish']
    lines = [f'# {metadata["title"]}', '']
    if candidate:
        lines.extend([
            '> This is a local, unpublished candidate preview. No public download is available.',
            '',
        ])
    lines.extend([
        '| Field | Value |', '| --- | --- |',
        f'| Version | `{entry["version"]}` |',
        f'| Genre | `{entry["genre"]}` |',
        f'| CJR SHA-256 | `{entry["artifact_sha256"]}` |',
        f'| Package SHA-256 | `{entry["package"]["sha256"]}` |',
        '| Emulator | ROM-less synthetic and local-ROM cassette profiles passed |',
        '| Hardware | Not run |',
        f'| License | `{metadata["license"]}` |',
        '', '## Play', '',
    ])
    if entry['package']['release_url'] is None:
        lines.append('The package is not published. Build the project locally and load the CJR manually.')
    else:
        lines.append(f'[Download the fixed package]({entry["package"]["release_url"]})')
    lines.extend(['', f'Load `{metadata["distribution"]["file"]}` with MLOAD, then run '
                      f'`{metadata["run"]["command"]}`.', '',
                  '## Screen', '',
                  f'<img src="media/{entry["wiki"]["slug"]}.png" '
                  f'alt="{html.escape(metadata["title"], quote=True)} emulator screen" '
                  'width="640">', '',
                  'Captured from the ROM-less synthetic emulator profile. '
                  'Physical display verification has not been run.', ''])
    if entry['wiki']['play_url'] is None:
        lines.extend([
            f'[Webエミュレータを開く]({EMULATOR_URL})（CJRは手動で選択）。',
            '[CJRのセットと実行手順](Play)。',
            '作品IDによるワンクリックのセットは、この版の公開CJRとURLの到達性が確認されるまで無効です。',
            '',
        ])
    else:
        lines.extend([f'[エミュレータにCJRをセット]({entry["wiki"]["play_url"]})',
                      'ROM・フォントは利用者が用意し、セット後にMLOADと作品の実行コマンドを入力してください。',
                      '[詳しい手順](Play)。', ''])
    lines.extend(['## Guide', '', readme_body(package['readme']).rstrip(), '',
                  '## Provenance', '',
                  f'- Source commit: `{release["source"]["commit"]}`',
                  f'- Source snapshot SHA-256: `{release["source"]["snapshot_sha256"]}`',
                  f'- Runner: `{release["compatibility"]["runner_version"]}`',
                  f'- Emulator source: `{release["compatibility"]["emulator_source_revision"]}`',
                  '- Physical JR-200 verification: not run', ''])
    return '\n'.join(lines)


def render_pages(root: Path, packages: Path | None,
                 include_candidates: bool,
                 expected_commit: str | None = None) -> tuple[dict[str, bytes], list[dict[str, Any]]]:
    selected = []
    for entry in catalog_entries(root):
        if entry['status'] == 'draft':
            raise WikiError(f'{entry["id"]}: draft games cannot be rendered')
        if entry['wiki']['publish']:
            selected.append(entry)
        elif include_candidates and entry['status'] == 'candidate':
            selected.append(entry)
    loaded = [(entry, load_package(
        root, entry, packages, require_release_ready=entry['wiki']['publish'],
        expected_commit=expected_commit))
              for entry in selected]
    availability = ('検証済みの公開ゲームはまだありません。' if not loaded
                    else '検証済みの公開ゲームを作品一覧から選べます。')
    if any(not entry['wiki']['publish'] for entry, _ in loaded):
        availability = 'この表示には未公開の候補版を含みます。配布リンクではありません。'
    files = {
        'Home.md': (
            '# JR-200ゲーム開発 Wiki\n\n'
            f'JR-200向けゲームとサンプルの開発情報です。{availability}\n\n'
            '- [ゲーム一覧](Games)\n'
            '- [Webエミュレータでの実行手順](Play)\n'
            '- [ライセンスと配布境界](Licenses)\n\n'
            f'[JR-200 Web Emulatorを開く]({EMULATOR_URL})\n'
        ).encode('utf-8'),
        'Play.md': (
            '# Webエミュレータで動かす\n\n'
            'ROMとフォント、商用ソフトは同梱していません。利用権のあるファイルを手元で選択してください。\n\n'
            '1. 作品別のセット用リンクを先に開きます。公開CJRが検証後、通常カセットへ自動マウントされます。'
            f'セット用リンクがない版は[JR-200 Web Emulator]({EMULATOR_URL})を開き、'
            '「04 カセット」でCJRを選んで「マウント」を押します。\n'
            '2. 「02 起動データ」でROMとフォントを選び、「起動」を押します。'
            '事前保存したROM・フォントを復元する場合も、画面の状態を確認してください。\n'
            '3. マシン語CJRならJR BASICで `MLOAD` を入力します。'
            '読み込み後、作品ページに記載された実行コマンドを入力します。\n\n'
            'URLだけでROMやフォントを取得・配布せず、CJRを自動実行しません。'
            '「高速ロード」は通常のカセット信号経路を通らない別機能です。\n'
        ).encode('utf-8'),
        'Licenses.md': (
            '# ライセンスと配布境界\n\n'
            '| 対象 | ライセンス・確認先 |\n| --- | --- |\n'
            '| jr200-devの共通コード・SDK、SIDE CATCH | '
            '[BSD-3-Clause](https://github.com/zabaglione/jr200-dev/blob/main/LICENSE) |\n'
            '| RELIC DIVE移植元（開発中、未配布） | '
            '[MIT原文](https://github.com/zabaglione/jr100dev/blob/9a3921c4371d84c55fc468879dbed2f00fe42960/games/relic_dive/LICENSE)。'
            '移植版に組み込むSDKはBSD-3-Clause |\n'
            '| Webエミュレータ | '
            f'[BSD-3-Clause]({EMULATOR_URL}LICENSE.txt)、'
            f'[第三者表記]({EMULATOR_URL}THIRD_PARTY_NOTICES.md) |\n'
            '| FIND VJR-200由来部分 | '
            f'[FINDの原文条件]({EMULATOR_URL}LICENSES/VJR200.txt) |\n'
            '| MAME MC6800由来部分 | '
            f'[BSD-3-Clause]({EMULATOR_URL}LICENSES/MAME_BSD-3-Clause.txt) |\n'
            '| Emscripten生成JavaScript | '
            f'[MIT・UIUC/NCSA]({EMULATOR_URL}LICENSES/Emscripten-6.0.9.txt) |\n'
            '| リンクされたlibc++abi | '
            f'[Apache-2.0 WITH LLVM-exception]({EMULATOR_URL}LICENSES/libcxxabi-6.0.9.txt) |\n'
            '| jrasm | 利用する外部ツール。ライセンス未確認のため再配布しません |\n\n'
            'メーカーROM・フォント、商用テープ、利用者録音は配布しません。'
            'ゲームのCJRを公開するときは、作品ごとの固定版と含まれるSDKのライセンス全文を確認します。\n'
        ).encode('utf-8'),
    }
    index = ['# JR-200ゲーム一覧', '']
    if any(not entry['wiki']['publish'] for entry, _ in loaded):
        index.extend(['> 開発中の候補版を含むローカルプレビューです。公開作品一覧ではありません。', ''])
    genres = sorted({entry['genre'] for entry, _ in loaded})
    for genre in genres:
        index.extend([f'## {genre}', ''])
        for entry, _ in loaded:
            if entry['genre'] == genre:
                title = entry['_metadata']['title']
                summary = entry['_metadata']['summary']
                index.append(f'- [{title}](Game-{entry["wiki"]["slug"]}) — {summary}')
        index.append('')
    if not loaded:
        index.extend(['検証済みの公開ゲームはまだありません。', ''])
    files['Games.md'] = '\n'.join(index).encode('utf-8')
    for entry, package in loaded:
        slug = entry['wiki']['slug']
        files[f'Game-{slug}.md'] = render_game(entry, package).encode('utf-8')
        files[f'media/{slug}.png'] = entry['_screenshot']
    summary = [{
        'id': entry['id'], 'version': entry['version'], 'status': entry['status'],
        'publish': entry['wiki']['publish'], 'artifact_sha256': entry['artifact_sha256'],
        'package_sha256': entry['package']['sha256'],
    } for entry, _ in loaded]
    return files, summary


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
        files, games = render_pages(
            root, packages, args.include_candidates, args.expected_commit)
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
