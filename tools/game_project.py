# SPDX-License-Identifier: BSD-3-Clause
"""Validate, build, package, create, or clean one JR-200 project."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any
import zipfile

from jrasm_tool import (DEFAULT_LOCK, ToolError, inspect, load_lock,
                         resolve_executable, sha256_file)


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RULES = ROOT / 'rules/jr200.json'
DEFAULT_TEMPLATE = ROOT / 'templates/minimal'
PROJECT_ID = re.compile(r'[a-z][a-z0-9-]{0,31}')
REGION_ID = re.compile(r'[a-z][a-z0-9_-]{0,31}')
PATH_TEXT = re.compile(r'[A-Za-z0-9][A-Za-z0-9._/-]*')
VERSION_TEXT = re.compile(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?')
SUPPORTED_GAME_LICENSES = {'BSD-3-Clause', 'MIT'}
INCLUDE_LINE = re.compile(r'^\s*\.include\s+(["\'])([^"\']+)\1', re.IGNORECASE)
SYMBOL_LINE = re.compile(r'^([0-9a-fA-F]{4})\s+(\S+)\s*$')


class ProjectError(ValueError):
    """Expected project configuration, dependency, or artifact failure."""


@dataclass(frozen=True)
class Region:
    name: str
    kind: str
    start: int
    end: int


@dataclass(frozen=True)
class CjrBlock:
    number: int
    start: int
    data: bytes

    @property
    def end(self) -> int:
        return self.start + len(self.data) - 1


@dataclass(frozen=True)
class ProjectSpec:
    project: Path
    repository_root: Path
    config: dict[str, Any]
    metadata: dict[str, Any]
    rules: dict[str, Any]
    regions: tuple[Region, ...]
    assembly_inputs: tuple[str, ...]
    sdk_inputs: tuple[str, ...]
    asset_inputs: tuple[str, ...]

    @property
    def source(self) -> Path:
        return self.project / self.config['source']

    @property
    def output(self) -> Path:
        return self.project / 'build' / self.config['output']


def read_json(path: Path, description: str) -> Any:
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
        raise ProjectError(f'Cannot read {description}: {path}: {exc}') from exc


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n'
    with tempfile.NamedTemporaryFile(
            mode='w', encoding='utf-8', dir=path.parent,
            prefix='.' + path.name + '.', delete=False) as output:
        temporary = Path(output.name)
        output.write(payload)
    temporary.replace(path)


def address(value: Any, label: str) -> int:
    if not isinstance(value, str) or not re.fullmatch(r'0x[0-9a-fA-F]{1,4}', value):
        raise ProjectError(f'{label} must be a 16-bit hexadecimal string')
    parsed = int(value, 16)
    if not 0 <= parsed <= 0xffff:
        raise ProjectError(f'{label} is outside the 16-bit address space')
    return parsed


def project_path(project: Path, value: Any, label: str) -> Path:
    if (not isinstance(value, str) or not PATH_TEXT.fullmatch(value)
            or value.startswith('/') or '\\' in value
            or any(part in ('', '.', '..') for part in PurePosixPath(value).parts)):
        raise ProjectError(f'Unsafe {label}: {value!r}')
    target = (project / value).resolve()
    try:
        target.relative_to(project)
    except ValueError as exc:
        raise ProjectError(f'{label} leaves the project: {value}') from exc
    return target


def validate_region_list(items: Any, label: str, with_kind: bool) -> tuple[Region, ...]:
    if not isinstance(items, list) or not items:
        raise ProjectError(f'{label} must be a non-empty array')
    regions: list[Region] = []
    names: set[str] = set()
    expected = {'name', 'start', 'end', 'kind'} if with_kind else {'name', 'start', 'end'}
    for item in items:
        if not isinstance(item, dict) or set(item) != expected:
            raise ProjectError(f'Invalid {label} fields')
        name = item['name']
        if (not isinstance(name, str) or not REGION_ID.fullmatch(name)
                or name in names):
            raise ProjectError(f'Invalid or duplicate {label} name: {name!r}')
        kind = item.get('kind', 'reserved')
        if with_kind and kind not in ('code', 'data'):
            raise ProjectError(f'Invalid region kind: {kind!r}')
        start = address(item['start'], f'{label} {name} start')
        end = address(item['end'], f'{label} {name} end')
        if start > end:
            raise ProjectError(f'Reversed {label}: {name}')
        names.add(name)
        regions.append(Region(name, kind, start, end))
    ordered = sorted(regions, key=lambda item: (item.start, item.end))
    for left, right in zip(ordered, ordered[1:]):
        if right.start <= left.end:
            raise ProjectError(
                f'Overlapping {label}: {left.name} and {right.name}')
    return tuple(regions)


def validate_machine_rules(value: Any) -> dict[str, Any]:
    expected = {'schema_version', 'machine', 'cpu', 'loadable_regions',
                'reserved_regions', 'vectors'}
    if not isinstance(value, dict) or set(value) != expected:
        raise ProjectError('Invalid JR-200 rules fields')
    if type(value['schema_version']) is not int or value['schema_version'] != 1:
        raise ProjectError('Unsupported JR-200 rules schema')
    if not isinstance(value['machine'], str) or not value['machine']:
        raise ProjectError('JR-200 rules require a machine name')
    cpu = value['cpu']
    if (not isinstance(cpu, dict)
            or set(cpu) != {'processor', 'documented_instruction_set',
                            'documented_machine_codes', 'unassigned_machine_codes',
                            'forbidden_mnemonics'}
            or cpu['processor'] != 'MN1800A'
            or cpu['documented_instruction_set'] != 'M6800'
            or type(cpu['documented_machine_codes']) is not int
            or type(cpu['unassigned_machine_codes']) is not int
            or not isinstance(cpu['forbidden_mnemonics'], list)
            or not cpu['forbidden_mnemonics']
            or not all(isinstance(item, str) and re.fullmatch(r'[a-z]+', item)
                       for item in cpu['forbidden_mnemonics'])
            or len(cpu['forbidden_mnemonics']) != len(set(cpu['forbidden_mnemonics']))):
        raise ProjectError('Invalid JR-200 CPU rules')
    loadable = validate_region_list(value['loadable_regions'], 'loadable region', False)
    reserved = validate_region_list(value['reserved_regions'], 'reserved region', False)
    all_regions = sorted((*loadable, *reserved), key=lambda item: item.start)
    if all_regions[0].start != 0 or all_regions[-1].end != 0xffff:
        raise ProjectError('JR-200 memory rules must cover the 16-bit address space')
    for left, right in zip(all_regions, all_regions[1:]):
        if right.start != left.end + 1:
            raise ProjectError('JR-200 memory rules overlap or leave a gap')
    vectors = value['vectors']
    if not isinstance(vectors, dict) or set(vectors) != {'irq', 'swi', 'nmi', 'reset'}:
        raise ProjectError('Invalid JR-200 vector rules')
    expected_vectors = {'irq': 0xfff8, 'swi': 0xfffa, 'nmi': 0xfffc, 'reset': 0xfffe}
    for name, expected_address in expected_vectors.items():
        if address(vectors[name], f'{name} vector') != expected_address:
            raise ProjectError(f'Unexpected {name} vector')
    return value


def load_rules(path: Path = DEFAULT_RULES) -> dict[str, Any]:
    return validate_machine_rules(read_json(path, 'JR-200 rules'))


def strip_assembly_comment(line: str) -> str:
    quote = ''
    escaped = False
    for index, character in enumerate(line):
        if escaped:
            escaped = False
        elif character == '\\' and quote:
            escaped = True
        elif character in ('"', "'"):
            quote = '' if quote == character else (character if not quote else quote)
        elif character == ';' and not quote:
            return line[:index]
    return line


def operation(line: str) -> str | None:
    code = strip_assembly_comment(line).strip()
    if not code:
        return None
    if ':' in code:
        possible_label, remainder = code.split(':', 1)
        if re.fullmatch(r'[A-Za-z_@.][A-Za-z0-9_@.]*', possible_label.strip()):
            code = remainder.strip()
    match = re.match(r'([A-Za-z_.][A-Za-z0-9_.]*)', code)
    return match.group(1).lower() if match else None


def discover_assembly_inputs(project: Path, repository_root: Path, source: str,
                             forbidden: set[str]) -> tuple[tuple[str, ...], tuple[str, ...]]:
    pending = [project_path(project, source, 'assembly input')]
    discovered: set[Path] = set()
    project_inputs: set[str] = set()
    sdk_inputs: set[str] = set()
    while pending:
        path = pending.pop()
        if path in discovered:
            continue
        try:
            relative = path.relative_to(project).as_posix()
            project_inputs.add(relative)
            shown = relative
        except ValueError:
            try:
                repository_relative = path.relative_to(repository_root).as_posix()
            except ValueError as exc:
                raise ProjectError(f'Assembly dependency leaves the repository: {path}') from exc
            if not repository_relative.startswith('sdk/'):
                raise ProjectError(
                    f'External assembly dependency is outside sdk/: {repository_relative}')
            sdk_inputs.add(repository_relative)
            shown = '@repo/' + repository_relative
        if not path.is_file():
            raise ProjectError(f'Missing assembly dependency: {shown}')
        try:
            lines = path.read_text(encoding='utf-8').splitlines()
        except (OSError, UnicodeDecodeError) as exc:
            raise ProjectError(f'Cannot read assembly input: {shown}: {exc}') from exc
        discovered.add(path)
        for line_number, line in enumerate(lines, 1):
            mnemonic = operation(line)
            if mnemonic in forbidden:
                raise ProjectError(
                    f'Forbidden instruction {mnemonic.upper()}: {shown}:{line_number}')
            include = INCLUDE_LINE.match(strip_assembly_comment(line))
            if include is None:
                continue
            included = include.group(2)
            if Path(included).is_absolute() or '\\' in included:
                raise ProjectError(f'Unsafe assembly include: {shown}: {included}')
            resolved = (path.parent / included).resolve()
            try:
                resolved.relative_to(project)
            except ValueError:
                try:
                    repository_relative = resolved.relative_to(repository_root).as_posix()
                except ValueError as exc:
                    raise ProjectError(
                        f'Assembly include leaves the repository: {shown}: {included}') from exc
                if not repository_relative.startswith('sdk/'):
                    raise ProjectError(
                        f'Assembly include outside sdk/: {shown}: {included}')
            pending.append(resolved)
    return tuple(sorted(project_inputs)), tuple(sorted(sdk_inputs))


def validate_assets(project: Path, declared: tuple[str, ...]) -> None:
    manifest_path = project / 'assets/manifest.json'
    manifest = read_json(manifest_path, 'asset manifest')
    if (not isinstance(manifest, dict)
            or set(manifest) != {'schema_version', 'assets'}
            or type(manifest['schema_version']) is not int
            or manifest['schema_version'] != 1
            or not isinstance(manifest['assets'], list)):
        raise ProjectError('Invalid asset manifest')
    expected_fields = {'path', 'kind', 'source', 'author', 'license', 'redistributable'}
    listed: list[str] = []
    forbidden_kinds = {'rom', 'firmware', 'manufacturer_font'}
    for item in manifest['assets']:
        if not isinstance(item, dict) or set(item) != expected_fields:
            raise ProjectError('Invalid asset entry fields')
        relative = item['path']
        asset = project_path(project, 'assets/' + str(relative), 'asset path')
        if (not isinstance(relative, str) or relative == 'manifest.json'
                or not isinstance(item['kind'], str) or not item['kind']
                or item['kind'] in forbidden_kinds
                or not all(isinstance(item[field], str) and item[field]
                           for field in ('source', 'author', 'license'))
                or item['redistributable'] is not True):
            raise ProjectError(f'Invalid or non-redistributable asset: {relative!r}')
        if not asset.is_file():
            raise ProjectError(f'Missing declared asset: assets/{relative}')
        listed.append('assets/' + relative)
    if len(listed) != len(set(listed)):
        raise ProjectError('Duplicate asset manifest path')
    actual = sorted(path.relative_to(project).as_posix()
                    for path in (project / 'assets').rglob('*')
                    if path.is_file() and path != manifest_path)
    if actual != sorted(listed):
        raise ProjectError(
            f'Asset manifest mismatch: listed={sorted(listed)!r}, actual={actual!r}')
    if tuple(sorted(listed)) != declared:
        raise ProjectError(
            f'Asset dependency mismatch: declared={list(declared)!r}, actual={sorted(listed)!r}')


def validate_metadata(value: Any, config: dict[str, Any]) -> dict[str, Any]:
    base_fields = {'schema_version', 'id', 'title', 'version', 'summary', 'license',
                   'distribution', 'load', 'run', 'verification'}
    if not isinstance(value, dict) or type(value.get('schema_version')) is not int:
        raise ProjectError('Invalid game metadata fields')
    version = value['schema_version']
    expected = base_fields if version == 1 else base_fields | {'genre', 'release'}
    if version not in (1, 2) or set(value) != expected:
        raise ProjectError('Unsupported game metadata schema')
    limits = {'title': 80, 'summary': 240, 'license': 64}
    for field, limit in limits.items():
        if (not isinstance(value[field], str) or not value[field].strip()
                or len(value[field]) > limit
                or any(ord(character) < 32 or ord(character) == 127
                       for character in value[field])):
            raise ProjectError(f'Invalid game metadata {field}')
    if value['license'] not in SUPPORTED_GAME_LICENSES:
        raise ProjectError('Unsupported game metadata license')
    if value['id'] != config['id']:
        raise ProjectError('game.json ID does not match build.json')
    if not isinstance(value['version'], str) or not VERSION_TEXT.fullmatch(value['version']):
        raise ProjectError('Invalid game version')
    distribution = value['distribution']
    if (not isinstance(distribution, dict)
            or distribution != {'format': 'cjr', 'file': config['output']}):
        raise ProjectError('Distribution metadata does not match build output')
    load = value['load']
    if (not isinstance(load, dict)
            or load != {'method': 'cjr_loader', 'address': config['load_address']}):
        raise ProjectError('Load metadata does not match build configuration')
    run = value['run']
    expected_run = {'method': 'basic_usr', 'command': config['execution']['command'],
                    'entry_address': config['entry_address'], 'return': 'RTS'}
    if not isinstance(run, dict) or run != expected_run:
        raise ProjectError('Run metadata does not match build configuration')
    verification = value['verification']
    if (not isinstance(verification, dict)
            or set(verification) != {'emulator', 'hardware'}
            or not all(status in ('not_run', 'passed', 'failed')
                       for status in verification.values())):
        raise ProjectError('Invalid verification metadata')
    if version == 2:
        if (not isinstance(value['genre'], str)
                or re.fullmatch(r'[a-z][a-z0-9-]{0,31}', value['genre']) is None):
            raise ProjectError('Invalid game genre')
        release = value['release']
        if (not isinstance(release, dict)
                or set(release) != {'status', 'sdk_contract', 'runner_contract',
                                    'minimum_runner_version', 'wav', 'publication'}
                or release['status'] not in ('draft', 'candidate', 'verified')
                or type(release['sdk_contract']) is not int
                or release['sdk_contract'] != 1
                or type(release['runner_contract']) is not int
                or release['runner_contract'] != 1
                or not isinstance(release['minimum_runner_version'], str)
                or VERSION_TEXT.fullmatch(release['minimum_runner_version']) is None
                or release['wav'] not in ('not-required', 'required')
                or release['publication'] not in ('not-published', 'published')):
            raise ProjectError('Invalid game release metadata')
    return value


def validate_project(project: Path, rules_path: Path = DEFAULT_RULES,
                     repository_root: Path = ROOT) -> ProjectSpec:
    project = project.resolve()
    repository_root = repository_root.resolve()
    if not project.is_dir():
        raise ProjectError(f'Project directory was not found: {project}')
    for relative in ('src', 'assets', 'tests', 'media'):
        if not (project / relative).is_dir():
            raise ProjectError(f'Missing project directory: {relative}')
    for relative in ('Makefile', 'README.md', 'build.json', 'game.json',
                     'assets/manifest.json', 'tests/expectations.json',
                     'media/README.md'):
        path = project / relative
        if not path.is_file() or not path.read_bytes():
            raise ProjectError(f'Missing or empty project file: {relative}')
    config = read_json(project / 'build.json', 'build configuration')
    expected = {'schema_version', 'id', 'source', 'output', 'load_address',
                'entry_address', 'entry_symbol', 'regions', 'inputs', 'execution'}
    if not isinstance(config, dict) or set(config) != expected:
        raise ProjectError('Invalid build configuration fields')
    if type(config['schema_version']) is not int or config['schema_version'] != 1:
        raise ProjectError('Unsupported build configuration schema')
    if not isinstance(config['id'], str) or not PROJECT_ID.fullmatch(config['id']):
        raise ProjectError('Invalid project ID')
    source = project_path(project, config['source'], 'source path')
    if source.suffix.lower() != '.asm':
        raise ProjectError('Project source must be an .asm file')
    output_name = config['output']
    if (not isinstance(output_name, str) or not re.fullmatch(r'[a-z][a-z0-9-]*\.cjr', output_name)
            or '/' in output_name):
        raise ProjectError('Build output must be a safe CJR filename')
    if not isinstance(config['entry_symbol'], str) or not re.fullmatch(
            r'[A-Za-z_][A-Za-z0-9_]*', config['entry_symbol']):
        raise ProjectError('Invalid entry symbol')
    load_address = address(config['load_address'], 'load address')
    entry_address = address(config['entry_address'], 'entry address')
    regions = validate_region_list(config['regions'], 'project region', True)
    rules = load_rules(rules_path)
    loadable = validate_region_list(rules['loadable_regions'], 'loadable region', False)
    for region in regions:
        if not any(region.start >= allowed.start and region.end <= allowed.end
                   for allowed in loadable):
            raise ProjectError(f'Project region is not loadable user RAM: {region.name}')
    if load_address != min(region.start for region in regions):
        raise ProjectError('Load address must equal the first declared region start')
    if not any(region.kind == 'code' and region.start <= entry_address <= region.end
               for region in regions):
        raise ProjectError('Entry address is outside a declared code region')
    inputs = config['inputs']
    if not isinstance(inputs, dict) or set(inputs) != {'assembly', 'sdk', 'assets'}:
        raise ProjectError('Build inputs require assembly, sdk, and assets arrays')
    declared_inputs: dict[str, tuple[str, ...]] = {}
    for kind in ('assembly', 'sdk', 'assets'):
        values = inputs[kind]
        if (not isinstance(values, list) or not all(isinstance(item, str) for item in values)
                or values != sorted(values) or len(values) != len(set(values))):
            raise ProjectError(f'{kind} inputs must be a sorted unique string array')
        for value in values:
            if kind == 'sdk':
                if not value.startswith('sdk/'):
                    raise ProjectError(f'SDK input must be under sdk/: {value!r}')
                sdk_path = (repository_root / value).resolve()
                try:
                    sdk_path.relative_to(repository_root / 'sdk')
                except ValueError as exc:
                    raise ProjectError(f'Unsafe sdk input: {value!r}') from exc
            else:
                project_path(project, value, f'{kind} input')
        declared_inputs[kind] = tuple(values)
    if config['source'] not in declared_inputs['assembly']:
        raise ProjectError('Assembly inputs do not contain the source')
    execution = config['execution']
    expected_execution = {'loader': 'cjr', 'launch': 'basic_usr',
                          'command': f'A=USR(${entry_address:04X})',
                          'return': 'rts', 'stack': 'caller'}
    if not isinstance(execution, dict) or execution != expected_execution:
        raise ProjectError('Invalid or inconsistent execution contract')
    actual_assembly, actual_sdk = discover_assembly_inputs(
        project, repository_root, config['source'],
        set(rules['cpu']['forbidden_mnemonics']))
    if actual_assembly != declared_inputs['assembly']:
        raise ProjectError(
            f'Assembly dependency mismatch: declared={list(declared_inputs["assembly"])!r}, '
            f'actual={list(actual_assembly)!r}')
    if actual_sdk != declared_inputs['sdk']:
        raise ProjectError(
            f'SDK dependency mismatch: declared={list(declared_inputs["sdk"])!r}, '
            f'actual={list(actual_sdk)!r}')
    validate_assets(project, declared_inputs['assets'])
    metadata = validate_metadata(read_json(project / 'game.json', 'game metadata'), config)
    if metadata['license'] != 'BSD-3-Clause':
        project_license = project / 'LICENSE'
        if not project_license.is_file() or not project_license.read_bytes():
            raise ProjectError(
                f'{metadata["license"]} game requires a project LICENSE file')
        if declared_inputs['sdk']:
            notice_path = project / 'THIRD_PARTY_NOTICES.md'
            if not notice_path.is_file():
                raise ProjectError(
                    'Non-BSD game with SDK inputs requires THIRD_PARTY_NOTICES.md')
            try:
                notice = notice_path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError) as exc:
                raise ProjectError('Cannot read project third-party notices') from exc
            if ('BSD-3-Clause' not in notice
                    or any(item not in notice for item in declared_inputs['sdk'])):
                raise ProjectError(
                    'Project third-party notices must name every BSD SDK input')
    return ProjectSpec(project, repository_root, config, metadata, rules, regions,
                       declared_inputs['assembly'], declared_inputs['sdk'],
                       declared_inputs['assets'])


def parse_cjr(data: bytes) -> dict[str, Any]:
    if len(data) < 39:
        raise ProjectError('CJR is too short')
    if data[0:2] != b'\x02\x2a' or data[2] != 0 or data[3] != 0x1a:
        raise ProjectError('Invalid CJR header')
    if sum(data[:32]) & 0xff != data[32]:
        raise ProjectError('Invalid CJR header checksum')
    if data[22] != 1:
        raise ProjectError('CJR is not a machine-code file')
    pointer = 33
    blocks: list[CjrBlock] = []
    expected_number = 1
    footer_address = -1
    while True:
        if pointer + 6 > len(data) or data[pointer:pointer + 2] != b'\x02\x2a':
            raise ProjectError('Invalid CJR block marker')
        number = data[pointer + 2]
        size_field = data[pointer + 3]
        if number == 0xff:
            if size_field != 0xff or pointer + 6 != len(data):
                raise ProjectError('Invalid CJR footer')
            footer_address = (data[pointer + 4] << 8) | data[pointer + 5]
            break
        if number != expected_number:
            raise ProjectError('CJR data blocks are not sequential')
        size = 256 if size_field == 0 else size_field
        block_end = pointer + 7 + size
        if block_end > len(data):
            raise ProjectError('Truncated CJR data block')
        checksum_index = pointer + 6 + size
        if sum(data[pointer:checksum_index]) & 0xff != data[checksum_index]:
            raise ProjectError(f'Invalid CJR checksum in block {number}')
        start = (data[pointer + 4] << 8) | data[pointer + 5]
        if start + size > 0x10000:
            raise ProjectError('CJR data block wraps the address space')
        blocks.append(CjrBlock(number, start, data[pointer + 6:checksum_index]))
        pointer = block_end
        expected_number += 1
        if expected_number == 0xff:
            raise ProjectError('Too many CJR data blocks')
    if not blocks:
        raise ProjectError('CJR has no data block')
    filename = data[6:22].split(b'\0', 1)[0]
    try:
        decoded_filename = filename.decode('ascii')
    except UnicodeDecodeError as exc:
        raise ProjectError('CJR filename is not ASCII') from exc
    ordered = sorted(blocks, key=lambda item: item.start)
    for left, right in zip(ordered, ordered[1:]):
        if right.start <= left.end:
            raise ProjectError('CJR data blocks overlap')
    return {'filename': decoded_filename, 'blocks': blocks,
            'footer_address': footer_address}


def parse_symbols(output: str) -> dict[str, int]:
    symbols: dict[str, int] = {}
    for line in output.splitlines():
        match = SYMBOL_LINE.fullmatch(line.strip())
        if match is None:
            continue
        name = match.group(2).lower()
        value = int(match.group(1), 16)
        if name in symbols and symbols[name] != value:
            raise ProjectError(f'Duplicate assembler symbol: {name}')
        symbols[name] = value
    return symbols


def check_cjr_layout(spec: ProjectSpec, parsed: dict[str, Any],
                     symbols: dict[str, int]) -> None:
    blocks: list[CjrBlock] = parsed['blocks']
    if blocks[0].start != address(spec.config['load_address'], 'load address'):
        raise ProjectError('CJR first block does not match load address')
    entry = address(spec.config['entry_address'], 'entry address')
    if not any(block.start <= entry <= block.end for block in blocks):
        raise ProjectError('CJR does not contain the entry address')
    symbol = spec.config['entry_symbol'].lower()
    if symbols.get(symbol) != entry:
        actual = symbols.get(symbol)
        shown = '<missing>' if actual is None else f'0x{actual:04x}'
        raise ProjectError(
            f'Entry symbol mismatch: expected 0x{entry:04x}, got {shown}')
    for block in blocks:
        for location in range(block.start, block.end + 1):
            if not any(region.start <= location <= region.end for region in spec.regions):
                raise ProjectError(
                    f'CJR byte 0x{location:04x} is outside declared regions')


def build_project(project: Path, jrasm: str | None = None,
                  lock_path: Path = DEFAULT_LOCK,
                  rules_path: Path = DEFAULT_RULES,
                  repository_root: Path = ROOT) -> tuple[ProjectSpec, dict[str, Any]]:
    spec = validate_project(project, rules_path, repository_root)
    try:
        lock = load_lock(lock_path, lock_path.resolve().parent)
        executable = resolve_executable(jrasm)
        tool_report = inspect(executable, lock)
    except ToolError as exc:
        raise ProjectError(str(exc)) from exc
    build_dir = spec.project / 'build'
    build_dir.mkdir(parents=True, exist_ok=True)
    temporary = build_dir / ('.' + spec.config['output'] + '.tmp')
    if temporary.exists():
        temporary.unlink()
    try:
        result = subprocess.run(
            [str(executable), '-l', '-o', str(temporary), str(spec.source)],
            cwd=spec.project, capture_output=True, text=True, check=False,
            timeout=lock['fixture']['timeout_seconds'],
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ProjectError(f'Cannot run jrasm: {exc}') from exc
    if result.returncode != 0:
        if temporary.exists():
            temporary.unlink()
        detail = (result.stderr or result.stdout).strip()
        raise ProjectError(f'jrasm failed with exit {result.returncode}: {detail}')
    if not temporary.is_file():
        raise ProjectError('jrasm did not create the requested CJR')
    try:
        payload = temporary.read_bytes()
        parsed = parse_cjr(payload)
        symbols = parse_symbols(result.stdout + result.stderr)
        check_cjr_layout(spec, parsed, symbols)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    temporary.replace(spec.output)
    dependencies = {
        'schema_version': 1,
        'project': spec.config['id'],
        'assembly': list(spec.assembly_inputs),
        'sdk': list(spec.sdk_inputs),
        'assets': list(spec.asset_inputs),
    }
    write_json(build_dir / 'dependencies.json', dependencies)
    inputs = []
    for relative in (*spec.assembly_inputs, *spec.asset_inputs):
        path = spec.project / relative
        inputs.append({'path': relative, 'sha256': sha256_file(path)})
    for relative in spec.sdk_inputs:
        path = spec.repository_root / relative
        inputs.append({'path': '@repo/' + relative, 'sha256': sha256_file(path)})
    report = {
        'schema_version': 1,
        'project': spec.config['id'],
        'artifact': {
            'path': 'build/' + spec.config['output'],
            'size': len(payload),
            'sha256': hashlib.sha256(payload).hexdigest(),
            'cjr_filename': parsed['filename'],
            'footer_address': f'0x{parsed["footer_address"]:04x}',
            'blocks': [
                {'number': block.number, 'start': f'0x{block.start:04x}',
                 'end': f'0x{block.end:04x}', 'size': len(block.data)}
                for block in parsed['blocks']
            ],
        },
        'inputs': inputs,
        'configuration': {
            'build.json': sha256_file(spec.project / 'build.json'),
            'game.json': sha256_file(spec.project / 'game.json'),
        },
        'toolchain': {
            'name': 'jrasm',
            'version': lock['version'],
            'revision': lock['revision'],
            'banner': tool_report['banner'],
            'executable_sha256': tool_report['sha256'],
        },
        'verification': {
            'structure': 'passed',
            'assembler': 'passed',
            'cjr_layout': 'passed',
            'emulator': 'not_run',
            'hardware': 'not_run',
        },
    }
    write_json(build_dir / 'build-report.json', report)
    return spec, report


def zip_entry(archive: zipfile.ZipFile, name: str, data: bytes) -> None:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def release_runtime_reports(spec: ProjectSpec, artifact_sha256: str) -> list[tuple[str, bytes, dict[str, Any]]]:
    directory = spec.project / 'build/runtime-reports'
    if not directory.is_dir():
        raise ProjectError('Release candidate requires profile-specific runtime reports')
    expectations = read_json(spec.project / 'tests/expectations.json', 'runtime expectations')
    runtime = expectations.get('runtime', {}) if isinstance(expectations, dict) else {}
    declared_profiles = {
        item.get('profile'): item.get('mode') for item in runtime.get('profiles', [])
        if isinstance(item, dict)
    } if isinstance(runtime.get('profiles'), list) else {}
    if (not declared_profiles or None in declared_profiles
            or any(mode not in ('synthetic-injection', 'rom-cassette')
                   for mode in declared_profiles.values())):
        raise ProjectError('Release candidate has invalid runtime profile declarations')
    reports = []
    profiles = set()
    evidence = set()
    for path in sorted(directory.glob('*.json')):
        value = read_json(path, 'runtime report')
        profile = path.stem
        result = value.get('result', {}) if isinstance(value, dict) else {}
        if (not PROJECT_ID.fullmatch(profile)
                or value.get('schema_version') != 1
                or value.get('project') != spec.config['id']
                or value.get('profile') != profile
                or value.get('mode') != declared_profiles.get(profile)
                or value.get('artifact_sha256') != artifact_sha256
                or value.get('expectations_sha256')
                != sha256_file(spec.project / 'tests/expectations.json')
                or value.get('verification', {}).get('emulator') != 'passed'
                or value.get('verification', {}).get('hardware') != 'not_run'
                or result.get('status') != 'passed'
                or result.get('profile') != profile
                or result.get('mode') != value.get('mode')
                or result.get('artifact_sha256') != artifact_sha256
                or result.get('hardware') != 'not_run'
                or result.get('evidence') not in ('emulator', 'emulator_with_local_rom')):
            raise ProjectError(f'Runtime report is stale or invalid: {path.name}')
        if profile in profiles:
            raise ProjectError(f'Duplicate runtime profile report: {profile}')
        payload = path.read_bytes()
        reports.append((profile, payload, value))
        profiles.add(profile)
        evidence.add(result['evidence'])
    if profiles != set(declared_profiles):
        raise ProjectError('Release candidate requires a report for every runtime profile')
    if evidence != {'emulator', 'emulator_with_local_rom'}:
        raise ProjectError(
            'Release candidate requires synthetic and local-ROM emulator evidence')
    return reports


def git_source_state(root: Path) -> tuple[str, str]:
    try:
        commit = subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=root, stderr=subprocess.PIPE,
            text=True).strip()
        status = subprocess.check_output(
            ['git', 'status', '--porcelain=v1', '--untracked-files=all'],
            cwd=root, stderr=subprocess.PIPE, text=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ProjectError('Cannot determine source revision for release candidate') from exc
    if re.fullmatch(r'[0-9a-f]{40}', commit) is None:
        raise ProjectError('Source revision is not a full Git commit')
    return commit, ('dirty' if status else 'clean')


def snapshot_presentation_paths(spec: ProjectSpec) -> set[str]:
    """Include tracked or visible new files, never ignored local byproducts."""
    prefix = spec.project.relative_to(spec.repository_root).as_posix()
    try:
        output = subprocess.check_output(
            ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z',
             '--', f'{prefix}/tests', f'{prefix}/media'],
            cwd=spec.repository_root, stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ProjectError('Cannot list release snapshot source files') from exc
    paths = set()
    for entry in output.split(b'\0'):
        if not entry:
            continue
        relative = Path(entry.decode('utf-8')).relative_to(prefix)
        path = spec.project / relative
        if path.is_symlink() or not path.is_file():
            raise ProjectError(f'Release source is missing or symlinked: {path}')
        paths.add(relative.as_posix())
    return paths


def source_snapshot_digest(spec: ProjectSpec, report: dict[str, Any]) -> str:
    snapshot_paths = {
        'Makefile', 'README.md', 'build.json', 'game.json',
        'assets/manifest.json',
    }
    snapshot_paths.update(snapshot_presentation_paths(spec))
    snapshot = []
    for relative in sorted(snapshot_paths):
        snapshot.append((relative, sha256_file(spec.project / relative)))
    for item in report['inputs']:
        snapshot.append((item['path'], item['sha256']))
    return hashlib.sha256(json.dumps(
        sorted(set(snapshot)), ensure_ascii=True,
        separators=(',', ':')).encode('ascii')).hexdigest()


def release_manifest(spec: ProjectSpec, report: dict[str, Any],
                     runtime_reports: list[tuple[str, bytes, dict[str, Any]]]) -> dict[str, Any]:
    commit, tree_state = git_source_state(spec.repository_root)
    snapshot_digest = source_snapshot_digest(spec, report)
    runtime_entries = []
    runner_versions = set()
    emulator_revisions = set()
    for profile, payload, runtime in runtime_reports:
        runner_versions.add(runtime['runner']['version'])
        emulator_revisions.add(runtime['runner']['source_revision'])
        runtime_entries.append({
            'profile': profile,
            'mode': runtime['mode'],
            'evidence': runtime['result']['evidence'],
            'report': f'VERIFICATION/{profile}.json',
            'report_sha256': hashlib.sha256(payload).hexdigest(),
        })
    if len(runner_versions) != 1 or len(emulator_revisions) != 1:
        raise ProjectError('Runtime reports do not use one fixed runner and emulator revision')
    runner_version = next(iter(runner_versions))
    if tuple(int(part) for part in runner_version.split('.')) < tuple(
            int(part) for part in spec.metadata['release']['minimum_runner_version'].split('.')):
        raise ProjectError('Runtime report uses an older runner than game metadata allows')
    return {
        'schema_version': 1,
        'project': spec.config['id'],
        'version': spec.metadata['version'],
        'status': spec.metadata['release']['status'],
        'artifact': {
            **{key: value for key, value in report['artifact'].items() if key != 'path'},
            'file': spec.config['output'],
        },
        'source': {
            'repository': 'https://github.com/zabaglione/jr200-dev',
            'commit': commit,
            'tree_state': tree_state,
            'snapshot_sha256': snapshot_digest,
            'expectations_sha256': sha256_file(
                spec.project / 'tests/expectations.json'),
        },
        'compatibility': {
            'sdk_contract': spec.metadata['release']['sdk_contract'],
            'runner_contract': spec.metadata['release']['runner_contract'],
            'runner_version': runner_version,
            'emulator_source_revision': next(iter(emulator_revisions)),
            'jrasm_version': report['toolchain']['version'],
            'jrasm_revision': report['toolchain']['revision'],
        },
        'verification': {
            'runtime_profiles': runtime_entries,
            'hardware': 'not_run',
        },
        'license': spec.metadata['license'],
        'wav': spec.metadata['release']['wav'],
        'publication': spec.metadata['release']['publication'],
        'release_ready': tree_state == 'clean',
    }


def package_project(project: Path, jrasm: str | None = None,
                    lock_path: Path = DEFAULT_LOCK,
                    rules_path: Path = DEFAULT_RULES,
                    repository_root: Path = ROOT) -> Path:
    spec, report = build_project(
        project, jrasm, lock_path, rules_path, repository_root)
    version = spec.metadata['version']
    base = f'{spec.config["id"]}-{version}'
    package_dir = spec.project / 'build/package'
    package_dir.mkdir(parents=True, exist_ok=True)
    output = package_dir / (base + '.zip')
    temporary = package_dir / ('.' + base + '.zip.tmp')
    entries = {
        spec.config['output']: spec.output.read_bytes(),
        'README.md': (spec.project / 'README.md').read_bytes(),
        'game.json': (spec.project / 'game.json').read_bytes(),
        'LICENSE': ((spec.project / 'LICENSE' if spec.metadata['license'] != 'BSD-3-Clause'
                     else spec.repository_root / 'LICENSE').read_bytes()),
        'BUILD_REPORT.json': (json.dumps(report, ensure_ascii=False, indent=2,
                                         sort_keys=True) + '\n').encode('utf-8'),
    }
    if spec.metadata['license'] != 'BSD-3-Clause' and spec.sdk_inputs:
        entries['THIRD_PARTY_NOTICES.md'] = (
            spec.project / 'THIRD_PARTY_NOTICES.md').read_bytes()
        entries['LICENSES/BSD-3-Clause.txt'] = (
            spec.repository_root / 'LICENSE').read_bytes()
    if spec.metadata['schema_version'] == 2:
        if spec.metadata['release']['wav'] != 'not-required':
            raise ProjectError('WAV-required release packaging is not implemented')
        runtime_reports = release_runtime_reports(
            spec, report['artifact']['sha256'])
        manifest = release_manifest(spec, report, runtime_reports)
        entries['RELEASE.json'] = (json.dumps(
            manifest, ensure_ascii=False, indent=2, sort_keys=True) + '\n').encode('utf-8')
        for profile, payload, _ in runtime_reports:
            entries[f'VERIFICATION/{profile}.json'] = payload
    sums = ''.join(
        f'{hashlib.sha256(data).hexdigest()}  {name}\n'
        for name, data in sorted(entries.items())
    ).encode('ascii')
    entries['SHA256SUMS'] = sums
    try:
        with zipfile.ZipFile(temporary, 'w') as archive:
            for name, data in sorted(entries.items()):
                zip_entry(archive, f'{base}/{name}', data)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    return output


def clean_project(project: Path) -> bool:
    project = project.resolve()
    build_dir = project / 'build'
    if build_dir.parent != project or build_dir.name != 'build':
        raise ProjectError('Refusing unsafe build directory')
    if not build_dir.exists():
        return False
    if not build_dir.is_dir() or build_dir.is_symlink():
        raise ProjectError('Refusing to clean a non-directory or symlink build path')
    shutil.rmtree(build_dir)
    return True


def create_project(identifier: str, title: str, destination: Path | None,
                   template: Path = DEFAULT_TEMPLATE) -> Path:
    if not PROJECT_ID.fullmatch(identifier):
        raise ProjectError('Project ID must match [a-z][a-z0-9-]{0,31}')
    if not title.strip():
        raise ProjectError('Project title must not be empty')
    target = (destination if destination is not None else ROOT / 'games' / identifier).resolve()
    if target.exists():
        raise ProjectError(f'Destination already exists: {target}')
    shutil.copytree(template, target)
    config = read_json(target / 'build.json', 'template build configuration')
    config['id'] = identifier
    config['output'] = identifier + '.cjr'
    write_json(target / 'build.json', config)
    metadata = read_json(target / 'game.json', 'template game metadata')
    metadata['id'] = identifier
    metadata['title'] = title.strip()
    metadata['distribution']['file'] = identifier + '.cjr'
    write_json(target / 'game.json', metadata)
    readme = (target / 'README.md').read_text(encoding='utf-8')
    readme = readme.replace('Minimal JR-200 Project', title.strip(), 1)
    readme = readme.replace('minimal.cjr', identifier + '.cjr')
    (target / 'README.md').write_text(readme, encoding='utf-8')
    validate_project(target)
    return target


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument('--rules', type=Path, default=DEFAULT_RULES)
    value.add_argument('--lock', type=Path, default=DEFAULT_LOCK)
    value.add_argument('--jrasm', help='jrasm executable; overrides JRASM and PATH')
    commands = value.add_subparsers(dest='command', required=True)
    for name in ('validate', 'build', 'package', 'clean'):
        command = commands.add_parser(name)
        command.add_argument('--project', type=Path, required=True)
    new = commands.add_parser('new')
    new.add_argument('--id', required=True)
    new.add_argument('--title', required=True)
    new.add_argument('--destination', type=Path)
    return value


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == 'validate':
            spec = validate_project(args.project, args.rules)
            print(f'Project validation: OK ({spec.config["id"]})')
            print('Runtime verification: emulator=not_run hardware=not_run')
        elif args.command == 'build':
            spec, report = build_project(args.project, args.jrasm, args.lock, args.rules)
            artifact = report['artifact']
            print(f'Project build: OK ({spec.config["id"]})')
            print(f'CJR: {spec.output} ({artifact["size"]} bytes, SHA-256 {artifact["sha256"]})')
            print('Runtime verification: emulator=not_run hardware=not_run')
        elif args.command == 'package':
            output = package_project(args.project, args.jrasm, args.lock, args.rules)
            print(f'Project package: OK ({output})')
            metadata = validate_project(args.project, args.rules).metadata
            emulator = 'passed' if metadata['schema_version'] == 2 else 'not_run'
            print(f'Runtime verification: emulator={emulator} hardware=not_run')
        elif args.command == 'clean':
            removed = clean_project(args.project)
            print('Project clean: OK' if removed else 'Project clean: OK (nothing to remove)')
        else:
            target = create_project(args.id, args.title, args.destination)
            print(f'Project created: {target}')
            print('Project validation: OK')
            print('Runtime verification: emulator=not_run hardware=not_run')
    except (ProjectError, OSError, subprocess.SubprocessError) as exc:
        print(f'Project command failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
