import { test, expect } from '@playwright/test';

async function ready(page, limit) {
  if (limit !== undefined) {
    await page.route('**/talk/slides.md', route => route.fulfill({ body: `---\ntime_limit: ${limit}\n---\n# One\n\n---\n\n# Two` }));
  }
  await page.goto('/');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  await page.clock.install();
  await page.clock.pauseAt(new Date(Date.now() + 100));
}

test('default five minutes counts down and expires before the final slide, then resumes once', async ({ page }) => {
  await ready(page);
  await page.keyboard.press('ArrowRight');
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
  await expect(page.locator('#position')).toHaveText('2 / 3');
  await page.keyboard.press('ArrowLeft');
  await expect(page.locator('#position')).toHaveText('1 / 3');
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

test('last five seconds grow progressively and shrink back in 0.8 seconds', async ({ page }) => {
  await ready(page, 0.1);
  await page.clock.fastForward(1_100);
  const countdown = page.locator('#countdown');
  for (let seconds = 5; seconds >= 1; seconds--) {
    await expect(countdown).toHaveText(String(seconds));
    await expect(countdown).toHaveClass('urgent');
    const sizes = await countdown.locator('span').evaluate(number => {
      const animation = number.getAnimations()[0];
      animation.pause();
      animation.currentTime = 0;
      const peak = parseFloat(getComputedStyle(number).fontSize);
      animation.currentTime = 800;
      return {
        peak, rest: parseFloat(getComputedStyle(number).fontSize),
        duration: animation.effect.getTiming().duration,
        shortSide: Math.min(innerWidth, innerHeight),
        normal: Math.min(48, Math.max(24, innerWidth * 0.04)),
      };
    });
    expect(sizes.peak).toBeCloseTo(sizes.shortSide * (6 - seconds) * 0.2, 1);
    expect(sizes.rest).toBeCloseTo(sizes.normal, 1);
    expect(sizes.duration).toBe(800);
    // The 200 ms polling must not restart the same number's animation.
    await page.clock.fastForward(400);
    expect(await countdown.locator('span').evaluate(number => number.getAnimations()[0].currentTime)).toBe(800);
    if (seconds > 1) await page.clock.fastForward(600);
  }
  await page.clock.fastForward(600);
  await expect(countdown).toBeHidden();
  await expect(page.locator('#time-expired')).toBeVisible();
});

test('reduced motion keeps the final countdown readable without scaling', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await ready(page, 0.1);
  await page.clock.fastForward(1_100);
  await expect(page.locator('#countdown')).toHaveText('5');
  await expect(page.locator('#countdown span')).toHaveCSS('animation-name', 'none');
});


test('final slide pauses the remaining time and returning resumes it', async ({ page }) => {
  await ready(page, 0.1);
  await page.clock.fastForward(1_100);
  await expect(page.locator('#countdown')).toHaveText('5');
  await page.keyboard.press('End');
  await expect(page.locator('#countdown')).toBeHidden();
  await page.clock.fastForward(60_000);
  await expect(page.locator('#time-expired')).toBeHidden();
  await page.keyboard.press('ArrowLeft');
  await expect(page.locator('#countdown')).toBeVisible();
  await expect(page.locator('#countdown')).toHaveText('5');
  await page.clock.fastForward(5_000);
  await expect(page.locator('#time-expired')).toBeVisible();
});

test('starting on the final slide, including a single slide, never expires', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '---\ntime_limit: 0.1\n---\n# Only slide' }));
  await ready(page);
  await page.clock.fastForward(60_000);
  await expect(page.locator('#countdown')).toBeHidden();
  await expect(page.locator('#time-expired')).toBeHidden();
  await page.unroute('**/talk/slides.md');
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '---\ntime_limit: 0.1\n---\n# First\n\n---\n\n# Last' }));
  await page.goto('/?final-slide-test#slide=2');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  await page.clock.fastForward(60_000);
  await expect(page.locator('#countdown')).toBeHidden();
  await expect(page.locator('#time-expired')).toBeHidden();
  await page.keyboard.press('Home');
  await expect(page.locator('#countdown')).toBeVisible();
  await page.clock.fastForward(6_100);
  await expect(page.locator('#time-expired')).toBeVisible();
});
