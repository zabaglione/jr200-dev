#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Local-only BRICK PULSE stage-12 Safari probe; no ROM/FONT is served."""
import argparse
import hashlib
import http.server
import json
import mimetypes
import statistics
import sys
import threading
import time
from pathlib import Path
from urllib.parse import urlsplit
from urllib.error import HTTPError
from urllib.request import urlopen

ROOT = None
PAGES = 'https://zabaglione.github.io/jr200-web-emulator/'
PAGES_MODE = False
ASSET_CACHE = {}
CANDIDATE_BYTES = None
CJR_PATH = ''


class Site(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT / 'build/site'), **kwargs)

    def log_message(self, *_args):
        pass

    def do_GET(self):
        path = urlsplit(self.path).path
        if '..' in path or not path.startswith('/'):
            self.send_error(400)
            return
        if PAGES_MODE:
            name = path.lstrip('/') or 'index.html'
            if CANDIDATE_BYTES is not None and name == CJR_PATH:
                payload = CANDIDATE_BYTES
            else:
                if name not in ASSET_CACHE:
                    try:
                        with urlopen(PAGES + name, timeout=30) as response:
                            ASSET_CACHE[name] = response.read(2 * 1024 * 1024)
                    except HTTPError as exc:
                        self.send_error(exc.code)
                        return
                payload = ASSET_CACHE[name]
                if CANDIDATE_BYTES is not None and name == 'game-catalog.json':
                    catalog = json.loads(payload)
                    entry = next(game for game in catalog['games']
                                 if game['id'] == 'brick-pulse')
                    entry['sha256'] = hashlib.sha256(CANDIDATE_BYTES).hexdigest()
                    payload = json.dumps(catalog).encode()
        else:
            target = ROOT / 'build/site' / (path.lstrip('/') or 'index.html')
            if not target.is_file():
                self.send_error(404)
                return
            payload = target.read_bytes()
        if path == '/app.mjs':
            source = payload.decode()
            needle = 'let codec;'
            assert source.count(needle) == 1
            probe = '''let codec;
window.__brickProbe = {
  get core() { return codec; },
  samples: [],
  latencies: [],
  missed: [],
  keydowns: [],
  install() {
    const original = codec.machine.run.bind(codec.machine);
    codec.machine.run = cycles => {
      const start = performance.now();
      const result = original(cycles);
      if (codec.machine.peek(0x4620) === 1 && codec.machine.peek(0x4621) === 11)
        this.samples.push(performance.now() - start);
      return result;
    };
    let pending = null;
    document.addEventListener('keydown', event => {
      if ((event.key === 'a' || event.key === 'd') && !event.repeat) {
        this.keydowns.push({key:event.key, paddle:codec.machine.peek(0x4659)});
        if (pending) this.missed.push(pending.key);
        pending = {key: event.key, at: performance.now(),
          paddle: codec.machine.peek(0x4659)};
      }
    }, true);
    const samplePaddle = () => {
      if (pending && codec.machine.peek(0x4659) !== pending.paddle) {
        this.latencies.push({key: pending.key,
          ms: performance.now() - pending.at,
          from: pending.paddle, to: codec.machine.peek(0x4659)});
        pending = null;
      }
      requestAnimationFrame(samplePaddle);
    };
    requestAnimationFrame(samplePaddle);
  }
};'''
            payload = source.replace(needle, probe).encode()
        self.send_response(200)
        self.send_header('Content-Type', mimetypes.guess_type(path if path != '/' else 'index.html')[0] or 'application/octet-stream')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(payload)


def key(driver, value, hold=150):
    driver.call('POST', '/actions', {'actions': [{
        'type': 'key', 'id': 'keyboard', 'actions': [
            {'type': 'keyDown', 'value': value},
            {'type': 'pause', 'duration': hold},
            {'type': 'keyUp', 'value': value},
        ]}]})
    driver.call('DELETE', '/actions')


def read(driver):
    return driver.execute('''const c = window.__brickProbe.core.machine;
      return {mode:c.peek(0x4620), level:c.peek(0x4621),
              paddle:c.peek(0x4659), held:c.peek(0x4678),
              cycles:c.state().cycles};''')


def wait(driver, predicate, timeout=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        state = read(driver)
        if predicate(state):
            return state
        time.sleep(.05)
    raise RuntimeError(f'game state timeout: {state}')


def wait_latency(driver, count, key_name, timeout=2):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        result = driver.execute('''return {latencies:window.__brickProbe.latencies,
          missed:window.__brickProbe.missed,
          keydowns:window.__brickProbe.keydowns};''')
        assert not result['missed'], result
        if len(result['latencies']) > count:
            assert len(result['latencies']) == count + 1, result
            sample = result['latencies'][-1]
            assert sample['key'] == key_name, sample
            assert 0 <= sample['ms'] <= 200, sample
            if key_name == 'a':
                assert sample['to'] < sample['from'], sample
            else:
                assert sample['to'] > sample['from'], sample
            return sample
        time.sleep(.02)
    raise RuntimeError(f'No paddle response for {key_name}: {result}; state={read(driver)}')


def main():
    global ROOT, PAGES_MODE, CANDIDATE_BYTES, CJR_PATH
    p = argparse.ArgumentParser()
    p.add_argument('--webdriver', required=True)
    p.add_argument('--emulator', type=Path, required=True)
    p.add_argument('--pages', action='store_true')
    p.add_argument('--candidate-cjr', type=Path)
    p.add_argument('--rom', type=Path, required=True)
    p.add_argument('--font', type=Path, required=True)
    a = p.parse_args()
    assert not a.candidate_cjr or a.pages, 'Candidate requires --pages proxy'
    ROOT = a.emulator.resolve()
    PAGES_MODE = a.pages
    sys.path.insert(0, str(ROOT / 'tests'))
    from webdriver_real_rom_smoke import WebDriver  # noqa: E402
    assert a.rom.stat().st_size == 16384 and a.font.stat().st_size == 2048
    catalog = json.loads((ROOT / 'web/game-catalog.json').read_text())
    selected = next(x for x in catalog['games'] if x['id'] == 'brick-pulse')
    CJR_PATH = selected['path']
    if a.candidate_cjr:
        assert a.candidate_cjr.is_file() and not a.candidate_cjr.is_symlink()
        CANDIDATE_BYTES = a.candidate_cjr.read_bytes()
        assert 0 < len(CANDIDATE_BYTES) < 1024 * 1024
    if PAGES_MODE:
        with urlopen(PAGES + 'game-catalog.json', timeout=30) as response:
            assert json.load(response) == catalog
        with urlopen(PAGES + selected['path'], timeout=30) as response:
            assert hashlib.sha256(response.read()).hexdigest() == selected['sha256']
        with urlopen(PAGES + 'backend.json', timeout=30) as response:
            assert json.load(response) == {'backend':'emscripten'}
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Site)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    driver = WebDriver(a.webdriver)
    try:
        driver.start('safari')
        driver.call('POST', '/window/rect', {'x':0,'y':0,'width':1280,'height':800})
        driver.call('POST', '/url', {'url':f'http://127.0.0.1:{server.server_port}/?game=brick-pulse&launch=1'})
        for _ in range(100):
            try:
                driver.find('#status')
                break
            except RuntimeError:
                time.sleep(.1)
        driver.wait_text('#status', 'WASM起動済み', 30)
        driver.upload('#rom-combined', str(a.rom))
        driver.upload('#font', str(a.font))
        driver.wait_text('#game-launch-status', 'を起動しました', 120)
        driver.click('#screen')
        key(driver, '\ue006')
        wait(driver, lambda s: s['mode'] == 1 and s['level'] == 0)
        # Diagnostic state setup only: the distributed CJR and renderer are unchanged.
        driver.execute('''const c=window.__brickProbe.core.machine;
          c.poke(0x4621,10); c.poke(0x4620,2);''')
        key(driver, '\ue006')
        initial = wait(driver, lambda s: s['mode'] == 1 and s['level'] == 11)
        driver.execute('window.__brickProbe.install()')
        time.sleep(5)
        samples = driver.execute('return window.__brickProbe.samples.splice(0)')
        assert len(samples) >= 100, len(samples)
        assert max(samples) < 16.7, max(samples)
        driver.execute('''const c=window.__brickProbe.core.machine;
          c.poke(0x4621,10); c.poke(0x4620,2);''')
        driver.click('#screen')
        time.sleep(.5)
        key(driver, '\ue006', 500)
        wait(driver, lambda s: s['mode'] == 1 and s['level'] == 11)
        base = read(driver)
        driver.click('#screen')
        key(driver, 'd', 120)
        latency_records = [wait_latency(driver, 0, 'd')]
        after_short = wait(driver, lambda s: s['paddle'] != base['paddle'])
        for value in 'adad':
            time.sleep(.2)
            key(driver, value, 180)
            latency_records.append(wait_latency(driver, len(latency_records), value))
        latencies = [item['ms'] for item in latency_records]
        assert len(latencies) == 5, latencies
        time.sleep(.6)
        stopped = read(driver)
        time.sleep(.4)
        released = read(driver)
        assert stopped['paddle'] == released['paddle'], (stopped,released)
        driver.call('POST', '/actions', {'actions': [{'type':'key','id':'keyboard',
             'actions':[{'type':'keyDown','value':'a'}]}]})
        after_hold = wait(driver, lambda s: s['paddle'] < released['paddle'])
        time.sleep(.4)
        long_held = read(driver)
        assert long_held['paddle'] < after_hold['paddle']
        driver.call('DELETE', '/actions')
        lost = wait(driver, lambda s: s['mode'] == 3, 30)
        driver.click('#screen')
        key(driver, '\ue006', 500)
        key(driver, 'd', 150)
        key(driver, '\ue006', 500)
        retry = wait(driver, lambda s: s['mode'] == 1 and s['level'] == 11)
        driver.call('POST', '/actions', {'actions': [{'type':'key','id':'keyboard',
             'actions':[{'type':'keyDown','value':'a'}]}]})
        before_blur = wait(driver, lambda s: s['held'] == 3 and
                           0 < s['paddle'] < retry['paddle'])
        assert before_blur['paddle'] > 0, before_blur
        original_handle = driver.call('GET', '/window')
        new_tab = driver.call('POST', '/window/new', {'type':'tab'})
        driver.call('POST', '/window', {'handle':new_tab['handle']})
        time.sleep(.4)
        driver.call('POST', '/window', {'handle':original_handle})
        time.sleep(.4)
        blur_stopped = read(driver)
        time.sleep(.4)
        blur_released = read(driver)
        assert blur_stopped['held'] == 0, blur_stopped
        assert blur_stopped['paddle'] > 0, blur_stopped
        assert blur_stopped['paddle'] == blur_released['paddle']
        driver.call('DELETE', '/actions')
        print(json.dumps({'browser':driver.capabilities.get('browserVersion'),
          'cjr_sha256':hashlib.sha256(CANDIDATE_BYTES).hexdigest()
            if CANDIDATE_BYTES is not None else selected['sha256'],
          'source':'candidate' if CANDIDATE_BYTES is not None else 'published',
          'stage':initial['level']+1,'run_samples':len(samples),
          'run_ms_p95':sorted(samples)[int(len(samples)*.95)],
          'run_ms_max':max(samples),'run_ms_mean':statistics.mean(samples),
          'latency_samples':len(latencies),
          'latency_events':latency_records,
          'latency_ms_p95':sorted(latencies)[int(len(latencies)*.95)],
          'latency_ms_max':max(latencies),
          'states':{'initial':initial,'short':after_short,'released':released,
                    'hold':long_held,'before_blur':before_blur,
                    'blur_released':blur_released,
                    'lost':lost,'retry':retry}},
          sort_keys=True))
    finally:
        driver.close()
        server.shutdown()


if __name__ == '__main__':
    main()
