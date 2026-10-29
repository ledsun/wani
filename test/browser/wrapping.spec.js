import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';

test('body wrapping uses rendered width at twenty fullwidth characters and respects breaks', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({
    body: readFileSync(new URL('../fixtures/wrapping/slides.md', import.meta.url), 'utf8'),
  }));
  await page.goto('/#slide=1');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  const results = [];
  for (let index = 0; index < 6; index++) {
    if (index) await page.keyboard.press('ArrowRight');
    results.push(await page.locator('.slide.active .body').evaluate(body => {
      const lines = [...body.querySelectorAll('[data-wani-line]')];
      return {
        wraps: lines.map(line => line.style.whiteSpace),
        rows: lines.map(line => {
          const range = document.createRange();
          range.selectNodeContents(line);
          return new Set([...range.getClientRects()].map(rect => Math.round(rect.top))).size;
        }),
        fits: body.scrollWidth <= body.clientWidth + 1 && body.scrollHeight <= body.clientHeight + 1,
      };
    }));
  }
  expect(results.map(result => result.wraps)).toEqual([
    ['nowrap'], ['nowrap'], ['normal'], ['nowrap'],
    ['nowrap', 'nowrap'], ['nowrap', 'normal'],
  ]);
  expect(results[0].rows).toEqual([1]);
  expect(results[1].rows).toEqual([1]);
  expect(results[2].rows[0]).toBeGreaterThan(1);
  expect(results.every(result => result.fits)).toBe(true);
  await expect(page.locator('#stage strong')).toHaveText('綺麗なUI');
  await expect(page.locator('#warnings')).toBeHidden();
});
