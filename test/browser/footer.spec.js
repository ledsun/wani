import { test, expect } from '@playwright/test';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';

const source = '---\nfooter: Shared footer\n---\n# First\n\n---\n\n# Second\n\n<!-- footer: <b>Specific footer</b> -->\n\n<!-- notes: Private notes -->\n\n---\n\n# Third\n\n<!-- footer: -->\n\n---\n\n# Fourth';

async function ready(page, markdown = source) {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: markdown }));
  await page.goto('/');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
}

async function pdfText(buffer) {
  const task = getDocument({ data: new Uint8Array(buffer), useSystemFonts: false });
  try {
    const pdf = await task.promise;
    const texts = [];
    for (let index = 1; index <= pdf.numPages; index++) {
      const content = await (await pdf.getPage(index)).getTextContent();
      texts.push(content.items.map(item => item.str + (item.hasEOL ? ' ' : '')).join('').replace(/\s+/g, ' '));
    }
    return texts;
  } finally {
    await task.destroy();
  }
}

test('only page footers appear and page count stays to the right of the bridge', async ({ page }, info) => {
  await ready(page);
  const footer = page.locator('.slide.active .footer-text');
  const count = page.locator('.slide.active .slide-number');
  await expect(footer).toHaveText('');
  await expect(count).toHaveText('1/4');
  await page.keyboard.press('ArrowRight');
  await expect(footer).toHaveText('<b>Specific footer</b>');
  await expect(footer.locator('b')).toHaveCount(0);
  await expect(page.locator('.slide.active .body')).not.toContainText('Specific footer');
  await expect(count).toHaveText('2/4');
  const bridge = await page.locator('.slide.active .decorations').boundingBox();
  const number = await count.boundingBox();
  expect(number.x).toBeGreaterThan(bridge.x + bridge.width);
  await page.screenshot({ path: info.outputPath('footer-and-page-number.png') });
  const opened = page.waitForEvent('popup');
  await page.keyboard.press('n');
  const speaker = await opened;
  await expect(speaker.locator('#footer')).toHaveText('<b>Specific footer</b>');
  await page.keyboard.press('ArrowRight');
  await expect(footer).toHaveText('');
  await expect(speaker.locator('#footer')).toHaveText('');
  await expect(count).toHaveText('3/4');
  await page.keyboard.press('End');
  await expect(footer).toHaveText('');
  await expect(count).toHaveText('4/4');
  await speaker.close();
});

test('page numbers remain without decorations', async ({ page }) => {
  await ready(page, '---\ndecorations: false\n---\n# First\n\n---\n\n# Second');
  await expect(page.locator('.decorations')).toHaveCount(0);
  await expect(page.locator('.slide.active .slide-number')).toHaveText('1/2');
  await page.keyboard.press('End');
  await expect(page.locator('.slide.active .slide-number')).toHaveText('2/2');
});

test('print and notes use each footer and logical slide number', async ({ page }, info) => {
  await ready(page);
  await page.locator('#print-notes').click();
  await expect(page.locator('#status')).toContainText('8 ページ');
  await expect(page.locator('#print-pages .footer-text')).toHaveText([
    '', '', '<b>Specific footer</b>', '<b>Specific footer</b>', '', '', '', '',
  ]);
  await expect(page.locator('#print-pages .slide-number')).toHaveText(['1/4', '1/4', '2/4', '2/4', '3/4', '3/4', '4/4', '4/4']);
  const texts = await pdfText(await page.pdf({ preferCSSPageSize: true, printBackground: true, path: info.outputPath('footers.pdf') }));
  expect(texts).toHaveLength(8);
  texts.forEach(text => expect(text).not.toContain('Shared footer'));
  expect(texts[2]).toContain('Specific footer');
  expect(texts[4]).not.toMatch(/Shared footer|Specific footer/);
  texts.forEach((text, index) => expect(text).toContain(`${Math.floor(index / 2) + 1}/4`));
});
