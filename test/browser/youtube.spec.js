import { test, expect } from '@playwright/test';

test('YouTube playback is stopped on navigation and printing uses a thumbnail', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ contentType: 'text/markdown', body: '# Cover\n\n---\n\n# Video\n\n![Example](https://www.youtube.com/watch?v=M7lc1UVf-VE&start=90&end=150)\n\n---\n\n# Next' }));
  await page.route('https://i.ytimg.com/**', route => route.fulfill({ path: 'test/fixtures/talk/images/wide.svg', contentType: 'image/svg+xml' }));
  await page.route('https://www.youtube.com/embed/**', route => route.fulfill({ contentType: 'text/html', body: '<title>Player</title>' }));
  await page.goto('/#slide=2');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  const video = page.locator('#stage .slide.active .youtube-video');
  const dimensions = await video.evaluate(element => {
    const body = element.closest('.body');
    return { width: element.offsetWidth, height: element.offsetHeight, bodyWidth: body.clientWidth, bodyHeight: body.clientHeight };
  });
  expect(dimensions.height / dimensions.bodyHeight).toBeGreaterThan(0.9);
  expect(dimensions.width / dimensions.height).toBeCloseTo(16 / 9, 1);
  expect(dimensions.width).toBeLessThanOrEqual(dimensions.bodyWidth);
  await video.locator('button').click();
  const overlay = page.locator('#stage .slide.active .youtube-overlay');
  await expect(overlay.locator('iframe')).toHaveAttribute('src', 'https://www.youtube.com/embed/M7lc1UVf-VE?start=90&end=150&autoplay=1');
  const overlayBounds = await overlay.evaluate(element => {
    const slide = element.closest('.slide');
    return { width: element.offsetWidth, height: element.offsetHeight, slideWidth: slide.offsetWidth, slideHeight: slide.offsetHeight };
  });
  expect(overlayBounds.width).toBe(overlayBounds.slideWidth);
  expect(overlayBounds.height).toBe(overlayBounds.slideHeight);
  await overlay.locator('button').click();
  await expect(overlay).toHaveCount(0);
  await expect(video.locator('button')).toBeFocused();
  await video.locator('button').click();
  await page.locator('#print').click();
  await expect(page.locator('#print-pages .youtube-overlay')).toHaveCount(0);
  await expect(page.locator('#print-pages .youtube-video img')).toHaveCount(1);
  await page.locator('#next').click();
  await expect(page.locator('#stage .youtube-overlay')).toHaveCount(0);
});


test('standalone thumbnails are centered in slides and print pages', async ({ page }) => {
  const video = '![Example](https://www.youtube.com/watch?v=M7lc1UVf-VE)';
  await page.route('**/talk/slides.md', route => route.fulfill({ contentType: 'text/markdown', body: `# Cover\n\n${video}\n\n---\n\n# Video\n\n${video}\n\n---\n\n${video}\n\n---\n\n# Mixed\n\nText ${video}` }));
  await page.route('https://i.ytimg.com/**', route => route.fulfill({ path: 'test/fixtures/talk/images/wide.svg', contentType: 'image/svg+xml' }));
  await page.goto('/#slide=1');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  async function expectCentered(locator) {
    const delta = await locator.evaluate(element => {
      const video = element.getBoundingClientRect();
      const body = element.closest('.body').getBoundingClientRect();
      return Math.abs((video.left + video.right - body.left - body.right) / 2);
    });
    expect(delta).toBeLessThan(1);
  }
  for (let index = 0; index < 3; index++) {
    if (index) await page.locator('#next').click();
    await expectCentered(page.locator('#stage .slide.active .youtube-video'));
  }
  await page.locator('#next').click();
  await expect(page.locator('#stage .slide.active p')).not.toHaveClass(/youtube-only/);
  await page.emulateMedia({ media: 'print' });
  for (let index = 0; index < 3; index++) {
    await expectCentered(page.locator('#print-pages .print-sheet').nth(index).locator('.youtube-video'));
  }
});
