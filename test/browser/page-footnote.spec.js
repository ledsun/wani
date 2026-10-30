import { test, expect } from '@playwright/test';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';

const source = '---\npage-footnote: Shared footnote\n---\n# First\n\n---\n\n# Second\n\n<!-- page-footnote: <b>Specific footnote</b> -->\n\n<!-- notes: Private notes -->\n\n---\n\n# Third\n\n<!-- page-footnote: -->\n\n---\n\n# Fourth';

async function ready(page, markdown = source) {
  await page.route('**/talk/slides.md', route => route.fulfill({ body: markdown }));
  await page.goto('/#slide=1');
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

for (const decorations of [true, false]) {
  test(`long footnotes are clipped and warn with decorations=${decorations}`, async ({ page }) => {
    if (!decorations) {
      await page.route('**/assets/style.css', async route => {
        const response = await route.fetch();
        await route.fulfill({ response, body: (await response.text()) + '\n.decorations { display: none; }' });
      });
    }
    const footnotes = ['短い脚注', '長い脚注です。'.repeat(100), 'https://example.com/' + 'a'.repeat(500), ''];
    await ready(page, footnotes.map((text, index) =>
      `# Page ${index + 1}\n\n<!-- page-footnote: ${text} -->`
    ).join('\n\n---\n\n'));
    await expect(page.locator('#warnings')).toHaveText([
      'スライド 2: 脚注が1行に収まりません。短くするか、詳細を本文へ移してください。',
      'スライド 3: 脚注が1行に収まりません。短くするか、詳細を本文へ移してください。',
    ].join('\n'));
    await page.keyboard.press('ArrowRight');
    const footnote = page.locator('.slide.active .page-footnote');
    await expect(footnote).toHaveText(footnotes[1]);
    const dimensions = await footnote.evaluate(node => {
      const style = getComputedStyle(node);
      return { width: node.clientWidth, scrollWidth: node.scrollWidth, height: node.clientHeight,
        lineHeight: parseFloat(style.lineHeight), overflow: style.overflow, whiteSpace: style.whiteSpace,
        fontSize: style.fontSize };
    });
    expect(dimensions.scrollWidth).toBeGreaterThan(dimensions.width);
    expect(Math.abs(dimensions.height - dimensions.lineHeight)).toBeLessThanOrEqual(1);
    expect(dimensions).toMatchObject({ overflow: 'hidden', whiteSpace: 'nowrap', fontSize: '24px' });
  });
}

test('only page footnotes appear and page count stays to the right of the bridge', async ({ page }, info) => {
  await ready(page);
  const footnote = page.locator('.slide.active .page-footnote');
  const count = page.locator('.slide.active .slide-number');
  await expect(footnote).toHaveText('');
  await expect(count).toHaveText('1/4');
  await page.keyboard.press('ArrowRight');
  await expect(footnote).toHaveText('<b>Specific footnote</b>');
  await expect(footnote.locator('b')).toHaveCount(0);
  await expect(page.locator('.slide.active .body')).not.toContainText('Specific footnote');
  await expect(count).toHaveText('2/4');
  const bridge = await page.locator('.slide.active .decorations').boundingBox();
  const number = await count.boundingBox();
  expect(number.x).toBeGreaterThan(bridge.x + bridge.width);
  await page.screenshot({ path: info.outputPath('footnote-and-page-number.png') });
  const opened = page.waitForEvent('popup');
  await page.keyboard.press('n');
  const speaker = await opened;
  await expect(speaker.locator('#page-footnote')).toHaveText('<b>Specific footnote</b>');
  await page.keyboard.press('ArrowRight');
  await expect(footnote).toHaveText('');
  await expect(speaker.locator('#page-footnote')).toHaveText('');
  await expect(count).toHaveText('3/4');
  await page.keyboard.press('End');
  await expect(footnote).toHaveText('');
  await expect(count).toHaveText('4/4');
  await speaker.close();
});

test('page numbers remain when printing', async ({ page }) => {
  await ready(page, '---\ndecorations: false\n---\n# First\n\n---\n\n# Second');
  await page.emulateMedia({ media: 'print' });
  await expect(page.locator('#print-pages .decorations').first()).toBeHidden();
  await expect(page.locator('#print-pages .slide-number').first()).toBeVisible();
  await expect(page.locator('.slide.active .slide-number')).toHaveText('1/2');
  await page.emulateMedia({ media: 'screen' });
  await page.keyboard.press('End');
  await expect(page.locator('.slide.active .slide-number')).toHaveText('2/2');
});

test('print and notes use each footnote and logical slide number', async ({ page }, info) => {
  await ready(page);
  await page.locator('#print-notes').click();
  await expect(page.locator('#status')).toContainText('8 ページ');
  await expect(page.locator('#print-pages .page-footnote')).toHaveText([
    '', '', '<b>Specific footnote</b>', '<b>Specific footnote</b>', '', '', '', '',
  ]);
  await expect(page.locator('#print-pages .slide-number')).toHaveText(['1/4', '1/4', '2/4', '2/4', '3/4', '3/4', '4/4', '4/4']);
  const texts = await pdfText(await page.pdf({ preferCSSPageSize: true, printBackground: true, path: info.outputPath('footnotes.pdf') }));
  expect(texts).toHaveLength(8);
  texts.forEach(text => expect(text).not.toContain('Shared footnote'));
  expect(texts[2]).toContain('Specific footnote');
  expect(texts[4]).not.toMatch(/Shared footnote|Specific footnote/);
  texts.forEach((text, index) => expect(text).toContain(`${Math.floor(index / 2) + 1}/4`));
});
