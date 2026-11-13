import { test, expect } from '@playwright/test';

async function ready(page, hash = '#slide=1') {
  await page.goto('/' + hash);
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
}

test('reloads Markdown in the same VM, keeps the page, and retains slides on failure', async ({ page }) => {
  let markdown = '# First\n\n---\n\n# Second\n\n---\n\n# Third';
  let fail = false;
  let wasmRequests = 0;
  page.on('request', request => { if (new URL(request.url()).pathname.endsWith('.wasm')) wasmRequests++; });
  await page.route('**/talk/slides.md', route => fail ? route.fulfill({ status: 500 }) : route.fulfill({ body: markdown }));
  await ready(page, '#slide=2');
  markdown = '# Updated\n\n---\n\n# New second';
  await page.locator('#reload-slides').click();
  await expect(page.locator('#status')).toHaveText('スライドを再読み込みしました');
  await expect(page.locator('.slide.active .title')).toHaveText('New second');
  await expect(page.locator('#position')).toHaveText('2 / 2');
  expect(wasmRequests).toBe(1);
  fail = true;
  await page.locator('#reload-slides').click();
  await expect(page.locator('#status')).toHaveText('スライドの再読み込みに失敗しました');
  await expect(page.locator('.slide.active .title')).toHaveText('New second');
  await expect(page.locator('#reload-slides')).toBeEnabled();
  expect(wasmRequests).toBe(1);
});

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

test('adds a modest title gap when a slide has spare space below its body', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '# Cover\n\n---\n\n# 人間とLLMの認知様式のちがい\n\n人間：抽象化・構造化  \nLLM：特徴ベクトルの次元数\n\n---\n\n# Dense\n\n' + Array(14).fill('A line of text').join('  \n') }));
  await ready(page, '#slide=2');
  const spacing = await page.locator('.slide.active .body').evaluate(body => ({
    margin: parseFloat(getComputedStyle(body).marginTop),
    fits: body.scrollHeight <= body.clientHeight + 1,
  }));
  expect(spacing.margin).toBeGreaterThan(0);
  expect(spacing.margin).toBeLessThanOrEqual(64);
  expect(spacing.fits).toBe(true);
  await page.keyboard.press('ArrowRight');
  const dense = await page.locator('.slide.active .body').evaluate(body => ({
    margin: parseFloat(getComputedStyle(body).marginTop),
    fits: body.scrollHeight <= body.clientHeight + 1,
  }));
  expect(dense.margin).toBeLessThan(spacing.margin);
  expect(dense.fits).toBe(true);
});

test('failed images and overflow display slide number and content', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '# Overflow\n\n' + 'Unbreakable'.repeat(2000) + '\n\n![bad](missing.svg)' }));
  await ready(page);
  await expect(page.locator('#warnings')).toContainText('missing.svg');
  await expect(page.locator('#warnings')).toContainText('スライド 1');
  await expect(page.locator('#warnings')).toContainText('Unbreakable');
  await expect(page.locator('#warnings')).toBeInViewport({ ratio: 1 });
  const warningBox = await page.locator('#warnings').boundingBox();
  const viewportBox = await page.locator('#viewport').boundingBox();
  expect(warningBox.y + warningBox.height).toBeLessThanOrEqual(viewportBox.y);
  for (const size of [{ width: 1700, height: 1100 }, { width: 800, height: 650 }]) {
    await page.setViewportSize(size);
    await expect.poll(() => page.evaluate(() => {
      const root = document.documentElement;
      const slide = document.querySelector('.slide.active').getBoundingClientRect();
      const viewport = document.querySelector('#viewport').getBoundingClientRect();
      return root.scrollHeight <= root.clientHeight && root.scrollWidth <= root.clientWidth &&
        slide.top >= viewport.top && slide.bottom <= viewport.bottom;
    })).toBe(true);
    await expect(page.locator('#warnings')).toBeInViewport({ ratio: 1 });
  }
  await expect(page.locator('#stage .body')).toHaveCSS('font-size', '48px');
});

test('cover centers its title and places a fixed right-aligned body on the right', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '# Cover title\n\nFirst line  \nSecond line\n\n---\n\n# Next slide\n\nBody' }));
  await ready(page);
  const cover = page.locator('.slide.active');
  await expect(cover.locator('.body')).toHaveCSS('font-size', '48px');
  await expect(cover.locator('.body')).toHaveCSS('text-align', 'right');
  const positions = await cover.evaluate(slide => {
    const bounds = slide.getBoundingClientRect();
    const title = slide.querySelector('.title').getBoundingClientRect();
    const paragraph = slide.querySelector('.body p').getBoundingClientRect();
    return { titleY: (title.top + title.bottom) / 2 - bounds.top, centerY: bounds.height / 2,
      titleX: (title.left + title.right) / 2, bodyRight: paragraph.right, bodyBottom: paragraph.bottom,
      contentRight: slide.querySelector('.body').getBoundingClientRect().right, contentBottom: slide.querySelector('.body').getBoundingClientRect().bottom, centerX: (bounds.left + bounds.right) / 2 };
  });
  expect(positions.titleY).toBeCloseTo(positions.centerY, 0);
  expect(positions.titleX).toBeCloseTo(positions.centerX, 0);
  expect(positions.bodyRight).toBeCloseTo(positions.contentRight, 0);
  expect(positions.bodyBottom).toBeCloseTo(positions.contentBottom, 0);
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('.slide.active .body')).not.toHaveCSS('font-size', '48px');
});

test('cover title preserves explicit line breaks and fits in the center', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '# Rubyで作る<br>プレゼンテーション\n\n発表者' }));
  await ready(page);
  const title = page.locator('.slide.active .title');
  await expect(title).toHaveText('Rubyで作る\nプレゼンテーション');
  const layout = await title.evaluate(node => {
    const title = node.getBoundingClientRect();
    const slide = node.closest('.slide').getBoundingClientRect();
    return { fits: node.scrollWidth <= node.clientWidth + 1 && node.scrollHeight <= node.clientHeight + 1,
      center: (title.top + title.bottom - slide.top - slide.bottom) / 2 };
  });
  expect(layout.fits).toBe(true);
  expect(layout.center).toBeCloseTo(0, 0);
  await expect(page.locator('#warnings')).toBeHidden();
});

test('moves a multiline cover title above a taller cover body', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '# Kaigi on Rails 2026の<br>DHH\n\n株式会社ラグザイア  \n中島滋  \n2026/11/13 MM' }));
  await ready(page);
  const gap = await page.locator('.slide.active').evaluate(slide => {
    const title = slide.querySelector('.title').getBoundingClientRect();
    const body = slide.querySelector('.body p').getBoundingClientRect();
    return body.top - title.bottom;
  });
  expect(gap).toBeGreaterThan(0);
  await expect(page.locator('#warnings')).toBeHidden();
});

test('warns when cover body overlaps its title', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '# Cover\n\n' + Array(12).fill('A line of text').join('  \n') }));
  await ready(page);
  await expect(page.locator('#warnings')).toContainText('スライド 1: タイトルと本文が重なっています');
});

test('does not warn when a short cover body fits', async ({ page }) => {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: '# AIコーディング時代のプログラマー\n\n株式会社ラグザイア  \n中島滋  \n2026/06/19 MM' }));
  await ready(page);
  await expect(page.locator('#warnings')).toBeHidden();
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

test('reconnects the existing speaker window after reloading the presentation', async ({ page }) => {
  await ready(page);
  const opened = page.waitForEvent('popup');
  await page.keyboard.press('n');
  const speaker = await opened;
  await expect(speaker.locator('#current')).toHaveText('Ruby in your browser');
  await page.reload();
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  await page.keyboard.press('n');
  await expect(speaker.locator('#current')).toHaveText('Ruby in your browser');
  await page.keyboard.press('ArrowRight');
  await expect(speaker.locator('#position')).toHaveText('2 / 3');
  await expect(speaker.locator('#notes')).toHaveText('Second slide notes.');
  await speaker.close();
});

test('speaker panels keep their height, fit the slide, and scroll long notes', async ({ page }) => {
  await ready(page);
  const opened = page.waitForEvent('popup');
  await page.keyboard.press('n');
  const speaker = await opened;
  await expect(speaker.locator('#current')).toHaveText('Ruby in your browser');
  for (const viewport of [{ width: 1200, height: 800 }, { width: 600, height: 800 }]) {
    await speaker.setViewportSize(viewport);
    const panels = speaker.locator('.speaker-columns > *');
    const before = await panels.evaluateAll(elements => elements.map(element => element.getBoundingClientRect().height));
    await speaker.evaluate(() => {
      document.querySelector('#body').textContent = 'Long slide content '.repeat(1000);
      document.querySelector('#notes').textContent = 'Long note content '.repeat(1000);
    });
    const after = await panels.evaluateAll(elements => elements.map(element => ({ height: element.getBoundingClientRect().height, clientHeight: element.clientHeight, scrollHeight: element.scrollHeight })));
    expect(before[0]).toBe(before[1]);
    expect(after.map(panel => panel.height)).toEqual(before);
    await expect.poll(() => speaker.locator('#speaker-slide-content').evaluate(node => Number(getComputedStyle(node).zoom))).toBeLessThan(1);
    await expect.poll(() => panels.first().evaluate(node => node.scrollHeight <= node.clientHeight + 1 && node.scrollWidth <= node.clientWidth + 1)).toBe(true);
    expect(after[1].scrollHeight).toBeGreaterThan(after[1].clientHeight);
  }
  await speaker.close();
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
