import { test, expect } from '@playwright/test';

async function ready(page) {
  await page.goto('/');
  await expect(page.locator('#status')).toHaveText('Ruby の DOM 操作の準備ができました', { timeout: 90_000 });
}

test('Ruby renders slides and handles keyboard navigation and boundaries', async ({ page }) => {
  const errors = [];
  const requests = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => requests.push(new URL(request.url())));
  await ready(page);
  await expect(page.locator('#slides section')).toHaveCount(3);
  await expect(page.locator('#slides section:visible')).toHaveCount(1);
  await expect(page.locator('#slides section:visible h1')).toHaveText('Ruby から DOM を操作');
  await expect(page.locator('#slides strong').first()).toHaveText('kramdown');
  await expect(page.locator('#position')).toHaveText('1 / 3');
  await expect(page.locator('#previous')).toBeDisabled();
  await page.locator('body').click({ position: { x: 5, y: 5 } });
  await page.keyboard.press('ArrowLeft');
  await expect(page.locator('#position')).toHaveText('1 / 3');
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('#position')).toHaveText('2 / 3');
  await expect(page.locator('#slides section:visible h1')).toHaveText('キーボード操作');
  await page.keyboard.press('ArrowRight');
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('#position')).toHaveText('3 / 3');
  await expect(page.locator('#next')).toBeDisabled();
  await page.keyboard.press('ArrowLeft');
  await expect(page.locator('#position')).toHaveText('2 / 3');
  await page.keyboard.press('Control+ArrowRight');
  await expect(page.locator('#position')).toHaveText('2 / 3');
  await page.locator('#markdown').focus();
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('#position')).toHaveText('2 / 3');
  await page.locator('#previous').click();
  await expect(page.locator('#position')).toHaveText('1 / 3');
  await page.locator('#next').click();
  await expect(page.locator('#position')).toHaveText('2 / 3');
  expect(errors).toEqual([]);
  expect(requests.some(url => url.pathname === '/slides.wasm')).toBe(true);
  expect(requests.every(url => url.origin === 'http://127.0.0.1:8080')).toBe(true);
  expect(requests.filter(url => /\.(rb|gem)$/.test(url.pathname))).toEqual([]);
});

test('redraw resets the deck and keeps callbacks usable; empty input works', async ({ page }) => {
  await ready(page);
  await page.locator('#next').click();
  await page.locator('#markdown').fill('# 差し替え\r\n\r\n---\r\n\r\n**二枚目**');
  await page.locator('#render').click();
  await expect(page.locator('#slides section')).toHaveCount(2);
  await expect(page.locator('#position')).toHaveText('1 / 2');
  await expect(page.locator('#slides section:visible h1')).toHaveText('差し替え');
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('#position')).toHaveText('2 / 2');
  await expect(page.locator('#slides section:visible strong')).toHaveText('二枚目');
  await page.locator('#markdown').fill('');
  await page.locator('#render').click();
  await expect(page.locator('#position')).toHaveText('1 / 1');
  await expect(page.locator('#slides section')).toHaveCount(1);
  await expect(page.locator('#previous')).toBeDisabled();
  await expect(page.locator('#next')).toBeDisabled();
});
