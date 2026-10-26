import { test, expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('new presentation renders all sample pages and its bundled image without warnings', async ({ page }, info) => {
  const directory = mkdtempSync(join(tmpdir(), 'wani-template-'));
  const talk = join(directory, 'talk');
  try {
    execFileSync('bundle', ['exec', 'ruby', '-Ilib', 'exe/wani', 'new', talk]);
    await page.route('**/talk/slides.md', route => route.fulfill({ path: join(talk, 'slides.md'), contentType: 'text/plain; charset=utf-8' }));
    await page.route('**/talk/images/workflow.svg', route => route.fulfill({ path: join(talk, 'images/workflow.svg'), contentType: 'image/svg+xml' }));
    await page.goto('/');
    await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
    await expect(page.locator('#stage > .slide')).toHaveCount(8);
    await expect(page.locator('#warnings')).toBeHidden();
    const slides = page.locator('#stage > .slide');
    await expect(slides.nth(1).locator('strong')).toHaveText('いちばん伝えたいこと');
    await expect(slides.nth(1).locator('em')).toHaveText('強調したい言葉');
    await expect(slides.nth(2).locator('ol li')).toHaveCount(3);
    await expect(slides.nth(3).locator('blockquote')).toContainText('一枚のスライド');
    await expect(slides.nth(4).locator('pre code')).toContainText('topics.each');
    await expect(slides.nth(5).locator('table tbody tr')).toHaveCount(4);
    await page.goto('/#slide=7');
    const image = page.locator('#stage .slide.active .body img');
    await expect(image).toBeVisible();
    expect(await image.evaluate(node => node.complete && node.naturalWidth > 0)).toBe(true);
    await page.screenshot({ path: info.outputPath('sample-image.png') });
    await page.locator('#print-notes').click();
    await expect(page.locator('#print-pages > .print-sheet')).toHaveCount(16);
    await expect(page.locator('#warnings')).toBeHidden();
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
