import { test, expect } from '@playwright/test';

test('embedded Ruby and kramdown convert text without fetching Ruby sources', async ({ page }) => {
  const requests = [];
  const errors = [];
  page.on('request', request => requests.push(new URL(request.url()).pathname));
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/');
  await expect(page.locator('#status')).toHaveText('Ruby / kramdown の準備ができました', { timeout: 90_000 });
  const button = page.getByRole('button', { name: 'HTML に変換' });
  await expect(button).toBeEnabled({ timeout: 90_000 });
  await button.click();
  await expect(page.locator('#output')).toContainText('<h1 id="ruby">こんにちは Ruby</h1>');
  await expect(page.locator('#output')).toContainText('<strong>kramdown</strong>');
  await page.locator('#markdown').fill('- one\n- two\n\n**再変換** & <script>alert("x")</script>\n\n`#{raise "injected"}`');
  await button.click();
  await expect(page.locator('#output')).toContainText('<li>two</li>');
  await expect(page.locator('#output')).toContainText('<strong>再変換</strong>');
  await expect(page.locator('#output')).toContainText('#{raise "injected"}');
  await expect(page.locator('#output script')).toHaveCount(0);
  await page.locator('#markdown').fill('');
  await button.click();
  await expect(page.locator('#output')).toHaveText('');
  expect(errors).toEqual([]);
  expect(requests).toContain('/kramdown.wasm');
  expect(requests.filter(url => /\.(rb|gem)$/.test(url))).toEqual([]);
  expect(requests.every(url => ['/', '/app.js', '/browser.umd.js', '/kramdown.wasm', '/favicon.ico'].includes(url))).toBe(true);
});
