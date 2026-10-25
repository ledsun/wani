import { test, expect } from '@playwright/test';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { readFile } from 'node:fs/promises';
import { ready } from './helpers.js';

test('Ruby waits for images/fonts and fits text at logical 1920x1080', async ({ page }) => {
  await page.route('**/wide.svg', async route => {
    await new Promise(resolve => setTimeout(resolve, 200));
    await route.fulfill({ body: await readFile('public/wide.svg'), contentType: 'image/svg+xml' });
  });
  await ready(page);
  const state = await page.locator('.slide.active').evaluate(slide => {
    const body = slide.querySelector('.body');
    const title = slide.querySelector('.title');
    const img = body.querySelector('img');
    return {
      width: slide.offsetWidth, height: slide.offsetHeight,
      bodyFits: body.scrollWidth <= body.clientWidth && body.scrollHeight <= body.clientHeight,
      titleFits: title.scrollWidth <= title.clientWidth,
      fontSize: parseFloat(getComputedStyle(body).fontSize),
      fontReady: document.fonts.status,
      imageReady: img.complete && img.naturalWidth === 800,
      imageRatio: img.width / img.height,
    };
  });
  expect(state).toMatchObject({ width: 1920, height: 1080, bodyFits: true, titleFits: true, fontReady: 'loaded', imageReady: true });
  expect(state.fontSize).toBeGreaterThan(16);
  expect(state.imageRatio).toBeCloseTo(4, 2);
  await page.setViewportSize({ width: 800, height: 600 });
  await expect.poll(async () => {
    const rect = await page.locator('.slide.active').boundingBox();
    return rect.width <= 800 && rect.height <= 420;
  }).toBe(true);
  await expect(page.locator('#warnings')).toHaveText('');
});

test('minimum font overflow and failed images produce visible diagnostics', async ({ page }) => {
  const source = '# Overflow\n\n' + 'Unbreakable'.repeat(2000) + '\n\n![missing](missing.svg)';
  await page.route('**/overflow.md', route => route.fulfill({ body: source }));
  await ready(page, 'overflow.md');
  await expect(page.locator('#warnings')).toContainText('image failed: missing.svg');
  await expect(page.locator('#warnings')).toContainText('slide 1: overflow:');
  await expect(page.locator('.body')).toHaveCSS('font-size', '16px');
});

test('titleless image-only slides preserve aspect ratios for multiple images', async ({ page }) => {
  await page.route('**/images.md', route => route.fulfill({ body: '![one](wide.svg)\n\n![two](wide.svg)' }));
  await ready(page, 'images.md');
  await expect(page.locator('.title')).toBeHidden();
  const images = await page.locator('.body img').evaluateAll(nodes => nodes.map(image => ({
    ratio: image.width / image.height, loaded: image.complete && image.naturalWidth > 0,
  })));
  expect(images).toHaveLength(2);
  images.forEach(image => {
    expect(image.loaded).toBe(true);
    expect(image.ratio).toBeCloseTo(4, 2);
  });
  await expect(page.locator('#warnings')).toHaveText('');
});

async function inspectPDF(buffer) {
  const task = getDocument({ data: new Uint8Array(buffer), useSystemFonts: true });
  const pdf = await task.promise;
  const pages = [];
  for (let index = 1; index <= pdf.numPages; index++) {
    const page = await pdf.getPage(index);
    const viewport = page.getViewport({ scale: 1 });
    const content = await page.getTextContent();
    pages.push({ width: viewport.width, height: viewport.height, text: content.items.map(item => item.str + (item.hasEOL ? ' ' : '')).join('').replace(/\s+/g, ' ') });
  }
  await task.destroy();
  return pages;
}

function expectWidePage(item) {
  // Chromium rounds CSS paper sizes. Allow one PDF point, not a whole page-size mismatch.
  expect(Math.abs(item.width - 320 * 72 / 25.4)).toBeLessThan(1);
  expect(Math.abs(item.height - 180 * 72 / 25.4)).toBeLessThan(1);
}

test('Ruby print DOM produces 16:9 PDFs with and without alternating notes', async ({ page }, info) => {
  await ready(page);
  // page.pdf exercises Chromium's print pipeline; the OS print dialog is manual.
  await page.locator('#print').click();
  await expect(page.locator('#status')).toHaveText('print-ready:2');
  const standard = await page.pdf({ preferCSSPageSize: true, printBackground: true, path: info.outputPath('slides.pdf') });
  const normal = await inspectPDF(standard);
  expect(normal).toHaveLength(2);
  normal.forEach(expectWidePage);
  expect(normal[0].text).toContain('Ruby layout');
  expect(normal[0].text).toContain('Wani preflight');
  expect(normal[0].text).toContain('800 × 200 image');
  expect(normal[0].text).toContain('🐇');
  expect(normal[0].text).toContain('🦈');
  expect(normal.map(item => item.text).join(' ')).not.toContain('Speaker notes');
  await page.locator('#print-notes').click();
  await expect(page.locator('#status')).toHaveText('print-ready:4');
  const notesPDF = await page.pdf({ preferCSSPageSize: true, printBackground: true, path: info.outputPath('notes.pdf') });
  const notes = await inspectPDF(notesPDF);
  expect(notes).toHaveLength(4);
  notes.forEach(expectWidePage);
  expect(notes[0].text).toContain('Ruby layout');
  expect(notes[1].text).toContain('Speaker notes for slide one.');
  expect(notes[2].text).toContain('Second slide');
  expect(notes[3].text).toContain('Notes for slide two.');
  await expect(page.locator('#stage > .slide')).toHaveCount(2);
  await page.screenshot({ path: info.outputPath('screen.png') });
});
