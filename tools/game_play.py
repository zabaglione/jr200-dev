#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Serve one locally built game with the pinned web emulator on loopback only.

This is the interactive counterpart of emulator_runner.py (headless). It does
not build the emulator, publish anything, or read ROM/FONT files: the player
selects those in the browser.
"""
from __future__ import annotations

import argparse
import functools
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
from typing import Any
import webbrowser

sys.path.insert(0, str(Path(__file__).resolve().parent))
from emulator_runner import RunnerError, load_lock  # noqa: E402
from game_project import ProjectError, ROOT, validate_project  # noqa: E402
from jrasm_tool import sha256_file  # noqa: E402

DEFAULT_LOCK = ROOT / 'emulator.lock.json'
DEFAULT_PORT = 8765
LOOPBACK = '127.0.0.1'
# The staged site layout of jr200-web-emulator scripts/stage_web.py.
WEB_FILES = ('app.mjs', 'audio.mjs', 'codec.mjs', 'keyboard.mjs', 'game-launch.mjs',
             'index.html', 'style.css', 'LICENSE.txt', 'THIRD_PARTY_NOTICES.md',
             'SBOM.spdx.json', 'backend.json')
WEB_DIRECTORIES = ('LICENSES',)
STRICT_VERSION = re.compile(r'\d+\.\d+\.\d+')
BANNER = ('<div class="jr200-dev-banner" role="status">DEVELOPMENT BUILD - {title} '
          '{version} - local loopback only, not a published game</div>')
BANNER_CSS = ('.jr200-dev-banner{background:#7a1f00;color:#fff;font:bold 14px sans-serif;'
              'padding:6px 12px;text-align:center}\n')


class PlayError(ValueError):
    """Expected staging or serving failure."""


def build_is_current(spec: Any) -> dict[str, Any]:
    report_path = spec.project / 'build/build-report.json'
    if not spec.output.is_file() or not report_path.is_file():
        raise PlayError('No built CJR. Run: JRASM=/path/to/jrasm make game-build '
                        f'PROJECT={spec.project}')
    try:
        report = json.loads(report_path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
        raise PlayError(f'Cannot read build report: {exc}') from exc
    current = [{'path': relative, 'sha256': sha256_file(spec.project / relative)}
               for relative in (*spec.assembly_inputs, *spec.asset_inputs)]
    current += [{'path': '@repo/' + relative,
                 'sha256': sha256_file(spec.repository_root / relative)}
                for relative in spec.sdk_inputs]
    if (report.get('inputs') != current
            or report.get('artifact', {}).get('sha256') != sha256_file(spec.output)):
        raise PlayError('The built CJR is older than its sources. Rebuild with '
                        'make game-build before playing.')
    return report


def verify_web(web: Path, lock: dict[str, Any]) -> dict[str, str]:
    """Check the staged emulator site: allow-listed UI files plus locked codec."""
    web = web.resolve()
    if not (web / 'index.html').is_file():
        raise PlayError(f'Not a staged emulator site (index.html missing): {web}')
    digests = {}
    for name in WEB_FILES:
        path = web / name
        if not path.is_file() or path.is_symlink():
            raise PlayError(f'Staged emulator site is missing {name}')
        digests[name] = sha256_file(path)
    for directory in WEB_DIRECTORIES:
        if not (web / directory).is_dir() or (web / directory).is_symlink():
            raise PlayError(f'Staged emulator site is missing {directory}/')
    try:
        backend = json.loads((web / 'backend.json').read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
        raise PlayError('Invalid backend.json in the staged site') from exc
    if backend != {'backend': 'emscripten'}:
        raise PlayError('The staged site must use the Emscripten backend')
    for item in lock['module_files']:
        path = web / item['path']
        if (not path.is_file() or path.is_symlink()
                or path.stat().st_size != item['size']
                or sha256_file(path) != item['sha256']):
            raise PlayError(f'{item["path"]} does not match emulator.lock.json '
                            f'(revision {lock["source"]["revision"]})')
        digests[item['path']] = item['sha256']
    return digests


def license_file(spec: Any) -> Path:
    if spec.metadata['license'] == 'BSD-3-Clause':
        return spec.repository_root / 'LICENSE'
    return spec.project / 'LICENSE'


def stage(project: Path, web: Path, destination: Path,
          lock_path: Path = DEFAULT_LOCK) -> dict[str, Any]:
    try:
        spec = validate_project(project.resolve())
        lock = load_lock(lock_path)
    except (ProjectError, RunnerError) as exc:
        raise PlayError(str(exc)) from exc
    build_is_current(spec)
    web_digests = verify_web(web, lock)
    if destination.exists() and any(destination.iterdir()):
        raise PlayError(f'Staging directory is not empty: {destination}')
    destination.mkdir(parents=True, exist_ok=True)
    web = web.resolve()
    for name in WEB_FILES:
        shutil.copy2(web / name, destination / name)
    for item in lock['module_files']:
        shutil.copy2(web / item['path'], destination / item['path'])
    for directory in WEB_DIRECTORIES:
        shutil.copytree(web / directory, destination / directory, symlinks=False)
    metadata = spec.metadata
    identifier = metadata['id']
    version = metadata['version']
    catalog_version = version if STRICT_VERSION.fullmatch(version) else '0.0.0'
    game_dir = destination / 'games' / identifier / catalog_version
    game_dir.mkdir(parents=True)
    cjr = game_dir / f'{identifier}.cjr'
    shutil.copy2(spec.output, cjr)
    shutil.copy2(license_file(spec), game_dir / 'LICENSE.txt')
    notices = spec.project / 'THIRD_PARTY_NOTICES.md'
    if notices.is_file():
        shutil.copy2(notices, game_dir / 'THIRD_PARTY_NOTICES.md')
    title = metadata['title'] if catalog_version == version else f'{metadata["title"]} [{version}]'
    entry = {'id': identifier, 'title': title[:80], 'version': catalog_version,
             'path': f'games/{identifier}/{catalog_version}/{identifier}.cjr',
             'sha256': sha256_file(cjr), 'runCommand': metadata['run']['command']}
    (destination / 'game-catalog.json').write_text(
        json.dumps({'schemaVersion': 1, 'games': [entry]}, indent=2) + '\n',
        encoding='utf-8')
    index = (destination / 'index.html').read_text(encoding='utf-8')
    banner = BANNER.format(title=_escape(metadata['title']), version=_escape(version))
    if '<body>' not in index or '</head>' not in index:
        raise PlayError('Unexpected index.html layout; refusing to add the banner')
    index = index.replace('</head>', '  <link rel="stylesheet" href="dev-banner.css">\n</head>', 1)
    index = index.replace('<body>', '<body>\n' + banner, 1)
    (destination / 'index.html').write_text(index, encoding='utf-8')
    (destination / 'dev-banner.css').write_text(BANNER_CSS, encoding='utf-8')
    return {'id': identifier, 'version': version, 'catalog_version': catalog_version,
            'cjr_sha256': entry['sha256'], 'run_command': entry['runCommand'],
            'emulator_revision': lock['source']['revision'], 'web': web_digests}


def _escape(value: str) -> str:
    return (value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            .replace('"', '&quot;'))


class StagedHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map,
                      '.mjs': 'text/javascript', '.wasm': 'application/wasm',
                      '.cjr': 'application/octet-stream', '.json': 'application/json'}

    def list_directory(self, path: str) -> None:  # noqa: D102 - no listings
        self.send_error(404)
        return None

    def end_headers(self) -> None:
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        sys.stderr.write('play: ' + (format % args) + '\n')


def serve(directory: Path, port: int) -> ThreadingHTTPServer:
    handler = functools.partial(StagedHandler, directory=str(directory))
    try:
        return ThreadingHTTPServer((LOOPBACK, port), handler)
    except OSError as exc:
        raise PlayError(f'Cannot listen on {LOOPBACK}:{port} ({exc.strerror}). '
                        'Stop the other server or pass --port. A different port is a '
                        'different browser origin, so ROM/FONT storage is separate.') from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--web', type=Path, default=os.environ.get('JR200_WEB_SITE'),
                        help='staged jr200-web-emulator site (build/site)')
    parser.add_argument('--port', type=int, default=DEFAULT_PORT)
    parser.add_argument('--lock', type=Path, default=DEFAULT_LOCK)
    parser.add_argument('--no-browser', action='store_true')
    parser.add_argument('--stage-only', type=Path,
                        help='write the staged site to this empty directory and exit')
    args = parser.parse_args(argv)
    if args.web is None:
        parser.error('--web or JR200_WEB_SITE is required')
    if not 0 < args.port < 65536:
        parser.error('--port must be 1-65535')
    try:
        if args.stage_only is not None:
            report = stage(args.project, args.web, args.stage_only, args.lock)
            print(json.dumps(report, indent=2))
            return 0
        with tempfile.TemporaryDirectory(prefix='jr200-play-') as temporary:
            report = stage(args.project, args.web, Path(temporary) / 'site', args.lock)
            server = serve(Path(temporary) / 'site', args.port)
            url = f'http://{LOOPBACK}:{args.port}/?game={report["id"]}'
            print(f'Serving {report["id"]} {report["version"]} '
                  f'(CJR SHA-256 {report["cjr_sha256"]})')
            print(f'Emulator revision {report["emulator_revision"]}; loopback only.')
            print(f'Open {url}')
            print('Select your own ROM/FONT in the page, then type MLOAD and '
                  f'{report["run_command"]}. Press Ctrl-C to stop.')
            if not args.no_browser:
                try:
                    webbrowser.open(url)
                except webbrowser.Error:
                    print('Could not open a browser; open the URL manually.')
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                print('\nStopping the local server.')
            finally:
                server.server_close()
        return 0
    except PlayError as exc:
        print(f'Game play failed: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
