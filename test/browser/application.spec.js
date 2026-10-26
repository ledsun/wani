import { test, expect } from '@playwright/test';

async function ready(page, hash = '') {
  await page.goto('/' + hash);
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
}

test('CLI server boots packaged Ruby and renders the presentation', async ({ page }) => {
  const errors = [];
  const requests = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => requests.push(new URL(request.url())));
  await ready(page);
  await expect(page.locator('#stage > .slide')).toHaveCount(3);
  await expect(page.locator('.slide.active .title')).toHaveText('Ruby in your browser');
  await expect(page.locator('.slide.active strong')).toHaveText('Wani');
  await expect(page.locator('.slide.active .page-footnote')).toHaveText('Wani test presentation');
  await expect(page.locator('.slide.active .rabbit-image')).toHaveCount(1);
  await expect(page.locator('.slide.active .bridge-segment[data-present="true"]')).toHaveCount(1);
  await expect(page.locator('#stage')).not.toContainText('speaker notes');
  await expect(page.locator('#warnings')).toBeHidden();
  expect(errors).toEqual([]);
  expect(requests.every(url => url.origin === new URL(page.url()).origin)).toBe(true);
  expect(requests.filter(url => url.pathname.endsWith('.js')).map(url => url.pathname)).toEqual(['/assets/runtime.pr672.js']);
});

test('all navigation keys, hash deep links, hash changes and boundaries', async ({ page }) => {
  await ready(page, '#slide=2');
  await expect(page.locator('#position')).toHaveText('2 / 3');
  await page.keyboard.press('Home');
  await expect(page.locator('#previous')).toBeDisabled();
  await page.keyboard.press('ArrowLeft');
  await expect(page).toHaveURL(/#slide=1$/);
  for (const key of ['ArrowRight', 'Space']) await page.keyboard.press(key);
  await expect(page.locator('#position')).toHaveText('3 / 3');
  await expect(page.locator('#next')).toBeDisabled();
  await page.keyboard.press('PageDown');
  await expect(page.locator('#position')).toHaveText('3 / 3');
  await page.keyboard.press('PageUp');
  await expect(page.locator('#position')).toHaveText('2 / 3');
  await page.keyboard.press('End');
  await expect(page).toHaveURL(/#slide=3$/);
  await page.evaluate(() => { location.hash = 'slide=1'; });
  await expect(page.locator('#position')).toHaveText('1 / 3');
  await page.keyboard.press('Control+ArrowRight');
  await expect(page.locator('#position')).toHaveText('1 / 3');
  await page.evaluate(() => { location.hash = 'slide=999'; });
  await expect(page.locator('#position')).toHaveText('3 / 3');
  await expect(page).toHaveURL(/#slide=3$/);
});

test('body fits, window resize scales and titleless PNG JPEG WebP images load', async ({ page }) => {
  await ready(page);
  const fit = await page.locator('.slide.active').evaluate(slide => {
    const body = slide.querySelector('.body');
    const title = slide.querySelector('.title');
    return {
      width: slide.offsetWidth, height: slide.offsetHeight,
      fits: body.scrollWidth <= body.clientWidth + 1 && body.scrollHeight <= body.clientHeight + 1,
      titleFits: title.scrollWidth <= title.clientWidth + 1,
      font: parseFloat(getComputedStyle(body).fontSize),
    };
  });
  expect(fit).toMatchObject({ width: 1920, height: 1080, fits: true, titleFits: true });
  expect(fit.font).toBeGreaterThan(16);
  await page.setViewportSize({ width: 800, height: 650 });
  await expect.poll(async () => (await page.locator('.slide.active').boundingBox()).width <= 760).toBe(true);
  await page.keyboard.press('End');
  await expect(page.locator('.slide.active .title')).toBeHidden();
  const images = await page.locator('.slide.active .body img').evaluateAll(nodes => nodes.map(image => ({ loaded: image.complete && image.naturalWidth > 0, ratio: image.width / image.height })));
  expect(images).toHaveLength(3);
  images.forEach(image => { expect(image.loaded).toBe(true); expect(image.ratio).toBeCloseTo(2, 1); });
  await expect(page.locator('#warnings')).toBeHidden();
});

test('failed images and overflow display slide number and content', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '# Overflow\n\n' + 'Unbreakable'.repeat(2000) + '\n\n![bad](missing.svg)' }));
  await ready(page);
  await expect(page.locator('#warnings')).toContainText('missing.svg');
  await expect(page.locator('#warnings')).toContainText('スライド 1');
  await expect(page.locator('#warnings')).toContainText('Unbreakable');
  await expect(page.locator('#stage .body')).toHaveCSS('font-size', '16px');
});

test('Ruby enters and exits fullscreen with keyboard shortcuts', async ({ page }) => {
  await ready(page);
  await page.keyboard.press('f');
  await expect.poll(() => page.evaluate(() => document.fullscreenElement !== null)).toBe(true);
  await page.keyboard.press('Escape');
  await expect.poll(() => page.evaluate(() => document.fullscreenElement === null)).toBe(true);
});

test('speaker window shows private notes and stays synchronized', async ({ page }) => {
  await ready(page);
  const opened = page.waitForEvent('popup');
  await page.keyboard.press('n');
  const speaker = await opened;
  await expect(speaker.locator('#notes strong')).toHaveText('speaker notes');
  await expect(speaker.locator('#current')).toHaveText('Ruby in your browser');
  await page.keyboard.press('ArrowRight');
  await expect(speaker.locator('#position')).toHaveText('2 / 3');
  await expect(speaker.locator('#notes')).toHaveText('Second slide notes.');
  await expect(page.locator('#stage')).not.toContainText('Second slide notes.');
  await speaker.evaluate(() => window.postMessage(JSON.stringify({ position: '999', title: 'spoof', html: '', notes_html: '' }), location.origin));
  await expect(speaker.locator('#position')).toHaveText('2 / 3');
  await speaker.close();
  await page.keyboard.press('ArrowLeft');
  await expect(page.locator('#position')).toHaveText('1 / 3');
});

test('legacy decorations setting is ignored and invalid Markdown is rejected', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '---\npage-footnote: Footnote\ndecorations: false\n---\n# Simple' }));
  await ready(page);
  await expect(page.locator('.slide.active .decorations')).toBeVisible();
  await page.unroute('**/talk/slides.md');
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '---\npage-footnote: !ruby/object:Object {}\n---' }));
  await page.reload();
  await expect(page.locator('#status')).toContainText('Invalid or unsafe YAML', { timeout: 60_000 });
  await expect(page.locator('#next')).toBeDisabled();
});
