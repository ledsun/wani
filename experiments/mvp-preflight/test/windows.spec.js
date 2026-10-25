import { test, expect } from '@playwright/test';
import { ready } from './helpers.js';
import { readFile } from 'node:fs/promises';

test('Ruby user callbacks enter/exit fullscreen', async ({ page }) => {
  await ready(page);
  await page.locator('#fullscreen').click();
  await expect.poll(() => page.evaluate(() => document.fullscreenElement !== null)).toBe(true);
  await page.locator('#exit-fullscreen').click();
  await expect.poll(() => page.evaluate(() => document.fullscreenElement === null)).toBe(true);
  await page.keyboard.press('f');
  await expect.poll(() => page.evaluate(() => document.fullscreenElement !== null)).toBe(true);
  await page.keyboard.press('Escape');
  await expect.poll(() => page.evaluate(() => document.fullscreenElement === null)).toBe(true);
});

test('Ruby opens speaker window and postMessage synchronizes notes', async ({ page }) => {
  await ready(page);
  const popupPromise = page.waitForEvent('popup');
  await page.keyboard.press('n');
  const popup = await popupPromise;
  await expect(popup.locator('#position')).toHaveText('1');
  await expect(popup.locator('#notes strong')).toHaveText('notes');
  await expect(popup.locator('#body strong')).toHaveText('Ruby');
  await expect(page.locator('#stage')).not.toContainText('Speaker notes');
  await page.locator('#next').click();
  await expect(popup.locator('#position')).toHaveText('2');
  await expect(popup.locator('#notes')).toContainText('Notes for slide two.');
  await popup.evaluate(() => window.postMessage(JSON.stringify({ position: '999', title: 'spoof', notes_html: 'spoof' }), location.origin));
  await expect(popup.locator('#position')).toHaveText('2');
  await popup.close();
  await page.locator('#previous').click();
  await expect(page.locator('#position')).toHaveText('1 / 2');
});

test('browser sandbox popup denial is reported', async ({ page }) => {
  await page.route('**/denied.html', async route => route.fulfill({
    body: await readFile('public/index.html', 'utf8'), contentType: 'text/html',
    headers: { 'Content-Security-Policy': 'sandbox allow-scripts allow-same-origin' },
  }));
  await page.goto('/denied.html');
  await expect(page.locator('#status')).toHaveText('ready', { timeout: 90_000 });
  await page.locator('#speaker').click();
  await expect(page.locator('#status')).toHaveText('popup blocked', { timeout: 90_000 });
});

test('browser Permissions Policy fullscreen denial is reported', async ({ page }) => {
  await page.route('**/denied.html', async route => route.fulfill({
    body: await readFile('public/index.html', 'utf8'), contentType: 'text/html',
    headers: { 'Permissions-Policy': 'fullscreen=()' },
  }));
  await page.goto('/denied.html');
  await expect(page.locator('#status')).toHaveText('ready', { timeout: 90_000 });
  await page.locator('#fullscreen').click();
  await expect(page.locator('#status')).toContainText('fullscreen rejected', { timeout: 90_000 });
});
