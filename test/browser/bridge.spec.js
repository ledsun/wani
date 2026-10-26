import { test, expect } from '@playwright/test';

const source = ['# Start', '# Bridge', '# Crossing', '# Finish'].join('\n\n---\n\n');

async function ready(page, markdown = source) {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: markdown }));
  await page.goto('/');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
}

async function rabbitFraction(page) {
  return page.locator('.slide.active .decorations').evaluate(scene => {
    const rabbit = scene.querySelector('.rabbit-position');
    return parseFloat(getComputedStyle(rabbit).left) / (scene.clientWidth - rabbit.offsetWidth);
  });
}

test('wanis build from the right, then rabbit crosses left to right and reverses', async ({ page }, info) => {
  await ready(page);
  const scene = page.locator('.slide.active .decorations');
  await expect(scene.locator('.island')).toHaveCount(2);
  const starting = await scene.evaluate(scene => {
    const rabbit = scene.querySelector('.rabbit-position').getBoundingClientRect();
    const island = scene.querySelector('.island-left').getBoundingClientRect();
    const bridge = scene.querySelector('.bridge').getBoundingClientRect();
    return { onIsland: Math.abs(rabbit.x - island.x) < 1 && Math.abs(rabbit.width - island.width) < 1, bridgeAfterIsland: bridge.left >= island.right - 1 };
  });
  expect(starting).toEqual({ onIsland: true, bridgeAfterIsland: true });
  await expect(scene.locator('.bridge-segment[data-present="true"]')).toHaveCount(1);
  expect(await scene.locator('.bridge-segment').evaluateAll(nodes => nodes.map(node => node.dataset.present))).toEqual([
    ...Array(19).fill('false'), 'true',
  ]);
  await expect.poll(() => rabbitFraction(page)).toBeCloseTo(0, 2);
  await page.keyboard.press('ArrowRight');
  await expect(scene.locator('.bridge-segment[data-present="true"]')).toHaveCount(20);
  await expect.poll(() => rabbitFraction(page)).toBeCloseTo(0, 2);
  await page.screenshot({ path: info.outputPath('bridge-complete.png') });
  await page.keyboard.press('ArrowRight');
  await expect.poll(() => rabbitFraction(page)).toBeCloseTo(0.5, 2);
  await expect(scene.locator('.bridge-segment[data-present="true"]')).toHaveCount(20);
  await page.keyboard.press('End');
  await expect.poll(() => rabbitFraction(page)).toBeCloseTo(1, 2);
  const positions = await scene.evaluate(scene => {
    const bridge = scene.querySelector('.bridge').getBoundingClientRect();
    const rabbit = scene.querySelector('.rabbit-position').getBoundingClientRect();
    const island = scene.querySelector('.island-right').getBoundingClientRect();
    return { onIsland: Math.abs(rabbit.x - island.x) < 1 && Math.abs(rabbit.width - island.width) < 1, bridgeBeforeIsland: bridge.right <= island.left + 1, above: rabbit.top < island.top };
  });
  expect(positions).toEqual({ onIsland: true, bridgeBeforeIsland: true, above: true });
  await page.screenshot({ path: info.outputPath('rabbit-finish.png') });
  await page.keyboard.press('ArrowLeft');
  await expect.poll(() => rabbitFraction(page)).toBeCloseTo(0.5, 2);
  await page.keyboard.press('Home');
  await expect.poll(() => rabbitFraction(page)).toBeCloseTo(0, 2);
  await expect(scene.locator('.bridge-segment[data-present="true"]')).toHaveCount(1);
});

test('normal and notes PDFs always hide the bridge and rabbit', async ({ page }) => {
  await ready(page, '---\ndecorations: true\n---\n' + source);
  for (const button of ['#print', '#print-notes']) {
    await page.locator(button).click();
    await page.emulateMedia({ media: 'print' });
    const scenes = page.locator('#print-pages .decorations');
    await expect(scenes).toHaveCount(button === '#print' ? 4 : 8);
    for (const scene of await scenes.all()) {
      await expect(scene).toBeHidden();
      await expect(scene.locator('.rabbit-image')).toBeHidden();
      for (const wani of await scene.locator('.bridge-wani').all()) await expect(wani).toBeHidden();
    }
    await expect(page.locator('#print-pages .slide-number').first()).toBeVisible();
    await page.emulateMedia({ media: 'screen' });
    await expect(page.locator('#stage .slide.active .decorations')).toBeVisible();
  }
});

test('reduced motion leaves the rabbit at the correct position', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await ready(page);
  await page.keyboard.press('End');
  await expect.poll(() => rabbitFraction(page)).toBeCloseTo(1, 2);
  await expect(page.locator('.slide.active .rabbit-position')).toHaveCSS('animation-name', 'none');
});

test('a single-slide presentation starts with one wani and hides it when printing', async ({ page }) => {
  await ready(page, '# Only slide');
  await expect(page.locator('.slide.active .bridge-segment[data-present="true"]')).toHaveCount(1);
  await page.emulateMedia({ media: 'print' });
  await expect(page.locator('#print-pages .decorations')).toBeHidden();
});
