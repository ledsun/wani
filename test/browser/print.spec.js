import { test, expect } from '@playwright/test';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';

async function inspect(buffer) {
  const task = getDocument({ data: new Uint8Array(buffer), useSystemFonts: true });
  const pdf = await task.promise;
  const pages = [];
  for (let index = 1; index <= pdf.numPages; index++) {
    const page = await pdf.getPage(index);
    const viewport = page.getViewport({ scale: 1 });
    const text = await page.getTextContent();
    expect(Math.abs(viewport.width - 320 * 72 / 25.4)).toBeLessThan(1);
    expect(Math.abs(viewport.height - 180 * 72 / 25.4)).toBeLessThan(1);
    pages.push(text.items.map(item => item.str + (item.hasEOL ? ' ' : '')).join('').replace(/\s+/g, ' '));
  }
  await task.destroy();
  return pages;
}

test('normal and alternating-notes PDFs retain content, images and page footnote', async ({ page }, info) => {
  await page.goto('/');
  await expect(page.locator('#status')).toHaveText('準備できました', { timeout: 60_000 });
  // Ctrl+P also has a prepared normal DOM immediately after startup.
  await expect(page.locator('#print-pages > .print-sheet')).toHaveCount(3);
  await page.locator('#print').click();
  await expect(page.locator('#status')).toContainText('3 ページ');
  const normal = await inspect(await page.pdf({ preferCSSPageSize: true, printBackground: true, path: info.outputPath('slides.pdf') }));
  expect(normal).toHaveLength(3);
  expect(normal[0]).toContain('Ruby in your browser');
  expect(normal[0]).toContain('800 × 200 image');
  expect(normal[0]).toContain('Wani test presentation');
  normal.slice(1).forEach(text => expect(text).not.toContain('Wani test presentation'));
  expect(normal.join(' ')).not.toContain('Private');
  await expect(page.locator('#print-pages .rabbit-image')).toHaveCount(3);
  await page.locator('#print-notes').click();
  await expect(page.locator('#status')).toContainText('6 ページ');
  const notes = await inspect(await page.pdf({ preferCSSPageSize: true, printBackground: true, path: info.outputPath('notes.pdf') }));
  expect(notes).toHaveLength(6);
  expect(notes[1]).toContain('Private speaker notes');
  expect(notes[2]).toContain('One source, two runtimes');
  expect(notes[3]).toContain('Second slide notes.');
  expect(notes[5]).toContain('Image slide notes.');
  await expect(page.locator('#stage > .slide')).toHaveCount(3);
  await page.screenshot({ path: info.outputPath('screen.png') });
});
