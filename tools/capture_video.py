#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Make a gallery video (WebM: VP9 + Opus) from a tested runtime profile.

Frames and sound are the fixed emulator's own output for the profile's replay;
nothing is drawn or dubbed afterwards. An optional speed-up keeps long first
goals short and is recorded in the output metadata. Requires FFMPEG (or ffmpeg
on PATH) with libvpx-vp9 and libopus; it is an external tool, not vendored.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from emulator_runner import (DEFAULT_LOCK, DEFAULT_NODE_RUNNER, RunnerError,
                             load_lock, request_for_project, run, verify_bundle)  # noqa: E402
from game_project import validate_project  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CAPTURE = ROOT / 'tools/jr200_capture.mjs'


def capture(project: Path, profile: str, bundle: Path, output: Path, fps: int = 30,
            speed: float = 1.0, lock_path: Path = DEFAULT_LOCK,
            rom: Path | None = None, font: Path | None = None,
            self_font: Path | None = None, start_cycle: int = 0) -> dict:
    lock = load_lock(lock_path)
    verify_bundle(bundle, lock)
    spec = validate_project(project.resolve())
    request, runtime = request_for_project(spec.project, spec.output, profile, rom, font)
    if runtime['mode'] == 'rom-cassette':
        if (self_font is None or not self_font.is_file() or start_cycle <= 0
                or start_cycle >= request['max_cycles']):
            raise RunnerError('ROM video requires authored font and a game-only start cycle')
    elif self_font is not None or start_cycle != 0:
        raise RunnerError('Synthetic video does not use ROM capture settings')
    if not 1 <= fps <= 60 or not 1.0 <= speed <= 4.0:
        raise RunnerError('Invalid frame rate or speed')
    ffmpeg = os.environ.get('FFMPEG') or shutil.which('ffmpeg')
    if not ffmpeg:
        raise RunnerError('Set FFMPEG to an ffmpeg with libvpx-vp9 and libopus')
    if output.exists():
        raise RunnerError(f'Refusing to overwrite {output}')
    run(spec.project, bundle, 'node', DEFAULT_NODE_RUNNER, lock_path,
        profile=profile, rom=rom, font=font)
    with tempfile.TemporaryDirectory(prefix='jr200-video-') as temporary:
        work = Path(temporary)
        (work / 'request.json').write_text(json.dumps(request))
        command = ['node', str(CAPTURE), '--bundle', str(bundle.resolve()),
                   '--request', str(work / 'request.json'),
                   '--frames', str(work / 'frames.rgba'), '--pcm', str(work / 'audio.pcm'),
                   '--summary', str(work / 'summary.json'),
                   '--system-api', str(lock['build']['system_api_version']),
                   '--fps', str(fps), '--start-cycle', str(start_cycle)]
        if self_font is not None:
            command.extend(('--self-font-data', str(self_font.resolve())))
        subprocess.run(command, check=True)
        summary = json.loads((work / 'summary.json').read_text())
        filters_v = ['scale=640:448:flags=neighbor']
        filters_a = []
        if speed != 1.0:
            filters_v.insert(0, f'setpts=PTS/{speed}')
            filters_a.append(f'atempo={speed}' if speed <= 2 else
                             f'atempo=2,atempo={speed / 2}')
        command = [ffmpeg, '-hide_banner', '-loglevel', 'error',
                   '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', '320x224', '-r', str(fps),
                   '-i', str(work / 'frames.rgba'),
                   '-f', 's16le', '-ar', str(summary['pcm_rate']), '-ac', '1',
                   '-i', str(work / 'audio.pcm'),
                   '-vf', ','.join(filters_v), '-c:v', 'libvpx-vp9', '-b:v', '0', '-crf', '30',
                   '-row-mt', '1', '-pix_fmt', 'yuv420p', '-c:a', 'libopus', '-b:a', '48k']
        if filters_a:
            command += ['-af', ','.join(filters_a)]
        command += ['-shortest', '-map_metadata', '-1', str(output)]
        subprocess.run(command, check=True)
    duration = summary['frames'] / fps / speed
    return {'file': output.name, 'profile': profile, 'mode': runtime['mode'],
            'artifact_sha256': request['artifact']['sha256'],
            'start_cycle': start_cycle, 'fps': fps, 'speed': speed,
            'seconds': round(duration, 1), 'frames': summary['frames'],
            'frames_sha256': summary['frames_sha256'], 'pcm_sha256': summary['pcm_sha256'],
            'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--profile', required=True)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--fps', type=int, default=30)
    parser.add_argument('--speed', type=float, default=1.0)
    parser.add_argument('--rom', type=Path)
    parser.add_argument('--font', type=Path)
    parser.add_argument('--self-font', type=Path)
    parser.add_argument('--start-cycle', type=int, default=0)
    args = parser.parse_args(argv)
    try:
        print(json.dumps(capture(args.project, args.profile, args.bundle, args.output,
                                 args.fps, args.speed, rom=args.rom, font=args.font,
                                 self_font=args.self_font,
                                 start_cycle=args.start_cycle), indent=2))
    except (RunnerError, subprocess.CalledProcessError, OSError) as exc:
        print(f'Video capture failed: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
