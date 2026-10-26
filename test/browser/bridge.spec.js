import { test, expect } from '@playwright/test';

const source = ['# Start', '# Bridge', '# Crossing', '# Finish'].join('\n\n---\n\n');

async function ready(page) {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: source }));
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
  await expect(scene.locator('.bridge-segment[data-present="true"]')).toHaveCount(10);
  expect(await scene.locator('.bridge-segment').evaluateAll(nodes => nodes.map(node => node.dataset.present))).toEqual([
    ...Array(10).fill('false'), ...Array(10).fill('true'),
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
    return { inside: rabbit.left >= bridge.left - 1 && rabbit.right <= bridge.right + 1, above: rabbit.top < bridge.top };
  });
  expect(positions).toEqual({ inside: true, above: true });
  await page.screenshot({ path: info.outputPath('rabbit-finish.png') });
  await page.keyboard.press('ArrowLeft');
  await expect.poll(() => rabbitFraction(page)).toBeCloseTo(0.5, 2);
  await page.keyboard.press('Home');
  await expect.poll(() => rabbitFraction(page)).toBeCloseTo(0, 2);
  await expect(scene.locator('.bridge-segment[data-present="true"]')).toHaveCount(10);
});

test('print and notes retain each slide progress without animation', async ({ page }) => {
  await ready(page);
  await page.locator('#print-notes').click();
  await expect(page.locator('#status')).toContainText('8 ページ');
  await page.emulateMedia({ media: 'print' });
  const states = await page.locator('#print-pages .decorations').evaluateAll(nodes => nodes.map(scene => ({
    sharks: Number(scene.dataset.sharks),
    rabbit: Number(scene.dataset.rabbit),
    animation: getComputedStyle(scene.querySelector('.rabbit-position')).animationName,
    fraction: parseFloat(getComputedStyle(scene.querySelector('.rabbit-position')).left) / (scene.clientWidth - 84),
  })));
  expect(states.map(state => state.sharks)).toEqual([10, 10, 20, 20, 20, 20, 20, 20]);
  expect(states.map(state => state.rabbit)).toEqual([0, 0, 0, 0, 0.5, 0.5, 1, 1]);
  states.forEach(state => {
    expect(state.animation).toBe('none');
    expect(state.fraction).toBeCloseTo(state.rabbit, 2);
  });
});

test('reduced motion leaves the rabbit at the correct position', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await ready(page);
  await page.keyboard.press('End');
  await expect.poll(() => rabbitFraction(page)).toBeCloseTo(1, 2);
  await expect(page.locator('.slide.active .rabbit-position')).toHaveCSS('animation-name', 'none');
});
