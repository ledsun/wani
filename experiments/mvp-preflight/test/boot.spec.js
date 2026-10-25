import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { ready } from './helpers.js';
import { createHash } from 'node:crypto';

test('pinned PR loader boots packed Ruby without rewriting JavaScript', async ({ page }) => {
  const requests = [];
  page.on('request', request => requests.push(new URL(request.url())));
  await ready(page);
  await expect(page.locator('#stage strong').first()).toHaveText('Ruby');
  expect(requests.every(url => url.origin === 'http://127.0.0.1:8080')).toBe(true);
  expect(requests.filter(url => url.pathname.endsWith('.js')).map(url => url.pathname)).toEqual(['/runtime.pr672.js']);
  expect(requests.filter(url => url.pathname.endsWith('.wasm')).map(url => url.pathname)).toEqual(['/preflight.wasm']);
  expect(requests.some(url => url.pathname === '/slides.md')).toBe(true);
  const inline = await page.locator('script:not([src])').allTextContents();
  expect(inline).toEqual([]);
  await expect(page.locator('script[src="runtime.pr672.js"]')).toHaveAttribute('data-ruby-wasm-url', './preflight.wasm');
  const vendored = await readFile('third_party/ruby-wasm-loader/browser.script.iife.js');
  expect(await readFile('public/runtime.pr672.js')).toEqual(vendored);
  const provenance = JSON.parse(await readFile('third_party/ruby-wasm-loader/provenance.json', 'utf8'));
  expect(createHash('sha256').update(vendored).digest('hex')).toBe(provenance.loader_sha256);
});

test('PR loader preserves CDN default when the attribute is omitted', async ({ page }) => {
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

test('HTML attribute selects a different local wasm path', async ({ page }) => {
  const requests = [];
  page.on('request', request => requests.push(request.url()));
  const html = (await readFile('public/index.html', 'utf8')).replace('data-ruby-wasm-url="./preflight.wasm"', 'data-ruby-wasm-url="./selected.wasm"');
  await page.route('**/selected.html', route => route.fulfill({ body: html, contentType: 'text/html' }));
  await page.route('**/selected.wasm', route => route.fulfill({ path: 'public/preflight.wasm', contentType: 'application/wasm' }));
  await page.goto('/selected.html');
  await expect(page.locator('#status')).toHaveText('ready', { timeout: 90_000 });
  expect(requests.filter(url => url.endsWith('.wasm'))).toEqual(['http://127.0.0.1:8080/selected.wasm']);
});

test('missing custom wasm fails without falling back to CDN', async ({ page }) => {
  const requests = [];
  page.on('request', request => requests.push(request.url()));
  const html = (await readFile('public/index.html', 'utf8')).replace('data-ruby-wasm-url="./preflight.wasm"', 'data-ruby-wasm-url="./missing.wasm"');
  await page.route('**/missing-loader.html', route => route.fulfill({ body: html, contentType: 'text/html' }));
  const failed = page.waitForEvent('pageerror');
  await page.goto('/missing-loader.html');
  await failed;
  expect(requests.filter(url => url.endsWith('.wasm'))).toEqual(['http://127.0.0.1:8080/missing.wasm']);
  await expect(page.locator('#status')).toHaveText('Loading Ruby…');
});

test('empty wasm attribute is rejected before fetching wasm', async ({ page }) => {
  const requests = [];
  page.on('request', request => requests.push(request.url()));
  const html = (await readFile('public/index.html', 'utf8')).replace('data-ruby-wasm-url="./preflight.wasm"', 'data-ruby-wasm-url=""');
  await page.route('**/invalid-loader.html', route => route.fulfill({ body: html, contentType: 'text/html' }));
  const failed = page.waitForEvent('pageerror');
  await page.goto('/invalid-loader.html');
  expect((await failed).message).toContain('data-ruby-wasm-url must be non-empty');
  expect(requests.filter(url => url.endsWith('.wasm'))).toEqual([]);
});

test('Ruby reports a missing Markdown file', async ({ page }) => {
  await page.goto('/?file=missing.md');
  await expect(page.locator('#status')).toContainText('Markdown HTTP 404', { timeout: 90_000 });
});
