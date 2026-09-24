#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Fetch an approved, digest-pinned runner Release without building the emulator."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import sys
import tempfile
import time
from urllib import error, parse, request
import zipfile

from emulator_runner import RunnerError, load_lock, verify_bundle
from ci_pipeline import PipelineError, validate_runner_lock


MAX_ARCHIVE = 8 * 1024 * 1024
MAX_EXPANDED = 16 * 1024 * 1024
MAX_ENTRIES = 16
REQUIRED_FILES = frozenset({'jr200_codec.mjs', 'jr200_codec.wasm',
    'LICENSE.txt', 'THIRD_PARTY_NOTICES.md', 'SBOM.spdx.json',
    'LICENSES/Emscripten-6.0.9.txt', 'LICENSES/VJR200.txt',
    'LICENSES/MAME_BSD-3-Clause.txt', 'LICENSES/libcxxabi-6.0.9.txt'})
RELEASE_PATH = re.compile(
    r'/zabaglione/jr200-web-emulator/releases/download/'
    r'[A-Za-z0-9][A-Za-z0-9._-]{0,63}/'
    r'jr200-runner-[A-Za-z0-9][A-Za-z0-9._-]{0,63}\.zip')
REDIRECT_HOSTS = frozenset({'github.com', 'release-assets.githubusercontent.com'})


class FetchError(ValueError):
    """An expected distribution, network or archive failure."""


def release_url(url: str) -> str:
    if not isinstance(url, str):
        raise FetchError('Runner release URL is missing')
    try:
        parsed = parse.urlsplit(url)
        approved = (parsed.scheme == 'https' and parsed.hostname == 'github.com'
                    and parsed.port is None and parsed.username is None
                    and parsed.password is None and not parsed.query
                    and not parsed.fragment
                    and RELEASE_PATH.fullmatch(parsed.path) is not None)
    except ValueError:
        approved = False
    if not approved:
        raise FetchError('Runner release URL is not an approved GitHub asset')
    return url


def redirect_url(url: str) -> None:
    try:
        parsed = parse.urlsplit(url)
        approved = (parsed.scheme == 'https' and parsed.hostname in REDIRECT_HOSTS
                    and parsed.port is None and parsed.username is None
                    and parsed.password is None)
    except ValueError:
        approved = False
    if not approved:
        raise FetchError('Runner download redirected outside approved HTTPS hosts')


class RestrictedRedirect(request.HTTPRedirectHandler):
    def __init__(self) -> None:
        super().__init__()
        self.count = 0

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        self.count += 1
        if self.count > 5:
            raise FetchError('Too many runner download redirects')
        redirect_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(url: str, destination: Path, expected_sha256: str) -> None:
    release_url(url)
    opener = request.build_opener(RestrictedRedirect())
    digest = hashlib.sha256()
    total = 0
    deadline = time.monotonic() + 60
    def expired(_signum, _frame):
        raise FetchError('Runner download exceeded time limit')
    previous_handler = signal.getsignal(signal.SIGALRM)
    previous_timer = signal.getitimer(signal.ITIMER_REAL)
    if previous_timer[0] != 0:
        raise FetchError('Runner download cannot reserve the time limit')
    signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, 60)
    try:
        with opener.open(request.Request(url, headers={
                'User-Agent': 'jr200-dev-runner-fetch/1'}), timeout=10) as response:
            redirect_url(response.geturl())
            with destination.open('xb') as output:
                while True:
                    if time.monotonic() > deadline:
                        raise FetchError('Runner download exceeded time limit')
                    reader = getattr(response, 'read1', response.read)
                    chunk = reader(min(64 * 1024, MAX_ARCHIVE + 1 - total))
                    if time.monotonic() > deadline:
                        raise FetchError('Runner download exceeded time limit')
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > MAX_ARCHIVE:
                        raise FetchError('Runner archive exceeds size limit')
                    digest.update(chunk)
                    output.write(chunk)
    except (OSError, error.URLError, ValueError) as exc:
        if isinstance(exc, FetchError):
            raise
        # HTTP errors can contain signed redirect URLs; never include their text.
        raise FetchError('Runner download failed') from None
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_handler)
    if digest.hexdigest() != expected_sha256:
        raise FetchError('Runner archive SHA-256 does not match lock')


def unpack_verified(archive: Path, destination: Path, lock: dict) -> None:
    if archive.stat().st_size > MAX_ARCHIVE:
        raise FetchError('Runner archive exceeds size limit')
    digest = hashlib.sha256()
    with archive.open('rb') as source:
        for chunk in iter(lambda: source.read(64 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != lock['source']['release_sha256']:
        raise FetchError('Runner archive SHA-256 does not match lock')
    try:
        with zipfile.ZipFile(archive) as bundle:
            entries = bundle.infolist()
            names = [item.filename for item in entries]
            if (len(entries) != len(REQUIRED_FILES) or len(entries) > MAX_ENTRIES
                    or len(set(names)) != len(names)
                    or set(names) != REQUIRED_FILES):
                raise FetchError('Runner archive file inventory is not approved')
            expanded = 0
            for item in entries:
                mode = (item.external_attr >> 16) & 0xffff
                if (item.is_dir() or item.flag_bits & 1
                        or (mode & 0o170000) not in (0, 0o100000)
                        or item.file_size <= 0):
                    raise FetchError('Runner archive has unsafe entry type')
                expanded += item.file_size
                if expanded > MAX_EXPANDED:
                    raise FetchError('Runner archive expands beyond size limit')
            for item in entries:
                target = destination / item.filename
                target.parent.mkdir(parents=True, exist_ok=True)
                with bundle.open(item) as source, target.open('xb') as output:
                    remaining = item.file_size
                    while remaining:
                        chunk = source.read(min(64 * 1024, remaining))
                        if not chunk:
                            raise FetchError('Runner archive entry was truncated')
                        output.write(chunk)
                        remaining -= len(chunk)
    except (zipfile.BadZipFile, RuntimeError, OSError) as exc:
        raise FetchError('Runner archive could not be safely extracted') from None
    try:
        verify_bundle(destination, lock)
        verify_notices(destination, lock)
    except RunnerError as exc:
        raise FetchError('Runner module or notice files do not match lock') from None


def verify_notices(directory: Path, lock: dict) -> None:
    expected_root = {'jr200_codec.mjs', 'jr200_codec.wasm', 'LICENSE.txt',
                     'THIRD_PARTY_NOTICES.md', 'SBOM.spdx.json', 'LICENSES'}
    legal_dir = directory / 'LICENSES'
    expected_legal = {name.split('/', 1)[1] for name in REQUIRED_FILES
                      if name.startswith('LICENSES/')}
    if (directory.is_symlink() or {path.name for path in directory.iterdir()} != expected_root
            or not legal_dir.is_dir() or legal_dir.is_symlink()
            or {path.name for path in legal_dir.iterdir()} != expected_legal):
        raise RunnerError('Runner bundle file inventory is not approved')
    for item in lock['notice_files']:
        path = directory / item['path']
        if (not path.is_file() or path.is_symlink() or path.parent.is_symlink()
                or path.stat().st_size != item['size']):
            raise RunnerError('Runner notice file does not match lock')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != item['sha256']:
            raise RunnerError('Runner notice file does not match lock')


def fetch(lock_path: Path, output: Path) -> Path | None:
    lock = load_lock(lock_path)
    source = lock['source']
    if source['availability'] == 'local_build_only':
        return None
    url = release_url(source['release_asset'])
    if output.is_symlink():
        raise FetchError('Runner output must not be a symlink')
    if output.exists():
        try:
            verify_bundle(output, lock)
            verify_notices(output, lock)
        except RunnerError as exc:
            raise FetchError('Existing runner output is invalid; refusing overwrite') from None
        return output
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.runner-fetch-', dir=output.parent) as temporary:
        archive = Path(temporary) / 'release.zip'
        download(url, archive, source['release_sha256'])
        staging = Path(temporary) / 'bundle'
        staging.mkdir()
        unpack_verified(archive, staging, lock)
        if output.exists() or output.is_symlink():
            raise FetchError('Runner output appeared during fetch')
        try:
            os.rename(staging, output)
        except FileExistsError:
            raise FetchError('Runner output appeared during fetch') from None
    return output


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lock', type=Path, default=Path('emulator.lock.json'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--github-output', type=Path)
    parser.add_argument('--target')
    parser.add_argument('--runner-lock', type=Path, default=Path('ci/runner.lock.json'))
    args = parser.parse_args(argv)
    try:
        if args.target is not None:
            runner = validate_runner_lock(json.loads(
                args.runner_lock.read_text(encoding='utf-8')))
            if runner['emulator']['runtime_policy'].get(args.target) == 'local_rom_only':
                print('Runner not fetched for local-ROM-only target')
                return 0
        result = fetch(args.lock, args.output)
        if result is None:
            print('Runner release unavailable; runtime remains not_run')
        else:
            if args.github_output:
                with args.github_output.open('a', encoding='utf-8') as output:
                    output.write(f'bundle={result.resolve()}\n')
            print('Verified fixed runner bundle')
    except (FetchError, RunnerError, PipelineError, OSError, json.JSONDecodeError) as exc:
        print(f'Runner fetch failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
