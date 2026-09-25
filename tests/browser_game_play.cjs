// SPDX-License-Identifier: BSD-3-Clause
// Manual local-ROM acceptance for the loopback game-play server.
// Requires Playwright/Chromium; ROM and FONT paths are supplied only at runtime.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { chromium } = require('playwright');

function argumentsOf(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    assert.match(argv[index], /^--[a-z0-9-]+$/);
    assert.ok(index + 1 < argv.length, `Missing value for ${argv[index]}`);
    values[argv[index].slice(2)] = argv[index + 1];
  }
  for (const name of ['url', 'game', 'rom', 'font', 'sha256']) {
    assert.ok(values[name], `Missing --${name}`);
  }
  const url = new URL(values.url);
  assert.equal(url.hostname, '127.0.0.1');
  assert.equal(url.protocol, 'http:');
  assert.match(values.sha256, /^[0-9a-f]{64}$/);
  return { ...values, origin: url.origin };
}

async function quickType(page, text) {
  await page.locator('#quick-type-text').fill(text);
  await page.locator('#quick-type-start').click();
  await page.waitForFunction(() => document.querySelector('#quick-type-status')
    .textContent.includes('入力が完了しました。'), null, { timeout: 30000 });
}

async function main() {
  const args = argumentsOf(process.argv.slice(2));
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  const external = [];
  try {
    await page.route('**/*', route => {
      if (!route.request().url().startsWith(`${args.origin}/`)) {
        external.push(route.request().url());
        return route.abort();
      }
      return route.continue();
    });
    const catalogResponse = await page.request.get(`${args.origin}/game-catalog.json`);
    assert.equal(catalogResponse.status(), 200);
    const catalog = await catalogResponse.json();
    assert.equal(catalog.games.length, 1);
    const entry = catalog.games[0];
    assert.equal(entry.id, args.game);
    assert.equal(entry.sha256, args.sha256);
    const cjrResponse = await page.request.get(`${args.origin}/${entry.path}`);
    assert.equal(cjrResponse.status(), 200);
    assert.equal(crypto.createHash('sha256').update(await cjrResponse.body()).digest('hex'),
      args.sha256);
    await page.goto(`${args.origin}/?game=${args.game}`);
    await page.waitForFunction(() => document.querySelector('#game-launch-status')
      .textContent.includes('セットしました'), null, { timeout: 15000 });
    assert.equal(await page.locator('#remember-assets').isChecked(), false);
    await page.locator('#rom-combined').setInputFiles(args.rom);
    await page.locator('#font').setInputFiles(args.font);
    await page.waitForFunction(() => !document.querySelector('#start').disabled);
    await page.locator('#start').click();
    await page.waitForTimeout(1500);
    await page.locator('#behavior-heading').click();
    await page.locator('#cpu-speed').evaluate(element => {
      element.value = '1000';
      element.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await page.locator('#input-assist-heading').click();
    await page.locator('#quick-type-interval').evaluate(element => {
      element.value = '100';
      element.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await quickType(page, 'MLOAD\n');
    await page.waitForFunction(() => document.querySelector('#tape-status')
      .textContent.includes('状態: 終端'), null, { timeout: 60000 });
    assert.match(await page.locator('#tape-status').textContent(), /REMOTE OFF/);
    await quickType(page, `${entry.runCommand}\n`);
    await page.waitForTimeout(3000);
    if (args['play-key']) {
      await page.locator('#screen').click();
      await page.keyboard.press(args['play-key']);
      await page.waitForTimeout(1500);
    }
    if (args.screenshot) await page.screenshot({ path: args.screenshot });
    assert.deepEqual(external, []);
    console.log(JSON.stringify({ game: args.game, cjr_sha256: args.sha256,
      cassette: 'normal MLOAD', run_command: entry.runCommand,
      external_requests: external.length, play_key: args['play-key'] || null,
      screenshot: args.screenshot || null }));
  } finally {
    await browser.close();
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
