import { test, expect } from '@playwright/test';

async function ready(page, limit) {
  if (limit !== undefined) {
    await page.route('**/talk/slides.md', route => route.fulfill({ body: `---\ntime_limit: ${limit}\n---\n# One\n\n---\n\n# Two` }));
  }
  await page.goto('/');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  await page.clock.install();
}

test('default five minutes counts down and expires even on the final slide, then resumes once', async ({ page }) => {
  await ready(page);
  await page.keyboard.press('End');
  await expect(page.locator('#countdown')).toBeHidden();
  await page.clock.fastForward(269_000);
  await expect(page.locator('#countdown')).toBeHidden();
  await page.clock.fastForward(1_100);
  await expect(page.locator('#countdown')).toHaveText('残り 30 秒');
  await page.keyboard.press('f');
  await expect.poll(() => page.evaluate(() => document.fullscreenElement !== null)).toBe(true);
  await expect(page.locator('#countdown')).toBeVisible();
  await page.clock.fastForward(29_900);
  await expect(page.locator('#time-expired')).toBeVisible();
  await expect(page.locator('#countdown')).toBeHidden();
  const image = await page.request.get('/assets/time-expired.png');
  expect(image.ok()).toBe(true);
  expect(image.headers()['content-type']).toBe('image/png');
  await expect(page.locator('#next')).toBeEnabled();
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('#time-expired')).toBeHidden();
  await expect(page.locator('#position')).toHaveText('3 / 3');
  await page.keyboard.press('ArrowLeft');
  await expect(page.locator('#position')).toHaveText('2 / 3');
  await page.clock.fastForward(600_000);
  await expect(page.locator('#time-expired')).toBeHidden();
});

test('custom fractional minutes expire; left arrow recovers at the first slide', async ({ page }) => {
  await ready(page, 0.5);
  await expect(page.locator('#countdown')).toBeVisible();
  await page.clock.fastForward(30_100);
  await expect(page.locator('#time-expired')).toBeVisible();
  await page.emulateMedia({ media: 'print' });
  await expect(page.locator('#time-expired')).toBeHidden();
  await expect(page.locator('#countdown')).toBeHidden();
  await expect(page.locator('#print-pages .print-sheet')).toHaveCount(2);
  await page.emulateMedia({ media: 'screen' });
  await page.keyboard.press('ArrowLeft');
  await expect(page.locator('#time-expired')).toBeHidden();
  await expect(page.locator('#position')).toHaveText('1 / 2');
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('#position')).toHaveText('2 / 2');
});

test('zero disables the timer', async ({ page }) => {
  await ready(page, 0);
  await page.clock.fastForward(3_600_000);
  await expect(page.locator('#countdown')).toBeHidden();
  await expect(page.locator('#time-expired')).toBeHidden();
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('#position')).toHaveText('2 / 2');
});

test('resume button recovers and reload starts a fresh timer', async ({ page }) => {
  await ready(page, 0.1);
  await page.clock.fastForward(6_100);
  await expect(page.locator('#time-expired')).toBeVisible();
  await page.locator('#resume-slides').click();
  await expect(page.locator('#time-expired')).toBeHidden();
  await page.reload();
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  await expect(page.locator('#time-expired')).toBeHidden();
  await expect(page.locator('#countdown')).toBeVisible();
});
