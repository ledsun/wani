import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { ready } from './helpers.js';

test('configured upstream loader boots packed Ruby without application JavaScript', async ({ page }) => {
  const requests = [];
  page.on('request', request => requests.push(new URL(request.url())));
  await ready(page);
  await expect(page.locator('#stage strong').first()).toHaveText('Ruby');
  expect(requests.every(url => url.origin === 'http://127.0.0.1:8080')).toBe(true);
  expect(requests.filter(url => url.pathname.endsWith('.js')).map(url => url.pathname)).toEqual(['/runtime.local.js']);
  expect(requests.some(url => url.pathname === '/slides.md')).toBe(true);
  const inline = await page.locator('script:not([src])').allTextContents();
  expect(inline).toEqual([]);
  const original = await readFile('public/runtime.original.js', 'utf8');
  const local = await readFile('public/runtime.local.js', 'utf8');
  expect(local).toBe(original.replace('`https://cdn.jsdelivr.net/npm/${pkg.name}@${pkg.version}/dist/ruby+stdlib.wasm`', '"./preflight.wasm"'));
});

test('unmodified loader requests the hardcoded CDN wasm', async ({ page }) => {
  const requests = [];
  await page.route('https://cdn.jsdelivr.net/**', async route => {
    requests.push(route.request().url());
    await route.abort(); // Observe dependency; do not disguise it as a local runtime.
  });
  await page.goto('/original.html');
  await expect.poll(() => requests.length).toBe(1);
  expect(requests[0]).toBe('https://cdn.jsdelivr.net/npm/@ruby/4.0-wasm-wasi@2.10.1/dist/ruby+stdlib.wasm');
  await expect(page.locator('#status')).toHaveText('loading');
});

test('Ruby reports a missing Markdown file', async ({ page }) => {
  await page.goto('/?file=missing.md');
  await expect(page.locator('#status')).toContainText('Markdown HTTP 404', { timeout: 90_000 });
});
